# cnidaria v0.1.2 の記録

本番 `fraction` の cnidaria を v0.1.1 から v0.1.2 にした（porkadot 0.37.4 → 0.37.5、`porkadot.yaml` の `addons.cnidaria.image_tag` の pin を外した。DaemonSet `kube-system/cnidaria` のイメージの 1 行だけが変わる）。手順は `../../runbook-cnidaria-0.1.2.md`（以下 runbook）、前提とベースラインは `baseline.md`。
時刻は UTC。2026-10-27 10:41:41Z の `install kubernetes` から 10:51:05Z の `nodes.sh final` まで。監視のログ（`dswatch.log`、`probe.log`、`newpods.log`）、クライアントのログ、`snap.sh`・`nodes.sh`・`verify-nodes.sh`・`check-apps.sh`・`dns-check.sh`・netcheck・npcheck の出力、`install kubernetes` の出力は、タスクディレクトリの `notes/cnidaria-0-1-2/` に置いた（リポジトリには入れない）。

**結果: runbook §4.2 の 16 項目、§4.3、§4.4 はすべて合格した。** 8 台の cnidaria の Pod は 10:41:59〜10:42:21Z（22 秒）に 1 台ずつ v0.1.2 に入れ替わり、8 つとも Ready・restart 0、ログは info だけだった。arm64 の control-plane 3 台でも同じ。既存の Pod 同士の通信・Service・DNS・NetworkPolicy は入れ替わりの間も落ちず（作った直後の 1 行のほか FAIL 0、OPEN 0）、入れ替わりの間を含めて作った 379 個の Pod はすべて Ready になり、許可の 8080 に 1〜3 秒で届き、9090 は止まった。Longhorn の 14 ボリュームは 1 秒ごとの監視で一度も healthy から外れず、LoadBalancer・VIP の監視も落ちなかった。cnidaria と一時的な名前空間のほかの Pod と、8 台の kubelet は変わっていない。

runbook と違ったのは 4 点（§8）: 新しい Pod の imageID の形、duchamp の readinessProbe の 2 回の失敗（Ready まで 11 秒）、`env-fraction.sh` の `FRACTION` の既定が無くなった worktree を指していたこと、nftables の `isolated_ingress` の集合の差。どれも止める条件には当たらない。

## 1. 流れ

| 時刻 | 何をしたか | 結果 |
|---|---|---|
| 10:37〜10:38 | §1・§2.2 の前提とベースライン（読み取り） | `baseline.md` §1・§2 |
| 10:38:46〜10:39:25 | ✋ §2.4 のイメージの事前 pull | 8 台 rc 0。`baseline.md` §3 |
| 10:39:31〜10:39:35 | ✋ §2.5 の etcd backup | rc 0。`baseline.md` §4 |
| 10:39:4x | §2.3 の `dswatch.sh`・`probe.sh` をジョブとして起動 | — |
| 10:39:54〜10:39:58 | ✋ トークンの発行、`watch.sh up`・`watch.sh clients` | `baseline.md` §5 |
| 10:41:02 | `watch.sh logs $L/pre` | 作った直後の 1 行のほか FAIL 0、OPEN 0 |
| 10:41:06 | ✋ `newpods.sh $L 300` をジョブとして起動 | — |
| 10:41:41〜10:42:06 | ✋ §3.2 の `install kubernetes --node 192.168.1.111` | **1 回目で rc 0**（25 秒） |
| 10:41:59〜10:42:21 | §4.1 の入れ替わり | §3 |
| 10:42:20 | `rollout status` | `successfully rolled out` |
| 10:46:10 | `newpods.sh` が終わった | 379 Pod。§4 |
| 10:46:18〜10:46:5x | §4.2 の `snap.sh`・`nodes.sh`・`verify-nodes.sh`・`check-apps.sh`・`dns-check.sh`・`watch.sh logs`（`after`） | §5 |
| 10:47:28〜10:47:48 | ✋ §4.3 の netcheck | PASS 168 / 168 |
| 10:47:54〜10:50:17 | ✋ §4.3 の npcheck | OK 56、not OK 0 |
| 10:50:24 | `watch.sh logs $L/final` | FAIL・OPEN は増えていない |
| 10:50:25〜10:50:44 | ✋ §4.4 の `watch.sh down`、`watch.stop`、トークンのファイルの削除 | 3 つの名前空間とも NotFound |
| 10:51:05 | `nodes.sh final` | §2.2 と同じに戻った |

