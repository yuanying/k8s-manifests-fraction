# 段 4 の `install kubernetes` の作業記録

control-plane のマニフェスト（kube-apiserver、kube-controller-manager、kube-scheduler、kube-proxy、CoreDNS）を、porkadot 0.33.0 の `install kubernetes --node 192.168.1.111` で v1.33.13（CoreDNS v1.12.4）に上げた記録。手順は `../../runbook-stage-4.md`（以下 runbook）の §3。
時刻は UTC。前の記録は `baseline.md`（ベースライン、etcd のバックアップ、storage version の確認）。読み取りの出力はタスクディレクトリの `notes/stage-4/cp/`。

## 1. 事前の確認（runbook §3.1。2026-10-20 02:01Z）

| 項目 | 結果 |
|---|---|
| 段 4 の開始の承認 | 2026-10-20 にユーザーが承認済み（PR #35 をマージ） |
| ベースライン、バックアップ、監視 | `baseline.md` §2・§3。監視は 01:57Z から動いている（FAIL 0） |
| storage version | `OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` は空（`baseline.md` §2 の 20） |
| Node、etcd、VIP | 8 台 Ready、etcd 3/3 healthy（リーダー .113）、VIP の `/readyz` は `ok` |
| checkout | 段 4 の worktree（PR #35 をマージした master の `e3ad437` から）。`git status --short assets porkadot.yaml` は空 |
| SSH | 01:57Z に 8 台ともサンドボックスの中で通った（`baseline.md` §1） |
| DaemonSet `kube-apiserver` の generation | 26 |

## 2. `install kubernetes`（runbook §3.2）

- 1 回目: 02:02:18Z〜02:02:37Z、**rc 1**。サンドボックスの中で流した。最後の 2 つの apply（MetalLB の `l2advertisements/system` と `validatingwebhookconfigurations/metallb-webhook-configuration`）が `dial tcp 127.0.0.1:6443: connect: connection refused` で失敗した（runbook §8.3 の形。dev の段 3 と同じ 2 つ）。それより前のものは apply されていた（`configured`: kube-apiserver・kube-proxy の DaemonSet、kube-controller-manager・kube-scheduler・coredns の Deployment、kube-controller-manager・kube-scheduler の PDB、kube-proxy の ConfigMap、3 つの ServiceAccount、`porkadot:*` の ClusterRoleBinding 4 つ、Service `porkadot-kubernetes-latest`。ほかは `unchanged`）
- rollout の順（Pod の作成の時刻）: controller-manager・scheduler の 1 つ目、CoreDNS の 2 つ、kube-proxy の .111 が 02:02:36Z〜37Z、**apiserver は .111（02:03:15Z）→ .112（02:04:07Z）→ .113（02:04:58Z）**、kube-proxy は 8 台を 02:02:37Z〜02:03:40Z に 1 台ずつ
- **apiserver の rollout が .111 から始まったので、runbook §8.3 のとおり .111 の上の `kubectl apply` の接続先が消えた**（段 3 の本番と 0.33 の rc の dev は .112 から始まって rc 0、0.32 の rc の dev は .111 から始まって rc 1。runbook §8.3 の見立てと合う）
- 02:05:19Z に 5 つの `rollout status` がすべて `successfully rolled out`。kube-apiserver の generation は 26 → 27
- ✋ 流し直し: 02:05:35Z〜02:06:02Z、**rc 0**。`configured` は kube-controller-manager・kube-scheduler の PDB、DaemonSet `kube-apiserver`、`metallb-webhook-configuration` の 4 つ（どれも毎回 `configured` になるもの）、ほか 60 個は `unchanged`。**DaemonSet `kube-apiserver` の generation は 27 のままで、2 回目の rollout は起きなかった**（observedGeneration 27、updated 3、ready 3）

## 3. 確認（runbook §3.3。02:06Z〜02:09Z）

