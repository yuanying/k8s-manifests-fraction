# CoreDNS を RuntimeDefault の seccomp で動かす手順書（本番 `fraction`）

本番クラスタ `fraction` の CoreDNS を、containerd の既定の seccomp プロファイル（`RuntimeDefault`）の下で動かす手順。porkadot を 0.37.3 から 0.37.4 に替え、`install kubernetes` を 1 回流す。**イメージ（`registry.k8s.io/coredns/coredns:v1.14.7`）と Corefile は変わらない。**
計画 `plan.md`（以下「計画」）§8 の CoreDNS の行の前半で、kube-dns-autoscaler の手順書 `runbook-dns-autoscaler-1.11.md`（以下「autoscaler の手順書」。2026-10-25 10:16〜10:20Z に本番で通した）と同じ形にする。ノードの kubelet にも etcd にも触らず、変わるのは Deployment 1 つ。ただし autoscaler と違い、**DNS を答えている Pod 2 つが入れ替わる。**

| | 更新前 | 更新後 |
|---|---|---|
| porkadot | 0.37.3（`121a264`、タグ `v0.37.3`） | **0.37.4**（`d0d84c9`、タグ `v0.37.4`） |
| seccomp | 注釈 `seccomp.security.alpha.kubernetes.io/pod: runtime/default`（K8s 1.27 から効かない。**今は seccomp なしで動いている**。§2.2 の 6） | **Pod の `securityContext.seccompProfile.type: RuntimeDefault`**（containerd の既定のプロファイルが実際に効く） |
| コンテナの `capabilities.drop` | `all` | **`ALL`**（containerd は大文字小文字を区別しないので動きは同じ。Pod Security の `restricted` の確かめが `ALL` だけを受け付けるため。porkadot#69） |
| イメージ・Corefile・引数・probe・resources・tolerations・RBAC・Service | — | **変わらない** |
| ConfigMap `kube-system/coredns`（Corefile） | resourceVersion `1239255997` | **変わらない**（`install kubernetes` は apply するが中身が同じ） |
| CoreDNS の replicas | 2（autoscaler が決める） | **2 のまま** |
| K8s、etcd、kubelet、kube-proxy、cnidaria、MetalLB、autoscaler、Longhorn | v1.37.1、3.7.3、… | 変えない（`install kubernetes` で apply し直されるが、マニフェストの差分が無い） |

porkadot 0.37.4 に入った PR は porkadot#69（マージ `8a54265`。`coredns.yaml.erb` の seccomp と `ALL`、テスト）と porkadot#70（`d0d84c9`。版を 0.37.4 にする）。0.37.3 から 0.37.4 の差分はこの 2 つだけ（`coredns.yaml.erb`、`version.rb`、`docs/spec/README.md`、テスト）で、**`install`・`etcd backup` の実装は 0.37.3 と同じ**。RuntimeDefault の下でも CoreDNS が `:53` を開けられる理由（containerd の既定のプロファイルは `bind`・`listen`・`setsockopt` を許す、`CAP_NET_BIND_SERVICE` の経路は変わらない）は porkadot#69 の本文にある。

**CoreDNS v1.15 はこの手順書の範囲の外**（§8.6）。v1.15.0 は registry.k8s.io にまだ無く（2026-10-26 06:4xZ に 404。§1.5）、出るまで待つ（2026-10-26 のユーザー判断）。それまで CoreDNS は v1.14.7 のままで、その前に seccomp の直しだけを入れる。

この手順は dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で先に通してある（2026-10-26 02:00〜02:08Z）。記録は porkadot-dev の `docs/k8s-upgrade/verification-coredns-seccomp.md`（以下「dev の記録」。porkadot-dev#23、main `ab2bcc3`）。dev は `8a54265` で通したもので、0.37.4 との違いは版の番号（#70）だけ。dev で分かったことは次のとおり。

- **`install kubernetes` は 1 回目で rc 0**（約 17 秒）。rollout は古い Pod の 1 つを止め、新しい Pod 2 つを同時に作り、2 つが Ready になってから残りの古い Pod を止める（約 9 秒）
- **入れ替わりの間、1 秒ごとの DNS の問い合わせ（クラスタ内・外・PTR・TCP）は 1 度も落ちなかった**（300 サンプル。入れ替わり 3 回とスケールを含む）
- 新しいコンテナは containerd の既定のプロファイルの下で動く（`Seccomp: 2`）。古いコンテナは CRI の profile が `Unconfined`、`Seccomp: 0`。capabilities は前後とも `CAP_NET_BIND_SERVICE` だけ
- 各 Pod の `:53`（UDP・TCP）の答えと rcode、`:8080/health`・`:8181/ready`・`:9153/metrics` は上げる前と同じ
- scale の書き込みの `non-functional in v1.27+` の warning が消えた
- v0.37.3 の `install kubernetes` で戻せた（rc 0。古い ReplicaSet が使われ、注釈と `drop: [all]` が戻り、`Seccomp: 0` に戻る）
- **新しい Pod が Ready になるまで 1〜10 秒でばらつく**（readinessProbe に `initialDelaySeconds` が無く、最初の probe が `:8181` の開く前に当たると次は 10 秒後。dev の見つけたことの 1）。その間 Ready な Pod は 1 つ（dev の見つけたことの 2）
- porkadot の `install kubernetes` のログには apply の warning が出ない（dev の見つけたことの 3）

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **本番の DNS の負荷**。入れ替わりの間、Ready な Pod が 1 つになる時間がある（§2.1 の 3）
- **新しい Pod のノードにイメージが無いときの pull**。dev はノードにイメージがあり pull が無かった。本番の v1.14.7 は chirico・duchamp にしか無い（§2.2 の 12、§8.3）
- **ノードの resolv.conf に kube-dns が入っていることによる `loop` の FATAL**。dev の 8 回の起動では出なかったが、本番では段 8 の reload で 1 回出ている（§2.2 の 8、§8.1）
- **arm64 のイメージ**（dev はすべて amd64）。本番でも taint のために worker（amd64）にしか載らないので、使われない（§2.1 の 4）
- **`fraction-auditor` での scale の dry-run**。auditor には `deployments/scale` の update が無く通らない（2026-10-26 06:4xZ の `kubectl auth can-i`）。本番は `infra-admin` のトークンで流す（§1.2、§4.3）

## 0. 役割と約束ごと

autoscaler の手順書 §0 と同じ形で、次のとおりにする。

- **承認の節目は 1 つ**。この手順書では ✋✋ を付けた。
  - ✋✋ **開始**: render の差分（§2.5。この手順書と同じ PR）、§2.2 のベースライン、§2.3 の監視、§2.6 の時間帯、§6 の止める条件、§7 のロールバックの形を見せ、PR をマージしてから、`install kubernetes` を流す前（§3.1）
- **節目の後の手順は、ユーザーに知らせるだけで進めてよい（✋）。** etcd のバックアップ（§2.4）、`infra-admin` のトークンの発行と scale の server dry-run（§3.1・§4.3）、`install kubernetes`（§3.2）は、この手順書に書いた形なら ✋ で、1 つずつ承認を取るものではない。✋ の前に、何をするかを知らせる。
- **runbook から外れる操作（ロールバック、`install kubernetes` の流し直しより先の対処、Pod の手での削除、Deployment の手での編集・scale・`rollout undo`、ConfigMap の書き換え、イメージの手での pull、ノードの resolv.conf の変更）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認は、知らせずに行ってよい。時刻はすべて UTC で記録する（control-plane のホストの時刻は JST）。

## 1. 前提

### 1.1 本番の今の姿

始める前に次を確かめる（読み取り）。2026-10-26 06:4xZ（この手順書を書いたとき）の値を書く。当日に読み直す。

