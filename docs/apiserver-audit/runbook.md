# kube-apiserver の audit のログを入れる手順書（本番 `fraction`）

本番クラスタ `fraction` の kube-apiserver に audit のログを入れる手順。判断と理由は [ADR 0009](../adr/0009-apiserver-audit-log-on-the-node.md)。入れるものはこの手順書と同じ PR にある。

| | 入れる前 | 入れた後 |
|---|---|---|
| kube-apiserver の引数 | audit の引数なし | `--audit-policy-file`・`--audit-log-path`・`--audit-log-format=json`・`--audit-log-maxsize=100`・`--audit-log-maxbackup=10`・`--audit-log-maxage=7` |
| policy | なし | ConfigMap `kube-system/kube-apiserver-audit-policy-<hash>`（`assets/kubernetes/audit/policy.yaml` から生成）を `/etc/kubernetes/audit/` に mount |
| ログ | なし | 各 control-plane の node の `/var/log/kubernetes/audit/audit.log`（hostPath、`DirectoryOrCreate`）。1 ファイル 100 MB で `audit-<時刻>.log` に回し、10 世代・7 日まで。上限はおよそ 1.1 GB |
| `porkadot.yaml`・`assets/kubernetes/manifests/` | — | 変えない（render しない）。足すのは `assets/kubernetes/kustomization.yaml` の patch と `assets/kubernetes/audit/policy.yaml` だけ |
| kube-apiserver の image・etcd・kubelet・ほかの部品 | v1.37.2 | 変えない |
| bootstrap の kube-apiserver（`assets/bootstrap/`） | audit なし | 変えない（audit なしのまま。ADR 0009 の Decision 項 4） |

**DaemonSet の更新の仕方を一時的に `OnDelete` にして、control-plane を 1 台ずつ、Pod を消して入れ替える。** `RollingUpdate`（`maxUnavailable: 1`）のまま apply すると、1 台目が Ready になった直後に 2 台目へ進み、1 台目のログを見てから止める間が無いためである。3 台が終わったら `RollingUpdate` に戻す。porkadot の `install kubernetes` は使わない（apiserver の rollout を待つので、`OnDelete` では待ちが終わらない）。

## 0. 役割と約束ごと

[ADR 0008](../adr/0008-approval-and-credentials-for-production-changes.md) の形で、次のとおりにする。

- **承認の節目は 1 つ**（✋✋ **開始**）。この PR の差分（§2.3 の `kubectl diff`）、§2.1 のベースライン、§2.2 の etcd のバックアップ、§3.4 の止める条件、§6 の戻し方を見せ、承認を得て PR をマージしてから §3 に入る
- **節目の後の手順は、知らせるだけで進めてよい（✋）。** 更新の仕方の切り替え（§3.1・§3.6）、apply（§3.2）、1 台ずつの Pod の削除（§3.3・§3.5）は、この手順書に書いた形なら ✋。1 つずつ承認は取らないが、✋ の前に何をするかを知らせる
- **手順書から外れる操作**（§6 の戻し、policy の書き換え、node の上のログのファイルの削除、想定外の対処）は、その都度承認を取る。想定外のことが起きたら、その場で止めて報告する
- 読み取りの確認は知らせずに行ってよい。時刻はすべて UTC で記録する（control-plane のホストの時刻は JST）
- **audit のログの中身（要求の本文を含む）を、このリポジトリやタスクの記録に写さない。** 記録には件数・大きさ・level の内訳のような集計だけを書く

## 1. 前提

### 1.1 本番の今の姿

始める前に読み直す（読み取り）。この手順書を書いたとき（2026-11-11 01:2xZ）の値:

- DaemonSet `kube-system/kube-apiserver` は generation 32、3/3 Ready、`updateStrategy` は `RollingUpdate`（`maxSurge: 0`、`maxUnavailable: 1`）、image `registry.k8s.io/kube-apiserver:v1.37.2`
- Pod は `kube-apiserver-8rxxd`（192.168.1.113）、`-k7b6b`（.112）、`-q4tpv`（.111）。どれも restartCount 0、2026-10-30 11:13〜11:14Z の起動
- checkpointer の Pod は無い（DaemonSet の annotation だけ）。名前に `audit` を含む ConfigMap は kube-system に無い
- control-plane の 3 台はルートの fs が 125 GB で、空きが 112〜113 GB（kubelet の `stats/summary`）

