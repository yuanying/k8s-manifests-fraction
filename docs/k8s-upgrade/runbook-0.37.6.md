# porkadot 0.37.6 の手順書: K8s を v1.37.2 へ、CoreDNS を v1.15.0 へ上げる（本番 `fraction`）

本番クラスタ `fraction` の Kubernetes を v1.37.1 から v1.37.2 へ（patch の更新）、CoreDNS を v1.14.7 から v1.15.0 へ上げる手順。porkadot を 0.37.5 から 0.37.6 に替え、**`install kubernetes` を 1 回流して control-plane と CoreDNS を上げ、続けて control-plane から 1 台ずつ `install kubelet` を流す**（drain しない）。2 つを 1 回の本番作業でまとめて上げるのは 2026-10-30 のユーザー判断。
K8s の部分は段 8 の手順書 `runbook-stage-8.md`（以下「段 8 の手順書」）の形（`install kubernetes` → control-plane を 1 台ずつ → worker を 1 台ずつ、✋ の置き方、止める条件、ロールバック）、CoreDNS の部分は `runbook-coredns-seccomp.md`（以下「seccomp の手順書」。CoreDNS の Pod が入れ替わる本番。DNS の監視）の形にし、**この 2 つから変わる点を中心に書く**。etcd はマイナーも patch も変わらない。

| | 更新前 | 更新後 |
|---|---|---|
| porkadot | 0.37.5（`aacfba7`、タグ `v0.37.5`） | **0.37.6**（`c01edef`、タグ `v0.37.6`） |
| kube-apiserver、kube-controller-manager、kube-scheduler、kube-proxy | v1.37.1 | **v1.37.2** |
| kubelet、kubectl（ノードの `/opt/bin`） | v1.37.1 | **v1.37.2** |
| CoreDNS | v1.14.7（`RuntimeDefault`） | **v1.15.0**（`RuntimeDefault` のまま。Corefile・引数・RBAC は変わらない） |
| etcd（static Pod）、etcdctl・etcdutl | 3.7.3（cluster version・storage 3.7.0） | 変えない（`etcd-server.yaml` に差分が無い） |
| crictl、CNI plugins | v1.37.0、v1.9.1 | 変えない |
| kubelet の `config.yaml`・`kubelet.service` | `containerRuntimeEndpoint` は `config.yaml` | 変えない（差分が無い） |
| cnidaria、MetalLB（pool を含む）、kubelet-serving-cert-approver、kube-dns-autoscaler | v0.1.2、v0.14.5、0.12.1、v1.11.0 | 変えない（マニフェストの差分が無い） |
| containerd、runc、Longhorn | 2.3.6、1.5.1、v1.13.0 | 変えない |

porkadot 0.37.6 に入った PR は porkadot#80（マージ `acb27bb`。`coredns.yaml.erb` のイメージを v1.15.0 に）、porkadot#79（`51959fa`。`default.yaml` の `kubernetes_version` を v1.37.2 に）、porkadot#81（`c01edef`。版を 0.37.6 にする）。v0.37.5 から v0.37.6 の差分は、この 3 つのほかは Renovate の設定、`.ruby-version`、GitHub Actions だけで、**`install`・`etcd backup`・`etcd restore` の実装は 0.37.5 と同じ**。`--node` に `porkadot.yaml` の `nodes` のキーでない値を渡すと、0.37.1 から入った porkadot#63 で exit 1 で止まる（段 8 で IP を渡して全ノードに流れた件は起きない。§1.4）。

dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で、2 つを別々に先に通してある。

- **CoreDNS v1.15.0**: porkadot-dev の `docs/k8s-upgrade/verification-coredns-1.15.md`（以下「CoreDNS の dev の記録」。porkadot-dev#25、2026-10-30 06:45〜06:59Z、porkadot `acb27bb`）
- **K8s v1.37.2**: porkadot-dev の `docs/k8s-upgrade/verification-1.37.2.md`（以下「1.37.2 の dev の記録」。porkadot-dev#26、2026-10-30 07:14〜09:30Z、porkadot `51959fa`。dev には CoreDNS v1.15.0 が先に入っていた）

`51959fa` は 0.37.6 と版の番号（#81）だけが違う。dev で分かったことは次のとおり。

- **`install kubernetes` は、どちらの検証でも 3 回（上げ・戻し・上げ直し）とも 1 回目で rc 0**。K8s の patch は約 3 分（apiserver の 3 台の入れ替えに約 2 分半）、CoreDNS だけのときは 16〜32 秒
- **`install kubelet` は 11 回とも rc 0、1 台 8〜15 秒。どの台でもコンテナは 1 つも再起動せず、etcd の static Pod も作り直されなかった**（`etcd-server.yaml` が変わらないため。段 8 と違うところ）。iscsid の PID は 7 台とも同じ。CSR は出ない
- **DNS**: CoreDNS の Pod の入れ替わりの間、Service への 1 秒ごとの問い合わせで、3 回の入れ替わりのうち 1 回、PTR の 1 サンプルが 1 秒の timeout で落ちた（最初の上げ、最後の古い Pod が止まる瞬間。原因は特定できなかった）。K8s の patch の間（7080 サンプル）は FAIL 0
- **v1.15.0 も `RuntimeDefault` の下で動く**（`Seccomp: 2`、規則 13、約 11 分 restart 0、ログに拒否の跡なし）。`:53`（UDP・TCP）の答えと rcode、`:8080`・`:8181`・`:9153` は上げる前と同じ
- **cache から返す外の名前の答えに AA が付かなくなる**（coredns#8419）。rcode と答えは変わらない
- porkadot#80 の本文の「IPv6 の Pod の名前が引けるようになる」は、porkadot の Corefile（`pods insecure`、`autopath` なし）では当たらない。答えは前後で同じ
- **v1.37.2 の kube-proxy は、`nf_conntrack_max` がすでに望む値以上なら書かない**（kubernetes#142198）。起動のログの `Setting nf_conntrack_max` が出なくなる。ノードの値は変わらない
- 戻しは、kubelet を先に、control-plane を最後に戻す。戻しの `install kubernetes` で VIP が 1 サンプル 000 になることがあった（2 回）。各ノードの kubelet の起き直しの時刻に、LoadBalancer の v6 が 1〜2 サンプル 000 になった（`systemd-networkd` の再起動。前の段からのもの）

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **CoreDNS と K8s を 1 回の `install kubernetes` で流す組み合わせ**（dev は別々に流した）。apiserver の rollout の後の全体の apply で、KCM・scheduler・kube-proxy の rollout と CoreDNS の Pod の入れ替わりが同時に起きる（§3.2）。見ることは §3.3 の前に決めておく（§2.1 の 13）
- **本番の DNS の負荷と、本番の CoreDNS の載るノードでの pull**（事前に pull する。§2.5）
- **arm64 の control-plane での v1.37.2**（dev は amd64 だけ。イメージとバイナリの arm64 は確かめてある。§1.5）
- **本番の Longhorn のボリュームがアタッチされたままの `install kubelet`**（2026-10-30 09:5xZ は chirico 9 本、duchamp 6 本、oeilvert 1 本）。段 3〜8 の本番では同じ形で問題が無かった
- **duchamp**（冷却ファンが壊れたまま、`no_turbo=1` で動かしている。`docs/duchamp-power-loss-2026-10/record.md` §6）。`install kubelet` は再起動しないが、前後で `no_turbo` と温度を見る

## 0. 役割と約束ごと

段 8 の手順書 §0 と同じ形で、次のとおりにする。

- **承認の節目は 1 つ**（計画 §9.1「本番の各段の開始」。etcd のマイナー更新を含まないので、段 5・段 8 の 2 つ目の節目は無い）。この手順書では ✋✋ を付けた。
  - ✋✋ **開始**: render の差分（§2.6。この手順書と同じ PR）、§2.2 のベースライン、§2.3 の監視、§2.11 の時間帯、§2.5 の事前 pull と §2.4 のバックアップ、§6 の止める条件、§7 のロールバックの形を見せ、PR をマージしてから、事前 pull（§2.5）の前
- **節目の後の手順は、ユーザーに知らせるだけで進めてよい（✋）。** イメージの事前 pull、etcd のバックアップ、`install kubernetes`、etcd のリーダーの移動、`install kubelet`（1 台ずつ）、`netcheck.sh` と NetworkPolicy の確認（一時的な名前空間）は、この手順書に書いた形なら ✋ で、1 つずつ承認を取るものではない。✋ の前に、何をするかを知らせる。
- **runbook から外れる操作（ロールバック、`etcd restore`、drain への切り替え、Pod の手での削除、Deployment の手での編集・scale・`rollout undo`、ConfigMap の書き換え、iSCSI のセッションの logout、unattended-upgrades の止め・手での apt の操作、duchamp の `no_turbo` の書き換え、想定外の対処）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認は、知らせずに行ってよい。**1 台ずつ行う。** 時刻はすべて UTC で記録する（control-plane のホストの時刻は JST）。

## 1. 前提

### 1.1 本番の今の姿

始める前に次を確かめる（読み取り）。2026-10-30 09:4x〜09:5xZ（この手順書を書いたとき）の値は §2.2 の表にある。当日に読み直す。

- 段 8（v1.37.1、etcd 3.7.3）、CoreDNS の seccomp の直し（`RuntimeDefault`）、cnidaria v0.1.2、片付けの単位 A〜D が済んでいる（`results/stage-8/`、`results/coredns-seccomp/`、`docs/cni/results/cnidaria-0.1.2/`、`results/cleanup/`）
- 8 台 Ready、全台 v1.37.1、`containerd://2.3.6`。etcd 3/3 が 3.7.3（cluster version・storage 3.7.0）
- duchamp は 2026-10-27 の電源断から戻っている（`docs/duchamp-power-loss-2026-10/record.md`）。ファンは壊れたままで、`no_turbo=1` で動いている

**段 8 の後（2026-10-23 23:0xZ〜）に、このタスクの手順の外で変わったこと**（読み取りで見つけたもの。この手順書のベースラインと止める条件は、変わった後の姿を前提にする）:

| 変わったこと | 時期 | この手順書での扱い |
|---|---|---|
| **rasp02（.112）が shutdown して起き直した**（`last -x` の `shutdown system down` と、`journalctl --list-boots`。このタスクの記録には無い）。その後 **iscsid は動いていない**（`MainPID=0`、`iscsid.socket` は active。control-plane には Longhorn のボリュームが無く、誰も iscsid を呼ばない） | 10-24 12:11Z | `install kubelet` の `install-pkgs.sh` が `systemctl start iscsid` を流すので、**.112 では「0 → 新しい PID」が想定どおり**（段 8 の手順書 §2.7 の oeilvert と同じ見分け方。§4.4 の 8）。etcd の Pod は restartCount 1 |
| **duchamp の電源断と復旧**（2026-10-27 16:51〜23:32Z）。iscsid は起動のときの PID（3589、10-27 23:33:23Z）、kubelet は NRestarts 1 | 10-27 | 前後の `no_turbo` と温度を見る（§5.3 の 21）。duchamp のエンジン 1 本（`pvc-3a665d04`、natsumi-myao）が iscsid より 1 秒早く起きていて `older-than-iscsid` と出る。エンジンが v1.13.0 なので止める理由にしない（段 8 の手順書 §2.7） |
| **CoreDNS の seccomp の直し**（RuntimeDefault）で、CoreDNS の Pod は chirico と oeilvert に入れ替わった。ReplicaSet `coredns-6bfc79bb8`（revision 11） | 10-26 07:04Z | §2.2 の 13〜16 |
| **natsumi の penelope**（名前空間 `natsumi` に CronJob `natsumi-backup-penelope`、Service `natsumi-sshd-penelope`（`…ace::135`）、Longhorn のボリューム `natsumi-penelope`。別タスク） | 10-29〜30 | Longhorn は 17 本（attached healthy 16、detached 1 は `natsumi/natsumi-penelope`。09:5xZ の時点で最後の Pod は 05:40Z）。detached のボリュームはこの作業で触らない |
| 作業端末の kubectl が v1.37.1 になった | — | v1.37.2 の server と ±1 に入る |

### 1.2 kubeconfig の運用

段 8 の手順書 §1.2 と同じ（確認は `fraction-auditor`）。本番に書き込むのは porkadot の `etcd backup`・`install kubernetes`・`install kubelet`（ノードの上の etcdctl と admin の kubeconfig）と、イメージの事前 pull（ノードの `crictl pull`）で、どれもトークンは要らない。

**`infra-admin` のトークンを使うのは、§5.5 と §6 の NetworkPolicy の確認（`tools/npcheck.sh`）だけ**（段 8 の手順書 §1.9 と同じ。`netcheck.sh` はトークンを使わない）。トークンのファイル名は `/tmp/k8u-0376-admin-token`（モード 600）にし、§6 の後に消す。

