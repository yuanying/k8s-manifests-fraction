# 段 2 のベースライン

本番 `fraction` の段 2（K8s 1.30.14 → 1.31.14、porkadot 0.31.0）に入る前に取った、クラスタ全体の読み取りの結果と etcd のバックアップの記録。手順は `../../runbook-stage-2.md`（以下 runbook）。
時刻は UTC。1 台ごとの確認は、この記録と比べる。読み取りの出力はタスクディレクトリの `notes/stage-2/baseline/` に置いた（リポジトリには入れない）。全 Pod の名前・UID・restartCount の控えは同じ場所の `baseline-pods.tsv`。

## 1. 前提（runbook §1）

| 項目 | 結果 |
|---|---|
| 段 1（§1.1） | `results/stage-1/summary.md` に完了の確認がある。8 台とも v1.30.14、`containerd://2.3.6`、etcd 3.5.34 |
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor`、`auth can-i delete pods -A` は `no`。`infra-admin` のトークンはまだ発行していない |
| porkadot（§1.4） | `porkadot-dev/porkadot` が `v0.31.0`（`62d8821`）、`lib/porkadot/version.rb` が 0.31.0。`porkadot help` が動く。cwd は段 2 の worktree（`stage-2-k8s-1-31` のブランチ。base は PR #30 をマージした master の `1c91327`）。`git status --short assets porkadot.yaml` は空 |
| SSH（§1.3、§1.4。07:14Z） | サンドボックスの中（`ssh-add -l` は `Error connecting to agent: Operation not permitted`）から、porkadot 0.31.0 を `require` した SSHKit で 8 台に `hostname` を流し、8 台とも `rasp01`〜`rasp03`、`pablo`、`duchamp`、`braque`、`chirico`、`oeilvert` を返した。素の `ssh` でも入れる |
| secrets（§1.6。07:17Z） | `assets/certs/kubernetes/ca.crt` と ConfigMap `default/kube-root-ca.crt` が一致（`AB:5A:49:9E:…:A0:3E`）。`assets/certs/kubernetes/apiserver.crt` と、VIP・.111・.112・.113 の 6443 が返す証明書の 4 つが一致（`4A:E8:7B:B3:…:97:63`）。.111 の `/etc/etcd/pki` の `ca.crt`・`etcd.key` は `assets/kubelet/192.168.1.111/addons/etcd/` のものと sha256 が一致。`etcd.crt` は render で作り直したので違うが、公開鍵が一致（runbook §8.2）。Secret `kube-apiserver`・`etcd-tls` との突き合わせは runbook §1.6 の 05:50Z のもの（同じ日）で、繰り返していない |
| 入れる版（§1.7。07:18Z） | `stable-1.31.txt` は v1.31.14（`stable.txt` は v1.37.1）。registry.k8s.io の kube-apiserver・kube-controller-manager・kube-scheduler・kube-proxy の v1.31.14 はどれも amd64 と arm64 を含む。kubelet・kubectl の v1.31.14（amd64、arm64）と `crictl-v1.31.1-linux-{amd64,arm64}.tar.gz` はどれも 200。`ghcr.io/alex1989hu/kubelet-serving-cert-approver:0.12.1` は amd64 と arm64 を含み、digest は `sha256:445a8e5584f6…`（runbook のとおり） |
| 作業端末の kubectl | v1.30.14（1.31 の ±1 に入る） |
| 監視（§2.3） | 07:14Z に作業端末で開始。ログはタスクディレクトリの `notes/stage-2/stage-2-probe.log` |

## 2. クラスタ全体のベースライン（runbook §2.2。2026-10-19 07:15Z〜07:16Z）

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node、版 | 8 台 Ready。全台 v1.30.14、`containerd://2.3.6`。Server Version v1.30.14 |
| 2 | `/opt/bin` | 8 台とも `kubelet-v1.30.14`、`kubectl-v1.30.14`、`etcdctl-3.5.34`、`crictl-v1.30.1`。`/opt/cni/bin/.porkadot-cni-plugins-version` は 8 台とも `v1.4.1`。kubelet は 8 台とも active |
| 3 | `/etc/etcd/pki` | 3 台とも `ca.crt`・`etcd.crt`・`etcd.key` が `600 root:root` |
| 4 | etcd、VIP | 3/3 healthy、3 台とも 3.5.34、DB 55 MB。リーダーは **192.168.1.113（`57ec6f12ac7b683e`）**。raft term 23114、raft index 1402640430 が 3 台とも同じ。ID は .111 `21ab2aeb56731588`、.112 `fbb0c648cf5852a5`。VIP の `/readyz` は `ok`、`/version` は v1.30.14 |
| 5 | Running / Completed 以外の Pod | 0 個 |
| 5 | 全 Pod の名前・UID・restartCount | `notes/stage-2/baseline/baseline-pods.tsv` に控えた（段 2 の比べる元） |
| 6 | Longhorn のボリューム | attached healthy 23、detached unknown 2（`myao/myao`、`homegallery/cg-data`。以前から）。degraded は 0 |
| 6 | Longhorn の replica | chirico 15（running 13、stopped 2）、duchamp 10（running 8、stopped 2）、oeilvert 17（running 16、stopped 1）、pablo 3（running 3）。同じボリュームの replica が同じノードに 2 つ載っているものは無い |
| 6 | instance-manager、engine image、node | instance-manager 4 つ（chirico、duchamp、oeilvert、pablo）とも running。engine image `longhorn-engine:v1.11.2` が deployed。Longhorn の node 4 つとも Ready、schedulable |
| 7 | cnidaria | `verify-nodes.sh` は 64 PASS、FAIL 0。cnidaria の Pod のログの error の数（runbook §8.1 で比べる）は .111 7、.112 7、.113 8、braque 8、chirico 8、duchamp 6、oeilvert 0、pablo 8（段 1 の各台の `install kubelet` のときの `no route` が残っているもの。Pod は段 1 から再起動していない）。`check-apps.sh`: nodes 8/8、Running でない Pod 0、IP の重複 0、Longhorn 23 attached healthy・2 detached unknown、hedgedoc の `db-postgresql-0` は Running（chirico）、192.168.1.200 と v6 の LB は 404、VIP の `/version` は 200 |
| 7 | NetworkPolicy | chirico の `table inet cnidaria` に `hedgedoc/db-postgresql` を含む行が 10 ある |
| 8 | MetalLB | LoadBalancer の Service 11 個がアドレスを持つ。gated の `192.168.1.200` と `[...:ace::200]` の 80 は 404（応答あり）。`h2-sshd`（`::131`）、`natsumi-sshd`（`::132`）、`natsumi-sshd-myao`（`::133`）、`natsumi-sshd-aki`（`::134`）の 3222 は SSH のバナーを返す。minecraft は UDP なので確かめていない |
| 9 | NFS | braque（192.168.1.131）と fs の Service の NFS の PV は Bound 14、Released 3（`codimd`、`codimd-backup`、`maildata`。以前から）。oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で、中身が読める。braque は 2049 を listen している（nfsd の DaemonSet の Pod）。`registry.fraction.jp/v2/` は 401（応答あり） |
| 10 | metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個。`apiserver_requested_deprecated_apis` は `metallb.io/v1beta1 addresspools`（`removed_release` なし）だけ |
| 11、15 | controller-manager と scheduler | controller-manager は .111（`-6pg99`）と .113（`-jg62c`、リーダー）。scheduler は .111（`-lffqk`、リーダー）と .112（`-nbklj`）。runbook §4.2 の 1 のとおり |
| 12 | CSR | 無い |
| 12 | kubelet の serving の証明書 | 8 台とも subject が `O = system:nodes, CN = system:node:<ノード名>`、issuer が `CN = kube-ca`。期限は .111 2027-10-16 12:00、.112 2027-10-16 11:46、.113 2027-10-16 11:31、braque 2027-08-18、chirico 2027-06-23、duchamp 2027-09-06、oeilvert 2027-03-20、pablo 2027-08-08 |
| 13 | kube-system の Deployment と DaemonSet、approver | 下の表。approver は `kubelet-serving-cert-approver-6b9bcf6f87-hz6mp`（chirico）、`:main`、`Always`、imageID `sha256:91853df47f4a…` |
| 14 | Longhorn の設定（§2.6） | `concurrent-replica-rebuild-per-node-limit` `5`、`replica-auto-balance` `disabled`、`node-drain-policy` `block-if-contains-last-replica`、`default-data-locality` `best-effort`、`replica-replenishment-wait-interval` `6000`、`current-longhorn-version` v1.11.2。どれも APPLIED が true |
| 16 | MetalLB の告知ノード（§2.7） | 下の表 |
| 17 | leader election を使う controller の再起動回数 | `gated-system/gated` は chirico の `qnvq4` が 3、duchamp の `w4hw7` が 0。`longhorn-system` の CSI sidecar は 12 個のうち `csi-attacher-...-n2l6k`（chirico）、`csi-resizer-...-md2xx`（pablo）、`csi-snapshotter-...-l7qpx`（pablo）が 1、ほかは 0（段 1 と同じ） |
| 18 | replica 1 のボリューム | chirico: `monitoring/prometheus-...-1`（pvc-99c35b80）。oeilvert: `monitoring/prometheus-...-0`（pvc-625c8825）、`minio/export-minio-0`〜`3`（pvc-e5688f70、beb6e798、c1d85062、ce2f24f9）。使っている Pod は prometheus-0（oeilvert）、prometheus-1（chirico）、minio-0（oeilvert）、minio-1（chirico）、minio-2（pablo）、minio-3（duchamp）。**runbook §2.6 の表と同じ**。Prometheus の `spec.replicas` は 2、`minio/minio` は 4 |
| 19 | drain する 4 台 | controller の無い Pod は 0。PDB は runbook §2.6 のとおり（controller-manager・scheduler、`csi-attacher`・`csi-provisioner` の ALLOWED 2、instance-manager 4 つの ALLOWED 0、`minio/minio` の maxUnavailable 1）。emptyDir を使う Pod（DaemonSet を除く）は chirico 11、duchamp 3、oeilvert 3、pablo 1 で、runbook §2.6 の表と同じ顔ぶれ（ほかに control-plane の controller-manager 2 つ）。`homegallery/api` は oeilvert |
| 20 | Longhorn のボリュームのアタッチ先 | VolumeAttachment は chirico 15、duchamp 5、oeilvert 4、pablo 1。longhorn-csi-plugin は chirico、duchamp、oeilvert、pablo の 4 台だけ。braque と control-plane にはアタッチされていない（runbook §8.11） |

