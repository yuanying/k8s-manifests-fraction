# oeilvert の段 C の作業記録

oeilvert（192.168.1.82）の containerd を、Ubuntu の `containerd` 2.2.1 から Docker の `containerd.io` 2.3.6 に置き換え、あわせて Ubuntu の `docker.io` 29.1.3 を Docker の `docker-ce` / `docker-ce-cli` 29.9.1 に移した記録。手順は `../../runbook-stage-c.md`（以下 runbook）の §3 と §4。
時刻は UTC。段 C の 5 台目で、worker の最後。1 台目は `chirico.md`、2 台目は `duchamp.md`、3 台目は `pablo.md`、4 台目は `braque.md`、クラスタ全体のベースラインと戻すための控えは `baseline.md`。

oeilvert は MinIO の 4 つと prometheus の replica 1 のボリュームの replica を持ち、ホストの Docker で devbox（`mosh.fraction.jp`）が動く。runbook §0 の ✋✋（Docker の入れ替えの前の承認）は、devbox を今まったく使っていないため、ユーザーが不要とした（2026-10-18）。✋ として coordinator に知らせてから進めた。

## 1. 事前の読み取り（2026-10-18 09:57Z〜）

### 1.1 クラスタ（runbook §2.3、§3.12）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。2.3.x のノード: braque、chirico、duchamp、pablo（`containerd://2.3.6`）、2.2.1 のノード: oeilvert と control-plane の 3 台 |
| etcd、VIP | 3/3 healthy、リーダー: 192.168.1.112、raft term 23111、raft index: 1402267929（そろっている）。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached（ベースラインのもの）: `myao/myao`、`homegallery/cg-data` |
| Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit`: `5`、`replica-auto-balance`: `disabled`（段 C の間の扱い）、`node-drain-policy`: `block-if-contains-last-replica`（`replica-replenishment-wait-interval` は `6000`、`default-data-locality` は `best-effort`） |
| controller-manager と scheduler の置き場所 | （worker なので無し） |
| `auth can-i delete pods -A`（`fraction-auditor`） | `no` |
| 入れる版（runbook §1.6） | `containerd.io` の 2.3 系の最新は 2.3.6-1 のまま（1 台目と同じ版を入れる）。`docker-ce` / `docker-ce-cli` の最新は 5:29.9.1-1 |
| `verify-nodes.sh` | 64 PASS、FAIL 0。cnidaria のログの error 0 |
| `check-apps.sh` | braque の後（`braque.md` §7、09:55Z）の出力と同じ |
| `minio/minio`、Prometheus の `spec.replicas` | 4/4、2 |

braque の後の runbook §3.12 は 09:55Z に確かめてある（`braque.md` §7）。

### 1.2 対象のノード（runbook §3.3、§4.1）

| 項目 | 値 |
|---|---|
| Node | Ready、`containerd://2.2.1`、6.8.0-147-generic、起動 2026-10-17 23:07:59Z |
| `containerd --version` / `runc --version` | 2.2.1 / 1.3.4-0ubuntu1~24.04.1 |
| `/etc/containerd/config.toml` | `version = 3`、md5: `665fb78e3b80c49c14575c184b3c5bcf` |
| 控え（`/root/k8u-stage-c/`） | config.toml.before（md5 同じ）、`containerd_2.2.1-0ubuntu1~24.04.3_amd64.deb`、`runc_1.3.4-0ubuntu1~24.04.1_amd64.deb`、`docker.io_29.1.3-0ubuntu3~24.04.2_amd64.deb`（sha256 は `baseline.md` と同じ） |
| `apt-cache policy containerd containerd.io runc docker.io docker-ce` | `containerd`、`runc`、`docker.io` は Ubuntu の版で入っている。`containerd.io`（1.6.8-1）と `docker-ce`（5:20.10.18）は候補なし（`/var/lib/dpkg/status` だけ） |
| `dpkg -l` | `containerd.io` 1.6.8-1 と `docker-ce` 20.10.18 が `rc`。`docker.io` の Recommends の `ubuntu-fan`、`pigz`、`bridge-utils` が入っている |
| `/etc/apt/sources.list.d/`、`preferences.d/`、`keyrings/` | `third-party.sources`（jammy、`Enabled: no`）・`ubuntu.sources` / `ubuntu-pro-esm-apps`、`ubuntu-pro-esm-infra` / 空（runbook のとおり） |
| 当たっていない Ubuntu の更新 | 0 |
| イメージの数（`crictl images -q`） | 73 |
| `systemctl --failed` | 無い |
| ZFS、ディスク | `zpool status -x` は `all pools are healthy`。`/` の空きは 82G |
| iSCSI | `iscsid.socket`・`multipathd` が active |
| Docker（runbook §4.1） | `docker.io` 29.1.3、Storage Driver **overlay2**、Docker Root Dir `/var/lib/docker`、Cgroup Driver systemd。Images 1212（タグは 202、`docker images -a -q` は 1245 行）、volume 1 つ。コンテナは `devbox`（動いている）と止まった 2 つで、どれも restart policy は `no`。`/etc/docker/daemon.json` は `ipv6: true`、`fixed-cidr-v6: fde0:17ad:84c5:82::/64` |
| devbox | `devbox.service` が active。3222 に繋いでいる SSH のセッションは無い |
| Pod と再起動回数（控え） | 48 個。コントローラを持たない Pod は無い |
| 最後の replica を持つボリューム（runbook §2.6） | **`minio/export-minio-0`〜`3`（4 つ）と `monitoring/prometheus-kube-prometheus-db-prometheus-kube-prometheus-1`**（どれも replica 1 で、replica は oeilvert）。見込みどおり。replica の数は chirico 15、duchamp 11、oeilvert 17、pablo 3（braque の後と同じ） |
| MetalLB の告知 | oeilvert の speaker が告知しているのは gated-v6（`2405:6581:8580:301:ace::200`）だけ（speaker のログの `serviceAnnounced`。`nodeAssigned` のイベントは消えていた）。VIP（`porkadot-kubernetes`）は pablo、gated-v4 は chirico |

