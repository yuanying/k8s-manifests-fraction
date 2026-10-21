# duchamp の段 7 の作業記録

duchamp（192.168.1.135）の kubelet を、porkadot 0.36.0 の `install kubelet --node` で v1.36.5 に上げた記録。手順は `../../runbook-stage-7.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 4 台目。前は `oeilvert.md`、次は `chirico.md`。読み取りの出力はタスクディレクトリの `notes/stage-7/duchamp/`。項目の形は `pablo.md` と同じで、違うところだけを書く。

## 1. 事前の読み取り（2026-10-21 13:28:57Z）

| 項目 | 結果 |
|---|---|
| クラスタ | 8 台 Ready（chirico と duchamp のほかは v1.36.5）。etcd 3/3 healthy。`/readyz` は `ok`。Running / Completed 以外の Pod は 0。Longhorn 16 + 1。告知ノードは `pablo.md` と同じ |
| 対象のノード | v1.35.9、`cgroup2fs`。`/opt/bin` は 1.35 の向き先、CNI は `v1.9.1`。iscsid 2695716、10-21 06:08:00Z（ベースラインと同じ。needrestart は段 6 の前に済んでいる）。セッション 4 つ（sid 5〜8、10.244.5.186:3260 = 今の instance-manager）、エンジン 4 つ（03:03:49Z、05:34:50Z〜52Z 起動、4 つとも `older-than-iscsid`。段 6 の前から）。アタッチされたボリュームは `natsumi` の 3 つと `monitoring/prometheus-…-0`（replica 1）、どれも attached healthy。**§8.12 の Pod なし**（natsumi のバックアップの CronJob の次の実行は 20:30Z）。Pod 30 個（CoreDNS の 1 つ `-469lz` を含む）。告知している LoadBalancer は `::133`（`natsumi-sshd-myao`）。`apt-daily-upgrade.service` は inactive |

## 3. `install kubelet`

- 開始 13:29:16Z、終わり 13:29:41Z（25 秒）、rc 0。サンドボックスの中で流した
- `install-deps.sh` 7.3 秒、`install-pkgs.sh` 10.1 秒、`install.sh` 5.4 秒。apt は何も入れていない（`history.log` の最後は 10-21 06:07Z）。CNI の plugins は展開していない
- kubelet の起動 13:29:41Z

## 4. 確認（13:30:31Z）

| # | 確認 | 結果 |
|---|---|---|
| 1、2 | Node、バイナリ | v1.36.5。`kubelet-v1.36.5`、`kubectl-v1.36.5`、`crictl-v1.36.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` のまま |
| 3 | iscsid | 2695716、10-21 06:08:00Z のまま |
| 4 | iSCSI のセッション | 同じ 4 つ（sid・portal・target）。古いセッションは無い |
| 5 | エンジン | 同じ 4 つ、同じ起動の時刻。`older-than-iscsid` は 4 のまま |
| 6 | Longhorn | ボリューム（replica 1 の `prometheus-…-0` を含む）・instance-manager はベースラインと同じ。Longhorn の node 4 つとも Ready。カーネルの I/O エラーなし |
| 7 | Pod の再起動 | **差分なし**（30 個。CoreDNS、natsumi、prometheus を含む） |
| 10 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。duchamp の error 21 → 28、`no route` 64 → 71。ほかの 7 台の `no route` は 2 ずつ増えた |
| 11 | kubelet のログ | 起動の直後の `Error getting the current node from lister`、eviction manager の imagefs だけ |
| 12 | 監視 | FAIL は増えていない |
| 14 | 告知していた LoadBalancer | `::133` は SSH のバナーを返す。告知の移動なし |
| 9、13、15 | ほか | leader election の再起動なし、CSR なし |

## 5. 監視の FAIL と、その原因

なし。

## 6. 次の 1 台へ進む条件

すべて合格。

## 7. 手順書との差、気づいたこと

- なし
