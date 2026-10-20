# Longhorn の古い ownerReference（controller-manager の GC のエラー）と orphan

本番 `fraction`（K8s v1.33.13、Longhorn v1.11.2）で見つかった 2 つの件について、調べた結果と直す手順をまとめる。

- kube-controller-manager の garbage collector（GC）が、`unable to get REST mapping for longhorn.io/v1beta1/Volume`（と `/ShareManager`）のエラーを繰り返している
- Longhorn の orphan（`orphans.longhorn.io`）が 12 個ある

本番の値は 2026-10-20 03:15〜03:45Z に読み取りだけで取った。dev（context `test`、K8s v1.33.13、Longhorn v1.11.2）では 03:25〜03:37Z に再現して手順を確かめ、使ったものは元に戻した。**この文書を書く間、本番には何も書き込んでいない。**

**実施済み**: 2026-10-20 03:50〜04:10Z に、本番で §2.6 と §3.4 を流した。8 つの ownerReference を書き換え、GC のエラーは止まった。orphan は 0 個になった。記録は `results/2026-10-20.md`。以下の「状態」の節は、流す前の値のまま残している。

## 0. 結論

### 0.1 GC のエラー

- **原因**: Longhorn v1.2.4（2022 年）が作った 8 つのオブジェクト（Engine 4、ShareManager 2、Service 2）が、owner を `longhorn.io/v1beta1` のまま参照している。Longhorn は ownerReferences を作るときにしか書かないので、v1.9 の CR の書き直しでも直らなかった。v1.10.0 で CRD が v1beta1 を提供しなくなってからは、GC がこの owner を引けずにエラーを返し、再試行を続けている（上限 1000 秒の間隔）。K8s の版には依らない。Longhorn v1.12.1・v1.13.0 の更新処理も直さない（§2.2）
- **影響**: 今は害が無い。GC は引けない owner を「無い」とは見なさないので、誤って消すことはない。ただし、RWX の 2 つのボリューム（`homegallery/tumblr-data`、`homegallery/ero-data`）を消したときに、**Service が GC で消えずに残る**（dev で確かめた）。Engine と ShareManager は Longhorn が自分で消すので残らない。ほかに、controller-manager のログに 1000 秒ごとに 8 行のエラーが出る。K8s 1.36 からはこのログが `--v=5` に下がって見えなくなるが、件そのものは残る（§2.3）
- **推奨**: 8 つの ownerReference の `apiVersion` だけを `longhorn.io/v1beta2` に書き換える（kind・name・uid は変えない）。スクリプト `tools/ownerref-apiversion.sh` を使い、owner の uid が今の Volume・ShareManager と一致すること（2026-10-20 は 8 つとも一致）を確かめ、server dry-run の後に 1 つずつ書き換える。ボリュームの停止や再アタッチは要らない。dev では、書き換えた後の GC の次の再試行でエラーが止まり、そのボリュームを消すと GC が Service を消した。controller-manager の再起動では直らない（§2.4〜§2.6）
- **時期**: K8s の段とも Longhorn の更新とも独立に、いつ流してもよい。段 5 の前に流すのを勧める。GC のエラーが出ているうちに、それが止まったことまで確かめられるため（§2.6）

### 0.2 orphan

- **中身**: 12 個とも、どの replica にも使われていない古い replica のディレクトリで、ノード上に残っている（oeilvert 8、duchamp 3、pablo 1。実使用の合計は約 78 GiB）。7 個は消したボリューム（Volume も PV も無い）のもの、5 個は今あるボリューム（`homegallery/ero-data`、`fs/h2`、`monitoring/prometheus-…-0`、`fs/sites` の 2 つ）の古い replica のもの。今の replica と重なるものは無い（§3.1）
- **消すとどうなるか**: v1.11.2 では、orphan の CR を消すと、そのノードの longhorn-manager が `<DiskPath>/replicas/<DataName>` を消す。上流の文書とコードで確かめ、dev でも確かめた（§3.2）。**取り消せない**
- **kubelet の再起動で作り直される理由**: longhorn-manager の Pod が一時的に Ready でなくなると Longhorn のノードが down と見なされ、`DataCleanable` が False の orphan は CR だけが消される（データは残る）。ノードが戻ると、ディスクの再スキャンで同じ名前の CR が作り直される。名前はディスクと DataName から決まる（§3.3）
- **推奨**: 12 個とも、1 つずつ CR を消してデータを消す（§3.4）。`orphan-resource-auto-deletion` は空のまま（無効）にし、orphan は見てから手で消す（§3.5）

### 0.3 流す前に要るユーザーの承認

1. GC: 本番の 8 つのオブジェクトの ownerReference の書き換え（§2.6。admin のトークンを使う）
2. orphan: 12 個の orphan の削除（§3.4。ノード上の古いデータが消え、戻せない）。消したボリュームの 7 個に残しておきたいデータがあるか。あるなら、消す前に写す（§3.4.1）
3. orphan の自動削除を無効のままにすること（§3.5）

## 1. 前提

- Longhorn の CRD（22 個）は 2026-10-20 時点で全部 `v1beta2` だけを served・storage にしていて、`status.storedVersions` も `v1beta2` だけ。v1beta1 は v1.9.0 で非推奨・提供停止とされ、v1.10.0 で CRD から消えた（longhorn/longhorn#10249、longhorn-manager#3804）
- 本番の Longhorn の経緯: 2020-10 に k8s-base（`yuanying/k8s-base` の `longhorn/`）で入れ、2022-03-21 に v1.2.4、2022-09-19 に v1.3.1。2023-04 から fleet-infra（`infrastructure/longhorn/`）で v1.4.1 → … → 2026-05-22 に v1.11.2
- kube-controller-manager は本番・dev とも `--v=2` で動いている

