# control-plane のマニフェストの段 7 の作業記録（`install kubernetes`）

kube-apiserver・kube-controller-manager・kube-scheduler・kube-proxy を v1.35.9 から v1.36.5 に、CoreDNS を v1.13.2 から v1.14.7 に、porkadot 0.36.0 の `install kubernetes --node 192.168.1.111` で上げた記録。続けて取った 2 つ目の etcd のバックアップ（runbook §4.2）もここに書く。手順は `../../runbook-stage-7.md`（以下 runbook）。
時刻は UTC。ベースラインは `baseline.md`。読み取りの出力はタスクディレクトリの `notes/stage-7/cp/`（`install kubernetes` の出力）、`notes/stage-7/cp-done/`（直後の読み取り）、`notes/stage-7/sv-after-install/`（storage version）。

## 1. 事前の読み取り（2026-10-21 13:01Z）

runbook §3.1 の項目:

| 項目 | 結果 |
|---|---|
| ベースライン、段の前のバックアップ、cgroup、`ipcidr-scan.py` | `baseline.md` のとおり済み。8 台とも `cgroup2fs`、`# findings: 0` |
| 監視（runbook §2.3） | 3 つのジョブ（bg1〜bg3）が `bg_list` に居る。13:01:31Z に読んだ 3 つのログの最後の行は 13:01:15Z（VIP と LB の `ok 300`）、13:01:30Z、13:01:30Z で、1 分以内。どれも FAIL・unhealthy 0 |
| storage version | `OLD: 0`（`baseline.md` §2 の 20） |
| Node、etcd、VIP | 8 台 Ready、全台 v1.35.9。etcd 3/3 healthy。VIP の `/readyz` は `ok` |
| Running / Completed 以外の Pod | 0 個 |
| checkout | worktree（`stage-7-k8s-1-36`、base は PR #48 をマージした master の `cd568cc`。足したのは記録だけ）。`git status --short assets porkadot.yaml` は前も後も空 |
| porkadot、SSH | `git -C $P describe --tags` は `v0.36.0`。8 台とも SSH が通る（`baseline.md` §1） |
| unattended-upgrades の時間帯 | 次の実行は CP が 10-21 21:10Z から、worker が 10-22 06:13Z から（`baseline.md` §5）。重ならない |

## 2. etcd のリーダー

`install kubernetes` では etcd に触らない（リーダーは .113 のまま）。

## 3. `install kubernetes`（runbook §3.2）

- 開始 13:01:39Z、終わり 13:04:41Z（約 3 分）、**rc 0（1 回目で通った）**。サンドボックスの中で流した。出力はタスクディレクトリの `notes/stage-7/cp/install-kubernetes.log`
- 1 段目: CRD を apply し（53 個とも `condition met`）、`service/porkadot-kubernetes-latest configured`、`daemonset.apps/kube-apiserver configured`。続けて `daemon set "kube-apiserver" successfully rolled out`（ログに時刻は無い。最後の Pod の Ready から 13:04:24Z ごろ）
- apiserver の入れ替え（Pod の作成と Ready）: **.112 `-vtv8d` 13:02:21Z → 13:02:42Z**、.111 `-pvvmc` 13:03:12Z → 13:03:33Z、.113 `-dnkpz` 13:04:04Z → 13:04:24Z。1 台約 50 秒、3 台で約 2 分（段 6 と同じ。入れ替えの順は段 6 の .113 → .112 → .111 と違い、DaemonSet の controller が選んだもの）
- 2 段目（全体の apply）: `configured` は `serviceaccount/kube-controller-manager`・`kube-proxy`・`kube-scheduler`、`clusterrolebinding…/porkadot:kube-controller-manager`・`porkadot:kube-scheduler`・`porkadot:node-proxier`・`porkadot:volume-scheduler`、`configmap/kube-proxy`、**`deployment.apps/coredns`**、`deployment.apps/kube-controller-manager`・`kube-scheduler`、`poddisruptionbudget.policy/kube-controller-manager`・`kube-scheduler`、`daemonset.apps/kube-apiserver`・`kube-proxy`、`validatingwebhookconfiguration…/metallb-webhook-configuration`。段 6 と同じ並び。approver・cnidaria・MetalLB の Deployment と DaemonSet、MetalLB の `ipaddresspool`・`l2advertisement`、`configmap/coredns` は `unchanged`
- KCM・scheduler・CoreDNS の新しい Pod は 13:04:32Z（.111 の KCM と scheduler、chirico と duchamp の CoreDNS）と 13:04:52Z〜13:04:53Z（.112 の KCM と scheduler）に作られ、13:05:14Z にすべて Ready。CoreDNS の 2 つは 13:04:37Z〜13:04:38Z に Ready。kube-proxy は 13:04:33Z〜13:05:05Z に 8 台を入れ替えた
- 5 つの `rollout status` がすべて `successfully rolled out`。`kubectl --context fraction version` の Server Version は v1.36.5