### 1.3 SSH

段 8 の手順書 §1.3 と同じ（worker は `ssh yuanying@<IP>`、control-plane は `ssh ubuntu@<IP>`。**名前ではなく IP で入る**。control-plane には `unset LC_ALL` してから入る。**サンドボックスの中で流す**）。2026-10-30 09:5xZ にこの手順書を書いたとき、8 台ともサンドボックスの中から §1.7 の `nodes.sh` を、braque と oeilvert から `dns-watch2.sh` を、.111 から `etcd-probe.sh` を流せた。

### 1.4 porkadot の置き場と流し方

段 8 の手順書 §1.4 と同じ形で、タスクディレクトリの独立の clone を使う。

| 用途 | 置き場 | 版 |
|---|---|---|
| **当日**（`etcd restore` を含む） | `/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-6` | v0.37.6（`c01edef`、detached） |
| **§7 の戻し** | `/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-5`（cnidaria v0.1.2 の本番で使ったもの。触らずに残す） | v0.37.5（`aacfba7`、detached） |

- 2026-10-30 09:4xZ に `git ls-remote https://github.com/yuanying/porkadot.git` で、GitHub の `refs/tags/v0.37.6`（tag object `95fcc22`）と `^{}`（`c01edef`）、`refs/tags/v0.37.5`（`812d11d`）と `^{}`（`aacfba7`）が、2 つの clone と一致することを確かめた。`lib/porkadot/version.rb` はそれぞれ 0.37.6 と 0.37.5。どちらの clone も `git status --short` が空。push しない・書き換えない
- この 2 つの clone で §2.6 の render と、§7.1 の 0.37.5 の render の確かめを流した

**このリポジトリのルートを cwd にして** 流す。

```sh
P=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-6
git -C $P describe --tags          # v0.37.6
cd <このリポジトリの checkout>     # §2.6 の PR をマージした master
BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

以下、この形を `porkadot <サブコマンド>` と書く。

- 始める前に `BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot help` が動くことを確かめる
- 作業ツリーの `assets/` と `porkadot.yaml` に PR の外の変更が無いこと（`git status --short assets porkadot.yaml` が空）
- **`--node` には `porkadot.yaml` の `nodes` のキーを渡す**: control-plane は IP（`192.168.1.111`〜`113`）、worker は名前（`pablo`、`braque`、`oeilvert`、`duchamp`、`chirico`）。0.37.6 は一致しない値を exit 1 で止める（porkadot#63）が、流す前に `grep -nE '^  [^ ]+:$' porkadot.yaml` でキーを確かめる
- 流す porkadot のコマンドは、`etcd backup`、`install kubernetes --node 192.168.1.111`、`install kubelet --node <ノードのキー>` の 3 つだけ。**`install all`、`--node` なしの `install kubelet` と `install kubernetes`、`render`（当日は render しない）、`setup-node`、`setup-containerd`、`etcd restore`（§7 の承認を得たときだけ）は流さない**
- 当日は 0.37.6 とこの PR をマージした master の組み合わせだけを使う。戻しは §7 の `/tmp` の clone（この PR の前の master）と 0.37.5 の組み合わせで行い、組み合わせを取り違えない

### 1.5 入れる版を確かめる

作業の当日に確かめ直す（読み取り）。

```sh
curl -fsSL https://dl.k8s.io/release/stable-1.37.txt     # v1.37.2
A='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
for i in kube-apiserver kube-controller-manager kube-scheduler kube-proxy; do
  curl -sL -H "Accept: $A" https://registry.k8s.io/v2/$i/manifests/v1.37.2 | jq -r '[.manifests[].platform.architecture] | join(",")'
done                                                       # amd64 と arm64 を含む
curl -sL -H "Accept: $A" https://registry.k8s.io/v2/coredns/coredns/manifests/v1.15.0 | jq -r '[.manifests[].platform.architecture] | join(",")'
for a in amd64 arm64; do for b in kubelet kubectl; do curl -sIL -o /dev/null -w "$b $a %{http_code}\n" https://dl.k8s.io/v1.37.2/bin/linux/$a/$b; done; done
```

2026-10-30 09:5xZ の時点（タスクディレクトリの `notes/runbook-0-37-6/versions.txt`）:

- `stable-1.37.txt` も `stable.txt` も v1.37.2
- registry.k8s.io の `kube-apiserver`・`kube-controller-manager`・`kube-scheduler`・`kube-proxy` の v1.37.2 は、manifest list に `linux/amd64`・`linux/arm64`（と ppc64le・s390x）がある。dev は arm64 の image config の `architecture` も確かめた（1.37.2 の dev の記録の「入手」）
- `registry.k8s.io/coredns/coredns:v1.15.0` は 200 で、amd64・arm・arm64・loong64・ppc64le・riscv64・s390x を含む。v1.15.1 は 404。GitHub の CoreDNS の最新のリリースも v1.15.0
- `dl.k8s.io` の kubelet と kubectl の v1.37.2（amd64、arm64）は、どれも 200。dev は `.sha512` との一致と ELF の arch も確かめた
- crictl v1.37.0、etcd 3.7.3、CNI plugins v1.9.1 はノードに入っているもので、変わらない（`install-deps.sh` は版の印・リンクが同じなら落とさない）
- 作業端末の kubectl は v1.37.1

### 1.6 render に使った secrets と、本番との突き合わせ

secrets の在りかと扱いは段 1 の手順書 §1.6 と同じ（sops。平文をディスクに書かない）。この PR の render は、sops の中身を新しく作らない（§2.6。作り直される証明書は元に戻した）。`kube-apiserver.secrets.yaml`・`kube-controller-manager.secrets.yaml` は、版のラベルのほかは data のハッシュが同じであることを確かめた（§2.6）。本番との突き合わせは、段 8 の手順書 §1.6 と同じスクリプト（タスクディレクトリの `notes/runbook-stage-8/scripts/secrets-check.sh`。復号をパイプで流してハッシュだけを比べる）で 2026-10-30 10:0xZ に流し直し、**30 項目すべて一致した**（CA と ConfigMap `kube-root-ca.crt`、VIP と 3 台の 6443 の証明書、.111 の apiserver の Pod（`kube-apiserver-qxb4k`）の Secret の 13 ファイル、3 台の `/etc/etcd/pki` の 9 ファイル、CA の鍵と証明書の 3 組。出力は `notes/runbook-0-37-6/secrets-check.txt`）。どれかが食い違えば、render の差分も assets も信用せず、止めて調べる。

### 1.7 確認に使うスクリプト

タスクディレクトリの `notes/runbook-0-37-6/scripts/` に置いた（dev の `notes/dev-coredns-1-15/scripts/`・`notes/dev-k8s-1-37-2/scripts/` と seccomp の手順書の `notes/runbook-coredns-seccomp/scripts/` を本番の値にしたもの）。`prepull.sh` のほかは読み取りだけ。出力先はどれも引数で渡す（当日は `notes/0-37-6/` の下）。

| スクリプト | 中身 |
|---|---|
| `snap.sh <dir>` | `fraction-auditor` で、server の版、Node、全 Pod（UID・restartCount・phase）、Running / Completed 以外の Pod、kube-system の DaemonSet・Deployment（generation・イメージ）、CoreDNS と autoscaler の Deployment・ReplicaSet・Pod の yaml、ConfigMap `coredns` と Corefile の SHA512・resourceVersion、Service `kube-dns` と EndpointSlice、control-plane と CoreDNS の Pod の events、CoreDNS の各 Pod のログと前のコンテナのログ、kube-proxy のログの conntrack・proxier・`E`・`W` の行、Longhorn のボリューム、CSR |
| `nodes.sh <dir> [IP...]` | 8 台（または指定の台）に IP で ssh し、このリポジトリの `docs/k8s-upgrade/tools/node-state.sh`（`/opt/bin` の向き先、CNI、iscsid、iSCSI のセッション、Longhorn のエンジン、`initiatorname`）と `node-extra.sh` を流す。このリポジトリのルートを cwd にする |
| `node-extra.sh` | 1 台の上で: kubelet の MainPID・NRestarts・起動の時刻・版、`kubelet.service`・`config.yaml` の md5 とフラグ・`containerRuntimeEndpoint` の有無、`cpu_manager_state`、cgroup、resolv.conf、`nf_conntrack_max`、`no_turbo`（intel_pstate の台）と最高温度、unattended-upgrades の次の時刻と `-security` の更新、`reboot-required`、iscsid、containerd の CoreDNS と control-plane のイメージ、ディスク、etcd のイメージとフラグ（control-plane） |
| `node-step.sh <IP> <dir> before\|after [since]` | 1 台の `install kubelet` の前と後に: `node-state.sh` と `node-extra.sh`、その台の Pod と全 Pod の名前・UID・restartCount（**「その台の Pod」は `spec.nodeName=<IP>` で引くので、ノード名が名前の worker では空になる**。全 Pod の比較に含まれるので、2026-10-30 の本番はそれで見た）。`after` では、前との差分（Pod、node-state）、`since` からの kubelet の journal の `E`・`W` の種類、CSR、`kubelet.service` のフラグ・`containerRuntimeEndpoint`・`crictl version` |
| `etcd-check.sh [since]` | .111 の etcdctl で `endpoint status`（json と table）・`health`・`member list`、3 台の `/version`、動いている etcd のイメージとフラグ、`since` からのログの warn 以上の種類と数 |
| `prepull.sh <IP> <image>...` | **ノードに書き込む（✋）**。その台で `crictl pull` を流し、入ったイメージを示す（§2.5） |
| `seccomp.sh <worker の IP>` | seccomp の手順書のもの。その台の `coredns` のコンテナの CRI の seccomp、OCI spec の `linux.seccomp`、capabilities、`/proc/<pid>/status` の `Seccomp` |
| `endpoints.sh <dir>` | oeilvert から、CoreDNS の各 Pod の IP の `:53` に UDP と TCP で 10 の問い合わせ（seccomp の手順書 §1.6 と同じもの）の rcode・flags・答え、`:8080/health`・`:8181/ready`・`:9153/metrics` と `coredns_build_info`。各 Pod のログと前のログ |
| `probe.sh <logdir>`（監視） | 1 秒ごとに VIP・.111〜.113 の `/readyz`、gated-v4（`http://192.168.1.200/`）、gated-v6（`http://[2405:6580:6740:ac01:ace::200]/`）の HTTP の状態（gated は 404 が応答あり。000 が応答なし）。`<logdir>/probe.log` |
| `dns-watch2.sh <logdir> [yuanying@<IP>]`（監視） | **dev の `dns-watch2.sh` の本番の形**。1 秒ごとに、そのノード（既定は braque）から kube-dns の Service `10.254.0.10` に `dig +time=1 +tries=1` で `in=`（`kubernetes.default.svc.cluster.local` A、UDP）、`fc=`（`kubernetes.default.svc.fraction.cluster` A）、`dns=`（`kube-dns.kube-system.svc.cluster.local` A）、`ext=`（`www.google.com` A）、`ptr=`（`1.0.254.10.in-addr.arpa` PTR）、`tcp=`（`in=` を TCP で）。**答えが無ければ `FAIL(<rcode>)`（`SERVFAIL` など）か `FAIL(timeout)`**。`<logdir>/dns2-<IP>.log` |
| `dns-replicas-watch.sh <logdir>`（監視） | seccomp の手順書のもの。1 秒ごとの `coredns` の replicas（spec / ready / updated / status）と、CoreDNS と autoscaler の Pod（名前、phase、Ready、restart、ノード、`:TERMINATING`）。`<logdir>/dns-replicas.log` |
| `etcd-probe.sh <IP> <秒> <logdir>`（監視） | その control-plane から 2 秒ごとに 3 つのメンバーの `endpoint health` を 1 行。**ループはノードの上で `<秒>` の後に自分で終わる**（段 8 で、ssh を止めてもノードの側の while が残った件の対策）。`<logdir>/etcd-probe-<IP>.log` |
| `cp-watch.sh <秒> <logdir>`（監視） | 2 秒ごとに、kube-system の control-plane のもの（apiserver・KCM・scheduler・kube-proxy）と CoreDNS の generation・イメージ、その Pod（ノード、phase、イメージ、Ready、restart、Terminating）。`<logdir>/cp-watch.log` |

監視の 3 つ（`probe.sh`、`dns-watch2.sh`、`dns-replicas-watch.sh`）は `<logdir>/watch.stop` を作ると止まる（`dns-watch2.sh` は 60 行ごとに ssh を張り直すので、止まるまで最長 1 分）。`etcd-probe.sh`・`cp-watch.sh` は渡した秒数で終わる。当日の `<logdir>` はタスクディレクトリの `notes/0-37-6/logs`。2026-10-30 09:52Z に 6 つとも本番で 1 分流し、行が足されることを確かめた（DNS 60 サンプルで FAIL 0、probe は 49 サンプルとも VIP と各 apiserver が 200・LB が 404、etcd 3/3 healthy）。

