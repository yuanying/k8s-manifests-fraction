# 段 3 のベースライン

本番 `fraction` の段 3（K8s 1.31.14 → 1.32.13、porkadot 0.32.0）に入る前に取った、クラスタ全体の読み取りの結果、etcd のバックアップ、storage version の書き直しの記録。手順は `../../runbook-stage-3.md`（以下 runbook）。
時刻は UTC。1 台ごとの確認は、この記録と比べる。読み取りの出力はタスクディレクトリの `notes/stage-3/baseline/` に置いた（リポジトリには入れない）。全 Pod の名前・UID・restartCount の控えは同じ場所の `pods.tsv`、8 台の `tools/node-state.sh` の出力は `node-<ノード>-before.txt`。

## 1. 前提（runbook §1）

| 項目 | 結果 |
|---|---|
| 段 2（§1.1） | `results/stage-2/summary.md` に完了の確認がある。8 台とも v1.31.14、`containerd://2.3.6`、etcd 3.5.34 |
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor`、`auth can-i delete pods -A` は `no` |
| porkadot（§1.4） | `porkadot-dev/porkadot` が `v0.32.0`（`0fece0a`）、`lib/porkadot/version.rb` が 0.32.0。Ruby 4.0.7。`porkadot help` が動く。cwd は段 3 の worktree（`stage-3-k8s-1-32` のブランチ。base は PR #33 をマージした master の `cc886c8`）。`git status --short assets porkadot.yaml` は空 |
| SSH（§1.3、§1.4。22:59Z） | サンドボックスの中（`ssh-add -l` は `Error connecting to agent: Operation not permitted`）から、porkadot 0.32.0 を `require` した SSHKit で 8 台に `hostname` を流し、8 台とも `rasp01`〜`rasp03`、`pablo`、`duchamp`、`braque`、`chirico`、`oeilvert` を返した |
| 入れる版（§1.7。23:00Z） | `stable-1.32.txt` は v1.32.13（`stable.txt` は v1.37.1） |
| 作業端末の kubectl | v1.31.14 |
| 監視（§2.3） | 23:00Z に作業端末で開始。ログはタスクディレクトリの `notes/stage-3/stage-3-probe.log` |

## 2. クラスタ全体のベースライン（runbook §2.2。2026-10-19 23:01Z〜23:03Z）

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node、版 | 8 台 Ready。全台 v1.31.14、`containerd://2.3.6`。Server Version v1.31.14 |
| 2 | `tools/node-state.sh` の `bin` と `cni` | 8 台とも `kubelet-v1.31.14`、`kubectl-v1.31.14`、`crictl-v1.31.1`、`etcdctl-3.5.34`。CNI の印は 8 台とも `v1.4.1`。プラグインは duchamp・chirico・oeilvert が bridge・host-local・portmap v1.9.1、loopback v1.4.1。ほかの 5 台は 4 つとも v1.4.1（runbook §8.11 のとおり） |
| 3 | `/etc/etcd/pki` | 3 台とも `ca.crt`・`etcd.crt`・`etcd.key` が `600 root:root` |
| 4 | etcd、VIP | 3/3 healthy、3 台とも 3.5.34、DB 55 MB。リーダーは **192.168.1.113（`57ec6f12ac7b683e`）**。raft term 23116、raft index 1402933664 が 3 台とも同じ。ID は .111 `21ab2aeb56731588`、.112 `fbb0c648cf5852a5`。VIP の `/readyz` は `ok`、`/version` は v1.31.14 |
| 5 | Running / Completed 以外の Pod | 0 個 |
| 5 | 全 Pod の名前・UID・restartCount | `notes/stage-3/baseline/pods.tsv` に控えた（152 個。§6 で「増えていない」ことを見る元） |
| 6 | Longhorn のボリューム | attached healthy 16、detached unknown 1（`homegallery/cg-data`。以前から）。degraded は 0 |
| 6 | Longhorn の replica | chirico 11（running 10、stopped 1）、duchamp 10（running 8、stopped 2）、oeilvert 11（running 10、stopped 1）、pablo 2（running 2） |
| 6 | instance-manager、engine image、node | instance-manager 4 つとも running: pablo `-17a539db…`（10.244.4.131）、chirico `-4128231c…`（10.244.8.216）、duchamp `-4df00b8c…`（10.244.5.112）、oeilvert `-d5905a9e…`（10.244.7.116）。engine image `longhorn-engine:v1.11.2` が deployed。Longhorn の node 4 つとも Ready、schedulable |
| 7 | cnidaria | `verify-nodes.sh` は FAIL 0。cnidaria の Pod のログ: error 0（8 台）、`no route` の行は .111 8、.112 10、.113 12、braque 2、chirico 0、duchamp 0、oeilvert 0、pablo 6（段 2 までのもの）。`check-apps.sh`: nodes 8/8、Running でない Pod 0、IP の重複 0、Longhorn 16 attached healthy・1 detached unknown、192.168.1.200 と v6 の LB は 404、VIP の `/version` は 200 |
| 7 | NetworkPolicy | 1 つも無い（runbook §1.1）。確かめるのは §1.9 の一時的な名前空間で |
| 8 | MetalLB | LoadBalancer の Service 11 個がアドレスを持つ。gated の `192.168.1.200` と `[...:ace::200]` の 80 は 404（応答あり）。`h2-sshd`（`::131`）、`natsumi-sshd`（`::132`）、`natsumi-sshd-myao`（`::133`）、`natsumi-sshd-aki`（`::134`）の 3222 は SSH のバナーを返す。minecraft は UDP なので確かめていない |
| 9 | NFS | PV は 31 で、すべて Bound。oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で、中身が読める。braque は 2049 を listen している。`registry.fraction.jp/v2/` は 401（応答あり） |
| 10 | metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個 |
| 11、15 | controller-manager と scheduler | controller-manager は .111（`-2blbx`）と .112（`-2ffhd`、リーダー）。scheduler は .112（`-vb2lz`）と .113（`-mp2ld`、リーダー）。runbook §4.2 の 1 のとおり |
| 12 | CSR | 無い |
| 12 | kubelet の serving の証明書 | 8 台とも subject が `O = system:nodes, CN = system:node:<ノード名>`。期限は .111 2027-10-16 12:00、.112 2027-10-16 11:46、.113 2027-10-16 11:31、braque 2027-08-18、chirico 2027-06-23、duchamp 2027-09-06、oeilvert 2027-03-20、pablo 2027-08-08（段 2 と同じ） |
| 13 | kube-system の Deployment と DaemonSet、approver | 下の表。approver は `kubelet-serving-cert-approver-7d5f768656-hls26`（oeilvert） |
| 14 | Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit` `5`、`replica-auto-balance` `disabled`、`node-drain-policy` `block-if-contains-last-replica`、`default-data-locality` `best-effort`、`replica-replenishment-wait-interval` `6000`、`current-longhorn-version` v1.11.2。どれも APPLIED が true |
| 16 | MetalLB の告知ノード | 下の表 |
| 17 | leader election を使う controller の再起動回数 | `gated-system/gated` の 2 つ（chirico、oeilvert）、`longhorn-system` の CSI sidecar 12 個とも 0 |
| 18 | Longhorn のボリュームのアタッチ先と iSCSI | 下の表 |
| 20 | storage version（§2.5 の前） | `prefixes: 63, keys: 2125, OLD: 32, CRDs with more than one stored version: 0`。`OLD` は FlowSchema 13・PriorityLevelConfiguration 8（`flowcontrol.apiserver.k8s.io/v1beta3`）、EndpointSlice 11（`discovery.k8s.io/v1beta1`。runbook §2.5 の 11 個と同じ名前）。CRD は 47 個。出力はタスクディレクトリの `notes/stage-3/sv-20261019T2301Z/` |
| 21 | `apiserver_requested_deprecated_apis` | `metallb.io/v1beta1 addresspools`（`removed_release` なし）だけ。`flowcontrol.apiserver.k8s.io/v1beta3` を使うクライアントは無い |
| 22 | Longhorn の PVC を使う Running と Completed の Pod（runbook §8.12） | **4 つある**（下の注） |

kube-system の Deployment と DaemonSet（§2.2 の 13）:

| KIND | NAME | GEN | IMAGE |
|---|---|---|---|
| Deployment | coredns | 9 | `coredns/coredns:v1.11.3` |
| Deployment | kube-controller-manager | 24 | `kube-controller-manager:v1.31.14` |
| Deployment | kube-dns-autoscaler | 4 | `cluster-proportional-autoscaler-amd64:1.7.1` |
| Deployment | kube-scheduler | 23 | `kube-scheduler:v1.31.14` |
| Deployment | metrics-server | 1 | `metrics-server/metrics-server:v0.7.2` |
| DaemonSet | cnidaria | 2 | `ghcr.io/yuanying/cnidaria-cni:v0.1.1` |
| DaemonSet | kube-apiserver | 25 | `kube-apiserver:v1.31.14` |
| DaemonSet | kube-proxy | 21 | `kube-proxy:v1.31.14` |

MetalLB の告知ノード（speaker のログの IP ごとの最後の `serviceAnnounced`。どれも 2026-10-19 09:43:19Z）。runbook §2.8 の表と同じ:

| Service | アドレス | 告知ノード |
|---|---|---|
| `kube-system/porkadot-kubernetes`（API の VIP） | 192.168.1.101 | **pablo** |
| `gated-system/gated-v4` | 192.168.1.200 | chirico |
| `gated-system/gated-v6` | `::200` | oeilvert |
| `fs/h2-sshd` | `::131` | 192.168.1.112 |
| `natsumi/natsumi-sshd` | `::132` | 192.168.1.111 |
| `natsumi/natsumi-sshd-myao` | `::133` | duchamp |
| `natsumi/natsumi-sshd-aki` | `::134` | 192.168.1.112 |

minecraft の 4 つは speaker のログに告知の行が無かった（段 1・段 2 と同じ）。

各ノードの iscsid、iSCSI のセッション、エンジン（`tools/node-state.sh`）。runbook §2.7 の表と同じ:

| ノード | iscsid（MainPID、起動） | セッション（portal） | `older-than-iscsid` | アタッチされたボリューム | `initiatorname.iscsi` |
|---|---|---|---|---|---|
| 192.168.1.111 | 90734、07:31:09Z | 0 | 0 | なし | assets と同じ（md5） |
| 192.168.1.112 | 89578、07:27:57Z | 0 | 0 | なし | 同じ |
| 192.168.1.113 | 95423、07:24:21Z | 0 | 0 | なし | 同じ |
| braque | 85966、08:06:03Z | 0 | 0 | なし | 同じ |
| pablo | 1194943、07:39:11Z | 1（10.244.4.131 = 今の instance-manager） | 0 | `fs/sites` | 同じ |
| duchamp | **0（動いていない）** | 0 | 0 | なし | 同じ |
| chirico | 4447、09:17:30Z | 10（すべて 10.244.8.216 = 今の instance-manager） | **1**（pvc-625c8825、09:17:28Z。runbook §2.7 の注のもの） | 10 | 同じ |
| oeilvert | 6334、09:04:34Z | 5（すべて 10.244.7.116 = 今の instance-manager） | 0 | 5 | 同じ |

- 古いセッションは無い
- chirico の `older-than-iscsid` の 1 つは、iscsid の起動の 2 秒前に起動したエンジンでセッションがある。runbook §2.7 の注の形なので、記録して進める

**Longhorn の PVC を使う Running と Completed の Pod**（runbook §8.12。23:01Z）。runbook の作成のとき（13:2xZ）には無かったが、JST 05:30（20:30Z）と 06:00（21:00Z）のバックアップの CronJob が Completed の Pod を残した:

| PVC | Running の Pod（ノード） | Completed の Pod（ノード） |
|---|---|---|
| `fraction-agents/data-deep-researcher-0` | `deep-researcher-0`（chirico） | `deep-researcher-backup-29874060-hg5hn`（chirico） |
| `natsumi/natsumi-myao` | `natsumi-myao-0`（chirico） | `natsumi-backup-myao-29874030-bxqpd`（chirico） |
| `natsumi/natsumi` | `natsumi-0`（oeilvert） | `natsumi-backup-29874030-7m9fw`（oeilvert） |
| `natsumi/natsumi-aki` | `natsumi-aki-0`（oeilvert） | `natsumi-backup-aki-29874030-tf9gj`（oeilvert） |

- `aphrael/aphrael-2` の Running と Succeeded の組は NFS の静的な PV なので当たらない
- oeilvert と chirico の `install kubelet` の前に読み直し、残っていれば消してよいかをユーザーに確かめる（runbook §5.2 の 1）

ほかに読んだもの:

- CronJob は 8 個（`notes/stage-3/baseline/cronjobs.txt`）
- Warning のイベントは無い

## 3. etcd のバックアップ（runbook §2.4）

| 項目 | 値 |
|---|---|
| コマンド | `porkadot etcd backup --config ./porkadot.yaml`（porkadot 0.32.0。サンドボックスの中で 23:13:51Z〜23:13:55Z、rc 0、すべて `successful`） |
| 取ったメンバー | 192.168.1.111（root で `etcdctl snapshot save`、chown 1000:1000、chmod 0600 してから写し、ノードのものを消した） |
| ファイル | `etcd-2026-10-19T23:13:51+00:00.db`、モード 0600、55,107,616 バイト |
| sha256 | `e716b97366c9a14b9ddf6a6dab07734e6c0f33415020b6e6c1e6fe72443c157e` |
| 置き場所 | 段 3 の worktree の `./backup/`（`.gitignore` で除外。git には入れていない）。worktree を片付ける前に、メインの checkout の `backup/` へ移す |
| 前のバックアップとの比較 | メインの checkout の `backup/` の段 2 の `etcd-2026-10-19T07:16:21+00:00.db`（55,107,616）と同じサイズ |

## 4. storage version の書き直し（runbook §2.5）

| 項目 | 値 |
|---|---|
| 洗い出し（§2.5 の 1。23:01Z） | `OLD: 32`（FlowSchema 13、PriorityLevelConfiguration 8、EndpointSlice 11）、`CRDs with more than one stored version: 0`。runbook の 3 種のほかは無い |
| トークン（§2.5 の 2） | 23:15:10Z に `infra-admin` の 1 時間のトークンを発行。`auth can-i update flowschemas` と `update endpointslices -A` は `yes` |
| FlowSchema と PriorityLevelConfiguration（§2.5 の 3） | `replace --dry-run=server` で 21 行の `replaced (server dry run)`。23:15:17Z〜23:15:18Z に `replace` で 21 行の `replaced`、rc 0。resourceVersion の衝突は無かった。21 個とも `autoupdate-spec` は `"true"` |
| EndpointSlice（§2.5 の 4） | `replace --dry-run=server` で 11 行の `replaced (server dry run)`。23:15:24Z〜23:15:25Z に `replace` で 11 行の `replaced`（runbook の 11 個と同じ名前）。衝突は無かった |
| 書き直した後（§2.5 の 5） | `tools/storage-versions.sh`: `prefixes: 63, keys: 2125, OLD: 0, CRDs with more than one stored version: 0`。FlowSchema・PriorityLevelConfiguration の 21 個は resourceVersion だけが変わり、generation と `autoupdate-spec` は同じ。VIP の `/readyz` は `ok`、監視の FAIL は 0。`nfsd/nfs-ntht8` の endpoint は 192.168.1.131 のままで、oeilvert から NFS が読める |
| トークンの破棄（§2.5 の 6） | 23:17Z にファイルを消した（サーバーの側では 00:15Z に切れる） |

出力（キーと版だけ）はタスクディレクトリの `notes/stage-3/sv-20261019T2301Z/`（前）と `sv-20261019T2301Z-after/`（後）。`apf-before.txt`・`apf-after.txt` は名前・generation・resourceVersion・`autoupdate-spec` だけ。
