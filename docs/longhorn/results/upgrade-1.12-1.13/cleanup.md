# Longhorn 1.13.0 の更新の後片付け（本番 `fraction`）

`../../runbook-upgrade-1.12-1.13.md`（以下 手順書）§11 のうち、2026-10-21 にユーザーが決めた 2 つ（§4.5 のスナップショットとバックアップの削除、ノードの containerd に残った古い Longhorn のイメージの片付け）と、途中で足した 1 つ（空になった BackupVolume の削除）を、本番 `fraction`（K8s v1.34.12、Longhorn v1.13.0）で流した記録。時刻は UTC。

- 承認（2026-10-21 ユーザー）: §4.5 の `lh1121-pre-*`・`lh1130-pre-*` のスナップショット、それらのバックアップ、SystemBackup `lh1121-pre`・`lh1130-pre` を消す。`homegallery/cg-data` は残す。古い Longhorn のイメージを片付ける。途中で、案 A（下の §1.3）と BackupVolume 17 個の削除をユーザーが承認した
- 消す前に読み取りで対象の一覧を作り、coordinator が範囲を確かめてから消した。消す操作は、実行の直前に coordinator へ知らせた
- admin の操作は `infra-admin` の短命トークン（3h）で行った（03:49 に発行、06:01 に発行し直し、06:08 にファイルを消した）。ほかの読み取りは `fraction-auditor`。ノードと braque への SSH はサンドボックスの中で通った
- 一覧・スクリプト・ログ（`targets.md`、`images-plan.tsv`、`delete.log`、`snap-delete.log`、`images.log`、`before/`・`after/`・`state-before/`・`state-after/`、`run-<ノード>/`）は、タスクディレクトリの `notes/longhorn-cleanup/` にある

## 0. 結果

- Snapshot `lh1121-pre-*` 16 個は消えた。`lh1130-pre-*` は 3 個が消え、13 個は `markRemoved: true` の Terminating で残った（§1.3。Longhorn が volume-head の親のスナップショットを畳まないため。ユーザーの判断で許した）
- Backup 32 個、SystemBackup 2 個、BackupVolume 17 個を消した。braque の `/export/backups/longhorn` は **246G → 1.0K**（`backupstore/` の空のディレクトリだけ）、`/export` の空きは 9.1T → 9.4T
- 古い Longhorn のイメージを 4 台で 299 個消し、`/` の空きが合わせて約 87 GiB 増えた（§2）
- ボリュームは前後とも attached healthy 16、detached 1（`homegallery/cg-data`）。degraded・faulted は一度も出ていない。非 Running の Pod は 0
- 想定外が 1 つあった: 別の作業（natsumi の更新）で natsumi の 3 本のボリュームが rebuild され、Longhorn が自分でシステムのスナップショットを畳んだ。残すはずだった `natsumi-myao` の `ad19d7cf-…` がそこで消えた（§1.4）。coordinator の判断で記録して続けた

## 1. スナップショット・バックアップ・SystemBackup・BackupVolume

### 1.1 事前の読み取り（03:47）

- Snapshot は 52 個: `lh1121-pre-*` 16、`lh1130-pre-*` 16（attached の 16 本。名前の 8 桁とボリュームの UUID の先頭 8 桁は全部一致）、ほかに Longhorn が作ったもの 20（17 が `markRemoved: true`。markRemoved でないのは `natsumi-myao` の `ad19d7cf-…` と、消えたボリューム `pvc-33c6c783`・`pvc-fc47f155` の `6f58e0f0-…`・`0757189a-…`）
- Backup は 32 個で、どれも `lh1121-pre-*`・`lh1130-pre-*`（Completed）。RecurringJob は 0 で、ほかのバックアップは無い
- SystemBackup は `lh1121-pre`（v1.11.2）・`lh1130-pre`（v1.12.1）の 2 個
- BackupVolume は 17 個（16 個と、2022 年の `pvc-fc47f155`）
- 設定 `auto-cleanup-when-delete-backup` は false（Backup を消してもスナップショットは消えない）、`auto-cleanup-system-generated-snapshot` は true

### 1.2 Backup と SystemBackup（03:50〜03:57）