このリポジトリの `tools/storage-versions.sh`・`tools/dns-check.sh`・`tools/npcheck.sh`、cnidaria の手順書の `netcheck.sh`・`verify-nodes.sh`・`check-apps.sh`（段 8 の手順書 §1.8 の env の上書きで）も使う。`RUNBOOK_ENV` はタスクディレクトリの `notes/runbook-cnidaria-0-1-2/scripts/env-fraction.sh` で、**`FRACTION_CHECKOUT` をこの作業の checkout に、`CNIDARIA_NFT_IMAGE` を `ghcr.io/yuanying/cnidaria-cni:v0.1.2` に上書きする**（env の既定の checkout `worktrees/runbook-cnidaria-0-1-2` はもう無い。`kadmin.sh` がそこの sops の admin の kubeconfig を読む）。

### 1.8 NetworkPolicy の確認（一時的な名前空間） ✋

段 8 の手順書 §1.9 と同じ（`tools/npcheck.sh` と `tools/npcheck.yaml`。合格は、`up` の後の `nft` が 8 台とも 1 以上、`run` が `OK 56, not OK 0`、`down` の後の `nft` が 8 台とも 0、名前空間 `k8u-npcheck` が NotFound）。流すのは、最初の worker の後（§5.5）と、完了の確認（§6）。

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 順序 | 事前 pull（§2.5）→ etcd のバックアップ → `install kubernetes --node 192.168.1.111`（control-plane と CoreDNS）→ rollout と CoreDNS の確認 → control-plane の `install kubelet --node` を 1 台ずつ（.113 → .112 → .111）→ worker を 1 台ずつ（§5.1）→ 完了の確認 | 段 8 の手順書 §2.1 の 1、1.37.2 の dev の記録 |
| 2 | CoreDNS と K8s | **1 回の `install kubernetes` でまとめて上げる**（render を分けない） | 2026-10-30 のユーザー判断 |
| 3 | drain | **どのノードも drain しない**（§2.7）。どの台の後でも、Pod のコンテナの再起動（restartCount の増加、UID の変化）が 1 つでも出たら止める。**段 8 と違い、control-plane の etcd の mirror Pod も作り直されない想定**（作り直されたら記録して止める） | 1.37.2 の dev の記録、段 3〜8 の本番 |
| 4 | etcd | 変わらない（3.7.3、cluster version 3.7.0）。各 control-plane の台の後に 3/3 healthy と 3.7.3 のままを見るだけ。リーダーの `move-leader` は段 8 のとおり行う（害が無い） | 1.37.2 の dev の記録 |
| 5 | etcd のバックアップ | `install kubernetes` の前に 1 回（§2.4）。control-plane の `install kubelet` の前にもう 1 回（§4.2。1.37.2 の control-plane、v1.15.0 の CoreDNS） | 段 8 の手順書 §2.1 の 11（etcd のマイナー更新が無いので全台 3.7 の後の 3 回目は要らない） |
| 6 | iSCSI | 各台の `install kubelet` の前と後に `node-step.sh` で iscsid の PID とセッションを見る。**動いていた iscsid の PID が変わったら止める。前が `MainPID=0` の台（.112）の「0 → 新しい PID」は想定どおり**（§2.7） | 段 8 の手順書 §2.1 の 5 |
| 7 | ノードの再起動 | しない | 計画 §9.3 |
| 8 | CoreDNS の入れ替わり | Deployment `coredns` の RollingUpdate（`maxSurge: 25%`・`maxUnavailable: 1`、replicas 2）。古い Pod の 1 つを止め、新しい Pod 2 つを作り、新しい Pod が Ready になったら残りを止める。**Ready な Pod が 1 つになる時間がある**（seccomp の手順書 §2.1 の 3） | seccomp の手順書、CoreDNS の dev の記録 |
| 9 | DNS の途切れ | 許容する範囲: Service への問い合わせの単発の `FAIL(timeout)`（記録して進む）。**続く失敗（5 秒を超える）や `FAIL(SERVFAIL)` は止める**（§6） | CoreDNS の dev の記録の「本番の runbook に効くこと」 |
| 10 | `loop` | 新しい CoreDNS の Pod の起動の `loop` の確かめで FATAL になり 1 回再起動しうる。**1 つの Pod で 1 回まで**は、前のコンテナのログに `plugin/loop` があり起き直して Ready なら想定どおりとして記録して進める。CrashLoopBackOff・2 回以上なら止める | seccomp の手順書 §2.1 の 9、§8.1 |
| 11 | イメージの事前 pull | **する**（§2.5）。CoreDNS v1.15.0 は CoreDNS が載りうる amd64 の worker 4 台へ、apiserver・KCM・scheduler の v1.37.2 は control-plane 3 台へ、kube-proxy の v1.37.2 は 8 台へ | CoreDNS の dev の記録の「本番の runbook に効くこと」、2026-10-30 の coordinator の指示 |
| 12 | Completed / Succeeded の Pod | **消さずに流す**（段 8 の本番では消す前に kubelet が上がり、`FailedMount` は出なかった）。`install kubelet` の後に、同じ PVC の Running の Pod に `FailedMount`・`ContainerCreating` が出たら止める（§8.5） | `results/stage-8/workers.md` §6 |
| 13 | **1 回で流す組み合わせで見ること**（dev で流していない） | (a) 全体の apply の後、KCM・scheduler・kube-proxy の rollout と CoreDNS の入れ替わりが重なる間の DNS（2 か所の `dns-watch2.sh`）と `coredns` の ready（0 にならない）。(b) CoreDNS の rollout が KCM・scheduler の入れ替わり（leader election）で止まって見えても、**古い Pod の 1 つが答えている間は、KCM・scheduler の rollout が終わるまで待つ**。両方の rollout が終わって 5 分たっても CoreDNS の新しい Pod が Ready にならなければ止める。(c) kube-proxy が入れ替わる間に、Service `kube-dns` の後ろが古い Pod のまま残らないこと（新しい kube-proxy の後に EndpointSlice の IP へ届く。§3.3 の 13）。(d) 新しい CoreDNS の Pod のノードの kube-proxy の入れ替わりの時刻と、DNS の FAIL の時刻を突き合わせる | §3.2、§3.3 |
| 14 | 停止時間 | いつでもよい。ただし時間帯を避ける（§2.11） | 計画 §9.6 |
| 15 | resolv.conf の kube-dns | 8 台とも CoreDNS の上流に 10.254.0.10 が入っている（前から。§8.1）。この作業では直さない | 段 8 の手順書 §2.10 |

### 2.2 ベースライン

作業の当日、事前 pull の前に次を取り、`results/0.37.6/baseline.md` に残す（すべて読み取り）。出力はタスクディレクトリの `notes/0-37-6/base/` に置く。

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-0-37-6/scripts
B=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/0-37-6/base
bash $S/snap.sh $B
bash $S/nodes.sh $B/nodes                        # このリポジトリのルートで
bash $S/etcd-check.sh > $B/etcd-check.txt
bash $S/endpoints.sh $B/dns
for ip in <CoreDNS の Pod のノードの IP>; do bash $S/seccomp.sh $ip > $B/dns/seccomp-$ip.txt; done
docs/k8s-upgrade/tools/dns-check.sh yuanying@192.168.1.82 > $B/dns/dns-check.txt
docs/k8s-upgrade/tools/storage-versions.sh $B/sv > $B/storage-versions.txt
```

2026-10-30 09:4x〜09:5xZ の値（この手順書を書いたとき。出力はタスクディレクトリの `notes/runbook-0-37-6/read/`）。**当日に読み直す。**

| # | 項目 | 2026-10-30 09:4x〜09:5xZ の値 |
|---|---|---|
| 1 | Node | 8 台 Ready・schedulable、全台 v1.37.1、`containerd://2.3.6`。taint は control-plane 3 台が `node-role.kubernetes.io/master:NoSchedule`、braque が `unstable.cloud/storage:NoSchedule` |
| 2 | Pod | 164 個（Running 140、Succeeded 24）。Running / Completed 以外は 0 個。全 Pod の名前・UID・restartCount を控える（`snap.sh` の `pods.txt`、`node-step.sh` の `before-all.tsv`） |
| 3 | kube-system の generation とイメージ | DaemonSet `kube-apiserver` 31（v1.37.1、3/3）、`kube-proxy` 27（v1.37.1、8/8）、`cnidaria` 4（v0.1.2）。Deployment `kube-controller-manager` 30・`kube-scheduler` 29（v1.37.1、2/2）、`coredns` 14（v1.14.7、2/2）、`kube-dns-autoscaler` 5（v1.11.0）、`metrics-server` 2（v0.9.0） |
| 4 | control-plane の Pod の置き場所 | apiserver は 1 台に 1 つ（.111 `-qxb4k`、.112 `-52p95`、.113 `-djbxn`）。KCM（`-2xdnl` .111、`-fn94h` .113。leader は `-fn94h`）と scheduler（`-9p84r` .111、`-4g4gg` .113。leader は `-4g4gg`）は .111 と .113。kube-proxy の restartCount は duchamp と .112 が 1（それぞれの再起動の分）、ほかは 0 |
| 5 | etcd | 3/3 healthy、3 台とも `{"etcdserver":"3.7.3","etcdcluster":"3.7.0","storage":"3.7.0"}`。リーダーは .113（`57ec6f12ac7b683e`）、raft term 23127、raft index 1408357563、`header.revision` 1,242,028,580、DB 75 MB（in use 31 MB）。フラグは `--feature-gates=InitialCorruptCheck=true`、`--snapshot-count=10000`、`--watch-progress-notify-interval=5s`。直近 10 分のログに warn 以上は 0。etcd の Pod は .112 だけ restartCount 1（10-24 の再起動） |
| 6 | `/opt/bin` と CNI（`nodes.sh`） | 8 台とも `kubelet-v1.37.1`、`kubectl-v1.37.1`、`crictl-v1.37.0`、`etcdctl-3.7.3`、`etcdutl-3.7.3`。CNI の印と 4 つのプラグインは `v1.9.1` |
| 7 | kubelet | MainPID・NRestarts・起動: .111 752609・0・10-23 22:44:11Z、.112 1028・1・10-24 12:11:32Z、.113 612672・0・10-23 22:44:11Z、braque 541944・0・10-23 22:44:45Z、chirico 3237977・0・10-23 22:44:34Z、duchamp 1303・1・10-27 16:54:15Z（電源断の後の起動。journal の時刻は電源断の後の時計の戻りの分ずれている。`record.md` §5.3）、oeilvert 916805・51・10-23 22:53:21Z（段 8 の `cpu_manager_state` の件の自動再起動の分）、pablo 3509679・0・10-23 22:44:38Z。8 台の `kubelet.service` と `config.yaml` の md5 は、この PR の assets の `assets/kubelet/<ノード>/` と同じ（この PR は変えない）。`kubelet.service` に `--container-runtime-endpoint` は無く、`config.yaml` に `containerRuntimeEndpoint` がある |
| 8 | `cpu_manager_state` | 8 台とも policy `none`、checksum 1353318690（oeilvert は 1.37 の kubelet の書いた v4 の形）。1.37.1 の kubelet が読めているので、1.37.2 も読める見込み（段 8 の手順書 §8.23 の件は当たらない） |
| 9 | iscsid と iSCSI（`node-state.sh`） | .111 522641（10-21 21:51:36Z）、**.112 0（動いていない。`iscsid.socket` は active。10-24 12:11Z の shutdown で止まった）**、.113 290821（10-20 21:30:04Z）、braque 271131（10-21 06:23:32Z）、chirico 3144486（10-22 06:20:27Z）、duchamp 3589（10-27 23:33:23Z）、oeilvert 912599（10-23 22:44:23Z）、pablo 4114921（10-21 06:40:42Z）。セッションは chirico 9（portal `10.244.8.60`）、duchamp 6（`10.244.5.89`）、oeilvert 1（`10.244.7.224`）、ほかは 0。portal はどれもそのノードの今の instance-manager の IP（instance-manager は 4 つとも v1.13.0、1 台に 1 つ。chirico の v1.11.2 のものは無くなった）。`older-than-iscsid` は duchamp の 1 本（`pvc-3a665d04`。エンジンが iscsid より 1 秒早い） |
| 10 | Longhorn | `current-longhorn-version` v1.13.0。ボリューム 17（attached healthy 16、detached unknown 1 の `natsumi/natsumi-penelope`）、エンジンは 17 本とも v1.13.0。**アタッチ先は chirico 9、duchamp 6、oeilvert 1、pablo 0** |
| 11 | duchamp の CPU | `no_turbo` 1、最高温度 53℃（09:50Z）。pablo も `no_turbo` 1（前から。理由はこのタスクの記録に無い）、braque は 0。chirico・oeilvert は intel_pstate が無い |
| 12 | `nf_conntrack_max` | control-plane 3 台・braque・pablo 131072、duchamp・oeilvert 262144、chirico 524288（§3.3 の 11 で、v1.37.2 の kube-proxy の後も同じであることを見る） |
| 13 | CoreDNS の Deployment と Pod | generation 14、ReplicaSet `coredns-6bfc79bb8`（revision 11、`RuntimeDefault`、2/2）。Pod は `coredns-6bfc79bb8-6gkk5`（chirico、`10.244.8.201`）と `coredns-6bfc79bb8-n75n5`（oeilvert、`10.244.7.65`）、どちらも restart 0。replicas 0 の古い ReplicaSet が 10 個（revision 1〜10。最も古いのは `coredns-76bd8dbd8c` の `k8s.gcr.io/coredns:1.6.7`）。EndpointSlice `kube-dns-wr2s4` はこの 2 つの IP |
| 14 | CoreDNS の seccomp（`seccomp.sh`） | 2 つとも CRI の config の `security_context.seccomp` が `{}`（RuntimeDefault）、OCI spec の `linux.seccomp` が `SCMP_ACT_ERRNO`・規則 13、`Seccomp: 2`・`Seccomp_filters: 1` |
| 15 | Corefile とログ | ConfigMap `coredns` の resourceVersion `1239255997`、Corefile の SHA512 `dbda5533…`（seccomp の手順書の時と同じ）。2 つの Pod のログは起動の 4〜5 行だけ（`CoreDNS-1.14.7`、`linux/amd64, go1.26.6`）。error・warn・fatal・loop は 0。前のコンテナは無い |
| 16 | 各 Pod の答え（`endpoints.sh`） | 2 つの Pod とも、UDP と TCP で: クラスタ内の A・SRV・PTR が NOERROR で seccomp の手順書 §2.2 の 9 と同じ答え、`nosuch.*` が NXDOMAIN、外の 2 つが NOERROR。クラスタ内の答えの flags は `qr aa rd`。**外の名前の答えは、cache に当たったもの（2 回目以降。TCP の問い合わせなど）が `qr aa rd ra`、当たらないものが `qr rd ra`**（v1.15.0 では cache に当たっても AA が付かなくなる。§3.3 の 13）。`:8080/health`・`:8181/ready`・`:9153/metrics` が 200、`coredns_build_info{…version="1.14.7"}` |
| 17 | `tools/dns-check.sh yuanying@192.168.1.82` | Service（作業端末から）と 2 つの Pod（oeilvert から）で答えが同じ（54 行） |
| 18 | DNS の監視（`dns-watch2.sh`） | braque と oeilvert から 60 サンプルずつで FAIL 0 |
| 19 | containerd のイメージ | **どのノードにも v1.37.2 と CoreDNS v1.15.0 は無い**。control-plane: `kube-apiserver:v1.37.1` が 3 台、`kube-controller-manager:v1.37.1`・`kube-scheduler:v1.37.1` が .111 と .113、`kube-proxy:v1.37.1` が 8 台。CoreDNS v1.14.7 は chirico・duchamp・oeilvert |
| 20 | storage version | `tools/storage-versions.sh`: `prefixes: 70, keys: 2486, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は 1.37 の 4 行。`/registry/clustertrustbundles/` は `certificates.k8s.io/v1beta1` の `ok` で 1 キー（v1.37.2 で変わらない。1.37.2 の dev の記録） |
| 21 | cgroup | 8 台とも `cgroup2fs` |
| 22 | resolv.conf | 8 台とも 10.254.0.10 が入っている（.112・.113 は 1 つ目、oeilvert は 2 つ目、ほかは 3 つ目） |
| 23 | unattended-upgrades | `-security` の更新は 8 台とも無い。`reboot-required` は無い。次の `apt-daily-upgrade.timer` は control-plane が 10-30 21:04〜21:36Z（JST 10-31 06:0x〜06:3x）、worker が 10-31 06:00〜06:52Z（`install kubelet` の `daemon-reload` で引き直されるので当てにしない。§2.11） |
| 24 | MetalLB の告知ノード | speaker のログ（直近 7 日）の最後の `serviceAnnounced`: VIP（192.168.1.101）pablo、gated-v4（192.168.1.200）と gated-v6（`…ace::200`）oeilvert、`::131` .113、`::132`・`::134` duchamp、`::133` oeilvert。LoadBalancer は 12（v4 3: `.101`・`.200`・`.223`、v6 9: `::131`〜`::135`、`::200`、`::9991`〜`::9993`）。告知ノードは日に何度か替わる（gated は 07:53Z に oeilvert へ）。**当日に読み直す** |
| 25 | Succeeded の Pod で Longhorn の PVC を使うもの（§8.5） | duchamp に natsumi の 8 つ（`natsumi-backup-*`・`-aki-*`・`-myao-*` と、手で作った `*-before-v0155-*`・`*-before-v0156-*`。Running の `natsumi-0`・`natsumi-aki-0`・`natsumi-myao-0` と同じ PVC）、chirico に `deep-researcher-backup` の 3 つ（`data-deep-researcher-0`、Running の `deep-researcher-0` と同じ）と `natsumi-backup-aki-before-v0155-…`（`natsumi-aki`、ボリュームは duchamp にアタッチ）。aphrael の 3 つは NFS の PV（`aphrael-2`）で当たらない |
| 26 | CronJob | `aphrael/tumblr-like` 3 時間ごとの :38、`fs/h2-backup` 05:44Z、`fs/sites-backup` 07:53Z、`fs/data-backup` 09:03Z、`natsumi` の 4 つ（`-penelope` を含む）JST 05:30（20:30Z）、`fraction-agents/deep-researcher-backup` JST 06:00（21:00Z） |
| 27 | VIP | `https://192.168.1.101:6443/readyz` が 200。.111〜.113 の `/readyz` も 200 |
| 28 | CSR | 無い |

