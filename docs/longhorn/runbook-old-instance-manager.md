# chirico に残る Longhorn の古い instance-manager と share-manager を片付ける手順書（本番 `fraction`）

本番 `fraction` の Longhorn は v1.13.0（2026-10-21 に上げた。`runbook-upgrade-1.12-1.13.md`）。ただし chirico に、v1.11.2 の instance-manager が 1 つ残り、その中で v1 のエンジン 4 つが動き続けている。RWX の share-manager 2 つも v1.11.2 のまま。この手順書は、その 4 つのボリュームを使うワークロードを一度 0 にして detach させ、戻して v1.13.0 の instance-manager・share-manager で attach し直させる手順である。

| | 今 | 後 |
|---|---|---|
| chirico の instance-manager | v1.11.2 の `instance-manager-4128231ccb0c288ab5a27791d898e928`（エンジン 4）と v1.13.0 の `instance-manager-ed03b27717c927983cfc70739d33ff3e` | v1.13.0 のものだけ（古いものは Longhorn が消す） |
| 4 つのボリュームのエンジン | イメージは v1.13.0、プロセスは v1.11.2 の instance-manager の中 | アタッチ先のノードの v1.13.0 の instance-manager の中 |
| share-manager（`homegallery/tumblr-data`・`ero-data`） | `longhorn-share-manager:v1.11.2`（CR の `spec.image` は v1.13.0、`status.currentImage` が v1.11.2） | v1.13.0 |
| Trivy の該当のレポート | `pod-767f7c764c`（instance-manager v1.11.2、Critical 3・High 95）、`pod-6ccd6c447c`・`pod-7596f8df9b`（share-manager v1.11.2、Critical 1・High 46） | 無くなる。新しい share-manager の Pod のレポートは v1.13.0 のもの |

依頼の資料: タスク `fraction-trivy-operator-scan` の `notes/handoff-longhorn-old-instance-manager.md` と、`notes/trivy-first-results.md` の申し送り 3。

**この手順書を書いた時点では、本番は何も変えていない**（§2 の値は 2026-10-26 07:4xZ に `fraction-auditor` と SSH で読んだもの）。

## 0. 役割と約束ごと

- **承認の節目は 1 つ**: ✋✋ **開始**（§4.2）。§2 の値を読み直した結果（§4.1）、§3 の決めごと、§5 の止まる時間と影響、§6 の止める条件、§7 のロールバックを示してから承認を取る。
- **節目の後、この手順書で ✋ を付けた操作（ワークロードの scale）は、ユーザーに知らせるだけで進めてよい。** 1 つずつ承認を取るものではない。
- **runbook から外れる操作（Pod の強制削除、ボリュームの強制 detach、iSCSI の logout、iscsid の再起動、ほかのワークロードの再起動、Longhorn の設定の変更、salvage）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認は、知らせずに行ってよい。時刻はすべて UTC で記録する。

## 1. 前提

### 1.1 kubeconfig

読み取りは `kubectl --context fraction`（`fraction-auditor`、read-only）。変更（scale）は `infra-admin` の短命のトークンで行う（`runbook-upgrade-1.12-1.13.md` §1.2 と同じ）。作業は 1 時間ほどで終わる見込みなので、期限は 2 時間でよい。

```sh
kubectl --context fraction create token infra-admin -n kube-system --duration=2h > /tmp/lh-oldim-admin-token
chmod 600 /tmp/lh-oldim-admin-token
ADMIN_TOKEN=$(cat /tmp/lh-oldim-admin-token)
kadm() { kubectl --context fraction --token="$ADMIN_TOKEN" "$@"; }
kadm auth can-i patch deployments.apps -n fs            # yes
kadm auth can-i patch deployments.apps -n homegallery   # yes
```

終わったら `unset ADMIN_TOKEN` と `rm /tmp/lh-oldim-admin-token`。トークンを使うのは §4.4・§4.5 の `scale` だけ。

### 1.2 SSH

chirico（192.168.1.83）に `ssh yuanying@192.168.1.83` で入り、パスワードなしで sudo できる（サンドボックスの中で通る。2026-10-26 にこの手順書を書いたとき、4 台に読み取りで入った）。使うのは読み取り（`iscsiadm -m session`、`tools/node-state.sh`、`dmesg`）だけ。

ほかのノード（pablo .134、duchamp .135、oeilvert .82）も、戻したボリュームがそのノードにアタッチされたときに同じ読み取りをする。

### 1.3 使うもの

- `tools/lh-state.sh <dir>`（前と後の Longhorn の状態。`engines.tsv` に instance-manager の列がある）、`tools/lh-watch.sh`（2 秒ごと、変わったものだけ）。`runbook-upgrade-1.12-1.13.md` §1.6
- `../k8s-upgrade/tools/node-state.sh`（iscsid の PID、iSCSI のセッション、エンジンの起動の時刻と `older-than-iscsid`）
- §4.3 の確認用の関数（この手順書の中で定義する）

## 2. 本番の今（2026-10-26 07:4xZ の読み取り）

作業の当日に §4.1 で読み直す。

### 2.1 instance-manager

| 名前 | ノード | イメージ | IP | エンジン | replica |
|---|---|---|---|---|---|
| `instance-manager-4128231ccb0c288ab5a27791d898e928` | chirico | **v1.11.2** | 10.244.8.216 | **4**（下の表） | 0 |
| `instance-manager-ed03b27717c927983cfc70739d33ff3e` | chirico | v1.13.0 | 10.244.8.60 | 1（`prometheus-…-0`） | 8 |
| `instance-manager-134f259ce23ee5fdbaa790d27788c977` | duchamp | v1.13.0 | 10.244.5.186 | 3 | 8 |
| `instance-manager-2cd5c26768cbf14b533a40a50d957ebe` | oeilvert | v1.13.0 | 10.244.7.224 | 8 | 13 |
| `instance-manager-b510f391147d37bff0198406b92f0e49` | pablo | v1.13.0 | 10.244.4.197 | 0 | 1 |

- 5 つとも `running`。v1.11.2 のものの Pod は 6d22h（2026-10-19 から）、owner は InstanceManager
- longhorn-manager の引数は `--instance-manager-image …:v1.13.0`、`--share-manager-image …:v1.13.0`
- 段 8 のベースライン（2026-10-23、`../k8s-upgrade/results/stage-8/baseline.md`）では、v1.11.2 の instance-manager の中に 8 つのエンジンがあった。その後の 3 日で 4 つが detach で抜け、今の 4 つになった（pablo・oeilvert の v1.11.2 の instance-manager も、その上のエンジンが無くなったときに Longhorn が消した。`../k8s-upgrade/runbook-stage-8.md` §1.10）。**中のエンジンが無くなれば Longhorn が消す、という上流の文書の動きは本番でも起きている**

### 2.2 4 つのボリューム

