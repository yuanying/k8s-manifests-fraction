# metrics-server を v0.7.2 から v0.9.0 へ上げる手順書（本番 `fraction`）

本番クラスタ `fraction` の metrics-server を v0.7.2 から v0.9.0 に上げる手順。fleet-infra の `infrastructure/metrics-server/prod/` の render を、`infra-admin` の短命トークンで `kubectl apply -f` する（client-side）。
計画 `plan.md`（以下「計画」）§8 の非クリティカルなコンポーネントの 3 つ目。前の 2 つ（MetalLB、kube-dns-autoscaler）は porkadot の addon で `install kubernetes` を流したが、metrics-server は fleet-infra が持ち、porkadot を使わない。**このリポジトリの `assets/` と `porkadot.yaml` は変わらない。** 手で apply する形は Longhorn の手順書 `../longhorn/runbook-upgrade-1.12-1.13.md`（以下「Longhorn の手順書」）に合わせる。変わるのは Deployment の image と Service の port の `appProtocol` の 2 つだけで、ノードにも etcd にも control-plane にも触らない。

| | 更新前 | 更新後 |
|---|---|---|
| 材料 | fleet-infra `c0b9f59` の render（本番の last-applied と同じ） | **fleet-infra `baecff7`（#203）の render**。main の `ebe7cc9`（#204 の後）でも同じバイト列（§2.5） |
| イメージ | `registry.k8s.io/metrics-server/metrics-server:v0.7.2` | **`registry.k8s.io/metrics-server/metrics-server:v0.9.0`**（manifest list に amd64・arm・arm64・ppc64le・s390x） |
| Service `kube-system/metrics-server` の port | `name: https`、443 → `https` | **`appProtocol: https` が付く**（ClusterIP、selector、port は同じ） |
| 引数・RBAC・APIService・probe・securityContext・リソース要求・strategy | — | **変わらない** |
| K8s、etcd、kubelet、CoreDNS、MetalLB、Longhorn、porkadot | v1.37.1、3.7.3、… | 変えない |

fleet-infra#203（マージ `baecff7`）は `scripts/update-metrics-server.sh` の `MANIFEST_VER` を 0.9.0 にし、`infrastructure/metrics-server/base/components.yaml` を上流の v0.9.0 に置き換えたもの。v0.7.2 から v0.9.0 で変わること（v0.9.0 の readiness がノードと Pod の両方の metrics を要するようになった #1818、Go と K8s の依存の更新）と互換表（0.9.x は 1.34 以上）は #203 の本文にある。Renovate の `allowedVersions: "<0.8.0"` の規則は fleet-infra#204（`ebe7cc9`）で外した。

この手順は dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で先に通してある（2026-10-25 10:56〜11:02Z）。記録は porkadot-dev の `docs/k8s-upgrade/verification-metrics-server-0.9.md`（以下「dev の記録」。porkadot-dev#21、main `58bbde4`）。dev には metrics-server が無かったので、本番の形（`c0b9f59`）を入れてから `baecff7` に上げた。dev で分かったことは次のとおり。

- **`kubectl diff` の差は image と Service の `appProtocol` の 2 つだけ**。apply の結果は `service/metrics-server configured`、`deployment.apps/metrics-server configured`、ほかの 7 つは `unchanged`
- **入れ替わりの間、1 秒ごとの `kubectl top nodes` は 1 度も失敗せず、APIService も Available のままだった**（`maxUnavailable: 0` で、新しい Pod が Ready になるまで古い Pod が答え続ける）。apply から rollout の完了まで約 23 秒（pull 2.5 秒・23 MB と readinessProbe の `initialDelaySeconds: 20`）
- kubelet への接続は `--kubelet-insecure-tls` なしで、kubelet-serving-cert-approver の証明書をクラスタの CA で検証して通った。v0.7.2・v0.9.0 のどちらのログにも `x509`・scrape の失敗は無い
- **`c0b9f59` の render の apply で v0.7.2 に戻せた**（古い ReplicaSet が使われ、Service の `appProtocol` は client-side apply が last-applied との差で消す）。途切れなし。上げ直しも途切れなし
- #203 の本文の「その間は `kubectl top` と APIService が短時間使えない」は、dev では起きなかった

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **本番の 8 台の scrape**（dev は 7 台、すべて amd64）。本番は control-plane 3 台が arm64 の Pi で、kubelet の serving 証明書の期限もノードごとに違う（§2.2 の 12）。v0.7.2 では 8 台とも scrape できている
- **arm64 のイメージ**。本番でも taint のために worker（amd64）にしか載らないので、使われない（§2.1 の 4）
- **HPA**。dev にも本番にも無い（§2.2 の 10）

## 0. 役割と約束ごと

kube-dns-autoscaler の手順書 `runbook-dns-autoscaler-1.11.md`（以下「autoscaler の手順書」）§0 と同じ形で、次のとおりにする。

- **承認の節目は 1 つ**。この手順書では ✋✋ を付けた。
  - ✋✋ **開始**: §2.5 の render とその差分（この手順書と同じ PR）、§2.2 のベースライン、§2.6 の `kubectl diff` と `--dry-run=server` の結果、§2.3 の監視、§2.7 の時間帯、§6 の止める条件、§7 のロールバックの形を見せ、PR をマージしてから、`kubectl apply` の前（§3.1）
