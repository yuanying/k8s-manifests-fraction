# duchamp の段 2 の作業記録

duchamp（192.168.1.135）の kubelet を、porkadot 0.31.0 の `install kubelet --node` で v1.31.14 に上げた記録。手順は `../../runbook-stage-2.md`（以下 runbook）。
時刻は UTC。worker の 2 台目（drain する台）。前は `pablo.md`。冷却ファンが故障中だが、ノードは再起動しないので `no_turbo` はそのまま。

## 1. 事前の読み取り（2026-10-19 07:43:30Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.31.14 のノード: .111、.112、.113、pablo、v1.30.14 のノード: braque、chirico、duchamp、oeilvert。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー .113、raft term 23116。3.5.34。`/readyz` `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached 2 |
| Longhorn の設定（runbook §2.6） | `5`、`disabled`、`block-if-contains-last-replica` |
| Prometheus の `spec.replicas`、`minio/minio` | 2、4 |
| controller-manager と scheduler のリーダー | controller-manager `-2ffhd`（.112）、scheduler `-mp2ld`（.113） |
| MetalLB の告知ノード（runbook §2.7） | VIP: pablo、gated-v4・v6: chirico、`h2-sshd`: .112、`natsumi-sshd`: .111、`natsumi-sshd-myao`: **duchamp**、`natsumi-sshd-aki`: .112 |
| Longhorn のボリュームがアタッチされたノード（runbook §8.11） | chirico 15、duchamp 5、oeilvert 5（pablo の minio-2 が oeilvert に移った） |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.30.14、`containerd://2.3.6` |
| `/opt/bin` の向き先 | kubelet: `kubelet-v1.30.14`、kubectl: `kubectl-v1.30.14`、crictl: `crictl-v1.30.1`。CNI の印: `v1.4.1` |
| Pod の名前・UID・restartCount（控え） | 32 個（DaemonSet 8 個と、gated の 1 つ、CoreDNS の 1 つ、`kube-dns-autoscaler`、minio-3、alertmanager-0、`wiki-keeper-0`・`gmail-agent-0`、CSI sidecar 4、instance-manager、longhorn-ui、`shja2/movies` など）。`fs/data-backup-29871903-89l7b` は Completed。控えは `notes/stage-2/duchamp/pre/` |
| Longhorn の replica | 10 個（running 8、stopped 2。stopped は `myao/myao`（detached）と `homegallery/ero-data` の古いもので、ベースラインと同じ） |
| 最後の replica を持つボリュームと、止めるもの（runbook §2.6） | なし。`node-drain-policy` は変えない。止める workload は無い |
| controller の無い Pod、PDB | controller の無い Pod は 0。PDB は runbook §2.6 のとおり |
| そのノードが告知している LoadBalancer | `natsumi/natsumi-sshd-myao`（`::133`） |
| cnidaria のログの error の数（8 台） | control-plane 3 台と pablo 0、braque 8、chirico 8、duchamp 6、oeilvert 0 |

## 2. etcd のリーダー

なし（worker）。

## 3. drain（runbook §5.2 の 2〜6）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 07:44:31Z | ✋ `infra-admin` のトークンを発行（3h） | `patch nodes` が yes |
| 07:44:31Z | ✋ `concurrent-replica-rebuild-per-node-limit` を `0` | 直前の値: `5`。APPLIED: true。`node-drain-policy` は変えていない |
| — | ✋ 止めた workload | なし |
| 07:44:35Z | ✋ `cordon duchamp` | controller の無い Pod: 0 |
| 07:44:35Z〜07:45:07Z | ✋ `drain duchamp --ignore-daemonsets --delete-emptydir-data --timeout=20m` | rc 0、32 秒。`--force` は要らなかった |

- 退いた Pod は 24 個（Completed の `data-backup` を含む）。instance-manager の `Cannot evict pod` は 4 回
- drain の後（07:45:44Z）: duchamp にアタッチされたボリューム 0、`currentNodeID` が duchamp のボリューム 0、duchamp に instance-manager は無い。duchamp の replica 10 個はすべて stopped、replica の組は drain の前と同じ。duchamp に残ったのは DaemonSet の 8 つだけ。退いた Pod はすべて Running に戻った（Running / Completed 以外の Pod 0）。Longhorn は attached degraded 8、healthy 15。VIP の FAIL は増えていない

## 4. `install kubelet`（runbook §5.2 の 7）

- 開始 07:45:51Z、終わり 07:47:02Z、rc 0。サンドボックスの中で流した
- 出力の要点: `install-deps.sh` 6.4 秒、`install-pkgs.sh` 7.0 秒、`install.sh` 54.2 秒。すべて `successful`（`install.sh` が長かった理由は見ていない。段 1 の duchamp は 1 台 32 秒）
- kubelet の再起動の時刻: 07:47:02Z

