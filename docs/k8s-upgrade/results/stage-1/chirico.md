# chirico の段 1 の作業記録

chirico（192.168.1.83）の kubelet を、porkadot 0.30.0 の `install kubelet --node` で v1.30.14 に上げた記録。手順は `../../runbook-stage-1.md`（以下 runbook）。
時刻は UTC。worker の 4 台目。前は `braque.md`。

## 1. 事前の読み取り（2026-10-19 01:19:41Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.29.8 のノード: chirico、oeilvert。ほかは v1.30.14 |
| etcd、VIP | 3/3 healthy、リーダー .113、3 台とも 3.5.34。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached（ベースラインのもの）: 2 |
| Longhorn の設定 | `replica-auto-balance`: `disabled` |
| MetalLB の告知ノード | VIP: pablo、gated-v4・v6: **chirico**、`h2-sshd`: .112、`natsumi-sshd`: .111、`natsumi-sshd-myao`: duchamp、`natsumi-sshd-aki`: .112 |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.29.8、`containerd://2.3.6` |
| `/opt/bin` の向き先 | kubelet: `kubelet-v1.29.8`、kubectl: `kubectl-v1.29.8`、etcdctl: `etcdctl-3.5.12`、crictl: `crictl-v1.29.0`。CNI の印: 無い |
| Pod の名前・UID・再起動回数（控え） | 67 個（`gated-…-qnvq4`、`prometheus-kube-prometheus-1`、`hedgedoc/db-postgresql-0`、`docker/registry`、`fs/h2`、share-manager 2 つ、`natsumi/natsumi-myao-0`、`fraction-agents/deep-researcher-0` など） |
| Longhorn の replica | chirico に 15（running 13、stopped 2。stopped はベースラインのとおり）。replica 1 のボリューム `prometheus-...-1`（pvc-99c35b80）がある。全ボリュームの置き場所を控えた |
| そのノードが告知している LoadBalancer | `gated-system/gated-v4`・`gated-v6`（192.168.1.200、`::200`） |

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`（runbook §5.2 の 2）

- 開始 01:20:08Z、終わり 01:20:35Z、rc 0。サンドボックスの外で流した（runbook §8.10）
- `install-deps.sh` 9.6 秒、`install-pkgs.sh` 9.4 秒、`install.sh` 4.9 秒。どれも `successful`
- kubelet の再起動は 01:20:35Z

## 4. 確認（runbook §5.3。01:20:59Z〜）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.30.14、`containerd://2.3.6` |
| 2 | バイナリ | `kubelet-v1.30.14`、`kubectl-v1.30.14`、`crictl-v1.30.1`（etcdctl も `etcdctl-3.5.34`）。CNI の印 `v1.4.1`。`kubelet-v1.29.8`・`kubectl-v1.29.8` も残っている |
| 3 | Pod の再起動 | 67 個とも名前・UID・再起動回数が控えと同じ |
| 4 | Longhorn | attached healthy 23、detached 2。replica の置き場所と instance-manager（UID も）が控えと同じ。longhorn-manager のログの直近 5 分に `could get evicted`・`Schedule replica to node` は無い。`replica-auto-balance` `disabled` |
| 5 | cnidaria | 8 台の Pod が 1/1。`verify-nodes.sh` 64 PASS、FAIL 0。chirico の cnidaria が `Reconciler error` を 8 件、ほかの 7 台が info の `no route for a family` を 2 件ずつ（runbook §8.1） |
| 6 | MetalLB の speaker | 再起動回数が控えと同じ |
| 7 | kubelet のログ | **Longhorn の 2 つのボリュームの `MountVolume.SetUp` の失敗が続いた**（下の 4.1） |
| 8 | 監視の FAIL | 0 |
| 9 | 告知していた LoadBalancer | gated-v4・v6 は chirico のまま（移っていない）で、80 が 404 を返す。`check-apps.sh` はベースラインと同じ |

leader election で再起動した controller は無い（01:20:08Z より後に終わったコンテナは 0）。

### 4.1 Longhorn の `no Pending workload pods`（longhorn/longhorn#8072 の形）

新しい kubelet は、起動の直後から次の 2 つの Pod のボリュームで `MountVolume.SetUp` を繰り返し、Longhorn の CSI が `Aborted` を返した（FailedMount のイベントが各 12 回、01:20:40Z〜01:28:54Z。kubelet の backoff は 2 分ほどまで伸びた）。

| Pod | PVC（ボリューム） | Longhorn の CSI の応答 |
|---|---|---|
| `natsumi/natsumi-myao-0` | `natsumi-myao`（pvc-3a665d04） | `no Pending workload pods for volume … to be mounted: map[Running:[natsumi-myao-0] Succeeded:[natsumi-backup-myao-29872590-tp7ww natsumi-backup-myao-before-v0151-qffrj]]` |
| `fraction-agents/deep-researcher-0` | `data-deep-researcher-0`（pvc-9aae4b86） | `… map[Running:[deep-researcher-0] Succeeded:[deep-researcher-backup-29872620-vnxrg]]` |

- kubelet は再起動のあと、動いている Pod のボリュームについても `NodePublishVolume` をやり直す。Longhorn の CSI は、その PVC を使う Pod に Running のほか Succeeded の Pod（backup の Job が残した Completed の Pod）があると、「mount を待つ Pending の Pod が無い」として断る。longhorn/longhorn#8072（v1.7.0 で直ったとされる）と同じ形で、本番の Longhorn v1.11.2 でも、Succeeded の Pod が同じ PVC にあると出る（直しの条件から外れると見られる。longhorn-manager のコードは確かめていない）
- 2 つの Pod は Running のまま（再起動 0）、ノードの mount（`/dev/longhorn/pvc-…`）も残っていて、動作への影響は見えなかった
- pablo、duchamp、braque では出なかった（Running の Pod と同じ PVC を使う Succeeded の Pod が無かった）

ユーザーの判断で（runbook から外れる操作として承認）、`infra-admin` の短命トークン（01:30:19Z 発行、2 時間）で、上の 3 つの Completed の Pod だけを消した（01:30:23Z）。Job・CronJob・Running の Pod には触っていない。

- kubelet の次のやり直し（01:30:54Z と 01:30:56Z）で、Longhorn の CSI は `NodePublishVolume` を受け付け、mount point の health の確認をして返した（`Aborted` は出ていない）
- FailedMount は 01:28:54Z の 12 回目で止まった。2 つの Pod は Running のまま、再起動 0

## 5. 監視の FAIL と、その原因

なし。

## 6. 次の 1 台へ進む条件（runbook §5.3）

| 条件 | 結果 |
|---|---|
| §5.3 の 1〜9 | 7 のほかは合格。7 は上の 4.1 のとおり Completed の Pod を消して収まった |
| 全 8 台の Node が Ready。終えたノードが v1.30.14、まだのノードが v1.29.8 | 合格 |
| etcd 3/3 healthy、VIP が応答する | 合格 |
| Running / Completed 以外の Pod がベースラインから増えていない | 合格（0 個） |
| Longhorn のボリュームが healthy | 合格 |

## 7. 手順書との差、気づいたこと

- 上の 4.1。runbook §8.11 に足した
