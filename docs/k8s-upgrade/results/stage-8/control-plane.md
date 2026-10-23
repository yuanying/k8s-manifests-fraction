# control-plane のマニフェストの段 8 の作業記録（`install kubernetes`）

control-plane のマニフェスト（kube-apiserver、kube-controller-manager、kube-scheduler、kube-proxy）を、porkadot 0.37.0 の `install kubernetes --node 192.168.1.111` で v1.36.5 から v1.37.1 に上げ、CoreDNS の Corefile の `cache` に `disable success/denial cluster.local` を足した記録。手順は `../../runbook-stage-8.md`（以下 runbook）の §3 と §4.2。
時刻は UTC。比べる元は `baseline.md`。読み取りの出力はタスクディレクトリの `notes/stage-8/cp/`（rollout の後のクラスタ全体は `cp/after/`、storage version は `sv-after-install/`）。

## 1. 事前の読み取り（2026-10-23 22:19Z）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready、全台 v1.36.5 |
| etcd、VIP | 3/3 healthy、リーダー .113、3 台とも 3.6.15（cluster version・storage 3.6.0）。`/readyz` `ok` |
| Running / Completed 以外の Pod | 0 |
| storage version | `OLD: 0`（`baseline.md` §2 の 20） |
| 監視（runbook §2.3） | 3 つのジョブが動いていて、3 つのログの最後の行が 1 分以内（probe は 22:19:11Z の `ok 120`、etcd は 22:19:34Z） |
| `git status --short assets porkadot.yaml` | 空（前と後とも） |
| 時間帯（runbook §2.11） | 22:19Z。control-plane の unattended-upgrades（21:00〜22:00Z）は終わっている（`baseline.md` §5）。worker の 06:00Z、jumelle の 18:00〜19:30Z の外 |

## 2. 承認

段 8 の開始はユーザーが承認済み（2026-10-23 22:05Z、PR #52 のマージ）。✋ の操作（etcd のバックアップ、`install kubernetes`）は、流す直前に coordinator に知らせた。

## 3. `install kubernetes`（runbook §3.2）

- `porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml`（porkadot 0.37.0、サンドボックスの中）。**22:19:51Z → 22:22:52Z、rc 0（1 回目で通った）**。出力は `notes/stage-8/cp/install-kubernetes.log`
- install.sh の 2 段（runbook §3.2）: CRD と kube-apiserver のものを apply し、`daemonset.apps/kube-apiserver configured` の後に `daemon set "kube-apiserver" successfully rolled out`、続けて全体を apply した。porkadot のログには時刻が無いので、時刻は Pod の起動の時刻から読んだ
  - apiserver の入れ替え: .112（`-n2gr4`、22:20:35Z 起動）→ .113（`-djbxn`、22:21:26Z）→ .111（`-qxb4k`、22:22:18Z）。約 2 分
  - 全体の apply の後: KCM と scheduler の 1 つ目が .113 で 22:22:46〜47Z、kube-proxy が 22:22:48Z〜22:23:24Z に 8 台、KCM と scheduler の 2 つ目が .111 で 22:23:24〜25Z
- 全体の apply の `configured`: `service/porkadot-kubernetes-latest`、`daemonset.apps/kube-apiserver`・`kube-proxy`、`deployment.apps/kube-controller-manager`・`kube-scheduler`、**`configmap/coredns`**、`configmap/kube-proxy`、serviceaccount の 3 つ（KCM、kube-proxy、scheduler）、clusterrolebinding の 4 つ（`porkadot:kube-controller-manager`・`kube-scheduler`・`node-proxier`・`volume-scheduler`）、PDB の 2 つ、`validatingwebhookconfiguration…/metallb-webhook-configuration`。どれも版のラベルが変わるもの（webhook と PDB は前の段から出ているもの。runbook §3.3 の注）。**`deployment.apps/coredns` は `unchanged`、`ipaddresspool.metallb.io/first-pool` は `unchanged`**。cnidaria、approver、MetalLB のほかのものは `unchanged`

## 4. 確認（runbook §3.3。22:23Z〜22:27Z）

```
kubectl --context fraction -n kube-system rollout status daemonset/kube-apiserver        # successfully rolled out
kubectl --context fraction -n kube-system rollout status deployment/kube-controller-manager  # successfully rolled out
kubectl --context fraction -n kube-system rollout status deployment/kube-scheduler        # successfully rolled out
kubectl --context fraction -n kube-system rollout status daemonset/kube-proxy            # successfully rolled out
kubectl --context fraction version                                                        # Server Version: v1.37.1
```