## 2. `install kubernetes`（runbook §3.2）

`porkadot install kubernetes --node 192.168.1.111`（porkadot 0.37.5、cwd は worktree `cnidaria-0-1-2-prod`）。10:41:41.07Z〜10:42:06.02Z、rc 0。流す前と後で `git status --short assets porkadot.yaml` は空。

- `configured`: **`daemonset.apps/cnidaria`**、DaemonSet `kube-apiserver`（2 回）、PDB `kube-controller-manager`・`kube-scheduler`、ValidatingWebhookConfiguration `metallb-webhook-configuration`。runbook §3.2 の組と同じ
- ServiceAccount・ClusterRole・ClusterRoleBinding `cnidaria`、`deployment.apps/coredns` を含め、ほかは `unchanged`（61 行）
- **`pruned`・`created`・`deleted` の行は無い**

## 3. 入れ替わり（runbook §4.1）

Pod の events と `dswatch.log`（1 秒ごと）から。古い Pod の止まった時刻は `Killing` の event、新しい Pod の Ready は `dswatch.log` で `R` になった最初の行。

| 順 | ノード | 古い Pod（止まった） | 新しい Pod（起動 → Ready） | 古い Pod の停止から Ready まで | readinessProbe の失敗 |
|---|---|---|---|---|---|
| 1 | chirico | `cnidaria-mvnxl` 10:41:59 | `cnidaria-vcnnb` 10:42:00 → 10:42:01 | 2 秒 | 1 回 |
| 2 | braque | `cnidaria-npbh7` 10:42:00 | `cnidaria-pj6nl` 10:42:01 → 10:42:02 | 2 秒 | 1 回 |
| 3 | pablo | `cnidaria-2dtt6` 10:42:02 | `cnidaria-m5vhk` 10:42:03 → 10:42:04 | 2 秒 | 1 回 |
| 4 | 192.168.1.112 | `cnidaria-bs2vm` 10:42:04 | `cnidaria-rd4zt` 10:42:04 → 10:42:05 | 1 秒 | 1 回 |
| 5 | duchamp | `cnidaria-7l94j` 10:42:05 | `cnidaria-h4jf8` 10:42:06 → **10:42:17** | **12 秒** | **2 回** |
| 6 | oeilvert | `cnidaria-s2zpl` 10:42:16 | `cnidaria-7qvrm` 10:42:17 → 10:42:17 | 1 秒 | 1 回 |
| 7 | 192.168.1.113 | `cnidaria-fj6kl` 10:42:17 | `cnidaria-2jmlt` 10:42:18 → 10:42:19 | 2 秒 | 1 回 |
| 8 | 192.168.1.111 | `cnidaria-dz92c` 10:42:18 | `cnidaria-v2lrp` 10:42:19 → 10:42:21 | 3 秒 | 1 回 |

- 8 台で 22 秒（dev の「pull なし」の 8 秒（7 台）より長いのは duchamp の 11 秒のため）。事前 pull が効き、どの Pod も `already present on machine`
- `dswatch.log` の 488 行（10:39:4x〜10:50:43）で `ready=` は 8 が 474 行、7 が 14 行（10:42:00〜10:42:19 の間）。**7 を下回った行は無い**
- readinessProbe の `connection refused` は 8 つの Pod すべてで、起動の同じ秒に 1 回出た（runbook §7.2 のとおり）。duchamp の `cnidaria-h4jf8` だけ 2 回（10:42:06 の event の count が 2）で、Ready まで 11 秒。daemon は起動の時点で table を当て直している（ログの `applied the nftables table`）ので、データプレーンへの影響は見えていない（§4 の duchamp の新しい Pod も 8080 に 1〜2 秒で届いた）
- oeilvert の新しい Pod に `DNSConfigForming`（`Nameserver limits were exceeded`）の warning。段 8 の申し送りの oeilvert の resolv.conf の重複で、以前からのもの

## 4. 監視

