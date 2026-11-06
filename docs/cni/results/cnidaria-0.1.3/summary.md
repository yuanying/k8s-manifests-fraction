# cnidaria v0.1.3 の記録

本番 `fraction` の cnidaria を v0.1.2 から v0.1.3 にした（porkadot 0.37.6 → 0.37.7。`porkadot.yaml` は変えていない。DaemonSet `kube-system/cnidaria` のイメージの 1 行だけが変わる）。手順は `../../runbook-cnidaria-0.1.3.md`（以下 runbook）、前提とベースラインは `baseline.md`。
時刻は UTC。2026-11-06 12:14:13Z の `install kubernetes` から 12:24:06Z の `nodes.sh final` まで。監視のログ（`dswatch.log`、`probe.log`、`newpods.log`）、クライアントのログ、`snap.sh`・`nodes.sh`・`verify-nodes.sh`・`check-apps.sh`・`dns-check.sh`・netcheck・npcheck の出力、`install kubernetes` の出力は、タスクディレクトリの `notes/cnidaria-0-1-3/` に置いた（リポジトリには入れない）。作業は worker（agent）が runbook どおりに流した。

**結果: runbook §4.2 の 16 項目、§4.3、§4.4 はすべて合格した。** 8 台の cnidaria の Pod は 12:14:31〜12:14:52Z（21 秒）に 1 台ずつ v0.1.3 に入れ替わり、8 つとも Ready・restart 0、ログは info だけだった。arm64 の control-plane 3 台でも同じ。既存の Pod 同士の通信・Service・DNS・NetworkPolicy は入れ替わりの間も落ちず（作った直後の 1 行のほか FAIL 0、OPEN 0）、入れ替わりの間を含めて作った 379 個の Pod はすべて Ready になり、許可の 8080 に 1〜2 秒で届き、9090 は止まった。Longhorn の 17 ボリュームは 1 秒ごとの監視で一度も healthy から外れず、LoadBalancer・VIP の監視も落ちなかった。既存の Pod（cnidaria と一時的な名前空間のほか）と 8 台の kubelet は変わっていない。依存の更新（client-go・controller-runtime）による daemon の振る舞いの差は、見た範囲では出ていない。

止まったのは 1 回: §2.5 の etcd のバックアップの大きさが前と桁が違った（`baseline.md` §4）。ユーザーの判断で続けた。runbook と違ったのはほかに 3 点（§8）: chirico の nftables の差（argocd の集合に一時的な Pod の IP が入る）、trivy-operator のスキャンの Pod、pablo の readinessProbe の 2 回の失敗（Ready まで 11 秒）。どれも止める条件には当たらない。

## 1. 流れ

| 時刻 | 何をしたか | 結果 |
|---|---|---|
| 12:07 | §1・§2.2 の前提とベースライン（読み取り） | `baseline.md` §1・§2 |
| 12:08:09〜12:09:04 | ✋ §2.4 のイメージの事前 pull | 8 台 rc 0。`baseline.md` §3 |
| 12:09:22〜12:09:27 | ✋ §2.5 の etcd backup | rc 0。**桁が違うので止めた**。`baseline.md` §4 |
| 12:1x | ユーザーの判断 | 続ける。バックアップは取り直さない |
| 12:12:01 | §2.3 の `dswatch.sh`・`probe.sh` をジョブとして起動 | — |
| 12:12:15〜12:12:23 | ✋ トークンの発行、`watch.sh up`・`watch.sh clients` | `baseline.md` §5 |
| 12:13:32 | `watch.sh logs $L/pre` | 作った直後の 1 行のほか FAIL 0、OPEN 0 |
| 12:13:36 | ✋ `newpods.sh $L 300` をジョブとして起動 | — |
| 12:14:13〜12:14:38 | ✋ §3.2 の `install kubernetes --node 192.168.1.111` | **1 回目で rc 0**（25 秒） |
| 12:14:31〜12:14:52 | §4.1 の入れ替わり | §3 |
| 12:14:52 | `rollout status` | `successfully rolled out` |
| 12:18:41 | `newpods.sh` が終わった | 379 Pod。§4 |
| 12:18:48〜12:19:22 | §4.2 の `snap.sh`・`nodes.sh`・`verify-nodes.sh`・`check-apps.sh`・`dns-check.sh`・`watch.sh logs`（`after`） | §5 |
| 12:20:20〜12:20:39 | ✋ §4.3 の netcheck | PASS 168 / 168 |
| 12:20:46〜12:23:08 | ✋ §4.3 の npcheck | OK 56、not OK 0 |
| 12:23:14 | `watch.sh logs $L/final` | FAIL・OPEN は増えていない |
| 12:23:15〜12:23:37 | ✋ §4.4 の `watch.sh down`、`watch.stop`、トークンのファイルの削除 | 3 つの名前空間とも NotFound |
| 12:24:06 | `nodes.sh final` | §2.2 と同じに戻った |

