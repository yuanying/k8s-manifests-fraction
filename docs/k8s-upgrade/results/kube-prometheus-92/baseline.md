# kube-prometheus-stack 92.13.1 のベースライン

本番 `fraction` の kube-prometheus-stack を chart 85.2.1 から 92.13.1 へ上げる（fleet-infra#206 の render を、CRD は server-side apply、CRD 以外は client-side apply）前に取った、読み取りの結果と `kubectl diff`・`--dry-run=server` の記録。手順は `../../runbook-kube-prometheus-92.md`（以下 runbook）。
時刻は UTC。`snap.sh`・`targets.sh`・`apps.sh`・`node-state.sh` の出力、`diff-*.txt`・`dry-run-*.txt`、監視のログは、タスクディレクトリの `notes/kube-prometheus-92/` に置いた（リポジトリには入れない）。

## 1. 前提（runbook §1。2026-10-26 00:10〜00:11Z）

| 項目 | 結果 |
|---|---|
| 本番の今の姿（§1.1） | 8 台 Ready・schedulable、v1.37.1、`containerd://2.3.6`。Pod 169 個（Running 145、Completed 24）で、Running / Completed 以外は 0 個。metrics-server の更新は済んでいる（`../metrics-server-0.9/summary.md`）。`monitoring` の Pod 23 個がすべて Running・Ready |
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor`。`auth can-i create serviceaccounts --subresource=token -n kube-system` は `yes`。作業端末の kubectl は v1.37.1（kustomize v5.8.1）。00:11:41Z に `infra-admin` のトークンを 2 時間の期限で発行し、`auth can-i patch customresourcedefinitions`・`patch prometheuses -n monitoring`・`create jobs -n monitoring` が 3 つとも `yes` |
| SSH（§1.3） | サンドボックスの中から、8 台に IP で `node-state.sh` を流せた |
| fleet-infra の render（§1.4） | GitHub から `/tmp/fleet-infra-kp` に clone した。main は `675f543`（#206 のマージ）。`git log 675f543..HEAD -- infrastructure/kube-prometheus/` は空。`kubectl kustomize …/prod/` の sha256 は `f5f2880f2ebf453ea691c4ea6dc049a7528e024880fdf6f72a5dd8409b38a6bb`（5,306,863 B）。yq v4.54.1 で分けた CRD と CRD 以外は `92.13.1-crds.yaml`・`92.13.1-rest.yaml` と `cmp` で同じ。`render/kube-prometheus-92/` の `sha256sum -c SHA256SUMS` は 4 つとも OK |
| 入れる版（§1.5。00:10Z） | chart の最新は 92.13.1（2026-10-24 13:08:20Z、appVersion v0.94.1）。その前は 92.13.0・92.12.0（同じ日）。92.13.2 や 93 は無い |
| etcd のスナップショット（§2.4） | 取らない。メインの checkout の `backup/etcd-2026-10-25T10:16:55+00:00.db`（55,107,616 B）があることを確かめた |

## 2. ベースライン（runbook §2.2。00:10:26Z の `snap.sh`、00:10:30Z の `targets.sh`・`apps.sh`、00:10:32Z の `node-state.sh`）

| # | 項目 | 結果 |
|---|---|---|
| 1 | Deployment | `grafana`（generation 4。k8s-sidecar 2.7.3 ×2、grafana 13.0.1-security-01）、`kube-prometheus-operator`（generation 2、v0.90.1）、`kube-state-metrics`（generation 1、v2.19.0）。どれも 1/1 |
| 2 | StatefulSet・CR | `prometheus-kube-prometheus` 2/2（revision `prometheus-kube-prometheus-844d4d5478`、generation 17）、`alertmanager-kube-prometheus` 2/2（`alertmanager-kube-prometheus-7d86bdb48`、generation 1）。Prometheus の CR は generation 17、`v3.11.3-distroless`、replicas 2、retention `10d`、bronze 20Gi、Available・Reconciled `True`。Alertmanager の CR は generation 1、`v0.32.1`、replicas 2、retention `120h`、storage なし、Available・Reconciled `True` |
| 3 | DaemonSet | `node-exporter` 8/8（v1.11.1-distroless）、`smart-exporter` 8/8（node-exporter-smartmon 0.19.0） |
| 4 | Pod | 23 個、すべて Running・Ready。operator は pablo の `kube-prometheus-operator-658779c859-zcrzg`（restart 0、10-19 08:09:58Z 起動）。Prometheus は pod-0 が duchamp（UID `2234b148-…`）・pod-1 が chirico（UID `25bcb4e2-…`）、どちらも restart 0、10-21 03:03:49Z 起動。Alertmanager は pod-0 が duchamp（10-23 06:24:56Z）・pod-1 が chirico（10-19 09:35:29Z）。Grafana `grafana-58c48f66d9-sg62g`・kube-state-metrics `kube-state-metrics-5cb8d8ffb9-cwp6t` は chirico。smart-exporter の 8 つは `2hqck`・`dpfg8`・`hm5b6`・`l4tf2`・`sbtzl`・`t9v4l`・`wd2kb`・`zr27p`（restart 2〜8） |
| 5 | PVC | `…-0`（UID `625c8825-4571-43d8-9119-c006a4a48399`）と `…-1`（UID `99c35b80-7928-4b9b-a4ac-3afa8e7a7b05`）。どちらも bronze 20Gi・Bound、2024-10-09 作成。Longhorn のボリュームは 2 つとも attached・healthy（pod-0 のものが duchamp、pod-1 のものが chirico）、replicas 1、engine v1.13.0 |
| 6 | Longhorn 全体 | attached・healthy 16、detached 1（以前から） |
| 7 | Prometheus の TSDB | 2 つとも v3.11.3、ブロック 16、最も古いサンプル 2026-10-15 06:00:00Z（`1792044000`）、ブロック 7,569,758,182 B（pod-0）・7,606,458,373 B（pod-1）、WAL 約 0.59 GB（pod-0）・0.46 GB（pod-1）、head の series 約 22.85 万 |
| 8 | Prometheus の設定（`apps.sh`） | 2 つとも job 18、`bearer_token_file` 0、`credentials_file` 9、`ca_file` が SA の `ca.crt` のもの 6、ConfigMap `kube-root-ca.crt` のもの 0。reload は成功（1）。ルールは 284 個とも ok |
| 9 | CRD 10 個 | どれも `operator.prometheus.io/version: 0.90.1`、generation 1。`storedVersions` は v1 の 7 つが `[v1]`、v1alpha1 の 3 つが `[v1alpha1]`。**ラベル `crd: "true"`・last-applied の注釈・managedFields の `kubectl-client-side-apply`（Update）があるのは `podmonitors`・`probes`・`prometheusrules`・`servicemonitors` の 4 つ**（last-applied は 41,705 B・41,726 B・8,484 B・42,213 B）。ほかの 6 つの managedFields は `kubectl`（Apply）と `kube-apiserver`（Update/status）だけ |
| 10 | admission | Secret `kube-prometheus-admission` は **`Opaque`、キーは `ca`・`cert`・`key`**、UID `f7fb10a4-c757-4c26-bbb8-a65558adbf76`、2026-08-22 作成。MutatingWebhookConfiguration・ValidatingWebhookConfiguration `kube-prometheus-admission` がある。Job は無い |
| 11 | ServiceMonitor など | ServiceMonitor 13、PodMonitor 1、PrometheusRule 37、Probe・ScrapeConfig・AlertmanagerConfig・PrometheusAgent・ThanosRuler は 0 |
| 12 | ターゲット（`targets.sh`） | 2 つの Prometheus とも **65 個すべて up**（kubelet 8×3、kube-proxy 8、node-exporter 8、apiserver 3、etcd 3、coredns 2、controller-manager 2、scheduler 2、Prometheus 2×2、Alertmanager 2×2、gated 2、Grafana 1、operator 1、kube-state-metrics 1） |
| 13 | アプリ（`apps.sh`） | Grafana の `/api/health` が `database: ok`、`13.0.1+security-01`。Alertmanager は 2 つとも 0.32.1、cluster `ready`、peers 2。operator のログの error の行は 0 |
| 14 | last-applied | `85.2.1-rest.yaml` は `SAME=122 DIFF=0 MISSING=2`（Job 2 つ）。`92.13.1-rest.yaml` は `SAME=5 DIFF=117 MISSING=3`（SAME は smart-exporter の DaemonSet、PrometheusRule `prometheus-smart-rules`、Ingress 3 つ） |
| 15 | 本番の Secret（名前・型・キーの名前・UID だけ） | `grafana`（`Opaque`、`admin-password`・`admin-user`・`ldap-toml`、UID `a71a973e-…`）、`alertmanager-kube-prometheus`（`Opaque`、`alertmanager.yaml`、UID `ef77b74a-…`）、`alertmanager-fraction-jp-gated-tls`（`07def603-…`）・`grafana-fraction-jp-gated-tls`（`b7ec3c5e-…`）・`prometheus-fraction-jp-gated-tls`（`39d8be42-…`）は `kubernetes.io/tls` |
| 16 | Ingress | `prometheus`・`alertmanager`・`grafana`（class `gated`、アドレス `192.168.1.200` と `2405:6580:6740:ac01:ace::200`）。外からの `https://<名前>.fraction.jp/` は 3 つとも `401` |
| 17 | cluster の RBAC | runbook のとおり。chart の外の `g0-grafana-clusterrole`・`p0-prometheus-kube-state-metrics`（と binding）も残っている |
| 18 | ノードのイメージ（`node-state.sh`） | 92.13.1 のイメージはどの台にも無い。85.2.1 の Prometheus・Alertmanager・config-reloader は chirico・duchamp・oeilvert・pablo、operator は chirico・pablo、Grafana は chirico・duchamp・pablo にある。control-plane と braque は node-exporter と smartmon だけ |
| 19 | kubelet（`node-state.sh`） | .111 MainPID 752609・NRestarts 0、.112 1028・1、.113 612672・0、braque 541944・0、chirico 3237977・0、duchamp 202232・0、oeilvert 916805・51、pablo 3509679・0（metrics-server のベースラインと同じ） |
| 20 | SA token の Secret | `kube-system/infra-admin` と `kube-system/infra-auditor` の 2 つだけ |
| 21 | operator が作る Service | `kube-system/kube-prometheus-kubelet`（UID `55a054e0-62ba-4a6d-8c2f-0943bf74ea93`、ownerReference なし） |
| 22 | その他 | `monitoring` の events は空（`InvalidConfiguration` は 0）。VIP の `https://192.168.1.101:6443/readyz` が 200 |