## 2. controller-manager の GC のエラー

### 2.1 状態（2026-10-20）

ownerReferences の `apiVersion` が `longhorn.io/` で始まり `v1beta2` でないものを、本番のすべての list できるリソースで探した。次の 8 つだけだった（`tools/ownerref-apiversion.sh list` の結果と同じ）。

| リソース | 名前（`longhorn-system`） | 作られた日 | owner（v1beta1 のまま） | owner の uid | 今の owner と uid が一致 |
|---|---|---|---|---|---|
| Engine | `pvc-c6fbd833-21ba-42db-8d6e-1093481307f2-e-d0ea8a1d` | 2022-03-24 | Volume `pvc-c6fbd833-…`（`fs/sites`） | `ed358f22-c2fd-404e-9673-5803e3feee36` | 一致 |
| Engine | `pvc-1d94c3ed-6b77-4077-83c1-cea28fb76628-e-29bded80` | 2022-03-29 | Volume `pvc-1d94c3ed-…`（`fs/data`） | `a23dd095-1a57-42d6-9c1d-51111a1ca104` | 一致 |
| Engine | `pvc-0b28d049-7da0-40f4-812a-122fe56161f3-e-58b23836` | 2022-08-28 | Volume `pvc-0b28d049-…`（`homegallery/tumblr-data`、RWX） | `2c9be960-1556-47eb-990a-b2d5460d8fcf` | 一致 |
| Engine | `pvc-baa41130-82c0-41ed-9df8-2569458615b6-e-1caaf475` | 2022-08-30 | Volume `pvc-baa41130-…`（`homegallery/ero-data`、RWX） | `7cf73680-d2e0-4889-8bd6-1a09546c844d` | 一致 |
| ShareManager | `pvc-0b28d049-7da0-40f4-812a-122fe56161f3` | 2022-08-28 | Volume `pvc-0b28d049-…` | `2c9be960-1556-47eb-990a-b2d5460d8fcf` | 一致 |
| ShareManager | `pvc-baa41130-82c0-41ed-9df8-2569458615b6` | 2022-08-30 | Volume `pvc-baa41130-…` | `7cf73680-d2e0-4889-8bd6-1a09546c844d` | 一致 |
| Service | `pvc-0b28d049-7da0-40f4-812a-122fe56161f3`（ClusterIP 10.254.0.67） | 2022-08-28 | ShareManager `pvc-0b28d049-…` | `e6218b7c-e262-414d-b85f-c020d97f9f88` | 一致 |
| Service | `pvc-baa41130-82c0-41ed-9df8-2569458615b6`（ClusterIP 10.254.0.4） | 2022-08-30 | ShareManager `pvc-baa41130-…` | `01671f9e-ac01-453d-bb07-2f9b90c9c606` | 一致 |

- 4 つのボリュームはどれも attached healthy、replica 2。Engine は 4 つとも running で、`longhorn-engine:v1.11.2`
- 4 つのボリュームの Replica は 2026 年に作り直されたもので、owner は v1beta2。2024 年以降に作られた Engine・ShareManager（14 個）は v1beta2
- controller-manager の leader（`kube-controller-manager-74f5bc6db4-fw4lb`）のログ（段 4 の起動の 02:03Z から 03:15Z まで）に、この 8 つが item として 21〜22 回ずつ出ている。間隔は 5ms から倍々に延び、02:42Z 以降は 1000 秒ごと（02:42:14、02:58:54、03:15:34）

```
E1020 03:15:34.508509 1 garbagecollector.go:358] "error syncing item" err="unable to get REST mapping for longhorn.io/v1beta1/Volume." logger="garbage-collector-controller" item="[longhorn.io/v1beta2/Engine, namespace: longhorn-system, name: pvc-0b28d049-7da0-40f4-812a-122fe56161f3-e-58b23836, uid: 141e5679-3b21-491d-af70-e549576ffe1b]"
```

item は dependent（Engine・ShareManager・Service。どれも今の版で見えている）で、err がその owner の参照を指している。

### 2.2 原因

**なぜ v1beta1 のまま残っているか**

- 8 つとも 2022-03〜08 に作られた。このころ本番の Longhorn は v1.2.4（k8s-base の 2022-04-11 と 2022-09-17 のコミットが `longhornio/longhorn-manager:v1.2.4`）で、Longhorn の API は v1beta1 だった。v1beta2 は v1.3.0（2022-06）から
- Longhorn は ownerReferences を、オブジェクトを作るときにだけ書く（v1.11.2 の `datastore.GetOwnerReferencesForVolume`、`ShareManagerController.createServiceManifest`）。今あるオブジェクトの ownerReferences を書き直す処理は無い。ShareManager の Service は、無いときだけ作る（`createServiceAndEndpoint`）
- v1.9.0 の更新処理（`upgrade/v18xto190`）は、すべての CR を読んで v1beta2 で書き直した（longhorn/longhorn#10250）。これは保存の版を変えるもので、`metadata.ownerReferences[].apiVersion` は中身のただの文字列なので変わらない。Service は CR ですらない
- この Engine は名前が古い形式（`-e-<8 桁>`）のとおり、ボリュームを作ったときのものがアタッチ・デタッチをまたいで使われ続けている
- Longhorn v1.12.1・v1.13.0 の更新処理（`upgrade/v1120to1121`、`upgrade/v112xto1130`）にも ownerReferences を直す処理は無い。Longhorn を上げても直らない