## 5. 確認（runbook §5.3。07:48:27Z〜。cordon のまま）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready,SchedulingDisabled、v1.31.14、`containerd://2.3.6` |
| 2 | バイナリ | `kubelet-v1.31.14`、`kubectl-v1.31.14`、`crictl-v1.31.1`。`Kubernetes v1.31.14`。CNI の印 `v1.4.1`。`kubelet-v1.30.14` なども残っている |
| 3 | 残った Pod の再起動 | DaemonSet の 8 つの Pod は名前・UID が同じで、**各コンテナの restartCount がちょうど 1 増えた**。`definition changed` のイベント 11 件。CrashLoopBackOff は無い |
| 4 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。duchamp の cnidaria の再起動の前のコンテナに `no route` の error が 6 件増えた（07:46:08〜09Z。runbook §8.1）。再起動の後は 0 |
| 5 | Longhorn | duchamp にアタッチされたボリュームは無い。duchamp の replica は stopped のまま、ほかのノードに足されていない。Longhorn の node duchamp は 07:47:08Z ごろ一瞬 `manager pod ... is not running`・`Waiting for disk` になり、Ready に戻った。engine-image は起き直す間に liveness・readiness が失敗し（pablo と同じ形）、1/1 Running |
| 6 | kubelet のログ | 古い kubelet の `Failed to update lease`（`connection reset by peer`）、起動の直後の `node not found`・`crio`・`InvalidDiskCapacity`、`node-driver-registrar` の PreStop hook の失敗、止まった engine-image のコンテナへの probe の `CONTAINER_EXITED` だけ |
| 7 | 監視の FAIL | 0（累計 9 のまま） |
| 8 | 告知していた LoadBalancer | `natsumi-sshd-myao`（`::133`）は、duchamp の speaker が止まった 07:47:03Z に .113 が告知し、07:47:04Z に duchamp へ戻った。`::131`〜`::134` の SSH のバナー、gated の v4・v6（404）、VIP（200）が応答する。gated-v6 は drain で gated の Pod が oeilvert に移ったので oeilvert が告知している（gated-v4 は chirico のまま） |
| 9 | CSR | 無い |

etcd 3/3 healthy（リーダー .113、raft term 23116）。ほかのノードで再起動したコンテナは無い（07:44Z より後）。

## 6. uncordon と後始末（runbook §5.5）

- uncordon: 07:49:01Z（cordon から 4 分 26 秒）
- 戻した workload: なし
- Longhorn の node duchamp が Ready・schedulable に戻ったのを 07:49:01Z に確かめ、同じ時刻に `concurrent-replica-rebuild-per-node-limit` を `5` に戻した（APPLIED true。`0` にしてから 4 分 30 秒）。`replica-auto-balance` `disabled`、`node-drain-policy` `block-if-contains-last-replica` のまま
- 再同期: 07:59:29Z に 23 attached healthy（設定を戻してから 10 分 28 秒）。degraded は 07:53:06Z までに 1 つに減り、最後の 1 つ（`fraction-agents/data-wiki-keeper-0`、pvc-092a74ed）に 6 分かかった
- **replica の置き場所が 1 つ変わった（data locality）**: `wiki-keeper-0` が drain で oeilvert に移ったため、Longhorn（`best-effort`）が oeilvert に replica（`r-485c4c1b`、07:51:06Z）を作り直し、duchamp の replica（`r-33c63368`）を消した。今の replica は pablo と oeilvert の 2 つで、`numberOfReplicas` 2、healthy。同じボリュームの replica が同じノードに 2 つ載っているものは無い。replica の数: chirico 15（running 13）、duchamp 9（running 7）、oeilvert 18（running 17）、pablo 3
- Running / Completed 以外の Pod: 0。退いた Pod はほかのノードで動き続けている（gated・`gmail-agent-0`・`wiki-keeper-0` は oeilvert、CoreDNS は pablo、`kube-dns-autoscaler` は chirico など）
- ✋ `netcheck.sh`（07:59:45Z〜08:00:02Z）: 168/168 PASS。`check-apps.sh`: ベースラインと同じ
- トークンの破棄: 08:00:03Z にファイルを消した（サーバーの側では 10:44Z に期限が切れる）

## 7. 監視の FAIL と、その原因

なし（duchamp の作業の間 FAIL 0）。

## 8. 次の 1 台へ進む条件（runbook §5.6）

| 条件 | 結果 |
|---|---|
| §5.3 がすべて合格 | 合格 |
| 全 8 台が Ready、SchedulingDisabled でない。終えたノードが v1.31.14 | 合格（.111〜.113、pablo、duchamp が v1.31.14） |
| etcd 3/3 healthy、VIP が応答する | 合格 |
| Running / Completed 以外の Pod がベースラインから増えていない | 合格（0 個） |
| Longhorn のボリュームが healthy、再同期が終わっている | 合格（23 + 2） |
| Longhorn の設定が元の値、Prometheus 2、MinIO 4 | 合格 |
| `netcheck.sh`、`check-apps.sh` | 合格 |

## 9. 手順書との差、気づいたこと

- drain で Longhorn のボリュームを使う Pod が移ると、data locality（`best-effort`）で移った先に replica が作り直され、元のノードの replica が消えることがある（runbook §2.6・§5.5 の 4 が予告していた形）。再同期が 10 分ほどに延びた
- 退いた Pod が oeilvert に寄っている（minio-2、aphrael、CSI sidecar 4、gated、`wiki-keeper-0`、`gmail-agent-0` など）。oeilvert の drain で、これらがもう一度動く