- **節目の後の手順は、ユーザーに知らせるだけで進めてよい（✋）。** `kubectl apply`（§3.2）は、この手順書に書いた形なら ✋ で、1 つずつ承認を取るものではない。✋ の前に、何をするかを知らせる。
- **runbook から外れる操作（ロールバック、apply の流し直しより先の対処、Pod の手での削除、Deployment の手での編集・scale・`rollout undo`、APIService の編集、イメージの手での pull、`--server-side` での apply）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認は、知らせずに行ってよい。時刻はすべて UTC で記録する（control-plane のホストの時刻は JST）。

## 1. 前提

### 1.1 本番の今の姿

始める前に次を確かめる（読み取り）。2026-10-25 11:2xZ（この手順書を書いたとき）の値を書く。当日に読み直す。

- 8 台 Ready・schedulable、全台 v1.37.1、`containerd://2.3.6`。Pod は 168 個（Running 145、Completed 23）で、Running / Completed 以外は 0 個
- kube-dns-autoscaler の更新（`results/dns-autoscaler-1.11/summary.md`）が済んでいる
- metrics-server は v0.7.2 の 1 つ（chirico の `metrics-server-75bf97fcc9-6t94q`、restart 0、2026-10-23 06:24:54Z 起動）。APIService は Available、`kubectl top nodes` は 8 台を答える（§2.2）

### 1.2 kubeconfig の運用

確認は `kubectl --context fraction`（`fraction-auditor`、read-only）で行う。`fraction-auditor` は `kubectl diff` も `--dry-run=server` も流せない（diff はサーバーへの patch として扱われる。#203 の本文。2026-10-25 に `auth can-i patch deployments -n kube-system` が `no`）。

**この手順書では `infra-admin` の短命トークンを使う**（autoscaler の手順書と違うところ。porkadot がノードの上の admin の kubeconfig で apply するのではなく、作業端末の kubectl で apply するため）。発行と破棄は Longhorn の手順書 §1.2 と同じ形で、今回は 1 時間の期限で足りる。

```sh
kubectl --context fraction create token infra-admin -n kube-system --duration=1h > /tmp/ms-upg-admin-token
chmod 600 /tmp/ms-upg-admin-token
ADMIN_TOKEN=$(cat /tmp/ms-upg-admin-token)
kubectl --context fraction --token="$ADMIN_TOKEN" auth can-i patch deployments -n kube-system   # yes
kubectl --context fraction --token="$ADMIN_TOKEN" auth can-i patch apiservices                  # yes
```

- `fraction-auditor` は `serviceaccounts/token` の create を持つ（2026-10-25 に `auth can-i create serviceaccounts --subresource=token -n kube-system` が `yes`。SA `infra-admin` は `cluster-admin` に結ばれている）
- トークンを使うのは、§2.6 の diff と dry-run、§3.2 の apply、§7 の戻しだけ。確認（`top`、`get`、`logs`、監視）は `fraction-auditor` のまま
- 使い終わったら（§4.4 の後）破棄する（`unset ADMIN_TOKEN` と `/tmp/ms-upg-admin-token` の削除）。期限が切れていたら発行し直す
- 以下、`kubectl --context fraction --token="$ADMIN_TOKEN"` を `kubectl-admin` と書く

### 1.3 SSH

autoscaler の手順書 §1.3 と同じ（worker は `ssh yuanying@<IP>`、control-plane は `ssh ubuntu@<IP>`。**名前ではなく IP で入る**。control-plane には `unset LC_ALL` してから入る）。2026-10-25 11:24Z にこの手順書を書いたとき、8 台ともサンドボックスの中から §1.6 の `node-state.sh` を流せた。SSH は読み取りだけに使う。

### 1.4 fleet-infra の render

材料はこの手順書と同じ PR に入れた render である（`render/metrics-server-0.9/`。§2.5）。当日はこの 2 つのファイルを使い、**当日にもう一度 fleet-infra の main を render して、同じバイト列であることを確かめる**（main が先に進んで `infrastructure/metrics-server/` が変わっていたら止める）。

```sh
F=/tmp/fleet-infra-ms
git clone https://github.com/yuanying/fleet-infra.git $F
git -C $F log --oneline -1                      # 2026-10-25 は ebe7cc9
git -C $F log --oneline baecff7..HEAD -- infrastructure/metrics-server/   # 空
kubectl kustomize $F/infrastructure/metrics-server/prod/ | sha256sum      # 1cec29a5…（render/metrics-server-0.9/SHA256SUMS の v0.9.0.yaml）
cd <このリポジトリの checkout>/docs/k8s-upgrade/render/metrics-server-0.9 && sha256sum -c SHA256SUMS   # 2 つとも OK
```

- 元の clone（`~/src/github.com/yuanying/fleet-infra`）の `.git` への書き込みはサンドボックスに拒否されるので、`/tmp` に clone する（Longhorn の手順書 §1.4 と同じ）
- 2026-10-25 11:2xZ に、タスクディレクトリの clone（`worktrees/fleet-infra-ms-rc`）から `c0b9f59`・`baecff7`・`ebe7cc9` を `git archive` で取り出して render し、`baecff7` と `ebe7cc9` が同じバイト列（sha256 `1cec29a5…`、4,330 B）、`c0b9f59` が `f103539a…`（4,307 B）であることを確かめた。dev の記録の render（`notes/dev-metrics-server/render/`）とも sha256 が一致する。`baecff7` の後の main の差（#204 の `renovate.json`、#205 の Flux の設定の削除など）は `infrastructure/metrics-server/` に触っていない
- 作業端末の kubectl は v1.37.1（`kubectl kustomize` も同じ）