| ボリューム | 名前空間/PVC | 大きさ | 実使用 | アクセス | data locality | エンジン | replica（ノード、instance-manager） |
|---|---|---|---|---|---|---|---|
| `pvc-1d94c3ed-6b77-4077-83c1-cea28fb76628` | fs/data | 200Gi | 59.4 GiB | RWO | disabled | `…-e-29bded80` | chirico（ed03b277）、duchamp（134f259c） |
| `pvc-c4944b75-7ed0-4cf4-adce-bb5723993ff8` | fs/h2 | 300Gi | 163.1 GiB | RWO | **best-effort** | `…-e-0` | chirico（ed03b277）、oeilvert（2cd5c267） |
| `pvc-0b28d049-7da0-40f4-812a-122fe56161f3` | homegallery/tumblr-data | 8Gi | 4.9 GiB | **RWX** | disabled | `…-e-58b23836` | duchamp（134f259c）、oeilvert（2cd5c267） |
| `pvc-baa41130-82c0-41ed-9df8-2569458615b6` | homegallery/ero-data | 20Gi | 6.4 GiB | **RWX** | disabled | `…-e-1caaf475` | pablo（b510f391）、oeilvert（2cd5c267） |

- 4 つとも chirico に attached・healthy、replica 2（running 2、`failedAt` なし）、frontend `blockdev`、エンジンのイメージ `longhorn-engine:v1.13.0`、`staleReplicaTimeout` 2880。エンジンの CR の `status.instanceManagerName` が 4 つとも v1.11.2 のもの
- replica は 4 つとも v1.13.0 の instance-manager にある（live upgrade で移った）。**detach と再 attach で動くのはエンジンだけで、replica のデータは動かない**
- Longhorn の VolumeAttachment の ticket: `fs/data`・`fs/h2` は `csi-attacher`（chirico）の 1 つ。RWX の 2 つは `csi-attacher`（chirico、duchamp）と `share-manager-controller`（chirico）。ほかの ticket（バックアップ、スナップショット、手でのアタッチ）は無い
- `fs/h2` だけ data locality が `best-effort`。戻したときに Pod が replica の無いノード（pablo・duchamp）に載ると、Longhorn がそのノードに replica を作り（163 GiB の rebuild）、終わってから 1 つを消す。rebuild の間もボリュームは healthy（§3 の 6）

### 2.3 share-manager

| 名前 | ノード | `spec.image` | `status.currentImage` | Pod（作られた時刻） | endpoint |
|---|---|---|---|---|---|
| `pvc-0b28d049-…`（tumblr-data） | chirico | v1.13.0 | **v1.11.2** | `share-manager-pvc-0b28d049-…`、10.244.8.240（2026-10-19T09:35:32Z） | `nfs://10.254.0.67/…` |
| `pvc-baa41130-…`（ero-data） | chirico | v1.13.0 | **v1.11.2** | `share-manager-pvc-baa41130-…`、10.244.8.230（2026-10-19T09:35:29Z） | `nfs://10.254.0.4/…` |
| `pvc-c9f006ad-…`（cg-data） | pablo | v1.13.0 | — | 無い（stopped、以前から） | — |

- share-manager の Pod は、ボリュームが detach されると消え（state `stopped`）、次にアタッチされるときに `spec.image`（v1.13.0）で作り直される。v1.13.0 の share-manager のイメージは、longhorn-manager の DaemonSet の `pre-pull-share-manager-image` のコンテナで 4 台とも取ってある
- 設定（変えない）: `rwx-volume-fast-failover` false、`auto-delete-pod-when-volume-detached-unexpectedly` true、`node-drain-policy` block-if-contains-last-replica、`auto-salvage` true、`default-data-locality` best-effort、`replica-auto-balance` disabled、`concurrent-replica-rebuild-per-node-limit` 5

### 2.4 ワークロードと、それに頼るもの

4 つのボリュームを直接使う（PVC をマウントする）のは、次の 4 つの Deployment だけ（全 Pod の `spec.volumes` で確かめた）。

| Deployment | replicas（今。戻す値） | strategy | PVC | Pod（ノード） | ほかのボリューム |
|---|---|---|---|---|---|
| `fs/data` | **1** | Recreate、grace 30 秒 | data | `data-66596b955b-wgs4w`（chirico） | 無い |
| `fs/h2` | **1** | Recreate、grace 30 秒 | h2 | `h2-6cb59468bd-lpdks`（chirico） | 無い |
| `homegallery/tumblr-web` | **2** | RollingUpdate | tumblr-data（RWX） | `-9vcg8`（chirico）、`-lk8ms`（duchamp） | **`h2.fs.svc.cluster.local:/` の NFS** |
| `homegallery/ero-web` | **2** | RollingUpdate | ero-data（RWX） | `-jtgq6`（chirico）、`-2rhp2`（duchamp） | **`h2.fs.svc.cluster.local:/` の NFS** |

- どれも nodeSelector・affinity が無い。PDB も無い。本番に Flux・Argo CD は動いておらず、`replicas` を書き戻すものは無い（manifest は `kubectl apply` で入れたもの）
- `fs/data`・`fs/h2` の Pod は、ボリュームを NFS（`nfs` コンテナ、`data.fs.svc` 10.254.0.60、`h2.fs.svc` 10.254.0.170）と SSH（`sshd` コンテナ、22。`h2` は LoadBalancer `h2-sshd`、`[2405:6580:6740:ac01:ace::131]:3222`）で出している

**同じ PVC を使うものは、ほかに無い。** `fs/data-restore`・`h2-restore`・`sites-restore` の Deployment と、CronJob `data-backup`・`h2-backup`・`sites-backup` は PVC を使わず、braque の NFS（`192.168.1.131:/data`・`/h`・`/sites`）と fs の NFS（`data.fs.svc`・`h2.fs.svc`・`sites.fs.svc`）を両方マウントして rsync する。

**`fs/data`・`fs/h2` の NFS に頼るもの**（止まる間、NFS の I/O が止まる。ボリュームのアタッチとは別）:

| 頼る先 | もの | 形 |
|---|---|---|
| `data.fs.svc:/` | `fs/data-restore`（duchamp）、CronJob `fs/data-backup`、oeilvert のホストの automount `/home/yuanying/shared/data`（今はマウントされていない） | Pod の inline の `nfs` ボリューム |
| `h2.fs.svc:/` | `fs/h2-restore`（duchamp）、CronJob `fs/h2-backup`、**`homegallery/tumblr-web`・`ero-web` の 4 つ**、oeilvert の automount `/home/yuanying/shared/h`（今はマウントされていない） | 同上 |
| `h2.fs.svc:/`（PV `aphrael-2`） | `aphrael/aphrael` の 4 つ（chirico 2、pablo、duchamp。Ingress `h.iwaco.pink`）、CronJob `aphrael/tumblr-like`（`38 */3 * * *`） | NFS の PV |
| `h2.fs.svc:/comics`（PV `comics-2`） | `comics/comics-webdav`（chirico。Ingress `comics-webdav.iwaco.pink`） | NFS の PV |
| SSH | LAN から `h2-sshd`（LB）、`data.fs.svc`・`h2.fs.svc` の 22（作業端末からも 10.254.0.60:22・10.254.0.170:22 に届く） | — |