```sh
kubectl-admin -n longhorn-system delete backups.longhorn.io <名前>...         # 4 個ずつ、NotFound になるまで待つ
kubectl-admin -n longhorn-system delete systembackups.longhorn.io lh1121-pre
kubectl-admin -n longhorn-system delete systembackups.longhorn.io lh1130-pre
```

- 1 本目の `lh1121-pre-29c27b73`（03:50:21 → 03:50:34 NotFound）で、置き場の `backup_lh1121-pre-29c27b73.cfg` が消えることを確かめてから、残りの `lh1121-pre-*` 15（03:50:47〜03:52:32）、`lh1130-pre-*` 14（03:52:38〜03:54:34）、大きい 2 本 `fs/data`・`fs/h2` の `lh1130-pre-*` を 1 本ずつ（03:54:41〜03:55:33）。1 回 4 本で 20〜30 秒
- SystemBackup は 1 つ 3〜4 秒（03:57:42〜03:57:49）。置き場の `system-backups/` はディレクトリごと消えた
- Backup の CR は数十秒で消えるが、置き場のブロックの削除は後から続く。04:19 の `du` は 197G で、大きい 4 本（`fs/h2`、`fs/data`、Prometheus の 2 本）のディレクトリに lock と `blocks/` が残っていた（Prometheus-0 の block のファイルは 04:22 に 1407、04:23 に 974）。06:01 には lock も `blocks/` も無く、`volume.cfg` だけが残った
- この間、ボリュームはどれも healthy のまま

### 1.3 Snapshot（03:58〜06:06）

```sh
kubectl-admin -n longhorn-system delete snapshots.longhorn.io lh1121-pre-<8 桁> lh1130-pre-<8 桁>   # 1 本のボリュームずつ
```

1 本ずつ、消す前にボリュームが healthy・replica が全部 running・エンジンの `rebuildStatus` が空であること（§1.4 の後に足した）、消した後に `lh1121-pre-*` が NotFound・エンジンの `purgeStatus` が全 replica で `complete`・`lh1130-pre-*` が markRemoved か NotFound、を待った（`notes/longhorn-cleanup/snap-del.sh`）。毎回、残すスナップショットが残っていること、どのボリュームも degraded・faulted でないことも見た。

- 1 本目の `data-calendar-keeper-0`（03:58:02）で、purge は 2 つの replica とも `complete`、`lh1121-pre-29c27b73` と、その間の markRemoved の `6cad62cb-…` は畳まれて CR も消えた。**`lh1130-pre-29c27b73` は子が volume-head なので畳めず、CR が `deletionTimestamp` と finalizer `longhorn.io` を持ったまま残った**（`markRemoved: true`、size 57 MB。15 分変わらない）。Longhorn は最後のスナップショットを volume-head へ畳まない。次にそのボリュームでスナップショットが作られて purge されたとき（rebuild など）に消える
- ここで止めて coordinator に報告し、ユーザーが案 A（残りも同じに消し、`lh1130-pre-*` が Terminating で残るのを許す）を選んだ。ほかの案は、`lh1121-pre-*` だけ消して `lh1130-pre-*` を残す（B）、新しいスナップショットを作って purge させる（C）
- 残りの 15 本は 06:01〜06:06。小さいもの 1 本 5〜11 秒、Prometheus-0 は 81 秒、Prometheus-1 は 29 秒、`fs/data`・`fs/h2` は 6 秒（purge の量は子の大きさで決まる。`fs/h2` の `lh1130-pre` の子は volume-head）

後の状態（06:07。`after/snapshots.tsv`）:

| 区分 | 数 | 中身 |
|---|---|---|
| `lh1130-pre-*` で Terminating（markRemoved、子が volume-head） | 13 | natsumi の 3 本以外の 13 本。size は前の鎖を畳んだもの（`fs/h2` 174 GB、`fs/data` 64 GB、Prometheus 20 GB ずつなど） |
| Longhorn が作った markRemoved のもの | 4 | natsumi の 3 本の新しいシステムのスナップショット（`fcd2d215-…`、`6d653656-…`、`2dc738ed-…`。§1.4）と `cg-data` の `dd6be854-…`（detached なので触っていない） |
| 残すもの（markRemoved でない） | 2 | `6f58e0f0-…`（`pvc-33c6c783`）、`0757189a-…`（`pvc-fc47f155`）。どちらも消えたボリュームのもの |

