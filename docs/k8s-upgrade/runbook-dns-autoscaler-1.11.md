# kube-dns-autoscaler を 1.7.1 から v1.11.0 へ上げる手順書（本番 `fraction`）

本番クラスタ `fraction` の kube-dns-autoscaler（cluster-proportional-autoscaler。CoreDNS の replicas を決める porkadot の addon）を、amd64 専用の `cluster-proportional-autoscaler-amd64:1.7.1` からマルチアーキの `cpa/cluster-proportional-autoscaler:v1.11.0` に替える手順。porkadot を 0.37.2 から 0.37.3 に替え、`install kubernetes` を 1 回流す。
計画 `plan.md`（以下「計画」）§8 の非クリティカルなコンポーネントの 2 つ目で、MetalLB の手順書 `runbook-metallb-0.16.md`（以下「MetalLB の手順書」。2026-10-25 02:11〜02:19Z に本番で通した）と同じ形にする。ノードの kubelet にも etcd にも触らず、変わるのは Deployment 1 つなので、MetalLB よりさらに小さい。

| | 更新前 | 更新後 |
|---|---|---|
| porkadot | 0.37.2（`020c7c7`、タグ `v0.37.2`） | **0.37.3**（`121a264`、タグ `v0.37.3`） |
| イメージ | `registry.k8s.io/cluster-proportional-autoscaler-amd64:1.7.1`（amd64 だけ） | **`registry.k8s.io/cpa/cluster-proportional-autoscaler:v1.11.0`**（amd64・arm・arm64・ppc64le・s390x の manifest list） |
| seccomp | 注釈 `seccomp.security.alpha.kubernetes.io/pod: docker/default`（K8s 1.27 から効かない。**今は seccomp なしで動いている**。§2.2 の 6） | **`securityContext.seccompProfile.type: RuntimeDefault`**（containerd の既定のプロファイルが実際に効く） |
| 引数・パラメータ・RBAC・tolerations・resources・priorityClass | — | **変わらない** |
| ConfigMap `kube-system/kube-dns-autoscaler` | `{"coresPerReplica":256,"nodesPerReplica":16,"preventSinglePointFailure":true}`（2018 年作成、porkadot の管理外） | **変わらない**（`install kubernetes` は触らない） |
| CoreDNS の replicas | 2 | **2 のまま**（§2.2 の 9 の計算） |
| K8s、etcd、kubelet、kube-proxy、cnidaria、CoreDNS、MetalLB、Longhorn | v1.37.1、3.7.3、… | 変えない（`install kubernetes` で apply し直されるが、マニフェストの差分が無い） |

porkadot 0.37.3 に入った PR は porkadot#67（マージ `06b4448`。`dns-horizontal-autoscaler.yaml.erb` のイメージと seccomp、renovate の規則、テスト）と porkadot#68（`121a264`。版を 0.37.3 にする）。0.37.2 から 0.37.3 の差分はこれだけで、**`install`・`etcd backup` の実装は 0.37.2 と同じ**。1.7.1 から v1.11.0 で変わること（数えるノードが Ready のものに限られる、数える CPU が allocatable になる、`:8080` の `/healthz`・`/last-poll`）とその本番への影響は porkadot#67 の本文にある。

この手順は dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で先に通してある（2026-10-25 02:59〜03:06Z）。記録は porkadot-dev の `docs/k8s-upgrade/verification-dns-autoscaler-1.11.md`（以下「dev の記録」。porkadot-dev#20、main `1076d99`）。dev は `06b4448` で通したもので、0.37.3 との違いは版の番号（#68）だけ。dev で分かったことは次のとおり。

- **`install kubernetes` は 1 回目で rc 0**（約 16 秒）。新しい Pod は taint の無い worker に載り、pull 2 秒（14 MB）で起動し、同時に古い Pod が止まった
- **入れ替わりの間、CoreDNS の replicas も Pod も変わらず、1 秒ごとの DNS の問い合わせは 1 度も落ちなかった**（360 サンプル）
- 新しいコンテナは containerd の既定の seccomp プロファイルの下で動く（`Seccomp: 2`）。古い 1.7.1 は `Seccomp: 0`
- どのログにも `Forbidden` は無く、ClusterRole は変わらない
- v0.37.2 の `install kubernetes` で 1.7.1 に戻せた（rc 0。古い ReplicaSet が使われ、`seccompProfile` は消えて注釈が戻る）
- **ConfigMap を書き換えてスケールを下げると、CoreDNS の Pod が入れ替わる**（見つけたことの 2。ReplicaSet は同じノードに 2 つある Pod を先に消す）。**本番ではスケールを試さない**（§4.3）
- CoreDNS も seccomp なしで動いている（見つけたことの 1）。**この手順書の範囲の外**（§8.3）

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **本番の 8 台・52 cores での計算**（dev は 7 台・14 cores）。どちらも 2 になる（§2.2 の 9）
- **arm64 のイメージ**（dev はすべて amd64）。本番でも taint のために worker（amd64）にしか載らないので、本番でも使われない（§2.1 の 4）
- **本番の CoreDNS の Pod の載り方**（chirico・duchamp。autoscaler の今の Pod も chirico）

## 0. 役割と約束ごと

MetalLB の手順書 §0 と同じ形で、次のとおりにする。

- **承認の節目は 1 つ**。この手順書では ✋✋ を付けた。
  - ✋✋ **開始**: render の差分（§2.5。この手順書と同じ PR）、§2.2 のベースライン、§2.3 の監視、§2.6 の時間帯、§6 の止める条件、§7 のロールバックの形を見せ、PR をマージしてから、`install kubernetes` を流す前（§3.1）
