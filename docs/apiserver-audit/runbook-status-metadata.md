# audit の policy の見直しを入れる手順書: status の subresource への書き込みを Metadata にする（本番 `fraction`）

kube-apiserver の audit の policy に、どのリソースの `status` の subresource への要求も誰の要求でも `Metadata` にする規則を足し、本番に入れる手順。判断と理由は [ADR 0009](../adr/0009-apiserver-audit-log-on-the-node.md) の「追記: status の subresource への書き込みは、誰の要求でも Metadata にする」。入れるものはこの手順書と同じ PR にある。

入れ方は [audit のログを入れる手順書](runbook.md)（以下「元の手順書」）の §3 と同じ形で、DaemonSet を一時的に `OnDelete` にして control-plane を 1 台ずつ入れ替える。この文書には、元の手順書と違うところと、今回に固有の確かめだけを書く。書いていない手順は元の手順書に従う。

| | 入れる前 | 入れた後 |
|---|---|---|
| policy | ConfigMap `kube-system/kube-apiserver-audit-policy-2gd9b4f598` | ConfigMap `kube-system/kube-apiserver-audit-policy-97tmd5m5gk`（status の規則が増えたもの）。名前は `kubectl kustomize assets/kubernetes` の出力で確かめる |
| status の subresource への書き込み（部品ではない身元） | `Request`（本文つき） | `Metadata` |
| ほかの規則、kube-apiserver の引数・mount・ローテーション | — | 変えない |
| `porkadot.yaml`・`assets/kubernetes/manifests/`・bootstrap の kube-apiserver・etcd | — | 変えない |

## 0. 役割と約束ごと

元の手順書 §0 と同じ。承認の節目は ✋✋ **開始** の 1 つで、この PR の差分（§2 の `kubectl diff`）、§1 のベースライン、§3 の止める条件、§5 の戻し方を見せ、承認を得て PR をマージしてから §3 に入る。audit のログの中身は写さず、集計だけを記録する。

## 1. 前提とベースライン

- 元の手順書 §1.1〜§1.4 の形で、今の姿を読み直す。DaemonSet `kube-system/kube-apiserver` が 3/3 Ready・`RollingUpdate`（`maxSurge: 0`、`maxUnavailable: 1`）で、3 つの Pod がどれも ConfigMap `kube-apiserver-audit-policy-2gd9b4f598` を mount していること
- 元の手順書 §2.1 の 1・3・4・5 を取る
- **3 台の audit のログの増え方**（元の手順書 §5 の測り方で 30 分）と、3 台それぞれの直近 2 万行で、`objectRef.subresource` が `status` の出来事の level の内訳と大きさの合計。入れた後と比べる

### etcd のバックアップは取らない

元の手順書 §2.2（etcd のバックアップ）は、今回は行わない。この変更は ConfigMap を 1 つ足して DaemonSet のテンプレートの ConfigMap の名前を変えるだけで、etcd のデータの形にも etcd 自体にも触らない。§5 の戻し方も前の版の apply と Pod の入れ替えで、restore を使わない。前回（audit を入れたとき）も本人の決定でバックアップを取らずに進めた。

## 2. 差分を見る

元の手順書 §2.3 の 2 つのコマンドを流す。`kubectl diff` で出てよいのは次だけ。ほかの差分があれば止めて調べる。

- ConfigMap `kube-system/kube-apiserver-audit-policy-<新しい hash>` が新しく作られる（label は前と同じ）。中身は前の policy に status の規則が 1 つ増えたもの
- DaemonSet `kube-apiserver` の volume `audit-policy` の ConfigMap の名前が、新しい hash の名前に変わる。generation が 1 つ上がる。引数・volumeMounts・ほかの volume は変わらない
- Service `porkadot-kubernetes`・`porkadot-kubernetes-latest` は差分なし
- 古い ConfigMap `kube-apiserver-audit-policy-2gd9b4f598` は差分に出ない（client-side の apply は消さない。§4）

## 3. 入れる

元の手順書の §3.0〜§3.6 を、この順で行う（✋✋ 開始、`OnDelete`、apply、1 台ずつの入れ替え、`RollingUpdate` に戻す）。違いは次のとおり。

- §3.2 の apply の出力は、ConfigMap が `created`、DaemonSet が `configured`、Service 2 つが `unchanged`
- 1 台目は、§1 で status への書き込みが最も多かった台にする（新しい規則の効き目がその台で見える）。2 台目・3 台目の順は問わない

### 3.1 1 台目の確かめと、止める条件

1 台目が Ready になったら、元の手順書 §4 の 1〜5 に加えて次を確かめ、**30 分以上**見てから 2 台目に進む。

