# 段 4 のベースライン

本番 `fraction` の段 4（K8s 1.32.13 → 1.33.13、porkadot 0.33.0）に入る前に取った、クラスタ全体の読み取りの結果、etcd のバックアップ、storage version の確認の記録。手順は `../../runbook-stage-4.md`（以下 runbook）。
時刻は UTC。1 台ごとの確認は、この記録と比べる。読み取りの出力はタスクディレクトリの `notes/stage-4/baseline/` に置いた（リポジトリには入れない）。全 Pod の名前・UID・restartCount の控えは同じ場所の `pods.tsv`、8 台の `tools/node-state.sh` の出力は `node-<ノード>-before.txt`。

## 1. 前提（runbook §1）

| 項目 | 結果 |
|---|---|
| 段 3（§1.1） | `results/stage-3/summary.md` に完了の確認がある。8 台とも v1.32.13、`containerd://2.3.6`、etcd 3.5.34 |
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor`、`auth can-i delete pods -A` は `no` |
| porkadot（§1.4） | `porkadot-dev/porkadot` が `v0.33.0`（`8beb3b4`）、`lib/porkadot/version.rb` が 0.33.0。Ruby 4.0.7。`porkadot help` が動く。cwd は段 4 の worktree（`stage-4-k8s-1-33` のブランチ。base は PR #35 をマージした master の `e3ad437`）。`git status --short assets porkadot.yaml` は空 |
| SSH（§1.3、§1.4。01:57Z） | サンドボックスの中（`ssh-add -l` は `Error connecting to agent: Operation not permitted`）から、porkadot 0.33.0 を `require` した SSHKit で 8 台に `hostname` を流し、8 台とも `rasp01`〜`rasp03`、`pablo`、`duchamp`、`braque`、`chirico`、`oeilvert` を返した |
| 入れる版（§1.7。01:57Z） | `stable-1.33.txt` は v1.33.13（`stable.txt` は v1.37.1） |
| 作業端末の kubectl | v1.33.13 |
| 監視（§2.3） | 01:57:33Z に作業端末で開始。ログはタスクディレクトリの `notes/stage-4/stage-4-probe.log` |

## 2. クラスタ全体のベースライン（runbook §2.2。2026-10-20 01:57Z〜02:00Z）

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node、版 | 8 台 Ready。全台 v1.32.13、`containerd://2.3.6`。Server Version v1.32.13 |
| 2 | `tools/node-state.sh` の `bin` と `cni` | 8 台とも `kubelet-v1.32.13`、`kubectl-v1.32.13`、`crictl-v1.32.0`、`etcdctl-3.5.34`。CNI の印と bridge・host-local・portmap・loopback が 8 台とも `v1.9.1` |
| 3 | `/etc/etcd/pki` | 3 台とも `ca.crt`・`etcd.crt`・`etcd.key` が `600 root:root` |
| 4 | etcd、VIP | 3/3 healthy、3 台とも 3.5.34、DB 55 MB。リーダーは **192.168.1.113（`57ec6f12ac7b683e`）**。raft term 23118、raft index 1402986108 が 3 台とも同じ。ID は .111 `21ab2aeb56731588`、.112 `fbb0c648cf5852a5`。VIP の `/readyz` は `ok`、`/version` は v1.32.13 |
| 5 | Running / Completed 以外の Pod | 0 個 |
| 5 | 全 Pod の名前・UID・restartCount | `notes/stage-4/baseline/pods.tsv` に控えた（148 個。§6 で「増えていない」ことを見る元） |
| 6 | Longhorn のボリューム | attached healthy 16、detached unknown 1（`homegallery/cg-data`。以前から）。degraded は 0 |
| 6 | Longhorn の replica | chirico 11（running 10、stopped 1）、duchamp 10（running 8、stopped 2）、oeilvert 11（running 10、stopped 1）、pablo 2（running 2） |
| 6 | instance-manager、engine image、node | instance-manager 4 つとも running: pablo `-17a539db…`（10.244.4.131）、chirico `-4128231c…`（10.244.8.216）、duchamp `-4df00b8c…`（10.244.5.112）、oeilvert `-d5905a9e…`（10.244.7.116）。engine image `longhorn-engine:v1.11.2` が deployed。Longhorn の node 4 つとも Ready、schedulable |
| 7 | cnidaria | `verify-nodes.sh` は 64 PASS、FAIL 0。cnidaria の Pod のログ: error は .111 8、.112 7、.113 8、braque 7、chirico 8、duchamp 6、oeilvert 0、pablo 7（段 3 の `install kubelet` の `no route` のもの。runbook §8.1）、`no route` の行は .111 28、.112 30、.113 33、braque 22、chirico 21、duchamp 19、oeilvert 15、pablo 26。`check-apps.sh`: nodes 8/8、Running でない Pod 0、IP の重複 0、Longhorn 16 attached healthy・1 detached unknown、192.168.1.200 と v6 の LB は 404、VIP の `/version` は 200 |
| 7 | NetworkPolicy | 1 つも無い。確かめるのは §1.9 の一時的な名前空間で |
| 8 | MetalLB | LoadBalancer の Service 11 個がアドレスを持つ。gated の `192.168.1.200` と `[...:ace::200]` の 80 は 404（応答あり）。`h2-sshd`（`::131`）、`natsumi-sshd`（`::132`）、`natsumi-sshd-myao`（`::133`）、`natsumi-sshd-aki`（`::134`）の 3222 は SSH のバナーを返す。minecraft は UDP なので確かめていない |
| 9 | NFS | PV は 31 で、すべて Bound。oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で、中身が読める。braque は 2049 を listen している。`registry.fraction.jp/v2/` は 401（応答あり） |
| 10 | metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個 |
| 11、15 | controller-manager と scheduler | controller-manager は .112（`-9cxxw`、リーダー）と .113（`-qmv4n`）。scheduler は .112（`-c5dxt`、リーダー）と .111（`-wf5xr`）。runbook §1.1 のとおり |
| 12 | CSR | 無い |
| 12 | kubelet の serving の証明書 | 8 台とも subject が `O = system:nodes, CN = system:node:<ノード名>`。期限は .111 2027-10-16 12:00、.112 2027-10-16 11:46、.113 2027-10-16 11:31、braque 2027-08-18、chirico 2027-06-23、duchamp 2027-09-06、oeilvert 2027-03-20、pablo 2027-08-08（段 3 と同じ） |
| 13 | kube-system の Deployment と DaemonSet、approver | 下の表。approver は `kubelet-serving-cert-approver-7d5f768656-hls26`（oeilvert） |
| 14 | Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit` `5`、`replica-auto-balance` `disabled`、`node-drain-policy` `block-if-contains-last-replica`、`default-data-locality` `best-effort`、`replica-replenishment-wait-interval` `6000`、`current-longhorn-version` v1.11.2。どれも APPLIED が true |
| 16 | MetalLB の告知ノード | 下の表 |
| 17 | leader election を使う controller の再起動回数 | `gated-system/gated` の 2 つ（chirico、oeilvert）、`longhorn-system` の CSI sidecar 12 個とも 0 |
| 18 | Longhorn のボリュームのアタッチ先と iSCSI | 下の表 |
| 20 | storage version | `prefixes: 63, keys: 2120, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は空（サーバーが 1.32）。CRD は 47 個とも `ok`。出力はタスクディレクトリの `notes/stage-4/sv-20261020T0158Z/` |
| 21 | `apiserver_requested_deprecated_apis` | `metallb.io/v1beta1 addresspools`（`removed_release` なし。.112 の apiserver）だけ |
| 22 | Longhorn の PVC を使う Running と Completed の Pod（runbook §8.12） | **無い**。Running と Succeeded が同じ PVC を使うのは `aphrael/aphrael-2` だけ（NFS の静的な PV。Succeeded の 3 つは CronJob `aphrael/tumblr-like` のもの） |
| 23 | CoreDNS の答え（v1.11.4。02:00Z） | 下の表 |
| 24 | Service の数 | 79 個。ClusterIP を持つもの 71 個（うち dual-stack 3 個）、ClusterIP の数は 74（runbook §2.2 の 24 の見込みと同じ） |

