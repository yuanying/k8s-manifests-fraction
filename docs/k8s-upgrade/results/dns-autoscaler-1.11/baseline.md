# kube-dns-autoscaler v1.11.0 のベースライン

本番 `fraction` の kube-dns-autoscaler を `cluster-proportional-autoscaler-amd64:1.7.1` から `cpa/cluster-proportional-autoscaler:v1.11.0` へ上げる（porkadot 0.37.2 → 0.37.3）前に取った、読み取りの結果と etcd のバックアップの記録。手順は `../../runbook-dns-autoscaler-1.11.md`（以下 runbook）。
時刻は UTC。`snap.sh`・`node-state.sh`・`seccomp.sh` の出力は、タスクディレクトリの `notes/dns-autoscaler-1-11/base/` に置いた（リポジトリには入れない）。

## 1. 前提（runbook §1。2026-10-25 10:16Z）

| 項目 | 結果 |
|---|---|
| 本番の今の姿（§1.1） | 8 台 Ready・schedulable、v1.37.1。Pod 168 個（Running 145、Succeeded 23）で、Running / Succeeded 以外は 0 個（runbook を書いたときの 166 個から 2 個増えた。どれも Running か Succeeded）。MetalLB の更新は済んでいる（`../metallb-0.16/summary.md`）。autoscaler は 1.7.1 の 1 つ（chirico の `kube-dns-autoscaler-cc5758b6f-dhc95`、restart 0、2026-10-19 09:35:32Z 起動） |
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor`。`auth can-i delete pods -A` は `no`。作業端末の kubectl は v1.37.1。`infra-admin` のトークンは発行していない |
| SSH（§1.3） | サンドボックスの中から、8 台に IP で `node-state.sh`、chirico に `seccomp.sh`、oeilvert に `dns-watch.sh` と `curl` を流せた |
| porkadot（§1.4） | `worktrees/porkadot-v0-37-3` は `git describe --tags` が `v0.37.3`（`121a264`）、`lib/porkadot/version.rb` が 0.37.3、作業ツリーに変更が無い。GitHub の `refs/tags/v0.37.3` は tag object `91a366b`、`^{}` は `121a264` で一致。`porkadot help` が動く。§7 の戻しの `worktrees/porkadot-v0-37-2` は `v0.37.2`（`020c7c7`）、変更なし。cwd は worktree `dns-autoscaler-prod`（base は PR #56 をマージした master の `a1f11db`）。`git status --short assets porkadot.yaml` は空 |
| 入れる版（§1.5。10:16Z） | `cpa/cluster-proportional-autoscaler:v1.11.0` は manifest list で amd64・arm・arm64・ppc64le・s390x。`cluster-proportional-autoscaler-amd64:1.7.1` の manifest は 200（§7 の戻しで取れる） |

## 2. ベースライン（runbook §2.2。10:16:15Z の `snap.sh`、10:16:28Z の `node-state.sh`）

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node と taint | 8 台 Ready、v1.37.1、cordon されたものは無い。taint は control-plane 3 台が `node-role.kubernetes.io/master:NoSchedule`、braque が `unstable.cloud/storage:NoSchedule`、chirico・duchamp・oeilvert・pablo は無い |
| 2 | 全 Pod | 168 個（Running 145、Succeeded 23）。名前・UID・restartCount は `notes/dns-autoscaler-1-11/base/pods.txt` |
| 3 | autoscaler の Deployment | generation 4、revision 2、1/1。イメージ `registry.k8s.io/cluster-proportional-autoscaler-amd64:1.7.1`。テンプレートの注釈 `seccomp.security.alpha.kubernetes.io/pod: docker/default`、Pod の securityContext は `fsGroup: 65534`・`supplementalGroups: [65534]` だけ。tolerations は `CriticalAddonsOnly`、nodeSelector は `kubernetes.io/os: linux`、affinity は無い。strategy は RollingUpdate（25%・25%）、revisionHistoryLimit 10 |
| 4 | autoscaler の Pod | chirico の `kube-dns-autoscaler-cc5758b6f-dhc95`（UID `7dea208a-af72-4b2e-b9c1-f56c948385c5`、restart 0、2026-10-19 09:35:32Z 起動、Pod IP `10.244.8.242`）。ログは起動の 6 行だけ（`Params from apiserver: {"coresPerReplica":256,"nodesPerReplica":16,"preventSinglePointFailure":true}`、`Defaulting min replicas count to 1`）。エラー・`Forbidden` は無い |
| 5 | autoscaler の ReplicaSet | `kube-dns-autoscaler-cc5758b6f`（1/1、`registry.k8s.io/…-amd64:1.7.1`）と `kube-dns-autoscaler-64bc6d94b9`（0、`k8s.gcr.io/…-amd64:1.7.1`） |
| 6 | 今の Pod の seccomp（`seccomp.sh 192.168.1.83`） | `status.seccomp` は無い、OCI spec に `linux.seccomp` が無い、`Seccomp: 0`・`Seccomp_filters: 0`・`NoNewPrivs: 0`。seccomp なしで動いている |
| 7 | ConfigMap `kube-system/kube-dns-autoscaler` | `data.linear` が `{"coresPerReplica":256,"nodesPerReplica":16,"preventSinglePointFailure":true}`。2018-10-23 作成、resourceVersion `901196490`、注釈も managedFields も無い |
| 8 | CoreDNS | Deployment `coredns` の generation 13、replicas 2、2/2。Pod は `coredns-76d7d8dc86-469lz`（duchamp、UID `f0d31e8b-…`、restart 7）と `coredns-76d7d8dc86-shdgn`（chirico、UID `a7417640-…`、restart 5）、どちらも 2026-10-21 13:04:32Z 起動。`coredns` の events は無い |
| 9 | 計算される replicas | Ready・schedulable のノード 8 台、allocatable の CPU は .111〜.113・braque・pablo が 4、chirico 16、duchamp・oeilvert 8 で合計 52。nodes ⌈8/16⌉ = 1 → `preventSinglePointFailure` で 2、cores ⌈52/256⌉ = 1。大きいほうの 2 で、今の replicas と同じ |
| 10 | RBAC | ClusterRole `system:kube-dns-autoscaler` は `nodes` の list・watch、`replicationcontrollers/scale` の get・update、`apps` の `deployments/scale`・`replicasets/scale` の get・update、`configmaps` の get・create（resourceVersion `1052851795`）。ClusterRoleBinding は ServiceAccount `kube-system/kube-dns-autoscaler` に結ぶ（`901197433`）。ServiceAccount は `1192412310` |
| 11 | kubelet（`node-state.sh`） | .111 MainPID 752609・NRestarts 0・10-23 22:44:11Z、.112 1028・1・10-24 12:11:32Z、.113 612672・0・10-23 22:44:11Z、braque 541944・0・10-23 22:44:45Z、chirico 3237977・0・10-23 22:44:34Z、duchamp 202232・0・10-23 22:44:40Z、oeilvert 916805・51・10-23 22:53:21Z、pablo 3509679・0・10-23 22:44:38Z（control-plane の時刻は JST の表示を UTC に直した。MetalLB のベースラインと同じ） |
| 12 | containerd の autoscaler のイメージ | `registry.k8s.io/cluster-proportional-autoscaler-amd64:1.7.1`（`14afc47fd5aff`）が chirico・duchamp・pablo にある（duchamp には `k8s.gcr.io/…` の同じイメージも）。oeilvert・braque・control-plane には無い。v1.11.0 はどの台にも無い |
| 13 | `:8080` | oeilvert から Pod IP の `10.244.8.242:8080/healthz` が接続できない（`Couldn't connect to server`）。1.7.1 は聞いていない |
| 14 | DNS | §3 の `dns-watch.sh` の最初の 1 分で FAIL 0（§3） |
| 15 | kube-system の NetworkPolicy | 無い |
| 16 | VIP | `https://192.168.1.101:6443/readyz` が 200 |

