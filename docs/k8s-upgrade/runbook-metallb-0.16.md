# MetalLB を v0.14.5 から v0.16.1 へ上げる手順書（本番 `fraction`）

本番クラスタ `fraction` の MetalLB（porkadot の addon）を v0.14.5 から v0.16.1 に上げる手順。porkadot を 0.37.1 から 0.37.2 に替え、`install kubernetes` を 1 回流す。あわせて、使われていない古い CRD `addresspools.metallb.io` を消す。
計画 `plan.md`（以下「計画」）§8 の非クリティカルなコンポーネントの最初の 1 つで、K8s の段（段 8 で v1.37.1）がすべて終わった後に行う。形は段 8 の手順書 `runbook-stage-8.md`（以下「段 8 の手順書」）を下敷きにするが、ノードの kubelet にも etcd にも触らないので、ずっと小さい。

| | 更新前 | 更新後 |
|---|---|---|
| porkadot | 0.37.1（`9e1b97b`、タグ `v0.37.1`） | **0.37.2**（`020c7c7`、タグ `v0.37.2`） |
| MetalLB の controller・speaker | `quay.io/metallb/controller:v0.14.5`・`speaker:v0.14.5` | **`v0.16.1`**（amd64 と arm64 を含む manifest list） |
| MetalLB の CRD | 8 つ（`addresspools` を含む） | porkadot の CRD は 9 つ（**`configurationstates`・`servicebgpstatuses` が増える**）。`addresspools` は §5 で消す |
| metrics | HTTP の `<ノード>:7472`（`prometheus.io/port: 7472`） | **HTTPS の `*:9120`**（認証・認可つき。RBAC が無いので 500。§8.3） |
| health probe | metrics と同じ `7472` | **`127.0.0.1:17472`**（speaker）、`[::]:17472`（controller） |
| memberlist | `<ノード>:7946`（tcp・udp） | 変わらない |
| RBAC | — | `configurationstates`・`servicebgpstatuses`・`ipaddresspools/status` を足す。RoleBinding `pod-lister` に controller を足す。`mutatingwebhookconfigurations` を外す |
| pool・L2Advertisement・`metallb-excludel2` | `first-pool`（`192.168.1.101/32`、`192.168.1.190-192.168.1.254`、`2405:6580:6740:ac01:ace::/96`）、`system` | **変わらない** |
| speaker の tolerations | master、control-plane、`nvidia.com/gpu`（`assets/kubernetes/kustomization.yaml` の patch） | **変わらない**（§2.4） |
| K8s、etcd、kubelet、kube-proxy、cnidaria、CoreDNS、Longhorn | v1.37.1、3.7.3、… | 変えない（`install kubernetes` で apply し直されるが、マニフェストの差分が無い） |

porkadot 0.37.2 に入った PR は porkadot#65（マージ `5646833`。`hack/metallb/` を v0.16.1 にし、テンプレートと CRD を `hack/update-metallb.sh` で render し直した）と porkadot#66（`020c7c7`。版を 0.37.2 にする）。0.37.1 から 0.37.2 の差分は MetalLB のテンプレートと CRD、`hack/metallb/`、テスト、`version.rb` だけで、**`install`・`etcd backup` の実装は 0.37.1 と同じ**。

この手順は dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で先に通してある（2026-10-24 14:33〜14:48Z）。記録は porkadot-dev の `docs/k8s-upgrade/verification-metallb-0.16.md`（以下「dev の記録」。porkadot-dev#19、main `7c85258`）。dev は porkadot#65 の `5646833` で通したもので、0.37.2 との違いは版の番号（#66）だけ。dev で分かったことは次のとおり。

- **`install kubernetes` は 1 回目で rc 0**（約 20 秒）。speaker の rollout は 1 台ずつで、1 台あたり約 20 秒（イメージの pull を含む。イメージがあれば約 11 秒）
- **API の VIP と LoadBalancer の v4・v6 は、1 秒ごとの probe で 1 度も落ちなかった。** 告知の持ち主は 1 つのアドレスにつき 2〜3 回移り、次の speaker が 1 秒以内に告知した
- kubelet・kube-proxy・cnidaria は再起動しなかった
- 更新の後、MetalLB の CRD はどれも `status.storedVersions` が 1 つ。`first-pool` と `system` は書き直さずに使え、LoadBalancer のアドレスは変わらない
- v0.37.1 の `install kubernetes` で v0.14.5 に戻せた（途切れなし）。新しい CRD 2 つは 0 件で残り、RBAC は v0.14.5 の形に戻る
- `addresspools` の CRD は、0 件を確かめて消せば 6 秒で消え、MetalLB には何も起きない（dev には無いので、v0.13.12 の CRD を作って試した）
- v0.16.1 の speaker は起動の直後に、受け持たないアドレスを一度告知してすぐ取り下げる（見つけたことの 2。害は無い）
- **v0.16.1 の metrics（`:9120`）は、upstream の native のマニフェストのままでは取れない**（401 か 500。見つけたことの 3）
- 更新の後の最長 5 分、speaker が消えた speaker の IP に memberlist の join を試してエラーを出す（見つけたことの 4。dev だけの形）。controller は起動の直後に `Reconciler error` を 2 回出す（見つけたことの 5）

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **arm64 の Raspberry Pi（control-plane の 3 台）での v0.16.1 の speaker と、Pi の pull の時間**（dev は amd64 の VM。arm64 のイメージがあることは確かめてある。§1.5）
- **本番の `nvidia.com/gpu` の toleration**（dev には無い。§2.4 で、`install kubernetes` の後も残る見込みと確かめた）
- **本番の `addresspools` の CRD そのものの削除**（2023 年に作られ、conversion webhook の先が今は無い Service `webhook-service`。§5）
- **`externalTrafficPolicy: Local` の LoadBalancer**（gated-v4・gated-v6。dev の `legacy-lb` は Cluster）。Local は endpoint のあるノードの speaker だけが告知するので、持ち主は endpoint のある chirico と pablo の間でしか移らない（§2.5）
- **本番の LoadBalancer の数**（11 個。dev は 2 個）

## 0. 役割と約束ごと

段 8 の手順書 §0 と同じ形で、次のとおりにする。

- **承認の節目は 1 つ**。この手順書では ✋✋ を付けた。
  - ✋✋ **開始**: render の差分（§2.6。この手順書と同じ PR）、§2.2 のベースライン、§2.3 の監視、§2.7 の時間帯、§6 の止める条件、§7 のロールバックの形を見せ、PR をマージしてから、`install kubernetes` を流す前（§3.1）
- **節目の後の手順は、ユーザーに知らせるだけで進めてよい（✋）。** イメージの事前 pull（§2.5）、etcd のバックアップ（§2.4）、`install kubernetes`（§3.2）、テスト用の LoadBalancer の Service と webhook の `--dry-run=server`（§4.3。本番への書き込み）、`addresspools` の CRD の削除（§5。**0 件を確かめてから**）は、この手順書に書いた形なら ✋ で、1 つずつ承認を取るものではない。✋ の前に、何をするかを知らせる。
- **runbook から外れる操作（ロールバック、`install kubernetes` の流し直しより先の対処、Pod の手での削除、DaemonSet・Deployment の手での編集、`addresspools` が 0 件でなかったときの扱い、metrics の RBAC の追加）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認は、知らせずに行ってよい。時刻はすべて UTC で記録する（control-plane のホストの時刻は JST）。