**なぜ GC がエラーを繰り返すか**（K8s v1.33.13 の `pkg/controller/garbagecollector/`）

- controller-manager が起動して GC のグラフを作るとき、dependent の ownerReference と owner の実際の座標（apiVersion・kind・name・uid）が合わないと、その dependent を検査の列（attemptToDelete）に入れる（`addDependentToOwners`、`processGraphChanges` の virtual ノードの置き換え）
- 検査（`attemptToDeleteItem` → `isDangling`）で `longhorn.io/v1beta1` の REST mapping を引こうとして失敗し、`restMappingError` として列に戻す。上限 1000 秒の指数バックオフで、永久に再試行する。引けない owner は「無い」とは見なさないので、dependent は消されない
- 起動した後に ownerReference の中身だけが変わった場合（同じ uid）は、検査し直さない（`referencesDiffs` の changed は `addDependentToOwners` に渡らない）。dev で v1beta2 → v1beta1 に書き換えてもエラーは出ず、controller-manager の Pod を作り直したときに初めて出た（§2.5）。本番でも、controller-manager が起動するたびに出ていたと見ている（段 4 より前のログは残っていない）
- K8s の上流でも同じ状況が報告されていて、開いたまま（kubernetes/kubernetes#102641「owned Custom Resources not garbage collected after CRD API version removal」。2026-10-13 にも v1.37.0 で再現の報告）。v1.36 で、このエラーのログは `V(5).Info` に下がった（kubernetes/kubernetes#136040）。本番の `--v=2` では、段 7 以降は見えなくなる

**Longhorn の上流の報告**: `gh search issues --repo longhorn/longhorn` で `ownerReferences`、`garbage collector`、`garbagecollector`、`REST mapping`、`v1beta1` などを探したが、同じ報告も推奨の手順も見つからなかった（2026-10-20）。近いものは #10869（v1.2 → v1.9 の後に uninstall が止まる。原因は別）、#3407（v1.2 → v1.3 の途中の GC と変換の件。解決済み）。

### 2.3 影響

| 対象 | 消すのは誰か | v1beta1 のままのとき |
|---|---|---|
| Engine（4） | Volume を消すと、Longhorn の volume controller が自分で Engine と Replica を消す（`volume_controller.go` の `DeletionTimestamp` の処理） | 影響なし |
| ShareManager（2） | 同じく volume controller が消す（`DeleteShareManager`） | 影響なし |
| Service（2） | Longhorn は ShareManager を消すときに Service を消さず、GC に任せている（`share_manager_controller.go` の `DeletionTimestamp` の処理は Pod と ConfigMap だけ） | **RWX のボリュームを消しても Service（と EndpointSlice）が残る**。ClusterIP を 1 つずつ持ったまま。手で消せば済む |

- GC が誤って消すことはない（§2.2）。今動いているボリュームへの影響は無い
- controller-manager のログのエラーは、steady state で 1000 秒ごとに 8 行。GC のほかの処理は止まらない
- `kubectl delete --cascade=foreground` で Volume などを消すと、GC が dependent を片付けられずに待ち続けうる（Longhorn と CSI の普段の削除は background なので当たらない）

### 2.4 直し方の比較

| 案 | 結果 |
|---|---|
| **A. ownerReference の `apiVersion` だけを `longhorn.io/v1beta2` に書き換える（推奨）** | kind・name・uid は同じなので、GC は今の owner をそのまま引ける。オブジェクトのほかの欄も、Longhorn の動きも変わらない。dev で確かめた（§2.5） |
| B. controller-manager を再起動する | 直らない。保存されている ownerReference が v1beta1 なので、起動のたびに同じエラーが出る（段 4 で controller-manager は作り直されたが出ている。dev でも Pod を作り直すとエラーが出た） |
| C. Longhorn に作り直させる | Engine は、ボリュームがある間は同じものが使われ続ける（デタッチしても作り直されない）。Service を消すと Longhorn が作り直すが、ClusterIP が変わる。本番は `endpoint-network-for-rwx-volume` が空で、RWX のマウント先は ClusterIP（`nfs://10.254.0.67/…`）なので、マウントしている Pod の作り直しが要る |
| D. ownerReference を消す | GC が Service を消さなくなる。今の不具合を固定するだけ |
| E. CRD に v1beta1 を served で戻す | v1.10 以降の CRD に v1beta1 の schema は無く、fleet-infra の manifest とも食い違う。採らない |

**A で誤ったときのこと**: uid や kind を誤って書くと、GC は owner が無いと判断して dependent を消す。Engine が消えればボリュームが止まり、Service が消えれば ClusterIP が変わる。そのため、スクリプトは次のときに書き込まない。

- ownerReference が 1 つでない、`apiVersion` が書き換える前の値でない、kind が Volume・ShareManager でない
- その名前の owner が無い、削除中である、uid が ownerReference の uid と違う

書き込みは JSON patch で、`metadata.uid` と `metadata.ownerReferences` の全体を `test` で照らしてから `apiVersion` だけを `replace` する。読んだ後に誰かがオブジェクトを変えていれば、API サーバーが patch ごと拒否する。

### 2.5 dev での確認（2026-10-20）

dev の `lh-gc-test` 名前空間に RWX の PVC を 2 つ（A `pvc-9d099448-…`、B `pvc-f1aa2fd2-…`、どちらも 1Gi、replica 3）と、それぞれをマウントする Pod を作った。Longhorn の Engine・ShareManager・Service は、どれも owner を v1beta2 で作った。

