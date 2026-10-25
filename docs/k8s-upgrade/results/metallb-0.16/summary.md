# MetalLB v0.16.1 の記録

本番 `fraction` の MetalLB を v0.14.5 から v0.16.1 へ上げた（porkadot 0.37.1 → 0.37.2）。あわせて、使われていない古い CRD `addresspools.metallb.io` を消した。手順は `../../runbook-metallb-0.16.md`（以下 runbook）、前提とベースラインは `baseline.md`。
時刻は UTC。2026-10-25 02:11:10Z の `install kubernetes` から 02:19:11Z の §5 まで。監視のログ、`snap.sh`・`node-ports.sh` の出力、speaker・controller のログの写しは、タスクディレクトリの `notes/metallb-0-16/` に置いた（リポジトリには入れない）。

**結果: runbook §4.2 の 16 項目と §5 はすべて合格した。** API の VIP、gated-v4・gated-v6、`::131`・`::132` は、1 秒ごとの probe（632 サンプル）で 1 度も落ちなかった。MetalLB 以外の Pod と 8 台の kubelet は変わっていない。

## 1. 流れ

| 時刻 | 何をしたか | 結果 |
|---|---|---|
| 02:06〜02:07 | §1・§2.2 の前提とベースライン（読み取り） | `baseline.md` |
| 02:08:11 | §2.3 の監視（`probe.sh`、`ml-watch.sh`）をジョブとして起動 | — |
| 02:08:18〜02:08:22 | ✋ §2.4 の etcd backup | rc 0。`baseline.md` §4 |
| 02:08:38〜02:09:39 | ✋ §2.5 のイメージの事前 pull | 11 回とも rc 0。`baseline.md` §5 |
| 02:11:02 | §3.1 の事前確認 | 8 台 Ready、VIP 200、MetalLB 8/8、監視の最後の行が 1 秒前、`git status --short assets porkadot.yaml` が空 |
| 02:11:10〜02:11:35 | ✋ §3.2 の `install kubernetes --node 192.168.1.111` | **1 回目で rc 0**（25 秒） |
| 02:11:28〜02:12:52 | §4.1 の入れ替わり | controller の後に speaker を 1 台ずつ。rollout の完了は 02:12:50 |
| 02:13:03〜02:13:15 | §4.2 の `snap.sh`・`node-ports.sh`（`after`） | §3 |
| 02:15:28 | ✋ `infra-admin` の 1 時間のトークンを発行 | — |
| 02:15:33〜02:15:53 | ✋ §4.2 の 16 の `netcheck.sh` | **PASS 168 / 168、pods 8/8** |
| 02:15:59〜02:18:31 | ✋ §4.2 の 16 の `npcheck.sh` | **`OK 56, not OK 0`** |
| 02:18:45〜02:18:55 | ✋ §4.3 の webhook と新しい LoadBalancer | §4 |
| 02:19:11 | ✋ §5 の `addresspools.metallb.io` の削除 | §5 |
| 02:19:58 | `snap.sh`（`final`） | §5 |
| 02:20:07 | 監視を止め、トークンのファイルを消した | §7 |

## 2. `install kubernetes`（runbook §3.2）

`porkadot install kubernetes --node 192.168.1.111`（porkadot 0.37.2、cwd は worktree `metallb-0-16-prod`）。02:11:10.474Z〜02:11:35.709Z、rc 0。流す前と後で `git status --short` は空。

- CRD の server-side apply: MetalLB の 9 つ（`configurationstates`・`servicebgpstatuses` を含む）と `nodenetworkpolicies.cnidaria.unstable.cloud` が `serverside-applied`。10 個の MetalLB の CRD（`addresspools` を含む）が `condition met`
- apiserver の apply の後に `daemon set "kube-apiserver" successfully rolled out`
- `configured`: Role `controller`・`pod-lister`、ClusterRole `metallb-system:controller`・`metallb-system:speaker`、RoleBinding `pod-lister`、Deployment `controller`、DaemonSet `speaker`、ValidatingWebhookConfiguration `metallb-webhook-configuration`、PDB `kube-controller-manager`・`kube-scheduler`、DaemonSet `kube-apiserver`（2 回）。dev の記録の出力と同じ組
  - DaemonSet `kube-apiserver` の `configured` は前の段からのもの（dev の MetalLB の検証、段 3・6・7・8 の本番の出力にもある）。generation は 31 で `observedGeneration` も 31、managedFields の `kubectl-client-side-apply` の最後は 2026-10-23 22:20:02Z（段 8）のまま、apiserver の 3 つの Pod の UID と restartCount はベースラインと同じ。runbook §3.2 の「apiserver は `unchanged`」は誤りなので直した（§6）