- PV `comics`（`h.fs.svc.cluster.local:/h/comics`）は、今は無い Service を指す古いもので、使う Pod は無い
- homegallery を外に出す Ingress は無い（`homegallery` の Service は ClusterIP の `api`・`cg`・`ero`・`tumblr` だけで、ほかの名前空間の Ingress・ConfigMap にも参照が無い。2026-10-26 の読み取り）。`homegallery/api`（oeilvert 固定）は 4 つのボリュームも fs の NFS も使わない
- 作業の前の Pod の restartCount は、上の表の Pod と aphrael・comics・restore のどれも 0

### 2.5 iSCSI（chirico と、ほかの 3 台）

`../k8s-upgrade/tools/node-state.sh` の出力（2026-10-26 07:4xZ）:

| ノード | iscsid の MainPID（起動） | Longhorn のセッション | エンジン（`older-than-iscsid`） |
|---|---|---|---|
| chirico | 3144486（2026-10-22 06:20:27Z） | 5: **10.244.8.216 に 4**（4 つのボリューム）、10.244.8.60 に 1（`prometheus-…-0`） | 4 つのボリュームのエンジンは 2026-10-21T03:07:46〜03:09:08Z の起動で、**4 つとも `older-than-iscsid`** |
| duchamp | 2695716（2026-10-21 06:08:00Z） | 3（10.244.5.186） | 2 つが `older-than-iscsid` |
| oeilvert | 912599（2026-10-23 22:44:23Z） | 8（10.244.7.224） | 0 |
| pablo | 4114921（2026-10-21 06:40:42Z） | 0 | — |

- セッションの portal はどれも、そのノードで今動いている instance-manager の IP。古いセッションは無い
- chirico の 4 つのエンジンは、iscsid の今の起動（10-22 06:20Z の needrestart）より前に起動している。Longhorn v1.11.2 のエンジンならこの形は detach で logout できず、セッションを残す（porkadot-dev の `docs/longhorn/iscsi-stale-sessions.md` の結論の 1）。**このエンジンのバイナリは v1.13.0**（live upgrade で起動し直した。`/engine-binaries/docker.io-longhornio-longhorn-engine-v1.13.0/longhorn`）で、`nsenter` が古い PID で失敗したら iscsid の PID を引き直す直し（go-common-libs `b3e1f44`）が入っている。dev では、live upgrade したエンジンでアタッチしたまま iscsid を再起動し、detach しても古いセッションは残らなかった（`runbook-upgrade-1.12-1.13.md` §5.3）
- **本番でも、同じ形のエンジンが detach できている**: 段 8 のベースライン（10-23）では chirico に 11 のセッション（10.244.8.216 に 8）と `older-than-iscsid` の 9 があった。今は 10.244.8.216 に 4、`older-than-iscsid` 4 で、抜けたエンジンの古いセッションは chirico に 1 つも残っていない
- それでも、detach の後に chirico のセッションを確かめる（§4.4 の 4、§4.5 の 4）。**残っていたら、iscsid を再起動する前に**そのセッションだけを logout すれば消える（同じ文書の §4.2）。runbook から外れるのでユーザーが決める（§6）

### 2.6 Trivy の該当のレポート（`longhorn-system` の vulnerabilityreports）

| レポート | 対象 | イメージ | Critical | High |
|---|---|---|---|---|
| `pod-767f7c764c` | Pod `instance-manager-4128231c…` | longhorn-instance-manager:v1.11.2 | 3 | 95 |
| `pod-7596f8df9b` | Pod `share-manager-pvc-0b28d049-…` | longhorn-share-manager:v1.11.2 | 1 | 46 |
| `pod-6ccd6c447c` | Pod `share-manager-pvc-baa41130-…` | longhorn-share-manager:v1.11.2 | 1 | 46 |
| （参考）`pod-6695669c4b` ほか 3 つ | v1.13.0 の instance-manager 4 つ | longhorn-instance-manager:v1.13.0 | 2 | 11 |
| （参考）`daemonset-longhorn-manager-pre-pull-share-manager-image` | | longhorn-share-manager:v1.13.0 | 1 | 8 |

- Pod のレポートは owner が Pod で、Pod が消えると消える。新しい share-manager の Pod には Trivy Operator が新しいレポートを作る（v1.13.0 のイメージなので、参考の行と同じ Critical 1・High 8 の見込み）
- v1.13.0 のイメージの Critical は別件（v1.13.x の更新で扱う。依頼の資料）

### 2.7 時間帯

fs の CronJob は `timeZone` を持たず、kube-controller-manager の時刻（UTC）で動く。Job の名前（スケジュールの時刻の分）と `lastScheduleTime` で確かめた: `h2-backup` は 2026-10-26T05:44:00Z（JST 14:44）、`data-backup` は 2026-10-25T09:03:00Z（JST 18:03）。依頼の資料の JST 14:44・18:03 と合う。

| UTC | もの | 避ける理由 |
|---|---|---|
| 00:38、03:38、06:38、09:38、12:38、15:38、18:38、21:38（数秒〜十数秒） | `aphrael/tumblr-like` | `aphrael-2`（`h2.fs.svc` の NFS）を使う。h2 が止まっている間に動くと NFS で止まる |
| 05:44〜05:46 | `fs/h2-backup` | `h2.fs.svc` を rsync する |
| 05:50〜06:40 ごろ | Trivy Operator の毎日のスキャン | 作業と重ねると、レポートの作り直しと見分けにくい（データには関わらない） |
| 06:00〜07:00 | worker の unattended-upgrades | needrestart が iscsid を再起動しうる（2026-10-22 の chirico）。detach の前後で iscsid が変わると §2.5 の見立てが崩れる |
| 07:53〜07:57 | `fs/sites-backup` | 作業の対象ではないが、fs の作業と重ねない |
| 09:03〜09:05 | `fs/data-backup` | `data.fs.svc` を rsync する |
| 18:00〜19:30 | jumelle の自動更新と自動再起動 | Pod が別のノードに載ると ghcr.io などからの pull が要る |
| 20:30、21:00 | natsumi・deep-researcher のバックアップ（JST の CronJob） | 作業の対象ではない。重ねない |
| 21:00〜22:00 | control-plane の unattended-upgrades | apiserver が揺れると確かめと取り違える |

**推奨は 10:00〜12:30Z（JST 19:00〜21:30）**。その日の `h2-backup`・`data-backup` が済んだ後なので、braque に前日より新しい fs のコピーがある（§3 の 5）。次の候補は 01:00〜03:30Z（JST 10:00〜12:30。前日の `data-backup` の後、その日の `h2-backup` の前）。

## 3. 決まっていること