### 1.5 入れる版を確かめる

作業の当日に確かめ直す（読み取り）。

```sh
for t in v0.9.0 v0.7.2; do
  curl -sL -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
    https://registry.k8s.io/v2/metrics-server/metrics-server/manifests/$t \
    | jq -r '[.manifests[].platform.architecture] | join(",")'          # amd64 を含む（v0.7.2 は §7 の戻しで要る）
done
gh api repos/kubernetes-sigs/metrics-server/releases --jq '.[0:4][] | [.tag_name,.published_at] | @tsv'
```

2026-10-25 11:2xZ の時点: どちらも manifest list で amd64・arm・arm64・ppc64le・s390x を含む。v0.9.0 の index の digest は `sha256:d9862115…`（dev の Pod の `imageID` と同じ）。アプリの最新の release は v0.9.0（2026-07-13）で、v0.9.1 は無い。**当日に v0.9.1 などのパッチが出ていたら、ここで止めて報告する**（fleet-infra を上げ直すかをユーザーが決める）。

### 1.6 確認に使うスクリプト

タスクディレクトリの `notes/runbook-metrics-server/scripts/` に置いた（dev の `notes/dev-metrics-server/scripts/` を本番の値にしたもの）。どれも読み取りだけ。

| スクリプト | 中身 |
|---|---|
| `snap.sh <dir>` | `fraction-auditor` で、Node、全 Pod（UID・restartCount）、metrics-server の Deployment・ReplicaSet・Pod・Service・EndpointSlice・ServiceAccount（yaml）、APIService、RBAC の resourceVersion、HPA、`top nodes`・`top pods -A`、metrics-server のログ、events、apiserver 3 つの直近 2 時間のログのうち `metrics.k8s.io`・`metrics-server` を含む行。出力は `notes/runbook-metrics-server/<dir>/` |
| `node-state.sh <dir>` | 8 台に IP で ssh し、kubelet の MainPID・NRestarts・ActiveEnterTimestamp、containerd の metrics-server のイメージ、kubelet の serving 証明書（`:10250` の issuer と期限） |
| `lastapplied-diff.sh <render>` | render の 9 つのオブジェクトを 1 つずつ、本番のオブジェクトの `kubectl.kubernetes.io/last-applied-configuration` と比べる（`SAME` / `DIFF` と差）。last-applied の `metadata.annotations: {}` は差として数えない |
| `top-watch.sh <logdir>` | 1 秒ごとに `kubectl top nodes`（`OK n=<台数>` か `FAIL <エラー>`）、APIService の Available の status と reason、metrics-server の Pod（名前、phase、Ready、restart、イメージ、ノード）を `<logdir>/top-watch.log` に 1 行。`<logdir>/watch.stop` を作ると止まる |

当日の出力は、タスクディレクトリの `notes/metrics-server-0-9/`（`base/`、`after/`、`logs/`）に置く。

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 流し方 | `kubectl-admin apply -f render/metrics-server-0.9/v0.9.0.yaml` を 1 回（**client-side**。`--server-side` にしない理由は §3.3） | dev の記録、Longhorn の手順書 §2 の表の 2 |
| 2 | drain・cordon | しない（ノードには触らない） | — |
| 3 | 入れ替わり | Deployment は RollingUpdate（`maxSurge: 25%`・`maxUnavailable: 0`、replicas 1。surge 1・unavailable 0）。新しい Pod が Ready になってから古い Pod が消える。readinessProbe は `/readyz`、`initialDelaySeconds: 20` | live の `strategy`（§2.2 の 3）、dev の記録 |
| 4 | 配置 | 新しい Pod は taint の無い worker（chirico、duchamp、oeilvert、pablo。どれも amd64）のどれか。tolerations は無く、control-plane（`node-role.kubernetes.io/master:NoSchedule`）と braque（`unstable.cloud/storage:NoSchedule`）には載らない | live の tolerations と taint（§2.2 の 1・3） |
| 5 | 途切れ | 見込まない（dev で 0）。許容する範囲: `top-watch.log` の 1〜2 サンプルの FAIL（記録する）。止める条件は §6 | 2026-10-19 のユーザーの方針（短時間の障害は許容） |
| 6 | イメージの事前 pull | **しない**。#3 のとおり古い Pod は新しい Pod が Ready になるまで答え続けるので、pull の時間は途切れにならない（dev では 23 MB で 2.5 秒）。registry.k8s.io から取れないときは新しい Pod が `ImagePullBackOff` のまま古い Pod が残り、§6 で止める | dev の記録の「時間」、autoscaler の手順書 §2.1 の 6 |
| 7 | etcd のバックアップ | **取らない**（§2.4） | Longhorn の手順書 |
| 8 | 材料 | この PR の `render/metrics-server-0.9/v0.9.0.yaml`。当日に fleet-infra の main の render と sha256 で照らす（§1.4） | — |
| 9 | 時間帯 | jumelle の 18:00〜19:30Z、worker の unattended-upgrades 06:00〜07:00Z、control-plane の 21:00〜22:00Z を避ける（§2.7） | autoscaler の手順書 §2.6 |
| 10 | 範囲の外 | 古い ReplicaSet と古いイメージの片付け（§10） | — |

### 2.2 ベースライン

