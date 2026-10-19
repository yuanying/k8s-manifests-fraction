# oeilvert の段 2 の作業記録

oeilvert（192.168.1.82）の kubelet を、porkadot 0.31.0 の `install kubelet --node` で v1.31.14 に上げた記録。手順は `../../runbook-stage-2.md`（以下 runbook）。
時刻は UTC。worker の 5 台目（最後。drain する台）。前は `chirico.md`。**drain の後に iSCSI の古いセッションの件が起き、ユーザーの承認を得て、uncordon の前に再起動した**（`iscsi-stale-sessions.md`）。

## 1. 事前の読み取り（2026-10-19 08:32:30Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.30.14 は oeilvert だけ。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー .113、raft term 23116。3.5.34。`/readyz` `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached 2 |
| Longhorn の設定（runbook §2.6） | `5`、`disabled`、`block-if-contains-last-replica` |
| Prometheus の `spec.replicas`、`minio/minio` | 2、4 |
| MetalLB の告知ノード（runbook §2.7） | VIP: pablo、gated-v4・v6: **oeilvert**（chirico の speaker の再起動で 08:12:35Z に移った）、`h2-sshd`: .112、`natsumi-sshd`: .111、`natsumi-sshd-myao`: duchamp、`natsumi-sshd-aki`: .112 |
| Longhorn のボリュームがアタッチされたノード | chirico 1、duchamp 10、oeilvert 11、pablo 3 |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.30.14、`containerd://2.3.6` |
| `/opt/bin` の向き先 | kubelet: `kubelet-v1.30.14`、kubectl: `kubectl-v1.30.14`、crictl: `crictl-v1.30.1`。CNI の印: `v1.4.1` |
| Pod の名前・UID・restartCount（控え） | 51 個（DaemonSet 8 個と、ほかに 43 個。`homegallery/api`、approver、minio-0・minio-2、CSI sidecar 4、gated、`wiki-keeper-0`・`gmail-agent-0`、hedgedoc の db など、前の台の drain で寄ったものを含む）。控えは `notes/stage-2/oeilvert/pre/` |
| Longhorn の replica | 18 個（running 17、stopped 1） |
| 最後の replica を持つボリュームと、止めるもの（runbook §2.6、§5.1） | **`minio/export-minio-0`〜`3` の 4 つだけ**。Prometheus の 2 つのボリュームは chirico の作業で chirico と pablo に移っていた（`chirico.md` §6）。runbook §5.1 の「当日の読み取りで変わっていれば、止めるものを決め直す」に従い、**MinIO だけを止め、Prometheus は止めなかった** |
| controller の無い Pod、PDB | controller の無い Pod は 0。PDB は runbook §2.6 のとおり |
| そのノードが告知している LoadBalancer | gated-v4・v6（gated の Pod の 1 つが oeilvert） |
| ほか | `docker`・`devbox` が active。`systemctl --failed` は空 |

## 2. etcd のリーダー

なし（worker）。

## 3. drain（runbook §5.2 の 2〜6）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 08:33:25Z | ✋ `infra-admin` のトークンを発行（3h） | `patch statefulsets/scale` が yes |
| 08:33:26Z | ✋ `concurrent-replica-rebuild-per-node-limit` を `0`、`node-drain-policy` を `allow-if-replica-is-stopped` | 直前の値: `5`、`block-if-contains-last-replica`。APPLIED: true |
| 08:33:29Z | ✋ `minio/minio` を 0 | 08:34:13Z に 4 つのボリュームが detached、oeilvert の replica が stopped（44 秒） |
| 08:34:22Z | ✋ `cordon oeilvert` | controller の無い Pod: 0 |
| 08:34:22Z〜08:41:26Z | ✋ `drain oeilvert --ignore-daemonsets --delete-emptydir-data --timeout=20m` | rc 0、**7 分 4 秒**。41 個を evict、instance-manager の `Cannot evict pod` 5 回。`--force` は要らなかった |

- drain が長かったのは、退いた Pod のボリュームが chirico でアタッチできず（§4）、Longhorn が oeilvert のボリュームを外し終えるのに時間がかかったため（instance-manager の PDB で待たされた）と見ている
- `homegallery/api`（`kubernetes.io/hostname: oeilvert`）は drain から uncordon まで Pending（runbook §2.6 のとおり）
- drain の後（08:42:11Z）: oeilvert の replica 18 個はすべて stopped、replica の組は前と同じ。oeilvert に残ったのは DaemonSet の 8 つだけ。**ただし oeilvert の VolumeAttachment が 1 つ（`tumblr-data`）残り、4 つのボリュームが `attaching` のまま、Pod が作り直され続けていた**。runbook §5.2 の 6 に従い `install kubelet` に入らず、止めて報告した（§4）

## 4. drain の後の止まり（iSCSI の古いセッション）

詳しくは `iscsi-stale-sessions.md`。要点:

- chirico のホストに、chirico の drain の前の instance-manager（10.244.8.88）への iSCSI のセッションが 15 本残っていて、そのボリュームのエンジンが chirico で起動できなかった（`failed to logout target`）。4 つのボリュームが faulted を繰り返し、`hedgedoc/db-postgresql-0`、`web-researcher-0`、`open-webui-0`、`tumblr-web` の 1 つが 20 分ほど止まった
- 08:46Z に止めて報告し、ユーザーの承認を得て、08:53:26Z に chirico を cordon、08:53:27Z に 4 つの Pod を消した。pablo・duchamp でアタッチされ、08:57Z までに 4 つとも Running に戻った
- 08:58:00Z に oeilvert の VolumeAttachment が 0 になったのを確かめてから、`install kubelet` に入った

