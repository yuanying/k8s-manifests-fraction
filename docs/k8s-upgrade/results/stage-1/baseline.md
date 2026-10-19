# 段 1 のベースライン

本番 `fraction` の段 1（K8s 1.29.8 → 1.30.14、porkadot 0.30.0）に入る前に取った、クラスタ全体の読み取りの結果と etcd のバックアップの記録。手順は `../../runbook-stage-1.md`（以下 runbook）。
時刻は UTC。1 台ごとの確認は、この記録と比べる。読み取りの出力はタスクディレクトリの `notes/stage-1/baseline/` に置いた（リポジトリには入れない）。

## 1. 前提（runbook §1）

| 項目 | 結果 |
|---|---|
| 段 C（§1.1） | `results/stage-c/summary.md` に完了の確認がある。8 台とも `containerd://2.3.6`。段 C の終わり（2026-10-18 12:33Z）から約 12 時間たっている |
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor`。`infra-admin` のトークンは発行していない |
| SSH（§1.3） | 8 台に鍵で入れる（2026-10-19 00:42Z） |
| porkadot（§1.4） | `porkadot-dev/porkadot` が `v0.30.0`、`lib/porkadot/version.rb` が 0.30.0。cwd は段 1 の worktree（`stage-1-k8s-1-30` のブランチ。base は PR #21 をマージした master の `60ef0a0`）。`git status --short assets porkadot.yaml` は空 |
| secrets（§1.6。2026-10-19 00:44Z） | `assets/certs/kubernetes/ca.crt` と ConfigMap `default/kube-root-ca.crt` が一致（`AB:5A:49:9E:…:A0:3E`）。`assets/certs/kubernetes/apiserver.crt` と、VIP・.111・.112・.113 の 6443 が返す証明書の 4 つが一致（`4A:E8:7B:B3:…:97:63`）。`front-proxy-ca.crt` は `extension-apiserver-authentication` の 4 つの CA のうち最新（2026-06-13 発行）と一致。.111 の `/etc/etcd/pki` の `ca.crt`・`etcd.key` は `assets/kubelet/192.168.1.111/addons/etcd/` のものと sha256 が一致。`etcd.crt` は render で作り直したので違うが、公開鍵が同じで、assets の etcd の CA で検証が通る（runbook §8.2） |
| 入れる版（§1.7。00:44Z） | `stable-1.30.txt` は v1.30.14（`stable.txt` は v1.37.1）。registry.k8s.io の kube-apiserver・kube-controller-manager・kube-scheduler・kube-proxy の v1.30.14、`etcd:3.5.34-0`、`coredns/coredns:v1.11.3` はどれも amd64 と arm64 を含む。kubelet・kubectl の v1.30.14、crictl v1.30.1、etcd v3.5.34 の amd64・arm64 はどれも 200 |
| 作業端末の kubectl | v1.29.8。.113 の作業の前（01:0xZ）に、ユーザーの指示で asdf の v1.30.14 にした（`~/.tool-versions`） |
| 監視（§2.3） | 00:44Z に作業端末で開始。ログはタスクディレクトリの `notes/stage-1/stage-1-probe.log` |

## 2. クラスタ全体のベースライン（runbook §2.2。2026-10-19 00:42Z〜00:50Z）

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node、版 | 8 台 Ready。全台 v1.29.8、`containerd://2.3.6`。Server Version v1.29.8 |
| 2 | `/opt/bin` | control-plane 3 台: `kubelet-v1.29.8`、`kubectl-v1.29.8`、`etcdctl-3.5.12`、**`crictl-v1.28.0`**。worker 5 台: `kubelet-v1.29.8`、`kubectl-v1.29.8`、`etcdctl-3.5.12`、**`crictl-v1.29.0`**（runbook の表の「crictl v1.28.0」は control-plane のことで、worker は v1.29.0 だった。前の版の porkadot で入れたもの）。8 台とも `/opt/cni/bin/.porkadot-cni-plugins-version` は無い。kubelet は 8 台とも active |
| 3 | `/etc/etcd/pki` | 3 台とも `ca.crt`・`etcd.crt`・`etcd.key` が `644 root:root` |
| 4 | etcd、VIP | 3/3 healthy、v3.5.12、DB 55 MB。リーダーは **192.168.1.113（`57ec6f12ac7b683e`）**。raft term 23112、raft index 1402527421 が 3 台とも同じ。ID は .111 `21ab2aeb56731588`、.112 `fbb0c648cf5852a5`。VIP の `/readyz` は `ok`、`/version` は v1.29.8 |
| 5 | Running / Completed 以外の Pod | 0 個 |
| 5 | 再起動回数の多い Pod（5 回以上） | `metallb-system/speaker` 4 つ（12〜17）、`longhorn-system` の `longhorn-csi-plugin` 3 つ（4〜8）・`longhorn-manager-wn5sl`（7）・`engine-image-ei-c9fa6d45-tkjf7`（5）、`kube-system` の `cnidaria-2jx6x`（7）・`cnidaria-r7jbk`（5）・`kube-proxy-zvhx8`（5）、`monitoring` の `node-exporter-9kqs7`・`smart-exporter-hm5b6`（5）、`carib2`・`shja2` の `movies`（6） |
| 6 | Longhorn のボリューム | attached healthy 23、detached unknown 2（`myao/myao`、`homegallery/cg-data`。以前から）。degraded は 0 |
| 6 | Longhorn の replica | chirico 15（running 13、stopped 2）、duchamp 11（running 8、stopped 3）、oeilvert 17（running 16、stopped 1）、pablo 3（running 3） |
| 6 | replica 1 のボリューム | chirico: `monitoring/prometheus-...-1`（pvc-99c35b80）。oeilvert: `monitoring/prometheus-...-0`（pvc-625c8825）、`minio/export-minio-0`〜`3`。runbook §5.1 の表と同じ |
| 6 | instance-manager、engine image、node | instance-manager 4 つ（chirico、duchamp、oeilvert、pablo）とも running。engine image `longhorn-engine:v1.11.2` が deployed。Longhorn の node 4 つとも Ready、schedulable |
| 7 | cnidaria | `verify-nodes.sh` は 64 PASS、FAIL 0。8 つの cnidaria の Pod のログの error は 0、`no route` も 0（applied-nftables 1414）。`check-apps.sh`: nodes 8/8、Running でない Pod 0、IP の重複 0、hedgedoc の `db-postgresql-0` は Running（chirico）、192.168.1.200 と v6 の LB は 404、VIP の `/version` は 200 |
| 7 | NetworkPolicy | chirico の `table inet cnidaria` に `hedgedoc/db-postgresql` を含む行が 10 ある（set とジャンプ） |
| 8 | MetalLB | LoadBalancer の Service 11 個がアドレスを持つ。gated の `192.168.1.200` と `[...:ace::200]` の 80 は 404（応答あり）。`h2-sshd`（`::131`）、`natsumi-sshd`（`::132`）、`natsumi-sshd-myao`（`::133`）、`natsumi-sshd-aki`（`::134`）の 3222 は SSH のバナーを返す。minecraft は UDP なので確かめていない |
| 9 | NFS | braque（192.168.1.131）と fs の Service の NFS の PV は Bound（Released の 3 つ `codimd`、`codimd-backup`、`maildata` は以前から）。oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で、中身が読める。braque の nfsd は **DaemonSet の Pod `nfsd/nfsd-vt5k2`（hostNetwork）で動いている**（ホストの `nfs-server.service` は inactive。fraction-nfsd-to-fleet-infra のタスクで移ったもの）。2049 を listen している。`registry.fraction.jp/v2/` は 401（応答あり） |
| 10 | metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個。`apiserver_requested_deprecated_apis` は `metallb.io/v1beta1 addresspools`（`removed_release` なし）だけ |
| 11 | controller-manager と scheduler | どちらも .112 と .113 に 1 つずつ、.111 には無い |
| 12 | CSR | 無い |
| 13 | kube-system の Deployment と DaemonSet | 下の表 |
| 14 | Longhorn の設定（§2.6） | `concurrent-replica-rebuild-per-node-limit` `5`、**`replica-auto-balance` `disabled`**、`node-drain-policy` `block-if-contains-last-replica`、`default-data-locality` `best-effort`。どれも APPLIED が true |
| 15 | リーダー | controller-manager は `kube-controller-manager-577bb5f446-tm2wt`（.113）、scheduler は `kube-scheduler-bfdd48467-jsnf2`（.113） |
| 16 | MetalLB の告知ノード（§2.7） | 下の表 |
| 17 | leader election を使う controller の再起動回数 | `gated-system/gated` は chirico の `qnvq4` が 3、duchamp の `w4hw7` が 0。`longhorn-system` の CSI sidecar は 12 個のうち `csi-attacher-...-n2l6k`（chirico）、`csi-resizer-...-md2xx`（pablo）、`csi-snapshotter-...-l7qpx`（pablo）が 1、ほかは 0 |