- 新しい Pod の起動の後の出来事で、`objectRef.subresource` が `status` で level が `Request` のものが 0 件。status への書き込み（`update`・`patch`）の出来事が `Metadata` で残っている（数えるのは新しい Pod が書き始めた後の行だけ）
- status 以外への、部品ではない身元の書き込みが、引き続き `Request` で残っている。30 分のうちにその台へ 1 件も来なかったときは、ほかの台（古い Pod）で `Request` になっている種類が、その台で `Metadata` になっていないかを見比べる。判断がつかなければ止めて報告する
- 部品の読みが落ちたまま（`Request` の出来事に部品のユーザーが無い、部品の get・list・watch の出来事が無い）

止める条件は元の手順書 §3.4 の表の 1〜5・7 に、次を足したもの。

| # | 条件 |
|---|---|
| 8 | 新しい Pod の出来事に、status への書き込みで `Request` のものがある（規則が効いていない） |
| 9 | 新しい Pod の出来事で、status 以外への部品ではない身元の書き込みが `Metadata` になっている（規則が広く当たりすぎている） |

元の手順書の条件 6（1 台で 40 MB/時）は、3 台がそろった後に §3.2 で見る。入れ替えのたびに長く続く接続が別の台へ移り、1 台目だけの間の増え方は §1 と比べられないため。

### 3.2 3 台がそろった後

- 元の手順書 §4 の確かめを 3 台について行う
- 元の手順書 §5 の測り方で 3 台の増え方を 30 分測り、§1 と比べる。台ごとの偏りは入れ替えで変わるので、比べるのは 3 台の合計と、status の出来事の大きさの合計
- 見込みは、§1 のときに status への書き込みが量の大半を占めていた台で、量が半分ほどになること（ADR 0009 の追記の References）。3 台の合計が §1 より減っていなければ報告する
- 1 日目にもう一度測り、記録する

## 4. 古い ConfigMap

- 古い ConfigMap `kube-apiserver-audit-policy-2gd9b4f598` は apply では消えずに残る。害は無い（mount している Pod が無くなるだけ）
- **3 台の入れ替えが終わるまでは消さない。** 戻すとき（§5）に、古いテンプレートの Pod がこれを mount する
- 入れ終わった後は、次の porkadot の `install kubernetes` の prune で消える（label `kubernetes.unstable.cloud/installed-by: porkadot` がある）。それより前に消すなら、手順書から外れる操作として承認を取って `kubectl-admin delete` で消す。§3.2 の 1 日目の測定を終えるまでは残しておくのを勧める

## 5. 戻し方

元の手順書 §6 と同じ形で、その都度承認を取る。etcd には触っていないので、restore は要らない。

- 途中（`OnDelete` の間）で戻す: この PR の前の master を別の場所に clone して checkout し、元の手順書 §1.4 の apply を流す。DaemonSet のテンプレートが古い ConfigMap を指す形に戻る。古い ConfigMap が残っていなくても、この apply が作り直す。その後、新しい policy の Pod を入れた順の逆に 1 台ずつ消し、`RollingUpdate` に戻す
- 入れ終わった後に戻す: この PR を revert する PR をマージし、この手順書の §3 の形で入れる

## 6. 手元で確かめたこと（2026-11-11）

kind v0.32.0 の `kindest/node:v1.37.0` に `registry.k8s.io/kube-apiserver:v1.37.2`（amd64）を入れ、static Pod の kube-apiserver に元の手順書と同じ引数・mount を足して、前の policy と新しい policy を入れ替えて確かめた。人は kubeadm の admin、ServiceAccount は cluster-admin を結んだもの（token で接続）。

- 前の policy では、CRD の CR と Deployment の status への `patch`・`update` が、人と ServiceAccount のどちらでも `Request` だった
- 新しい policy では、同じ要求が `Metadata` になった。CRD の CR（`update`・`patch`）、Deployment（`patch`）、core の group の Service と Namespace（`patch`）で確かめた
- 同じ身元の spec への `patch`（CR・Deployment）と、Deployment の `scale` の subresource への書き込みは `Request` のままだった
- Secret・ConfigMap の create と `serviceaccounts/token` の create は `Metadata` で、値はログに無かった。exec は `Metadata`。probe・event・lease の `update` の出来事は 0 件
- controller（deployment-controller）と kubelet の status への書き込みは `Metadata`。部品の `Request` の出来事と、部品の読みの出来事は 0 件
- `kubectl kustomize assets/kubernetes` で組み立てた ConfigMap は、kind の kube-apiserver で `kubectl apply --dry-run=server --validate=strict` を通った。前の版との差は、ConfigMap の中身と名前、DaemonSet の volume の ConfigMap の名前だけだった
- 元の手順書 §7 の 2・3（DaemonSet の audit の引数が 6 つで 1 回ずつ、bootstrap の kube-apiserver に audit の引数が無い）は変わらない

確かめていないこと: arm64 の node での起動（image は今動いているものと同じ v1.37.2）、本番の量が見込みどおりに減ること（§3.2 で測る）。

## 7. 記録

`docs/apiserver-audit/results/` に、元の手順書 §10 と同じ形で書く。§1 と §3.2 の増え方の比較と、status の出来事の level の内訳（集計だけ）を加える。
