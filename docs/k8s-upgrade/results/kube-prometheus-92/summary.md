# kube-prometheus-stack 92.13.1 の記録

本番 `fraction` の kube-prometheus-stack を chart 85.2.1 から 92.13.1 へ上げた（2026-10-26）。手順は `../../runbook-kube-prometheus-92.md`（以下 runbook）、前の状態は `baseline.md`。材料は `render/kube-prometheus-92/` の `92.13.1-crds.yaml`・`92.13.1-rest.yaml`（fleet-infra `675f543` の render。当日の main の render とバイト列が同じ）。
時刻は UTC。`snap.sh`・`targets.sh`・`apps.sh`・`node-state.sh` の出力（`after/`・`late/`）、apply の出力、監視のログは、タスクディレクトリの `notes/kube-prometheus-92/` に置いた。

## 1. 経過

| 時刻 | できごと |
|---|---|
| 00:10〜00:12 | ベースライン、監視の起動（bg1）、`infra-admin` のトークンの発行（00:11:41Z、2 時間）、§2.6 の diff と dry-run（`baseline.md`） |
| 00:12〜01:00 | CRD の dry-run の Warning（`baseline.md` §4）で止めて coordinator に報告。ユーザーが「止める理由にしない、`--force-conflicts` は使わずに進める」と判断した |
| 01:01:06 | §3.1 の確認（監視の最後の行が 2 秒前、StatefulSet 2:2 と 2:2、Job なし、8 台 Ready、`SHA256SUMS` が 4 つとも OK、`auth can-i patch customresourcedefinitions` が `yes`） |
| 01:01:15.575〜01:01:19.391 | §3.2 CRD の `apply --server-side`。**rc 0、10 個とも `serverside-applied`、Warning は出なかった** |
| 01:01:30.724〜01:01:42.087 | §3.3 CRD 以外の `apply`（client-side）。**rc 0、`configured` 117・`created` 3・`unchanged` 5**（dry-run と同じ組） |
| 01:04:40 | 最後の rollout（Prometheus の StatefulSet 2/2）の完了 |
| 01:05:14〜01:05:36 | §4.2 の `after/` |
| 01:15:07 | §4.3 の `late/` |
| 01:15:20 | 監視の停止、トークンの破棄（§4.4） |

## 2. 出力（runbook §3.2・§3.3）

- CRD: `customresourcedefinition.apiextensions.k8s.io/<名前> serverside-applied` が 10 行。dry-run で出た last-applied の移行の Warning は、本番の apply では出なかった。apply の後、10 個とも `operator.prometheus.io/version: 0.94.1`、ラベル `crd: "true"`、Established `True`、`storedVersions` は 1 つずつ（v1 の 7 つが `v1`、3 つが `v1alpha1`）。generation は 9 つが 2、`prometheusrules` が 1（schema の差が無い）
- CRD 以外: `configured` 以外の行は `configmap/kube-prometheus-k8s-resources-nodes-overview created`、`job.batch/kube-prometheus-admission-create created`、`job.batch/kube-prometheus-admission-patch created`、`daemonset.apps/smart-exporter unchanged`、`prometheusrule.monitoring.coreos.com/prometheus-smart-rules unchanged`、`ingress.networking.k8s.io/{alertmanager,grafana,prometheus} unchanged`。エラーは無い

## 3. 入れ替わり（runbook §4.1。`mon-watch.log`、約 4 秒ごと）

| 時刻 | apply から | できごと |
|---|---|---|
| 01:01:35〜36 | +5 秒 | 新しい operator `kube-prometheus-operator-664c4f9785-rxptb`、Grafana `grafana-8677b879d8-rdst7`、kube-state-metrics `kube-state-metrics-74f47fffb8-hkj5k` が oeilvert に Pending。Job 2 つができる。node-exporter の 1 台目（.112）の入れ替わりが始まる |
| 01:01:40 | +10 秒 | 古い operator が新しい CR から StatefulSet を作り直す（中間の revision `prometheus-kube-prometheus-fcb767d96`・`alertmanager-kube-prometheus-5c77f879f4`）。Prometheus と Alertmanager の pod-1 が消え、oeilvert で作り直される。ready は 2 つとも 1 |
| 01:01:42 | +12 秒 | 古い operator が ServiceMonitor `kube-prometheus-operator` を `ca.crt` が無いとして拒否（`InvalidConfiguration`、count 2。§4 の 13） |
| 01:02:16 | +46 秒 | create Job が Secret `kube-prometheus-admission` を作り直す: **`Opaque` → `kubernetes.io/tls`、キーは `ca`・`ca.crt`・`cert`・`key`・`tls.crt`・`tls.key`、UID `f7fb10a4-…` → `cbff1b2e-1ac5-4363-80dc-2ed67bf59052`**。create・patch の Job が完了（どちらも 44〜45 秒。certgen 1.11.0 の pull を含む） |
| 01:02:23 | +53 秒 | **新しい operator が restart 0 で Ready**、古い operator `…-658779c859-zcrzg` が消える。新しい operator が StatefulSet をもう一度作り直す（最後の revision `prometheus-kube-prometheus-7ff77c67b7`・`alertmanager-kube-prometheus-8546966d9`） |
| 01:02:27〜31 | | 中間の revision の Alertmanager の pod-1（oeilvert、まだ起動していなかった）が `Failed` と出て作り直される |
| 01:02:36 | | 新しい kube-state-metrics が Ready、古いものが消える |
| 01:02:57 | | 新しい Grafana が Ready、古いもの（chirico）が `Succeeded` になって消える（01:03:00） |
| 01:02:57〜01:03:00 | | Prometheus の pod-1 が一度 Running になり、最後の revision のためにもう一度作り直される（oeilvert） |
| 01:03:04 | | node-exporter の 8 台目が Running。8 台とも新しい Pod |
| 01:03:08〜32 | | Alertmanager の pod-1 が Ready（oeilvert）。pod-0 が duchamp から消え、chirico で作り直されて Ready（01:03:32、StatefulSet 2/2） |
| 01:03:20 | | Job 2 つが TTL で消える |
| 01:03:40 | +2 分 10 秒 | Prometheus の pod-1 が Ready（oeilvert）。pod-0 が duchamp から消え、chirico で作り直される |
| 01:04:40 | +3 分 10 秒 | Prometheus の pod-0 が Ready（chirico）。StatefulSet 2/2 |