1. `ownerref-apiversion.sh undo` で、A と B の Engine・ShareManager・Service（6 つ）の owner の `apiVersion` を `longhorn.io/v1beta1` にした（本番と同じ状態）。先に `--dry-run` を流し、Longhorn の admission webhook を通ることを確かめた。Longhorn は 45 秒たっても書き戻さなかった
2. この時点では controller-manager のログにエラーは出なかった（§2.2）。leader の Pod を消すと、引き継いだ controller-manager が起動した直後から、6 つの item で本番と同じ `unable to get REST mapping for longhorn.io/v1beta1/Volume.`・`…/ShareManager.` を繰り返した
3. **A を直した**: 3 つとも `fix … --dry-run` で、`after` が v1beta2 になることを見た。その後、Engine・ShareManager・Service の順に `fix` を流した（03:30:05〜03:30:21Z）。それぞれの後もボリュームは attached healthy、shareState running のままで、Pod は書き続けていた。書き換えたものに `fix` をもう一度流すと、`apiVersion is not longhorn.io/v1beta1` で止まった
4. GC は A の 3 つを、次の再試行（Engine 03:30:07、ShareManager・Service 03:31:29）でエラーなしに処理して、列から外した。controller-manager の再起動は要らなかった。B の 3 つはエラーを続けた
5. **B（v1beta1 のまま）を消した**: Pod と PVC を消すと、60 秒以内に Volume・Engine・ShareManager・Replica は消えたが、**Service（ClusterIP 10.252.0.24）と EndpointSlice は残った**。GC は B の Service でエラーを続けた（§2.3 の影響）
6. **A（直したもの）を消した**: Pod と PVC を消すと、GC が Service と EndpointSlice を消した（`"Deleting item" … v1/Service … pvc-9d099448-…`、03:33:02Z）
7. 片付け: B の残った Service を手で消し、`lh-gc-test` 名前空間を消した。PV・Longhorn のボリュームは残っていない。`list` は空で、controller-manager のエラーは止まった。dev の controller-manager は Deployment が作り直した Pod（`kube-controller-manager-859b459fd9-5cfp7`）で 2 つとも Running

### 2.6 本番の手順（承認の後に流す）

#### 2.6.1 前の確認（読み取りだけ）

```bash
cd <k8s-manifests-fraction>
T=docs/longhorn/tools/ownerref-apiversion.sh
KUBECTL="kubectl --context fraction" $T list
kubectl --context fraction -n longhorn-system get volumes.longhorn.io pvc-c6fbd833-21ba-42db-8d6e-1093481307f2 pvc-1d94c3ed-6b77-4077-83c1-cea28fb76628 pvc-0b28d049-7da0-40f4-812a-122fe56161f3 pvc-baa41130-82c0-41ed-9df8-2569458615b6
kubectl --context fraction -n longhorn-system get sharemanagers.longhorn.io
kubectl --context fraction -n longhorn-system get svc pvc-0b28d049-7da0-40f4-812a-122fe56161f3 pvc-baa41130-82c0-41ed-9df8-2569458615b6
```

- `list` が §2.1 の 8 行で、`UID_MATCH` が 8 行とも `yes`。行が違えば止める
- 4 つのボリュームが attached healthy、ShareManager の 2 つが running、Service の ClusterIP が 10.254.0.67 と 10.254.0.4
- 段の作業（kubelet・controller-manager の入れ替え）と重ねない

#### 2.6.2 書き換え

```bash
ADMIN_TOKEN=$(kubectl --context fraction create token infra-admin -n kube-system --duration=1h)
export KUBECTL="kubectl --context fraction --token=$ADMIN_TOKEN"
date -u +%FT%TZ
```

次の順に 1 つずつ、`--dry-run` → 書き換え → 確認、を流す。dry-run の `after` が v1beta2 で、kind・name・uid が `before` と同じことを見てから書き換える。

| # | `<resource> <name>` |
|---|---|
| 1 | `services pvc-0b28d049-7da0-40f4-812a-122fe56161f3` |
| 2 | `services pvc-baa41130-82c0-41ed-9df8-2569458615b6` |
| 3 | `sharemanagers.longhorn.io pvc-0b28d049-7da0-40f4-812a-122fe56161f3` |
| 4 | `sharemanagers.longhorn.io pvc-baa41130-82c0-41ed-9df8-2569458615b6` |
| 5 | `engines.longhorn.io pvc-1d94c3ed-6b77-4077-83c1-cea28fb76628-e-29bded80` |
| 6 | `engines.longhorn.io pvc-c6fbd833-21ba-42db-8d6e-1093481307f2-e-d0ea8a1d` |
| 7 | `engines.longhorn.io pvc-0b28d049-7da0-40f4-812a-122fe56161f3-e-58b23836` |
| 8 | `engines.longhorn.io pvc-baa41130-82c0-41ed-9df8-2569458615b6-e-1caaf475` |

```bash
$T fix <resource> <name> --dry-run
$T fix <resource> <name>
```

Service から始めるのは、もし消えても Longhorn が作り直し、データに関わらないため（Engine は消えるとボリュームが止まる）。

それぞれの後に確かめる（変わっていないこと）:

- Service: 残っていて ClusterIP が同じ。ShareManager が running
- ShareManager: 残っていて uid が同じ、running。share-manager の Pod が作り直されていない
- Engine: 残っていて running。ボリュームが attached healthy、`status.currentNodeID` が同じ