最後の replica があるので、runbook §3.8 のとおり `node-drain-policy` を変え、MinIO と Prometheus を止める。`replica-auto-balance` は既に `disabled` なので、切り替えるのは `concurrent-replica-rebuild-per-node-limit` だけ。

作業の時間帯（10:00〜10:30Z）は unattended-upgrades の自動再起動（04:00Z）にかからない。

## 2. 入れ替え（runbook §3.4、§4.2）

### 2.1 リポジトリ、鍵、pin（09:59:33Z〜09:59:38Z）

- 鍵の fingerprint: `9DC858229FC7DD38854AE2D88D81803C0EBFCD88`（一致）
- `docker.sources` の `Architectures` は `amd64`
- `apt-cache policy containerd.io` の Candidate と優先度: `2.3.6-1~ubuntu.24.04~noble`。2.3 系の行（2.3.3-1〜2.3.6-1）が 1001、2.4 系と 2.2 系以下の行は 500
- `docker-ce`、`docker-ce-cli` の Candidate は `5:29.9.1-1~ubuntu.24.04~noble`（pin しない。runbook §4.4）

### 2.2 `containerd.io`、`docker-ce`、`docker-ce-cli` を入れる（10:00:00Z〜10:00:33Z）

- `apt-get install -s --no-install-recommends` の結果: `0 upgraded, 3 newly installed, 3 to remove`。Remv `docker.io`・`containerd`・`runc`、Inst `containerd.io` 2.3.6・`docker-ce-cli` 29.9.1・`docker-ce` 29.9.1。runbook §4.2 の 1 のとおり
- 10:00:00 に `systemctl stop devbox`、10:00:11 に `systemctl stop docker docker.socket`（どちらも rc 0。restart policy のあるコンテナが無いので、待ちは devbox の `docker stop` の 10 秒だけ）
- 10:00:11〜10:00:33 に、版を指定して入れた（`containerd.io=2.3.6-1~ubuntu.24.04~noble docker-ce=5:29.9.1-1~ubuntu.24.04~noble docker-ce-cli=5:29.9.1-1~ubuntu.24.04~noble`）。rc 0
- conffile の扱い: ほかの worker と同じく `Using current old file as you requested` は出ず、手元の config が残った（md5 が控えと同じ）。`docker-ce` は `/etc/default/docker` と `/etc/init.d/docker` の新しい版を入れ、`/etc/init/docker.conf` を消した（どれも `docker.io` の conffile。`/etc/docker/daemon.json` はそのまま）
- needrestart が `systemctl restart containerd.service` を流し、`No containers need to be restarted.` と出した
- apt は `mailcap` と `ubuntu-fan` を autoremove の候補に挙げた。runbook §4.2 の 3 のとおり、autoremove は流していない。`docker.io` と `containerd` は `rc` で残った