| 監視 | サンプル | 結果 |
|---|---|---|
| `cli-a`（pablo。same_a、cross_b・cross_b6、svc、dns、deny9090_a・deny9090_b） | 613 行（10:39:57〜10:50:24） | **FAIL は作った直後の 10:39:57 の 1 行だけ**（same_a・cross_b・cross_b6・svc。許可が効く前）、OPEN 0 |
| `cli-b`（chirico。cross_a・cross_a6、cross_b、svc、dns、deny9090_b） | 621 行（10:39:58〜10:50:23） | **FAIL は作った直後の 10:39:58 の 1 行だけ**、OPEN 0 |
| `cli-deny`（chirico。deny_other_a・deny_other_b） | 621 行 | FAIL 0、**OPEN 0** |
| `probe.log`（VIP の `/readyz`、gated-v4、gated-v6、h2-sshd） | 601 行（10:39:39〜10:50:44） | **FAIL 0**（vip=200、gated4・gated6=404、h2sshd=OK が続いた） |
| `dswatch.log` の Longhorn | 488 行 | すべて `healthy=14 notattached=0`。degraded・faulted は一度も無い |
| `newpods.log` | 379 Pod（10:41:06〜10:46:10。8 台で 47〜48 ずつ） | **すべて Ready、v4 と v6 のアドレスあり、9090 は `BLOCKED`**。`NOTREADY`・`NEVER`・`OPEN`・`RESULT none` は 0 |

`newpods.log` の 8080 に届くまでの秒数:

| | 1 秒 | 2 秒 | 3 秒 |
|---|---|---|---|
| srv-a（pablo） | 170 | 208 | **1** |
| srv-b（.113） | 372 | 7 | 0 |

3 秒の 1 つは `np-chirico-10`（10:42:01 に作成。pablo の cnidaria が 10:42:02〜10:42:04 に入れ替わっていた）。runbook §7.1 の、宛先のノードの cnidaria が入れ替わっている間の許可の遅れ（dev では 3〜5 秒）と同じもの。

## 5. 後の確認（runbook §4.2。10:46:18Z の `snap.sh`、10:46:46Z の `nodes.sh`）

| # | 確認 | 結果 |
|---|---|---|
| 1 | DaemonSet | generation 4（observed 4）、desired・ready・updated・available 8。イメージ `v0.1.2`。`spec` の差はイメージの 1 行だけ |
| 2 | cnidaria の Pod | **8 つとも新しい Pod で、v0.1.2・Ready・restart 0**。古い 8 つは無い。imageID は 8 つとも `ghcr.io/yuanying/cnidaria-cni@sha256:68756535d44a…`（§1.5 の index。runbook の書いた config の ID の形ではなかった。§8）。containerd のイメージ ID は amd64 `497c4354be2dd`、arm64 `726fe8469ab50` |
| 3 | ControllerRevision | revision 5 `74cd464ffc`（10:41:59Z）ができ、新しい Pod の `controller-revision-hash` がそれ。revision 1〜4 は残っている |
| 4 | cnidaria のログ | 新しい 8 つの Pod で 1,287 行、**すべて info**（error 0）。各 Pod に `applied the nftables table` がある。`Reconciler error`・`results may be incomplete` は 0 |
| 5 | `/opt/cni/bin` | 8 台とも `cni-bin.txt` が §2.2 とバイトまで同じ（ctime を含む）。cnidaria のバイナリは無いまま |
| 6 | conflist | 8 台とも `conflist.txt` が §2.2 と同じ |
| 7 | nftables | 6 台は §2.2 と同じ。pablo（265 → 295 行）と .113（110 → 140 行）は `k8u-cni012` の規則と集合（`pods_k8u-cni012/srv-allow-client-8080/v4` など）と、`isolated_ingress_v4`・`v6` への srv-a・srv-b の IP だけが増えた。chain・規則の形は同じ。§4.4 の後は §2.2 と同じに戻った（下の §4.4） |
| 8 | 経路 | `verify-nodes.sh` が PASS 64 / 64、FAIL 0、rc 0。proto 200 は 8 台とも v4 7・v6 7 |
| 9 | 一時的な名前空間の監視 | §4 のとおり。入れ替わりの間（10:41:59〜10:42:21）の行も FAIL 0・OPEN 0 |
| 10 | 新しい Pod | §4 のとおり |
| 11 | ほかの Pod | 全 Pod の比較で、名前・UID・restartCount が変わったのは cnidaria の Pod と `k8u-cni012` の Pod だけ。`gens.tsv` の差は DaemonSet `cnidaria` の 3 → 4 だけ。Pod は 165 個（Running 141、Succeeded 24。`k8u-cni012` の 5 つを含む）、Running / Completed 以外は 0 |
| 12 | kubelet | 8 台の MainPID・NRestarts・ActiveEnterTimestamp が §2.2 と同じ |
| 13 | Longhorn | 14 とも attached・healthy、アタッチ先も同じ（`volumes.tsv` が同じ）。`dswatch.log` に degraded・faulted は無い |
| 14 | LoadBalancer・VIP・NFS・etcd | `probe.log` の FAIL 0。`lb-nfs.txt` が §2.2 と同じ。etcd 3/3 healthy |
| 15 | DNS | `dns-check.sh` の出力が `base/dns-check.txt` と同じ |
| 16 | 健全性 | 8 台 Ready、`check-apps.sh` の duplicates 0、Running / Completed 以外の Pod 0 |