## 2. `install kubernetes`（runbook §3.2）

`porkadot install kubernetes --node 192.168.1.111`（porkadot 0.37.7、cwd は worktree `cnidaria-0-1-3-prod`）。12:14:13.28Z〜12:14:38.73Z、rc 0。

- `configured`: **`daemonset.apps/cnidaria`**、DaemonSet `kube-apiserver`（2 回）、PDB `kube-controller-manager`・`kube-scheduler`、ValidatingWebhookConfiguration `metallb-webhook-configuration`。runbook §3.2 の組と同じ
- CRD `nodenetworkpolicies.cnidaria.unstable.cloud`、ServiceAccount・ClusterRole・ClusterRoleBinding `cnidaria`、`deployment.apps/coredns` を含め、ほかは `unchanged`（61 行）
- **`pruned`・`created`・`deleted` の行は無い**

## 3. 入れ替わり（runbook §4.1）

Pod の events と `dswatch.log`（1 秒ごと）から。古い Pod の止まった時刻は `Killing` の event、新しい Pod の Ready は `dswatch.log` で `R` になった最初の行。

| 順 | ノード | 古い Pod（止まった） | 新しい Pod（起動 → Ready） | 古い Pod の停止から Ready まで | readinessProbe の失敗 |
|---|---|---|---|---|---|
| 1 | chirico | `cnidaria-vcnnb` 12:14:31 | `cnidaria-88lxb` 12:14:32 → 12:14:34 | 3 秒 | 1 回 |
| 2 | 192.168.1.112 | `cnidaria-rd4zt` 12:14:33 | `cnidaria-6vqg9` 12:14:34 → 12:14:34 | 1 秒 | 1 回 |
| 3 | duchamp | `cnidaria-h4jf8` 12:14:34 | `cnidaria-zcr6z` 12:14:35 → 12:14:36 | 2 秒 | 1 回 |
| 4 | 192.168.1.111 | `cnidaria-v2lrp` 12:14:36 | `cnidaria-zsf62` 12:14:36 → 12:14:36 | 1 秒未満 | 1 回 |
| 5 | pablo | `cnidaria-m5vhk` 12:14:36 | `cnidaria-dlppx` 12:14:37 → **12:14:48** | **12 秒** | **2 回** |
| 6 | braque | `cnidaria-pj6nl` 12:14:47 | `cnidaria-nrpgz` 12:14:48 → 12:14:49 | 2 秒 | 1 回 |
| 7 | oeilvert | `cnidaria-7qvrm` 12:14:49 | `cnidaria-s4k2k` 12:14:49 → 12:14:51 | 2 秒 | 1 回 |
| 8 | 192.168.1.113 | `cnidaria-2jmlt` 12:14:50 | `cnidaria-wc45q` 12:14:51 → 12:14:52 | 2 秒 | 1 回 |

- 8 台で 21 秒（v0.1.2 の本番の 22 秒とほぼ同じ。pablo の 11 秒が多くを占める）。事前 pull が効き、どの Pod も `already present on machine`
- `dswatch.log`（12:12:01〜12:23:38）で `ready=` は 8 が 520 行、7 が 14 行（12:14:33〜12:14:51 の間）。**7 を下回った行は無い**
- readinessProbe の `connection refused` は 8 つの Pod すべてで、起動の同じ秒に出た（runbook §7.2 のとおり）。pablo の `cnidaria-dlppx` だけ 2 回（event の count が 2）で、Ready まで 11 秒。v0.1.2 の本番の duchamp と同じ形。daemon は起動の時点で table を当て直している（ログの `applied the nftables table`）
- oeilvert の新しい Pod に `DNSConfigForming`（`Nameserver limits were exceeded`）の warning。以前からのもの（v0.1.2 の記録 §3）

## 4. 監視