### 2.3 監視

`install kubernetes` の前（事前 pull と etcd のバックアップの後）から流す（読み取り）。段 8 の手順書 §2.3 と同じく、**`nohup` や `&` で起動しない。** worker のハーネスのバックグラウンド実行で、**監視ごとに 1 つのジョブとして**起動する。

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-0-37-6/scripts
L=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/0-37-6/logs
bash $S/probe.sh $L                                   # ジョブ 1: VIP・各 apiserver・gated v4/v6
bash $S/dns-watch2.sh $L                              # ジョブ 2: braque から kube-dns
bash $S/dns-watch2.sh $L yuanying@192.168.1.82        # ジョブ 3: oeilvert から kube-dns
bash $S/dns-replicas-watch.sh $L                      # ジョブ 4: CoreDNS の replicas と Pod
bash $S/cp-watch.sh 3600 $L                           # ジョブ 5: control-plane と CoreDNS の Pod（1 時間）
bash $S/etcd-probe.sh 192.168.1.111 3600 $L           # ジョブ 6: .111 から etcd の health（1 時間）
bash $S/etcd-probe.sh 192.168.1.112 3600 $L           # ジョブ 7: .112 から etcd の health（1 時間）
```

- 起動したら、ジョブの一覧に 7 つが居ることと、各ログに行が足されていくことを確かめる。**`install kubernetes` の前に、各ログの最後の行の時刻が 1 分以内であること**（`dns2-*.log` は ssh の 1 回分の 60 行ずつまとめて書かれることがあるので、最初の 1 分は待つ）
- 流す期間: `probe.sh`・`dns-watch2.sh` の 2 つ・`dns-replicas-watch.sh` は最後の worker の確認（§5）の後まで。`cp-watch.sh` は §3.3 の確認の後まで（1 時間で終わる）。**`etcd-probe.sh` は control-plane の 3 台目の確認（§4.4）の後まで**（1 時間で終わる。足りなければ同じ形で起動し直す。§4 の前に残りの時間を見る）
- **DNS の監視を 2 か所にするのは、監視するノードの側の途切れと見分けるため**。そのノードの `install kubelet` は `dns` の addon で `systemd-networkd` を再起動するので、その時刻にそのノードの監視だけが落ちることがある（1.37.2 の dev の記録の見つけたことの 3 の v6 の LB と同じ形）。2 か所とも落ちたものを DNS の途切れと読む。braque には CoreDNS が載らない（taint）。oeilvert には CoreDNS の Pod が載っている（§2.2 の 13）
- 作業の途中で、ログの最後の行の時刻を節目（§3.2 の前と後、§4 の各台の前、§5 の各台の前）ごとに見て、監視が止まっていないことを確かめる。止まっていたら、その時刻を記録して起動し直す
- 止めるときは `touch $L/watch.stop`（`probe.sh`・`dns-watch2.sh`・`dns-replicas-watch.sh` が止まる）。`etcd-probe.sh` と `cp-watch.sh` は渡した秒数で終わる。止めた後に .111 と .112 で `pgrep -af 'etcdctl.*endpoint health'` が空であること（秒数の前に止めたいときは、ノードの側のループの PID を確かめて kill する）
- 段 8 の本番では、VIP の FAIL は `install kubernetes` の apiserver の入れ替えの 1 回、LB は `systemd-networkd` の再起動の 1 回、etcd の unhealthy は起き直す台の 1〜2 サンプルだった。**今回は etcd が起き直さないので、etcd の unhealthy は 0 の見込み**

### 2.4 etcd のバックアップ ✋

`install kubernetes` の前（事前 pull の後）に、porkadot 0.37.6 で取る（段 8 の手順書 §2.4 と同じ形。0.37.6 の `etcd backup` は 0.37.5 と同じ実装で、ノードの 3.7.3 の etcdctl を使う）。

```sh
porkadot etcd backup
ls -l ./backup/
```

- 手元のファイルは `./backup/etcd-<日時>.db`、モード 0600。`./backup/` は `.gitignore` で除外してある。スナップショットには Secret が平文で入っているので、`git add -f` などで追加しない。worktree で流したときは、worktree を片付ける前にメインの checkout の `backup/` へ写す（coordinator が行う）
- 時刻、ファイル名、サイズ、sha256 を記録する（2026-10-27 の cnidaria の前のものは 68,919,328 B。今の DB は 75 MB 前後。§2.2 の 5）。桁が違えば止める
- このバックアップは「作業の前」のもの（1.37.1 の control-plane、CoreDNS v1.14.7）。§7.4 の restore の第一の候補（ただし §7 の戻しは restore を要しない見込み）

### 2.5 イメージの事前 pull ✋

`install kubernetes` の前に、新しいイメージを載りうるノードへ入れておく（イメージを足すだけで、何も止めない・消さない）。dev では CoreDNS v1.15.0 の pull が約 2.7 秒だったが、本番の CoreDNS の入れ替わりの間（Ready な Pod が 1 つの時間）と、apiserver の 1 台ずつの入れ替わりを短くするために入れる。

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-0-37-6/scripts
R=registry.k8s.io
for ip in 192.168.1.111 192.168.1.112 192.168.1.113; do
  bash $S/prepull.sh $ip $R/kube-apiserver:v1.37.2 $R/kube-controller-manager:v1.37.2 $R/kube-scheduler:v1.37.2 $R/kube-proxy:v1.37.2
done
bash $S/prepull.sh 192.168.1.131 $R/kube-proxy:v1.37.2
for ip in 192.168.1.83 192.168.1.135 192.168.1.82 192.168.1.134; do
  bash $S/prepull.sh $ip $R/kube-proxy:v1.37.2 $R/coredns/coredns:v1.15.0
done
```

- 1 台ずつ流し、各 pull の rc 0 と、最後の `crictl images` にそのイメージが出ることを見る。時刻と image ID を記録し、同じイメージの ID が台の間でそろう（arch ごとに）ことを見る
- KCM と scheduler は Deployment で、新しい Pod は control-plane のどれに載るか決まらない（今は .111 と .113。§2.2 の 4）ので、3 台とも入れる
- CoreDNS は taint の無い amd64 の worker 4 台（chirico、duchamp、oeilvert、pablo）のどれかに載る（seccomp の手順書 §2.1 の 4）ので、4 台とも入れる。braque と control-plane には載らない
- pull が失敗したら（jumelle の時間帯、registry の障害）、`install kubernetes` に進まない。原因を見てから流し直す（流し直しは ✋ の範囲）
- 入れたイメージは、戻しの後も残る（害は無い）。片付けは計画 §10 のイメージの片付けの形で、後で

### 2.6 render の差分（この手順書と同じ PR）

2026-10-30 09:46Z に、porkadot 0.37.6（`c01edef`。§1.4 の clone）で、このリポジトリのルートを cwd にして `render kubelet` / `render etcd` / `render bootstrap` / `render kubernetes` を流した（4 つとも rc 0。`render all` と `render certs` は使っていない）。`porkadot.yaml` は変えていない。前の render は master の `b33a531` の assets（cnidaria v0.1.2 の porkadot 0.37.5 の render。その後の #68〜#71 は `assets/` を変えていない）。