## 1. 前提

### 1.1 本番の今の姿

始める前に次を確かめる（読み取り）。2026-10-25 01:4xZ（この手順書を書いたとき）の値を書く。当日に読み直す。

- 8 台 Ready、全台 v1.37.1、`containerd://2.3.6`。Pod は 169 個で、Running / Succeeded 以外は 0 個
- 段 8 の完了の確認（`results/stage-8/summary.md`）と、その後の様子見が済んでいる
- MetalLB は v0.14.5。controller 1（pablo）、speaker 7。speaker の restartCount は 5〜20（前からのもの。.112 の `speaker-r4s5d` は 7 で、最後の再起動は 2026-10-24 12:39:55Z。.112 は 10-24 12:11Z に kubelet が起き直している（ノードの再起動とみられる。この手順書の範囲の外））
- **2026-10-24 12:11Z の .112 の再起動の後、6 台の speaker のログに `partial join`（`Failed to join 192.168.1.112:7946`）が 12:39Z まで 1 台 34〜35 回出ていた。** それより後の warn・error は無い。controller の最後の error は 2026-10-23 03:24:04Z（IPv6 のプレフィックスの切り替えのときの `IP allocation failed`。今は出ていない）

### 1.2 kubeconfig の運用

段 8 の手順書 §1.2 と同じ（確認は `fraction-auditor`、変更系は `infra-admin` の 1 時間のトークンと `kubectl-admin`）。発行と破棄は段 3 の手順書 §1.2 の形。

```sh
umask 077
kubectl --context fraction create token infra-admin -n kube-system --duration=1h > /tmp/k8u-metallb-admin-token
ADMIN_TOKEN=$(cat /tmp/k8u-metallb-admin-token)
kubectl-admin() { kubectl --context fraction --token="$ADMIN_TOKEN" "$@"; }
kubectl-admin auth can-i delete customresourcedefinitions.apiextensions.k8s.io   # yes
```

**この手順書で `infra-admin` のトークンを使うのは、§4.3 のテスト用の Service と webhook の `--dry-run=server`、§5 の `addresspools` の CRD の削除だけ**。`install kubernetes` は porkadot がノードの上の admin の kubeconfig で流すので、トークンは要らない。使い終えたら破棄する（`unset ADMIN_TOKEN`、ファイルの削除）。

### 1.3 SSH

段 8 の手順書 §1.3 と同じ（worker は `ssh yuanying@<IP>`、control-plane は `ssh ubuntu@<IP>`。**名前ではなく IP で入る**。control-plane には `unset LC_ALL` してから入る）。2026-10-25 01:49Z にこの手順書を書いたとき、8 台ともサンドボックスの中から §2.2 の `node-ports.sh` を流せた。サンドボックスの中で通らないときは、サンドボックスの外での実行を coordinator に頼む（読み取りのコマンドだけ）。

### 1.4 porkadot の置き場と流し方

段 8 の手順書 §1.4 と同じ形で、タスクディレクトリの独立の clone を使う。

| 用途 | 置き場 | 版 |
|---|---|---|
| **当日** | `/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-2` | v0.37.2（`020c7c7`、detached） |
| **§7 の戻し** | `/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-1`（dev の検証で使ったもの。触らずに残す） | v0.37.1（`9e1b97b`、detached） |

- 0.37.2 の clone は、元の clone（`porkadot-dev/porkadot`）から `git clone` し、tag `v0.37.2` を detached で checkout したもの（push しない）。2026-10-25 01:4xZ に `git ls-remote https://github.com/yuanying/porkadot.git` で、GitHub の `refs/tags/v0.37.2`（tag object `61c3623`）と `^{}`（`020c7c7`）が手元と一致することを確かめた。`lib/porkadot/version.rb` は 0.37.2。この clone で §2.6 の render を流した
- 0.37.1 の clone は `git describe --tags` が `v0.37.1`（`9e1b97b`、GitHub の tag object `d566fb9`）。§7.1 の render をこの clone で流した

**このリポジトリのルートを cwd にして** 流す。

```sh
P=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-2
git -C $P describe --tags          # v0.37.2
cd <このリポジトリの checkout>     # §2.6 の PR をマージした master
BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

以下、この形を `porkadot <サブコマンド>` と書く。

- 始める前に `BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot help` が動くことを確かめる
- 作業ツリーの `assets/` と `porkadot.yaml` に PR の外の変更が無いこと（`git status --short assets porkadot.yaml` が空）
- **流す porkadot のコマンドは `etcd backup` と `install kubernetes --node 192.168.1.111` の 2 つだけ。** `install kubelet`、`install all`、`--node` なしの `install kubernetes`、`render`（当日は render しない）、`setup-node`、`setup-containerd`、`etcd restore` は流さない
- `install kubernetes` の `--node` は control-plane の `porkadot.yaml` の `nodes` のキー（`192.168.1.111`）。付けないと bootstrap ノード（pablo）で流し、`127.0.0.1:6443` に届かず rc 1 になる

### 1.5 入れる版を確かめる

作業の当日に確かめ直す（読み取り）。

```sh
gh api repos/metallb/metallb/tags --jq '.[0:3][].name'      # v0.16.1 が最新
for i in speaker controller; do
  curl -s -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
    https://quay.io/v2/metallb/$i/manifests/v0.16.1 | jq -r '[.manifests[].platform.architecture] | join(",")'
done                                                        # amd64 と arm64 を含む
```

2026-10-25 01:5xZ の時点: MetalLB の最新の tag は v0.16.1（v0.16.0、v0.15.3 が続く）。`quay.io/metallb/speaker:v0.16.1` と `controller:v0.16.1` は amd64・arm64・s390x・ppc64le・arm を含む。v0.16.1 を選んだ理由（v0.16.0 の controller の health probe の不具合、metallb#3062）は porkadot#65 の本文。

### 1.6 確認に使うスクリプト

タスクディレクトリの `notes/runbook-metallb-0-16/scripts/` に置いた（dev の `notes/dev-metallb-0-16/scripts/` を本番の値にしたもの）。どれも読み取りだけ。

| スクリプト | 中身 |
|---|---|
| `snap.sh <dir>` | `fraction-auditor` で、Node と taint、全 Pod（UID・restartCount）、MetalLB の Pod・DaemonSet（status、tolerations、managedFields）・Deployment、CRD（served、storage、storedVersions）、MetalLB の CR の件数（`addresspools` を含む）、ClusterRole・webhook、LoadBalancer の Service、Local の Service の endpoint のノード。出力は `notes/runbook-metallb-0-16/<dir>/` |
| `node-ports.sh <dir>` | 8 台に IP で ssh し、kubelet の MainPID・NRestarts・ActiveEnterTimestamp、9120・17472・7472・7946 で聞いているプロセス（MetalLB 以外を含む）、containerd の MetalLB のイメージ |
| `probe.sh <logdir>` | 作業端末から 1 秒ごとに、VIP の `https://192.168.1.101:6443/readyz`、gated-v4 の `http://192.168.1.200/`、gated-v6 の `http://[2405:6580:6740:ac01:ace::200]/`（どちらも 404 が返れば応答あり）、`h2-sshd`（`…ace::131`）と `natsumi-sshd`（`…ace::132`）の SSH のバナーを見る。`<logdir>/probe.log` に 1 秒 1 行 |
| `ml-watch.sh <logdir>` | 2 秒ごとの MetalLB の Pod（名前、ノード、イメージ、Ready、restart、phase）を `<logdir>/ml-watch.log` に、6 秒ごとに全部の speaker と controller のログを `<logdir>/pods/<Pod>.log` に（消えた Pod は最後の写しが残る） |
| `announce.sh <logdir> <from> <to>` | `<logdir>/pods/` の speaker のログの `serviceAnnounced`・`serviceWithdrawn` を時刻順に並べる。`notes/dev-metallb-0-16/scripts/owners.py` に流すと、アドレスごとの持ち主の移りになる |

