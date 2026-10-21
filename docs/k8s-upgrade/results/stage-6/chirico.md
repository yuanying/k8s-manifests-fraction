# chirico の段 6 の作業記録

chirico（192.168.1.83）の kubelet を、porkadot 0.35.0 の `install kubelet --node` で v1.35.9 に上げた記録。手順は `../../runbook-stage-6.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 5 台目（最後）。前は `duchamp.md`。完了の確認は `summary.md`。読み取りの出力はタスクディレクトリの `notes/stage-6/chirico/`。項目の形は `pablo.md` と同じで、違うところだけを書く。

## 1. 事前の読み取り（2026-10-21 07:16:02Z）

| 項目 | 結果 |
|---|---|
| クラスタ | 8 台 Ready（chirico のほかは v1.35.9）。etcd 3/3 healthy。`/readyz` は `ok`。Running / Completed 以外の Pod は 0。Longhorn 16 + 1 |
| 対象のノード | v1.34.12、`cgroup2fs`。CNI は `v1.9.1`。iscsid 4447、10-19 09:17:30Z（今日の unattended-upgrades では liblzma5 が上がらず、再起動していない。`baseline.md` §5） |
| iSCSI のセッション | 9（8 つが 10.244.8.216 = instance-manager `-4128231c…`、1 つ（sid 16、`prometheus-…-1`）が 10.244.8.60 = `-ed03b277…`。どちらも今の instance-manager）。`older-than-iscsid` 0 |
| アタッチされたボリューム | 9（`homegallery/tumblr-data`・`ero-data`、`fs/data`・`fs/h2`、`monitoring/prometheus-…-1`（replica 1。replica も chirico）、`fraction-agents` の 4 つ）。どれも attached healthy |
| §8.12 の Pod | **1 つ当たった**（下） |
| ほか | Pod 47 個。告知している LoadBalancer は gated-v4（192.168.1.200）。apt-daily-upgrade は inactive |

## 1.3 §8.12 の Pod の削除 ✋

`fraction-agents/deep-researcher-backup-29875500-z8gc4`（chirico、Succeeded、CronJob `deep-researcher-backup` の 10-20 21:00Z の Job）。Running の `deep-researcher-0`（chirico）と同じ PVC `data-deep-researcher-0`（PV は `driver.longhorn.io`）を使う。coordinator に名前を知らせてから、`infra-admin` の 1 時間のトークン（07:16:23Z に発行）で 07:16:23Z に消した（rc 0）。トークンのファイルは直後に消した。Job と CronJob には触っていない。

消した Pod は chirico の上のものなので、Pod の控えを消した後に取り直し（`pods-pre2.tsv`。前のものは `pods-pre-before-delete.tsv`）、それを §4 の 7 の比べる元にした（差分は消した 1 つだけ。`node-state.sh` は前と同じ）。

## 3. `install kubelet`

- 開始 07:16:42Z、終わり 07:17:02Z（20 秒）、rc 0。サンドボックスの中で流した
- `install-deps.sh` 5.5 秒、`install-pkgs.sh` 7.1 秒、`install.sh` 4.6 秒。apt は何も入れていない。CNI の plugins は展開していない
- kubelet の再起動 07:17:02Z

## 4. 確認（07:17:52Z）

| # | 確認 | 結果 |
|---|---|---|
| 1、2 | Node、バイナリ | v1.35.9。`kubelet-v1.35.9`、`kubectl-v1.35.9`、`crictl-v1.35.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` のまま |
| 3 | iscsid | 4447 のまま |
| 4 | iSCSI のセッション | 同じ 9 つ（sid、portal、target）。古いセッションなし |
| 5 | エンジン | 同じ 9 本、同じ起動の時刻。`older-than-iscsid` 0 のまま |
| 6 | Longhorn | 9 本とも attached healthy のまま。ボリューム・instance-manager の一覧は前と同じ。カーネルの I/O エラーなし |
| 7 | Pod の再起動 | **差分なし**（46 個。アタッチされた 9 本を使う Pod、CoreDNS の 1 つ、gated の 1 つを含む） |
| 10 | cnidaria | 64 PASS、FAIL 0。chirico の error 8 → 15、`no route` 42 → 49。ほかの 7 台の `no route` は 2 ずつ増えた |
| 11 | kubelet のログ | 起動のときの `node "chirico" not found` だけ。`FailedMount` なし |
| 14 | 告知していた LoadBalancer | 192.168.1.200 の 80 は 404（応答あり）。告知は chirico のまま |
| 12、13、15 | 監視の FAIL、leader election、CSR | なし |

## 5. 監視の FAIL と、その原因

なし。

## 6. 次の 1 台へ進む条件

最後の 1 台。すべて合格。8 台すべてが v1.35.9 になった。

## 7. 手順書との差、気づいたこと

- なし
