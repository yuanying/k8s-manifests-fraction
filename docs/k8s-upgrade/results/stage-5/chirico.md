# chirico の段 5 の作業記録

chirico（192.168.1.83）の kubelet を、porkadot 0.34.1 の `install kubelet --node` で v1.34.12 に上げた記録。手順は `../../runbook-stage-5.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 5 台目（最後）。前は `oeilvert.md`、次は `summary.md`。読み取りの出力はタスクディレクトリの `notes/stage-5/chirico/`。項目の形は `duchamp.md` と同じ。

## 1. 事前の読み取り（2026-10-20 10:26:38Z）

| 項目 | 結果 |
|---|---|
| クラスタ | 8 台 Ready（v1.33.13 は chirico だけ）。etcd 3/3 healthy、3.6.15。Running / Completed 以外の Pod は 0。Longhorn は 16 + 1 |
| 対象のノード | v1.33.13。iscsid 4447、10-19 09:17:30Z。セッション 10（どれも 10.244.8.216 = 今の instance-manager）。エンジン 10、`older-than-iscsid` は `pvc-625c8825…`（`prometheus-…-0`）の 1 つ（ベースラインと同じ、runbook §2.7 の注）。アタッチされたボリューム 10、どれも attached healthy |
| §8.12 の Pod | 無い |
| Pod の控え | `pods-pre.tsv`（46 個） |
| 告知している LoadBalancer | gated-v4（192.168.1.200） |

## 2. `install kubelet`

- 開始 10:26:55Z、終わり 10:27:18Z（23 秒）、rc 0。サンドボックスの中で流した
- `install-deps.sh` 8.0 秒、`install-pkgs.sh` 8.4 秒、`install.sh` 4.3 秒。kubelet の再起動 10:27:18Z

## 3. 確認（10:28:13Z）

| # | 確認 | 結果 |
|---|---|---|
| 1、2 | Node、バイナリ | v1.34.12。`kubelet-v1.34.12`、`kubectl-v1.34.12`、`crictl-v1.34.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` のまま |
| 3 | iscsid | 4447 のまま |
| 4 | iSCSI のセッション | 10 とも同じ sid・portal・target（`tools/node-state.sh` の差は `bin` の行だけ） |
| 5 | エンジン | 10 とも同じボリューム、同じ起動の時刻。`older-than-iscsid` は 1 つのまま |
| 6 | Longhorn | 10 とも attached healthy のまま、instance-manager は同じ。Longhorn の node の `is down`・`Waiting for disk` の event（数秒）。カーネルの I/O エラーなし |
| 7 | Pod の再起動 | **差分なし**（46 個。prometheus の `-0` も） |
| 10 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。chirico の cnidaria の error 8（runbook §8.1） |
| 11 | kubelet のログ | 起動のときのものと `Failed to trigger a manual run`（2 回） |
| 12 | 監視の FAIL | 0 |
| 14 | 告知していた LoadBalancer | 下の注 |
| 13、15 | ほか | 再起動なし、CSR なし |

- **gated-v4 の告知**: 10:27:23Z に oeilvert の speaker が 192.168.1.200 を `serviceAnnounced` → `serviceWithdrawn`（`notOwner`）、chirico の speaker が 10:27:40Z にもう一度 `serviceAnnounced`。告知ノードは chirico のまま。監視（`192.168.1.200` を 1 秒ごと）の FAIL は無い。同じ間に `::133`（duchamp）が 10:27:22Z に withdraw、10:27:27Z に announce し直した（告知ノードは同じ）。段 4 の chirico と同じ形

## 4. 次の 1 台へ進む条件

8 台を終えたので、runbook §6 の完了の確認（`summary.md`）に進んだ。

## 5. 手順書との差、気づいたこと

- なし