kube-system の Deployment と DaemonSet（§2.2 の 13）:

| KIND | NAME | GEN | IMAGE |
|---|---|---|---|
| Deployment | coredns | 9 | `coredns/coredns:v1.11.3` |
| Deployment | kube-controller-manager | 23 | `kube-controller-manager:v1.30.14` |
| Deployment | kube-dns-autoscaler | 4 | `cluster-proportional-autoscaler-amd64:1.7.1` |
| Deployment | kube-scheduler | 22 | `kube-scheduler:v1.30.14` |
| Deployment | metrics-server | 1 | `metrics-server/metrics-server:v0.7.2` |
| DaemonSet | cnidaria | 2 | `ghcr.io/yuanying/cnidaria-cni:v0.1.1` |
| DaemonSet | kube-apiserver | 24 | `kube-apiserver:v1.30.14` |
| DaemonSet | kube-proxy | 20 | `kube-proxy:v1.30.14` |

MetalLB の告知ノード（speaker のログの IP ごとの最後の `serviceAnnounced`。`fs/h2-sshd` と `natsumi-sshd-aki` は `nodeAssigned` のイベントも .112）。runbook §2.7 の表と同じ:

| Service | `externalTrafficPolicy` | アドレス | 告知ノード（最後の告知） |
|---|---|---|---|
| `kube-system/porkadot-kubernetes`（API の VIP） | Cluster | 192.168.1.101 | **pablo**（05:59:39Z） |
| `gated-system/gated-v4`、`gated-v6` | Local | 192.168.1.200、`::200` | chirico（03:57:32Z） |
| `fs/h2-sshd` | Cluster | `::131` | 192.168.1.112（06:44:36Z） |
| `natsumi/natsumi-sshd` | Cluster | `::132` | 192.168.1.111（01:38:53Z） |
| `natsumi/natsumi-sshd-myao` | Cluster | `::133` | duchamp（05:20:19Z） |
| `natsumi/natsumi-sshd-aki` | Cluster | `::134` | 192.168.1.112（06:44:36Z） |