- **operator の restart は 0**。dev のように `/cert/tls.crt` が無くて落ちることは無かった（新しい operator のイメージの pull の間に、create Job が Secret を作り直し終えた）
- **StatefulSet の ready が 0 か空になる行は、Prometheus も Alertmanager も 0 行**（apply の後の 49 行）。Service 経由の `grafana=`・`prom=`・`am=` の失敗も 0 行
- Prometheus の Pod の入れ替わりは pod-1 が 2 回、pod-0 が 1 回（dev と同じ形）。Pod は duchamp・chirico から chirico・oeilvert に移り、Longhorn のボリュームも付け直された（pod-0 のものが chirico、pod-1 のものが oeilvert）

## 4. 確認（runbook §4.2。01:05Z の `after/`）

| # | 確認 | 結果 |
|---|---|---|
| 1 | operator | 1/1、v0.94.1、restart 0。ログの `level=error` は 0 行 |
| 2 | admission | Secret が `kubernetes.io/tls`、キー 6 つ（上）。webhook 2 つがある。Job は消えている |
| 3 | Prometheus | StatefulSet 2/2（generation 19、revision `prometheus-kube-prometheus-7ff77c67b7`）。2 つの Pod が `v3.15.0-distroless` と config-reloader `v0.94.1`、restart 0。CR は generation 18、Available・Reconciled `True`。`apps.sh` で 3.15.0、reload が成功、**ルール 286 個とも ok**（284 から 2 つ増えた）、`err` は空 |
| 4 | Alertmanager | 2/2（generation 3、revision `alertmanager-kube-prometheus-8546966d9`）、`v0.34.1`、restart 0。2 つとも cluster `ready`、peers 2 |
| 5 | StatefulSet の rollout の間 | ready が 0 か空になる行は 0（§3） |
| 6 | Grafana | 1/1、`13.2.4-distroless` と k8s-sidecar `2.14.1`、restart 0。`/api/health` が `database: ok`、`13.2.4`。advisor の件（runbook §8.4）は出なかった（`SQLITE_BUSY` の retry の info はあるが、`grafana-advisor-app` の error は無く、`level=error` は 0 行） |
| 7 | kube-state-metrics・node-exporter・smart-exporter | kube-state-metrics 1/1 で `v2.20.0`。node-exporter 8/8 で `v1.12.1-distroless`、8 台とも新しい Pod。**smart-exporter の 8 つの Pod の名前・UID・restart はベースラインと同じ** |
| 8 | ターゲット | 2 つの Prometheus とも 65 個すべて up（01:05:3x。§4.3 でも見た） |
| 9 | control-plane の scrape | `credentials_file` 9 のまま、`ca_file` の SA の `ca.crt` が 6 → 0、ConfigMap `kube-root-ca.crt` が 0 → 6、`bearer_token_file` 0。control-plane のターゲットはすべて up。`prometheus-kube-prometheus-tls-assets-0` のキーに `kube-root-ca.crt` の CA が足された |
| 10 | SA token の Secret | `kube-system/infra-admin` と `infra-auditor` の 2 つだけ |
| 11 | grafana-test | pod・cm・sa とも NotFound |
| 12 | CRD | 10 個とも 0.94.1、ラベル `crd: "true"`、`storedVersions` 1 つずつ、Established。last-applied を持つ 4 つは、注釈が残って新しい内容（42,592 B・42,434 B・8,484 B・43,227 B）になり、managedFields は `kubectl-last-applied`（Apply）・`kubectl`（Apply）・`kube-apiserver`（Update/status）。`kubectl-client-side-apply` は無くなった |
| 13 | `InvalidConfiguration` | 1 件だけ: 古い operator が 01:01:42Z に ServiceMonitor `kube-prometheus-operator` を「`ca.crt` が無い」で拒否（count 2、最後は 01:01:42.41Z）。新しい operator が Ready になった 01:02:23Z より前で、その後は出ていない |
| 14 | PVC | 2 つとも UID がベースラインと同じ（`625c8825-…`・`99c35b80-…`）で Bound。**PVC の作り直し（§5.2）はしていない**。Longhorn のボリュームは 2 つとも attached・healthy |
| 15 | Prometheus のデータ | 2 つともブロック 16、最も古いサンプル 2026-10-16 00:00:00Z（`1792108800`）。ベースラインの 10-15 06:00Z から進んだのは保持 10 日によるもの（最も古いブロックが期限で消えた）で、更新の前のデータは引ける（§5） |
| 16 | ほかの名前空間 | `monitoring` 以外の Pod は、名前・UID がベースラインと同じ（CronJob `aphrael/tumblr-like` の Completed の Pod が 1 つ入れ替わっただけ）。**restartCount が増えたのは chirico の `shja2/movies-69bf4c594c-ddxtm` と `carib2/movies-78dc5856b6-lflxg`（21 → 22）で、どちらも OOMKilled（00:18:25Z・00:18:52Z）**。apply（01:01:30Z）の 43 分前で、前の起動は 2026-10-25 21:18Z（約 3 時間ごとの OOM）。この更新とは関係が無い。Running / Completed 以外は 0 |
| 17 | kubelet | 8 台の MainPID・NRestarts・ActiveEnterTimestamp がベースラインと同じ |
| 18 | last-applied | `lastapplied-diff.sh 92.13.1-rest.yaml` が `SAME=123 DIFF=0 MISSING=2`（Job 2 つ） |
| 19 | 本番の Secret | `grafana`・`alertmanager-kube-prometheus`・Ingress の TLS 3 つの型・キーの名前・UID がベースラインと同じ |
| 20 | operator が作るもの | `kube-system/kube-prometheus-kubelet` の UID が同じ（`55a054e0-…`）。kubelet のターゲットは 8×3 |
| 21 | Ingress | 外からの 3 つとも `401`。Ingress の spec と address が同じ。`mon-watch.log` の最後の行で `grafana=ok prom=Prometheus Server is Ready. am=OK` |
| 22 | 健全性 | 8 台 Ready、VIP の `/readyz` が 200。Longhorn は attached・healthy 16、detached 1（以前から） |