- `ipaddresspool.metallb.io/first-pool` と `l2advertisement.metallb.io/system` は `unchanged`
- **`pruned` の行は無い**。`unchanged` は 55 行

## 3. 入れ替わりと告知（runbook §4.1）

### 3.1 入れ替わり

`ml-watch.log`（2 秒ごと）と Pod の `startTime` から。古い Pod の「最後に見えた」は `ml-watch.log` に最後に出た時刻、新しい Pod の Ready は `ml-watch.log` で最初に `true` になった時刻。

| 順 | ノード | 古い Pod（最後に見えた） | 新しい Pod（startTime） | Ready | 居なかった間 |
|---|---|---|---|---|---|
| — | controller | `controller-7f974cb86-28grh`、pablo（02:11:36） | `controller-76f4cf76b7-cbmmr`、**oeilvert**（02:11:27） | 02:11:38 | 無い（新しい Pod が Ready になってから古い Pod が消えた） |
| 1 | duchamp | `speaker-nz58r`（02:11:28） | `speaker-ns4l8`（02:11:28） | 02:11:42 | 約 14 秒 |
| 2 | .112 | `speaker-r4s5d`（02:11:38） | `speaker-dq6rv`（02:11:40） | 02:11:54 | 約 16 秒 |
| 3 | oeilvert | `speaker-ph5z7`（02:11:51） | `speaker-c7xxz`（02:11:52） | 02:12:04 | 約 13 秒 |
| 4 | .113 | `speaker-xcbcj`（02:12:01） | `speaker-wcxps`（02:12:04） | 02:12:16 | 約 15 秒 |
| 5 | pablo | `speaker-9fwg2`（02:12:14） | `speaker-ltpd7`（02:12:15） | 02:12:27 | 約 13 秒 |
| 6 | .111 | `speaker-xgnzb`（02:12:27） | `speaker-lrh56`（02:12:27） | 02:12:39 | 約 12 秒 |
| 7 | chirico | `speaker-7fcfw`（02:12:39） | `speaker-xj76z`（02:12:39） | 02:12:52 | 約 13 秒 |

- speaker の 7 台で 84 秒（02:11:28〜02:12:52）。1 台あたり 12〜16 秒で、**arm64 の Pi（.111〜.113）も amd64 と同じ**（イメージは §2.5 で pull してあった。dev の「イメージがあれば約 11 秒」に近い）
- 新しい speaker が 2 分たっても Ready にならない台は無かった

### 3.2 告知の持ち主の移り

speaker のログの `serviceAnnounced`・`serviceWithdrawn`（`announce.sh` → `owners.py`、02:11〜02:20。出力は `notes/metallb-0-16/announce.txt`、`owners.txt`、`owners-by-pod.txt`）。02:11:27.8 に古い speaker が一斉に告知し直した（`install kubernetes` の全体の apply と同じ時刻）。

| アドレス | 持ち主の移り（`ノード/Pod`） | 起動の直後の告知と取り下げ（1 秒以内の `notOwner`） |
|---|---|---|
| `192.168.1.101`（VIP） | pablo/`9fwg2` → 02:12:15.244 .113/`wcxps` → 02:12:16.686 pablo/`ltpd7` | — |
| `192.168.1.200`（gated-v4） | chirico/`7fcfw` → 02:12:38.665 pablo/`ltpd7` → 02:12:42.322 chirico/`xj76z` | — |
| `…ace::200`（gated-v6） | pablo/`9fwg2` → 02:12:15.247 chirico/`7fcfw` → 02:12:16.669 pablo/`ltpd7` | — |
| `…ace::131` | .113/`xcbcj` → 02:12:03.682 pablo/`9fwg2` → 02:12:04.933 .113/`wcxps` | — |
| `…ace::132` | 02:11:27.979 chirico/`7fcfw` → 02:11:30.355 duchamp/`ns4l8` | 02:11:29.451 chirico |
| `…ace::133` | oeilvert/`ph5z7` → 02:11:53.108 oeilvert/`c7xxz` | 02:11:52.173 .113（古い `xcbcj`） |
| `…ace::134` | 02:11:27.881 .112/`r4s5d` → 02:11:30.362 duchamp/`ns4l8` | 02:11:29.461 .112 |

