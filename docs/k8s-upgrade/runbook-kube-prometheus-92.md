# kube-prometheus-stack を chart 85.2.1 から 92.13.1 へ上げる手順書（本番 `fraction`）

本番クラスタ `fraction` の kube-prometheus-stack を chart 85.2.1 から 92.13.1 に上げる手順。fleet-infra の `infrastructure/kube-prometheus/prod/` の render を CRD と CRD 以外に分け、`infra-admin` の短命トークンで、**CRD は server-side apply、CRD 以外は client-side apply** で流す。
計画 `plan.md`（以下「計画」）§8 の非クリティカルなコンポーネントの 4 つ目。前の metrics-server（`runbook-metrics-server-0.9.md`。以下「metrics-server の手順書」）と同じく fleet-infra が持ち、porkadot を使わない。**このリポジトリの `assets/` と `porkadot.yaml` は変わらない。** ノードにも etcd にも control-plane にも触らない。

| | 更新前 | 更新後 |
|---|---|---|
| 材料 | fleet-infra `9a08fb9` の render（本番の last-applied と同じ。§2.2 の 14） | **fleet-infra `675f543`（#206 のマージ）の render**。main も `675f543`（§1.4） |
| prometheus-operator・config-reloader | v0.90.1 | **v0.94.1** |
| Prometheus | v3.11.3-distroless | **v3.15.0-distroless** |
| Alertmanager | v0.32.1 | **v0.34.1** |
| Grafana | 13.0.1-security-01、k8s-sidecar 2.7.3 | **13.2.4-distroless**、k8s-sidecar 2.14.1 |
| kube-state-metrics | v2.19.0 | **v2.20.0** |
| node-exporter | v1.11.1-distroless | **v1.12.1-distroless** |
| kube-webhook-certgen（admission の Job） | 1.8.3 | **1.11.0** |
| smart-exporter（chart の外の追加。fleet-infra の `base/smartmon.yaml`） | node-exporter-smartmon 0.19.0 | 変わらない（`unchanged`） |
| CRD 10 個 | `operator.prometheus.io/version: 0.90.1` | **0.94.1**。served と storage の版は変わらない |
| Prometheus の PVC 2 つ（bronze 20Gi） | — | 変わらない見込み（作り直しになっても許す。§5） |
| K8s、etcd、kubelet、CoreDNS、MetalLB、Longhorn、porkadot、metrics-server | v1.37.1、3.7.3、… | 変えない |

fleet-infra#206（マージ `675f543`）は `scripts/update-kube-prometheus.sh` の `CHART_VER` を 92.13.1 にして生成物を作り直し、values で `prometheus.controlPlaneScrapeClass.enabled: true`・`prometheus.serviceAccount.createTokenSecret: false`（期限の無い SA token の Secret を作らず、control-plane の 7 つの ServiceMonitor を scrape class で Pod に投影された token で scrape する）と `grafana.testFramework.enabled: false`（`grafana-test` の Pod を作らない）を足したもの。各 major の upgrade notes、admission の Secret の型の変化、operator の RBAC と引数の変化、本番の last-applied と main の生成物が一致することは #206 の本文にある。

この手順は dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で先に通してある（2026-10-25 12:36〜12:56Z）。記録は porkadot-dev の `docs/k8s-upgrade/verification-kube-prometheus-92.md`（以下「dev の記録」。porkadot-dev#22、main `eaa017b`）。dev には kube-prometheus が無かったので、本番の形（`9a08fb9`）を入れてから `675f543` に上げ、`9a08fb9` に戻し、上げ直した。dev で分かったことは次のとおり。

- **順と方法**: CRD を `kubectl apply --server-side`（10 個とも `serverside-applied`、conflict なし、2 秒）→ CRD 以外を client-side の `kubectl apply -f`（`configured` 117・`created` 3・`unchanged` 5）。エラーも immutable なフィールドの拒否も出なかった
- **新しい operator は、admission の create Job が Secret `kube-prometheus-admission` を `kubernetes.io/tls` で作り直すまで 2 回落ちる**（`open /cert/tls.crt: no such file or directory`）。restart は 2 で止まり、apply から 38 秒で Ready。その間も古い operator は Ready のままだった
- **Prometheus・Alertmanager の StatefulSet は 2 回 rollout する**（まだ動いている古い operator が新しい CR から 1 回、替わった新しい operator がもう 1 回）。Prometheus の Pod の入れ替わりは計 3 回（pod-1 は 2 回）で、**どの時点でも少なくとも 1 つは Ready だった**。apply から Prometheus の rollout の完了まで 2 分 8 秒（Alertmanager は 1 分 20 秒）
- **operator が替わる間、ServiceMonitor が一時的に拒否される**（`InvalidConfiguration` のイベント。上げるときは古い operator が `kube-prometheus-operator` の ServiceMonitor を「`ca.crt` が無い」で 23 秒、戻すときは新しい operator が control-plane の 7 つを「scrapeClass が無い」で 3 秒）。替わった後は受け付けられ、ターゲットは全部 up に戻った
- control-plane の scrape は scrape class（`authorization.credentialsFile`）と ConfigMap `kube-root-ca.crt` の CA に切り替わり、ターゲット 34 個はどの時点でも全部 up。**期限の無い SA token の Secret は作られなかった**。`grafana-test` も無い
- Prometheus・Alertmanager は同じ PVC（UID 不変）のまま新しい版になり、上げる前の時間の `up` の値が引けた（ただし dev のデータは head と WAL だけで、ブロックは 0）
- **`9a08fb9` の CRD 以外の apply で 85.2.1 に戻せた**（CRD は新しいまま、古い operator はそれで restart 0 で動く）。`675f543` で上げ直せた
- **admission の Job は immutable で、`ttlSecondsAfterFinished: 60` で消える。** 前の apply から 60 秒以内に apply し直すと Job の更新が拒否されるので、`kubectl -n monitoring get jobs` が空になってから流す
- Grafana 13.2.4 は最初の起動でだけ `grafana-advisor-app` を読み込まなかった（`SQLITE_BUSY`）。データソースとダッシュボードは使えた

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **本番の CRD のうち 4 つ（`podmonitors`・`probes`・`prometheusrules`・`servicemonitors`）は、client-side apply の last-applied の注釈と `crd: "true"` のラベルを持ち、managedFields に `kubectl-client-side-apply` がある**（§2.2 の 9）。2026-05-22 の導入のとき、server-side の apply の後に `kubectl apply -k` も流し、小さい 4 つだけが client-side でも通ったものとみられる（推測）。dev はこの形を作らずに確かめた。`kubectl-client-side-apply` が持つのはラベル `crd` と last-applied の注釈だけ（2026-10-25 に読んだ）で、新しい render も同じラベルの値なので conflict は出ない見込み。server-side apply の後に last-applied の注釈が残るか消えるかは確かめていない（どちらでもよい。§2.6）
- **ブロックのある TSDB**。本番の Prometheus は 2 つとも 16 ブロック・約 7.6 GB、WAL 約 0.4〜0.5 GB、保持 10 日（§2.2 の 7）。Prometheus v3.15.0 が開けることは dev では確かめていない。**開けなくても止める条件にしない**（データは失ってもよい。§5）
- **本番の 8 台**（dev は 7 台、すべて amd64）。node-exporter と smart-exporter の DaemonSet は control-plane の Pi 5（arm64）にも載る。92.13.1 の 9 つのイメージには `linux/arm64` がある（#206）
- **render の外のもの**: `gated-system` の PodMonitor `gated` と PrometheusRule `gated`（fleet-infra の `apps/gated`）。新しい CRD でも同じ形のまま scrape されることを見る（§4.2）
- **Ingress**（gated。外から `401` を返す。§2.2 の 16）。dev には Ingress の controller が無かった

## 0. 役割と約束ごと

metrics-server の手順書 §0 と同じ形で、次のとおりにする。

- **承認の節目は 1 つ**。この手順書では ✋✋ を付けた。
  - ✋✋ **開始**: §2.5 の render とその差分（この手順書と同じ PR）、§2.2 のベースライン、§2.6 の `kubectl diff` と `--dry-run=server` の結果、§2.3 の監視、§2.7 の時間帯、§5 のデータの扱い（**PVC の作り直しを ✋ で行ってよいか**を併せて確かめる）、§6 の止める条件、§7 のロールバックの形を見せ、PR をマージしてから、CRD の apply の前（§3.1）
- **節目の後の手順は、ユーザーに知らせるだけで進めてよい（✋）。** CRD の server-side apply（§3.2）、CRD 以外の client-side apply（§3.3）、§5.2 の PVC の作り直し（開始の承認で認められた場合だけ）は、この手順書に書いた形なら ✋ で、1 つずつ承認を取るものではない。✋ の前に、何をするかを知らせる。
- **runbook から外れる操作（ロールバック、apply の流し直しより先の対処、`--force-conflicts`、Pod・Job・Secret の手での削除、StatefulSet・Deployment の手での編集・scale・`rollout undo`、CRD を古い版に戻すこと、イメージの手での pull、operator が作ったものの削除）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認は、知らせずに行ってよい。時刻はすべて UTC で記録する（control-plane のホストの時刻は JST）。

## 1. 前提

### 1.1 本番の今の姿

始める前に次を確かめる（読み取り）。2026-10-25 23:5xZ（この手順書を書いたとき）の値を書く。当日に読み直す。

- 8 台 Ready・schedulable、全台 v1.37.1、`containerd://2.3.6`。Pod は 169 個（Running 145、Completed 24）で、Running / Completed 以外は 0 個
- metrics-server の更新（`results/metrics-server-0.9/summary.md`）が済んでいる
- kube-prometheus-stack は chart 85.2.1 で、`monitoring` の Pod 23 個がすべて Running・Ready（§2.2 の 1〜3）。Prometheus のターゲットは 2 つとも 65 個すべて up（§2.2 の 12）

