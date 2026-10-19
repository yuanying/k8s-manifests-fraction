# pablo の段 2 の作業記録

pablo（192.168.1.134）の kubelet を、porkadot 0.31.0 の `install kubelet --node` で v1.31.14 に上げた記録。手順は `../../runbook-stage-2.md`（以下 runbook）。
時刻は UTC。worker の 1 台目（drain する台）。前は `192.168.1.111.md`。

## 1. 事前の読み取り（2026-10-19 07:37Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.31.14 のノード: .111、.112、.113、v1.30.14 のノード: worker 5 台。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー: .113（ID: `57ec6f12ac7b683e`）、raft term: 23116。版: 3.5.34。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 個。.111 の後（07:31:45Z より後）の再起動は 0（07:37Z） |
| Longhorn | attached healthy 23、detached（ベースラインのもの）: 2 |
| Longhorn の設定（runbook §2.6） | `concurrent-replica-rebuild-per-node-limit`: `5`、`replica-auto-balance`: `disabled`、`node-drain-policy`: `block-if-contains-last-replica` |
| Prometheus の `spec.replicas`、`minio/minio` | 2、4 |
| controller-manager と scheduler の置き場所とリーダー | controller-manager .111（`-2blbx`）・.112（`-2ffhd`、リーダー）、scheduler .112（`-vb2lz`）・.113（`-mp2ld`、リーダー） |
| MetalLB の告知ノード（runbook §2.7） | VIP: **pablo**、gated-v4・v6: chirico、`h2-sshd`: .112、`natsumi-sshd`: .111、`natsumi-sshd-myao`: duchamp、`natsumi-sshd-aki`: .112 |
| Longhorn のボリュームがアタッチされたノード（runbook §8.11） | chirico 15、duchamp 5、oeilvert 4、pablo 1（minio-2 の `export-minio-2`） |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.30.14、`containerd://2.3.6` |
| `/opt/bin` の向き先 | kubelet: `kubelet-v1.30.14`、kubectl: `kubectl-v1.30.14`、crictl: `crictl-v1.30.1`。CNI の印: `v1.4.1` |
| Pod の名前・UID・restartCount（控え） | 15 個。DaemonSet 8 個（cnidaria、kube-proxy、engine-image、longhorn-csi-plugin、longhorn-manager、speaker、node-exporter、smart-exporter）と、aphrael 1、Longhorn の CSI sidecar 4（attacher、provisioner、resizer、snapshotter）、instance-manager、minio-2。控えは `notes/stage-2/pablo/pre/` |
| Longhorn の replica | pablo に 3 つ（`pvc-092a74ed`（wiki-keeper）、`pvc-baa41130`（homegallery `ero-data`）、`pvc-bf2d7ef2`（news-agent））、どれも running で、ほかのノードにも replica がある |
| 最後の replica を持つボリュームと、止めるもの（runbook §2.6） | なし（replica 1 のボリュームの replica は chirico と oeilvert だけ）。`node-drain-policy` は変えない。止める workload は無い |
| controller の無い Pod、PDB | controller の無い Pod は 0。PDB は runbook §2.6 のとおり |
| そのノードが告知している LoadBalancer | `kube-system/porkadot-kubernetes`（API の VIP 192.168.1.101） |
| cnidaria のログの error の数（8 台） | .111 0、.112 0、.113 0、braque 8、chirico 8、duchamp 6、oeilvert 0、pablo 8 |

## 2. etcd のリーダー

なし（worker）。

## 3. drain（runbook §5.2 の 2〜6）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 07:38:03Z | ✋ `infra-admin` のトークンを発行（3h） | `/tmp` のモード 600 のファイル。`patch nodes`、`create pods/eviction`、`patch settings.longhorn.io` が yes |
| 07:38:09Z | ✋ `concurrent-replica-rebuild-per-node-limit` を `0` | 直前の値: `5`。APPLIED: true。`node-drain-policy` は変えていない |
| — | ✋ 止めた workload | なし |
| 07:38:13Z | ✋ `cordon pablo` | controller の無い Pod: 0 |
| 07:38:13Z〜07:38:19Z | ✋ `drain pablo --ignore-daemonsets --delete-emptydir-data --timeout=20m` | rc 0、6 秒。`--force` は要らなかった |

- 退いた Pod: aphrael、CSI sidecar 4、minio-2、instance-manager。instance-manager の `Cannot evict pod` は 1 回だけ
- drain の後（07:38:47Z）: pablo にアタッチされたボリューム 0、`currentNodeID` が pablo のボリューム 0、pablo に instance-manager は無い。pablo の replica 3 つは stopped、replica の組（ボリュームとノード）は drain の前と同じ（ほかのノードに足されていない）。pablo に残ったのは DaemonSet の 8 つだけ。minio-2 は oeilvert で Running（33 秒で起き直した）。Running / Completed 以外の Pod は 0。Longhorn は attached degraded 3（pablo の replica が止まった 3 つ）、healthy 20

## 4. `install kubelet`（runbook §5.2 の 7）

- 開始 07:38:54Z、終わり 07:39:14Z、rc 0。サンドボックスの中で流した
- 出力の要点: `install-deps.sh` 6.6 秒、`install-pkgs.sh` 6.8 秒、`install.sh` 3.1 秒。すべて `successful`
- kubelet の再起動の時刻: 07:39:14Z

