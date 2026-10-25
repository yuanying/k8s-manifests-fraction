# MetalLB v0.16.1 のベースライン

本番 `fraction` の MetalLB を v0.14.5 から v0.16.1 へ上げる（porkadot 0.37.1 → 0.37.2）前に取った、読み取りの結果、etcd のバックアップ、イメージの事前 pull の記録。手順は `../../runbook-metallb-0.16.md`（以下 runbook）。
時刻は UTC。`snap.sh`・`node-ports.sh` の出力と speaker・controller のログの写しは、タスクディレクトリの `notes/metallb-0-16/base/` に置いた（リポジトリには入れない）。

## 1. 前提（runbook §1。2026-10-25 02:06Z〜02:07Z）

| 項目 | 結果 |
|---|---|
| 本番の今の姿（§1.1） | runbook §1.1 のとおり。8 台 Ready、v1.37.1、`containerd://2.3.6`。Pod 169 個（Running 145、Succeeded 24） |
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `infra-auditor`（`system:serviceaccounts:kube-system`）。`auth can-i delete pods -A` は `no`。作業端末の kubectl は v1.37.1 |
| SSH（§1.3） | サンドボックスの中から、8 台に IP で `node-ports.sh` を流せた |
| porkadot（§1.4） | `worktrees/porkadot-v0-37-2` は `git describe --tags` が `v0.37.2`（`020c7c7`）、作業ツリーに変更が無い。`porkadot help` が動く。§7 の戻しの `worktrees/porkadot-v0-37-1` は `v0.37.1`。cwd は worktree `metallb-0-16-prod`（base は PR #54 をマージした master の `ea99bf8`）。`git status --short assets porkadot.yaml` は空 |
| 入れる版（§1.5。02:06Z） | MetalLB の tag は v0.16.1、v0.16.0、v0.15.3 の順。`quay.io/metallb/speaker:v0.16.1`・`controller:v0.16.1` は amd64・arm64・s390x・ppc64le・arm を含む |

## 2. ベースライン（runbook §2.2。02:07:04Z の `snap.sh`、02:07:16Z の `node-ports.sh`）

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node と taint | 8 台 Ready、v1.37.1。taint は control-plane 3 台が `node-role.kubernetes.io/master:NoSchedule`、braque が `unstable.cloud/storage:NoSchedule`、chirico・duchamp・oeilvert・pablo は無い。`nvidia.com/gpu` の taint を持つノードは無い |
| 2 | 全 Pod | 169 個（Running 145、Succeeded 24）。Running / Succeeded 以外は 0 個。名前・UID・restartCount は `notes/metallb-0-16/base/pods.txt` |
| 3 | speaker の DaemonSet | generation 22。desired 7、current 7、ready 7、available 7、updated 7、misscheduled 0 |
| 4 | speaker の配置 | .111 `speaker-xgnzb`（restart 6）、.112 `speaker-r4s5d`（7）、.113 `speaker-xcbcj`（5）、chirico `speaker-7fcfw`（20）、duchamp `speaker-nz58r`（18）、oeilvert `speaker-ph5z7`（17）、pablo `speaker-9fwg2`（17）。braque には無い |
| 5 | speaker の tolerations（live） | `node-role.kubernetes.io/master`、`node-role.kubernetes.io/control-plane`、`nvidia.com/gpu`（どれも `NoSchedule`・`Exists`）。nodeSelector は `kubernetes.io/os: linux`。managedFields の最後は `kube-controller-manager`（2026-10-24 12:40:07Z、status） |
| 6 | controller | Deployment の generation 18、1/1。pablo の `controller-7f974cb86-28grh`（restart 0、2026-10-19 08:09:58Z 起動） |
| 7 | LoadBalancer の Service | 11 個。`status.loadBalancer.ingress` は 11 個とも `spec.loadBalancerIP` と同じ（runbook §2.2 の表のとおり）。`metallb.universe.tf/loadBalancerIPs` の注釈はどれにも無い |
| 8 | Local の LoadBalancer の endpoint | gated-v4・gated-v6 は chirico と pablo（どちらも ready）。minecraft・minecraft2・minecraft3 の `bds` は endpoint が無い |
| 9 | 告知しているノード | speaker のログの最後の `serviceAnnounced`（JSON の `ts`。古いプレフィックスの行は除く）: VIP（`.101`）pablo（10-24 18:45:33Z）、gated-v4（`.200`）chirico（10-25 01:20:33Z）、gated-v6（`::200`）pablo（10-24 18:45:33Z）、`::131` .113（10-24 23:23:16Z）、`::132`・`::134` duchamp（10-25 00:02:04Z）、`::133` oeilvert（10-24 23:06:49Z）。runbook §2.2 の 9 と同じ |
| 10 | CRD と storedVersions | runbook §2.2 の表と同じ 8 つ。どれも storedVersions が 1 つ（`bgppeers` は `[v1beta2]`、ほかは `[v1beta1]`） |
| 11 | `addresspools` の件数 | 0 |
| 12 | MetalLB の CR | `ipaddresspools` 1（`first-pool`）、`l2advertisements` 1（`system`）。bgppeers・bgpadvertisements・bfdprofiles・communities・servicel2statuses は 0。`configurationstates`・`servicebgpstatuses` は API に無い（`the server doesn't have a resource type`） |
| 13 | ClusterRole・webhook | ClusterRole・ClusterRoleBinding `metallb-system:controller`・`metallb-system:speaker`、`mlb0-metallb:controller`・`mlb0-metallb:speaker`。ValidatingWebhookConfiguration `metallb-webhook-configuration`（webhook 6 つ）。MutatingWebhookConfiguration は無い |
| 14 | 全ノードのポート | speaker の 7 台で、speaker が `<ノード>:7946`（tcp・udp）と `<ノード>:7472`（tcp）。9120・17472 で聞いているプロセスは 8 台とも無い。braque は 4 つとも無い |
| 15 | kubelet | .111 MainPID 752609・NRestarts 0・10-23 22:44:11Z、.112 1028・1・10-24 12:11:32Z、.113 612672・0・10-23 22:44:11Z、braque 541944・0・10-23 22:44:45Z、chirico 3237977・0・10-23 22:44:34Z、duchamp 202232・0・10-23 22:44:40Z、oeilvert 916805・51・10-23 22:53:21Z、pablo 3509679・0・10-23 22:44:38Z（control-plane の時刻は JST の表示を UTC に直した） |
| 16 | containerd の MetalLB のイメージ（§2.5 の前） | `speaker:v0.14.5` は speaker の 7 台にある。`controller:v0.14.5` は chirico・duchamp・pablo にある（oeilvert には無い）。v0.16.1 はどの台にも無い。chirico・duchamp・pablo には v0.12.1・v0.13.9 の古いイメージも残る（duchamp に `controller:v0.13.9` は無い） |
| 17 | metrics を集めているか | Prometheus の active target の job は apiserver、coredns、gated-system/gated、grafana、kube-controller-manager、kube-etcd、kube-prometheus-alertmanager・operator・prometheus、kube-proxy、kube-scheduler、kube-state-metrics、kubelet、node-exporter で、MetalLB は無い。`metallb_*` の series は 0 個。`{namespace="metallb-system"}` は kubelet 1228、kube-state-metrics 514、job なし（recording rule）48。ServiceMonitor・PodMonitor・PrometheusRule に `metallb` は無い。ConfigMap は MetalLB の `metallb-excludel2` だけ |
| 18 | MetalLB のログ | controller の最後の error は 10-23 03:24:04Z の `IP allocation failed`（古いプレフィックス）。speaker の最後の error は 10-24 12:39:19Z〜12:39:34Z の `partial join`（`Failed to join 192.168.1.112:7946`。.112 以外の 6 台で 34〜35 回）。それより後の warn・error は無い。runbook §1.1 のとおり |
| 19 | 監視の対象が応答する | 02:08:11Z に起動した `probe.sh` の最初の 97 行（約 1 分 40 秒）がすべて `vip=200 v4=404 v6=404 ssh131=ok ssh132=ok` |

