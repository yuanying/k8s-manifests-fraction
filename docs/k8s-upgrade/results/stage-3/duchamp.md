# duchamp の段 3 の作業記録

duchamp（192.168.1.135）の kubelet を、porkadot 0.32.0 の `install kubelet --node` で v1.32.13 に上げた記録。手順は `../../runbook-stage-3.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 1 台目。前の台は `192.168.1.111.md`。読み取りの出力はタスクディレクトリの `notes/stage-3/duchamp/`。

## 1. 事前の読み取り（2026-10-19 23:33Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.32.13 のノード: .111、.112、.113、v1.31.14 のノード: worker 5 台。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー: 192.168.1.113（`57ec6f12ac7b683e`）、raft term 23118。版: 3.5.34。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 |
| Longhorn | attached healthy 16、detached（ベースラインのもの）: `homegallery/cg-data` |
| Longhorn の設定 | `5`、`disabled`、`block-if-contains-last-replica` |
| controller-manager と scheduler の置き場所とリーダー | controller-manager .112（リーダー）・.113、scheduler .112（リーダー）・.111 |
| MetalLB の告知ノード | VIP: pablo、gated-v4: chirico、gated-v6: oeilvert、`h2-sshd`: .112、`natsumi-sshd`: .111、`natsumi-sshd-myao`: duchamp、`natsumi-sshd-aki`: .112 |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.31.14、`containerd://2.3.6` |
| `/opt/bin` の向き先、CNI の印と 4 つのプラグイン | `kubelet-v1.31.14`、`kubectl-v1.31.14`、`crictl-v1.31.1`、`etcdctl-3.5.34`。印 `v1.4.1`、bridge・host-local・portmap v1.9.1、loopback v1.4.1 |
| iscsid（MainPID、ActiveEnterTimestamp） | **0（動いていない。`iscsid.socket` だけ）** |
| iSCSI のセッション | 0 |
| `older-than-iscsid` のエンジン | なし |
| アタッチされたボリュームと robustness | なし。replica は 10（running 8、stopped 2） |
| 同じ Longhorn の PVC を使う Completed / Succeeded の Pod | なし（`aphrael/tumblr-like-*` の Completed の 3 つは NFS の `aphrael-2` を使うもの） |
| Pod の控え | `pods-pre.tsv`、13 個（cnidaria、CoreDNS、kube-proxy、engine-image、instance-manager `-4df00b8c…`（10.244.5.112）、longhorn-csi-plugin、longhorn-manager、speaker、node-exporter、smart-exporter、Completed の `tumblr-like` 3 つ） |
| そのノードが告知している LoadBalancer | `natsumi/natsumi-sshd-myao`（`::133`） |
| cnidaria のログの error の数（8 台） | .111 8、.112 7、.113 8（control-plane の `install kubelet` のもの）、worker 0 |

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`

- 開始 23:33:17Z、終わり 23:33:48Z、rc 0。サンドボックスの中で流した
- 出力の要点: SSHKit のコマンド 7 つがすべて `successful`。`install-pkgs.sh` 9.6 秒、`install.sh` 3.0 秒
- kubelet の再起動の時刻: 23:33:47Z。iscsid の起動: 23:33:45Z

## 4. 確認（23:34Z〜）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.32.13、`containerd://2.3.6` |
| 2 | バイナリ、CNI | `kubelet-v1.32.13`、`kubectl-v1.32.13`、`crictl-v1.32.0`。CNI の印 `v1.9.1`、4 つとも v1.9.1 |
| 3 | iscsid | **`install kubelet` の 23:33:45Z に起動した**（MainPID 663628、`TriggeredBy: iscsid.socket`）。前は動いていなかった台なので、runbook §5.3 の 3・§8.10 の見込みどおり |
| 4 | iSCSI のセッション | 0 のまま |
| 5 | エンジン | なし |
| 6 | Longhorn | instance-manager `-4df00b8c…` は running、IP 10.244.5.112 のまま。Longhorn の node は Ready。replica は running 8、stopped 2 のまま。16 attached healthy のまま。カーネルの I/O エラーは無い。kubelet の再起動の間に Longhorn の node のイベント `Node duchamp is down: manager pod longhorn-manager-pzx5h is not running`、`Waiting for disk ... to be ready / schedulable` が出た（23:33:5xZ。下の注） |
| 7 | Pod の再起動 | **`pods-pre.tsv` と `pods-post.tsv` の差分は無い**（13 個とも名前・UID・restartCount が同じ。instance-manager、longhorn-manager、longhorn-csi-plugin、engine-image も再起動していない） |
| 8 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。duchamp の cnidaria が `Reconciler error` を 6 件、23:33:45Z の 1 秒に出した。ほかの 7 台は info の `no route for a family` を 2 件ずつ |
| 9 | kubelet のログ | 起動の直後の `node "duchamp" not found`（lister）、crio の factory、eviction manager の imagefs だけ。続くエラーは無い |
| 10 | 監視の FAIL | 無い |
| 11 | 告知していた LoadBalancer | `::133` の 3222 は SSH のバナーを返す。告知は移らない。ほかの LB も応答する |
| 12 | CSR | 無い |

