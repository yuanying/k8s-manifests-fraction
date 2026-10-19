# chirico の段 2 の作業記録

chirico（192.168.1.83）の kubelet を、porkadot 0.31.0 の `install kubelet --node` で v1.31.14 に上げた記録。手順は `../../runbook-stage-2.md`（以下 runbook）。
時刻は UTC。worker の 4 台目（drain する台。最後の replica を持つ台）。前は `braque.md`。

## 1. 事前の読み取り（2026-10-19 08:08:30Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.30.14 のノード: chirico、oeilvert、ほかは v1.31.14。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー .113、raft term 23116。3.5.34。`/readyz` `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached 2 |
| Longhorn の設定（runbook §2.6） | `5`、`disabled`、`block-if-contains-last-replica` |
| Prometheus の `spec.replicas`、`minio/minio` | 2、4 |
| MetalLB の告知ノード（runbook §2.7） | VIP: pablo、gated-v4・v6: **chirico**（`nodeAssigned` のイベント）、`h2-sshd`: .112、`natsumi-sshd`: .111、`natsumi-sshd-myao`: duchamp、`natsumi-sshd-aki`: .112 |
| Longhorn のボリュームがアタッチされたノード（runbook §8.11） | chirico 15、oeilvert 9、pablo 1 |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.30.14、`containerd://2.3.6` |
| `/opt/bin` の向き先 | kubelet: `kubelet-v1.30.14`、kubectl: `kubectl-v1.30.14`、crictl: `crictl-v1.30.1`。CNI の印: `v1.4.1` |
| Pod の名前・UID・restartCount（控え） | 63 個（DaemonSet 8 個と、ほかに 55 個）。控えは `notes/stage-2/chirico/pre/` |
| Longhorn の replica | 15 個（running 13、stopped 2） |
| 最後の replica を持つボリュームと、止めるもの（runbook §2.6） | `monitoring/prometheus-...-1`（pvc-99c35b80。prometheus-1 が chirico）。runbook の表のとおり。Prometheus を止める（prometheus-0 の pvc-625c8825 も一緒に止まる） |
| controller の無い Pod、PDB | controller の無い Pod は 0。PDB は runbook §2.6 のとおり |
| そのノードが告知している LoadBalancer | `gated-system/gated-v4`、`gated-v6` |
| cnidaria のログの error の数（8 台） | chirico 8、ほかは 0 |

## 2. etcd のリーダー

なし（worker）。

## 3. drain（runbook §5.2 の 2〜6）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 08:09:28Z | ✋ `infra-admin` のトークンを発行（3h） | `patch prometheuses` が yes |
| 08:09:28Z | ✋ `concurrent-replica-rebuild-per-node-limit` を `0`、`node-drain-policy` を `allow-if-replica-is-stopped` | 直前の値: `5`、`block-if-contains-last-replica`。APPLIED: true |
| 08:09:32Z | ✋ Prometheus `monitoring/kube-prometheus` の `spec.replicas` を 0 | 08:09:42Z に pvc-625c8825、08:09:45Z に pvc-99c35b80 が detached、chirico の pvc-99c35b80 の replica が stopped（13 秒） |
| 08:09:50Z | ✋ `cordon chirico` | controller の無い Pod: 0 |
| 08:09:50Z〜08:10:31Z | ✋ `drain chirico --ignore-daemonsets --delete-emptydir-data --timeout=20m` | rc 0、41 秒。55 個を evict。`--force` は要らなかった |

- instance-manager の `Cannot evict pod` は 7 回
- drain の後（08:11:22Z）: chirico にアタッチされたボリューム 0、`currentNodeID` が chirico のボリューム 0、chirico に instance-manager は無い。chirico の replica 15 個はすべて stopped、replica の組は drain の前と同じ。chirico に残ったのは DaemonSet の 8 つだけ。退いた Pod はすべて Running に戻った。Longhorn は attached degraded 12、healthy 9、detached 4（ベースラインの 2 と Prometheus の 2）
- 監視: **LB（gated-v4）の FAIL 1 回**（08:09:56Z。drain で chirico の gated の Pod が退いたとき。runbook §2.3 の見込みどおり）

## 4. `install kubelet`（runbook §5.2 の 7）

- 開始 08:11:32Z、終わり 08:12:33Z、rc 0。サンドボックスの中で流した
- 出力の要点: `install-deps.sh` 5.9 秒、`install-pkgs.sh` 5.2 秒、`install.sh` 46.9 秒。すべて `successful`
- kubelet の再起動の時刻: 08:12:33Z