kube-system の Deployment と DaemonSet（§2.2 の 13）:

| KIND | NAME | GEN | IMAGE |
|---|---|---|---|
| Deployment | coredns | 10 | `coredns/coredns:v1.11.4` |
| Deployment | kube-controller-manager | 25 | `kube-controller-manager:v1.32.13` |
| Deployment | kube-dns-autoscaler | 4 | `cluster-proportional-autoscaler-amd64:1.7.1` |
| Deployment | kube-scheduler | 24 | `kube-scheduler:v1.32.13` |
| Deployment | metrics-server | 1 | `metrics-server/metrics-server:v0.7.2` |
| DaemonSet | cnidaria | 2 | `ghcr.io/yuanying/cnidaria-cni:v0.1.1` |
| DaemonSet | kube-apiserver | 26 | `kube-apiserver:v1.32.13` |
| DaemonSet | kube-proxy | 22 | `kube-proxy:v1.32.13` |

MetalLB の告知ノード（speaker のログの IP ごとの最後の `serviceAnnounced`）。runbook §2.8 の表と同じ:

| Service | アドレス | 告知ノード |
|---|---|---|
| `kube-system/porkadot-kubernetes`（API の VIP） | 192.168.1.101 | **pablo** |
| `gated-system/gated-v4` | 192.168.1.200 | chirico |
| `gated-system/gated-v6` | `::200` | oeilvert |
| `fs/h2-sshd` | `::131` | 192.168.1.112 |
| `natsumi/natsumi-sshd` | `::132` | 192.168.1.111 |
| `natsumi/natsumi-sshd-myao` | `::133` | duchamp |
| `natsumi/natsumi-sshd-aki` | `::134` | 192.168.1.112 |