- **節目の後の手順は、ユーザーに知らせるだけで進めてよい（✋）。** etcd のバックアップ（§2.4）と `install kubernetes`（§3.2）は、この手順書に書いた形なら ✋ で、1 つずつ承認を取るものではない。✋ の前に、何をするかを知らせる。
- **runbook から外れる操作（ロールバック、`install kubernetes` の流し直しより先の対処、Pod の手での削除、Deployment の手での編集・scale、ConfigMap の書き換え、イメージの手での pull）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認は、知らせずに行ってよい。時刻はすべて UTC で記録する（control-plane のホストの時刻は JST）。

## 1. 前提

### 1.1 本番の今の姿

始める前に次を確かめる（読み取り）。2026-10-25 06:0xZ（この手順書を書いたとき）の値を書く。当日に読み直す。

- 8 台 Ready・schedulable、全台 v1.37.1。Pod は 166 個で、Running / Completed 以外は 0 個
- MetalLB の更新（`results/metallb-0.16/summary.md`）が済んでいる
- autoscaler は 1.7.1 の 1 つ（chirico の `kube-dns-autoscaler-cc5758b6f-dhc95`、restart 0、2026-10-19 09:35:32Z 起動）。ログは起動のときの 6 行だけで、エラーは無い（§2.2 の 4）

### 1.2 kubeconfig の運用

段 8 の手順書 §1.2 と同じ（確認は `fraction-auditor`）。**この手順書では `infra-admin` のトークンを使わない。** 本番に書き込むのは porkadot の `etcd backup`（ノードの上の etcdctl）と `install kubernetes`（ノードの上の admin の kubeconfig）だけで、どちらもトークンは要らない。§4.3 のとおり ConfigMap も書き換えない。

### 1.3 SSH

MetalLB の手順書 §1.3 と同じ（worker は `ssh yuanying@<IP>`、control-plane は `ssh ubuntu@<IP>`。**名前ではなく IP で入る**。control-plane には `unset LC_ALL` してから入る）。2026-10-25 06:0xZ にこの手順書を書いたとき、8 台ともサンドボックスの中から §1.6 の `node-state.sh` と、chirico に `seccomp.sh`、oeilvert に `dns-watch.sh` を流せた。サンドボックスの中で通らないときは、サンドボックスの外での実行を coordinator に頼む（読み取りのコマンドだけ）。

### 1.4 porkadot の置き場と流し方

MetalLB の手順書 §1.4 と同じ形で、タスクディレクトリの独立の clone を使う。

| 用途 | 置き場 | 版 |
|---|---|---|
| **当日** | `/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-3` | v0.37.3（`121a264`、detached） |
| **§7 の戻し** | `/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-2`（MetalLB の本番と dev の戻しで使ったもの。触らずに残す） | v0.37.2（`020c7c7`、detached） |

- 2026-10-25 06:0xZ に `git ls-remote https://github.com/yuanying/porkadot.git` で、GitHub の `refs/tags/v0.37.3`（tag object `91a366b`）と `^{}`（`121a264`）が 0.37.3 の clone と一致することを確かめた。`lib/porkadot/version.rb` は 0.37.3。この clone で §2.5 の render を流した
- 0.37.2 の clone は `git describe --tags` が `v0.37.2`（`020c7c7`、GitHub の tag object `61c3623`）。§7.1 の render をこの clone で流した

**このリポジトリのルートを cwd にして** 流す。

```sh
P=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-3
git -C $P describe --tags          # v0.37.3
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
curl -sL -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
  https://registry.k8s.io/v2/cpa/cluster-proportional-autoscaler/manifests/v1.11.0 \
  | jq -r '[.manifests[].platform.architecture] | join(",")'        # amd64 を含む
curl -sL -o /dev/null -w '%{http_code}\n' -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  https://registry.k8s.io/v2/cluster-proportional-autoscaler-amd64/manifests/1.7.1   # 200（§7 の戻しで要る）
```

2026-10-25 06:0xZ の時点: v1.11.0 は manifest list で amd64・arm・arm64・ppc64le・s390x を含む。1.7.1 は amd64 だけの manifest で、まだ取れる。v1.10.3 ではなく v1.11.0 にした理由（registry.k8s.io に出ている最新で、署名がある。GitHub の release は無い）は porkadot#67 の本文。

### 1.6 確認に使うスクリプト

タスクディレクトリの `notes/runbook-dns-autoscaler/scripts/` に置いた（dev の `notes/dev-dns-autoscaler/scripts/` を本番の値にしたもの）。どれも読み取りだけ。

