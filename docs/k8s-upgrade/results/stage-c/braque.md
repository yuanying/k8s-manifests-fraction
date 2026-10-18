# braque の段 C の作業記録

braque（192.168.1.131）の containerd を、Ubuntu の `containerd` 2.2.1 から Docker の `containerd.io` 2.3.6 に置き換えた記録。手順は `../../runbook-stage-c.md`（以下 runbook）。
時刻は UTC。段 C の 4 台目。1 台目は `chirico.md`、2 台目は `duchamp.md`、3 台目は `pablo.md`、クラスタ全体のベースラインと戻すための控えは `baseline.md`。

braque は ZFS（`tank1`）と NFS の nfsd（DaemonSet `nfsd/nfsd`）を持つ。taint `unstable.cloud/storage:NoSchedule` で DaemonSet 以外の Pod は載らず、Longhorn の node でもない。

## 1. 事前の読み取り（2026-10-18 09:16Z〜）

### 1.1 クラスタ（runbook §2.3、§3.12）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。2.3.x のノード: chirico、duchamp、pablo（`containerd://2.3.6`）、2.2.1 のノード: ほかの 5 台 |
| etcd、VIP | 3/3 healthy、リーダー: 192.168.1.112、raft term 23111、raft index: 1402255311（そろっている）。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached（ベースラインのもの）: `myao/myao`、`homegallery/cg-data` |
| Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit`: `5`、`replica-auto-balance`: `disabled`（pablo の作業からの扱い。段 C の間は止めたまま）、`node-drain-policy`: `block-if-contains-last-replica`（`replica-replenishment-wait-interval` は `6000`、`default-data-locality` は `best-effort`） |
| controller-manager と scheduler の置き場所 | （worker なので無し） |
| `auth can-i delete pods -A`（`fraction-auditor`） | `no` |
| `containerd.io` の版（runbook §1.6） | 2.3 系の最新は 2.3.6-1 のまま（1 台目と同じ版を入れる） |
| `verify-nodes.sh` | 64 PASS、FAIL 0。cnidaria のログの error 0 |
| `check-apps.sh` | pablo の後（`pablo.md` §6）の出力と同じ |
| `minio/minio`、Prometheus の `spec.replicas` | 4/4、2 |
| CronJob の schedule（runbook §2.5） | ベースラインから変わっていない |

### 1.2 対象のノード（runbook §3.3）

| 項目 | 値 |
|---|---|
| Node | Ready、`containerd://2.2.1`、6.8.0-147-generic、起動 2026-10-18 00:18:30Z。taint `unstable.cloud/storage:NoSchedule` |
| `containerd --version` / `runc --version` | 2.2.1 / 1.3.4-0ubuntu1~24.04.1 |
| `/etc/containerd/config.toml` | `version = 3`、md5: `665fb78e3b80c49c14575c184b3c5bcf` |
| 控え（`/root/k8u-stage-c/`） | config.toml.before（md5 同じ）、`containerd_2.2.1-0ubuntu1~24.04.3_amd64.deb`、`runc_1.3.4-0ubuntu1~24.04.1_amd64.deb`（sha256 は `baseline.md` と同じ） |
| `apt-cache policy containerd containerd.io runc` | `containerd` と `runc` は Ubuntu の版で入っている。`containerd.io` は候補なし（`1.6.8-1 -1`、`/var/lib/dpkg/status` だけ） |
| `dpkg -l containerd.io docker-ce` | `containerd.io` 1.6.8-1 が `rc`。`docker-ce` は無い |
| `/etc/apt/sources.list.d/`、`preferences.d/`、`keyrings/` | `docker.list.disabled-20261017`、`ubuntu.sources` / `ubuntu-pro-esm-apps`、`ubuntu-pro-esm-infra` / `docker.gpg`（runbook のとおり） |
| 当たっていない Ubuntu の更新 | 0 |
| イメージの数（`crictl images -q`） | 29 |
| `systemctl --failed` | `systemd-networkd-wait-online.service`（ベースラインと同じ） |
| ZFS、NFS | `zfs-import-cache.service` は enabled、`zpool status -x` は `all pools are healthy`、`/export` は `tank1/export`（zfs）。nfsd は `nfsd-vt5k2` が Running（イメージ `registry.k8s.io/e2e-test-images/volume/nfs:1.6.0`） |
| iSCSI | `iscsid.socket`・`multipathd` が active。セッションは無い |
| Pod と再起動回数（控え） | 5 個（`cnidaria`、`kube-proxy`、`node-exporter`、`smart-exporter` が再起動 2、`nfsd` が 0）。コントローラを持たない Pod は無い |
| 最後の replica を持つボリューム（runbook §2.6） | **無い**。braque は Longhorn の node ではなく、replica は 0。replica の数は chirico 15、duchamp 11、oeilvert 17、pablo 3（pablo の後と同じ） |
| MetalLB の告知 | braque に speaker の Pod は無い（ラベル `metallb=speaker` はあるが taint で載らない）。告知しているノード: VIP（`porkadot-kubernetes`）は pablo、gated-v4 は chirico、gated-v6 は oeilvert、`h2-sshd`・`natsumi-sshd-aki` は .112、`natsumi-sshd` は .111、`natsumi-sshd-myao` は duchamp |