### 1.2 kubeconfig の運用

段 1 の手順書 `docs/k8s-upgrade/runbook-stage-1.md` §1.2 と同じ。確認は `kubectl --context fraction`（`fraction-auditor`）で行う。

**この手順書は porkadot ではなく作業端末の kubectl で書き込む**ので、`infra-admin` のトークンを 3 時間の期限で発行し、作業端末のモード 600 のファイルに置く。次の操作が `auth can-i` で yes であることを確かめる: kube-system の `daemonsets` の `patch`、`pods` の `delete`、`configmaps` の `create`。以下、変更系のコマンドを `kubectl-admin`（`kubectl --context fraction --token="$ADMIN_TOKEN"` のこと）と書く。§3.6 の後に破棄する。

### 1.3 SSH

control-plane は `ssh ubuntu@<IP>`（名前ではなく IP。`unset LC_ALL` してから入る）。ログのファイルは root の 0600 なので、読むときは `sudo` を使う。

### 1.4 組み立て方

**このリポジトリのルートを cwd にして**、この PR をマージした master で流す。`git status --short assets porkadot.yaml` が空であること。

kube-apiserver のものだけを組み立てて apply する（`install.sh` の最初の apply と同じ選び方）:

```sh
kubectl-admin apply -l app.kubernetes.io/component=kube-apiserver -k assets/kubernetes
```

`assets/kubernetes/kustomization.yaml` の resources に Secret の manifest（`*.secrets.yaml`）は入っていないので、この apply は Secret に触らない。

## 2. 事前準備

### 2.1 ベースライン

読み取りで、次を `notes/apiserver-audit/baseline/`（タスクディレクトリ）に取る。

1. §1.1 の値（DaemonSet の generation・`updateStrategy`・Pod の名前・UID・restartCount・起動時刻、`kubectl get ds kube-apiserver -o yaml` の全体）
2. 3 台の `df -h /` と `/var/log` の使用量（`sudo du -sh /var/log`）。`/var/log/kubernetes/audit` が無いこと
3. VIP（`https://192.168.1.101:6443/readyz`）と 3 台の `:6443/readyz` が `ok`
4. 全台 Ready、etcd 3/3 healthy
5. kube-apiserver の各 Pod のログの `E` の行の種類（入れた後に新しい種類が増えていないかを比べる）

### 2.2 etcd のバックアップ ✋

この変更は etcd に触らないが、ADR 0008 の「戻せるようにしておくこと」に従い、§3 の前に取る。porkadot は本番の render と同じ版（0.37.7）の clone を使う（流し方は `docs/k8s-upgrade/runbook-0.37.6.md` §1.4 と同じ形）。

```sh
porkadot etcd backup
```

時刻・ファイル名・サイズ・sha256 を記録する。`./backup/` は git に入れない（Secret が平文で入っている）。

### 2.3 差分を見る

```sh
kubectl kustomize assets/kubernetes > /tmp/audit-built.yaml   # 通ること
kubectl-admin diff -l app.kubernetes.io/component=kube-apiserver -k assets/kubernetes
```

`kubectl diff` で出てよいのは次だけ。ほかの差分があれば止めて調べる。

- ConfigMap `kube-system/kube-apiserver-audit-policy-<hash>` が新しく作られる（label に `app.kubernetes.io/component: kube-apiserver` と `kubernetes.unstable.cloud/installed-by: porkadot`）
- DaemonSet `kube-apiserver` の command の末尾に audit の引数 6 つ、volumeMounts に `audit-policy`（`/etc/kubernetes/audit`、readOnly）と `audit-log`（`/var/log/kubernetes/audit`）、volumes に ConfigMap と hostPath の 2 つ。generation が 1 つ上がる
- Service `porkadot-kubernetes`・`porkadot-kubernetes-latest` は差分なし

### 2.4 時間帯

