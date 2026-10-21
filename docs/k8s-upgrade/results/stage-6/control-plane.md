# control-plane のマニフェストの段 6 の作業記録（`install kubernetes`）

kube-apiserver・kube-controller-manager・kube-scheduler・kube-proxy を v1.34.12 から v1.35.9 に、CoreDNS を v1.12.4 から v1.13.2 に、porkadot 0.35.0 の `install kubernetes --node 192.168.1.111` で上げた記録。続けて取った 2 つ目の etcd のバックアップ（runbook §4.2）もここに書く。手順は `../../runbook-stage-6.md`（以下 runbook）。
時刻は UTC。ベースラインは `baseline.md`。読み取りの出力はタスクディレクトリの `notes/stage-6/cp/`（`install kubernetes` の出力）、`notes/stage-6/cp-done/`（直後の読み取り）、`notes/stage-6/sv-after-install/`（storage version）、`notes/stage-6/pre-cp/`（2 つ目のバックアップの直後の etcd）。

## 1. 事前の読み取り（2026-10-21 06:48Z）

runbook §3.1 の項目:

| 項目 | 結果 |
|---|---|
| ベースライン、段の前のバックアップ、cgroup の確認 | `baseline.md` のとおり済み。8 台とも `cgroup2fs` |
| 監視（runbook §2.3） | VIP と LB は 06:39:40Z から、etcd の health（.111 と .112 から 2 秒ごと）は 06:48:09Z から動いている。どちらも FAIL 0 |
| storage version | `OLD: 0`（`baseline.md` §2 の 20） |
| Node、etcd、VIP | 8 台 Ready、全台 v1.34.12。etcd 3/3 healthy。VIP の `/readyz` は `ok` |
| Running / Completed 以外の Pod | 0 個 |
| checkout | worktree（`stage-6-k8s-1-35`、base は PR #46 をマージした master の `6272eb3`。足したのは記録だけ）。`git status --short assets porkadot.yaml` は前も後も空 |
| porkadot、SSH | `git -C $P describe --tags` は `v0.35.0`。8 台とも SSH が通る（`baseline.md` §1） |
| unattended-upgrades の時間帯 | 次の実行は CP が 10-21 21:18Z から、worker が 10-22 06:01Z から（`baseline.md` §5）。重ならない |

## 2. etcd のリーダー

`install kubernetes` では etcd に触らない（リーダーは .112 のまま）。

## 3. `install kubernetes`（runbook §3.2）

- 開始 06:48:33Z、終わり 06:51:38Z、**rc 0（1 回目で通った）**。サンドボックスの中で流した。出力はタスクディレクトリの `notes/stage-6/cp/install-kubernetes.log`
- 1 段目: CRD を apply し（`condition met`）、`service/porkadot-kubernetes-latest configured`、`daemonset.apps/kube-apiserver configured`。続けて `daemon set "kube-apiserver" successfully rolled out`（ログに時刻は無い。Pod の Ready から 06:51:22Z ごろ）
- apiserver の入れ替え（Pod の作成と Ready）: .113 `-rbbgw` 06:49:18Z → 06:49:39Z、.112 `-82plt` 06:50:09Z → 06:50:30Z、.111 `-wdw65` 06:51:02Z → 06:51:22Z。1 台約 50 秒、3 台で約 2 分 10 秒（段 5 と同じ）
- 2 段目（全体の apply）: `configured` は `serviceaccount/kube-controller-manager`・`kube-proxy`・`kube-scheduler`、`clusterrolebinding…/porkadot:kube-controller-manager`・`porkadot:kube-scheduler`・`porkadot:node-proxier`・`porkadot:volume-scheduler`、`configmap/kube-proxy`、**`deployment.apps/coredns`**、`deployment.apps/kube-controller-manager`・`kube-scheduler`、`poddisruptionbudget.policy/kube-controller-manager`・`kube-scheduler`、`daemonset.apps/kube-apiserver`・`kube-proxy`、`validatingwebhookconfiguration…/metallb-webhook-configuration`。CoreDNS のほかは段 5 と同じ並び（版のラベルか、前から `configured` に出る PDB と MetalLB の webhook）。approver・cnidaria・MetalLB の Deployment と DaemonSet、`configmap/coredns` は `unchanged`
- KCM・scheduler・CoreDNS の新しい Pod は 06:51:29Z（.113 の KCM、.112 の scheduler、chirico と duchamp の CoreDNS）と 06:52:11Z〜06:52:14Z（.112 の KCM、.113 の scheduler）に作られ、06:52:37Z にすべて Ready。CoreDNS の 2 つは 06:51:34Z に Ready。kube-proxy は 06:51:30Z〜06:52:17Z に 8 台を入れ替えた
- 06:52:38Z に 5 つの `rollout status` がすべて `successfully rolled out`。`kubectl --context fraction version` の Server Version は v1.35.9

## 4. 確認（runbook §3.3。06:52Z〜06:55Z）

