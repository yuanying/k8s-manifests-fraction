# `install kubernetes` の段 1 の作業記録

control-plane のマニフェスト（apiserver、controller-manager、scheduler、kube-proxy、CoreDNS）を、porkadot 0.30.0 の `install kubernetes --node 192.168.1.111` で v1.30.14 に上げた記録。手順は `../../runbook-stage-1.md`（以下 runbook）§3。
時刻は UTC。前の読み取りは `baseline.md`。

## 1. 事前の読み取り（2026-10-19 00:42Z〜00:47Z）

`baseline.md` §2 のとおり（runbook §3.1 の項目はすべて満たしていた）。

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready、全台 v1.29.8 |
| etcd、VIP | 3/3 healthy、リーダー .113（`57ec6f12ac7b683e`）、raft term 23112。版 3.5.12。`/readyz` `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached 2（`myao/myao`、`homegallery/cg-data`） |
| Longhorn の設定 | `replica-auto-balance` `disabled`、`concurrent-replica-rebuild-per-node-limit` `5`、`node-drain-policy` `block-if-contains-last-replica` |
| controller-manager と scheduler | どちらも .112 と .113 に 1 つずつ。リーダーはどちらも .113 の Pod |
| MetalLB の告知ノード | VIP: pablo、gated-v4・v6: chirico、`h2-sshd`: .112、`natsumi-sshd`: .111、`natsumi-sshd-myao`: duchamp、`natsumi-sshd-aki`: .112 |
| 作業ツリー | `git status --short assets porkadot.yaml` は空 |

## 2. `install kubernetes`（runbook §3.2）

- `porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml`
- 開始 00:47:50Z、終わり 00:48:18Z、rc 0
- `kubectl apply` の結果: `configured` は次の 17 個で、ほかの 47 個は `unchanged`
  - Deployment `coredns`、`kube-controller-manager`、`kube-scheduler`、DaemonSet `kube-apiserver`、`kube-proxy`、Service `porkadot-kubernetes-latest`（runbook §2.5 の差分のとおり）
  - ServiceAccount `kube-controller-manager`・`kube-proxy`・`kube-scheduler`、ClusterRoleBinding `porkadot:kube-controller-manager`・`porkadot:kube-scheduler`・`porkadot:node-proxier`・`porkadot:volume-scheduler`、ConfigMap `kube-proxy`、PodDisruptionBudget `kube-controller-manager`・`kube-scheduler`（どれも `app.kubernetes.io/version` のラベル。runbook §2.5 の表には個別に書いていない）
  - ValidatingWebhookConfiguration `metallb-webhook-configuration`（MetalLB の controller が入れる `caBundle` がマニフェストに無いためと見られる。00:51Z に 6 つの webhook とも `caBundle` が入っていた）
- Secret は `install.secrets.sh` で apply された（`kube-apiserver.secrets.yaml`、`kube-controller-manager.secrets.yaml`、`metallb.secrets.yaml`）

## 3. rollout（runbook §3.3）

`rollout status` は 5 つとも `successfully rolled out`。00:51:02Z に終わった（`install kubernetes` の開始から 3 分 12 秒。dev は 2 分 42 秒）。apiserver の DaemonSet は .113（00:48:30Z ごろ）→ .111（00:49:40Z ごろ）→ .112（00:50:31Z ごろ）の順に入れ替わった。止まって見える間は無かった。

## 4. 確認（runbook §3.3。00:51Z〜00:54Z）

| # | 確認 | 結果 |
|---|---|---|
| 1 | `kubectl version` | Server v1.30.14 |
| 2 | Deployment と DaemonSet | coredns gen 8 → 9（`v1.11.3`）、kube-controller-manager 22 → 23、kube-scheduler 21 → 22、kube-apiserver 23 → 24、kube-proxy 19 → 20（どれも v1.30.14）。kube-dns-autoscaler（4）、metrics-server（1）、cnidaria（2）、MetalLB の controller（18）・speaker（22）は変わらない |
| 3 | apiserver | 3/3 Running・Ready（`kube-apiserver-s4wln` .113、`-nm6fc` .111、`-b2rjt` .112）。VIP の `/readyz` `ok`、`/version` v1.30.14 |
| 4 | KCM と scheduler | 2/2 ずつ Running。controller-manager は .111（`-6pg99`）と .113（`-jg62c`）、scheduler は .111（`-lffqk`）と .112（`-nbklj`）。同じ master に同じ component が 2 つ載っていない。リーダーは controller-manager が `-jg62c`（.113）、scheduler が `-lffqk`（.111） |
| 5 | kube-proxy | 8 台で Running。8 つともログに `Using iptables Proxier` |
| 6 | CoreDNS | 2/2 Running（duchamp、oeilvert）。chirico と .112 のホストから `dig @10.254.0.10 kubernetes.default.svc.cluster.local` が `10.254.0.1` を返す |
| 7 | Node | 8 台 Ready、kubelet は全台 v1.29.8 のまま |
| 8 | Pod | Running / Completed 以外は 0 個。00:47:50Z より後に終わったコンテナは無い（rollout で入れ替わった Pod のほかに再起動は無い） |
| 9 | Longhorn | attached healthy 23、detached unknown 2（ベースラインと同じ） |
| 10 | 監視 | FAIL 0 |
| 11 | warning | rollout で消える古い Pod の readiness の失敗（`coredns-774448dc8-9hwxg`、`kube-apiserver-m7wv9`・`-6jv8s`・`-h2xpf` の `connection refused`）だけ |
| 12 | leader election を使う controller | 再起動したものは無い（runbook §8.9 のコマンドで 00:47:50Z より後に終わったコンテナが 0） |

ほかに: `verify-nodes.sh` 64 PASS、FAIL 0、cnidaria のログの error 0。`check-apps.sh` はベースラインと同じ（Running でない Pod 0、IP の重複 0、hedgedoc の db Running、192.168.1.200 と v6 の LB 404、VIP 200）。`h2-sshd`、`natsumi-sshd*` の 4 つは SSH のバナーを返す。

## 5. 監視の FAIL と、その原因

なし（00:47:50Z〜00:54Z で FAIL 0）。

## 6. 次へ進む条件

| 条件 | 結果 |
|---|---|
| §3.3 の 1〜12 | すべて合格 |
| 全 8 台 Ready | 合格 |
| etcd 3/3 healthy | 合格（control-plane の kubelet の前に読み直す） |
| Running / Completed 以外の Pod がベースラインから増えていない | 合格（0 個） |

## 7. 手順書との差、気づいたこと

- apply の `configured` には、runbook §2.5 の表に無い ServiceAccount・ClusterRoleBinding・ConfigMap・PDB（版のラベル）と、MetalLB の ValidatingWebhookConfiguration（`caBundle` の入れ直し）が含まれる。どれも害は無い
- dev より 30 秒ほど長かった（apiserver の Pod の起動を Pi で待つ分と見られる）
