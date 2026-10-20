# duchamp の段 5 の作業記録

duchamp（192.168.1.135）の kubelet を、porkadot 0.34.1 の `install kubelet --node` で v1.34.12 に上げた記録。手順は `../../runbook-stage-5.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 1 台目。前は `192.168.1.111.md`、次は `pablo.md`。読み取りの出力はタスクディレクトリの `notes/stage-5/duchamp/`。

## 1. 事前の読み取り（2026-10-20 10:14:31Z）

| 項目 | 結果 |
|---|---|
| クラスタ | 8 台 Ready（control-plane 3 台が v1.34.12、worker 5 台が v1.33.13）。etcd 3/3 healthy、3 台とも 3.6.15、cluster version 3.6.0、リーダー .112。`/readyz` は `ok`。Running / Completed 以外の Pod は 0。Longhorn は 16 + 1 |
| 対象のノード | v1.33.13。`/opt/bin` は `kubelet-v1.33.13`、`kubectl-v1.33.13`、`crictl-v1.33.0`、`etcdctl-3.5.34`、`etcdutl:none`。CNI は `v1.9.1`。iscsid 663628、10-19 23:33:45Z。セッション・エンジン・アタッチされたボリュームは無い |
| §8.12 の Pod | 無い（同じ PVC を使う Succeeded の Pod は NFS の `aphrael/aphrael-2` の `tumblr-like` の 3 つだけ。§8.12 に当たらない） |
| Pod の控え | `pods-pre.tsv`（16 個） |
| 告知している LoadBalancer | `::133`（`natsumi-sshd-myao`） |

## 2. `install kubelet`

- 開始 10:14:49Z、終わり 10:15:16Z（27 秒）、rc 0。サンドボックスの中で流した
- `install-deps.sh` 10.1 秒、`install-pkgs.sh` 11.4 秒、`install.sh` 3.0 秒。kubelet の再起動 10:15:16Z

## 3. 確認（10:16:11Z）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.34.12、`containerd://2.3.6` |
| 2 | バイナリ、CNI | `kubelet-v1.34.12`、`kubectl-v1.34.12`、`crictl-v1.34.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` のまま |
| 3 | iscsid | 663628、10-19 23:33:45Z のまま |
| 4〜6 | iSCSI、エンジン、Longhorn | セッション・エンジンなし。Longhorn は 16 + 1 のまま、instance-manager は同じ。Longhorn の node の `is down`・`Waiting for disk` の event（kubelet の再起動の数秒）。カーネルの I/O エラーなし |
| 7 | Pod の再起動 | **差分なし**（16 個とも名前・UID・restartCount が同じ） |
| 10 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。duchamp の cnidaria の error 8（`no route`。runbook §8.1） |
| 11 | kubelet のログ | 1.34.12 の起動のときのもの（`Error getting the current node from lister`、crio の factory、`no imagefs label`）だけ |
| 12 | 監視の FAIL | 0 |
| 13 | leader election の controller | 再起動なし |
| 14 | 告知していた LoadBalancer | `::133` は SSH のバナーを返す。告知は duchamp のまま |
| 15 | CSR | なし |

NetworkPolicy と Pod 間通信の確認（runbook §5.5。1.34 の apiserver と 1.34 の kubelet のノードを含む形）:

- ✋ `netcheck.sh`（up → run → down、10:16:57Z〜10:17:15Z）: **168/168 PASS**、名前空間 `cnidaria-netcheck` は NotFound
- `infra-admin` の 1 時間のトークンを発行（10:17Z。`auth can-i create daemonsets -n k8u-npcheck` は `yes`）
- ✋ `npcheck.sh`（10:17:21Z〜10:19:53Z）: `nft` は up の前 8 台とも 0、up の後 8 台とも 9、`run` は **`OK 56, not OK 0`**、down の後 8 台とも 0。`k8u-npcheck` は NotFound
- トークンのファイルを消した（10:19:53Z）

## 4. 次の 1 台へ進む条件

すべて合格。

## 5. 手順書との差、気づいたこと

- なし
