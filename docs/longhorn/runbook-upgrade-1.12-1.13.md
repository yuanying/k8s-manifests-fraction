# Longhorn を 1.11.2 から 1.12.1、1.13.0 へ上げる手順書（本番 `fraction`）

本番クラスタ `fraction`（K8s v1.34.12）の Longhorn を **v1.11.2 → v1.12.1 → v1.13.0** と 2 回上げる手順。
計画は `../k8s-upgrade/plan.md`（以下「計画」）の §4（経路 A。§4.3 の表と注、§4.4）で、段 5 の後に行う（`../k8s-upgrade/runbook-stage-5.md` §10）。

| | 今 | 1 回目の後 | 2 回目の後 |
|---|---|---|---|
| Longhorn（manager・engine・instance-manager・share-manager・UI） | v1.11.2 | **v1.12.1** | **v1.13.0** |
| 要求する K8s | ≥ 1.25 | ≥ 1.25 | **≥ 1.34**（csi-provisioner v6.3.0） |
| CSI のサイドカー | `*-20260428`（attacher v4.11.0 など） | attacher v4.12.0、provisioner v5.3.0、resizer v2.2.1、snapshotter v8.6.0、registrar v2.17.0、livenessprobe v2.19.0 | attacher v4.13.0、**provisioner v6.3.0**、registrar v2.18.0、livenessprobe v2.20.0（専用の ServiceAccount で動く） |
| 内部の NetworkPolicy | 無い | **6 つ**（ingress だけ） | 6 つ（`instance-manager` に 3260 を足したもの） |
| `longhorn-global-manager` | 無い | 無い | **Deployment、replicas 3** |
| iscsid の再起動の後に iSCSI を logout できない問題（計画 §4.4） | 直っていない | **直る**（新しいエンジンのイメージで動くエンジンから） | 直っている |
| `/etc/apt/apt.conf.d/51fraction-hold-open-iscsi`（Longhorn のノード 4 台） | ある | **消す**（§5.3） | 無い |

manifest は fleet-infra の `infrastructure/longhorn/`（`scripts/update-longhorn.sh` で取ってきた上流の `deploy/longhorn.yaml` と、prod overlay）。本番には Flux が動いておらず、手で `kubectl apply -k infrastructure/longhorn/prod/` する。

- **1 回目**: fleet-infra の PR（ブランチ `fleet-longhorn-1-12-1`。`MANIFEST_VER` 1.12.1 と、prod overlay の NetworkPolicy の直し）をマージした main で流す
- **2 回目**: 1.13.0 の manifest の fleet-infra の PR（1 回目の後に出す。この手順書の時点ではまだ無い）をマージした main で流す

この 2 回は dev クラスタ（porkadot-dev、context `test`、K8s v1.34.12）で先に通してある（2026-10-20）。記録は porkadot-dev の `docs/longhorn/upgrade-1.12-1.13.md`（以下「dev の記録」。porkadot-dev#15、`feadd42`）。dev で分かったことは次のとおり。

- 2 回とも書き込みを止めずに通り、データは失われず、I/O エラーも書き込む Pod の再起動も無かった。manifest の apply から全 Pod が揃うまで 3〜4 分、エンジンの live upgrade は 1 本 5 秒（detached は 2 秒）
- **本番の prod overlay のまま apply すると、1.12.1 から入る NetworkPolicy の selector に `commonLabels` の `region: fraction` が入り、longhorn-csi-plugin（`region` を持たない）から longhorn-manager への通信が止まる**（dev の結論の 1）。fleet-infra の PR で、NetworkPolicy の selector に `region` が入らないように直す（§1.4）。本番の Pod の label を読み、csi-plugin・instance-manager・share-manager が `region` を持たないことを確かめた（§2.4）
- **manager の更新の直後、新しい instance-manager のイメージ（約 0.5 GB）の pull と重なって、replica が 8 秒の timeout で落ち、degraded になった**（2 回目。約 2 分で自動の rebuild で戻った。dev の結論の 2）。本番の replica 1 のボリューム（Prometheus の 2 本）で同じことが起きると faulted になる。そこで、apply の前に新しいイメージを Longhorn のノードに pull しておき（§4.6）、Prometheus を apply の間止める（§4.7）
- **iscsid の直しは、live upgrade したエンジンにも効く**（dev の結論の 3）。全ボリュームのエンジンが 1.12.1 になった時点で、open-iscsi の hold を消してよい（§5.3）
- **live upgrade の後も、エンジンは detach するまで古い instance-manager の Pod の中で動き続ける**（dev の結論の 4。上流の文書どおり）。replica は新しい instance-manager に移る
- **ロールバックはできない**（ダウングレード防止）。戻り道は事前のバックアップだけ（§8）。dev には BackupTarget が無いので、バックアップは dev で取っていない

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **バックアップ**（Snapshot・Backup・SystemBackup の CR を作る形。§4.5）。dev には BackupTarget が無い
- **イメージの事前 pull**（§4.6）。dev では 2 回目の後に気づいたので試していない
- **prod overlay の直しの後の NetworkPolicy が実際に効く形**（instance-manager・longhorn-manager の Pod を選ぶ）での CSI の provision・attach と RWX。dev は base の overlay（`region` を足さない）で入れたので、selector の形は同じになる。cnidaria が NetworkPolicy を enforce するのも dev と同じ
- **RWX のボリューム**（`homegallery/tumblr-data`・`ero-data`。share-manager と recovery backend）。dev には RWX のボリュームが無かった
- **古い形式の名前のエンジン**（`-e-<8 桁>`。本番は 4 つ。§2.7）。dev には無かった
- **2 世代前の instance-manager が残る形**（1 回目の v1.11.2 の instance-manager にエンジンが残ったまま、2 回目の manager を入れる）。dev は 1 回目の後に detach で片付けた（§3 の 9）
- 本番のボリュームの数と大きさ（17 本、`fs/h2` 300 GiB など。dev は 1 GiB の 4 本）

## 0. 役割と約束ごと

- **承認の節目は 2 つ**（計画 §9.1「Longhorn の各更新の前（`kubectl diff` と `--dry-run=server` を見せてから）」）。この手順書では ✋✋ を付けた。
  - ✋✋ **1 回目（1.12.1）の開始**: fleet-infra の PR のマージ、§4.1 の事前の確認、§4.2 の diff と dry-run、§4.5 のバックアップの取り方、§4.6 の事前 pull、§4.7 で Prometheus を止めること、§8 のロールバックの形（apply の後は戻せないこと）を示してから、§4.5 のバックアップを取る前
  - ✋✋ **2 回目（1.13.0）の開始**: 1 回目の完了の確認（§4.12、§5.4）、1.13.0 の fleet-infra の PR のマージ、§4.1・§4.2 と §6 の 1.13.0 に固有のことを示してから、§4.5 のバックアップを取る前
- **節目の間の手順は、ユーザーに知らせるだけで進めてよい。** この手順書で ✋ を付けた操作（バックアップ、事前 pull、Prometheus の停止と再開、apply、`pvcheck.sh`、エンジンの更新、古い engine image の削除、open-iscsi の hold の削除）は、知らせてから行う。1 つずつ承認を取るものではない。
- **runbook から外れる操作（§7 で止めた後の対処、NetworkPolicy の削除、ワークロードの再起動、replica の数の変更、バックアップからの戻し）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認は、知らせずに行ってよい。時刻はすべて UTC で記録する。

## 1. 前提

### 1.1 段 5 が終わっていること

- 段 5 の完了の確認が `../k8s-upgrade/results/stage-5/summary.md` に残っている。8 台が v1.34.12、etcd 3.6.15
- 段 5 の後、1 日ほど様子を見た（計画 §9.6。`runbook-stage-5.md` §10）。ユーザーは 2026-10-20 に「今からでもいい」とした（タスクの STATE）
- K8s 1.34 は 1.12（≥ 1.25）と 1.13（≥ 1.34）の要件に入る

### 1.2 kubeconfig の運用

確認は `kubectl --context fraction`（`fraction-auditor`、read-only）で行う。`fraction-auditor` は `kubectl diff` と `--dry-run=server` も流せない（patch の権限が無い。2026-10-20 に `auth can-i patch daemonsets -n longhorn-system` が `no`）。

変更系と diff・dry-run は `infra-admin` の短命なトークンで行う（段の手順書と同じ。`runbook-stage-1.md` §1.2）。1 回ごとに 3 時間の期限で発行し、作業端末のモード 600 のファイル（`/tmp/lh-upg-admin-token`）に置き、使い終わったら破棄する（`unset ADMIN_TOKEN` とファイルの削除）。以下、変更系のコマンドを `kubectl-admin` と書く（`kubectl --context fraction --token="$ADMIN_TOKEN"` のこと）。

```sh
kubectl --context fraction create token infra-admin -n kube-system --duration=3h > /tmp/lh-upg-admin-token
chmod 600 /tmp/lh-upg-admin-token
ADMIN_TOKEN=$(cat /tmp/lh-upg-admin-token)
kubectl --context fraction --token="$ADMIN_TOKEN" auth can-i patch volumes.longhorn.io -n longhorn-system   # yes
```

トークンを使うのは、§4.2 の diff と dry-run、§4.5 のバックアップ、§4.7 の Prometheus、§4.8 の apply、§4.9 の `pvcheck.sh`、§4.10 のエンジンの更新、§4.11 の engine image の削除だけ。

### 1.3 SSH

Longhorn のノードは worker の 4 台（pablo 192.168.1.134、duchamp .135、chirico .83、oeilvert .82）。`ssh yuanying@<IP>` で入り、パスワードなしで sudo できる。サンドボックスの中で通る（2026-10-20 にこの手順書を書いたとき、4 台と braque に読み取りで入った）。

SSH を使うのは、`iscsiadm -m session` などの読み取り、§4.6 の事前 pull、§5.3 の hold の削除。braque（.131）と control-plane には Longhorn の Pod が載らない（taint。§2.4）。

### 1.4 fleet-infra の manifest

各回で、その回の fleet-infra の PR をマージした main を、作業端末の `/tmp` に clone して使う（元の clone の `.git` への書き込みはサンドボックスに拒否されるので、`git worktree add` や `git fetch` はしない。`runbook-stage-5.md` §7.1 と同じ）。

```sh
F=/tmp/fleet-infra-lh-<回>          # 例 /tmp/fleet-infra-lh-1121
git clone git@github.com:yuanying/fleet-infra.git $F
git -C $F log --oneline -1          # その回の PR のマージ commit であること
grep '^MANIFEST_VER=' $F/scripts/update-longhorn.sh                         # 1.12.1（2 回目は 1.13.0）
kubectl kustomize $F/infrastructure/longhorn/prod/ > /tmp/lh-prod-<回>.yaml
```

