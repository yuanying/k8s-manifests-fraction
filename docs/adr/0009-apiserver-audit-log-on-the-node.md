# 0009. kube-apiserver の audit のログを control-plane の node のファイルに書き、policy と引数は kustomization の patch で足す

- Date: 2026-11-11
- Status: Accepted

## Context

本番 `fraction` では、クラスタの中の自動化（ServiceAccount で動くエージェントなど）に書き込みの権限を渡していく。防ぐ仕組みを厚くするより、何が起きたかにすぐ気づける形を先に作る方針で、その元になるのが kube-apiserver の audit のログである（誰が・いつ・何に・何をしたか）。今の kube-apiserver は audit の引数を持たず、何も残していない。

前提になる本番の姿:

- kube-apiserver は porkadot が描く kube-system の DaemonSet で、control-plane の 3 台（arm64）に 1 つずつ hostNetwork で動く。証明書は Secret の volume で受け取る。更新は `RollingUpdate`（`maxUnavailable: 1`）
- `assets/kubernetes/manifests/` は porkadot が描いたもので、手で直すと次の render で消える。porkadot が上書きしないのは `assets/kubernetes/kustomization.yaml` で、ここに patch を書ける。`install.sh` はまず `app.kubernetes.io/component=kube-apiserver` のものだけを apply して rollout を待ち、その後に全体を apply する
- DaemonSet には checkpointer の annotation があるが、checkpointer は動いていない。control-plane が 3 台とも止まったとき、kube-apiserver の Pod はひとりでは戻らない。復旧は porkadot の `install bootstrap node` で、bootstrap の kube-apiserver（`assets/bootstrap/` の static Pod）を立て、それ越しに DaemonSet を立て直す
- porkadot は `porkadot.yaml` の `kubernetes.apiserver.extra_args` を、DaemonSet だけでなく bootstrap の kube-apiserver にも入れる（`Porkadot::Configs::Component#args` が `bootstrap: true` でも extra_args を混ぜる）。bootstrap の static Pod は porkadot の雛形で volume が決まっていて、kustomization の patch も届かない
- kube-apiserver は `--audit-policy-file` のファイルが読めないと起動しない（kind の v1.37.0 で `loading audit policy file: … no such file or directory` で終わることを確かめた）
- control-plane の node のディスクは 125 GB で、使っているのは 12 GB ほど
- ログの溜め場（Loki）と、node のファイルを読んで送る収集役（Alloy の DaemonSet）は、クラスタの中に別のリポジトリ（fleet-infra）で入れる

## Decision

**1. 運び方: kube-apiserver が control-plane の node の hostPath のファイルに書き、収集役が読んで送る。** audit の webhook の backend は使わない。

**2. 何を残すか（policy）。** 最初に当たった規則で level が決まる形で、次を守る。

- 基本は Metadata（誰が・どの動詞で・どのリソースの何に・結果）
- **クラスタの部品ではない身元**（人と、control-plane の外の ServiceAccount）**の書き込み**（create・update・patch・delete・deletecollection）は Request（要求の本文も）。何を変えたか（image・ServiceAccount・volume・RoleBinding の中身など）が見えないと、異常の規則が書けないため
- **Secret・ConfigMap・token の発行（`serviceaccounts/token`）は、誰の要求でも Metadata**。値をログに出さない
- exec・attach・port-forward・proxy は、誰の要求でも Metadata 以上で残し、どの規則でも落とさない
- 落とすもの（None）: probe・version・metrics、event、lease の get・list・watch・update、TokenReview と SubjectAccessReview、**部品の読み**
- 部品の書き込みは Metadata
- **「部品」は、Kubernetes と porkadot がどのクラスタにも置く身元だけで書く**: `system:nodes` の group、kube-apiserver 自身（`system:apiserver`）、porkadot が kube-system に置く kube-controller-manager・kube-scheduler・kube-proxy の ServiceAccount、Kubernetes の bootstrap policy の `system:controller:*` の ServiceAccount（kube-controller-manager は `--use-service-account-credentials=true`）。このリポジトリは public なので、このクラスタに固有の ServiceAccount やインスタンスの名前は policy に入れない。kube-system の名前空間で一括りにはしない（kube-system には人が使う admin の ServiceAccount もあり、その書き込みの本文を落とすことになるため）

**3. 設定の置き場: このリポジトリの `assets/kubernetes/kustomization.yaml` の patch と、そこから生成する ConfigMap だけで足す。** `porkadot.yaml` の `extra_args` は使わない。

