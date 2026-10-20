# control-plane のマニフェストの段 5 の作業記録（`install kubernetes`）

kube-apiserver・kube-controller-manager・kube-scheduler・kube-proxy を、porkadot 0.34.1 の `install kubernetes --node 192.168.1.111` で v1.33.13 から v1.34.12 に上げ、1.33 の apiserver が v1beta1 で保存した IPAddress と ServiceCIDR を v1 に書き直した記録。続けて取った 2 つ目の etcd のバックアップ（runbook §4.2 の 1）もここに書く。手順は `../../runbook-stage-5.md`（以下 runbook）。
時刻は UTC。ベースラインは `baseline.md`。読み取りの出力はタスクディレクトリの `notes/stage-5/cp/`（`install kubernetes` の出力と直後の読み取り）、`notes/stage-5/sv-after-install*/`（storage version）、`notes/stage-5/pre-cp/`（2 つ目のバックアップの直後の読み取り）。

## 1. 事前の読み取り（2026-10-20 09:10Z〜）

runbook §3.1 の項目:

| 項目 | 結果 |
|---|---|
| ベースライン、段の前のバックアップ、v2store の確認 | `baseline.md` のとおり済み。v2store は 3 台とも合格 |
| 監視（runbook §2.3） | 08:45:03Z から動いている。FAIL 0 |
| storage version | `OLD: 0`（`baseline.md` §2 の 20） |
| Node、etcd、VIP | 8 台 Ready、全台 v1.33.13。etcd 3/3 healthy。VIP の `/readyz` は `ok` |
| Running / Completed 以外の Pod | 0 個 |
| checkout | worktree（`stage-5-k8s-1-34`、base は PR #40 をマージした master の `deef235`。足したのは記録だけ）。`git status --short assets porkadot.yaml` は前も後も空 |
| porkadot、SSH | `git -C $P describe --tags` は `v0.34.1`。8 台とも SSH が通る（`baseline.md` §1） |

## 2. etcd のリーダー

`install kubernetes` では etcd に触らない（リーダーは .113 のまま）。

## 3. `install kubernetes`（runbook §3.2）

- 開始 09:11:14Z、終わり 09:14:19Z、**rc 0（1 回目で通った）**。サンドボックスの中で流した。出力はタスクディレクトリの `notes/stage-5/cp/install-kubernetes.log`
- 1 段目: CRD を apply し（`condition met`）、`service/porkadot-kubernetes-latest configured`、`daemonset.apps/kube-apiserver configured`。続けて `daemon set "kube-apiserver" successfully rolled out`（ログに時刻は無い。Pod の Ready から 09:14:03Z ごろ）
- apiserver の入れ替え（Pod の作成と Ready）: .112 `-srsxs` 09:11:59Z → 09:12:20Z、.113 `-5sgvj` 09:12:50Z → 09:13:11Z、.111 `-56jg7` 09:13:42Z → 09:14:03Z。1 台約 50 秒、3 台で約 2 分 10 秒
- 2 段目（全体の apply）: `configured` は `serviceaccount/kube-controller-manager`・`kube-proxy`・`kube-scheduler`、`clusterrolebinding…/porkadot:kube-controller-manager`・`porkadot:kube-scheduler`・`porkadot:node-proxier`・`porkadot:volume-scheduler`、`configmap/kube-proxy`、`deployment.apps/kube-controller-manager`・`kube-scheduler`、`poddisruptionbudget.policy/kube-controller-manager`・`kube-scheduler`、`daemonset.apps/kube-apiserver`・`kube-proxy`、`validatingwebhookconfiguration…/metallb-webhook-configuration`。Deployment と DaemonSet のほかは、どれも `app.kubernetes.io/version` のラベルが変わったもの（runbook §2.6 の 23 行）か、前から `configured` に出るもの（PDB と MetalLB の webhook）。CoreDNS・approver・cnidaria・MetalLB の Deployment と DaemonSet は `unchanged`
- KCM と scheduler の新しい Pod は 09:14:11Z（.112 の KCM、.111 の scheduler）と 09:14:31Z（.111 の KCM、.113 の scheduler）に作られ、09:14:52Z にすべて Ready。kube-proxy は 09:14:11Z〜09:14:41Z に 8 台を入れ替えた
- 09:15:09Z に 4 つの `rollout status` がすべて `successfully rolled out`。`kubectl --context fraction version` の Server Version は v1.34.12

## 4. 確認（runbook §3.3。09:15Z〜09:16Z）