minecraft の 4 つ（`bds`、`bds-v4`、`minecraft2/bds`、`minecraft3/bds`）は speaker のログに告知の行が無かった（段 1 と同じ）。

ほかに読んだもの:

- `systemctl --failed`: braque の `systemd-networkd-wait-online.service` だけ（段 1 と同じ）。ほかの 7 台は空
- CronJob は 8 個（`notes/stage-2/baseline/cronjobs.txt`。schedule は段 1 と同じ）

## 3. etcd のバックアップ（runbook §2.4）

| 項目 | 値 |
|---|---|
| コマンド | `porkadot etcd backup --config ./porkadot.yaml`（porkadot 0.31.0。サンドボックスの中で 07:16:20Z〜07:16:24Z、すべて `successful`） |
| 取ったメンバー | 192.168.1.111（root で `etcdctl snapshot save`、chown 1000:1000、chmod 0600 してから写し、ノードのものを消した） |
| ファイル | `etcd-2026-10-19T07:16:21+00:00.db`、モード 0600、55,107,616 バイト |
| sha256 | `328bcd5dee9196b28457a14c7174c99841b9b2f5e460d0c9808672661dcdaa91` |
| 置き場所 | 段 2 の worktree の `./backup/`（`.gitignore` で除外。git には入れていない）。worktree を片付ける前に、メインの checkout の `backup/` へ移す |
| 前のバックアップとの比較 | メインの checkout の `backup/` の段 1 の `etcd-2026-10-19T00:45:32+00:00.db`（55,107,616）と同じサイズ |
