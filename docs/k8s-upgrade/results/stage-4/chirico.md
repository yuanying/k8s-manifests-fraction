# chirico の段 4 の作業記録

chirico（192.168.1.83）の kubelet を、porkadot 0.33.0 の `install kubelet --node` で v1.33.13 に上げた記録。手順は `../../runbook-stage-4.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 5 台目（最後）。前の台は `oeilvert.md`。読み取りの出力はタスクディレクトリの `notes/stage-4/chirico/`。

## 1. 事前の読み取り（2026-10-20 02:34Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.33.13 のノード: chirico のほかの 7 台、v1.32.13 のノード: chirico。SchedulingDisabled のノード: なし |
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
| iscsid（MainPID、ActiveEnterTimestamp） | 4447、2026-10-19 09:17:30Z |
| iSCSI のセッション | 10（sid 1〜5、7〜11、どれも 10.244.8.216:3260）。portal は今の instance-manager `-4128231c…` の IP（10.244.8.216）で、古いセッションは無い |
| `older-than-iscsid` のエンジン | 1（`pvc-625c8825…`、`prometheus-…-0`、09:17:28Z。ベースラインと同じもので、runbook §2.7 の注の形。増えていない） |
| アタッチされたボリュームと robustness | 10 本とも attached healthy（`tumblr-data`、`ero-data`、`fs/data`、`fs/h2`、`natsumi-myao`、`prometheus-…-0`（replica 1）、`fraction-agents` の 4 つ）。replica は 11（running 10、stopped 1） |
| 同じ Longhorn の PVC を使う Completed / Succeeded の Pod | なし（当たったのは NFS の `aphrael/aphrael-2` の `tumblr-like` の 3 つだけ） |
| Pod の控え | `pods-pre.tsv`、46 個（instance-manager、longhorn-manager、`fs/h2`、`fs/data`、`natsumi-myao-0`、`prometheus-kube-prometheus-0`、`fraction-agents` の 4 つ、`gated`、CoreDNS など） |
| そのノードが告知している LoadBalancer | `gated-system/gated-v4`（192.168.1.200） |
| cnidaria のログの error の数（8 台） | .111 15、.112 15、.113 16、braque 14、chirico 8、duchamp 14、oeilvert 0、pablo 15 |

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`

- 開始 02:35:19Z、終わり 02:35:35Z、rc 0。サンドボックスの中で流した。前と後の `git status --short assets porkadot.yaml` は空
- 出力の要点: SSHKit のコマンド 7 つがすべて `successful`。`install-deps.sh` 6.0 秒、`install-pkgs.sh` 3.3 秒、`install.sh` 4.2 秒
- kubelet の再起動の時刻: 02:35:35Z

## 4. 確認（02:36Z〜）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.33.13、`containerd://2.3.6` |
| 2 | バイナリ、CNI | `kubelet-v1.33.13`、`kubectl-v1.33.13`、`crictl-v1.33.0`、`etcdctl-3.5.34`。CNI の印 `v1.9.1`、4 つとも v1.9.1（変わらない） |
| 3 | iscsid | MainPID 4447、ActiveEnterTimestamp 09:17:30Z。**前と同じ** |
| 4 | iSCSI のセッション | 10 本とも sid・portal・target が**前と同じ** |
| 5 | エンジン | 10 個とも同じ起動の時刻で動いている（`older-than-iscsid` は `pvc-625c8825…` の 1 つのまま） |
| 6 | Longhorn | 10 本とも attached healthy のまま（`volumes` の差分なし）。instance-manager `-4128231c…` は running、IP 10.244.8.216 のまま。Longhorn の node は Ready、schedulable。replica は running 10、stopped 1 のまま。カーネルの I/O エラーは無い。kubelet の再起動の間に Longhorn の node のイベント `Node chirico is down: manager pod longhorn-manager-v6f2c is not running`・`Waiting for disk ... to be ready / schedulable` が出て、`Node chirico is ready`・`Disk ... is ready / schedulable` に戻った（runbook §5.3 の 6 の想定内）。chirico には orphan が無く、`OrphanCleanupCompleted` は出ていない |
| 7 | Pod の再起動 | **`pods-pre.tsv` と `pods-post.tsv` の差分は無い**（46 個とも名前・UID・restartCount が同じ。instance-manager、longhorn-manager、`fs/h2`、`fs/data`、prometheus、CoreDNS、gated も再起動していない） |
| 8 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。chirico の cnidaria の error が 8 件増えた（`no route`、runbook §8.1）。ほかの 7 台は `no route` の行が増えた（info） |
| 9 | kubelet のログ | 起動の直後の `node "chirico" not found`（lister）、crio の factory、`Image garbage collection failed once`、`InvalidDiskCapacity`、eviction manager の imagefs、info の `Failed to trigger a manual run probe="Readiness"`（02:35:39Z〜02:35:49Z に 12 回）だけ。続くエラーは無い。`FailedMount`（`no Pending workload pods`）は出ていない |
| 10 | 監視の FAIL | 無い（gated-v4 の 192.168.1.200 も途切れていない） |
| 11 | 告知していた LoadBalancer | 192.168.1.200 の 80 は 404（応答あり）。gated-v4 の告知は下の注のとおり一瞬 oeilvert に移り、chirico に戻った。ほかの LB も応答する。gated-v6（oeilvert）と `natsumi-sshd-myao`（duchamp）が 02:35:41Z・02:35:49Z にもう一度 `serviceAnnounced` された（告知ノードは変わらない） |
| 12 | CSR | 無い |

- **gated-v4 の告知の動き**（`externalTrafficPolicy: Local`）: oeilvert の speaker が 02:35:40Z に 192.168.1.200 を `serviceAnnounced` し、02:35:41Z に `serviceWithdrawn`（`notOwner`）。chirico の speaker が 02:35:59Z に `serviceWithdrawn`（`notOwner`）と `serviceAnnounced` を続けて出した（ログの順）。最後は chirico が告知している。`gated` の Pod（chirico、oeilvert）は再起動しておらず、EndpointSlice の 2 つとも ready。1 秒ごとの監視の LB の FAIL は無い。kubelet の再起動の間に speaker の見る状態が一瞬変わったものと見ている（確かめていない。段 3 の chirico では告知の行は 23:49:38Z の `serviceAnnounced` だけが残っていた）
- 各台の記録の「告知ノード」は、speaker のログの IP ごとの最後の行で読んでいる。同じ秒の行は時刻だけでは順が決まらないので、取り下げと告知が同じ秒に出たときは、ログの順で読み直す

## 5. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因 |
|---|---|---|
| — | — | 無かった |

## 6. 次の 1 台へ進む条件（runbook §5.5）

最後の台。§6 の完了の確認へ進む。

| 条件 | 結果 |
|---|---|
| §5.3 がすべて合格 | はい |
| 全 8 台の Node が Ready、SchedulingDisabled でない | はい。8 台とも v1.33.13 |
| etcd 3/3 healthy、VIP が応答する | はい |
| Running / Completed 以外の Pod がベースラインから増えていない | 0 のまま |
| Longhorn のボリュームが healthy | 16 attached healthy、`cg-data` は detached のまま |
| Longhorn の設定がベースラインのまま | `5`、`disabled`、`block-if-contains-last-replica` |
| `check-apps.sh` | ベースラインと同じ |

## 7. 手順書との差、気づいたこと

- gated-v4 の告知が kubelet の再起動の間に一瞬 oeilvert へ移って戻った（上の注）。途切れは監視に出ていない