minecraft の 4 つは speaker のログに告知の行が無かった（段 1〜3 と同じ）。

各ノードの iscsid、iSCSI のセッション、エンジン（`tools/node-state.sh`）。runbook §2.7 の表と同じ:

| ノード | iscsid（MainPID、起動） | セッション（portal） | `older-than-iscsid` | アタッチされたボリューム | `initiatorname.iscsi` |
|---|---|---|---|---|---|
| 192.168.1.111 | 90734、07:31:09Z | 0 | 0 | なし | assets と同じ（md5） |
| 192.168.1.112 | 89578、07:27:57Z | 0 | 0 | なし | 同じ |
| 192.168.1.113 | 95423、07:24:21Z | 0 | 0 | なし | 同じ |
| braque | 85966、08:06:03Z | 0 | 0 | なし | 同じ |
| pablo | 1194943、07:39:11Z | 1（10.244.4.131 = 今の instance-manager） | 0 | `fs/sites` | 同じ |
| duchamp | 663628、23:33:45Z（段 3 の `install kubelet` で起動） | 0 | 0 | なし | 同じ |
| chirico | 4447、09:17:30Z | 10（すべて 10.244.8.216 = 今の instance-manager） | **1**（pvc-625c8825、09:17:28Z。runbook §2.7 の注のもの） | 10 | 同じ |
| oeilvert | 6334、09:04:34Z | 5（すべて 10.244.7.116 = 今の instance-manager） | 0 | 5 | 同じ |

- 古いセッションは無い
- chirico の `older-than-iscsid` の 1 つは、段 3 の前から同じもの（iscsid の起動の 2 秒前に起動したエンジンでセッションがある）。runbook §2.7 の注の形なので、記録して進める
- アタッチ先: chirico 10（`tumblr-data`、`ero-data`、`fs/data`、`fs/h2`、`natsumi-myao`、`prometheus-…-0`、`fraction-agents` の 4 つ）、oeilvert 5（`natsumi`、`natsumi-aki`、`prometheus-…-1`、`fraction-agents` の 2 つ）、pablo 1（`fs/sites`）。runbook §5.1 の順のまま進める

CoreDNS の答え（§2.2 の 23。作業端末から kube-dns の 10.254.0.10 へ。v1.11.4）:

| 問い合わせ | 答え |
|---|---|
| `kubernetes.default.svc.cluster.local`、`kubernetes.default.svc.fraction.cluster` | `10.254.0.1` |
| `www.google.com` A | 外のアドレス（8 つ） |
| PTR `10.254.0.1` | `kubernetes.default.svc.cluster.local.` |
| PTR `fd20:afc2:7c09::521` | `h2.fs.svc.cluster.local.` |
| PTR の、kube-dns の Endpoint の Pod の IP（`10.244.5.119`、`10.244.8.7`） | NXDOMAIN（coredns#6898） |
| PTR の、`fs/h2` の Endpoint の Pod の IP（`10.244.8.246`、`fde7:4ad6:425d:3::4b1f`） | NXDOMAIN |

ほかに読んだもの:

- CronJob は 8 個（`notes/stage-4/baseline/cronjobs.txt`）。runbook §5.4 のとおり。JST 05:30・06:00 の Job の Pod は段 3 で消したので残っていない（次は JST 10/21 05:30）
- Warning のイベントは無い

## 3. etcd のバックアップ（runbook §2.4）

| 項目 | 値 |
|---|---|
| コマンド | `porkadot etcd backup --config ./porkadot.yaml`（porkadot 0.33.0。サンドボックスの中で 02:00:34Z〜02:00:38Z、rc 0、6 つとも `successful`） |
| 取ったメンバー | 192.168.1.111（写したあと、ノードのものを消した） |
| ファイル | `etcd-2026-10-20T02:00:34+00:00.db`、モード 0600、55,107,616 バイト |
| sha256 | `766c2b60d508f52425c94544d168ff7f324e409a3e9512ffcd3d61e7480cefd7` |
| 置き場所 | 段 4 の worktree の `./backup/`（`.gitignore` で除外。git には入れていない）。worktree を片付ける前に、メインの checkout の `backup/` へ移す（coordinator） |
| 前のバックアップとの比較 | メインの checkout の `backup/` の段 3 の `etcd-2026-10-19T23:13:51+00:00.db`（55,107,616）と同じサイズ |

## 4. storage version（runbook §2.5）

段 4 では書き直すものは無い。`install kubernetes` の前の確認（§2.5 の 1）は §2 の 20 のとおり `OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` は空で、止める条件に当たらない。