## 6. netcheck と npcheck（runbook §4.3）

- netcheck（`kadmin.sh`。`FRACTION_CHECKOUT` はこの worktree）: `up` 10:47:28Z（8/8 Ready）、`run` が **PASS 168 / 168, pods 8/8**、`down` で `cnidaria-netcheck` を消した
- npcheck（`infra-admin` のトークン）: `up` 10:47:54Z（server・allowed・denied とも 8/8）、`up` の後の `nft` が 8 台とも 9、`run` が **OK 56, not OK 0**、`down` の後の `nft` が 8 台とも 0、`k8u-npcheck` を消した

## 7. 片付け（runbook §4.4）

- 10:50:24Z の `watch.sh logs $L/final`: cli-a 613 行・FAIL 1・OPEN 0、cli-b 621 行・FAIL 1・OPEN 0、cli-deny 621 行・FAIL 0・OPEN 0（FAIL は作った直後の行だけで、`after` から増えていない）
- 10:50:25〜10:50:44Z に `watch.sh down`。`k8u-cni012`・`k8u-npcheck`・`cnidaria-netcheck` の 3 つとも NotFound
- 10:50:44Z に `watch.stop` を置き、`dswatch.sh`・`probe.sh` は 10:50:45Z に止まった（2 つのジョブとも終わった）。`newpods.sh` のジョブは 10:46:10Z に終わっている
- 10:50:44Z に `/tmp/k8u-cni012-admin-token` を消した。トークンはサーバーの側で発行（10:39:54Z）から 1 時間（11:39:54Z）で切れる
- 10:51:05Z の `nodes.sh final`: 8 台とも `nft-<ノード>.txt`・`cni-bin.txt`・`conflist.txt` が §2.2 とバイトまで同じ。host-local の割り当ての数も §2.2 と同じ（.111 6、.112 2、.113 6、braque 2、chirico 78、duchamp 40、oeilvert 43、pablo 28）。kubelet も変わらない。`state.txt` の差は containerd の v0.1.2 のイメージの行だけ

## 8. runbook との差

| 点 | runbook | 実際 | 扱い |
|---|---|---|---|
| 新しい Pod の imageID（§4.2 の 2） | config の ID（amd64 `sha256:497c4354…`、arm64 `sha256:726fe846…`） | 8 つとも index の repo digest `ghcr.io/yuanying/cnidaria-cni@sha256:68756535d44a…`。containerd のイメージ ID は config の ID | どちらも §1.5 の v0.1.2 のもの。runbook を直した。v0.1.1 の Pod の imageID が config の ID の形だった理由は確かめていない |
| readinessProbe の失敗（§4.1・§7.2） | 1 回出て 10 秒以内に Ready | 7 つは 1 回で 0〜2 秒。duchamp の 1 つは 2 回で 11 秒 | 止める条件（2 分）には遠い。runbook §4.1・§7.2 を「1〜2 回、10 秒ほど」に直した |
| `env-fraction.sh` の `FRACTION` | 既定は `worktrees/runbook-cnidaria-0-1-2` | その worktree は #67 の後に片付けてあった | `FRACTION_CHECKOUT` を当日の worktree にして流した。runbook §1.6 に書いた |
| nftables の差（§4.2 の 7、§7.3） | `k8u-cni012/` のコメントの行と集合を除いて比べる | pablo と .113 の `isolated_ingress_v4`・`v6` にも srv-a・srv-b の IP が入った | runbook §7.3 に書いた |

## 9. 申し送り

- etcd のスナップショット `etcd-2026-10-27T10:39:31+00:00.db`（68,919,328 B、sha256 `e25ea637…`）は worktree `cnidaria-0-1-2-prod` の `./backup/` にある。worktree を片付ける前にメインの checkout の `backup/` へ写す（coordinator）
- ノードの containerd に残る v0.1.1（8 台）と v0.1.0（7 台）は runbook §9 のとおり後で片付ける。§6 の戻しは v0.1.1 が残っている間は pull なしでできる
- readinessProbe の `initialDelaySeconds`（runbook §7.2・§9）は範囲の外のまま
