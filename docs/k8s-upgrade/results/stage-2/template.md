# <ノード> の段 2 の作業記録

<ノード>（192.168.1.XX）の kubelet を、porkadot 0.31.0 の `install kubelet --node` で v1.31.14 に上げた記録。手順は `../../runbook-stage-2.md`（以下 runbook）。
時刻は UTC（control-plane のホストの時刻は JST なので直して書く）。<何台目か。前の台の記録へのリンク>

この雛形を `<ノード>.md`（control-plane は `192.168.1.11N.md`）として写して使う。`install kubernetes` の記録（`control-plane.md`）は §1 と §5〜§8 を使う。当てはまらない節は「なし」と書いて残す（control-plane と braque は §3 と §6 が無い）。

## 1. 事前の読み取り（YYYY-MM-DD hh:mmZ〜）

### 1.1 クラスタ（runbook §2.2、§4.3 / §5.6 の「次の 1 台へ進む条件」）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.31.14 のノード: 、v1.30.14 のノード: 。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー: （ID: ）、raft term: 、raft index: 。版: 3.5.34。`/readyz`: |
| Running / Completed 以外の Pod | |
| Longhorn | attached healthy N、detached（ベースラインのもの）: |
| Longhorn の設定（runbook §2.6） | `concurrent-replica-rebuild-per-node-limit`: 、`replica-auto-balance`: `disabled`、`node-drain-policy`: |
| Prometheus の `spec.replicas`、`minio/minio` | |
| controller-manager と scheduler の置き場所とリーダー | |
| MetalLB の告知ノード（runbook §2.7） | VIP: 、gated-v4・v6: 、`h2-sshd`: 、`natsumi-sshd*`: |
| Longhorn のボリュームがアタッチされたノード（runbook §8.11） | |

### 1.2 対象のノード（runbook §4.2 の 1 / §5.2 の 1 / §5.4 の 1）

| 項目 | 値 |
|---|---|
| Node | Ready、v1.30.14、`containerd://2.3.6` |
| `/opt/bin` の向き先 | kubelet: 、kubectl: 、etcdctl: 、crictl: 。CNI の印: |
| `/etc/etcd/pki`（control-plane） | |
| Pod の名前・UID・restartCount（控え） | |
| Longhorn の replica（対象のノード、全ボリュームの置き場所の控え） | |
| 最後の replica を持つボリュームと、止めるもの（drain する台。runbook §2.6） | |
| controller の無い Pod、PDB（drain する台） | |
| そのノードが告知している LoadBalancer | |
| cnidaria のログの error の数（8 台） | |
| braque: 時間帯、NFS の PV を使う Pod の restartCount | |

## 2. etcd のリーダー（control-plane。runbook §4.2 の 2）

- リーダーか: 
- `move-leader`（時刻、移す先、出力、raft term の前後）: 

## 3. drain（drain する台。runbook §5.2 の 2〜6）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| | ✋ `infra-admin` のトークンを発行（3h） | |
| | ✋ `concurrent-replica-rebuild-per-node-limit` を `0`（`node-drain-policy` を変えたときはそれも） | 直前の値: 。APPLIED: |
| | ✋ 止めた workload（Prometheus / MinIO） | detached になった時刻、stopped の replica: |
| | ✋ `cordon <ノード>` | controller の無い Pod: |
| | ✋ `drain <ノード> --ignore-daemonsets --delete-emptydir-data --timeout=20m` | rc、所要時間、`--force` の要否 |

- 止まった Pod（instance-manager の `Cannot evict pod` の回数など）:
- drain の後: 対象のノードにアタッチされたボリューム（0 であること）、対象のノードの replica（stopped）、ほかのノードに足された replica（無いこと）、Pending の Pod:

## 4. `install kubelet`（runbook §4.2 の 3 / §5.2 の 7 / §5.4 の 2）

- 開始 hh:mm:ssZ、終わり hh:mm:ssZ、rc: 。サンドボックスの中で流したか: 
- 出力の要点（`install-deps.sh` が落としたもの）: 
- kubelet の再起動の時刻: 

## 5. 確認（runbook §3.3 / §4.3 / §5.3 / §5.4 の 3。kubelet の起動から 1 分ほど待ってから）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | |
| 2 | バイナリ | |
| 3 | etcd の pki（control-plane） | |
| 4 | etcd（control-plane） | |
| 5 | etcd の Pod（control-plane） | |
| 6 | apiserver（control-plane） | |
| 7 | コンテナの再起動（残った Pod の名前・UID が同じで、restartCount がちょうど 1 増えたか。2 以上のもの、CrashLoopBackOff の回数） | |
| 8 | cnidaria | |
| 9 | Longhorn（アタッチ、replica の置き場所、Longhorn の node が Ready に戻ったか） | |
| 10 | KCM と scheduler（リーダーの移動） / MetalLB の speaker | |
| 11 | kubelet のログ | |
| 12 | 監視（runbook §2.3）の FAIL | |
| 13 | leader election で再起動した controller（対象のノードの外。runbook §8.8） | |
| 14 | 告知していた LoadBalancer | |
| 15 | CSR（runbook §8.10） | |

ノードごとの追加の確認（approver の Pod、braque の nfsd・NFS・`registry.fraction.jp`、oeilvert の MinIO・`homegallery/api`・devbox、pablo の VIP など）:

## 6. uncordon と後始末（drain した台。runbook §5.5）

- uncordon の時刻（cordon から何分）:
- 戻した workload（Prometheus / MinIO）と、Running・attached を確かめた時刻:
- Longhorn の node が Ready・schedulable に戻った時刻、設定を戻した時刻と値（切り替えから何分）:
- 再同期が終わった時刻（設定を戻してから何分）:
- replica の置き場所（data locality で動いたもの、同じノードに 2 つ載ったものが無いこと）:
- Running / Completed 以外の Pod:
- `netcheck.sh`、`check-apps.sh`:
- トークンの破棄:

## 7. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因（告知ノードの speaker の再起動、gated の Pod の移動、apiserver の止まりかけ、gated の再起動、それ以外） |
|---|---|---|

## 8. 次の 1 台へ進む条件（runbook §4.3 / §5.6）

| 条件 | 結果 |
|---|---|

## 9. 手順書との差、気づいたこと

-