- 8 台 Ready・schedulable、全台 v1.37.1。Pod は 170 個（Running 146、Succeeded 24）で、Running / Completed 以外は 0 個
- autoscaler の更新（`results/dns-autoscaler-1.11/summary.md`）が済んでいる。autoscaler は v1.11.0 の 1 つ（oeilvert の `kube-dns-autoscaler-5959bf78f6-pnh8z`、restart 0）で、ログは起動の 6 行だけ
- CoreDNS は v1.14.7 の 2 つ（§2.2 の 4）。どちらも段 7・段 8 の再起動の数が残る（§2.2 の 8）

### 1.2 kubeconfig の運用

段 8 の手順書 §1.2 と同じ（確認は `fraction-auditor`）。本番に書き込むのは porkadot の `etcd backup`（ノードの上の etcdctl）と `install kubernetes`（ノードの上の admin の kubeconfig）で、どちらもトークンは要らない。

**この手順書で `infra-admin` のトークンを使うのは、§3.1 と §4.3 の `kubectl scale --dry-run=server` だけ。** `fraction-auditor`（SA `infra-auditor`）は `deployments/scale` を update できず（2026-10-26 06:4xZ の `kubectl auth can-i update deployments/scale -n kube-system` が `no`）、server dry-run も書き込みの権限が要るため。dry-run は何も変えない。

```sh
ADMIN_TOKEN=$(kubectl --context fraction create token infra-admin -n kube-system --duration=1h)
kubectl-admin() { kubectl --context fraction --token="$ADMIN_TOKEN" "$@"; }
```

- トークンは §3.1 の dry-run の前に発行し、§4.3 の dry-run の後に破棄する（`unset ADMIN_TOKEN`。ファイルに書かない）。サーバーの側では 1 時間で切れる
- worker のハーネスのようにコマンドごとにシェルが新しくなり変数が残らないときは、§3.1 と §4.3 の dry-run ごとに、同じコマンドの中で発行・使用・`unset` する（2026-10-26 の本番。トークンをファイルに書いて持ち越さない）
- `kubectl-admin` で流すのは `kubectl-admin -n kube-system scale deployment/coredns --replicas=3 --dry-run=server` だけ。**`--dry-run=server` の無い `scale` は流さない**（replicas は autoscaler が決める）

### 1.3 SSH

autoscaler の手順書 §1.3 と同じ（worker は `ssh yuanying@<IP>`、control-plane は `ssh ubuntu@<IP>`。**名前ではなく IP で入る**。control-plane には `unset LC_ALL` してから入る）。2026-10-26 06:4xZ にこの手順書を書いたとき、8 台ともサンドボックスの中から §1.6 の `node-state.sh` を、chirico・duchamp に `seccomp.sh` を、oeilvert に `dns-watch.sh`・`endpoints.sh` を流せた。サンドボックスの中で通らないときは、サンドボックスの外での実行を coordinator に頼む（読み取りのコマンドだけ）。

### 1.4 porkadot の置き場と流し方

autoscaler の手順書 §1.4 と同じ形で、タスクディレクトリの独立の clone を使う。

| 用途 | 置き場 | 版 |
|---|---|---|
| **当日** | `/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-4` | v0.37.4（`d0d84c9`、detached） |
| **§7 の戻し** | `/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-3`（autoscaler の本番と dev の戻しで使ったもの。触らずに残す） | v0.37.3（`121a264`、detached） |

- 2026-10-26 06:4xZ に `git ls-remote https://github.com/yuanying/porkadot.git` で、GitHub の `refs/tags/v0.37.4`（tag object `59c82ba`）と `^{}`（`d0d84c9`）が 0.37.4 の clone と一致することを確かめた。`lib/porkadot/version.rb` は 0.37.4。この clone で §2.5 の render を流した
- 0.37.3 の clone は `git describe --tags` が `v0.37.3`（`121a264`、GitHub の tag object `91a366b`）。§7.1 の render をこの clone で流した
- どちらの clone も `git status --short` が空。push しない・書き換えない

**このリポジトリのルートを cwd にして** 流す。

```sh
P=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-4
git -C $P describe --tags          # v0.37.4
cd <このリポジトリの checkout>     # §2.5 の PR をマージした master
BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

以下、この形を `porkadot <サブコマンド>` と書く。

- 始める前に `BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot help` が動くことを確かめる
- 作業ツリーの `assets/` と `porkadot.yaml` に PR の外の変更が無いこと（`git status --short assets porkadot.yaml` が空）
- **流す porkadot のコマンドは `etcd backup` と `install kubernetes --node 192.168.1.111` の 2 つだけ。** `install kubelet`、`install all`、`--node` なしの `install kubernetes`、`render`（当日は render しない）、`setup-node`、`setup-containerd`、`etcd restore` は流さない
- `install kubernetes` の `--node` は control-plane の `porkadot.yaml` の `nodes` のキー（`192.168.1.111`）。付けないと bootstrap ノード（pablo）で流し、`127.0.0.1:6443` に届かず rc 1 になる

### 1.5 入れる版を確かめる

作業の当日に確かめ直す（読み取り）。

```sh
A='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
curl -sL -H "Accept: $A" https://registry.k8s.io/v2/coredns/coredns/manifests/v1.14.7 \
  | jq -r '[.manifests[].platform.architecture] | join(",")'      # amd64 を含む（§8.3 の pull で要る）
