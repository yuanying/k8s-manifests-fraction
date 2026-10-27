# cnidaria を v0.1.2 にする手順書（本番 `fraction`）

本番クラスタ `fraction` の cnidaria（自作の CNI。NetworkPolicy も nftables で担う）を v0.1.1 から v0.1.2 にする手順。`porkadot.yaml` の `addons.cnidaria.image_tag: v0.1.1` の pin を外し、porkadot 0.37.5（既定の cnidaria が v0.1.2）で render した assets で `install kubernetes` を 1 回流す。**変わるのは DaemonSet `kube-system/cnidaria` のイメージの 1 行だけ。** 8 台の cnidaria の Pod が 1 台ずつ入れ替わる。

| | 更新前 | 更新後 |
|---|---|---|
| `porkadot.yaml` | `addons.cnidaria.image_tag: v0.1.1`（`1269cba` で入れた pin） | **pin なし**（porkadot の `default.yaml` に従う。`network_name: cbr0` は残す） |
| porkadot | 0.37.4（`d0d84c9`、タグ `v0.37.4`） | **0.37.5**（`aacfba7`、タグ `v0.37.5`） |
| cnidaria のイメージ | `ghcr.io/yuanying/cnidaria-cni:v0.1.1` | **`ghcr.io/yuanying/cnidaria-cni:v0.1.2`**（index `sha256:68756535…`、amd64・arm64） |
| DaemonSet のほかの項目（引数、probe、resources、securityContext、volumes、tolerations、updateStrategy） | — | **変わらない** |
| ノードの `/opt/cni/bin`（CNI plugins v1.9.1）と conflist | porkadot の `install kubelet` が置いたもの | **変わらない**（v0.1.2 は `/opt/cni/bin` を mount しない） |
| K8s、etcd、kubelet、kube-proxy、CoreDNS、MetalLB、Longhorn | v1.37.1、3.7.3、… | 変えない（`install kubernetes` で apply し直されるが、マニフェストの差分が無い） |

- cnidaria-cni v0.1.2（`b5ed1bc`）と v0.1.1 の差は cnidaria-cni#19 だけ: イメージから標準の CNI plugins（bridge・host-local・portmap）を外し、`deploy/daemonset.yaml` から plugins をコピーする init container を外した。Go のコードは同じ
- 本番の DaemonSet からは、その init container と `/opt/cni/bin` の hostPath を 2026-10-20 に外してある（porkadot 0.33.1、`cnidaria-no-plugin-copy.md`）。標準の plugins は porkadot の `install kubelet` だけが置く。v0.1.2 のイメージは plugins を持たないので init container のあるマニフェストとは組み合わせられないが、本番はもうその形ではない
- porkadot 0.37.4 から 0.37.5 の差は porkadot#71・#42・#72・#73・#54 と版の番号（#74）。**本番の assets に効くのは #54（`default.yaml` の cnidaria を v0.1.2）だけ**（§2.6）。#42 の flannel の版は、本番が flannel を有効にしていないので render に出ない。#71 は CoreDNS のテンプレートの Renovate のコメント（ERB のコメントで、render に出ない）。`install`・`etcd backup` の実装は 0.37.4 と同じ
- **pin を外す理由**（2026-10-27 のユーザー判断）: porkadot の既定の版に従う。cnidaria は porkadot#73 で Renovate の自動マージから外れ、dev の検証の後に手でマージする形になった。pin を外すと、以後 porkadot のリリースのたびに cnidaria の版が porkadot に従って変わる（§9）

この手順は dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で先に通してある（2026-10-27 02:00〜02:13Z）。記録は porkadot-dev の `docs/cni/verification-cnidaria-0.1.2.md`（以下「dev の記録」。main `dd17557`、porkadot-dev#24）。dev は `403c58b` に #54 の 1 行を足したもので通し、`default.yaml` は 0.37.5 と同じ。dev で分かったことは次のとおり。

- **`install kubernetes` は 1 回目で rc 0**。Pod が入れ替わったのは cnidaria の DaemonSet だけ
- 入れ替わりは 1 台ずつ（`maxUnavailable: 1`）。7 台で 33 秒（pull あり）。1 台あたり 3〜6 秒。新しい Pod は 7 つとも Ready・restart 0、ログは info だけ
- **既存の Pod 同士（同じノード、ノードをまたぐ v4 と v6）、Service、DNS は、上げる・戻す・上げ直すの 3 回の入れ替わりの間を含めて 12 分、FAIL 0**。NetworkPolicy の許可は FAIL 0、拒否が通った（OPEN）のも 0
- 入れ替わりの間に作った Pod（586 個）は全部 Ready になり、v4・v6 のアドレスが付き、許可の 8080 に届き、9090 は止まった。**宛先のノードの cnidaria が入れ替わっている数秒だけ、新しい Pod への許可が効くのが 3〜4 秒に遅れる**（普段は 1〜2 秒。止まる側で、拒否が通ることは無い。dev の見つけたことの 2）
- nftables の `inet cnidaria` の table（counter を除く）と `/opt/cni/bin`（一覧・sha256・大きさ・mtime・ctime）と conflist は、どの時点でも変わらない
- **新しい cnidaria の Pod は、起動直後の readinessProbe がほぼ毎回 1 回失敗する**（`connect: connection refused`。多くは 1〜4 秒で Ready、遅いと 10 秒。データプレーンには影響しない。dev の見つけたことの 3）
- v0.1.1 の render で `install kubernetes` を流せば戻る（rc 0、8 秒で 7 台、通信・NetworkPolicy・`/opt/cni/bin` は変わらない）

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **arm64 の control-plane（Raspberry Pi 5）での v0.1.2**。dev の VM はすべて amd64。本番の .111〜.113 は arm64 のイメージ（`sha256:93374551…`）を使う（§1.5）
- **Longhorn のボリュームの通信**。dev の Longhorn の 3 ボリュームは detached だった。本番は 14 が attached で、エンジンとレプリカの通信はノードをまたぐ Pod の通信（cnidaria の経路）を通る（§2.3 の `dswatch.sh` で 1 秒ごとに見る）
- **MetalLB の LoadBalancer**（gated-v4・gated-v6・h2-sshd）。ingress の Pod は Pod のネットワークにいる（§2.3 の `probe.sh`）
- **NetworkPolicy のある本番のアプリ**。本番の NetworkPolicy は `longhorn-system` の 6 つだけ（§2.2 の 8）
- **本番の Pod の数と負荷**（160 個。dev は少ない）

## 0. 役割と約束ごと

CoreDNS の seccomp の手順書（`../k8s-upgrade/runbook-coredns-seccomp.md`。以下「CoreDNS の手順書」）§0 と同じ形にする。

- **承認の節目は 1 つ**。この手順書では ✋✋ を付けた。
  - ✋✋ **開始**: render の差分（§2.6。この手順書と同じ PR）、§2.2 のベースライン、§2.3 の監視、§2.7 の時間帯、§5 の止める条件、§6 のロールバックの形を見せ、承認を得て PR をマージしてから、§2.4 に入る前（§3.1）
- **節目の後の手順は、ユーザーに知らせるだけで進めてよい（✋）。** イメージの事前 pull（§2.4）、etcd のバックアップ（§2.5）、`infra-admin` のトークンの発行と一時的な名前空間 `k8u-cni012` の作成・削除（§2.3・§4.4）、入れ替わりの間の新しい Pod の作成（§2.3 の `newpods.sh`）、`install kubernetes`（§3.2）、netcheck・npcheck（§4.3）は、この手順書に書いた形なら ✋ で、1 つずつ承認を取るものではない。✋ の前に、何をするかを知らせる
- **runbook から外れる操作（ロールバック、`install kubernetes` の流し直しより先の対処、Pod の手での削除、DaemonSet の手での編集・`rollout undo`、ノードの nftables・経路・conflist・`/opt/cni/bin` への手出し、`install kubelet`）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する
- 読み取りの確認は、知らせずに行ってよい。時刻はすべて UTC で記録する（control-plane のホストの時刻は JST）

## 1. 前提

### 1.1 本番の今の姿

始める前に次を確かめる（読み取り）。2026-10-27 03:1xZ（この手順書を書いたとき）の値を書く。当日に読み直す。

- 8 台 Ready・schedulable、全台 v1.37.1、`containerd://2.3.6`。etcd 3/3 healthy。Pod は 160 個（Running 136、Succeeded 24）で、Running / Completed 以外は 0 個
- cnidaria は v0.1.1 の DaemonSet（generation 3、8/8 Ready、updated 8）。Pod は 2026-10-20 05:04Z（`cnidaria-no-plugin-copy.md` の rollout）からのもの
- CoreDNS の seccomp の直し（`results/coredns-seccomp/`）と Longhorn の古い instance-manager の片付け（#66）が済んでいる

