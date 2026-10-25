# metrics-server v0.9.0 のベースライン

本番 `fraction` の metrics-server を v0.7.2 から v0.9.0 へ上げる（fleet-infra#203 の render を client-side apply）前に取った、読み取りの結果と `kubectl diff`・`--dry-run=server` の記録。手順は `../../runbook-metrics-server-0.9.md`（以下 runbook）。
時刻は UTC。`snap.sh`・`node-state.sh` の出力、`diff.txt`・`dry-run.txt` は、タスクディレクトリの `notes/metrics-server-0-9/` に置いた（リポジトリには入れない）。

## 1. 前提（runbook §1。2026-10-25 11:30〜11:32Z）

| 項目 | 結果 |
|---|---|
| 本番の今の姿（§1.1） | 8 台 Ready・schedulable、v1.37.1、`containerd://2.3.6`。Pod 168 個（Running 145、Completed 23）で、Running / Completed 以外は 0 個。kube-dns-autoscaler の更新は済んでいる（`../dns-autoscaler-1.11/summary.md`）。metrics-server は v0.7.2 の 1 つ（chirico の `metrics-server-75bf97fcc9-6t94q`、restart 0、2026-10-23 06:24:54Z 起動）。APIService は Available |
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor`。`auth can-i create serviceaccounts --subresource=token -n kube-system` は `yes`。作業端末の kubectl は v1.37.1。11:32:09Z に `infra-admin` のトークンを 1 時間の期限で発行し、`auth can-i patch deployments -n kube-system`・`auth can-i patch apiservices` がどちらも `yes` |
| SSH（§1.3） | サンドボックスの中から、8 台に IP で `node-state.sh` を流せた |
| fleet-infra の render（§1.4） | タスクディレクトリの clone `worktrees/fleet-infra-ms-rc` を fetch した。main は `9a08fb9`（GitHub の `refs/heads/main` と同じ。runbook を書いたときの `ebe7cc9` の後に Renovate の #43・#45 が入った）。`git log baecff7..origin/main -- infrastructure/metrics-server/` は空。main の `infrastructure/metrics-server/` を `git archive` で取り出した `kubectl kustomize …/prod/` の sha256 は `1cec29a5…`（`v0.9.0.yaml` と同じ）。`render/metrics-server-0.9/` の `sha256sum -c SHA256SUMS` は 2 つとも OK |
| 入れる版（§1.5。11:31Z） | v0.9.0・v0.7.2 とも manifest list で amd64・arm・arm64・ppc64le・s390x。v0.9.0 の index の digest は `sha256:d9862115e7c7881280d3d75ca26bda8ffc0fc213315979575bf23ce9826205c0`、v0.7.2 は `sha256:ffcb2bf0…`（今の Pod の `imageID` と同じ）。アプリの最新の release は v0.9.0（2026-07-13）で、v0.9.1 は無い |
| etcd のスナップショット（§2.4） | 取らない。メインの checkout の `backup/etcd-2026-10-25T10:16:55+00:00.db`（55,107,616 B）があることを確かめた |

## 2. ベースライン（runbook §2.2。11:31:31Z の `snap.sh`、11:31:43Z の `node-state.sh`）

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node と taint | 8 台 Ready、v1.37.1、cordon されたものは無い。taint は control-plane 3 台（arm64）が `node-role.kubernetes.io/master:NoSchedule`、braque が `unstable.cloud/storage:NoSchedule`、chirico・duchamp・oeilvert・pablo（amd64）は無い |
| 2 | 全 Pod | 168 個（Running 145、Completed 23）。名前・UID・restartCount は `notes/metrics-server-0-9/base/pods.txt` |
| 3 | Deployment | 2026-10-15 08:39:44Z 作成、generation 1、revision 1、1/1。イメージ `registry.k8s.io/metrics-server/metrics-server:v0.7.2`。引数は `--cert-dir=/tmp --secure-port=10250 --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname --kubelet-use-node-status-port --metric-resolution=15s`（`--kubelet-insecure-tls` は無い）。strategy は RollingUpdate（`maxSurge: 25%`・`maxUnavailable: 0`）、revisionHistoryLimit 10。nodeSelector は `kubernetes.io/os: linux`、tolerations は無い、priorityClass は `system-cluster-critical` |
| 4 | Pod | chirico の `metrics-server-75bf97fcc9-6t94q`（UID `60d76b92-f25a-4fa4-b816-8ff5dfe9a177`、restart 0、2026-10-23 06:24:54Z 起動、Pod IP `10.244.8.87`）。`imageID` は `registry.k8s.io/metrics-server/metrics-server@sha256:ffcb2bf004d6aa0a17d90e0247cf94f2865c8901dcab4427034c341951c239f9` |
| 5 | ReplicaSet | `metrics-server-75bf97fcc9`（1/1、v0.7.2）だけ |
| 6 | Service・EndpointSlice | ClusterIP `10.254.0.133`、port `https` 443 → `https`（`appProtocol` は無い）、resourceVersion `1235922531`。EndpointSlice `metrics-server-hkw72` は `10.244.8.87:10250` |
| 7 | APIService `v1beta1.metrics.k8s.io` | Available `True`（`Passed`、`all checks passed`）、2026-10-23 06:25:16Z から。`insecureSkipTLSVerify: true`、`groupPriorityMinimum: 100`、`versionPriority: 100`、resourceVersion `1238973626`。Local でない APIService はこれだけ |
| 8 | `kubectl top` | `top nodes` が 8 台、`top pods -A` が 145 行（Running の Pod の数と同じ） |
| 9 | ログ | 178 行。`I` の行は起動の 14 行、`E` の行は 164 行でどれも `Failed to scrape node`（ノードが止まっていた間のもの）。最後の `E` は 2026-10-24 12:39:41Z（.112 の `connection refused`）。`x509` は 0 行。metrics-server の events は無い。apiserver 3 つの直近 2 時間のログに `metrics.k8s.io`・`metrics-server` を含む行は無い |
| 10 | HPA・VPA | HPA は 0 個。VPA の CRD は無い |
| 11 | RBAC と last-applied | ServiceAccount `metrics-server`（rv `1235922524`）、ClusterRole `system:aggregated-metrics-reader`（`1235922525`）・`system:metrics-server`（`1235922526`）、RoleBinding `metrics-server-auth-reader`（`1235922527`）、ClusterRoleBinding `metrics-server:system:auth-delegator`（`1235922528`）・`system:metrics-server`（`1235922529`）。`lastapplied-diff.sh` で、`v0.7.2.yaml` は 9 つとも `SAME`、`v0.9.0.yaml` は Service（`appProtocol: https`）と Deployment（image）だけ `DIFF` |
| 12 | kubelet と serving 証明書（`node-state.sh`） | .111 MainPID 752609・NRestarts 0、.112 1028・1、.113 612672・0、braque 541944・0、chirico 3237977・0、duchamp 202232・0、oeilvert 916805・51、pablo 3509679・0（ActiveEnterTimestamp を含めて autoscaler のベースラインと同じ）。serving 証明書は 8 台とも issuer `CN = kube-ca`、期限は oeilvert 2027-03-20、chirico 2027-06-23、pablo 2027-08-08、braque 2027-08-18、duchamp 2027-09-06、.111〜.113 2027-10-16 |
| 13 | containerd の metrics-server のイメージ | v0.7.2（`48d9cfaaf3904`、19.5 MB）が chirico・duchamp・oeilvert にある。pablo・braque・control-plane には無い。v0.9.0 はどの台にも無い |
| 14 | kube-system の NetworkPolicy | 無い |
| 15 | VIP | `https://192.168.1.101:6443/readyz` が 200 |

