# chirico に残る Longhorn の古い instance-manager と share-manager の片付け（本番 `fraction`）

`../runbook-old-instance-manager.md`（以下 手順書）を、本番 `fraction`（K8s v1.37.1、Longhorn v1.13.0）で流した記録。時刻は UTC。

- 承認（2026-10-26 08:02Z ユーザー）: 開始（手順書 §4.2 の ✋✋）。§9 の 3 つは、(1) homegallery の 2 本のバックアップは取らない、(2) 段 A が全部合格したら同じ日に段 B へ続けてよい、(3) NFS の頼り手（aphrael、comics、restore）は止めない
- 読み取りは `fraction-auditor`。`scale` は `infra-admin` の短命トークンで行う。ノードへの SSH はサンドボックスの中で通った
- 出力（`lh-state.sh` の前後、`node-*.txt`、`watch.log`、`probe.log`、`replicas-*.txt`、`pods-*.txt`、`trivy-*.txt`）は、タスクディレクトリの `notes/longhorn-old-im/` にある

## 1. 事前の確認（§4.1）

### 1.1 準備の読み取り（08:03〜08:05）

書き込みの時間帯（10:00Z から）の前に、手順書 §4.1 を一度流した（`notes/longhorn-old-im/baseline-0810/`）。11 項目とも §2 と同じだった。

| # | 確認 | 結果 |
|---|---|---|
| 2 | Longhorn の版 | `current-longhorn-version` v1.13.0、engine image は `ei-2f3240cb`（v1.13.0）だけが deployed |
| 3 | instance-manager | 5 つとも running。`instance-manager-4128231c…`（chirico、v1.11.2、10.244.8.216）の中のエンジンは 4 つのボリュームだけ |
| 4 | 4 つのボリューム | 4 つとも attached/healthy（chirico）、エンジンが `$OLD_IM`、replica は running 2 で `failedAt` なし、Replica の CR は 2 つずつ。Longhorn の VolumeAttachment の ticket は §2.2 のとおり |
| 5 | ほかのボリューム | attached/healthy 16、detached 1（`cg-data`）、replica running 30・stopped 2、Ready でない Pod 0 |
| 6 | share-manager | tumblr-data・ero-data は running（chirico）、`status.currentImage` v1.11.2、Pod は 2026-10-19T09:35Z の作成。cg-data は stopped |
| 7 | ワークロード | `replicas` は data 1、h2 1、tumblr-web 2、ero-web 2。PVC を使う Pod は data（chirico）、h2（chirico）、tumblr-web（chirico、duchamp）、ero-web（chirico、duchamp）だけ。restartCount 0 |
| 8 | NFS の頼り手 | aphrael 4（chirico 2、pablo、duchamp）、`comics-webdav`（chirico）、`*-restore` 3（duchamp）が Running。プローブ 8 つ（NFS・SSH・LB・service proxy）が全部 ok、`www.fraction.jp` 200 |
| 9 | iSCSI | iscsid の MainPID: chirico 3144486、duchamp 2695716、oeilvert 912599、pablo 4114921（§2.5 と同じ）。chirico は 10.244.8.216 に 4、10.244.8.60 に 1。どのノードも portal は今の instance-manager の IP だけ。chirico の 4 本のエンジンは `older-than-iscsid` |
| 10 | Pod | Running / Completed 以外 0。8 台 Ready（v1.37.1） |
| 11 | Trivy | `pod-767f7c764c`（instance-manager v1.11.2、C3/H95）、`pod-7596f8df9b`・`pod-6ccd6c447c`（share-manager v1.11.2、C1/H46） |

### 1.2 当日の読み直し（09:48）

`notes/longhorn-old-im/before/`、`node-before-*.txt`、`replicas-before.txt`、`pods-before.txt`、`trivy-before.txt`。1.1 と同じだった（iscsid の MainPID 4 台とも同じ、`lh-state.sh` の要約も同じ）。その日の `data-backup` は 09:03 に済み、`aphrael/tumblr-like` は 09:38 に済んで次は 12:38。09:48 に監視（§4.3 の 2 つ）を起動し、10:00:10 に `infra-admin` のトークン（2h）を発行した。

## 2. 段 A: `fs/data`（§4.4）