## 3. 監視（runbook §2.3）

02:08:11Z に、ハーネスのバックグラウンド実行で 2 つのジョブとして起動した（bg1: `probe.sh`、bg2: `ml-watch.sh`）。`nohup`・`&` は使っていない。ログはタスクディレクトリの `notes/metallb-0-16/logs/`（`probe.log`、`ml-watch.log`、`pods/`）。

## 4. etcd のバックアップ（runbook §2.4）

02:08:18Z〜02:08:22Z に、porkadot 0.37.2 の `etcd backup` を worktree のルートで流した（rc 0。出力は `notes/metallb-0-16/etcd-backup.log`）。.111 の etcdctl で取ってダウンロードしている。

| ファイル | 置き場所 | バイト | sha256 |
|---|---|---|---|
| `etcd-2026-10-25T02:08:18+00:00.db`（モード 0600） | worktree `metallb-0-16-prod` の `./backup/`（git には入れない） | 55,107,616 | `77560f5fcead180fe937da90a4240496e0fbc89cf705fdf14252bda3b01655cb` |

サイズはメインの checkout の `backup/etcd-2026-10-23T22:41:23+00:00.db`（段 8 の最後、55,107,616 B、sha256 `d27e68b6…`）と同じ（bbolt のファイルの大きさが同じ。中身は別）。worktree を片付ける前に、メインの checkout の `backup/` へ写す（coordinator）。

## 5. イメージの事前 pull（runbook §2.5。02:08:38Z〜02:09:39Z）

1 台ずつ IP で入り、`sudo /opt/bin/crictl pull` を流した（rc は 11 回とも 0）。時間は ssh を含む。

| ノード | speaker:v0.16.1 | controller:v0.16.1 |
|---|---|---|
| .111 | 6.4 秒 | — |
| .112 | 7.0 秒 | — |
| .113 | 6.1 秒 | — |
| chirico | 5.9 秒 | 4.3 秒 |
| duchamp | 7.2 秒 | 4.3 秒 |
| oeilvert | 4.5 秒 | 3.3 秒 |
| pablo | 6.4 秒 | 4.8 秒 |

02:09:54Z の `node-ports.sh`（`notes/metallb-0-16/prepull/`）で、7 台に `speaker:v0.16.1`（arm64 `f29acc9f6465`、amd64 `99cea31eb93c`）、worker 4 台に `controller:v0.16.1`（`5e1d13fb5c2d`）があることを確かめた。braque には pull していない。
