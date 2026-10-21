# <ノード> の段 7 の作業記録

<ノード>（192.168.1.XX）の kubelet を、porkadot 0.36.0 の `install kubelet --node` で v1.36.5 に上げた記録（etcd は 3.6.15 のまま）。手順は `../../runbook-stage-7.md`（以下 runbook）。
時刻は UTC（control-plane のホストの時刻は JST なので直して書く）。<何台目か。前の台の記録へのリンク>

この雛形を `<ノード>.md`（control-plane は `192.168.1.11N.md`）として写して使う。`install kubernetes` の記録（`control-plane.md`）は §1 と §4〜§7 を使い、§3 に install.sh の 2 段（`successfully rolled out` の時刻と、その後の `configured`）を、§4 に runbook §3.3 の 13（CoreDNS が v1.14.7 になったことと `tools/dns-check.sh` の答えの比べ）、16（storage version）、17（ServiceCIDR と IPAddress）、18（v1 Endpoints の warning）、19（FlowSchema）、20（CoreDNS のプロセスの UID と capability）と、§4.2 の 2 つ目のバックアップを足す。当てはまらない節は「なし」と書いて残す（control-plane と braque は iSCSI のセッション・エンジン・Longhorn の項目が「なし」）。

## 1. 事前の読み取り（YYYY-MM-DD hh:mmZ〜）

### 1.1 クラスタ（runbook §2.2、§4.4 / §5.5 の「次の 1 台へ進む条件」）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.36.5 のノード: 、v1.35.9 のノード: 。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー: （ID: ）、raft term: 、raft index: 。版（.111 / .112 / .113）: 3.6.15。cluster version・storage: 3.6.0。`/readyz`: |
| Running / Completed 以外の Pod | |
| Longhorn | attached healthy N、detached（ベースラインのもの）: |
| Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit`: 、`replica-auto-balance`: `disabled`、`node-drain-policy`: |
| controller-manager と scheduler の置き場所とリーダー | |
| MetalLB の告知ノード（runbook §2.8） | VIP: 、gated-v4: 、gated-v6: 、`h2-sshd`: 、`natsumi-sshd*`: |

### 1.2 対象のノード（runbook §4.3 の 1 / §5.2 の 1）

| 項目 | 値 |
|---|---|
| Node | Ready、v1.35.9、`containerd://2.3.6`、cgroup（`stat -fc %T /sys/fs/cgroup`）: |
| `tools/node-state.sh`（ファイル名） | |
| `/opt/bin` の向き先、CNI の印と 4 つのプラグイン | |
| iscsid（MainPID、ActiveEnterTimestamp。前の記録から変わっていれば、その原因（unattended-upgrades など。runbook §2.11）） | |
| iSCSI のセッション（数、portal が今の instance-manager の IP か） | |
| `older-than-iscsid` のエンジン | |
| アタッチされたボリュームと robustness | |
| 同じ Longhorn の PVC を使う Completed / Succeeded の Pod（runbook §8.12） | |
| `/etc/etcd/pki`（control-plane） | |
| etcd の `/version`、動いている etcd のフラグ（control-plane） | |
| Pod の控え（`snap` のファイル名、Pod の数） | |
| そのノードが告知している LoadBalancer | |
| cnidaria のログの error の数（8 台） | |
| braque: 時間帯、nfsd の restartCount | |

## 2. etcd のリーダー（control-plane。runbook §4.3 の 2）

- リーダーか: 
- `move-leader`（時刻、移す先、出力、raft term の前後）: 

## 3. `install kubelet`（runbook §4.3 の 3 / §5.2 の 2）

- 開始 hh:mm:ssZ、終わり hh:mm:ssZ、rc: 。サンドボックスの中で流したか: 
- 出力の要点（`install-deps.sh` が落としたもの、CNI plugins の展開、`install-pkgs.sh` の apt と iscsid）: 
- kubelet の再起動の時刻: 

## 4. 確認（runbook §3.3 / §4.4 / §5.3。kubelet の起動から 1 分ほど待ってから）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | |
| 2 | バイナリ、CNI（印と 4 つのプラグイン） | |
| 3 | iscsid（MainPID と ActiveEnterTimestamp が前と同じか） | |
| 4 | iSCSI のセッション（同じ sid・portal・target） | |
| 5 | エンジン（同じボリューム、同じ起動の時刻） | |
| 6 | Longhorn（robustness、instance-manager、Longhorn の node、カーネルの I/O エラー） | |
| 7 | Pod の再起動（`snap` の diff。control-plane は etcd の mirror Pod の UID だけ） | |
| 8 | etcd の pki・etcd・etcd の Pod（control-plane。mirror Pod の restartCount 1〜2 は想定どおり） | |
| 16 | etcd の版（3 台の `/version` が 3.6.15・3.6.0 のまま。control-plane） | |
| 17 | etcd のフラグ（`--feature-gates=InitialCorruptCheck=true`、`--watch-progress-notify-interval=5s`、`--experimental-` が無い、`unknown flag` が無い。control-plane） | |
| 18 | etcd のログ（`bind: address already in use` など想定どおりのものと、増えたもの。control-plane） | |
| 9 | apiserver、KCM と scheduler（control-plane） | |
| 10 | cnidaria（`verify-nodes.sh`、`no route` の数） | |
| 11 | kubelet のログ | |
| 12 | 監視（runbook §2.3）の FAIL と、監視が止まっていなかったか（3 つのログの最後の行の時刻） | |
| 13 | leader election で再起動した controller（runbook §8.8） | |
| 14 | 告知していた LoadBalancer | |
| 15 | CSR（runbook §8.9） | |

NetworkPolicy の確認（runbook §1.9。最初の worker の後だけ）: `nft`（up の前・後・down の後）、`run` の OK / not OK、名前空間が消えたこと:

ノードごとの追加の確認（braque の nfsd・NFS・`registry.fraction.jp`、pablo の VIP、oeilvert の `homegallery/api` など）:

control-plane の 3 台目の後（runbook §4.5）: 3 台の `/version`、リーダー、etcd の health の監視を止めた時刻:

## 5. 監視の FAIL と、その原因

| 時刻 | VIP / LB / etcd の health | 原因 |
|---|---|---|

## 6. 次の 1 台へ進む条件（runbook §4.4 / §5.5）

| 条件 | 結果 |
|---|---|

## 7. 手順書との差、気づいたこと

-