### 1.2 kubeconfig とトークン

段 8 の手順書 §1.2 と同じ（確認は `fraction-auditor`）。本番に書き込むのは次のもの。

| 書き込み | 使うもの |
|---|---|
| `porkadot etcd backup`、`porkadot install kubernetes` | ノードの上の etcdctl と admin の kubeconfig（porkadot が SSH で流す。トークンは要らない） |
| §2.4 のイメージの事前 pull | ノードの `crictl pull`（SSH） |
| §2.3 の一時的な名前空間 `k8u-cni012`（`watch.sh`・`newpods.sh`）、§4.3 の npcheck（`tools/npcheck.sh`） | **`infra-admin` の 1 時間のトークン** |
| §4.3 の netcheck（cnidaria の手順書の `netcheck.sh`） | cnidaria の手順書の `kadmin.sh`（sops の admin の kubeconfig。段 7・段 8 と同じ） |

トークンは、`k8u-cni012` を作る前（§3.1 の後、§2.3）に 1 回発行し、§4.4 で `k8u-cni012` と npcheck の名前空間を消した後にファイルを消す。

```sh
(umask 077; kubectl --context fraction create token infra-admin -n kube-system --duration=1h > /tmp/k8u-cni012-admin-token)
```

- **トークンはファイル `/tmp/k8u-cni012-admin-token`（モード 0600）に置く**。CoreDNS の手順書は「ファイルに書かない」だったが、この手順ではトークンを使うコマンドが 30 分ほどの間に何度も、ハーネスのバックグラウンドのジョブ（`newpods.sh`）からも走る。段 8 の `/tmp/k8u-stage8-admin-token` と同じ扱いにする。`watch.sh`・`newpods.sh` は `ADMIN_TOKEN_FILE`（既定はこのファイル）から読み、npcheck には `ADMIN_TOKEN="$(cat /tmp/k8u-cni012-admin-token)"` で渡す
- サーバーの側では 1 時間で切れる。§2.3 の作成から §4.4 の削除までが 1 時間を超えそうなら、同じ形で発行し直す（✋）
- §4.4 で `rm -f /tmp/k8u-cni012-admin-token` する。ファイルを git に入れない・タスクディレクトリに写さない

### 1.3 SSH

段 8 の手順書 §1.3 と同じ（worker は `ssh yuanying@<IP>`、control-plane は `ssh ubuntu@<IP>`。**名前ではなく IP で入る**。**サンドボックスの中で流す**。control-plane には `unset LC_ALL` してから入る）。2026-10-27 03:1xZ にこの手順書を書いたとき、8 台ともサンドボックスの中から §1.6 の `nodes.sh` と、cnidaria の手順書の `verify-nodes.sh` を流せた。

### 1.4 porkadot の置き場と流し方

CoreDNS の手順書 §1.4 と同じ形で、タスクディレクトリの独立の clone を使う。

| 用途 | 置き場 | 版 |
|---|---|---|
| **当日** | `/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-5` | v0.37.5（`aacfba7`、detached） |
| **§6 の戻し** | `/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-4`（CoreDNS の seccomp の本番で使ったもの。触らずに残す） | v0.37.4（`d0d84c9`、detached） |

- 2026-10-27 03:1xZ に `git ls-remote https://github.com/yuanying/porkadot.git` で、GitHub の `refs/tags/v0.37.5`（tag object `812d11d`）と `^{}`（`aacfba7`）が 0.37.5 の clone と一致することを確かめた。`lib/porkadot/version.rb` は 0.37.5。この clone で §2.6 の render を流した
- 0.37.4 の clone は `git describe --tags` が `v0.37.4`（`d0d84c9`、GitHub の tag object `59c82ba`）。§6.1 の render をこの clone で流した
- どちらの clone も `git status --short` が空。push しない・書き換えない

**このリポジトリの checkout のルートを cwd にして** 流す。

