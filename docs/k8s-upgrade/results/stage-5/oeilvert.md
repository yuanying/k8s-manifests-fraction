# oeilvert の段 5 の作業記録

oeilvert（192.168.1.82）の kubelet を、porkadot 0.34.1 の `install kubelet --node` で v1.34.12 に上げた記録。手順は `../../runbook-stage-5.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 4 台目。前は `braque.md`、次は `chirico.md`。読み取りの出力はタスクディレクトリの `notes/stage-5/oeilvert/`。項目の形は `duchamp.md` と同じ。

## 1. 事前の読み取り（2026-10-20 10:24:21Z）

| 項目 | 結果 |
|---|---|
| クラスタ | 8 台 Ready（v1.33.13 は oeilvert と chirico）。etcd 3/3 healthy、3.6.15。Running / Completed 以外の Pod は 0。Longhorn は 16 + 1 |
| 対象のノード | v1.33.13。iscsid 6334、10-19 09:04:34Z。セッション 5（sid 3〜7、どれも 10.244.7.116 = 今の instance-manager）。エンジン 5（`older-than-iscsid` は無い）。アタッチされたボリューム 5（`fraction-agents` の 2 つ、`natsumi/natsumi`・`natsumi-aki`、`prometheus-…-1`（replica 1））、どれも attached healthy |
| §8.12 の Pod | 無い |
| Pod の控え | `pods-pre.tsv`（39 個） |
| 告知している LoadBalancer | gated-v6（`::200`） |

## 2. `install kubelet`

- 開始 10:24:37Z、終わり 10:25:00Z（23 秒）、rc 0。サンドボックスの中で流した
- `install-deps.sh` 8.7 秒、`install-pkgs.sh` 6.0 秒、`install.sh` 4.9 秒。kubelet の再起動 10:25:00Z

## 3. 確認（10:25:55Z）

| # | 確認 | 結果 |
|---|---|---|
| 1、2 | Node、バイナリ | v1.34.12。`kubelet-v1.34.12`、`kubectl-v1.34.12`、`crictl-v1.34.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` のまま |
| 3 | iscsid | 6334 のまま |
| 4 | iSCSI のセッション | sid 3〜7、同じ portal・target |
| 5 | エンジン | 5 つとも同じボリューム、同じ起動の時刻 |
| 6 | Longhorn | 5 つとも attached healthy のまま、instance-manager は同じ。カーネルの I/O エラーなし |
| 7 | Pod の再起動 | **差分なし**（39 個） |
| 10 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。oeilvert の cnidaria の error 0（段 4 と同じ） |
| 11 | kubelet のログ | 起動のときのものと、cadvisor の `Partial failure issuing cadvisor.ContainerInfoV2`（1 回）、`Failed to trigger a manual run`（Readiness、info、8 回。起動の直後 9 秒の間） |
| 12 | 監視の FAIL | 0 |
| 14 | 告知していた LoadBalancer | 下の注 |
| 13、15 | ほか | 再起動なし、CSR なし |

- **gated-v6 の告知**: 10:25:05Z に、oeilvert の speaker が `::200` を `serviceWithdrawn`（`notOwner`）→ `serviceAnnounced`、chirico の speaker が `serviceAnnounced` → `serviceWithdrawn`（`notOwner`）を同じ秒の中で出した（speaker ごとのログの順で読んだ。ETP Local の Service で、oeilvert の kubelet の再起動の直後に起きた）。最後は oeilvert のまま。`[...:ace::200]` の 80 は 404（応答あり）。同じころ `::132`（.111）と `::134`（.112）が 10:25:03Z に `notOwner` で withdraw し、10:25:09Z に同じノードで announce し直した（段 4 の oeilvert と同じ形）。監視（v4 の LB）の FAIL は無い

## 4. 次の 1 台へ進む条件

すべて合格。

## 5. 手順書との差、気づいたこと

- なし（告知の一時的な揺れは段 4 にもあった。runbook §8 の範囲）