作業の当日、`kubectl apply` の前に次を取り、`results/metrics-server-0.9/baseline.md` に残す（すべて読み取り）。

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-metrics-server/scripts
R=<このリポジトリの checkout>/docs/k8s-upgrade/render/metrics-server-0.9
bash $S/snap.sh ../metrics-server-0-9/base
bash $S/node-state.sh ../metrics-server-0-9/base
bash $S/lastapplied-diff.sh $R/v0.7.2.yaml    # 9 つとも SAME
bash $S/lastapplied-diff.sh $R/v0.9.0.yaml    # Service と Deployment だけ DIFF
```

| # | 項目 | 2026-10-25 11:2xZ の値（当日に読み直す） |
|---|---|---|
| 1 | Node と taint | 8 台 Ready、v1.37.1、cordon されたものは無い。taint は control-plane 3 台（arm64）が `node-role.kubernetes.io/master:NoSchedule`、braque が `unstable.cloud/storage:NoSchedule`、chirico・duchamp・oeilvert・pablo（amd64）は無い |
| 2 | 全 Pod の名前・UID・restartCount | 168 個（Running 145、Completed 23）。Running / Completed 以外は 0 個（§4.2 で「metrics-server 以外は変わらない」を見る元） |
| 3 | Deployment | 2026-10-15 08:39:44Z 作成、**generation 1**、revision 1、1/1。イメージ `registry.k8s.io/metrics-server/metrics-server:v0.7.2`。引数は `--cert-dir=/tmp --secure-port=10250 --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname --kubelet-use-node-status-port --metric-resolution=15s`（`--kubelet-insecure-tls` は無い）。strategy は RollingUpdate（`maxSurge: 25%`・`maxUnavailable: 0`）、revisionHistoryLimit 10。nodeSelector は `kubernetes.io/os: linux`、tolerations は無い、priorityClass は `system-cluster-critical` |
| 4 | Pod | chirico の `metrics-server-75bf97fcc9-6t94q`（UID `60d76b92-f25a-4fa4-b816-8ff5dfe9a177`、restart 0、2026-10-23 06:24:54Z 起動、Pod IP `10.244.8.87`）。`imageID` は `registry.k8s.io/metrics-server/metrics-server@sha256:ffcb2bf0…` |
| 5 | ReplicaSet | `metrics-server-75bf97fcc9`（1/1、v0.7.2）だけ。**古い ReplicaSet は無い**（§7 の戻しでは、この ReplicaSet が 0 で残ったものが使われる見込み） |
| 6 | Service・EndpointSlice | `metrics-server` は ClusterIP `10.254.0.133`、port `https` 443 → `https`（`appProtocol` は無い）、resourceVersion `1235922531`。EndpointSlice は `10.244.8.87:10250` |
| 7 | APIService `v1beta1.metrics.k8s.io` | **Available `True`（`Passed`、`all checks passed`）**、2026-10-23 06:25:16Z から。`insecureSkipTLSVerify: true`、`groupPriorityMinimum: 100`、`versionPriority: 100`、resourceVersion `1238973626`。Local でない APIService はこれだけ（custom metrics などの adapter は無い） |
| 8 | `kubectl top` | `top nodes` が 8 台を答える。`top pods -A` が 145 行（Running の Pod の数と同じ） |
| 9 | ログ | 178 行。`I` の行は 2026-10-23 06:24:56Z の起動のときの 14 行だけ。`E` の行は 164 行で、**どれも `Failed to scrape node`**（`no route to host` 112、`connection refused` 50、`context deadline exceeded` 2）で、ノードが止まっていた間のもの（10-23 06Z の oeilvert の再起動の 12 行、10-23 22Z の段 8 の oeilvert の 36 行と .113 の 1 行、10-24 12:32〜12:39Z の .112 の再起動の 115 行）。最後の `E` は 2026-10-24 12:39:41Z で、その後は無い。`x509` は 0 行 |
| 10 | HPA・VPA | **HPA は 0 個**（`get hpa -A` が `No resources found`）。VPA は CRD が無い |
| 11 | RBAC と last-applied | ServiceAccount `metrics-server`（rv `1235922524`）、ClusterRole `system:aggregated-metrics-reader`（`1235922525`）・`system:metrics-server`（`1235922526`）、RoleBinding `metrics-server-auth-reader`（`1235922527`）、ClusterRoleBinding `metrics-server:system:auth-delegator`（`1235922528`）・`system:metrics-server`（`1235922529`）。`lastapplied-diff.sh` で、**`v0.7.2.yaml` は 9 つとも `SAME`、`v0.9.0.yaml` は Service（`appProtocol: https`）と Deployment（image）だけ `DIFF`**。`k8s-app=metrics-server` のオブジェクトで render に無いものは無い |
| 12 | kubelet と serving 証明書（`node-state.sh`） | .111 MainPID 752609・NRestarts 0、.112 1028・1、.113 612672・0、braque 541944・0、chirico 3237977・0、duchamp 202232・0、oeilvert 916805・51、pablo 3509679・0（autoscaler のベースラインと同じ）。serving 証明書は 8 台とも issuer `CN = kube-ca`、期限は早いものから oeilvert 2027-03-20、chirico 2027-06-23、pablo 2027-08-08、braque 2027-08-18、duchamp 2027-09-06、.111〜.113 2027-10-16 |
| 13 | containerd の metrics-server のイメージ | v0.7.2（`48d9cfaaf3904`、19.5 MB）が chirico・duchamp・oeilvert にある。pablo・braque・control-plane には無い。**v0.9.0 はどの台にも無い** |
| 14 | kube-system の NetworkPolicy | 無い |
| 15 | VIP | `https://192.168.1.101:6443/readyz` が 200 |