### 1.2 kubeconfig の運用

確認は `kubectl --context fraction`（`fraction-auditor`、read-only）で行う。`fraction-auditor` は `kubectl diff` も `--dry-run=server` も流せない（2026-10-25 に `auth can-i patch prometheuses -n monitoring` が `no`）。

**`infra-admin` の短命トークンを使う**（metrics-server の手順書 §1.2 と同じ形）。今回は監視の起動から §4.3 まで 1 時間を超えうるので、2 時間の期限にする。

```sh
kubectl --context fraction create token infra-admin -n kube-system --duration=2h > /tmp/kp-upg-admin-token
chmod 600 /tmp/kp-upg-admin-token
ADMIN_TOKEN=$(cat /tmp/kp-upg-admin-token)
kubectl --context fraction --token="$ADMIN_TOKEN" auth can-i patch customresourcedefinitions      # yes
kubectl --context fraction --token="$ADMIN_TOKEN" auth can-i patch prometheuses -n monitoring     # yes
kubectl --context fraction --token="$ADMIN_TOKEN" auth can-i create jobs -n monitoring            # yes
```

- `fraction-auditor` は `serviceaccounts/token` の create を持つ（2026-10-25 に `auth can-i create serviceaccounts --subresource=token -n kube-system` が `yes`）
- トークンを使うのは、§2.6 の diff と dry-run、§3.2・§3.3 の apply、§5.2 の PVC の作り直し、§7 の戻しだけ。確認（`get`、`logs`、proxy、監視）は `fraction-auditor` のまま
- 使い終わったら（§4.4 の後）破棄する（`unset ADMIN_TOKEN` と `/tmp/kp-upg-admin-token` の削除）。期限が切れていたら発行し直す
- 以下、`kubectl --context fraction --token="$ADMIN_TOKEN"` を `kubectl-admin` と書く
- **Secret の中身は読まない。** `fraction-auditor` は `monitoring` の Secret を get できる（2026-10-25 に `yes`）が、この手順書の確認は名前・型・キーの名前・UID だけを読む（§1.6 のスクリプトは `.data` の値を出さない）。Grafana の確認も、管理者のパスワードを使わず `/api/health` だけにする（dev の `grafana.sh` は本番では流さない）

### 1.3 SSH

metrics-server の手順書 §1.3 と同じ（worker は `ssh yuanying@<IP>`、control-plane は `ssh ubuntu@<IP>`。**名前ではなく IP で入る**。control-plane には `unset LC_ALL` してから入る）。2026-10-25 23:56Z にこの手順書を書いたとき、8 台ともサンドボックスの中から §1.6 の `node-state.sh` を流せた。SSH は読み取りだけに使う。

### 1.4 fleet-infra の render

材料はこの手順書と同じ PR に入れた render である（`render/kube-prometheus-92/`。§2.5）。当日はこの 4 つのファイルを使い、**当日にもう一度 fleet-infra の main を render して、同じバイト列であることを確かめる**（main が先に進んで `infrastructure/kube-prometheus/` が変わっていたら止める）。

```sh
F=/tmp/fleet-infra-kp
R=<このリポジトリの checkout>/docs/k8s-upgrade/render/kube-prometheus-92
git clone https://github.com/yuanying/fleet-infra.git $F
git -C $F log --oneline -1                                               # 2026-10-25 は 675f543
git -C $F log --oneline 675f543..HEAD -- infrastructure/kube-prometheus/  # 空
kubectl kustomize $F/infrastructure/kube-prometheus/prod/ > /tmp/kp-main.yaml
sha256sum /tmp/kp-main.yaml                                              # f5f2880f…（下の表）
yq 'select(.kind == "CustomResourceDefinition")' /tmp/kp-main.yaml | cmp - $R/92.13.1-crds.yaml && echo crds-same
yq 'select(.kind != "CustomResourceDefinition")' /tmp/kp-main.yaml | cmp - $R/92.13.1-rest.yaml && echo rest-same
(cd $R && sha256sum -c SHA256SUMS)                                       # 4 つとも OK
```

- 元の clone（`~/src/github.com/yuanying/fleet-infra`）の `.git` への書き込みはサンドボックスに拒否されるので、`/tmp` に clone する（metrics-server の手順書 §1.4 と同じ）。タスクディレクトリの `worktrees/fleet-infra-kp-rc` は origin がローカルの clone で、2026-10-25 に fetch しても main が `9a08fb9` のままだった。当日の照合には使わない
- 2026-10-25 23:5xZ に GitHub から clone し、`9a08fb9`・`675f543`・main（`675f543`）を `git archive` で取り出して render した。`675f543` と main は同じバイト列（sha256 `f5f2880f…`、5,306,863 B）、`9a08fb9` は `0506fbea…`（5,145,715 B）。どちらも dev の記録の prod の render（`notes/dev-kube-prometheus/render/<commit>-prod.yaml`）と sha256 が一致する
- 分け方は dev の記録と同じ `yq 'select(.kind == "CustomResourceDefinition")'` とその否定（yq v4.54.1）。分けた CRD の render は dev の `<commit>-crds.yaml`（test overlay の render から分けたもの）と同じ中身
- 作業端末の kubectl は v1.37.1（`kubectl kustomize` は kustomize v5.8.1）

### 1.5 入れる版を確かめる

作業の当日に確かめ直す（読み取り）。

```sh
curl -sL https://prometheus-community.github.io/helm-charts/index.yaml \
  | yq '.entries."kube-prometheus-stack"[0:3] | .[] | .version + " " + .created + " " + .appVersion'
```

2026-10-25 23:5xZ の時点: 最新は 92.13.1（2026-10-24 13:08Z、appVersion v0.94.1）。**当日に 92.13.2 や 93 などが出ていても、この手順は 92.13.1 で進める**（fleet-infra を上げ直すのは別の PR と dev の検証になる）。セキュリティの修正などで急ぐ理由が書かれていたら、止めて報告する。
イメージの `linux/arm64` は #206 で確かめた（node-exporter は control-plane にも載る）。

### 1.6 確認に使うスクリプト

タスクディレクトリの `notes/runbook-kube-prometheus/scripts/` に置いた（dev の `notes/dev-kube-prometheus/scripts/` を本番の値にしたもの）。どれも読み取りだけで、Secret の値を出さない。

| スクリプト | 中身 |
|---|---|
| `snap.sh <dir>` | `fraction-auditor` で、Node、全 Pod（UID・restartCount）、`monitoring` の Deployment・StatefulSet・DaemonSet（generation・Ready・revision・イメージ。yaml も）、Pod、Prometheus・Alertmanager の CR、PVC と Longhorn のボリューム、Secret（名前・型・キーの名前・UID だけ）、Job、events、ServiceMonitor などの数、Ingress、CRD（版の注釈・storage の版・`storedVersions`・ラベル `crd`・last-applied の有無・managedFields の manager・generation・UID）、webhook、ClusterRole など、SA token の Secret、`kube-system/kube-prometheus-kubelet` の Service、Running / Completed 以外の Pod。出力は `notes/runbook-kube-prometheus/<dir>/` |
| `targets.sh <dir>` | 2 つの Prometheus のターゲット（apiserver の pod proxy）。scrape pool ごとの数と up 以外 |
| `apps.sh <dir>` | Grafana の `/api/health`、Alertmanager の版と cluster の状態、Prometheus ごとの版・ルールの health・head・設定（`bearer_token_file`・`credentials_file`・`ca_file` の数）・reload・ブロック数・最も古いサンプルの時刻、operator のログの error の行数 |
| `mon-watch.sh <logdir>` | 3 秒ごとに `monitoring` の Pod（phase・Ready・restart・ノード）、Job、admission の Secret（型・キーの名前・UID）、PVC（UID）、StatefulSet（ready・updated・revision）、Grafana の `/api/health`、Prometheus と Alertmanager の Service 経由の `/-/ready` を `<logdir>/mon-watch.log` に 1 行。`<logdir>/mon.stop` を作ると止まる |
| `node-state.sh <dir>` | 8 台に IP で ssh し、kubelet の MainPID・NRestarts・ActiveEnterTimestamp と、containerd の kube-prometheus のイメージ |
| `lastapplied-diff.sh <rest.yaml>` | CRD 以外の render の各オブジェクトを、本番のオブジェクトの last-applied と比べる（`SAME` / `DIFF` / `MISSING` と数） |

