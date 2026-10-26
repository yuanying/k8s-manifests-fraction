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