### 2.3 監視

`kubectl apply` の前から、§4 の確認が終わるまで流す（読み取り）。autoscaler の手順書 §2.3 と同じく、**`nohup` や `&` で起動しない。** worker のハーネスのバックグラウンド実行で、1 つのジョブとして起動する。

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-metrics-server/scripts
L=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/metrics-server-0-9/logs
bash $S/top-watch.sh $L
```

- 1 行に `kubectl` を 3 回流すので、間隔は 1〜2 秒になる（dev では 211 サンプル / 約 4 分 15 秒）
- 起動したら、ジョブの一覧に居ることと、`top-watch.log` に行が足されていくこと、`top=OK n=8 apiservice=True:Passed` であることを確かめる。**`kubectl apply` の前に、最後の行の時刻が 10 秒以内であること**
- 止めるときは `touch $L/watch.stop`
- 見るもの: `top=FAIL` の行、`apiservice=` が `True:Passed` 以外の行、Pod の列の入れ替わり（新しい Pod の Pending → Running・Ready `false` → Ready `true`、古い Pod の消えた時刻）
- 段 8 の手順書 §2.3 の etcd の health の監視、MetalLB の手順書の `probe.sh`、autoscaler の手順書の DNS の監視は流さない（etcd にも LoadBalancer にも DNS にも触らない）

### 2.4 etcd のバックアップは取らない

**この更新では `porkadot etcd backup` を取らない。** 理由は次のとおり。

- 前例の Longhorn の手順書（fleet-infra のマニフェストを本番に手で apply したもの）は、etcd のバックアップを取っていない。戻り道は Longhorn 自身のバックアップで、etcd の restore は戻し方に入っていない
- §8 のほかの更新（MetalLB、autoscaler）で取ったのは、porkadot の `install kubernetes` を流し、porkadot の手順（計画 §6.1 の 5）に従ったため。この更新は porkadot を使わず、変わるのは Deployment と Service の 2 つのオブジェクトの 1 箇所ずつだけ
- 戻し方は `v0.7.2.yaml` の apply で、dev で確かめた（§7）。2 つのオブジェクトのために etcd 全体を restore する場面は無い（restore はクラスタ全体を巻き戻し、この更新より害が大きい）
- 想定外のときの最後の手段としては、autoscaler の更新の前に取った 2026-10-25 10:16:55Z のスナップショット（`results/dns-autoscaler-1.11/baseline.md` §4）が新しい

当日に、そのスナップショットがメインの checkout の `backup/` にあることだけ確かめる（読み取り。無ければ記録して進める）。

### 2.5 render（この手順書と同じ PR）

`render/metrics-server-0.9/` に 2 つの render と sha256 を入れた。

| ファイル | 元 | sha256 | 用途 |
|---|---|---|---|
| `v0.9.0.yaml` | fleet-infra `baecff7`（= main `ebe7cc9`）の `kubectl kustomize infrastructure/metrics-server/prod/` | `1cec29a5267809306a2c6ec74a3e449abbb705b4a8beed0c8a1963910f72c79b` | §3.2 の apply |
| `v0.7.2.yaml` | fleet-infra `c0b9f59` の同じ render | `f103539a54ed72efe66616afc74a8bfaed651703cb3918797599046af5617441` | §7 の戻し。本番の last-applied と 9 つとも同じ（§2.2 の 11） |

リソースは 9 個（ServiceAccount、ClusterRole 2、RoleBinding、ClusterRoleBinding 2、Service、Deployment、APIService）。2 つの差は次の 2 箇所だけ（dev の記録の「render」と同じ）。

```diff
   ports:
-  - name: https
+  - appProtocol: https
+    name: https
     port: 443