## 5. `install kubelet` と再起動

### 5.1 `install kubelet`（runbook §5.2 の 7）

- 開始 08:58:11Z、終わり 08:58:28Z、rc 0。サンドボックスの中で流した
- 出力の要点: `install-deps.sh` 6.2 秒、`install-pkgs.sh` 5.9 秒、`install.sh` 2.3 秒。すべて `successful`

### 5.2 確認（runbook §5.3。08:59:53Z。cordon のまま）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready,SchedulingDisabled、v1.31.14、`containerd://2.3.6` |
| 2 | バイナリ | `kubelet-v1.31.14`、`kubectl-v1.31.14`、`crictl-v1.31.1`。`Kubernetes v1.31.14`。CNI の印 `v1.4.1`。`kubelet-v1.30.14` なども残っている |
| 3 | 残った Pod の再起動 | DaemonSet の 8 つの Pod は名前・UID が同じで、**各コンテナの restartCount がちょうど 1 増えた** |
| 4 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。oeilvert の cnidaria は `no route` を出さなかった（段 1 と同じ） |
| 5 | Longhorn | oeilvert にアタッチされたボリュームは無い。oeilvert の replica は stopped のまま。engine-image は起き直す間に probe が失敗し、1/1 Running |
| 6〜9 | kubelet のログ、監視、LB、CSR | 起動の直後のものだけ。監視の FAIL 0。LB と VIP は応答する。CSR は無い |

### 5.3 再起動（ユーザーの承認。runbook から外れる）

- 再起動の前: oeilvert は LoadBalancer を告知していない（gated-v4・v6 は 08:58:31Z に chirico へ移っていた）。iSCSI の古いセッション 2 本（`natsumi`、`natsumi-aki`）。devbox が動いている
- ✋ 09:00:36Z `sudo systemctl reboot` → SSH 09:02:58Z → Node Ready 09:03:08Z
- 再起動の後（09:04:15Z。段 C の手順書 §3.10、§4.3）: Ready,SchedulingDisabled、v1.31.14、`containerd://2.3.6`。cnidaria 1/1 Ready、`verify-nodes.sh` 全 PASS。**iSCSI のセッション 0**。FORWARD・ip6tables の FORWARD の先頭が `CNIDARIA-FWD`。`iscsid.socket`・`multipathd`・`docker`・`devbox`・`home-yuanying-shared-nfs.mount`・`-data.automount`・`-h.automount` が active、devbox のコンテナが動いている。failed の unit 無し、`ordering cycle` 0、`porka-dummy01` に 10.254.0.10。ZFS は healthy

## 6. uncordon と後始末（runbook §5.5）

- uncordon: 09:04:30Z（cordon から 30 分 8 秒）
- 戻した workload: 09:04:31Z に `minio/minio` を 4。09:05:00Z に 4 つとも Running（minio-0・minio-3 は oeilvert、minio-1 は duchamp、minio-2 は pablo）。`homegallery/api` は oeilvert で Running に戻った
- Longhorn の node oeilvert が Ready・schedulable に戻ったのを 09:04:31Z に確かめ、同じ時刻に `concurrent-replica-rebuild-per-node-limit` を `5`、`node-drain-policy` を `block-if-contains-last-replica` に戻した（APPLIED true。切り替えてから 31 分 5 秒）
- 再同期: 09:10:38Z に 23 attached healthy（設定を戻してから 6 分）
- Running / Completed 以外の Pod: 0
- ✋ `netcheck.sh`（09:10:49Z〜）: 168/168 PASS。`check-apps.sh`: ベースラインと同じ
- トークン: chirico と duchamp の再起動（`iscsi-stale-sessions.md` §5）でも使い、10:16:09Z にファイルを消した

## 7. 監視の FAIL と、その原因

なし（oeilvert の作業の間 FAIL 0）。

## 8. 次へ進む条件（runbook §5.6）

| 条件 | 結果 |
|---|---|
| §5.3 がすべて合格 | 合格 |
| 全 8 台が Ready、全台 v1.31.14 | 合格（chirico・duchamp の再起動の後に、すべて uncordon 済み） |
| etcd 3/3 healthy、VIP が応答する | 合格 |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn のボリュームが healthy、再同期が終わっている | 合格（10:15:45Z。duchamp の再起動の後） |
| Longhorn の設定が元の値、Prometheus 2、MinIO 4 | 合格 |
| `netcheck.sh`、`check-apps.sh` | 合格 |

## 9. 手順書との差、気づいたこと

- drain の後の iSCSI の古いセッション（`iscsi-stale-sessions.md`）。runbook §5.2 に「drain した台は uncordon の前に再起動する」と「drain の後に iSCSI のセッションを確かめる」を足した
- replica 1 のボリュームの置き場所が、前の台の作業で runbook §2.6 の表から変わった（Prometheus の 2 つが oeilvert から出ていった）。止めるものを決め直した