| # | 内容 | 決定 | 理由・出典 |
|---|---|---|---|
| 1 | 片付け方 | 4 つのボリュームを使うワークロードを 0 にして detach させ、戻して attach させる。エンジンはアタッチ先のノードの v1.13.0 の instance-manager で起動し直し、空になった v1.11.2 の instance-manager は Longhorn が消す。RWX の share-manager は detach で止まり、次のアタッチで v1.13.0 で作り直される | 上流の文書「Instance Manager Pods During Upgrade」（v1.13.0）の「How to Fully Clean Up Old Instance Manager Pods」（detach すれば、エンジンと replica の無くなった古い instance-manager を Longhorn が消す）と KB「Some old instance manager pods are still running after upgrade」。detach の仕方は「Detach Longhorn Volumes」（Deployment の `replicas` を 0）。エンジンはもう v1.13.0 なので、エンジンの更新は要らない |
| 2 | 使わない方法 | 古い instance-manager の Pod を消す、share-manager の Pod だけを消す、chirico を drain する、は使わない | Pod を消すと、アタッチしたままのエンジンが落ち、I/O エラーや faulted になりうる。share-manager の Pod だけを消すと、NFS のクライアントがマウントしたままエンジンが起動し直す。drain は chirico のほかの Pod（Prometheus の replica 1 のボリューム、aphrael、comics など）も動かし、段 2 の iSCSI の件を起こした形でもある |
| 3 | 単位と順 | **段 A: `fs/data` を 1 つだけ**（止める → detach → 戻す）。結果を確かめてから **段 B: `homegallery` の 2 つと `fs/h2` をまとめて**（止めるのは homegallery → h2、戻すのは h2 → homegallery）。段 B の後に古い instance-manager が消える | 段 A は、NFS の頼り手がいちばん少ない（`data-restore` と、時間帯で避ける `data-backup` だけ）ボリュームで、本番の `older-than-iscsid` のエンジンの detach と、新しい instance-manager でのアタッチを先に 1 本で確かめる。homegallery は `h2.fs.svc` の NFS に頼るので、h2 と別に止めると homegallery が 2 回止まる |
| 4 | 段 B の止める順と戻す順 | **止める: homegallery（tumblr-web、ero-web）→ fs/h2。戻す: fs/h2 → homegallery** | homegallery の Pod は `h2.fs.svc` の NFS をマウントしている。h2 が止まった後に homegallery の Pod を消すと、kubelet の NFS の umount が止まった NFS サーバーで止まり（既定の hard マウント）、Pod が Terminating のまま残りうる。h2 が動いている間に消し、h2 が戻ってから作る |
| 5 | バックアップ | 取らない。作業はその日の `h2-backup`・`data-backup` の後に行う（§2.7） | detach と attach は Pod がノードを移るたびに起きるふだんの操作で、replica のデータに触らない。fs の 2 本は CronJob で braque に毎日 rsync されている。homegallery の 2 本はアプリの側のバックアップを確かめていない（§9 の 1） |
| 6 | Pod の載るノード | 指定しない（manifest を変えない）。scheduler が決める | `fs/h2` が replica の無いノードに載ると、data locality（best-effort）の rebuild が 163 GiB 走る。その間も healthy で、止まる時間には入らない。rebuild の始めと終わりを記録する |
| 7 | 1 つずつか同時か | 段 B の中では、homegallery の 2 つを同時に 0 にし、2 本の detach を確かめてから h2 を 0 にする。戻すときは h2 の attach と NFS の応答を確かめてから homegallery の 2 つを同時に戻す | homegallery の 2 つは同じ形（RWX、share-manager、同じ NFS）で、別々にする理由が無い |
| 8 | NFS の頼り手（aphrael、comics、restore、oeilvert の automount） | 止めない | Service の ClusterIP は変わらないので、NFS サーバーが戻ればクライアントはつなぎ直す見込み（hard マウントは I/O を止めて待つ）。止めると戻す値が増える。戻らないときは §6 |
| 9 | `replicas` の戻す値 | §4.1 で読んだ値に戻す（2026-10-26: data 1、h2 1、tumblr-web 2、ero-web 2） | `kubectl scale` は `replicas` だけを変える |
| 10 | Longhorn の設定 | 変えない | — |

## 4. 手順

### 4.1 事前の確認（読み取り）

```sh
D=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/longhorn-old-im
mkdir -p $D
T=docs/longhorn/tools
K="kubectl --context fraction -n longhorn-system"
OLD_IM=instance-manager-4128231ccb0c288ab5a27791d898e928
V_DATA=pvc-1d94c3ed-6b77-4077-83c1-cea28fb76628
V_H2=pvc-c4944b75-7ed0-4cf4-adce-bb5723993ff8
V_TUMBLR=pvc-0b28d049-7da0-40f4-812a-122fe56161f3
V_ERO=pvc-baa41130-82c0-41ed-9df8-2569458615b6
KUBECTL="kubectl --context fraction" $T/lh-state.sh $D/before
for ip in 192.168.1.83 192.168.1.135 192.168.1.82 192.168.1.134; do
  ssh yuanying@$ip 'sudo bash -s' < docs/k8s-upgrade/tools/node-state.sh > $D/node-before-$ip.txt
done
```

確認用の関数（読み取り）:

```sh
# instance-manager: 名前、ノード、版、状態、IP、中のエンジンのボリューム
im_state() {
  $K get instancemanagers.longhorn.io -o json | jq -r '.items[] | [.metadata.name, .spec.nodeID,
    (.spec.image | sub(".*:"; "")), .status.currentState, .status.ip,
    ((.status.instanceEngines // {}) | keys | map(sub("-e-[0-9a-z]+$"; "")) | join(","))] | @tsv'
}
# ボリュームの状態と、エンジンのいる instance-manager
vol_state() {   # <volume>...
  for v in "$@"; do
    $K get volumes.longhorn.io $v -o jsonpath='{.metadata.name} {.status.state}/{.status.robustness} node={.status.currentNodeID} img={.status.currentImage}{"\n"}'
    $K get engines.longhorn.io -l longhornvolume=$v -o jsonpath='{range .items[*]}  engine {.metadata.name} {.status.currentState} im={.status.instanceManagerName}{"\n"}{end}'
    $K get replicas.longhorn.io -l longhornvolume=$v -o jsonpath='{range .items[*]}  replica {.spec.nodeID} {.status.currentState} failedAt={.spec.failedAt}{"\n"}{end}'
  done
}
# ボリュームの state が <want> になるまで待つ（既定 300 秒）
wait_vol() {   # <volume> <want> [timeout]
  local v=$1 want=$2 end=$((SECONDS + ${3:-300}))
  until [ "$($K get volumes.longhorn.io $v -o jsonpath='{.status.state}')" = "$want" ]; do
    [ $SECONDS -ge $end ] && { echo "TIMEOUT $v $want"; return 1; }
    sleep 2
  done
  echo "$(date -u +%T) $v $want"
}
sm_state() {
  $K get sharemanagers.longhorn.io -o custom-columns=N:.metadata.name,STATE:.status.state,NODE:.status.ownerID,SPEC:.spec.image,CUR:.status.currentImage --no-headers
  $K get pods -l longhorn.io/component=share-manager -o custom-columns=N:.metadata.name,NODE:.spec.nodeName,PHASE:.status.phase,IMG:.spec.containers[0].image,CREATED:.metadata.creationTimestamp --no-headers
}
```