- 引数（policy のファイル、ログのファイル、ローテーション）も patch で DaemonSet の command に足す。extra_args に書くと bootstrap の kube-apiserver にも入り、policy のファイルが無いので起動せず、全台停止からの復旧の道が壊れるため
- policy は ConfigMap で渡し、内容が変わると名前が変わる形にする（kube-apiserver は policy を起動のときにしか読まないので、変われば入れ替わる必要がある）。`install.sh` が最初に apply する組に入るよう、kube-apiserver の component のラベルを付ける
- ログは node の `/var/log/kubernetes/audit/` に置く。ローテーションは、収集役が止まっても数日分は node に残り、かつ control-plane のディスクを埋めない大きさにする（今の値は 1 ファイル 100 MB・10 世代・7 日、上限はおよそ 1.1 GB）
- porkadot に audit の機能を足すときは、引数・volume・policy をそこへ移し、この patch を外す。そのときも bootstrap の kube-apiserver が policy 無しで起動できることを保つ

**4. 全台停止からの復旧は audit に頼らない。** 復旧に使う bootstrap の kube-apiserver には audit を入れない。復旧のあいだ（bootstrap の kube-apiserver だけが動いている時間）の要求はログに残らないことを受け入れる。DaemonSet の Pod は bootstrap の kube-apiserver 越しに ConfigMap を受け取って起動する。checkpointer を動かすようにするときは、ConfigMap の volume も node に保存されるかを確かめてから入れる。

### 本 ADR で決定しないこと

- 収集役（Alloy）・溜め場（Loki）の置き方、残す期間、異常の規則と知らせ方（委譲先: fleet-infra の監視の構成）
- control-plane への入れ方・止める条件・戻し方（委譲先: `docs/apiserver-audit/runbook.md`）
- porkadot に audit の機能を足すときの形（委譲先: porkadot のリポジトリ）
- ログの量を見たあとの policy の見直し（委譲先: 本番に入れた後の記録。規則を変えるときは、この ADR の Decision 項 2（何を残すか）の範囲なら policy の変更だけで行う）

## Consequences

- 収集役や Loki が止まっても kube-apiserver は動き続け、止まっていた間のログは node に残る（ローテーションの範囲で）。webhook と違い、受け手がクラスタの中にあることによる循環が無い
- node の root を取られた場合は、ファイルを消されたり書き換えられたりしうる。これは node のファイルに書く形の限界で、溜め場への送りが途絶えたことに気づく側（クラスタの外の見張り）で拾う
- 人と ServiceAccount の書き込みの本文が残るので、変更の中身で規則が書ける。一方、Deployment の env に直接書いた秘密のような、Secret の外にある値は本文としてログに残る。ログのファイルは node の root だけが読め、溜め場を読める人も絞ることで受け入れる
- control-plane の node（arm64 の小さな機械）に、ログの書き込みとディスクの使用が増える。入れた後の量で policy とローテーションを見直す
- 引数を patch の JSON patch で command の末尾に足すので、porkadot が引数を足したり並べ替えたりしても壊れない。ただし porkadot が同じ引数を自分で出すようになったら二重になる。また patch は DaemonSet の最初のコンテナが kube-apiserver であることに頼る（patch の中で名前を確かめ、違えば kustomize が失敗する）。render の後にこの 2 点を確かめる
- bootstrap の kube-apiserver で動いている間の要求は残らない。全台停止は稀で、復旧の確実さを優先する
- policy の部品の一覧は Kubernetes の bootstrap policy の controller の名前に頼る。K8s の更新で controller が増えると、その controller の書き込みは Request で残る（多く残る側に倒れる）。K8s の段の後に `system:controller:*` の ClusterRoleBinding と突き合わせる

## Alternatives Considered

- **audit の webhook の backend で溜め場へ直接送る**: 受け手がクラスタの中なので、受け手が止まっている間の出来事が落ち、受け手の起動が kube-apiserver に頼る循環ができる
- **`extra_args` で引数を足す**: 上の Decision 項 3 の理由で、bootstrap の kube-apiserver が起動しなくなる
- **policy を node の上のファイルとして置く**: 3 台に手で配ることになり、git の版と DaemonSet の入れ替わりに結びつかない。復旧の道でも ConfigMap と差が無い（bootstrap の kube-apiserver は policy を使わず、DaemonSet の Pod はもともと Secret を API から受け取っている）
- **policy の部品を名前空間（kube-system の ServiceAccount 全部）で除く**: kube-system の admin の ServiceAccount の書き込みの本文まで落ちる

## 追記: status の subresource への書き込みは、誰の要求でも Metadata にする（2026-11-11）

本 ADR の「本 ADR で決定しないこと」の「ログの量を見たあとの policy の見直し」に当たる。Decision 項 2（何を残すか）の範囲の中の見直しで、policy の変更だけで行う。Decision 項 1・3・4 は変えない。

### Context

本番に入れた後、ログが 1 台で 7 日分を残せる量を大きく超えた。要求の多い台では、量の 6 割ほどが、ストレージの operator の ServiceAccount が自分の CR の `status` の subresource を数秒おきに `update` する出来事だった。部品ではない身元の書き込みなので Request（本文つき）で残っていた。1 件の大きさは Request で Metadata のおよそ 5 倍になる。

