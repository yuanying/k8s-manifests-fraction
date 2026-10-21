# 段 6 のベースライン

本番 `fraction` の段 6（K8s 1.34.12 → 1.35.9、CoreDNS v1.12.4 → v1.13.2、porkadot 0.35.0）に入る前に取った、クラスタ全体の読み取りの結果、etcd のバックアップ、storage version、cgroup、resolv.conf、unattended-upgrades の確認の記録。手順は `../../runbook-stage-6.md`（以下 runbook）。
時刻は UTC。1 台ごとの確認は、この記録と比べる。読み取りの出力はタスクディレクトリの `notes/stage-6/baseline/` に置いた（リポジトリには入れない）。全 Pod の名前・UID・restartCount の控えは同じ場所の `pods.tsv`、8 台の `tools/node-state.sh` の出力は `node-<ノード>-before.txt`、etcd の詳細は `etcd-*-base.txt`、8 台の OS の読み取り（cgroup、resolv.conf、unattended-upgrades）は `notes/stage-6/node-os-1.txt` と `node-os-pablo-1.txt`。

## 1. 前提（runbook §1）

| 項目 | 結果 |
|---|---|
| 段 5 と Longhorn の更新（§1.1） | `results/stage-5/summary.md` に完了の確認がある。Longhorn は `current-longhorn-version` v1.13.0、engine image `longhorn-engine:v1.13.0` だけが deployed、アタッチされた 16 本のエンジンの `status.currentImage` が v1.13.0（detached の `cg-data` は `spec.image` が v1.13.0）。Longhorn の片付け（work-longhorn-cleanup-prod）は #45 で済んでいる（coordinator の STATE） |
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor` |
| porkadot（§1.4） | (a) の独立の clone `worktrees/porkadot-v0-35-0` が `v0.35.0`（`e4aa3e6`、detached）、`lib/porkadot/version.rb` が 0.35.0。Ruby 4.0.7。`porkadot help` が動く。cwd は段 6 の worktree（`stage-6-k8s-1-35` のブランチ。base は PR #46 をマージした master の `6272eb3`）。`git status --short assets porkadot.yaml` は空。§7 の戻しに使う 0.34.1 は元の clone（`porkadot-dev/porkadot`、v0.34.1）のまま |
| SSH（§1.3、§1.4。06:39Z） | サンドボックスの中（`ssh-add -l` は `Error connecting to agent: Operation not permitted`）から、porkadot 0.35.0 を `require` した SSHKit で 8 台に `hostname` を流し、8 台とも `rasp01`〜`rasp03`、`pablo`、`duchamp`、`braque`、`chirico`、`oeilvert` を返した |
| 入れる版（§1.7。06:39Z） | `stable-1.35.txt` は v1.35.9（`stable.txt` は v1.37.1） |
| 作業端末の kubectl | v1.34.12 |
| 監視（§2.3） | 06:39:40Z に作業端末で VIP と LB の監視を開始。ログはタスクディレクトリの `notes/stage-6/stage-6-probe.log`。etcd の health の 2 秒ごとの監視は `install kubernetes` の前に始める |

## 2. クラスタ全体のベースライン（runbook §2.2。2026-10-21 06:41Z〜06:45Z）

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node、版 | 8 台 Ready。全台 v1.34.12、`containerd://2.3.6`。Server Version v1.34.12 |
| 2 | `tools/node-state.sh` の `bin` と `cni` | 8 台とも `kubelet-v1.34.12`、`kubectl-v1.34.12`、`crictl-v1.34.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と bridge・host-local・portmap・loopback が 8 台とも `v1.9.1` |
| 3 | `/etc/etcd/pki` | 3 台とも `ca.crt`・`etcd.crt`・`etcd.key` が `600 root:root` |
| 4 | etcd、VIP | 3/3 healthy、3 台とも 3.6.15、STORAGE VERSION 3.6.0、DB 55 MB（in use 約 18 MB）。リーダーは **192.168.1.112（`fbb0c648cf5852a5`）**。raft term 23122、raft index 1403504714〜715 でそろう。`header.revision` は **1,238,129,610**（§7.4 の restore の目安）。ID は .111 `21ab2aeb56731588`、.113 `57ec6f12ac7b683e`。`member list` は 3 つとも `started`。VIP の `/readyz` は `ok`、`/version` は v1.34.12 |
| 4 | etcd の `/version` | 3 台とも `{"etcdserver":"3.6.15","etcdcluster":"3.6.0","storage":"3.6.0"}` |
| 4 | 動いている etcd のフラグ | 3 台とも `--feature-gates=InitialCorruptCheck=true`、`--watch-progress-notify-interval=5s`、`--snapshot-count=10000` があり、`--experimental-` で始まるものは無い。プロセスの環境に `ETCD_*` は無い |
| 4 | etcd の Pod のログの warn の種類 | 3 台とも `check file permission`、`Running http and grpc server on single port`、`simple token is not cryptographically signed`、`found invalid file under data directory`、`apply request took too long`（.111 35、.112 11、.113 31）。.111 は段 5 の 3.6 の起動の直後の `failed to publish local member to cluster through raft`（43）、.112 は `ignored file in WAL directory`（段 5 の `.wal.broken`）、.112・.113 は段 5 の起き直しのときの `lost TCP streaming connection`・`peer became inactive`、.113 は `closed TCP streaming connection`・`request stats`・`waiting for ReadIndex response took too long`・`ignored out-of-date read index response`（各 1〜4）。error は無い |
| 5 | Running / Completed 以外の Pod | 0 個 |
| 5 | 全 Pod の名前・UID・restartCount | `notes/stage-6/baseline/pods.tsv` に控えた（165 個。§6 で「増えていない」ことを見る元） |
| 6 | Longhorn のボリューム | attached healthy 16、detached unknown 1（`homegallery/cg-data`。以前から）。degraded は 0 |
| 6 | Longhorn の replica | chirico 9（running 8、stopped 1）、duchamp 12（running 12）、oeilvert 9（running 8、stopped 1）、pablo 2（running 2） |
| 6 | instance-manager、engine image、node | instance-manager 7 つとも running: pablo `-17a539db…`（10.244.4.131）と `-b510f391…`（10.244.4.197）、chirico `-4128231c…`（10.244.8.216）と `-ed03b277…`（10.244.8.60）、duchamp `-134f259c…`（10.244.5.186）、oeilvert `-d5905a9e…`（10.244.7.116）と `-2cd5c267…`（10.244.7.198）。engine image は `longhorn-engine:v1.13.0`（`ei-2f3240cb`）だけが deployed。Longhorn の node 4 つとも Ready、schedulable |
| 7 | cnidaria | `verify-nodes.sh` は 8 台とも exit 0（§5 の注: nft を流すイメージを v0.1.1 にした写しで流した）。cnidaria の Pod のログの error / `no route` は .111 8/29、.112 8/29、.113 16/34、braque 14/33、chirico 8/28、duchamp 14/33、oeilvert 0/23、pablo 6/24（段 5 の `install kubelet` と Longhorn の更新の間のもの。各台の前と後の差で見る）。`check-apps.sh`: nodes 8/8、Running でない Pod 0、IP の重複 0、Longhorn 16 attached healthy・1 detached unknown、192.168.1.200 と v6 の LB は 404、VIP の `/version` は 200 |
| 7 | NetworkPolicy | `longhorn-system` の 6 つ（Longhorn v1.13.0 のもの）だけ。確かめるのは §1.9 の一時的な名前空間で |
| 8 | MetalLB | gated の `192.168.1.200` と `[...:ace::200]` の 80 は 404（応答あり）。`::131`〜`::134` の 3222 は SSH のバナーを返す |
| 9 | NFS | oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で、中身が読める。braque は 2049 を listen している。`registry.fraction.jp/v2/` は 401（応答あり） |
| 10 | metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個 |
| 11、15 | controller-manager と scheduler | controller-manager は .111（`-cs97f`）と .112（`-gz9wf`、リーダー）。scheduler は .113（`-mmpr7`、リーダー）と .111（`-xkbzx`） |
| 12 | CSR | 無い |
| 12 | kubelet の serving の証明書 | 8 台とも subject `O = system:nodes, CN = system:node:<ノード名>`。期限は CP 3 台が 2027-10-16、braque 2027-08-18、chirico 2027-06-23、duchamp 2027-09-06、oeilvert 2027-03-20、pablo 2027-08-08 |
| 13 | kube-system の Deployment と DaemonSet、approver | 下の表。approver は `kubelet-serving-cert-approver-7d5f768656-hls26`（oeilvert） |
| 14 | Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit` `5`、`replica-auto-balance` `disabled`、`node-drain-policy` `block-if-contains-last-replica`、`default-data-locality` `best-effort`、`replica-replenishment-wait-interval` `6000`、`current-longhorn-version` v1.13.0。どれも APPLIED が true |
| 16 | MetalLB の告知ノード | 下の表 |
| 17 | leader election を使う controller の再起動回数 | `gated-system/gated` の 2 つ（chirico、oeilvert）は 0。`longhorn-system` の CSI sidecar 12 個は `csi-attacher-…-s6fmv`（oeilvert）が 1、ほかは 0 |
| 18 | Longhorn のボリュームのアタッチ先と iSCSI | 下の表 |
| 20 | storage version | `prefixes: 65, keys: 2362, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は空。出力はタスクディレクトリの `notes/stage-6/sv-20261021T0644Z/` |
| 21 | `apiserver_requested_deprecated_apis` | `endpoints`（v1）と `metallb.io/v1beta1 addresspools`。`removed_release` はどれも空 |
| 22 | Longhorn の PVC を使う Running と Completed の Pod（runbook §8.12） | **7 つ当たる**（下の表）。NFS の `aphrael/aphrael-2` の `tumblr-like` の 3 つは当たらない |
| 23 | CoreDNS の答え（v1.12.4。06:45Z） | `tools/dns-check.sh` の出力は `notes/stage-6/baseline/dns-check.txt`。Service（10.254.0.10）と 2 つの Pod（10.244.8.16 chirico、10.244.5.129 duchamp）で同じ答え。runbook §3.3 の 13 の表の v1.12.4 の列と同じ。2 つの Pod のログは `CoreDNS-1.12.4` だけで、`[ERROR]`・`[WARNING]`・`loop` は無い。restartCount 0 |
| 24 | Service の数 | 79 個。ClusterIP を持つもの 71 個（うち dual-stack 3 個）、ClusterIP の数 74。IPAddress 74。ServiceCIDR は `kubernetes`（`10.254.0.0/24,fd20:afc2:7c09::/108`）の 1 つ |
| 25 | Prometheus のスクレイプ | `count by (job) (up)` の `apiserver` 3、`kube-etcd` 3、`count(etcd_server_has_leader)` 3 |
| 26 | cgroup（runbook §2.9） | §3 |
| 27 | resolv.conf（runbook §2.10） | §4 |
| 28 | unattended-upgrades（runbook §2.11） | §5 |
| 29 | FlowSchema | 11 個。`system-leader-election` が generation 8、ほかの 10 個は 1 |

kube-system の Deployment と DaemonSet（§2.2 の 13）:

| KIND | NAME | GEN | IMAGE |
|---|---|---|---|
| Deployment | coredns | 11 | `coredns/coredns:v1.12.4` |
| Deployment | kube-controller-manager | 27 | `kube-controller-manager:v1.34.12` |
| Deployment | kube-dns-autoscaler | 4 | `cluster-proportional-autoscaler-amd64:1.7.1` |
| Deployment | kube-scheduler | 26 | `kube-scheduler:v1.34.12` |
| Deployment | metrics-server | 1 | `metrics-server/metrics-server:v0.7.2` |
| DaemonSet | cnidaria | 3 | `ghcr.io/yuanying/cnidaria-cni:v0.1.1` |
| DaemonSet | kube-apiserver | 28 | `kube-apiserver:v1.34.12` |
| DaemonSet | kube-proxy | 24 | `kube-proxy:v1.34.12` |

MetalLB の告知ノード（speaker のログの IP ごとの最後の `serviceAnnounced`）。段 5 の完了の確認と同じ:

| Service | アドレス | 告知ノード |
|---|---|---|
| `kube-system/porkadot-kubernetes`（API の VIP） | 192.168.1.101 | **pablo** |
| `gated-system/gated-v4` | 192.168.1.200 | chirico |
| `gated-system/gated-v6` | `::200` | oeilvert |
| `fs/h2-sshd` | `::131` | 192.168.1.112 |
| `natsumi/natsumi-sshd` | `::132` | 192.168.1.111 |
| `natsumi/natsumi-sshd-myao` | `::133` | duchamp |
| `natsumi/natsumi-sshd-aki` | `::134` | 192.168.1.112 |

各ノードの iscsid、iSCSI のセッション、エンジン（`tools/node-state.sh`、06:41Z〜06:42Z）:

| ノード | iscsid（MainPID、起動） | セッション（portal） | `older-than-iscsid` | アタッチされたボリューム | `initiatorname.iscsi` |
|---|---|---|---|---|---|
| 192.168.1.111 | 90734、10-19 07:31:09Z | 0 | — | なし | assets と同じ（md5） |
| 192.168.1.112 | 89578、10-19 07:27:57Z | 0 | — | なし | 同じ |
| 192.168.1.113 | **290821、10-20 21:30:04Z**（unattended-upgrades。§5） | 0 | — | なし | 同じ |
| braque | **271131、10-21 06:23:32Z**（unattended-upgrades。§5） | 0 | — | なし | 同じ |
| pablo | **4114921、10-21 06:40:42Z**（unattended-upgrades。§5） | 1（10.244.4.131 = 今の instance-manager） | **1** | `fs/sites` | 同じ |
| oeilvert | 6334、10-19 09:04:34Z | 2（10.244.7.116 = 今の instance-manager） | 0 | 2 | 同じ |
| duchamp | **2695716、10-21 06:08:00Z**（unattended-upgrades。§5） | 4（10.244.5.186 = 今の instance-manager） | **4** | 4 | 同じ |
| chirico | 4447、10-19 09:17:30Z | 9（8 つが 10.244.8.216、1 つが 10.244.8.60。どちらも今の instance-manager） | 0 | 9 | 同じ |

- 古いセッション（今の instance-manager の IP でない portal）は無い
- `older-than-iscsid` のエンジンは、pablo の 1 つと duchamp の 4 つ。どれも iscsid が unattended-upgrades で再起動する前に起動したもの（エンジンは v1.13.0 なので止める理由にしない。runbook §2.7）。各台の前と後で数が変わらないことを見る
- アタッチ先: chirico 9（`homegallery/tumblr-data`・`ero-data`、`fs/data`・`fs/h2`、`monitoring/prometheus-…-1`、`fraction-agents` の 4 つ）、duchamp 4（`natsumi/natsumi`・`natsumi-aki`・`natsumi-myao`、`monitoring/prometheus-…-0`）、oeilvert 2（`fraction-agents` の 2 つ）、pablo 1（`fs/sites`）。runbook §2.7 の 06:1xZ の読み取りと同じ
- replica 1 のボリューム: `prometheus-…-0`（replica もアタッチも duchamp）、`prometheus-…-1`（replica もアタッチも chirico）。drain しないので、止めない
- worker の順は runbook §5.1 のまま **pablo → braque → oeilvert → duchamp → chirico**（アタッチの数 1、0、2、4、9）

runbook §8.12 に当たる Pod（Running の Pod と同じ Longhorn の PVC を使う Succeeded の Pod。PV の `spec.csi.driver` はどれも `driver.longhorn.io`）:

| Succeeded の Pod | ノード | Job（持ち主） | PVC | Running の Pod（ノード） |
|---|---|---|---|---|
| `fraction-agents/deep-researcher-backup-29875500-z8gc4` | chirico | CronJob の 10-20 21:00Z の Job | `data-deep-researcher-0` | `deep-researcher-0`（chirico） |
| `natsumi/natsumi-backup-29875470-fm6xs` | oeilvert | CronJob の 10-20 20:30Z の Job | `natsumi` | `natsumi-0`（duchamp） |
| `natsumi/natsumi-backup-before-v0152-wg7pp` | oeilvert | CronJob から 10-21 05:33Z に作られた Job | `natsumi` | 同上 |
| `natsumi/natsumi-backup-aki-29875470-p8nj6` | oeilvert | CronJob の 10-20 20:30Z の Job | `natsumi-aki` | `natsumi-aki-0`（duchamp） |
| `natsumi/natsumi-backup-aki-before-v0152-kv7kg` | oeilvert | CronJob から 10-21 05:33Z に作られた Job | `natsumi-aki` | 同上 |
| `natsumi/natsumi-backup-myao-29875470-cfrfk` | chirico | CronJob の 10-20 20:30Z の Job | `natsumi-myao` | `natsumi-myao-0`（duchamp） |
| `natsumi/natsumi-backup-myao-before-v0152-rrg74` | chirico | CronJob から 10-21 05:33Z に作られた Job | `natsumi-myao` | 同上 |

- runbook §5.2（段 4 の手順書 §5.2 の 1）のとおり、Running の Pod のあるノードの `install kubelet` の前に、名前を知らせてから消す: duchamp の前に natsumi の 6 つ、chirico の前に `deep-researcher-backup-…`。Job と CronJob には触らない

ほかに読んだもの:

- Warning のイベントは、Liveness / Readiness の probe の失敗が 6 件（`natsumi/natsumi-0` 05:5xZ、`carib2`・`shja2`・`pondo2` の `movies` 06:0xZ〜06:1xZ）。段 6 の作業の前のもので、各台の前と後で増えたものを見る
- CronJob は `notes/stage-6/baseline/cronjobs.txt`

## 3. cgroup（runbook §2.9。06:39Z〜06:41Z）

8 台とも `stat -fc %T /sys/fs/cgroup` が **`cgroup2fs`**。systemd は 8 台とも 255（255.4-1ubuntu8.18）、kernel の引数に `systemd.unified_cgroup_hierarchy` は無い。止める条件（`tmpfs`）に当たらない。

## 4. resolv.conf（runbook §2.10。06:39Z〜06:41Z）

8 台とも kubelet の `resolvConf` は `/run/systemd/resolve/resolv.conf` で、nameserver の並びは runbook §2.10 の表と同じ（8 台とも kube-dns の 10.254.0.10 が入っている）。

| ノード | nameserver（並び順） |
|---|---|
| 192.168.1.111、braque、pablo | 192.168.0.1、2405:6581:8580:301::1、10.254.0.10 |
| 192.168.1.112、192.168.1.113、chirico、duchamp | 10.254.0.10、192.168.0.1、2405:6581:8580:301::1 |
| oeilvert | 192.168.0.1、10.254.0.10、192.168.0.1 |

前からのもので、段 6 は止めない（runbook §2.10、§8.16）。§2 の 23 のとおり、CoreDNS の 2 つの Pod のログに `loop` は無い。

## 5. unattended-upgrades と iscsid（runbook §2.11。06:39Z〜06:41Z）

| ノード | 今日の実行（UTC） | liblzma5 | iscsid の再起動 | 次の `apt-daily-upgrade.timer`（UTC） |
|---|---|---|---|---|
| 192.168.1.111 | 10-20 21:34Z（JST 06:34） | 0.3（0.4 が upgradable） | なし | 10-21 21:34:55Z |
| 192.168.1.112 | 10-20 21:34Z（JST 06:34） | 0.3（0.4 が upgradable） | なし | 10-21 21:18:41Z |
| 192.168.1.113 | 10-20 21:29Z（JST 06:29） | **0.4**（10-20 21:30:00Z） | **10-20 21:30:04Z**（needrestart） | 10-21 21:55:20Z |
| braque | 10-21 06:22Z | **0.4**（06:23:26Z） | **06:23:32Z**（needrestart） | 10-22 06:11:06Z |
| chirico | 10-21 06:21Z | 0.3（upgradable に無い） | なし | 10-22 06:01:11Z |
| duchamp | 10-21 06:07Z | **0.4**（06:07:56Z） | **06:08:00Z**（needrestart） | 10-22 06:27:30Z |
| oeilvert | 10-21 06:28Z | 0.3（upgradable に無い） | なし | 10-22 06:19:46Z |
| pablo | 10-21 06:40Z | **0.4**（06:40:39Z） | **06:40:42Z**（needrestart） | 10-22 06:13:02Z |

- 0.4 に上がった 4 台（.113、braque、duchamp、pablo）は、どれも `/var/log/apt/history.log` の liblzma5・xz-utils の更新の直後に、`unattended-upgrades-dpkg.log` に `systemctl restart … iscsid.service …`（needrestart）がある。runbook §2.11 の見込みどおり
- **pablo** はこの段の作業の直前（06:40Z）に流れた（coordinator の読み取りの予定どおり）。iscsid は 06:40:42Z に再起動し、アタッチされた `fs/sites` のセッション（sid 3、10.244.4.131）を引き取った。エンジンは `older-than-iscsid` になった。ボリュームは attached healthy のまま。この後のベースラインは、unattended-upgrades が終わった（`apt-daily-upgrade.service` が inactive、`unattended-upgrades.log` に 06:40:51Z の `All upgrades installed`）ことを確かめてから取った
- **chirico・oeilvert** は今日の実行で liblzma5 が上がらなかった（`apt list --upgradable` に無い。apt のリストに 0.4 が載っていない）。iscsid は 10-19 のまま。次の実行（10-22 06:0xZ〜06:2xZ）で上がり、iscsid が再起動する見込み
- **.111・.112** は今日の実行で liblzma5 が上がっていない（0.4 は upgradable）。次の実行（10-21 21:18Z、21:34Z）で上がり、iscsid が再起動する見込み
- 段 6 の作業は、次の実行（CP は 10-21 21:18Z から、worker は 10-22 06:01Z から）より前に終える。時間帯は重ならない
- open-iscsi は 8 台とも 2.1.9-3ubuntu5.5。`51fraction-hold-open-iscsi` は 8 台とも無い（2026-10-21 に消した）

## 6. etcd のバックアップ（runbook §2.4。段の前）

| 項目 | 値 |
|---|---|
| コマンド | `porkadot etcd backup --config ./porkadot.yaml`（porkadot 0.35.0、etcdctl 3.6.15。サンドボックスの中で 06:46:11Z〜06:46:15Z、rc 0、6 つとも `successful`） |
| 取ったメンバー | 192.168.1.111（写したあと、ノードのものを消した） |
| ファイル | `etcd-2026-10-21T06:46:11+00:00.db`、モード 0600、55,107,616 バイト |
| sha256 | `39ca697a979b55d141afdff73b26a9e5240911807c241ca1f64940e2b84ed34f` |
| 置き場所 | 段 6 の worktree の `./backup/`（`.gitignore` で除外。git には入れていない）。worktree を片付ける前に、メインの checkout の `backup/` へ移す（coordinator） |
| 前のバックアップとの比較 | メインの checkout の `backup/` の `etcd-2026-10-20T10:11:45+00:00.db`（55,107,616）と同じサイズ |

このバックアップは 1.34 の control-plane、CoreDNS v1.12.4 の状態で、runbook §7.4 の restore の第一の候補。

## 7. storage version（runbook §2.5）

`install kubernetes` の前の確認（§2.5 の 1）は §2 の 20 のとおり `OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` は空で、止める条件に当たらない。

## 8. 手順書との差、気づいたこと

- **cnidaria の手順書の `verify-nodes.sh` が oeilvert で exit 1 になった**（`FAIL nft table inet cnidaria exists (image nft)`、`ctr: image "ghcr.io/yuanying/cnidaria-cni:v0.1.0": not found`）。スクリプト（cnidaria-cni-dev の `notes/fraction-runbook/common.sh`）は、ノードの nft の代わりに `cnidaria-cni:v0.1.0` のイメージの nft を `ctr run` で流すが、oeilvert の containerd からこのイメージが消えていた。oeilvert の kubelet の image GC が 10-20 18:45Z に、使われていないイメージを消している（`image_gc_manager.go` の `Removing image to free bytes`。ディスクは今 79%）。ほかの 7 台には v0.1.0 が残っている。テーブル `inet cnidaria` は oeilvert にある（`nft list tables`）。スクリプトの写しを作業端末の `/tmp` に置き、イメージを今の DaemonSet の `v0.1.1`（8 台にある）にして流し、8 台とも exit 0。段 6 の確認はこの写しで流す（元のスクリプトは別のタスクのものなので触っていない）