| # | 確認 | 結果 |
|---|---|---|
| 1〜12 | 段 1 の手順書 §3.3 の 1〜12 | Server v1.34.12。DaemonSet `kube-apiserver` は generation 27 → 28、`kube-proxy` 23 → 24、Deployment `kube-controller-manager` 26 → 27、`kube-scheduler` 25 → 26、どれも v1.34.12。Node は 8 台 Ready で kubelet は v1.33.13 のまま。etcd は 3/3 healthy、3.5.34 のまま、リーダーは .113 のまま。VIP の `/readyz` は `ok`、`/version` は v1.34.12。Running / Completed 以外の Pod は 0。controller-manager は .111（`-cs97f`）と .112（`-gz9wf`、リーダー）、scheduler は .111（`-xkbzx`）と .113（`-mmpr7`、リーダー）。**4 つの Pod のログに `Failed to watch` は 0 行、`E` で始まる行も 0 行** |
| 13 | CoreDNS | 動かない。generation 11 のまま、2/2、`coredns:v1.12.4`。名前の答えはベースラインと同じ（`www.google.com` の A の並びだけが違う） |
| 14 | approver | `kubelet-serving-cert-approver-7d5f768656-hls26` が 1/1 のまま、generation も変わらない |
| 15 | CSR | 無い |
| 16 | storage version | `prefixes: 65, keys: 2375, OLD: 75, CRDs with more than one stored version: 0`。`overrides.tsv` は空。`OLD` は `/registry/ipaddresses/` 74 と **`/registry/servicecidrs/` 1**（どちらも `networking.k8s.io/v1beta1`）。ほかの `OLD` と CRD の `MULTI` は無い。**ServiceCIDR は 1.34 の apiserver が自分で v1 に書き直さなかった**（dev とは違う。runbook §3.3 の 16 のとおり §3.4 で一緒に書き直した） |
| 17 | ServiceCIDR と IPAddress | `servicecidrs` は `kubernetes` の 1 つで Ready、CIDRS は `10.254.0.0/24,fd20:afc2:7c09::/108`。IPAddress は 74（ClusterIP の数と同じ）。`ClusterIPNotAllocated` の event は無い |
| 18 | v1 Endpoints の warning | `apiserver_requested_deprecated_apis` は `endpoints`（v1）と `metallb.io/v1beta1 addresspools` で、`removed_release` は空。1.34 以前に消える API は出ていない |
| 19 | FlowSchema | **`endpoint-controller` と `workload-leader-election` が消えた**（13 個 → 11 個）。ほかの 11 個の generation は変わらない（`system-leader-election` 8、ほかは 1）。下の注 |

- **FlowSchema の 2 つが消えたのは 1.34 の apiserver の既定の変更**: v1.34.12 の `staging/src/k8s.io/apiserver/pkg/apis/flowcontrol/bootstrap/default.go` の `SuggestedFlowSchemas` には `endpoint-controller` と `workload-leader-election` が無い（v1.33.13 にはある）。apiserver は、`apf.kubernetes.io/autoupdate-spec: "true"` の付いた suggested のオブジェクトで、自分の一覧に無いものを消す。dev でも FlowSchema が 13 → 11 になっていた（dev の記録の storage version の表）。runbook は「generation が増える」と書いていたので直した（§6）
- `/registry/` のキーは 2200 → 2375 で、増えたのは events（9 → 172。apiserver の入れ替えの Readiness probe の失敗など）、controllerrevisions（+6）、clusterroles・clusterrolebindings・serviceaccounts（+2 ずつ）、apiservices（+1）、pods（+1、下の `fs/data-backup`）。FlowSchema は −2。`resource.k8s.io` は `v1` だけを返す
- Warning のイベント: 3 台の旧い kube-apiserver の Pod の `Readiness probe failed … connection refused`（止まるときのもの。想定内）と、下の `movies` の 2 つ
- 全 Pod の UID・restartCount（`baseline/pods.tsv` と比べた）: 変わったのは、`install kubernetes` で作り直された apiserver 3・KCM 2・scheduler 2・kube-proxy 8 と、次の 3 つ
  - `carib2/movies-78dc5856b6-msfk2` と `shja2/movies-69bf4c594c-tmcwz`（どちらも oeilvert）の restartCount 7 → 8。前のコンテナは 06:07Z・06:09Z に起動し、09:07:05Z（exit 2、liveness の失敗）と 09:09:05Z（OOMKilled）に終わった。**`install kubernetes` の前**で、作業が触っていない worker の上のもの。約 3 時間ごとに再起動している形（restartCount 7 は約 24 時間の Pod の年齢と合う）。段 5 の作業とは関係が無い
  - `fs/data-backup-29874783-p89zb`（CronJob `fs/data-backup` の 09:03Z の Job、duchamp、Completed）。ボリュームは NFS だけで、runbook §8.12 には当たらない

## 5. IPAddress と ServiceCIDR の書き直し（runbook §3.4）