当日の出力は、タスクディレクトリの `notes/kube-prometheus-92/`（`base/`、`after/`、`late/`、`logs/`）に置く（`snap.sh ../kube-prometheus-92/base` のように渡す）。この手順書を書いたときの出力は `notes/runbook-kube-prometheus/base-20261025/` にある。

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 流し方 | **2 回に分ける**。CRD は `kubectl-admin apply --server-side -f 92.13.1-crds.yaml`、CRD 以外は `kubectl-admin apply -f 92.13.1-rest.yaml`（client-side）。理由は §3.4 | dev の記録、#206 の「CRD」 |
| 2 | 順 | CRD → CRD 以外。CRD の apply が rc 0 で 10 個とも `serverside-applied` になってから CRD 以外を流す | dev の記録、upgrade notes |
| 3 | drain・cordon | しない（ノードには触らない） | — |
| 4 | 入れ替わり | operator・Grafana・kube-state-metrics は Deployment の RollingUpdate（replicas 1、`maxSurge: 25%`・`maxUnavailable: 25%` で surge 1・unavailable 0）。node-exporter・smart-exporter は DaemonSet（`maxUnavailable: 1`、1 台ずつ）。Prometheus・Alertmanager は operator が作る StatefulSet（replicas 2、`podManagementPolicy: Parallel`、RollingUpdate）で、**2 回 rollout する**（§8.2） | live（§2.2 の 4）、dev の記録 |
| 5 | 途切れ | Prometheus・Alertmanager は常に 1 つ以上 Ready（dev）。それぞれの Prometheus には自分の入れ替わりの間（30〜60 秒）の欠けが 2〜3 回入る。operator・Grafana・kube-state-metrics は新しい Pod が Ready になってから古い Pod が消える | dev の記録、2026-10-19 のユーザーの方針（短時間の障害は許容） |
| 6 | Prometheus のデータ | **失ってもよい**（2026-10-25 ユーザー方針）。データが引けないこと・PVC の作り直しは止める条件にしない（§5） | TASK.md「現在地」 |
| 7 | イメージの事前 pull | **しない**。どの台にも 92.13.1 のイメージは無い（§2.2 の 18）が、Prometheus・Alertmanager は replicas 2 で、operator などは新しい Pod が Ready になるまで古い Pod が動く。pull の時間は途切れにならず、rollout が延びるだけ（dev の 51 秒は pull 36 秒を含む）。事前 pull はノードへの操作になる | dev の記録の「時間」、metrics-server の手順書 §2.1 の 6 |
| 8 | etcd のバックアップ | **取らない**（§2.4） | metrics-server の手順書 §2.4 |
| 9 | 材料 | この PR の `render/kube-prometheus-92/`。当日に fleet-infra の main の render と照らす（§1.4） | — |
| 10 | 前の Job | apply の前に `kubectl --context fraction -n monitoring get jobs` が空（admission の Job は immutable、TTL 60 秒）。2026-10-25 は空 | dev の記録 |
| 11 | 時間帯 | jumelle の 18:00〜19:30Z、worker の unattended-upgrades 06:00〜07:00Z、control-plane の 21:00〜22:00Z を避ける（§2.7） | metrics-server の手順書 §2.7 |
| 12 | 範囲の外 | 古いイメージ・古い ReplicaSet と ControllerRevision の片付け、chart の外に残った古い ClusterRole（`g0-grafana-clusterrole`・`p0-prometheus-kube-state-metrics` など。§2.2 の 17）の片付け、92.13.1 で増えた ConfigMap の戻しでの片付け（§10） | — |

### 2.2 ベースライン

作業の当日、CRD の apply の前に次を取り、`results/kube-prometheus-92/baseline.md` に残す（すべて読み取り）。

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-kube-prometheus/scripts
R=<このリポジトリの checkout>/docs/k8s-upgrade/render/kube-prometheus-92
bash $S/snap.sh ../kube-prometheus-92/base
bash $S/targets.sh ../kube-prometheus-92/base
bash $S/apps.sh ../kube-prometheus-92/base
bash $S/node-state.sh ../kube-prometheus-92/base
bash $S/lastapplied-diff.sh $R/85.2.1-rest.yaml | tail -3    # SAME=122 DIFF=0 MISSING=2（Job 2 つ）
bash $S/lastapplied-diff.sh $R/92.13.1-rest.yaml | tail -1   # SAME=5 DIFF=117 MISSING=3
for h in prometheus alertmanager grafana; do echo "$h $(curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://$h.fraction.jp/)"; done
```

| # | 項目 | 2026-10-25 23:5xZ の値（当日に読み直す） |
|---|---|---|
| 1 | Deployment | `grafana`（generation 4。k8s-sidecar 2.7.3 ×2、grafana 13.0.1-security-01）、`kube-prometheus-operator`（generation 2、v0.90.1）、`kube-state-metrics`（generation 1、v2.19.0）。どれも 1/1。2026-05-22 作成 |
| 2 | StatefulSet・CR | `prometheus-kube-prometheus` 2/2（revision `prometheus-kube-prometheus-844d4d5478`、generation 17）、`alertmanager-kube-prometheus` 2/2（`alertmanager-kube-prometheus-7d86bdb48`、generation 1）。どちらも `podManagementPolicy: Parallel`、`persistentVolumeClaimRetentionPolicy` は `Retain`/`Retain`。Prometheus の CR は generation 17、`v3.11.3-distroless`、replicas 2、retention `10d`、storage は bronze 20Gi、Available・Reconciled `True`。Alertmanager の CR は generation 1、`v0.32.1`、replicas 2、retention `120h`、storage なし（emptyDir）、Available・Reconciled `True`。Prometheus の startupProbe は `/-/ready`、15 秒ごと 60 回（15 分） |
| 3 | DaemonSet | `node-exporter` 8/8（v1.11.1-distroless、nodeSelector `kubernetes.io/os=linux`）、`smart-exporter` 8/8（node-exporter-smartmon 0.19.0）。どちらも `maxUnavailable: 1`・`maxSurge: 0` |
| 4 | Pod | 23 個、すべて Running・Ready。operator は pablo（restart 0、10-19 08:09:58Z 起動）。Prometheus は pod-0 が duchamp・pod-1 が chirico（どちらも restart 0、10-21 03:03:49Z 起動）。Alertmanager は pod-0 が duchamp（10-23 06:24:56Z）・pod-1 が chirico（10-19 09:35:29Z）。Grafana・kube-state-metrics は chirico。node-exporter と smart-exporter の restart は 2〜8（ノードの再起動のときのもの。§4.2 では増えないことを見るのではなく、Pod が新しくなることを見る） |
| 5 | PVC | `prometheus-kube-prometheus-db-prometheus-kube-prometheus-0`（UID `625c8825-4571-43d8-9119-c006a4a48399`）と `…-1`（UID `99c35b80-7928-4b9b-a4ac-3afa8e7a7b05`）。どちらも bronze 20Gi・Bound、2024-10-09 作成、PV の reclaimPolicy は `Delete`。Longhorn のボリュームは 2 つとも attached・healthy（pod-0 のものが duchamp、pod-1 のものが chirico）、replicas 1、engine v1.13.0。使用量は約 8.2 GB と 8.1 GB（`kubelet_volume_stats_used_bytes`）。StorageClass bronze は Longhorn の `numberOfReplicas: 1`・`reclaimPolicy: Delete`・`Immediate` |
| 6 | Longhorn 全体 | attached・healthy 16、detached 1（以前から）。空きは chirico 1.5 TB、duchamp 1.8 TB、oeilvert 0.27 TB + 1.7 TB、pablo 1.9 TB |
| 7 | Prometheus の TSDB | 2 つとも v3.11.3、ブロック 16、最も古いサンプル 2026-10-15 06:00:00Z、ブロック約 7.6 GB、WAL 約 0.41〜0.54 GB、head の series 約 22.7 万。10-21 の起動のときの WAL の読み直しは 5〜8 秒 |
| 8 | Prometheus の設定（`apps.sh`） | job 18、`bearer_token_file` 0（Prometheus 3 は `credentials_file` に直して出す）、`credentials_file` 9、`ca_file` が SA の `ca.crt` のもの 6、ConfigMap `kube-root-ca.crt` のもの 0。reload は成功（1）。ルールは 284 個とも ok |
| 9 | CRD 10 個 | どれも `operator.prometheus.io/version: 0.90.1`、`controller-gen.kubebuilder.io/version: v0.19.0`、generation 1、2026-05-22 作成。storage の版と `storedVersions` は v1 の 7 つが `[v1]`、v1alpha1 の 3 つ（alertmanagerconfigs・prometheusagents・scrapeconfigs）が `[v1alpha1]` で、1 つずつ。**ラベル `crd: "true"` と last-applied の注釈と managedFields の `kubectl-client-side-apply`（Update）があるのは `podmonitors`・`probes`・`prometheusrules`・`servicemonitors` の 4 つ**で、`kubectl-client-side-apply` が持つのは `metadata.labels.crd` と last-applied の注釈だけ。ほかの 6 つはラベルも注釈も無く、managedFields は `kubectl`（Apply）と `kube-apiserver`（Update/status）だけ |
| 10 | admission | Secret `kube-prometheus-admission` は **`Opaque`、キーは `ca`・`cert`・`key`**、UID `f7fb10a4-c757-4c26-bbb8-a65558adbf76`、2026-08-22 作成。MutatingWebhookConfiguration・ValidatingWebhookConfiguration `kube-prometheus-admission` がある（webhook 3 つとも `failurePolicy: Ignore`）。Job は無い |
| 11 | ServiceMonitor など | ServiceMonitor 13（すべて `monitoring`）、PodMonitor 1（`gated-system/gated`。render の外）、PrometheusRule 37（render の 36 と `gated-system/gated`）、Probe・ScrapeConfig・AlertmanagerConfig・PrometheusAgent・ThanosRuler は 0 |
| 12 | ターゲット（`targets.sh`） | 2 つの Prometheus とも **65 個すべて up**: kubelet 8×3、kube-proxy 8、node-exporter 8、apiserver 3、etcd 3、coredns 2、controller-manager 2、scheduler 2、Prometheus 2×2、Alertmanager 2×2、gated 2、Grafana 1、operator 1、kube-state-metrics 1 |
| 13 | アプリ（`apps.sh`） | Grafana の `/api/health` が `database: ok`、`13.0.1+security-01`。Alertmanager は 2 つとも 0.32.1、cluster `ready`、peers 2。operator のログの error の行は 0 |
| 14 | last-applied | `85.2.1-rest.yaml` は **122 個が SAME、DIFF 0、MISSING は Job 2 つ**（TTL で消えたもの）。`92.13.1-rest.yaml` は SAME 5（smart-exporter の DaemonSet、PrometheusRule `prometheus-smart-rules`、Ingress 3 つ）、DIFF 117、MISSING 3（ConfigMap `kube-prometheus-k8s-resources-nodes-overview`、Job 2 つ） |
| 15 | 本番の Secret（名前・型・キーの名前だけ） | `grafana`（`Opaque`、`admin-password`・`admin-user`・`ldap-toml`）、`alertmanager-kube-prometheus`（`Opaque`、`alertmanager.yaml`）。どちらも fleet-infra の `secrets/prod/kube-prometheus.enc.yaml` を別に apply したもので、render に無い（base が Secret `grafana` を消している）。ほかに Ingress の TLS 3 つ（`*-fraction-jp-gated-tls`、`kubernetes.io/tls`）と operator が作るもの（`prometheus-kube-prometheus`、`*-tls-assets-0`、`*-web-config` など）。この更新で `grafana`・`alertmanager-kube-prometheus`・TLS の 3 つは変わらない |
| 16 | Ingress | `prometheus`・`alertmanager`・`grafana`（class `gated`、ホスト `*.fraction.jp`、アドレス `192.168.1.200` と `2405:6580:6740:ac01:ace::200`）。**外からの `https://<名前>.fraction.jp/` は 3 つとも `401`**（gated の認証。中に届く前に止まる形が更新の前後で同じであることを見る） |
| 17 | cluster の RBAC | ClusterRole `kube-prometheus-admission`・`kube-prometheus-operator`・`kube-prometheus-prometheus`・`kube-state-metrics`・`grafana-clusterrole` と同じ名前の ClusterRoleBinding。ほかに chart の外の古い `g0-grafana-clusterrole`・`p0-prometheus-kube-state-metrics`（とその binding）が残っている（この更新では触らない。§10） |
| 18 | ノードのイメージ（`node-state.sh`） | **92.13.1 のイメージはどの台にも無い。** 85.2.1 のイメージは、Prometheus・Alertmanager・config-reloader が chirico・duchamp・oeilvert・pablo、operator が chirico・pablo、Grafana が chirico・duchamp・pablo にある。control-plane と braque は node-exporter と smartmon だけ |
| 19 | kubelet（`node-state.sh`） | .111 MainPID 752609・NRestarts 0、.112 1028・1、.113 612672・0、braque 541944・0、chirico 3237977・0、duchamp 202232・0、oeilvert 916805・51、pablo 3509679・0（metrics-server のベースラインと同じ） |
| 20 | SA token の Secret | クラスター全体で **2 つ: `kube-system/infra-admin` と `kube-system/infra-auditor`**（kubeconfig 用。kube-prometheus とは関係が無い）。`monitoring` には無い |
| 21 | operator が作る Service | `kube-system/kube-prometheus-kubelet`（UID `55a054e0-62ba-4a6d-8c2f-0943bf74ea93`、ownerReference なし。render に無い） |
| 22 | NetworkPolicy | `monitoring` に無い |