- 6 の Longhorn の node のイベントは、kubelet の再起動の数秒の間に longhorn-manager の Pod の状態が読めなくなったときのもの（段 2 の summary の「Longhorn の node の一瞬の not ready」と同じ）。longhorn-manager のコンテナは再起動しておらず、確認の時点で node は Ready、schedulable

NetworkPolicy の確認（runbook §1.9。最初の worker の後）:

- `infra-admin` の 1 時間のトークンを発行（23:35Z）
- ✋ `netcheck.sh`（up → run → down、23:35:2xZ〜23:35:49Z）: **168/168 PASS**
- ✋ `npcheck.sh`（23:36Z〜23:38:38Z）:
  - `nft`（up の前）: 8 台とも 0
  - `up`: 3 つの DaemonSet が 23:36:10Z に 8/8 Ready
  - `nft`（up の後）: 8 台とも 9（`k8u-npcheck/allow-8080` の規則が 8 台の `table inet cnidaria` に入った）
  - `run`（23:36:28Z〜23:38:13Z）: **`OK 56, not OK 0`、rc 0**（PASS 24 = 各サーバーの自分の 9090 の 8 と allowed → 8080 の v4・v6 の 16、BLOCK 32 = allowed → 9090 と denied → 8080 の v4・v6）
  - `down`: 名前空間を消した。`nft` は 8 台とも 0、`get ns k8u-npcheck` は NotFound
- トークンのファイルを消した（23:38Z）
- 1.32 の apiserver と、1.32 の kubelet のノード（control-plane 3 台と duchamp）を含む形で、cnidaria が NetworkPolicy の規則を入れて消すことを確かめた

## 5. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因 |
|---|---|---|
| — | — | 無かった |

## 6. 次の 1 台へ進む条件（runbook §5.5）

| 条件 | 結果 |
|---|---|
| §5.3 がすべて合格 | はい |
| 全 8 台の Node が Ready、SchedulingDisabled でない | はい。v1.32.13: control-plane 3 台と duchamp、v1.31.14: ほかの worker 4 台 |
| etcd 3/3 healthy、VIP が応答する | はい |
| Running / Completed 以外の Pod がベースラインから増えていない | 0 のまま |
| Longhorn のボリュームが healthy | 16 attached healthy、`cg-data` は detached のまま |
| Longhorn の設定がベースラインのまま | `5`、`disabled`、`block-if-contains-last-replica` |
| `check-apps.sh`、`netcheck.sh` | ベースラインと同じ。168/168 PASS |
| NetworkPolicy の確認（§1.9） | 合格 |

## 7. 手順書との差、気づいたこと

- 最初の worker で、Longhorn の DaemonSet の Pod（instance-manager、longhorn-manager、longhorn-csi-plugin、engine-image）を含め、コンテナの再起動は無かった（runbook §2.1 の 3 の確かめ）
- duchamp の iscsid は、0.32.0 の `install-pkgs.sh` の `systemctl start` で起動した（runbook §8.10 の見込みどおり）
- Longhorn の node の一瞬の down のイベントは runbook §5.3 に無いが、段 2 と同じ一時的なもの