| # | 確認 | 結果 |
|---|---|---|
| 1〜12 | Server、コンポーネント、Node、etcd、VIP | Server Version v1.33.13。apiserver 3/3（`-6kv5q` .111、`-mjvwf` .112、`-g9jhl` .113）、controller-manager 2/2（.111 `-9wqgd`、.113 `-fw4lb` リーダー）、scheduler 2/2（.113 `-l2qfv`、.112 `-8kt9t` リーダー）、kube-proxy 8/8、どれも v1.33.13 で restartCount 0。Node は 8 台 Ready、kubelet は v1.32.13 のまま。etcd 3/3 healthy、リーダーは .113 のまま、raft term 23118、raft index がそろう。VIP の `/readyz` は `ok`、`/version` は v1.33.13。DaemonSet `kube-apiserver` の generation 26 → 27、kube-proxy 22 → 23、Deployment の kube-controller-manager 25 → 26、kube-scheduler 24 → 25 |
| 13 | CoreDNS | Deployment `coredns` 2/2（chirico `-bt9pk`、duchamp `-fj8j8`）、generation 10 → 11、イメージ `registry.k8s.io/coredns/coredns:v1.12.4`。2 つのログは `maxprocs`・`.:53`・`plugin/reload` の設定の SHA512 の行の後に `CoreDNS-1.12.4`、`linux/amd64, go1.25.0, f323295` で、ほかの行（エラー）は無い。名前の答えは下の表 |
| 14 | approver | `kubelet-serving-cert-approver` は `0.12.1` のまま 1/1（`-hls26`、oeilvert、restartCount 0）。generation 2 のまま。apply の出力で `unchanged` |
| 15 | CSR | 無い |
| 16 | storage version | `tools/storage-versions.sh`: `prefixes: 66, keys: 2468, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は 2 行（`/registry/ipaddresses/`、`/registry/servicecidrs/` が `networking.k8s.io/v1beta1`、`ResourceEncodingOverrides 1.33`）。`summary.tsv` に IPAddress 74 と ServiceCIDR 1 が `networking.k8s.io/v1beta1` の `ok` で出る。ベースラインから増えた prefix はこの 2 つと `/registry/events/`（Event 267。rollout のもの）だけ。数が変わったもの: ClusterRole と ClusterRoleBinding が 117 → 119（1.33 の apiserver の bootstrap の `system:controller:selinux-warning-controller`、`system:controller:service-cidrs-controller`）、ServiceAccount 118 → 119（`kube-system/service-cidrs-controller`）、ReplicaSet 150 → 151（新しい ReplicaSet 3 つ、消えた古いもの 2 つ） |
| 17 | ServiceCIDR と IPAddress | `servicecidrs` は `kubernetes` が 1 つで、CIDRS は `10.254.0.0/24,fd20:afc2:7c09::/108`。IPAddress は 74（ClusterIP の数と同じ。Service は 79 個、ClusterIP を持つもの 71 個、dual-stack 3 個）。`ClusterIPNotAllocated` の Warning の event は 71 件で、どれも 02:03:24Z〜02:03:25Z（1.33 の apiserver の .111 が起きた直後）の 1 回ずつ。02:09Z までに新しいものは出ていない |
| 18 | v1 Endpoints の warning | `apiserver_requested_deprecated_apis` に `resource="endpoints",version="v1"` が 3 台の apiserver（.111、.112、.113）とも出た（runbook §8.15 のとおり。合格基準にしない）。ほかは `metallb.io/v1beta1 addresspools`（.111）だけで、`removed_release` が 1.33 以前のものは無い |
| — | ほかの Pod | ベースラインの 148 個のうち、作り直された 17 個（apiserver 3、controller-manager 2、scheduler 2、kube-proxy 8、CoreDNS 2）を除き、名前・UID・restartCount がすべて同じ。Running / Completed 以外の Pod は 0 |
| — | cnidaria | `verify-nodes.sh` は 64 PASS、FAIL 0。cnidaria のログの error と `no route` の行数はベースラインと同じ |
| — | MetalLB、Prometheus | gated の v4・v6 は 404（応答あり）、`::131`〜`::134` の 3222 は SSH のバナー。告知ノードは変わらない（pablo が 02:05:19Z に VIP をもう一度 `serviceAnnounced`）。`up == 0` は 0 |
| — | leader election を使う controller | `gated-system/gated` の 2 つ、CSI sidecar 12 個とも restartCount 0 のまま |

CoreDNS の名前の答え（§3.3 の 13。作業端末から 10.254.0.10 へ。02:06:59Z）:

| 問い合わせ | v1.11.4（`baseline.md`） | v1.12.4 |
|---|---|---|
| `kubernetes.default.svc.cluster.local`、`kubernetes.default.svc.fraction.cluster` | `10.254.0.1` | 同じ |
| `www.google.com` A | 外のアドレス | 同じ |
| PTR `10.254.0.1`、`fd20:afc2:7c09::521` | `kubernetes.default.svc.cluster.local.`、`h2.fs.svc.cluster.local.` | 同じ |
| PTR の kube-dns の Endpoint の Pod の IP | NXDOMAIN | **`10-244-5-129.kube-dns.kube-system.svc.cluster.local.`、`10-244-8-16.kube-dns.kube-system.svc.cluster.local.`**（新しい CoreDNS の Pod。同じ Pod を Endpoint に持つ `kube-system/kube-prometheus-coredns` の名前も返る） |
| PTR の `fs/h2` の Endpoint の Pod の IP | NXDOMAIN | **`10-244-8-246.h2.fs.svc.cluster.local.`、`fde7-4ad6-425d-3--4b1f.h2.fs.svc.cluster.local.`**（v6 は `h2-sshd.fs` の名前も返る） |

hostname の無い Endpoint の Pod の IP の逆引きが直った（coredns#6898 の回帰が v1.12.4 で直っている。dev の記録と同じ）。1 つの Pod を複数の Service が Endpoint に持つときは、Service ごとの名前が返る。

## 4. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因 |
|---|---|---|
| — | — | FAIL は無かった（01:57Z〜02:09Z。apiserver の rollout の間も） |

## 5. leader election で再起動した controller（runbook §8.8）

なし（`gated-system/gated` の 2 つ、`longhorn-system` の CSI sidecar 12 個とも restartCount 0 のまま）。controller-manager と scheduler は作り直され、リーダーは controller-manager が .113 の `-fw4lb`、scheduler が .112 の `-8kt9t` になった。

## 6. 次へ進む条件

runbook §3.3 の 1〜18 はすべて合格（18 は記録だけ）。control-plane の kubelet（§4）へ進む。

## 7. 手順書との差、気づいたこと

- 1 回目は rc 1（runbook §8.3）。runbook §3.2 のとおり rollout の完了を待って流し直し、rc 0 で 2 回目の rollout は無かった
- 段 3 の本番には無かった Warning のイベント（apiserver の rollout が .111 から始まったためと見ている）。どれも 1 回きりで続かず、Pod の再起動も監視の FAIL も無い:
  - 02:02:37Z: 新しい controller-manager（`-9wqgd`、.111）の `FailedMount`（`failed to sync secret cache: timed out waiting for the condition`）1 回。Pod の作成の直後で、.111 の apiserver の入れ替えの前（原因は確かめていない）。Pod は Running、restartCount 0
  - 02:03:36Z〜37Z: endpoints controller の `FailedToUpdateEndpoint` 14 件（`minecraft*`、`monitoring`、`longhorn-system`、`metallb-system` の Endpoints）、EndpointSlice の controller の `FailedToUpdateEndpointSlices` 1 件（`kube-system/kube-prometheus-kube-proxy`）、DaemonSet の controller の kube-proxy の `FailedCreate`（9 回）。どれも `dial tcp 10.254.0.1:443: connect: connection refused`。controller-manager が Service `kubernetes` 経由で、止まりかけた古い apiserver（.112 の `-2nccn`。02:04:07Z に入れ替わる前で、02:04:01Z まで `connection refused` の probe の失敗を出していた）に当たったものと見ている（段 2 の手順書 §8.7 と同じ形。確かめていない）。kube-proxy は 02:03:37Z〜40Z に作られ、Endpoints はその後に更新されている
  - 置き換えられた古い apiserver の 3 つの止まりかけの間の `Readiness probe failed`（500 と `connection refused`）。段 3 と同じ
- CoreDNS のログの `CoreDNS-1.12.4` は、最初の行ではなく `maxprocs`・`.:53`・設定の SHA512 の行の後に出る（v1.11.4 と同じ並び）