render した manifest で次を確かめる（読み取り。作業端末だけで流れる）。

```sh
R=/tmp/lh-prod-<回>.yaml
# 1. イメージの版（その回の版だけであること）
grep -oE 'docker\.io/longhornio/[a-z0-9-]+:[A-Za-z0-9._-]+' $R | sort -u
# 2. NetworkPolicy の selector に region が無い（6 行とも false）
yq -N 'select(.kind == "NetworkPolicy") | .metadata.name + " selector-region=" + (([.spec.podSelector, .spec.ingress[]?.from[]?.podSelector] | tojson | test("region")) | tostring)' $R
# 3. DaemonSet・Deployment・Service の selector は今の本番と同じ（region: fraction がある）
yq -N 'select(.kind == "DaemonSet" or .kind == "Deployment") | .kind + "/" + .metadata.name + " " + (.spec.selector.matchLabels.region // "-")' $R
yq -N 'select(.kind == "Service") | .metadata.name + " " + (.spec.selector.region // "-")' $R
```

- 2 が 1 行でも `true` なら止める（fleet-infra の直しが入っていない）
- 3 は、`longhorn-manager`（DaemonSet）、`longhorn-driver-deployer`・`longhorn-ui`（Deployment。2 回目は `longhorn-global-manager` も）、Service の `longhorn-admission-webhook`・`longhorn-backend`・`longhorn-frontend`・`longhorn-recovery-backend` が `fraction`。今の本番の DaemonSet・Deployment の `spec.selector` は immutable で、`region: fraction` を持っている（2026-10-20 の読み取り）。違えば apply が通らないので止める
- 2026-10-20 に、fleet-infra のブランチ `fleet-longhorn-1-12-1`（`e13164e`。PR の前）を render して、1〜3 がこのとおりになることを確かめた（NetworkPolicy の 6 つとも `false`、DaemonSet・Deployment・Service は `fraction`）
- fleet-infra の直しの形（`commonLabels` を `labels` の `fields` 指定に替える、など）に依らず、この render の結果で確かめる

### 1.5 入れる版を確かめる

作業の当日、各回の前に確かめ直す（読み取り）。

```sh
gh api repos/longhorn/longhorn/releases --jq '.[] | select(.tag_name|test("^v1\\.1[23]\\.")) | [.tag_name,.prerelease,.published_at] | @tsv' | head
```

- 2026-10-20 の時点: 1.12 は **v1.12.1**（2026-08-14）が最新で、v1.12.2 は rc1（2026-10-15）まで。1.13 は **v1.13.0**（2026-09-29）
- 計画 §4.3 は「その時点の 1.12 の最新パッチ」とする。**当日に v1.12.2 が正式に出ていたら、ここで止めて報告する**（fleet-infra の manifest を 1.12.2 で作り直すかをユーザーが決める。dev の記録 §5.5 の見込みでは、差は `instance-manager` の NetworkPolicy に 3260 を足すことと修正で、手順は変わらない）。1.13 も同じ
- 本番の Longhorn の `latest-longhorn-version` の設定は v1.12.1、`stable-longhorn-versions` に v1.12.1 がある（2026-10-20）

### 1.6 確認に使うスクリプト

この手順書で足したもの（`tools/`）:

| スクリプト | 書き込み | 中身 |
|---|---|---|
| `tools/lh-state.sh <dir>` | しない | ボリューム・replica・エンジン・instance-manager・engine image・Pod（UID・restart）・Setting・CRD の `storedVersions`・NetworkPolicy の selector・orphan などを TSV に保存し、要約を出す。前と後のディレクトリを `diff` で比べる |
| `tools/lh-watch.sh` | しない | 2 秒ごとに読み、変わったものだけを出す（ボリュームの state/robustness・ノード・エンジンの版、replica の状態の数、instance-manager の版と状態の数、Ready でない Pod） |
| `tools/engine-upgrade.sh <volume> <image> [--dry-run]` | **する**（Volume の `spec.image`） | 1 本のエンジンを更新して、終わるまで待つ。attached なら healthy、detached ならそのまま、であることを確かめてから patch し、`status.currentImage` が新しい版になり、Replica の CR の数が `numberOfReplicas` に戻り、attached なら healthy に戻るまで待つ。faulted になったら止まる（rc 1）。600 秒で timeout（rc 2） |
| `tools/pvcheck.sh` と `tools/pvcheck.yaml` | **する**（一時的な名前空間 `lh-pvcheck`） | silver（replica 2）の RWO と RWX の PVC を作り、ノードを指定した Pod で両方に書いて md5 を確かめ、別のノードに移して確かめ直し、名前空間ごと消す。`up`・`move`・`status`・`down`・`dry-run` |

- `engine-upgrade.sh` は、偽の `kubectl` で 11 の場合（live、offline、degraded を断る、faulted で止まる、読み取りの一時的な失敗（1 回と 2 回続けて）、dry-run、同じ版、不明な引数、無い engine image、timeout）を確かめた。本番では、配られていない engine image（v1.12.1）を渡して patch の前で断ることだけを確かめた（読み取りだけ）
- `lh-state.sh`・`lh-watch.sh` は本番で流した（2026-10-20。§2 の値はその出力）
- `pvcheck.sh dry-run` は本番で通した（`--dry-run=client`）。`up` 以降は流していない

ほかに使うもの: `../k8s-upgrade/tools/storage-versions.sh`（CRD の `storedVersions`。`crds.tsv`）、`../k8s-upgrade/tools/node-state.sh`（iscsid の PID と iSCSI のセッション）、cnidaria の手順書の `check-apps.sh`・`netcheck.sh`（`runbook-stage-1.md` §1.8）。

## 2. 本番の今（2026-10-20 12:4xZ の読み取り）

作業の当日に、§4.1 で読み直す。

### 2.1 Longhorn

- v1.11.2（manager、engine image `ei-c9fa6d45`、instance-manager 4 つ、UI 2、driver-deployer 1、CSI のサイドカー 3 つずつ、csi-plugin 4、engine-image 4、share-manager 2）。`longhorn-system` の Pod は 33 個で、Running でないものは 0
- instance-manager: pablo 10.244.4.131、chirico 10.244.8.216、duchamp 10.244.5.112、oeilvert 10.244.7.116（どれも v1.11.2、running）
- Longhorn の Node は 4 台（chirico、duchamp、oeilvert、pablo）。どれも Ready・schedulable
- CRD は 22 個で、`status.storedVersions` はどれも `["v1beta2"]`
- NetworkPolicy は `longhorn-system` に無い（0 個）
- orphan 0、backing image 0、recurring job 0
- **BackupTarget** `default`: `nfs://192.168.1.131:/backups/longhorn`、`available: true`、`pollInterval` 5m。**ボリュームのバックアップは 0 個、system backup も 0 個**（BackupVolume は 2022 年の消えたボリュームの 1 つだけで、中のバックアップは無い）。スナップショットの CR は 20 個で、ユーザーが作ったもの（`userCreated`）は無い（rebuild のときに Longhorn が作って `markRemoved` になったもの 17、`natsumi-myao` の 1、消えたボリュームの 2 つは `lost track of the corresponding snapshot info inside volume engine`）
- 設定（変えない）: `concurrent-replica-rebuild-per-node-limit` 5、`replica-auto-balance` disabled、`node-drain-policy` block-if-contains-last-replica、`default-data-locality` best-effort、`replica-replenishment-wait-interval` 6000、`engine-replica-timeout` `{"v1":"8"}`、`concurrent-automatic-engine-upgrade-per-node-limit` 0（エンジンの自動更新は無効）、`auto-salvage` true、`system-managed-pods-image-pull-policy` if-not-present、`orphan-resource-auto-deletion` 空、`backup-concurrent-limit` 2、`backup-compression-method` lz4、`taint-toleration` 空

### 2.2 ボリューム（17 本）

| ボリューム | 名前空間/PVC | 大きさ | 実使用（GiB） | replica | アタッチ先 | アクセス |
|---|---|---|---|---|---|---|
| `pvc-29c27b73-…` | fraction-agents/data-calendar-keeper-0 | 1Gi | 0.0 | 2 | chirico | RWO |
| `pvc-984a7d6b-…` | fraction-agents/data-web-researcher-0 | 1Gi | 0.0 | 2 | chirico | RWO |
| `pvc-bf2d7ef2-…` | fraction-agents/data-news-agent-0 | 1Gi | 0.0 | 2 | chirico | RWO |
| `pvc-aee2ec0e-…` | fraction-agents/data-gmail-agent-0 | 1Gi | 0.0 | 2 | oeilvert | RWO |
| `pvc-092a74ed-…` | fraction-agents/data-wiki-keeper-0 | 1Gi | 0.6 | 2 | oeilvert | RWO |
| `pvc-9aae4b86-…` | fraction-agents/data-deep-researcher-0 | 20Gi | 0.5 | 2 | chirico | RWO |
| `pvc-3a665d04-…` | natsumi/natsumi-myao | 5Gi | 0.5 | 2 | chirico | RWO |
| `pvc-e224cffa-…` | natsumi/natsumi-aki | 5Gi | 0.6 | 2 | oeilvert | RWO |
| `pvc-6b8f51fa-…` | natsumi/natsumi | 10Gi | 1.0 | 2 | oeilvert | RWO |
| `pvc-0b28d049-…` | homegallery/tumblr-data | 8Gi | 4.9 | 2 | chirico（share-manager） | **RWX** |
| `pvc-baa41130-…` | homegallery/ero-data | 20Gi | 6.4 | 2 | chirico（share-manager） | **RWX** |
| `pvc-c6fbd833-…` | fs/sites | 20Gi | 6.6 | 2 | pablo | RWO |
| `pvc-1d94c3ed-…` | fs/data | 200Gi | 59.3 | 2 | chirico | RWO |
| `pvc-c4944b75-…` | fs/h2 | 300Gi | 161.8 | 2 | chirico | RWO |
| `pvc-625c8825-…` | monitoring/prometheus-kube-prometheus-db-prometheus-kube-prometheus-0 | 20Gi | 24.5 | **1**（bronze） | chirico | RWO |
| `pvc-99c35b80-…` | monitoring/prometheus-kube-prometheus-db-prometheus-kube-prometheus-1 | 20Gi | 25.1 | **1**（bronze） | oeilvert | RWO |
| `pvc-c9f006ad-…` | homegallery/cg-data | 16Gi | 11.9 | 2 | **detached**（以前から） | RWX |

