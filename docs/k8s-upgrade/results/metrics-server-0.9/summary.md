# metrics-server v0.9.0 の記録

本番 `fraction` の metrics-server を `registry.k8s.io/metrics-server/metrics-server:v0.7.2` から `v0.9.0` へ上げた（fleet-infra#203 `baecff7` の render を `infra-admin` の短命トークンで client-side apply）。手順は `../../runbook-metrics-server-0.9.md`（以下 runbook）、前提とベースラインは `baseline.md`。
時刻は UTC。2026-10-25 11:31:31Z のベースラインから 11:38:45Z の監視の停止まで。監視のログ、`snap.sh`・`node-state.sh` の出力、`diff.txt`・`dry-run.txt`・`apply.txt` は、タスクディレクトリの `notes/metrics-server-0-9/` に置いた（リポジトリには入れない）。

**結果: runbook §4.2 の 15 項目と §4.3 は合格した。** 新しい Pod は oeilvert で作成から 23 秒で Ready になり、同じ秒に古い Pod が止まった。1 秒ごとの監視（292 サンプル）は `kubectl top nodes` も APIService も 1 度も落ちなかった。**ただし apiserver のログで、古い Pod が止まった瞬間に APIService が約 70 ms だけ `False` になって戻ったのが見えた**（§3.2。dev では出なかった。coordinator の判断で許容し、runbook §4.2 の 8 の基準を直した）。metrics-server 以外の Pod と 8 台の kubelet は変わっていない。

## 1. 流れ

| 時刻 | 何をしたか | 結果 |
|---|---|---|
| 11:30〜11:31:43 | §1・§2.2 の前提とベースライン（読み取り） | `baseline.md` |
| 11:31:5x | §2.3 の監視（`top-watch.sh`）をジョブとして起動 | — |
| 11:32:09 | §1.2 の `infra-admin` のトークンの発行（1 時間） | `can-i patch` が `yes` |
| 11:32:13 | §2.6 の `diff` と `--dry-run=server` | `baseline.md` §4 |
| 11:33:18 | §3.1 の事前確認 | 8 台 Ready、metrics-server 1/1、監視の最後の行が 1 秒前で FAIL 0、`sha256sum -c` OK、トークンが `yes` |
| 11:33:28.3〜11:33:28.8 | ✋ §3.2 の `kubectl apply -f v0.9.0.yaml` | **1 回目で rc 0** |
| 11:33:28〜11:33:51 | §4.1 の入れ替わり | §3 |
| 11:33:51 | `rollout status` | `successfully rolled out` |
| 11:34:50〜11:35:02 | §4.2 の `snap.sh`・`node-state.sh`（`after`）、`lastapplied-diff.sh` | §4 |
| 11:38:39 | §4.3 の 5 分後のログと `top` | §4 |
| 11:38:45 | 監視を止め（`watch.stop`）、トークンを破棄 | §5 |

作業の全体は §2.7 の時間帯に重なっていない。

## 2. `kubectl apply`（runbook §3.2）

`kubectl --context fraction --token=<infra-admin> apply -f docs/k8s-upgrade/render/metrics-server-0.9/v0.9.0.yaml`（checkout は worktree `metrics-server-prod`、base は PR #58 をマージした master の `d872755`。render は sha256 で照合済み）。11:33:28.277Z〜11:33:28.778Z、rc 0。

- `configured`: **`service/metrics-server`、`deployment.apps/metrics-server`**
- `unchanged`: ServiceAccount、ClusterRole 2、RoleBinding、ClusterRoleBinding 2、APIService の 7 つ
- `created` は無い。dev・dry-run と同じ組

## 3. 入れ替わり（runbook §4.1）

events、Pod の conditions、`top-watch.log`（約 1.4 秒ごと）から。

| 時刻 | できごと |
|---|---|
| 11:33:28 | ReplicaSet `metrics-server-6bcd67b6cf` を 0 → 1。Pod `metrics-server-6bcd67b6cf-ncdf8` を作り、**oeilvert** に割り当て |
| 11:33:29〜11:33:30 | v0.9.0 の pull（1.406 s、23,258,428 B）、コンテナの作成・起動（11:33:30） |
| 11:33:31 | metrics-server の起動のログ（`Serving securely on [::]:10250`、caches synced） |
| 11:33:51 | 新しい Pod が Ready（起動から約 21 秒。`initialDelaySeconds: 20` で決まる）。同じ秒に古い Pod `metrics-server-75bf97fcc9-6t94q`（chirico）の `Killing`、`75bf97fcc9` を 1 → 0 |
| 11:33:53 | `top-watch.log` から古い Pod が消えた（11:33:51.791 の行で `Succeeded`） |