| # | 確認 | 結果 |
|---|---|---|
| 1〜12 | 段 1 の手順書 §3.3 の 1〜12 | Server v1.35.9。DaemonSet `kube-apiserver` は generation 28 → 29、`kube-proxy` 24 → 25、Deployment `kube-controller-manager` 27 → 28、`kube-scheduler` 26 → 27、どれも v1.35.9。Node は 8 台 Ready で kubelet は v1.34.12 のまま。etcd は 3/3 healthy、3.6.15 のまま、リーダーは .112 のまま。VIP の `/readyz` は `ok`、`/version` は v1.35.9。Running / Completed 以外の Pod は 0。controller-manager は .113（`-qjt9d`、リーダー）と .112（`-bvqcn`）、scheduler は .112（`-zkslm`、リーダー）と .113（`-wb6t5`）。**4 つの Pod のログに `Failed to watch`・`failed to list` は 0 行、`E` で始まる行も 0 行** |
| 13 | CoreDNS | **v1.13.2 に rollout した**。generation 11 → 12、2/2（`coredns-7dfdc87799-stznf` chirico 10.244.8.65、`-tbgq5` duchamp 10.244.5.197）、イメージ `registry.k8s.io/coredns/coredns:v1.13.2`。2 つのログに `CoreDNS-1.13.2`、`linux/amd64, go1.25.5, 0233f3e`（どちらも amd64 の worker）。`[ERROR]`・`[WARNING]`・`loop` は無い。古い v1.12.4 の Pod は消えた。**`tools/dns-check.sh` の答えは `baseline.md` §2 の 23 と同じ**（Service と 2 つの Pod の 3 か所とも。違うのは kube-dns の Endpoint の Pod の IP が新しい Pod のものに替わったことだけ）。出力は `notes/stage-6/cp-done/dns-check.txt` |
| 14 | approver | `kubelet-serving-cert-approver-7d5f768656-hls26` が 1/1 のまま、generation も変わらない |
| 15 | CSR | 無い |
| 16 | storage version | `prefixes: 65, keys: 2525, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は空のまま。`/registry/ipaddresses/` 74 と `/registry/servicecidrs/` 1 が `networking.k8s.io/v1` の `ok` |
| 17 | ServiceCIDR と IPAddress | `servicecidrs` は `kubernetes` の 1 つ、CIDRS は `10.254.0.0/24,fd20:afc2:7c09::/108`。IPAddress は 74（ClusterIP の数と同じ）。`ClusterIPNotAllocated` の event は無い |
| 18 | v1 Endpoints の warning | `apiserver_requested_deprecated_apis` は `endpoints`（v1）と `metallb.io/v1beta1 addresspools` で、`removed_release` は空。1.35 以前に消える API は出ていない |
| 19 | FlowSchema | 11 個のまま、generation も変わらない（`system-leader-election` 8、ほかは 1） |

- `/registry/` のキーは 2362 → 2525 で、増えたのはおもに events（apiserver の入れ替えの Readiness probe の失敗など）と controllerrevisions
- Warning のイベント: 3 台の旧い kube-apiserver の Pod（`-5sgvj`、`-srsxs`、`-56jg7`）の `Readiness probe failed … connection refused`（止まるときのもの。想定内）と、ベースラインからの `movies` の probe の失敗
- 全 Pod の UID・restartCount（`baseline/pods.tsv` と比べた）: 変わったのは、`install kubernetes` で作り直された apiserver 3・KCM 2・scheduler 2・kube-proxy 8・CoreDNS 2 だけ（新しい名前・UID で restartCount 0）
- MetalLB は apiserver の入れ替えの後に、同じノードで `serviceAnnounced` を出し直した（VIP pablo 06:51:22Z、gated-v4 chirico 06:51:03Z、gated-v6 oeilvert 06:50:10Z）。告知ノードは変わらない
- `install kubernetes` の直後（全体の apply の後の 1 分ほど）も、etcd の health は 3 台とも healthy のまま（runbook §8.13 の dev の詰まりは本番では起きなかった）

## 5. 2 つ目の etcd のバックアップ（runbook §4.2）

| 項目 | 値 |
|---|---|
| コマンド | `porkadot etcd backup --config ./porkadot.yaml`（porkadot 0.35.0、etcdctl 3.6.15。サンドボックスの中で 06:56:16Z〜06:56:19Z、rc 0、6 つとも `successful`） |
| 取ったメンバー | 192.168.1.111 |
| ファイル | `etcd-2026-10-21T06:56:16+00:00.db`、モード 0600、55,107,616 バイト（段の前のものと同じサイズ） |
| sha256 | `9a799412c697fd6f11a220b3c2b5c927f16c6833c6d4c7021684982874f20681` |
| 置き場所 | 段 6 の worktree の `./backup/`（git には入れていない）。片付けの前に coordinator がメインの checkout の `backup/` へ移す |
| 中身 | 1.35 の control-plane、CoreDNS v1.13.2、kubelet は 1.34。runbook §7.4 の restore で、段の前のもの（`etcd-2026-10-21T06:46:11+00:00.db`）の代わりに使える |

直後の etcd（06:56Z。`notes/stage-6/pre-cp/`）: 3/3 が 3.6.15（cluster version・storage とも 3.6.0）、raft term 23122・index 1403511629〜632 でそろう、`header.revision` 1,238,134,557。

## 6. 監視の FAIL と、その原因

| 時刻 | VIP / LB / etcd の health | 原因 |
|---|---|---|
| 06:49:39Z | VIP | .113 の kube-apiserver の入れ替え（新しい Pod の Ready と同じ秒。古い Pod の停止から新しい Pod の Ready まで） |

LB（`192.168.1.200`）の FAIL は 0、etcd の health の unhealthy も 0。段 5 の本番（VIP の FAIL 2 回）より少ない。

## 7. 手順書との差、気づいたこと

- なし。`install kubernetes` は 1 回目で rc 0、CoreDNS の rollout も runbook §3.3 の 13 のとおり
- CoreDNS の 2 つの Pod は amd64 の worker（chirico、duchamp）に置かれたので、arm64 の CoreDNS v1.13.2 は本番では動いていない（runbook の「dev で確かめていないもの」の 1 つ目のうち CoreDNS の部分）。arm64 のイメージがあることは runbook §1.7 で確かめてある