## 5. 確認（runbook §5.3。08:13:58Z〜。cordon のまま）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready,SchedulingDisabled、v1.31.14、`containerd://2.3.6` |
| 2 | バイナリ | `kubelet-v1.31.14`、`kubectl-v1.31.14`、`crictl-v1.31.1`。`Kubernetes v1.31.14`。CNI の印 `v1.4.1`。`kubelet-v1.30.14` なども残っている |
| 3 | 残った Pod の再起動 | DaemonSet の 8 つの Pod は名前・UID が同じで、**各コンテナの restartCount がちょうど 1 増えた**。`definition changed` のイベント 11 件。CrashLoopBackOff は無い |
| 4 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。chirico の cnidaria の再起動の前のコンテナに `no route` の error が 6 件増えた（08:11:47Z ほか。runbook §8.1）。再起動の後は 0 |
| 5 | Longhorn | chirico にアタッチされたボリュームは無い。chirico の replica は stopped のまま、ほかのノードに足されていない。Longhorn の node chirico は一瞬 `manager pod ... is not running` になり、Ready に戻った。engine-image は起き直す間に probe が失敗し、1/1 Running |
| 6 | kubelet のログ | 古い kubelet の `Failed to update lease`（`connection reset by peer`）、起動の直後の `node not found`・`crio`・`InvalidDiskCapacity`、`node-driver-registrar` の PreStop hook の失敗だけ |
| 7 | 監視の FAIL | `install kubelet` の間は 0 |
| 8 | 告知していた LoadBalancer | gated-v4・v6 の `nodeAssigned` は、chirico の speaker が再起動した 08:12:35Z に oeilvert に移った（gated の Pod は duchamp と oeilvert）。192.168.1.200 と v6 の 80 は 404 で応答する。`::131`〜`::134` の SSH のバナー、VIP（200）も応答する |
| 9 | CSR | 無い |

etcd 3/3 healthy（リーダー .113、raft term 23116）。ほかのノードで再起動したコンテナは無い（08:11:30Z より後）。

## 6. uncordon と後始末（runbook §5.5）

- uncordon: 08:14:30Z（cordon から 4 分 40 秒）
- 戻した workload: 08:14:30Z に Prometheus の `spec.replicas` を 2 に戻した。08:14:39Z に 2 つのボリュームが attached、08:15:32Z に 2 つの Pod が 2/2 Running。**prometheus-0 は chirico、prometheus-1 は pablo で起き直した**（前は oeilvert と chirico）
- Longhorn の node chirico が Ready・schedulable に戻ったのを 08:14:30Z に確かめ、同じ時刻に `concurrent-replica-rebuild-per-node-limit` を `5`、`node-drain-policy` を `block-if-contains-last-replica` に戻した（APPLIED true。切り替えてから 5 分 2 秒）
- 再同期: 08:30:27Z に 23 attached healthy（設定を戻してから 15 分 57 秒）
- **replica の置き場所が data locality（`best-effort`）で 7 つ動いた**。drain で Pod が移った先に Longhorn がローカルの replica を作り、元の replica を消した
  - replica 1 の 2 つ: `prometheus-...-1`（pvc-99c35b80）は chirico → **pablo**、`prometheus-...-0`（pvc-625c8825）は oeilvert → **chirico**（どちらも 08:14:40Z に作られ、healthy。Pod が起き直したノード）
  - `natsumi-myao`（pvc-3a665d04）chirico → duchamp、`open-webui-pipelines`（pvc-8af6876b）chirico → duchamp、`hedgedoc/data-db-postgresql-0`（pvc-8eb75c08）duchamp → oeilvert、`news-agent`（pvc-bf2d7ef2）pablo → duchamp
  - `fs/h2`（pvc-c4944b75）は duchamp に replica が足され（08:30:18Z）、08:31Z の時点で chirico・duchamp・oeilvert の 3 つが running（`numberOfReplicas` 2）。消えるはずの 1 つが残っている（oeilvert の前に読み直す）
  - 同じボリュームの replica が同じノードに 2 つ載っているものは無い。replica の数: chirico 13（running 11）、duchamp 12（running 10）、oeilvert 18（running 17）、pablo 3
- Running / Completed 以外の Pod: 0
- ✋ `netcheck.sh`（08:31:53Z〜08:32:11Z）: 168/168 PASS。`check-apps.sh`: ベースラインと同じ
- トークンの破棄: 08:32:12Z にファイルを消した（サーバーの側では 11:09Z に期限が切れる）

## 7. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因 |
|---|---|---|
| 08:09:56Z（1 回） | LB | gated の Pod の移動（drain で chirico の gated が退いた） |

## 8. 次の 1 台へ進む条件（runbook §5.6）

| 条件 | 結果 |
|---|---|
| §5.3 がすべて合格 | 合格 |
| 全 8 台が Ready、SchedulingDisabled でない。終えたノードが v1.31.14 | 合格（oeilvert のほかは v1.31.14） |
| etcd 3/3 healthy、VIP が応答する | 合格 |
| Running / Completed 以外の Pod がベースラインから増えていない | 合格（0 個） |
| Longhorn のボリュームが healthy、再同期が終わっている | 合格（23 + 2） |
| Longhorn の設定が元の値、Prometheus 2、MinIO 4 | 合格 |
| `netcheck.sh`、`check-apps.sh` | 合格 |

## 9. 手順書との差、気づいたこと

- Prometheus を止めて戻すと、Pod は前と違うノードで起き直すことがあり、replica 1 のボリュームは data locality でそのノードへ replica ごと移る（20 GiB のコピー）。**oeilvert の前に、replica 1 のボリュームの置き場所が runbook §2.6 の表から変わった**: Prometheus の 2 つは chirico と pablo になり、oeilvert の最後の replica は MinIO の 4 つだけになった（runbook §5.1 の「当日の読み取りで変わっていれば、止めるものを決め直す」に当たる）
- 再同期が 16 分かかったのは、data locality の replica の移動を含むため
