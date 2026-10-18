# 段 C のまとめと完了の確認

本番 `fraction` の 8 台で、Ubuntu の `containerd` 2.2.1 を Docker の `containerd.io` 2.3.6 に置き換えた段 C（K8s は v1.29.8 のまま）の、全体のまとめと完了の確認（runbook §6）の記録。手順は `../../runbook-stage-c.md`（以下 runbook）。
時刻は UTC。各台の記録は同じディレクトリの `<ノード>.md`（control-plane は `192.168.1.11N.md`）、作業の前のクラスタ全体と戻すための控えは `baseline.md`。

## 1. 各台の作業（2026-10-18）

| 順 | ノード | 再起動 → Ready | cordon → uncordon | 監視（runbook §2.4）の FAIL | 記録 |
|---|---|---|---|---|---|
| 1 | chirico | 06:41:30 → 06:43:49 | 06:39:11 → 06:45:39 | 0 | `chirico.md` |
| 2 | duchamp | 07:59:25 → 08:01:45 | 07:54:35 → 08:02:51 | 0 | `duchamp.md` |
| 3 | pablo | 08:39:02 → 08:41:24 | 08:38:13 → 08:43:27 | VIP 2（pablo が VIP を告知していた） | `pablo.md` |
| 4 | braque | 09:21:26 → 09:24:31 | 09:21:19 → 09:26:28 | 0 | `braque.md` |
| 5 | oeilvert（`docker-ce` 29.9.1 へ） | 10:05:28 → 10:07:52 | 10:03:49 → 10:10:10 | 0 | `oeilvert.md` |
| 6 | 192.168.1.113 | 10:45:26 → 10:46:10 | 10:42:48 → 10:47:41 | VIP 6 | `192.168.1.113.md` |
| 7 | 192.168.1.112（etcd のリーダーを .113 へ移した） | 11:53:40 → 11:54:25 | 11:50:32 → 12:05:47 | VIP 6、LB 1 | `192.168.1.112.md` |
| 8 | 192.168.1.111 | 12:17:11 → 12:17:55 | 12:14:45 → 12:19:06 | VIP 7、LB 1 | `192.168.1.111.md` |

- 8 台とも `containerd.io=2.3.6-1~ubuntu.24.04~noble`（版を指定した）。どの台でも、入れ替えと kubelet の再起動ではそのノードの Pod は再起動せず、監視の FAIL も無かった
- ロールバック（runbook §7）は一度も行っていない

## 2. 完了の確認（runbook §6。2026-10-18 12:22Z〜12:34Z）

.111 の作業の後、様子見（15 分）の間とその終わり（12:33Z）に読み取りで確かめた。