curl -sL -o /dev/null -w '%{http_code}\n' -H "Accept: $A" https://registry.k8s.io/v2/coredns/coredns/manifests/v1.15.0   # 404 なら §8.6 のとおり
```

2026-10-26 06:4xZ の時点: v1.14.7 は manifest list で amd64・arm・arm64・loong64・ppc64le・riscv64・s390x を含む。v1.15.0 は 404（registry.k8s.io の tags は v1.14.7 まで）。

### 1.6 確認に使うスクリプト

タスクディレクトリの `notes/runbook-coredns-seccomp/scripts/` に置いた（dev の `notes/dev-coredns-seccomp/scripts/` と autoscaler の手順書の `notes/runbook-dns-autoscaler/scripts/` を本番の値にしたもの）。どれも読み取りだけ。

| スクリプト | 中身 |
|---|---|
| `snap.sh <dir>` | `fraction-auditor` で、Node（Ready、unschedulable、allocatable の CPU、arch、taint）、全 Pod（UID・restartCount・phase）、CoreDNS と autoscaler の Deployment・ReplicaSet・Pod（securityContext を含む yaml）、`coredns` の ReplicaSet の一覧（revision・seccomp）、ConfigMap `coredns`・`kube-dns-autoscaler`、Service `kube-dns` と EndpointSlice、PDB、`coredns` の events、autoscaler のログ、CoreDNS の各 Pod のログと前のコンテナのログ。出力は `notes/runbook-coredns-seccomp/<dir>/` |
| `node-state.sh <dir>` | 8 台に IP で ssh し、kubelet の MainPID・NRestarts・ActiveEnterTimestamp、containerd の CoreDNS のイメージ |
| `seccomp.sh <worker の IP>` | その worker の `coredns` のコンテナすべての `crictl inspect`（CRI の config の `security_context.seccomp`、OCI spec の `linux.seccomp` の有無と規則の数、capabilities、`noNewPrivileges`）と `/proc/<pid>/status` の `Seccomp`（0 はなし、2 は filter）・`Seccomp_filters`・`NoNewPrivs`・`CapEff`・`CapBnd` |
| `endpoints.sh <dir>` | oeilvert（192.168.1.82）から、CoreDNS の各 Pod の IP の `:53` に UDP と TCP で 10 の問い合わせ（下）の rcode と答え、`:8080/health`・`:8181/ready`・`:9153/metrics` の HTTP の状態と `coredns_build_info`。各 Pod のログの `error`・`warn`・`fatal`・`loop` の行の数、autoscaler のログの seccomp の warning の数 |
| `dns-watch.sh <logdir>` | oeilvert から 1 秒ごとに、kube-dns の Service `10.254.0.10` に `dig +time=1 +tries=1` で `kubernetes.default.svc.cluster.local`（`in=`）、`kube-dns.kube-system.svc.cluster.local`（`dns=`）、`www.google.com`（`ext=`）の A（UDP）、`10.0.254.10.in-addr.arpa` の PTR（`ptr=`、UDP）、`kubernetes.default.svc.cluster.local` の A（`tcp=`、TCP）を問い合わせる。答えが無ければ `FAIL`。`<logdir>/dns.log` に 1 秒 1 行 |
| `dns-replicas-watch.sh <logdir>` | 1 秒ごとの `coredns` の replicas（spec / ready / updated / status）と、CoreDNS と autoscaler の Pod（名前、phase、Ready、restart、ノード、Terminating の印）を `<logdir>/dns-replicas.log` に |

`endpoints.sh` の問い合わせ: A の `kubernetes.default.svc.cluster.local`・`kubernetes.default.svc.fraction.cluster`・`kube-dns.kube-system.svc.cluster.local`、SRV の `kube-dns.kube-system.svc.cluster.local`、NXDOMAIN の `nosuch.default.svc.cluster.local`・`nosuch.invalid`、PTR の `1.0.254.10.in-addr.arpa`・`10.0.254.10.in-addr.arpa`、外の `www.google.com`・`example.com`。外の名前の A は毎回変わりうるので、比べるのは rcode だけ。

`dns-watch.sh` と `dns-replicas-watch.sh` は `<logdir>/watch.stop` を作ると止まる（`dns-watch.sh` は 60 秒ごとに ssh を張り直すので、止まるまで最長 1 分）。当日の `<logdir>` はタスクディレクトリの `notes/coredns-seccomp/logs`。

このリポジトリの `tools/dns-check.sh`（段 6〜8 で使った、Service と各 Pod への AAAA・Service の PTR を含む問い合わせ）も、§2.2 と §4.2 で前後に 1 回ずつ流す。

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 流し方 | porkadot 0.37.4 の `install kubernetes --node 192.168.1.111` を 1 回。CRD の server-side apply、apiserver の apply と rollout の待ち（apiserver は変わらないので Pod は入れ替わらない）、全体の `apply -k --prune` | dev の記録、`assets/kubernetes/install.sh` |
| 2 | drain・cordon | しない（ノードには触らない） | — |
| 3 | 入れ替わり | Deployment `coredns` は RollingUpdate（`maxSurge: 25%`・`maxUnavailable: 1`、replicas 2。surge は切り上げで 1）。rollout は古い Pod の 1 つを止め（`lameduck 5s` の間は答え続ける）、新しい Pod 2 つを同時に作り、新しい Pod が Ready になると残りの古い Pod を止める（`maxUnavailable: 1` なので、新しい Pod が 1 つ Ready になれば止めてよい。2026-10-26 の本番では 1 つ目が Ready になった秒に止めた。dev では 2 つがほぼ同時に Ready になった）。**その間 Ready な Pod は 1 つになる時間がある**（dev では数秒〜10 秒。本番は pull があれば延びる。§8.2・§8.3）。PDB は無い | live の `strategy`、dev の記録の見つけたことの 1・2 |
| 4 | 配置 | 新しい Pod は taint の無い worker（chirico、duchamp、oeilvert、pablo。どれも amd64）のどれか。tolerations は `CriticalAddonsOnly` だけで、control-plane（`node-role.kubernetes.io/master:NoSchedule`）と braque（`unstable.cloud/storage:NoSchedule`）には載らない。`podAntiAffinity` は無いので、新しい 2 つが同じノードに載ることはありうる（§8.4） | live の tolerations と taint（§2.2 の 1・3） |
| 5 | 途切れ | 見込まない（dev で 0）。許容する範囲: DNS の監視の 1〜2 サンプルの FAIL（記録する）。止める条件は §6 | 2026-10-19 のユーザーの方針（短時間の障害は許容） |
| 6 | イメージの事前 pull | **しない**。#3 のとおり古い Pod の 1 つは新しい Pod が Ready になるまで答え続けるので、pull の時間は途切れにならない（Ready な Pod が 1 つの時間が延びるだけ）。v1.14.7 は 24.3 MB。registry.k8s.io から取れないときは新しい Pod が `ImagePullBackOff` のまま古い Pod の 1 つが残り、§6 で止める | §2.2 の 12、autoscaler の手順書 §2.1 の 6 |
| 7 | etcd のバックアップ | `install kubernetes` の前に 1 回（§2.4） | 計画 §6.1 の 5 と同じ扱い |
| 8 | warning の確かめ | **ConfigMap `kube-dns-autoscaler` は書き換えない。** autoscaler は replicas が 2 のまま scale を書かないので、自然な動きでは warning は出ない。`infra-admin` のトークンで `kubectl scale --replicas=3 --dry-run=server` を前後に流し、warning が消えたことを見る（§3.1・§4.3。何も変えない） | dev の記録の「確かめ方」、§1.2 |
| 9 | `loop` | 新しい Pod の起動の `loop` の確かめで FATAL になり 1 回再起動しうる。**1 つの Pod で 1 回まで**は、前のコンテナのログに `plugin/loop` があり起き直して Ready なら想定どおりとして記録して進める。CrashLoopBackOff・2 回以上なら止める | 段 8 の手順書 §8.16、dev の記録の「loop」、§8.1 |
| 10 | 時間帯 | jumelle の 18:00〜19:30Z、worker の unattended-upgrades 06:00〜07:00Z、control-plane の 21:00〜22:00Z を避ける（§2.6） | autoscaler の手順書 §2.6 |
| 11 | 範囲の外 | CoreDNS v1.15（§8.6）、ノードの resolv.conf の kube-dns（§8.1）、古い ReplicaSet と古いイメージの片付け（§10） | 2026-10-26 のユーザー判断、段 8 の手順書 §10 |

### 2.2 ベースライン

作業の当日、`install kubernetes` の前に次を取り、`results/coredns-seccomp/baseline.md` に残す（すべて読み取り）。出力はタスクディレクトリの `notes/coredns-seccomp/base/` に置く（`snap.sh` などは `notes/runbook-coredns-seccomp/` の下に書くので、`../coredns-seccomp/base` と渡す）。

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-coredns-seccomp/scripts
B=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/coredns-seccomp/base
bash $S/snap.sh ../coredns-seccomp/base
bash $S/node-state.sh ../coredns-seccomp/base
bash $S/endpoints.sh ../coredns-seccomp/base
bash $S/seccomp.sh 192.168.1.135 > $B/seccomp-duchamp.txt    # CoreDNS の Pod のノードごとに
bash $S/seccomp.sh 192.168.1.83 > $B/seccomp-chirico.txt
docs/k8s-upgrade/tools/dns-check.sh yuanying@192.168.1.82 > $B/dns-check.txt
```