`probe.sh` と `ml-watch.sh` は `<logdir>/probe.stop` を作ると止まる。当日の `<logdir>` はタスクディレクトリの `notes/metallb-0-16/logs`。

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 流し方 | porkadot 0.37.2 の `install kubernetes --node 192.168.1.111` を 1 回。CRD の server-side apply の後に apiserver のものを apply して rollout を待ち（apiserver は変わらないので Pod は入れ替わらない）、全体を `apply -k --prune` | dev の記録、`assets/kubernetes/install.sh` |
| 2 | drain・cordon | しない（ノードには触らない） | — |
| 3 | 入れ替わり | speaker の DaemonSet は `maxUnavailable: 1`・`maxSurge: 0` で 1 台ずつ（古い Pod を消してから新しい Pod を作る）。controller の Deployment は replica 1 で新しい Pod が Ready になってから古い Pod が消える | live の `updateStrategy`、dev の記録 |
| 4 | 途切れ | 許容する範囲: 1 つの監視で 1〜2 サンプルの FAIL（記録する）。止める条件は §6 | 2026-10-19 のユーザーの方針（短時間の障害は許容） |
| 5 | イメージの事前 pull | 流す前に 8 台のうち speaker の 7 台で `speaker:v0.16.1`、controller の置かれうる 4 台で `controller:v0.16.1` を pull しておく（§2.5。✋） | dev の記録の「本番の runbook に効くこと」 |
| 6 | etcd のバックアップ | `install kubernetes` の前に 1 回（§2.4） | 計画 §6.1 の 5 と同じ扱い |
| 7 | `addresspools` の CRD | 更新の後に消す（§5。0 件を確かめてから） | 計画 §8、§10、porkadot#65 |
| 8 | metrics | 今は誰も scrape していないので、RBAC は足さない。記録だけ（§8.3） | dev の見つけたことの 3 |
| 9 | 時間帯 | jumelle の 18:00〜19:30Z を必ず避ける。unattended-upgrades の 06:00〜07:00Z（worker）と 21:00〜22:00Z（control-plane）も避ける（§2.7） | 段 8 の手順書 §2.11 |
| 10 | 古い Helm の残り | ClusterRole・ClusterRoleBinding `mlb0-metallb:controller`・`mlb0-metallb:speaker`（2018 年の Tiller の chart `metallb-0.8.0`）と空の名前空間 `metallb` には触らない（計画 §10 の片付けで扱う） | 2026-10-25 の読み取り |

### 2.2 ベースライン

作業の当日、`install kubernetes` の前に次を取り、`results/metallb-0.16/baseline.md` に残す（すべて読み取り）。`snap.sh` と `node-ports.sh` の出力はタスクディレクトリの `notes/metallb-0-16/base/` に置く。

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-metallb-0-16/scripts
bash $S/snap.sh ../metallb-0-16/base
bash $S/node-ports.sh ../metallb-0-16/base
```

| # | 項目 | 2026-10-25 01:4xZ の値（当日に読み直す） |
|---|---|---|
| 1 | Node と taint | 8 台 Ready、v1.37.1。taint は control-plane 3 台が `node-role.kubernetes.io/master:NoSchedule`、braque が `unstable.cloud/storage:NoSchedule`、ほかの 4 台は無い。**`nvidia.com/gpu` の taint を持つノードは無い** |
| 2 | 全 Pod の名前・UID・restartCount | 169 個。Running / Succeeded 以外は 0 個（§6 で「MetalLB 以外は変わらない」を見る元） |
| 3 | speaker の DaemonSet | generation 22。**desired 7、current 7、ready 7、available 7、updated 7、misscheduled 0** |
| 4 | speaker の配置 | **.111、.112、.113、chirico、duchamp、oeilvert、pablo の 7 台。braque には無い**（taint のため。これが正しい形） |
| 5 | speaker の tolerations（live） | `node-role.kubernetes.io/master`、`node-role.kubernetes.io/control-plane`、`nvidia.com/gpu`（どれも `NoSchedule`・`Exists`）。nodeSelector は `kubernetes.io/os: linux` |
| 6 | controller | Deployment の generation 18、1/1、pablo（`controller-7f974cb86-28grh`、restart 0）。tolerations は無いので、taint の無い worker 4 台（chirico、duchamp、oeilvert、pablo）にだけ載る |
| 7 | LoadBalancer の Service とアドレス | 11 個（下の表）。`status.loadBalancer.ingress` が `spec.loadBalancerIP` と同じ |
| 8 | Local の LoadBalancer の endpoint | gated-v4・gated-v6 は chirico と pablo（どちらも ready）。minecraft・minecraft2・minecraft3 の `bds` は endpoint が無い（ワークロードが無い。告知されない） |
| 9 | 告知しているノード | speaker のログの最後の `serviceAnnounced`（アドレスで分ける。古いプレフィックス `2405:6581:8580:3…` の行は除く）: VIP（`192.168.1.101`）pablo、gated-v4（`.200`）chirico、gated-v6（`::200`）pablo、`::131` .113、`::132`・`::134` duchamp、`::133` oeilvert。`bds-v4`（`.223`）と `bds`（`::9991`〜`::9993`）は endpoint が無いので告知されない |
| 10 | CRD と storedVersions | 下の表。**どれも storedVersions が 1 つ** |
| 11 | `addresspools` の件数 | **0**（`kubectl --context fraction get addresspools.metallb.io -A` が `No resources found`。deprecated の warning が出る） |
| 12 | MetalLB の CR | `ipaddresspools` 1（`first-pool`、generation 2、`autoAssign: true`、`avoidBuggyIPs: false`）、`l2advertisements` 1（`system`、generation 1）。bgppeers・bgpadvertisements・bfdprofiles・communities・servicel2statuses は 0。`configurationstates`・`servicebgpstatuses` は API に無い |
| 13 | ClusterRole・webhook | `metallb-system:controller`・`metallb-system:speaker`（porkadot）、`mlb0-metallb:*`（2018 年の残り。§2.1 の 10）、ValidatingWebhookConfiguration `metallb-webhook-configuration`。MutatingWebhookConfiguration は無い |
| 14 | 全ノードのポート（`node-ports.sh`） | speaker の 7 台で、speaker が `<ノード>:7946`（tcp・udp）と `<ノード>:7472`（tcp）。**9120・17472 で聞いているプロセスは 8 台とも無い**（MetalLB 以外も含めて）。braque は 4 つとも無い |
| 15 | kubelet | 8 台の MainPID・NRestarts・ActiveEnterTimestamp（§4 で「変わらない」を見る元。2026-10-25 は oeilvert の NRestarts が 51（段 8 の §8.23 のもの）、.112 が 1（10-24 12:11Z）、ほかは 0） |
| 16 | containerd の MetalLB のイメージ | v0.14.5 は 8 台のうち speaker の 7 台にある。v0.16.1 はどの台にも無い（§2.5 の前）。chirico・duchamp・pablo には v0.12.1・v0.13.9 の古いイメージも残っている |
| 17 | metrics を集めているか | Prometheus の active target の job に MetalLB は無い。`{namespace="metallb-system"}` の series は kubelet と kube-state-metrics のものだけで、`metallb_*` は 0 個。ServiceMonitor・PodMonitor・PrometheusRule・ConfigMap に `metallb` は無い（§8.3） |
| 18 | MetalLB のログ | speaker と controller のログの warn・error の種類と最後の時刻（§1.1） |
| 19 | 監視の対象が応答する | VIP の `/readyz` が 200、gated-v4・gated-v6 が 404、`::131`・`::132` が SSH のバナーを返す（§1.6 の `probe.sh` を 5 秒流して確かめた） |

**LoadBalancer の Service**（2026-10-25 01:48Z）:

| 名前空間/名前 | ETP | アドレス | ポート | endpoint のノード |
|---|---|---|---|---|
| `kube-system/porkadot-kubernetes`（API の VIP） | Cluster | `192.168.1.101` | 6443 | control-plane 3 台 |
| `gated-system/gated-v4` | Local | `192.168.1.200` | 80, 443 | chirico, pablo |
| `gated-system/gated-v6` | Local | `2405:6580:6740:ac01:ace::200` | 80, 443 | chirico, pablo |
| `fs/h2-sshd` | Cluster | `…ace::131` | 3222 | — |
| `natsumi/natsumi-sshd` | Cluster | `…ace::132` | 3222 | — |
| `natsumi/natsumi-sshd-myao` | Cluster | `…ace::133` | 3222 | — |
| `natsumi/natsumi-sshd-aki` | Cluster | `…ace::134` | 3222 | — |
| `minecraft/bds-v4` | Cluster | `192.168.1.223` | 19132/UDP | 無い |
| `minecraft/bds`、`minecraft2/bds`、`minecraft3/bds` | Local | `…ace::9991`〜`::9993` | 19133/UDP | 無い |

**MetalLB の CRD**（2026-10-25 01:48Z）:

| CRD | served | storage | storedVersions |
|---|---|---|---|
| `addresspools` | v1alpha1, v1beta1（どちらも deprecated） | v1beta1 | `[v1beta1]` |
| `bgppeers` | v1beta1, v1beta2 | v1beta2 | `[v1beta2]` |
| `bfdprofiles`、`bgpadvertisements`、`communities`、`ipaddresspools`、`l2advertisements`、`servicel2statuses` | v1beta1 | v1beta1 | `[v1beta1]` |

### 2.3 監視

`install kubernetes` の前から、§4 の確認が終わるまで流す（読み取り）。段 8 の手順書 §2.3 と同じく、**`nohup` や `&` で起動しない。** worker のハーネスのバックグラウンド実行で、**監視ごとに 1 つのジョブとして**起動する（`probe.sh` で 1 つ、`ml-watch.sh` で 1 つ。合わせて 2 つ）。

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-metallb-0-16/scripts
L=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/metallb-0-16/logs
bash $S/probe.sh $L       # ジョブ 1
bash $S/ml-watch.sh $L    # ジョブ 2
```