- 移りは 1 つのアドレスにつき 1〜2 回で、次の speaker は 1.5 秒以内に告知した（dev の記録の「2〜3 回、1 秒以内」と同じ形）
- gated（Local）の持ち主は chirico と pablo の間だけで移った（runbook §2.8 のとおり）
- 作業の後の告知のノードはベースラインと同じ（ServiceL2Status: VIP pablo、gated-v4 chirico、gated-v6 pablo、`::131` .113、`::132`・`::134` duchamp、`::133` oeilvert）

### 3.3 途切れ

| 監視 | サンプル | FAIL |
|---|---|---|
| `vip`（`/readyz`） | 632（02:08:11〜02:20:06） | **0** |
| `v4`（gated-v4） | 632 | **0** |
| `v6`（gated-v6） | 632 | **0** |
| `ssh131` | 632 | **0** |
| `ssh132` | 632 | **0** |

`install kubernetes` から rollout の完了まで（02:11:10〜02:12:51）は 90 サンプルで、FAIL は 0。2 秒を超えるサンプルの抜けも無い。

## 4. 確認（runbook §4.2、§4.3）

| # | 確認 | 結果 |
|---|---|---|
| 1 | controller | **1/1 Ready、`controller:v0.16.1`、restart 0**。oeilvert（taint の無い worker）。Deployment の generation 18 → 19 |
| 2 | speaker | **7 つとも Ready、`speaker:v0.16.1`、restart 0**（arm64 の .111〜.113 を含む） |
| 3 | speaker の DaemonSet | generation 22 → 23。**desired 7、current 7、ready 7、available 7、updated 7、misscheduled 0** |
| 4 | speaker の配置と tolerations | ベースラインと同じ 7 台（braque に無い）。live の tolerations は `master`・`control-plane`・**`nvidia.com/gpu`** の 3 つで、ベースラインと同じ。nodeSelector も同じ。Node の taint も変わらない |
| 5 | ポート | speaker の 7 台で、speaker が **`*:9120`**（tcp）、**`127.0.0.1:17472`**、`<ノード>:7946`（tcp・udp）。**`7472` は無い**。braque は 4 つとも無い。MetalLB 以外のプロセスは 9120・17472 に居ない |
| 6 | probe | `metallb-system` の events に `Unhealthy` は無い |
| 7 | CRD | MetalLB の CRD が 10（`addresspools` を入れて。§5 の後は 9）。**どれも storedVersions が 1 つ**（`bgppeers` は `[v1beta2]`、ほかは `[v1beta1]`）。`configurationstates`・`servicebgpstatuses` は `[v1beta1]`。既存の CRD の served・storage はベースラインと同じ |
| 8 | ConfigurationState | 8 つ（`controller` と `speaker-<ノード>` の 7 つ）。**どれも `result` が `Valid`**、errorSummary なし。owner はそれぞれ今の Pod |
| 9 | pool | `first-pool` の `spec.addresses` はベースラインと同じ（`192.168.1.101/32`、`192.168.1.190-192.168.1.254`、`2405:6580:6740:ac01:ace::/96`）、generation 2 のまま、`autoAssign: true`、`avoidBuggyIPs: false`。status は `assignedIPv4: 3`、`assignedIPv6: 8`、`availableIPv4: 63`、`availableIPv6: 4294967288`。`system` は generation 1 のまま |
| 10 | LoadBalancer のアドレス | 11 個とも `status.loadBalancer.ingress` がベースラインと同じ。変わった・外れたものは無い |
| 11 | 告知と応答 | §3.2、§3.3。probe は最後まで FAIL 0 |
| 12 | MetalLB のログ | 下の 4.1 |
| 13 | ほかの Pod | `metallb-system` 以外の Pod の名前・UID・restartCount・phase が、ベースラインと同じ（`after` と `final` の両方）。169 個（Running 145、Succeeded 24）で、Running / Succeeded 以外は 0 |
| 14 | kubelet | 8 台の MainPID・NRestarts・ActiveEnterTimestamp がベースラインと同じ |
| 15 | 監視の FAIL | §3.3。`install kubernetes` から rollout の完了まで 0 |
| 16 | 健全性 | ✋ `netcheck.sh`（cnidaria の手順書のもの。段 8 と同じく `RUNBOOK_ENV` で `IMAGE` を `cnidaria-cni:v0.1.1`、`CHECK_URLS` を新しいプレフィックス、`FRACTION` をこの worktree にした）: `up` → `run` が **PASS 168 / 168、pods 8/8** → `down`、`cnidaria-netcheck` は NotFound。✋ `tools/npcheck.sh`: up の前の `nft` は 8 台とも 0、up の後は 8 台とも 9、`run` は **`OK 56, not OK 0`**、down の後は 8 台とも 0、`k8u-npcheck` は NotFound。どちらも段 8 の完了の確認と同じ結果 |

