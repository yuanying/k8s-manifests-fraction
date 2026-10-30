# porkadot 0.37.6: control-plane と CoreDNS（`install kubernetes`）

runbook §2.4・§2.5・§2.3・§3 の記録。時刻は UTC。出力はタスクディレクトリの `notes/0-37-6/`（`prepull.log`、`etcd-backup-1.log`、`install-kubernetes.log`、`cp/`、`logs/`）。

## 1. イメージの事前 pull（§2.5。11:09:21〜11:10:23Z）

`prepull.sh` を 1 台ずつ流し、15 の pull がすべて rc 0。最後の `crictl images` に入れたイメージが出た（ベースラインではどのノードにも無かった。crictl の出力は pull の後の `Image is up to date for <ID>`）。

| イメージ | 入れた台 | image ID |
|---|---|---|
| `kube-apiserver:v1.37.2` | .111・.112・.113（arm64） | `a6d02e64d4827`（27.8 MB） |
| `kube-controller-manager:v1.37.2` | 同上 | `9958587f99032`（24.4 MB） |
| `kube-scheduler:v1.37.2` | 同上 | `97b03ac504259`（18.7 MB） |
| `kube-proxy:v1.37.2` | control-plane 3 台（arm64） | `58649d92879e0`（26.5 MB） |
| `kube-proxy:v1.37.2` | braque・chirico・duchamp・oeilvert・pablo（amd64） | `55b428162aa8c`（30.2 MB） |
| `coredns/coredns:v1.15.0` | chirico・duchamp・oeilvert・pablo（amd64） | `881cbdacb8c16`（24.9 MB） |

同じイメージの ID は arch ごとに台の間でそろった。

## 2. etcd のバックアップ（§2.4）

11:10:29〜11:10:33Z に、porkadot 0.37.6 の `etcd backup` を worktree のルートで流した（rc 0）。流す前と後で `git status --short assets porkadot.yaml` は空。

| ファイル | 置き場所 | バイト | sha256 |
|---|---|---|---|
| `etcd-2026-10-30T11:10:29+00:00.db`（モード 0600） | worktree `0-37-6-prod` の `./backup/`（git には入れない） | 74,612,768 | `e1cdf191638d7bb80ef4e67f66d034e32dafe4b4640abe590bf89b8bd98c8360` |

メインの checkout の前のもの（`etcd-2026-10-27T10:39:31+00:00.db`、68,919,328 B）と同じ桁。worktree を片付ける前に、メインの checkout の `backup/` へ写す（coordinator）。

## 3. 監視（§2.3）

11:10:4xZ に、ハーネスのバックグラウンド実行で 7 つのジョブとして起動した（bg1 `probe.sh`、bg2 `dns-watch2.sh`（braque）、bg3 `dns-watch2.sh`（oeilvert）、bg4 `dns-replicas-watch.sh`、bg5 `cp-watch.sh 3600`、bg6・bg7 `etcd-probe.sh`（.111・.112、3600 秒））。`nohup`・`&` は使っていない。11:12:06Z に 7 つのログの最後の行が 1 秒以内で、FAIL 0 だった。

## 4. `install kubernetes --node 192.168.1.111`（§3.2。11:12:17〜11:15:04Z、rc 0）

- 2 分 47 秒。SSH 先は `ubuntu@192.168.1.111` だけ。流す前と後で `git status --short assets porkadot.yaml` は空
- `daemon set "kube-apiserver" successfully rolled out` の後に全体を apply。`deployment.apps/coredns`・`kube-controller-manager`・`kube-scheduler`、`daemonset.apps/kube-proxy`・`kube-apiserver` が `configured`。ServiceAccount 3 つ、ClusterRoleBinding 4 つ、ConfigMap `kube-proxy`、Service `porkadot-kubernetes-latest` が `configured`。前からの `configured` は PDB 2 つと `metallb-webhook-configuration`
- **ConfigMap `coredns` は `unchanged`**、`ipaddresspool.metallb.io/first-pool` は `unchanged`、`pruned` の行は無い

入れ替わりの時刻（`cp-watch.log`・`dns-replicas.log`。2 秒・1 秒ごと）:

| 時刻 | 何が起きたか |
|---|---|
| 11:12:59〜11:13:01Z | .113 の apiserver（`-djbxn` → `-8rxxd`）。.113 の `/readyz` は 11:12:30〜11:13:06Z に 000・500 |
| 11:13:50〜11:13:52Z | .112（`-52p95` → `-k7b6b`）。.112 の `/readyz` は 11:13:21〜11:13:59Z に 000・403・500 |
| 11:14:31〜11:14:34Z | .111（`-qxb4k` → `-q4tpv`）。.111 の `/readyz` は 11:14:04〜11:14:41Z に 000・500 |
| 11:14:55Z | 全体の apply。CoreDNS の古い `-6gkk5`（chirico）が `TERMINATING`、新しい `-lsjhk`（duchamp）が Pending。KCM `-5zz9j`・scheduler `-5pfsh` が .112 に |
| 11:14:56Z | 新しい `-4kjb5`（chirico）、`-lsjhk` Ready。古い `-n75n5`（oeilvert）も `TERMINATING`。ready 1（spec 2、status 3） |
| 11:14:57Z | ready 2（新しい 2 つとも Ready） |
| 11:14:55〜11:15:04Z | kube-proxy 8 つ（.113・.111 → braque・pablo・duchamp・oeilvert・.112 → chirico） |
| 11:15:01〜11:15:02Z | 古い CoreDNS の 2 つが消えた |
| 11:15:04〜11:15:25Z | 古い scheduler・KCM が消えた。新しい scheduler `-7blnt`・KCM `-cv2bb` が .111 に（11:15:07・11:15:16Z） |

**CoreDNS の入れ替わり（11:14:55〜11:15:02Z）と kube-proxy の 8 台の入れ替わり（11:14:55〜11:15:04Z）、KCM・scheduler の入れ替わりが重なったが、ready が 0 になる行は無く、2 か所の DNS の監視の FAIL は 0**（runbook §2.1 の 13）。CoreDNS の rollout は KCM・scheduler の入れ替わりで止まらなかった。

## 5. rollout と確認（§3.3。11:15:44Z に 5 つの `rollout status` が完了、11:15:55Z〜の `snap.sh`・`etcd-check.sh`・`endpoints.sh` など）