```bash
kubectl --context fraction -n longhorn-system get volumes.longhorn.io,engines.longhorn.io,sharemanagers.longhorn.io | grep <volume>
kubectl --context fraction -n longhorn-system get svc,pods | grep <volume>
```

どれかが消えた・変わったら、そこで止めてユーザーに知らせる（§2.6.4）。

#### 2.6.3 後の確認

- `KUBECTL="kubectl --context fraction" $T list` がヘッダーだけ
- 書き換えてから 17 分（GC の再試行の上限 1000 秒）以上たってから、controller-manager の leader のログに、書き換えた時刻より後の `REST mapping for longhorn.io` が無い。leader は `kubectl --context fraction -n kube-system get lease kube-controller-manager -o jsonpath='{.spec.holderIdentity}'` の `_` より前

```bash
kubectl --context fraction -n kube-system logs <leader の Pod> --since=30m | grep 'REST mapping for longhorn'
```

- 直った後の最初の再試行で、書き換えた 8 つが 1 回ずつ `"item has at least one existing owner, will not garbage collect"` になり、それきり出なくなる（2026-10-20 の本番はそうだった。`grep 'will not garbage collect'`）

- 4 つのボリュームが attached healthy、Pod の再起動なし
- `unset ADMIN_TOKEN KUBECTL`

#### 2.6.4 戻し方

- 書き換えだけを戻すなら `$T undo <resource> <name>`（`apiVersion` を v1beta1 に戻す。GC のエラーも戻る）。普通は要らない
- スクリプトの確認のとおりなら GC は何も消さない。それでも消えたときは、元に戻す操作をせずに止める。Service は ShareManager の reconcile で Longhorn が作り直す（ClusterIP は変わるので、マウントしている Pod の作り直しが要る）。Engine・ShareManager が消えた場合は、ボリュームの状態を見てユーザーが判断する

## 3. orphan

### 3.1 一覧（2026-10-20）

`orphans.longhorn.io` は 12 個で、どれも type `replica`（replica のデータの置き場所）、`DataCleanable=True`、`Error=False`。`orphan-resource-auto-deletion` は空（自動削除は無効）、`orphan-resource-auto-deletion-grace-period` は 300。

ディレクトリはノードに SSH して読んだ（`sudo du`、`stat`、`volume.meta`）。「実使用」は `du -sh`、「見かけ」は `du -sh --apparent-size`（sparse のファイルの大きさ）。「最終更新」はディレクトリの中で一番新しいファイルの日付で、そのころまで replica として使われていたと見られる。

| ノード | orphan | DataName（`<DiskPath>replicas/` の下） | ディスク | ボリューム | 実使用 / 見かけ | 最終更新 |
|---|---|---|---|---|---|---|
| oeilvert | `orphan-1eb55a24…` | `pvc-c4944b75-7ed0-4cf4-adce-bb5723993ff8-7dade898` | `/var/lib/longhorn2/` | 今ある: `fs/h2`（attached healthy、replica 2） | 9.2G / 901G | 2026-06-18 |
| oeilvert | `orphan-373d8f8d…` | `pvc-625c8825-4571-43d8-9119-c006a4a48399-9d2b30c9` | `/var/lib/longhorn2/` | 今ある: `monitoring/prometheus-kube-prometheus-db-prometheus-kube-prometheus-0`（attached healthy、replica 1） | 9.7G / 41G | 2026-09-05 |
| oeilvert | `orphan-06546f11…` | `pvc-baa41130-82c0-41ed-9df8-2569458615b6-75f06f11` | `/var/lib/longhorn/` | 今ある: `homegallery/ero-data`（attached healthy、replica 2） | 6.0G / 41G | 2022-09-18 |
| oeilvert | `orphan-d0bb6087…` | `pvc-3d784a2b-11af-409f-81f7-fd1d50542893-aa6acdb3` | `/var/lib/longhorn2/` | 無い | 10G / 21G | 2024-05-12 |
| oeilvert | `orphan-6a6ca268…` | `pvc-33c6c783-fe55-4dd6-b172-cf8c35df367c-044e0644` | `/var/lib/longhorn/` | 無い | 16G / 41G | 2022-09-19 |
| oeilvert | `orphan-ea9813d8…` | `pvc-ba224143-f16a-4a4f-86eb-dd267ec9fcdc-89c1c4dd` | `/var/lib/longhorn/` | 無い | 10G / 21G | 2022-09-19 |
| oeilvert | `orphan-63d8f1a7…` | `pvc-23f76055-5f9a-45c1-abc8-5e795809351b-002c3396` | `/var/lib/longhorn/` | 無い | 506M / 17G | 2022-09-19 |
| oeilvert | `orphan-efd8f681…` | `pvc-1e167175-a508-4fd6-817a-c85e5a5edf9b-a6fa6fdd` | `/var/lib/longhorn/` | 無い | 2.3M / 21G | 2022-03-16 |
| duchamp | `orphan-b59387893…` | `pvc-c6fbd833-21ba-42db-8d6e-1093481307f2-155a01f7` | `/var/lib/longhorn/` | 今ある: `fs/sites`（attached healthy、replica 2） | 5.8G / 41G | 2024-05-12 |
| duchamp | `orphan-b5c07e9d…` | `pvc-9b304208-f60d-4097-bffd-85ad4bb0951d-1ca131a3` | `/var/lib/longhorn/` | 無い | 4.7G / 17G | 2024-05-12 |
| duchamp | `orphan-b73236f3…` | `pvc-8af6876b-6ead-49de-8f3a-4f43fba95b3c-b1d50f90` | `/var/lib/longhorn/` | 無い（`open-webui/open-webui-pipelines`。2026-10-19 に消した） | 98M / 4.1G | 2025-01-27 |
| pablo | `orphan-89c30906…` | `pvc-c6fbd833-21ba-42db-8d6e-1093481307f2-4207d544` | `/var/lib/longhorn/` | 今ある: `fs/sites`（attached healthy、replica 2） | 6.2G / 61G | 2026-06-09 |