- apply から rollout の完了まで 23 秒（dev と同じ）。2 分の止める条件に近づくことは無かった

### 3.1 監視の途切れ

| 監視 | サンプル | FAIL |
|---|---|---|
| `top-watch.log`（`top nodes`、APIService、Pod。11:32:01〜11:38:44） | 292 | **0** |

apply から §4.3 の終わりまで（11:33:28〜11:38:40）は 225 サンプルで、すべて `top=OK n=8 apiservice=True:Passed`。サンプルの間隔は最大 1.5 秒。

### 3.2 古い Pod の終了の瞬間の APIService の `False`（runbook と違ったこと）

apiserver 3 つのログ（`notes/metrics-server-0-9/after/apiserver-metrics.log`）に、古い Pod が止まった瞬間の次の行があった。

| 時刻 | apiserver | 行 |
|---|---|---|
| 11:33:51.622 | `kube-apiserver-djbxn` | `"changing APIService availability" … oldStatus="True" newStatus="False" message="failing or missing response from https://10.254.0.133:443/apis/metrics.k8s.io/v1beta1: … dial tcp 10.254.0.133:443: connect: connection refused" reason="FailedDiscoveryCheck"` |
| 11:33:51.630〜.633 | 3 つとも | `Error updating APIService "v1beta1.metrics.k8s.io" with err: failed to download v1beta1.metrics.k8s.io: failed to retrieve openAPI spec, http error: ResponseCode: 503, Body: service unavailable` |
| 11:33:51.691〜.693 | 3 つとも | `"changing APIService availability" … oldStatus="False" newStatus="True" message="all checks passed" reason="Passed"` |
| 11:33:51.699〜.701 | 2 つ | `Operation cannot be fulfilled on apiservices … the object has been modified`（status の同時の書き込みの競合） |

- `False` だったのは約 70 ms で、1 秒ごとの監視（11:33:50.363 と 11:33:51.791 のサンプルはどちらも `True:Passed`）にも `kubectl top` にも映っていない。APIService の `lastTransitionTime` が 11:33:51Z に変わり、resourceVersion が `1238973626` → `1239911117` になったのはこのため
- 11:33:52Z から 11:38:4xZ まで、apiserver のログに `metrics.k8s.io`・`metrics-server` を含む行は無い（繰り返していない）
- **dev では出なかった**（dev の上げ（10:58Z）の後の apiserver のログに同じ行は無い。dev の記録の 10:57:24Z の `FailedDiscoveryCheck` と 503 は v0.7.2 を入れたときのもの）
- 原因は、古い Pod の終了（10250 を閉じる）と Service の endpoints の切り替え（kube-proxy の iptables の書き換え）の順のずれで、切り替わる前の ClusterIP への接続が古い Pod に届いて拒まれたとみられる（**推測**。確かめていない）
- runbook §6 の止める条件には当たらない。coordinator に報告し、ユーザーの方針（短時間の障害は許容）の範囲として進めてよいとの判断を得た。runbook §4.2 の 8 の基準を直し、§6 に「繰り返す・1 秒を超えて続く」を足し、§8.4 に書いた（この PR）