最後の replica が無いので、`node-drain-policy` を変えず、workload も止めない。`replica-auto-balance` は既に `disabled` なので、切り替えるのは `concurrent-replica-rebuild-per-node-limit` だけ。

## 2. 入れ替え（runbook §3.4〜§3.7）

### 2.1 リポジトリ、鍵、pin（09:18:00Z〜09:18:36Z）

- 鍵の fingerprint: `9DC858229FC7DD38854AE2D88D81803C0EBFCD88`（一致）
- `docker.sources` の `Architectures` は `amd64`
- `apt-cache policy containerd.io` の Candidate と優先度: `2.3.6-1~ubuntu.24.04~noble`。2.3 系の行（2.3.3-1〜2.3.6-1）が 1001、2.4 系と 2.2 系の行は 500

### 2.2 `containerd.io` を入れる（09:18:48Z〜09:19:05Z）

- `apt-get install -s` の結果（Remv / Inst）: runbook §3.5 の 1 と同じ（`0 upgraded, 1 newly installed, 2 to remove`、Remv `containerd`・`runc`、Inst `containerd.io` 2.3.6）
- 入れた版: `containerd.io=2.3.6-1~ubuntu.24.04~noble`（版を指定した）。rc 0
- conffile の扱い: ほかの worker と同じく `Using current old file as you requested` は出ず、手元の config が残った（md5 が控えと同じ）
- needrestart が `systemctl restart containerd.service` を流し、`No containers need to be restarted.` と出した

### 2.3 ノードでの確認（runbook §3.6）

| 項目 | 結果 |
|---|---|
| `containerd --version` / `runc --version` | `containerd containerd v2.3.6 ee2735368117d2eb259779949d5e75cdafec9761` / `runc version 1.5.1` |
| config の先頭と md5（控えと同じか） | `version = 3`、`665fb78e3b80c49c14575c184b3c5bcf`（同じ） |
| `containerd config dump`（version、SystemdCgroup、sandbox） | `version = 4`、`SystemdCgroup = true`、`sandbox = 'registry.k8s.io/pause:3.10.1'` |
| journal の error / warning（§8.1 のもの以外） | 無い。`Configuration migrated from version 3` と `failed check for fsverity support` が containerd の起動ごと（09:18:58Z、09:19:01Z）に出た。`unmarshal sandbox spec` は 18 行 |
| `ctr deprecations list` | 空 |
| `crictl info` / イメージの数（入れる前 → 後） | 応答する / 29 → 29 |
| `apt-cache policy containerd.io` | Installed と Candidate が 2.3.6-1、優先度 1001 |
| Pod の再起動回数 | 控えと同じ |

### 2.4 Longhorn の設定の切り替えと kubelet の再起動（runbook §3.7）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 09:19:19 | ✋ `infra-admin` のトークンを発行（3h） | 作業端末の 600 のファイルに置いた。`auth can-i patch nodes` が yes |
| 09:19:24 | ✋ `concurrent-replica-rebuild-per-node-limit` を `0` | 直前の値は `5`。読み直して APPLIED true。`replica-auto-balance` は既に `disabled`、`node-drain-policy` は変えない |
| 09:19:31 | ✋ `systemctl restart kubelet` | |

- Node と CONTAINER-RUNTIME: Ready、`containerd://2.3.6`（40 秒後に確認）
- Pod の再起動回数（控えとの差）: 5 個とも同じ（`diff` が空）
- kubelet の journal: 再起動の前の kubelet が、containerd の再起動の間（09:18:58Z〜09:19:01Z）に `containerd.sock: connect: no such file or directory` を出した。再起動の後の kubelet は、起動の直後（09:19:31Z）に `Error getting the current node from lister`、`Image garbage collection failed once`、crio の factory の登録の失敗（info）、`kubelet_internal_checkpoint` が無い（info）を出しただけ
- Longhorn の replica は動かなかった（kubelet の再起動の前後で `replicas.longhorn.io` の一覧が同じ）
- 監視（runbook §2.4）の FAIL: 無い