| # | 確認 | 合格基準 |
|---|---|---|
| 1 | 時刻 | §2.7 の避ける時間帯に入っていない。段 B の終わりまで（見込み 1 時間）が次の避ける時刻にかからない |
| 2 | Longhorn の版 | `current-longhorn-version` が v1.13.0。engine image は `ei-2f3240cb`（v1.13.0）だけが deployed |
| 3 | instance-manager | `im_state` が §2.1 と同じ形。`$OLD_IM` の中のエンジンが 4 つのボリュームだけ（増えていない）、replica 0。5 つとも `running` |
| 4 | 4 つのボリューム | `vol_state $V_DATA $V_H2 $V_TUMBLR $V_ERO` で 4 つとも attached・healthy、エンジンが `$OLD_IM`、replica が running 2 で `failedAt` なし。rebuild の途中のもの（`WO` の replica、Replica の CR が 3 つ）が無い |
| 5 | ほかのボリューム | attached のものが全部 healthy、faulted 0、detached は `homegallery/cg-data` だけ（`lh-state.sh` の要約） |
| 6 | share-manager | `sm_state` が §2.3 と同じ |
| 7 | ワークロード | §2.4 の 4 つの Deployment の `replicas` と Pod（ノード、restartCount）を控える（下）。同じ PVC を使う Pod がほかに無い |
| 8 | NFS の頼り手 | §2.4 の表の Pod が Running。aphrael・homegallery が service proxy で答える（下） |
| 9 | iSCSI | 4 台の `node-before-*.txt` が §2.5 と同じ形。chirico の 10.244.8.216 のセッションが 4 つ（4 つのボリューム）。今動いている instance-manager の IP でない portal が無い。iscsid の MainPID を控える |
| 10 | Pod | クラスタ全体で Running / Completed 以外の Pod が無い |
| 11 | Trivy | §2.6 の 3 つのレポートがある（名前を控える） |

```sh
kubectl --context fraction -n fs get deploy data h2 -o custom-columns=N:.metadata.name,R:.spec.replicas --no-headers > $D/replicas-before.txt
kubectl --context fraction -n homegallery get deploy tumblr-web ero-web -o custom-columns=N:.metadata.name,R:.spec.replicas --no-headers >> $D/replicas-before.txt
cat $D/replicas-before.txt     # data 1、h2 1、tumblr-web 2、ero-web 2
kubectl --context fraction get pods -n fs -o json | jq -r '.items[] | select([.spec.volumes[]? | .persistentVolumeClaim.claimName // empty] | any(. == "data" or . == "h2")) | .metadata.name + " " + .spec.nodeName + " " + .status.phase'
kubectl --context fraction get pods -n homegallery -o json | jq -r '.items[] | select([.spec.volumes[]? | .persistentVolumeClaim.claimName // empty] | any(. == "tumblr-data" or . == "ero-data")) | .metadata.name + " " + .spec.nodeName + " " + .status.phase'
#   fs は data-… と h2-… の 2 つ、homegallery は tumblr-web-… 2 つと ero-web-… 2 つだけ（PVC は名前空間の中のものなので、ほかの名前空間からは使えない）
kubectl --context fraction get pods -n fs -o wide > $D/pods-fs-before.txt
kubectl --context fraction get pods -n homegallery -o wide > $D/pods-homegallery-before.txt
kubectl --context fraction get pods -A -o custom-columns=NS:.metadata.namespace,N:.metadata.name,UID:.metadata.uid,NODE:.spec.nodeName,R:.status.containerStatuses[*].restartCount --no-headers | sort > $D/pods-before.txt
$K get vulnerabilityreports -o custom-columns=N:.metadata.name,POD:.metadata.labels.trivy-operator\\.resource\\.name,REPO:.report.artifact.repository,TAG:.report.artifact.tag,C:.report.summary.criticalCount,H:.report.summary.highCount --no-headers | grep -E 'instance-manager|share-manager' > $D/trivy-before.txt
```

ここで止めるのは、3・4・5・9 が合わないとき（4 つのボリュームのどれかが degraded・rebuild 中、古い instance-manager に別のエンジンが増えた、古いセッションがある、など）。

### 4.2 承認 ✋✋

§4.1 の結果、§3、§5、§6、§7 を示して、開始の承認を取る。§9 の決めることも、ここで答えをもらう。

### 4.3 監視を始める

承認の後、§4.4 の前から、§4.6 の確認が済むまで、作業端末で流しておく（読み取り）。

```sh
# 1. Longhorn（2 秒ごと、変わったものだけ）
KUBECTL="kubectl --context fraction" $T/lh-watch.sh | tee -a $D/watch.log &
# 2. fs の NFS・SSH と、それに頼るもの（2 秒ごと。失敗だけと、60 回ごとの ok）
n=0
while true; do
  t=$(date -u +%FT%TZ)
  for a in data:10.254.0.60:2049 data-ssh:10.254.0.60:22 h2:10.254.0.170:2049 h2-ssh:10.254.0.170:22 h2-sshd-lb:[2405:6580:6740:ac01:ace::131]:3222; do
    n_=${a%%:*}; hp=${a#*:}; h=${hp%:*}; p=${hp##*:}; h=${h#[}; h=${h%]}
    timeout 3 bash -c "exec 3<>/dev/tcp/$h/$p" 2>/dev/null || echo "$t FAIL $n_"
  done
  for s in aphrael/aphrael:80 homegallery/tumblr:3000 homegallery/ero:3000; do
    ns=${s%%/*}; r=${s#*/}
    timeout 5 kubectl --context fraction get --raw "/api/v1/namespaces/$ns/services/http:${r%:*}:${r#*:}/proxy/" >/dev/null 2>&1 || echo "$t FAIL $s"
  done
  n=$((n+1)); (( n % 60 == 0 )) && echo "$t ok $n"
  sleep 2
done | tee -a $D/probe.log &
```

- 2026-10-26 07:5xZ に、作業端末から 10.254.0.60:22・10.254.0.170:22・`h2-sshd` の LB に TCP でつながり、aphrael・tumblr・ero の service proxy が HTML を返すことを確かめた
- 止める間の `FAIL` は想定どおり（§5）。戻した後に `FAIL` が続かないことを見る
- 止めるのは §4.6 の後（`kill %1 %2`）

### 4.4 段 A: `fs/data`

1. 前の確認（読み取り）

   ```sh
   date -u +%FT%TZ
   vol_state $V_DATA      # attached/healthy node=chirico、engine im=$OLD_IM、replica running 2
   ```

2. ✋ 0 にする

   ```sh
   kadm -n fs scale deploy/data --replicas=0
   kubectl --context fraction -n fs wait --for=delete pod -l app=nfs,component=data --timeout=120s
   wait_vol $V_DATA detached 300
   ```

   - Pod が 120 秒で消えなければ止める（強制削除しない。§6）
   - ボリュームが 300 秒で detached にならなければ止める（§6）
   - Pod が消えた時刻と detached になった時刻を記録する