**差分は次の 13 ファイルで、これ以外の差分は無い**（新しくできたファイル、消えたファイルも無い）。

| ファイル | 変わったもの |
|---|---|
| `kubernetes/manifests/kube-apiserver.yaml`・`kube-controller-manager.yaml`・`kube-scheduler.yaml`・`kube-proxy.yaml`、`bootstrap/manifests/*.bootstrap.yaml`（4 つ） | イメージ v1.37.1 → v1.37.2、`app.kubernetes.io/version` のラベル |
| `kubernetes/manifests/porkadot.yaml` | Service `porkadot-kubernetes-latest` の selector の `app.kubernetes.io/version` |
| `kubernetes/manifests/kube-apiserver.secrets.yaml`・`kube-controller-manager.secrets.yaml`（sops） | Secret の `app.kubernetes.io/version` のラベルだけ（2 か所と 1 か所）。data は同じ（HEAD と作業ツリーを復号して、キーごとの sha256 を比べた。13 キーと 3 キー） |
| `kubelet-default/install-deps.sh` | `RELEASE`（kubelet・kubectl）v1.37.1 → v1.37.2（1 行） |
| `kubernetes/manifests/addons/coredns/coredns.yaml` | イメージ `registry.k8s.io/coredns/coredns:v1.14.7` → `v1.15.0`（1 行） |

- 平文のマニフェストの `-` と `+` の行は、`app.kubernetes.io/version` の 23 行、K8s のイメージの 8 行、`RELEASE` の 1 行、CoreDNS のイメージの 1 行だけ（`-` はどれも v1.37.1 か v1.14.7、`+` はどれも v1.37.2 か v1.15.0）。**dev の 2 つの render の差分（`notes/dev-k8s-1-37-2/render-rc-vs-acb27bb.diff` と `notes/dev-coredns-1-15/render-rc-vs-0375.diff`）を合わせたものと、ファイル・行とも同じ**
- **変わらないもの**: etcd の `etcd-server.yaml`（`3.7.3-0`、フラグ）・`install.sh`・`etcd.env`、`install-deps.sh` の `ETCD_VER`（3.7.3）・`CRICTL_VER`（v1.37.0）・`CNI_VERSION`（v1.9.1）、`install-pkgs.sh`・`setup-containerd.sh`、`kubelet/<ノード>/config.yaml`・`kubelet.service`・`bootstrap-kubelet.conf`・`metadata.json`・`initiatorname.iscsi`、`kubernetes/install.sh`、kube-proxy の ConfigMap（`mode: iptables`）、CoreDNS の ConfigMap（Corefile）・Deployment のほかのフィールド（`seccompProfile: RuntimeDefault`、`drop: [ALL]`、probe、resources）・RBAC・Service、autoscaler、cnidaria（v0.1.2）・MetalLB（pool を含む）・kubelet-serving-cert-approver
- **render が毎回作り直す証明書**（各ノードと bootstrap の `bootstrap.crt` 9 つ、control-plane の `addons/etcd/etcd.crt` 3 つ）は、どれも同じ鍵・同じ subject・issuer・SAN・用途で、assets の CA で検証が通った（期限が 2027-10-30 に延びるだけ）。**この PR には入れず、master のもの（期限 2027-10-23）に戻した**（ノードに今あるものと同じ）
- **ロールバックの材料**: 同じ checkout（この PR の前の master）で porkadot 0.37.5 の 4 つの render を流すと、上の作り直される証明書の 12 ファイルのほかは **master の assets とバイトまで同じ**だった（2026-10-30 09:4xZ。§7.1）
- 当日は render しない。この PR の `assets/` で流す

確かめ方とログはタスクディレクトリの `notes/runbook-0-37-6/`（`render-0375-*.log`・`render-0376-*.log`、`render.diff`、`cert-cmp.txt`、`secrets-yaml-cmp.txt`）。スクリプトは段 8 の `notes/runbook-stage-8/scripts/`（`cert-cmp.sh`、`secrets-yaml-cmp.sh`）。

### 2.7 drain しない理由と、Longhorn・iSCSI の前提

**drain しない理由**は段 8 の手順書 §2.7 と同じで、今回の根拠は次のとおり。

- 1.37.2 の kubelet でも、dev の 7 台でコンテナが 1 つも再起動しなかった（etcd の static Pod も。1.37.2 の dev の記録）
- 0.37.6 の `install-pkgs.sh` は 0.37.5 と同じで、`initiatorname.iscsi` が同じなら iscsid を再起動しない（`systemctl start` だけ）。この PR の render は `initiatorname.iscsi` を変えていない
- 段 3〜8 の本番でも、drain しないで 8 台を流し、コンテナの再起動・`install kubelet` による iscsid の再起動・古いセッションは 1 つも無かった
- dev では Longhorn のボリュームをアタッチしたまま流していない（3 本とも detached）。本番の段 3〜8 ではアタッチしたまま流して問題が無かった

iscsid と iSCSI のセッションの確認は、段 8 の手順書 §2.7 のとおり続ける。

- 各台の `install kubelet` の前と後に `node-step.sh` を取り、iscsid の MainPID・ActiveEnterTimestamp、セッション（sid・portal・target）、エンジンの起動の時刻を比べる
- **動いていた iscsid の PID が変わったら止めて報告する**
- 古いセッション（そのノードの今の instance-manager の IP でない portal へのもの）があれば止める
- **.112 は iscsid が動いていない（`MainPID=0`）**。`install kubelet` の後に新しい PID で動いているのが想定どおり。`ActiveEnterTimestamp` が `install-pkgs.sh` の時刻で、`journalctl -u iscsid` にその時刻の `Started iscsid.service` があり、その前に `Stopping`・`Stopped` が無いこと（起動であって再起動ではないこと）を確かめて記録する（段 8 の手順書 §2.7 の oeilvert と同じ見分け方）
- `older-than-iscsid` のエンジン（duchamp の 1 本）は、エンジンが v1.13.0 なので止める理由にしない。数を記録する

### 2.8 MetalLB の告知ノードと IPv6

段 8 の手順書 §2.8 と同じ。v6 の LB は `2405:6580:6740:ac01:ace::` の下で確かめる（`probe.sh` は gated-v6 を見る）。各 worker の `install kubelet` の `systemd-networkd` の再起動で、その台が告知している LB が 1〜2 サンプル途切れることがある（段 8 の本番の LB 1 回、1.37.2 の dev の v6）。

### 2.9 cgroup v2

段 8 の手順書 §2.9 と同じ。2026-10-30 09:5xZ は 8 台とも `cgroup2fs`（§2.2 の 21）。当日、§3.1 の前に `nodes.sh` で読み直す。

### 2.10 CoreDNS v1.15.0 で変わること

CoreDNS の dev の記録と porkadot#80 の本文から、本番に関わるものを書く。

| v1.15.0 の変更 | 本番 | この手順書での扱い |
|---|---|---|
| cache から返した答えに AA を付けない（coredns#8419） | 外の名前の 2 回目以降の答え（§2.2 の 16 の `qr aa rd ra`）が `qr rd ra` になる。クラスタ内の名前（`kubernetes` plugin）は前後とも `aa` | 答えと rcode だけを比べ、flags は比べない（§3.3 の 13）。AA を見て判断するクライアントは本番に無い見込み |
| cache が `forward` の失敗の SERVFAIL を 5 秒持つ | 上流（jumelle、192.168.0.1）が答えない間の SERVFAIL が、5 秒の間 cache から返る | 上流の止まる時間帯（§2.11）を避ける。`ext=` の `FAIL(SERVFAIL)` は上流の問題のこともあるので、`in=`・`fc=`・`dns=`・`ptr=`・`tcp=` と分けて読む（§6） |
| `forward` が `IP_RECVERR` を使う | 上流への UDP のエラーを早く知る | seccomp の `RuntimeDefault` で許される（dev で `Seccomp: 2` のまま動いた） |
| `kubernetes` plugin が Pod の `status.podIPs` のすべての IP で Pod の索引を作る（coredns#8635） | porkadot の Corefile は `pods insecure` で、`autopath`・`metadata` が無いので、外から見えない（CoreDNS の dev の記録の見つけたことの 2） | 「前と同じに答える」ことだけを見る |
| Go 1.27.3 でビルド | seccomp の下で動くことは dev（amd64）で確かめた | 本番の CoreDNS は amd64 の worker に載る。§3.3 の 13 で `Seccomp: 2` と restart 0 を見る |
| イメージ 24.9 MB | 事前 pull で入れる（§2.5） | — |

Corefile は v1.14 と同じ plugin で動く（corefile-migration v1.0.36 の表が 1.14 と同じ。porkadot#80 の本文）。ConfigMap `coredns` は変わらない。

### 2.11 時間帯

段 8 の手順書 §2.11 と同じ時間帯を避ける。CoreDNS の入れ替わりと事前 pull があるので、jumelle の時間帯は特に避ける。

| 時間帯（UTC） | 何が起きるか | 避ける理由 |
|---|---|---|
| **18:00〜19:30** | jumelle の unattended-upgrades（18:00〜18:30）と、`reboot-required` のときの自動再起動（19:00） | registry.k8s.io と dl.k8s.io に届かず、事前 pull・`install-deps.sh` が失敗する。CoreDNS の上流が止まり、新しい Pod の起動の `loop` の確かめと OOM の繰り返し（段 8 の手順書 §2.10）、v1.15.0 の SERVFAIL の cache（§2.10）が重なる |
| **06:00〜07:00** | worker 5 台の unattended-upgrades | needrestart の iscsid の再起動を porkadot によるものと取り違えないため |
| **21:00〜22:00** | control-plane 3 台の unattended-upgrades | 同上（.112 は iscsid が止まっているので、起きればそれも見分けが要る） |
| 20:30・21:00 | natsumi の 4 つ・`deep-researcher-backup` の CronJob | Succeeded の Pod が増える（§8.5） |
| 05:44・07:53・09:03 | fs のバックアップの CronJob | braque の NFS を使う。braque の `install kubelet` は重ねない（段 8 の手順書 §5.4） |

**所要時間の見込み**: 事前 pull 10 分、`install kubernetes` 約 3〜4 分（dev は 2 分 25 秒〜2 分 55 秒。その後の KCM・scheduler・kube-proxy・CoreDNS の rollout の完了まで 1〜2 分）、§3.3 の確認 10 分、control-plane 3 台（1 台 8〜15 秒の porkadot と確認で 1 台 3〜5 分）、worker 5 台（同じく 1 台 3〜5 分）、§6 の確認 15 分。**ベースラインから完了の確認まで約 1.5 時間**。段 8 の本番は `install kubernetes` から最後の確認まで約 45 分だった。

**作業の時間は 00:00〜05:15Z か 10:00〜17:30Z に収める**（cnidaria v0.1.2 の本番と同じ枠。どちらも時間帯の外で 1.5 時間が入る）。

## 3. control-plane と CoreDNS を上げる（`install kubernetes`）

### 3.1 事前確認

✋✋ **開始の承認を取る。** §2.6 の差分と PR、§2.2 のベースライン（特に 9 の .112 の iscsid、11 の duchamp、13〜16 の CoreDNS、19 のイメージ、25 の Succeeded の Pod）、§2.1 の 13 の「1 回で流す組み合わせで見ること」、§2.3 の監視、§2.5 の事前 pull、§2.11 の時間帯、§6 の止める条件、§7 のロールバックの形を示す。承認を得て PR をマージし、マージした master で次に入る。

- §2.2 のベースラインが済んでいる
- 全台 Ready、etcd 3/3 healthy、VIP の `/readyz` が `ok`、`coredns` が 2/2
- checkout が §2.6 の PR をマージした master で、`git status --short assets porkadot.yaml` が空。`git -C $P describe --tags` が `v0.37.6`、`porkadot help` が動く
- 作業の時間が §2.11 の時間帯と重ならない
- ✋ §2.5 の事前 pull（8 台）
- ✋ §2.4 の etcd のバックアップ
- §2.3 の 7 つの監視がジョブとして動き、ログの最後の行が 1 分以内

### 3.2 流す ✋

```sh
porkadot install kubernetes --node 192.168.1.111
```

