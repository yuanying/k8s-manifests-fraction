# CoreDNS の seccomp の記録

本番 `fraction` の CoreDNS を、containerd の既定の seccomp プロファイル（`RuntimeDefault`）で動かした（porkadot 0.37.3 → 0.37.4。イメージ `registry.k8s.io/coredns/coredns:v1.14.7` と Corefile は変わらない）。手順は `../../runbook-coredns-seccomp.md`（以下 runbook）、前提とベースラインは `baseline.md`。
時刻は UTC。2026-10-26 07:03:59Z の `install kubernetes` から 07:05:54Z の監視の停止まで。監視のログ、`snap.sh`・`node-state.sh`・`endpoints.sh`・`seccomp.sh`・`dns-check.sh` の出力、`install kubernetes` の出力、CoreDNS の events は、タスクディレクトリの `notes/coredns-seccomp/` に置いた（リポジトリには入れない）。

**結果: runbook §4.2 の 16 項目と §4.3 はすべて合格した。** 新しい Pod 2 つ（chirico、oeilvert）は v1.14.7 で起動から 1〜2 秒で Ready になり、restart 0、`loop` の FATAL も無かった。2 つとも `Seccomp: 2` で動いている。1 秒ごとの DNS の問い合わせ（240 サンプル）は 1 度も落ちなかった。CoreDNS 以外の Pod と 8 台の kubelet は変わっていない。

## 1. 流れ

| 時刻 | 何をしたか | 結果 |
|---|---|---|
| 06:55〜07:01:31 | §1・§2.2 の前提とベースライン（読み取り。§1 の確認は 07:00Z より前、ベースラインは 07:01Z から） | `baseline.md` |
| 07:01:58 | §2.3 の監視（`dns-watch.sh`、`dns-replicas-watch.sh`）をジョブとして起動 | — |
| 07:02:07〜07:02:11 | ✋ §2.4 の etcd backup | rc 0。`baseline.md` §4 |
| 07:02:36 | ✋ §3.1 の scale の server dry-run | warning あり。`baseline.md` §5 |
| 07:03:47 | §3.1 の事前確認 | 8 台 Ready、`coredns` 2/2、autoscaler 1/1、監視の最後の行が 1 秒以内で FAIL 0、`git status --short assets porkadot.yaml` が空、porkadot が `v0.37.4`、checkout は Draft PR の `1baca73`（master `96df273` に記録を足しただけ） |
| 07:03:59〜07:04:25 | ✋ §3.2 の `install kubernetes --node 192.168.1.111` | **1 回目で rc 0**（26.4 秒） |
| 07:04:16〜07:04:24 | §4.1 の入れ替わり | §3 |
| 07:04:29 | `rollout status` | `successfully rolled out` |
| 07:04:47〜07:05:1x | §4.2 の `snap.sh`・`node-state.sh`・`endpoints.sh`・`seccomp.sh`・`dns-check.sh`（`after`）、VIP | §4 |
| 07:05:45 | ✋ §4.3 の scale の server dry-run、トークンの破棄 | warning なし。§4 の 15 |
| 07:05:53 | Pod・Node・ログの最後の確認 | 変わらず |
| 07:05:54 | 監視を止めた（`watch.stop`） | 2 つのジョブとも終わった（`dns.log` の最後の行は 07:06:32） |

## 2. `install kubernetes`（runbook §3.2）

`porkadot install kubernetes --node 192.168.1.111`（porkadot 0.37.4、cwd は worktree `coredns-seccomp-prod`）。07:03:59.145Z〜07:04:25.552Z、rc 0。流す前と後で `git status --short` は空。

- `configured`: **`deployment.apps/coredns`**、DaemonSet `kube-apiserver`（2 回）、PDB `kube-controller-manager`・`kube-scheduler`、ValidatingWebhookConfiguration `metallb-webhook-configuration`。runbook §3.2 の組と同じ
- ConfigMap `coredns`、Service `kube-dns`、ServiceAccount・ClusterRole・ClusterRoleBinding `coredns`（`system:coredns`）、`kube-dns-autoscaler` の 4 つは `unchanged`。`unchanged` は 61 行
- **`pruned` の行は無い**。`created`・`deleted` も無い。warning・error の行も無い

## 3. 入れ替わり（runbook §4.1）