- attached healthy 16、detached unknown 1（`homegallery/cg-data`。share-manager は stopped）。エンジンはどれも `docker.io/longhornio/longhorn-engine:v1.11.2`、frontend はどれも `blockdev`（live upgrade できる。上流の文書で live upgrade できないのは `iscsi` の frontend）、data engine はどれも v1、`backupTargetName` はどれも `default`
- アタッチ先: chirico 10、oeilvert 5、pablo 1、duchamp 0
- 実使用（`status.actualSize`。スナップショットを含む）の合計は約 304 GiB、attached の 16 本で約 292 GiB
- `fs/h2` と `fs/sites` は、その上の NFS サーバー（`h2.fs.svc`、`sites.fs.svc`）が `aphrael/aphrael-2`・`comics/comics-2`・`sites/sites-2` の PV を出している。この 2 本が止まると、それらの Pod も止まる
- replica 1 のボリュームは Prometheus の 2 本だけ。Prometheus（CR `monitoring/kube-prometheus`、Helm 管理、`replicas: 2`）の 2 つの Pod が 1 本ずつ使う（`prometheus-kube-prometheus-0` が chirico、`-1` が oeilvert で、replica もそれぞれ同じノード）

### 2.3 replica

- 33 個: running 30、stopped 3
- stopped の 3 つ: `homegallery/cg-data` の 2 つ（chirico、oeilvert。detached なので）と、**`fs/h2` の duchamp の `pvc-c4944b75-…-r-43fe8619`（`failedAt` 2026-10-19T09:36:03Z）**。後者は前からのもので、`fs/h2` は running の replica 2 つ（chirico、oeilvert）で healthy。`staleReplicaTimeout` は 2880 分なので、2026-10-21 09:36Z ごろに Longhorn が消す見込み（タスクの STATE の 2b）。§4.12 の「`failedAt` なし」は、この 1 つを除いて数える（消えていれば除く必要は無い）
- running の replica の数: chirico 10、duchamp 8、oeilvert 10、pablo 2

### 2.4 Pod の label と、ノードの taint

- `region: fraction` を持つのは、overlay の template から作る Pod（longhorn-manager 4、longhorn-ui 2、longhorn-driver-deployer 1）だけ。**longhorn-csi-plugin、CSI のサイドカー、instance-manager、engine-image、share-manager は持たない**（dev の記録 §2.3 の見立てのとおり）
- taint: control-plane 3 台は `node-role.kubernetes.io/master:NoSchedule`、braque は `unstable.cloud/storage:NoSchedule`。chirico・duchamp・oeilvert・pablo には taint が無い。**1.13.0 の `longhorn-global-manager`（toleration・nodeSelector なし、replicas 3）は、この 4 台のどれかに載る**

### 2.5 ノード（Longhorn の 4 台）

| ノード | iscsid の MainPID（起動） | Longhorn の iSCSI のセッション | `/` の空き（containerd） | `/var/lib/longhorn` |
|---|---|---|---|---|
| pablo | 1194943（2026-10-19 07:39:11） | 1（10.244.4.131） | 131G | 1.8T のうち 15G 使用 |
| duchamp | 663628（2026-10-19 23:33:45） | 0 | 110G | 1.8T のうち 241G 使用 |
| chirico | 4447（2026-10-19 09:17:30） | 10（10.244.8.216） | 312G | 1.8T のうち 419G 使用 |
| oeilvert | 6334（2026-10-19 09:04:34） | 5（10.244.7.116） | 74G | `/var/lib/longhorn` と `/var/lib/longhorn2` |

- セッションの portal は、どれもそのノードの今の instance-manager の IP（古いセッションは無い）
- 4 台とも `/etc/apt/apt.conf.d/51fraction-hold-open-iscsi`（`Unattended-Upgrade::Package-Blacklist` に `open-iscsi`・`libopeniscsiusr`）があり、open-iscsi は 2.1.9-3ubuntu5.5
- containerd に、`docker.io/longhornio/` の v1.11.2 のイメージがある（pablo・duchamp・chirico には v1.2.4 からの古い版も残っている）。v1.12.1・v1.13.0 のものは無い
- containerd にレジストリのミラーの設定は無い（`/etc/containerd/certs.d` が無い）。イメージは Docker Hub から直接取る
- ネットワークは 4 台と braque とも 1 GbE

### 2.6 braque の NFS（BackupTarget）

- BackupTarget の `/backups/longhorn` は、braque の nfsd（fleet-infra の `infrastructure/nfsd`）が出す `/export` の下（ZFS `tank1/export`）。空きは **9.4T**。`/export/backups/longhorn` は今 9 KB（`backupstore` だけ）
- braque の NFS を使うバックアップの CronJob の時間帯（UTC で 05:44 ごろ、07:53 ごろ、09:03 ごろ、20:30 ごろ、21:00 ごろ。計画 §9.6）は、ボリュームのバックアップと重ねない

### 2.7 古い形式の名前のエンジン

`-e-<8 桁>` の名前のエンジンが 4 つある（`fs/sites`、`fs/data`、`homegallery/tumblr-data`、`homegallery/ero-data`。2022 年に v1.2.4 が作ったもの。`gc-and-orphans.md` §2.1）。fleet-infra の `infrastructure/longhorn/CLAUDE.md` の事前の確認は、これを「v1.7.0 で問題が確認されたが v1.7.1 以降で修正済み」としている。本番はこの 4 つのまま v1.8〜v1.11 へ上げてきた。止める理由にはしないが、dev には無かった形なので、§4.10 でこの 4 つの更新を特に見る。

## 3. 決まっていること

| # | 内容 | 決定 | 理由・出典 |
|---|---|---|---|
| 1 | 版 | 1 回目 v1.12.1、2 回目 v1.13.0。当日に新しいパッチが正式に出ていたら止めて決める（§1.5） | 計画 §4.3 |
| 2 | 入れ方 | `kubectl apply -k infrastructure/longhorn/prod/`（client-side。今の本番のオブジェクトは `last-applied-configuration` を持つ） | fleet-infra の `CLAUDE.md`。dev で client-side の `--dry-run=server` が通った（最大の object は 13 KB の CRD） |
| 3 | バックアップ | 各回の apply の前に、attached の 16 本のボリュームのバックアップと、Longhorn の system backup を取る（§4.5）。`homegallery/cg-data`（detached）は取らない（下の注） | 計画 §4.1。上流の Manual Checks |
| 4 | 事前 pull | 各回の apply の前に、その回の Longhorn のイメージ 11 個を、Longhorn のノード 4 台で 1 台ずつ `crictl pull` する（§4.6） | dev の結論の 2 |
| 5 | replica 1 のボリューム（Prometheus の 2 本） | **apply の前に Prometheus を止め（CR の `replicas` を 0）、manager の rollout が済んで全部のボリュームが healthy になり、2 本のエンジンを detached のまま更新してから戻す**（§4.7） | 下の §3.1 |
| 6 | ほかのボリューム | 止めない。apply の後に degraded になっても、faulted でなく、rebuild で戻るなら待つ | dev の記録 §5.2 の 6。短時間の障害は許容する（2026-10-19 のユーザーの方針） |
| 7 | NetworkPolicy | fleet-infra の直しで、6 つの selector に `region` を入れない（§1.4）。apply の後に `pvcheck.sh` で CSI の provision・attach・detach と RWX を確かめる（§4.9） | dev の結論の 1 |
| 8 | エンジンの更新 | 全ボリューム（detached を含む）を `engine-upgrade.sh` で 1 本ずつ。小さいものから、`fs/h2` を最後に（§4.10）。UI は使わない | 計画 §4.3、dev の記録 §3.3 |
| 9 | 古い instance-manager | 片付けない（ワークロードを止めて detach・アタッチし直すことはしない）。エンジンは古い instance-manager の中で新しい版のバイナリで動き、iscsid の直しも効く（dev の結論の 3・4）。古い instance-manager は、中のエンジンが detach で無くなったときに Longhorn が消す。2 回目の manager（1.13.0）も v1.11.2 の instance-manager を扱える（longhorn-manager v1.13.0 の `MinInstanceManagerAPIVersion` は 1 で、v1.11.2 の instance-manager の API の版は 7）。2 世代前が残る形は dev で確かめていないので、§6 で見る | dev の結論の 4、上流の KB「Some old instance manager pods are still running after upgrade」 |
| 10 | open-iscsi の hold | 1 回目で全ボリュームの `status.currentImage` が v1.12.1 になり、古いセッションが無いことを確かめたら、4 台の `51fraction-hold-open-iscsi` を消す（§5.3） | TASK.md の 2026-10-19 のユーザー指示、計画 §4.3、dev の結論の 3 |
| 11 | 古い engine image | その回のエンジンの更新が全部済み、`REFCOUNT` が 0 になったら消す（§4.11） | dev の記録 §3.3 |
| 12 | Longhorn の設定 | 変えない。版が足す設定は既定のまま | dev の記録 §2 |
| 13 | 1.13.0 の `longhorn-csi-secret-bind`（CSI のサイドカーにクラスタ全体の Secret の `get`） | 既定のまま入れる。外すかは 2 回目の後に別に決める（§6、§11） | 上流の Important Notes。fleet-infra の StorageClass は provisioner の secret を使っていない |
| 14 | 1 回目と 2 回目の間 | 必須の間隔は無い。1 回目の完了の確認（§4.12）が全部合格し、2 回目の承認を取ってから | 計画 §4.3 |
| 15 | 時間帯 | いつでもよい。§4.5 のバックアップは braque の CronJob の時間帯（§2.6）を避ける | 計画 §9.6 |

**`homegallery/cg-data` のバックアップを取らない理由**: detached のボリュームのスナップショットは、Longhorn がボリュームを一時的にアタッチして取る。`cg-data` は 2024 年から detached（share-manager stopped）で、今アタッチすると何が起きるかを確かめていない。エンジンの更新は detached のまま `spec.image` を変えるだけで、データに触らない（dev の記録 §3.3）。残したいならユーザーが決める（その場合は §4.5 の対象に足す）。

### 3.1 replica 1 のボリュームを止める理由

dev の 2 回目では、manager の apply の約 2 分後、新しい instance-manager のイメージの pull・展開と重なった replica が `R/W Timeout. No response received in 8s` で落ちた（replica 3 のボリュームが degraded になり、自動の rebuild で 2 分で戻った）。replica 1 のボリュームで同じことが起きると、残る replica が無いので faulted になる。`auto-salvage` が直すことが多いが、確かではない。

| 案 | 判断 |
|---|---|
| **A. apply の間、Prometheus を止める（推奨）** | Prometheus の 2 本が detached になり、manager の更新と instance-manager の入れ替わりの間に I/O が無い。エンジンは detached のまま更新でき（2 秒）、再開のときに新しい instance-manager でアタッチされる。代わりに、止めている間（見込み 10〜20 分）のメトリクスが 2 つの Prometheus の両方で欠ける。短時間の障害は許容する（ユーザーの方針） |
| B. 止めずに、事前 pull だけに頼る | 事前 pull は dev で試していない（§4.6）。pull が timeout の唯一の原因だったかも確かめていない（dev の 2 vCPU の VM の負荷とも見ている） |
| C. replica を一時的に 2 にする | 25 GiB ずつの rebuild が 2 回、元に戻すときの replica の削除も要り、Longhorn の状態を余計に動かす。どのノードに 2 つ目を置くかも Longhorn 任せになる |