## 3. 監視（runbook §2.3）

00:11:2xZ に、ハーネスのバックグラウンド実行で 1 つのジョブとして起動した（bg1: `mon-watch.sh`）。`nohup`・`&` は使っていない。ログはタスクディレクトリの `notes/kube-prometheus-92/logs/mon-watch.log`。起動の直後から `sts=alertmanager-kube-prometheus:2:2:… prometheus-kube-prometheus:2:2:…`、`grafana=ok prom=Prometheus Server is Ready. am=OK`。

## 4. `kubectl diff` と `--dry-run=server`（runbook §2.6。00:11:49〜00:12:14Z）

`infra-admin` のトークンで流した。

| コマンド | rc | 結果 |
|---|---|---|
| `diff --server-side -f 92.13.1-crds.yaml` | 1 | `diff -u` 10 個 |
| `apply --server-side --dry-run=server -f 92.13.1-crds.yaml` | 0 | 10 個とも `serverside-applied (server dry run)`。**4 つに Warning（下）** |
| `diff -f 92.13.1-rest.yaml` | 1 | `diff -u` 120 個 |
| `apply --dry-run=server -f 92.13.1-rest.yaml` | 0 | `configured` 117・`created` 3（ConfigMap `kube-prometheus-k8s-resources-nodes-overview`、Job `kube-prometheus-admission-create`・`-patch`）・`unchanged` 5（smart-exporter、`prometheus-smart-rules`、Ingress 3 つ）。エラーは無い |