3. detach の後の確認（読み取り）

   ```sh
   vol_state $V_DATA                  # detached/unknown、エンジンは stopped（または instanceManagerName が空）、replica は stopped 2 で failedAt なし
   im_state                           # $OLD_IM の中のエンジンが 3 つ（h2、tumblr-data、ero-data）に減った
   ssh yuanying@192.168.1.83 'sudo iscsiadm -m session; ls /dev/longhorn/'
   ```

4. chirico の iSCSI（§2.5）
   - `iqn.2019-10.io.longhorn:pvc-1d94c3ed-…` のセッションが無い。10.244.8.216 のセッションが 3 つ（ほかの 3 本）に減っている
   - `/dev/longhorn/pvc-1d94c3ed-…` が無い
   - **セッションが残っていたら止める**（§6）。そのとき iscsid を再起動しない。残ったまま段 B に進まない
   - `ssh yuanying@192.168.1.83 'sudo dmesg -T | tail -50'` に I/O エラー（`Buffer I/O error`、`blk_update_request`、`connection … error`）が無い

5. ✋ 戻す

   ```sh
   kadm -n fs scale deploy/data --replicas=1    # §4.1 で控えた値
   kubectl --context fraction -n fs rollout status deploy/data --timeout=300s
   wait_vol $V_DATA attached 300
   vol_state $V_DATA
   kubectl --context fraction -n fs get pods -l app=nfs,component=data -o wide
   ```

6. 戻した後の確認（読み取り）

   | # | 確認 | 合格基準 |
   |---|---|---|
   | 1 | ボリューム | attached・healthy。アタッチ先が Pod のノード |
   | 2 | エンジン | `instanceManagerName` が、そのノードの **v1.13.0 の instance-manager**（§2.1 の表）。`$OLD_IM` でない |
   | 3 | replica | running 2、`failedAt` なし。data locality は disabled なので、replica は chirico・duchamp のまま |
   | 4 | iSCSI | Pod のノードで `sudo iscsiadm -m session` に `pvc-1d94c3ed-…` のセッションが 1 つ、portal がそのノードの v1.13.0 の instance-manager の IP |
   | 5 | Pod | `data-…` が 2/2 Running。`fs/data-restore` が Running で restartCount 0 のまま |
   | 6 | 監視 | `probe.log` の `data`・`data-ssh` の `FAIL` が止まった。止まっていた時間（最初の `FAIL` から最後の `FAIL` まで）を記録する |
   | 7 | Trivy | （段 A では変わらない。古い instance-manager はまだ残る） |

   どれかが合わなければ、段 B に進まずに止める（§6）。

### 4.5 段 B: `homegallery` と `fs/h2`

1. 前の確認（読み取り）

   ```sh
   date -u +%FT%TZ
   vol_state $V_H2 $V_TUMBLR $V_ERO
   sm_state
   kubectl --context fraction -n homegallery get pods -o wide
   ```

   - 時刻が次の `aphrael/tumblr-like`（:38）と `fs/h2-backup`（05:44）に、30 分以上の余裕がある

2. ✋ homegallery を 0 にする（h2 が動いている間に）

   ```sh
   kadm -n homegallery scale deploy/tumblr-web deploy/ero-web --replicas=0
   kubectl --context fraction -n homegallery wait --for=delete pod -l app=homegallery,component=tumblr --timeout=120s
   kubectl --context fraction -n homegallery wait --for=delete pod -l app=homegallery,component=ero --timeout=120s
   wait_vol $V_TUMBLR detached 300
   wait_vol $V_ERO detached 300
   sm_state     # 2 つとも stopped、share-manager の Pod が無い
   ```

   - share-manager の Pod は、ボリュームを使う Pod が無くなると Longhorn が止め、ボリュームが detach される。数十秒かかりうる
   - Pod が 120 秒で消えない、ボリュームが 300 秒で detached にならない、share-manager が stopped にならない、のどれかなら止める。**h2 を止める前に止める**（homegallery の Pod が残ったまま h2 を止めない）

3. ✋ `fs/h2` を 0 にする

   ```sh
   kadm -n fs scale deploy/h2 --replicas=0
   kubectl --context fraction -n fs wait --for=delete pod -l app=nfs,component=h2 --timeout=120s
   wait_vol $V_H2 detached 300
   ```

   - この時点から、`h2.fs.svc` の NFS と SSH、`h2-sshd` の LB が止まる（§5）

4. detach の後の確認（読み取り）

   ```sh
   vol_state $V_H2 $V_TUMBLR $V_ERO
   im_state                           # $OLD_IM が無くなる（下）
   ssh yuanying@192.168.1.83 'sudo iscsiadm -m session; ls /dev/longhorn/'
   ```

   - 3 本とも detached、replica は stopped 2 で `failedAt` なし
   - **`$OLD_IM` が消える**（中のエンジンが 0 になれば、Longhorn がすぐ消す。上流の文書）。`$K get pods $OLD_IM` が NotFound、`im_state` に v1.11.2 の行が無い。数分たっても残っていれば記録する（データの危険は無いので、5 に進んでよい。§6）
   - chirico の 10.244.8.216 のセッションが 0。10.244.8.60（`prometheus-…-0`）のセッションは残る。**ほかのセッションが残っていたら止める**（§6）。`/dev/longhorn/` に 3 本が無い
   - `dmesg` に I/O エラーが無い

5. ✋ `fs/h2` を戻す

   ```sh
   kadm -n fs scale deploy/h2 --replicas=1      # §4.1 で控えた値
   kubectl --context fraction -n fs rollout status deploy/h2 --timeout=300s
   wait_vol $V_H2 attached 300
   vol_state $V_H2
   kubectl --context fraction -n fs get pods -l app=nfs,component=h2 -o wide
   ```

   - §4.4 の 6 の 1〜4 と同じことを確かめる（エンジンがそのノードの v1.13.0 の instance-manager、iSCSI の portal がその IP）
   - Pod が chirico・oeilvert（replica のあるノード）でないノードに載ったら、data locality の rebuild が始まる（§3 の 6）。replica が 3 つになり、新しい 1 つが `WO` から `RW` になってから、Longhorn がほかの 1 つを消す。始めの時刻を記録し、終わるのを待たずに 6 へ進んでよい（healthy のまま）
   - `probe.log` の `h2`・`h2-ssh`・`h2-sshd-lb` の `FAIL` が止まる。aphrael の service proxy が答える（NFS サーバーの起動の後、NFSv4 の grace の 90 秒ほど、クライアントの I/O が待たされうる）