## 3. 監視（runbook §2.3）

11:31:5xZ に、ハーネスのバックグラウンド実行で 1 つのジョブとして起動した（bg1: `top-watch.sh`）。`nohup`・`&` は使っていない。ログはタスクディレクトリの `notes/metrics-server-0-9/logs/top-watch.log`。起動の直後から `top=OK n=8 apiservice=True:Passed` で、間隔は約 1.4 秒。

## 4. `kubectl diff` と `--dry-run=server`（runbook §2.6。11:32:13Z）

`infra-admin` のトークンで流した。

- `diff -f v0.9.0.yaml` は **rc 1**。差は Deployment の `generation`（1 → 2）と image（v0.7.2 → v0.9.0）、Service の port の `appProtocol: https` だけ。ほかのオブジェクトの差は無い。dev の `diff-2-baecff7.txt` と同じ形
  - runbook §2.6 が差に挙げていた「last-applied の注釈の中の image」は diff に出なかった（dev の diff にも出ていない。`kubectl diff` の MERGED 側は last-applied の注釈を書き換えない）。runbook を直した（この PR）
- `apply -f v0.9.0.yaml --dry-run=server` は **rc 0**。`service/metrics-server configured (server dry run)`、`deployment.apps/metrics-server configured (server dry run)`、ほかの 7 つは `unchanged (server dry run)`。`created` は無い