kube-system の Deployment と DaemonSet（§2.2 の 13）:

| KIND | NAME | GEN | IMAGE |
|---|---|---|---|
| Deployment | coredns | 8 | `coredns/coredns:v1.10.1` |
| Deployment | kube-controller-manager | 22 | `kube-controller-manager:v1.29.8` |
| Deployment | kube-dns-autoscaler | 4 | `cluster-proportional-autoscaler-amd64:1.7.1` |
| Deployment | kube-scheduler | 21 | `kube-scheduler:v1.29.8` |
| Deployment | metrics-server | 1 | `metrics-server/metrics-server:v0.7.2` |
| DaemonSet | cnidaria | 2 | `ghcr.io/yuanying/cnidaria-cni:v0.1.1` |
| DaemonSet | kube-apiserver | 23 | `kube-apiserver:v1.29.8` |
| DaemonSet | kube-proxy | 19 | `kube-proxy:v1.29.8` |

MetalLB の告知ノード（speaker のログの IP ごとの最後の `serviceAnnounced`。`nodeAssigned` のイベントは消えていた。どれも 2026-10-18 12:18Z、段 C の .111 の後のもの）。runbook §2.7 の表と同じ:

| Service | `externalTrafficPolicy` | アドレス | 告知ノード |
|---|---|---|---|
| `kube-system/porkadot-kubernetes`（API の VIP） | Cluster | 192.168.1.101 | **pablo** |
| `gated-system/gated-v4`、`gated-v6` | Local | 192.168.1.200、`::200` | chirico |
| `fs/h2-sshd` | Cluster | `::131` | 192.168.1.112 |
| `natsumi/natsumi-sshd` | Cluster | `::132` | 192.168.1.111 |
| `natsumi/natsumi-sshd-myao` | Cluster | `::133` | duchamp |
| `natsumi/natsumi-sshd-aki` | Cluster | `::134` | 192.168.1.112 |