6. ✋ homegallery を戻す（h2 の NFS が答えてから）

   ```sh
   kadm -n homegallery scale deploy/tumblr-web deploy/ero-web --replicas=2    # §4.1 で控えた値
   kubectl --context fraction -n homegallery rollout status deploy/tumblr-web --timeout=300s
   kubectl --context fraction -n homegallery rollout status deploy/ero-web --timeout=300s
   wait_vol $V_TUMBLR attached 300
   wait_vol $V_ERO attached 300
   vol_state $V_TUMBLR $V_ERO
   sm_state
   ```

   - share-manager が 2 つとも `running`、Pod のイメージが **`longhorn-share-manager:v1.13.0`**、`status.currentImage` が v1.13.0
   - ボリュームは share-manager の Pod のノードにアタッチされ、エンジンがそのノードの v1.13.0 の instance-manager にいる
   - `tumblr-web`・`ero-web` の 4 つの Pod が Running・Ready（RWX の NFS と `h2.fs.svc` の NFS の両方をマウントする）。`FailedMount` が続かない
   - service proxy の `homegallery/tumblr`・`homegallery/ero` が答える

### 4.6 後の確認

```sh
KUBECTL="kubectl --context fraction" $T/lh-state.sh $D/after
diff -r $D/before $D/after > $D/state.diff
for ip in 192.168.1.83 192.168.1.135 192.168.1.82 192.168.1.134; do
  ssh yuanying@$ip 'sudo bash -s' < docs/k8s-upgrade/tools/node-state.sh > $D/node-after-$ip.txt
done
```

| # | 確認 | 合格基準 |
|---|---|---|
| 1 | 4 つのボリューム | attached・healthy。replica は running 2（`fs/h2` が rebuild の途中なら、終わってから 2 に戻ることを待って確かめる）、`failedAt` なし |
| 2 | エンジン | 4 つとも、アタッチ先のノードの v1.13.0 の instance-manager にいる（`engines.tsv` の instance-manager の列） |
| 3 | instance-manager | 4 つ（各ノードに v1.13.0 が 1 つずつ）。v1.11.2 のものが無い。`$OLD_IM` の CR と Pod が NotFound |
| 4 | share-manager | 2 つとも running、`status.currentImage` が v1.13.0、Pod のイメージが v1.13.0。`cg-data` は stopped のまま |
| 5 | ほかのボリューム | `lh-state.sh` の要約が §4.1 と同じ（attached healthy、detached は `cg-data` だけ）。ほかのボリュームの state・ノード・エンジンが変わっていない |
| 6 | iSCSI | 4 台とも、Longhorn のセッションの portal が、そのノードで今動いている instance-manager の IP だけ。**chirico に 10.244.8.216 のセッションが無い**。セッションの数が、そのノードにアタッチされたボリュームの数と同じ |
| 7 | iscsid | 4 台の MainPID が §4.1 と同じ |
| 8 | Pod | クラスタ全体で Running / Completed 以外が無い。`pods-before.txt` と比べ、作り直されたのが `fs/data`・`fs/h2`・`tumblr-web`・`ero-web`・share-manager 2 つだけ。aphrael 4・`comics-webdav`・`*-restore` 3 つの UID と restartCount が変わっていない |
| 9 | アプリ | §4.3 の監視の `FAIL` が止まっている。`h2-sshd` の LB と `data.fs.svc`・`h2.fs.svc` の 22 が SSH のバナーを返す。aphrael・tumblr・ero の service proxy が答える。`www.fraction.jp` が 200（`fs/sites` は触っていない対照） |
| 10 | Trivy | `$K get vulnerabilityreports` に §2.6 の `pod-767f7c764c`・`pod-7596f8df9b`・`pod-6ccd6c447c` が無い。新しい share-manager の Pod の 2 つのレポートが、`longhorn-share-manager:v1.13.0` で作られる（スキャンは Pod の作成の後、数分〜十数分） |
| 11 | ノード | 8 台 Ready。Longhorn の Node 4 つが Ready・schedulable |
| 12 | 監視 | §4.3 の 2 つを止め、`FAIL` の数と時刻、`watch.log` の degraded・faulted の時刻を記録する |
| 13 | 片付け | `unset ADMIN_TOKEN`、`rm /tmp/lh-oldim-admin-token` |

`fs/h2` の data locality の rebuild が走ったときは、1 と 6 は rebuild の終わりの後に読み直して確かめる。

## 5. 止まる時間と影響（見込み）

本番の 4 つのボリュームで detach と attach を測ったことは無い。段 2 の drain では、Longhorn のボリュームを使う Pod がアタッチを待って 1〜2 分で起動した（`../k8s-upgrade/runbook-stage-2.md`）。イメージ（`docker-nfs-server:0.3.1`、`docker-sshd:0.4.0`、`xemle/home-gallery`）は、今の Pod のノードには取ってある。別のノードに載ると pull が要り、数十秒〜数分のびる。

| 段 | 止まるもの | 見込み | 中身 |
|---|---|---|---|
| A | `fs/data` の NFS と SSH | **2〜5 分** | Pod の停止（grace 30 秒）、detach（数十秒）、attach と Pod の起動（1〜2 分） |
| B | homegallery（tumblr、ero） | **5〜15 分** | homegallery の停止 → h2 の停止 → h2 の起動 → homegallery の起動。share-manager の Pod の作り直しを含む |
| B | `fs/h2` の NFS と SSH | **3〜8 分**（homegallery の中に入る） | h2 の停止から、h2 の Pod の起動と NFSv4 の grace（90 秒ほど）まで |
| 段 A と B の間 | — | 段 A の確かめ（5〜10 分） | |

全体で 30 分〜1 時間（確かめを含む）。

止まる間に使えないもの:

- **段 A**: `data.fs.svc` の NFS（`fs/data-restore` の I/O が止まる。oeilvert の `/home/yuanying/shared/data` の automount もアクセスすれば待たされる）、`data.fs.svc` の SSH
- **段 B**:
  - homegallery の tumblr・ero（Pod が 0）。homegallery を外に出す Ingress は無い（§2.4）。`homegallery/api` は動く
  - `h2.fs.svc` の NFS: **aphrael（`h.iwaco.pink`）と `comics-webdav`（`comics-webdav.iwaco.pink`）の NFS の I/O が止まる**（Pod は動き続け、リクエストが待たされるか失敗する）。`fs/h2-restore` の I/O、oeilvert の `/home/yuanying/shared/h`
  - `h2-sshd`（LB、`[2405:6580:6740:ac01:ace::131]:3222`）と `h2.fs.svc` の SSH
- 止まらないもの: `fs/sites`（`www.fraction.jp`、`sites-2`）、ほかの 13 本のボリューム、Prometheus（`prometheus-…-0` は chirico の v1.13.0 の instance-manager にいて、この作業で動かない）

短時間の障害はユーザーの方針で許容されている（2026-10-19）。この作業の止まる時間は、ワークロードを止める分だけ、段の更新より長い。

## 6. 止める条件

次のどれかになったら、その場で止めて報告する。止めた後の対処はユーザーが決める（§0）。**データの安全（faulted を避けること）を最優先にする。** 強制削除、強制 detach、iscsid の再起動、同じ操作の繰り返しはしない。