orphan の名前の全体は §3.4.2 の表にある。

- 実使用の合計は約 78 GiB（oeilvert 61.4G、duchamp 10.6G、pablo 6.2G）。ディスクの空きは oeilvert `/var/lib/longhorn` 207G・`/var/lib/longhorn2` 1.5T、duchamp 1.5T、pablo 1.7T で、困ってはいない
- **今の replica と重ならない**: 3 台の `replicas/` の下のディレクトリは 35 個で、どれも「今の Replica の `dataDirectoryName`」か「orphan の DataName」のどちらか一方だけに当たる。両方に当たるものも、どちらにも当たらないものも無い。今の Replica で、ディレクトリが無いものも無い
- 今あるボリュームの 5 個は、その後に replica が別の場所で作り直された古い replica のディレクトリ（`fs/sites` は今 duchamp `-e2abe59c` と oeilvert `-08528dea`、`fs/h2` は oeilvert `-c74b2ab6` と chirico `-b9c82d7d`、`homegallery/ero-data` は oeilvert `/var/lib/longhorn2/…-616884a4` と pablo `-af7ddd87`、`prometheus-…-0` は chirico `-15975080`）。`volume.meta` の `Rebuilding: true` が 3 つ（`fs/h2`、`prometheus-…-0`、`1e167175`）で、rebuild の途中で使われなくなったもの
- 消したボリュームの 7 個のうち、名前が分かったのは `pvc-8af6876b`（`open-webui/open-webui-pipelines`。`docs/worker-os-upgrade/results/duchamp.md`）だけ。2026-10-19 にユーザーが消したアプリ（MinIO、open-webui、hedgedoc など）か、それより前に消えたもの。最終更新が 2022-09 のものが 4 つある
- orphan の CR の作られた日（2026-10-19 07:40Z〜2026-10-20 02:32Z）は、§3.3 の作り直しの日で、ディレクトリができた日ではない

### 3.2 orphan の CR を消すとデータが消える

- 上流の文書（Longhorn v1.11.2「Orphaned Data Cleanup」）: `kubectl -n longhorn-system delete orphan <name>` で「the corresponding orphaned replica directory will be deleted」。手で消したときは grace period を待たずにすぐ消す
- コード（longhorn-manager v1.11.2 `controller/orphan_controller.go`）: CR に `DeletionTimestamp` が付くと、`cleanupOrphanedResource` が次のように動き、終わったら finalizer を外して `OrphanCleanupCompleted` のイベントを出す
  - CR の `spec.nodeID` のノードの manager が処理するときで、`DataCleanable` が True なら、`<DiskPath>/replicas/<DataName>` を消す（`deleteOrphanedReplicaDataStore`。ログ「Deleting orphan … replica data store … in disk … on node …」）
  - `DataCleanable` が True でないとき（ノードが down、ディスクが無い・変わった・evict 中）は CR だけを消す（ログ「Only delete orphan … resource object and do not delete the orphaned data store」）。別のノードの manager が処理したときも CR だけ（「Orphan does not belong to this controller. Skipping resource cleanup」）
- dev で確かめた（2026-10-20 03:35〜03:36Z）: 192.168.22.121 の `/var/lib/longhorn/replicas/` に、`volume.meta`（既存の replica のもの）と 8MiB のファイルを入れた偽のディレクトリ `pvc-00000000-0000-4000-8000-0000000000aa-deadbeef` を作った。30 秒で orphan（`DataCleanable=True`）ができた。CR を消すと、`OrphanCleanupCompleted` のイベントと、そのノードの manager のログ「Deleting orphan … replica data store pvc-00000000-…-deadbeef in disk /var/lib/longhorn/ on node 192.168.22.121」が出て、ディレクトリは消えた。dev はこれで元の状態
- Longhorn が orphan とするのは、`replicas/` の下で名前が replica の形をしていて、`volume.meta` が読め、同じディスク（uuid とパス）のどの Replica の `dataDirectoryName` でもないディレクトリ（`controller/monitor/disk_monitor.go` の `getOrphanedReplicaDirectoryNames`）。evict 中のノード・ディスクのものは orphan にしない

### 3.3 kubelet の再起動で作り直される理由

段 4 の oeilvert の `install kubelet` で、orphan の 3 つ（`orphan-1eb55a24…`、`orphan-373d8f8d…`、`orphan-ea9813d8…`）が消えて同じ名前で作り直された（`results/stage-4/oeilvert.md`）。oeilvert の longhorn-manager（`longhorn-manager-wn5sl`）のログで経路を確かめた。

