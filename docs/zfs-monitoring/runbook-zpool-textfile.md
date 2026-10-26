# braque の zpool status を node-exporter の textfile に書く手順書

braque（192.168.1.131、NFS サーバー）の ZFS プール `tank1` について、vdev ごとの READ / WRITE / CKSUM のエラー数と scrub の結果を Prometheus から見えるようにする。
node-exporter の zfs collector は `/proc/spl/kstat/zfs` しか読まず、これらの値はそこに無い（`zpool status` でしか分からない）。そこで、ホストの systemd timer が 5 分ごとに `zpool status -P -p` を読み、node-exporter の textfile collector のディレクトリ `/var/lib/node-exporter`（Pod の中では `/srv/txt_collector`）に `zpool.prom` を書く。

アラートのルールは fleet-infra の `infrastructure/kube-prometheus/` にある。この手順書はメトリクスを出す側だけを扱う。

## 1. ファイル

| リポジトリの中 | braque の置き場所 | 内容 |
|---|---|---|
| `tools/zpool-textfile.sh` | `/usr/local/sbin/zpool-textfile.sh`（root、0755） | `zpool status -P -p` を読んで `zpool.prom` を書く。一時ファイルに書いてから rename する。依存は bash、gawk、coreutils の `date`、zfsutils だけ |
| `tools/zpool-textfile.service` | `/etc/systemd/system/` | root で 1 回だけ動く（oneshot）。書けるのは `/var/lib/node-exporter` だけにしてある |
| `tools/zpool-textfile.timer` | `/etc/systemd/system/` | 5 分ごと（`OnCalendar=*:0/5`、`Persistent=true`、30 秒以内のずらし） |
| `tools/test/` | — | bats のテストと、`zpool status` の出力例（fixtures） |

ホストの zfsutils をそのまま使うので、OS の更新で zfsutils と zfs-kmod の版が上がっても版のずれは起きない。ただし `zpool status` の表示の形が変わると読めなくなる（§6）。

## 2. メトリクス

すべて gauge。名前とラベルは、ルールを書く側（fleet-infra）との取り決めで決めたもので、変えるときは両方を同時に直す。

| メトリクス | ラベル | 値 |
|---|---|---|
| `zpool_textfile_last_run_timestamp_seconds` | なし | 最後に書いた時刻（Unix 時刻） |
| `zpool_vdev_state` | `zpool`、`vdev`、`state` | その行の STATE を小文字で `state` に入れて 1。`vdev` は `zpool status -P` の名前で、プール自身・raidz・葉のディスクの各行がある |
| `zpool_vdev_errors` | `zpool`、`vdev`、`type` | READ / WRITE / CKSUM の数。`type` は `read` / `write` / `checksum` |
| `zpool_scrub_in_progress` | `zpool` | scrub が進行中か一時停止中なら 1、それ以外は 0 |
| `zpool_scrub_last_end_timestamp_seconds` | `zpool` | 最後に完了した scrub の終了時刻 |
| `zpool_scrub_last_repaired_bytes` | `zpool` | その scrub で修復した量（バイト） |
| `zpool_scrub_last_errors` | `zpool` | その scrub で見つかったエラーの数 |
| `zpool_data_errors` | `zpool` | `errors:` の行の件数（`No known data errors` なら 0） |

振る舞いの細部:

- **scrub の進行中（一時停止を含む）は、前回の scrub の結果（`_last_*` の 3 つ）が出ない。** `zpool status` が前回の結果を表示しないため。braque の scrub は約 8 時間かかるので、毎月第 2 日曜の 00:24Z（`/etc/cron.d/zfsutils-linux`）から 8 時間ほど欠ける。resilver の完了が表示されているとき、scrub が取り消されたとき、一度も scan していないときも出ない
- 修復量は `zpool status` の表示（`1.50M` など、1024 進の丸めた値）から換算するので、正確なバイト数ではない
- 終了時刻は表示されたローカル時刻を `date -d` で読む。braque のホストの時刻は UTC
- **`zpool status` が失敗したら、ファイルを書き換えずに失敗で終わる。** `zpool_textfile_last_run_timestamp_seconds` が古くなることで気づける
- プールが 1 つも無い（取り込まれていない）ときは、`zpool_textfile_last_run_timestamp_seconds` だけを書く
- logs / cache / spares の行も `zpool_vdev_state` に出る。spares の行（`AVAIL` など）はエラー数の列が無いので `zpool_vdev_errors` は出ない

## 3. テスト

作業端末で次を実行する。fixtures は ONLINE（braque の実際の出力）、DEGRADED（FAULTED と UNAVAIL を含む）、scrub の進行中、一時停止、エラーありの scrub、複数のプール（logs / cache / spares、resilver の完了、scan なし）、プールなし。