- natsumi の 3 本（`natsumi-myao`、`natsumi`、`natsumi-aki`）は、`lh1130-pre-*` の後ろにシステムのスナップショットがあったので、`lh1130-pre-*` も畳まれて CR が消えた
- 前の markRemoved のシステムのスナップショット 17 個のうち、`cg-data` の 1 個を除く 16 個は、purge で畳まれて CR が消えた（natsumi の 3 本の 3 個は §1.4 の rebuild のときに先に畳まれた）。coordinator の判断（Longhorn が消すと決めたものの後始末）のとおり

### 1.4 natsumi の rebuild（別の作業、05:34ごろ）

06:01 の再開の直後に、残すはずの `natsumi-myao` の `ad19d7cf-…` が無いことに気づいて止めた。調べると、06:01 の再開の前（03:58 の 1 本目の後）にすでに消えていた。

- 05:34 ごろ、natsumi の 3 つの Pod（`natsumi-0`、`natsumi-aki-0`、`natsumi-myao-0`）が作り直されて duchamp に移った（その直前に `natsumi-backup-*-before-v0152` の Job が動いた。natsumi の v0.15.2 の更新とみられる。この作業では触っていない）
- data locality（best-effort）で、3 本のボリュームの replica が duchamp に rebuild された（`natsumi-myao` では 05:34:58 に `-r-18b9d850` を作って rebuild し、chirico の古い replica を外した）。rebuild のときに Longhorn がシステムのスナップショットを作り、`auto-cleanup-system-generated-snapshot` で畳んだ
- `natsumi-myao` では、markRemoved の `81d4eca3-…` と markRemoved でない `ad19d7cf-…`（Longhorn が作ったもの、`userCreated: false`）が `lh1121-pre-3a665d04` に畳まれ（size 66 MB → 533 MB）、`lh1130-pre-3a665d04` の後ろに markRemoved の `fcd2d215-…` ができた。`natsumi`・`natsumi-aki` もシステムのスナップショットの名前が変わった（`4e61e752-…` → `6d653656-…`、`80812b3a-…` → `2dc738ed-…`）
- coordinator の判断で、`ad19d7cf-…` は Longhorn が自分で畳んだシステムのスナップショットとして記録し、残す対象を 2 つにして続けた。あわせて、各ボリュームを消す前に rebuild が進んでいないことを確かめる形にした（§1.3）。natsumi の 3 本は rebuild が終わっていた

### 1.5 BackupVolume（06:07〜06:08）

- 消す前に、Backup の CR が 0、braque の置き場の 17 のディレクトリがどれも `volume.cfg` だけで `backups/` が 0 であることを確かめた（`after/backupstore-before-bv-delete.txt`）
- `kubectl-admin -n longhorn-system delete backupvolumes.longhorn.io <名前>...` を 4 個ずつ。1 回 3〜4 秒で NotFound（06:07:51〜06:08:10）
- 置き場の `backupstore/volumes/` はディレクトリごと消え、`backupstore/` は空になった。`/export/backups/longhorn` の中のファイルは 0
- BackupTarget `default` は `nfs://192.168.1.131:/backups/longhorn`、`available: true` のまま

## 2. 古い Longhorn のイメージ（04:14〜04:18）

対象は `longhornio/*` だけ。v1.13.0 の manifest（fleet-infra の `353875c` を render したもの）にあるイメージ（ノードにある 11）と、そのノードのコンテナ（`crictl ps -a` の imageRef）が参照するものを残し、それ以外を消した。各ノードで消す直前に images と `ps -a` を読み直して判定し直し（`notes/longhorn-cleanup/rmi-node.sh`。判定は 03:47 の一覧と同じだった）、`sudo crictl rmi <image id>` で 1 つずつ消した。`crictl rmi --prune` は使っていない。Longhorn 以外のタグを持つイメージは対象に無かった。