```sh
P=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-5
git -C $P describe --tags          # v0.37.5
cd <このリポジトリの checkout>     # §2.6 の PR をマージした master
BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

以下、この形を `porkadot <サブコマンド>` と書く。

- 始める前に `BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot help` が動くことを確かめる
- checkout は書き込める worktree にする（`etcd backup` が `./backup/` に書く。メインの checkout の作業ツリーはサンドボックスの中から書き込めない）。`git status --short assets porkadot.yaml` が空で、`grep -n image_tag porkadot.yaml` が cnidaria の行を返さないこと
- **流す porkadot のコマンドは `etcd backup` と `install kubernetes --node 192.168.1.111` の 2 つだけ。** `install kubelet`、`install all`、`--node` なしの `install kubernetes`、`render`（当日は render しない）、`setup-node`、`setup-containerd`、`etcd restore` は流さない
- `install kubernetes` の `--node` は control-plane の `porkadot.yaml` の `nodes` のキー（`192.168.1.111`）。付けないと bootstrap ノード（pablo）で流し、`127.0.0.1:6443` に届かず rc 1 になる

### 1.5 入れる版を確かめる

作業の当日に確かめ直す（読み取り）。

```sh
T=$(curl -s "https://ghcr.io/token?scope=repository:yuanying/cnidaria-cni:pull" | jq -r .token)
A='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
curl -sI -H "Authorization: Bearer $T" -H "Accept: $A" https://ghcr.io/v2/yuanying/cnidaria-cni/manifests/v0.1.2 | grep -i docker-content-digest
curl -s  -H "Authorization: Bearer $T" -H "Accept: $A" https://ghcr.io/v2/yuanying/cnidaria-cni/manifests/v0.1.2 | jq -r '.manifests[] | "\(.platform.os)/\(.platform.architecture) \(.digest)"'
```

2026-10-27 03:1xZ の時点:

| タグ | index | linux/amd64 | linux/arm64 |
|---|---|---|---|
| v0.1.2 | `sha256:68756535d44a…`（dev の記録と同じ） | `sha256:6d70ce4d…`（config `497c4354be2d`、層 57.3 MB） | `sha256:93374551…`（config `726fe8469ab5`、層 55.5 MB） |
| v0.1.1（今） | `sha256:60ac785235cb…` | config `effbb078f9c3`（ノードの imageID と同じ） | config `0657905b3769`（同じ） |

ほかに attestation の `unknown/unknown` が 2 つずつある。

### 1.6 確認に使うスクリプト

タスクディレクトリの `notes/runbook-cnidaria-0-1-2/scripts/` に置いた（dev の `notes/dev-cnidaria-0-1-2/scripts/` を本番の値にしたもの）。

| スクリプト | 書き込み | 中身 |
|---|---|---|
| `snap.sh <dir>` | なし | `fraction-auditor` で、Node、全 Pod（UID・restartCount・ノード・phase）、Deployment・DaemonSet・StatefulSet の generation、cnidaria の DaemonSet・ControllerRevision・Pod（yaml と一覧）・ログ（level ごとの数）・Pod の events、NetworkPolicy、Longhorn のボリューム、LoadBalancer の Service。作業端末から gated-v4・gated-v6・VIP の `/readyz`・`::131`〜`::134` の SSH のバナー・`registry.fraction.jp`、oeilvert から braque の NFS、.111 から etcd の health |
| `nodes.sh <dir>` | なし | 8 台に IP で ssh し、`/opt/cni/bin` の全ファイルの sha256・大きさ・mtime・ctime（UTC）と版の印・4 つの plugins の版・cnidaria のバイナリの有無（`cni-bin.txt`）、`/etc/cni/net.d` の一覧・sha256・中身（`conflist.txt`）、`nft -s list table inet cnidaria`（`nft-<ノード>.txt`。ホストの nft 1.0.9）、kubelet の MainPID・NRestarts・ActiveEnterTimestamp・containerd の cnidaria-cni のイメージ・proto 200 の経路の数（v4・v6）・host-local の割り当ての数（`state.txt`） |
| `dswatch.sh <logdir>` | なし | 1 秒ごとに cnidaria の DaemonSet（generation、desired・ready・updated・available）と Pod（`名前@ノード:タグ:R/nr:r<restart>:phase`、Terminating は `:T`）、attached の Longhorn のボリュームの robustness ごとの数。`<logdir>/dswatch.log` |
| `probe.sh <logdir>` | なし | 1 秒ごとに作業端末から VIP の `/readyz`、gated-v4（`192.168.1.200`）、gated-v6（`[2405:6580:6740:ac01:ace::200]`）、`fs/h2-sshd`（`::131` の 3222）の SSH のバナー。届かなければ `FAIL`。`<logdir>/probe.log` |
| `watch.sh dry-run\|up\|clients\|logs <dir>\|down` | up・clients・down | 一時的な名前空間 `k8u-cni012`（`watch.yaml`）。下の表 |
| `newpods.sh <logdir> <秒>` | Pod の作成と削除 | 8 台のそれぞれで、`role=client` の Pod を作り、Ready を待ち、Pod の中から srv-a・srv-b の 8080 に届くまでの秒数と srv-a の 9090 が止まることを見て、消し、2 秒待つ、を `<秒>` の間くり返す。1 Pod 1 行で `<logdir>/newpods.log` |
| `prepull.sh` | containerd のイメージ | 8 台で 1 台ずつ `crictl pull ghcr.io/yuanying/cnidaria-cni:v0.1.2`（§2.4） |
| `env-fraction.sh` | — | cnidaria の手順書のスクリプト（`verify-nodes.sh`・`check-apps.sh`・`netcheck.sh`・`kadmin.sh`）に渡す `RUNBOOK_ENV`。段 8 の写しの env と同じく、`IMAGE`（`image_nft` の nft のイメージ）を v0.1.1、`CHECK_URLS` の v6 を今のプレフィックス、`FRACTION` を checkout にする（`FRACTION_CHECKOUT` で替えられる）。**既定の `worktrees/runbook-cnidaria-0-1-2` は #67 の後に片付けたので、当日は `export FRACTION_CHECKOUT=<当日の checkout>` してから流す**（2026-10-27 の本番。netcheck の `kadmin.sh` がそこの sops の kubeconfig を読む） |

`watch.yaml` と `watch.sh clients` で作るもの（dev の `servers.yaml`・`clients.sh` と同じ形で、ノードを本番の値にした）:

| Pod | ノード | ラベル | 1 秒ごとに見るもの（期待） |
|---|---|---|---|
| `srv-a` | pablo（amd64、worker） | `app=srv` | busybox の httpd を 8080 と 9090 で |
| `srv-b` | 192.168.1.113（arm64、control-plane） | `app=srv` | 同上 |
| `cli-a` | pablo | `role=client` | srv-a:8080（同じノード、通る）、srv-b:8080（v4 と v6、ノードをまたぐ、通る）、Service `srv`（通る）、DNS（`kubernetes.default` を kube-dns `10.254.0.10` に、通る）、srv-a と srv-b の 9090（止まる） |
| `cli-b` | chirico | `role=client` | srv-a:8080（v4 と v6）、srv-b:8080、Service、DNS（`srv.k8u-cni012`）、srv-b の 9090（止まる） |
| `cli-deny` | chirico | `role=other` | srv-a と srv-b の 8080（止まる） |

- NetworkPolicy `srv-allow-client-8080` は `app=srv` の ingress を `role=client` からの TCP 8080 だけ許す。Service `srv` は dual-stack（PreferDualStack）で srv-a・srv-b の 8080
- どの Pod も `nodeName` と `tolerations: [{operator: Exists}]` で置く（control-plane の taint を越える）。イメージは `busybox:1.36`（`IfNotPresent`。2026-10-27 に 8 台とも containerd にあった）。requests は cpu 5m・memory 8Mi
- `cli-*` は 1 秒 1 行を標準出力に書く（`OK`・`FAIL`・`BLOCKED`・`OPEN`）。`watch.sh logs <dir>` が `fraction-auditor` の `kubectl logs` で `<dir>/cli-<名前>.txt` に取り、`FAIL` と `OPEN` の数を出す

このほかに、段 8 と同じものを使う。

- cnidaria の手順書（`/home/yuanying/.local/state/herdr-tasks/cnidaria-cni-dev/notes/fraction-runbook/`）の `verify-nodes.sh`（8 台の経路・conflist・iptables の FORWARD・nft の table。読み取り）、`check-apps.sh`（読み取り）、`netcheck.sh up|run|down`（✋）。`RUNBOOK_ENV=<scripts>/env-fraction.sh` で流す。元のスクリプトは別のタスクのものなので書き換えない
- このリポジトリの `docs/k8s-upgrade/tools/npcheck.sh`（✋ `up`・`run`・`down`、読み取りの `nft`）、`docs/k8s-upgrade/tools/dns-check.sh`（読み取り）

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 流し方 | porkadot 0.37.5 の `install kubernetes --node 192.168.1.111` を 1 回。CRD の server-side apply、apiserver の apply と rollout の待ち（apiserver は変わらないので Pod は入れ替わらない）、全体の `apply -k --prune` | dev の記録、`assets/kubernetes/install.sh` |
| 2 | pin | `porkadot.yaml` の `addons.cnidaria.image_tag` を消す（`v0.1.2` に書き換えるのではなく）。以後 porkadot の既定に従う | 2026-10-27 のユーザー判断 |
| 3 | drain・cordon | しない（ノードには触らない） | — |
| 4 | 入れ替わり | DaemonSet `cnidaria` は RollingUpdate（`maxSurge: 0`・`maxUnavailable: 1`）、`minReadySeconds` なし。1 台ずつ、古い Pod を止めてから新しい Pod を作る。**その台の cnidaria の daemon が居ない数秒の間も、ノードの nftables の table・proto 200 の経路・conflist は残る**（daemon は止まるときに片付けない。新しい daemon は同じ table を当て直す）。CNI の ADD は `/opt/cni/bin` の bridge・host-local・portmap で、daemon に依らない | live の `updateStrategy`、dev の記録の「本番に効くこと」 |
| 5 | 途切れ | 見込まない（dev で 0）。新しく作る Pod は、宛先のノードの cnidaria が入れ替わっている数秒だけ許可が遅れる（§7.1）。許容する範囲は §5 | 2026-10-19 のユーザーの方針（短時間の障害は許容） |
| 6 | イメージの事前 pull | **する**（§2.4。✋）。本番の 8 台に v0.1.2 は無い（§2.2 の 5）。pull を入れ替わりの外に出し、1 台あたりの daemon の居ない時間を dev の「pull なし」（1〜10 秒）に近づける。pull が失敗するなら、入れ替わりの前に分かる | dev の記録の「時間」 |
| 7 | etcd のバックアップ | `install kubernetes` の前に 1 回（§2.5） | 計画 §6.1 の 5 と同じ扱い |
| 8 | 一時的な名前空間 | `k8u-cni012` に Pod 5 つ・Service・NetworkPolicy（§1.6）を作り、入れ替わりの前から後の確認まで 1 秒ごとに見る。入れ替わりの間は `newpods.sh` で新しい Pod も作る。§4.4 で名前空間ごと消す（✋） | dev の記録の「通信と NetworkPolicy」「入れ替わりの間に作った Pod」 |
| 9 | 後の NetworkPolicy の確認 | 段 8 と同じ netcheck（168 項目）と npcheck（56 項目）を、入れ替わりの後に 1 回ずつ（§4.3。✋） | 段 8 の手順書 §1.8・§1.9 |
| 10 | 時間帯 | §2.7 | autoscaler・CoreDNS の手順書 §2.6 |
| 11 | 範囲の外 | cnidaria の readinessProbe の `initialDelaySeconds`（§7.2）、ノードの古い cnidaria のイメージ（v0.1.0）の片付け（§9） | dev の記録の申し送り |

### 2.2 ベースライン

作業の当日、`install kubernetes` の前に次を取り、`results/cnidaria-0.1.2/baseline.md` に残す（すべて読み取り）。出力はタスクディレクトリの `notes/cnidaria-0-1-2/base/` に置く。

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-cnidaria-0-1-2/scripts
B=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/cnidaria-0-1-2/base
R=/home/yuanying/.local/state/herdr-tasks/cnidaria-cni-dev/notes/fraction-runbook
bash $S/snap.sh $B
bash $S/nodes.sh $B
RUNBOOK_ENV=$S/env-fraction.sh $R/verify-nodes.sh > $B/verify-nodes.txt 2>&1
RUNBOOK_ENV=$S/env-fraction.sh $R/check-apps.sh > $B/check-apps.txt 2>&1
docs/k8s-upgrade/tools/dns-check.sh > $B/dns-check.txt
```