- 起動したら、ジョブの一覧に 2 つが居ることと、`probe.log`・`ml-watch.log` に行が足されていくことを確かめる。**`install kubernetes` の前に、2 つのログの最後の行の時刻が 1 分以内であること**
- 止めるときは `touch $L/probe.stop`（2 つとも止まる）
- `probe.log` の FAIL は、`vip` が 200 以外、`v4`・`v6` が 000（404 は応答あり）、`ssh131`・`ssh132` が `none`。FAIL があれば、その時刻と `announce.sh` の告知の移りを照らす（§4.1）
- 段 8 の手順書 §2.3 の etcd の health の監視は流さない（etcd に触らない）。VIP の FAIL が出たら、そのとき etcd の health を読む

### 2.4 etcd のバックアップ ✋

`install kubernetes` の前に、porkadot 0.37.2 で取る（段 8 の手順書 §2.4 と同じ形。0.37.2 の `etcd backup` は 0.37.0 と同じ実装で、ノードの 3.7.3 の etcdctl を使う）。

```sh
porkadot etcd backup
ls -l ./backup/
```

- 手元のファイルは `./backup/etcd-<日時>.db`、モード 0600。`./backup/` は `.gitignore` で除外してある。スナップショットには Secret が平文で入っているので、`git add -f` などで追加しない。worktree で流したときは、worktree を片付ける前にメインの checkout の `backup/` へ写す
- 時刻、ファイル名、サイズ、sha256 を記録する（段 8 の 3 つは 55 MB 台）。桁が違えば止める
- MetalLB の更新は etcd の restore を要しない見込み（§7 のロールバックは `install kubernetes` で戻す）。このバックアップは、想定外で MetalLB の CR や CRD を失ったときの最後の手段

### 2.5 イメージの事前 pull ✋

本番の Pi（arm64）の pull の時間は dev で見ていない。speaker が入れ替わる間（古い Pod を消してから新しい Pod が Ready になるまで）、その台の speaker は居ないので、pull の時間だけ告知の持ち主が他の台に寄る。**先に pull しておいて、1 台あたりの入れ替わりを dev の約 11 秒の形にする。**

```sh
for h in ubuntu@192.168.1.111 ubuntu@192.168.1.112 ubuntu@192.168.1.113; do
  ssh -n $h 'sudo /opt/bin/crictl pull quay.io/metallb/speaker:v0.16.1'
done
for h in yuanying@192.168.1.83 yuanying@192.168.1.135 yuanying@192.168.1.82 yuanying@192.168.1.134; do
  ssh -n $h 'sudo /opt/bin/crictl pull quay.io/metallb/speaker:v0.16.1 && sudo /opt/bin/crictl pull quay.io/metallb/controller:v0.16.1'
done
```

- 1 台ずつ、IP で入る（§1.3）。braque には speaker も controller も置かれないので pull しない
- 流した後に `node-ports.sh` の `crictl images` で、v0.16.1 があることを確かめる
- コンテナには触らない（pull だけ）。containerd の image の GC で消えることは、当日のうちならまず無い。前の日に pull したなら当日に読み直す
- 時刻と、1 台あたりの pull の時間を記録する（dev の見積りの元）

### 2.6 render の差分（この手順書と同じ PR）

2026-10-25 01:47Z に、porkadot 0.37.2（`020c7c7`。§1.4 の clone）で、このリポジトリのルートを cwd にして `render kubernetes` を流した（rc 0）。`porkadot.yaml` は変えていない。前の render は master の `c0f8b42`（段 8 の porkadot 0.37.0 の render。0.37.1 との違いは `--node` の扱いだけで、render は同じ）。

**差分は次の 2 ファイルだけ**（新しくできたファイル、消えたファイル、証明書・sops の Secret の作り直しも無い）。