| スクリプト | 中身 |
|---|---|
| `snap.sh <dir>` | `fraction-auditor` で、Node（Ready、unschedulable、allocatable の CPU、arch、taint）、全 Pod（UID・restartCount）、autoscaler と CoreDNS の Deployment・ReplicaSet・Pod（securityContext を含む yaml）、ConfigMap、autoscaler の ClusterRole・ClusterRoleBinding・ServiceAccount、autoscaler のログ、`coredns` の events。出力は `notes/runbook-dns-autoscaler/<dir>/` |
| `node-state.sh <dir>` | 8 台に IP で ssh し、kubelet の MainPID・NRestarts・ActiveEnterTimestamp、containerd の autoscaler のイメージ |
| `seccomp.sh <worker の IP>` | その worker の autoscaler のコンテナの `crictl inspect`（`status.seccomp`、OCI spec の `linux.seccomp` の有無）と `/proc/<pid>/status` の `Seccomp`（0 はなし、2 は filter） |
| `dns-watch.sh <logdir>` | oeilvert（192.168.1.82。CoreDNS も autoscaler も載っていない）から 1 秒ごとに、kube-dns の Service `10.254.0.10` に `dig +time=1 +tries=1` で `kubernetes.default.svc.cluster.local`、`kube-dns.kube-system.svc.cluster.local`、`www.google.com` の A を問い合わせる。答えが無ければ `FAIL`。`<logdir>/dns.log` に 1 秒 1 行 |
| `dns-replicas-watch.sh <logdir>` | 2 秒ごとの `coredns` の replicas（spec / ready / status）と、CoreDNS と autoscaler の Pod（名前、phase、Ready、restart、ノード、イメージ）を `<logdir>/dns-replicas.log` に |

`dns-watch.sh` と `dns-replicas-watch.sh` は `<logdir>/watch.stop` を作ると止まる（`dns-watch.sh` は 60 秒ごとに ssh を張り直すので、止まるまで最長 1 分）。当日の `<logdir>` はタスクディレクトリの `notes/dns-autoscaler-1-11/logs`。

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 流し方 | porkadot 0.37.3 の `install kubernetes --node 192.168.1.111` を 1 回。CRD の server-side apply、apiserver の apply と rollout の待ち（apiserver は変わらないので Pod は入れ替わらない）、全体の `apply -k --prune` | dev の記録、`assets/kubernetes/install.sh` |
| 2 | drain・cordon | しない（ノードには触らない） | — |
| 3 | 入れ替わり | Deployment `kube-dns-autoscaler` は RollingUpdate（maxSurge 25%・maxUnavailable 25%、replica 1。切り上げ・切り捨てで surge 1・unavailable 0）。新しい Pod が Running になってから古い Pod が消える（readiness probe は無い）。autoscaler が居ない間は scale を書かないだけで、CoreDNS の replicas も Pod も変わらない | live の `strategy`、dev の記録の「本番の runbook に効くこと」 |
| 4 | 配置 | 新しい Pod は taint の無い worker（chirico、duchamp、oeilvert、pablo。どれも amd64）のどれか。tolerations は `CriticalAddonsOnly` だけで、control-plane（`node-role.kubernetes.io/master:NoSchedule`）と braque（`unstable.cloud/storage:NoSchedule`）には載らない。マルチアーキになっても今の taint では arm64 の Pi には載らない | live の tolerations と taint（§2.2 の 1・3） |
| 5 | 途切れ | 見込まない（dev で 0）。許容する範囲: DNS の監視の 1〜2 サンプルの FAIL（記録する）。止める条件は §6 | 2026-10-19 のユーザーの方針（短時間の障害は許容） |
| 6 | イメージの事前 pull | **しない**。#3 のとおり古い Pod は新しい Pod が起動するまで動き続けるので、pull の時間は途切れにならない（dev では 14 MB で 2 秒）。registry.k8s.io から取れないときは新しい Pod が `ImagePullBackOff` のまま古い Pod が残り、§6 で止める | dev の記録 |
| 7 | etcd のバックアップ | `install kubernetes` の前に 1 回（§2.4） | 計画 §6.1 の 5 と同じ扱い |
| 8 | スケールの確かめ | **本番では ConfigMap を書き換えない。** v1.11.0 が今の ConfigMap を読み、`coredns` の scale を書かない（2 のまま）ことを、ログと replicas で見る（§4.3） | dev の記録の見つけたことの 2 |
| 9 | 時間帯 | jumelle の 18:00〜19:30Z、worker の unattended-upgrades 06:00〜07:00Z、control-plane の 21:00〜22:00Z を避ける（§2.6） | MetalLB の手順書 §2.7 |
| 10 | 範囲の外 | CoreDNS の seccomp（§8.3）、古い ReplicaSet と古いイメージの片付け（§10） | dev の記録、backlog |

### 2.2 ベースライン

