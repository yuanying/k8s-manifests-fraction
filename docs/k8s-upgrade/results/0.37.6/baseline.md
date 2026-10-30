# porkadot 0.37.6 のベースライン

本番 `fraction` の K8s を v1.37.1 → v1.37.2、CoreDNS を v1.14.7 → v1.15.0 へ上げる（porkadot 0.37.5 → 0.37.6）前に取った、読み取りの結果と etcd のバックアップ、イメージの事前 pull の記録。手順は `../../runbook-0.37.6.md`（以下 runbook）。
時刻は UTC。スクリプトの出力は、タスクディレクトリの `notes/0-37-6/base/` に置いた（リポジトリには入れない）。

## 1. 前提（runbook §1。2026-10-30 11:05〜11:09Z）

| 項目 | 結果 |
|---|---|
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor`。作業端末の kubectl は v1.37.1 |
| SSH（§1.3） | サンドボックスの中から、8 台に IP で `nodes.sh`、.111 に `etcd-check.sh`、oeilvert に `endpoints.sh`・`dns-check.sh`、chirico・oeilvert に `seccomp.sh` を流せた |
| porkadot（§1.4） | `worktrees/porkadot-v0-37-6` は `git describe --tags` が `v0.37.6`、作業ツリーに変更が無い。`porkadot help` が動く。§7 の戻しの `worktrees/porkadot-v0-37-5` は `v0.37.5`。cwd は worktree `0-37-6-prod`（base は PR #72 をマージした master の `1573b0f`）。`git status --short assets porkadot.yaml` は空。`porkadot.yaml` の `nodes` のキーは `192.168.1.111`〜`113`、`pablo`、`duchamp`、`braque`、`oeilvert`、`chirico` |
| 入れる版（§1.5。11:08Z） | `stable-1.37.txt`・`stable.txt` とも v1.37.2。`kube-apiserver`・`kube-controller-manager`・`kube-scheduler`・`kube-proxy` の v1.37.2 は amd64・arm64・ppc64le・s390x。`coredns/coredns:v1.15.0` は 200（amd64・arm・arm64・loong64・ppc64le・riscv64・s390x）、v1.15.1 は 404、tags/list の v1.15 以降は v1.15.0 だけ。GitHub の CoreDNS の最新のリリースも v1.15.0。`dl.k8s.io` の kubelet・kubectl の v1.37.2（amd64・arm64）は 4 つとも 200 |
| 時間帯（§2.11） | 11:05Z に始めた（10:00〜17:30Z の枠） |

## 2. ベースライン（runbook §2.2。11:05:10〜11:09Z）

**runbook §2.2 の表の値（09:4x〜09:5xZ）と、すべての項目で同じだった**（Longhorn のボリュームのアタッチ先、MetalLB の告知ノードを含む）。差は storage version のキーの数（2486 → 2458。Event などの増減）だけ。

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node | 8 台 Ready・schedulable、全台 v1.37.1、`containerd://2.3.6` |
| 2 | Pod | 164 個（Running 140、Succeeded 24）。Running / Completed 以外は 0 個。名前・UID・restartCount は `base/pods.txt` |
| 3 | kube-system の generation とイメージ | DaemonSet `kube-apiserver` 31（v1.37.1、3）、`kube-proxy` 27（v1.37.1、8）、`cnidaria` 4（v0.1.2）。Deployment `kube-controller-manager` 30・`kube-scheduler` 29（v1.37.1、2）、`coredns` 14（v1.14.7、2）、`kube-dns-autoscaler` 5（v1.11.0）、`metrics-server` 2（v0.9.0） |
| 5 | etcd | 3/3 healthy、3 台とも 3.7.3・storage 3.7.0。リーダーは .113（`57ec6f12ac7b683e`）、raft term 23127。DB 75〜76 MB（in use 31 MB）。フラグは runbook と同じ。直近 10 分の warn 以上は 0。コンテナの起動は .111 10-24 07:40:02 JST、.112 10-24 21:11:33 JST、.113 10-24 07:35:09 JST |
| 6 | `/opt/bin` | 8 台とも `kubelet-v1.37.1`、`kubectl-v1.37.1`、`crictl-v1.37.0`、`etcdctl-3.7.3`、`etcdutl-3.7.3` |
| 7 | kubelet | MainPID・NRestarts: .111 752609・0、.112 1028・1、.113 612672・0、braque 541944・0、chirico 3237977・0、duchamp 1303・1、oeilvert 916805・51、pablo 3509679・0（起動の時刻も runbook と同じ） |
| 8 | `cpu_manager_state` | 8 台とも policy `none`、checksum 1353318690 |
| 9 | iscsid と iSCSI | .111 522641、**.112 0（動いていない）**、.113 290821、braque 271131、chirico 3144486、duchamp 3589、oeilvert 912599、pablo 4114921。セッションは chirico 9（portal `10.244.8.60`）、duchamp 6（`10.244.5.89`）、oeilvert 1（`10.244.7.224`）、ほかは 0。`older-than-iscsid` は duchamp の `pvc-3a665d04` の 1 本 |
| 10 | Longhorn | ボリューム 17（attached healthy 16、detached unknown 1 の `pvc-0fac3150`＝`natsumi-penelope`）、エンジンは 17 本とも v1.13.0。アタッチ先は chirico 9、duchamp 6、oeilvert 1、pablo 0 |
| 11 | CPU | duchamp `no_turbo` 1・最高温度 55℃、pablo `no_turbo` 1、braque 0 |
| 12 | `nf_conntrack_max` | control-plane 3 台・braque・pablo 131072、duchamp・oeilvert 262144、chirico 524288 |
| 13 | CoreDNS の Pod | `coredns-6bfc79bb8-6gkk5`（chirico、`10.244.8.201`、UID `2304e87a-…`）と `coredns-6bfc79bb8-n75n5`（oeilvert、`10.244.7.65`、UID `f15249d1-…`）、restart 0。autoscaler は `kube-dns-autoscaler-5959bf78f6-pnh8z`（oeilvert、restart 0）。replicas 0 の古い ReplicaSet は 10 個（revision 1 は `coredns-76bd8dbd8c` の 1.6.7） |
| 14 | CoreDNS の seccomp | 2 つとも CRI の `security_context.seccomp` が `{}`、OCI spec の `linux.seccomp` が `SCMP_ACT_ERRNO`・規則 13、`Seccomp: 2`・`Seccomp_filters: 1`、`CapEff` `0x400` |
| 15 | Corefile とログ | resourceVersion `1239255997`、SHA512 `dbda5533…`。ログは起動の 5 行ずつで error・warn・fatal・loop は 0 |
| 16 | 各 Pod の答え（`endpoints.sh`） | 2 つの Pod とも UDP・TCP で runbook §2.2 の 16 と同じ答え。`:8080/health`・`:8181/ready`・`:9153/metrics` が 200、`coredns_build_info{goversion="go1.26.6",revision="427fc80",version="1.14.7"}` |
| 17 | `tools/dns-check.sh yuanying@192.168.1.82` | Service と 2 つの Pod の答えが同じ（54 行） |
| 19 | containerd のイメージ | どのノードにも v1.37.2 と CoreDNS v1.15.0 は無い |
| 20 | storage version | `prefixes: 70, keys: 2458, OLD: 0, CRDs with more than one stored version: 0` |
| 21・22・23 | cgroup・resolv.conf・unattended-upgrades | 8 台とも `cgroup2fs`、10.254.0.10 が resolv.conf に入っている（並びは runbook と同じ）。`-security` の更新・`reboot-required` は無い |
| 24 | MetalLB の告知ノード（直近 7 日の最後の `serviceAnnounced`） | VIP（.101）pablo（10-30 05:49Z）、gated-v4（.200）・gated-v6（`::200`）・`::133` oeilvert（07:53Z）、`::131` .113、`::132`・`::134` duchamp。LoadBalancer は 12 |
| 27 | VIP | VIP と .111〜.113 の `/readyz` が 200 |
| 28 | CSR | 無い |