| 監視 | サンプル | 結果 |
|---|---|---|
| `cli-a`（pablo。same_a、cross_b・cross_b6、svc、dns、deny9090_a・deny9090_b） | 637 行（12:12:22〜12:23:13） | **FAIL は作った直後の 12:12:22 の 1 行だけ**（same_a・cross_b・cross_b6・svc。許可が効く前）、OPEN 0 |
| `cli-b`（chirico。cross_a・cross_a6、cross_b、svc、dns、deny9090_b） | 645 行（12:12:23〜12:23:13） | **FAIL は作った直後の 12:12:23 の 1 行だけ**、OPEN 0 |
| `cli-deny`（chirico。deny_other_a・deny_other_b） | 646 行 | FAIL 0、**OPEN 0** |
| `probe.log`（VIP の `/readyz`、gated-v4、gated-v6、h2-sshd） | 12:12:01〜12:23:37 | **FAIL 0**（vip=200、gated4・gated6=404、h2sshd=OK が続いた） |
| `dswatch.log` の Longhorn | 12:12:01〜12:23:38 | すべて `healthy=17 notattached=0`。degraded・faulted は一度も無い |
| `newpods.log` | 379 Pod（12:13:36〜12:18:41。8 台で 47〜48 ずつ） | **すべて Ready、v4 と v6 のアドレスあり、9090 は `BLOCKED`**。`NOTREADY`・`NEVER`・`OPEN`・`RESULT none` は 0 |

`newpods.log` の 8080 に届くまでの秒数:

| | 1 秒 | 2 秒 | 3 秒以上 |
|---|---|---|---|
| srv-a（pablo） | 186 | 193 | 0 |
| srv-b（.113） | 375 | 4 | 0 |

v0.1.2 の本番にあった 3 秒（宛先のノードの cnidaria の入れ替わり中に作られた Pod。runbook §7.1）は、今回は出なかった。srv-b の 2 秒の 4 つは、.113 の入れ替わり（12:14:50〜52）と重ならない時刻（12:14:09、12:14:21 の 2 つ、12:14:47）のもの。

## 5. 後の確認（runbook §4.2。12:18:48Z の `snap.sh`、12:19:16Z の `nodes.sh`）

| # | 確認 | 結果 |
|---|---|---|
| 1 | DaemonSet | generation 5（observed 5）、desired・ready・updated・available 8。イメージ `v0.1.3`。`spec` の差はイメージの 1 行だけ |
| 2 | cnidaria の Pod | **8 つとも新しい Pod で、v0.1.3・Ready・restart 0**。古い 8 つは無い。imageID は 8 つとも `ghcr.io/yuanying/cnidaria-cni@sha256:f77ec3210c82…`（§1.5 の index）。containerd のイメージ ID は amd64 `bc8ccf387a771`、arm64 `6320de424020c` |
| 3 | ControllerRevision | revision 6 `f78d6c684`（12:14:31Z）ができ、新しい Pod の `controller-revision-hash` がそれ。revision 1〜5 は残っている |
| 4 | cnidaria のログ | 新しい 8 つの Pod で 1,985 行、**すべて info**（error 0）。各 Pod に `applied the nftables table` がある |
| 5 | `/opt/cni/bin` | 8 台とも `cni-bin.txt` が §2.2 とバイトまで同じ（ctime を含む）。cnidaria のバイナリは無いまま |
| 6 | conflist | 8 台とも `conflist.txt` が §2.2 と同じ |
| 7 | nftables | 5 台は §2.2 と同じ。pablo（265 → 295 行）と .113（110 → 140 行）は `k8u-cni013` の規則と集合と、`isolated_ingress_v4`・`v6` への srv-a・srv-b の IP だけが増えた（v0.1.2 の本番と同じ行の数）。**chirico（1017 → 1038 行）は、argocd の NetworkPolicy の集合に `k8u-cni013` の 5 つの Pod の IP（v4 と v6）が入っただけ**（全名前空間を選ぶ peer の集合。§8）。3 台とも chain・規則の形は同じ。§4.4 の後は §2.2 と同じに戻った |
| 8 | 経路 | `verify-nodes.sh` が PASS 64 / 64、FAIL 0、rc 0。proto 200 は 8 台とも v4 7・v6 7 |
| 9 | 一時的な名前空間の監視 | §4 のとおり。入れ替わりの間（12:14:31〜12:14:52）の行も FAIL 0・OPEN 0 |
| 10 | 新しい Pod | §4 のとおり |
| 11 | ほかの Pod | 全 Pod の比較で、既存の Pod の名前・UID・restartCount が変わったのは cnidaria の Pod だけ。増えたのは `k8u-cni013` の 5 つと、`trivy-system` の `scan-vulnerabilityreport-…` の 1 つ（trivy-operator のスキャンの Job の Pod。`k8u-cni013` の Pod の VulnerabilityReport が 12:12〜12:19Z にできており、その後に消えた。§8）。`gens.tsv` の差は DaemonSet `cnidaria` の 4 → 5 だけ。Pod は 182 個（Running 151、Succeeded 31）、Running / Completed 以外は 0 |
| 12 | kubelet | 8 台の MainPID・NRestarts・ActiveEnterTimestamp が §2.2 と同じ |
| 13 | Longhorn | 17 とも attached・healthy、アタッチ先も同じ（`volumes.tsv` が同じ）。`dswatch.log` に degraded・faulted は無い |
| 14 | LoadBalancer・VIP・NFS・etcd | `probe.log` の FAIL 0。`lb-nfs.txt`・`lb-svc.txt` が §2.2 と同じ。etcd 3/3 healthy |
| 15 | DNS | `dns-check.sh` の出力が `base/dns-check.txt` と同じ |
| 16 | 健全性 | 8 台 Ready、`check-apps.sh` の duplicates 0、Running / Completed 以外の Pod 0 |