| # | 確認 | 結果 |
|---|---|---|
| 1 | 版 | Server v1.37.2。apiserver・KCM・scheduler・kube-proxy は v1.37.2。Node は 8 台 Ready で kubelet は v1.37.1 |
| 2 | generation | `kube-apiserver` 32、`kube-proxy` 28、KCM 31、scheduler 30、`coredns` 15。`cnidaria` 4、autoscaler 5、`metrics-server` 2、approver は変わらない |
| 3 | 作り直された Pod | apiserver 3、KCM 2、scheduler 2、kube-proxy 8、CoreDNS 2 の 17 個が新しい UID で restartCount 0。**ほかの Pod の UID・restartCount はベースラインと同じ**（etcd の static Pod も）。別に `natsumi/natsumi-penelope-0` が増えた（§6） |
| 4 | VIP と apiserver | VIP の `/readyz` は 200。`probe.log` の VIP の 000 は 11:13:21Z の 1 サンプル（.112 の apiserver が止まった直後）。`dns-replicas-watch.sh` の kubectl も 11:14:03Z（.111 が止まった直後）に 1 回 `connection refused` |
| 5 | etcd | 3/3 healthy、3.7.3・storage 3.7.0、リーダー .113、raft term 23127、raft index がそろう（1408390916〜917）。`etcd-probe` の unhealthy は 0。11:12Z からの warn 以上は `apply request took too long` だけ（.111 21、.112 17、.113 2） |
| 6 | KCM と scheduler のログ | `Failed to watch`・`failed to list` は 0。`The manifest file is empty, ignoring.` が 1 行ずつ。KCM の leader `-cv2bb` に、11:17:50Z の `natsumi/natsumi-penelope` の `Error syncing StatefulSet, requeuing`（`read version … is not as new as written version`）が 1 行（§6 の 2 回目の作り直しと同じ時刻） |
| 7 | apiserver のログ | 3 つとも `W` は起動の `Skipping API … because it has no resources` と `Resetting endpoints for master service "kubernetes"`、`E` は `The manifest file is empty, ignoring.` の 1 行 |
| 8 | approver | 1/1、変わらない |
| 9 | CSR | 無い |
| 10 | storage version | `prefixes: 70, keys: 2766, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は 4 行、`/registry/clustertrustbundles/` は `certificates.k8s.io/v1beta1` の `ok` で 1 キー |
| 11 | kube-proxy | 8 つとも v1.37.2 で `Using iptables Proxier`。**`Setting nf_conntrack_max` の行は 0**（ベースラインは 8）。8 台の `nf_conntrack_max` はベースラインと同じ。`nodePortAddresses is unset` の `E` の 1 行は前から |
| 12 | MetalLB | `first-pool` は `unchanged`、`addresses` は `192.168.1.101/32`、`192.168.1.190-192.168.1.254`、`2405:6580:6740:ac01:ace::/96` |
| 14 | FlowSchema、ServiceCIDR、IPAddress | FlowSchema 11、`servicecidrs` の `kubernetes`（`10.254.0.0/24,fd20:afc2:7c09::/108`）、IPAddress 68 で ClusterIP の数（68）と同じ |

CoreDNS（13）:

| # | 確認 | 結果 |
|---|---|---|
| 13a | Deployment | generation 15、ReplicaSet `coredns-74668cf466`（revision 12、`RuntimeDefault`）が 2/2、イメージ v1.15.0。`spec` のベースラインとの差はイメージの 1 行だけ。`coredns-6bfc79bb8`（revision 11）は 0 で残り、最も古い `coredns-76bd8dbd8c`（revision 1）は消えた |
| 13b | Pod | `coredns-74668cf466-4kjb5`（chirico、`10.244.8.71`）と `coredns-74668cf466-lsjhk`（duchamp、`10.244.5.154`）、2 つとも Running・Ready・restart 0。別のノード。古い 2 つは無い |
| 13c | 入れ替わり | §4 の表。ready が 0 になる行は無い |
| 13d | seccomp | 2 つとも CRI の `security_context.seccomp` が `{}`、OCI spec の `linux.seccomp` が `SCMP_ACT_ERRNO`・規則 13、`Seccomp: 2`・`Seccomp_filters: 1`、capabilities は `CAP_NET_BIND_SERVICE` だけ（`CapEff`・`CapBnd` `0x400`）、`NoNewPrivs: 1` |
| 13e | 答え（`endpoints.sh`） | 2 つの Pod とも UDP・TCP で、flags を除いた rcode と答えがベースラインと同じ（diff 0 行）。外の名前の flags は `qr rd ra`（`aa` が付かない。v1.15.0 の想定どおり）。`:8080/health`・`:8181/ready`・`:9153/metrics` が 200、`coredns_build_info{goversion="go1.27.3",revision="a6fde3f",version="1.15.0"}` |
| 13f | `tools/dns-check.sh` | ベースラインとの差は CoreDNS の Pod の IP の入った PTR の行と server の行だけ（IP の読み替え） |
| 13g | ログ | 起動の行だけ（`.:53`、`CoreDNS-1.15.0`、`linux/amd64, go1.27.3, a6fde3f`）。`-4kjb5` に `[INFO] plugin/ready: Plugins not ready: "kubernetes"` が 1 行（runbook §8.2 の想定内）。error・warn・fatal・loop は 0 |
| 13h | `loop` | restart 0。前のコンテナは無い |
| 13i | Corefile と Service | resourceVersion `1239255997`、SHA512 `dbda5533…` で同じ。EndpointSlice `kube-dns-wr2s4` は新しい 2 つの IP だけ |
| 13j | autoscaler | `kube-dns-autoscaler-5959bf78f6-pnh8z`（UID・restart 0）で同じ |
| 13k | DNS の監視 | `install kubernetes` から §3.3 の終わりまで、braque・oeilvert とも FAIL 0 |

## 6. 別タスクの natsumi-penelope（作業と重なった変化）

別タスク natsumi-dev の coordinator が、同じ時間帯に名前空間 `natsumi` に apply していた（coordinator が確認。StatefulSet `natsumi-penelope` の replicas 0 → 1、v0.1.57、ConfigMap の作り直し）。この作業の操作によるものではない。

| 時刻 | 何が起きたか |
|---|---|
| 11:10:05Z | StatefulSet `natsumi-penelope` の新しい revision（`natsumi-penelope-fc85fdc5d`）、ConfigMap 4 つ（`natsumi-sidecars-penelope-…` など）。Pod `natsumi-penelope-0` が chirico に。Longhorn の `natsumi-penelope`（`pvc-0fac3150`）が chirico にアタッチ（エンジンの起動 11:10:07Z、iSCSI のセッション 36） |
| 11:13:14Z | readiness の失敗（`10.244.8.68:2222` refused）の後、11:13:23Z に STS が Pod を作り直した（UID `7f46653e`） |
| 11:17:49Z | readiness の失敗（`10.244.8.70:2222`）の後、11:17:50Z に STS が Pod を作り直した（UID `a7c706df`、`10.244.8.72`、6/6 Running、restart 0） |

どちらの作り直しも、chirico の `install kubelet` の前で、その時刻にこの作業の本番の操作は無い（11:15:44Z の後は読み取りだけ）。coordinator の判断で、これを新しいベースラインにした: Longhorn は 17 本とも attached healthy（chirico 10、duchamp 6、oeilvert 1）、chirico の iSCSI のセッションは 10。