### 2.3 ノードでの確認（runbook §3.6、§4.2 の 6）

| 項目 | 結果 |
|---|---|
| `containerd --version` / `runc --version` | `containerd containerd v2.3.6 ee2735368117d2eb259779949d5e75cdafec9761` / `runc version 1.5.1` |
| config の先頭と md5（控えと同じか） | `version = 3`、`665fb78e3b80c49c14575c184b3c5bcf`（同じ） |
| `containerd config dump`（version、SystemdCgroup、sandbox） | `version = 4`、`SystemdCgroup = true`、`sandbox = 'registry.k8s.io/pause:3.10.1'` |
| journal の error / warning（§8.1 のもの以外） | 無い。`Configuration migrated from version 3` と `failed check for fsverity support` が containerd の起動ごと（10:00:21Z、10:00:31Z）に出た。`unmarshal sandbox spec` は 110 行 |
| `ctr deprecations list` | 空 |
| `crictl info` / イメージの数（入れる前 → 後） | 応答する / 73 → 73 |
| `apt-cache policy containerd.io` | Installed と Candidate が 2.3.6-1、優先度 1001 |
| Pod の再起動回数 | 控えと同じ |
| Docker | `docker version` は 29.9.1（server、client）。**Storage Driver は overlay2 のまま**、Docker Root Dir `/var/lib/docker`、Cgroup Driver systemd、containerd version `ee27353…`（2.3.6）。Images 1212、タグの一覧（202）は控えと同じ（`diff` が空）、`docker images -a -q` の md5 も同じ。volume は元の 1 つ。`docker network inspect bridge` は IPv6 が有効で `fde0:17ad:84c5:82::/64` がある |
| iptables | v4・v6 とも FORWARD の先頭が `DOCKER-USER`、`DOCKER-FORWARD`、3 番目が `CNIDARIA-FWD`（runbook §4.2 の 6 の見込みどおり）。v6 の policy は DROP |

`/etc/docker/daemon.json` に `containerd-snapshotter` の設定を足す必要は無かった（runbook §4.2 の 6。前から入っていた Docker の `/var/lib/docker` が overlay2 なので、Docker 29.9.1 はそのまま overlay2 を使った）。

### 2.4 Longhorn の設定の切り替えと kubelet の再起動（runbook §3.7、§4.2 の 5）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 10:00:59 | ✋ `infra-admin` のトークンを発行（3h） | 作業端末の 600 のファイルに置いた。`auth can-i patch nodes` が yes |
| 10:01:08 | ✋ `concurrent-replica-rebuild-per-node-limit` を `0` | 直前の値は `5`。読み直して APPLIED true。`replica-auto-balance` は既に `disabled`、`node-drain-policy` はここでは変えない |
| 10:01:19 | ✋ `systemctl restart kubelet` | |

- 10:00:58 に、トークンのファイルができる前に patch を流してしまい、`infra-auditor` の権限で `Forbidden` になった（変更なし）。作業端末のコマンドを並べて流した誤りで、10:01:08 に流し直した
- Node と CONTAINER-RUNTIME: Ready、`containerd://2.3.6`（40 秒後に確認）
- Pod の再起動回数（控えとの差）: 48 個とも同じ（`diff` が空）
- kubelet の journal: 再起動の前の kubelet が、containerd の再起動の間（10:00:31Z）に `containerd.sock: connect: no such file or directory` を出した。再起動の後の kubelet は、起動の直後に `Image garbage collection failed once`、crio の factory の登録の失敗（info）、`Failed to trigger a manual run`（info）を出しただけ
- Longhorn の replica は動かなかった（kubelet の再起動の前後で `replicas.longhorn.io` の一覧が同じ）
- 監視（runbook §2.4）の FAIL: 無い