### 2.3 監視

CRD の apply の前から、§4 の確認が終わるまで流す（読み取り）。metrics-server の手順書 §2.3 と同じく、**`nohup` や `&` で起動しない。** worker のハーネスのバックグラウンド実行で、1 つのジョブとして起動する。

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-kube-prometheus/scripts
L=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/kube-prometheus-92/logs
bash $S/mon-watch.sh $L
```

- 1 行に `kubectl` を 8 回流すので、間隔は 3〜5 秒になる
- 起動したら、ジョブの一覧に居ることと、`mon-watch.log` に行が足されていくこと、`grafana=ok`、`prom=` と `am=` が ready の応答であること、`sts=` が `prometheus-kube-prometheus:2:2:…` と `alertmanager-kube-prometheus:2:2:…` であることを確かめる。**CRD の apply の前に、最後の行の時刻が 10 秒以内であること**
- 止めるときは `touch $L/mon.stop`
- 見るもの: operator の Pod の入れ替わりと restart、Job の作成と完了、admission の Secret の型とキーと UID、StatefulSet の ready・updated・revision（**`prometheus-kube-prometheus` と `alertmanager-kube-prometheus` の ready が 0 か空になる行が無いこと**）、PVC の UID、`grafana=`・`prom=`・`am=` の失敗
- 段 8 の手順書の etcd の health の監視、MetalLB の手順書の `probe.sh` は流さない（etcd にも LoadBalancer にも触らない）

### 2.4 etcd のバックアップは取らない

**この更新では `porkadot etcd backup` を取らない。** metrics-server の手順書 §2.4 と同じ判断で、理由は次のとおり。

- fleet-infra のマニフェストを手で apply する更新で、porkadot を使わない。前例の Longhorn の手順書と metrics-server の手順書も取っていない。§8 のほかの更新（MetalLB、autoscaler）で取ったのは porkadot の `install kubernetes` の手順に従ったため
- 戻し方は `85.2.1-rest.yaml` の client-side apply で、dev で確かめた（§7）。CRD は新しいまま残し、古い operator はそれで動く（dev）。CRD の served と storage の版は変わらず、`storedVersions` も変わらない（§2.6）ので、etcd に保存されたカスタムリソースの形は変わらない
- 変わるオブジェクトは多い（CRD 10、CRD 以外 120）が、どれも `monitoring` と kube-prometheus の cluster-scoped のもの（CRD・ClusterRole・webhook）で、ほかの名前空間とクラスタの制御には影響しない。etcd の restore はクラスタ全体を巻き戻し、この更新より害が大きい
- Prometheus のデータは etcd に無く、失ってもよい（§5）
- 想定外のときの最後の手段としては、autoscaler の更新の前に取った 2026-10-25 10:16:55Z のスナップショット（`results/dns-autoscaler-1.11/baseline.md` §4）がある

当日に、そのスナップショットがメインの checkout の `backup/` にあることだけ確かめる（読み取り。2026-10-25 23:5xZ にあった。無ければ記録して進める）。

### 2.5 render（この手順書と同じ PR）

`render/kube-prometheus-92/` に 4 つの render と sha256 を入れた。

| ファイル | 元 | sha256 | 用途 |
|---|---|---|---|
| `92.13.1-crds.yaml` | fleet-infra `675f543`（= main）の `kubectl kustomize infrastructure/kube-prometheus/prod/` の CRD 10 個 | `e0a3308da0a61a7a5d79cfe56660b0c2027ac1392f88e815bf82f8a9efe32cde` | §3.2 の server-side apply |
| `92.13.1-rest.yaml` | 同じ render の CRD 以外 125 個 | `f431618804d51e6aab83ab03a3ac92b12a0c21a39fd4801e24b8e84bb169a2db` | §3.3 の client-side apply |
| `85.2.1-crds.yaml` | fleet-infra `9a08fb9` の同じ render の CRD 10 個 | `840fdce7627dbeba93db984b0dfbe534402e25e6d429dbfdb2e4010c24856930` | §7.3 で CRD まで戻すと決めた場合だけ（dev では使っていない） |
| `85.2.1-rest.yaml` | 同じ render の CRD 以外 124 個 | `aacf2c04b9e06e381a9ee3a8c7c89ceb1455f951856b74cc6f50e5ddd91c5af8` | §7.2 の戻し。本番の last-applied と 122 個が同じ（§2.2 の 14） |

分ける前の render の sha256 は、`675f543` が `f5f2880f2ebf453ea691c4ea6dc049a7528e024880fdf6f72a5dd8409b38a6bb`、`9a08fb9` が `0506fbeaea58b06bb674ceb57dfd61e7079da190ddd799f98e1b423382d9428a`（§1.4 の当日の照合で使う）。

- 種類の内訳（`675f543`）: CRD 10、ConfigMap 32、PrometheusRule 36、ServiceMonitor 13、Service 11、ServiceAccount 7、ClusterRole 5、ClusterRoleBinding 5、Deployment 3、Ingress 3、DaemonSet 2、Job 2、Role・RoleBinding・Prometheus・Alertmanager・MutatingWebhookConfiguration・ValidatingWebhookConfiguration が 1 ずつ。`9a08fb9` との違いは ConfigMap `kube-prometheus-k8s-resources-nodes-overview` が増えることだけ（消えるものは無い）
- **秘密情報は入っていない。** `kind: Secret` と `kind: Namespace` は 0 個（base が Secret `grafana` を消している）。Secret の参照（`secretKeyRef` の `grafana` の `admin-user`・`admin-password`、Ingress の TLS の Secret 名、admission の Secret 名）と、Pod の SA token のファイルのパスだけがある。CRD の中の `password`・`token`・`apiKey` は schema のフィールド名
- Prometheus の CR の差は image と `version`（v3.11.3 → v3.15.0）、`nodeSelector: kubernetes.io/os: linux`、`scrapeClasses`（`kube-prometheus-stack-control-plane`、`authorization.credentialsFile` が Pod の SA token）とラベルだけ。**`storage` は変わらない**。Alertmanager の CR の差は image と `version`（v0.32.1 → v0.34.1）、`nodeSelector`、`hostNetwork: false` の明示が消えること（既定と同じ）とラベル
- CRD の差: 注釈 `operator.prometheus.io/version` が 0.90.1 → 0.94.1、`controller-gen.kubebuilder.io/version` が v0.19.0 → v0.22.0、schema。**served と storage の版は 10 個とも同じ**（v1 の 7 つは v1、ほかの 3 つは v1alpha1 だけ）。どちらの render の CRD にもラベル `crd: "true"` がある（prod overlay のパッチ）
- render を PR に入れるのは、当日の材料と戻しの材料を fleet-infra の clone に頼らずに固定するため（metrics-server の手順書と同じ考え）。4 つで約 10 MB ある

### 2.6 `kubectl diff` と dry-run（トークンを使うが、書き込まない）

承認（§3.1）の前に流し、結果を見せる。

```sh
R=<このリポジトリの checkout>/docs/k8s-upgrade/render/kube-prometheus-92
D=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/kube-prometheus-92
kubectl-admin diff --server-side -f $R/92.13.1-crds.yaml > $D/diff-crds.txt 2>&1; echo rc=$?                    # 1
kubectl-admin apply --server-side --dry-run=server -f $R/92.13.1-crds.yaml > $D/dry-run-crds.txt 2>&1; echo rc=$?  # 0
kubectl-admin diff -f $R/92.13.1-rest.yaml > $D/diff-rest.txt 2>&1; echo rc=$?                                   # 1
kubectl-admin apply --dry-run=server -f $R/92.13.1-rest.yaml > $D/dry-run-rest.txt 2>&1; echo rc=$?              # 0
grep -c '^diff -u' $D/diff-crds.txt $D/diff-rest.txt                                                            # 10、120
awk '{print $NF, $(NF-1)}' $D/dry-run-rest.txt | sort | uniq -c
```

- `diff` の rc は 1（差分あり）。**rc が 1 より大きければ、差分ではなくエラーなので止める**。`conflict` の文字が出たら止める（§3.2）
- **CRD（server-side の diff）**: 10 個とも差がある。差は `metadata.annotations` の `controller-gen.kubebuilder.io/version`（v0.19.0 → v0.22.0）と `operator.prometheus.io/version`（0.90.1 → 0.94.1）、`generation`（1 → 2）、schema の中（description と新しいフィールド）。**ラベル `crd: "true"` は、今ラベルの無い 6 つに足される**（dev と同じ）。今ある 4 つ（`podmonitors`・`probes`・`prometheusrules`・`servicemonitors`）はラベルの差が無い。この 4 つは、kubectl が client-side の managedFields を server-side に移すために、**last-applied の注釈が消える差が出るかもしれない**（dev で確かめていない。出ても出なくても進める）。`spec.versions[].name`・`served`・`storage` の差、`status` の差があれば止める
- CRD の dry-run は rc 0 で、10 個とも `serverside-applied (server dry run)`
- **CRD 以外（client-side の diff）**: 125 個のうち 120 個に差（`DIFF` 117 と新しい 3 つ。§2.2 の 14 と同じ組）。差の無い 5 つは smart-exporter の DaemonSet、PrometheusRule `prometheus-smart-rules`、Ingress 3 つ。見るところ:
  - Prometheus の CR: image・`version`・`nodeSelector`・`scrapeClasses`・ラベル。**`spec.storage` に差が無いこと**（差があれば §5 を読み直してから止めて報告する）
  - Alertmanager の CR: image・`version`・`nodeSelector`・`hostNetwork`・ラベル
  - operator の Deployment: image、引数（`--web.cert-file=/cert/tls.crt`・`--web.key-file=/cert/tls.key`、`--secret-field-selector` から `type!=kubernetes.io/service-account-token` が外れる、`--prometheus-config-reloader` が v0.94.1）、`nodeSelector`
  - control-plane の 7 つの ServiceMonitor: `bearerTokenFile` と `tlsConfig.caFile` が消え、`scrapeClass: kube-prometheus-stack-control-plane` と `tlsConfig.ca.configMap`（`kube-root-ca.crt`）が付く
  - Job 2 つ（新しい。create の引数に `--secret-type=kubernetes.io/tls`）、Role `kube-prometheus-admission` に Secret の `delete` が足される
  - **Deployment・DaemonSet・Service の `spec.selector` に差が無いこと**（#206 の「作り直しが要るもの: 無い」）
- CRD 以外の dry-run は rc 0 で、**`configured` 117・`created` 3（ConfigMap `kube-prometheus-k8s-resources-nodes-overview`、Job `kube-prometheus-admission-create`・`-patch`）・`unchanged` 5**（dev と同じ）。これと違えば中身を読み、説明がつかなければ止める。エラー（`Invalid value`、`field is immutable` など）があれば止める
- `--dry-run=server` は admission の webhook も通すので、PrometheusRule は今の operator（v0.90.1）の webhook で検査される（`failurePolicy: Ignore`）
- last-applied の注釈は diff に出ない（`kubectl diff` の MERGED 側は注釈を書き換えない。metrics-server の手順書 §2.6）

### 2.7 時間帯

metrics-server の手順書 §2.7 と同じ時間帯を避ける。

| 時間帯（UTC） | 何が起きるか | 避ける理由 |
|---|---|---|
| **18:00〜19:30** | jumelle の unattended-upgrades と自動再起動 | jumelle が落ちると quay.io・docker.io・registry.k8s.io・ghcr.io からの pull が止まる（新しい Pod が起動しない。Prometheus・Alertmanager は片方が残る） |
| 06:00〜07:00 | worker 5 台の unattended-upgrades | needrestart がサービスを再起動すると、§4.2 の「kubelet が再起動しない」「ほかの Pod が変わらない」の確かめと取り違える。Prometheus・Alertmanager・operator は worker に載っている。kubelet が止まるとターゲットが down になり、§4.2 の確かめと取り違える |
| 21:00〜22:00 | control-plane 3 台の unattended-upgrades | 同上（apiserver・etcd・controller-manager・scheduler のターゲット、node-exporter の DaemonSet の rollout） |

- 作業は、監視の起動から §4.3 の確認まで 40〜60 分を見込む（rollout は dev で 2 分 8 秒だが、本番は pull と Longhorn のボリュームの付け直しと、8 台の DaemonSet の rollout がある。§4.3 で 10 分おく）。その間が上の時間帯に重ならないこと

### 2.8 dev の記録と違う本番の形

| 点 | dev | 本番 | この手順書での扱い |
|---|---|---|---|
| 始めの状態 | kube-prometheus が無い（85.2.1 を入れて数分 scrape してから上げた） | 85.2.1 が 2026-05-22 から動いている | Prometheus の CR は generation 17 から。`InvalidConfiguration` のイベントは今は 0 個（§2.2。`get events` が空） |
| CRD の形 | `base/crds.yaml` を server-side だけで入れた（ラベルなし、manager `kubectl` だけ） | 6 つは同じ形。**4 つはラベル `crd: "true"`・last-applied・`kubectl-client-side-apply` を持つ**（§2.2 の 9） | §2.6 の diff で conflict の無いことを見る。last-applied の注釈は残っても消えてもよい |
| ノード | 7 台、すべて amd64 | 8 台、control-plane 3 台が arm64 | DaemonSet は 8 台。node-exporter の rollout は 1 台ずつで、Pi の pull を含む |
| PVC | bronze（replicas 1）2Gi、数分のデータ（ブロック 0） | bronze（replicas 1）20Gi、ブロック 16・約 7.6 GB、WAL 約 0.5 GB | WAL の読み直しが延びうる（10-21 の起動では 5〜8 秒）。startupProbe は 15 分。データは失ってもよい（§5） |
| ターゲット | 34 個 | 65 個（gated の PodMonitor を含む） | §4.2 で 65 個すべて up を見る |
| Secret | ダミーの `grafana` と `alertmanager-kube-prometheus` | 本物（sops） | 中身は読まない。名前・型・キーの名前と UID が変わらないことを見る |
| Ingress | controller が無い | gated、外から `401` | 更新の後も 3 つとも `401` であることを見る |
| SA token の Secret | 0 個 | 2 個（`kube-system/infra-admin`・`infra-auditor`） | 増えないことを見る |
| render の外のもの | 無い | `gated-system` の PodMonitor・PrometheusRule | 新しい operator で受け付けられ、gated のターゲットが up でルールが ok であることを見る |

## 3. apply

### 3.1 事前確認

✋✋ **開始の承認を取る。** §2.5 の render と PR、§2.2 のベースライン、§2.6 の diff と dry-run の結果、§2.3 の監視、§2.7 の時間帯、§5 のデータの扱い（§5.2 の PVC の作り直しを ✋ で行ってよいか）、§6 の止める条件、§7 のロールバックの形を示す。承認を得て PR をマージし、マージした master の `render/kube-prometheus-92/` で §3.2 に入る。

- §2.2 のベースラインと §2.6 が済んでいる。§2.3 の監視がジョブとして動き、最後の行が 10 秒以内で、StatefulSet が 2 つとも `2:2`、`grafana=ok`
- 全台 Ready、`monitoring` の Pod がすべて Running・Ready
- **`kubectl --context fraction -n monitoring get jobs` が空**
- checkout が PR をマージした master で、`sha256sum -c SHA256SUMS` が 4 つとも OK。§1.4 の当日の fleet-infra の main の render が `92.13.1-*.yaml` と同じ
- `ADMIN_TOKEN` の期限が残っている（`kubectl-admin auth can-i patch customresourcedefinitions` が `yes`）
- 作業の時間が §2.7 の時間帯と重ならない

### 3.2 CRD を server-side で流す ✋

```sh
date -u +%FT%T.%3NZ
kubectl-admin apply --server-side -f $R/92.13.1-crds.yaml 2>&1 | tee $D/apply-crds.txt; echo rc=$?
date -u +%FT%T.%3NZ
kubectl --context fraction get crd -o json | jq -r '.items[] | select(.spec.group=="monitoring.coreos.com") | [.metadata.name, .metadata.annotations["operator.prometheus.io/version"], (.status.storedVersions|join(",")), (.metadata.labels.crd // "-"), ([.status.conditions[] | select(.type=="Established") | .status] | join(""))] | @tsv'
```

- 時刻と rc を記録する。dev では 2 秒
- 出力は 10 行とも `customresourcedefinition.apiextensions.k8s.io/<名前> serverside-applied`
- **`conflict` が出たら止めて報告する**（`--force-conflicts` は runbook から外れる操作。§2.6 の dry-run で出ていなければ出ない見込み）。#206 の本文は、出たら `--force-conflicts` を使うと書いている。推奨はそれだが、どのフィールドで誰と conflict したかを見てからユーザーが決める
- 流した後、10 個とも版の注釈が `0.94.1`、ラベル `crd` が `true`、`storedVersions` が §2.2 の 9 と同じ（1 つずつ）、`Established` が `True` であることを上の jq で見る（2026-10-25 は 10 個とも `0.90.1`、ラベルは 4 つだけ `true`、Established `True`）
- この時点で operator は v0.90.1 のまま動いている。新しい CRD の schema で古い operator が困らないことは dev で確かめた（戻しのときに 85.2.1 が新しい CRD で動いた）。CRD の後に CRD 以外を流すまでの間を空けない（数分以内）

### 3.3 CRD 以外を client-side で流す ✋

```sh
kubectl --context fraction -n monitoring get jobs          # No resources found
date -u +%FT%T.%3NZ
kubectl-admin apply -f $R/92.13.1-rest.yaml 2>&1 | tee $D/apply-rest.txt; echo rc=$?
date -u +%FT%T.%3NZ
grep -v ' configured$' $D/apply-rest.txt
awk '{print $NF}' $D/apply-rest.txt | sort | uniq -c        # configured 117、created 3、unchanged 5
```

- 時刻と rc を記録する。dev では 10 秒
- 出力で見るもの: **`configured` 117・`created` 3（ConfigMap `kube-prometheus-k8s-resources-nodes-overview`、Job `kube-prometheus-admission-create`・`kube-prometheus-admission-patch`）・`unchanged` 5（`daemonset.apps/smart-exporter`、`prometheusrule.monitoring.coreos.com/prometheus-smart-rules`、Ingress 3 つ）**。それ以外の `created` や、エラーの行があれば中身を読み、§2.6 の dry-run と違えば止める
- `kubectl apply` は prune しないので、消えるオブジェクトは無い
- rc が 0 でないとき（トークンの期限切れ、`connection refused` など）は、出力を読んで原因を見る。**流し直す前に `get jobs` が空になるのを待つ**（Job が残っていると、Job の更新が immutable で拒否される。§2.1 の 10）。トークンの期限なら発行し直して流し直す（✋ の範囲）。2 回目も落ちたら止めて報告する
- 流した直後から §4.1 の入れ替わりを見る

### 3.4 CRD を server-side、CRD 以外を client-side で流す理由

- **CRD は client-side では入らない。** いちばん大きい `prometheuses` の CRD は約 497 KB あり、client-side apply の last-applied の注釈（262,144 B が上限）に入らない（#206）。upgrade notes も `kubectl apply --server-side` を指示している。本番の CRD は 10 個とも manager `kubectl` の server-side apply で入っている（§2.2 の 9）。同じ field manager（既定の `kubectl`）で流せば conflict は出ない見込みで、dev でも出なかった
- **CRD 以外は client-side で流す。** 本番の CRD 以外のオブジェクトは client-side apply で作られている（122 個とも last-applied が 85.2.1 の render と同じ。§2.2 の 14）。同じ形で流せば差は last-applied との 3-way merge で決まり、dev で見た結果（configured 117・created 3・unchanged 5）がそのまま当たる。§7 の戻しも client-side apply に頼っている（92.13.1 で足されたフィールドを、last-applied との差として消す）。dev は CRD 以外を client-side だけで確かめた
- render をそのまま `kubectl apply -k` には渡せない（CRD が client-side で落ちる）。だから render を 2 つのファイルに分けて PR に入れた
- server-side に移すなら、kube-prometheus だけでなく fleet-infra 全体の apply の運用として別に決める（metrics-server の手順書 §3.3 と同じ。§10）

## 4. 後の確認

### 4.1 入れ替わりを見る

```sh
K="kubectl --context fraction -n monitoring"
$K rollout status deployment/kube-prometheus-operator --timeout=5m
$K rollout status statefulset/prometheus-kube-prometheus --timeout=15m
$K rollout status statefulset/alertmanager-kube-prometheus --timeout=10m
$K rollout status deployment/grafana --timeout=5m
$K rollout status deployment/kube-state-metrics --timeout=5m
$K rollout status daemonset/node-exporter --timeout=15m
```

`mon-watch.log` で次の順に進むことを見る（dev の記録の「入れ替わり」。時刻は dev の apply からの秒）。

| dev の時刻 | できごと | 本番で見ること |
|---|---|---|
| +0〜7 秒 | 新しい operator（v0.94.1）の Pod が Pending。Job 2 つが作られる。古い operator が新しい CR から StatefulSet を作り直し（中間の revision）、pod-1 が入れ替わり始める | Job ができること。古い operator は Ready のまま |
| +24 秒 | 新しい operator が restart 1（`open /cert/tls.crt: no such file or directory`） | **restart は 2 まで許す** |
| +23〜27 秒 | create Job が Secret `kube-prometheus-admission` を作り直す: **型が `Opaque` → `kubernetes.io/tls`、UID が変わり、キーが `ca`・`cert`・`key` に `ca.crt`・`tls.crt`・`tls.key` が足される**。create・patch の Job が完了 | `adm=` の列の型・キー・UID |
| +34 秒 | 新しい operator が restart 2 | — |
| +38 秒 | 新しい operator だけになり Ready。新しい operator が StatefulSet をもう一度作り直し（最後の revision）、pod-0 が入れ替わる | 古い operator の Pod が消える |
| +1 分 20 秒 | Alertmanager の StatefulSet が 2/2 | **どの行でも ready が 1 以上** |
| +1 分 45 秒 | Prometheus の pod-1 がもう一度入れ替わる | — |
| +2 分 8 秒 | Prometheus の StatefulSet が 2/2 | **どの行でも ready が 1 以上** |
| +1 分ほど | Job 2 つが TTL（60 秒）で消える | `jobs=` が空になる |

- **apply から 1 分たって新しい operator が Ready でないとき**は、`kubectl --context fraction -n monitoring get secret kube-prometheus-admission -o jsonpath='{.type}'` と、`kubectl --context fraction -n monitoring logs deploy/kube-prometheus-operator`、Job の Pod のログを見る（dev の記録）。Secret が `kubernetes.io/tls` になっていれば、さらに 1 分待つ。3 分たっても Ready でなければ止める（§6）
- Prometheus の Pod は、消えてから Running になるまで dev で最も長いもので 51 秒（同じノードで Longhorn のボリュームを付け直し、pull 36 秒を含む）。本番は pull（Prometheus のイメージ約 150 MB）と WAL の読み直しが加わる。**1 つの Pod が作られてから 10 分たっても Ready にならないとき**は §5 と §6 に従う
- node-exporter の DaemonSet は 8 台を 1 台ずつ入れ替える（control-plane の Pi の pull を含む）。smart-exporter は `unchanged` で入れ替わらない
- Grafana・kube-state-metrics は新しい Pod が Ready になってから古い Pod が消える

### 4.2 確認

rollout が終わったら、`snap.sh`・`targets.sh`・`apps.sh`・`node-state.sh` を `../kube-prometheus-92/after` に取り、§2.2 と比べる。`lastapplied-diff.sh $R/92.13.1-rest.yaml` も流す。

| # | 確認 | 合格基準 |
|---|---|---|
| 1 | operator | Deployment 1/1、`v0.94.1`。**Pod の restart は 2 以下**で、create Job が Secret を作り直した後に増えていない。ログに `level=error` が続かない（`server TLS client verification disabled` の warn は 85.2.1 でもある） |
| 2 | admission | Secret `kube-prometheus-admission` が `kubernetes.io/tls`、キーが `ca`・`ca.crt`・`cert`・`key`・`tls.crt`・`tls.key`（値は読まない）。webhook 2 つがある。Job は TTL で消えている |
| 3 | Prometheus | StatefulSet 2/2、2 つの Pod が `v3.15.0-distroless` と config-reloader `v0.94.1` で Running・Ready、restart 0。CR の Available・Reconciled が `True`。`apps.sh` で版が 3.15.0、設定の reload が成功、ルールがすべて ok（dev では 281 → 283 に増えた。本番は 284 から増えうる。`err` が空であること） |
| 4 | Alertmanager | StatefulSet 2/2、`v0.34.1`、restart 0。`apps.sh` で 2 つとも cluster `ready`、peers 2 |
| 5 | StatefulSet の rollout の間 | `mon-watch.log` の `sts=` で、**`prometheus-kube-prometheus` と `alertmanager-kube-prometheus` の ready が 0 か空になる行が無い**（表の下のコマンドが 2 つとも 0）。`prom=`・`am=` の失敗の行数を記録する |
| 6 | Grafana | Deployment 1/1、`13.2.4-distroless` と k8s-sidecar `2.14.1`、restart 0。`/api/health` が `database: ok`。`grafana-advisor-app` を読み込まない件（§8.4）は記録だけ |
| 7 | kube-state-metrics・node-exporter・smart-exporter | kube-state-metrics 1/1 で `v2.20.0`。node-exporter 8/8 で `v1.12.1-distroless`、8 台とも新しい Pod。**smart-exporter は 8 つの Pod の名前・UID・restart が §2.2 と同じ**（`unchanged`） |
| 8 | ターゲット（`targets.sh`） | 2 つの Prometheus とも **65 個すべて up**（§2.2 の 12 と同じ組。gated の 2 を含む）。apply から 5 分以上たってから見る |
| 9 | control-plane の scrape | `apps.sh` の設定で、`ca_file` の SA の `ca.crt` が 6 → 0、ConfigMap `kube-root-ca.crt` が 0 → 6（kubelet 3・apiserver・controller-manager・scheduler。dev の記録から推した値。違えば設定の中身を読む）、`credentials_file` は 9 のまま。kubelet（3 つの endpoint）・apiserver・etcd・controller-manager・scheduler・kube-proxy・coredns が up |
| 10 | SA token の Secret | `kubectl --context fraction get secret -A --field-selector type=kubernetes.io/service-account-token` が **`kube-system/infra-admin` と `infra-auditor` の 2 つだけ**（`kube-prometheus-prometheus-token` が無い） |
| 11 | grafana-test | `kubectl --context fraction -n monitoring get pod,cm,sa grafana-test` が 3 つとも NotFound |
| 12 | CRD | 10 個とも `operator.prometheus.io/version: 0.94.1`、ラベル `crd: "true"`、**`storedVersions` が 1 つずつ**（v1 の 7 つが `[v1]`、v1alpha1 の 3 つが `[v1alpha1]`）、Established。4 つの last-applied の注釈と managedFields の manager を記録する |
| 13 | `InvalidConfiguration` | `kubectl --context fraction -n monitoring get events --field-selector reason=InvalidConfiguration` の時刻が、どれも新しい operator が Ready になった時刻より前（入れ替わりの間のもの。§8.3）。その後に新しいものが出ていない |
| 14 | PVC | 2 つの PVC の UID が §2.2 の 5 と同じで Bound（**違っても、作り直しが §5.2 の手順によるものなら合格**）。Longhorn のボリュームが attached・healthy |
| 15 | Prometheus のデータ | `apps.sh` のブロック数と最も古いサンプルの時刻を記録する（§2.2 の 7 は 16 と 2026-10-15 06:00Z）。**引けなくても不合格にしない**（§5） |
| 16 | ほかの名前空間 | 全 Pod の比較で、**`monitoring` 以外の Pod の名前・UID・restartCount が §2.2 と同じ**。Running / Completed 以外が 0 |
| 17 | kubelet | 8 台の MainPID・NRestarts・ActiveEnterTimestamp が §2.2 の 19 と同じ |
| 18 | last-applied | `lastapplied-diff.sh $R/92.13.1-rest.yaml` が `SAME=123 DIFF=0 MISSING=2`（Job 2 つは TTL で消える） |
| 19 | 本番の Secret | `grafana`・`alertmanager-kube-prometheus`・Ingress の TLS 3 つの型・キーの名前・UID が §2.2 の 15 と同じ |
| 20 | operator が作るもの | `kube-system/kube-prometheus-kubelet` の Service が同じ UID であり、kubelet のターゲットが 8 つ（#8 に含む） |
| 21 | Ingress | 外からの `https://prometheus.fraction.jp/`・`alertmanager.fraction.jp`・`grafana.fraction.jp` が 3 つとも `401`（§2.2 の 16 と同じ）。Ingress の spec と address が同じ。apiserver の proxy 経由で Prometheus・Alertmanager の `/-/ready`、Grafana の `/api/health` が答える（`mon-watch.log` の最後の行） |
| 22 | 健全性 | 8 台 Ready、VIP の `https://192.168.1.101:6443/readyz` が 200 |