...
-        image: registry.k8s.io/metrics-server/metrics-server:v0.7.2
+        image: registry.k8s.io/metrics-server/metrics-server:v0.9.0
```

- render を PR に入れるのは、当日の材料と戻しの材料を fleet-infra の clone に頼らずに固定するため（MetalLB・autoscaler の手順書が `assets/` の render を同じ PR に入れたのと同じ考え）。当日の fleet-infra の main との照合は §1.4
- render に秘密情報は無い

### 2.6 `kubectl diff` と dry-run（トークンを使うが、書き込まない）

承認（§3.1）の前に流し、結果を見せる。

```sh
R=<このリポジトリの checkout>/docs/k8s-upgrade/render/metrics-server-0.9
D=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/metrics-server-0-9
kubectl-admin diff -f $R/v0.9.0.yaml > $D/diff.txt; echo rc=$?                        # 1（差分あり）
kubectl-admin apply -f $R/v0.9.0.yaml --dry-run=server > $D/dry-run.txt; echo rc=$?   # 0
cat $D/dry-run.txt
```

- `diff` の rc は 1（差分あり）。**rc が 1 より大きければ、差分ではなくエラーなので止める**
- 差分は **Deployment の image（v0.7.2 → v0.9.0）と generation（1 → 2）、Service の port の `appProtocol: https` だけ**（dev の `diff-2-baecff7.txt` と同じ形）。ほかの差、ほかのオブジェクトの差があれば止める
- last-applied の注釈は diff に出ない（`kubectl diff` の MERGED 側は注釈を書き換えない。dev でも本番でも同じ。2026-10-25 の本番の作業で確かめた）
- `--dry-run=server` は rc 0 で、`service/metrics-server configured (server dry run)`、`deployment.apps/metrics-server configured (server dry run)`、ほかの 7 つは `unchanged (server dry run)`。`created` の行があれば止める

### 2.7 時間帯

autoscaler の手順書 §2.6 と同じ時間帯を避ける。

| 時間帯（UTC） | 何が起きるか | 避ける理由 |
|---|---|---|
| **18:00〜19:30** | jumelle の unattended-upgrades と自動再起動 | jumelle が落ちると registry.k8s.io からの pull が止まる（新しい Pod が起動しない。古い Pod は残る） |
| 06:00〜07:00 | worker 5 台の unattended-upgrades | needrestart がサービスを再起動すると、§4.2 の「kubelet が再起動しない」「ほかの Pod が変わらない」の確かめと取り違える。metrics-server は worker に載っている。kubelet が止まるとそのノードの scrape が失敗し、ログの確かめ（§4.2 の 7）と取り違える |
| 21:00〜22:00 | control-plane 3 台の unattended-upgrades | 同上（apiserver。APIService の確かめと取り違える） |

- 作業は、監視の起動から §4 の確認まで 20 分ほどを見込む。その間が上の時間帯に重ならないこと

### 2.8 dev の記録と違う本番の形

| 点 | dev | 本番 | この手順書での扱い |
|---|---|---|---|
| 始めの状態 | metrics-server が無い（v0.7.2 を入れてから上げた） | v0.7.2 が 10 日動いている（generation 1） | 入れたときの `503`（dev の見つけたことの 2）は当たらない |
| ノード | 7 台、すべて amd64 | 8 台、control-plane 3 台が arm64 | scrape は 8 台。`top nodes` の `n=8` を見る |
| v0.7.2 のイメージ | .121・.122 | chirico・duchamp・oeilvert | v0.9.0 はどこにも無いので、新しい Pod の載るノードで pull する。§7 の戻しで pablo に載ると v0.7.2 を pull する |
| 古い ReplicaSet | 無い（作ったばかり） | 無い（revision 1） | 戻しでは `75bf97fcc9` が使い直される見込み（dev の `5f8759489f` と同じ形） |

## 3. `kubectl apply`

### 3.1 事前確認

✋✋ **開始の承認を取る。** §2.5 の render と PR、§2.2 のベースライン（特に 3〜11）、§2.6 の diff と dry-run の結果、§2.3 の監視、§2.7 の時間帯、§6 の止める条件、§7 のロールバックの形を示す。承認を得て PR をマージし、マージした master の `render/metrics-server-0.9/` で §3.2 に入る。

- §2.2 のベースラインと §2.6 が済んでいる。§2.3 の監視がジョブとして動き、最後の行が 10 秒以内で `top=OK n=8 apiservice=True:Passed`
- 全台 Ready、metrics-server が 1/1
- checkout が PR をマージした master で、`sha256sum -c SHA256SUMS` が 2 つとも OK。§1.4 の当日の fleet-infra の main の render が `v0.9.0.yaml` と同じ
- `ADMIN_TOKEN` の期限が残っている（`kubectl-admin auth can-i patch deployments -n kube-system` が `yes`）
- 作業の時間が §2.7 の時間帯と重ならない

### 3.2 流す ✋

```sh
kubectl-admin apply -f $R/v0.9.0.yaml 2>&1 | tee $D/apply.txt; echo rc=$?
```

- 時刻と rc を記録する
- 出力で見るもの: `service/metrics-server configured`、`deployment.apps/metrics-server configured`、**ほかの 7 つは `unchanged`**。それ以外の `configured`・`created` があれば中身を読み、§2.2 の 11 と違えば止める
- `kubectl apply` は prune しないので、消えるオブジェクトは無い
- rc が 0 でないとき（トークンの期限切れ、`connection refused` など）は、出力を読んで原因を見る。トークンの期限なら発行し直して流し直す（✋ の範囲）。2 回目も落ちたら止めて報告する

### 3.3 client-side で流す理由（`--server-side` にしない）

- **本番のオブジェクトは client-side apply で作られている**（9 つとも `kubectl.kubernetes.io/last-applied-configuration` を持つ。§2.2 の 11）。同じ形で流せば、差は last-applied との 3-way merge で決まり、dev で見た結果（configured 2、unchanged 7）がそのまま当たる
- **§7 の戻しが client-side apply に頼っている。** v0.7.2 に戻すとき、Service の `appProtocol` は「last-applied にあって新しい設定に無いもの」として client-side apply が消す（dev で確かめた）。server-side で上げると、`appProtocol` の持ち主が field manager の側に移り、last-applied との関係が変わる。戻しの形が dev で確かめたものと違ってしまう
- dev は client-side だけで確かめた。fleet-infra の `CLAUDE.md` の手順と Longhorn の手順書も client-side（`kubectl apply -k`）
- server-side に移すなら、metrics-server だけでなく fleet-infra 全体の apply の運用として別に決める（§10）

## 4. 後の確認

### 4.1 入れ替わりを見る

```sh
kubectl --context fraction -n kube-system rollout status deployment/metrics-server --timeout=3m
```

- `top-watch.log` で、新しい Pod が taint の無い worker に作られ、Running になり、約 20 秒後に Ready になり、古い Pod `metrics-server-75bf97fcc9-6t94q` が消えるのを見る（dev では apply から 23 秒で完了）。**新しい Pod が 2 分たっても Ready にならないときは止める**（古い Pod は残っている。§6）
- 同じ間、`top=OK n=8` と `apiservice=True:Passed` が続くこと。FAIL が出たら時刻を控える

### 4.2 確認

rollout が終わったら、`snap.sh` と `node-state.sh` を `../metrics-server-0-9/after` に取り、§2.2 と比べる。`lastapplied-diff.sh $R/v0.9.0.yaml` も流す。

| # | 確認 | 合格基準 |
|---|---|---|
| 1 | Deployment | generation が 1 → 2、revision 2。1/1、updated 1。テンプレートのイメージが `registry.k8s.io/metrics-server/metrics-server:v0.9.0`。引数・strategy・probe・securityContext・resources が §2.2 の 3 と同じ |
| 2 | Pod | **1 つだけ、v0.9.0 で Running、Ready、restart 0**。古い Pod が無い。`imageID` が `…@sha256:d9862115…`（§1.5）であることを記録する |
| 3 | 配置 | chirico・duchamp・oeilvert・pablo のどれか（control-plane と braque には無い） |
| 4 | ReplicaSet | 新しい ReplicaSet が 1/1。`75bf97fcc9` は 0 で残る（§7 で使う） |
| 5 | Service・EndpointSlice | Service の port に `appProtocol: https`、ClusterIP `10.254.0.133` と port 443 → `https` は同じ。EndpointSlice の endpoint が新しい Pod の IP の 10250 だけ（`appProtocol` は EndpointSlice の port にも写る） |
| 6 | APIService | Available `True`（`Passed`）。spec と resourceVersion（`1238973626`）が §2.2 の 7 と同じ（status が変われば resourceVersion は変わりうる。変わったら status を読む） |
| 7 | ログ（`kubectl --context fraction -n kube-system logs deploy/metrics-server`） | 起動の `I` の行（`Generated self-signed cert`、`Serving securely on [::]:10250`、caches synced）。**`E` で始まる行、`x509`、`Failed to scrape node`、`unable to fetch`、`Forbidden` が無い** |
| 8 | apiserver のログ（`snap.sh` の `apiserver-metrics.log`） | apply の後に `v1beta1.metrics.k8s.io` の `failing or missing response`・`503`・`OpenAPI` のエラーが無い |
| 9 | `kubectl top` | `top nodes` が 8 台、`top pods -A` が Running の Pod の数と同じ行数。新しい Pod の起動から 1 分（`--metric-resolution=15s` で 4 周）たってから見る |
| 10 | RBAC と last-applied | `lastapplied-diff.sh $R/v0.9.0.yaml` が 9 つとも `SAME`。RBAC の 6 つの resourceVersion が §2.2 の 11 と同じ |
| 11 | ほかの Pod | 全 Pod の比較で、**変わったのは metrics-server の Pod だけ**（名前・UID・restartCount）。Running / Completed 以外が 0 |
| 12 | kubelet | 8 台の MainPID・NRestarts・ActiveEnterTimestamp が §2.2 の 12 と同じ |
| 13 | 監視の FAIL | `top-watch.log` の apply から §4.3 の終わりまでの `top=FAIL` の数と、`apiservice=` が `True:Passed` 以外の数。dev では 0 |
| 14 | HPA | 0 個のまま（あれば `kubectl get hpa -A` の TARGETS が `<unknown>` でないこと） |
| 15 | 健全性 | 8 台 Ready、VIP の `https://192.168.1.101:6443/readyz` が 200 |