| ファイル | 変わったもの |
|---|---|
| `assets/kubernetes/manifests/addons/metallb/metallb.yaml` | イメージ v0.14.5 → v0.16.1。`--port=7472` → `9120`、`--tls-min-version` を外す、コンテナのポート `monitoring`（7472）→ `metricshttps`（9120）、probe のポート `monitoring` → `17472`、Pod の注釈 `prometheus.io/port` → `9120`、speaker に任意の ConfigMap `metallb-memberlist-config` のマウント、RBAC（`configurationstates`・`servicebgpstatuses`・`ipaddresspools/status`、RoleBinding `pod-lister` の subjects に controller を足す、`mutatingwebhookconfigurations` を外す）。オブジェクトの組（16 個）は変わらない |
| `assets/kubernetes/manifests/crds/metallb/crds.yaml` | CRD `configurationstates`・`servicebgpstatuses` を足す（7 → 9）。`ipaddresspools` の status、BGPPeer の conversion webhook の仮の `caBundle` を外す、など。既存の CRD の served・storage の版は変わらない |

- **この差分は dev の差分と同じ**: `metallb.yaml` の `-`・`+` の行は、dev の `k8s-manifests-test` の `514d101`（v0.37.1 の render）→ `ceb19f5`（`5646833` の render）の差分と 1 行も違わない。`crds.yaml` は `ceb19f5` のものとバイトまで同じ
- **変わらないもの**: `metallb.config.yaml`（pool は `192.168.1.101/32`、`192.168.1.190-192.168.1.254`、`2405:6580:6740:ac01:ace::/96`。L2Advertisement `system`）、`000-metallb.yaml`、addon の `kustomization.yaml`、`metallb-excludel2`（`dummy.*` などの unanchored の形のまま。porkadot#65 の「Interfaces MetalLB does not announce on」）
- **`render kubelet`・`render etcd`・`render bootstrap` は流していない。** 0.37.2 では、この 3 つは証明書（各ノードと bootstrap の `bootstrap.crt`、control-plane の `etcd.crt`）を作り直すだけで、`install kubernetes` では使わない（このリポジトリの `/tmp` の clone で 4 つとも流し、差分が証明書の 12 ファイルと上の 2 ファイルだけであることを確かめた）
- `render kubernetes` は証明書を作り直さない。当日は render しない（この PR の `assets/` で流す）
- secrets（`assets/` の sops の証明書と鍵）は、この PR では変わらない。段 8 の前に本番と突き合わせた 28 項目のまま（段 8 の手順書 §1.6）

**`install kubernetes` に入る最終の形**（`kubectl kustomize assets/kubernetes`。読み取り）:

- DaemonSet `speaker`: `speaker:v0.16.1`、ラベル `kubernetes.unstable.cloud/installed-by: porkadot`、tolerations は master・control-plane・`nvidia.com/gpu`（`assets/kubernetes/kustomization.yaml` の patch）
- Deployment `controller`: `controller:v0.16.1`、tolerations なし

### 2.7 時間帯

段 8 の手順書 §2.11 と同じ時間帯を避ける。

| 時間帯（UTC） | 何が起きるか | 避ける理由 |
|---|---|---|
| **18:00〜19:30** | jumelle の unattended-upgrades と自動再起動 | jumelle が落ちると quay.io からの pull が止まり、speaker が入れ替わらない（古い Pod は消えた後）。IPv6 も止まり、v6 の LoadBalancer の監視が意味を失う |
| 06:00〜07:00 | worker 5 台の unattended-upgrades | needrestart がサービスを再起動すると、§4 の「kubelet・kube-proxy・cnidaria が再起動しない」の確かめと取り違える |
| 21:00〜22:00 | control-plane 3 台の unattended-upgrades | 同上 |

- braque には speaker が無いので、braque のバックアップの CronJob の時間帯は気にしなくてよい
- 作業は、`install kubernetes` から §4 の確認まで 30 分ほど、§5 まで含めて 1 時間ほどを見込む。その間が上の時間帯に重ならないこと

### 2.8 dev の記録と違う本番の形

| 点 | dev | 本番 | この手順書での扱い |
|---|---|---|---|
| speaker の数 | 7 台（.124 は taint の後から misscheduled のまま動き、rollout で消えた） | 7 台、misscheduled 0（braque には前から無い） | desired が 7 のままであることを見る（§4.2 の 3） |
| tolerations | master・control-plane | master・control-plane・`nvidia.com/gpu`。`assets/kubernetes/kustomization.yaml`（porkadot が上書きしないファイル）の patch で入っている | §2.6 の最終の形にあるので、`install kubernetes` の後も残る見込み。§4.2 の 4 で確かめる。`nvidia.com/gpu` の taint のノードは今は無いので、どちらでも配置は変わらない |
| LoadBalancer | 2 個（VIP と `legacy-lb`。Cluster） | 11 個。Local が 5 個（endpoint があるのは gated の 2 つ） | Local のアドレスは endpoint のある chirico と pablo の speaker だけが告知できる。chirico と pablo の speaker が同時に居なくなることは無い（`maxUnavailable: 1`）ので、gated は途切れない見込み |
| `addresspools` の CRD | 無い（v0.13.12 のものを作って試した） | ある（2023-04-09 作成、0 件、conversion webhook の先が今は無い Service `webhook-service`） | 0 件なので conversion は呼ばれない。§5 |
| CPU | amd64 の VM | control-plane は arm64 の Pi 5 | §2.5 の事前 pull。§4.2 で arm64 の speaker が Ready・restart 0 であることを見る |

## 3. `install kubernetes`

### 3.1 事前確認

✋✋ **開始の承認を取る。** §2.6 の差分と PR、§2.2 のベースライン（特に 3〜5 の speaker、7〜9 の LoadBalancer、10〜11 の CRD と `addresspools`、14 のポート）、§2.3 の監視、§2.7 の時間帯、§6 の止める条件、§7 のロールバックの形を示す。承認を得て PR をマージし、マージした master で §3.2 に入る。

- §2.2 のベースライン、§2.4 のバックアップ、§2.5 の事前 pull が済んでいる。§2.3 の 2 つの監視がジョブとして動き、ログの最後の行が 1 分以内
- 全台 Ready、VIP の `/readyz` が 200、MetalLB の Pod が 8 つとも Ready
- checkout が §2.6 の PR をマージした master で、`git status --short assets porkadot.yaml` が空。`git -C $P describe --tags` が `v0.37.2`
- 作業の時間が §2.7 の時間帯と重ならない

### 3.2 流す ✋

```sh
porkadot install kubernetes --node 192.168.1.111
```

- 時刻と rc を記録する。dev では約 20 秒で rc 0
- 出力で見るもの:
  - CRD の server-side apply: MetalLB の 9 つ（`configurationstates`・`servicebgpstatuses` が `serverside-applied` で新しくできる）と、ほかの CRD
  - apiserver の apply の後に `daemon set "kube-apiserver" successfully rolled out`（apiserver は変わらないので待たずに終わる）
  - 全体の apply で `configured` になるもの: dev では ClusterRole 2 つ、Role `controller`・`pod-lister`、RoleBinding `pod-lister`（subjects に controller が加わる）、DaemonSet `speaker`、Deployment `controller`、ValidatingWebhookConfiguration。**`ipaddresspool.metallb.io/first-pool` と `l2advertisement.metallb.io/system` は `unchanged`**。`configured` なら §4.2 の 9 で `addresses` を読み、違えば止める
  - **`pruned` の行が無い**（オブジェクトの組は変わらない。§2.6）
  - kube-system のもの（apiserver、KCM、scheduler、kube-proxy、CoreDNS）と cnidaria、kubelet-serving-cert-approver は `unchanged`。前からの `configured`（PDB の `kube-controller-manager`・`kube-scheduler` など。段 8 の手順書 §3.3 の注）は generation が変わらなければ想定内