作業の当日、`install kubernetes` の前に次を取り、`results/dns-autoscaler-1.11/baseline.md` に残す（すべて読み取り）。出力はタスクディレクトリの `notes/dns-autoscaler-1-11/base/` に置く。

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-dns-autoscaler/scripts
bash $S/snap.sh ../dns-autoscaler-1-11/base
bash $S/node-state.sh ../dns-autoscaler-1-11/base
bash $S/seccomp.sh <autoscaler の Pod のノードの IP> > /home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/dns-autoscaler-1-11/base/seccomp.txt
```

| # | 項目 | 2026-10-25 06:0xZ の値（当日に読み直す） |
|---|---|---|
| 1 | Node と taint | 8 台 Ready、v1.37.1、cordon されたものは無い。taint は control-plane 3 台が `node-role.kubernetes.io/master:NoSchedule`、braque が `unstable.cloud/storage:NoSchedule`、chirico・duchamp・oeilvert・pablo は無い |
| 2 | 全 Pod の名前・UID・restartCount | 166 個。Running / Completed 以外は 0 個（§4.2 で「autoscaler 以外は変わらない」を見る元） |
| 3 | autoscaler の Deployment | generation 4、revision 2、1/1。イメージ `registry.k8s.io/cluster-proportional-autoscaler-amd64:1.7.1`。テンプレートの注釈 `seccomp.security.alpha.kubernetes.io/pod: docker/default`、Pod の securityContext は `fsGroup: 65534`・`supplementalGroups: [65534]` だけ（`seccompProfile` は無い）。tolerations は `CriticalAddonsOnly`、nodeSelector は `kubernetes.io/os: linux`、affinity は無い。strategy は RollingUpdate（25%・25%）、revisionHistoryLimit 10 |
| 4 | autoscaler の Pod | chirico の `kube-dns-autoscaler-cc5758b6f-dhc95`（UID `7dea208a-…`、restart 0、2026-10-19 09:35:32Z 起動）。ログは起動の 6 行だけ（`Params from apiserver: {"coresPerReplica":256,"nodesPerReplica":16,"preventSinglePointFailure":true}`、`Defaulting min replicas count to 1`）。エラー・`Forbidden` は無い |
| 5 | autoscaler の ReplicaSet | `kube-dns-autoscaler-cc5758b6f`（1/1、`registry.k8s.io/…-amd64:1.7.1`。§7 の戻しで使われる見込み）と `kube-dns-autoscaler-64bc6d94b9`（0、`k8s.gcr.io/…-amd64:1.7.1`。2020 年の残り） |
| 6 | 今の Pod の seccomp（`seccomp.sh 192.168.1.83`） | `status.seccomp` は無い、OCI spec に `linux.seccomp` が無い、`Seccomp: 0`・`Seccomp_filters: 0`・`NoNewPrivs: 0`。**今は seccomp なしで動いている** |
| 7 | ConfigMap `kube-system/kube-dns-autoscaler` | `data.linear` が `{"coresPerReplica":256,"nodesPerReplica":16,"preventSinglePointFailure":true}`。2018-10-23 作成、resourceVersion `901196490`、注釈も managedFields も無い（porkadot の管理外） |
| 8 | CoreDNS | Deployment `coredns` の generation 13、replicas 2、2/2。Pod は `coredns-76d7d8dc86-469lz`（duchamp、restart 7）と `coredns-76d7d8dc86-shdgn`（chirico、restart 5）、どちらも 2026-10-21 13:04:32Z 起動（restart は段 7・8 のもの）。`coredns` の events は無い |
| 9 | 計算される replicas | Ready・schedulable のノード 8 台、allocatable の CPU は .111〜.113 と braque・pablo が 4、chirico 16、duchamp・oeilvert 8 で **合計 52**（capacity と同じ）。nodes ⌈8/16⌉ = 1 → `preventSinglePointFailure` で 2、cores ⌈52/256⌉ = 1。**大きいほうの 2** で、今の replicas と同じ。v1.11.0 は taint のあるノードも数える（dev の記録）。2 でなくなるのは Ready のノードが 1 台以下（1 になる）か、33 台以上・513 cores 以上のとき |
| 10 | RBAC | ClusterRole `system:kube-dns-autoscaler` は `nodes` の list・watch、`replicationcontrollers/scale` の get・update、`apps` の `deployments/scale`・`replicasets/scale` の get・update、`configmaps` の get・create。porkadot#67 で変わらない |
| 11 | kubelet（`node-state.sh`） | .111 MainPID 752609・NRestarts 0、.112 1028・1、.113 612672・0、braque 541944・0、chirico 3237977・0、duchamp 202232・0、oeilvert 916805・51、pablo 3509679・0（MetalLB のベースラインと同じ） |
| 12 | containerd の autoscaler のイメージ | `registry.k8s.io/cluster-proportional-autoscaler-amd64:1.7.1` が chirico・duchamp・pablo にある（duchamp には `k8s.gcr.io/…` の同じイメージも）。**oeilvert・braque・control-plane には無い**。v1.11.0 はどの台にも無い |
| 13 | `:8080` | 1.7.1 は聞いていない（oeilvert から Pod IP の `:8080/healthz` が `Connection refused`。v1.11.0 から足される） |
| 14 | DNS | oeilvert から `10.254.0.10` に 3 つの名前が引ける（§2.3 の `dns-watch.sh` を 1 分流し、60 サンプルで FAIL 0） |
| 15 | kube-system の NetworkPolicy | 無い（`:8080` の確かめと DNS の監視に効くものは無い） |
| 16 | VIP | `https://192.168.1.101:6443/readyz` が 200 |

### 2.3 監視