| 項目 | 結果 |
|---|---|
| 書き直す前 | `OLD: 75`（`/registry/ipaddresses/` 74、`/registry/servicecidrs/` 1。どちらも `networking.k8s.io/v1beta1`）。ほかの `OLD` は無い |
| トークン | 09:18Z に `infra-admin` の 1 時間のトークンを発行（`/tmp/k8u-stage5-admin-token`）。`auth can-i replace ipaddresses`・`update servicecidrs` が yes |
| dry-run | 09:18:36Z。IPAddress は `replaced (server dry run)` が 74、エラー 0。ServiceCIDR は 1 |
| 書き直し | 09:18:45Z〜09:18:46Z。IPAddress は `replaced` が 74、rc 0。**衝突（`the object has been modified`）・`NotFound` は 0**。続けて ServiceCIDR `kubernetes` を同じ形で `replaced` |
| 書き直した後 | `prefixes: 65, keys: 2375, OLD: 0, CRDs with more than one stored version: 0`。`/registry/ipaddresses/` 74 と `/registry/servicecidrs/` 1 が `networking.k8s.io/v1` の `ok` |
| 名前・generation・`parentRef` | `ip-before.txt` と `ip-after.txt` で同じ（resourceVersion だけが変わった）。ServiceCIDR は Ready のまま |
| ClusterIP の割り当て | `ClusterIPNotAllocated` の event は無い |
| VIP と監視 | `/readyz` は `ok`。書き直しの間に監視の FAIL は無い |
| トークンの破棄 | 09:19Z にファイルを消した（変数は書き直しを流したシェルの中だけ） |

出力（キー・版・名前だけで値は無い）はタスクディレクトリの `notes/stage-5/sv-after-install/`（`ip-before.txt`、`ip-after.txt`、`ip-dryrun.txt`、`ip-replace.txt`、`sc-before.txt`、`sc-replace.txt`）と `sv-after-install-after/`。

## 6. 2 つ目の etcd のバックアップ（runbook §4.2 の 1）

| 項目 | 値 |
|---|---|
| コマンド | `porkadot etcd backup --config ./porkadot.yaml`（porkadot 0.34.1、etcdctl 3.5.34。サンドボックスの中で 09:20:45Z〜09:20:48Z、rc 0、6 つとも `successful`） |
| 取ったメンバー | 192.168.1.111 |
| ファイル | `etcd-2026-10-20T09:20:45+00:00.db`、モード 0600、55,107,616 バイト（段の前のものと同じサイズ） |
| sha256 | `e70a304290fde754721d8c43ed9633ebe322343f56e9f7e1661b7b1b5f76a10f` |
| 置き場所 | 段 5 の worktree の `./backup/`（git には入れていない）。片付けの前に coordinator がメインの checkout の `backup/` へ移す |
| 中身 | 1.34 の control-plane、IPAddress と ServiceCIDR は v1、etcd 3.5 の最後の状態。runbook §7.4 の restore で、段の前のもの（`etcd-2026-10-20T09:08:38+00:00.db`）の代わりに使える |

直後の読み取り（09:21:00Z。`notes/stage-5/pre-cp/`）: 8 台 Ready（kubelet は v1.33.13）、etcd 3/3 が 3.5.34（cluster version 3.5.0）、raft term 23120・index 1403115686 でそろう、`header.revision` 1,237,789,675、VIP の `/readyz` は `ok`、Running / Completed 以外の Pod は 0、Pod の UID・restartCount は §4 の後から変わらない、Longhorn は attached healthy 16 と detached 1、`check-apps.sh` は合格、Prometheus の `up == 0` は 0。VIP の告知は pablo のまま（09:14:03Z に pablo でもう一度 `serviceAnnounced`）。

## 7. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因 |
|---|---|---|
| 09:11:30Z | VIP | .112 の kube-apiserver の入れ替え（古い Pod の停止から新しい Pod の Ready まで） |
| 09:12:21Z | VIP | .113 の kube-apiserver の入れ替え |

LB（`192.168.1.200`）の FAIL は 0。dev（2 サンプル 000）と同じ程度。

## 8. 手順書との差、気づいたこと

- **FlowSchema**: runbook §2.5 と §3.3 の 19、§7.2 は「1.34 の apiserver が `endpoint-controller`・`workload-leader-election` を書き直し、generation が増える」と書いていたが、実際には 1.34 の apiserver が 2 つとも消した（§4 の注）。runbook を直した。1.33 に戻すと、1.33 の apiserver が suggested の 2 つを作り直す見込み
- **ServiceCIDR**: 1.34 の apiserver は自分で v1 に書き直さなかった（dev では書き直した）。runbook §3.3 の 16 の想定の範囲で、§3.4 で一緒に書き直した。runbook の「書き直す見込み」の書き方を直した
- `install kubernetes` は 1 回目で rc 0（段 4 の本番の `connection refused` は起きなかった）