1 台目の後に 30 分以上ログを見る（§3.4）。全体で 1 時間半ほどを、ほかの本番の作業と重ならない時間に取る。

## 3. 入れる

### 3.0 開始 ✋✋

§0 の開始の承認を取る。承認を得たら PR をマージし、マージした master で §1.4 を満たしてから進める。

### 3.1 更新の仕方を `OnDelete` にする ✋

```sh
kubectl-admin -n kube-system patch daemonset kube-apiserver --type merge \
  -p '{"spec":{"updateStrategy":{"type":"OnDelete","rollingUpdate":null}}}'
```

- Pod は入れ替わらない（3 つとも §2.1 と同じ UID）。generation は 1 つ上がる
- この間に porkadot の `install kubernetes` を流さない（apiserver の rollout の待ちが終わらない）

### 3.2 apply する ✋

§1.4 の apply を流す。

- 出力が `configmap/kube-apiserver-audit-policy-<hash> created`、`daemonset.apps/kube-apiserver configured`、Service 2 つが `unchanged` であること
- `OnDelete` なので、Pod は入れ替わらない。3 つの Pod の UID が変わっていないことを確かめる
- DaemonSet の `updateStrategy` が `OnDelete` のままであること（apply の manifest には `updateStrategy` が無いので、§3.1 の値が残る）

### 3.3 1 台目（192.168.1.113）を入れ替える ✋

```sh
kubectl-admin -n kube-system delete pod <.113 の kube-apiserver の Pod>
kubectl --context fraction -n kube-system get pods -l app.kubernetes.io/component=kube-apiserver -o wide -w
```

新しい Pod が .113 に作られ、Running・Ready になるのを待つ（startupProbe の上限は約 8 分）。

### 3.4 1 台目の確かめと、止める条件

Ready になったら §4 の確かめを .113 について行い、**30 分以上**見てから §3.5 に進む。

**止める条件**（当たったら 2 台目に進まず、§6.1 で戻すかを決めるために報告する）:

| # | 条件 |
|---|---|
| 1 | 新しい Pod が 5 分たっても Ready にならない。または CrashLoopBackOff・restart がある |
| 2 | kube-apiserver のログに `audit` を含む `E` の行がある（policy の読み込み、ファイルの書き込みの失敗） |
| 3 | 2 分たっても `/var/log/kubernetes/audit/audit.log` が無い、または大きくならない |
| 4 | Secret・ConfigMap・TokenReview・`serviceaccounts/token` の出来事に `requestObject` か `responseObject` が付いている（§4 の 4） |
| 5 | VIP の `/readyz` が 1 分を超えて応答しない。etcd が 2/3 を下回る |
| 6 | ログの増え方が 1 台で 40 MB/時を超える（7 日分を残すには 1 台で約 6.5 MB/時までに収まってほしい。40 MB/時だと 1 日分ほどしか残らないので、policy を見直す） |
| 7 | §2.1 の 5 に無い種類の `E` の行が、続けて出る |

- 1 台目だけが audit を持つ間、そのログには .113 の kube-apiserver が受けた要求だけが入る（VIP の振り分け次第で全体の一部）。増え方は 3 台そろった後にもう一度測る（§5）
- 6 は安全の問題ではない（上限の 1.1 GB で止まる）。残る日数が足りないと収集役が止まったときに穴が開くので、ここで一度止めて判断する

### 3.5 2 台目（.112）、3 台目（.111）✋

§3.3 と同じ形で 1 台ずつ入れ替え、Ready と §4 の 1〜3 を確かめてから次へ進む。止める条件は §3.4 の 1〜5・7。

### 3.6 更新の仕方を `RollingUpdate` に戻す ✋

**3 台とも新しいテンプレートの Pod になってから戻す**（`kubectl get ds kube-apiserver` の `UP-TO-DATE` が 3）。古いテンプレートの Pod が残ったまま戻すと、DaemonSet がその Pod を続けて入れ替える。

```sh
kubectl-admin -n kube-system patch daemonset kube-apiserver --type merge \
  -p '{"spec":{"updateStrategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":0,"maxUnavailable":1}}}}'
kubectl --context fraction -n kube-system get ds kube-apiserver -o jsonpath='{.spec.updateStrategy}'
kubectl-admin diff -k assets/kubernetes
```

