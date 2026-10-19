# 段 3 の `install kubernetes` の作業記録

control-plane のマニフェスト（kube-apiserver、kube-controller-manager、kube-scheduler、kube-proxy、CoreDNS）を、porkadot 0.32.0 の `install kubernetes --node 192.168.1.111` で v1.32.13（CoreDNS v1.11.4）に上げた記録。手順は `../../runbook-stage-3.md`（以下 runbook）の §3。
時刻は UTC。前の記録は `baseline.md`（ベースライン、etcd のバックアップ、storage version の書き直し）。読み取りの出力はタスクディレクトリの `notes/stage-3/cp/`。

## 1. 事前の確認（runbook §3.1。2026-10-19 23:17Z）

| 項目 | 結果 |
|---|---|
| 段 3 の開始の承認 | 2026-10-19 にユーザーが承認済み（PR #33 をマージ） |
| ベースライン、バックアップ、監視 | `baseline.md` §2・§3。監視は 23:00Z から動いている |
| storage version | §2.5 の書き直しの後、`OLD: 0`、`CRDs with more than one stored version: 0`（`baseline.md` §4） |
| Longhorn の `replica-auto-balance` | `disabled` |
| Node、etcd、VIP | 8 台 Ready、etcd 3/3 healthy（リーダー .113）、VIP の `/readyz` は `ok` |
| checkout | 段 3 の worktree（PR #33 をマージした master の `cc886c8` から）。`git status --short assets porkadot.yaml` は空 |
| SSH | 22:59Z に 8 台ともサンドボックスの中で通った（`baseline.md` §1） |
| DaemonSet `kube-apiserver` の generation | 25 |

## 2. `install kubernetes`（runbook §3.2）

- 23:17:31Z〜23:17:55Z、**rc 0**。サンドボックスの中で流した。流し直しは要らなかった
- `configured` になったもの: kube-apiserver・kube-proxy の DaemonSet、kube-controller-manager・kube-scheduler・coredns の Deployment、kube-controller-manager・kube-scheduler の PDB、kube-proxy の ConfigMap、kube-controller-manager・kube-scheduler・kube-proxy の ServiceAccount、`porkadot:*` の ClusterRoleBinding 4 つ、Service `porkadot-kubernetes-latest`、`metallb-webhook-configuration`（どれも版のラベル、または毎回 `configured` になるもの）。kubelet-serving-cert-approver・cnidaria・MetalLB の Deployment と DaemonSet、`ipaddresspool`、`l2advertisement` は `unchanged`
- rollout の順（Pod の作成の時刻）: controller-manager・scheduler・CoreDNS の 1 つ目と kube-proxy の .112 が 23:17:48Z〜49Z、**apiserver は .112（23:18:25Z）→ .111（23:19:16Z）→ .113（23:20:08Z）**、kube-proxy は 8 台を 23:17:49Z〜23:18:31Z に 1 台ずつ
- apiserver の rollout が .111 からでなく .112 から始まったので、`127.0.0.1:6443` の `connection refused`（runbook §8.3）は起きなかった（runbook §8.3 の見立てと合う）
- 23:20:29Z に 5 つの `rollout status` がすべて `successfully rolled out`

## 3. 確認（runbook §3.3。23:21Z〜23:24Z）

| # | 確認 | 結果 |
|---|---|---|
| 1〜12 | Server、コンポーネント、Node、etcd、VIP | Server Version v1.32.13。apiserver 3/3（`-2nccn` .112、`-z2pdq` .111、`-hksh7` .113）、controller-manager 2/2（.112 `-9cxxw` リーダー、.113 `-qmv4n`）、scheduler 2/2（.112 `-c5dxt` リーダー、.111 `-wf5xr`）、kube-proxy 8/8、どれも v1.32.13 で restartCount 0。Node は 8 台 Ready、kubelet は v1.31.14 のまま。etcd 3/3 healthy、リーダーは .113 のまま、raft index がそろう。VIP の `/readyz` は `ok`、`/version` は v1.32.13 |
| 13 | CoreDNS | Deployment `coredns` 2/2（chirico `-8jmd5`、duchamp `-v6zg8`）、generation 9 → 10、イメージ `registry.k8s.io/coredns/coredns:v1.11.4`、2 つともログの最初に `CoreDNS-1.11.4`。pablo のホストから kube-dns（10.254.0.10）に `kubernetes.default.svc.cluster.local`（10.254.0.1）、`github.com`（A）、`google.com`（AAAA）が引けた |
| 14 | approver | `kubelet-serving-cert-approver` は `0.12.1` のまま 1/1（`-hls26`、oeilvert、restartCount 0）。`install kubernetes` の出力で `unchanged`、generation 2 |
| 15 | CSR | 無い |
| 16 | storage version | `tools/storage-versions.sh`: `prefixes: 64, keys: 2304, OLD: 0, CRDs with more than one stored version: 0`。書き直しの後（`baseline.md` §4）からの差は、`/registry/events/` が増えた（Event 179。rollout のもの）、ReplicaSet 149 → 150、**APIService 31 → 30（`v1beta3.flowcontrol.apiserver.k8s.io` が消えた。1.32 で提供されなくなった版の Local の APIService）** |
| — | ほかの Pod | ベースラインの Pod のうち、作り直された 17 個（apiserver 3、controller-manager 2、scheduler 2、kube-proxy 8、CoreDNS 2）を除き、名前・UID・restartCount がすべて同じ。Running / Completed 以外の Pod は 0 |
| — | cnidaria | `verify-nodes.sh` は 64 PASS、FAIL 0。cnidaria のログの error 0、`no route` の行数はベースラインと同じ |
| — | MetalLB、Prometheus | gated の v4・v6 は 404（応答あり）、`::131`〜`::134` の 3222 は SSH のバナー。`up == 0` は 0、`apiserver_requested_deprecated_apis` は `metallb.io/v1beta1 addresspools` だけ |
| — | Warning のイベント | 置き換えられた古い apiserver の 3 つ（`-bvcxk`、`-rxv47`、`-v7wdz`）の止まりかけの間の `Readiness probe failed`（500 と `connection refused`）だけ |

## 4. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因 |
|---|---|---|
| — | — | FAIL は無かった（23:00Z〜23:24Z） |

## 5. leader election で再起動した controller（runbook §8.8）

なし（`gated-system/gated` の 2 つ、`longhorn-system` の CSI sidecar 12 個とも restartCount 0 のまま）。

## 6. 次へ進む条件

runbook §3.3 の 1〜16 はすべて合格。control-plane の kubelet（§4）へ進む。

## 7. 手順書との差、気づいたこと

- rc 0 で終わり、runbook §3.2 の流し直しは要らなかった。apiserver の rollout は .112 から始まった
- 1.32 の kube-apiserver で `v1beta3.flowcontrol.apiserver.k8s.io` の APIService が消えた（`storage-versions.sh` の APIService の数が 1 つ減る）。想定どおり
