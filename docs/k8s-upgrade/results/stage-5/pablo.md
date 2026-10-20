# pablo の段 5 の作業記録

pablo（192.168.1.134）の kubelet を、porkadot 0.34.1 の `install kubelet --node` で v1.34.12 に上げた記録。手順は `../../runbook-stage-5.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 2 台目。前は `duchamp.md`、次は `braque.md`。読み取りの出力はタスクディレクトリの `notes/stage-5/pablo/`。項目の形は `duchamp.md` と同じ。

## 1. 事前の読み取り（2026-10-20 10:19:58Z）

| 項目 | 結果 |
|---|---|
| クラスタ | 8 台 Ready（v1.34.12 は control-plane 3 台と duchamp）。etcd 3/3 healthy、3.6.15。Running / Completed 以外の Pod は 0。Longhorn は 16 + 1 |
| 対象のノード | v1.33.13。iscsid 1194943、10-19 07:39:11Z。セッション 1（sid 3、10.244.4.131 = 今の instance-manager、`pvc-c6fbd833…`）。エンジン 1（10-19 08:10:04Z、`older-than-iscsid` ではない）。アタッチされたボリューム `fs/sites`（attached healthy） |
| §8.12 の Pod | 無い |
| Pod の控え | `pods-pre.tsv`（20 個） |
| 告知している LoadBalancer | **API の VIP（192.168.1.101）** |

## 2. `install kubelet`

- 開始 10:20:16Z、終わり 10:20:44Z（28 秒）、rc 0。サンドボックスの中で流した
- `install-deps.sh` 9.9 秒、`install-pkgs.sh` 11.2 秒、`install.sh` 4.0 秒。kubelet の再起動 10:20:44Z

## 3. 確認（10:21:39Z）

| # | 確認 | 結果 |
|---|---|---|
| 1、2 | Node、バイナリ | v1.34.12。`kubelet-v1.34.12`、`kubectl-v1.34.12`、`crictl-v1.34.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` のまま |
| 3 | iscsid | 1194943 のまま |
| 4 | iSCSI のセッション | sid 3、同じ portal・target |
| 5 | エンジン | 同じボリューム、同じ起動の時刻 |
| 6 | Longhorn | `fs/sites` は attached healthy のまま、instance-manager は同じ。Longhorn の node の `is down`・`Waiting for disk` の event（数秒）。カーネルの I/O エラーなし |
| 7 | Pod の再起動 | **差分なし**（20 個） |
| 10 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。pablo の cnidaria の error 1（10:20:41Z の `routes` の `no route to host`。次の reconcile で入った。runbook §8.1） |
| 11 | kubelet のログ | 止まる前の古い kubelet の `Unable to write event`（10:20:41Z、1 回）と、起動のときのもの |
| 12 | 監視の FAIL | 0（VIP も途切れなかった） |
| 14 | 告知していた LoadBalancer | VIP は pablo のまま（`/readyz` は `ok`）。metallb の speaker（`speaker-9fwg2`）の Liveness probe の失敗が 1 回（10:20:40Z、`dial tcp 192.168.1.134:7472: connect: network is unreachable`。`dns` の addon が `systemd-networkd` を再起動した瞬間。runbook §8.1）。restartCount は 17 のまま |
| 13、15 | ほか | 再起動なし、CSR なし |

## 4. 次の 1 台へ進む条件

すべて合格。

## 5. 手順書との差、気づいたこと

- なし
