# chirico の段 7 の作業記録

chirico（192.168.1.83）の kubelet を、porkadot 0.36.0 の `install kubelet --node` で v1.36.5 に上げた記録。手順は `../../runbook-stage-7.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 5 台目（最後）。前は `duchamp.md`。完了の確認は `summary.md`。読み取りの出力はタスクディレクトリの `notes/stage-7/chirico/`。項目の形は `pablo.md` と同じで、違うところだけを書く。

## 1. 事前の読み取り（2026-10-21 13:30:53Z）

| 項目 | 結果 |
|---|---|
| クラスタ | 8 台 Ready（chirico のほかは v1.36.5）。etcd 3/3 healthy。`/readyz` は `ok`。Running / Completed 以外の Pod は 0。Longhorn 16 + 1。告知ノードは `pablo.md` と同じ |
| 対象のノード | v1.35.9、`cgroup2fs`。`/opt/bin` は 1.35 の向き先、CNI は `v1.9.1`。iscsid 4447、10-19 09:17:30Z（needrestart はまだ。liblzma5 は 0.3。`baseline.md` §5）。セッション 9 つ（8 つが 10.244.8.216、1 つが 10.244.8.60。どちらも今の instance-manager）、エンジン 9 つ（03:03:49Z〜03:09:08Z 起動、`older-than-iscsid` 0）。アタッチされたボリュームは 9 本（`monitoring/prometheus-…-1`（replica 1）を含む）、どれも attached healthy。**§8.12 の Pod なし**（deep-researcher のバックアップの CronJob の次の実行は 21:00Z）。Pod 46 個（CoreDNS の 1 つ `-shdgn` を含む）。告知している LoadBalancer は gated-v4（192.168.1.200）。`apt-daily-upgrade.service` は inactive |

## 3. `install kubelet`

- 開始 13:31:11Z、終わり 13:31:31Z（20 秒）、rc 0。サンドボックスの中で流した
- `install-deps.sh` 6.6 秒、`install-pkgs.sh` 7.7 秒、`install.sh` 4.0 秒。apt は何も入れていない（`history.log` の最後は 10-21 06:21Z）。CNI の plugins は展開していない
- `install.sh` の `dns` の addon が `systemd-networkd` を 13:31:27Z に止めて起こし直した（13:31:28Z に `eno1`・`porka-dummy01`・`cni0`・veth が `Link UP`）
- kubelet の起動 13:31:31Z

## 4. 確認（13:32:21Z）

| # | 確認 | 結果 |
|---|---|---|
| 1、2 | Node、バイナリ | v1.36.5。`kubelet-v1.36.5`、`kubectl-v1.36.5`、`crictl-v1.36.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` のまま |
| 3 | iscsid | 4447、10-19 09:17:30Z のまま |
| 4 | iSCSI のセッション | 同じ 9 つ（sid・portal・target）。古いセッションは無い |
| 5 | エンジン | 同じ 9 つ、同じ起動の時刻。`older-than-iscsid` は 0 のまま |
| 6 | Longhorn | ボリューム（replica 1 の `prometheus-…-1` を含む）・instance-manager はベースラインと同じ。Longhorn の node 4 つとも Ready。カーネルの I/O エラーなし |
| 7 | Pod の再起動 | **差分なし**（46 個。CoreDNS、prometheus、`fs/h2` などを含む） |
| 10 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。chirico の error 15 → 16、`no route` 61 → 62。ほかの 7 台は増えていない |
| 11 | kubelet のログ | 起動の直後の `Error getting the current node from lister`、eviction manager の imagefs のほかに、13:31:31Z の `Unable to write event`（`node-exporter-8d9z6` の event）と `Error updating node status, will retry` が 1 回ずつ。どちらも `read tcp 192.168.1.83:…->192.168.1.101:6443: read: connection reset by peer` で、`systemd-networkd` の再起動で API への既存の接続が切れたもの。次の更新で通り、Node は Ready |
| 12 | 監視 | **LB の FAIL 1 回（13:31:28Z）**（§5）。VIP は途切れていない |
| 14 | 告知していた LoadBalancer | gated-v4（192.168.1.200）は chirico のまま（告知の移動なし）、404 を返す |
| 9、13、15 | ほか | leader election の再起動なし（`gated-system/gated` の 2 つも restartCount は同じ）、CSR なし |

## 5. 監視の FAIL と、その原因

| 時刻 | VIP / LB / etcd の health | 原因 |
|---|---|---|
| 13:31:28Z | LB（`http://192.168.1.200/`） | gated-v4 を告知している chirico の `systemd-networkd` の再起動（`install.sh` の `dns` の addon。13:31:27Z〜28Z）。1 サンプルだけで、次から通った |

runbook §2.1 の 16（gated の LoadBalancer の 1 回の途切れは許容する）に当たる。段 6 の本番では chirico の `install kubelet` の間に LB の FAIL は出ていない。

## 6. 次の 1 台へ進む条件

最後の 1 台。runbook §6 の完了の確認に進んだ（`summary.md`）。

## 7. 手順書との差、気づいたこと

- LB の告知ノードの `install kubelet` で、`systemd-networkd` の再起動の 1 秒ほどに当たると LB が 1 サンプル落ちる。runbook §2.1 の 16 で許容している形で、runbook は変えていない