- 段 8 の手順書 §1.8 の `netcheck.sh`、§1.9 の `npcheck.sh` は流さない（ネットワークにも NetworkPolicy にも触らない）
- #5 の数え方（ready が 0 のとき、custom-columns は `<none>` を出す。`T` は §3.2 の apply の始めの時刻。dev の `mon-watch.log` で、kube-prometheus を入れた直後の行だけが当たることを確かめた）:

```sh
awk -v t=<T> '$1 >= t' $L/mon-watch.log | grep -cE 'sts=.*prometheus-kube-prometheus:(0|<none>)?:'    # 0
awk -v t=<T> '$1 >= t' $L/mon-watch.log | grep -cE 'sts=.*alertmanager-kube-prometheus:(0|<none>)?:'  # 0
awk -v t=<T> '$1 >= t' $L/mon-watch.log | grep -cv 'grafana=ok prom=Prometheus Server is Ready. am=OK'   # 記録する（Service 経由の応答の失敗）
```

### 4.3 10 分おいて見直す

最後の rollout の完了から 10 分たってから、`targets.sh` と `apps.sh` を `../kube-prometheus-92/late` に取る。ターゲットが 65 個すべて up、ルールがすべて ok、operator のログに新しい error が無く、§4.2 の 13 の新しいイベントが無ければ合格。あわせて、2 つの Prometheus で apply の前後の時間の `up` が引けるかを記録する（§5。合否には使わない）。

