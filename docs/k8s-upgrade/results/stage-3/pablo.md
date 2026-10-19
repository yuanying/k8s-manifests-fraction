# pablo の段 3 の作業記録

pablo（192.168.1.134）の kubelet を、porkadot 0.32.0 の `install kubelet --node` で v1.32.13 に上げた記録。手順は `../../runbook-stage-3.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 2 台目で、Longhorn のボリュームがアタッチされた最初の台。前の台は `duchamp.md`。読み取りの出力はタスクディレクトリの `notes/stage-3/pablo/`。

## 1. 事前の読み取り（2026-10-19 23:39Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.32.13 のノード: control-plane 3 台、duchamp、v1.31.14 のノード: pablo、braque、oeilvert、chirico。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー: 192.168.1.113。版: 3.5.34。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 |
| Longhorn | attached healthy 16、detached（ベースラインのもの）: `homegallery/cg-data` |
| Longhorn の設定 | `5`、`disabled`、`block-if-contains-last-replica` |
| controller-manager と scheduler の置き場所とリーダー | controller-manager .112（リーダー）・.113、scheduler .112（リーダー）・.111 |
| MetalLB の告知ノード | `duchamp.md` と同じ（VIP: **pablo**） |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.31.14、`containerd://2.3.6` |
| `/opt/bin` の向き先、CNI の印と 4 つのプラグイン | `kubelet-v1.31.14`、`kubectl-v1.31.14`、`crictl-v1.31.1`、`etcdctl-3.5.34`。印 `v1.4.1`、4 つとも v1.4.1 |
| iscsid（MainPID、ActiveEnterTimestamp） | 1194943、07:39:11Z |
| iSCSI のセッション | 1（sid 3、`10.244.4.131:3260` = 今の instance-manager `-17a539db…` の IP、`pvc-c6fbd833…`） |
| `older-than-iscsid` のエンジン | なし（エンジン `pvc-c6fbd833…` は 08:10:04Z 起動） |
| アタッチされたボリュームと robustness | `fs/sites`（pvc-c6fbd833）attached healthy |
| 同じ Longhorn の PVC を使う Completed / Succeeded の Pod | なし（`aphrael/aphrael-2` の組は出るが、PV は NFS（`h2.fs.svc.cluster.local`）） |
| Pod の控え | `pods-pre.tsv`、20 個（`fs/sites`、CSI の sidecar 4 つ、MetalLB の controller、kube-prometheus-operator など） |
| そのノードが告知している LoadBalancer | `kube-system/porkadot-kubernetes`（API の VIP 192.168.1.101） |
| cnidaria のログの error の数（8 台） | .111 8、.112 7、.113 8、duchamp 6（それぞれの `install kubelet` のもの）、ほか 0 |

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`

- 開始 23:39:39Z、終わり 23:40:36Z、rc 0。サンドボックスの中で流した
- 出力の要点: SSHKit のコマンド 7 つがすべて `successful`。`install-pkgs.sh` 9.6 秒、`install.sh` 4.0 秒
- kubelet の再起動の時刻: 23:40:36Z

## 4. 確認（23:41Z〜）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.32.13、`containerd://2.3.6` |
| 2 | バイナリ、CNI | `kubelet-v1.32.13`、`kubectl-v1.32.13`、`crictl-v1.32.0`。CNI の印 `v1.9.1`、4 つとも v1.9.1 |
| 3 | iscsid | MainPID 1194943、07:39:11Z。**前と同じ** |
| 4 | iSCSI のセッション | sid 3、`10.244.4.131:3260`、`pvc-c6fbd833…`。**前と同じ** |
| 5 | エンジン | `pvc-c6fbd833…` が 08:10:04Z の起動のまま動いている |
| 6 | Longhorn | `fs/sites` は attached healthy のまま（remount の要求は 2026-01 のもののまま）。instance-manager `-17a539db…` は running、IP 10.244.4.131 のまま。Longhorn の node は Ready。カーネルの I/O エラーは無い。kubelet の再起動の間に duchamp と同じ Longhorn の node のイベント（`Node pablo is down: manager pod ... is not running`、`Waiting for disk ...`）が出た |
| 7 | Pod の再起動 | **差分は無い**（20 個とも名前・UID・restartCount が同じ。`fs/sites`、instance-manager、longhorn-manager、CSI も再起動していない） |
| 8 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。pablo の cnidaria が `Reconciler error` を 7 件、23:40:32Z〜23:40:33Z に出した。ほかの 7 台は info を 2 件ずつ |
| 9 | kubelet のログ | 起動の直後の `node "pablo" not found`（lister）、crio の factory、`Image garbage collection failed once`、eviction manager の imagefs だけ。`FailedMount` は無い |
| 10 | 監視の FAIL | 無い（pablo が告知する VIP も途切れなかった） |
| 11 | 告知していた LoadBalancer | VIP の `/readyz` は `ok`、`/version` は 200。告知は pablo のまま（移らない）。ほかの LB も応答する |
| 12 | CSR | 無い |

## 5. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因 |
|---|---|---|
| — | — | 無かった |

## 6. 次の 1 台へ進む条件（runbook §5.5）

| 条件 | 結果 |
|---|---|
| §5.3 がすべて合格 | はい |
| 全 8 台の Node が Ready、SchedulingDisabled でない | はい。v1.32.13: control-plane 3 台、duchamp、pablo。v1.31.14: braque、oeilvert、chirico |
| etcd 3/3 healthy、VIP が応答する | はい |
| Running / Completed 以外の Pod がベースラインから増えていない | 0 のまま |
| Longhorn のボリュームが healthy | 16 attached healthy |
| Longhorn の設定がベースラインのまま | はい |
| `check-apps.sh` | ベースラインと同じ |

## 7. 手順書との差、気づいたこと

- Longhorn のボリュームがアタッチされたまま `install kubelet` しても、iscsid・セッション・エンジンはそのままで、ボリュームは healthy のままだった（runbook の冒頭の「dev で確かめていないもの」の 2 つ目の 1 台目）