| # | 項目 | 2026-10-26 06:4xZ の値（当日に読み直す） |
|---|---|---|
| 1 | Node と taint | 8 台 Ready、v1.37.1、cordon されたものは無い。taint は control-plane 3 台が `node-role.kubernetes.io/master:NoSchedule`、braque が `unstable.cloud/storage:NoSchedule`、chirico・duchamp・oeilvert・pablo は無い |
| 2 | 全 Pod の名前・UID・restartCount | 170 個（Running 146、Succeeded 24）。Running / Completed 以外は 0 個（§4.2 で「CoreDNS 以外は変わらない」を見る元） |
| 3 | `coredns` の Deployment | generation 13、revision 10、2/2（updated 2）。イメージ `registry.k8s.io/coredns/coredns:v1.14.7`。テンプレートの注釈 `seccomp.security.alpha.kubernetes.io/pod: runtime/default`、Pod の securityContext は `{}`（`seccompProfile` は無い）。コンテナの securityContext は `allowPrivilegeEscalation: false`・`capabilities: {add: [NET_BIND_SERVICE], drop: [all]}`・`readOnlyRootFilesystem: true`。readinessProbe は `:8181/ready`（`periodSeconds: 10`、`initialDelaySeconds` なし）、livenessProbe は `:8080/health`（`initialDelaySeconds: 60`、`failureThreshold: 5`）。resources は requests `cpu: 100m`・`memory: 70Mi`、limits `memory: 170Mi`。tolerations は `CriticalAddonsOnly`、nodeSelector は `kubernetes.io/os: linux`、affinity は無い、`dnsPolicy: Default`、`terminationGracePeriodSeconds: 30`。strategy は RollingUpdate（`maxSurge: 25%`・`maxUnavailable: 1`）、revisionHistoryLimit 10。PDB は無い（kube-system の PDB は `kube-controller-manager`・`kube-scheduler` だけ） |
| 4 | CoreDNS の Pod | `coredns-76d7d8dc86-469lz`（duchamp、`10.244.5.210`、UID `f0d31e8b-…`、restart 7）と `coredns-76d7d8dc86-shdgn`（chirico、`10.244.8.74`、UID `a7417640-…`、restart 5）。どちらも 2026-10-21 13:04:32Z 作成。imageID は `registry.k8s.io/coredns/coredns@sha256:7efd3c63…`。EndpointSlice `kube-dns-wr2s4` の endpoint はこの 2 つの IP |
| 5 | `coredns` の ReplicaSet | `coredns-76d7d8dc86`（revision 10、2/2、v1.14.7。§7 の戻しで使われる見込み）と、replicas 0 の 9 つ（revision 1〜9、k8s.gcr.io の 1.6.7 から v1.13.2 まで）。どれも `seccompProfile` が無い |
| 6 | 今の Pod の seccomp（`seccomp.sh 192.168.1.135`・`192.168.1.83`） | 2 つとも CRI の config の `security_context.seccomp` が `{'profile_type': 1}`（Unconfined）、OCI spec に `linux.seccomp` が無い、`Seccomp: 0`・`Seccomp_filters: 0`。capabilities は bounding・effective・permitted とも `CAP_NET_BIND_SERVICE` だけ（`CapEff`・`CapBnd` が `0x400`）、`noNewPrivileges: true`（`NoNewPrivs: 1`）。**今は seccomp なしで動いている**（dev の古い Pod と同じ） |
| 7 | ConfigMap `kube-system/coredns` | resourceVersion `1239255997`。Corefile は段 8 のもの（`kubernetes cluster.local fraction.cluster in-addr.arpa ip6.arpa`、`forward . /etc/resolv.conf`、`cache 30 { disable success cluster.local; disable denial cluster.local }`、`loop`、`reload`、`health { lameduck 5s }`）。Corefile の SHA512（`kubectl get cm coredns -o jsonpath='{.data.Corefile}' \| sha512sum`）は `dbda5533…`、Pod のログの `Running configuration SHA512` は `78384ea2…` |
| 8 | CoreDNS のログと前の再起動 | `-469lz` の最後の終わり方は 2026-10-23 02:19:56Z の exit 1（前のコンテナのログの最後が `[FATAL] plugin/loop: Loop (10.244.5.1:39089 -> :53) detected for zone "."`。段 8 の手順書 §2.10 の IPv6 のプレフィックスの切り替えの件）。`-shdgn` は 2026-10-23 22:23:40Z の exit 1（段 8 の `install kubernetes` の reload の後の `[FATAL] plugin/loop: Loop (10.244.5.210:47808 -> :53)`。段 8 の手順書 §3.3 の 13 の想定どおりの 1 回）。今のコンテナのログに、`-469lz` は 2026-10-26 00:38:07〜00:38:11Z の `api.tumblr.com` の上流（192.168.0.1、10.254.0.10）への `i/o timeout` が 4 行（前からのもの。§4.2 で数を比べる）、`-shdgn` はエラーが無い |
| 9 | 各 Pod の答え（`endpoints.sh`） | 2 つの Pod とも、UDP と TCP で同じ: `kubernetes.default.svc.cluster.local`・`kubernetes.default.svc.fraction.cluster` が `10.254.0.1`、`kube-dns.kube-system.svc.cluster.local` が `10.254.0.10`、SRV が 53 と 9153、`nosuch.default.svc.cluster.local`・`nosuch.invalid` が NXDOMAIN、PTR の `1.0.254.10`・`10.0.254.10` が `kubernetes.default.svc.cluster.local.`・`kube-dns.kube-system.svc.cluster.local.`、`www.google.com`・`example.com` が NOERROR。`:8080/health`・`:8181/ready`・`:9153/metrics` が 200、`coredns_build_info{…version="1.14.7"}` |
| 10 | autoscaler | v1.11.0 の 1/1（§1.1）。ConfigMap `kube-dns-autoscaler` の `data.linear` が `{"coresPerReplica":256,"nodesPerReplica":16,"preventSinglePointFailure":true}`、resourceVersion `901196490`。計算は 2（autoscaler の手順書 §2.2 の 9）。ログに seccomp の warning は 0（scale を書いていない） |
| 11 | kubelet（`node-state.sh`） | .111 MainPID 752609・NRestarts 0、.112 1028・1、.113 612672・0、braque 541944・0、chirico 3237977・0、duchamp 202232・0、oeilvert 916805・51、pablo 3509679・0（autoscaler のベースラインと同じ） |
| 12 | containerd の CoreDNS のイメージ | **`coredns:v1.14.7` は chirico と duchamp にだけある**（`97efff2babf85`、24.3 MB）。oeilvert には CoreDNS のイメージが 1 つも無く、pablo は v1.11.3 まで、braque・control-plane には無い。新しい Pod が oeilvert か pablo に載ると pull する（§8.3） |
| 13 | ノードの resolv.conf | chirico・duchamp・pablo の `/run/systemd/resolve/resolv.conf` の nameserver は 192.168.0.1、`2405:6580:6740:ac01::1`、10.254.0.10。oeilvert は 192.168.0.1、10.254.0.10、192.168.0.1、`2405:6580:6740:ac01::1`。**4 台とも kube-dns（10.254.0.10）が入っている**（前からのもの。段 8 の手順書 §2.10、§8.1） |
| 14 | DNS | oeilvert から `10.254.0.10` に 5 つの問い合わせが通る（§2.3 の `dns-watch.sh` を 1 分流し、60 サンプルで FAIL 0）。`tools/dns-check.sh yuanying@192.168.1.82` は Service（作業端末から）と 2 つの Pod（oeilvert から）で答えが同じ（クラスタ内の A・AAAA・PTR、`h2.fs` の A・AAAA、外の A・AAAA、NXDOMAIN 2 つ） |
| 15 | 権限 | `fraction-auditor` は `deployments/scale` の update・`deployments` の patch が `no`（§1.2）。scale の dry-run の warning は §3.1 で取る |
| 16 | VIP | `https://192.168.1.101:6443/readyz` が 200 |

### 2.3 監視