## 3. drain（runbook §3.8）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| — | `node-drain-policy` の変更、workload の停止 | しない（§1.2 のとおり最後の replica が無い） |
| 09:21:19 | ✋ `cordon braque` | コントローラを持たない Pod は無い |
| 09:21:19〜09:21:20 | ✋ `drain braque --ignore-daemonsets --delete-emptydir-data --timeout=20m` | rc 0、`node/braque drained`（1 秒）。`--force` は要らなかった |

- 退いた Pod は 0 個。braque に載るのは DaemonSet の 5 つ（`cnidaria`、`kube-proxy`、`node-exporter`、`smart-exporter`、`nfsd`）だけ
- Longhorn: braque は Longhorn の node ではなく、ボリュームも replica も無いので変化なし
- braque の追加の確認（OS 更新の手順書 §3.3）: `zfs-import-cache.service` が enabled（§1.2）。JST 18:21 で runbook §2.5 の止めてよい時間帯（18:15〜翌 05:15）の中

## 4. 再起動（runbook §3.9）

- 09:21:26 に `systemctl reboot`。kernel の起動は 09:21:58（`uptime -s`）。`systemd-networkd-wait-online` が 09:24:17 に失敗するまで待ち（前からの 2 分の遅れ）、containerd は 09:24:20、SSH は 09:24:22 に戻った。Node は 09:24:31 に Ready（SchedulingDisabled）に戻った（Ready の lastTransitionTime）。再起動から Ready まで約 3 分 5 秒（前タスクの約 3 分と同じくらい）
- boot id は `8d706ee9-…` から `4d7ced2c-…` に変わった
- MetalLB: braque には speaker が載らず、告知している LoadBalancer は無い（§1.2）
- 監視（runbook §2.4）の FAIL: **無い**（VIP、LB とも 0）
- braque が止まっていた間（09:21:26〜09:24:20 ごろ）、NFS、`registry.fraction.jp`、LAN からの 10.254.0.0/16 と `fraction.cluster` が使えなかった（runbook §2.5。影響は coordinator がユーザーに伝えてあった）

## 5. 再起動の後の確認（runbook §3.10）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready,SchedulingDisabled、v1.29.8、`containerd://2.3.6`。ラベルが残っている（`nfsd.unstable.cloud/storage=yes`、`metallb=speaker`、`tgtd.unstable.cloud/storage` など） |
| 2 | cnidaria の Pod | `cnidaria-q8bhw` は **CrashLoopBackOff にならず**、再起動の分だけ restart 2 → 3、09:25:52Z には 1/1 Running。`--previous` は再起動の前のコンテナのログ（info だけ）。起動の後のログの error は 0 |
| 3 | `verify-nodes.sh` | 64 PASS、FAIL 0（ベースラインと同じ）。cnidaria のログの error 0 |
| 4 | DaemonSet の Pod | 5 つとも Running。再起動回数は `cnidaria`、`kube-proxy`、`node-exporter`、`smart-exporter` が 2→3、`nfsd` が 0→1（どれも再起動の分だけ）。speaker と `longhorn-csi-plugin` は braque に載らない |
| 5 | ストリーミング | `cnidaria`、`nfsd` のログが読める |
| 6 | iptables | v4・v6 とも FORWARD の policy ACCEPT、`CNIDARIA-FWD` へのジャンプが先頭 |
| 7 | ディスク、ZFS | `zfs-import-cache.service`・`zfs-mount.service` が active、`zpool status -x` は `all pools are healthy`、**`/export` は `tank1/export`（zfs、15T、使用 5.1T）**。`/` は空き 87G |
| 8 | iSCSI | `iscsid.socket` と `multipathd` が active、`iscsid.service` は inactive（ほかの worker と同じ） |
| 9 | DNS | `porka-dummy01` に 10.254.0.10、検索ドメイン `default.svc.cluster.local svc.cluster.local cluster.local` |
| 10 | 失敗している unit | `systemd-networkd-wait-online.service` だけ（ベースラインと同じ） |
| 11 | apt | Candidate `2.3.6-1~ubuntu.24.04~noble`、優先度 1001。`apt-get -s full-upgrade` は `0 upgraded, 0 newly installed, 0 to remove` |
| 12 | `unmarshal sandbox spec` の数 | 31（起動の後） |

ほかに見たもの: containerd は v2.3.6、runc 1.5.1、config は `version = 3` で md5 が控えと同じ。`config dump` は `version = 4`、`SystemdCgroup = true`、`pause:3.10.1`。`ctr deprecations list` は空。イメージは 29 のまま。起動の後の containerd の journal の warning は `Configuration migrated from version 3` と `failed check for fsverity support` の 1 行ずつ。`unmarshal sandbox spec` のほかに error は無かった（runbook §8.1 の `ContainerStatus ... NotFound` も、braque では出なかった）。