```
bats docs/zfs-monitoring/tools/test
```

braque の実際の値で確かめるには、環境変数 `ZPOOL` に「ssh で braque の `zpool` を呼ぶ」小さなスクリプトを渡し、出力先を手元のファイルにして `zpool-textfile.sh` を動かす（braque では `zpool status` を読むだけ）。

## 4. 導入

braque への変更なので、ユーザーの承認を得てから行う。作業端末（このリポジトリの checkout）から実行する。

1. 3 つのファイルを braque に送る。
   ```
   ssh yuanying@192.168.1.131 'mkdir -p ~/zpool-textfile'
   scp docs/zfs-monitoring/tools/zpool-textfile.{sh,service,timer} yuanying@192.168.1.131:zpool-textfile/
   ```
2. 置いて、1 回動かしてから timer を有効にする。
   ```
   ssh yuanying@192.168.1.131 'cd ~/zpool-textfile &&
     sudo install -o root -g root -m 0755 zpool-textfile.sh /usr/local/sbin/zpool-textfile.sh &&
     sudo install -o root -g root -m 0644 zpool-textfile.service zpool-textfile.timer /etc/systemd/system/ &&
     sudo systemctl daemon-reload &&
     sudo systemctl start zpool-textfile.service &&
     sudo systemctl enable --now zpool-textfile.timer'
   ```
3. 送ったファイルを消す（`rm -r ~/zpool-textfile`）。

## 5. 確認

1. braque で:
   - `systemctl status zpool-textfile.service` が `status=0/SUCCESS` で終わっている
   - `systemctl list-timers zpool-textfile.timer` に次の実行の時刻がある
   - `/var/lib/node-exporter/zpool.prom` が root、0644 で、中身が §2 の形
2. Prometheus で（`fraction-auditor` の kubeconfig。API server の service proxy `kubectl get --raw '/api/v1/namespaces/monitoring/services/http:kube-prometheus-prometheus:9090/proxy/api/v1/query?query=...'`）:
   - `zpool_vdev_state{instance="192.168.1.131:9100"}` が 5 系列（`tank1`、`raidz1-0`、ディスク 3 台）、すべて `state="online"`
   - `zpool_vdev_errors` が 15 系列ですべて 0、`zpool_data_errors` が 0
   - `zpool_scrub_last_end_timestamp_seconds{zpool="tank1"}` が最後の scrub の終了時刻
   - `time() - zpool_textfile_last_run_timestamp_seconds` が 300 秒前後より小さい
   - `node_textfile_scrape_error{instance="192.168.1.131:9100"}` が 0

## 6. 壊れたとき・戻し方

- **`zpool.prom` が古くなった**: `systemctl status zpool-textfile.service` と `journalctl -u zpool-textfile.service` を見る。`zpool status` の失敗なら、ファイルは前回のまま残る
- **OS の更新で `zpool status` の表示が変わった**: 新しい出力を fixtures に足し、テストを直してからスクリプトを置き直す
- **やめる**:
  ```
  ssh yuanying@192.168.1.131 'sudo systemctl disable --now zpool-textfile.timer &&
    sudo rm /etc/systemd/system/zpool-textfile.service /etc/systemd/system/zpool-textfile.timer &&
    sudo systemctl daemon-reload &&
    sudo rm /usr/local/sbin/zpool-textfile.sh /var/lib/node-exporter/zpool.prom'
  ```
  `zpool.prom` を消すと、次の scrape から `zpool_*` が消える。ルール側に「メトリクスが無い」で鳴るものがあれば鳴る

## 7. 古い `zfs.prom` の削除

`/var/lib/node-exporter/zfs.prom`（2023-04-08 の、go_* などの別の exporter の出力のダンプ。ZFS の情報ではない）が textfile collector のディレクトリに残っていて紛らわしいので消す。braque への変更なので、ユーザーの承認を得てから行う。

1. 退避してから消す。
   ```
   ssh yuanying@192.168.1.131 'sudo cp -p /var/lib/node-exporter/zfs.prom /root/zfs.prom.bak-YYYYMMDD &&
     sudo rm /var/lib/node-exporter/zfs.prom'
   ```
2. 確かめる: `node_textfile_mtime_seconds{instance="192.168.1.131:9100"}` に `zfs.prom` の系列が無く、`node_textfile_scrape_error` が 0。
3. 戻すときは、退避したものを `/var/lib/node-exporter/zfs.prom` に戻す（`sudo cp -p`）。

## 8. やらないこと

- **zed の通知（メール、Slack）は設定しない。** プールの状態は node-exporter の `node_zfs_zpool_state`、vdev のエラーと scrub の結果はこの textfile で Prometheus から取れ、Alertmanager から通知されるため。zed の Slack 通知は webhook の秘密をホストに置くことにもなる