### 2.5 devbox を起こす（runbook §4.2 の 7）

- 10:02:07 に `systemctl start devbox`（rc 0）。`docker ps` に `devbox`（`registry.fraction.jp/yuanying/devbox-amd64`）。3222・8080・9090（tcp）、60000〜60010（udp）が v4・v6 で開いた。イメージは残っていたので pull し直していない
- 作業端末から `192.168.1.82:3222` と、`mosh.fraction.jp` の A レコード（119.150.71.160）の 3222 に繋ぐと、どちらも `SSH-2.0-OpenSSH_9.6p1` が返る。devbox は使っていないので、ユーザーにログインまでは確かめてもらっていない
- `mosh.fraction.jp` の AAAA レコードは `2405:6581:8580:301:ace::200`（gated-v6 の LoadBalancer。80 と 443 だけ）で、v6 の 3222 には繋がらない。入れ替えの前からの構成で、この作業とは関係が無い

devbox が止まっていたのは 10:00:00〜10:02:07 の約 2 分。

## 3. drain（runbook §3.8）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 10:03:00 | ✋ `node-drain-policy` を `allow-if-replica-is-stopped` | 読み直して APPLIED true |
| 10:03:00 | ✋ `minio/minio` を 0、Prometheus `monitoring/kube-prometheus` の `spec.replicas` を 0 | |
| 10:03:44 | 6 つのボリューム（MinIO の 4 つ、prometheus-0、prometheus-1）が detached | replica は stopped（prometheus-0 のものは chirico、ほかの 5 つは oeilvert） |
| 10:03:49 | ✋ `cordon oeilvert` | コントローラを持たない Pod は無い |
| 10:03:50〜10:04:25 | ✋ `drain oeilvert --ignore-daemonsets --delete-emptydir-data --timeout=20m` | rc 0、`node/oeilvert drained`（35 秒）。`--force` は要らなかった |

- 退いた Pod は 37 個。`instance-manager-…` の evict が PDB で 3 回待たされてから通った（ほかの worker と同じ。Longhorn がボリュームを外し終えるまで）
- drain の後、Longhorn は attached healthy 6、attached degraded 11、detached 8（ベースラインの 2 つと、止めた 6 つ）。oeilvert の 17 の replica は stopped で、ほかのノードに代わりの replica は作られていない（rebuild-limit が 0 のため。`replicas.longhorn.io` のボリュームとノードの組が事前と同じ）
- **`homegallery/api` は Deployment の `nodeSelector` が `kubernetes.io/hostname: oeilvert` なので、drain から uncordon まで Pending になった**（10:04Z〜10:10Z）。前タスクの OS 更新と同じで、止まってよいことはユーザーが決めている（OS 更新の手順書 §3.3）
- oeilvert の追加の確認（OS 更新の手順書 §3.3）: devbox を使っている人はいない（§1.2）。作業の時間帯は自動再起動の 04:00Z にかからない

## 4. 再起動（runbook §3.9）

- 10:05:28 に `systemctl reboot`。kernel の起動は 10:07:26（`uptime -s`）、containerd は 10:07:41、SSH は 10:07:45 に戻った。Node は 10:07:52 に Ready（SchedulingDisabled）に戻った（Ready の lastTransitionTime）。再起動から Ready まで約 2 分 24 秒（前タスクの約 2 分と同じくらい）
- boot id は `50807d81-…` から `d22340c9-…` に変わった
- MetalLB: gated-v6（`::200`）の告知は、**drain の時点（10:03:56Z）で chirico に移っていた**。gated の Service（v4・v6）は `externalTrafficPolicy: Local` で、告知は gated の Pod のあるノードに付いていく。drain で oeilvert の gated の Pod が duchamp に移ったので、再起動の前に oeilvert は何も告知していなかった（§8 のとおり runbook を直した）
- 監視（runbook §2.4）の FAIL: **無い**（VIP、LB とも 0）。gated-v6（`http://[2405:6581:8580:301:ace::200]/`）も drain の後（10:05Z の少し前）から 8 分間 1 秒ごとに見て、失敗は 0

