# oeilvert の段 1 の作業記録

oeilvert（192.168.1.82）の kubelet を、porkadot 0.30.0 の `install kubelet --node` で v1.30.14 に上げた記録。手順は `../../runbook-stage-1.md`（以下 runbook）。
時刻は UTC。worker の 5 台目（最後）。前は `chirico.md`。

## 1. 事前の読み取り（2026-10-19 01:33:37Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.29.8 のノード: oeilvert だけ |
| etcd、VIP | 3/3 healthy、リーダー .113、3 台とも 3.5.34。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached（ベースラインのもの）: 2 |
| Longhorn の設定 | `replica-auto-balance`: `disabled` |
| MetalLB の告知ノード | VIP: pablo、gated-v4・v6: chirico、ほかは前と同じ。oeilvert が告知しているものは無い |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.29.8、`containerd://2.3.6` |
| `/opt/bin` の向き先 | kubelet: `kubelet-v1.29.8`、kubectl: `kubectl-v1.29.8`、etcdctl: `etcdctl-3.5.12`、crictl: `crictl-v1.29.0`。CNI の印: 無い |
| Pod の名前・UID・再起動回数（控え） | 18 個（`minio/minio-0`、`monitoring/prometheus-kube-prometheus-0`、`natsumi/natsumi-0`、`natsumi/natsumi-aki-0`、Longhorn の instance-manager・manager など） |
| Longhorn の replica | oeilvert に 17（running 16、stopped 1。stopped はベースラインのとおり）。replica 1 のボリューム（prometheus-0、minio-0〜3）がある。全ボリュームの置き場所を控えた |
| そのノードが告知している LoadBalancer | なし |

### 1.3 同じ PVC の Completed の Pod を消した（runbook §8.11）

chirico の longhorn/longhorn#8072 の形（`chirico.md` §4.1）を避けるため、ユーザーの判断で（runbook から外れる操作として承認）、oeilvert の Running の Pod と同じ PVC を使う **oeilvert の上の** Succeeded の Pod を、`infra-admin` の短命トークンで消した（01:33:37Z）。

| PVC | Running の Pod | 消した Pod |
|---|---|---|
| `natsumi/natsumi` | `natsumi-0` | `natsumi-backup-29872590-rjjf4` |
| `natsumi/natsumi-aki` | `natsumi-aki-0` | `natsumi-backup-aki-29872590-ctsb9` |

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`（runbook §5.2 の 2）

- 開始 01:34:09Z、終わり 01:34:36Z、rc 0。サンドボックスの外で流した（runbook §8.10）
- `install-deps.sh` 10.8 秒、`install-pkgs.sh` 9.7 秒、`install.sh` 3.4 秒。どれも `successful`
- kubelet の再起動は 01:34:36Z

## 4. 確認（runbook §5.3。01:35:41Z〜）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.30.14、`containerd://2.3.6` |
| 2 | バイナリ | `kubelet-v1.30.14`、`kubectl-v1.30.14`、`crictl-v1.30.1`（etcdctl も `etcdctl-3.5.34`）。CNI の印 `v1.4.1`。`kubelet-v1.29.8`・`kubectl-v1.29.8` も残っている |
| 3 | Pod の再起動 | 18 個とも名前・UID・再起動回数が控えと同じ |
| 4 | Longhorn | attached healthy 23、detached 2。replica の置き場所と instance-manager（UID も）が控えと同じ。longhorn-manager のログの直近 5 分に `could get evicted`・`Schedule replica to node` は無い。`replica-auto-balance` `disabled`。Longhorn の node `oeilvert` は 01:34:41Z に一瞬 not ready（`manager pod longhorn-manager-wn5sl is not running`、2 つのディスクの `Waiting for disk …`）になり、すぐ Ready に戻った |
| 5 | cnidaria | 8 台の Pod が 1/1。`verify-nodes.sh` 64 PASS、FAIL 0。oeilvert の cnidaria は `Reconciler error` を出さず、ほかの 7 台の `no route for a family` も増えなかった（ほかの 7 台と違う。理由は調べていない） |
| 6 | MetalLB の speaker | 再起動回数が控えと同じ |
| 7 | kubelet のログ | **Longhorn の 2 つのボリュームの `MountVolume.SetUp` の失敗が続いた**（下の 4.1） |
| 8 | 監視の FAIL | 0 |
| 9 | 告知していた LoadBalancer | なし。`check-apps.sh` はベースラインと同じ |

ノードごとの追加の確認（oeilvert）: MinIO の 4 つの Pod（minio-0 は oeilvert、minio-1〜3 は chirico・pablo・duchamp）と `prometheus-kube-prometheus-0` が Running、再起動 0。ボリュームは healthy。`docker` が active で `devbox` のコンテナが動いている。

leader election で再起動した controller は無い（01:34:09Z より後に終わったコンテナは 0）。

### 4.1 longhorn/longhorn#8072 の形（ほかのノードの Completed の Pod）

1.3 で oeilvert の上の Succeeded の Pod を消したが、新しい kubelet は `natsumi-0`（pvc-6b8f51fa）と `natsumi-aki-0`（pvc-e224cffa）のボリュームで `MountVolume.SetUp` を繰り返し、Longhorn の CSI が `Aborted` を返した（FailedMount が各 9 回、01:34:37Z〜01:36:46Z）。

| Pod | Longhorn の CSI の応答の map |
|---|---|
| `natsumi-0` | `Running:[natsumi-0] Succeeded:[natsumi-backup-before-v0151-202610181122-fwn7n]`（この Pod は **chirico** の上） |
| `natsumi-aki-0` | `Running:[natsumi-aki-0] Succeeded:[natsumi-backup-aki-before-v0151-9pv6s]`（この Pod は **duchamp** の上） |

**Longhorn は、ノードを問わず、同じ PVC を使う Succeeded の Pod を数える。** 1.3 の洗い出しはノードで絞っていたので、この 2 つが残った。

ユーザーの判断で、この 2 つの Completed の Pod だけを消した（01:38:24Z）。

- kubelet の次のやり直し（01:38:47Z と 01:38:49Z）で、Longhorn の CSI は `NodePublishVolume` を受け付け、mount point の health の確認をして返した（`Aborted` は出ていない）
- FailedMount は 01:36:46Z の 9 回目で止まった。2 つの Pod は Running のまま、再起動 0

## 5. 監視の FAIL と、その原因

なし。

## 6. 次へ進む条件（runbook §5.3）

| 条件 | 結果 |
|---|---|
| §5.3 の 1〜9 とノードごとの確認 | 7 のほかは合格。7 は上の 4.1 のとおり Completed の Pod を消して収まった |
| 全 8 台の Node が Ready、v1.30.14 | 合格 |
| etcd 3/3 healthy、VIP が応答する | 合格 |
| Running / Completed 以外の Pod がベースラインから増えていない | 合格（0 個） |
| Longhorn のボリュームが healthy | 合格 |

## 7. 手順書との差、気づいたこと

- 上の 4.1。runbook §8.11 の洗い出しを、ノードを問わない形に直した