- `updateStrategy` が §1.1 と同じであること。Pod が入れ替わらないこと（`updatedNumberScheduled` が 3）
- 全体の `kubectl diff` に、kube-apiserver のものの差分が無いこと（次の porkadot の `install kubernetes` で kube-apiserver が入れ替わらない）。ほかの差分が出たら、§2.1 の時点からあったものかを調べて記録する
- トークンを破棄する

## 4. ログが書かれていることの確かめ

1 台ずつ、ssh で node に入って読む。

1. `sudo ls -l /var/log/kubernetes/audit/` に `audit.log` があり、root の 0600。数十秒おいて大きくなっている
2. `sudo tail -n 1 /var/log/kubernetes/audit/audit.log` が 1 行の JSON で、`apiVersion` が `audit.k8s.io/v1`、`stage` が `ResponseComplete` か `ResponseStarted`（`RequestReceived` は出ない）
3. 直近の数千行の level の内訳（`None` の出来事は書かれないので、`Metadata` と `Request` だけが出る）。`Request` の出来事の `user.username` に、部品（`system:node:*`、`system:apiserver`、kube-system の controller の ServiceAccount）が無い
4. 次が 0 件: `objectRef.resource` が `secrets`・`configmaps`・`tokenreviews` か、`objectRef.subresource` が `token` で、`requestObject` か `responseObject` を持つもの
5. probe（`/livez`・`/readyz`）、`events`、`leases` の `update` の出来事が無い

読むときは node の上で `jq` を使うか、ssh の出力を作業端末の `jq` に流す。ファイルを作業端末に写して残さない（§0）。

## 5. ディスクの使用量の見方

- 使用量: `sudo du -sh /var/log/kubernetes/audit`、`df -h /`
- 増え方: `audit.log` の大きさを 2 つの時刻で読み、MB/時に直す。100 MB を超えると `audit-<時刻>.log` に回るので、回った後は回ったファイルも足す
- 残る日数のめやす: 1.1 GB ÷（1 台の MB/時 × 24）。7 日に届かなければ、`maxbackup` で先に消えている
- 入れた後、1 日目と 1 週間後に 3 台の増え方を測り、記録する。policy かローテーションを変えるときは、この PR と同じ形の PR にする（policy が変わると ConfigMap の名前が変わり、DaemonSet が入れ替わる。そのときもこの手順書の §3 の形で 1 台ずつ入れる）

## 6. 戻し方

**戻すのは手順書から外れる操作なので、その都度承認を取る。** etcd には触っていないので、restore は要らない。

### 6.1 途中（`OnDelete` の間）で戻す ✋

1. この PR の前の master（`06d24d4`）を別の場所に clone して checkout し、そこで §1.4 の apply を流す。DaemonSet のテンプレートが audit の無い形に戻る（`OnDelete` なので Pod はまだ入れ替わらない）
2. audit の入った Pod を、入れた順の逆に 1 台ずつ消し、Ready を待つ
3. §3.6 の patch で `RollingUpdate` に戻す
4. ConfigMap `kube-apiserver-audit-policy-<hash>` は client-side の apply では消えずに残る。害は無く、次の porkadot の `install kubernetes` の prune で消える（label `kubernetes.unstable.cloud/installed-by: porkadot` がある）。すぐ消すなら承認を取って `kubectl-admin delete`

### 6.2 入れ終わった後に戻す ✋

この PR を revert する PR を作ってマージし、§3.1〜§3.6 と同じ形（`OnDelete` で 1 台ずつ）で入れる。急ぐときは porkadot の `install kubernetes --node 192.168.1.111` でもよい（`RollingUpdate` で 3 台が続けて入れ替わる）。

### 6.3 node の上のログ

戻してもログのファイルは node に残る。消すかどうかは承認を取って決める（消すなら 3 台の `/var/log/kubernetes/audit/` を `sudo rm -r`）。

## 7. render の後の確かめ（今後の porkadot の更新のたび）

audit は porkadot の外で足しているので、porkadot で render した PR では、次を確かめる。