1. kubelet の再起動の間、longhorn-manager の Pod が一時的に Ready でなくなり、Longhorn のノードが down（「Node oeilvert is down: manager pod … is not running」）、ディスクが not ready になる。orphan の `DataCleanable` は False（NodeUnavailable）になる
2. `DataCleanable` が False の orphan は、データに届かないものとして CR の削除が出される（コードでは node controller の `canDeleteOrphan`。誰が削除を出したかはログに出ないので、確かめていない）。orphan controller は False なので CR だけを消す（02:32:44Z「Only delete orphan … resource object and do not delete the orphaned data store」、`OrphanCleanupCompleted`）
3. ノードとディスクが戻ると、ディスクの監視（30 秒ごと）がディレクトリを再び見つけ、node controller が orphan を作り直す（02:32:57Z、duchamp の manager の webhook のログに 3 つの CREATE）。名前は `orphan-` とノード・ディスク・パス・ディスクの uuid・DataName のハッシュなので同じになる

8 個のうち 3 個だけだったのは、down の 1 秒ほどの間に `DataCleanable` が False になった orphan がそれだけだったためと見ている（タイミングで変わる）。データは消えない。今の CR の作られた日も、それぞれのノードの作業の直後に当たる: 段 3 の duchamp の `install kubelet` の直後（2026-10-19 23:34:16Z、3 個）、段 2 の oeilvert の drain・`install kubelet`・再起動（09:00:36Z）の後（09:04:28Z、5 個）、段 2 の pablo の `install kubelet`（07:38:54〜07:39:14Z）の後（07:40:46Z、1 個）。

### 3.4 消す手順（承認の後に流す）

#### 3.4.1 前の確認（読み取りだけ）

```bash
K="kubectl --context fraction -n longhorn-system"
$K get orphans.longhorn.io -o json | jq -r '.items[] | [.metadata.name, .spec.nodeID, .spec.parameters.DiskPath + "replicas/" + .spec.parameters.DataName, (.status.conditions | map(.type + "=" + .status) | join(","))] | @tsv'
# 今の Replica と重ならないこと（何も出ない）
$K get orphans.longhorn.io -o json | jq -r '.items[].spec.parameters.DataName' | sort > /tmp/orphan-data.txt
$K get replicas.longhorn.io -o json | jq -r '.items[].spec.dataDirectoryName' | sort > /tmp/replica-data.txt
comm -12 /tmp/orphan-data.txt /tmp/replica-data.txt
$K get volumes.longhorn.io
```

- orphan が §3.1 の 12 個（名前・ノード・DataName が同じ）で、どれも `DataCleanable=True`、`Error=False`
- `comm` が何も出さない
- ボリュームが全部 attached healthy（detached の `homegallery/cg-data` は前から）
- 段の作業（kubelet の入れ替え）と重ねない。重なると `DataCleanable` が False になり、CR だけが消えて作り直される（害は無いが消えない）
- 消したボリュームの 7 個に残したいデータがあるなら、先にノードで写す（例: `sudo tar -C /var/lib/longhorn/replicas -cSf <退避先>/<DataName>.tar <DataName>`。`-S` で sparse を保つ）。replica のディレクトリは Longhorn の replica の形式（`volume-head-*.img` と snapshot の差分）で、中身のファイルシステムを読むには Longhorn に戻すなどの手間が要る

#### 3.4.2 1 つずつ消す

```bash
ADMIN_TOKEN=$(kubectl --context fraction create token infra-admin -n kube-system --duration=1h)
kubectl --context fraction --token="$ADMIN_TOKEN" -n longhorn-system delete orphans.longhorn.io <orphan の名前>
```

順は、データの小さいものを最初に流して手順を確かめ、消したボリュームのもの → 今あるボリュームのもの、とする。

| # | ノード | orphan | DataName の末尾 | 種類 |
|---|---|---|---|---|
| 1 | oeilvert | `orphan-efd8f6810125c2bcbbb86bda13dace3975b049c9e932a232d05993b9d75e147b` | `pvc-1e167175-…-a6fa6fdd` | 消したボリューム（2.3M） |
| 2 | oeilvert | `orphan-63d8f1a742c054bfc4f847df02edf49cb517f49c4d64ad58dd91519429779bb4` | `pvc-23f76055-…-002c3396` | 消したボリューム |
| 3 | oeilvert | `orphan-6a6ca268699f2096778a92777f4649462432745fe212cebe2c22f1d7f2855528` | `pvc-33c6c783-…-044e0644` | 消したボリューム |
| 4 | oeilvert | `orphan-ea9813d82e5b8838a3df0301b31d8adbde33ac32b57a10163984a2891f39bbec` | `pvc-ba224143-…-89c1c4dd` | 消したボリューム |
| 5 | oeilvert | `orphan-d0bb60873cbfb870641d56c0ebfa8e447be2d079b784d8f45f57c23d3b5392f2` | `pvc-3d784a2b-…-aa6acdb3` | 消したボリューム |
| 6 | duchamp | `orphan-b5c07e9d3629b559c73604185f87953da4fadaa7fafec1d3e1a529ef5e240518` | `pvc-9b304208-…-1ca131a3` | 消したボリューム |
| 7 | duchamp | `orphan-b73236f3b86c7f88dec26b70a474c5348103a0d86b23e842f05fcd773484a299` | `pvc-8af6876b-…-b1d50f90` | 消したボリューム |
| 8 | oeilvert | `orphan-06546f11eef87f1f2e1e7261295c4f41128a7b1c5bced3caf9fdb7728e9ac2b0` | `pvc-baa41130-…-75f06f11` | `homegallery/ero-data` の古い replica |
| 9 | oeilvert | `orphan-1eb55a24cd1ceb1db76cb2892a98f760652e8274ee8204d5d9931e98fb7b98f7` | `pvc-c4944b75-…-7dade898` | `fs/h2` の古い replica |
| 10 | oeilvert | `orphan-373d8f8d388973dae902858607f3d874cded5746738e8c56352de8b31d833c2e` | `pvc-625c8825-…-9d2b30c9` | `prometheus-…-0` の古い replica |
| 11 | duchamp | `orphan-b59387893915a5e742166600dde7ca031c9e673c6c2b5ed70b7742fae39da3cf` | `pvc-c6fbd833-…-155a01f7` | `fs/sites` の古い replica |
| 12 | pablo | `orphan-89c30906e7e7af796a7756b72b6135b9d8696c0f1b8370e30dea68832c206539` | `pvc-c6fbd833-…-4207d544` | `fs/sites` の古い replica |