## 5. 確認（runbook §5.3。07:40:43Z〜07:41:07Z。cordon のまま）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready,SchedulingDisabled、v1.31.14、`containerd://2.3.6` |
| 2 | バイナリ | `kubelet-v1.31.14`、`kubectl-v1.31.14`、`crictl-v1.31.1`（etcdctl は 3.5.34 のまま）。`Kubernetes v1.31.14`。CNI の印 `v1.4.1`。`kubelet-v1.30.14` なども残っている |
| 7 | コンテナの再起動 | DaemonSet の 8 つの Pod は名前・UID が同じで、**各コンテナの restartCount がちょうど 1 増えた**（longhorn-csi-plugin の 3 つ、longhorn-manager の 2 つを含む）。`definition changed` のイベント 11 件。CrashLoopBackOff は無い |
| 8 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。pablo の cnidaria は再起動の前のコンテナに `no route` の error が 7 件増えた（runbook §8.1）。再起動の後は 0 |
| 9 | Longhorn | pablo にアタッチされたボリュームは無い。pablo の replica は stopped のまま、ほかのノードに足されていない。Longhorn の node pablo は 07:39:47Z ごろ一瞬 `manager pod ... is not running`・`Waiting for disk` になり、07:41:07Z に Ready=True（Schedulable=False は `KubernetesNodeCordoned`）。engine-image は 07:39:27〜45Z に liveness・readiness が `/data/longhorn` が無いと失敗し、起き直して 1/1 Running（再起動 +1）。engine image は deployed のまま |
| 10 | KCM と scheduler / MetalLB の speaker | リーダーは変わらない。VIP の告知は、pablo の speaker が止まった 07:39:16Z に .113 が告知して取り下げ、同じ秒に pablo へ戻った |
| 11 | kubelet のログ | 古い kubelet の `Failed to update lease`（`connection reset by peer`。`dns` の addon の `systemd-networkd` の再起動。段 1 の braque と同じ形）、起動の直後の `node not found`・`crio`・`InvalidDiskCapacity`、longhorn-csi-plugin の `node-driver-registrar` の PreStop hook の失敗（`/bin/sh` が無いイメージ。`FailedPreStopHook` のイベント 1 件）だけ |
| 12 | 監視の FAIL | **0**（runbook の見込みの「pablo で VIP が 1〜数回」は起きなかった） |
| 13 | leader election で再起動した controller（対象のノードの外） | 無い |
| 14 | 告知していた LoadBalancer | VIP は pablo のまま応答する（`/version` 200、`/readyz` ok）。gated の v4・v6（404）、`h2-sshd`・`natsumi-sshd*` の 4 つ（SSH のバナー）も応答する |
| 15 | CSR | 無い |

etcd 3/3 healthy（リーダー .113、raft term 23116、raft index 1402649159 でそろう）。Longhorn の node の `Multipathd`・`KernelModulesLoaded` が False なのは 4 台とも前からのもの。

## 6. uncordon と後始末（runbook §5.5）

- uncordon: 07:41:20Z（cordon から 3 分 7 秒）
- 戻した workload: なし
- Longhorn の node pablo が Ready・schedulable に戻ったのを 07:41:20Z に確かめ、同じ時刻に `concurrent-replica-rebuild-per-node-limit` を `5` に戻した（APPLIED true。`0` にしてから 3 分 11 秒）。`replica-auto-balance` `disabled`、`node-drain-policy` `block-if-contains-last-replica` のまま
- 再同期: 07:42:49Z に 23 attached healthy（設定を戻してから 1 分 29 秒）。pablo の replica 3 つは running。同じボリュームの replica が同じノードに 2 つ載っているものは無い。replica の置き場所は drain の前と同じ
- Running / Completed 以外の Pod: 0。退いた Pod は oeilvert で動いている（aphrael `-z2mtj`、CSI sidecar 4、minio-2）。instance-manager は pablo で作り直された
- ✋ `netcheck.sh`（07:42:54Z〜07:43:11Z。up → run → down）: 168/168 PASS。`check-apps.sh`: ベースラインと同じ（nodes 8/8、Running でない Pod 0、IP の重複 0、Longhorn 23 healthy・2 detached、hedgedoc の db Running、LB 404・VIP 200）
- トークンの破棄: 07:43:18Z にファイルを消した（サーバーの側では 10:38Z に期限が切れる）

## 7. 監視の FAIL と、その原因

なし（pablo の作業の間 FAIL 0。累計は .111 の 9 回のまま）。

## 8. 次の 1 台へ進む条件（runbook §5.6）

| 条件 | 結果 |
|---|---|
| §5.3 がすべて合格 | 合格 |
| 全 8 台が Ready、SchedulingDisabled でない。終えたノードが v1.31.14 | 合格（.111〜.113、pablo が v1.31.14） |
| etcd 3/3 healthy、VIP が応答する | 合格 |
| Running / Completed 以外の Pod がベースラインから増えていない | 合格（0 個） |
| Longhorn のボリュームが healthy、再同期が終わっている | 合格（23 + 2） |
| Longhorn の設定が元の値、Prometheus 2、MinIO 4 | 合格 |
| `netcheck.sh`、`check-apps.sh` | 合格 |

## 9. 手順書との差、気づいたこと

- VIP の告知ノードでも、speaker の再起動の間の VIP の FAIL は 0 だった（告知は同じ秒に戻った）
- drain は 6 秒、再同期は 1 分半で、段 C より短い（replica の止まっていた時間が 4 分ほどだったため）
- longhorn-csi-plugin の `node-driver-registrar` の PreStop hook は、イメージに `/bin/sh` が無いので毎回失敗する（`FailedPreStopHook`）。害は無い
