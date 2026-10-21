# braque の段 7 の作業記録

braque（192.168.1.131）の kubelet を、porkadot 0.36.0 の `install kubelet --node` で v1.36.5 に上げた記録。手順は `../../runbook-stage-7.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 2 台目。前は `pablo.md`、次は `oeilvert.md`。読み取りの出力はタスクディレクトリの `notes/stage-7/braque/`。項目の形は `pablo.md` と同じで、違うところだけを書く。

## 1. 事前の読み取り（2026-10-21 13:24:34Z）

| 項目 | 結果 |
|---|---|
| クラスタ | 8 台 Ready（control-plane の 3 台と pablo が v1.36.5）。etcd 3/3 healthy。`/readyz` は `ok`。Running / Completed 以外の Pod は 0。Longhorn 16 + 1。告知ノードは `pablo.md` と同じ |
| 時間帯（runbook §5.4） | JST 22:24。バックアップの CronJob の時間帯（JST 05:15〜06:45、14:30〜15:00、16:45〜17:05、17:55〜18:15）の外 |
| 対象のノード | v1.35.9、`cgroup2fs`。`/opt/bin` は 1.35 の向き先、CNI は `v1.9.1`。iscsid 271131、10-21 06:23:32Z（ベースラインと同じ）。セッション・エンジン・ボリュームなし。§8.12 の Pod なし。Pod 5 個（`nfsd/nfsd-vt5k2` の restartCount 2 は前から）。告知している LoadBalancer なし。`apt-daily-upgrade.service` は inactive |

## 3. `install kubelet`

- 開始 13:24:52Z、終わり 13:25:26Z（34 秒）、rc 0。サンドボックスの中で流した
- `install-deps.sh` 10.0 秒、`install-pkgs.sh` 16.1 秒、`install.sh` 6.5 秒。apt は何も入れていない（`history.log` の最後は 10-21 06:23Z）。CNI の plugins は展開していない
- kubelet の起動 13:25:26Z

## 4. 確認（13:26:16Z）

| # | 確認 | 結果 |
|---|---|---|
| 1、2 | Node、バイナリ | v1.36.5。`kubelet-v1.36.5`、`kubectl-v1.36.5`、`crictl-v1.36.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` のまま |
| 3 | iscsid | 271131 のまま |
| 4〜6 | iSCSI、エンジン、Longhorn | セッション・エンジンなし。Longhorn はベースラインと同じ。カーネルの I/O エラーなし |
| 7 | Pod の再起動 | **差分なし**（nfsd の restartCount も 2 のまま） |
| 10 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。braque の error 22 → 27、`no route` 63 → 68。ほかの 7 台の `no route` は 2 ずつ増えた |
| 11 | kubelet のログ | 古い kubelet の `Failed to update lease`（13:25:24Z、`systemd-networkd` の再起動の間）、起動の直後の `Error getting the current node from lister`、`Image garbage collection failed once`（と Node の event の `InvalidDiskCapacity`）、checkpoint、eviction manager の imagefs。どれも前の段と同じ形（`results/stage-3/summary.md`） |
| 12 | 監視 | FAIL は増えていない |
| ほか | NFS、registry | oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で読める。braque は 2049 を listen。`registry.fraction.jp/v2/` は 401 |
| 9、13〜15 | ほか | 告知の移動なし、leader election の再起動なし、CSR なし |

## 5. 監視の FAIL と、その原因

なし。

## 6. 次の 1 台へ進む条件

すべて合格。

## 7. 手順書との差、気づいたこと

- なし