## 4. 確認（runbook §3.3。13:05Z〜13:08Z）

| # | 確認 | 結果 |
|---|---|---|
| 1〜12 | 段 1 の手順書 §3.3 の 1〜12 | Server v1.36.5。DaemonSet `kube-apiserver` は generation 29 → 30、`kube-proxy` 25 → 26、Deployment `kube-controller-manager` 28 → 29、`kube-scheduler` 27 → 28、どれも v1.36.5。Node は 8 台 Ready で kubelet は v1.35.9 のまま。etcd は 3/3 healthy、3.6.15 のまま、リーダーは .113 のまま。VIP の `/readyz` は `ok`、`/version` は v1.36.5。Running / Completed 以外の Pod は 0。controller-manager は .111（`-h9fg6`、リーダー）と .112（`-nlvtq`）、scheduler は .111（`-5vqks`、リーダー）と .112（`-ntsf7`）。**KCM と scheduler の 4 つの Pod のログに `Failed to watch`・`failed to list` は 0 行**。`E` の行は 7 つの Pod とも `The manifest file is empty, ignoring.` の 1 行（runbook §8.17）があり、ほかは下の注 |
| 13 | CoreDNS | **v1.14.7 に rollout した**。generation 12 → 13、2/2（`coredns-76d7d8dc86-shdgn` chirico 10.244.8.74、`-469lz` duchamp 10.244.5.210）、イメージ `registry.k8s.io/coredns/coredns:v1.14.7`。2 つのログに `CoreDNS-1.14.7`、`linux/amd64, go1.26.6, 427fc80`（どちらも amd64 の worker。runbook §2.13）。`[ERROR]`・`[WARNING]`・`loop` は無い。古い v1.13.2 の Pod は消えた。**`tools/dns-check.sh` の答えは `baseline.md` §2 の 23 と同じ**（Service と 2 つの Pod の 3 か所とも。Pod の IP を伏せて diff して差は 0。違うのは kube-dns の Endpoint の Pod の IP が新しい Pod のものに替わったことだけ）。出力は `notes/stage-7/cp-done/dns-check.txt` |
| 14 | approver | `kubelet-serving-cert-approver-7d5f768656-hls26` が 1/1 のまま（restartCount 0）、generation 2 のまま |
| 15 | CSR | 無い |
| 16 | storage version | `prefixes: 66, keys: 2464, OLD: 0, CRDs with more than one stored version: 0`。**`overrides.tsv` は 1.36 の 2 行**（`/registry/mutatingadmissionpolicies/`・`/registry/mutatingadmissionpolicybindings/` の `admissionregistration.k8s.io/v1beta1`）。増えた prefix は **`/registry/peerserverleases/`**（core の `v1` の `Endpoints`、3 キー、`ok`。runbook §8.18）。出力は `notes/stage-7/sv-after-install/` |
| 17 | ServiceCIDR と IPAddress | `servicecidrs` は `kubernetes` の 1 つ、CIDRS は `10.254.0.0/24,fd20:afc2:7c09::/108`。IPAddress は 74（ClusterIP の数と同じ）。`ClusterIPNotAllocated` の event は無い |
| 18 | v1 Endpoints の warning | `apiserver_requested_deprecated_apis` は `endpoints`（v1）と `metallb.io/v1beta1 addresspools` で、`removed_release` は空。1.36 以前に消える API は出ていない |
| 19 | FlowSchema | 11 個のまま、generation も変わらない（`system-leader-election` 8、ほかは 1） |
| 20 | CoreDNS のプロセス | 2 つとも `/proc/<PID>/status` が `Uid: 65532 65532 65532 65532`、`CapEff: 0000000000000400`（`NET_BIND_SERVICE`）。dev の記録と同じ（`notes/stage-7/cp-done/coredns-proc.txt`） |