- 段 8 の手順書 §1.8 の `netcheck.sh`、§1.9 の `npcheck.sh` は流さない（ネットワークにも NetworkPolicy にも触らない）

### 4.3 5 分おいて見直す

新しい Pod の起動から 5 分たってから、ログ（§4.2 の 7）と `top nodes`（§4.2 の 9）を見直す。v0.9.0 の readiness の変化（#1818）や scrape の失敗は、起動の直後より後の周回で出ることがあるため。`E` の行が無く、`top nodes` が 8 台を答えれば合格。

### 4.4 監視を止め、トークンを破棄する

§4.2・§4.3 が終わったら、§2.3 の監視を止め（`touch $L/watch.stop`）、ジョブが終わったことを確かめる。`unset ADMIN_TOKEN` と `rm /tmp/ms-upg-admin-token` でトークンを破棄する。

## 5. （なし）

片付けはこの手順書には無い。古い ReplicaSet と v0.7.2 のイメージは §7 の戻しの材料なので残す（§10）。

## 6. 止める条件

次のどれかに当たったら、その場で止めて報告する。続けるか §7 で戻すかはユーザーが決める。

- §2.6 の `diff` の rc が 1 より大きい、差が image と `appProtocol` 以外にある、dry-run に `created` がある
- `kubectl apply` の出力に、Service と Deployment 以外の `configured`・`created` があり、§2.2 の 11 と違う
- **新しい Pod が 2 分たっても Ready にならない**（`ImagePullBackOff`、`CrashLoopBackOff`、readiness の失敗など）
- 新しい Pod の restartCount が増える
- **`top-watch.log` の FAIL（`top=FAIL` か APIService が `True` でない）が 5 サンプルを超えて続く**、または合わせて 10 サンプルを超える
- ログに `x509`、`Forbidden`、`Failed to scrape node` が続く（ノードの再起動と重なった 1 回だけなら記録して見る）
- `top nodes` が 8 台より少ない
- metrics-server 以外の Pod の再起動、Node の NotReady
- `kubectl apply` が 2 回続けて rc 0 にならない