`install kubernetes` の前から、§4 の確認が終わるまで流す（読み取り）。MetalLB の手順書 §2.3 と同じく、**`nohup` や `&` で起動しない。** worker のハーネスのバックグラウンド実行で、**監視ごとに 1 つのジョブとして**起動する（`dns-watch.sh` で 1 つ、`dns-replicas-watch.sh` で 1 つ。合わせて 2 つ）。

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-dns-autoscaler/scripts
L=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/dns-autoscaler-1-11/logs
bash $S/dns-watch.sh $L             # ジョブ 1
bash $S/dns-replicas-watch.sh $L    # ジョブ 2
```

- 起動したら、ジョブの一覧に 2 つが居ることと、`dns.log`・`dns-replicas.log` に行が足されていくことを確かめる。**`install kubernetes` の前に、2 つのログの最後の行の時刻が 1 分以内であること**（`dns.log` は ssh の 1 回分の 60 行ずつまとめて書かれることがあるので、最初の 1 分は待つ）
- 止めるときは `touch $L/watch.stop`（2 つとも止まる）
- `dns.log` の FAIL は `in=`・`dns=`・`ext=` のどれかが `FAIL`。`ssh rc=` の行は監視の側の切れ目（記録して、続くなら見直す）
- `dns-replicas.log` で見るもの: `coredns(spec/ready/status)=2/2/2` のまま、CoreDNS の 2 つの Pod の名前と restart が変わらない
- 段 8 の手順書 §2.3 の etcd の health の監視、MetalLB の手順書の `probe.sh` は流さない（etcd にも LoadBalancer にも触らない）

### 2.4 etcd のバックアップ ✋

`install kubernetes` の前に、porkadot 0.37.3 で取る（MetalLB の手順書 §2.4 と同じ形。0.37.3 の `etcd backup` は 0.37.2 と同じ実装で、ノードの 3.7.3 の etcdctl を使う）。

```sh
porkadot etcd backup
ls -l ./backup/
```

- 手元のファイルは `./backup/etcd-<日時>.db`、モード 0600。`./backup/` は `.gitignore` で除外してある。スナップショットには Secret が平文で入っているので、`git add -f` などで追加しない。worktree で流したときは、worktree を片付ける前にメインの checkout の `backup/` へ写す
- 時刻、ファイル名、サイズ、sha256 を記録する（MetalLB の前のものは 55,107,616 B）。桁が違えば止める
- autoscaler の更新は etcd の restore を要しない見込み（§7 のロールバックは `install kubernetes` で戻す）。このバックアップは想定外のときの最後の手段

### 2.5 render の差分（この手順書と同じ PR）

2026-10-25 06:01Z に、porkadot 0.37.3（`121a264`。§1.4 の clone）で、このリポジトリのルートを cwd にして `render kubernetes` を流した（rc 0）。`porkadot.yaml` は変えていない。前の render は master の `0a32713`（MetalLB の porkadot 0.37.2 の render）。

**差分は `assets/kubernetes/manifests/addons/coredns/dns-horizontal-autoscaler.yaml` の 1 ファイルだけ**（新しくできたファイル、消えたファイル、証明書・sops の Secret の作り直しも無い）。

```diff
     metadata:
       labels:
         k8s-app: kube-dns-autoscaler
-      annotations:
-        seccomp.security.alpha.kubernetes.io/pod: 'docker/default'
     spec:
       priorityClassName: system-cluster-critical
       securityContext:
+        seccompProfile:
+          type: RuntimeDefault
         supplementalGroups: [ 65534 ]
         fsGroup: 65534
       containers:
       - name: autoscaler