- 全 Pod の UID・restartCount（`baseline/pods.tsv` と比べた）: 変わったのは、`install kubernetes` で作り直された apiserver 3・KCM 2・scheduler 2・kube-proxy 8・CoreDNS 2 の 17 個だけ（新しい名前・UID で restartCount 0）。名前が同じまま残った Pod の UID と restartCount はすべて同じ
- `E` の行の注（どれも入れ替わりの直後だけで、続かない）:
  - .111 の新しい apiserver（`-pvvmc`）の起動の直後（13:03:20Z）に `handler_proxy.go:144] error resolving kube-system/metrics-server: service "metrics-server" not found` が 4 行と `"Unhandled Error"` が 1 行。Service はあり（6d4h）、APIService `v1beta1.metrics.k8s.io` は `True`、`kubectl top nodes` も応答する。起動の直後に Service の informer がそろう前の 1 秒ほどのものと見ている
  - KCM の `-h9fg6` に 13:05:32Z の `replica_set.go] "Unhandled Error" err="sync … read version: … is not as new as written version …"` 1 行と、`disruption.go] "Error syncing PodDisruptionBudget, requeuing" … the object has been modified` 1 行（scheduler の ReplicaSet と PDB。rollout の終わりの競合）
- Prometheus の `up == 0` は 13:05Z の読み取りで 1 つあったが、13:06Z に読み直すと 0。`count by (job) (up)` の数はベースラインと同じ（`apiserver` 3、`kube-etcd` 3 など）。入れ替えの間の古いターゲットと見ている
- Warning のイベント: 3 台の旧い kube-apiserver の Pod（`-82plt`、`-wdw65`、`-rbbgw`）の `Readiness probe failed … connection refused`（止まるときのもの）と、旧い CoreDNS（`-stznf`）の `Readiness probe failed … 8181 … connection refused`（止まるときのもの）。想定内
- MetalLB は apiserver の入れ替えの後に、同じノードで `serviceAnnounced` を出し直した（gated-v4 chirico 13:03:13Z、`::133` duchamp 13:04:05Z、VIP pablo 13:04:24Z）。告知ノードは変わらない
- `install kubernetes` の直後（全体の apply の後の 1 分ほど）も、etcd の health は 3 台とも healthy のまま（runbook §8.13 の dev の遅れは本番では起きなかった）

## 5. 2 つ目の etcd のバックアップ（runbook §4.2）

| 項目 | 値 |
|---|---|
| コマンド | `porkadot etcd backup --config ./porkadot.yaml`（porkadot 0.36.0、etcdctl 3.6.15。サンドボックスの中で 13:08:44Z〜13:08:47Z、rc 0、6 つとも `successful`） |
| 取ったメンバー | 192.168.1.111 |
| ファイル | `etcd-2026-10-21T13:08:44+00:00.db`、モード 0600、55,107,616 バイト（段の前のものと同じサイズ） |
| sha256 | `fd239f03267a6f5b48f5299c5b9398541371d9a575159c358c9c65ecba547f40` |
| 置き場所 | 段 7 の worktree の `./backup/`（git には入れていない）。片付けの前に coordinator がメインの checkout の `backup/` へ移す |
| 中身 | 1.36 の control-plane、CoreDNS v1.14.7、kubelet は 1.35。runbook §7.4 の restore で、段の前のもの（`etcd-2026-10-21T12:59:15+00:00.db`）の代わりに使える |

## 6. 監視の FAIL と、その原因

| 時刻 | VIP / LB / etcd の health | 原因 |
|---|---|---|
| 13:02:42Z | VIP | .112 の kube-apiserver の入れ替え（新しい Pod の Ready と同じ秒） |

LB（`192.168.1.200`）の FAIL は 0、etcd の health の unhealthy も 0。段 6 の本番と同じ（VIP 1 回）。

## 7. 手順書との差、気づいたこと

- なし。`install kubernetes` は 1 回目で rc 0、CoreDNS の rollout も runbook §3.3 の 13・20 のとおり
- runbook §3.3 の 1〜12 の「`The manifest file is empty, ignoring.` の 1 行」は、KCM・scheduler に加えて apiserver の 3 つにも出た（runbook §8.17 のとおり）。apiserver の起動の直後の `metrics-server not found` は runbook に無いが、一時的なもの（§4 の注）
- CoreDNS の 2 つの Pod は amd64 の worker（chirico、duchamp）に置かれた（runbook §2.13 の見込みどおり）。arm64 の CoreDNS は本番では動いていない