Prometheus 2 つを同時に止めるのは、どちらも replica 1 で、どちらの replica も apply の影響を受けるため（chirico と oeilvert）。Alertmanager は Longhorn を使わない（PVC が無い）ので止めない。

## 4. 各回の手順

1 回目と 2 回目は同じ形で流す。`<版>` は 1 回目が `v1.12.1`、2 回目が `v1.13.0`、`<前の版>` は 1 回目が `v1.11.2`、2 回目が `v1.12.1`。回に固有のことは §5（1 回目）と §6（2 回目）にある。

### 4.1 事前の確認（読み取り）

```sh
D=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/longhorn-upgrade/<版>
mkdir -p $D
T=docs/longhorn/tools
KUBECTL="kubectl --context fraction" $T/lh-state.sh $D/before
K="kubectl --context fraction -n longhorn-system"
```

| # | 確認 | 合格基準 |
|---|---|---|
| 1 | Longhorn の版 | `current-longhorn-version` の設定が `<前の版>`。`longhorn-system` の Pod の image が `<前の版>`（CSI のサイドカーはその版のもの）。1 回目の前は §2.1 と同じ |
| 2 | ボリューム | attached のものが全部 healthy、faulted が 0（`lh-state.sh` の要約の `volumes`）。detached は `homegallery/cg-data` だけ。2 回目の前は、全部の `status.currentImage` が v1.12.1 |
| 3 | replica | running でないものが §2.3 のものだけ。`failedAt` のあるものが §2.3 の 1 つだけ（消えていれば 0） |
| 4 | replica 1 のボリューム | `$K get volumes.longhorn.io -o json \| jq -r '.items[] \| select(.spec.numberOfReplicas == 1) \| .metadata.name + " " + .status.kubernetesStatus.namespace + "/" + .status.kubernetesStatus.pvcName'` が Prometheus の 2 本だけ。増えていれば止めて、§4.7 の扱いをユーザーと決める |
| 5 | 古い形式の名前のエンジン | `$K get engines.longhorn.io -o name \| grep -cE '\-e\-[a-z0-9]{8}$'` が 4（§2.7） |
| 6 | backing image | 0（failed のものが無い） |
| 7 | orphan | 0。増えていたら `gc-and-orphans.md` §3.1 の調べ方で中身を確かめ、記録する（止めない） |
| 8 | CRD | `lh-state.sh` の `crds.tsv` がどれも `v1beta2`（1 回目の前は 22 個、2 回目の前は 25 個） |
| 9 | BackupTarget | `$K get backuptargets.longhorn.io default -o jsonpath='{.spec.backupTargetURL} {.status.available}'` が `nfs://192.168.1.131:/backups/longhorn true` |
| 10 | iSCSI | 4 台の `sudo iscsiadm -m session` の Longhorn のセッション（`iqn.2019-10.io.longhorn:`）の portal が、どれも今動いている instance-manager の IP（`lh-state.sh` の `instancemanagers.tsv`）。iscsid の MainPID を控える（`../k8s-upgrade/tools/node-state.sh` でもよい） |
| 11 | ノード | 8 台 Ready、どれも SchedulingDisabled でない。Longhorn のノード 4 台の `/` の空きが 10 GB 以上（1 回のイメージは 1 台約 1.2 GB） |
| 12 | Pod | クラスタ全体で Running / Completed 以外の Pod が無い（`check-apps.sh`）。全 Pod の名前・UID・restartCount を控える（`kubectl --context fraction get pods -A -o custom-columns=NS:.metadata.namespace,N:.metadata.name,UID:.metadata.uid,R:.status.containerStatuses[*].restartCount --no-headers \| sort > $D/pods-before.txt`） |
| 13 | manifest | §1.4 の render の確認が合格 |
| 14 | 版 | §1.5 |

ここで止めるのは、2・3・4・6・13・14 が合わないとき。

### 4.2 diff と dry-run（トークンを使うが、書き込まない）

```sh
cd $F    # §1.4 の clone
kubectl --context fraction --token="$ADMIN_TOKEN" diff -k infrastructure/longhorn/prod/ > $D/diff.txt; echo rc=$?   # 1（差分あり）
kubectl --context fraction --token="$ADMIN_TOKEN" apply -k infrastructure/longhorn/prod/ --dry-run=server > $D/dry-run.txt; echo rc=$?   # 0
grep -vE ' (unchanged|configured) \(server dry run\)$' $D/dry-run.txt   # created の行
```

- `diff` の rc は 1（差分あり）。rc が 1 より大きければ、差分ではなくエラーなので止める
- 差分が、fleet-infra の PR の本文の要点（その回の版のイメージ、足されるリソース、RBAC、CRD）と合うこと。1 回目は §5.1、2 回目は §6.1
- **消えるリソースは無い**（`kubectl apply` は prune しないので、manifest に無いものは残る）。`created` に出るのは、1 回目が CRD 3 つと NetworkPolicy 6 つ、2 回目が §6.1 のもの
- `--dry-run=server` は admission webhook（Longhorn の validator を含む）を通る。rc 0 で、エラーの行が無いこと
- Setting の CR は manifest に無い（`longhorn-default-setting` の ConfigMap だけ）。本番の設定の値が変わらないことは §4.12 で `settings.tsv` を比べて見る

### 4.3 承認 ✋✋

1 回目・2 回目のそれぞれで、§0 のとおり示して承認を取る。

### 4.4 監視を始める

承認の後、§4.5 の前から、§4.12 の確認が済むまで、作業端末で 2 つ流しておく（読み取り）。

```sh
# 1. Longhorn（2 秒ごと、変わったものだけ）
KUBECTL="kubectl --context fraction" docs/longhorn/tools/lh-watch.sh | tee -a $D/watch.log &
# 2. VIP、LoadBalancer、fs/sites を通る HTTP（1 秒ごと。段の手順書の監視に 1 つ足したもの）
n=0
while true; do
  t=$(date -u +%FT%TZ)
  curl -sk -m 2 -o /dev/null -w '%{http_code}' https://192.168.1.101:6443/livez | grep -q 200 || echo "$t FAIL vip"
  curl -s  -m 2 -o /dev/null http://192.168.1.200/ || echo "$t FAIL lb"
  c=$(curl -sk -m 3 -o /dev/null -w '%{http_code}' --resolve www.fraction.jp:443:192.168.1.200 https://www.fraction.jp/)
  [ "$c" = 200 ] || echo "$t FAIL sites $c"
  n=$((n+1)); (( n % 60 == 0 )) && echo "$t ok $n"
  sleep 1
done | tee -a $D/probe.log &
```

- `www.fraction.jp` は gated → `sites/sites` → `sites-2`（NFS の PV。`fs/sites` のボリュームの上の NFS サーバー）と通る。Longhorn のボリュームの I/O が止まると、ここが遅れるか失敗しうる。2026-10-20 は 200、10 ms ほど
- `lh-watch.sh` の出力の見方は §1.6。degraded・faulted、replica の `failed`・`error`、instance-manager の状態、Ready でない Pod の時刻を、各段階の記録に写す
- 止めるのは §4.12 の後（`kill %1 %2`）

### 4.5 バックアップ ✋

**ダウングレードはできないので、これが唯一の戻り道である**（§8）。attached の 16 本のボリュームのバックアップを取り、全部が Completed になってから Longhorn の system backup を取る。

dev では確かめていない（BackupTarget が無い）。形は、Longhorn の system backup の controller がボリュームのバックアップを作るときと同じ（longhorn-manager v1.11.2 の `controller/system_backup_controller.go` の `createVolumeSnapshot`・`createVolumeBackupFromSnapshot`。Snapshot の CR を `createSnapshot: true` で作り、`readyToUse` になったら、`backup-target`・`backup-volume` の label を付けた Backup の CR を `snapshotName` で作る）。**最初に 1 本（いちばん小さい `data-calendar-keeper-0`）だけ流して形を確かめてから、残りを流す。**

**見込みの時間**: 初回は全量で、実使用の合計は約 292 GiB（`fs/h2` 162 GiB、`fs/data` 59 GiB、Prometheus 25 GiB ずつ）。ノードと braque は 1 GbE なので、線速でも約 50 分、実際は 1〜2 時間の見込み（確かめていない）。lz4 で圧縮し、使っていないブロックは送らない。2 回目は差分なので短い。braque の空き（9.4T）は足りる。

1. 名前を決める（回ごとに別にする）。

   ```sh
   TAG=lh1121-pre        # 2 回目は lh1130-pre
   $K get volumes.longhorn.io -o json | jq -r '.items[] | select(.status.state == "attached") | .metadata.name' > $D/backup-volumes.txt
   wc -l < $D/backup-volumes.txt   # 16
   ```

2. ✋ スナップショットを作る（1 本で確かめてから残り）。

   ```sh
   snap() {   # <volume>
     printf '{"apiVersion":"longhorn.io/v1beta2","kind":"Snapshot","metadata":{"name":"%s","namespace":"longhorn-system"},"spec":{"volume":"%s","createSnapshot":true}}\n' \
       "$TAG-${1:4:8}" "$1" | kubectl --context fraction --token="$ADMIN_TOKEN" apply -f -
   }
   snap pvc-29c27b73-984a-4e28-8af8-9d6014ba174e
   $K get snapshots.longhorn.io $TAG-29c27b73 -o jsonpath='{.status.readyToUse} {.status.creationTime} {.status.size}{"\n"}'   # true ...
   ```

   - `${1:4:8}` はボリュームの名前の UUID の先頭 8 桁。今の 17 本で重ならない
   - スナップショットはエンジンが取る（ボリュームは止まらない）。`readyToUse` が `true` になるまで数秒

3. ✋ その 1 本のバックアップを作る。

   ```sh
   backup() {   # <volume>
     printf '{"apiVersion":"longhorn.io/v1beta2","kind":"Backup","metadata":{"name":"%s","namespace":"longhorn-system","labels":{"backup-target":"default","backup-volume":"%s"}},"spec":{"snapshotName":"%s"}}\n' \
       "$TAG-${1:4:8}" "$1" "$TAG-${1:4:8}" | kubectl --context fraction --token="$ADMIN_TOKEN" apply -f -
   }
   backup pvc-29c27b73-984a-4e28-8af8-9d6014ba174e
   $K get backups.longhorn.io $TAG-29c27b73 -o jsonpath='{.status.state} {.status.progress} {.status.url}{"\n"}'   # Completed 100 ...
   ```

   - `state` が `Completed`、`url` が `nfs://192.168.1.131:/backups/longhorn` の下、`$K get backupvolumes.longhorn.io` にそのボリュームが出ること
   - `Error` になったら、`status.error` と、そのボリュームのエンジンのある instance-manager のログを見て止める。ほかの手順に進まない