- **`--node` を必ず付ける**（付けないと bootstrap ノードの pablo で流し、`127.0.0.1:6443` に届かず rc 1 になる）
- `install kubernetes` は段 8 と同じ 2 段で流れる（`assets/kubernetes/install.sh` は変わらない）: CRD と kube-apiserver のものを先に apply し、DaemonSet `kube-apiserver` の rollout の完了を待ち（3 台を 1 台ずつ。dev は約 2 分半）、全体を apply する
- **全体の apply で同時に動くもの**: KCM・scheduler（Deployment、2 つずつ）、kube-proxy（DaemonSet、8 台を 1 台ずつ）、**CoreDNS の Pod 2 つの入れ替わり**（Deployment `coredns` が `configured`）。ConfigMap `coredns`・autoscaler・cnidaria・MetalLB・approver はマニフェストが変わらない（`unchanged` か、前からの `configured`）
- 出力で見るもの:
  - `daemon set "kube-apiserver" successfully rolled out` の時刻
  - `deployment.apps/coredns configured`、`deployment.apps/kube-controller-manager configured`、`deployment.apps/kube-scheduler configured`、`daemonset.apps/kube-proxy configured`、`daemonset.apps/kube-apiserver configured`
  - ラベルの変わる control-plane のもの（ServiceAccount、ClusterRoleBinding、ConfigMap `kube-proxy`、Secret 2 つ、Service `porkadot-kubernetes-latest` など）の `configured`。前からの `configured`（PDB `kube-controller-manager`・`kube-scheduler`、ValidatingWebhookConfiguration `metallb-webhook-configuration`）
  - **ConfigMap `coredns` が `unchanged`**（Corefile は変わらない。`configured` なら止めて §2.2 の 15 と比べる）。`ipaddresspool.metallb.io/first-pool` が `unchanged`
  - **`pruned` の行が無い**
- 時刻と rc を記録する。rc 1 のときの扱い（`connection refused`、apiserver の rollout の timeout）は段 8 の手順書 §8.3 と同じ（流し直しは ✋ の範囲。2 回目も落ちたら止める）
- 流した直後（全体の apply の後の 1〜2 分）に、§2.3 の監視のログが続いていることを確かめる。`dns-replicas.log` で CoreDNS の入れ替わりを、`cp-watch.log` で KCM・scheduler・kube-proxy の入れ替わりを追う（§2.1 の 13）

### 3.3 rollout の完了を確かめる

```sh
kubectl --context fraction -n kube-system rollout status daemonset/kube-apiserver --timeout=10m
kubectl --context fraction -n kube-system rollout status deployment/kube-controller-manager --timeout=10m
kubectl --context fraction -n kube-system rollout status deployment/kube-scheduler --timeout=10m
kubectl --context fraction -n kube-system rollout status daemonset/kube-proxy --timeout=10m
kubectl --context fraction -n kube-system rollout status deployment/coredns --timeout=10m
kubectl --context fraction version
```

終わったら、`snap.sh`・`etcd-check.sh`・`endpoints.sh` を `notes/0-37-6/cp/` に、`seccomp.sh <新しい CoreDNS の Pod のノード>`、`tools/dns-check.sh yuanying@192.168.1.82`、`tools/storage-versions.sh` を取り、§2.2 と比べる。

| # | 確認 | 合格基準 |
|---|---|---|
| 1 | 版 | Server が v1.37.2。apiserver・KCM・scheduler・kube-proxy のイメージが v1.37.2。Node は 8 台 Ready で kubelet は v1.37.1 のまま（同じマイナーの patch の差） |
| 2 | generation | DaemonSet `kube-apiserver` 31 → 32、`kube-proxy` 27 → 28、Deployment `kube-controller-manager` 30 → 31、`kube-scheduler` 29 → 30、`coredns` 14 → 15。`cnidaria`・autoscaler・`metrics-server`・approver は変わらない |
| 3 | 作り直された Pod | apiserver 3、KCM 2、scheduler 2、kube-proxy 8、CoreDNS 2 の 17 個が新しい UID で restartCount 0（CoreDNS の `loop` の 1 回は 13 で扱う）。**ほかの Pod の UID・restartCount は §2.2 の 2 と同じ**（etcd の static Pod も） |
| 4 | VIP と apiserver | VIP の `/readyz` が 200。`probe.log` の FAIL（000）は apiserver の入れ替えの数サンプルまで（段 8 の本番は 1 回、dev の上げは 0 回）。1 分を超えて続けば §6 |
| 5 | etcd | 3/3 healthy、3.7.3 のまま、raft index がそろう。`etcd-probe` の unhealthy は 0 の見込み（`install kubernetes` は etcd を止めない）。`etcd-check.sh` のログの warn 以上の種類を記録する（`apply request took too long` の数行は段 8 の手順書 §8.13 のとおり想定内） |
| 6 | KCM と scheduler のログ | `Failed to watch`・`failed to list` が続いていない（dev は 0）。`The manifest file is empty, ignoring.` の 1 行は想定どおり（段 8 の手順書 §8.17） |
| 7 | apiserver のログ | `W`・`E` の行の種類が 1.37.1 と同じ形（起動の `Skipping API … because it has no resources`、`Resetting endpoints for master service "kubernetes"` など。1.37.2 の dev の記録） |
| 8 | approver | `kubelet-serving-cert-approver` が 0.12.1 のまま 1/1。generation が変わらない |
| 9 | CSR | 新しい CSR が無い |
| 10 | storage version | `tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` が 1.37 の 4 行、`/registry/clustertrustbundles/` が `ok` で 1 キー（§2.2 の 20 と同じ。v1.37.2 で変わらない） |
| 11 | kube-proxy | 8 つとも v1.37.2 で Running。ログに `Using iptables Proxier` があり、`mode` の warning が無い。**`Setting nf_conntrack_max` の行が出ない**（v1.37.2 の #142198。v1.37.1 は起動のたびに出していた。§2.2 の 12）。8 台の `nf_conntrack_max` が §2.2 の 12 と同じ（`nodes.sh` で読む）。`nodePortAddresses is unset` の `E` の 1 行は前から |
| 12 | MetalLB | `first-pool` が `unchanged`、pool の `addresses` が段 8 の手順書 §2.2 の 31 と同じ |
| 13 | **CoreDNS** | 下の表 |
| 14 | FlowSchema、ServiceCIDR、IPAddress | 段 8 の手順書 §3.3 の 17・19 と同じ（FlowSchema 11 個、`servicecidrs` の `kubernetes` が Ready、IPAddress の数が ClusterIP の数と同じ） |

**CoreDNS の確認**（13）:

| # | 確認 | 合格基準 |
|---|---|---|
| 13a | Deployment | generation 15、新しい ReplicaSet（revision 12）が 2/2、イメージ `registry.k8s.io/coredns/coredns:v1.15.0`。テンプレートの `seccompProfile.type: RuntimeDefault`、`capabilities.drop: [ALL]`、引数・probe・resources・tolerations・strategy は §2.2 の 13 と同じ。ReplicaSet `coredns-6bfc79bb8` は 0 で残る（§7 で使う）。revisionHistoryLimit 10 のため、最も古い `coredns-76bd8dbd8c`（revision 1、1.6.7）が消えるのは想定どおり |
| 13b | Pod | **2 つとも v1.15.0 で Running・Ready**、restart 0（`loop` の 1 回は下）。chirico・duchamp・oeilvert・pablo のどれか（2 つが同じノードかを記録する。seccomp の手順書 §8.4）。古い Pod 2 つ（`-6gkk5`・`-n75n5`）が無い |
| 13c | 入れ替わり | `dns-replicas.log` で、古い Pod の 1 つに `:TERMINATING`、新しい Pod 2 つの作成・Running・Ready、残りの古い Pod の `:TERMINATING` と消えた時刻を控える。**ready が 0 になる行が無い**。KCM・scheduler・kube-proxy の入れ替わり（`cp-watch.log`）の時刻と並べて記録する（§2.1 の 13） |
| 13d | seccomp（`seccomp.sh`） | 新しい Pod 2 つとも、CRI の config の `security_context.seccomp` が `{}`、OCI spec の `linux.seccomp` が `SCMP_ACT_ERRNO`（規則 13）、`Seccomp: 2`・`Seccomp_filters: 1`。capabilities は `CAP_NET_BIND_SERVICE` だけ（`CapEff`・`CapBnd` が `0x400`）、`NoNewPrivs: 1`（§2.2 の 14 と同じ） |
| 13e | 答え（`endpoints.sh`） | 新しい Pod 2 つとも、UDP と TCP で、**クラスタ内の名前の答え（A・SRV・PTR）と、すべての rcode が §2.2 の 16 と同じ**（外の名前の A は rcode だけ比べる。**flags は比べない**。外の名前の cache に当たった答えから `aa` が消えるのは v1.15.0 の想定どおり。§2.10）。`:8080/health`・`:8181/ready`・`:9153/metrics` が 200、`coredns_build_info{…version="1.15.0"}`（goversion `go1.27.3`） |
| 13f | 答え（`tools/dns-check.sh`） | Service と各 Pod の答えが §2.2 の 17 と同じ（Pod の IP の入った PTR の行は、IP が変わる分を読み替える） |
| 13g | ログ | 新しい Pod のログが起動の行（`.:53`、`CoreDNS-1.15.0`、`linux/amd64, go1.27.3`）だけ。**`[ERROR]`・`[WARNING]`・`[FATAL]`・`plugin/loop`・`not permitted` が無い**。上流の `i/o timeout` が出たら時刻と上流を記録する（前から出うる。続くなら §6） |
| 13h | `loop` | restartCount が 1 になった Pod は、前のコンテナのログ（`--previous`）の最後が `[FATAL] plugin/loop: Loop (…) detected for zone "."` で、起き直して Ready なら想定どおりとして記録して進める（§2.1 の 10、§8.1）。`plugin/loop` 以外の理由（`OOMKilled`、`operation not permitted` など）の 1 回、2 回以上、CrashLoopBackOff は止める |
| 13i | Corefile と Service | ConfigMap `coredns` の resourceVersion（`1239255997`）と Corefile の SHA512 が §2.2 の 15 と同じ。EndpointSlice の endpoint が新しい Pod 2 つの IP だけ。Service `kube-dns` の clusterIP が `10.254.0.10` |
| 13j | autoscaler | Pod（名前・UID・restart）と ConfigMap `kube-dns-autoscaler` が §2.2 と同じ。replicas 2 |
| 13k | DNS の監視 | `dns2-192.168.1.131.log` と `dns2-192.168.1.82.log` の、`install kubernetes` から §3.3 の終わりまでの FAIL の数（名前ごと、`FAIL(timeout)` と `FAIL(<rcode>)` を分けて）と時刻。2 か所とも同じ秒に落ちたものと、片方だけのものを分ける。**FAIL の時刻を、CoreDNS の古い Pod の止まった時刻、各ノードの kube-proxy の入れ替わりの時刻と突き合わせる**（§2.1 の 13 の d） |

- ここで問題があれば、kubelet にはまだ触っていないので、§7.2 で control-plane と CoreDNS だけを戻せる

## 4. control-plane の kubelet を上げる（192.168.1.113 → .112 → .111）

### 4.1 何が起きるか

`install kubelet --node <IP>` は、`install-deps.sh`（kubelet・kubectl の v1.37.2 を落として張り替える。crictl・etcdctl・etcdutl・CNI は版が同じなので落とさない）、`install-pkgs.sh`（iscsid は `systemctl start` だけ）、`install.sh`（addon の `dns`、`multipathd`、`etcd`）を root で流し、kubelet を v1.37.2 で再起動する。

**`etcd` の addon は `etcd-server.yaml` を置き直すが、中身が同じなので etcd の static Pod は作り直されない**（1.37.2 の dev の記録の見つけたことの 1）。`/etc/etcd/pki` の証明書と鍵も、この PR では同じもの（render の作り直しを戻した。§2.6）。

- `dns` の addon は `systemd-networkd` を再起動するので、cnidaria の `no route` のログが出る（段 8 の手順書 §8.1）。その台の DNS の監視（oeilvert のとき）や、その台の告知している LB が 1〜2 サンプル落ちることがある（§2.3、§2.8）
- control-plane には Longhorn のボリュームが無い。iscsid は .111・.113 で動いていてセッションは無い、.112 は動いていない（§2.7）
- 戻しのために、前の版のファイル（`kubelet-v1.37.1`、`kubectl-v1.37.1`）がノードに残る

### 4.2 2 つ目のバックアップ ✋

最初の control-plane の `install kubelet` の前に、etcd のバックアップを取る（§2.4 と同じ形）。1.37.2 の control-plane と v1.15.0 の CoreDNS の状態。§7.4 の restore で §2.4 の代わりに使える。etcd の監視（`etcd-probe.sh`）の残りの時間が 20 分より短ければ、起動し直す。

### 4.3 1 台の手順

