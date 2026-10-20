# pablo の段 4 の作業記録

pablo（192.168.1.134）の kubelet を、porkadot 0.33.0 の `install kubelet --node` で v1.33.13 に上げた記録。手順は `../../runbook-stage-4.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 2 台目（API の VIP を告知し、Longhorn のボリュームがアタッチされた最初の台）。前の台は `duchamp.md`。読み取りの出力はタスクディレクトリの `notes/stage-4/pablo/`。

## 1. 事前の読み取り（2026-10-20 02:27Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.33.13 のノード: control-plane 3 台、duchamp、v1.32.13 のノード: pablo、braque、oeilvert、chirico。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー: 192.168.1.113（`57ec6f12ac7b683e`）、raft term 23120。版: 3.5.34。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 |
| Longhorn | attached healthy 16、detached（ベースラインのもの）: `homegallery/cg-data` |
| Longhorn の設定 | `5`、`disabled`、`block-if-contains-last-replica` |
| controller-manager と scheduler の置き場所とリーダー | controller-manager .111・.113（リーダー）、scheduler .113・.112（リーダー） |
| MetalLB の告知ノード | VIP: pablo（02:23:01Z にもう一度 `serviceAnnounced`）、gated-v4: chirico、gated-v6: oeilvert、`h2-sshd`: .112、`natsumi-sshd`: .111、`natsumi-sshd-myao`: duchamp、`natsumi-sshd-aki`: .112 |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.32.13、`containerd://2.3.6` |
| `tools/node-state.sh`（ファイル名） | `node-state-pre.txt` |
| `/opt/bin` の向き先、CNI の印と 4 つのプラグイン | `kubelet-v1.32.13`、`kubectl-v1.32.13`、`crictl-v1.32.0`、`etcdctl-3.5.34`。印 `v1.9.1`、4 つとも v1.9.1 |
| iscsid（MainPID、ActiveEnterTimestamp） | 1194943、2026-10-19 07:39:11Z |
| iSCSI のセッション | 1（sid 3、10.244.4.131:3260、`pvc-c6fbd833…`）。portal は今の instance-manager `-17a539db…` の IP（10.244.4.131）で、古いセッションは無い |
| `older-than-iscsid` のエンジン | なし（`pvc-c6fbd833…` のエンジンは 2026-10-19 08:10:04Z 起動） |
| アタッチされたボリュームと robustness | `fs/sites`（`pvc-c6fbd833…`）attached healthy。replica は 2（running 2） |
| 同じ Longhorn の PVC を使う Completed / Succeeded の Pod | なし（当たったのは `aphrael/aphrael-2` の `tumblr-like` の 3 つだけで、PV `aphrael-2` は NFS（`h2.fs.svc.cluster.local`）） |
| Pod の控え | `pods-pre.tsv`、20 個（`fs/sites`、longhorn の CSI sidecar 4 つ、instance-manager、longhorn-manager、longhorn-csi-plugin、engine-image、MetalLB の controller と speaker、kube-prometheus-operator など） |
| そのノードが告知している LoadBalancer | `kube-system/porkadot-kubernetes`（API の VIP、192.168.1.101） |
| cnidaria のログの error の数（8 台） | .111 15、.112 15、.113 16、braque 7、chirico 8、duchamp 14、oeilvert 0、pablo 7 |

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`

- 開始 02:27:29Z、終わり 02:27:47Z、rc 0。サンドボックスの中で流した。前と後の `git status --short assets porkadot.yaml` は空
- 出力の要点: SSHKit のコマンド 7 つがすべて `successful`。`install-deps.sh` 8.4 秒、`install-pkgs.sh` 3.5 秒、`install.sh` 4.1 秒
- kubelet の再起動の時刻: 02:27:47Z

## 4. 確認（02:28Z〜）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.33.13、`containerd://2.3.6` |
| 2 | バイナリ、CNI | `kubelet-v1.33.13`、`kubectl-v1.33.13`、`crictl-v1.33.0`、`etcdctl-3.5.34`。CNI の印 `v1.9.1`、4 つとも v1.9.1（変わらない） |
| 3 | iscsid | MainPID 1194943、ActiveEnterTimestamp 07:39:11Z。**前と同じ** |
| 4 | iSCSI のセッション | sid 3、10.244.4.131:3260、`pvc-c6fbd833…` の 1 つ。**前と同じ** |
| 5 | エンジン | `pvc-c6fbd833…` が 08:10:04Z の起動のまま動いている |
| 6 | Longhorn | `fs/sites` は attached healthy のまま。instance-manager `-17a539db…` は running、IP 10.244.4.131 のまま。Longhorn の node は Ready、schedulable。replica は running 2 のまま。16 attached healthy のまま。カーネルの I/O エラーは無い。kubelet の再起動の間（02:27:52Z）に Longhorn の node のイベント `Node pablo is down: manager pod longhorn-manager-hgj47 is not running`・`Waiting for disk ... to be ready / schedulable` が出て、同じ時刻に `Node pablo is ready`・`Disk ... is ready / schedulable` に戻った（runbook §5.3 の 6 の想定内。longhorn-manager は再起動していない） |
| 7 | Pod の再起動 | **`pods-pre.tsv` と `pods-post.tsv` の差分は無い**（20 個とも名前・UID・restartCount が同じ。`fs/sites`、instance-manager、longhorn-manager、CSI、speaker も再起動していない） |
| 8 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。pablo の cnidaria の error が 8 件増えた（`no route`、runbook §8.1）。ほかの 7 台は `no route` の行が 3 件ずつ増えた（info） |
| 9 | kubelet のログ | 起動の直後の `node "pablo" not found`（lister）、crio の factory、`Image garbage collection failed once`、`InvalidDiskCapacity`、eviction manager の imagefs、info の `Failed to trigger a manual run probe="Readiness"`（02:27:52Z の 2 回）だけ。続くエラーは無い。`FailedMount`（`no Pending workload pods`）は出ていない |
| 10 | 監視の FAIL | 無い |
| 11 | 告知していた LoadBalancer | API の VIP（192.168.1.101）の `/readyz` は `ok`、`/version` は 200。告知は pablo のまま（`announce-last` の差分なし）。ほかの LB も応答する |
| 12 | CSR | 無い |

## 5. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因 |
|---|---|---|
| — | — | 無かった（VIP を告知するノードの kubelet の再起動の間も） |

## 6. 次の 1 台へ進む条件（runbook §5.5）

| 条件 | 結果 |
|---|---|
| §5.3 がすべて合格 | はい |
| 全 8 台の Node が Ready、SchedulingDisabled でない | はい。v1.33.13: control-plane 3 台、duchamp、pablo、v1.32.13: braque、oeilvert、chirico |
| etcd 3/3 healthy、VIP が応答する | はい |
| Running / Completed 以外の Pod がベースラインから増えていない | 0 のまま |
| Longhorn のボリュームが healthy | 16 attached healthy、`cg-data` は detached のまま |
| Longhorn の設定がベースラインのまま | `5`、`disabled`、`block-if-contains-last-replica` |
| `check-apps.sh` | ベースラインと同じ |

## 7. 手順書との差、気づいたこと

- 無い。Longhorn のボリュームがアタッチされたまま 1.33 の kubelet にしても、エンジン・セッション・iscsid はそのままだった（runbook §2.1 の 3 の確かめ）