## 6. netcheck と npcheck（runbook §4.3）

- netcheck（`kadmin.sh`。`FRACTION` はこの worktree）: `up` 12:20:20Z（8/8 Ready）、`run` が **PASS 168 / 168, pods 8/8**、`down` で `cnidaria-netcheck` を消した
- npcheck（`infra-admin` のトークン）: `up` 12:20:46Z（server・allowed・denied とも 8/8）、`up` の後の `nft` が 8 台とも 9、`run` が **OK 56, not OK 0**、`down` の後の `nft` が 8 台とも 0、`k8u-npcheck` を消した

## 7. 片付け（runbook §4.4）

- 12:23:14Z の `watch.sh logs $L/final`: cli-a 637 行・FAIL 1・OPEN 0、cli-b 645 行・FAIL 1・OPEN 0、cli-deny 646 行・FAIL 0・OPEN 0（FAIL は作った直後の行だけで、`after` から増えていない）
- 12:23:15〜12:23:36Z に `watch.sh down`。`k8u-cni013`・`k8u-npcheck`・`cnidaria-netcheck` の 3 つとも NotFound
- 12:23:37Z に `watch.stop` を置き、`dswatch.sh`・`probe.sh` は 12:23:37〜38Z に止まった（2 つのジョブとも終わった）。`newpods.sh` のジョブは 12:18:41Z に終わっている
- 12:23:37Z に `/tmp/k8u-cni013-admin-token` を消した。トークンはサーバーの側で発行（12:12:15Z）から 1 時間（13:12:15Z）で切れる
- 12:24:06Z の `nodes.sh final`: 8 台とも `nft-<ノード>.txt`・`cni-bin.txt`・`conflist.txt` が §2.2 とバイトまで同じ。host-local の割り当ての数も §2.2 と同じ（.111 6、.112 6、.113 2、braque 2、chirico 90、duchamp 36、oeilvert 53、pablo 28）。kubelet も変わらない。`state.txt` の差は containerd の v0.1.3 のイメージの行（と行の順）だけ

## 8. runbook との差

| 点 | runbook | 実際 | 扱い |
|---|---|---|---|
| etcd のバックアップの大きさ（§2.5） | 前のもの（74,612,768 B）と桁が違えば止める | 125,042,720 B で桁が違った。etcd の DB SIZE 121〜125 MB、IN USE 40 MB | 止めて報告し、ユーザーの判断で続けた（`baseline.md` §4）。runbook §2.5 を、`etcdctl endpoint status` の DB SIZE と比べる形に直した |
| nftables の差（§4.2 の 7、§7.3） | `k8u-cni013` の差は pablo と .113 だけ | chirico の argocd の NetworkPolicy の peer の集合にも `k8u-cni013` の Pod の IP が入った（1017 → 1038 行。v0.1.2 の本番では argocd の NetworkPolicy が無かった） | 構造は同じで、§4.4 の後に元に戻った。runbook §7.3 に書いた |
| ほかの Pod（§4.2 の 11） | 変わるのは cnidaria と `k8u-cni013` の Pod だけ | trivy-operator のスキャンの Pod が 1 つ増えていた（一時的な Pod のイメージのスキャン） | 既存の Pod は変わっていない。runbook §4.2 の 11 に書いた |
| readinessProbe の失敗（§4.1・§7.2） | 1〜2 回、Ready まで 0〜11 秒 | 7 つは 1 回で 0〜2 秒。pablo の 1 つは 2 回で 11 秒 | runbook のとおり。直していない |

## 9. 申し送り

- etcd のスナップショット `etcd-2026-11-06T12:09:23+00:00.db`（125,042,720 B、sha256 `f671b56b…`）は worktree `cnidaria-0-1-3-prod` の `./backup/` にある。worktree を片付ける前にメインの checkout の `backup/` へ写す（coordinator）
- etcd の DB の 67〜69% が使われていないページ（`baseline.md` §4）。defrag するかは別件
- ノードの containerd に残る v0.1.1 と v0.1.2（8 台）は runbook §9 のとおり後で片付ける。§6 の戻しは v0.1.2 が残っている間は pull なしでできる
- readinessProbe の `initialDelaySeconds`（runbook §7.2・§9）は範囲の外のまま