| 条件 | 見方 | 止めた後に考えること（ユーザーが決める） |
|---|---|---|
| **Pod が消えない** | `scale --replicas=0` の後 120 秒で Pod が残る（Terminating のまま） | `kubectl describe pod`、kubelet のログ（NFS の umount で止まっていないか）。強制削除はしない（kubelet がボリュームを離していないまま、Longhorn が detach に進みうる） |
| **detach しない** | 300 秒で `detached` にならない（`detaching`・`attached` のまま） | Longhorn の VolumeAttachment の ticket（`$K get volumeattachments.longhorn.io <volume> -o yaml`）、K8s の VolumeAttachment、longhorn-manager のログ。ワークロードを戻せば attached に戻る見込み |
| **faulted** | どれかのボリュームの robustness が faulted（`watch.log`、`vol_state`） | 戻さずに止める。replica の状態、`auto-salvage` の動き、instance-manager のログ。salvage はユーザーが決める |
| **attach できない** | `scale` で戻した後、300 秒で attached にならない。Pod が `ContainerCreating` のまま（`FailedAttachVolume`、`FailedMount`）。エンジンが `Failed to init frontend` で落ちる | 同じ形を繰り返さない（Longhorn が Pod を消して作り直すのを続けさせない。必要なら一度 0 に戻す）。iSCSI のセッション、エンジンのログ |
| **degraded のまま戻らない** | degraded が 10 分を超える、replica が `error` のまま、`failedAt` が付く | rebuild の様子。data locality の rebuild（`fs/h2`）の間の healthy とは別 |
| **エンジンが古い instance-manager で起動する** | 戻した後の `instanceManagerName` が `$OLD_IM` | 起きない見込み（Longhorn は新しいエンジンを既定の instance-manager で起動する）。起きたらそのまま動かして止める |
| **iSCSI の古いセッション** | detach の後、chirico にそのボリュームの iqn のセッションが残る。今動いている instance-manager の IP でない portal のセッションが現れる | **iscsid を再起動しない。** 残ったセッションが今のもの（10.244.8.216 の、まだアタッチされたボリューム）でないことを確かめ、そのセッションの sid だけを logout する（`sudo iscsiadm -m session -r <sid> -u`。porkadot-dev の `docs/longhorn/iscsi-stale-sessions.md` §4.2 の形）。**`docs/k8s-upgrade/tools/iscsi-logout-stale.sh` は使わない**（drain したノードのためのもので、keep の IP を 1 つしか渡せず、段 A の後の chirico では、まだ使っている 10.244.8.216 のセッションも logout してしまう） |
| **iscsid の PID が変わった** | 4 台のどれかの MainPID が §4.1 と違う | 作業の外の再起動（needrestart など）。どのエンジンが `older-than-iscsid` になったかを記録する |
| **I/O エラー** | Longhorn を使う Pod のログ、ノードの `dmesg` に `Buffer I/O error`・`blk_update_request` | — |
| **share-manager が動かない** | 戻した後、share-manager が `running` にならない、Pod が v1.13.0 で起動しない、RWX の Pod の NFS のマウントが止まる | share-manager の Pod のログ、longhorn-manager のログ（recovery backend）、NetworkPolicy（`longhorn-recovery-backend`） |
| **NFS の頼り手が戻らない** | h2 を戻してから 5 分たっても、aphrael・comics の service proxy や `h2-restore` が答えない | Pod の再起動はユーザーが決める（hard マウントのつなぎ直しが効かなかった場合） |
| **想定外の再起動** | 作り直したもの（§4.6 の 8）のほかの Pod の UID・restartCount が変わる | — |
| **古い instance-manager が消えない** | 段 B の後、`$OLD_IM` の中のエンジンが 0 なのに 10 分たっても残る | データの危険は無い。ワークロードを戻してから報告する。手で消すかはユーザーが決める |

## 7. ロールバック

この作業に「元に戻す」はほとんど要らない。変えるのは 4 つの Deployment の `replicas` だけで、Longhorn の設定・manifest・エンジンの版は変えない。

| どこまで進んだか | 戻し方 |
|---|---|
| §4.4 の 2・§4.5 の 2〜3 で止めた（detach の途中・前） | ワークロードを §4.1 の値に戻す（`kadm -n <ns> scale deploy/<name> --replicas=<値>`）。ボリュームは、古い instance-manager がまだあれば、そこではなく新しい instance-manager でアタッチされる（それで構わない） |
| detach の後に止めた | 同じ。止めた理由がボリュームそのもの（faulted、attach できない）なら、戻さずに止めたまま報告する（§6） |
| 段 A の後に、段 B へ進まないと決めた | 段 A の結果のまま置いてよい（`fs/data` は v1.13.0 の instance-manager、ほかの 3 本は古い instance-manager のまま）。段 B は別の日にこの手順書で流す |

- **古い instance-manager（v1.11.2）には戻せない**し、戻す必要も無い。エンジンのバイナリは前から v1.13.0 で、変わるのはエンジンのプロセスの居場所だけ
- データの戻し: detach と attach は replica のデータに触らない。万一データが壊れたときは、fs の 2 本は braque の rsync のコピー（`192.168.1.131:/data`・`/h`。§2.7 の時間帯なら、その日のもの）から、Longhorn の新しいボリュームに戻すことになる。どれも runbook の外の操作で、ユーザーと決める。homegallery の 2 本はアプリの側のバックアップを確かめていない（§9 の 1）
- Longhorn のバックアップ（BackupTarget `default`、braque）には、今この 4 本のバックアップは無い（2026-10-21 に消した。`results/upgrade-1.12-1.13/cleanup.md`）

## 8. 記録

`docs/longhorn/results/old-instance-manager.md` に残す。時刻（UTC）、§4.1 の結果、各 `scale` の時刻、Pod が消えた時刻、detached・attached になった時刻、Pod が載ったノード、エンジンの instance-manager、古い instance-manager が消えた時刻、iSCSI のセッションの前後、止まっていた時間（`probe.log` の `FAIL` の始めと終わり）、`fs/h2` の rebuild の有無と時間、Trivy のレポートの前後、手順書との差を書く。

`lh-state.sh` の出力、`node-*.txt`、`watch.log`、`probe.log`、`replicas-before.txt`、`pods-*.txt`、`trivy-before.txt` は、タスクディレクトリの `notes/longhorn-old-im/` に置き、要点を記録に写す。手順書と実際の作業の差は、作業の後にこの手順書に反映する（記録の PR で）。

## 9. 決めること（開始の承認のときに）

1. **homegallery の 2 本（`tumblr-data`、`ero-data`）のバックアップ**: 推奨は取らない（§3 の 5。detach と attach はデータに触らない）。アプリの側のバックアップがあるかを確かめていない。心配なら、§4.5 の前に Longhorn のスナップショットとバックアップを 2 本だけ取る形にできる（`runbook-upgrade-1.12-1.13.md` §4.5 の形。小さいので数分）
2. **段 A と段 B を同じ日に続けるか**: 推奨は続ける（段 A の確かめが全部合格したら、そのまま段 B）。段 A の結果を見てから別の日にもできる（§7）
3. **NFS の頼り手（aphrael、comics、restore）を止めるか**: 推奨は止めない（§3 の 8）