```sh
K="kubectl --context fraction"
for p in prometheus-kube-prometheus-0 prometheus-kube-prometheus-1; do
  b="/api/v1/namespaces/monitoring/pods/$p:9090/proxy/api/v1"
  q='sum by (job) (count_over_time(up{job=~"apiserver|kubelet|kube-etcd|coredns|kube-proxy|kube-controller-manager|kube-scheduler"}[1m]))'
  echo "== $p"; $K get --raw "$b/query_range?query=$(jq -rn --arg q "$q" '$q|@uri')&start=<apply の 10 分前>&end=<今>&step=60" \
    | jq -r '.data.result[] | "\(.metric.job) \([.values[][1]] | join(","))"'
done
```

- control-plane の job の 1 分ごとのサンプル数が、apply の後で 0 になる分が無いこと（dev の記録の「入れ替わり」の末尾）。その Prometheus 自身の Pod が入れ替わっていた分だけ減るのは許す

### 4.4 監視を止め、トークンを破棄する

§4.2・§4.3 が終わったら、§2.3 の監視を止め（`touch $L/mon.stop`）、ジョブが終わったことを確かめる。`unset ADMIN_TOKEN` と `rm /tmp/kp-upg-admin-token` でトークンを破棄する。

## 5. Prometheus のデータと PVC