minecraft の 4 つ（`bds`、`bds-v4`、`minecraft2/bds`、`minecraft3/bds`）は speaker のログに告知の行が無かった。

ほかに読んだもの:

- `systemctl --failed`: braque の `systemd-networkd-wait-online.service` だけ（段 C と同じ）。ほかの 7 台は空
- oeilvert: `docker` が active、`devbox` のコンテナが動いている
- warning のイベント: `natsumi/natsumi-aki-0` の liveness の失敗（runner の socket、14 回）、`shja2`・`carib2` の `movies` の liveness・readiness の失敗（段 C の `summary.md` §2.1 と同じもの）だけ
- CronJob は 8 個（`notes/stage-1/baseline/cronjobs.txt`）

## 3. etcd のバックアップ（runbook §2.4）

| 項目 | 値 |
|---|---|
| コマンド | `porkadot etcd backup --config ./porkadot.yaml`（porkadot 0.30.0。00:45:32Z〜00:45:35Z、すべて `successful`） |
| 取ったメンバー | 192.168.1.111（root で `etcdctl snapshot save`、chown 1000:1000、chmod 0600 してから写し、ノードのものを消した） |
| ファイル | `etcd-2026-10-19T00:45:32+00:00.db`、モード 0600、55,107,616 バイト |
| sha256 | `08f87366aa0bee76bd6cf45511933e5092bb723fccc48cb1a916e2018c3b54ec` |
| 置き場所 | 段 1 の worktree の `./backup/`（`.gitignore` で除外。git には入れていない）。worktree を片付ける前に、メインの checkout の `backup/` へ移す |
| 前のバックアップとの比較 | メインの checkout の `backup/` の `etcd-2026-10-16T11:48:43+00:00.db`（55,107,616）、`etcd-2026-10-16T12:02:57+00:00.db`（55,124,000）と同じ桁 |