| # | 項目 | 2026-10-27 03:1xZ の値（当日に読み直す。出力は `notes/runbook-cnidaria-0-1-2/base-20261027/`） |
|---|---|---|
| 1 | Node | 8 台 Ready、v1.37.1、`containerd://2.3.6`、cordon されたものは無い。control-plane 3 台は arm64、worker 5 台は amd64 |
| 2 | 全 Pod の名前・UID・restartCount | 160 個（Running 136、Succeeded 24）。Running / Completed 以外は 0 個。hostNetwork でない Pod は 122 個（§4.2 で「cnidaria 以外は変わらない」を見る元） |
| 3 | DaemonSet `cnidaria` | generation 3（observed 3）、desired・ready・updated 8。イメージ `ghcr.io/yuanying/cnidaria-cni:v0.1.1`。`updateStrategy` は RollingUpdate（`maxSurge: 0`・`maxUnavailable: 1`）、`minReadySeconds` なし、`revisionHistoryLimit` 10。init container なし、volumes は `cni-conf`・`proc-sys-net`・`xtables-lock`（`/opt/cni/bin` は無い）、tolerations は `operator: Exists`。readinessProbe は `127.0.0.1:19080/readyz`（`periodSeconds: 10`、`initialDelaySeconds` なし）、livenessProbe は `/healthz`（`initialDelaySeconds: 10`、`periodSeconds: 30`）。引数 `--proc-sys=/host/proc/sys`・`--network-name=cbr0` |
| 4 | cnidaria の Pod | 8 つとも v0.1.1・Ready、2026-10-20 05:04:47〜05:04:58Z の起動（`controller-revision-hash` `69d47f6475`、`pod-template-generation` 3）。imageID は amd64 が `sha256:effbb078…`、arm64 が `sha256:0657905b…`。restartCount は `cnidaria-bs2vm`（.112）2（最後は 2026-10-24 12:39:55Z の exit 1。.112 の再起動のとき）、`cnidaria-s2zpl`（oeilvert）2（2026-10-23 06:29:17Z の exit 1。oeilvert の再起動のとき）、ほかの 6 つは 0 |
| 5 | containerd の cnidaria-cni のイメージ | **v0.1.2 は 8 台とも無い。** v0.1.1 は 8 台にある。v0.1.0 は oeilvert のほかの 7 台にある（oeilvert は image GC で消えた。段 6 の記録） |
| 6 | ControllerRevision | 4 つ（revision 1〜4）。revision 3 `69d47f6475`（2026-10-20 05:04:47Z）が今の Pod のもの。revision 4 `74d46565f`（2026-10-20 09:15:08Z）は revision 3 とテンプレートの `metadata.creationTimestamp: null` の有無だけが違う（段 4 の apiserver の更新で直列化が変わったもの）。Pod は `pod-template-generation` が 3 で一致するので入れ替わらなかった |
| 7 | cnidaria のログ | 8 つの Pod の今のコンテナで 16,341 行、info 16,120、**error 221**、ほかは 0。error はどれも前のもの（最後は 2026-10-23 22Z の段 8 の kubelet の再起動のとき。ほかに 10-20 10Z、10-21 06〜07Z・13Z・21Z、10-22 06Z（IPv6 のプレフィックスの切り替え））。**10-24 以降の error は 0** |
| 8 | NetworkPolicy | 6 つ、すべて `longhorn-system`（`backing-image-data-source`、`backing-image-manager`、`instance-manager`、`longhorn-manager`、`longhorn-recovery-backend`、`longhorn-webhook`） |
| 9 | `/opt/cni/bin`（`nodes.sh` の `cni-bin.txt`） | 8 台とも 21 ファイル（CNI plugins v1.9.1 の tarball の 20 個と版の印 `.porkadot-cni-plugins-version`）。版の印は `v1.9.1`、4 つの plugins は `CNI … plugin v1.9.1`。mtime は tarball の中の時刻（2026-03-16 14:18Z）、ctime は段 3 の `install kubelet`（2026-10-19 23:25〜23:48Z。ノードごと）。**cnidaria のバイナリは無い**。sha256（先頭 16 桁）は下の表 |
| 10 | conflist（`conflist.txt`） | 8 台とも `/etc/cni/net.d/10-cnidaria.conflist` の 1 つだけ（2026-10-17 05:32Z、580 B。oeilvert は 578 B）。`name: cbr0`、bridge（`cni0`）+ host-local（ノードの v4 /24 と v6 /64）+ portmap。sha256 はノードごとに違う（.111 `344a5d13…`、.112 `868eb736…`、.113 `1e9d73d9…`、braque `48978f16…`、chirico `d9259ea2…`、duchamp `506172ce…`、oeilvert `c01bedc7…`、pablo `c2dcfaf7…`） |
| 11 | nftables（`nft-<ノード>.txt`） | 8 台とも `table inet cnidaria` がある（ホストの `nft` 1.0.9 で読める）。行の数は control-plane 3 台と braque が 110（NetworkPolicy の Pod が無い）、chirico・duchamp・oeilvert・pablo が 265（うち `longhorn-system/` のコメントの付いた行が 47） |
| 12 | 経路（`state.txt`・`verify-nodes.sh`） | 8 台とも proto 200 の経路が v4 7・v6 7。`verify-nodes.sh` は 8 台とも PASS 8（64 / 64）、rc 0。`node-ipv6 matches flannel public-ipv6 on 0 nodes` は段 8 と同じ（flannel の注釈が無いため） |
| 13 | kubelet（`state.txt`） | .111 MainPID 752609・NRestarts 0、.112 1028・1、.113 612672・0、braque 541944・0、chirico 3237977・0、duchamp 202232・0、oeilvert 916805・51、pablo 3509679・0 |
| 14 | host-local の割り当て（`state.txt`） | .111 6、.112 2、.113 6、braque 2、chirico 78、duchamp 40、oeilvert 43、pablo 28（数を比べるだけ。Pod の増減で変わる） |
| 15 | Longhorn | ボリューム 14、すべて attached・healthy |
| 16 | LoadBalancer・VIP・NFS | gated-v4・gated-v6 が 404（応答あり）、VIP の `/readyz` が 200、`::131`〜`::134` の 3222 が SSH のバナー、`registry.fraction.jp/v2/` が 401、oeilvert の `/home/yuanying/shared/nfs` が `192.168.1.131:/` の nfs4 で読める。etcd 3/3 healthy |
| 17 | ディスク | `/var/lib/containerd` の使用率は oeilvert が 82%（残り 82 GB）、ほかは 9〜41%。kubelet の image GC の既定のしきい値は 85% |

`/opt/cni/bin` の 4 つの plugins の sha256（先頭 16 桁。同じアーキテクチャのノードは 21 ファイルとも同じ。2026-10-20 の `cnidaria-no-plugin-copy.md` §5 と同じ値）:

| ファイル | amd64（braque、chirico、duchamp、oeilvert、pablo） | arm64（192.168.1.111〜113） |
|---|---|---|
| bridge | `3553f5e8f47ed62a` | `35132ed8c8487372` |
| host-local | `ac5ff19b1120bd1d` | `b1d68ea8f0bbd89b` |
| portmap | `10cc11a28d9c1646` | `9d41b9e34eed0dbe` |
| loopback | `02956bdd03b9b716` | `4234e86e220b3e01` |

### 2.3 監視