ほかに: `metallb-system` の Warning のイベントは、oeilvert の `speaker-c7xxz` の `DNSConfigForming`（`Nameserver limits were exceeded`）だけ。oeilvert の resolv.conf に 192.168.0.1 が 2 つあるためで、前からのもの（段 8 の `baseline.md` §2 の注）。ServiceL2Status が 0 → 7 になった（告知している Service ごとに 1 つ。v0.16.1 の speaker が作る）。

### 4.1 MetalLB のログ（§4.2 の 12）

新しい Pod のログの warn・error（02:20 まで）。どれも起動の直後の 1 回か、§4.3 の操作のときだけで、**続いている error は無い**。02:13 より後に speaker の warn・error は無い。

| Pod | 時刻 | 内容 | 扱い |
|---|---|---|---|
| controller | 02:11:29 | `Reconciler error`（PoolStatusController、`first-pool` の `the object has been modified`）2 回 | 想定どおり（dev の見つけたことの 5。dev は 1 回） |
| controller | 02:11:29 | `Reconciler error`（controller `service`、`metallbreload/reload`、`event handling failed, retrying`）1 回 | dev の記録に無いもの。controller の中の reload の仮の Service で、起動の直後の 1 回だけ |
| controller | 02:11:29、02:18:51 | annotation の deprecated の warn（22 回、11 回） | 想定どおり（runbook §8.4）。02:18:51 は §4.3 の Service を消したときの再処理 |
| controller | 02:18:45 | `ipaddresspool_webhook.go` の error（§4.3 の重なる pool を拒んだもの）と、PoolStatusController の `the object has been modified` 1 回 | §4.3 の操作によるもの |
| speaker（.112、.113） | 02:11:42、02:12:04 | `configurationstates.metallb.io "speaker-<ノード>" not found` の `Reconciler error`（ConfigReconciler と bgppeer）各 1 回 | dev の記録に無いもの。自分の ConfigurationState を作る前の報告（controller の `"controller" not found` と同じ形）。今は 8 つとも `Valid` |
| speaker（7 つとも） | 起動の直後 | `memberlist: Refuting a dead message (from: <自分>)` の warn 1 回 | 同じノードの IP の古い speaker が dead と見なされたのを打ち消すもの |

- controller の `configurationstates.metallb.io "controller" not found`（dev の見つけたことの 5）は出なかった
- speaker の `partial join`（runbook §8.2）は出なかった（本番は speaker の IP がノードの IP で、入れ替わりの前後で同じ）

### 4.2 新しい LoadBalancer と webhook（runbook §4.3）