| 時刻 | できごと |
|---|---|
| 10:00:23 | ✋ `scale deploy/data --replicas=0` |
| 10:00:28 | Pod `data-66596b955b-wgs4w` が消えた |
| 10:00:36 | detaching |
| 10:00:38 | detached。エンジン stopped（`instanceManagerName` 空）、replica は stopped 2 で `failedAt` なし |
| 10:00:42 | `$OLD_IM` の中のエンジンが 3 つ（tumblr-data、ero-data、h2）に減った |
| 10:00:49 | ✋ `scale deploy/data --replicas=1` |
| 10:00:52〜55 | attaching → attached（chirico） |
| 10:01:00 | healthy |
| 10:01:01 | rollout 完了。Pod `data-66596b955b-vb98t`（chirico）、2/2 Running |

- **chirico の iSCSI**: detach の後、`pvc-1d94c3ed` のセッション（sid 4、10.244.8.216）と `/dev/longhorn/pvc-1d94c3ed-…` が消え、10.244.8.216 のセッションは 3 本になった。`dmesg` には ext4 の umount だけで、I/O エラーは無い。**iscsid の今の起動より前に起動した（`older-than-iscsid`）エンジンでも、logout は通った**（§2.5 の見立てのとおり。v1.13.0 のエンジンのバイナリの nsenter の直しが効いている）
- 戻した後: エンジンは `instance-manager-ed03b277…`（chirico、v1.13.0）。セッションは sid 20、portal 10.244.8.60（その instance-manager の IP）。iscsid の MainPID は 3144486 のまま。replica は chirico・duchamp の running 2
- Pod は前と同じ chirico に載った（イメージの pull は無い）
- `fs/data-restore` は Running、restartCount 0 のまま
- 止まっていた時間（`probe.log`）: `data`（NFS）は 10:00:27〜10:01:00 の `FAIL`（約 36 秒）、`data-ssh` は 10:00:24〜10:01:05（約 41 秒）。10:01:43 に SSH のバナーが返った。見込み（2〜5 分）よりずっと短い
- `watch.log`: degraded・faulted は出ていない

## 3. 段 B: `homegallery` と `fs/h2`（§4.5）

段 A の確かめが全部合格したので、続けて流した（§9 の 2）。10:02:03 の前の確認で、3 本とも attached/healthy、エンジンが `$OLD_IM`、share-manager は v1.11.2 のまま。次の `tumblr-like` は 12:38。

| 時刻 | できごと |
|---|---|
| 10:02:14 | ✋ `scale deploy/tumblr-web deploy/ero-web --replicas=0` |
| 10:02:46 | 4 つの Pod が消えた（32 秒。RollingUpdate の Pod の grace） |
| 10:02:56 | tumblr-data detached |
| 10:02:59 | ero-data detached。share-manager は 2 つとも `stopping` |
| 10:03:13 | share-manager が 2 つとも `stopped`、Pod が無い（`status.currentImage` は空になった） |
| 10:03:18 | ✋ `scale deploy/h2 --replicas=0` |
| 10:03:23 | Pod `h2-6cb59468bd-lpdks` が消えた |
| 10:03:32 | h2 detached |
| 10:03:35 | **古い instance-manager の Pod が Terminating**（中のエンジンが 0 になった） |
| 10:03:43 | ✋ `scale deploy/h2 --replicas=1` |
| 10:03:49〜54 | h2 attached（chirico）→ healthy |
| 10:03:55 | rollout 完了。Pod `h2-6cb59468bd-jlpb2`（chirico）。**`$OLD_IM` の CR と Pod が NotFound** |
| 10:04:17 | h2 の NFS・SSH・LB、aphrael の service proxy が答える |
| 10:04:24 | ✋ `scale deploy/tumblr-web deploy/ero-web --replicas=2`。share-manager の Pod が v1.13.0 で作られた |
| 10:04:33〜36 | ero-data・tumblr-data が attached/healthy（chirico） |
| 10:04:42 | rollout 完了。tumblr-web・ero-web は chirico と duchamp に 1 つずつ |

- detach の後の chirico の iSCSI（10:03:35）: 10.244.8.216 のセッションは 0。残ったのは 10.244.8.60 の 2 本（`prometheus-…-0` と、段 A で戻した `fs/data`）。`/dev/longhorn/` に 3 本が無い。I/O エラーは無い。iscsid の MainPID は同じ。**3 本とも `older-than-iscsid` のエンジンだったが、古いセッションは残らなかった**
- h2 の Pod は chirico（replica のあるノード）に載ったので、data locality の rebuild は起きなかった
- 古い instance-manager は、最後のエンジンが止まってから数秒で Longhorn が消した（§6 の「消えない」には当たらない）
- homegallery の `FailedMount` の event は無い
- 止まっていた時間（`probe.log`）:

  | もの | `FAIL` の始め〜終わり | 長さ |
  |---|---|---|
  | homegallery の tumblr・ero（service proxy） | 10:02:15〜10:04:40 | 約 2 分 25 秒 |
  | `h2`（NFS） | 10:03:23〜10:03:53 | 約 30 秒 |
  | `h2-ssh`・`h2-sshd-lb` | 10:03:21〜10:03:58 | 約 37 秒 |
  | aphrael の service proxy | 無し | — |

