# <ノード> の段 1 の作業記録

<ノード>（192.168.1.XX）の kubelet（control-plane は etcd も）を、porkadot 0.30.0 の `install kubelet --node` で v1.30.14 に上げた記録。手順は `../../runbook-stage-1.md`（以下 runbook）。
時刻は UTC（control-plane のホストの時刻は JST なので直して書く）。<何台目か。前の台の記録へのリンク>

この雛形を `<ノード>.md`（control-plane は `192.168.1.11N.md`）として写して使う。`install kubernetes` の記録（`control-plane.md`）は §1 と §4〜§6 を使う。当てはまらない節は「なし」と書いて残す。

## 1. 事前の読み取り（YYYY-MM-DD hh:mmZ〜）

### 1.1 クラスタ（runbook §2.2、§4.3 / §5.3 の「次の 1 台へ進む条件」）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.30.14 のノード: 、v1.29.8 のノード: |
| etcd、VIP | 3/3 healthy、リーダー: （ID: ）、raft term: 、raft index: 。版: 。`/readyz`: |
| Running / Completed 以外の Pod | |
| Longhorn | attached healthy N、detached（ベースラインのもの）: |
| Longhorn の設定（runbook §2.6） | `replica-auto-balance`: `disabled`、`concurrent-replica-rebuild-per-node-limit`: 、`node-drain-policy`: |
| controller-manager と scheduler の置き場所とリーダー | |
| MetalLB の告知ノード（runbook §2.7） | VIP: 、gated-v4・v6: 、`h2-sshd`: 、`natsumi-sshd*`: |

### 1.2 対象のノード（runbook §4.2 の 1 / §5.2 の 1）

| 項目 | 値 |
|---|---|
| Node | Ready、v1.29.8、`containerd://2.3.6` |
| `/opt/bin` の向き先 | kubelet: 、kubectl: 、etcdctl: 、crictl: 。CNI の印: |
| `/etc/etcd/pki`（control-plane） | |
| Pod の名前・UID・再起動回数（控え） | |
| Longhorn の replica（対象のノード、全ボリュームの置き場所の控え） | |
| そのノードが告知している LoadBalancer | |
| cnidaria のログの error の数（8 台） | |

## 2. etcd のリーダー（control-plane。runbook §4.2 の 2）

- リーダーか: 
- `move-leader`（時刻、移す先、出力、raft term の前後）: 

## 3. `install kubelet`（runbook §4.2 の 3 / §5.2 の 2）

- 開始 hh:mm:ssZ、終わり hh:mm:ssZ、rc: 
- 出力の要点（`install-deps.sh` が落としたもの、CNI plugins の落とし直し）: 

## 4. 確認（runbook §3.3 / §4.3 / §5.3）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | |
| 2 | バイナリ | |
| 3 | etcd の pki（control-plane） | |
| 4 | etcd（control-plane） | |
| 5 | etcd の Pod（control-plane） | |
| 6 | apiserver（control-plane） | |
| 7 | Pod の再起動 | |
| 8 | cnidaria | |
| 9 | Longhorn（replica の置き場所が変わっていないか） | |
| 10 | KCM と scheduler / MetalLB の speaker | |
| 11 | kubelet のログ | |
| 12 | 監視（runbook §2.3）の FAIL | |
| 13 | leader election で再起動した controller（runbook §8.9） | |
| 14 | 告知していた LoadBalancer | |

ノードごとの追加の確認（braque の NFS、oeilvert の MinIO・devbox、pablo の share-manager など）:

## 5. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因（apiserver の入れ替わり、告知ノード、gated の再起動、それ以外） |
|---|---|---|

## 6. 次の 1 台へ進む条件（runbook §4.3 / §5.3）

| 条件 | 結果 |
|---|---|

## 7. 手順書との差、気づいたこと

-