CoreDNS の events、Pod の conditions、`dns-replicas.log`（1〜2 秒ごと）から。

| 時刻 | できごと |
|---|---|
| 07:04:16 | ReplicaSet `coredns-6bfc79bb8`（revision 11）を 0 → 1 → 2、`coredns-76d7d8dc86` を 2 → 1。古い Pod `coredns-76d7d8dc86-shdgn`（chirico）の `Killing`。新しい Pod `coredns-6bfc79bb8-6gkk5` を作った |
| 07:04:17 | `-6gkk5` を **chirico** に、`coredns-6bfc79bb8-n75n5` を **oeilvert** に割り当て。`-6gkk5` はイメージがあり（`already present`）、コンテナを起動。最初の readiness probe が `:8181` の `connection refused`。`-n75n5` は pull を始めた。`-n75n5` に `DNSConfigForming` の warning（§5） |
| 07:04:18 | **`-6gkk5` が Ready**。`-n75n5` の pull が終わった（1.282 秒、24,261,571 B）。`coredns-76d7d8dc86` を 1 → 0、残りの古い Pod `coredns-76d7d8dc86-469lz`（duchamp）の `Killing` |
| 07:04:19 | `-n75n5` のコンテナを起動。最初の readiness probe が `connection refused`。同じ秒に **`-n75n5` が Ready** |
| 07:04:22 | `dns-replicas.log` から `-shdgn` が消えた |
| 07:04:23 | `-469lz` の readiness probe が `connection refused`（lameduck の後の終わり方） |
| 07:04:25 | `dns-replicas.log` から `-469lz` が消えた |

- `dns-replicas.log` の 192 行（07:01:58〜07:05:53）で、ready は 07:04:17・07:04:18 の 2 行が 1、ほかの 190 行は 2。**0 の行は無い**。07:04:18 の行は `-6gkk5` と、Terminating だが lameduck の間 Ready の `-469lz` の 2 つが答えていた
- 新しい Pod は作られてから 2 秒で Ready。2 分の止める条件に近づくことは無かった
- **残りの古い Pod `-469lz` は、新しい Pod の 1 つ目（`-6gkk5`）が Ready になった 07:04:18 に止められた**（2 つ目の `-n75n5` は 07:04:19 に Ready）。runbook §2.1 の 3 の「2 つが Ready になってから」とは違う（§5）

### 3.1 途切れ

| 監視 | サンプル | FAIL |
|---|---|---|
| `in=`（`kubernetes.default.svc.cluster.local`） | 240（07:01:58〜07:06:32） | **0** |
| `dns=`（`kube-dns.kube-system.svc.cluster.local`） | 240 | **0** |
| `ext=`（`www.google.com`） | 240 | **0** |
| `ptr=`（`10.0.254.10.in-addr.arpa`） | 240 | **0** |
| `tcp=`（`kubernetes.default.svc.cluster.local`、TCP） | 240 | **0** |

`install kubernetes` から §4.3 の終わりまで（07:03:59〜07:05:46）は 93 サンプルで、FAIL は 0。`ssh rc=` の行は無く、サンプルの間隔は最大 1.95 秒。

