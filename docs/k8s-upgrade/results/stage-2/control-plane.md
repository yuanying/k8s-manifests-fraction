# `install kubernetes` の段 2 の作業記録

control-plane のマニフェスト（apiserver、controller-manager、scheduler、kube-proxy）を v1.31.14 に、kubelet-serving-cert-approver を `0.12.1` に、porkadot 0.31.0 の `install kubernetes --node 192.168.1.111` で上げた記録。手順は `../../runbook-stage-2.md`（以下 runbook）§3。
時刻は UTC。前の読み取りは `baseline.md`。

## 1. 事前の読み取り（2026-10-19 07:15Z〜07:18Z）

`baseline.md` §2 のとおり（runbook §3.1 の項目はすべて満たしていた。段 2 の開始の承認は 2026-10-19 にユーザーから得ていて、§2.5 の render の PR #30 はマージ済み）。

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready、全台 v1.30.14 |
| etcd、VIP | 3/3 healthy、リーダー .113（`57ec6f12ac7b683e`）、raft term 23114。版 3.5.34。`/readyz` `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached 2（`myao/myao`、`homegallery/cg-data`） |
| Longhorn の設定 | `replica-auto-balance` `disabled`、`concurrent-replica-rebuild-per-node-limit` `5`、`node-drain-policy` `block-if-contains-last-replica` |
| controller-manager と scheduler | controller-manager は .111（`-6pg99`）と .113（`-jg62c`、リーダー）、scheduler は .111（`-lffqk`、リーダー）と .112（`-nbklj`） |
| MetalLB の告知ノード | VIP: pablo、gated-v4・v6: chirico、`h2-sshd`: .112、`natsumi-sshd`: .111、`natsumi-sshd-myao`: duchamp、`natsumi-sshd-aki`: .112 |
| approver | `kubelet-serving-cert-approver-6b9bcf6f87-hz6mp`（chirico）、`:main`、`Always` |
| 作業ツリー | `git status --short assets porkadot.yaml` は空（流した後も空） |

## 2. `install kubernetes`（runbook §3.2）

- `porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml`（cwd は段 2 の worktree。サンドボックスの中）
- 開始 07:18:08Z、終わり 07:18:35Z、rc 0
- `kubectl apply` の結果: `configured` は次の 17 個で、ほかの 47 個は `unchanged`（段 1 と同じ数）
  - Deployment `kube-controller-manager`、`kube-scheduler`、`kubelet-serving-cert-approver`、DaemonSet `kube-apiserver`、`kube-proxy`、Service `porkadot-kubernetes-latest`（runbook §2.5 の差分のとおり）
  - ServiceAccount `kube-controller-manager`・`kube-proxy`・`kube-scheduler`、ClusterRoleBinding `porkadot:kube-controller-manager`・`porkadot:kube-scheduler`・`porkadot:node-proxier`・`porkadot:volume-scheduler`、ConfigMap `kube-proxy`、PodDisruptionBudget `kube-controller-manager`・`kube-scheduler`（どれも `app.kubernetes.io/version` のラベル。段 1 と同じ）
  - ValidatingWebhookConfiguration `metallb-webhook-configuration`（MetalLB の controller が入れる `caBundle` の入れ直し。段 1 と同じ）
- CoreDNS は `unchanged`（v1.11.3 のまま）

## 3. rollout（runbook §3.3）

`rollout status` は 5 つ（kube-apiserver、kube-controller-manager、kube-scheduler、kube-proxy、kubelet-serving-cert-approver）とも `successfully rolled out`。07:21:07Z に終わった（`install kubernetes` の開始から 2 分 59 秒。段 1 は 3 分 12 秒）。

- apiserver の DaemonSet は .112（07:18:57Z に作られ 07:19:18Z に Ready）→ .113（07:19:54Z → 07:20:15Z）→ .111（07:20:45Z → 07:21:06Z）の順に入れ替わった
- controller-manager は .112（`-2ffhd`、07:18:26Z）と .111（`-2blbx`、07:18:47Z）、scheduler は .113（`-mp2ld`、07:18:27Z）と .112（`-vb2lz`、07:18:47Z）に作り直された
- approver は 07:18:27Z に oeilvert に作られ、07:18:38Z に Ready（startupProbe を通った）
- 止まって見える間は無かった

## 4. 確認（runbook §3.3。07:21Z〜07:22Z）

| # | 確認 | 結果 |
|---|---|---|
| 1 | `kubectl version` | Server v1.31.14 |
| 2 | Deployment と DaemonSet | kube-controller-manager 23 → 24、kube-scheduler 22 → 23、kube-apiserver 24 → 25、kube-proxy 20 → 21（どれも v1.31.14）。coredns（9、`v1.11.3`）、kube-dns-autoscaler（4）、metrics-server（1）、cnidaria（2）、MetalLB の controller（18）・speaker（22）は変わらない |
| 3 | apiserver | 3/3 Running・Ready（`kube-apiserver-bvcxk` .112、`-rxv47` .113、`-v7wdz` .111）。VIP の `/readyz` `ok`、`/version` v1.31.14 |
| 4 | KCM と scheduler | 2/2 ずつ Running。controller-manager は .111（`-2blbx`、リーダー）と .112（`-2ffhd`）、scheduler は .112（`-vb2lz`、リーダー）と .113（`-mp2ld`）。同じ master に同じ component が 2 つ載っていない |
| 5 | kube-proxy | 8 台で Running。8 つともログに `Using iptables Proxier` |
| 6 | CoreDNS | 2/2 Running（duchamp、oeilvert。再起動していない）。chirico のホストから `dig @10.254.0.10 kubernetes.default.svc.cluster.local` が `10.254.0.1` を返す |
| 7 | Node | 8 台 Ready、kubelet は全台 v1.30.14 のまま |
| 8 | Pod | Running / Completed 以外は 0 個。07:18:08Z より後に終わったコンテナは無い。ベースラインの控えと比べ、rollout で入れ替わった 16 個（apiserver 3、controller-manager 2、scheduler 2、kube-proxy 8、approver 1）のほかは、名前・UID・restartCount が変わっていない |
| 9 | Longhorn | attached healthy 23、detached unknown 2（ベースラインと同じ） |
| 10 | 監視 | FAIL 0 |
| 11 | warning | rollout で消える古い apiserver の Pod（`-b2rjt`、`-nm6fc`、`-s4wln`）の readiness の失敗（`statuscode: 500` 1 回と `connection refused`）だけ |
| 12 | leader election を使う controller | 再起動したものは無い（runbook §8.8 のコマンドで 07:18:08Z より後に終わったコンテナが 0） |
| 13 | approver | `kubelet-serving-cert-approver-7d5f768656-fhsk8`（**oeilvert**）、1/1。イメージ `ghcr.io/alex1989hu/kubelet-serving-cert-approver:0.12.1`、`IfNotPresent`、imageID `sha256:445a8e5584f659701092d2ec8b625da8929dc75fe4d45274333bd9fe6db8fb75`。startupProbe（`/healthz`、10 秒ごと、30 回）と `node.cloudprovider.kubernetes.io/uninitialized` の toleration が入っている。ログに `Successfully connected to Kubernetes API Server`、`Starting workers` |
| 14 | CSR | 無い |

ほかに: `verify-nodes.sh` 64 PASS、FAIL 0。cnidaria のログの error の数はベースラインと同じ（.111 7、.112 7、.113 8、braque 8、chirico 8、duchamp 6、oeilvert 0、pablo 8）。`check-apps.sh` はベースラインと同じ（Running でない Pod 0、IP の重複 0、hedgedoc の db Running、192.168.1.200 と v6 の LB 404、VIP 200）。`h2-sshd`、`natsumi-sshd*` の 4 つは SSH のバナーを返す。

## 5. 監視の FAIL と、その原因

なし（07:14Z〜07:22Z で FAIL 0）。

## 6. 次へ進む条件

| 条件 | 結果 |
|---|---|
| §3.3 の 1〜14 | すべて合格 |
| 全 8 台 Ready | 合格 |
| etcd 3/3 healthy | 合格（control-plane の kubelet の前に読み直す） |
| Running / Completed 以外の Pod がベースラインから増えていない | 合格（0 個） |

## 7. 手順書との差、気づいたこと

- approver の Pod は chirico から **oeilvert** に移った（新しい ReplicaSet の Pod の置き場所）。oeilvert は worker の最後に drain するので、そのときにもう一度ほかのノードへ移る（1 replica。数十秒止まる。runbook §2.6 の表の「1 replica の Deployment」）
- controller-manager と scheduler の置き場所とリーダーが変わった（段 1 の後の .111・.113 と .111・.112 から、.111・.112 と .112・.113 へ）。runbook §4.2 の 1 の 2026-10-19 の値は使えないので、各台の前に読み直す