### 5.1 方針

**2026-10-25 のユーザー方針: 本番の Prometheus のデータは失ってもよい。** データを残すことはこの更新の完了条件にしない。

- PVC は同じもの（UID 不変）が使われる見込み（#206: CR の `storage` と StatefulSet の `volumeClaimTemplates` は変わらない。dev でも UID 不変）。ただし dev のデータにはブロックが無かった（§2.8）
- **データが引けない（ブロック数が減る、最も古いサンプルが新しくなる、TSDB のエラーで一部が読めない）ことは止める条件にしない。** 記録して進める
- 合格の条件は「**Prometheus が 2 つとも新しい版で Ready になり、ターゲットを scrape している**」こと。古い PVC のままでも、作り直した新しい PVC でもよい
- Alertmanager は storage を持たない（emptyDir。§2.2 の 2）ので、silence と通知の状態は Pod の入れ替わりで消える（今までの再起動と同じ。2 つの peer の間で引き継がれる分はある）。Grafana のデータも emptyDir（ダッシュボードとデータソースは ConfigMap から入る）

### 5.2 PVC の作り直し ✋（開始の承認で認められた場合だけ）

Prometheus の Pod が、PVC の中身のために起動しないとき（WAL・ブロックの読み込みで落ちて CrashLoopBackOff になる、startupProbe が 15 分で通らない、ボリュームが壊れて mount できない、など）に限って、**その Pod の PVC を消して作り直す**。もう片方の Prometheus が Ready であることを確かめてから、1 つずつ行う。

```sh
P=prometheus-kube-prometheus-<n>
C=prometheus-kube-prometheus-db-$P
kubectl --context fraction -n monitoring logs $P -c prometheus --tail=100 > $D/$P-before-pvc-delete.log 2>&1   # 理由を残す
kubectl --context fraction -n monitoring get sts prometheus-kube-prometheus -o jsonpath='{.status.readyReplicas}'  # 1 以上
kubectl-admin -n monitoring delete pvc $C --wait=false
kubectl-admin -n monitoring delete pod $P
kubectl --context fraction -n monitoring get pvc $C -o custom-columns=N:.metadata.name,UID:.metadata.uid,PH:.status.phase   # 新しい UID で Bound になるまで、間をおいて見る
```

- StatefulSet の controller が `volumeClaimTemplates`（bronze 20Gi）から同じ名前の PVC を新しい UID で作り、Pod を作り直す。古い PV は reclaimPolicy `Delete` なので、Longhorn のボリュームごと消える（データは戻らない）
- 新しい Pod が Ready になり、§4.2 の 3・8 を満たせば合格。PVC の UID の変化と時刻を記録する
- 開始の承認でこの扱いが認められなかったときは、ここで止めて報告する
- 原因が PVC の中身でない（イメージの pull、設定のエラー、Longhorn のボリュームの attach の失敗など）ときは、PVC を消さずに止めて報告する（§6）。消してもその原因は直らない
- 2 つの Prometheus がともに起動しないときも、1 つずつ行う（片方が Ready になるのを待ってから、もう片方）

## 6. 止める条件

次のどれかに当たったら、その場で止めて報告する。続けるか §7 で戻すかはユーザーが決める。

- §2.6 の `diff` の rc が 1 より大きい、`conflict` が出る、CRD の served・storage の版に差がある、Prometheus の CR の `storage` に差がある、Deployment・DaemonSet・Service の `selector` に差がある、dry-run の数（configured 117・created 3・unchanged 5、CRD は 10 個とも `serverside-applied`）と違って説明がつかない、dry-run にエラーがある
- CRD の apply が rc 0 でない、`conflict` が出る、10 個のうち `serverside-applied` でないものがある
- CRD 以外の apply が 2 回続けて rc 0 にならない、immutable のエラーが出る
- **新しい operator が apply から 3 分たっても Ready にならない**、restart が 3 以上になる（create Job が Secret を作り直した後も落ちる）
- create Job が失敗する（`jobs=` の failed が 1 以上で、Secret が `kubernetes.io/tls` にならない）
- **Prometheus か Alertmanager の StatefulSet の ready が 0 になる**（`mon-watch.log`）
- Prometheus の Pod が、作られてから 10 分たっても Ready にならない。**原因が PVC の中身なら §5.2（認められていれば ✋）**、そうでなければ止める
- Alertmanager・Grafana・kube-state-metrics・node-exporter の新しい Pod が 5 分たっても Ready にならない、restart が増え続ける（`ImagePullBackOff`、`CrashLoopBackOff` など）
- 新しい operator が Ready になってから 5 分たっても、ターゲットに up でないものがある、`InvalidConfiguration` のイベントが新しく出続ける、ルールに `err` がある
- 期限の無い SA token の Secret が増える、`grafana-test` の Pod ができる
- CRD の `storedVersions` が 2 つ以上になる
- `monitoring` 以外の Pod の再起動、Node の NotReady、kubelet の再起動
- Ingress の外からの応答が `401` 以外になる（`5xx` など）
- **止める条件にしないもの**: Prometheus のデータが引けないこと、PVC が作り直しになったこと（§5）、operator の restart の 2 回まで、入れ替わりの間の `InvalidConfiguration` のイベントと一時的なターゲットの down、Grafana の advisor の件（§8.4）