4. ✋ 残りの 15 本。小さいものはまとめて、大きい 4 本（`fs/data`、Prometheus の 2 本、`fs/h2`）は 1 本ずつ。

   ```sh
   # 小さい 11 本（1 で流した calendar-keeper と、大きい 4 本を除く）
   grep -v -e 29c27b73 -e 1d94c3ed -e 625c8825 -e 99c35b80 -e c4944b75 $D/backup-volumes.txt > $D/backup-small.txt
   wc -l < $D/backup-small.txt   # 11
   for v in $(cat $D/backup-small.txt); do snap $v; done
   $K get snapshots.longhorn.io | grep $TAG     # 全部 READYTOUSE true になったら
   for v in $(cat $D/backup-small.txt); do backup $v; done
   # 小さいものが全部 Completed になってから、大きいものを 1 本ずつ、この順に snap → backup → Completed を待つ
   #   pvc-625c8825-4571-43d8-9119-c006a4a48399（prometheus-0）
   #   pvc-99c35b80-7928-4b9b-a4ac-3afa8e7a7b05（prometheus-1）
   #   pvc-1d94c3ed-6b77-4077-83c1-cea28fb76628（fs/data）
   #   pvc-c4944b75-7ed0-4cf4-adce-bb5723993ff8（fs/h2）
   $K get backups.longhorn.io -l backup-target=default -o custom-columns=N:.metadata.name,VOL:.status.volumeName,STATE:.status.state,PROGRESS:.status.progress,SIZE:.status.size,ERR:.status.error | grep $TAG
   ```

   - 時刻と、各バックアップの所要時間・`size` を記録する
   - バックアップの間、ボリュームは止まらない。`lh-watch.sh` で degraded などが出ないことを見る

5. ✋ 16 本が全部 `Completed` になったら、system backup を取る。ボリュームのバックアップは 4 で取ったので、`volumeBackupPolicy` は `disabled` にする（`cg-data` に触らないため。§3 の注）。system restore は、各ボリュームの最新のバックアップから戻す（上流の文書「Restore Longhorn System」）。

   ```sh
   printf '{"apiVersion":"longhorn.io/v1beta2","kind":"SystemBackup","metadata":{"name":"%s","namespace":"longhorn-system"},"spec":{"volumeBackupPolicy":"disabled"}}\n' \
     "$TAG" | kubectl --context fraction --token="$ADMIN_TOKEN" apply -f -
   $K get systembackups.longhorn.io $TAG   # VERSION <前の版>、STATE Ready
   ```

   - `Ready` にならず `Error` なら、`status.conditions` を見て止める
   - system backup の中身は Longhorn の CRD・Setting・Volume・PV・PVC・StorageClass・DaemonSet・Deployment など（上流の文書）。Longhorn の Node は含まない

6. braque で、バックアップの置き場所の大きさを記録する（読み取り。`ssh yuanying@192.168.1.131 'sudo du -sh /export/backups/longhorn'`）。

- スナップショット（`$TAG-*`）は消さずに残す（§11）。バックアップは NFS に残るので、スナップショットを消してもバックアップは消えない。スナップショットは、それより後に書き換えたブロックの分だけ replica のディスクを使う
- 1 回目と 2 回目の両方のバックアップを、Longhorn の更新が終わって落ち着くまで消さない

### 4.6 新しいイメージを Longhorn のノードに先に pull する ✋

dev の結論の 2。apply の後に containerd が 1.2 GB 前後を pull・展開するのと、replica の I/O が重ならないようにする。dev では試していない。

1. pull するイメージを、§1.4 で render した manifest から引く（support-bundle-kit と、backing image が無いので backing-image-manager は除く）。

   ```sh
   IMGS=$(grep -oE 'docker\.io/longhornio/[a-z0-9-]+:[A-Za-z0-9._-]+' $R | sort -u | grep -vE '/(support-bundle-kit|backing-image-manager):' | xargs)
   echo "$IMGS" | wc -w   # 11
   ```

   1 回目（2026-10-20 に fleet-infra のブランチで render したもの）: `longhorn-manager`・`longhorn-engine`・`longhorn-instance-manager`・`longhorn-share-manager`・`longhorn-ui` の v1.12.1、`csi-attacher:v4.12.0`、`csi-provisioner:v5.3.0`、`csi-resizer:v2.2.1`、`csi-snapshotter:v8.6.0`、`csi-node-driver-registrar:v2.17.0`、`livenessprobe:v2.19.0`。`longhorn-global-manager`（2 回目）は `longhorn-manager` のイメージを使う。

2. ✋ 1 台ずつ流す（pablo → duchamp → oeilvert → chirico。アタッチされたボリュームの少ない順）。

   ```sh
   for ip in 192.168.1.134 192.168.1.135 192.168.1.82 192.168.1.83; do
     echo "== $ip $(date -u +%T)"
     ssh -n yuanying@$ip "for i in $IMGS; do sudo /opt/bin/crictl pull \$i >/dev/null && echo pulled \$i || echo FAIL \$i; done"
     echo "== $ip done $(date -u +%T)"
   done 2>&1 | tee $D/pull.log
   ```

   - 1 台の pull の間、`lh-watch.sh` で replica の `error`・ボリュームの degraded が出ないことを見る。出たら次の台へ進まずに止める（pull そのものも I/O を重くする）
   - `FAIL` が出たら、その台をもう一度流す。`429 Too Many Requests`（Docker Hub の匿名の pull の上限。100 回 / 6 時間 / IP）なら、時間をおいて流し直す。1 回の事前 pull は 44 回（11 × 4 台）
   - 全部の `pulled` を確かめる: `ssh -n yuanying@<ip> 'sudo /opt/bin/crictl images | grep -E "longhornio/(longhorn-|csi-|livenessprobe)" | grep -E "<版>|<その回の CSI の版>"'`

- Longhorn の Pod の `imagePullPolicy` は `IfNotPresent`（manifest と、設定 `system-managed-pods-image-pull-policy` の `if-not-present`）なので、apply の後は pull しない
- 古い版のイメージ（v1.11.2 など）は消さない（§11）

### 4.7 Prometheus を止める ✋

§3.1。apply の直前に行う（止めている時間を短くする）。

```sh
kubectl --context fraction -n monitoring get prometheus kube-prometheus -o jsonpath='{.spec.replicas}{"\n"}'   # 2（控える）
kubectl-admin -n monitoring patch prometheus kube-prometheus --type=merge -p '{"spec":{"replicas":0}}'
kubectl --context fraction -n monitoring get pods -l app.kubernetes.io/name=prometheus -w   # 2 つとも消えるまで
$K get volumes.longhorn.io pvc-625c8825-4571-43d8-9119-c006a4a48399 pvc-99c35b80-7928-4b9b-a4ac-3afa8e7a7b05   # 2 本とも detached
```

- Prometheus の CR は Helm（kube-prometheus-stack）が作ったものだが、本番に Flux は動いておらず、Helm がこの値を書き戻すことは無い。戻すのは §4.10 の 2
- prometheus-operator が StatefulSet を 0 にし、Pod が止まり、ボリュームが detach される。止まるまで（WAL を閉じる）数十秒
- 時刻（止めた時刻と、2 本が detached になった時刻）を記録する。この間のメトリクスが欠ける（Grafana、アラート）

### 4.8 apply と rollout ✋

```sh
cd $F
date -u +%FT%TZ
kubectl-admin apply -k infrastructure/longhorn/prod/ 2>&1 | tee $D/apply.txt; echo rc=$?
```

- rc 0。`created` と `configured` の行が §4.2 の dry-run と同じ
- **manager が版の飛ばしを拒んだら**（longhorn-manager が起動せず、ログに upgrade path のエラー）、§8.1 のとおり前の版の manifest を apply して戻せる。ほかのエラーで rc が 0 でなければ止める

rollout を待つ（dev は全部の Pod が揃うまで 3〜4 分）。

```sh
$K rollout status daemonset/longhorn-manager --timeout=10m
$K rollout status deployment/longhorn-driver-deployer --timeout=10m
$K rollout status deployment/longhorn-ui --timeout=10m
$K get pods -o wide -w     # 全部が Running・Ready になるまで
```

| # | 確認 | 合格基準 |
|---|---|---|
| 1 | manager | `longhorn-manager` の DaemonSet が 4 つとも `<版>`、Ready（`maxUnavailable: 100%` なので 4 台同時に入れ替わる） |
| 2 | 版の設定 | `$K get settings.longhorn.io current-longhorn-version -o jsonpath='{.value}'` が `<版>`。`default-engine-image`・`default-instance-manager-image` が `<版>` |
| 3 | engine image | 新しい engine image（`docker.io/longhornio/longhorn-engine:<版>`）が `deployed`。古いもの（`<前の版>`）も残る（`REFCOUNT` はまだ 0 でない） |
| 4 | instance-manager | 各ノードに `<版>` の instance-manager が 1 つずつ `running`（4 つ）。`<前の版>` のものも、エンジンを持つものは残る（1 回目は 4 つとも。エンジンの無い duchamp のものも replica を持つので残る） |
| 5 | CSI | `longhorn-csi-plugin` 4、`csi-attacher`・`csi-provisioner`・`csi-resizer`・`csi-snapshotter` 3 ずつが新しい版で Running。サイドカーの 1〜3 回の再起動は想定内（`csi.sock` を待つ。dev の記録 §3.2） |
| 6 | UI・driver-deployer | 新しい版で Running |
| 7 | ボリューム | **attached のものが全部 healthy**（degraded になったら、faulted でなく rebuild が進んでいれば待つ。§7）。Prometheus の 2 本と `cg-data` は detached |
| 8 | replica | `failed`・`error` の増えたものがあれば記録し、rebuild で running に戻ることを見る。戻らなければ §7 |
| 9 | share-manager | 2 つ（`tumblr-data`、`ero-data`）が running。Pod が作り直されたかを記録する（dev には RWX が無かった）。`homegallery` の `ero-web`・`tumblr-web` の Pod が Running で、restartCount が増えていない |
| 10 | Pod | `longhorn-system` の全 Pod が Running・Ready。クラスタ全体で Running / Completed 以外の Pod が無い。Longhorn を使う Pod の restartCount が §4.1 の 12 から増えていない |
| 11 | NetworkPolicy | `longhorn-system` に 6 つ。`lh-state.sh $D/after-apply` の要約の `with region in a selector` が 0 |
| 12 | 監視 | §4.4 の `FAIL` の時刻と数、`lh-watch.sh` の degraded・`error` の時刻を記録する |