1〜2 サンプルの FAIL は、記録して進める。

## 7. ロールバック

**戻すのは runbook から外れる操作なので、ユーザーの承認を取る。** この PR の `render/metrics-server-0.9/v0.7.2.yaml`（fleet-infra `c0b9f59` の render）を client-side apply して v0.7.2 に戻す（dev で確かめた。途切れなし）。

### 7.1 戻すための材料

- **v0.7.2 の render**: `render/metrics-server-0.9/v0.7.2.yaml`（sha256 `f103539a…`）。本番の今の last-applied と 9 つとも同じ（§2.2 の 11）
- **トークン**: §1.2。§4.4 で破棄した後なら発行し直す
- fleet-infra 側は戻さない（main は v0.9.0 のまま）。戻した後に fleet-infra をどうするかはユーザーと決める

### 7.2 戻す ✋

```sh
kubectl-admin diff -f $R/v0.7.2.yaml > $D/diff-rollback.txt; echo rc=$?   # 1。image と appProtocol だけ
kubectl-admin apply -f $R/v0.7.2.yaml 2>&1 | tee $D/apply-rollback.txt; echo rc=$?
kubectl --context fraction -n kube-system rollout status deployment/metrics-server --timeout=3m
```

- §2.3 の監視を流したまま行う
- Deployment は古い ReplicaSet `75bf97fcc9` を使い直す（テンプレートが同じなので pod-template-hash も同じ）。Service の `appProtocol` は last-applied との差で消える（dev の記録の「ロールバック」）
- v0.7.2 の Pod が pablo に載ると、v0.7.2 を pull する（§2.2 の 13。§1.5 で取れることを確かめる）
- 確かめること: §4.2 を版を読み替えて行う（v0.7.2 で Running・Ready・restart 0、Service に `appProtocol` が無い、`lastapplied-diff.sh $R/v0.7.2.yaml` が 9 つとも `SAME`、`top nodes` が 8 台、APIService が Available、ほかの Pod が変わらない）

### 7.3 それでも戻らないとき

§7.2 で戻らないとき（Pod が Ready にならない、APIService が Available に戻らないなど）は止めて報告する。**metrics-server が止まっても、クラスタで影響を受けるのは `kubectl top` と metrics API だけ**（HPA・VPA は無い。§2.2 の 10。kubelet・スケジューラーは metrics API を使わない）ので、急がない。立て直しの手（Pod の削除、`rollout undo`、APIService の一時的な削除）は、その時点でユーザーと決める。etcd の restore は要らない（§2.4）。

## 8. 既知の問題と注意

### 8.1 古い scrape の失敗のログ

v0.7.2 のログには、ノードが止まっていた間の `Failed to scrape node` が 164 行残っている（§2.2 の 9。最後は 2026-10-24 12:39:41Z）。Pod が入れ替わると消える。§4.2 の 7 は新しい Pod のログだけを見る。

### 8.2 v0.9.0 の readiness の変化

v0.9.0 は、ノードと Pod の両方の metrics がそろうまで Ready にならない（#1818）。dev では起動から Ready まで v0.7.2 と同じ約 21 秒（`initialDelaySeconds: 20` で決まる）。本番は scrape するノードが多いが、`maxUnavailable: 0` なので Ready が遅れても古い Pod が答え続ける。§6 の「2 分」はこれを見込んだ値。

### 8.3 kubelet の serving 証明書の期限

metrics-server は kubelet の serving 証明書をクラスタの CA で検証する（`--kubelet-insecure-tls` は無い）。8 台の証明書は kubelet-serving-cert-approver が承認したもので、`rotateCertificates` で更新される。いちばん早い期限は oeilvert の 2027-03-20（§2.2 の 12）。この更新とは関係しないが、ログに `x509` が出たらまず期限を見る。

## 9. 記録

`results/metrics-server-0.9/` に、ベースライン（`baseline.md`。§1 の前提、§1.4 の当日の render の照合、§2.2 の表、§2.6 の diff と dry-run）と、作業の記録（`summary.md`。§3.2 の出力、§4.1 の入れ替わりの時刻（新しい Pod の作成・Running・Ready、古い Pod の消えた時刻）、§4.2 の各項目、§4.3 の結果、監視の FAIL、手順書との差）を残す。形は `results/dns-autoscaler-1.11/` に合わせる。
`snap.sh`・`node-state.sh` の出力と監視のログ（`top-watch.log`）、`diff.txt`・`dry-run.txt`・`apply.txt` はタスクディレクトリの `notes/metrics-server-0-9/` に置き、要点を記録に写す（トークンは書かない）。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（記録の PR で）。

## 10. この後

- 計画 §8 の残りの非クリティカルなコンポーネント（kube-prometheus-stack、CoreDNS v1.15）
- 計画 §10 の片付けで、metrics-server に関わるもの: 古い ReplicaSet `metrics-server-75bf97fcc9`（v0.9.0 で落ち着いてから）、ノードの containerd に残る v0.7.2 のイメージ（chirico・duchamp・oeilvert）、private の `metrics-server/`（1.22 で削除済みの API を使う古いマニフェスト。計画 §10）
- fleet-infra の apply を server-side に移すかどうか（§3.3）。この更新の範囲の外
