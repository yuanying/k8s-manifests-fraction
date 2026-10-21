# 段 7 のベースライン

本番 `fraction` の段 7（K8s 1.35.9 → 1.36.5、CoreDNS v1.13.2 → v1.14.7、porkadot 0.36.0）に入る前に取った、クラスタ全体の読み取りの結果、etcd のバックアップ、storage version と MutatingAdmissionPolicy、StrictIPCIDRValidation、cgroup、resolv.conf、unattended-upgrades の確認の記録。手順は `../../runbook-stage-7.md`（以下 runbook）。
時刻は UTC。1 台ごとの確認は、この記録と比べる。読み取りの出力はタスクディレクトリの `notes/stage-7/baseline/` に置いた（リポジトリには入れない）。全 Pod の名前・UID・restartCount の控えは同じ場所の `pods.tsv`、8 台の `tools/node-state.sh` の出力は `node-<ノード>-before.txt`、etcd の詳細は `etcd-*-base.txt`、8 台の OS の読み取り（cgroup、resolv.conf、unattended-upgrades）は `notes/stage-7/node-os-1.txt`。

## 1. 前提（runbook §1）

| 項目 | 結果 |
|---|---|
| 段 6（§1.1） | `results/stage-6/summary.md` に完了の確認がある。8 台 v1.35.9、`containerd://2.3.6`、etcd 3/3 が 3.6.15（cluster version・storage とも 3.6.0）、Longhorn v1.13.0（engine image は `longhorn-engine:v1.13.0` だけが deployed） |
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor` のグループ（`system:serviceaccounts:kube-system`） |
| porkadot（§1.4） | 独立の clone `worktrees/porkadot-v0-36-0` が `v0.36.0`（`7247f15`、detached）、`lib/porkadot/version.rb` が 0.36.0、作業ツリーに変更が無い。`porkadot help` が動く。cwd は段 7 の worktree（`stage-7-k8s-1-36` のブランチ。base は PR #48 をマージした master の `cd568cc`）。`git status --short assets porkadot.yaml` は空。§7 の戻しに使う `worktrees/porkadot-v0-35-0` は `v0.35.0` で、作業ツリーに変更が無い |
| SSH（§1.3、§1.4。12:55Z） | サンドボックスの中から、`ssh -n` と、porkadot 0.36.0 を `require` した SSHKit の両方で 8 台に `hostname` を流し、8 台とも `rasp01`〜`rasp03`、`pablo`、`duchamp`、`braque`、`chirico`、`oeilvert` を返した（`notes/stage-7/ssh-check.txt`） |
| 入れる版（§1.7。12:55Z） | `stable-1.36.txt` は v1.36.5（`stable.txt` は v1.37.1） |
| 作業端末の kubectl | v1.36.5 |
| 監視（§2.3） | 12:55:57Z〜12:56:2xZ に、pi の `bg_run` で 3 つのジョブとして起動した（bg1: VIP と LB、bg2: etcd の health を .111 から、bg3: 同じく .112 から）。ジョブの中は前景のループ（`nohup`・`&` なし）。ログはタスクディレクトリの `notes/stage-7/stage-7-probe.log`、`stage-7-etcd-192.168.1.11{1,2}.log` |

## 2. クラスタ全体のベースライン（runbook §2.2。2026-10-21 12:56Z〜12:58Z）

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node、版 | 8 台 Ready。全台 v1.35.9、`containerd://2.3.6`。Server Version v1.35.9 |
| 2 | `tools/node-state.sh` の `bin` と `cni` | 8 台とも `kubelet-v1.35.9`、`kubectl-v1.35.9`、`crictl-v1.35.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と bridge・host-local・portmap・loopback が 8 台とも `v1.9.1` |
| 3 | `/etc/etcd/pki` | 3 台とも `ca.crt`・`etcd.crt`・`etcd.key` が `600 root:root` |
| 4 | etcd、VIP | 3/3 healthy、3 台とも 3.6.15、STORAGE VERSION 3.6.0、DB 55 MB（in use 約 16 MB）。リーダーは **192.168.1.113（`57ec6f12ac7b683e`）**。raft term 23123、raft index 1403629320 でそろう。`header.revision` は **1,238,237,468**（§7.4 の restore の目安）。ID は .111 `21ab2aeb56731588`、.112 `fbb0c648cf5852a5`。`member list` は 3 つとも `started`。VIP の `/readyz` は `ok`、`/version` は v1.35.9 |
| 4 | etcd の `/version` | 3 台とも `{"etcdserver":"3.6.15","etcdcluster":"3.6.0","storage":"3.6.0"}` |
| 4 | 動いている etcd のフラグ | 3 台とも `--feature-gates=InitialCorruptCheck=true`、`--watch-progress-notify-interval=5s`、`--snapshot-count=10000` があり、`--experimental-` で始まるものは無い。プロセスの環境に `ETCD_*` は無い |
| 4 | etcd の Pod のログの warn の種類 | 3 台とも `check file permission`、`Running http and grpc server on single port`、`simple token is not cryptographically signed`、`found invalid file under data directory`。.112 は段 6 の起き直しのときの `failed to publish local member to cluster through raft`（5）・`request stats`（5）・`apply request took too long`（4）・`lost`/`closed TCP streaming connection`・`peer became inactive`・`waiting for ReadIndex response took too long`・`ignored out-of-date read index response`・`ignored file in WAL directory`、.113 は `lost TCP streaming connection`（8）・`peer became inactive`（2）・`apply request took too long`（1）。error は無い |
| 5 | Running / Completed 以外の Pod | 0 個 |
| 5 | 全 Pod の名前・UID・restartCount | `notes/stage-7/baseline/pods.tsv` に控えた（160 個。§6 で「増えていない」ことを見る元） |
| 6 | Longhorn のボリューム | attached healthy 16、detached unknown 1（`homegallery/cg-data`。以前から）。degraded は 0 |
| 6 | Longhorn の replica | chirico 9（running 8、stopped 1）、duchamp 12（running 12）、oeilvert 9（running 8、stopped 1）、pablo 2（running 2）。段 6 の完了の確認と同じ |
| 6 | instance-manager、engine image、node | instance-manager 7 つとも running で、段 6 と同じ名前・IP（pablo 10.244.4.131・10.244.4.197、chirico 10.244.8.216・10.244.8.60、duchamp 10.244.5.186、oeilvert 10.244.7.116・10.244.7.198）。engine image は `longhorn-engine:v1.13.0`（`ei-2f3240cb`）だけが deployed。Longhorn の node 4 つとも Ready、schedulable |
| 7 | cnidaria | `verify-nodes.sh`（nft を流すイメージを `v0.1.1` にした写し。runbook §1.8）は 64 PASS、FAIL 0。cnidaria の Pod のログの error / `no route` は .111 16/50、.112 15/49、.113 24/56、braque 22/55、chirico 15/49、duchamp 21/54、oeilvert 0/39、pablo 12/44（前の段のもの。各台の前と後の差で見る）。`check-apps.sh`: nodes 8/8、Running でない Pod 0、IP の重複 0、Longhorn 16 attached healthy・1 detached unknown、192.168.1.200 と v6 の LB は 404、VIP の `/version` は 200 |
| 7 | NetworkPolicy | `longhorn-system` の 6 つ（Longhorn v1.13.0 のもの）だけ。確かめるのは §1.9 の一時的な名前空間で |
| 8 | MetalLB | gated の `192.168.1.200` と `[...:ace::200]` の 80 は 404（応答あり）。`::131`〜`::134` の 3222 は SSH のバナーを返す |
| 9 | NFS | oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で、中身が読める。braque は 2049 を listen している。`registry.fraction.jp/v2/` は 401（応答あり） |
| 10 | metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個 |
| 11、15 | controller-manager と scheduler | controller-manager は .113（`-qjt9d`、リーダー）と .112（`-bvqcn`）。scheduler は .112（`-zkslm`、リーダー）と .113（`-wb6t5`）。段 6 の完了の確認と同じ |
| 12 | CSR | 無い |
| 12 | kubelet の serving の証明書 | 8 台とも subject `O = system:nodes, CN = system:node:<ノード名>`。期限は CP 3 台が 2027-10-16、braque 2027-08-18、chirico 2027-06-23、duchamp 2027-09-06、oeilvert 2027-03-20、pablo 2027-08-08（段 6 と同じ） |
| 13 | kube-system の Deployment と DaemonSet、approver | 下の表。approver は `kubelet-serving-cert-approver-7d5f768656-hls26`（oeilvert、restartCount 0） |
| 14 | Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit` `5`、`replica-auto-balance` `disabled`、`node-drain-policy` `block-if-contains-last-replica`、`default-data-locality` `best-effort`、`replica-replenishment-wait-interval` `6000`、`current-longhorn-version` v1.13.0。どれも APPLIED が true |
| 16 | MetalLB の告知ノード | 下の表 |
| 17 | leader election を使う controller の再起動回数 | `gated-system/gated` の 2 つと `longhorn-system` の CSI sidecar 12 個のうち、`csi-attacher-…-s6fmv`（oeilvert）が 1（段 6 の前から）、ほかの 13 個は 0 |
| 18 | Longhorn のボリュームのアタッチ先と iSCSI | 下の表 |
| 20 | storage version | `prefixes: 65, keys: 2294, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は 1.35 の `/registry/volumeattributesclasses/` `storage.k8s.io/v1beta1` の 1 行（runbook §2.5 の 1 のとおり）。出力はタスクディレクトリの `notes/stage-7/sv-baseline/` |
| 21 | `apiserver_requested_deprecated_apis` | `endpoints`（v1）と `metallb.io/v1beta1 addresspools`。`removed_release` はどれも空 |
| 22 | Longhorn の PVC を使う Running と Completed の Pod（runbook §8.12） | **当たるものは 0**。同じ PVC を使う Running と Succeeded の組は `aphrael/aphrael-2` の `tumblr-like-*` の 3 つ（duchamp）だけで、PV は NFS（`h2.fs.svc.cluster.local`）なので当たらない（段 6 と同じ扱い）。natsumi と deep-researcher のバックアップの CronJob の次の実行は JST 05:30・06:00（20:30Z・21:00Z）で、段 7 の作業の間には走らない見込み。各台の前に読み直す |
| 23 | CoreDNS の答え（v1.13.2。12:58Z） | `tools/dns-check.sh` の出力は `notes/stage-7/baseline/dns-check.txt`。Service（10.254.0.10）と 2 つの Pod（10.244.8.65 chirico、10.244.5.197 duchamp）で同じ答え（runbook-stage-6 §3.3 の 13 の表と同じ形）。2 つの Pod のログは `CoreDNS-1.13.2` だけで、`[ERROR]`・`[WARNING]`・`loop` は無い。restartCount 0 |
| 24 | Service の数 | 79 個。ClusterIP を持つもの 71 個（うち dual-stack 3 個）、ClusterIP の数 74。IPAddress 74。ServiceCIDR は `kubernetes`（`10.254.0.0/24,fd20:afc2:7c09::/108`）の 1 つ |
| 25 | Prometheus のスクレイプ | `count by (job) (up)` の `apiserver` 3、`kube-etcd` 3、`count(etcd_server_has_leader)` 3 |
| 26 | cgroup（runbook §2.9） | §3 |
| 27 | resolv.conf（runbook §2.10） | §4 |
| 28 | unattended-upgrades（runbook §2.11） | §5 |
| 29 | FlowSchema | 11 個。`system-leader-election` が generation 8、ほかの 10 個は 1 |
| 30 | StrictIPCIDRValidation（runbook §2.12） | §7 |
| 31 | MutatingAdmissionPolicy（runbook §2.5） | §8 |

kube-system の Deployment と DaemonSet（§2.2 の 13）:

| KIND | NAME | GEN | IMAGE |
|---|---|---|---|
| Deployment | coredns | 12 | `coredns/coredns:v1.13.2` |
| Deployment | kube-controller-manager | 28 | `kube-controller-manager:v1.35.9` |
| Deployment | kube-dns-autoscaler | 4 | `cluster-proportional-autoscaler-amd64:1.7.1` |
| Deployment | kube-scheduler | 27 | `kube-scheduler:v1.35.9` |
| Deployment | metrics-server | 1 | `metrics-server/metrics-server:v0.7.2` |
| DaemonSet | cnidaria | 3 | `ghcr.io/yuanying/cnidaria-cni:v0.1.1` |
| DaemonSet | kube-apiserver | 29 | `kube-apiserver:v1.35.9` |
| DaemonSet | kube-proxy | 25 | `kube-proxy:v1.35.9` |

MetalLB の告知ノード（speaker のログの IP ごとの最後の `serviceAnnounced`）。段 6 の完了の確認と同じノード:

| Service | アドレス | 告知ノード |
|---|---|---|
| `kube-system/porkadot-kubernetes`（API の VIP） | 192.168.1.101 | **pablo** |
| `gated-system/gated-v4` | 192.168.1.200 | chirico |
| `gated-system/gated-v6` | `::200` | oeilvert |
| `fs/h2-sshd` | `::131` | 192.168.1.112 |
| `natsumi/natsumi-sshd` | `::132` | 192.168.1.111 |
| `natsumi/natsumi-sshd-myao` | `::133` | duchamp |
| `natsumi/natsumi-sshd-aki` | `::134` | 192.168.1.112 |

各ノードの iscsid、iSCSI のセッション、エンジン（`tools/node-state.sh`、12:56Z〜12:57Z）:

| ノード | iscsid（MainPID、起動） | セッション（portal） | `older-than-iscsid` | アタッチされたボリューム |
|---|---|---|---|---|
| 192.168.1.111 | 90734、10-19 07:31:09Z | 0 | — | なし |
| 192.168.1.112 | 89578、10-19 07:27:57Z | 0 | — | なし |
| 192.168.1.113 | 290821、10-20 21:30:04Z（unattended-upgrades。段 6 の前から） | 0 | — | なし |
| braque | 271131、10-21 06:23:32Z（同上） | 0 | — | なし |
| pablo | 4114921、10-21 06:40:42Z（同上） | 1（10.244.4.131 = 今の instance-manager） | 1 | `fs/sites` |
| oeilvert | 6334、10-19 09:04:34Z | 2（10.244.7.116 = 今の instance-manager） | 0 | 2 |
| duchamp | 2695716、10-21 06:08:00Z（同上） | 4（10.244.5.186 = 今の instance-manager） | 4 | 4 |
| chirico | 4447、10-19 09:17:30Z | 9（8 つが 10.244.8.216、1 つが 10.244.8.60。どちらも今の instance-manager） | 0 | 9 |

- runbook §2.7 の表（12:36Z の読み取り）と同じ。古いセッション（今の instance-manager の IP でない portal）は無い
- `initiatorname.iscsi` の md5 は 8 台とも段 6 の完了の確認と同じ
- アタッチ先: chirico 9（`homegallery/tumblr-data`・`ero-data`、`fs/data`・`fs/h2`、`monitoring/prometheus-…-1`、`fraction-agents` の 4 つ）、duchamp 4（`natsumi/natsumi`・`natsumi-aki`・`natsumi-myao`、`monitoring/prometheus-…-0`）、oeilvert 2（`fraction-agents` の 2 つ）、pablo 1（`fs/sites`）
- worker の順は runbook §5.1 のまま **pablo → braque → oeilvert → duchamp → chirico**（アタッチの数 1、0、2、4、9）

ほかに読んだもの:

- Warning のイベントは、Liveness / Readiness の probe の失敗（`natsumi/natsumi-myao-0` 12:0xZ、`carib2`・`shja2`・`pondo2` の `movies` 12:0xZ）。段 7 の作業の前のもので、各台の前と後で増えたものを見る
- CronJob は `notes/stage-7/baseline/cronjobs.txt`

## 3. cgroup（runbook §2.9。12:56Z〜12:57Z）

8 台とも `stat -fc %T /sys/fs/cgroup` が **`cgroup2fs`**。systemd は 8 台とも 255（255.4-1ubuntu8.18）、kernel の引数に `systemd.unified_cgroup_hierarchy` は無い。止める条件（`tmpfs`）に当たらない。

## 4. resolv.conf（runbook §2.10。12:56Z〜12:57Z）

8 台とも kubelet の `resolvConf` は `/run/systemd/resolve/resolv.conf` で、nameserver の並びは段 6 のベースライン（`results/stage-6/baseline.md` §4）と同じ（8 台とも kube-dns の 10.254.0.10 が入っている）。前からのもので、段 7 は止めない。

## 5. unattended-upgrades と iscsid（runbook §2.11。12:56Z〜12:57Z）

| ノード | liblzma5 | iscsid の再起動（needrestart） | `apt-daily-upgrade.service` | 次の `apt-daily-upgrade.timer`（UTC） |
|---|---|---|---|---|
| 192.168.1.111 | **0.3**（0.4 が upgradable） | まだ | inactive | 10-21 21:10:04Z |
| 192.168.1.112 | **0.3**（0.4 が upgradable） | まだ | inactive | 10-21 21:33:53Z |
| 192.168.1.113 | 0.4 | 10-20 21:30:04Z | inactive | 10-21 21:42:28Z |
| braque | 0.4 | 10-21 06:23:32Z | inactive | 10-22 06:31:41Z |
| chirico | **0.3**（0.4 が upgradable） | まだ | inactive | 10-22 06:32:15Z |
| duchamp | 0.4 | 10-21 06:08:00Z | inactive | 10-22 06:13:28Z |
| oeilvert | **0.3**（0.4 が upgradable） | まだ | inactive | 10-22 06:35:45Z |
| pablo | 0.4 | 10-21 06:40:42Z | inactive | 10-22 06:42:22Z |

- runbook §2.11 の 12:36Z の読み取りと同じ。.111・.112・chirico・oeilvert の 4 台は、needrestart による iscsid の再起動がまだ
- 作業の開始は 12:59Z。control-plane の次の実行は 21:10Z から、worker は 10-22 06:13Z からで、段 7 の作業（段 6 は約 40 分）は時間帯に重ならない
- open-iscsi は 8 台とも 2.1.9-3ubuntu5.5

## 6. etcd のバックアップ（runbook §2.4。段の前）

| 項目 | 値 |
|---|---|
| コマンド | `porkadot etcd backup --config ./porkadot.yaml`（porkadot 0.36.0、etcdctl 3.6.15。サンドボックスの中で 12:59:15Z〜12:59:18Z、rc 0、6 つとも `successful`） |
| 取ったメンバー | 192.168.1.111（写したあと、ノードのものを消した） |
| ファイル | `etcd-2026-10-21T12:59:15+00:00.db`、モード 0600、55,107,616 バイト |
| sha256 | `a8e40ed48472f0e09c9028a9778b895a8a862104f36e4ddd5654984f4ef30875` |
| 置き場所 | 段 7 の worktree の `./backup/`（`.gitignore` で除外。git には入れていない。`git status` に出ない）。worktree を片付ける前に、メインの checkout の `backup/` へ移す（coordinator） |
| 前のバックアップとの比較 | メインの checkout の `backup/` の `etcd-2026-10-21T06:56:16+00:00.db`（55,107,616）と同じサイズ |

このバックアップは 1.35 の control-plane、CoreDNS v1.13.2 の状態で、runbook §7.4 の restore の第一の候補。

## 7. StrictIPCIDRValidation（runbook §2.12。12:58Z）

`tools/ipcidr-scan.py` の結果は **`# findings: 0`**（`non-canonical` も 0）。見た値は EndpointSlice 157、Endpoints 154、IPAddress 74、Ingress 66、Node 35、Pod 835、Service 167、ServiceCIDR 2。runbook の 12:36Z の読み取りと同じ（Pod の値の数だけ 832 → 835）。出力は `notes/stage-7/baseline/ipcidr.txt`。

## 8. storage version と MutatingAdmissionPolicy（runbook §2.5）

- `install kubernetes` の前の確認（§2.5 の 1）は §2 の 20 のとおりで、止める条件に当たらない
- `kubectl get mutatingadmissionpolicies,mutatingadmissionpolicybindings` は `the server doesn't have a resource type "mutatingadmissionpolicies"`（1.35）。`admissionregistration.k8s.io` の版は `v1` だけ。ValidatingAdmissionPolicy は 0 個
- `storage-versions.sh` の `prefixes.txt` に `/registry/mutatingadmissionpolicies/`・`/registry/mutatingadmissionpolicybindings/`・`/registry/volumeattributesclasses/`・`/registry/peerserverleases/` は無い（キー 0 個）

## 9. 手順書との差、気づいたこと

- 無い（runbook §2 のとおりに取れた）