ここで止めるのは §7 に当たるとき。

### 4.9 NetworkPolicy と CSI を確かめる ✋

apply の後、エンジンの更新の前に、新しい NetworkPolicy のもとで CSI の provision・attach・detach と RWX（share-manager と recovery backend）が動くことを、一時的な名前空間で確かめる（`tools/pvcheck.sh`。§1.6）。

```sh
export ADMIN_TOKEN
docs/longhorn/tools/pvcheck.sh up chirico       # provision、chirico でアタッチ、書いて md5 を確かめる
docs/longhorn/tools/pvcheck.sh move pablo       # detach、pablo でアタッチ、md5 を確かめる
docs/longhorn/tools/pvcheck.sh status
docs/longhorn/tools/pvcheck.sh down             # 名前空間と PV、Longhorn のボリュームが消える
```

- 合格: `up` と `move` が rc 0 で `/rwo/blob: OK`、`/rwx/blob: OK`。2 本のボリュームが `<版>` のエンジンで attached healthy。`down` で PV と Longhorn のボリュームが消え、名前空間が NotFound
- 新しく作るボリュームは、新しい engine image と新しい instance-manager で動く。replica は silver の 2 で、別々のノードに置かれる（instance-manager どうしの通信を通る）
- RWX のボリュームは share-manager の Pod を作り、Pod は NFS でマウントする。share-manager から longhorn-manager の recovery backend（9503）への通信を通る
- **止める条件**: PVC が Pending のまま、Pod が `ContainerCreating` のまま（`FailedAttachVolume`・`FailedMount`）、5 分たっても `done` が出ない。そのときは名前空間を消さずに止め、`$K logs` で longhorn-manager・csi-plugin・csi-provisioner・csi-attacher のログ（`connection timed out`・`deadline exceeded`）を見て報告する。上流の文書は、内部の NetworkPolicy が通信を止めたときに 6 つの NetworkPolicy を消す手を示しているが、runbook から外れるのでユーザーが決める（§7）
- 時刻を記録する。`down` を流し忘れない（失敗して止めたときも、ユーザーの判断の後に流す）

### 4.10 エンジンの更新 ✋

1. ✋ **detached のボリュームから**（Prometheus を早く戻すため）。`engine-upgrade.sh` は detached のボリュームは `spec.image` を変えるだけで、2 秒ほどで終わる。

   ```sh
   EI=docker.io/longhornio/longhorn-engine:<版>
   export KUBECTL="kubectl --context fraction --token=$ADMIN_TOKEN"
   T=docs/longhorn/tools
   for v in pvc-625c8825-4571-43d8-9119-c006a4a48399 pvc-99c35b80-7928-4b9b-a4ac-3afa8e7a7b05 pvc-c9f006ad-fe37-48c0-9a4a-c3f7831fbd46; do
     $T/engine-upgrade.sh $v $EI --dry-run && $T/engine-upgrade.sh $v $EI | tee -a $D/engine-upgrade.log || break
   done
   ```

   - engine image の名前は `docker.io/` を付けた形（`default-engine-image` の設定と同じ。dev の記録 §3.3）
   - `--dry-run` は server-side の dry run で、Longhorn の webhook を通る

2. ✋ Prometheus を戻す。

   ```sh
   kubectl-admin -n monitoring patch prometheus kube-prometheus --type=merge -p '{"spec":{"replicas":2}}'
   kubectl --context fraction -n monitoring get pods -l app.kubernetes.io/name=prometheus -o wide -w   # 2 つとも Running・Ready
   ```

   - 2 本のボリュームが、`<版>` のエンジン、`<版>` の instance-manager でアタッチされ healthy になる（replica 1 なので degraded にはならない）
   - **2 つの Pod が前と別のノードに載ることがある**（StatefulSet の Pod はノードに固定されず、`preferred` の podAntiAffinity だけ。段 C では 2 回とも、prometheus-0 と -1 のノードが入れ替わった。`../k8s-upgrade/runbook-stage-c.md` §2.6）。そのときボリュームは Pod のノードでアタッチされ、`dataLocality: best-effort` で Longhorn がそのノードに replica を作り直し（25 GiB の rebuild）、前の replica を消す。rebuild の間も healthy で、終われば replica は 1 つに戻る。載ったノード、rebuild の始めと終わりの時刻を記録する。rebuild が終わるのを待たずに 3 へ進んでよい
   - Prometheus は起動のときに WAL を読み直すので、Ready まで数分かかりうる。`https://prometheus.fraction.jp/` と Grafana で、止めていた間の欠けの後にメトリクスが戻ることを見る
   - 止めていた時間（§4.7 から Ready まで）を記録する

3. ✋ **attached のボリュームを 1 本ずつ live upgrade する**。次の順に、1 本ごとに結果を見てから次へ進む。

   | # | ボリューム | 名前空間/PVC | 注 |
   |---|---|---|---|
   | 1 | `pvc-29c27b73-984a-4e28-8af8-9d6014ba174e` | fraction-agents/data-calendar-keeper-0 | |
   | 2 | `pvc-984a7d6b-5e67-42a3-a453-58a86c302166` | fraction-agents/data-web-researcher-0 | |
   | 3 | `pvc-bf2d7ef2-0a1d-4411-ab83-b41e5cf51fe6` | fraction-agents/data-news-agent-0 | |
   | 4 | `pvc-aee2ec0e-277d-4692-a977-04981f4201eb` | fraction-agents/data-gmail-agent-0 | oeilvert |
   | 5 | `pvc-092a74ed-ea00-4778-a862-2754af440747` | fraction-agents/data-wiki-keeper-0 | oeilvert |
   | 6 | `pvc-9aae4b86-a62c-4fc6-81fc-5292aa8422dd` | fraction-agents/data-deep-researcher-0 | |
   | 7 | `pvc-3a665d04-c867-449a-a216-f8bb00658185` | natsumi/natsumi-myao | |
   | 8 | `pvc-e224cffa-39e2-41e8-89e1-24ab2c9a6129` | natsumi/natsumi-aki | oeilvert |
   | 9 | `pvc-6b8f51fa-ba8e-4981-8a55-c8efb4ab96a7` | natsumi/natsumi | oeilvert |
   | 10 | `pvc-0b28d049-7da0-40f4-812a-122fe56161f3` | homegallery/tumblr-data | **RWX**、古い形式の名前のエンジン |
   | 11 | `pvc-baa41130-82c0-41ed-9df8-2569458615b6` | homegallery/ero-data | **RWX**、古い形式の名前のエンジン |
   | 12 | `pvc-c6fbd833-21ba-42db-8d6e-1093481307f2` | fs/sites | pablo、古い形式の名前のエンジン、`sites-2` の NFS |
   | 13 | `pvc-1d94c3ed-6b77-4077-83c1-cea28fb76628` | fs/data | 古い形式の名前のエンジン |
   | 14 | `pvc-c4944b75-7ed0-4cf4-adce-bb5723993ff8` | fs/h2 | 300 GiB、`aphrael-2`・`comics-2` の NFS |

   ```sh
   $T/engine-upgrade.sh <volume> $EI --dry-run && $T/engine-upgrade.sh <volume> $EI | tee -a $D/engine-upgrade.log
   ```

   1 本ごとに確かめる（合格したら次へ）:

   - `engine-upgrade.sh` が rc 0（`done in Ns`）。dev は 1 本 5 秒で、Replica の CR が `numberOfReplicas` → 2 倍 → `numberOfReplicas` と動いた
   - ボリュームが attached healthy、アタッチ先のノードが同じ
   - そのボリュームを使う Pod（§2.2）の restartCount が増えていない
   - そのノードの iSCSI のセッション（`sudo iscsiadm -m session`）の数が前と同じ（dev では同じ sid のまま）
   - `lh-watch.sh` と §4.4 の監視に、そのボリュームの degraded・faulted、`FAIL` が出ていない
   - RWX（10・11）では、share-manager の Pod が作り直されていないこと、`homegallery` の Pod が Running のまま
   - 12（`fs/sites`）の後は `www.fraction.jp`、14（`fs/h2`）の後は `aphrael`・`comics` の Pod が Running のままであること

   rc 1（faulted、または前の確認で断った）・rc 2（timeout）なら、次へ進まずに止める（§7）。

4. 全部の後:

   ```sh
   $K get volumes.longhorn.io -o custom-columns=N:.metadata.name,STATE:.status.state,ROB:.status.robustness,IMG:.status.currentImage
   ```

   17 本とも `status.currentImage` が `<版>`。attached のものは healthy。

- エンジンは古い（`<前の版>` の）instance-manager の Pod の中で、新しい版のバイナリで動き続ける（dev の結論の 4）。replica は新しい instance-manager に移る。`lh-state.sh` の `engines.tsv` の instance-manager の列と、`replicas.tsv` の instance-manager の列で見る。古い instance-manager は、エンジンが残る間は消えない（§3 の 9）

### 4.11 古い engine image を消す ✋

```sh
$K get engineimages.longhorn.io   # <前の版> の REFCOUNT が 0
kubectl-admin -n longhorn-system delete engineimages.longhorn.io <前の版の engine image の名前>
```

- `REFCOUNT` が 0 でなければ消さない（エンジンの更新が済んでいないボリュームがある）
- 消すと、その engine image の DaemonSet（`engine-image-ei-<…>`）も消える（dev の記録 §3.3）。1 回目は `ei-c9fa6d45`（v1.11.2）

### 4.12 その回の完了の確認

```sh
KUBECTL="kubectl --context fraction" docs/longhorn/tools/lh-state.sh $D/after
diff -r $D/before $D/after > $D/state.diff
```