## 7. ロールバック

**戻すのは runbook から外れる操作なので、ユーザーの承認を取る。** この PR の `render/kube-prometheus-92/85.2.1-rest.yaml`（fleet-infra `9a08fb9` の render の CRD 以外）を client-side apply して 85.2.1 に戻す。**CRD は 92.13.1 のまま残す**（dev で確かめた形。古い operator v0.90.1 は新しい CRD でも、`kubernetes.io/tls` になった admission の Secret でも restart 0 で起動した）。

### 7.1 戻すための材料

- **85.2.1 の render**: `render/kube-prometheus-92/85.2.1-rest.yaml`（sha256 `aacf2c04…`）。本番の今の last-applied と 122 個が同じ（§2.2 の 14）
- **トークン**: §1.2。§4.4 で破棄した後なら発行し直す
- fleet-infra 側は戻さない（main は 92.13.1 のまま）。戻した後に fleet-infra をどうするかはユーザーと決める

### 7.2 戻す ✋

```sh
kubectl --context fraction -n monitoring get jobs           # 空になるまで待つ（TTL 60 秒）
kubectl-admin diff -f $R/85.2.1-rest.yaml > $D/diff-rollback.txt 2>&1; echo rc=$?   # 1
kubectl-admin apply -f $R/85.2.1-rest.yaml 2>&1 | tee $D/apply-rollback.txt; echo rc=$?
awk '{print $NF}' $D/apply-rollback.txt | sort | uniq -c     # dev: configured 117、created 2、unchanged 5
```

- §2.3 の監視を流したまま行う
- dev では、古い operator が restart 0 で Ready になり（apply から 16 秒）、StatefulSet は戻すときも 2 回 rollout した（新しい operator が古い CR から 1 回、古い operator がもう 1 回）。戻すときは、まだ動いている新しい operator が control-plane の 7 つの ServiceMonitor を「scrapeClass が無い」で数秒拒否する（§8.3）
- certgen 1.8.3 の create Job は既存の Secret（`kubernetes.io/tls`、古いキー `cert`・`key` も残っている）をそのまま使う（UID も型も変わらない）
- **92.13.1 で増えた ConfigMap `kube-prometheus-k8s-resources-nodes-overview` は残る**（`kubectl apply` は prune しない。ダッシュボードが 1 つ多いだけで害は無い。消すかは戻した後に決める）
- 確かめること: §4.2 を版を読み替えて行う（operator v0.90.1、Prometheus v3.11.3、Alertmanager v0.32.1 など。`lastapplied-diff.sh $R/85.2.1-rest.yaml` が `SAME=122 DIFF=0 MISSING=2`、ターゲットが 65 個すべて up、ルールがすべて ok、control-plane の 7 つの ServiceMonitor が `bearerTokenFile` に戻る）。CRD は 0.94.1 のまま
- 上げ直すときは、§3.2（差なし）と §3.3 を、Job が消えてから流す（dev では operator が restart 0、中間の revision は見えなかった）

### 7.3 CRD まで戻すか

**戻さない（推奨）。** dev は CRD を新しいまま 85.2.1 に戻して動くことを確かめ、CRD を古い版に戻す形は確かめていない。CRD の served と storage の版は変わらないので、新しい CRD のままでも古い operator と古いカスタムリソースは読める。
新しい CRD のために古い operator が動かないなど、どうしても戻す必要が出たときは、`85.2.1-crds.yaml` を `kubectl-admin apply --server-side` で流す形になる（その時点でユーザーと決める。92.13.1 にしかないフィールドを使うカスタムリソースが無いこと（render のものは §2.5 のとおり scrapeClasses だけで、それは 85.2.1 の CR では消える）を先に確かめる）。

### 7.4 それでも戻らないとき

§7.2 で戻らないとき（operator が Ready にならない、StatefulSet が 2/2 に戻らないなど）は止めて報告する。**kube-prometheus が止まっても、クラスタで影響を受けるのは監視（メトリクス、アラート、ダッシュボード）だけ**（HPA・VPA は無く、metrics API は metrics-server が持つ。admission の webhook は `failurePolicy: Ignore`）ので、急がない。立て直しの手（Pod・Job の削除、admission の Secret の作り直し、StatefulSet の手での直し、PVC の作り直し）は、その時点でユーザーと決める。etcd の restore は要らない（§2.4）。

## 8. 既知の問題と注意

### 8.1 operator の 2 回の restart と create Job

新しい operator（v0.94.1）は `/cert/tls.crt`・`/cert/tls.key` を読むが、今の Secret `kube-prometheus-admission` は `Opaque` で `cert`・`key` しか持たない。certgen 1.11.0 の create Job が、同じ証明書のまま Secret を消して `kubernetes.io/tls` で作り直すまで、新しい operator は `open /cert/tls.crt: no such file or directory` で落ちる（dev で restart 2、apply から 38 秒で Ready）。**止めないで待つ。** その間も古い operator が Ready のまま動いている（Deployment の surge）。admission の Role に Secret の `delete` が足されるのはこのため（#206）。

### 8.2 StatefulSet の 2 回の rollout

CRD 以外の apply で CR が変わると、まだ動いている古い operator（v0.90.1）が新しい CR から StatefulSet を一度作り直し（Prometheus v3.15.0 と config-reloader v0.90.1 の組み合わせ）、新しい operator が替わってもう一度作り直す。Prometheus の Pod の入れ替わりは計 3 回になりうる（dev では pod-1 が 2 回）。`podManagementPolicy: Parallel` でも、RollingUpdate は 1 つずつで、dev ではどの時点でも 1 つは Ready だった。それぞれの Prometheus には自分の入れ替わりの間（30〜60 秒）の欠けが入る。

### 8.3 `InvalidConfiguration` のイベント

operator が替わる間だけ、ServiceMonitor が一時的に拒否される。上げるときは古い operator が `kube-prometheus-operator` の ServiceMonitor を「Secret `kube-prometheus-admission` に `ca.crt` が無い」で拒否する（Secret が作り直されるまで。dev で 23 秒）。戻すときは新しい operator が control-plane の 7 つを「scrapeClass `kube-prometheus-stack-control-plane` が無い」で拒否する（dev で 3 秒）。替わった後は受け付けられる。§4.2 の 13 では、新しい operator が Ready になった後に新しいものが出ていないことを見る。

### 8.4 Grafana の advisor

Grafana 13.2.4 は、dev で 92.13.1 に上げた最初の起動でだけ `grafana-advisor-app` を読み込まなかった（`database is locked (SQLITE_BUSY)` で署名の検証に失敗）。上げ直した後の起動では読み込まれた。Grafana のデータは emptyDir なので起動のたびに作り直される。ダッシュボードとデータソースは使えた。本番で出ても止めない（記録する）。

### 8.5 前の Job の TTL

admission の Job（create・patch）は `ttlSecondsAfterFinished: 60` で消える。Job の spec は immutable なので、Job が残っている間に CRD 以外を apply し直すと Job の更新が拒否される（ほかのオブジェクトは apply される）。apply し直す（§3.3 の流し直し、§7.2 の戻し、上げ直し）前は、`get jobs` が空になるのを待つ。

### 8.6 operator が作るもの

`kube-system/kube-prometheus-kubelet` の Service（と Endpoints）は operator が作る（`--kubelet-service`。render に無く、ownerReference も無い）。更新では触られず、新しい operator がそのまま使う。

### 8.7 `grafana` の Secret と `checksum/secret`

`grafana` の Secret は render に無い（base のパッチで消している。本物は sops の `secrets/prod/kube-prometheus.enc.yaml`）。Grafana の Deployment の `checksum/secret` の注釈は helm の生成のたびに変わる値で、本物の Secret の中身とは関係が無い（#206）。この更新で Grafana の Pod が作り直されるのは image などが変わるためで、Secret は変わらない。

## 9. 記録

`results/kube-prometheus-92/` に、ベースライン（`baseline.md`。§1 の前提、§1.4 の当日の render の照合、§2.2 の表、§2.6 の diff と dry-run）と、作業の記録（`summary.md`。§3.2・§3.3 の出力、§4.1 の入れ替わりの時刻（operator の restart と Ready、Job、Secret の作り直し、StatefulSet の revision と ready、古い Pod の消えた時刻）、§4.2 の各項目、§4.3 の結果、§5 のデータの扱い（ブロック数、最も古いサンプル、PVC の UID）、手順書との差）を残す。形は `results/metrics-server-0.9/` に合わせる。
`snap.sh`・`targets.sh`・`apps.sh`・`node-state.sh` の出力と監視のログ（`mon-watch.log`）、diff・dry-run・apply の出力はタスクディレクトリの `notes/kube-prometheus-92/` に置き、要点を記録に写す（トークンと Secret の値は書かない）。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（記録の PR で）。

## 10. この後

- 計画 §8 の残りの非クリティカルなコンポーネント（CoreDNS v1.15）
- 計画 §10 の片付けで、kube-prometheus に関わるもの: ノードの containerd に残る古いイメージ（85.2.1 のものと、それより前の Prometheus v2.x・operator v0.53・v0.63・prometheus-adapter など。§2.2 の 18）、chart の外に残った古い ClusterRole・ClusterRoleBinding（`g0-grafana-clusterrole`・`p0-prometheus-kube-state-metrics`。§2.2 の 17）、戻した場合の ConfigMap `kube-prometheus-k8s-resources-nodes-overview`
- fleet-infra の apply を server-side に移すかどうか（§3.4）。この更新の範囲の外