- **webhook**（02:18:45、`--dry-run=server`）: `admission webhook "ipaddresspoolvalidationwebhook.metallb.io" denied the request: CIDR "192.168.1.250/32" in pool "k8u-mlb-overlap" overlaps with already defined CIDR "192.168.1.248/30"` で拒まれた（rc 1）。重なる先は範囲 `192.168.1.190-192.168.1.254` を CIDR に分けたもので表示される（runbook の例の文言を直した。§6）。IPAddressPool は `first-pool` だけのまま
- **割り当て**: 名前空間 `k8u-mlb` に selector の無い IPv4 の `type: LoadBalancer` の Service `k8u-mlb-test` を 02:18:45.427Z に作り、**0.4 秒で `192.168.1.190`** が割り当てられた（event `IPAllocated`、`Assigned IP ["192.168.1.190"]`）。`first-pool` の `assignedIPv4` は 3 → 4。02:18:46Z に名前空間を消し、`k8u-mlb` は NotFound、`assignedIPv4` は 3 に戻った（02:18:55Z）

## 5. `addresspools.metallb.io` の削除（runbook §5）

- 消す前（02:19Z）: `get addresspools.metallb.io -A` は deprecated の warning と `No resources found`、`-o name | wc -l` は **0**。CRD は `2023-04-09T07:32:54Z`、conversion は `Webhook`、先は `webhook-service`。CRD の yaml をタスクディレクトリの `notes/metallb-0-16/addresspools-crd.yaml` に控えた
- ✋ 02:19:11.214Z に `kubectl-admin delete crd addresspools.metallb.io`。`deleted` で rc 0、02:19:11.431Z に終わり、02:19:11.544Z の `get` は NotFound（Terminating は見えなかった）
- 消した後: MetalLB の CRD は 9 つ（storedVersions は 1 つずつ）。controller・speaker のログに 02:19 より後の行は無く、`AddressPool` を含む行も無い。MetalLB の Pod は 8 つとも Ready・restart 0 のまま。`probe.log` は FAIL 0
- 02:19:58Z の `snap.sh`（`final`）: MetalLB の Pod、LoadBalancer のアドレス、`metallb-system` 以外の Pod は `after` と同じ。ConfigurationState は 8 つとも `Valid`

## 6. 手順書との差

- **`announce.sh` が Pi の speaker の行を落としていた。** Pi（.111〜.113）の kubelet は `kubectl logs --timestamps` の時刻を JST（`+09:00`）で付けるので、UTC の範囲で絞ると Pi の行が外れる（dev は VM だけで UTC だった）。タスクディレクトリのスクリプトを、時刻を UTC に直してから並べて絞るように直して取り直した（§3.2 はその結果）
- runbook §3.2 の「kube-system のもの（apiserver …）は `unchanged`」は誤り。DaemonSet `kube-apiserver` は `configured` と出る（前の段から。§2）
- runbook §4.3 の webhook の文言の例は、本番では重なる先が `192.168.1.248/30` と CIDR で出る
- runbook §4.2 の 12 に無かったログ（§4.1 の speaker の `configurationstates … not found`、controller の `metallbreload/reload`）。runbook §8.2 の `partial join` は出なかった
- ServiceL2Status が 0 → 7 になる（runbook に無かった）
- controller は pablo から oeilvert に移った（runbook の「taint の無い worker 4 台のどれか」のとおり）

これらは runbook に反映した（この PR）。

## 7. 片付けと、残したこと

- 一時的な名前空間 `cnidaria-netcheck`・`k8u-npcheck`・`k8u-mlb` は消した（NotFound）
- `infra-admin` のトークン: 02:15:28Z に 1 時間の期限で発行し、作業端末の `/tmp/k8u-metallb-admin-token`（モード 600）に置いた。`npcheck.sh`、§4.3、§5 に使い、02:20Z にファイルを消した（サーバーの側では 03:15Z ごろに期限が切れる）
- 監視は 02:20:07Z に止めた（2 つのジョブとも終わった）
- etcd のバックアップは worktree の `./backup/etcd-2026-10-25T02:08:18+00:00.db`（55,107,616 B、sha256 `77560f5fcead180fe937da90a4240496e0fbc89cf705fdf14252bda3b01655cb`）。git には入れていない。worktree を片付ける前に、メインの checkout の `backup/` へ写す（coordinator）
- runbook §10 の片付けの対象（空の名前空間 `metallb`、`mlb0-metallb:*` の ClusterRole・ClusterRoleBinding、ノードに残る MetalLB の古いイメージ v0.12.1・v0.13.9・v0.14.5）には触っていない
- MetalLB の metrics（`:9120`）の RBAC は足していない（runbook §8.3）