```sh
S=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/runbook-0-37-6/scripts
D=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/0-37-6/<IP>
bash $S/node-step.sh <IP> $D before                         # 1. 前の控え（このリポジトリのルートで）
bash $S/etcd-check.sh > $D/etcd-before.txt                  #    リーダーを読む
# 2. ✋ 対象がリーダーなら move-leader（段 8 の手順書 §4.3 と同じ形）
# 3. ✋
porkadot install kubelet --node <IP>
# 4. kubelet の起動から 1 分ほど待って
bash $S/node-step.sh <IP> $D after "<3 の開始の時刻 UTC>"   # 差分が出る
bash $S/etcd-check.sh "<3 の開始の時刻 UTC>" > $D/etcd-after.txt
```

- 2026-10-30 09:5xZ のリーダーは .113（`57ec6f12ac7b683e`）。このままなら、.113 の前に .111（`21ab2aeb56731588`）か .112（`fbb0c648cf5852a5`）へ移す。その後も、各台の前にリーダーを読み、対象がリーダーなら移す（dev では .113 と .111 の前に移した）
- porkadot のログの SSH 先（`as ubuntu@<IP>`）がその台だけであることを確かめる
- 1 台ずつ、§4.4 の確認が済んだら次の台に入る

### 4.4 1 台ごとの確認と、次の 1 台へ進む条件

| # | 確認 | 合格基準 |
|---|---|---|
| 1 | Node | VERSION が v1.37.2、Ready |
| 2 | バイナリ | 向き先が `kubelet-v1.37.2`、`kubectl-v1.37.2`。`crictl-v1.37.0`、`etcdctl-3.7.3`、`etcdutl-3.7.3`、CNI の印と 4 つのプラグイン `v1.9.1` は変わらない。`node-step.sh` の node-state の差分は `bin` の 2 つと kubelet の PID・起動の時刻だけ（.112 は iscsid も。8） |
| 3 | etcd | 3/3 healthy、3 台とも 3.7.3・cluster version 3.7.0 のまま、リーダーが居る、raft index がそろう（`-w json` で比べる）。`etcd-probe` の unhealthy が 0 の見込み（出たら記録する。続けば止める） |
| 4 | etcd の Pod | **mirror Pod の UID と restartCount が前と同じ**（作り直されない。作り直されたら記録して止め、`etcd-server.yaml` の差分を見る）。動いている etcd のコンテナの ID と起動の時刻が前と同じ |
| 5 | Pod の再起動 | **差分が無い**（その台と全体の Pod の名前・UID・restartCount が前と同じ）。1 つでもあれば止める |
| 6 | apiserver の Pod | その台の apiserver の Pod が 1/1 Running のまま（UID が同じ） |
| 7 | kubelet のログ | 起動の直後の項目は 1.37.1 のときと同じ（etcd の mirror Pod の `already exists`、`Failed to read data from checkpoint`、`could not load v4 checkpoint` など。段 8 の手順書 §4.4 の 19）。止まる前の古い kubelet の `missing content for CA bundle` の 1 行、起動の直後の `Error getting the current node from lister`・`Eviction manager: failed to get summary stats … node not found` の 1 行ずつは想定内（1.37.2 の dev の記録の見つけたことの 4・6）。`Effective KubeletConfiguration` の 1 行がある。ほかに増えたものは記録する |
| 8 | iscsid | .111・.113 は MainPID と ActiveEnterTimestamp が前と同じ。**.112 は「0 → 新しい PID」が想定どおり**（§2.7 の見分け方で確かめて記録する）。セッションは 0 のまま |
| 9 | `containerRuntimeEndpoint` | `kubelet.service` に `--container-runtime-endpoint` が無い、`config.yaml` にある、`crictl version` が `containerd v2.3.6`、`Flag … has been deprecated` が無い（`node-step.sh` の `cri.txt`） |
| 10 | CSR | 新しい CSR が無い |
| 11 | 監視 | VIP・各 apiserver・LB と、2 か所の DNS の FAIL の数と時刻（その台の `systemd-networkd` の再起動の時刻と突き合わせる） |

次の 1 台へ進む条件: すべて合格、全 8 台 Ready、etcd 3/3 healthy、Running / Completed 以外の Pod が §2.2 から増えていない。

- その台の kubelet が 1.37.2 で起きないときは、次の台に進まず、止めて報告する（§7.6 で戻すかはユーザーが決める）
- 3 台目（.111）の後に、`etcd-probe.sh` の 2 つのジョブを止める（終わっていなければ。§2.3）

## 5. worker の kubelet を上げる（1 台ずつ、drain しない）

### 5.1 順番

アタッチされた Longhorn のボリュームが少ない台から多い台へ（段 8 の手順書 §5.1 と同じ考え方）。2026-10-30 09:5xZ のアタッチの数（pablo 0、braque 0（Longhorn のノードでない）、oeilvert 1、duchamp 6、chirico 9）から、**pablo → braque → oeilvert → duchamp → chirico** にする。当日の読み取りでアタッチの数が変わっていれば並べ直してよい。braque はバックアップの CronJob の時間帯を避ける（§2.11）。

- pablo は API の VIP を告知している（§2.2 の 24）。段 8 の本番でも pablo の `install kubelet` の間、VIP は途切れなかった
- oeilvert は CoreDNS の Pod が載っていることがあり、DNS の監視の 1 つを流しているノード。その台の `install kubelet` の間の `dns2-192.168.1.82.log` の FAIL は、braque の監視と並べて読む（§2.3）
- duchamp は前後で `no_turbo` と温度を見る（§5.3 の 21）

### 5.2 1 台の手順

§4.3 と同じ（move-leader は無い）。**`--node` にはノードの名前を渡す**（`porkadot install kubelet --node pablo`）。流した後に porkadot のログの SSH 先（`as yuanying@<IP>`）がその台だけであることを確かめる。

### 5.3 1 台ごとの確認

| # | 確認 | 合格基準 |
|---|---|---|
| 1 | Node | VERSION が v1.37.2、Ready |
| 2 | バイナリ | §4.4 の 2 と同じ |
| 3 | iscsid | **MainPID と ActiveEnterTimestamp が前と同じ**。変わっていたら止める（§2.7、段 8 の手順書 §2.11） |
| 4 | iSCSI のセッション | 同じ sid・portal・target。portal がそのノードの今の instance-manager の IP（§2.2 の 9）。古いセッションが無い |
| 5 | エンジン | 同じボリューム、同じ起動の時刻。`older-than-iscsid` の数が前と同じ |
| 6 | Longhorn | その台のボリュームが attached healthy のまま。Longhorn の node の一瞬の `is down`・`Waiting for disk` は段 8 の手順書 §5.3 と同じ扱い |
| 7 | Pod の再起動 | **差分が無い**（その台と全体）。1 つでもコンテナの再起動があれば止める |
| 8 | `FailedMount` | その台の Pod に `FailedMount`・`ContainerCreating` が出ない（§8.5） |
| 11 | kubelet のログ | §4.4 の 7 と同じ。**braque は cAdvisor・ZFS の error が無い**（段 8 の手順書 §2.12） |
| 14 | 告知していた LoadBalancer | 応答する（`probe.log`、`tools/check-apps.sh`）。v6 は新しいプレフィックスのアドレスで見る。oeilvert はノードの IPv6 が `2405:6580:6740:ac01::183` のまま |
| 20 | `containerRuntimeEndpoint` | §4.4 の 9 と同じ |
| 21 | duchamp の CPU（duchamp だけ） | 前と後で `no_turbo` が 1、最高温度が前と同じくらい（09:50Z は 53℃）。**`no_turbo` が 0 になっていたら止めて報告する**（書き換えはユーザーの承認。§0）。85℃ を超えたら止めて報告する |

### 5.4 braque

段 8 の手順書 §5.4 と同じ（バックアップの CronJob の時間帯を避ける。§2.2 の 26）。

### 5.5 次の 1 台へ進む条件

§4.4 と同じ（版を読み替える。終えたノードが v1.37.2、まだのノードが v1.37.1）。

- **最初の worker（pablo）の後に、✋ `netcheck.sh` と §1.8 の NetworkPolicy の確認を流す**（v1.37.2 の apiserver・kube-proxy と、v1.37.2 の kubelet のノードを含む形で、cnidaria の Pod 間通信と NetworkPolicy が動くこと）

## 6. 完了の確認

8 台を終えたら次を確かめ、`results/0.37.6/summary.md` に残す。段 8 の手順書 §6 と同じ項目で、次を読み替える・足す。

- 8 台が Ready、全台 v1.37.2、`containerd://2.3.6`、SchedulingDisabled でない
- 8 台の `/opt/bin` が `kubelet-v1.37.2`、`kubectl-v1.37.2`、`crictl-v1.37.0`、`etcdctl-3.7.3`、`etcdutl-3.7.3`。CNI の印と 4 つのプラグインが `v1.9.1`
- etcd 3/3 healthy、3.7.3、cluster version・storage 3.7.0、リーダーが居る、raft index がそろう。etcd の Pod の UID と restartCount が §2.2 と同じ
- VIP の `/livez` が `ok`、`/version` が v1.37.2
- **CoreDNS v1.15.0 が 2/2 Running**、`RuntimeDefault`・`Seccomp: 2`、restart 0（`loop` の 1 回は §3.3 の 13h に記録したもの）、ログにエラーが無い。`endpoints.sh` と `tools/dns-check.sh` の答えと rcode が §2.2 の 16・17 と同じ
- **全 Pod の UID・restartCount が、§2.2 の 2 から `install kubernetes` の 17 個（§3.3 の 3）のほかに変わっていない**
- storage version（`OLD: 0`）、ServiceCIDR と IPAddress、FlowSchema 11 個、cgroup（8 台 `cgroup2fs`）、`containerRuntimeEndpoint`（8 台。kubelet の起動時の `Flag --… has been deprecated` が 0）
- kube-proxy の 8 つのログに `Setting nf_conntrack_max` が無く、8 台の `nf_conntrack_max` が §2.2 の 12 と同じ
- Longhorn（17 本、attached healthy 16 と detached の `natsumi-penelope`、エンジン v1.13.0）、iSCSI（8 台の iscsid の PID とセッションが §2.2 の 9 と同じか、変わったものは .112 の起動）、cnidaria（✋ `netcheck.sh`、✋ §1.8 の NetworkPolicy の確認、`verify-nodes.sh`）、MetalLB（v4 と v6 の LB、`check-apps.sh`）、braque の NFS、`registry.fraction.jp`、CSR: 段 8 の手順書 §6 と同じ
- duchamp の `no_turbo` が 1
- `kubectl --context fraction top nodes` が応答し、Prometheus の `up == 0` が 0 個、`count(etcd_server_has_leader)` が 3、CoreDNS の scrape（`up{job="coredns"}`。`kube-prometheus-coredns` は Service の名前で、job の名前ではない）が 2 つとも up
- §2.3 の監視の FAIL（VIP・LB、2 か所の DNS、etcd）の数と時刻を記録する
- 監視を止める（`touch $L/watch.stop`）。トークンのファイル（`/tmp/k8u-0376-admin-token`）を消す。一時的な名前空間（`k8u-npcheck`、`cnidaria-netcheck`）が NotFound
- etcd のバックアップ（§2.4、§4.2 の 2 つ）を worktree からメインの checkout の `backup/` へ写す（worktree で流した場合。coordinator が行う）

## 7. ロールバック

**戻すのは runbook から外れる操作なので、その都度ユーザーの承認を取る。** 戻すと決める目安は段 8 の手順書 §7 と同じ（rollout が終わらない、VIP が 1 分を超えて応答しない、Node が 5 分たっても Ready にならない、etcd が 2/3 を下回る、Pod の再起動が続く、Longhorn のボリュームが degraded のまま戻らない、DNS が続けて答えない、1.37.2 や v1.15.0 に固有と見られる問題）。

**etcd は変わらないので、どこまで進んでも `install kubernetes` と `install kubelet` で戻せる**（restore は要らない見込み）。**kubelet は apiserver より新しくしない**ので、戻すときは kubelet を先に、control-plane を最後に戻す（§7.5）。同じマイナーの patch の差なので、kubelet v1.37.2 と apiserver v1.37.1 が数分並んでも skew policy の範囲内（dev で 3 分ほど並び、問題は出なかった）だが、順は守る。

| どこまで進んだか | 戻し方 | dev で確かめたか |
|---|---|---|
| `install kubernetes` の後（kubelet はまだ v1.37.1） | §7.2（0.37.5 で `install kubernetes`）。control-plane が v1.37.1、CoreDNS が v1.14.7 に戻る | どちらも確かめた（別々に。0.37.5 への戻しは CoreDNS の dev の記録、`acb27bb` への戻しは 1.37.2 の dev の記録） |
| kubelet の途中・全部の後 | §7.3 で上げた台を逆の順に 1 台ずつ戻し、最後に §7.2 | 確かめた（.124 と .113 を戻した。5〜6 秒、Pod の差 0） |
| CoreDNS だけを戻したい（v1.15.0 に固有の問題） | §7.4 | 確かめていない（§7.4 の注） |

### 7.1 戻すための材料