1. `kubectl kustomize assets/kubernetes` が通る（patch は DaemonSet の最初のコンテナの名前が `kube-apiserver` であることを `test` で確かめているので、違えば失敗する）
2. 組み立てた DaemonSet の command に、`--audit-` で始まる引数が 6 つずつ、1 回だけある（porkadot が同じ引数を出すようになったら二重になる）
3. `assets/bootstrap/manifests/kube-apiserver.bootstrap.yaml` に `--audit-` の引数が無い（`porkadot.yaml` の `extra_args` に audit の引数を足していない）
4. K8s のマイナーを上げた後は、本番の `system:controller:*` の ClusterRoleBinding の subject と、policy の controller の一覧を突き合わせる。足りない controller の書き込みは `Request` で残る（多く残る側）ので、急がないが次の PR で足す

## 8. 既知の注意

- **bootstrap の kube-apiserver には audit が無い。** 全台停止からの復旧（`install bootstrap node`）の間の要求はログに残らない（ADR 0009 の Decision 項 4）
- **ログのファイルは root の 0600。** 収集役（Alloy）は root か、ファイルを読める権限で動かす。読む場所は `/var/log/kubernetes/audit/audit.log` と、回った `audit-*.log`（gzip しない）
- **exec・attach・port-forward は verb `get` で出る**（kubectl の websocket の接続）。規則を書くときは `objectRef.subresource` で見る
- kube-apiserver は `--audit-policy-file` が読めないと起動しない。ConfigMap が無い状態で DaemonSet の Pod を作ると、Pod は `ContainerCreating` で止まる（ConfigMap は `install.sh` の最初の apply に入るよう label を付けてある）
- 確かめていないこと: ローテーションの実際の動き（回る大きさ・世代の消え方）、ディスクが埋まったときの kube-apiserver の振る舞い、arm64 の node での起動（image は今動いているものと同じ v1.37.2 なので pull は無い）

## 9. 手元で確かめたこと（2026-11-11）

kind v0.32.0 の `kindest/node:v1.37.0` に `registry.k8s.io/kube-apiserver:v1.37.2`（amd64）を入れ、static Pod の kube-apiserver に、この PR と同じ policy・引数・mount を足して確かめた。

- kube-apiserver v1.37.2 がこの policy を読み込んで起動し、hostPath（`DirectoryOrCreate`）の下に `audit.log`（root の 0600）を作って書いた
- 人（admin）の namespace・Deployment・ServiceAccount・ClusterRoleBinding の create、ServiceAccount の Deployment の patch、403 になった Role の create は `Request`（本文つき）。ConfigMap・Secret の create・get と `serviceaccounts/token` の create は誰の要求でも `Metadata`。controller・scheduler・kubelet の書き込みは `Metadata`
- Secret と ConfigMap の値は、平文でも base64 でもログに無かった。`managedFields` も無い
- exec は `Metadata` で、`ResponseStarted` と `ResponseComplete` の 2 つが残った
- probe・event・TokenReview・SubjectAccessReview の出来事は 0 件
- policy のファイルが無いと、kube-apiserver は `loading audit policy file: failed to read file path "/etc/kubernetes/audit/policy.yaml": … no such file or directory` で終わる
- 更新の仕方: `updateStrategy` を書かない manifest の DaemonSet を client-side の apply で作り、`OnDelete` に patch してからテンプレートを変えて apply し直すと、`updateStrategy` は `OnDelete` のまま残り、Pod は入れ替わらなかった。Pod を消すと新しいテンプレートで作られ、全部が新しい状態で `RollingUpdate`（`maxSurge: 0`、`maxUnavailable: 1`）に戻しても Pod は入れ替わらなかった
- `kubectl kustomize assets/kubernetes` で組み立てた DaemonSet と ConfigMap は、kind の kube-apiserver で `kubectl apply --dry-run=server --validate=strict` を通った

## 10. 記録

`docs/apiserver-audit/results/` に、時刻（UTC）、承認と知らせた内容、各台の入れ替えの時刻と新しい Pod の名前、§4 の確かめの結果（集計だけ）、§5 の増え方、止める条件に当たったかどうか、手順書との差を書く。