`install kubernetes` の前から、§4 の確認が終わるまで流す（読み取り）。autoscaler の手順書 §2.3 と同じく、**`nohup` や `&` で起動しない。** worker のハーネスのバックグラウンド実行で、**監視ごとに 1 つのジョブとして**起動する（`dns-watch.sh` で 1 つ、`dns-replicas-watch.sh` で 1 つ。合わせて 2 つ）。

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-coredns-seccomp/scripts
L=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/coredns-seccomp/logs
bash $S/dns-watch.sh $L             # ジョブ 1
bash $S/dns-replicas-watch.sh $L    # ジョブ 2
```

- 起動したら、ジョブの一覧に 2 つが居ることと、`dns.log`・`dns-replicas.log` に行が足されていくことを確かめる。**`install kubernetes` の前に、2 つのログの最後の行の時刻が 1 分以内であること**（`dns.log` は ssh の 1 回分の 60 行ずつまとめて書かれることがあるので、最初の 1 分は待つ）
- 止めるときは `touch $L/watch.stop`（2 つとも止まる）
- `dns.log` の FAIL は `in=`・`dns=`・`ext=`・`ptr=`・`tcp=` のどれかが `FAIL`。`ssh rc=` の行は監視の側の切れ目（記録して、続くなら見直す）
- `dns-replicas.log` で見るもの: `coredns(spec/ready/updated/status)` の ready が 1 を下回らないこと、新しい Pod と古い Pod の名前・restart・`:TERMINATING`
- 監視のノード oeilvert には、新しい CoreDNS の Pod が載ることがある。Service への問い合わせなので監視には関わらない（autoscaler の本番で autoscaler が oeilvert に載ったときと同じ）
- 段 8 の手順書 §2.3 の etcd の health の監視、MetalLB の手順書の `probe.sh` は流さない（etcd にも LoadBalancer にも触らない）

### 2.4 etcd のバックアップ ✋

`install kubernetes` の前に、porkadot 0.37.4 で取る（autoscaler の手順書 §2.4 と同じ形。0.37.4 の `etcd backup` は 0.37.3 と同じ実装で、ノードの 3.7.3 の etcdctl を使う）。

```sh
porkadot etcd backup
ls -l ./backup/
```

- 手元のファイルは `./backup/etcd-<日時>.db`、モード 0600。`./backup/` は `.gitignore` で除外してある。スナップショットには Secret が平文で入っているので、`git add -f` などで追加しない。worktree で流したときは、worktree を片付ける前にメインの checkout の `backup/` へ写す
- 時刻、ファイル名、サイズ、sha256 を記録する（autoscaler の前のものは 55,107,616 B、この手順の 2026-10-26 07:02Z のものは 66,986,016 B）。桁が違えば止める
- CoreDNS の seccomp の直しは etcd の restore を要しない見込み（§7 のロールバックは `install kubernetes` で戻す）。このバックアップは想定外のときの最後の手段

### 2.5 render の差分（この手順書と同じ PR）

2026-10-26 06:42Z に、porkadot 0.37.4（`d0d84c9`。§1.4 の clone）で、このリポジトリのルートを cwd にして `render kubernetes` を流した（rc 0）。`porkadot.yaml` は変えていない。前の render は master の `e52d04b` の assets（autoscaler の porkadot 0.37.3 の render。その後の #61・#62 は `assets/` を変えていない）。

**差分は `assets/kubernetes/manifests/addons/coredns/coredns.yaml` の 1 ファイルだけ**（新しくできたファイル、消えたファイル、証明書・sops の Secret の作り直しも無い）。

```diff
@@ -116,9 +116,10 @@ spec:
     metadata:
       labels:
         k8s-app: kube-dns
-      annotations:
-        seccomp.security.alpha.kubernetes.io/pod: 'runtime/default'
     spec:
+      securityContext:
+        seccompProfile:
+          type: RuntimeDefault
       priorityClassName: system-cluster-critical
       serviceAccountName: coredns
       tolerations:
@@ -171,7 +172,7 @@ spec:
             add:
             - NET_BIND_SERVICE
             drop:
-            - all
+            - ALL
           readOnlyRootFilesystem: true
       dnsPolicy: Default
       volumes:
```

- **この差分は dev の差分と同じ**（dev の記録の「render の差分」、porkadot#69 の本文。#69 の本文は、本番の設定と assets でも同じ 1 ファイルだけと書いている）
- **変わらないもの**: 同じファイルの ServiceAccount・ClusterRole・ClusterRoleBinding・ConfigMap `coredns`（Corefile）・Service `kube-dns`、Deployment のイメージ・引数・probe・resources・tolerations、`dns-horizontal-autoscaler.yaml`、addon の `kustomization.yaml`
- `render kubelet`・`render etcd`・`render bootstrap` は、このリポジトリの `/tmp` の clone で 4 つとも流し（rc 0）、差分が証明書の 12 ファイル（各ノードと bootstrap の `bootstrap.crt`、control-plane の `etcd.crt`）と上の 1 ファイルだけであることを確かめた。この 3 つは `install kubernetes` で使わないので、PR には入れていない（autoscaler の手順書 §2.5 と同じ）
- `render kubernetes` は証明書を作り直さない。当日は render しない（この PR の `assets/` で流す）
- secrets（`assets/` の sops の証明書と鍵）は、この PR では変わらない

### 2.6 時間帯

autoscaler の手順書 §2.6 と同じ時間帯を避ける。CoreDNS は上流（`forward . /etc/resolv.conf`）に直接関わるので、jumelle の時間帯は特に避ける。

| 時間帯（UTC） | 何が起きるか | 避ける理由 |
|---|---|---|
| **18:00〜19:30** | jumelle の unattended-upgrades と自動再起動 | jumelle が落ちると registry.k8s.io からの pull が止まり（新しい Pod が起動しない）、DNS の監視の外の名前（`www.google.com`）が FAIL になって入れ替わりの影響と見分けられない。**上流の DNS が答えない間の CoreDNS の起動は、`loop` の FATAL と OOMKilled の繰り返しになりうる**（段 8 の手順書 §2.10 の 2026-10-23 02:14〜02:26Z の件） |
| 06:00〜07:00 | worker 5 台の unattended-upgrades | needrestart がサービスを再起動すると、§4.2 の「kubelet が再起動しない」「ほかの Pod が変わらない」の確かめと取り違える。CoreDNS は worker に載っている |
| 21:00〜22:00 | control-plane 3 台の unattended-upgrades | 同上（apiserver） |

- 作業は、監視の起動から §4 の確認まで 20 分ほどを見込む。その間が上の時間帯に重ならないこと

### 2.7 dev の記録と違う本番の形

| 点 | dev | 本番 | この手順書での扱い |
|---|---|---|---|
| kube-dns の Service | `10.252.0.10` | `10.254.0.10` | スクリプトは本番の値 |
| DNS の監視のノード | .122（ubuntu） | oeilvert（`yuanying@192.168.1.82`）。CoreDNS は chirico・duchamp | 新しい CoreDNS が oeilvert に載ることはあるが、Service への問い合わせなので監視には関わらない |
| v1.14.7 のイメージ | 全台にあった（pull 無し） | chirico・duchamp だけ | oeilvert・pablo に載ると 24.3 MB を pull する。Ready な Pod が 1 つの時間が延びる（§8.3） |
| ドメイン | `cluster.local` | `cluster.local` と `fraction.cluster` | `endpoints.sh` で `kubernetes.default.svc.fraction.cluster` も問い合わせる |
| 負荷 | ほぼ無い | アプリの問い合わせがある | 入れ替わりの間に Ready が 1 つの時間の FAIL を §6 で見る |
| resolv.conf の kube-dns | .121・.122 で 3 つ目 | chirico・duchamp・pablo で 3 つ目、oeilvert で 2 つ目 | `loop` の FATAL が出うる（§8.1）。dev の 8 回の起動では出ていない |
| scale の dry-run | `test-admin` で流せた | `fraction-auditor` では流せない | `infra-admin` のトークン（§1.2） |
| warning | autoscaler が実際に scale を書いた（ConfigMap を書き換えた）ときにも見た | ConfigMap は書き換えない | dry-run だけで見る（§4.3） |

## 3. `install kubernetes`

### 3.1 事前確認

✋✋ **開始の承認を取る。** §2.5 の差分と PR、§2.2 のベースライン（特に 3〜9・12・13 の Deployment・Pod・seccomp・Corefile・前の再起動・答え・イメージの有無・resolv.conf）、§2.3 の監視、§2.6 の時間帯、§6 の止める条件、§7 のロールバックの形、§8.1 の `loop` の扱いを示す。承認を得て PR をマージし、マージした master で次に入る。

- §2.2 のベースラインと §2.4 のバックアップが済んでいる。§2.3 の 2 つの監視がジョブとして動き、ログの最後の行が 1 分以内
- 全台 Ready、`coredns` が 2/2、autoscaler が 1/1
- checkout が §2.5 の PR をマージした master で、`git status --short assets porkadot.yaml` が空。`git -C $P describe --tags` が `v0.37.4`
- 作業の時間が §2.6 の時間帯と重ならない
- ✋ `infra-admin` のトークンを発行し（§1.2）、scale の server dry-run の warning を取る。**`--dry-run=server` を付けたことを確かめてから流す**

  ```sh
  kubectl-admin -n kube-system scale deployment/coredns --replicas=3 --dry-run=server
  ```

  dev では `Warning: spec.template.metadata.annotations[seccomp.security.alpha.kubernetes.io/pod]: non-functional in v1.27+; use the "seccompProfile" field instead` と `deployment.apps/coredns scaled (server dry run)` が出た。同じ warning が出ることを記録する。直後に `coredns` の replicas が 2 のままで generation が 13 のままであることを確かめる（dry-run が何も変えていないこと）

### 3.2 流す ✋

```sh
porkadot install kubernetes --node 192.168.1.111
```

- 時刻と rc を記録する。dev では約 17 秒で rc 0、autoscaler の本番では 24.5 秒
- 出力で見るもの:
  - `deployment.apps/coredns configured`
  - 前からの `configured`: PDB `kube-controller-manager`・`kube-scheduler`、DaemonSet `kube-apiserver`（apiserver の apply と全体の apply で 2 回）、ValidatingWebhookConfiguration `metallb-webhook-configuration`。dev の出力と autoscaler の本番の出力にもあり、Pod は入れ替わらない（autoscaler の記録 `summary.md` §2。generation が変わらなければ想定内）
  - **ほかは `unchanged`**（`kube-dns-autoscaler`・ConfigMap `coredns`・Service `kube-dns`・ServiceAccount・ClusterRole・ClusterRoleBinding `coredns`（`system:coredns`）を含む）。ConfigMap `coredns` が `configured` なら止める（Corefile は変わらないはず。§2.2 の 7 と比べる）
  - **`pruned` の行が無い**（オブジェクトの組は変わらない）
  - apply の warning はログに出ない（dev の見つけたことの 3）。warning は §4.3 で見る
- rc 1 のときの扱い（`connection refused` など）は段 8 の手順書 §8.3 と同じ。全体の apply の前に落ちたなら CoreDNS は前のまま。原因を見て流し直す（流し直しは ✋ の範囲）。2 回目も落ちたら止めて報告する
- 流した直後に、§2.3 の 2 つの監視のログが続いていることを確かめる

## 4. 後の確認

### 4.1 入れ替わりを見る

```sh
kubectl --context fraction -n kube-system rollout status deployment/coredns --timeout=3m
```

- `dns-replicas.log` で、古い Pod の 1 つに `:TERMINATING` が付き、新しい Pod 2 つが taint の無い worker に作られ、Running・Ready になり、残りの古い Pod が `:TERMINATING` になって消えるのを見る（dev では約 9 秒）。時刻を控える
- **ready が 0 になる行が無いこと**（`coredns(spec/ready/updated/status)` の 2 つ目。Terminating の古い Pod は lameduck の間 Ready に数えられることがある）
- **新しい Pod が 2 分たっても Ready にならないときは止める**（古い Pod の 1 つは残っている。§6）。`ImagePullBackOff`・`ErrImagePull` なら pull の失敗（§8.3）
- 新しい Pod の restart が 1 になったら、その Pod の前のコンテナのログを取る（`kubectl --context fraction -n kube-system logs <Pod> --previous`）。最後が `[FATAL] plugin/loop` なら §8.1 の想定どおりとして記録して進める（§6 の条件まで）
- `dns.log` に FAIL が出たら、時刻と名前を控える

### 4.2 確認

rollout が終わったら、`snap.sh`・`node-state.sh`・`endpoints.sh` を `../coredns-seccomp/after` に、`seccomp.sh <新しい Pod のノードの IP>`（ノードごと）を `after/seccomp-<ノード>.txt` に、`tools/dns-check.sh yuanying@192.168.1.82` を `after/dns-check.txt` に取り、§2.2 と比べる。

| # | 確認 | 合格基準 |
|---|---|---|
| 1 | Deployment | generation が 1 つ増える（2026-10-26 は 13 → 14）、revision 11。2/2、updated 2。テンプレートの Pod の `securityContext.seccompProfile.type` が `RuntimeDefault`、注釈 `seccomp.security.alpha.kubernetes.io/pod` が無い（テンプレートの annotations が無い）、コンテナの `capabilities.drop` が `[ALL]`。イメージ・引数・probe・resources・tolerations・strategy が §2.2 の 3 と同じ |
| 2 | Pod | **2 つとも v1.14.7 で Running、Ready**。古い Pod 2 つ（`-469lz`・`-shdgn`）が無い。restart は 0（§8.1 の `loop` の 1 回は、前のコンテナのログに `plugin/loop` があり起き直して Ready なら記録して合格とする）。imageID が §2.2 の 4 と同じ digest（`sha256:7efd3c63…`） |
| 3 | 配置 | chirico・duchamp・oeilvert・pablo のどれか（control-plane と braque には無い）。2 つが同じノードかを記録する（§8.4） |
| 4 | ReplicaSet | 新しい ReplicaSet が 2/2（revision 11、`seccompProfile` が `RuntimeDefault`）。`76d7d8dc86` は 0 で残る（§7 で使う）。古い 9 つも 0 のまま残る（古い ReplicaSet は 10 になり、revisionHistoryLimit 10 に収まる。§7 で戻すと新しいほうが古い側に回り 11 になるので、最も古い `coredns-76bd8dbd8c`（revision 1）が消える） |
| 5 | seccomp（`seccomp.sh`。ノードへの SSH はサンドボックスの中で） | **新しい Pod 2 つとも**、CRI の config の `security_context.seccomp` が `{}`（`profile_type` 0 = RuntimeDefault。JSON で 0 が省かれる。dev の `RuntimeDefault`）、OCI spec に `linux.seccomp`（`defaultAction: SCMP_ACT_ERRNO`。規則の数を記録する。dev は 13、autoscaler の本番は 14）がある、**`/proc/<pid>/status` が `Seccomp: 2`、`Seccomp_filters: 1`**。capabilities は §2.2 の 6 と同じ（`CAP_NET_BIND_SERVICE` だけ、`CapEff`・`CapBnd` が `0x400`、`NoNewPrivs: 1`） |
| 6 | 答え（`endpoints.sh`） | 新しい Pod 2 つとも、UDP と TCP で、**クラスタ内の名前の答え（A・SRV・PTR）と、すべての rcode が §2.2 の 9 と同じ**（外の名前の A は rcode だけ比べる）。`:8080/health`・`:8181/ready`・`:9153/metrics` が 200、`coredns_build_info` が 1.14.7 |
| 7 | 答え（`tools/dns-check.sh`） | Service と各 Pod の答えが `base/dns-check.txt` と同じ（外の名前と、Pod の IP の入った PTR の行は、IP が変わる分を読み替える） |
| 8 | ログ | 新しい Pod のログが起動の行（`maxprocs`、`.:53`、`Running configuration SHA512 = 78384ea2…`（§2.2 の 7 と同じ Corefile）、`CoreDNS-1.14.7`、`linux/amd64`）だけ。**`[ERROR]`・`[WARNING]`・`[FATAL]`・`plugin/loop` が無い**（§8.1 の 1 回は前のコンテナのログに残る。記録する）。上流の `i/o timeout` が出たら時刻と上流を記録する（§2.2 の 8 のとおり前から出うる。続くなら §6） |
| 9 | Corefile | ConfigMap `coredns` の resourceVersion（`1239255997`）と Corefile の SHA512 が §2.2 の 7 と同じ |
| 10 | Service | EndpointSlice の endpoint が新しい Pod 2 つの IP だけ。Service `kube-dns` の clusterIP が `10.254.0.10` のまま |
| 11 | replicas と autoscaler | `coredns` の replicas 2。autoscaler の Pod（名前・UID・restart）と ConfigMap `kube-dns-autoscaler`（resourceVersion `901196490`）が §2.2 の 10 と同じ。autoscaler のログに `Replicas are not as expected`・`E`・`W` で始まる行が無い |
| 12 | ほかの Pod | 全 Pod の比較で、**変わったのは CoreDNS の Pod だけ**（名前・UID・restartCount）。kube-proxy・cnidaria・autoscaler・apiserver・KCM・scheduler・MetalLB の Pod の UID と restartCount が §2.2 の 2 と同じ。Running / Completed 以外が 0 |
| 13 | kubelet | 8 台の MainPID・NRestarts・ActiveEnterTimestamp が §2.2 の 11 と同じ。containerd のイメージは、pull があった台に `coredns:v1.14.7` が増えただけ |
| 14 | 監視の FAIL | `dns.log` の `install kubernetes` から §4.3 の終わりまでの FAIL の数（名前ごと）とサンプルの間の最大。dev では 0 |
| 15 | warning | §4.3 |
| 16 | 健全性 | 8 台 Ready、VIP の `https://192.168.1.101:6443/readyz` が 200 |