## 5. 10 分おいた見直し（runbook §4.3）

01:15:07Z（最後の rollout の完了から 10 分 27 秒）に `targets.sh`・`apps.sh` を `late/` に取った。**合格。**

- ターゲットは 2 つの Prometheus とも 65 個すべて up。ルールは 286 個とも ok。reload は成功。operator のログの error は 0 行
- `InvalidConfiguration` は §4 の 13 の 1 件（01:01:42Z）のままで、新しいものは無い
- `monitoring` の Pod 23 個がすべて Running・Ready。新しい Pod の restart は 0
- Prometheus のデータ（§5）: 2 つともブロック 16、最も古いサンプル 2026-10-16 00:00Z、ブロック約 7.16 GB（pod-0）・7.19 GB（pod-1）。apply の 10 分前（00:51:30Z）から 01:15Z までの control-plane の job の `up` の 1 分ごとのサンプル数（`late/up-range.txt`）は、どの job も 0 になる分が無い。減ったのは、pod-0 が自分の入れ替わりの 01:04Z ごろの 2 分（kubelet 80 → 9・63）、pod-1 が 01:02〜03Z ごろ（kubelet 80 → 14・78。apiserver と coredns は 2 分ぶんの点が無い）で、それぞれ自分の Pod の入れ替わりの分だけ。apply の前の時間の値も引ける

## 6. 後片付け（runbook §4.4）

- 01:15:20Z に `touch logs/mon.stop` で監視（bg1）を止めた。ログは 961 行。apply の後の行で、StatefulSet の ready が 0 か空のものは 0 行、Service 経由の失敗は 0 行
- `/tmp/kp-upg-admin-token` を消した（トークンはシェルの変数に置かず、コマンドごとにファイルから読んだ）。トークンを使ったのは §2.6 の diff と dry-run、§3.2・§3.3 の apply だけ

## 7. 手順書との差

- **CRD の dry-run の Warning**（`baseline.md` §4）。runbook §2.6 は「`conflict` の文字が出たら止める」としていたので止めた。ユーザーが止める理由にしないと判断し、`--force-conflicts` は使わずに進めた。本番の apply では Warning も出なかった。runbook §2.6・§3.2・§6 を、この Warning と apply の conflict を分ける形に直した（この PR）
- `prometheusrules` の CRD は generation が 1 のまま（schema の差が無い）。runbook §2.6 に書いた
- 新しい operator の restart は 0（dev は 2）。runbook §4.1 の表に書いた
- ルールは 284 → 286