## 4. 後の確認（§4.6、10:05〜10:06）

`notes/longhorn-old-im/after/`、`state.diff`、`node-after-*.txt`、`pods-after.txt`。

| # | 確認 | 結果 |
|---|---|---|
| 1 | 4 つのボリューム | attached/healthy（4 本とも chirico）、replica running 2、`failedAt` なし |
| 2 | エンジン | 4 本とも `instance-manager-ed03b277…`（chirico、v1.13.0）。`state.diff` の `engines.tsv` の差はこの 4 行だけ |
| 3 | instance-manager | 4 つ、どれも v1.13.0・running。`$OLD_IM` は CR も Pod も NotFound |
| 4 | share-manager | 2 つとも running、`status.currentImage` v1.13.0、Pod のイメージ v1.13.0（10:04:24 の作成）。`cg-data` は stopped のまま |
| 5 | ほかのボリューム | `lh-state.sh` の要約は前と同じ（attached/healthy 16、detached 1、replica running 30・stopped 2）。`state.diff` はエンジンの instance-manager、instance-manager の行、Pod の 3 行（古い instance-manager、share-manager 2）だけ |
| 6 | iSCSI | chirico は 10.244.8.60 に 5（4 本と `prometheus-…-0`）、10.244.8.216 は 0。duchamp 3、oeilvert 8、pablo 0 は前と同じ。どのノードも portal は今の instance-manager の IP だけ |
| 7 | iscsid | 4 台の MainPID は前と同じ |
| 8 | Pod | Running / Completed 以外 0。`pods-before.txt` との差は、data、h2、tumblr-web 2、ero-web 2、share-manager 2、古い instance-manager だけ。aphrael 4、`comics-webdav`、`*-restore` 3 の UID・restartCount は同じ |
| 9 | アプリ | プローブ 8 つが ok。`data.fs.svc`・`h2.fs.svc` の 22 と `h2-sshd` の LB がつながる。`www.fraction.jp` 200。`h.iwaco.pink`・`comics-webdav.iwaco.pink` は 401（認証。前と同じ形）。`comics-webdav` の service proxy の `/` は 404 だが、アプリの応答（ログにも 404 が出る。ファイルのパスで配っていて、`/` には何も返さない） |
| 10 | Trivy | `pod-767f7c764c`（instance-manager v1.11.2）は NotFound。share-manager の `pod-7596f8df9b`・`pod-6ccd6c447c` は**同じ名前のまま新しい Pod のレポートになった**（10:04:31・10:04:40 の作成、owner は新しい Pod の UID、`longhorn-share-manager:v1.13.0`、Critical 1・High 8）。v1.11.2 のレポートは 0 |
| 11 | ノード | 8 台 Ready。Longhorn の Node 4 つが Ready・schedulable |
| 12 | 監視 | 10:06 に止めた。`watch.log` に degraded・faulted は 0 |
| 13 | 片付け | 10:06 にトークンのファイルを消した（シェルの変数には置かず、毎回ファイルから読んだ） |

## 5. 手順書との差

- **§4.6 の 10・§2.6 の Trivy のレポートの名前**: share-manager のレポートの名前は Pod の名前のハッシュで、share-manager の Pod の名前は作り直しても同じなので、新しい Pod のレポートが同じ名前で作られた（古いレポートは Pod とともに消え、数秒〜十数秒で同じ名前のものができる）。「名前が無いこと」ではなく、そのレポートのタグが v1.13.0 であることで確かめる。手順書を直した
- **§4.5 の 2 の share-manager**: ボリュームが detached になった直後の `sm_state` は `stopping` で、`stopped` になるまで 14 秒ほどかかった。待つ形に直した
- **§5 の止まる時間**: 見込みよりずっと短かった（`fs/data` 約 40 秒、`fs/h2` 約 40 秒、homegallery 約 2 分 30 秒、作業全体で 10:00〜10:06）。Pod が同じノードに戻り、イメージの pull が要らなかったため。実際の値を足した
- **§4.3 の監視**: 手順書は `&` で流す形だが、今回はハーネスのバックグラウンド実行で 1 つずつ起動し、ファイルに追記した。中身は同じ
- `comics-webdav` の service proxy の `/` はふだんから 404 を返す（§6 の「NFS の頼り手が戻らない」の見方に書き足した）
