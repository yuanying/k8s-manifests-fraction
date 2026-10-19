# pablo の段 1 の作業記録

pablo（192.168.1.134）の kubelet を、porkadot 0.30.0 の `install kubelet --node` で v1.30.14 に上げた記録。手順は `../../runbook-stage-1.md`（以下 runbook）。
時刻は UTC。worker の 1 台目。前は `192.168.1.111.md`（control-plane の最後）。

## 1. 事前の読み取り（2026-10-19 01:12:28Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.30.14 のノード: .111、.112、.113、v1.29.8 のノード: worker 5 台 |
| etcd、VIP | 3/3 healthy、リーダー .113、3 台とも 3.5.34。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached（ベースラインのもの）: 2 |
| Longhorn の設定 | `replica-auto-balance`: `disabled` |
| replica 1 のボリューム（runbook §5.1） | chirico 1（prometheus-1）、oeilvert 5（prometheus-0、minio-0〜3）。ベースラインと同じなので順も変えない |
| controller-manager と scheduler のリーダー | controller-manager `-jg62c`（.113）、scheduler `-lffqk`（.111） |
| MetalLB の告知ノード | VIP: **pablo**、gated-v4・v6: chirico、`h2-sshd`: .112、`natsumi-sshd`: .111、`natsumi-sshd-myao`: duchamp、`natsumi-sshd-aki`: .112 |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.29.8、`containerd://2.3.6` |
| `/opt/bin` の向き先 | kubelet: `kubelet-v1.29.8`、kubectl: `kubectl-v1.29.8`、etcdctl: `etcdctl-3.5.12`、crictl: `crictl-v1.29.0`。CNI の印: 無い |
| Pod の名前・UID・再起動回数（控え） | 15 個（`aphrael`、`minio/minio-2`、Longhorn の instance-manager・manager・csi-plugin・engine-image・CSI sidecar 4 つ、speaker、cnidaria、kube-proxy、node-exporter、smart-exporter） |
| Longhorn の replica | pablo に 3（running）。全ボリュームの置き場所を控えた |
| そのノードが告知している LoadBalancer | `kube-system/porkadot-kubernetes`（API の VIP 192.168.1.101） |

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`（runbook §5.2 の 2）

- 開始 01:12:52Z、終わり 01:13:39Z、rc 0。サンドボックスの外で流した（runbook §8.10）
- `install-deps.sh` 28.7 秒、`install-pkgs.sh` 11.8 秒、`install.sh` 3.8 秒。どれも `successful`
- kubelet の再起動は 01:13:39Z

## 4. 確認（runbook §5.3。01:14Z〜01:15Z。kubelet の再起動から 20 秒おいて読んだ）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.30.14、`containerd://2.3.6` |
| 2 | バイナリ | `kubelet-v1.30.14`、`kubectl-v1.30.14`、`crictl-v1.30.1`（etcdctl も `etcdctl-3.5.34`）。CNI の印 `v1.4.1`。`kubelet-v1.29.8`・`kubectl-v1.29.8` も残っている |
| 7 | Pod の再起動 | 15 個とも名前・UID・再起動回数が控えと同じ |
| 8 | cnidaria | 8 台の Pod が 1/1。`verify-nodes.sh` 64 PASS、FAIL 0。pablo の cnidaria が `Reconciler error` を 8 件、ほかの 7 台が info の `no route for a family` を 2 件ずつ（runbook §8.1） |
| 9 | Longhorn | attached healthy 23、detached 2。replica の置き場所と instance-manager（UID も）が控えと同じ。longhorn-manager のログの直近 5 分に `could get evicted`・`Schedule replica to node` は無い。`replica-auto-balance` `disabled`。Longhorn の node `pablo` は 01:13:41Z に一瞬 not ready（`Node pablo is down: manager pod longhorn-manager-hgj47 is not running`、`Waiting for disk …`）になり、同じ秒に `Node pablo is ready` に戻った（runbook §2.6 の一瞬の not ready。longhorn-manager の Pod は再起動していない） |
| 10 | MetalLB の speaker | `speaker-9fwg2` の再起動回数 16 のまま |
| 11 | kubelet のログ | 起動の直後（01:13:39Z）の `node not found`、crio の factory だけ |
| 12 | 監視の FAIL | 0（VIP を告知していたが途切れなかった） |
| 13 | leader election で再起動した controller | なし（01:12:52Z より後に終わったコンテナは 0） |
| 14 | 告知していた LoadBalancer | VIP は pablo のまま（移っていない）。`/version` 200。`check-apps.sh` はベースラインと同じ |

ノードごとの追加の確認（pablo）: share-manager（2 つ）、fs の h2、`docker/registry` は今は pablo に載っていない（どれも chirico で Running）。pablo の `minio/minio-2` は Running で、再起動していない。

warning のイベントは、Longhorn の node `pablo` の上のものだけ。

## 5. 監視の FAIL と、その原因

なし。

## 6. 次の 1 台へ進む条件（runbook §5.3）

| 条件 | 結果 |
|---|---|
| §5.3 の 1〜9 とノードごとの確認 | すべて合格 |
| 全 8 台の Node が Ready。終えたノードが v1.30.14、まだのノードが v1.29.8 | 合格 |
| etcd 3/3 healthy、VIP が応答する | 合格 |
| Running / Completed 以外の Pod がベースラインから増えていない | 合格（0 個） |
| Longhorn のボリュームが healthy | 合格 |

## 7. 手順書との差、気づいたこと

- Longhorn のノードでは、kubelet の再起動で Longhorn の node が 1 秒未満 not ready になり、warning のイベントが数件出る。auto-balance が `disabled` なので replica は動かなかった（runbook §2.6 の想定どおり）
- VIP を告知しているノードでも、kubelet の再起動で告知は移らず、途切れなかった