- 段 8 の手順書 §1.8 の `netcheck.sh`、§1.9 の `npcheck.sh` は流さない（ネットワークにも NetworkPolicy にも触らない）

### 4.3 warning の確かめ（ConfigMap は書き換えない）

✋ §3.1 と同じ server dry-run を流す。

```sh
kubectl-admin -n kube-system scale deployment/coredns --replicas=3 --dry-run=server
unset ADMIN_TOKEN
```

- **`non-functional in v1.27+` の warning が出ない**こと（`deployment.apps/coredns scaled (server dry run)` だけ）。dev と同じ
- 直後に `coredns` の replicas が 2、generation が 14 のままであること
- トークンを破棄する（§1.2）
- autoscaler のログは、replicas が 2 のまま scale を書かないので warning の有無を示さない（§2.2 の 10）。autoscaler が何かの理由で scale を書いたなら、そのログに warning が無いことも記録する

### 4.4 監視を止める

§4.2・§4.3 が終わったら、§2.3 の監視を止める（`touch $L/watch.stop`）。2 つのジョブが終わったことを確かめる。

## 5. （なし）

autoscaler の手順書 §5 と同じく、片付けは無い。古い ReplicaSet `76d7d8dc86` とイメージは §7 の戻しの材料なので残す（§10）。

## 6. 止める条件

次のどれかに当たったら、その場で止めて報告する。続けるか §7 で戻すかはユーザーが決める。

- **新しい Pod が 2 分たっても Ready にならない**（`ImagePullBackOff`、`CreateContainerError` など。seccomp のためにコンテナが起きないときもここに入る）
- **新しい Pod が CrashLoopBackOff になる、または 1 つの Pod の restartCount が 2 以上になる**。1 回で、前のコンテナのログの最後が `[FATAL] plugin/loop` で、起き直して Ready なら §8.1 のとおり記録して進める。`plugin/loop` 以外の理由（`OOMKilled`、seccomp の拒否らしいもの（`operation not permitted`）など）での 1 回は止める
- **`coredns` の ready が 0 になる**（`dns-replicas.log`）
- **DNS の監視の FAIL が 5 サンプル（約 5 秒）を超えて続く**、または合わせて 10 サンプルを超える（`ext=` だけの FAIL は jumelle と上流の問題のこともあるので、`in=`・`dns=`・`ptr=`・`tcp=` と分けて記録する）
- 新しい Pod の答え・rcode が §2.2 の 9 と違う、`:8080`・`:8181`・`:9153` が 200 にならない
- 新しい Pod が `Seccomp: 2` にならない（CoreDNS は動いていても、この手順の目的が果たせていない。戻すかはユーザーが決める）
- `coredns` の replicas が 2 でなくなる、ConfigMap `coredns`・`kube-dns-autoscaler` が変わる
- CoreDNS 以外の Pod の再起動（kubelet・kube-proxy・cnidaria・autoscaler・apiserver など）、Node の NotReady
- `install kubernetes` が 2 回続けて rc 0 にならない
- `install kubernetes` の出力に `pruned` の行がある、ConfigMap `coredns` が `configured`

1〜2 サンプルの FAIL は、記録して進める。

## 7. ロールバック

**戻すのは runbook から外れる操作なので、ユーザーの承認を取る。** porkadot 0.37.3 の `install kubernetes` で注釈だけの CoreDNS に戻す（dev で確かめた。rc 0、途切れなし）。CoreDNS の Pod はもう 1 度入れ替わる。

### 7.1 戻すための材料

- **前の版の assets**: この PR の前の master（**`e52d04b`**）の `assets/` と `porkadot.yaml`。**porkadot 0.37.3 で `render kubernetes` しても、この `assets/` とバイトまで同じ**（2026-10-26 06:42Z に `/tmp` の clone で確かめた。`git status --short` が空）なので、当日に render しないで使う
- **porkadot 0.37.3**: §1.4 の `worktrees/porkadot-v0-37-3`

用意の仕方（作業端末で。autoscaler の手順書 §7.1 と同じ形。`git worktree add` は元の clone の `.git` に書き込むので使わない）:

```sh
P_OLD=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-3   # git -C $P_OLD describe --tags が v0.37.3
git clone <このリポジトリの checkout> /tmp/fraction-coredns-0373
git -C /tmp/fraction-coredns-0373 checkout e52d04b
cd /tmp/fraction-coredns-0373
grep -n -A1 'annotations:' assets/kubernetes/manifests/addons/coredns/coredns.yaml   # seccomp.security.alpha.kubernetes.io/pod: 'runtime/default'
```

### 7.2 戻す ✋

```sh
cd /tmp/fraction-coredns-0373
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml
```

- §2.3 の監視を流したまま行う
- client-side apply なので、テンプレートから `seccompProfile` が消えて注釈と `drop: [all]` が戻り、テンプレートが §2.2 の 3 と同じになる。Deployment は古い ReplicaSet `coredns-76d7d8dc86` を使い直す（dev では古い ReplicaSet が使われた）。CoreDNS の Pod 2 つが §4.1 と同じ形で入れ替わる
- 戻した Pod が oeilvert・pablo に載ると、v1.14.7 を pull する（前に pull していなければ。§2.2 の 12）
- §8.1 の `loop` の 1 回は戻すときも出うる
- 確かめること: §4.2 を読み替えて行う（Pod 2 つが v1.14.7 で Running・Ready、CRI の profile が `Unconfined`（`profile_type` 1）・`Seccomp: 0`、答えが §2.2 の 9 と同じ、Corefile が同じ、CoreDNS 以外の Pod が変わらない）
- 戻した後に `install kubernetes` を流し直したいときは、`/tmp/fraction-coredns-0373` と 0.37.3 を使う。**この PR をマージした master で 0.37.3 の `install kubernetes` を流さない**（assets が `RuntimeDefault` なので、また `RuntimeDefault` になる）

