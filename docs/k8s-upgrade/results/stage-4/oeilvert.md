# oeilvert の段 4 の作業記録

oeilvert（192.168.1.82）の kubelet を、porkadot 0.33.0 の `install kubelet --node` で v1.33.13 に上げた記録。手順は `../../runbook-stage-4.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 4 台目。前の台は `braque.md`。読み取りの出力はタスクディレクトリの `notes/stage-4/oeilvert/`。

## 1. 事前の読み取り（2026-10-20 02:31Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.33.13 のノード: control-plane 3 台、duchamp、pablo、braque、v1.32.13 のノード: oeilvert、chirico。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー: 192.168.1.113（`57ec6f12ac7b683e`）、raft term 23120。版: 3.5.34。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 |
| Longhorn | attached healthy 16、detached（ベースラインのもの）: `homegallery/cg-data` |
| Longhorn の設定 | `5`、`disabled`、`block-if-contains-last-replica` |
| controller-manager と scheduler の置き場所とリーダー | controller-manager .111・.113（リーダー）、scheduler .113・.112（リーダー） |
| MetalLB の告知ノード | VIP: pablo、gated-v4: chirico、gated-v6: oeilvert、`h2-sshd`: .112、`natsumi-sshd`: .111、`natsumi-sshd-myao`: duchamp、`natsumi-sshd-aki`: .112 |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.32.13、`containerd://2.3.6` |
| `tools/node-state.sh`（ファイル名） | `node-state-pre.txt` |
| `/opt/bin` の向き先、CNI の印と 4 つのプラグイン | `kubelet-v1.32.13`、`kubectl-v1.32.13`、`crictl-v1.32.0`、`etcdctl-3.5.34`。印 `v1.9.1`、4 つとも v1.9.1 |
| iscsid（MainPID、ActiveEnterTimestamp） | 6334、2026-10-19 09:04:34Z |
| iSCSI のセッション | 5（sid 3〜7、どれも 10.244.7.116:3260）。portal は今の instance-manager `-d5905a9e…` の IP（10.244.7.116）で、古いセッションは無い |
| `older-than-iscsid` のエンジン | なし（5 つのエンジンは 09:12:23Z〜09:17:27Z 起動） |
| アタッチされたボリュームと robustness | 5 本とも attached healthy: `natsumi`（`pvc-6b8f51fa…`）、`natsumi-aki`（`pvc-e224cffa…`）、`prometheus-…-1`（`pvc-99c35b80…`、replica 1）、`fraction-agents/data-wiki-keeper-0`（`pvc-092a74ed…`）、`fraction-agents/data-gmail-agent-0`（`pvc-aee2ec0e…`）。replica は 11（running 10、stopped 1） |
| 同じ Longhorn の PVC を使う Completed / Succeeded の Pod | なし（当たったのは NFS の `aphrael/aphrael-2` の `tumblr-like` の 3 つだけ） |
| Pod の控え | `pods-pre.tsv`、39 個（instance-manager、longhorn-manager、CSI、`natsumi-0`、`natsumi-aki-0`、`prometheus-kube-prometheus-1`、`alertmanager-kube-prometheus-0`、`gated`、`homegallery/api`、approver など） |
| そのノードが告知している LoadBalancer | `gated-system/gated-v6`（`::200`） |
| cnidaria のログの error の数（8 台） | .111 15、.112 15、.113 16、braque 14、chirico 8、duchamp 14、oeilvert 0、pablo 15 |

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`

- 開始 02:32:15Z、終わり 02:32:32Z、rc 0。サンドボックスの中で流した。前と後の `git status --short assets porkadot.yaml` は空
- 出力の要点: SSHKit のコマンド 7 つがすべて `successful`。`install-deps.sh` 5.8 秒、`install-pkgs.sh` 3.4 秒、`install.sh` 4.9 秒
- kubelet の再起動の時刻: 02:32:32Z

## 4. 確認（02:33Z〜）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.33.13、`containerd://2.3.6` |
| 2 | バイナリ、CNI | `kubelet-v1.33.13`、`kubectl-v1.33.13`、`crictl-v1.33.0`、`etcdctl-3.5.34`。CNI の印 `v1.9.1`、4 つとも v1.9.1（変わらない） |
| 3 | iscsid | MainPID 6334、ActiveEnterTimestamp 09:04:34Z。**前と同じ** |
| 4 | iSCSI のセッション | sid 3〜7 の 5 つ、portal・target とも**前と同じ** |
| 5 | エンジン | 5 つとも同じ起動の時刻で動いている |
| 6 | Longhorn | 5 本とも attached healthy のまま（`volumes` の差分なし）。instance-manager `-d5905a9e…` は running、IP 10.244.7.116 のまま。Longhorn の node は Ready、schedulable。replica は running 10、stopped 1 のまま。カーネルの I/O エラーは無い。kubelet の再起動の間（02:32:43Z〜44Z）に Longhorn の node のイベント `Node oeilvert is down: manager pod longhorn-manager-wn5sl is not running`・`Waiting for disk ... to be ready / schedulable`（2 つのディスク）が出て、02:32:44Z に `Node oeilvert is ready`・`Disk ... is ready / schedulable` に戻った（runbook §5.3 の 6 の想定内）。orphan の件は下の注 |
| 7 | Pod の再起動 | **`pods-pre.tsv` と `pods-post.tsv` の差分は無い**（39 個とも名前・UID・restartCount が同じ。instance-manager、longhorn-manager、CSI、`natsumi*`、prometheus、gated も再起動していない） |
| 8 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。oeilvert の cnidaria の error は 0 のまま（段 3 と同じ）。ほかの 7 台は `no route` の行が増えた（info） |
| 9 | kubelet のログ | 起動の直後の `node "oeilvert" not found`（lister）、crio の factory、`Image garbage collection failed once`、`InvalidDiskCapacity`、eviction manager の imagefs、info の `Failed to trigger a manual run probe="Readiness"`（02:32:36Z〜02:32:45Z に 17 回。Pod の多いノードなので数が多い）だけ。続くエラーは無い。`FailedMount`（`no Pending workload pods`）は出ていない |
| 10 | 監視の FAIL | 無い |
| 11 | 告知していた LoadBalancer | `[...:ace::200]` の 80 は 404（応答あり）。gated-v6 の告知は oeilvert のまま。ほかの LB も応答する。`natsumi-sshd`（`::132`、.111）と `natsumi-sshd-aki`（`::134`、.112）が 02:32:43Z〜45Z にもう一度 `serviceAnnounced` された（告知ノードは変わらない） |
| 12 | CSR | 無い |

