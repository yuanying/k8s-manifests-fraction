# duchamp の段 6 の作業記録

duchamp（192.168.1.135）の kubelet を、porkadot 0.35.0 の `install kubelet --node` で v1.35.9 に上げた記録。手順は `../../runbook-stage-6.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 4 台目。前は `oeilvert.md`、次は `chirico.md`。読み取りの出力はタスクディレクトリの `notes/stage-6/duchamp/`。項目の形は `pablo.md` と同じで、違うところだけを書く。

## 1. 事前の読み取り（2026-10-21 07:13:37Z）

| 項目 | 結果 |
|---|---|
| クラスタ | 8 台 Ready（duchamp と chirico のほかは v1.35.9）。etcd 3/3 healthy。`/readyz` は `ok`。Running / Completed 以外の Pod は 0。Longhorn 16 + 1 |
| 対象のノード | v1.34.12、`cgroup2fs`。CNI は `v1.9.1`。iscsid 2695716、10-21 06:08:00Z（unattended-upgrades の needrestart。`baseline.md` §5。ベースラインから変わらない） |
| iSCSI のセッション | 4（sid 5〜8、どれも 10.244.5.186 = 今の instance-manager `-134f259c…`）。`older-than-iscsid` 4（iscsid の 06:08:00Z の再起動より前に起動したエンジン） |
| アタッチされたボリューム | `natsumi/natsumi`・`natsumi-aki`・`natsumi-myao`、`monitoring/prometheus-…-0`（replica 1。replica も duchamp）。どれも attached healthy |
| §8.12 の Pod | **6 つ当たった**（下） |
| ほか | Pod 28 個。告知している LoadBalancer は `::133`（`natsumi-sshd-myao`）。apt-daily-upgrade は inactive |

## 1.3 §8.12 の Pod の削除 ✋

Running の Pod（duchamp の `natsumi-0`・`natsumi-aki-0`・`natsumi-myao-0`）と同じ Longhorn の PVC（PV の `spec.csi.driver` は 3 つとも `driver.longhorn.io`）を使う Succeeded の Pod 6 つ。`baseline.md` §2 の表のとおり。coordinator に名前を知らせてから、`infra-admin` の 1 時間のトークン（07:14:00Z に発行、`auth can-i delete pods -n natsumi` は `yes`）で 07:14:01Z に消した（rc 0）。トークンのファイルは直後に消した。

| Pod | ノード | PVC |
|---|---|---|
| `natsumi/natsumi-backup-29875470-fm6xs` | oeilvert | `natsumi` |
| `natsumi/natsumi-backup-before-v0152-wg7pp` | oeilvert | `natsumi` |
| `natsumi/natsumi-backup-aki-29875470-p8nj6` | oeilvert | `natsumi-aki` |
| `natsumi/natsumi-backup-aki-before-v0152-kv7kg` | oeilvert | `natsumi-aki` |
| `natsumi/natsumi-backup-myao-29875470-cfrfk` | chirico | `natsumi-myao` |
| `natsumi/natsumi-backup-myao-before-v0152-rrg74` | chirico | `natsumi-myao` |

- Job（9 個）と CronJob には触っていない。消した後に同じ洗い出しを流し、duchamp の Running の Pod の PVC で当たるものは無くなった
- 消した Pod はどれも duchamp の上のものではないので、duchamp の Pod の控え（`pods-pre.tsv`）は変わらない

## 3. `install kubelet`

- 開始 07:14:21Z、終わり 07:14:44Z（23 秒）、rc 0。サンドボックスの中で流した
- `install-deps.sh` 5.6 秒、`install-pkgs.sh` 9.0 秒、`install.sh` 5.5 秒。apt は何も入れていない。CNI の plugins は展開していない
- kubelet の再起動 07:14:44Z

## 4. 確認（07:15:34Z）

| # | 確認 | 結果 |
|---|---|---|
| 1、2 | Node、バイナリ | v1.35.9。`kubelet-v1.35.9`、`kubectl-v1.35.9`、`crictl-v1.35.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` のまま |
| 3 | iscsid | 2695716 のまま |
| 4 | iSCSI のセッション | 同じ sid 5〜8、portal、target。古いセッションなし |
| 5 | エンジン | 同じ 4 本、同じ起動の時刻。`older-than-iscsid` 4 のまま |
| 6 | Longhorn | 4 本とも attached healthy のまま。ボリューム・instance-manager の一覧は前と同じ。カーネルの I/O エラーなし |
| 7 | Pod の再起動 | **差分なし**（28 個。natsumi の 3 つ、prometheus-…-0、CoreDNS の 1 つを含む） |
| 10 | cnidaria | 64 PASS、FAIL 0。duchamp の error 14 → 21、`no route` 45 → 52。ほかの 7 台の `no route` は 2 ずつ増えた |
| 11 | kubelet のログ | 起動のときの `node "duchamp" not found` と、`prober_manager.go` の `Failed to trigger a manual run`（Info、3 回、起動の直後）。続くエラーなし。**`FailedMount`（`no Pending workload pods`）の event は無い** |
| 14 | 告知していた LoadBalancer | `::133` は SSH のバナーを返す。告知は duchamp のまま |
| 12、13、15 | 監視の FAIL、leader election、CSR | なし |

## 5. 監視の FAIL と、その原因

なし。

## 6. 次の 1 台へ進む条件

すべて合格。

## 7. 手順書との差、気づいたこと

- `natsumi-backup-*-before-v0152` の 3 つは、CronJob から 10-21 05:33Z に手で作られた Job の Pod（natsumi の v0.15.2 への更新の前のバックアップと見ている）。runbook §8.12 の条件（Running の Pod と同じ Longhorn の PVC を使う Succeeded の Pod）に当たるので、CronJob の定時の Pod と同じに扱った