`install kubernetes` の前から、§4.2 の確認が終わるまで流す。CoreDNS の手順書 §2.3 と同じく、**`nohup` や `&` で起動しない。** worker のハーネスのバックグラウンド実行で、**監視ごとに 1 つのジョブとして**起動する。

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-cnidaria-0-1-2/scripts
L=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/cnidaria-0-1-2/logs
bash $S/dswatch.sh $L                 # ジョブ 1（読み取り）
bash $S/probe.sh $L                   # ジョブ 2（読み取り）
```

一時的な名前空間（✋。§1.2 のトークンを発行してから）:

```sh
bash $S/watch.sh dry-run              # 読み取り
bash $S/watch.sh up                   # ✋ srv-a・srv-b・Service・NetworkPolicy。Ready を待つ
bash $S/watch.sh clients              # ✋ cli-a・cli-b・cli-deny。Ready を待つ
bash $S/watch.sh logs $L/pre          # 読み取り。1 分ほど待ってから
bash $S/newpods.sh $L 300             # ジョブ 3（✋）。install kubernetes の 30 秒ほど前に起動する
```

- 起動したら、ジョブの一覧に居ることと、`dswatch.log`・`probe.log` に行が足されていくことを確かめる
- **`install kubernetes` の前に、`watch.sh logs $L/pre` で 3 つのクライアントの最後の行が 1 分以内で、`FAIL` と `OPEN` が 0 であること**。クライアントを作った直後の 1〜2 行は、許可がまだ効かず `FAIL` になりうる（新しい Pod の IP が宛先のノードの table に入る前。dev の記録の「通信と NetworkPolicy」）。その後に `FAIL` が続くなら、入れる前の問題として止める
- `newpods.sh` は 300 秒で終わる（入れ替わりの前の 30 秒、入れ替わり、後の 2〜3 分）。`install kubernetes` の前に `newpods.log` に 8 台の行が出始めていること
- `dswatch.sh`・`probe.sh` は `touch $L/watch.stop` で止まる（§4.4）
- `dswatch.log` で見るもの: `ready=` が 7 を下回らないこと（1 台ずつ）、新しい Pod のタグ（`v0.1.2`）・`R`・`r0`、`lh` の `healthy=14` が続くこと（`degraded`・`faulted` が出ないこと）
- `probe.log` で見るもの: `FAIL` の行
- 段 8 の手順書 §2.3 の etcd の health の監視は流さない（etcd には触らない）。DNS は `cli-a`・`cli-b` が 1 秒ごとに見る

### 2.4 イメージの事前 pull ✋

§3.1 の ✋✋ の後、`install kubernetes` の前に流す（サンドボックスの中で）。

```sh
bash $S/prepull.sh | tee /home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/cnidaria-0-1-2/prepull.txt
```

- 8 台とも `rc=0` で、`crictl images` に `cnidaria-cni v0.1.2` が出る。台ごとのかかった秒数を記録する。イメージ ID は amd64 が `497c4354be2d…`、arm64 が `726fe8469ab5…`（§1.5 の config）であること
- pull に失敗した台があれば、止めて報告する（ghcr.io に届かない、など）。`install kubernetes` を流しても、その台で `ImagePullBackOff` になり rollout が止まる
- oeilvert のディスクは 82%（§2.2 の 17）。57 MB を足しても 85% には届かない見込み。pull の後に `df -h /var/lib/containerd` を記録する
- 事前 pull と `install kubernetes` の間は短くする（30 分以内）。使われていないイメージは image GC の対象になる

### 2.5 etcd のバックアップ ✋

`install kubernetes` の前に、porkadot 0.37.5 で取る（CoreDNS の手順書 §2.4 と同じ形。0.37.5 の `etcd backup` は 0.37.4 と同じ実装で、ノードの 3.7.3 の etcdctl を使う）。

```sh
porkadot etcd backup
ls -l ./backup/
```

- 手元のファイルは `./backup/etcd-<日時>.db`、モード 0600。`./backup/` は `.gitignore` で除外してある。スナップショットには Secret が平文で入っているので、`git add -f` などで追加しない。worktree で流したときは、worktree を片付ける前にメインの checkout の `backup/` へ写す（coordinator）
- 時刻、ファイル名、サイズ、sha256 を記録する（CoreDNS の seccomp の前の 2026-10-26 07:02Z のものは 66,986,016 B）。桁が違えば止める
- この更新は etcd の restore を要しない見込み（§6 のロールバックは `install kubernetes` で戻す）。このバックアップは想定外のときの最後の手段

### 2.6 render の差分（この手順書と同じ PR）

2026-10-27 03:11Z に、porkadot 0.37.5（`aacfba7`。§1.4 の clone）で、このリポジトリのルートを cwd にして、`porkadot.yaml` の pin を消してから `render kubernetes` を流した（rc 0）。前の render は master の `70af4bf` の assets（CoreDNS の seccomp の porkadot 0.37.4 の render `253576e`。その後の PR は `assets/` を変えていない）。

`porkadot.yaml` の差分:

```diff
@@ -62,7 +62,6 @@ addons:
   enabled: [cnidaria, coredns, metallb, kubelet-serving-cert-approver]
   cnidaria:
     network_name: cbr0
-    image_tag: v0.1.1
   metallb:
```

**assets の差分は `assets/kubernetes/manifests/addons/cnidaria/cnidaria.yaml` のイメージの 1 行だけ**（新しくできたファイル、消えたファイル、証明書・sops の Secret の作り直しも無い）。

```diff
@@ -85,7 +85,7 @@ spec:
       # `porkadot install kubelet` (kubernetes.networking.cni_version).
       containers:
       - name: cnidaria
-        image: ghcr.io/yuanying/cnidaria-cni:v0.1.1
+        image: ghcr.io/yuanying/cnidaria-cni:v0.1.2
         args:
         - --proc-sys=/host/proc/sys
         - --network-name=cbr0