### 7.3 それでも戻らないとき

`install kubernetes` で CoreDNS の Pod が起きないなど、§7.2 で戻らないときは止めて報告する。rollout は `maxUnavailable: 1` なので、新しい Pod が起きない間も古い Pod の 1 つは答え続ける（§2.1 の 3）。立て直しの手（Deployment の `rollout undo`、手での `kubectl apply`、Pod の削除）は、その時点でユーザーと決める。etcd の restore は要らない見込み。

## 8. 既知の問題と注意

### 8.1 `loop` の FATAL（ノードの resolv.conf の kube-dns）

段 8 の手順書 §2.10・§8.16 と同じ件。CoreDNS は `dnsPolicy: Default` で、ノードの `/run/systemd/resolve/resolv.conf` を `forward . /etc/resolv.conf` の上流にする。そこに kube-dns（10.254.0.10）が入っている（§2.2 の 13）ので、起動のときの `loop` の確かめ（上流へ HINFO を投げて自分に返るか）が kube-dns に当たると、もう 1 つの CoreDNS を経て自分に返り、`[FATAL] plugin/loop: Loop (…) detected for zone "."` で exit 1 する。起き直したときの確かめで当たらなければ通る。

- この手順では **Pod が 2 つ作り直される**ので、起動の確かめが 2 回走る（段 8 の reload と同じ数）。段 8 の reload では chirico の `-shdgn` が 1 回 exit した（§2.2 の 8）。dev の 8 回の起動では出ていない
- **1 つの Pod で 1 回まで**は、前のコンテナのログに `plugin/loop` があり起き直して Ready なら想定どおりとして記録して進める（§2.1 の 9）。CrashLoopBackOff・2 回以上は止める（§6）
- seccomp の件とは関係しない（戻した `Unconfined` の Pod でも同じに出うる）。見分けるには、前のコンテナのログの最後の行が `plugin/loop` かを見る。seccomp で syscall が拒まれたときは、`operation not permitted` などのエラーで止まるはず（dev でも本番の autoscaler でも出ていない）
- 上流の DNS が答えない間は再起動が続きうる（2026-10-23 02:14〜02:26Z）。§2.6 の jumelle の時間帯を避ける
- oeilvert の resolv.conf は nameserver が 4 つで、kubelet は最初の 3 つ（192.168.0.1、10.254.0.10、192.168.0.1）だけを Pod に渡す。CoreDNS の Pod が oeilvert に載ると `DNSConfigForming`（`Nameserver limits were exceeded`）の warning の event が出る。前からの件で、想定どおりとして記録する（2026-10-26 の本番で出た。`loop` の FATAL は出なかった）
- resolv.conf の kube-dns を外す直しは、この手順書の範囲の外（§10）

### 8.2 Ready の遅れ

readinessProbe に `initialDelaySeconds` が無く、`periodSeconds: 10`。最初の probe がコンテナの起動直後に当たると `:8181` がまだ開いておらず `connection refused`（`Readiness probe failed` の event）になり、次は 10 秒後になる（dev の見つけたことの 1。seccomp とは関係しない）。その間 Ready な Pod は 1 つ（と lameduck の古い Pod）。`Readiness probe failed` の event が 1 回出て 10 秒後に Ready になるのは想定どおりとして記録する。2026-10-26 の本番では、2 つの Pod とも 1 回目の probe が `connection refused` になったが、1 秒ほどで Ready になった（10 秒は待たなかった）。

### 8.3 pull

v1.14.7 は chirico・duchamp にしか無い（§2.2 の 12）。scheduler はノードにイメージがあるかを少し重く見る（ImageLocality）が、新しい Pod が oeilvert・pablo に載ることはありうる。そのときは registry.k8s.io から 24.3 MB を pull する（autoscaler の v1.11.0 の 14.3 MB は 0.9 秒）。pull の間、rollout の最初に止めた古い Pod の分だけ Ready な Pod が 1 つの時間が延びる。事前 pull はしない（§2.1 の 6）。pull が失敗したら §6 の「2 分たっても Ready にならない」で止める。

### 8.4 2 つが同じノードに載る

`podAntiAffinity` は無い（porkadot#69 の本文が、上流の soft な `podAntiAffinity` を範囲の外として残した）。scheduler の既定の topology spread で分かれることが多い（dev では分かれた）が、同じノードに 2 つ載ると、そのノードが落ちたときに DNS が止まる。**同じノードに載っても止めない**。記録し、§10 の申し送りにする（Pod の手での削除は runbook から外れる操作）。

### 8.5 capabilities の `ALL`

`drop` が `all` から `ALL` に変わる。containerd の CRI は大文字小文字を区別しない（porkadot#69 の本文）ので、動きは同じ。§4.2 の 5 の capabilities が §2.2 の 6 と同じであることで確かめる。

### 8.6 CoreDNS v1.15（範囲の外）

計画 §8 の CoreDNS の目標は v1.15.x だが、v1.15.0 は registry.k8s.io にまだ無い（§1.5）。docker.io の上流のイメージは使わない。**registry.k8s.io に出るまで待つ**（2026-10-26 のユーザー判断）。それまで CoreDNS は v1.14.7 で、その理由を記録する（タスクの完了条件の「非クリティカルなコンポーネントが最新版」）。v1.15 は `cache`・`forward` の振る舞いが変わる（porkadot#61）ので、上げるときは別の porkadot の PR・dev の検証・手順書にする。

## 9. 記録

`results/coredns-seccomp/` に、ベースライン（`baseline.md`。§1 の前提、§2.2 の表、§2.4 のバックアップ、§3.1 の dry-run の warning）と、作業の記録（`summary.md`。§3.2 の出力の要点、§4.1 の入れ替わりの時刻（古い Pod の Terminating、新しい Pod の作成・Ready、古い Pod の消えた時刻）、§4.2 の各項目、§4.3 の結果、監視の FAIL、`loop` の有無、手順書との差）を残す。形は `results/dns-autoscaler-1.11/` に合わせる。
`snap.sh`・`node-state.sh`・`seccomp.sh`・`endpoints.sh`・`dns-check.sh` の出力と監視のログ（`dns.log`、`dns-replicas.log`）はタスクディレクトリの `notes/coredns-seccomp/` に置き、要点を記録に写す。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（記録の PR で）。

## 10. この後

- CoreDNS v1.15（§8.6。registry.k8s.io に出てから）
- ノードの resolv.conf の kube-dns を外す（§8.1、段 8 の手順書 §10。CoreDNS v1.15 のときに一緒に考える。計画 §8）
- `podAntiAffinity` を足すか（§8.4。上流の addon と kubeadm は soft な `podAntiAffinity` を持つ）
- 計画 §10 の片付けで、CoreDNS に関わるもの: `coredns` の古い ReplicaSet（replicas 0 の 9 つ。`76d7d8dc86` は戻しの材料なので、`RuntimeDefault` で落ち着いてから）、ノードの containerd に残る古い CoreDNS のイメージ（chirico・duchamp に v1.9.3〜v1.13.2、duchamp・pablo に `k8s.gcr.io` の v1.8.3 など。§2.2 の 12）