- EngineImage の CR は `ei-2f3240cb`（v1.13.0）の 1 つだけ。設定のイメージ（`default-engine-image` など）も v1.13.0（support-bundle-kit は v0.0.98）
- 残した使用中の古いもの: pablo・chirico・oeilvert の `longhorn-instance-manager:v1.11.2`（エンジンの残る v1.11.2 の instance-manager。`1.13.0.md` §8.2）、chirico の `longhorn-share-manager:v1.11.2`（作り直されていない share-manager の Pod 2 つ）
- 消したもの: engine・manager・ui・share-manager・instance-manager の v1.2.4〜v1.12.1、`v1_2022xxxx` の instance-manager・share-manager、CSI のサイドカーの古い版（`-2025xxxx`・`-20260428` を含む）と 1.12.1 の CSI のサイドカー

| ノード | 時刻 | 消した数 | crictl の size の合計 | 残り | `/` の空き（前 → 後） |
|---|---|---|---|---|---|
| oeilvert | 04:14:16〜04:14:28 | 19 | 1.78 GB | 12 | 87.1 GiB → 92.4 GiB |
| pablo | 04:14:33〜04:15:47 | 87 | 8.66 GB | 12 | 123.5 GiB → 149.4 GiB |
| duchamp | 04:15:51〜04:17:14 | 100 | 9.68 GB | 11 | 102.9 GiB → 131.9 GiB |
| chirico | 04:17:33〜04:18:43 | 93 | 8.80 GB | 13 | 304.1 GiB → 329.7 GiB |

- duchamp の 1 つ（`longhorn-instance-manager:v1.9.2`）は `crictl rmi` が `DeadlineExceeded` で失敗と出たが、後の一覧には無く、消えていた
- 1 台ごとに、Longhorn のボリューム（attached healthy 16・detached 1）と、クラスタ全体の非 Running の Pod（0）が変わらないことを見た

## 3. 後の確認（06:08）

| # | 確認 | 結果 |
|---|---|---|
| 1 | ボリューム | attached healthy 16、detached unknown 1（`cg-data`）。エンジンは 17 本とも v1.13.0。`lh-state.sh` の前（03:49）と後の差は、natsumi の 3 本のアタッチ先が duchamp に移ったことだけ（§1.4） |
| 2 | replica | running 30、stopped 2（`cg-data` の 2 つ）。前と同じ |
| 3 | instance-manager | v1.11.2 が 3、v1.13.0 が 4。どれも running で、前と同じ |
| 4 | engine image | v1.13.0 だけ（deployed、refcount 66） |
| 5 | Pod | クラスタ全体で Running / Completed 以外 0 |
| 6 | Longhorn のほかのもの | Backup 0、SystemBackup 0、BackupVolume 0、orphan 0、backing image 0。CRD 28 個とも `v1beta2`。NetworkPolicy 6、selector に `region` 0 |
| 7 | braque | `/export/backups/longhorn` は 1.0K（前 246G）、`/export` の空き 9.4T |
| 8 | ノードの空き | §2 の表 |

- 作業端末の `lh-watch.sh` を 03:49 に流したが、すぐに止まっていて、初めの状態しか取れていない。代わりに、削除のスクリプトが 3〜5 秒ごとに全ボリュームの robustness を読み、degraded・faulted が出たら止まる形で見た（一度も出ていない）

## 4. 手順書との差・申し送り

- 手順書 §4.5 の「スナップショットを消してもバックアップは消えない」に加えて、**最後のスナップショット（子が volume-head）は CR を消しても畳まれず、Terminating で残る**。消したいスナップショットの後ろにシステムのスナップショットがあれば畳まれる。次の更新で同じ形でバックアップを取るなら、後片付けではこれが起きる
- Backup の CR は数十秒で消えるが、置き場のブロックの削除は 1〜2 時間続く（`fs/h2` の約 9 万ブロック）。`du` はその後で取る
- 残った Terminating の `lh1130-pre-*` 13 個は、そのボリュームで次に rebuild などでスナップショットが作られ purge されたときに消える見込み（確かめていない）
- 別の作業（natsumi の更新）の Pod の移動で rebuild が起き、システムのスナップショットが畳まれた。本番の Longhorn の後片付けをするときは、その間のほかの作業を確かめる