| # | 確認 | 合格基準 |
|---|---|---|
| 1 | 版 | `current-longhorn-version` が `<版>`。`longhorn-system` の Pod の image が `<版>`（engine-image の DaemonSet は `<版>` のものだけ）。古い instance-manager は、エンジンの残るものだけが `<前の版>` |
| 2 | ボリューム | 17 本とも `status.currentImage` が `<版>`。attached 16 が healthy、detached は `cg-data` だけ（§4.1 と同じ。Prometheus の 2 本は attached に戻っている） |
| 3 | replica の数 | 各ボリュームの running の replica の数が `numberOfReplicas` と同じ。全体の数が §4.1 と同じ（Prometheus の 2 本は、Pod が別のノードに載ると data locality の rebuild で replica の置き場所が変わる。§4.10 の 2。rebuild が終わっていること） |
| 4 | `failedAt` | §2.3 の 1 つ（消えていれば 0）のほかに無い |
| 5 | orphan | 0（増えていたら `gc-and-orphans.md` §3.1 で中身を見て記録する。消すのは別に承認を取る） |
| 6 | CRD | `crds.tsv` がどれも `v1beta2` だけ（1 回目の後は 25 個、2 回目の後は 28 個）。`../k8s-upgrade/tools/storage-versions.sh` の `crds.tsv` で、Longhorn の CRD の `MULTI` が 0。古い版が残っていたら計画 §4.3 の末尾の手順を、ユーザーに示してから流す |
| 7 | 設定 | `settings.tsv` の差分が、版の入ったイメージの名前と、版が足した設定だけ（§2.1 の値は変わらない） |
| 8 | iSCSI | 4 台の Longhorn のセッションの数が、そのノードにアタッチされたボリュームの数と同じ（作業の前は chirico 10、oeilvert 5、pablo 1、duchamp 0。Prometheus の 2 本は、戻した Pod のノードで数える）。portal は、どれもそのエンジンのいる instance-manager の IP（古い instance-manager の IP でもよい）。それ以外の portal が無い |
| 9 | iscsid | 4 台の MainPID が §4.1 の 10 と同じ（この作業では iscsid を再起動しない） |
| 10 | Pod | クラスタ全体で Running / Completed 以外が無い。Longhorn を使う Pod の restartCount が §4.1 の 12 から増えていない（Prometheus の 2 つは作り直したもの） |
| 11 | アプリ | `check-apps.sh` が前と同じ。Prometheus の 2 つが Running で、スクレイプが落ちていない（`up == 0` が 0 個）。natsumi（`aki.fraction.jp`、`myao3.fraction.jp`、`natsumi.poissonnerie.dev`）、`www.fraction.jp`、homegallery の Pod、fraction-agents の 6 つ、`aphrael`・`comics` の Pod が Running |
| 12 | cnidaria | ✋ `netcheck.sh` が通る |
| 13 | 監視 | §4.4 の 2 つを止め、`FAIL` の数と時刻、`lh-watch.sh` の degraded・faulted・`error` の時刻を記録する |
| 14 | ノード | 8 台 Ready。Longhorn の Node 4 台が Ready・schedulable |

1 回目は、このあと §5.3（open-iscsi の hold）を流してから、1 回目の完了とする。

## 5. 1 回目（1.11.2 → 1.12.1）に固有のこと

### 5.1 manifest の差分

dev の記録 §2.1 のとおり（`kubectl kustomize` の render で比べたもの）。§4.2 の diff と合うこと。

- 追加: CRD 3 つ（`enginefrontends`、`shardgroups`、`shards`。どれも `v1beta2` だけ）、**NetworkPolicy 6 つ**（`backing-image-data-source`、`backing-image-manager`、`instance-manager`、`longhorn-manager`、`longhorn-recovery-backend`、`longhorn-webhook`）
- 削除: 無し
- `longhorn-manager`（DaemonSet）、`longhorn-driver-deployer`、`longhorn-ui` の image の版。CSI のサイドカーの版（driver-deployer の環境変数）
- RBAC の中身（ラベルの版と権限の追加）
- Setting: 既存の値は変わらない。足されるもの: `allow-live-engine-upgrade-on-same-image-commit`、`data-engine-cpu-isolation-enabled`、`data-engine-iobuf-*-pool-size`、`data-engine-number-of-cpu-cores`、`engine-image-pod-liveness-probe-*`、`kubernetes-metrics-server-metrics-enabled`、`snapshot-count-warning-threshold`

### 5.2 内部の NetworkPolicy（1.12.1）

`policyTypes: [Ingress]` だけで、egress は絞らない。fleet-infra の直しの後の selector（§1.4 の 2 で `region` が無いこと）:

| NetworkPolicy | 選ぶ Pod（本番） | 通すもの |
|---|---|---|
| `longhorn-manager` | longhorn-manager 4（`app: longhorn-manager`） | longhorn-manager、longhorn-ui、**longhorn-csi-plugin**、longhorn-driver-deployer、recurring job と `longhorn.io/job-task` の Pod から |
| `instance-manager` | instance-manager（`longhorn.io/component: instance-manager`。新旧とも） | longhorn-manager、instance-manager、backing-image-manager、backing-image-data-source から |
| `longhorn-recovery-backend` | longhorn-manager（`longhorn.io/recovery-backend`） | **share-manager** から 9503 |
| `longhorn-webhook` | longhorn-manager（`longhorn.io/admission-webhook`） | どこからでも 9501・9502 |
| `backing-image-*` | 無い（backing image が 0） | — |

- **V1 の iSCSI（ノードの initiator → 同じノードの instance-manager の 3260）は、1.12.1 の `instance-manager` の policy では通さないが、cnidaria ではノードから同じノードの Pod への通信に ingress の policy をかけない**（cnidaria-cni の README「A node reaching a pod on itself」。dev の記録 §2.1）。dev では 1.12.1 の policy のまま 4 本をアタッチし直して通った。1.12.2・1.13.0 は 3260 を足す
- エンジンから別のノードの replica へ（instance-manager どうし）は、`instance-manager` の policy が通す
- kubelet の probe（ノードから同じノードの Pod）は cnidaria の policy の対象外
- 名前空間の外からの longhorn-manager（9500）への scrape は止まる（上流の Note）。本番の Prometheus は Longhorn を scrape していない（fleet-infra と k8s-manifests-fraction-private に ServiceMonitor が無い。dev の記録 §2.1）
- 本番の `longhorn-system` には、ほかに NetworkPolicy が無い（§2.1）。この 6 つが初めて入るので、`longhorn-system` の中で選ばれた Pod は、ここに無い通信を受けなくなる

### 5.3 open-iscsi の hold を消す ✋

計画 §4.3・§4.4、TASK.md の 2026-10-19 のユーザー指示（「Longhorn を v1.12.1 以上にし、全ボリュームのエンジンを新しいイメージにしたら、このファイルを消して戻す」）、dev の結論の 3。

前提（§4.12 の後に読み直す）:

- 17 本とも `status.currentImage` が `docker.io/longhornio/longhorn-engine:v1.12.1`（`cg-data` を含む。detached のものは、次にアタッチしたときに新しいエンジンで起動する）
- 4 台の Longhorn の iSCSI のセッションに、今動いている instance-manager の IP でない portal が無い（§4.12 の 8）。**残っていたら hold を消さずに止める**（1.11.2 のエンジンが前に残したもの。消し方は porkadot-dev の `docs/longhorn/iscsi-stale-sessions.md` §4.2。iscsid を再起動する前なら logout できる。runbook から外れるのでユーザーが決める）

1 台ずつ（pablo → duchamp → oeilvert → chirico）:

```sh
ssh -n yuanying@<IP> 'cat /etc/apt/apt.conf.d/51fraction-hold-open-iscsi'          # 中身が §2.5 のものであること
ssh -n yuanying@<IP> 'sudo rm /etc/apt/apt.conf.d/51fraction-hold-open-iscsi'
ssh -n yuanying@<IP> 'ls /etc/apt/apt.conf.d/51fraction-hold-open-iscsi; apt-config dump | grep -A3 -i "Package-Blacklist"; apt-cache policy open-iscsi | head -3'
```

- ファイルが無い（`No such file or directory`）。`apt-config dump` の `Unattended-Upgrade::Package-Blacklist` に `open-iscsi`・`libopeniscsiusr` が無い（ほかの項目があれば記録する）
- `apt-cache policy open-iscsi` の Installed と Candidate を記録する。Candidate が新しければ、次の unattended-upgrades で open-iscsi が上がり、iscsid が再起動しうる。**エンジンが直った版なので、それで構わない**（dev で、アタッチしたまま iscsid を再起動して detach しても、古いセッションは残らなかった。dev の記録 §3.4）
- 時刻を記録する

これで、計画 §4.4 の「守ること」（Longhorn の iSCSI のセッションが残ったノードで iscsid を再起動しない、`install kubelet` の前後で iscsid の PID とセッションを見る）は終わる。段 6 以降の手順書では、この確認を止める条件から外してよい（iscsid の PID が変わることは止める理由にならない）。古いセッションが無いことは、引き続き健全性の確認で見る。

### 5.4 1 回目の完了

§4.12 と §5.3 が済んだら、1 回目の記録（§10）を残し、2 回目の承認を取る（§0）。

## 6. 2 回目（1.12.1 → 1.13.0）に固有のこと

### 6.1 manifest の差分

dev の記録 §2.2 のとおり。2 回目の fleet-infra の PR で 1.13.0 の manifest を render し、§1.4 と §4.2 で確かめる。

- 追加: CRD 3 つ（`instancemanagerupgradecontrols`、`instancemanagerupgrades`、`snapshotgroups`）、**Deployment `longhorn-global-manager`**（`longhorn-manager -d global`、replicas 3、ServiceAccount `longhorn-service-account`、`priorityClassName: longhorn-critical`、同じノードを避ける `preferred` の podAntiAffinity）、**CSI の専用の ServiceAccount** `longhorn-csi-service-account` と ClusterRole/Binding・Role/RoleBinding `longhorn-csi-role`・`longhorn-csi-bind`、**ClusterRole/Binding `longhorn-csi-secret-role`・`longhorn-csi-secret-bind`（クラスタ全体の Secret の `get`）**
- 変更: NetworkPolicy `instance-manager` に、どこからでも 3260 を通す規則が足される
- 削除: 無し
- Setting: 既存の値は変わらない。足されるもの: `allow-instance-manager-automatic-upgrade`、`default-nvme-tcp-nr-io-queues`、`instance-manager-upgrade-start-time`、`instance-manager-upgrade-timeout`（どれも V2 だけ）
- **`longhorn-global-manager` の Deployment も、prod overlay で `spec.selector` に `region: fraction` が付く**（§1.4 の 3。新しく作るので immutable の問題は無い）。2 回目の fleet-infra の PR で、`longhorn-global-manager` の selector と template に `region` が付き、NetworkPolicy の selector に付かないことを確かめる

### 6.2 1.13.0 で特に見ること

