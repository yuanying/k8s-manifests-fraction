# duchamp の段 4 の作業記録

duchamp（192.168.1.135）の kubelet を、porkadot 0.33.0 の `install kubelet --node` で v1.33.13 に上げた記録。手順は `../../runbook-stage-4.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 1 台目。前の台は `192.168.1.111.md`。読み取りの出力はタスクディレクトリの `notes/stage-4/duchamp/`。

## 1. 事前の読み取り（2026-10-20 02:20Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.33.13 のノード: .111、.112、.113、v1.32.13 のノード: worker 5 台。SchedulingDisabled のノード: なし |
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
| iscsid（MainPID、ActiveEnterTimestamp） | 663628、2026-10-19 23:33:45Z（段 3 の `install kubelet` で起動したもの） |
| iSCSI のセッション | 0 |
| `older-than-iscsid` のエンジン | なし |
| アタッチされたボリュームと robustness | なし。replica は 10（running 8、stopped 2） |
| 同じ Longhorn の PVC を使う Completed / Succeeded の Pod | なし（`aphrael/tumblr-like-*` の Completed の 3 つは NFS の `aphrael-2` を使うもの） |
| Pod の控え | `pods-pre.tsv`、13 個（cnidaria、CoreDNS、kube-proxy、engine-image、instance-manager `-4df00b8c…`（10.244.5.112）、longhorn-csi-plugin、longhorn-manager、speaker、node-exporter、smart-exporter、Completed の `tumblr-like` 3 つ） |
| そのノードが告知している LoadBalancer | `natsumi/natsumi-sshd-myao`（`::133`） |
| cnidaria のログの error の数（8 台） | .111 15、.112 15、.113 16（control-plane の段 3・段 4 の `install kubelet` のもの）、braque 7、chirico 8、duchamp 6、oeilvert 0、pablo 7 |

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`

- 開始 02:20:57Z、終わり 02:21:13Z、rc 0。サンドボックスの中で流した。前と後の `git status --short assets porkadot.yaml` は空
- 出力の要点: SSHKit のコマンド 7 つがすべて `successful`。`install-deps.sh` 6.8 秒、`install-pkgs.sh` 3.5 秒、`install.sh` 2.9 秒
- kubelet の再起動の時刻: 02:21:13Z

## 4. 確認（02:22Z〜）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.33.13、`containerd://2.3.6` |
| 2 | バイナリ、CNI | `kubelet-v1.33.13`、`kubectl-v1.33.13`、`crictl-v1.33.0`、`etcdctl-3.5.34`。CNI の印 `v1.9.1`、4 つとも v1.9.1（変わらない） |
| 3 | iscsid | MainPID 663628、ActiveEnterTimestamp 23:33:45Z。**前と同じ** |
| 4 | iSCSI のセッション | 0 のまま |
| 5 | エンジン | なし |
| 6 | Longhorn | instance-manager `-4df00b8c…` は running、IP 10.244.5.112 のまま。Longhorn の node は Ready、schedulable。replica は running 8、stopped 2 のまま。16 attached healthy のまま。カーネルの I/O エラーは無い。`longhorn-system` のイベントは 02:21:18Z の engine image の `ready`（Normal）だけで、段 3 の `Node duchamp is down` は出なかった |
| 7 | Pod の再起動 | **`pods-pre.tsv` と `pods-post.tsv` の差分は無い**（13 個とも名前・UID・restartCount が同じ。instance-manager、longhorn-manager、longhorn-csi-plugin、engine-image も再起動していない） |
| 8 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。duchamp の cnidaria の error が 8 件増えた（`no route`、runbook §8.1）。ほかの 7 台は `no route` の行が 2 件ずつ増えた（info） |
| 9 | kubelet のログ | 起動の直後の `node "duchamp" not found`（lister）、crio の factory、eviction manager の imagefs、info の `Failed to trigger a manual run probe="Readiness"`（02:21:18Z、02:21:23Z）だけ。続くエラーは無い |
| 10 | 監視の FAIL | 無い |
| 11 | 告知していた LoadBalancer | `::133` の 3222 は SSH のバナーを返す。告知は duchamp のまま。ほかの LB も応答する |
| 12 | CSR | 無い |

NetworkPolicy の確認（runbook §1.9、§5.5。最初の worker の後）:

- ✋ `netcheck.sh`（up → run → down、02:22:51Z〜02:23:10Z）: **168/168 PASS**、名前空間 `cnidaria-netcheck` は NotFound
- `infra-admin` の 1 時間のトークンを発行（02:23:15Z。`auth can-i create daemonsets -n k8u-npcheck` と `delete pods -A` は `yes`）
- ✋ `npcheck.sh`（02:23:24Z〜02:26:01Z）:
  - `nft`（up の前）: 8 台とも 0
  - `up`: 3 つの DaemonSet が 02:23:40Z に 8/8 Ready
  - `nft`（up の後）: 8 台とも 9
  - `run`: **`OK 56, not OK 0`、rc 0**（PASS 24、BLOCK 32。段 3 と同じ）
  - `down`: 名前空間を消した。`nft` は 8 台とも 0、`get ns k8u-npcheck` は NotFound
- トークンのファイルを消した（02:26Z）
- 1.33 の apiserver と、1.33 の kubelet のノード（control-plane 3 台と duchamp）を含む形で、cnidaria が NetworkPolicy の規則を入れて消すことを確かめた

## 5. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因 |
|---|---|---|
| — | — | 無かった |

## 6. 次の 1 台へ進む条件（runbook §5.5）

| 条件 | 結果 |
|---|---|
| §5.3 がすべて合格 | はい |
| 全 8 台の Node が Ready、SchedulingDisabled でない | はい。v1.33.13: control-plane 3 台と duchamp、v1.32.13: ほかの worker 4 台 |
| etcd 3/3 healthy、VIP が応答する | はい |
| Running / Completed 以外の Pod がベースラインから増えていない | 0 のまま |
| Longhorn のボリュームが healthy | 16 attached healthy、`cg-data` は detached のまま |
| Longhorn の設定がベースラインのまま | `5`、`disabled`、`block-if-contains-last-replica` |
| `check-apps.sh`、`netcheck.sh` | ベースラインと同じ。168/168 PASS |
| NetworkPolicy の確認（§1.9） | 合格 |

## 7. 手順書との差、気づいたこと

- 最初の worker で、Longhorn の DaemonSet の Pod（instance-manager、longhorn-manager、longhorn-csi-plugin、engine-image）を含め、コンテナの再起動は無かった（runbook §2.1 の 3 の確かめ）
- 段 3 の duchamp で出た Longhorn の node の `is down` のイベントは、今回は出なかった