-        image: registry.k8s.io/cluster-proportional-autoscaler-amd64:1.7.1
+        image: registry.k8s.io/cpa/cluster-proportional-autoscaler:v1.11.0
```

- **この差分は dev の差分と同じ**（dev の記録の「render の差分」、porkadot#67 の本文。#67 の本文は、本番の設定と assets でも同じ 1 ファイルだけと書いている）
- **変わらないもの**: 同じファイルの ServiceAccount・ClusterRole・ClusterRoleBinding と Deployment の引数・resources・tolerations、`coredns.yaml`（CoreDNS の Deployment と Corefile）、addon の `kustomization.yaml`
- `render kubelet`・`render etcd`・`render bootstrap` は、このリポジトリの `/tmp` の clone で 4 つとも流し（rc 0）、差分が証明書の 12 ファイル（各ノードと bootstrap の `bootstrap.crt`、control-plane の `etcd.crt`）と上の 1 ファイルだけであることを確かめた。この 3 つは `install kubernetes` で使わないので、PR には入れていない（MetalLB の手順書 §2.6 と同じ）
- `render kubernetes` は証明書を作り直さない。当日は render しない（この PR の `assets/` で流す）
- secrets（`assets/` の sops の証明書と鍵）は、この PR では変わらない

### 2.6 時間帯

MetalLB の手順書 §2.7 と同じ時間帯を避ける。

| 時間帯（UTC） | 何が起きるか | 避ける理由 |
|---|---|---|
| **18:00〜19:30** | jumelle の unattended-upgrades と自動再起動 | jumelle が落ちると registry.k8s.io からの pull が止まり（新しい Pod が起動しない。古い Pod は残る）、DNS の監視の外の名前（`www.google.com`）が FAIL になって、入れ替わりの影響と見分けられない |
| 06:00〜07:00 | worker 5 台の unattended-upgrades | needrestart がサービスを再起動すると、§4.2 の「kubelet が再起動しない」「ほかの Pod が変わらない」の確かめと取り違える。CoreDNS と autoscaler は worker に載っている |
| 21:00〜22:00 | control-plane 3 台の unattended-upgrades | 同上（apiserver） |

- 作業は、監視の起動から §4 の確認まで 20 分ほどを見込む。その間が上の時間帯に重ならないこと

### 2.7 dev の記録と違う本番の形

| 点 | dev | 本番 | この手順書での扱い |
|---|---|---|---|
| ノードと CPU | 7 台、allocatable 2 ずつで 14 | 8 台、52 | どちらも計算は 2（§2.2 の 9） |
| kube-dns の Service | `10.252.0.10` | `10.254.0.10` | `dns-watch.sh` は本番の値 |
| DNS の監視のノード | .123（ubuntu） | oeilvert（`yuanying@192.168.1.82`）。CoreDNS は chirico・duchamp | 新しい autoscaler が oeilvert に載ることはあるが、監視（dig）には関わらない |
| 1.7.1 のイメージ | 全台にあったかは見ていない | chirico・duchamp・pablo だけ | §7 の戻しで oeilvert に載ると pull する（1.7.1 は registry.k8s.io にまだある。§1.5） |
| `:8080` の確かめ | Pod IP の `/healthz`・`/last-poll` が 200 | 同じ形で oeilvert から見る | §4.2 の 6 |

## 3. `install kubernetes`

### 3.1 事前確認

✋✋ **開始の承認を取る。** §2.5 の差分と PR、§2.2 のベースライン（特に 3〜9 の autoscaler・seccomp・ConfigMap・CoreDNS・計算）、§2.3 の監視、§2.6 の時間帯、§6 の止める条件、§7 のロールバックの形を示す。承認を得て PR をマージし、マージした master で §3.2 に入る。

- §2.2 のベースラインと §2.4 のバックアップが済んでいる。§2.3 の 2 つの監視がジョブとして動き、ログの最後の行が 1 分以内
- 全台 Ready、`coredns` が 2/2、autoscaler が 1/1
- checkout が §2.5 の PR をマージした master で、`git status --short assets porkadot.yaml` が空。`git -C $P describe --tags` が `v0.37.3`
- 作業の時間が §2.6 の時間帯と重ならない

### 3.2 流す ✋

```sh
porkadot install kubernetes --node 192.168.1.111
```

- 時刻と rc を記録する。dev では約 16 秒で rc 0、MetalLB の本番では 25 秒
- 出力で見るもの:
  - `deployment.apps/kube-dns-autoscaler configured`
  - 前からの `configured`: PDB `kube-controller-manager`・`kube-scheduler`、DaemonSet `kube-apiserver`（apiserver の apply と全体の apply で 2 回）、ValidatingWebhookConfiguration `metallb-webhook-configuration`。dev の出力と MetalLB の本番の出力にもあり、Pod は入れ替わらない（MetalLB の記録 `summary.md` §2。generation が変わらなければ想定内）
  - **ほかは `unchanged`**（`coredns`・ConfigMap `coredns`・ClusterRole `system:kube-dns-autoscaler` を含む）。ServiceAccount・ClusterRole・ClusterRoleBinding `kube-dns-autoscaler` が `configured` なら中身を読み、§2.2 の 10 と違えば止める
  - **`pruned` の行が無い**（オブジェクトの組は変わらない）
- rc 1 のときの扱い（`connection refused` など）は段 8 の手順書 §8.3 と同じ。全体の apply の前に落ちたなら autoscaler は 1.7.1 のまま。原因を見て流し直す（流し直しは ✋ の範囲）。2 回目も落ちたら止めて報告する
- 流した直後に、§2.3 の 2 つの監視のログが続いていることを確かめる

## 4. 後の確認

### 4.1 入れ替わりを見る

```sh
kubectl --context fraction -n kube-system rollout status deployment/kube-dns-autoscaler --timeout=3m
```

- `dns-replicas.log` で、新しい Pod が taint の無い worker に作られ、Running になり、古い Pod `kube-dns-autoscaler-cc5758b6f-dhc95` が消えるのを見る（dev では作られてから 4 秒で入れ替わり）。**新しい Pod が 2 分たっても Running にならないときは止める**（古い Pod は残っている。§6）
- 同じ間、`coredns(spec/ready/status)=2/2/2` と CoreDNS の 2 つの Pod が変わらないこと
- `dns.log` に FAIL が出たら、時刻を控える

### 4.2 確認

rollout が終わったら、`snap.sh` と `node-state.sh` を `../dns-autoscaler-1-11/after` に、`seccomp.sh <新しい Pod のノードの IP>` を `after/seccomp.txt` に取り、§2.2 と比べる。

| # | 確認 | 合格基準 |
|---|---|---|
| 1 | Deployment | generation が 1 つ増える（2026-10-25 は 4 → 5）、revision 3。1/1、updated 1。テンプレートのイメージが `registry.k8s.io/cpa/cluster-proportional-autoscaler:v1.11.0`、`securityContext.seccompProfile.type` が `RuntimeDefault`、注釈 `seccomp.security.alpha.kubernetes.io/pod` が無い。引数・tolerations・resources が §2.2 の 3 と同じ |
| 2 | Pod | **1 つだけ、v1.11.0 で Running、Ready、restart 0**。古い Pod が無い。イメージの digest（`imageID`）を記録する |
| 3 | 配置 | chirico・duchamp・oeilvert・pablo のどれか（control-plane と braque には無い） |
| 4 | ReplicaSet | 新しい ReplicaSet が 1/1。`cc5758b6f` と `64bc6d94b9` は 0 で残る（§7 で使う） |
| 5 | seccomp（`seccomp.sh`。ノードへの SSH はサンドボックスの中で） | `status.seccomp` が RuntimeDefault（dev では `profile_type` 0）、OCI spec に `linux.seccomp`（`defaultAction: SCMP_ACT_ERRNO`）がある、**`/proc/<pid>/status` が `Seccomp: 2`**、`Seccomp_filters: 1`（dev と同じ） |
| 6 | `:8080` | oeilvert から Pod IP の `:8080/healthz` と `:8080/last-poll` が 200（`ssh -n yuanying@192.168.1.82 'curl -s -o /dev/null -w "%{http_code}\n" --max-time 3 http://<Pod IP>:8080/healthz'`） |
| 7 | ログ | `Scaling Namespace: kube-system, Target: deployment/coredns`、`Set control mode to linear`、`Params from apiserver:` に §2.2 の 7 の値、`Defaulting min replicas count to 1` が出る。**`E` で始まる行、`W` で始まる行、`Forbidden`、`Replicas are not as expected` が無い**（§4.3） |
| 8 | CoreDNS | `coredns` の generation が 13 のまま、replicas 2、2/2。**Pod 2 つの名前・UID・restartCount が §2.2 の 8 と同じ**。`coredns` の events に `ScalingReplicaSet` が無い |
| 9 | ConfigMap | `kube-dns-autoscaler` の `data`・resourceVersion（`901196490`）が §2.2 の 7 と同じ |
| 10 | RBAC | ClusterRole・ClusterRoleBinding・ServiceAccount が §2.2 の 10 と同じ（resourceVersion が変わらない） |
| 11 | ほかの Pod | 全 Pod の比較で、**変わったのは autoscaler の Pod だけ**（名前・UID・restartCount）。kube-proxy・cnidaria・CoreDNS・apiserver・KCM・scheduler・MetalLB の Pod の UID と restartCount が §2.2 の 2 と同じ。Running / Completed 以外が 0 |
| 12 | kubelet | 8 台の MainPID・NRestarts・ActiveEnterTimestamp が §2.2 の 11 と同じ |
| 13 | 監視の FAIL | `dns.log` の `install kubernetes` から §4.3 の終わりまでの FAIL の数（名前ごと）。dev では 0 |
| 14 | 健全性 | 8 台 Ready、VIP の `https://192.168.1.101:6443/readyz` が 200 |