## 4. 確認（runbook §4.2、§4.3）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Deployment | generation 1 → **2**（observedGeneration 2）、revision 1 → **2**。1/1、updated 1。テンプレートのイメージが `registry.k8s.io/metrics-server/metrics-server:v0.9.0`。Pod のテンプレートの spec はイメージを除いてベースラインと同じ（引数・probe・securityContext・resources・nodeSelector・priorityClass）、strategy も同じ |
| 2 | Pod | **1 つだけ。`metrics-server-6bcd67b6cf-ncdf8`（UID `a627c391-7c4b-4755-9d2b-5faf02c5efca`）、v0.9.0 で Running、Ready、restart 0**、2026-10-25 11:33:28Z 作成、Pod IP `10.244.7.27`。`imageID` は `registry.k8s.io/metrics-server/metrics-server@sha256:d9862115e7c7881280d3d75ca26bda8ffc0fc213315979575bf23ce9826205c0`（§1.5 の index の digest と同じ）。古い Pod は無い |
| 3 | 配置 | **oeilvert**（taint の無い worker。control-plane と braque には無い） |
| 4 | ReplicaSet | `metrics-server-6bcd67b6cf` が 1/1（v0.9.0）。`75bf97fcc9` は 0 で残る |
| 5 | Service・EndpointSlice | Service の port に `appProtocol: https`、ClusterIP `10.254.0.133`、443 → `https` は同じ（resourceVersion `1235922531` → `1239910962`）。EndpointSlice `metrics-server-hkw72` の endpoint は `10.244.7.27` だけ、port 10250 に `appProtocol: https` |
| 6 | APIService | Available `True`（`Passed`）。spec はベースラインと同じ。resourceVersion と `lastTransitionTime`（11:33:51Z）が変わったのは §3.2 の status の書き換え |
| 7 | ログ | 11:33:31Z の起動の `I` の 14 行だけ（`Generated self-signed cert`、`Adding GroupVersion metrics.k8s.io v1beta1`、`Serving securely on [::]:10250`、`Caches are synced`）。**`E` の行、`x509`、`Failed to scrape node`、`unable to fetch`、`Forbidden` は無い** |
| 8 | apiserver のログ | §3.2 の 11:33:51Z の 1 回（約 70 ms）だけ。その後は無い。直した基準で合格 |
| 9 | `kubectl top` | 11:34:50Z に `top nodes` が 8 台、`top pods -A` が 145 行（Running の Pod の数と同じ） |
| 10 | RBAC と last-applied | `lastapplied-diff.sh v0.9.0.yaml` が 9 つとも `SAME`。RBAC の 6 つの resourceVersion がベースラインと同じ |
| 11 | ほかの Pod | metrics-server の Pod を除いた全 Pod の名前・UID・restartCount・phase がベースラインと同じ。168 個（Running 145、Succeeded 23）で、Running / Completed 以外は 0 |
| 12 | kubelet | 8 台の MainPID・NRestarts・ActiveEnterTimestamp と serving 証明書がベースラインと同じ。containerd のイメージは oeilvert に v0.9.0（`d7b01abacd67f`、23.3 MB）が増えただけ |
| 13 | 監視の FAIL | §3.1。0 |
| 14 | HPA | 0 個のまま |
| 15 | 健全性 | 8 台 Ready、`https://192.168.1.101:6443/readyz` が 200（11:35Z） |

**§4.3 の 5 分後の見直し**: 新しい Pod の起動（11:33:30）から約 5 分後の 11:38:39Z に、ログは起動の 14 行のままで `I` 以外の行と `x509`・scrape の失敗は無い。`top nodes` は 8 台、`top pods -A` は 145 行、Pod は 1/1 Running restart 0、APIService は `True`。合格。

## 5. 片付けと、残したこと

- 監視は 11:38:45Z に止めた（ジョブが終わった）
- `infra-admin` のトークンは 11:38:45Z に破棄した（`/tmp/ms-upg-admin-token` を消し、変数も残していない。期限は 12:32Z）。トークンは記録・git・タスクディレクトリに置いていない
- etcd のバックアップは取っていない（runbook §2.4）
- runbook §10 の片付けの対象（古い ReplicaSet `metrics-server-75bf97fcc9`、ノードの v0.7.2 のイメージ（chirico・duchamp・oeilvert）、private の `metrics-server/`）には触っていない

## 6. 手順書との差

- **§3.2 の APIService の `False`**（上）。runbook §4.2 の 8、§6、§8.4 を直した
- **§2.6 の diff に last-applied の注釈は出ない**（`baseline.md` §4）。runbook §2.6 を直した
- fleet-infra の main は runbook を書いたときの `ebe7cc9` から `9a08fb9` に進んでいた（Renovate の #43・#45）。`infrastructure/metrics-server/` は変わらず、render は同じバイト列
- そのほかは runbook のとおり（apply の `configured` の組、入れ替わりの時間、ログ、`top`）