- rc 1 のときの扱い（`connection refused` など）は段 8 の手順書 §8.3 と同じ。CRD の apply の後・全体の apply の前に落ちたなら、新しい CRD ができただけで MetalLB は v0.14.5 のまま。原因を見て流し直す（流し直しは ✋ の範囲）。2 回目も落ちたら止めて報告する
- 流した直後に、§2.3 の 2 つの監視のログが続いていることを確かめる

## 4. 後の確認

### 4.1 入れ替わりを見る

`install kubernetes` の後、speaker の rollout が終わるまで（dev では約 2 分。本番の 7 台で 2〜3 分を見込む）、次を見ながら待つ。

```sh
kubectl --context fraction -n metallb-system rollout status deployment/controller --timeout=5m
kubectl --context fraction -n metallb-system rollout status daemonset/speaker --timeout=10m
```

- `ml-watch.log` で、1 台ずつ古い Pod が消えて新しい Pod が Ready になるのを見る。**ある台の新しい speaker が 2 分たっても Ready にならないときは止める**（DaemonSet の rollout はそこで止まり、残りの台の古い speaker は動き続ける。§6）
- `probe.log` に FAIL が出たら、時刻を控える。rollout の後に `announce.sh $L <from> <to> | python3 notes/dev-metallb-0-16/scripts/owners.py` で、アドレスごとの持ち主の移りと照らす
- 告知の持ち主は 1 つのアドレスにつき 2〜3 回移りうる（dev の記録の「入れ替わりと告知」）。起動の直後の告知と取り下げ（`reason: notOwner`）も想定どおり（dev の見つけたことの 2）

### 4.2 確認

rollout が終わったら、`snap.sh` と `node-ports.sh` を `../metallb-0-16/after` に取り、§2.2 と比べる。

| # | 確認 | 合格基準 |
|---|---|---|
| 1 | controller | 1/1 Ready、`controller:v0.16.1`、restart 0。Deployment の generation が 1 つ増える（2026-10-25 は 18）。taint の無い worker 4 台のどれか |
| 2 | speaker | **7 つとも Ready、`speaker:v0.16.1`、restart 0**。arm64 の .111〜.113 を含む |
| 3 | speaker の DaemonSet | generation が 1 つ増える（2026-10-25 は 22）。**desired・current・ready・available・updated が §2.2 の 3 と同じ 7、misscheduled 0** |
| 4 | speaker の配置と tolerations | §2.2 の 4 と同じ 7 台（braque に無い）。live の tolerations が §2.2 の 5 と同じ 3 つ（`nvidia.com/gpu` が残る）。消えていたら記録して報告する（今の本番では配置は変わらないので、止めはしない） |
| 5 | ポート（`node-ports.sh`） | speaker の 7 台で、speaker が **`*:9120`**（tcp。v4 と v6）、**`127.0.0.1:17472`**、`<ノード>:7946`（tcp・udp）を持ち、**`7472` が無い**。braque は 4 つとも無い。MetalLB 以外のプロセスが 9120・17472 に居ない |
| 6 | probe | controller と speaker の Pod の events に `Unhealthy` が無い（readiness と liveness の probe が `17472` で通る） |
| 7 | CRD | MetalLB の CRD が 9 つ（`addresspools` を入れて 10。§5 で消す）。**どれも `status.storedVersions` が 1 つ**（`bgppeers` は `[v1beta2]`、ほかは `[v1beta1]`）。`configurationstates`・`servicebgpstatuses` が `[v1beta1]`。既存の CRD の served・storage が §2.2 の表と同じ |
| 8 | ConfigurationState | `kubectl --context fraction get configurationstates.metallb.io -A` に controller と各 speaker のノードの分（8 つ）があり、**どれも `result` が `Valid`** |
| 9 | pool | `first-pool` の `spec.addresses` が §2.2 の 12 と同じ。generation が変わらない（2）。v0.16.1 では status（`assignedIPv4`・`assignedIPv6` など）が付く |
| 10 | LoadBalancer のアドレス | 11 個とも `status.loadBalancer.ingress` が §2.2 の 7 と同じ。**変わった・外れたものが無い** |
| 11 | 告知と応答 | `probe.log` の最後の 1 分が FAIL 0。告知しているノードを §2.2 の 9 と同じ形で読み、記録する（変わっていてよい。gated-v4・gated-v6 は chirico か pablo） |
| 12 | MetalLB のログ | controller の `Reconciler error`（`configurationstates.metallb.io "controller" not found`、`first-pool` の status の更新の衝突。どちらも起動の直後に 1 回だけ。dev の見つけたことの 5）、speaker の `partial join`（最長 5 分。dev の見つけたことの 4）、annotation `metallb.universe.tf/*` の deprecated の warn は想定どおり。**ほかの error が続いていないこと** |
| 13 | ほかの Pod | 全 Pod の比較で、**変わったのは `metallb-system` の Pod だけ**（名前・UID・restartCount）。kube-proxy・cnidaria・CoreDNS・apiserver・KCM・scheduler・gated の Pod の UID と restartCount が §2.2 の 2 と同じ。Running / Succeeded 以外が 0 |
| 14 | kubelet | 8 台の MainPID・NRestarts・ActiveEnterTimestamp が §2.2 の 15 と同じ |
| 15 | 監視の FAIL | `probe.log` の `install kubernetes` から rollout の完了までの FAIL の数（監視ごと）。dev では 0 |
| 16 | 健全性 | 段 8 の手順書 §1.8 の `netcheck.sh`（✋。一時的な DaemonSet を作る）と `tools/npcheck.sh`（✋。一時的な名前空間を作る。段 8 の手順書 §1.9）が通る。どちらも段 8 の手順書のとおりの形で、本番の段 8 の後と同じ結果 |

### 4.3 新しい LoadBalancer と webhook ✋

controller と webhook が v0.16.1 で動くことを、新しい割り当てで確かめる。**本番への書き込み**なので ✋（知らせてから行う）。`kubectl-admin` を使う（§1.2）。

**webhook**（書き込みなし）: 今の pool と重なる IPAddressPool を `--dry-run=server` で作ろうとし、webhook が拒むことを見る。

```sh
cat <<'EOF' | kubectl-admin create --dry-run=server -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: k8u-mlb-overlap
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.250/32
EOF
```

- 合格: `admission webhook "ipaddresspoolvalidationwebhook.metallb.io" denied the request: CIDR "192.168.1.250/32" in pool "k8u-mlb-overlap" overlaps with already defined CIDR "192.168.1.190-192.168.1.254"` の形で拒まれる（dev の記録の「新しい LoadBalancer」）。`created (server dry run)` と出たら止めて報告する（何も作られていない）

**割り当て**: 一時的な名前空間に、**selector の無い** `type: LoadBalancer` の IPv4 の Service を作り、アドレスが割り当てられることを見て消す。