- **K8s の要件**: 1.34 以上（csi-provisioner v6.3.0）。本番は v1.34.12
- **`longhorn-global-manager`**: 3 つとも Running・Ready で、chirico・duchamp・oeilvert・pablo のどれかに載る（§2.4。上流は「少なくとも 1 つが載ること」を求める）。1 つも載らなければ止める。dev では、起動の後に leader が lease の更新に失敗して 1 回再起動した（leader election のふだんの動き。dev の記録 §4.1）
- **CSI のサイドカー**: `longhorn-csi-service-account` で動く（`$K get deploy csi-provisioner -o jsonpath='{.spec.template.spec.serviceAccountName}'`）。§4.9 の `pvcheck.sh` で provision・attach が動くこと
- **`longhorn-csi-secret-bind`**: 既定のまま入れる（§3 の 13）。fleet-infra の StorageClass（gold・silver・bronze、`longhorn`、`longhorn-static`）は `csi.storage.k8s.io/provisioner-secret-*` を使っていない。外すなら、manifest の apply のたびに入るので overlay で除く（上流の Important Notes「Optional restriction of CSI controller Secret access」）。2 回目の後に別に決める
- **2 世代前の instance-manager**（§3 の 9）: 1 回目の v1.11.2 の instance-manager にエンジンが残っている場合、2 回目の apply の後も、その Pod が `running` のままで、中のエンジンが running であること（`lh-state.sh` の `instancemanagers.tsv`・`engines.tsv`）。v1.11.2 の instance-manager が `error`・`unknown` になったら止める。dev では確かめていない
- v1.12.1 の instance-manager（1 回目で作られ、replica を持つもの）も、2 回目の live upgrade の後はエンジンの残るものだけになる。4 つの instance-manager に新旧 2〜3 世代が並ぶ形を記録する

## 7. 止める条件

次のどれかになったら、その場で止めて報告する。止めた後の対処はユーザーが決める（§0）。

| 条件 | 例・見方 |
|---|---|
| **faulted** | どれかのボリュームの robustness が faulted。`engine-upgrade.sh` が rc 1 で `is faulted` |
| **データが読めない** | Longhorn を使う Pod に I/O エラー（`kubectl logs`、`dmesg` の `Buffer I/O error`・`blk_update_request`）、`pvcheck.sh` の md5 が合わない |
| **degraded のまま戻らない** | degraded が 10 分を超える、rebuild が進まない（replica が `error` のまま、`failedAt` が付いたまま） |
| **更新が止まる** | manager の DaemonSet・Deployment の rollout が 10 分で終わらない、Pod が CrashLoopBackOff、新しい engine image が `deployed` にならない、instance-manager が `running` にならない、`engine-upgrade.sh` が rc 2（600 秒の timeout）、`longhorn-global-manager` が 1 つも載らない（2 回目） |
| **NetworkPolicy で通信が止まる** | `pvcheck.sh` が 5 分で終わらない、PVC が Pending・Pod が `ContainerCreating` のまま、longhorn-manager・csi-plugin・csi-provisioner・csi-attacher・share-manager のログに `connection timed out`・`deadline exceeded`、RWX の Pod の NFS のマウントが止まる |
| **バックアップが取れない** | §4.5 の Backup・SystemBackup が `Error`。バックアップの無いまま apply しない |
| **事前 pull の間の replica の失敗** | §4.6 で、replica の `error`、ボリュームの degraded が出た |
| **想定外の再起動** | Longhorn を使う Pod の restartCount が増えた、share-manager の Pod が作り直されて RWX の Pod が止まった |
| **iSCSI** | 今の instance-manager の IP でない portal へのセッションが現れた、iscsid の PID が変わった（§5.3 の前） |

NetworkPolicy で通信が止まったときの選択肢（その場でユーザーが決める）: 上流の文書（1.12.1 の Important Notes「Internal Network Policies」）は、manifest で入れた場合、6 つの NetworkPolicy だけを `kubectl delete` してから同じ更新をやり直す手を示している。消しても、次に manifest を apply すると作り直されるので、fleet-infra の overlay で除くことになる。

## 8. ロールバック

**Longhorn はダウングレードできない**（v1.5.0 からのダウングレード防止。上流の「Upgrade」の文書）。apply が成功した後に前の版の manifest を apply しても、Longhorn が拒む（dev の記録の「ロールバック」）。

| どこまで進んだか | 戻せるか | 戻し方 |
|---|---|---|
| §4.5〜4.7（バックアップ、事前 pull、Prometheus の停止）まで | 戻せる | 何も変わっていない。Prometheus は §4.10 の 2 で戻す。スナップショット・バックアップ・pull したイメージは残してよい |
| §4.8 の apply で、manager が版の飛ばしを拒んだ | 戻せる | §8.1 |
| §4.8 の apply が通った後 | **戻せない** | 前に進めて直すか、§8.2 のバックアップからの戻し |

### 8.1 manager が更新を拒んだとき ✋（その都度承認）

上流の文書（「Upgrade」の Upgrade Path Enforcement）: サポートされない版から上げようとすると、manager が自動で失敗し、前の版へは中断なしに戻せる。1 回目の前に `current-longhorn-version` が v1.11.2、2 回目の前に v1.12.1 であることを §4.1 で確かめるので、起きない見込み。

起きたら、前の回の fleet-infra の commit の manifest を apply する（1 回目なら PR の前の main、`0a744d6`）。そのときも §1.4 の render の確認（DaemonSet・Deployment の selector が今と同じ）をしてから流す。

### 8.2 バックアップからの戻し（その都度承認）

apply の後に、ボリュームのデータが失われた・壊れたとき。どれも runbook の外の操作で、その時点でユーザーと決める。

- **1 本のボリューム**: §4.5 のそのボリュームのバックアップ（`$TAG-<8 桁>`）から、新しい Longhorn のボリュームに restore し（Longhorn の UI の Backup、または `fromBackup` を指定した Volume の CR）、ワークロードを止めて PV・PVC を付け替える。バックアップの後に書かれたデータは失われる
- **Longhorn の system restore**: §4.5 の system backup から。上流の文書（「Restore Longhorn System」）は、更新に失敗したときに限って、前のマイナー版の system backup を新しいマイナー版に戻すこと（例 1.4.x → 1.5）を認めている。**今あるボリュームと、その PV・PVC は戻さない**（無いものだけを、それぞれの最新のバックアップから作る）。前提として、今あるボリュームが全部 detached であること
- バックアップの後にスナップショット（`$TAG-*`）も残っているので、replica が健全なら、そのスナップショットへの revert（ボリュームを detach して）もできる

どの戻しも、バックアップを取った時点（§4.5）より後の書き込みを失う。

## 9. 既知の問題と注意

### 9.1 manager の更新の後の、replica の timeout

dev の結論の 2。manager の apply の後 1〜3 分の間、新しい instance-manager のイメージの pull・展開と replica の I/O が重なって、replica が `R/W Timeout. No response received in 8s`（`engine-replica-timeout` 8 秒）で落ちうる。§4.6 の事前 pull と §4.7 の Prometheus の停止で避ける。落ちた replica は、ほかの replica が健全なら自動の rebuild で戻る（dev で約 2 分）。書き込みは 20 秒ほど止まりうる（dev で 22〜26 秒が 3 回）。

### 9.2 CSI のサイドカーの再起動

manager と csi-plugin の入れ替わりの間、CSI のサイドカー（csi-attacher・provisioner・resizer・snapshotter）が `csi.sock` を待って `context deadline exceeded` で 1〜3 回再起動する（dev の記録 §3.2・§4.1。上流の文書の例と同じ）。続かなければ想定内。

### 9.3 古い instance-manager と、エンジンの居場所

live upgrade の後、エンジンは detach まで古い instance-manager の Pod の中で動き、replica は新しい instance-manager に移る（§3 の 9、§4.10）。そのノードのワークロードが止まって detach されたときに、Longhorn が古い instance-manager を消す。`lh-watch.sh` の `im` の行で、新旧の数の移り変わりを見る。

### 9.4 RWX のボリューム

`homegallery/tumblr-data`・`ero-data` は、share-manager の Pod（chirico）が NFS で出し、`homegallery` の Pod（chirico と pablo・oeilvert）がマウントしている。dev には RWX のボリュームが無く、manager の更新とエンジンの live upgrade の間に share-manager がどう動くかを確かめていない。share-manager の Pod が作り直されると、NFS のクライアントが数十秒止まりうる（`rwx-volume-fast-failover` は false）。§4.8 の 9 と §4.10 の 3 の 10・11 で見る。

### 9.5 `fs/h2` の stopped の replica

§2.3。2026-10-19 から `failedAt` の付いた stopped の replica（duchamp）が 1 つあり、2026-10-21 09:36Z ごろに Longhorn が消す見込み。作業の前と後で同じなら記録だけする。作業の途中に消えるのは想定どおり。

### 9.6 Docker Hub の pull の上限

匿名の pull は IP ごとに 6 時間で 100 回（2026-10-20 の Docker の文書）。1 回の事前 pull は 44 回。1 回目と 2 回目の事前 pull を 6 時間の中に続けて流すと 88 回になり、ほかの Pod の pull と合わせて上限に近づく。`429` が出たら時間をおく（§4.6）。

### 9.7 apply は消さない

`kubectl apply -k` は prune しない。前の版の manifest にあり、新しい版に無いリソースは残る（1.12.1・1.13.0 では削除は無い。§5.1、§6.1）。本番には 2022 年の `longhorn-conversion-webhook` の Service が残っていて、今の manifest には無い（害は無い。この作業では触らない）。

## 10. 記録

`docs/longhorn/results/upgrade-1.12-1.13/` に、`1.12.1.md`（1 回目。§4.1 の事前の確認、§4.2 の diff の要点、§4.5〜4.12、§5.3）と `1.13.0.md`（2 回目）を残す。
時刻（UTC）、読み取りの結果、実行したコマンドと出力の要点、バックアップの名前・所要時間・大きさ、事前 pull の時間、Prometheus を止めていた時間、apply から全 Pod が揃うまでの時間、エンジンの更新の 1 本ごとの所要時間、degraded・faulted・replica の失敗の時刻、監視の `FAIL`、Pod の再起動、手順書との差を書く。
`lh-state.sh` の出力、`watch.log`、`probe.log`、`engine-upgrade.log`、`pull.log`、`diff.txt`・`dry-run.txt`・`apply.txt` は、タスクディレクトリの `notes/longhorn-upgrade/<版>/` に置き、要点を記録に写す（Secret の値は書かない。diff に Secret は出ない見込みだが、出たら写さない）。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（記録の PR で）。

## 11. 後で決めること

- §4.5 のスナップショット（`lh1121-pre-*`、`lh1130-pre-*`）とバックアップを、いつ消すか（段 6 に入ってからなど）。消すのは別に承認を取る
- `homegallery/cg-data`（2024 年から detached）を残すか
- 1.13.0 の `longhorn-csi-secret-bind` を外すか（§6.2）
- ノードの containerd に残った Longhorn の古いイメージ（v1.2.4〜v1.11.2）を片付けるか（pablo・duchamp・chirico で数 GB）
- fleet-infra の `infrastructure/longhorn/CLAUDE.md` の手順（エンジンの一括更新、`docker.io/` の無い image の名前、オフラインの更新の注）を、この手順書の形（1 本ずつ、`docker.io/` 付き、事前 pull、NetworkPolicy の確認）に合わせるか
- 段 6 以降の手順書で、計画 §4.4 の iscsid と iSCSI のセッションの確認をどこまで続けるか（§5.3）