### 5.1 NFS と NFS を使う Pod（OS 更新の手順書 §3.7 の braque）

- nfsd: `nfsd-vt5k2` が Running（restart 1）。ログは `Serving /exports`、`Serving /`、`exportfs: / does not support NFS export`、`NFS started` で、再起動の前のコンテナ（`--previous`）と同じ
- oeilvert のホストの `/home/yuanying/shared/nfs`（`192.168.1.131:/` の nfs4）の中身が読める
- `registry.fraction.jp`: `https://registry.fraction.jp/v2/` が 401（認証を求める応答）、`docker/registry` の Pod（oeilvert）から `/var/lib/registry` が読める
- NFS を使う Pod（`docker`、`carib`・`pondo`・`shja` と `*2`、`fs`、`hedgedoc`）はどれも Running。**`carib2`・`pondo2`・`shja2` の `movies` が 1 回ずつ再起動した**（下）。ほかは再起動なし

`movies` の 3 つの Pod（chirico、oeilvert、duchamp で動く。PV は braque の `/movies/carib`、`/movies/pondo`、`/movies/shja`）は、braque が止まった後の 09:21:37Z ごろからログが途切れ（NFS で待ち）、readiness が `EOF` やタイムアウトで失敗し、NFS が戻った直後の 09:24:35〜37Z に exit code 2 で終わって再起動した、09:26Z には 3 つとも 1/1 Running。braque の NFS が止まったことによるもので、containerd とは関係が無い。同じ PV を使う `carib`・`pondo`・`shja` の `nginx` は再起動していない。runbook §3.10 に足した。

## 6. uncordon と後始末（runbook §3.11）

- uncordon の時刻: 09:26:28（cnidaria が Ready になり `verify-nodes.sh` が通った後）。cordon から 5 分 9 秒
- 戻した workload: なし（止めていない）
- Longhorn の node（chirico、duchamp、oeilvert、pablo）が Ready、schedulable であることを確かめてから、09:26:28 に `concurrent-replica-rebuild-per-node-limit` を `5` に戻した（APPLIED true）。切り替えから 7 分 4 秒。`replica-auto-balance` は指示どおり `disabled` のまま、`node-drain-policy` は `block-if-contains-last-replica` のまま
- 再同期: 要らなかった。attached healthy 23、detached 2（ベースラインのもの）、degraded 0 のまま。`replicas.longhorn.io` の一覧（ボリューム、ノード、state）は kubelet の再起動の前と同じ。同じボリュームの replica が同じノードに 2 つ載ったものは無い。running 以外の replica は事前と同じ（`myao`・`cg-data` の stopped、`ero-data`（pvc-baa41130）と `natsumi-aki`（pvc-e224cffa）の duchamp のもの）
- Running / Completed 以外の Pod: 0 個
- `netcheck.sh`: 09:26:40〜09:26:59 に `up` → `run` → `down`。`PASS 168 / 168, pods 8/8`。namespace は消した
- `check-apps.sh`: 事前（09:17Z）の出力と同じ（差が無い）
- トークンの破棄: 09:27:06 に作業端末のファイルを消した。SA のトークンは個別に失効できないので、サーバーの側では発行から 3 時間（12:19 ごろ）で切れる

## 7. 次の 1 台へ進む条件（runbook §3.12）

（作業中）

## 8. 手順書との差、気づいたこと

- §3.7 の 2: `replica-auto-balance` は pablo の作業から `disabled` のままなので、`concurrent-replica-rebuild-per-node-limit` だけを切り替えた。§3.11 の 3 も rebuild-limit だけを戻した。runbook の §2.6、§3.7、§3.11、§3.12、§6 に、段 C の間は auto-balance を止めたままにする扱いを書いた（pablo の PR では書き残していた）。`least-effort` に戻す時期は段 C の最後にユーザーと決める
- §3.10: braque の再起動で NFS が止まると、`carib2`・`pondo2`・`shja2` の `movies` が liveness で 1 回ずつ再起動する（§5.1）。runbook に足した
- §2.5: braque の cordon から uncordon までは 5 分 9 秒だった（見込みの 30 分前後より短い）。runbook に実績として足した
- §3.10 の 2・§8.3: braque では cnidaria が CrashLoopBackOff にならなかった。containerd と kubelet が `systemd-networkd-wait-online` の 2 分の待ちの後に上がるので、kube-proxy の規則が入るのが間に合ったと見られる（確かめてはいない）。runbook は「なることがある」のままでよい
- braque の drain では Pod が退かず、Longhorn にも影響が無いので、rebuild-limit の切り替えは braque に限れば要らなかった。runbook どおりに行った（変えていない）