## 5. 再起動の後の確認（runbook §3.10、§4.3）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready,SchedulingDisabled、v1.29.8、`containerd://2.3.6`。ラベルが残っている（`node-role.kubernetes.io/simone`、`role=worker`、`tgtd.unstable.cloud/storage`、`zfs.unstable.cloud/storage` など） |
| 2 | cnidaria の Pod | `cnidaria-tfpbp` は **CrashLoopBackOff にならず**、再起動の分だけ restart 2 → 3、10:08:01Z には 1/1 Running。起動の後のログの error は 0 |
| 3 | `verify-nodes.sh` | 64 PASS、FAIL 0（ベースラインと同じ。差は cnidaria のログの `applied-nftables` の数だけ。Pod の再起動で数え直したもの） |
| 4 | DaemonSet の Pod | 8 つとも 10:09Z に Running。再起動回数は `cnidaria`、`kube-proxy`、`engine-image`、`node-exporter`、`smart-exporter` が +1、`longhorn-manager`（2 コンテナ）が +2、`longhorn-csi-plugin`（3 コンテナ）が +3（どれも再起動の分だけ。csi-plugin は CrashLoopBackOff にならなかった）。**speaker は +2**: 起動の直後（10:07:54Z）に `dial tcp 10.254.0.1:443: connect: connection refused` で 1 回落ち、10 秒の CrashLoopBackOff の後に Running（runbook §3.10 の 4 のとおり） |
| 5 | ストリーミング | `speaker`、`cnidaria` のログが読める |
| 6 | iptables | v4・v6 とも `CNIDARIA-FWD` へのジャンプが FORWARD の先頭。v4 の policy は ACCEPT、v6 の policy は DROP（Docker が DROP にする。runbook §4.3 のとおり）。Docker の `DOCKER-USER` と `DOCKER-FORWARD` へのジャンプは先頭の 3 行に無い |
| 7 | ディスク、ZFS | `/var/lib/longhorn`（`zd0`、zvol）と `/var/lib/longhorn2`（`sdb1`）がマウントされている。`zpool status -x` は `all pools are healthy`。`/` は空き 82G |
| 8 | iSCSI | `iscsid.socket` と `multipathd` が active、`iscsid.service` は inactive（ほかの worker と同じ） |
| 9 | DNS | `porka-dummy01` に 10.254.0.10、検索ドメイン `default.svc.cluster.local svc.cluster.local cluster.local` |
| 10 | 失敗している unit | 無い（ベースラインと同じ） |
| 11 | apt | Candidate `2.3.6-1~ubuntu.24.04~noble`、優先度 1001。`apt-get -s full-upgrade` は `0 upgraded, 0 newly installed, 0 to remove` |
| 12 | `unmarshal sandbox spec` の数 | 60（起動の後） |
| — | oeilvert: Docker、devbox | `docker`、`devbox` が active（`devbox.service` が起動で自動で上がった）。`docker ps` に devbox。Storage Driver overlay2、Images 1212、Server Version 29.9.1。3222 を v4・v6 で listen |
| — | oeilvert: ordering cycle、cluster-dns、automount、NFS | `journalctl -b 0 \| grep "ordering cycle"` は 0 行。`cluster-dns.service` は `BindsTo=sys-subsystem-net-devices-porka\x2ddummy01.device`、`After` と `Wants` に `systemd-networkd.service`。`home-yuanying-shared-data.automount`・`-h.automount` が `active (waiting)`、`home-yuanying-shared-nfs.mount` が active で、`/home/yuanying/shared/nfs`（braque の NFS）の中身が読める |

ほかに見たもの: containerd は v2.3.6、runc 1.5.1、config は `version = 3` で md5 が控えと同じ。`config dump` は `version = 4`、`SystemdCgroup = true`、`pause:3.10.1`。`ctr deprecations list` は空。イメージは 73 のまま。起動の後の containerd の journal は、`Configuration migrated from version 3` と `failed check for fsverity support` の warning が 1 行ずつ、runbook §8.1 の `ContainerStatus ... NotFound`（10:07:52Z）が 11 行。ほかの error は無かった。
kubelet は起動の直後（10:07:42Z）に 1 度 `validate CRI v1 runtime API for endpoint "/run/containerd/containerd.sock"` で落ち、systemd が 10 秒後にやり直して上がった（containerd の socket ができる前に起動したもの。chirico と同じ。`chirico.md` §5）。