| 項目 | 結果 |
|---|---|
| containerd、runc、Node | 8 台とも `containerd --version` が v2.3.6、`runc --version` が 1.5.1。`kubectl get nodes -o wide` の CONTAINER-RUNTIME が 8 台とも `containerd://2.3.6`、VERSION が v1.29.8、8 台 Ready |
| config | 8 台とも `/etc/containerd/config.toml` が `version = 3` で、md5 が `/root/k8u-stage-c/config.toml.before` と同じ（control-plane `1affd0b8924eee632fb2aeb566d78b55`、worker `665fb78e3b80c49c14575c184b3c5bcf`。ベースラインと同じ）。`containerd config dump` に `SystemdCgroup = true` |
| apt の pin | 8 台とも `apt-cache policy containerd.io` の Installed と Candidate が `2.3.6-1~ubuntu.24.04~noble`、優先度 1001。`apt-get -s full-upgrade` で `containerd.io` は上がらない（上がるのは control-plane の当たっていない Ubuntu の更新だけ: .111 は `snapd`、.112・.113 は `apparmor`、`libapparmor1`、`snapd`。worker は `0 upgraded`） |
| etcd、VIP | 3/3 healthy、リーダー .113（`57ec6f12ac7b683e`）、raft index がそろっている。VIP の `/livez` は `ok`、`/version` は v1.29.8 |
| apiserver、controller-manager、scheduler | kube-apiserver の DaemonSet 3/3。controller-manager と scheduler は 2/2 で、どちらも .112 と .113 に 1 つずつ（.111 には無い）。同じ master に同じ component が 2 つ載っていない |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached 2（`myao/myao`、`homegallery/cg-data`。ベースラインのとおり）。instance-manager 4 つ（chirico、duchamp、oeilvert、pablo）とも running、engine image `v1.11.2` deployed、Longhorn の node 4 つとも Ready・schedulable |
| Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit` `5`、`node-drain-policy` `block-if-contains-last-replica`（ベースラインと同じ）。**`replica-auto-balance` は `disabled` のまま**（段 C の間の扱い。runbook §2.6。ベースラインは `least-effort`。戻すかどうかと時期はユーザーが決める） |
| MinIO、Prometheus | `minio/minio` 4/4、Prometheus の `spec.replicas` 2 |
| cnidaria | 8 台の Pod が Ready、`verify-nodes.sh` 64 PASS、FAIL 0。`netcheck.sh` 168/168（.111 の作業の後、12:19Z）。chirico の `table inet cnidaria` に `hedgedoc/db-postgresql` の set とジャンプがある |
| MetalLB | gated の `192.168.1.200` と `[...:ace::200]` の 80 は 404（応答あり。ベースラインと同じ）。`h2-sshd`（`::131`）、`natsumi-sshd`（`::132`）、`natsumi-sshd-myao`（`::133`）、`natsumi-sshd-aki`（`::134`）の 3222 が SSH のバナーを返す。minecraft は UDP なので確かめていない（ベースラインと同じ） |
| NFS | braque と fs の Service の NFS の PV は Bound（Released の 3 つ `codimd`、`codimd-backup`、`maildata` はベースラインのとおり）。oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で、中身が読める |
| metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個。`apiserver_requested_deprecated_apis` は `metallb.io/v1beta1 addresspools` だけ（ベースラインと同じ） |
| devbox | oeilvert の `docker` と `devbox` が active、`devbox` のコンテナが動いている。`mosh.fraction.jp:3222` が SSH のバナーを返す（mosh で入れるかはユーザーが確かめる） |
| 失敗している unit | braque の `systemd-networkd-wait-online.service` だけ（ベースラインのとおり）。ほかの 7 台は空 |
| warning のイベント・ログ | 下の 2.1 |
| 監視の FAIL | 下の 2.2 |

### 2.1 warning のイベント・ログ

- 段 C で出たもので、runbook §8.1 にあるもの: containerd の `failed to unmarshal sandbox spec`、`Configuration migrated from version 3`、`failed check for fsverity support`、再起動の直後の `ContainerStatus ... NotFound`
- ノードの再起動の直後のもの: 再起動したノードの Pod の `NodeNotReady`、Node の `Rebooted` と `InvalidDiskCapacity`（kubelet の起動の直後の `Image garbage collection failed once` と同じもの）、speaker の `BackOff`（runbook §3.10 の 4、§8.3）、kubelet の起動の直後の 1 回の `validate CRI v1 runtime API` の失敗（control-plane。systemd が 10 秒後にやり直して上がる）
- control-plane の再起動の間の leader election の controller の再起動（runbook §5.3）: .113 で `csi-attacher`・`csi-resizer`、.112 で `gated`・`csi-snapshotter`、.111 で `gated`。どれもすぐに Running に戻った
- 段 C の作業と結びつかないもの: `carib2`・`shja2` の `movies`（braque の NFS の `/movies/*` を使う）の liveness / readiness の timeout が、braque の再起動（09:21Z）から 12:22Z まで間をおいて数回ずつ出ている。再起動は braque の再起動のときの 1 回（`braque.md` §5）と、.111 の作業の後の 1 回ずつ（`shja2` が 12:22:56Z に exit 2、`carib2` が 12:24:21Z に OOMKilled。どちらも .111 の作業で触っていない worker の上。`192.168.1.111.md` §7）。`natsumi/natsumi-aki-0` の liveness の timeout（runner の socket）が 11:52Z〜12:22Z に 4 回（再起動はしていない）。段 C の前から `movies` は再起動の多い Pod だった（`baseline.md` §2 の 4）
- kubelet、apiserver、kube-proxy、cnidaria、containerd のログに、上のもの以外の新しい warning は見ていない（各台の記録の §2.3〜§5）

### 2.2 監視（runbook §2.4）の FAIL

監視は台ごとに流し、ログはタスクディレクトリの `notes/stage-c/stage-c-probe.log` に足していった。段 C の全体で **VIP が 21 回、LB（gated-v4）が 2 回**。

| 原因 | VIP | LB |
|---|---|---|
| control-plane の再起動（runbook §5.3。apiserver が Endpoints から外れるまでの振り分け） | 19（.113 6、.112 6、.111 7） | 2（.112、.111。gated のリーダーの Pod が leader election lost で再起動した） |
| VIP を告知していたノードの再起動（pablo、§3.9） | 2 | 0 |
| それ以外（入れ替え、kubelet の再起動、drain、uncordon、worker の再起動） | 0 | 0 |

## 3. 残したこと、段 C の後に決めること

- **Longhorn の `replica-auto-balance` を `least-effort` に戻すかどうかと時期**（runbook §2.6、§6）。段 C の間は `disabled` にしてあり、今もそのまま
- 計画 §9.6 のとおり、1 日ほど様子を見てから段 1 へ進む
- 片付け（段 C の後にユーザーと決めるもの）: worker の古い Docker のリポジトリと鍵（runbook §8.5）、`rc` の `containerd.io` 1.6.8・`docker-ce` 20.10.18 と、`rc` の Ubuntu の `containerd`（purge はしない。runbook §8.7）、oeilvert の `ubuntu-fan`・`pigz`・`bridge-utils`（`autoremove` を勧められる）、各台の `/root/k8u-stage-c/` の控え
- containerd 2.3 の新しいパッチの扱いと、config の version 4 化は計画 §5.8、§10 のとおり
- control-plane の再起動の間の VIP の途切れと leader election の controller の再起動を無くす方法（runbook §5.3 の候補）は、K8s の段の dev の検証で確かめる