- **前の版**: この PR の前の master（**`b33a531`**）の `assets/` と `porkadot.yaml`、**porkadot 0.37.5**（§1.4 の `worktrees/porkadot-v0-37-5`）。この `assets/` は本番が今動いているもの（K8s v1.37.1、CoreDNS v1.14.7 の `RuntimeDefault`、cnidaria v0.1.2）。**0.37.5 で render し直しても、作り直される証明書のほかはバイトまで同じ**（§2.6）なので、当日に render しないで使う
- **0.37.5 の置き場**: `worktrees/porkadot-v0-37-5`（`git describe --tags` が `v0.37.5`）
- **etcd のバックアップ**: §2.4（作業の前）、§4.2（control-plane と CoreDNS を上げた後、kubelet の前）

用意の仕方（作業端末で。ノードには触らない。`git worktree add` は元の clone の `.git` に書き込むので使わない）:

```sh
P_OLD=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-5   # git -C $P_OLD describe --tags が v0.37.5
git clone <このリポジトリの checkout> /tmp/fraction-0375
git -C /tmp/fraction-0375 checkout b33a531
cd /tmp/fraction-0375
grep -n 'image:' assets/kubernetes/manifests/addons/coredns/coredns.yaml    # coredns:v1.14.7
grep -n '^RELEASE' assets/kubelet-default/install-deps.sh                   # v1.37.1
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot help
```

0.37.5 の `install kubelet` について:

- `/opt/bin/<名前>` の向き先で判定して張り替える。前の版のバイナリ（`kubelet-v1.37.1`、`kubectl-v1.37.1`）はノードに残っているので、落とし直さずに向き先を戻す（dev は 5〜6 秒）
- etcd・crictl・CNI・`kubelet.service`・`config.yaml`・`initiatorname.iscsi` は 0.37.6 と同じなので変わらない。etcd の static Pod は作り直されない見込み
- 1.37.2 → 1.37.1 の kubelet の戻しで、dev ではコンテナが再起動しなかった（2 台）。Longhorn のボリュームがアタッチされた台を戻すときも、drain しないでよい見込みだが、段 8 の手順書 §7.1 の注のとおり、その時点でユーザーと決める

### 7.2 control-plane と CoreDNS を戻す ✋

```sh
cd /tmp/fraction-0375
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml
```

- **kubelet が v1.37.2 の台が残っているうちは流さない**（先に §7.3 で戻す）
- apiserver・KCM・scheduler・kube-proxy が v1.37.1 に、CoreDNS が v1.14.7 に戻る。CoreDNS は古い ReplicaSet `coredns-6bfc79bb8` が使われ、Pod 2 つがもう 1 度入れ替わる（イメージはノードにあるので pull は無い。CoreDNS の dev の記録では FAIL 0）
- 戻しの apiserver の入れ替えで、VIP が 1 サンプル 000 になることがある（1.37.2 の dev の記録の見つけたことの 2）
- §2.3 の監視を流したまま行う。§3.3 と同じ確認を、版を読み替えて行う（v1.37.1、CoreDNS v1.14.7、答えが §2.2 の 16 と同じ、kube-proxy のログに `Setting nf_conntrack_max` が戻る）
- **この PR をマージした master で 0.37.5 の `install kubernetes` を流さない**（assets が v1.37.2・v1.15.0 なので、また上がる）。`/tmp/fraction-0375` を使う

### 7.3 kubelet を戻す（1 台） ✋

```sh
cd /tmp/fraction-0375
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubelet --node <ノードのキー> --config ./porkadot.yaml
```

- 上げた順の逆に 1 台ずつ（chirico → duchamp → oeilvert → braque → pablo → .111 → .112 → .113 のうち、上げたもの）
- `/opt/bin` の向き先が `kubelet-v1.37.1`、`kubectl-v1.37.1` に戻る。§4.4 または §5.3 の確認を、版を読み替えて行う（iscsid は「PID が同じ」）
- control-plane の台は、リーダーなら先に移す（§4.3）

### 7.4 CoreDNS だけを v1.14.7 に戻す ✋

v1.15.0 に固有の問題（seccomp の拒否、答えの違い、CrashLoop）で、K8s の v1.37.2 は残したいとき。**0.37.6 の assets の CoreDNS のイメージだけを v1.14.7 にしたものは、どの porkadot の版の render にも無い**（CoreDNS のイメージは `coredns.yaml.erb` に書き込まれていて、`porkadot.yaml` の `addons.coredns` で上書きできない。0.37.6 の `default.yaml` は `coredns: {}`）ので、次のどれかをその時点でユーザーと決める。

- (a) §7.3 と §7.2 で全部を 0.37.5 に戻す（確かめた道。K8s も v1.37.1 に戻る）
- (b) Deployment `coredns` の `rollout undo`（runbook から外れる操作。古い ReplicaSet `coredns-6bfc79bb8` に戻る。次の `install kubernetes` でまた v1.15.0 になるので、porkadot の直しか (a) まで残る形）
- (c) porkadot で CoreDNS の版を戻した版を出して render し直す（porkadot の PR と dev の確かめが要る）

### 7.5 全体をやめる

kubelet を先に、control-plane を最後に戻す: 上げた worker と control-plane を §7.3 で逆の順に戻し、最後に §7.2。戻し終えたら、§6 の確認を版を読み替えて行い、`results/0.37.6/` に戻した経緯を残す。

**`etcd restore`**（§2.4 か §4.2 の backup）は、etcd のデータに問題が出たときの最後の手段で、この作業では要らない見込み。形は段 8 の手順書 §7.4 と同じ（0.37.6 の `etcd restore` は 0.37.5 と同じ実装）。使うならその時点でユーザーと決める。

## 8. 既知の問題と注意

### 8.1 `loop` の FATAL（ノードの resolv.conf の kube-dns）

seccomp の手順書 §8.1 と同じ。新しい CoreDNS の Pod 2 つの起動の `loop` の確かめが kube-dns（10.254.0.10）に当たると、もう 1 つの CoreDNS を経て自分に返り、`[FATAL] plugin/loop` で exit 1 する。1 つの Pod で 1 回までは想定どおりとして記録して進める（§3.3 の 13h）。seccomp の本番（10-26）と CoreDNS の dev の記録（6 回の起動）では出なかった。上流の DNS が答えない間は再起動が続きうる（§2.11 の jumelle の時間帯を避ける）。resolv.conf の kube-dns を外す直しは、この手順書の範囲の外（§10）。

oeilvert の resolv.conf は nameserver が 4 つで、CoreDNS の Pod が oeilvert に載ると `DNSConfigForming`（`Nameserver limits were exceeded`）の warning の event が出る（前から。seccomp の手順書 §8.1）。

### 8.2 CoreDNS の Ready の遅れ

readinessProbe に `initialDelaySeconds` が無く、最初の probe が `:8181` の開く前に当たると次は 10 秒後になる（seccomp の手順書 §8.2、CoreDNS の dev の記録の見つけたことの 3。dev の上げ直しでは `plugin/ready: Plugins not ready: "kubernetes"` が 2 行出た）。`Readiness probe failed` の event が 1 回出て 10 秒後に Ready になるのは想定どおり。**今回は、全体の apply の直後に apiserver への接続が KCM・scheduler の入れ替わりと重なるので、`kubernetes` plugin の同期が遅れて Ready が延びうる**。2 分を超えたら §6 の目安で止める（古い Pod の 1 つは答え続けている）。

### 8.3 Service の切り替えの瞬間の取りこぼし

CoreDNS の dev の記録の見つけたことの 1（最後の古い Pod が止まる瞬間の PTR の 1 回の timeout）。kube-proxy の規則の書き換えの間に 1 秒のタイムアウトで取りこぼしたものと見ている（クライアントの既定の `timeout:5 attempts:2` なら再送で答えが返る範囲）。**単発の `FAIL(timeout)` は記録して進む**。今回は kube-proxy 自身も同じ時間帯に入れ替わるので、そのノードの規則の更新が数秒遅れうる（§2.1 の 13 の c）。5 秒を超えて続けば止める（§6）。

### 8.4 install kubelet のたびの `systemd-networkd` の再起動

段 8 の手順書 §8.1 と同じ。その台の cnidaria の `no route` のログ、その台の告知している LB の 1〜2 サンプルの途切れ、その台から流している DNS の監視の途切れ（§2.3）。

### 8.5 Succeeded の Pod と Longhorn の PVC（longhorn/longhorn#8072 の形）

段 8 の手順書 §8.12 の件。段 8 の本番では、duchamp と chirico の Succeeded の Pod（同じ PVC の Running の Pod がある）を消す前に kubelet が上がったが、Running の Pod は再起動せず、`FailedMount` も出なかった（`results/stage-8/workers.md` §6）。**今回は消さずに流す**（§2.1 の 12）。`install kubelet` の後に、その台の Running の Pod に `FailedMount`・`ContainerCreating` が出たら止めて報告する（消すのは、その時点の ✋ の判断。名前を知らせてから）。

### 8.6 `cpu_manager_state`

段 8 の手順書 §8.23 の件（古い checksum のファイルを 1.37 の kubelet が読めない）。8 台とも 1.37.1 の kubelet が読めている形（§2.2 の 8）なので、当たらない見込み。kubelet が起きずに `checkpoint is corrupted` が出たら止めて報告する。

### 8.7 v1.37.2 の CHANGELOG

1.37.2 の dev の記録の「本番の runbook に効くこと」。kube-proxy の `nf_conntrack_max`（#142198。§3.3 の 11）、Go 1.26.10、apiserver の要求のヘッダの値の数（#142770）、Job の作り直しの reconcile（#142390）、DRA の `NoExecute` の DeviceTaintRule（#142492）。既知の問題の節は無い。本番で止める理由になるものは無い。

### 8.8 etcd の遅れ

段 8 の手順書 §8.13 と同じ。今回は etcd が起き直さないので、`install kubelet` の間も 3/3 healthy の見込み。dev の 07:55 の 3 台同時の遅れは dev のホストのディスクに特有のもの（1.37.2 の dev の記録の見つけたことの 5）。

### 8.9 duchamp

`docs/duchamp-power-loss-2026-10/record.md` §6。冷却ファンが壊れたままで、`no_turbo=1` で動かしている。`install kubelet` は再起動しないので `no_turbo` は変わらない見込み。`install-deps.sh` の kubelet の展開の間に CPU の負荷が少し上がる。§5.3 の 21 で前後を見る。duchamp の電源断の前兆は記録に無い（§4 の見立ては電源）。作業中に duchamp が落ちたら止めて報告する（ノードの電源はユーザーの物理の作業）。

## 9. 記録

`results/0.37.6/` に、ベースライン（`baseline.md`。§2.2 の表、§2.4 のバックアップ、§2.5 の事前 pull）、`install kubernetes`（`control-plane.md`。§3.2 の出力の要点、§3.3 の各項目、CoreDNS の入れ替わりの時刻と KCM・scheduler・kube-proxy の入れ替わりの時刻、DNS の FAIL、§4.2 のバックアップ）、各台（`<ノード>.md`。control-plane は `192.168.1.11N.md`）、まとめ（`summary.md`。§6）を残す。形は `results/stage-8/` と `results/coredns-seccomp/` に合わせる。
時刻（UTC）、読み取りの結果、実行したコマンドと出力の要点、Pod の再起動の有無、iscsid の PID とセッションの前と後、監視の FAIL と監視が止まっていた時間、手順書との差を書く。スクリプトの出力と監視のログはタスクディレクトリの `notes/0-37-6/` に置き、要点を記録に写す。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（記録の PR で）。

## 10. この後

- 1 日ほど様子を見る（CoreDNS の restartCount、ログの `[ERROR]`、Prometheus の CoreDNS の SERVFAIL の数）
- 計画 §8 の CoreDNS の行は、これで v1.15.0（registry.k8s.io の最新）になる。計画と TASK の完了条件の「非クリティカルなコンポーネントが最新版」の CoreDNS の理由の記録を、v1.15.0 に直す
- 申し送り（この手順書の範囲の外）:
  - ノードの resolv.conf の kube-dns を外す（§8.1。段 8 の手順書 §10）
  - CoreDNS の `podAntiAffinity`（seccomp の手順書 §8.4）と、readinessProbe の `initialDelaySeconds`（§8.2）
  - 古い CoreDNS の ReplicaSet と、ノードの containerd に残る古いイメージ（v1.37.1 の control-plane のイメージ、CoreDNS v1.14.7・v1.13.2 など）の片付け。`/opt/bin` の `kubelet-v1.37.1`・`kubectl-v1.37.1` は戻しの材料なので落ち着いてから
  - rasp02 の 10-24 12:11Z の shutdown の理由（このタスクの記録に無い。§1.1）
  - containerd の config v4（計画 §10。2026-10-27 のユーザー判断で片付けの後に）