## 3. 監視（runbook §2.3）

10:16:47Z に、ハーネスのバックグラウンド実行で 2 つのジョブとして起動した（bg1: `dns-watch.sh`、bg2: `dns-replicas-watch.sh`）。`nohup`・`&` は使っていない。ログはタスクディレクトリの `notes/dns-autoscaler-1-11/logs/`（`dns.log`、`dns-replicas.log`）。

## 4. etcd のバックアップ（runbook §2.4）

10:16:55Z〜10:16:58Z に、porkadot 0.37.3 の `etcd backup` を worktree のルートで流した（rc 0。出力は `notes/dns-autoscaler-1-11/etcd-backup.log`）。.111 の etcdctl で取ってダウンロードしている。流した後も `git status --short` は空。

| ファイル | 置き場所 | バイト | sha256 |
|---|---|---|---|
| `etcd-2026-10-25T10:16:55+00:00.db`（モード 0600） | worktree `dns-autoscaler-prod` の `./backup/`（git には入れない） | 55,107,616 | `3a928c55a66a1d53ebe06480ae94ebacd40458f9b9f95607015977f3e53107bd` |

サイズはメインの checkout の `backup/etcd-2026-10-25T02:08:18+00:00.db`（MetalLB の前、55,107,616 B）と同じ。worktree を片付ける前に、メインの checkout の `backup/` へ写す（coordinator）。
