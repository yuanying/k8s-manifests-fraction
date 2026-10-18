# 段 C のベースラインと戻すための控え

本番 `fraction` の段 C（containerd を Docker の `containerd.io` 2.3 系へ置き換える）に入る前に取った、クラスタ全体の読み取りの結果と、8 台で取った戻すための控えの記録。手順は `../../runbook-stage-c.md`（以下 runbook）。
時刻は UTC。1 台ごとの確認は、この記録と比べる。

## 1. 前提（runbook §1）

| 項目 | 結果 |
|---|---|
| kubeconfig（§1.1） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor`、`auth can-i delete pods -A` は `no`（2026-10-18 06:31Z） |
| 入れる版（§1.6） | **`containerd.io` 2.3.6-1~ubuntu.24.04~noble**（amd64・arm64 とも 2.3 系の最新）。**段 C の 8 台はすべてこの版にそろえる。** 2.4 系は 2.4.1-2、2.4.2-1、2.4.2-2 があるが入れない。`docker-ce` の最新は 5:29.9.1-1~ubuntu.24.04~noble（runbook の表と同じ） |
| 監視（§2.4） | 06:32Z に作業端末で開始。ログはタスクディレクトリの `notes/stage-c/stage-c-probe.log` |

§1.6 のコマンドは、`containerd.io` と `docker-ce` を 1 つの `sort -V | tail -12` に流すので、`docker-ce` の 12 行で埋まり `containerd.io` の行が出ない。`containerd.io` だけを別に流して確かめた（runbook を直した）。

## 2. クラスタ全体のベースライン（runbook §2.3。2026-10-18 06:32Z〜06:34Z）

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node、版 | 8 台 Ready。全台 v1.29.8、Ubuntu 24.04.5、`containerd://2.2.1`。control-plane は 6.8.0-1065-raspi、worker は 6.8.0-147-generic。Server Version は v1.29.8 |
| 2 | ノードの containerd、runc、config | 8 台とも `containerd` 2.2.1-0ubuntu1~24.04.3、`runc` 1.3.4-0ubuntu1~24.04.1、config は `version = 3`。md5 は control-plane 3 台が `1affd0b8924eee632fb2aeb566d78b55`、worker 5 台が `665fb78e3b80c49c14575c184b3c5bcf`。worker 5 台に `containerd.io` 1.6.8-1 が `rc`、oeilvert に `docker-ce` 5:20.10.18 も `rc`。oeilvert は `docker.io` 29.1.3-0ubuntu3~24.04.2 |
| 2 | apt のファイル | 全台 `sources.list.d/ubuntu.sources`、`preferences.d/ubuntu-pro-esm-apps`・`ubuntu-pro-esm-infra`。braque・chirico・duchamp は `docker.list.disabled-20261017`、pablo は `docker.list.disabled-20261018`、この 4 台に `keyrings/docker.gpg`。oeilvert は `third-party.sources`。control-plane の `keyrings/` は空 |
| 2 | 当たっていない Ubuntu の更新 | worker 5 台は 0。.111 は `snapd`、.112・.113 は `apparmor`、`libapparmor1`、`snapd`（段 C では当てない） |
| 2 | `systemctl --failed` | braque の `systemd-networkd-wait-online.service` だけ。ほかの 7 台は空 |
| 3 | etcd | 3/3 healthy、v3.5.12、DB 55 MB。リーダーは 192.168.1.112（`fbb0c648cf5852a5`）。raft term 23111、raft index 1402195343 が 3 台とも同じ。ID は .111 `21ab2aeb56731588`、.113 `57ec6f12ac7b683e` |
| 3 | VIP | `https://192.168.1.101:6443/readyz` は `ok`、`/version` は v1.29.8 |
| 4 | Running / Completed 以外の Pod | 0 個 |
| 4 | 再起動回数の多い Pod（5 回以上） | `metallb-system/speaker` 4 つ（10〜15）、`longhorn-system/longhorn-csi-plugin` 4 つ（7〜12）、`longhorn-manager` 4 つ（5〜10）、`kube-system/cnidaria-2jx6x`（5）、`carib2`・`pondo2`・`shja2` の `movies`（7。直近 13 分前） |
| 5 | Longhorn のボリューム | attached healthy 23、detached unknown 2（`myao/myao`、`homegallery/cg-data`。以前から）。degraded は 0 |
| 5 | Longhorn の replica | chirico 17（running 15、stopped 2）、duchamp 10（running 8、stopped 2）、oeilvert 18（running 17、stopped 1）。stopped は detached の 2 つの replica 4 つと、`natsumi/natsumi-aki`（pvc-e224cffa）の duchamp の 1 つ（前タスクから） |
| 5 | instance-manager、engine image、node | instance-manager 4 つ（chirico、duchamp、oeilvert、pablo）とも running。engine image `longhorn-engine:v1.11.2` が deployed。Longhorn の node 4 つとも Ready、schedulable |
| 6 | Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit` `5`、`replica-auto-balance` `least-effort`、`node-drain-policy` `block-if-contains-last-replica`、`replica-replenishment-wait-interval` `6000`、`current-longhorn-version` v1.11.2 |
| 7 | cnidaria | `verify-nodes.sh` は 64 PASS、FAIL 0。cnidaria のログは errors 0、applied-nftables 1430。`check-apps.sh`: nodes 8/8、Running でない Pod 0、IP の重複 0、hedgedoc の db-postgresql-0 は Running（chirico）、192.168.1.200 と v6 の LB は 404、VIP の `/version` は 200 |
| 7 | NetworkPolicy | chirico の `table inet cnidaria` に `pods_hedgedoc/db-postgresql/v4`・`v6` の set と、`egress_`・`ingress_hedgedoc/db-postgresql` へのジャンプがある |
| 8 | MetalLB | LoadBalancer の Service 11 個がアドレスを持つ。gated の `192.168.1.200` と `[...:ace::200]` の 80 は 404（応答あり）。443 は SNI を付けない `curl` では 000（ホスト名が無いため。以後も同じ形で比べる）。`h2-sshd`（`::131`）、`natsumi-sshd`（`::132`）、`natsumi-sshd-myao`（`::133`）、`natsumi-sshd-aki`（`::134`）の 3222 は SSH のバナーを返す。minecraft は UDP なので確かめていない |
| 9 | NFS | braque（192.168.1.131）と fs の Service の NFS の PV は Bound（Released の 3 つ `codimd`、`codimd-backup`、`maildata` は以前から）。oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で、中身が読める |
| 10 | metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個。`apiserver_requested_deprecated_apis` は `metallb.io/v1beta1 addresspools`（`removed_release` なし）だけ |
| 11 | controller-manager と scheduler | どちらも .112 と .113 に 1 つずつ、.111 には無い（runbook と同じ）。同じ master に同じ component が 2 つ載っていない |

ほかに読んだもの:

- replica 1 のボリュームと replica の置き場所は runbook §2.6 の表と同じ。chirico は `monitoring/prometheus-kube-prometheus-db-prometheus-kube-prometheus-1`（pvc-99c35b80、Pod も chirico）。prometheus-0（pvc-625c8825）は duchamp、MinIO の 4 つ（minio-0〜3）は replica がすべて oeilvert。Prometheus の `spec.replicas` は 2、`minio/minio` は 4/4
- CronJob は 9 個（schedule は `notes/stage-c/baseline/cronjobs.txt`）
- **control-plane 3 台のホストの時刻は Asia/Tokyo（JST）**、worker は UTC。runbook §0 の「ノードのホストの時刻も UTC」は control-plane には当てはまらない（runbook を直した）

読み取りの出力はタスクディレクトリの `notes/stage-c/baseline/` に置いた（リポジトリには入れない）。

## 3. 戻すための控え（runbook §2.7。2026-10-18 06:33:55Z〜06:34:10Z）

chirico で Docker のリポジトリを足す前に、8 台すべてで取った。8 台とも rc 0。どの deb も Ubuntu の archive から落ちた（Docker のリポジトリを足す前）。

| ノード | `config.toml.before` の md5（`/etc/containerd/config.toml` と同じ） | deb |
|---|---|---|
| 192.168.1.111〜113 | `1affd0b8924eee632fb2aeb566d78b55` | `containerd_2.2.1-0ubuntu1~24.04.3_arm64.deb`、`runc_1.3.4-0ubuntu1~24.04.1_arm64.deb` |
| braque、chirico、duchamp、pablo | `665fb78e3b80c49c14575c184b3c5bcf` | `containerd_2.2.1-0ubuntu1~24.04.3_amd64.deb`、`runc_1.3.4-0ubuntu1~24.04.1_amd64.deb` |
| oeilvert | `665fb78e3b80c49c14575c184b3c5bcf` | 上の amd64 の 2 つと `docker.io_29.1.3-0ubuntu3~24.04.2_amd64.deb` |

sha256（同じ arch のノードでは同じ値だった）:

| deb | sha256 |
|---|---|
| `containerd_2.2.1-0ubuntu1~24.04.3_arm64.deb` | `e12495f100f025750ca91c07bab3a58c674afb1576fe55516608a8daa4d067bd` |
| `runc_1.3.4-0ubuntu1~24.04.1_arm64.deb` | `725a27bbdd5f58d7059ed25d88f14f2d45f6a1ce089585eddc715e04d4a3f79f` |
| `containerd_2.2.1-0ubuntu1~24.04.3_amd64.deb` | `459a0184cc631c17eb4a625392f749fa753627b4ddba196919e0666a6206d92a` |
| `runc_1.3.4-0ubuntu1~24.04.1_amd64.deb` | `6ddd64ed7ef1693dd95620a2b1148a4187ef4fe0819c3c3049fad9385ecfd5dc` |
| `docker.io_29.1.3-0ubuntu3~24.04.2_amd64.deb`（oeilvert） | `bd5c22d42d4ce3021958b7a8d627701597f61a1a9867ba83fe3c841f04991e3a` |

- `dpkg-deb -f` で、各 deb の Package・Version・Architecture が上の名前どおりであることを確かめた
- root の `apt-get download` の `Download is performed unsandboxed as root` の注意は出たが、どれも落とせた