- **Longhorn の orphan の作り直し**（runbook に無い。害は無い）: oeilvert の 3 つの orphan（`orphan-1eb55a24…`、`orphan-373d8f8d…`、`orphan-ea9813d8…`。古い replica のデータの置き場所 `pvc-c4944b75-…-7dade898`（`/var/lib/longhorn2/`）、`pvc-625c8825-…-9d2b30c9`（同）、`pvc-ba224143-…-89c1c4dd`（`/var/lib/longhorn/`））に、02:32:44Z に `OrphanCleanupCompleted` が出て、02:32:57Z に同じ名前の orphan が作り直された。orphan の名前はデータの置き場所から決まるので、作り直されたことは、ディスクのデータが残っていることを示す。`orphan-resource-auto-deletion` は空（自動では消さない）。今の replica・ボリュームには関係しない（replica の数・状態、ボリュームの robustness は変わらない）。kubelet の再起動で Longhorn の node が一瞬 down になったときに、longhorn-manager が orphan の CR を片付けて検出し直したものと見ている（確かめていない）。duchamp の 3 つの orphan の作成が段 3 の duchamp の `install kubelet` の直後（2026-10-19 23:34:16Z）なので、段 3 でも同じことが起きていたと見ている

## 5. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因 |
|---|---|---|
| — | — | 無かった |

## 6. 次の 1 台へ進む条件（runbook §5.5）

| 条件 | 結果 |
|---|---|
| §5.3 がすべて合格 | はい |
| 全 8 台の Node が Ready、SchedulingDisabled でない | はい。v1.33.13: chirico のほかの 7 台、v1.32.13: chirico |
| etcd 3/3 healthy、VIP が応答する | はい |
| Running / Completed 以外の Pod がベースラインから増えていない | 0 のまま |
| Longhorn のボリュームが healthy | 16 attached healthy、`cg-data` は detached のまま |
| Longhorn の設定がベースラインのまま | `5`、`disabled`、`block-if-contains-last-replica` |
| `check-apps.sh` | ベースラインと同じ |

## 7. 手順書との差、気づいたこと

- Longhorn の orphan の CR が、kubelet の再起動の間に片付けられて作り直される（上の注）。runbook §5.3 の 6 の想定内のイベントに足す
