# braque への zpool textfile の導入（本番 `fraction`、2026-10-26）

braque（192.168.1.131）に `zpool status` を node-exporter の textfile に書く systemd timer を置き、古い `zfs.prom` を消した記録。
手順の正は `runbook-zpool-textfile.md`。この記録は実際に行ったことと、その結果。

## 1. 導入前の読み取り（01:41Z）

- `/usr/local/sbin/zpool-textfile.sh`、`/etc/systemd/system/zpool-textfile.*`、`~/zpool-textfile` は無かった。timer も無かった
- `/var/lib/node-exporter/` には `smart.prom`（smartmon が書く）と `zfs.prom`（2023-04-08、6948 バイト）だけがあった
- `/root/zfs.prom.bak-20261026` は無かった

## 2. 導入（01:42Z、手順書 §4）

手順書 §4 のとおりに 3 つのファイルを送って置き、`zpool-textfile.service` を 1 回動かしてから `zpool-textfile.timer` を enable --now した。送ったファイルは消した。

置いたファイルの sha256 はリポジトリのもの（このコミットの `tools/`）と一致した。

| ファイル | sha256 |
|---|---|
| `/usr/local/sbin/zpool-textfile.sh` | `cd2c0302f49e761f14a878048ad8138ab07c7d231b0afc2d09c30afbda0c6b40` |
| `/etc/systemd/system/zpool-textfile.service` | `49cd1099b8ca4b92bb252f84fab9e2739efc9109ec5267a9b8b0a9b709ece3d8` |
| `/etc/systemd/system/zpool-textfile.timer` | `df35f9a8d83a00b0840cf7059f28a68046922fb2e34b914a47c4db102de15e50` |

## 3. 古い `zfs.prom` の削除（01:42Z、手順書 §7）

`/var/lib/node-exporter/zfs.prom` を `/root/zfs.prom.bak-20261026`（root、0644、mtime 2023-04-08 のまま）に `cp -p` してから消した。

## 4. 確認（01:42Z〜01:46Z、手順書 §5）

braque で:

- 01:42:08Z の手動の実行と、01:45:27Z の timer からの実行が、どちらも `Deactivated successfully` で終わった。次の実行は 01:50:28Z
- `/var/lib/node-exporter/zpool.prom` は root、0644、2914 バイト。中身は手順書 §2 の形

Prometheus で（`fraction-auditor`、service proxy 経由）:

| クエリ | 結果 |
|---|---|
| `zpool_vdev_state{instance="192.168.1.131:9100"}` | 5 系列（`tank1`、`raidz1-0`、`/dev/disk/by-partlabel/zfs-tank1-{0,1,2}`）、すべて `state="online"` |
| `count(zpool_vdev_errors{instance="192.168.1.131:9100"})` / `sum(...)` | 15 / 0 |
| `zpool_data_errors` | `tank1` が 0 |
| `zpool_scrub_in_progress` | `tank1` が 0 |
| `zpool_scrub_last_end_timestamp_seconds` | `1791706351`（2026-10-11 08:12:31Z） |
| `zpool_scrub_last_repaired_bytes` / `zpool_scrub_last_errors` | 0 / 0 |
| `time() - zpool_textfile_last_run_timestamp_seconds` | 32 秒（01:45:58Z） |
| `node_textfile_scrape_error{instance="192.168.1.131:9100"}` | 0 |
| `node_textfile_mtime_seconds{instance="192.168.1.131:9100"}` | `smart.prom` と `zpool.prom` の 2 系列。`zfs.prom` は無い |

## 5. 戻し方

- 導入を戻す: 手順書 §6 の「やめる」
- `zfs.prom` を戻す: `sudo cp -p /root/zfs.prom.bak-20261026 /var/lib/node-exporter/zfs.prom`