## 6. uncordon と後始末（runbook §3.11）

- uncordon の時刻: 10:10:10（cnidaria が Ready になり `verify-nodes.sh` が通った後）。cordon から 6 分 21 秒
- 戻した workload: 10:10:11 に `minio/minio` を 4、Prometheus の `spec.replicas` を 2 に戻した。MinIO の 4 つと prometheus の 2 つの Pod は Running、ボリュームは attached になった。`homegallery/api` も oeilvert で Running に戻った
- Longhorn の node（chirico、duchamp、oeilvert、pablo）が Ready、schedulable であることを確かめてから、10:10:15 に `concurrent-replica-rebuild-per-node-limit` を `5`、`node-drain-policy` を `block-if-contains-last-replica` に戻した（APPLIED true）。切り替えから 9 分 7 秒。`replica-auto-balance` は指示どおり `disabled` のまま
- 再同期が終わった時刻: 10:26:34（attached healthy 23、detached 2。degraded 0）。設定を戻してから 16 分 19 秒。10:13:47 には degraded は 1 つ（`fs/h2`、pvc-c4944b75）だけになり、その replica の rebuild が 10:26:32 に終わった。ほかの 10 個は oeilvert の stopped の replica をそのまま再同期した
- Running / Completed 以外の Pod: 0 個
- `netcheck.sh`: 10:26:59〜10:27:19 に `up` → `run` → `down`。`PASS 168 / 168, pods 8/8`。namespace は消した
- `check-apps.sh`: 事前（09:58Z）の出力と同じ（差が無い）
- トークンの破棄: 10:27:26 に作業端末のファイルを消した。SA のトークンは個別に失効できないので、サーバーの側では発行から 3 時間（13:01 ごろ）で切れる

### 6.1 Longhorn の replica の置き場所

再同期の後（10:27Z）、replica の数はノードごとに chirico 15、duchamp 11、oeilvert 17、pablo 3 で、事前と同じ。同じボリュームの replica が同じノードに 2 つ載ったものは無い。running 以外の replica は事前と同じ（`myao`・`cg-data` の stopped、`ero-data`（pvc-baa41130）と `natsumi-aki`（pvc-e224cffa）の duchamp のもの）。

ただし、**prometheus の 2 つのボリュームの replica の置き場所が入れ替わった**。Prometheus を 2 に戻したとき、prometheus-0 の Pod が oeilvert、prometheus-1 の Pod が chirico に載り（事前は 0 が chirico、1 が oeilvert）、data locality の `best-effort` で、prometheus-1 のボリューム（pvc-99c35b80）は 10:13:52 に chirico に、prometheus-0 のボリューム（pvc-625c8825）は 10:15:20 に oeilvert に replica を作り直し、古い replica を消した。

| ボリューム | 事前の replica | 後の replica | 後の Pod |
|---|---|---|---|
| prometheus-0（pvc-625c8825） | chirico | **oeilvert** | oeilvert |
| prometheus-1（pvc-99c35b80） | oeilvert | **chirico** | chirico |
| export-minio-0〜3 | oeilvert | oeilvert（変わらない） | minio-0 は oeilvert、minio-1 は chirico、minio-2 は pablo、minio-3 は duchamp |

MinIO のボリュームは data locality が `disabled` なので、Pod が別のノードに載っても replica は oeilvert のまま（`pablo.md` §6.1 と同じ）。
**control-plane は Longhorn の node ではないので、この置き場所は段 C の残り（control-plane の 3 台）には効かない。** 段 C の後の作業で worker を drain するときは、prometheus-0 と MinIO の 4 つの最後の replica が oeilvert、prometheus-1 の最後の replica が chirico にあるものとして読み直す。

## 7. 次の 1 台へ進む条件（runbook §3.12）

5 台目なので、runbook の既定の 30 分をおいて、2026-10-18 10:39Z に確かめた。**すべて満たした**（Longhorn の `replica-auto-balance` は `disabled` を正しい値として扱う。runbook §2.6）。