| # | 確認 | 結果 |
|---|---|---|
| 1〜12 | 段 1 の手順書 §3.3 の 1〜12 | 合格。Server v1.37.1、VIP の `/readyz` `ok`・`/version` v1.37.1。apiserver 3/3（`-qxb4k` .111、`-n2gr4` .112、`-djbxn` .113）、KCM 2/2（.113 `-fn94h` リーダー、.111 `-2xdnl`）、scheduler 2/2（.113 `-4g4gg` リーダー、.111 `-9p84r`）、kube-proxy 8/8、どれも `v1.37.1` で restartCount 0。generation は DaemonSet `kube-apiserver` 30 → 31、Deployment `kube-controller-manager` 29 → 30、`kube-scheduler` 28 → 29、DaemonSet `kube-proxy` 26 → 27。Node は 8 台 Ready で kubelet は v1.36.5 のまま。**KCM と scheduler のログの `Failed to watch`・`failed to list` は 4 つとも 0**。`The manifest file is empty, ignoring.` は 4 つとも 1 行（runbook §8.17）。kube-proxy は 8 つとも `Using iptables Proxier` があり、`mode` の warning は無い（`E` は `nodePortAddresses is unset` の 1 行で、前の段から） |
| 13 | CoreDNS | **Pod は作り直されていない**: Deployment `coredns` の generation 13 のまま、2/2、`coredns:v1.14.7`、Pod の名前と UID がベースラインと同じ（`-469lz` duchamp、`-shdgn` chirico）。ConfigMap `coredns` の Corefile は `cache 30 {` `disable success cluster.local` `disable denial cluster.local` `}` になった。**`-shdgn` は 22:23:40Z ごろに `[INFO] Reloading` → 新しい SHA512（`78384ea2…`）の `Running configuration` → `Reloading complete` の直後に `[FATAL] plugin/loop: Loop (10.244.5.210:47808 -> :53) detected for zone "."` で exit 1 し（`lastState.terminated` の `finishedAt` 22:23:40Z、restartCount 4 → 5）、22:23:41Z に新しい Corefile（`78384ea2…`）で起き直して Ready**（runbook §3.3 の 13 の条件のとおり。§8.16。ループの相手は duchamp の `-469lz` の Pod の IP）。`-469lz` は 22:25Z ごろに `Reloading` → `78384ea2…` → `Reloading complete` で、exit せず restartCount 7 のまま。22:27Z の時点で 2 つともログに `FATAL`・`[ERROR]` の後の行は無く、CrashLoopBackOff になっていない。`tools/dns-check.sh` の答えはベースラインと同じ（Service と 2 つの Pod の 3 か所とも、diff 0 行。`cp/after/dns-check.txt`）。**TTL の確かめ**（22:26:42Z。`cp/after/dns-ttl.txt`）: 2 回目の答えの TTL は `kubernetes.default.svc.cluster.local` が 2 つの Pod とも **30**（cache されない。ベースラインは 23 と 13）、`kubernetes.default.svc.fraction.cluster` は 20 と 10（30 秒 cache される。2026-10-23 のユーザー判断のとおり）、`github.com` は 17 と 8（cache される） |
| 14 | approver | `kubelet-serving-cert-approver` が `0.12.1` のまま 1/1。generation は変わらない |
| 15 | CSR | 無い |
| 16 | storage version | 22:24Z（KCM の leader が 22:22:4xZ に決まった後）に流した: `prefixes: 67, keys: 2437, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は 1.37 の 4 行（`clustertrustbundles`・`podcertificaterequests` の `certificates.k8s.io/v1beta1`、`storageversionmigrations` の `storagemigration.k8s.io/v1beta1`、`devicetaintrules` の `resource.k8s.io/v1beta2`）。**`/registry/clustertrustbundles/` が `certificates.k8s.io/v1beta1` の `ok` で 1 キー**。`kubectl get clustertrustbundles` は `kubernetes.io:kube-apiserver-serving:e861f40efa6f73a9415ecb89`（signer `kubernetes.io/kube-apiserver-serving`）の 1 つ。runbook §2.5 の 2 のとおり |
| 17 | ServiceCIDR と IPAddress | `servicecidrs` は `kubernetes`（`10.254.0.0/24,fd20:afc2:7c09::/108`）の 1 つ。Service 77、ClusterIP の数 72、IPAddress 72（ベースラインと同じ）。`ClusterIPNotAllocated` の event は無い |
| 18 | v1 Endpoints の warning | `apiserver_requested_deprecated_apis` は `endpoints`（v1）と `metallb.io/v1beta1 addresspools` で、`removed_release` は空（ベースラインと同じ） |
| 19 | FlowSchema | 11 個、generation もベースラインと同じ |
| 20 | MetalLB | `ipaddresspool.metallb.io/first-pool unchanged`。`addresses` は `192.168.1.101/32`、`192.168.1.190-192.168.1.254`、`2405:6580:6740:ac01:ace::/96`（`baseline.md` §2 の 31 と同じ） |

ほかに読んだもの:

- **Pod の再起動**: ベースラインの `pods.tsv` と 22:26Z の `cp/after/pods.tsv` を比べ、`install kubernetes` で作り直された 15 個（apiserver 3、KCM 2、scheduler 2、kube-proxy 8。新しい UID で restartCount 0）のほかに変わったのは、**CoreDNS の `-shdgn` の restartCount 4 → 5（上の 13）だけ**。Running / Completed 以外の Pod は 0
- etcd: 3/3 healthy、3 台とも 3.6.15、リーダーは .113 のまま、raft term 23125、raft index 1404905546 でそろう。DB 55 MB（in use 16 → 22 MB）
- leader election を使う controller（`gated-system/gated`、Longhorn の CSI sidecar）の restartCount はベースラインと同じ
- MetalLB: 告知ノードはベースラインと同じ（VIP と gated-v6 は pablo で、apiserver の入れ替えの後の 22:20:19Z・22:22:36Z に `serviceAnnounced` を出し直した）。gated の v4 と v6 は 404、`::131`〜`::134` は SSH のバナー
- cnidaria のログの error / `no route` の数は 8 台ともベースラインと同じ
- warning のイベント: 置き換えられた古い apiserver 3 つの `Readiness probe failed … connection refused`（止まりかけ）と、`-shdgn` の起き直しの間の `Readiness probe failed`（8181）。どれも 1 回ずつ
- KCM（`-fn94h`）の 22:23:21Z の `daemon_controller` / `replica_set` の `read version … is not as new as written version` が数行（KCM の rollout の終わり。段 7 と同じ形）。.111 の新しい apiserver の起動の直後（22:22:23Z）の `error resolving kube-system/metrics-server: service "metrics-server" not found` 3 行と `Unhandled Error` 1 行（段 7 と同じ）。.113 の apiserver の `Failed to encode watch event … http2: stream closed` 1 行（22:23:21Z。KCM の入れ替えの間の watch の切断）
- **1.37 の apiserver は、grpc の `operation was canceled`（runbook §8.19）を出していない**: 22:26Z に 3 つとも直近 10 分で 0 行（起動から 4〜6 分。1.36 の apiserver はベースラインで 10 分に 35〜40 行）。`W` の行は起動のときの `Skipping API … because it has no resources` などだけ
- 1.37 の apiserver・KCM・scheduler のログの `E` の行は、上に書いたもののほかに無い

## 5. 監視の FAIL と、その原因

| 時刻 | VIP / LB / etcd の health | 原因 |
|---|---|---|
| 22:21:45Z | VIP 1 回 | apiserver の入れ替え（.113 の apiserver が 22:21:24Z に作り直された直後。段 7 と同じ形） |

etcd の health の unhealthy は 0（.111 と .112 の両方。`install kubernetes` の直後も 3 台とも healthy）。LB の FAIL は 0。

## 6. 2 つ目のバックアップ（runbook §4.2 の 1）

| 項目 | 値 |
|---|---|
| コマンド | `porkadot etcd backup --config ./porkadot.yaml`（porkadot 0.37.0、etcdctl 3.6.15。サンドボックスの中で 22:27:19Z〜22:27:23Z、rc 0、6 つとも `successful`） |
| 中身 | 1.37 の control-plane、Corefile の新しい `cache`、ClusterTrustBundle 1 つ、etcd 3.6（kubelet はまだ 1.36）。runbook §7.4 の restore で、段の前（`baseline.md` §7）の代わりに使える |
| ファイル | `etcd-2026-10-23T22:27:19+00:00.db`、モード 0600、55,107,616 バイト |
| sha256 | `34674bc8310100d9d7371e85c6842232185ba9379dcc76f0d591fcb2b7fa7104` |
| 置き場所 | 段 8 の worktree の `./backup/`（git には入れていない）。worktree を片付ける前に、coordinator がメインの checkout の `backup/` へ移す |

## 7. 手順書との差、気づいたこと

- CoreDNS の `loop` による 1 回の exit は、runbook §3.3 の 13・§8.16 に書いたとおりに起きた（dev の段 8 の reload では起きず、restore の後の reload で起きたもの）。1 つ目の Pod の reload で、上流の 10.254.0.10 を通ってもう 1 つの Pod に HINFO が届き、それがまた自分に返ってきた形と見ている
- runbook §8.19 の grpc の `operation was canceled` は、1.37 の apiserver では（起動から数分の間）出ていない。§6 で読み直す