## 4. 確認（runbook §4.2、§4.3）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Deployment | generation 13 → **14**（observedGeneration 14）、revision 10 → **11**。2/2、updated 2。テンプレートの Pod の `securityContext` が `{seccompProfile: {type: RuntimeDefault}}`、テンプレートの annotations は無い（`seccomp.security.alpha.kubernetes.io/pod` が消えた）、コンテナの `capabilities.drop` が `[ALL]`。ほかのテンプレート（イメージ、引数、コンテナの securityContext のほかの値、probe、resources、tolerations、nodeSelector、affinity、`dnsPolicy`、`terminationGracePeriodSeconds`）と strategy・revisionHistoryLimit はベースラインと同じ（`notes/coredns-seccomp/{base,after}/deploy-summary.json` の diff） |
| 2 | Pod | **`coredns-6bfc79bb8-6gkk5`（UID `2304e87a-9139-4ff8-979a-e16233da6438`）と `coredns-6bfc79bb8-n75n5`（UID `f15249d1-d7e6-4bd0-9ad8-c305778e10bd`）が v1.14.7 で Running、Ready、restart 0**。imageID はどちらも `sha256:7efd3c635b03…`（ベースラインと同じ digest）。古い Pod `-469lz`・`-shdgn` は無い |
| 3 | 配置 | `-6gkk5` が **chirico**（`10.244.8.201`）、`-n75n5` が **oeilvert**（`10.244.7.65`）。別のノード。control-plane と braque には無い |
| 4 | ReplicaSet | `coredns-6bfc79bb8`（revision 11、`seccompProfile` が `RuntimeDefault`）が 2/2。`coredns-76d7d8dc86`（revision 10）は 0 で残る。古い 9 つも 0 のまま（replicas 0 の ReplicaSet は 10 で、revisionHistoryLimit 10 に収まる） |
| 5 | seccomp（`seccomp.sh 192.168.1.83`・`192.168.1.82`） | **2 つとも**、CRI の config の `security_context.seccomp` が `{}`（`profile_type` 0 = RuntimeDefault）、OCI spec に `linux.seccomp`（`defaultAction: SCMP_ACT_ERRNO`、syscall の規則 13。dev と同じ）がある、**`/proc/<pid>/status` が `Seccomp: 2`、`Seccomp_filters: 1`**。capabilities は bounding・effective・permitted とも `CAP_NET_BIND_SERVICE` だけ（`CapEff`・`CapBnd` が `0x400`）、`noNewPrivileges: true`（`NoNewPrivs: 1`）。ベースラインと同じ |
| 6 | 答え（`endpoints.sh`） | 2 つとも、UDP と TCP で、Pod の名前・IP と外の名前の A の答えを除いて **ベースラインとまったく同じ**（クラスタ内の A・SRV・PTR の答え、すべての rcode）。`:8080/health`・`:8181/ready`・`:9153/metrics` が 200、`coredns_build_info{goversion="go1.26.6",revision="427fc80",version="1.14.7"}` |
| 7 | 答え（`tools/dns-check.sh`） | Service と 2 つの Pod の答えが `base/dns-check.txt` と同じ。違うのは CoreDNS の Pod の IP の PTR（`-x 10.244.8.201`・`-x 10.244.7.65` の答えが新しい IP の名前）の行だけ。外の名前の答えも同じだった |
| 8 | ログ | 2 つとも起動の 5 行だけ（`maxprocs`、`.:53`、`Running configuration SHA512 = 78384ea2…`、`CoreDNS-1.14.7`、`linux/amd64, go1.26.6, 427fc80`）。**`[ERROR]`・`[WARNING]`・`[FATAL]`・`plugin/loop` は無い**（07:05:53 にも 0）。前のコンテナは無い。**`loop` の FATAL は出なかった** |
| 9 | Corefile | ConfigMap `coredns` の yaml がベースラインとまったく同じ（resourceVersion `1239255997`）。Corefile の SHA512 は `dbda5533…` のまま |
| 10 | Service | EndpointSlice `kube-dns-wr2s4` の endpoint が `10.244.8.201`・`10.244.7.65` だけ。Service `kube-dns` の yaml がベースラインとまったく同じ（clusterIP `10.254.0.10`） |
| 11 | replicas と autoscaler | `coredns` の replicas 2。autoscaler の Pod（`kube-dns-autoscaler-5959bf78f6-pnh8z`、UID・restart 0）と ConfigMap `kube-dns-autoscaler`（resourceVersion `901196490`）の yaml がベースラインと同じ。autoscaler のログはベースラインとまったく同じ 6 行で、`Replicas are not as expected`・`E`・`W` で始まる行は無い |
| 12 | ほかの Pod | CoreDNS の Pod を除いた全 Pod の名前・ノード・UID・restartCount・phase がベースラインとまったく同じ（`pods.txt` の diff が空）。170 個（Running 146、Succeeded 24）で、07:05:53 に Running / Completed 以外は 0 |
| 13 | kubelet | 8 台の MainPID・NRestarts・ActiveEnterTimestamp がベースラインと同じ。containerd のイメージは oeilvert に `coredns/coredns:v1.14.7`（`97efff2babf85`、24.3 MB）が増えただけ |
| 14 | 監視の FAIL | §3.1。0 |
| 15 | warning（§4.3） | 07:05:45 に `infra-admin` のトークン（`--duration=1h`）を発行し、`--dry-run=server` を確かめてから流した。出力は **`deployment.apps/coredns scaled (server dry run)` だけで、`non-functional in v1.27+` の warning は消えた**。直後の replicas 2、generation 14、ready 2。トークンは同じシェルの中で `unset` した（ファイルには書いていない。サーバー側では 08:05:45Z に切れる） |
| 16 | 健全性 | 8 台 Ready、`https://192.168.1.101:6443/readyz` が 200（07:05Z） |

