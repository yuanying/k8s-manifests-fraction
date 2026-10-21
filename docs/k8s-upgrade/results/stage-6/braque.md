# braque の段 6 の作業記録

braque（192.168.1.131）の kubelet を、porkadot 0.35.0 の `install kubelet --node` で v1.35.9 に上げた記録。手順は `../../runbook-stage-6.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 2 台目。前は `pablo.md`、次は `oeilvert.md`。読み取りの出力はタスクディレクトリの `notes/stage-6/braque/`。項目の形は `pablo.md` と同じで、違うところだけを書く。

## 1. 事前の読み取り（2026-10-21 07:09:43Z）

| 項目 | 結果 |
|---|---|
| クラスタ | 8 台 Ready（CP 3 台と pablo が v1.35.9、ほかは v1.34.12）。etcd 3/3 healthy。`/readyz` は `ok`。Running / Completed 以外の Pod は 0。Longhorn 16 + 1 |
| 時間帯（runbook §5.4） | 07:09Z（JST 16:09）。バックアップの CronJob の時間帯（`fs/sites-backup` 07:53Z、`fs/data-backup` 09:03Z、`fs/h2-backup` 05:44Z）の外。走っている Job は無い |
| 対象のノード | v1.34.12、`cgroup2fs`。`/opt/bin` は v1.34.12 の 3 つと 3.6.15 の 2 つ。CNI は `v1.9.1`。iscsid 271131、10-21 06:23:32Z（unattended-upgrades の needrestart。`baseline.md` §5）。セッション・ボリュームなし。§8.12 の Pod なし。Pod 5 個。告知している LoadBalancer なし。`nfsd/nfsd-vt5k2` は restartCount 2（ベースラインと同じ） |

## 3. `install kubelet`

- 開始 07:09:55Z、終わり 07:10:21Z（26 秒）、rc 0。サンドボックスの中で流した
- `install-deps.sh` 6.0 秒、`install-pkgs.sh` 12.5 秒、`install.sh` 4.6 秒。apt は何も入れていない。CNI の plugins は展開していない
- kubelet の再起動 07:10:21Z

## 4. 確認（07:11:11Z）

| # | 確認 | 結果 |
|---|---|---|
| 1、2 | Node、バイナリ | v1.35.9。`kubelet-v1.35.9`、`kubectl-v1.35.9`、`crictl-v1.35.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` のまま |
| 3 | iscsid | 271131 のまま |
| 4〜6 | iSCSI、エンジン、Longhorn | セッション・エンジンなし。Longhorn は 16 + 1 のまま |
| 7 | Pod の再起動 | **差分なし**（5 個。`nfsd-vt5k2` も同じ UID・restartCount 2） |
| 10 | cnidaria | 64 PASS、FAIL 0。braque の error 14 → 22、`no route` 43 → 51。ほかの 7 台の `no route` は 2 ずつ増えた |
| 11 | kubelet のログ | 起動のときのものだけ。07:10:16Z に `monitoring/node-exporter-bp7zj` の Readiness probe の失敗（`dial tcp 192.168.1.131:9100: connect: network is unreachable`）を event に書こうとして `connection reset by peer`。`dns` の addon が systemd-networkd を再起動した間の 1 回（runbook §8.1 と同じ時刻）で、続かない。node-exporter の restartCount は変わらない |
| 12 | 監視の FAIL | なし |
| 4〜6、9、13〜15 | ほか | pablo と同じ（Longhorn の node は Ready、再起動なし、CSR なし） |

braque の追加の確認: oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で中身が読める、braque は 2049 を listen している、`registry.fraction.jp/v2/` は 401（応答あり）。

## 5. 監視の FAIL と、その原因

なし。

## 6. 次の 1 台へ進む条件

すべて合格。

## 7. 手順書との差、気づいたこと

- なし