それぞれの後に確かめる:

- `kubectl delete` が返り、CR が無い。`kubectl --context fraction -n longhorn-system get events --field-selector involvedObject.name=<orphan>` に `OrphanCleanupCompleted`
- そのノードの longhorn-manager のログに「Deleting orphan <orphan> replica data store <DataName> in disk <DiskPath> on node <ノード>」がある（「Only delete orphan … resource object」なら、データは残っている。CR が作り直されるのを待って、`DataCleanable=True` を確かめてから消し直す）

```bash
kubectl --context fraction -n longhorn-system logs <そのノードの longhorn-manager の Pod> -c longhorn-manager --since=5m | grep <orphan>
```

- ノードでディレクトリが無い: `ssh yuanying@<ノードの IP> 'sudo test -e <DiskPath>replicas/<DataName> && echo STILL-THERE || echo gone'`
- 1 分待って、同じ名前の orphan が作り直されていない
  - 消した数秒後に、Longhorn が同じ名前の orphan を新しい uid で作り直し、20〜25 秒後に自分で消すことがある（2026-10-20 の本番は 12 個のうち 7 個。イベントの `OrphanCleanupCompleted` が uid 2 つ分出る）。ディスクの監視が削除の前に読んだ一覧を使うためと見ている。作り直した CR を消すときも同じディレクトリを消すだけなので、データには影響しない。`kubectl delete` の直後の `get` で CR が見えても、1 分待ってから判断する
- 8〜12（今あるボリューム）では、そのボリュームが attached healthy のままで、Replica の数と名前・状態が前と同じ（`kubectl --context fraction -n longhorn-system get replicas.longhorn.io -l longhornvolume=<ボリューム>`）

最後に、orphan が 0 個で、全ボリュームが前と同じ状態であることを確かめ、`unset ADMIN_TOKEN` する。

ノードごとにまとめて消す方法もある（`kubectl -n longhorn-system delete orphans.longhorn.io -l longhorn.io/orphan-type=replica,longhornnode=<ノード>`。上流の文書の例は `orphan-type=replica-instance` だが、replica のデータの orphan のラベルは `replica`）。12 個なので 1 つずつ流す。

#### 3.4.3 戻し方

無い。消したディレクトリは戻らない。どれも今の replica・ボリュームには使われていないので、ボリュームへの影響は無い（§3.1）。

### 3.5 `orphan-resource-auto-deletion` を有効にするか

推奨: **無効のまま**（今の値は空）にし、orphan が出たら中身を見てから手で消す。

- 自動削除を有効にすると（値に `replica-data` を入れる）、orphan の CR ができてから grace period（今は 300 秒）がたつと、データごと消える。取り消せない
- 新しい orphan ができるのは、replica の CR がノードやディスクの down の間に消された場合（上流の文書）など、障害のときが多い。そのデータが、壊れたボリュームを戻す手がかりになることがある。本番には replica 1 のボリューム（`prometheus-…-0`、`prometheus-…-1`）がある
- orphan はめったに増えない（今の 12 個は 2022〜2026-09 の分）。手で消す手間は小さい
- kubelet の再起動で CR が作り直されても、データは消えない（§3.3）。有効にした場合は、作り直しで grace period が数え直されるだけ
- 有効にするなら、`kubectl` で直接ではなく fleet-infra の Longhorn の設定（`infrastructure/longhorn/prod/` の Setting、または `longhorn-default-setting`）に入れる

代わりに、段の健全性の確認や Longhorn の更新の前後で orphan の数を見る（`kubectl -n longhorn-system get orphans.longhorn.io`）。増えていれば、§3.1 の調べ方で中身を確かめて消す。

## 4. 参照

- longhorn-manager v1.11.2: `datastore/longhorn.go`（`GetOwnerReferencesForVolume`）、`controller/volume_controller.go`、`controller/share_manager_controller.go`、`controller/orphan_controller.go`、`controller/node_controller.go`（`syncOrphans`、`canDeleteOrphan`）、`controller/monitor/disk_monitor.go`、`upgrade/v18xto190/upgrade.go`
- Kubernetes v1.33.13: `pkg/controller/garbagecollector/garbagecollector.go`（`attemptToDeleteWorker`、`isDangling`）、`graph_builder.go`（`addDependentToOwners`、`processGraphChanges`）
- longhorn/longhorn#7943、#10249、#10250（v1beta1 の廃止と CR の書き直し）、#10869、#3407
- kubernetes/kubernetes#102641（CRD の版を外した後に GC が owner を引けない）、#136040（v1.36 でログを `V(5).Info` に）
- Longhorn v1.11.2 の文書「Orphaned Data Cleanup」（`https://longhorn.io/docs/1.11.2/advanced-resources/data-cleanup/orphaned-data-cleanup/`）
- `docs/k8s-upgrade/results/stage-4/summary.md`（§2.2、§3 の申し送り）、`results/stage-4/oeilvert.md`（orphan の作り直し）
