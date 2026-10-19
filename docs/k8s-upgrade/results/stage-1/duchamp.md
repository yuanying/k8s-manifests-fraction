# duchamp の段 1 の作業記録

duchamp（192.168.1.135）の kubelet を、porkadot 0.30.0 の `install kubelet --node` で v1.30.14 に上げた記録。手順は `../../runbook-stage-1.md`（以下 runbook）。
時刻は UTC。worker の 2 台目。前は `pablo.md`。

## 1. 事前の読み取り（2026-10-19 01:14:58Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.30.14 のノード: control-plane 3 台、pablo、v1.29.8 のノード: braque、chirico、duchamp、oeilvert |
| etcd、VIP | 3/3 healthy、リーダー .113、3 台とも 3.5.34。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached（ベースラインのもの）: 2 |
| Longhorn の設定 | `replica-auto-balance`: `disabled` |
| controller-manager と scheduler のリーダー | controller-manager `-jg62c`（.113）、scheduler `-lffqk`（.111） |
| MetalLB の告知ノード | VIP: pablo、gated-v4・v6: chirico、`h2-sshd`: .112、`natsumi-sshd`: .111、`natsumi-sshd-myao`: **duchamp**、`natsumi-sshd-aki`: .112 |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.29.8、`containerd://2.3.6` |
| `/opt/bin` の向き先 | kubelet: `kubelet-v1.29.8`、kubectl: `kubectl-v1.29.8`、etcdctl: `etcdctl-3.5.12`、crictl: `crictl-v1.29.0`。CNI の印: 無い |
| Pod の名前・UID・再起動回数（控え） | 33 個（`gated-…-w4hw7`、CoreDNS 1 つ、Longhorn の instance-manager・manager・CSI sidecar など、`shja2/movies` を含む） |
| Longhorn の replica | duchamp に 11（running 8、stopped 3。stopped はベースラインのとおり）。全ボリュームの置き場所を控えた |
| そのノードが告知している LoadBalancer | `natsumi/natsumi-sshd-myao`（`::133`） |

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`（runbook §5.2 の 2）

- 開始 01:15:24Z、終わり 01:15:56Z、rc 0。サンドボックスの外で流した（runbook §8.10）
- `install-deps.sh` 11.2 秒、`install-pkgs.sh` 11.8 秒、`install.sh` 5.2 秒。どれも `successful`
- kubelet の再起動は 01:15:56Z。再起動はしないので、冷却ファンの故障に合わせた `no_turbo` はそのまま

## 4. 確認（runbook §5.3。01:16Z〜01:17Z。kubelet の再起動から 20 秒おいて読んだ）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.30.14、`containerd://2.3.6` |
| 2 | バイナリ | `kubelet-v1.30.14`、`kubectl-v1.30.14`、`crictl-v1.30.1`（etcdctl も `etcdctl-3.5.34`）。CNI の印 `v1.4.1`。`kubelet-v1.29.8`・`kubectl-v1.29.8` も残っている |
| 3 | Pod の再起動 | 33 個とも名前・UID・再起動回数が控えと同じ |
| 4 | Longhorn | attached healthy 23、detached 2。replica の置き場所と instance-manager（UID も）が控えと同じ。longhorn-manager のログの直近 5 分に `could get evicted`・`Schedule replica to node` は無い。`replica-auto-balance` `disabled`。Longhorn の node `duchamp` は 01:15:59Z に一瞬 not ready（`manager pod longhorn-manager-pzx5h is not running`、`Waiting for disk …`）になり、すぐ Ready に戻った（pablo と同じ形） |
| 5 | cnidaria | 8 台の Pod が 1/1。`verify-nodes.sh` 64 PASS、FAIL 0。duchamp の cnidaria が `Reconciler error` を 6 件、ほかの 7 台が info の `no route for a family` を 2 件ずつ（runbook §8.1） |
| 6 | MetalLB の speaker | 再起動回数が控えと同じ（Pod の控えの比較に含まれる） |
| 7 | kubelet のログ | 起動の直後（01:15:56Z）の crio の factory と `invalid capacity 0 on image filesystem` だけ |
| 8 | 監視の FAIL | 0 |
| 9 | 告知していた LoadBalancer | `natsumi-sshd-myao`（`::133`）は duchamp のまま（移っていない）で、SSH のバナーを返す。gated-v4・v6 は chirico が 01:15:59Z に告知し直した（移っていない。duchamp の gated の Pod の readiness が kubelet の再起動でやり直されたためと見られる）。`check-apps.sh` はベースラインと同じ |

leader election で再起動した controller は無い（01:15:24Z より後に終わったコンテナは 0）。warning のイベントは、duchamp の `InvalidDiskCapacity` と Longhorn の node `duchamp` の上のものだけ。

## 5. 監視の FAIL と、その原因

なし。

## 6. 次の 1 台へ進む条件（runbook §5.3）

| 条件 | 結果 |
|---|---|
| §5.3 の 1〜9 | すべて合格 |
| 全 8 台の Node が Ready。終えたノードが v1.30.14、まだのノードが v1.29.8 | 合格 |
| etcd 3/3 healthy、VIP が応答する | 合格 |
| Running / Completed 以外の Pod がベースラインから増えていない | 合格（0 個） |
| Longhorn のボリュームが healthy | 合格 |

## 7. 手順書との差、気づいたこと

- 段 C で auto-balance が replica を動かしたノードだが、`disabled` のおかげで replica は動かなかった（runbook §2.6 の想定どおり）