status は controller が観測した結果を書く場所で、書き換えても workload が何を動かすかは変わらない。異常の規則が本文で見たいのは spec の側（image・ServiceAccount・volume・RoleBinding の中身など）である。

### Decision

- **どのリソースの `status` の subresource への要求も、誰の要求でも Metadata にする。** core・名前付きの group・CRD の group のすべてに当てる。誰が・いつ・どのリソースの status を書いたか・結果は残り、本文だけが残らない。Decision 項 2 の「部品ではない身元の書き込みは Request」は、status の subresource を除いたものになる
- 決め方を特定の operator の名前にしない。クラスタに固有の ServiceAccount の名前を policy に書かずに済み（このリポジトリは public）、別の operator が増えても同じ扱いになる
- 次は変えない: exec・attach・port-forward・proxy はどの規則でも落とさない。Secret・ConfigMap・token は誰の要求でも Metadata。部品の読みは落とし、部品の書き込みは Metadata。status と名の付かない subresource（`scale` など）と spec への書き込みは、部品ではない身元なら Request のまま
- 読み（get・list・watch）は落とさない。誰が何を読んだかを残す。node に残る日数が足りないことは、収集役と溜め場（Loki）に送ることで補う

### Consequences

- 要求の多い台の量は半分ほどになる見込み。ただし 1 台で 7 日分を残す目安にはまだ届かない。残りの多くは spec の側の書き込み（GitOps の controller の自分の CR への `patch` など）と読みで、本文や記録を残すために受け入れる
- status への書き込みの本文は残らない。status を書き換えて controller や人を欺く操作（たとえば Service の LoadBalancer の宛先、CertificateSigningRequest の status に載る発行済みの証明書、Pod の Ready の状態）は、誰が・いつ・どのリソースに書いたかでしか追えない。spec の側と違い、status の書き込みの権限を持つ身元は限られるので、身元と頻度で見る規則で拾う
- 規則がリソースの名前ではなく subresource の名前で当たるので、新しい CRD や operator が増えても policy を変えずに済む

## Related ADRs

- Related: ADR-0008 本番の変更は節目でだけ承認を取り、短命の admin トークンで行い、etcd のバックアップと前の版の render で戻せるようにする（入れ方はその Decision の「承認」「資格」「戻せるようにしておくこと」に従う）

## References

- Kubernetes のドキュメント「Auditing」（https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/、2026-11-11 確認）
- porkadot の `lib/porkadot/configs/kubernetes.rb` の `Porkadot::Configs::Component#args` と、`lib/porkadot/assets/bootstrap/manifests/kube-apiserver.bootstrap.yaml.erb`（2026-11-11 確認）
- 本番の DaemonSet `kube-system/kube-apiserver` の `updateStrategy`、Pod の一覧（checkpointer が無いこと）、`system:controller:*` の ClusterRoleBinding、control-plane のディスクの容量（`fraction-auditor` で読んだ。2026-11-11）
- kind（`kindest/node:v1.37.0` に `registry.k8s.io/kube-apiserver:v1.37.2` を入れたもの）で、この policy と引数の kube-apiserver が起動してログを書くこと、policy のファイルが無いと起動しないことを確かめた（2026-11-11。記録は `docs/apiserver-audit/runbook.md` の「手元で確かめたこと」）
- 追記（status の subresource）の根拠:
  - Kubernetes v1.37.2 の `staging/src/k8s.io/apiserver/pkg/audit/policy/checker.go` の `ruleMatchesResource` と、`staging/src/k8s.io/apiserver/pkg/apis/audit/v1/types.go` の `GroupResources`（`group` の `*` がすべての group に、`resources` の `*/status` がすべての status の subresource に当たる。2026-11-11 確認）
  - 本番の 3 台の audit のログの直近 2 万行の集計（`fraction` の control-plane で集計だけを読んだ。2026-11-11 10:4xZ）。要求の多い台は約 36 MB/時で、その 63% が部品ではない身元の status への書き込み（Request）だった。同じ出来事を Metadata にすると、その台は約 18 MB/時になる。ほかの台では status への書き込みはほぼ無かった
  - kind（`kindest/node:v1.37.0` に `registry.k8s.io/kube-apiserver:v1.37.2` を入れたもの）で、人と ServiceAccount の、CRD の CR・Deployment・Service・Namespace の status への update・patch が Metadata、同じ身元の spec と `scale` への書き込みが Request で残り、Secret・ConfigMap・token・exec・probe・event・lease の扱いが変わらないことを確かめた（2026-11-11。記録は `docs/apiserver-audit/runbook-status-metadata.md`）