- 段 8 の手順書 §1.8 の `netcheck.sh`、§1.9 の `npcheck.sh` は流さない（ネットワークにも NetworkPolicy にも触らない。MetalLB の本番の後の結果のまま）

### 4.3 計算の確かめ（ConfigMap は書き換えない）

dev では ConfigMap の `nodesPerReplica` を 2 にして上げ下げを確かめたが、**本番ではしない。** 下げるとき ReplicaSet が同じノードに 2 つある Pod を先に消すので、元の CoreDNS の Pod が入れ替わりうる（dev の記録の見つけたことの 2）。代わりに、次で v1.11.0 が本番の値で 2 を計算していることを確かめる。

- §4.2 の 7 のログの `Params from apiserver` が本番の ConfigMap の値（v1.11.0 が ConfigMap を読み、`linear` で動いている）
- v1.11.0 は poll（既定 10 秒）ごとに数え直し、**計算が今の replicas と違うときだけ** `Cluster status: SchedulableNodes[…], TotalNodes[…], SchedulableCores[…], TotalCores[…]` と `Replicas are not as expected : updating deployment/coredns from … to …` を出す（dev の記録の「入れ替わりとスケール」）。`--v=2` では一致しているときの計算の結果はログに出ない
- そこで、新しい Pod の起動から **2 分（poll 12 回）以上** たってから、ログに `Cluster status`・`Replicas are not as expected` が無く、`coredns` が 2/2/2 のままであることを見る。これが §2.2 の 9 の計算（8 台・52 cores で 2）と一致していることの確かめになる
- `Replicas are not as expected` が出て replicas が 2 以外になったら止める（§6）。そのログの `SchedulableNodes`・`SchedulableCores` を記録する

### 4.4 監視を止める

§4.2・§4.3 が終わったら、§2.3 の監視を止める（`touch $L/watch.stop`）。2 つのジョブが終わったことを確かめる。

## 5. （なし）

MetalLB の手順書 §5 のような片付けは、この手順書には無い。古い ReplicaSet とイメージは §7 の戻しの材料なので残す（§10）。

## 6. 止める条件

次のどれかに当たったら、その場で止めて報告する。続けるか §7 で戻すかはユーザーが決める。

- **新しい Pod が 2 分たっても Running にならない**（`ImagePullBackOff`、`CreateContainerError` など。seccomp のためにコンテナが起きないときもここに入る）
- 新しい Pod が CrashLoopBackOff になる、restartCount が増える
- **`coredns` の replicas が 2 でなくなる**、または CoreDNS の Pod が入れ替わる・再起動する
- ログに `Forbidden`、`E` で始まる行が続く（起動の直後の 1 回だけなら記録して見る）
- **DNS の監視の FAIL が 5 サンプル（約 5 秒）を超えて続く**、または合わせて 10 サンプルを超える（`ext=` だけの FAIL は jumelle と上流の問題のこともあるので、`in=`・`dns=` と分けて記録する）
- ConfigMap `kube-dns-autoscaler` が変わる
- autoscaler 以外の Pod の再起動（kubelet・kube-proxy・cnidaria・CoreDNS・apiserver など）、Node の NotReady
- `install kubernetes` が 2 回続けて rc 0 にならない
- `install kubernetes` の出力に `pruned` の行がある

1〜2 サンプルの FAIL は、記録して進める。

## 7. ロールバック

**戻すのは runbook から外れる操作なので、ユーザーの承認を取る。** porkadot 0.37.2 の `install kubernetes` で 1.7.1 に戻す（dev で確かめた。rc 0、途切れなし）。

### 7.1 戻すための材料

- **前の版の assets**: この PR の前の master（**`0a32713`**）の `assets/` と `porkadot.yaml`。**porkadot 0.37.2 で `render kubernetes` しても、この `assets/` とバイトまで同じ**（2026-10-25 06:0xZ に `/tmp` の clone で確かめた。`git status` が空）なので、当日に render しないで使う
- **porkadot 0.37.2**: §1.4 の `worktrees/porkadot-v0-37-2`

用意の仕方（作業端末で。MetalLB の手順書 §7.1 と同じ形。`git worktree add` は元の clone の `.git` に書き込むので使わない）:

```sh
P_OLD=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-2   # git -C $P_OLD describe --tags が v0.37.2
git clone <このリポジトリの checkout> /tmp/fraction-dns-autoscaler-1.7
git -C /tmp/fraction-dns-autoscaler-1.7 checkout 0a32713
cd /tmp/fraction-dns-autoscaler-1.7
grep 'image:' assets/kubernetes/manifests/addons/coredns/dns-horizontal-autoscaler.yaml    # cluster-proportional-autoscaler-amd64:1.7.1
```

### 7.2 戻す ✋

```sh
cd /tmp/fraction-dns-autoscaler-1.7
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml
```

- §2.3 の監視を流したまま行う
- client-side apply なので、テンプレートから `seccompProfile` が消えて注釈が戻り、テンプレートが §2.2 の 3 と同じになる。Deployment は古い ReplicaSet `kube-dns-autoscaler-cc5758b6f` を使い直す（dev では古い ReplicaSet が使われた）
- 1.7.1 の Pod が chirico・duchamp・pablo 以外（oeilvert）に載ると、1.7.1 を pull する（§2.2 の 12、§1.5）
- CoreDNS には何も起きない（dev の記録）
- 確かめること: §4.2 を版を読み替えて行う（1.7.1 で Running・restart 0、`Seccomp: 0`、`coredns` が 2/2 で Pod が変わらない、ConfigMap が同じ、autoscaler 以外の Pod が変わらない。`:8080` は聞かない）
- 戻した後に `install kubernetes` を流し直したいときは、`/tmp/fraction-dns-autoscaler-1.7` と 0.37.2 を使う。**この PR をマージした master で 0.37.2 の `install kubernetes` を流さない**（assets が v1.11.0 なので、また v1.11.0 になる）

### 7.3 それでも戻らないとき

`install kubernetes` で autoscaler の Pod が起きないなど、§7.2 で戻らないときは止めて報告する。**autoscaler が居なくても CoreDNS は今の replicas（2）で動き続ける**ので、急がない。立て直しの手（手での `kubectl apply`、Pod の削除、Deployment の `rollout undo`）は、その時点でユーザーと決める。etcd の restore は要らない見込み。

## 8. 既知の問題と注意

### 8.1 計算の結果がログに出ない

v1.11.0 の `--v=2` では、計算が今の replicas と同じときは結果をログに出さない（§4.3）。本番で計算そのものを見る手は、ConfigMap を書き換える（しない）か `--v` を上げる（porkadot のテンプレートの変更になる）ことしか無い。§4.3 の「2 分以上 `updating` が出ない」で足りるとする。

### 8.2 数えるノードの変化

v1.11.0 は Ready のノードだけを数える（v1.10.1。1.7.1 は cordon されていないノードをすべて数えた）。ノードが 1 台 NotReady になっても 7 台で ⌈7/16⌉ = 1 → 2 なので、この先の運用で replicas が変わるのは Ready のノードが 1 台以下のときだけ（porkadot#67 の本文）。

### 8.3 CoreDNS も seccomp なしで動いている（範囲の外）

porkadot の `coredns.yaml.erb` も alpha の注釈（`seccomp.security.alpha.kubernetes.io/pod: 'runtime/default'`）だけで、`seccompProfile` が無い（§2.2 の 8 の live のテンプレートも同じ）。autoscaler が `coredns` の scale を書くたびに、apiserver が `non-functional in v1.27+` の warning を返し、v1.11.0 のログに出る（dev の記録の見つけたことの 1）。本番では scale が 2 のままなら出ない。**この手順書では直さない**。CoreDNS v1.15 に上げるときなどに、porkadot の PR で `RuntimeDefault` にする候補（`notes/backlog.md`）。

### 8.4 1.7.1 の Pod の古い `Forbidden`

dev の 1.7.1 の Pod には、段 8 の apiserver の入れ替えの間の `Forbidden` が 1 回ずつ残っていた（dev の記録の見つけたことの 3）。本番の 1.7.1 の Pod（2026-10-19 起動）のログには無い（§2.2 の 4）。

## 9. 記録

`results/dns-autoscaler-1.11/` に、ベースライン（`baseline.md`。§1 の前提、§2.2 の表、§2.4 のバックアップ）と、作業の記録（`summary.md`。§3.2 の出力の要点、§4.1 の入れ替わりの時刻（新しい Pod の作成・Running、古い Pod の消えた時刻）、§4.2 の各項目、§4.3 の結果、監視の FAIL、手順書との差）を残す。形は `results/metallb-0.16/` に合わせる。
`snap.sh`・`node-state.sh`・`seccomp.sh` の出力と監視のログ（`dns.log`、`dns-replicas.log`）はタスクディレクトリの `notes/dns-autoscaler-1-11/` に置き、要点を記録に写す。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（記録の PR で）。

## 10. この後

- 計画 §8 の残りの非クリティカルなコンポーネント（kube-prometheus-stack、metrics-server、CoreDNS v1.15）
- CoreDNS の seccomp（§8.3）
- 計画 §10 の片付けで、autoscaler に関わるもの: 古い ReplicaSet（`kube-dns-autoscaler-64bc6d94b9`。`k8s.gcr.io` の 2020 年のもの。`cc5758b6f` は戻しの材料なので、v1.11.0 で落ち着いてから）、ノードの containerd に残る 1.7.1 のイメージ（chirico・duchamp・pablo）。`coredns` の古い ReplicaSet（replicas 0 が 9 つ。revisionHistoryLimit の既定 10 で残る）も同じ扱い
- autoscaler の Pod は小さい（20m CPU、10Mi）ので affinity は足していない。taint が変われば arm64 の Pi にも載りうる（マルチアーキなので動く。porkadot#67 の本文）