```sh
kubectl-admin create namespace k8u-mlb
cat <<'EOF' | kubectl-admin apply -f -
apiVersion: v1
kind: Service
metadata:
  name: k8u-mlb-test
  namespace: k8u-mlb
spec:
  type: LoadBalancer
  ipFamilyPolicy: SingleStack
  ipFamilies: [IPv4]
  ports:
  - port: 80
EOF
kubectl --context fraction -n k8u-mlb get svc k8u-mlb-test -o jsonpath='{.status.loadBalancer.ingress}'; echo
kubectl --context fraction -n k8u-mlb get events --field-selector involvedObject.name=k8u-mlb-test
kubectl-admin delete namespace k8u-mlb
```

- 合格: 数秒で `first-pool` の空いているアドレス（2026-10-25 なら `192.168.1.190`。`.101`・`.200`・`.223` は使われている）が割り当てられ、event に `IPAllocated` が出る。名前空間を消した後、`first-pool` の status の割り当ての数が元に戻る
- **selector が無いので endpoint が無く、speaker はこのアドレスを告知しない**（ARP・NDP は出ない）。宅内のほかの機器と取り合うことも、トラフィックを受けることも無い。告知（L2）まで確かめたいときは、dev のように endpoint のある Service を作ることになるが、本番では gated と VIP の告知が §4.2 の 11 で見えているので、それで足りるとする
- 割り当てられないときは、controller のログを見て記録し、名前空間を消してから止めて報告する
- 作ったもの（名前空間 `k8u-mlb`）が消えたことを確かめる

## 5. `addresspools.metallb.io` の削除 ✋

`addresspools` は MetalLB の v0.14 より前に CRD から外れた古い API（`AddressPool`。v1alpha1・v1beta1、どちらも deprecated）で、porkadot は CRD を `apply -f` で入れるだけで prune しないので、本番に残っている（porkadot#65 の本文）。**v0.14.5 も v0.16.1 も読まない。** 0 件を確かめてから消す。admin 権限が要る（`kubectl-admin`）。

```sh
kubectl --context fraction get addresspools.metallb.io -A
# Warning: metallb.io v1beta1 AddressPool is deprecated, consider using IPAddressPool
# No resources found
kubectl --context fraction get addresspools.metallb.io -A -o name | wc -l
# 0
kubectl --context fraction get crd addresspools.metallb.io -o jsonpath='{.metadata.creationTimestamp} {.spec.conversion.strategy} {.spec.conversion.webhook.clientConfig.service.name}{"\n"}'
# 2023-04-09T07:32:54Z Webhook webhook-service
kubectl-admin delete crd addresspools.metallb.io
kubectl --context fraction get crd addresspools.metallb.io
# Error from server (NotFound)
```

- **`wc -l` が 0 でなければ止める。** 中身を読んで報告する（消すかはユーザーが決める）
- 消す前に、CRD の yaml をタスクディレクトリの `notes/metallb-0-16/addresspools-crd.yaml` に控える（`kubectl --context fraction get crd addresspools.metallb.io -o yaml`。Secret は含まない）。§7 で要ることは無い見込みだが、元の形を残す
- 消した直後の数秒は `customresourcecleanup` の finalizer で Terminating として見える（dev では作ってから消し終わるまで 6 秒）
- 本番の CRD の conversion webhook の先は、今は無い Service `webhook-service`（今の webhook の Service は `metallb-webhook-service`）。0 件なので conversion は呼ばれず、`get` も `delete` も通る（2026-10-25 の `get` は通った）
- 消した後に、controller と speaker のログに `addresspool` もエラーも出ないこと、MetalLB の Pod が 8 つとも Ready・restart 0 のままであること、MetalLB の CRD が 9 つ残ることを見る。`probe.log` が FAIL 0
- v0.16.1 の controller の ClusterRole が CRD を触れるのは `resourceNames` の 7 つ（`addresspools` を含まない）だけで、消した CRD を controller が入れ直すことは無い（dev の記録）
- 時刻を記録する

§5 が終わったら、§2.3 の監視を止める（`touch $L/probe.stop`）。ジョブが終わったことを確かめる。

## 6. 止める条件

次のどれかに当たったら、その場で止めて報告する。続けるか §7 で戻すかはユーザーが決める。

- **VIP の `/readyz` の FAIL が 5 サンプル（約 5 秒）を超えて続く**、または rollout の間に合わせて 10 サンプルを超える
- **gated-v4・gated-v6・`::131`・`::132` のどれかの FAIL が 5 サンプルを超えて続く**
- ある台の新しい speaker が 2 分たっても Ready にならない、CrashLoopBackOff になる、restartCount が増える
- controller が 2 分たっても Ready にならない、または restartCount が増える
- LoadBalancer のアドレスが変わる・外れる（`status.loadBalancer.ingress`）
- speaker の DaemonSet の desired が 7 でなくなる、misscheduled が 0 でなくなる
- MetalLB 以外の Pod の再起動（kubelet・kube-proxy・cnidaria・CoreDNS・apiserver など）、Node の NotReady
- ConfigurationState に `Valid` でないものがある
- CRD の storedVersions が 2 つになったものがある
- `install kubernetes` が 2 回続けて rc 0 にならない
- `install kubernetes` の出力に `pruned` の行がある
- 9120・17472 で、MetalLB の前から別のプロセスが聞いていた（§2.2 の 14。当日に見つかったら流す前に止める）

1〜2 サンプルの FAIL、§4.2 の 12 の想定どおりのログは、記録して進める。

## 7. ロールバック

**戻すのは runbook から外れる操作なので、ユーザーの承認を取る。** porkadot 0.37.1 の `install kubernetes` で v0.14.5 に戻す（dev で確かめた。rc 0、途切れなし）。

### 7.1 戻すための材料

- **前の版の assets**: この PR の前の master（**`c0f8b42`**）の `assets/` と `porkadot.yaml`。**porkadot 0.37.1 で `render kubernetes` しても、この `assets/` とバイトまで同じ**（2026-10-25 01:5xZ に `/tmp` の clone で確かめた。`git status` が空）なので、当日に render しないで使う
- **porkadot 0.37.1**: §1.4 の `worktrees/porkadot-v0-37-1`

用意の仕方（作業端末で。段 8 の手順書 §7.1 と同じ形。`git worktree add` は元の clone の `.git` に書き込むので使わない）:

```sh
P_OLD=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-1   # git -C $P_OLD describe --tags が v0.37.1
git clone <このリポジトリの checkout> /tmp/fraction-metallb-0.14
git -C /tmp/fraction-metallb-0.14 checkout c0f8b42
cd /tmp/fraction-metallb-0.14
grep 'image:' assets/kubernetes/manifests/addons/metallb/metallb.yaml    # v0.14.5 が 2 つ
```

### 7.2 戻す ✋

```sh
cd /tmp/fraction-metallb-0.14
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml
```