```

- **この差分は dev の差分と同じ**（dev の記録の「render の差分」）。`--network-name=cbr0` は残る
- **変わらないもの**: 同じファイルの ServiceAccount・ClusterRole・ClusterRoleBinding と DaemonSet のほかの項目、CoreDNS（v1.14.7、`RuntimeDefault` の seccomp、Corefile）・kube-dns-autoscaler・MetalLB・kubelet-serving-cert-approver・kube-proxy・control-plane のマニフェスト。**0.37.4 から 0.37.5 で CoreDNS などに差は出ない**（下の 2 つ目の確かめ）
- 次の 3 つの render も `/tmp` の clone で流して確かめた（どれも rc 0。PR には入れていない）
  - **0.37.4 で、pin のある `porkadot.yaml`（`70af4bf`）の `render kubernetes`: master の assets とバイトまで同じ**（`git status --short` が空）。§6 のロールバックの材料
  - **0.37.5 で、pin のある `porkadot.yaml` の `render kubernetes`: 同じく master の assets と同じ。** 0.37.5 の差で本番の assets に効くのは cnidaria の既定の版だけ
  - 0.37.5 で、pin を外した `porkadot.yaml` の `render kubernetes`・`render kubelet`・`render etcd`・`render bootstrap`: 差分は上の 1 行と、毎回作り直される証明書の 12 ファイル（各ノードと bootstrap の `bootstrap.crt`、control-plane の `etcd.crt`）だけ。kubelet・etcd・bootstrap は `install kubernetes` で使わないので、PR には入れていない（CoreDNS の手順書 §2.5 と同じ）。`install-deps.sh` の CNI plugins の版（v1.9.1）も変わらない
- `render kubernetes` は証明書を作り直さない。当日は render しない（この PR の `assets/` で流す）。secrets（`assets/` の sops の証明書と鍵）は、この PR では変わらない

### 2.7 時間帯

CoreDNS の手順書 §2.6 の時間帯に、fs のバックアップの CronJob を足して避ける。

| 時間帯（UTC） | 何が起きるか | 避ける理由 |
|---|---|---|
| **18:00〜19:30** | jumelle の unattended-upgrades と自動再起動 | jumelle が落ちると ghcr.io からの pull が止まり（新しい Pod が起動しない）、監視の外向きの確かめと入れ替わりの影響を見分けられない |
| 06:00〜07:00 | worker 5 台の unattended-upgrades | needrestart がサービスを再起動すると、§4.2 の「kubelet が再起動しない」「ほかの Pod が変わらない」の確かめと取り違える |
| 21:00〜22:00 | control-plane 3 台の unattended-upgrades（`fraction-agents/deep-researcher-backup` の 06:00 JST = 21:00Z もここ） | 同上（apiserver） |
| 05:44、07:53、09:03 | fs のバックアップの CronJob（`h2-backup`、`sites-backup`、`data-backup`） | 入れ替わりの間に作られる Pod と、Longhorn・NFS への書き込みが重なる。前後 15 分を避ける |
| 20:30 | `natsumi` のバックアップの CronJob 3 つ（05:30 JST） | 同上 |

- `aphrael/tumblr-like` は 3 時間ごとの 38 分（00:38、03:38、…）に走る。`aphrael` に NetworkPolicy は無いので、入れ替わりと重なっても許可の遅れ（§7.1）は効かない。重なったら記録する
- 作業は、§2.4 の事前 pull から §4.4 の片付けまで 60 分ほどを見込む。その間が上の時間帯に重ならないこと。たとえば 00:00〜05:15Z、10:00〜17:30Z の中

### 2.8 dev の記録と違う本番の形

| 点 | dev | 本番 | この手順書での扱い |
|---|---|---|---|
| ノード | 7 台、すべて amd64 の VM | 8 台、control-plane 3 台は arm64（Raspberry Pi 5） | srv-b を .113（arm64）に置く。newpods も 8 台 |
| v0.1.2 のイメージ | pull しながら入れ替わった（1 台 3〜6 秒） | 8 台とも無い | 事前 pull（§2.4） |
| kube-dns | `10.252.0.10` | `10.254.0.10` | スクリプトは本番の値 |
| Pod の CIDR | `10.242.` | v4 `10.244.<n>.0/24`、v6 `fde7:4ad6:425d:<n>::/64` | — |
| テスト用の名前空間 | `cni012` | **`k8u-cni012`**（段 3〜8 の `k8u-npcheck` と同じ前置き） | §4.4 で消す |
| Longhorn | 3 ボリュームとも detached | 14 が attached・healthy | `dswatch.sh` で 1 秒ごとに robustness を見る |
| NetworkPolicy | `e2e-np` と `cni012` | `longhorn-system` の 6 つ | 入れる前後で nft の table を比べる。npcheck（§4.3） |
| LoadBalancer | v4 と v6 の 1 つずつ | gated-v4・gated-v6・h2-sshd ほか | `probe.sh` で 1 秒ごと |
| 書き込みの権限 | `test-admin` | `infra-admin` の 1 時間のトークン（§1.2）、netcheck は `kadmin.sh` | — |
| 入れ替わりの間の新しい Pod | 1 台に 1 つずつ作り続けた（3 回で 586 個） | 同じ形で、1 つごとに 2 秒あける。300 秒（§2.3） | — |

## 3. `install kubernetes`

### 3.1 事前確認

✋✋ **開始の承認を取る。** §2.6 の差分と PR、§2.2 のベースライン（特に 3〜5・7・9〜12 の DaemonSet・Pod・イメージ・ログ・`/opt/cni/bin`・conflist・nftables・経路）、§2.3 の監視と一時的な名前空間、§2.4 の事前 pull、§2.7 の時間帯、§5 の止める条件、§6 のロールバックの形を示す。承認を得て PR をマージし、マージした master の checkout（§1.4）で次に入る。

**この PR をマージしてから §3.2 を流すまでの間に、ほかの作業で `install kubernetes` を流さない**（この assets で流すと、その時点で cnidaria が入れ替わる）。マージは流す直前にする。

- §2.2 のベースラインが当日の値で取れている
- 全台 Ready、cnidaria が 8/8 Ready・updated 8
- checkout が §2.6 の PR をマージした master で、`git status --short assets porkadot.yaml` が空、`grep -n 'cnidaria-cni' assets/kubernetes/manifests/addons/cnidaria/cnidaria.yaml` が `v0.1.2`。`git -C $P describe --tags` が `v0.37.5`
- 作業の時間が §2.7 の時間帯と重ならない

ここから次の順に進める。

1. ✋ §2.4 のイメージの事前 pull
2. ✋ §2.5 の etcd のバックアップ
3. §2.3 の `dswatch.sh`・`probe.sh` をジョブとして起動する
4. ✋ §1.2 のトークンを発行し、§2.3 の `watch.sh up`・`watch.sh clients` で一時的な名前空間を作る。1 分ほど待って `watch.sh logs $L/pre`
5. ✋ §2.3 の `newpods.sh $L 300` をジョブとして起動し、30 秒ほど待つ
6. ✋ §3.2

### 3.2 流す ✋

```sh
porkadot install kubernetes --node 192.168.1.111 2>&1 | tee /home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/cnidaria-0-1-2/install-kubernetes.log
```

- 時刻と rc を記録する。dev では約 17 秒で rc 0、2026-10-20 の本番（`cnidaria-no-plugin-copy.md`）では 25 秒
- 出力で見るもの:
  - **`daemonset.apps/cnidaria configured`**
  - 前からの `configured`: PDB `kube-controller-manager`・`kube-scheduler`、DaemonSet `kube-apiserver`（apiserver の apply と全体の apply で 2 回）、ValidatingWebhookConfiguration `metallb-webhook-configuration`。2026-10-20 の本番と dev でも出ており、Pod は入れ替わらない（generation が変わらなければ想定内）
  - **ほかは `unchanged`**（ServiceAccount・ClusterRole・ClusterRoleBinding `cnidaria`、`deployment.apps/coredns` を含む）
  - **`pruned` の行が無い**（オブジェクトの組は変わらない）
- rc 1 のときの扱い（`connection refused` など）は段 8 の手順書 §8.3 と同じ。全体の apply の前に落ちたなら cnidaria は前のまま。原因を見て流し直す（流し直しは ✋ の範囲）。2 回目も落ちたら止めて報告する
- 流した直後に、§2.3 のジョブのログが続いていることを確かめる

## 4. 後の確認

### 4.1 入れ替わりを見る

```sh
kubectl --context fraction -n kube-system rollout status ds/cnidaria --timeout=5m
```

- `dswatch.log` で、1 台ずつ古い Pod が `:T` になって消え、そのノードに新しい Pod（`v0.1.2`）が作られて `R` になるのを見る。各ノードの古い Pod の止まった時刻と新しい Pod の Ready の時刻を控える（dev の記録の「入れ替わり」の表と同じ形）。dev では 1 台あたり 3〜6 秒、7 台で 33 秒（pull あり）・8 秒（pull なし）
- **どの時点でも Ready でない cnidaria の Pod は 1 つまで**（`ready=` が 7 を下回らない）
- **新しい Pod が 2 分たっても Ready にならないときは止める**（§5）。rollout はそこで止まり、ほかのノードは古い Pod のまま。`ImagePullBackOff` なら §2.4 が効いていない
- 新しい Pod の起動直後の `Readiness probe failed: … connection refused` が 1〜2 回出て、10 秒ほどで Ready になるのは想定どおり（§7.2。2026-10-27 の本番では 7 つが 1 回で 0〜2 秒、duchamp の 1 つが 2 回で 11 秒）。記録する
- `dswatch.log` の `lh` が `healthy=14` から変わったら、時刻を控える（§5）
- `probe.log` に `FAIL` が出たら、時刻と対象を控える

### 4.2 確認

rollout が終わり、`newpods.sh` が終わったら（300 秒）、次を取って §2.2 と比べる。

```sh
A=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/cnidaria-0-1-2/after
bash $S/snap.sh $A
bash $S/nodes.sh $A
RUNBOOK_ENV=$S/env-fraction.sh $R/verify-nodes.sh > $A/verify-nodes.txt 2>&1
RUNBOOK_ENV=$S/env-fraction.sh $R/check-apps.sh > $A/check-apps.txt 2>&1
docs/k8s-upgrade/tools/dns-check.sh > $A/dns-check.txt
bash $S/watch.sh logs $L/after
for f in cni-bin.txt conflist.txt; do diff $B/$f $A/$f && echo "$f same"; done
for n in 192.168.1.111 192.168.1.112 192.168.1.113 braque chirico duchamp oeilvert pablo; do diff -q $B/nft-$n.txt $A/nft-$n.txt; done
```

| # | 確認 | 合格基準 |
|---|---|---|
| 1 | DaemonSet | generation が 1 つ増える（3 → 4）、observed も 4。desired・ready・updated・available が 8。イメージが `v0.1.2`。ほかの項目（§2.2 の 3）が同じ |
| 2 | cnidaria の Pod | **8 つとも新しい Pod で、v0.1.2・Ready・restart 0**。imageID が `ghcr.io/yuanying/cnidaria-cni@sha256:68756535d44a…`（§1.5 の index。事前 pull したイメージは repo digest の形で出る）、ノードの `crictl images` の ID が amd64 は `497c4354be2d…`、arm64 は `726fe8469ab5…`（§1.5 の config）。古い 8 つが無い |
| 3 | ControllerRevision | 新しい revision 5 ができ、新しい Pod の `controller-revision-hash` がそれ。revision 1〜4 は残る（§6 で使われうる） |
| 4 | cnidaria のログ | **新しい 8 つの Pod のログが info だけ**（`error` 0）。nftables の table を当て直した行（`applied the nftables table`）が各 Pod にある。`results may be incomplete` の `Reconciler error` が 1 回出て再試行で消えるのは、2026-10-20 の本番の見つけたことの 2 と同じとして記録する（続くなら §5） |
| 5 | `/opt/cni/bin` | 8 台とも `cni-bin.txt` が §2.2 の 9 と同じ（一覧・sha256・大きさ・mtime・**ctime**・版の印・plugins の版）。cnidaria のバイナリは無いまま |
| 6 | conflist | 8 台とも `conflist.txt` が §2.2 の 10 と同じ（一覧・mtime・sha256・中身） |
| 7 | nftables | 8 台とも `nft-<ノード>.txt` が §2.2 の 11 と同じ。違いがあれば中身を見て、**Pod の増減で説明できる差（`longhorn-system` の Pod の IP の集合など）か**を見分けて記録する（§7.3）。chain・規則の形が違えば §5 |
| 8 | 経路 | `verify-nodes.sh` が 64 / 64 PASS、rc 0。`state.txt` の proto 200 が 8 台とも v4 7・v6 7 |
| 9 | 一時的な名前空間の監視（`watch.sh logs`） | `cli-a`・`cli-b` の `FAIL` が、作った直後の行（§2.3）のほか 0。`cli-a`・`cli-b`・`cli-deny` の `OPEN` が 0。入れ替わりの間の行（`dswatch.log` の時刻と突き合わせる）も同じ。dev では FAIL 0・OPEN 0 |
| 10 | 新しい Pod（`newpods.log`） | **すべての Pod が Ready になり、v4 と v6 のアドレスが付き、srv-a・srv-b の 8080 に届き、9090 が `BLOCKED`**（`NOTREADY`・`NEVER`・`OPEN`・`RESULT none` が 0）。8080 に届くまでの秒数の分布を記録する。dev では 1〜2 秒、入れ替わりの間の宛先のノードで 3〜5 秒 |
| 11 | ほかの Pod | 全 Pod の比較で、**変わったのは cnidaria の Pod と `k8u-cni012` の Pod だけ**（名前・UID・restartCount）。ほかの DaemonSet・Deployment・StatefulSet の generation が同じ（`gens.tsv`）。Running / Completed 以外が 0（`k8u-cni012` のほか） |
| 12 | kubelet | 8 台の MainPID・NRestarts・ActiveEnterTimestamp が §2.2 の 13 と同じ |
| 13 | Longhorn | 14 とも attached・healthy で、`dswatch.log` の `lh` に `degraded`・`faulted` が一度も出ていない。アタッチ先が §2.2 と同じ |
| 14 | LoadBalancer・VIP・NFS・etcd | `probe.log` の `FAIL` が 0（§5 の範囲なら記録）。`snap.sh` の `lb-nfs.txt` が §2.2 の 16 と同じ。etcd 3/3 healthy |
| 15 | DNS | `dns-check.sh` の答えが `base/dns-check.txt` と同じ（外の名前は rcode だけ） |
| 16 | 健全性 | 8 台 Ready、`check-apps.sh` の duplicates 0、Running / Completed 以外の Pod 0（`k8u-cni012` のほか） |

### 4.3 netcheck と npcheck ✋

段 8 の手順書 §1.8・§1.9 と同じものを 1 回ずつ流す。§4.2 の後、§4.4 の前。

```sh
RUNBOOK_ENV=$S/env-fraction.sh $R/netcheck.sh up    > $A/netcheck-up.txt 2>&1     # ✋
RUNBOOK_ENV=$S/env-fraction.sh $R/netcheck.sh run   > $A/netcheck-run.txt 2>&1
RUNBOOK_ENV=$S/env-fraction.sh $R/netcheck.sh down  > $A/netcheck-down.txt 2>&1   # ✋
T=docs/k8s-upgrade/tools/npcheck.sh
ADMIN_TOKEN="$(cat /tmp/k8u-cni012-admin-token)" $T up  > $A/npcheck-up.txt 2>&1     # ✋
$T nft > $A/npcheck-nft-up.txt 2>&1
ADMIN_TOKEN="$(cat /tmp/k8u-cni012-admin-token)" $T run > $A/npcheck-run.txt 2>&1
ADMIN_TOKEN="$(cat /tmp/k8u-cni012-admin-token)" $T down > $A/npcheck-down.txt 2>&1  # ✋
$T nft > $A/npcheck-nft-down.txt 2>&1
```

- netcheck は `PASS 168 / 168, pods 8/8`。名前空間 `cnidaria-netcheck` が NotFound に戻る（段 8 と同じ）
- npcheck は、`up` の後の `nft` が 8 台とも 1 以上（段 8 は 9）、`run` が `OK 56, not OK 0`、`down` の後の `nft` が 8 台とも 0、名前空間 `k8u-npcheck` が NotFound
- 新しい cnidaria の daemon が、Pod と NetworkPolicy の作成・削除を受けて table を当て直すことの確かめになる（§4.2 の 9・10 は入れ替わりの間、ここは入れ替わりの後）

### 4.4 片付け ✋

```sh
bash $S/watch.sh logs $L/final        # 読み取り。最後のクライアントのログ
bash $S/watch.sh down                 # ✋ 名前空間 k8u-cni012 を消す
kubectl --context fraction get ns k8u-cni012 k8u-npcheck cnidaria-netcheck   # 3 つとも NotFound
touch $L/watch.stop                   # dswatch.sh・probe.sh を止める
rm -f /tmp/k8u-cni012-admin-token
bash $S/nodes.sh /home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/cnidaria-0-1-2/final
```

- `final/nft-<ノード>.txt` から `k8u-cni012` の規則が消え、§2.2 の 11 と同じに戻ること（pablo・.113 の table。§7.3）
- 2 つのジョブが終わったことを確かめる。トークンのファイルを消した時刻を記録する（サーバーの側では発行から 1 時間で切れる）
- busybox の Pod の消えた後の host-local の割り当ての数が、§2.2 の 14 と同じくらいに戻ること（dev の見つけたことの 5）

## 5. 止める条件

次のどれかに当たったら、その場で止めて報告する。続けるか §6 で戻すかはユーザーが決める。止めるときは、`newpods.sh` がまだ動いていればジョブを止める（作った Pod は `k8u-cni012` にあり、§4.4 で消える）。

- **新しい cnidaria の Pod が 2 分たっても Ready にならない**（`ImagePullBackOff`、`CrashLoopBackOff`、`CreateContainerError` など）、**または restartCount が 1 以上になる**（dev では 0）。rollout はその台で止まり、その台は daemon の無いまま（table・経路は残るが、当て直しは止まる）
- **`cli-a`・`cli-b` の `FAIL` が 3 秒を超えて続く、または合わせて 5 秒を超える**（作った直後の行のほか）。名前（`same_a`・`cross_b6`・`svc`・`dns` など）と時刻を控える
- **拒否のはずのものが通る（`OPEN`）**: `cli-*` の `deny*`、`newpods.log` の `a9090=OPEN`、npcheck の `not OK`。1 回でも止める（NetworkPolicy の enforce が崩れている）
- `newpods.log` に `NOTREADY`・`ips=[]` や v6 の無いもの・`NEVER`（30 秒たっても許可に届かない）がある
- `dswatch.log` の `ready=` が 7 を下回る（2 台以上が同時に Ready でない）
- **Longhorn のボリュームが `degraded`・`faulted` になる**、アタッチ先が変わる
- `probe.log` の `FAIL` が 5 秒を超えて続く（gated-v4・gated-v6・h2-sshd・VIP のどれか）
- 新しい cnidaria の Pod のログに `error` が続く（1 回で再試行で消えるもののほか）
- `/opt/cni/bin` または conflist が変わる、proto 200 の経路が 7 本でなくなる、`verify-nodes.sh` に FAIL、nft の table の形（chain・規則）が変わる
- cnidaria と `k8u-cni012` 以外の Pod の再起動、Node の NotReady、kubelet の MainPID の変化
- `install kubernetes` が 2 回続けて rc 0 にならない、出力に `pruned` の行がある、§3.2 の 5 つのほかに `configured` がある
- netcheck に FAIL がある

`cli-*` の 1〜2 秒の `FAIL`、`newpods.log` の 3〜5 秒の遅れは、記録して進める。

## 6. ロールバック

**戻すのは runbook から外れる操作なので、ユーザーの承認を取る。** porkadot 0.37.4 と pin のある `porkadot.yaml`（この PR の前の master `70af4bf`）の assets で `install kubernetes` を流し、v0.1.1 に戻す（dev で確かめた。rc 0、8 秒で 7 台、通信・NetworkPolicy・`/opt/cni/bin` は変わらない）。cnidaria の Pod はもう 1 度、1 台ずつ入れ替わる。

### 6.1 戻すための材料

- **前の版の assets**: この PR の前の master（**`70af4bf`**）の `assets/` と `porkadot.yaml`（pin あり）。**porkadot 0.37.4 で `render kubernetes` しても、この `assets/` とバイトまで同じ**（2026-10-27 03:1xZ に `/tmp` の clone で確かめた。`git status --short` が空）なので、当日に render しないで使う
- **porkadot 0.37.4**: §1.4 の `worktrees/porkadot-v0-37-4`
- **v0.1.1 のイメージ**: 8 台の containerd にある（§2.2 の 5）。入れ替わりの後は使われていないイメージになり、image GC で消えうる（oeilvert のディスクは 82%。§7.4）。消えていれば戻すときに ghcr.io から pull する（66 MB）

用意の仕方（作業端末で。CoreDNS の手順書 §7.1 と同じ形。`git worktree add` は元の clone の `.git` に書き込むので使わない）:

```sh
P_OLD=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-4   # git -C $P_OLD describe --tags が v0.37.4
git clone <このリポジトリの checkout> /tmp/fraction-cnidaria-011
git -C /tmp/fraction-cnidaria-011 checkout 70af4bf
cd /tmp/fraction-cnidaria-011
grep -n 'cnidaria-cni' assets/kubernetes/manifests/addons/cnidaria/cnidaria.yaml   # v0.1.1
grep -n 'image_tag' porkadot.yaml                                                   # image_tag: v0.1.1
```

### 6.2 戻す ✋

```sh
cd /tmp/fraction-cnidaria-011
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml
```

- §2.3 の監視と一時的な名前空間を流したまま行う（片付けの前なら）
- テンプレートが v0.1.1 のもの（revision 4 と同じ中身）に戻り、DaemonSet はそれに合う古い ControllerRevision を使い直す（revision の番号が上がる）。8 台の Pod が §4.1 と同じ形で入れ替わる
- 確かめること: §4.2 を読み替えて行う（8 つとも v0.1.1・Ready・restart 0、`/opt/cni/bin`・conflist・nft の table・経路が §2.2 と同じ、監視の FAIL・OPEN が 0、cnidaria 以外の Pod が変わらない、Longhorn が healthy）
- **戻した後は、master の `porkadot.yaml` と assets が v0.1.2 のまま残る。** 次に誰かが master で `install kubernetes` を流すと v0.1.2 に戻ってしまう。戻したら、この PR を revert する PR（pin を戻し、assets を 0.37.4 の render に戻す）を出し、それがマージされるまで master で `install kubernetes` を流さない。`/tmp/fraction-cnidaria-011` と 0.37.4 で流し直すのはよい

### 6.3 それでも戻らないとき

`install kubernetes` で cnidaria の Pod が起きないなど、§6.2 で戻らないときは止めて報告する。rollout は `maxUnavailable: 1` なので、起きない Pod は 1 つで、ほかの台は動いている daemon のまま。daemon の居ない台も、table・経路・conflist はノードに残るので、既存の通信は続く見込み（§2.1 の 4）。立て直しの手（DaemonSet の `rollout undo`、手での `kubectl apply`、Pod の削除）は、その時点でユーザーと決める。etcd の restore は要らない見込み。

## 7. 既知の問題と注意

### 7.1 入れ替わりの間に作られる Pod の許可の遅れ

dev の見つけたことの 2 と同じ。NetworkPolicy の許可（ingress の `from`）の相手の集合は宛先のノードの table にあり、新しい Pod の IP は、そのノードの cnidaria が Pod の event を受けて table を当て直したときに入る。宛先のノードの cnidaria が入れ替わっている数秒の間に作られた Pod は、その宛先に届くまで 3〜4 秒かかる（止まる側。拒否が通ることは無い）。既存の Pod の IP はすでに集合に入っているので影響しない。v0.1.1 の入れ替わりでも同じで、v0.1.2 の変更とは関係しない。

本番で NetworkPolicy があるのは `longhorn-system` だけ（§2.2 の 8）。入れ替わりの間に Longhorn の Pod が作られることはまず無いが、CronJob の Pod などが Longhorn の Pod に最初に接続するときに数秒待つことはありうる（§2.7）。

### 7.2 readinessProbe の 1 回の失敗

dev の見つけたことの 3 と同じ。readinessProbe に `initialDelaySeconds` が無く `periodSeconds: 10` なので、新しい Pod の最初の probe が daemon の `:19080` の開く前に当たると `connection refused` になり、次は 10 秒後になる。daemon は起動の時点で table を当て直しているので、データプレーンには影響せず、rollout が長くなるだけ（8 台で最長 80 秒ほど延びる）。`Readiness probe failed` の event が 1〜2 回出て 10 秒ほどで Ready になるのは想定どおりとして記録する（2026-10-27 の本番では 8 つとも起動の同じ秒に 1 回失敗し、duchamp の 1 つは 2 回で Ready まで 11 秒）。直すなら porkadot の `cnidaria.yaml.erb` と cnidaria-cni の `deploy/daemonset.yaml`（範囲の外。§9）。

### 7.3 nftables の table の差

`nft -s` は counter を除くが、NetworkPolicy の相手の Pod の IP の集合は table に入る。`longhorn-system` の Pod が作り直されると、chirico・duchamp・oeilvert・pablo の table の集合が変わる。入れ替わりの前後で差が出たら、その間に Pod が変わったか（§4.2 の 11 の比較）と突き合わせて見分ける。`k8u-cni012` の NetworkPolicy の規則は、srv-a・srv-b のノード（pablo、.113）の table に、名前空間を作ってから消すまでの間だけ入る（§2.2 の値はその前、§4.2 の値はその間、§4.4 の `final` は消した後）。§4.2 の 7 で比べるときは、`k8u-cni012/` のコメントの行と、その集合を除いて比べる。既存の集合 `isolated_ingress_v4`・`isolated_ingress_v6` にも、NetworkPolicy の対象になった srv-a（pablo）・srv-b（.113）の IP が入る（2026-10-27 の本番で pablo 265 → 295 行、.113 110 → 140 行）。これも `k8u-cni012` の差として除く。

### 7.4 image GC と古いイメージ

入れ替わりの後、v0.1.1 は使われていないイメージになる。kubelet の image GC（`/var/lib/containerd` の使用率が 85% を超えると、使われていないイメージを古い順に消す）で消えうる。oeilvert は 82%（§2.2 の 17）。消えると §6 の戻しで pull が要る（ghcr.io に届けば戻せる）。v0.1.0（oeilvert のほかの 7 台）は flannel から移ったときの戻しの材料で、今は使われていない（§9）。

### 7.5 pin を外したことの後の影響

pin を外したので、**以後 porkadot のリリースで `default.yaml` の cnidaria の版が上がると、次の本番の `render kubernetes` で cnidaria も上がる。** porkadot#73 で cnidaria の Renovate の PR は自動でマージされなくなったので、版が上がるのは dev で確かめて手でマージしたときだけ。ほかの作業の手順書で porkadot を上げて `render kubernetes` するときは、render の差分に cnidaria のイメージが入っていないかを見る。入っていたら、その作業とは分けて扱う（この手順書と同じ形）。

## 8. 記録

`results/cnidaria-0.1.2/` に、ベースライン（`baseline.md`。§1.1 の前提、§2.2 の表、§2.4 の事前 pull、§2.5 のバックアップ、§2.3 の監視の起動）と、作業の記録（`summary.md`。§3.2 の出力の要点、§4.1 の入れ替わりの表（各ノードの古い Pod の止まった時刻と新しい Pod の Ready の時刻）、§4.2 の各項目、§4.3 の結果、監視の FAIL・OPEN、新しい Pod の 8080 に届くまでの秒数、§4.4 の片付け、手順書との差）を残す。形は `../k8s-upgrade/results/coredns-seccomp/` に合わせる。
`snap.sh`・`nodes.sh`・`verify-nodes.sh`・`check-apps.sh`・`dns-check.sh`・`watch.sh logs` の出力と監視のログ（`dswatch.log`、`probe.log`、`newpods.log`）はタスクディレクトリの `notes/cnidaria-0-1-2/` に置き、要点を記録に写す。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（記録の PR で）。

2026-10-27 10:37〜10:51Z に本番で実施した。記録は `results/cnidaria-0.1.2/baseline.md`・`summary.md`。手順書との差（imageID の形、readinessProbe の 2 回の失敗、`FRACTION_CHECKOUT`、`isolated_ingress` の集合）は §1.6・§4.1・§4.2・§7.2・§7.3 に反映した。

## 9. この後

- cnidaria の readinessProbe に `initialDelaySeconds` を足すか（§7.2。porkadot と cnidaria-cni）
- ノードの containerd に残る cnidaria の古いイメージ（v0.1.0 の 7 台、v0.1.1 の 8 台）の片付け（計画 §10。v0.1.1 は v0.1.2 で落ち着いてから）
- cnidaria の ControllerRevision 1〜4（`revisionHistoryLimit` 10 の中で残る）。片付けは要らない