## 5. 手順書との差

- **残りの古い Pod は、新しい Pod の 1 つ目が Ready になった時点で止められた**（§3）。runbook §2.1 の 3（と dev の記録の要約）の「2 つが Ready になってから残りの古い Pod を止める」は、本番ではそうならなかった。`maxUnavailable: 1` なので、Deployment controller は「available が replicas − 1 = 1 以上」を保てるところまで古い Pod を減らす。新しい 1 つが Ready になれば、古い Pod を 0 にしても available は 1 になる。dev で 2 つが Ready になってから止まったのは、2 つ目がほぼ同時に Ready になったためとみる。どちらでも Ready な Pod が 0 になることは無い。runbook の §2.1 の 3 を直した（この PR）
- **oeilvert の Pod に `DNSConfigForming` の warning が出た**: `Nameserver limits were exceeded, some nameservers have been omitted, the applied nameserver line is: 192.168.0.1 10.254.0.10 192.168.0.1`。oeilvert の resolv.conf に nameserver が 4 つあり（`baseline.md` §2 の 13）、kubelet は最初の 3 つだけを渡す（`dnsPolicy: Default`）。前からの resolv.conf の件（runbook §8.1）で、この手順で変わったものではない。oeilvert の CoreDNS の上流は 192.168.0.1・10.254.0.10・192.168.0.1 になり、IPv6 の上流は使われない。`loop` の FATAL は出なかった。runbook §8.1 に書き足した（この PR）
- **readiness probe の 1 回目の失敗の後、Ready になるまでは 1 秒ほどだった**（`-6gkk5` は 07:04:17 に失敗して 07:04:18 に Ready、`-n75n5` は 07:04:19 に失敗して同じ秒に Ready）。runbook §8.2 の「次は 10 秒後」にはならなかった。runbook §8.2 に書き足した（この PR）
- **`infra-admin` のトークンは 2 回発行した**（§3.1 と §4.3）。worker のハーネスでは、コマンドごとに新しいシェルになり、シェルの変数が残らない。runbook §1.2 の「§3.1 で発行し §4.3 の後に破棄する」の代わりに、dry-run ごとに同じコマンドの中で発行・使用・`unset` した。トークンはファイルに書いていない。runbook §1.2 に書き足した（この PR）
- **etcd のバックアップが前より 21% 大きかった**（66,986,016 B。前は 55,107,616 B）。桁は同じなので止めていない（`baseline.md` §4）。runbook §2.4 の比べる値を直した（この PR）
- Pod は oeilvert（DNS の監視のノード）にも載った。runbook §2.7 のとおり監視（Service への dig）には関わらず、FAIL は 0
- そのほかは runbook のとおり（`install kubernetes` の `configured` の組、pull（1.3 秒）、seccomp、答え、ログ、warning）

## 6. 片付けと、残したこと

- 一時的なリソース・名前空間は作っていない。`infra-admin` のトークンは 2 回とも使った直後に `unset` した（§4 の 15）
- 監視は 07:05:54Z に止めた（2 つのジョブとも終わった）
- etcd のバックアップは worktree の `./backup/etcd-2026-10-26T07:02:07+00:00.db`（66,986,016 B、sha256 `0642993b21e894013073835b8f6e17c81145b8a14b22597e9b2d1f53cf786b40`）。git には入れていない。worktree を片付ける前に、メインの checkout の `backup/` へ写す（coordinator）
- runbook §10 の対象（CoreDNS v1.15、ノードの resolv.conf の kube-dns、`podAntiAffinity`、古い ReplicaSet `coredns-76d7d8dc86` とほかの 9 つ、ノードの古い CoreDNS のイメージ）には触っていない。CoreDNS は registry.k8s.io に v1.15.0 が無い（07:00Z の前に 404）ため v1.14.7 のまま