- **CRD の dry-run の Warning**: last-applied を持つ 4 つ（`podmonitors`・`probes`・`prometheusrules`・`servicemonitors`）で、それぞれ次の 1 行が出た。

  ```
  Warning: failed to migrate kubectl.kubernetes.io/last-applied-configuration for Server-Side Apply. This is non-fatal and will be retried next time you apply. Error: Apply failed with 1 conflict: conflict with "kubectl-client-side-apply" using apiextensions.k8s.io/v1: .metadata.annotations.kubectl.kubernetes.io/last-applied-configuration
  ```

  kubectl が client-side apply の managedFields（`kubectl-client-side-apply`）を server-side の manager に移そうとして、last-applied の注釈の持ち主の違いで失敗したという警告で、kubectl は non-fatal と書いている。apply の本体は 4 つとも `serverside-applied` で、`--force-conflicts` は要らない。runbook §2.6 は「`conflict` の文字が出たら止める」と書いているので、ここで止めて coordinator に報告した（判断は summary.md）
- **CRD の差**（server-side の diff）: 10 個とも注釈 `controller-gen.kubebuilder.io/version`（v0.19.0 → v0.22.0）と `operator.prometheus.io/version`（0.90.1 → 0.94.1）。ラベルの無い 6 つに `crd: "true"` が足される。**`generation` は 9 つが 1 → 2 で、`prometheusrules` だけ 1 のまま**（schema の差が無く、注釈だけが変わるため）。last-applied を持つ 4 つは、**last-applied の注釈が消えずに新しい内容（0.94.1 の注釈）に書き換わる**差が出た。`spec.versions[].name`・`served`・`storage` の差、`status` の差は無い
- **CRD 以外の差**（client-side の diff）: runbook §2.6 のとおり。Prometheus の CR は generation 17 → 18、ラベル、image と `version`（v3.15.0-distroless）、`nodeSelector`、`scrapeClasses`（`kube-prometheus-stack-control-plane`）だけで、**`spec.storage` の差は無い**。Alertmanager の CR は generation 1 → 2、ラベル、image と `version`（v0.34.1）、`nodeSelector`、`hostNetwork: false` が消える。operator の Deployment は image（v0.94.1）、`--prometheus-config-reloader`（v0.94.1）、`--thanos-default-base-image`（v0.42.4）、`--secret-field-selector` から `type!=kubernetes.io/service-account-token` が外れる、`--web.cert-file=/cert/tls.crt`・`--web.key-file=/cert/tls.key`、`nodeSelector`。Role `kube-prometheus-admission` に Secret `kube-prometheus-admission` の `delete` が足される。create の Job に `--secret-type=kubernetes.io/tls`。**Deployment・DaemonSet・Service の `spec.selector` の差は無い**（selector が `+` で出るのは新しい Job 2 つだけ）