| 条件 | 結果 |
|---|---|
| 全 8 台の Node が Ready。終えたノードが `containerd://2.3.x`、まだのノードが `containerd://2.2.1` | 8 台 Ready。worker の 5 台（braque、chirico、duchamp、oeilvert、pablo）が `containerd://2.3.6`（v1.29.8）、control-plane の 3 台が `containerd://2.2.1` |
| 終えたノードの cnidaria の Pod が Ready で、`verify-nodes.sh` が全 PASS | `cnidaria-tfpbp` 1/1 Running（restart 3 のまま）。64 PASS、cnidaria のログの error 0 |
| etcd 3/3 healthy、VIP が応答する | 3/3 healthy、リーダー .112、raft term 23111、index 1402283811 でそろっている。`/readyz` は `ok` |
| Running / Completed 以外の Pod が、ベースラインから増えていない | 0 個 |
| Longhorn のボリュームが healthy。再同期が終わっている | attached healthy 23、detached 2（ベースラインのもの）。replica の一覧は 10:27Z（§6.1）と同じ |
| Longhorn の設定。`minio/minio` が 4、Prometheus の `spec.replicas` が 2 | `concurrent-replica-rebuild-per-node-limit` `5`、`node-drain-policy` `block-if-contains-last-replica`（元の値）。`replica-auto-balance` は `disabled`（段 C の間の扱い）。MinIO 4/4、Prometheus 2 |
| `netcheck.sh`、`check-apps.sh` がベースラインと同じ | netcheck 168/168（10:27Z）。`check-apps.sh` は事前（09:58Z）と 10:39Z で同じ |
| 終えたノードが 30 分以上、再起動や NotReady なしで動いている | Ready は 10:07:52Z から変わらない（約 31 分）。boot id も同じ（`d22340c9-…`）。oeilvert の DaemonSet の Pod の再起動回数は 10:09Z から増えていない。`docker`、`devbox` は active |

監視（runbook §2.4）は 09:58Z ごろから 10:39:31Z まで流し、**FAIL は 0**（入れ替え、kubelet の再起動、drain、再起動、uncordon の間を通して）。oeilvert の作業の終わりで止めた。

## 8. 手順書との差、気づいたこと

- §4（✋✋）: Docker の入れ替えの前の承認は、ユーザーが不要とした（devbox を使っていない）。✋ として知らせて進めた。devbox は入れ替えと再起動の後に自動で上がり、SSH が応答した
- §4.2 の 3: `docker-ce` と `docker-ce-cli` も版を指定して入れた（`containerd.io` と同じ扱い。作業の途中で `docker-ce` の新しい版が出ても、模擬と同じものを入れるため）
- §4.2 の 6: Storage Driver は overlay2 のままで、`containerd-snapshotter` の設定は要らなかった。イメージ、タグ、volume、daemon.json の IPv6 も残った
- §3.9: **`externalTrafficPolicy: Local` の LoadBalancer（gated-v4・v6、minecraft の `bds`）の告知は、Service の Pod のあるノードに付いていく**。oeilvert の gated-v6 は drain の時点で chirico に移り、再起動では途切れなかった。再起動で約 10 秒途切れるのは `Cluster` の LoadBalancer（VIP の `porkadot-kubernetes`、`h2-sshd`、`natsumi-sshd*`、`minecraft/bds-v4`）を告知しているノードである。runbook §3.9 と §5.3 に書いた。control-plane の 3 台には gated の Pod が載らないので、告知しているのは `Cluster` のものだけ（2026-10-18 10:08Z は、.112 が `h2-sshd`（`::131`）と `natsumi-sshd-aki`（`::134`）、.111 が `natsumi-sshd`（`::132`）。VIP は pablo、gated-v4・v6 は chirico、`natsumi-sshd-myao`（`::133`）は duchamp）。§2.4 の監視は v4 の VIP と gated-v4 しか見ないので、control-plane の再起動の間の `h2-sshd` などの途切れは監視に出ない
- §3.11 の 4: prometheus の 2 つのボリュームの replica の置き場所が入れ替わった（§6.1）。runbook §2.6 の表の後の経過に足した
- §3.10: oeilvert では cnidaria が CrashLoopBackOff にならず、speaker が 1 回だけ落ちた
- devbox の `mosh.fraction.jp` の AAAA は gated-v6 を指していて、v6 からは devbox の 3222 に繋がらない（前からの構成。段 C の範囲外）