- §2.3 の監視を流したまま行う
- speaker と controller が v0.14.5 に入れ替わる（dev では 1 台あたり約 11 秒。v0.14.5 のイメージはノードに残っている）
- **新しい CRD 2 つ（`configurationstates`・`servicebgpstatuses`）は残る**（`install.sh` の `apply -f manifests/crds` は prune しない）。ConfigurationState は Pod を owner に持つので、speaker と controller の入れ替えで消え、2 つとも 0 件になる。v0.14.5 はこれらを読まないので害は無い。消すかは後で決める
- RBAC（ClusterRole 2 つ、Role `controller`・`pod-lister`、RoleBinding `pod-lister`）は v0.14.5 の形に上書きされる。オブジェクトの組は同じなので prune されるものは無い
- **`addresspools` の CRD を §5 で消した後なら、戻さない**（v0.14.5 も読まない）。§5 で控えた yaml がある
- 確かめること: §4.2 を版を読み替えて行う（controller・speaker が v0.14.5 で Ready、desired 7、ポートが `<ノード>:7472`・`<ノード>:7946` に戻り 9120・17472 が無い、CRD の storedVersions が 1 つずつ、LoadBalancer のアドレスが §2.2 の 7 と同じ、MetalLB 以外の Pod が変わらない）。§4.3 の割り当ての確かめは、戻した理由によってユーザーと決める
- 戻した後に `install kubernetes` を流し直したいときは、`/tmp/fraction-metallb-0.14` と 0.37.1 を使う。**この PR をマージした master で 0.37.1 の `install kubernetes` を流さない**（assets が v0.16.1 なので、また v0.16.1 になる）

### 7.3 それでも戻らないとき

`install kubernetes` で MetalLB の Pod が起きない、CR が壊れたなど、§7.2 で戻らないときは止めて報告する。立て直しの手は、その時点でユーザーと決める（手での `kubectl apply`、Pod の削除、§2.4 の etcd の backup の restore は最後の手段で、段 8 の手順書 §7.4 の形。API の中身すべてが backup の時点に戻る）。

## 8. 既知の問題と注意

### 8.1 起動の直後の告知と取り下げ

v0.16.1（と v0.14.5）の speaker は、起動の直後に、受け持たないアドレスを一度告知して数ミリ秒で取り下げる（`serviceAnnounced` の後に同じ speaker の `serviceWithdrawn`、`reason: notOwner`）。memberlist に入る前に自分を唯一のメンバーとして選ぶためとみている（dev の見つけたことの 2）。gratuitous ARP・NDP が出ると、聞いた側はそのノードに送るが、そのノードの kube-proxy が転送するので届く（Cluster の Service）。**Local の gated は、endpoint の無いノードに来たパケットは落ちる**が、endpoint の無いノードの speaker は gated を告知しない（Local の告知は endpoint のあるノードに限られる）ので、当たらない見込み。`probe.log` の v4・v6 で見る。

### 8.2 memberlist の `partial join`

更新の後の最長 5 分、新しい speaker が、消えた古い speaker の IP（dev では消えた .124）に join を試してエラーを 1 分ごとに出すことがある（speaker の IP の一覧は 5 分ごとに読み直す。dev の見つけたことの 4）。本番では speaker の IP はノードの IP で入れ替わりの前後で同じなので、出ないか短い見込み。5 分を超えて続いたら記録する。

### 8.3 metrics（`:9120`）

v0.16.1 の metrics は HTTPS の `:9120` で、controller-runtime の認証・認可が付く。トークン無しは 401。`/metrics` の `get` を許したトークンでも、speaker と controller に `tokenreviews`・`subjectaccessreviews` の `create` の権限が無いので 500 になる（dev の見つけたことの 3。upstream でも `metallb-native-prometheus.yaml` だけがその権限を持つ）。

- **本番は MetalLB の metrics を集めていない**（§2.2 の 17）ので、今は影響しない。この手順書では RBAC を足さない
- 集めるときは、porkadot のマニフェストに `tokenreviews`・`subjectaccessreviews` の `create` の ClusterRole を足し、Prometheus の側に `/metrics` の `get` を許す（porkadot の PR と dev の検証が要る）。計画 §8 の kube-prometheus-stack の更新の時に決める
- Pod の注釈 `prometheus.io/scrape: "true"`、`prometheus.io/port: "9120"` は残る。本番の Prometheus はこの注釈で集める job を持たない
- 9120 は全インターフェイス（v4 と v6。ノードのグローバルの IPv6 を含む）で開く。v0.14.5 の `7472` は認証なしの HTTP（ノードの IPv4 だけ）だった。外から届くかは jumelle の filter による（この手順書の範囲の外）

### 8.4 `metallb.universe.tf` の注釈の deprecated

v0.14.9 から、annotation の `metallb.universe.tf/*` は deprecated で、controller が起動のときに warn を出す（まだ使える。dev の記録）。本番の LoadBalancer は `spec.loadBalancerIP`（K8s で deprecated。MetalLB はまだ読む）でアドレスを決めていて、`metallb.universe.tf/loadBalancerIPs` の注釈は使っていない（§2.2 の 7）。どちらも今は直さない。

### 8.5 `addresspools` の conversion webhook

§5 のとおり、本番の `addresspools` の CRD の conversion webhook の先（`metallb-system/webhook-service`）は無い。0 件なので害は無いが、1 件でもあれば `get` の版の変換で失敗しうる。§5 で 0 件でなかったら止める。

### 8.6 dev の .124 の形は本番に当たらない

dev では、speaker の載った後に taint の付いた .124 の speaker が rollout で消え、作り直されなかった（dev の見つけたことの 1）。本番は misscheduled 0 で、braque には前から speaker が無い（§2.2 の 3〜4）。§4.2 の 3 で desired が 7 のままであることを見る。

## 9. 記録

`results/metallb-0.16/` に、ベースライン（`baseline.md`。§2.2 の表、§2.4 のバックアップ、§2.5 の事前 pull の時間）と、作業の記録（`summary.md`。§3.2 の出力の要点、§4.1 の入れ替わりの表（ノードごとの古い Pod が止まった時刻と新しい Pod が Ready になった時刻）と告知の持ち主の移り、§4.2 の各項目、§4.3 と §5 の結果、監視の FAIL、手順書との差）を残す。dev の記録の「入れ替わりと告知」「途切れ」の表の形を使う。
`snap.sh`・`node-ports.sh` の出力、監視のログ（`probe.log`、`ml-watch.log`、`pods/`）、`announce.sh`・`owners.py` の出力はタスクディレクトリの `notes/metallb-0-16/` に置き、要点を記録に写す。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（記録の PR で）。

## 10. この後

- dev の .124 に speaker が無い形を残すか（toleration を足すか）は決めていない（dev の記録）。本番には当たらない
- 計画 §8 の次の非クリティカルなコンポーネント（kube-prometheus-stack、metrics-server、kube-dns-autoscaler、CoreDNS v1.15）
- 計画 §10 の片付けで、MetalLB に関わるもの: 空の名前空間 `metallb`、2018 年の Helm（Tiller）の ClusterRole・ClusterRoleBinding `mlb0-metallb:controller`・`mlb0-metallb:speaker`（subjects は名前空間 `metallb` の無い ServiceAccount）、ノードの containerd に残る MetalLB の古いイメージ（v0.12.1、v0.13.9、v0.14.5）。`addresspools` はこの手順書の §5 で片付く
- MetalLB の metrics を集めるなら §8.3
- **IPv6 の pool を porkadot から外す案**（プレフィックスに追随する仕組みを本番への CD の別タスクで作る。段 8 の前提のメモ §1）は、この更新と同時に動かさない
