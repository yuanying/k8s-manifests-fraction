# 段 7 の手順書: K8s を 1.35.9 から 1.36.5 へ上げる（本番 `fraction`）

本番クラスタ `fraction` の Kubernetes を v1.35.9 から v1.36.5 へ上げ、**CoreDNS を v1.13.2 から v1.14.7 へ上げる**手順。porkadot を 0.35.0 から 0.36.0 に替える。etcd（3.6.15）と CNI plugins（v1.9.1）は据え置く。
計画は同じディレクトリの `plan.md`（以下「計画」）の §6（骨子）と §7 の段 7 の行、決まったことは §9 にある。前の段は `runbook-stage-6.md`（以下「段 6 の手順書」）で、この手順書はそれを下敷きにし、**段 6 から変わる点を中心に書く**。段 3〜6 と同じく drain しない。

| | 更新前 | 更新後 |
|---|---|---|
| porkadot | 0.35.0（`e4aa3e6`、タグ `v0.35.0`） | **0.36.0**（`7247f15`、タグ `v0.36.0`） |
| kube-apiserver、kube-controller-manager、kube-scheduler、kube-proxy | v1.35.9 | **v1.36.5** |
| kubelet、kubectl（ノードの `/opt/bin`） | v1.35.9 | **v1.36.5** |
| crictl（ノードの `/opt/bin`） | v1.35.0 | **v1.36.0** |
| CoreDNS | v1.13.2 | **v1.14.7**（Corefile・RBAC・引数・securityContext は変えない） |
| etcd（control-plane の static Pod）、etcdctl・etcdutl（ノードの `/opt/bin`） | 3.6.15-0、3.6.15 | 変えない（マニフェストも変わらない） |
| CNI plugins（ノードの `/opt/cni/bin`） | v1.9.1 | 変えない（版の印が同じなので展開しない） |
| `install-pkgs.sh`、`initiatorname.iscsi` | iscsid は `initiatorname.iscsi` が変わったときだけ再起動 | 変えない |
| cnidaria、MetalLB、kubelet-serving-cert-approver | v0.1.1、v0.14.5、0.12.1 | 変えない（マニフェストの差分が無い。MetalLB の CRD・webhook は apply し直されるが中身は同じ） |
| kubelet の `config.yaml`・`kubelet.service` | — | 変えない |
| containerd、runc | 段 C の 2.3.6、1.5.1 | 変えない |
| Longhorn | v1.13.0（17 本ともエンジンは v1.13.0） | 変えない（§1.10） |

porkadot 0.36.0 に入った PR は porkadot#58（`6a639db`。K8s v1.36.5、crictl v1.36.0、CoreDNS v1.13.2 → v1.14.7。etcd 3.6.15-0 は据え置き）と、porkadot#59（`1d75678`。版を 0.36.0 にする）。0.35.0 から 0.36.0 の差分は `lib/porkadot/default.yaml`（`kubernetes_version`・`crictl_version`）、`coredns.yaml.erb`（イメージのタグ）、`version.rb`、文書とテストの 7 ファイル・10 行だけで、`install`・`etcd backup`・`etcd restore` の実装は 0.35.0 と同じ。

この手順は dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で先に通してある（2026-10-21）。記録は porkadot-dev の `docs/k8s-upgrade/verification-0.36-rc.md`（以下「dev の記録」。porkadot-dev の main `5341bc4`、porkadot-dev#17）。dev は #58 の `6a639db` で通したもので、0.36.0 との違いは版の番号（#59）だけ。dev で分かったことは次のとおり。

- **1.36 の kubelet に上げても、コンテナは再起動しなかった**（1.32〜1.35 と同じ）。7 台すべてで Pod の UID・restartCount が変わらず、変わったのは control-plane の etcd の static Pod だけ（3 台とも restartCount 1）。**iscsid も 7 台とも PID が変わらなかった。** Longhorn v1.13.0 のボリュームをアタッチしたまま `install kubelet` した 2 台で、ボリュームは `attached`・`healthy` のまま、セッション・iscsid の PID も変わらず、書き込みに途切れは無く、detach の後にセッションは残らなかった
- **`install kubernetes` は 1 回目で rc 0**（約 3 分。apiserver の 3 台の入れ替えに約 2 分、全部の rollout の完了まで約 4 分）。1.36 の scheduler・KCM のログに `Failed to watch` / `failed to list` は 0（1.35 の apiserver の返さない API を待つ形は無かった）。MetalLB の CRD・webhook も apply し直され（`validatingwebhookconfiguration … configured`）、rc 0 で通った
- **CoreDNS は v1.14.7 で 2/2 で起きた**。イメージの User は `nonroot:nonroot` から `65532:65532` に変わったが UID は同じ 65532 で、53 番の bind は `NET_BIND_SERVICE` で通る。名前の答えは上げる前と同じ。ログにエラーは無い
- **storage version の書き直しは要らない**。1.36 の apiserver は dev にあるオブジェクトの storage の版を変えない。ただし 1.36 の `ResourceEncodingOverrides` は MutatingAdmissionPolicy・MutatingAdmissionPolicyBinding を `v1beta1` で保存する（dev の見つけたことの 3）。この PR で `tools/storage-versions.sh` に足した（§2.5）
- **StrictIPCIDRValidation（1.36 で beta・既定 on）**: dev の既存のオブジェクトに当たる値は無かった。値を変えない update は通り、新しい正規形でない値は拒否される。この PR で `tools/ipcidr-scan.py` を取り込み、本番を読み取りで流した（§2.12。**該当は 0**）
- 1.36 の apiserver・KCM・scheduler は起動のたびに `The manifest file is empty, ignoring.` を error のレベルで 1 行出す（害は無い。dev の見つけたことの 1。§8.17）
- 1.36 では `UnknownVersionInteroperabilityProxy`（apiserver の peer proxy）が既定 on になり、etcd に `/registry/peerserverleases/` が増える（dev の見つけたことの 2。§8.18）
- **etcd は 3.6.15 のまま 3/3 healthy**。control-plane の `install kubelet` で static Pod が作り直される（段 6 と同じ）
- dev では、`install kubernetes` の直後に etcd が遅くなった（`apply request took too long` 最大 0.98 秒、`slow fdatasync` 2.6 秒。段 6 の dev より軽い）。7 台の VM が同じホストのディスクを使う dev に特有と見ている（§8.13）
- CSR は 1 つも出なかった。作業端末の kubectl v1.36.5 で 1.35 と 1.36 の server を問題なく使えた。porkadot のコマンドとノードへの `ssh` は、すべてサンドボックスの中で流した
- **dev では `install kubernetes` の間（12:00〜12:05Z）の監視が取れていない**。監視の shell をバックグラウンドで起動したが、起動した shell が終わったときにサンドボックスに止められた（§2.3 で本番の起動の形を変えた）

これを受けて、**本番の段 7 でも、どのノードも drain しない**（§2.7）。止める条件は段 6 のまま使う（etcd の static Pod の作り直しは想定どおりとして除く）。

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **arm64 の control-plane での 1.36 の kubelet**。dev は amd64 の VM。arm64 のイメージとバイナリが配布されていることは確かめてある（§1.7）。CoreDNS は本番では control-plane に載らない（§2.13）
- **本番の Longhorn のボリュームがアタッチされたままの `install kubelet`**（2026-10-21 12:37Z は chirico 9 本、duchamp 4 本、oeilvert 2 本、pablo 1 本）。段 3〜6 の本番では同じ形で問題が無かった
- **`install kubernetes` の間の VIP と etcd**（dev は監視が欠けた。§2.3）
- **ロールバック**（§7）。1.36 → 1.35 の戻しは、どの形も dev で流していない

## 0. 役割と約束ごと

段 6 の手順書 §0 と同じ。違いは次のとおり。

- **承認の節目は 1 つ**（計画 §9.1「本番の各段の開始」。段 7 は etcd のマイナー更新を含まないので、control-plane の kubelet の前の節目は無い）。この手順書では ✋✋ を付けた。
  - ✋✋ **段 7 の開始**: render の差分（§2.6。この手順書と同じ PR）、drain しないこと（§2.7）、StrictIPCIDRValidation の読み取りの結果（§2.12）、storage version と MutatingAdmissionPolicy の読み取りの結果（§2.5）、unattended-upgrades の時刻（§2.11）、ベースライン（§2.2）とバックアップ（§2.4）、porkadot 0.36.0 の置き場（§1.4）を見せ、PR をマージしてから、`install kubernetes` を流す前（§3.1）
- **節目の間の手順は、ユーザーに知らせるだけで進めてよい。** etcd のバックアップ、etcd のリーダーの移動、`install kubelet`、`install kubernetes` の流し直し（§3.2）、一時的な DaemonSet・NetworkPolicy の確認（`netcheck.sh`、`npcheck.sh`）は、この手順書に書いた形なら ✋（知らせてから行う操作）で、1 つずつ承認を取るものではない。
- **§8.12 の Completed / Succeeded の Pod の削除は、段の開始の承認の範囲の ✋ とする**（段 6 と同じ。消す前に対象の名前を知らせる）。段 7 には storage version の書き直しは無い（§2.5）。
- **runbook から外れる操作（ロールバック、`etcd restore`、drain への切り替え、想定外の対処、上のほかの Pod の削除、iSCSI のセッションの logout、unattended-upgrades の止め・手での apt の操作）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- **StrictIPCIDRValidation の読み取り（§2.12）で該当が見つかっても、段は止めない。** 見つかったものと、作り直す可能性（Flux・Helm・GitOps の管理下か）を coordinator に知らせ、記録する。
- 読み取りの確認は、知らせずに行ってよい。**1 台ずつ行う。** 時刻はすべて UTC で記録する（control-plane のホストの時刻は JST）。

## 1. 前提

### 1.1 段 6 が終わっていること

始める前に次を確かめる。

- 段 6 の完了の確認（段 6 の手順書 §6）が `results/stage-6/summary.md` に残っている
- 8 台すべてが v1.35.9、CONTAINER-RUNTIME が `containerd://2.3.6`、etcd が 3/3 で 3.6.15（cluster version・storage とも 3.6.0）
- Longhorn が v1.13.0 で、17 本とも `status.currentImage` が `longhorn-engine:v1.13.0`

2026-10-21 12:3xZ の読み取り（この手順書を書いたとき）:

- 8 台 Ready、全台 v1.35.9、`containerd://2.3.6`。etcd 3/3 が 3.6.15（cluster version・storage とも 3.6.0）、リーダーは .113（`57ec6f12ac7b683e`）、raft term 23123、DB 55 MB（in use 17 MB）。Pod は 160 個で、Running / Completed 以外は 0 個
- generation: DaemonSet `kube-apiserver` 29、Deployment `kube-controller-manager` 28、`kube-scheduler` 27、DaemonSet `kube-proxy` 25、Deployment `coredns` 12（v1.13.2、2/2。chirico と duchamp）、DaemonSet `cnidaria` 3（`cnidaria-cni:v0.1.1`）。FlowSchema は 11 個
- Longhorn は v1.13.0。ボリュームは 17（attached healthy 16、detached unknown 1 の `homegallery/cg-data`）。アタッチ先は chirico 9、duchamp 4、oeilvert 2、pablo 1（段 6 のときと同じ。当日に読み直す）
- `tools/storage-versions.sh`（この PR で直したもの）は `prefixes: 65, keys: 2290, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は 1.35 の VolumeAttributesClass の 1 行（§2.5）。IPAddress 74、Service 79
- 8 台の `tools/node-state.sh`: `/opt/bin` は `kubelet-v1.35.9`、`kubectl-v1.35.9`、`crictl-v1.35.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。iSCSI と iscsid は §2.7、§2.11

### 1.2 kubeconfig の運用

段 6 の手順書 §1.2 と同じ（確認は `fraction-auditor`、変更系は `infra-admin` の 1 時間のトークンと `kubectl-admin`）。

**段 7 で `infra-admin` のトークンを使うのは、§1.9 の NetworkPolicy の確認と、§8.12 の Pod の削除だけ**（`netcheck.sh` はトークンを使わず、cnidaria の手順書の `kadmin.sh` で sops の admin の kubeconfig を使う。段 6 と同じ）。トークンのファイル名は `/tmp/k8u-stage7-admin-token` にする。

### 1.3 SSH

段 6 の手順書 §1.3 と同じ（worker は `ssh yuanying@<IP>`、control-plane は `ssh ubuntu@<IP>`。**サンドボックスの中で流す**。control-plane には `unset LC_ALL` してから入る）。2026-10-21 12:36Z にこの手順書を書いたとき、8 台ともサンドボックスの中から `tools/node-state.sh` を流せた。

### 1.4 porkadot の置き場と流し方

元の clone（`/home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot`）は v0.34.1 のまま（2026-10-21）で、サンドボックスの中からは書き込めない。段 6 と同じく、タスクディレクトリの独立の clone を使う。

| 用途 | 置き場 | 版 |
|---|---|---|
| **段 7 の当日** | `/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-36-0` | v0.36.0（`7247f15`、detached） |
| **§7 の戻し** | `/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-35-0`（段 6 で使ったもの。触らずに残す） | v0.35.0（`e4aa3e6`、detached） |

- 0.36.0 の clone は、元の clone から `git clone` し、origin を `https://github.com/yuanying/porkadot.git` にして tag `v0.36.0` を fetch し、detached で checkout した（push しない）。`git ls-remote` で GitHub の `refs/tags/v0.36.0`（tag object `164b030`）と `^{}`（`7247f15`）が手元と一致することを確かめた。`lib/porkadot/version.rb` は 0.36.0。`bundle install` 済み（Ruby 4.0.7）で、2026-10-21 12:34Z にこの clone で §2.6 の render を流した
- 0.35.0 の clone は 2026-10-21 12:3xZ に `git describe --tags` が `v0.35.0`、作業ツリーに変更が無く、`porkadot help` が動くことを確かめた

**このリポジトリのルートを cwd にして** 流す。形は段 6 の手順書 §1.4 と同じ。

```sh
P=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-36-0
git -C $P describe --tags          # v0.36.0（lib/porkadot/version.rb も 0.36.0）
cd <このリポジトリの checkout>     # §2.6 の PR をマージした master
BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

以下、この形を `porkadot <サブコマンド>` と書く。

- 始める前に `BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot help` が動くことを確かめる
- 作業ツリーの `assets/` と `porkadot.yaml` に PR の外の変更が無いこと（`git status --short assets porkadot.yaml` が空）。メインの checkout にほかの作業があれば、master の別の worktree を作ってそこで流す
- 段 7 で流す porkadot のコマンドは、`etcd backup`、`install kubernetes --node 192.168.1.111`、`install kubelet --node <ノード>` の 3 つだけ。**`install all`、`--node` なしの `install kubelet` と `install kubernetes`、`render`（特に `render all` と `render certs`）、`setup-node`、`setup-containerd`、`etcd restore`（§7.4 の承認を得たときだけ）は流さない**
- **ノードに入る porkadot のコマンドもサンドボックスの中で流す**（0.36.0 の SSH は 0.35.0 と同じ）。当日の流す前の確かめ方は段 2 の手順書 §1.4 のスクリプト（`P` を 0.36.0 の置き場にする）。8 台とも hostname を返すこと

### 1.5 etcdctl の使い方

段 6 の手順書 §1.5 と同じ。8 台ともノードの `/opt/bin/etcdctl` は 3.6.15 で、段 7 では変わらない。

### 1.6 render に使った secrets と、本番との突き合わせ

secrets の在りかと扱いは段 1 の手順書 §1.6 と同じ（`assets/` の中に sops の binary 形式で暗号化してある。`assets/secrets.tar.asc` を展開しない。平文をディスクに書かない）。
段 7 の render（§2.6）の前に、段 6 の手順書 §1.6 と同じ形で本番と突き合わせ直した（2026-10-21 12:34Z。読み取りだけ。復号をパイプで流してハッシュだけを比べた。スクリプトはタスクディレクトリの `notes/runbook-stage-7/scripts/secrets-check.sh`）。**28 項目すべて一致した。**

| 比べたもの | 本番の側 | 結果 |
|---|---|---|
| `assets/certs/kubernetes/ca.crt` | ConfigMap `default/kube-root-ca.crt` | 一致（SHA-256 `AB:5A:49:9E:…`。段 1〜6 と同じ） |
| `assets/certs/kubernetes/apiserver.crt` | VIP と 192.168.1.111〜113 の 6443 が返す証明書 | 4 つとも一致（`4A:E8:7B:B3:…`） |
| `assets/certs/kubernetes/` の 10 ファイル | .111 の kube-apiserver の Pod（`kube-apiserver-wdw65`）にマウントされた Secret `kube-apiserver` | 10 ファイルとも sha256 が一致 |
| `assets/certs/etcd/{ca.crt,etcd-client.crt,etcd-client.key}` | 同じく Secret `etcd-tls` | 3 ファイルとも一致 |
| `assets/kubelet/192.168.1.11{1,2,3}/addons/etcd/{ca.crt,etcd.crt,etcd.key}`（render の前） | 3 台の `/etc/etcd/pki/` | 9 ファイルとも一致（`etcd.crt` は段 6 の render のもの） |
| CA の鍵と証明書（kubernetes、front-proxy、etcd） | — | 3 組とも公開鍵が一致 |

当日に確かめ直すときの形は段 1 の手順書 §1.6 と同じ。どれかが食い違えば、render の差分も assets も信用せず、止めて調べる。

### 1.7 入れる版を確かめる

作業の当日に確かめ直す（読み取り）。

```sh
curl -fsSL https://dl.k8s.io/release/stable-1.36.txt     # v1.36.5
```

2026-10-21 12:37Z の時点:

- `stable-1.36.txt` は v1.36.5。`stable.txt` は v1.37.1
- registry.k8s.io の `kube-apiserver`・`kube-controller-manager`・`kube-scheduler`・`kube-proxy` の v1.36.5、`coredns/coredns:v1.14.7`、`etcd:3.6.15-0` は、どれも amd64 と arm64 を含む（manifest list を読んだ）
- `dl.k8s.io` の kubelet と kubectl の v1.36.5（amd64、arm64）、cri-tools の `crictl-v1.36.0-linux-{amd64,arm64}.tar.gz` は、どれも 200 を返す。cri-tools の 1.36 系は v1.36.0 だけ
- etcd 3.6.15 と CNI plugins v1.9.1 はノードに入っているもので、変わらない
- CoreDNS の最新は v1.15.0。段 7 は porkadot 0.36.0 の v1.14.7 にする（計画 §2。段 8 で最新を確かめ直す）
- **作業端末の kubectl は v1.36.5**（2026-10-21 に上げた）。1.35 にも 1.36 にも ±1 に入る（dev でも v1.36.5 で使えた）

### 1.8 確認に使うスクリプト

段 6 の手順書 §1.8 と同じ（cnidaria の手順書の `verify-nodes.sh`・`netcheck.sh`・`check-apps.sh`、`tools/node-state.sh`、`tools/storage-versions.sh`、`tools/dns-check.sh`）。違いは次のとおり。

- **`tools/storage-versions.sh` をこの PR で直した**。サーバーの版ごとの override（`overrides.tsv`）に、1.33〜1.35 の VolumeAttributesClass（`storage.k8s.io/v1beta1`）と、1.36 の MutatingAdmissionPolicy・MutatingAdmissionPolicyBinding（`admissionregistration.k8s.io/v1beta1`）を足した（§2.5、`storage-versions.md` §3.2）。**`overrides.tsv` は空でなくなる**（1.35 は 1 行、1.36 は 2 行）。合格の基準は `OLD: 0` のまま
- **`tools/ipcidr-scan.py` をこの PR で足した**（読み取り）。porkadot-dev の `docs/k8s-upgrade/tools/ipcidr-scan.py`（main `5341bc4`、porkadot-dev#17）をそのまま写し、出どころをファイルの頭に書いた。使い方は §2.12
- **cnidaria の手順書の `verify-nodes.sh` は、段 6 と同じく写しの `IMAGE` を `cnidaria-cni:v0.1.1` にして流す**（段 6 の手順書 §1.8）。2026-10-21 12:3xZ の読み取りでも、oeilvert の containerd には `v0.1.0` が無く（`v0.1.1` だけ。ディスク 79%）、ほかの 7 台には両方ある。image GC でほかの台からも消えうるので、元のスクリプトの `v0.1.0` のまま流さない

### 1.9 NetworkPolicy の確認（一時的な名前空間） ✋

段 6 の手順書 §1.9 と同じ（`tools/npcheck.sh` と `tools/npcheck.yaml`）。合格は、`up` の後の `nft` が 8 台とも 1 以上、`run` が `OK 56, not OK 0`、`down` の後の `nft` が 8 台とも 0、名前空間 `k8u-npcheck` が NotFound。段 6 の本番では、`up` の後の `nft` は 8 台とも 9 だった。

流すのは、最初の worker の後（§5.5）と、段 7 の完了の確認（§6）。

### 1.10 Longhorn と K8s 1.36

Longhorn v1.13.0 の要件は **Kubernetes >= v1.34**（上流の文書 `https://longhorn.io/docs/1.13.0/deploy/install/` の Installation Requirements の「Kubernetes >= v1.34」と Kubernetes Version の「Longhorn requires Kubernetes >= v1.34.」、v1.13.0 の release notes の「Kubernetes v1.34 Minimum Version」）。**上限の表明は無い**（文書にも release notes にも、上限や検証した版の一覧は無い。2026-10-21 12:4xZ に読み直した。計画 §4.1）。1.36.5 は下限を満たすので、段 7 では Longhorn を変えない。計画 §4.3 の経路 A のとおり、段 6〜8 は 1.13.x で走る。v1.13 系の release は v1.13.0（2026-09-29）だけ。dev の段 7 も Longhorn v1.13.0 で通した。

- 1.36 で削除される GA の API は無く、Longhorn の使う API（CSI、`storage.k8s.io/v1`、`coordination.k8s.io/v1`、`discovery.k8s.io/v1`、v1 Endpoints）は 1.36 でも提供される。v1 Endpoints の warning は段 6 と同じく出る（§6）
- 1.36 で無効になる `gitRepo` volume、kubeadm の flex-volume の扱いの変更は、本番では使っていない（2026-10-21 12:4xZ の読み取りで、Pod・Deployment・StatefulSet・DaemonSet・CronJob・Job・ReplicaSet に `gitRepo`・`flexVolume` は 0、PV に `flexVolume` は 0）

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 順序 | `install kubernetes --node 192.168.1.111` → rollout の完了 → control-plane の `install kubelet --node` を 1 台ずつ（.113 → .112 → .111）→ worker を 1 台ずつ（§5.1） | 計画 §6.2、dev の記録 |
| 2 | etcd のリーダー | `install kubelet` の前に、対象がリーダーなら `move-leader` で別のメンバーへ移す（etcd の static Pod が作り直されるため） | 計画 §6.2、dev の記録 |
| 3 | drain | **どのノードも drain しない**（§2.7）。**ただし、どの台の後でも、Pod のコンテナの再起動（restartCount の増加、UID の変化。control-plane の etcd の mirror Pod を除く）が 1 つでも出たら止める。** 特に最初の worker と、Longhorn のボリュームが多い台の前に見る。止めた後、残りの Longhorn のノードを drain に切り替えるかはユーザーが決める（§8.10） | dev の記録、段 3〜6 の本番、2026-10-19 のユーザーの方針 |
| 4 | drain の基準 | 「短時間の途切れ」より「Longhorn のボリュームの安全（データ、degraded のまま戻らないこと）」を重く見る。短時間の障害は許容する | 2026-10-19 のユーザーの方針 |
| 5 | iSCSI | **各台の `install kubelet` の前と後に `tools/node-state.sh` で iscsid の PID と iSCSI のセッションを見る**。`install kubelet` で iscsid の PID が変わったら止める。古いセッションがあれば止める（§2.7、§5.3）。unattended-upgrades による iscsid の再起動との見分け方は §2.11 | 2026-10-21 のユーザーの判断、段 6 の手順書 §2.7 |
| 6 | cgroup | 上げる前に 8 台で `cgroup2fs` を確かめる（段 6 と同じ。§2.9） | 段 6 の手順書 §2.9 |
| 7 | ノードの再起動 | しない | 計画 §9.3 |
| 8 | コンテナの再起動 | 1.36 の kubelet では起きないことを前提にする（§8.4）。control-plane の etcd の static Pod だけは作り直される（restartCount 1〜2 は想定どおり） | dev の記録 |
| 9 | Longhorn の設定 | 変えない | 段 1 の手順書 §2.6 |
| 10 | etcd | 変えない（3.6.15 のまま。マニフェストも変わらない）。control-plane の各台の後に 3/3 healthy、raft index がそろうことを見る | dev の記録 |
| 11 | etcd のバックアップ | 2 回取る: 段の前（`install kubernetes` の前。§2.4）と、`install kubernetes` の後・control-plane の `install kubelet` の前（§4.2） | 計画 §6.1 の 5 |
| 12 | storage version | 書き直しは無い。`install kubernetes` の前と後に `OLD: 0` を確かめる。MutatingAdmissionPolicy・…Binding は本番に無い（§2.5） | dev の記録、2026-10-21 の読み取り |
| 13 | CoreDNS | `install kubernetes` で v1.14.7 に rollout する。名前の答えが上げる前と同じことを確かめる（§3.3 の 13）。control-plane には載らない（§2.13） | dev の記録 |
| 14 | Completed / Succeeded の Pod | Running の Pod と同じ Longhorn の PVC を使うものは、`install kubelet` の前に消す（§8.12。段の開始の承認の範囲の ✋。§0） | 段 3 の本番 |
| 15 | v1 Endpoints の warning | 段の更新を止める理由にしない。出どころを記録する（段 4 の手順書 §8.15） | 段 4 の本番 |
| 16 | leader election を使う controller の 1 回の再起動と、gated の LoadBalancer の 1 回の途切れ | 許容する。記録して、Running に戻ったことを確かめる（§8.8） | 段 C、ユーザーの判断 |
| 17 | 停止時間 | いつでもよい。braque は念のためバックアップの CronJob の時間帯を避ける（§5.4）。**unattended-upgrades の時間帯（worker は 06:00〜07:00Z、control-plane は 21:00〜22:00Z）も避ける**（§2.11） | 計画 §9.6、段 6 の手順書 §2.11 |
| 18 | resolv.conf の kube-dns | 8 台とも CoreDNS の upstream に 10.254.0.10 が入っている（前から。段 6 の手順書 §2.10）。段 7 は止めない。CoreDNS のログに `loop` が出ないことを見る | 段 6 の手順書 §2.10 |
| 19（新） | StrictIPCIDRValidation | 上げる前に `tools/ipcidr-scan.py` を流す。該当があっても止めない（記録して coordinator に知らせる。§0、§2.12） | dev の記録、指示（2026-10-21） |
| 20（新） | control-plane のログの `The manifest file is empty, ignoring.` | 止める理由にしない（§8.17） | dev の見つけたことの 1 |

### 2.2 クラスタ全体のベースライン

作業の当日、`install kubernetes` の前に次を取り、`results/stage-7/baseline.md` に残す（すべて読み取り）。段 6 の手順書 §2.2 と同じもので、次を読み替える・足す。

- 1: 全台 v1.35.9
- 2: 8 台の `tools/node-state.sh` の出力（ファイルに残す）。`/opt/bin` の向き先が `kubelet-v1.35.9`、`kubectl-v1.35.9`、`crictl-v1.35.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と 4 つのプラグインが `v1.9.1`
- 4: **etcd**: 段 6 の手順書 §2.2 の 4 と同じ（版、STORAGE VERSION、DB SIZE、リーダー、raft term・index、`header.revision`、3 台の `/version`、動いている etcd のフラグ、warning の種類）
- 5: **全 Pod の名前・UID・restartCount を控える**（§6 で「増えていない」ことを見る元になる）
- 14・18: Longhorn の設定とボリューム（`current-longhorn-version` が v1.13.0、17 本ともエンジンが v1.13.0）
- 20: **storage version**: この PR の `tools/storage-versions.sh` の結果。`OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` が 1.35 の `volumeattributesclasses` の 1 行
- 21: Prometheus の `apiserver_requested_deprecated_apis`
- 22: Longhorn のボリュームを使う Pod と、同じ PVC を使う Completed / Succeeded の Pod
- 23: **CoreDNS の答え**: `tools/dns-check.sh` の出力。v1.13.2 の答えとして、§3.3 の 13 の比べる元にする
- 24: Service の数と ClusterIP の数、IPAddress の数（2026-10-21 12:37Z は Service 79 個、IPAddress 74）
- 25: Prometheus の etcd と apiserver のスクレイプ（`kube-etcd` 3、`apiserver` 3、`count(etcd_server_has_leader)` 3）
- 26: cgroup（8 台の `stat -fc %T /sys/fs/cgroup`）
- 27: resolv.conf（8 台の `/run/systemd/resolve/resolv.conf` の nameserver）
- 28: **unattended-upgrades**: 8 台の `liblzma5` の版、`apt list --upgradable`、`systemctl list-timers apt-daily-upgrade.timer` の次の時刻、`/var/log/apt/history.log` の最後の実行（§2.11）
- 29: FlowSchema の名前と generation（11 個）
- 30（新）: **StrictIPCIDRValidation**: `tools/ipcidr-scan.py` の出力（§2.12）
- 31（新）: **MutatingAdmissionPolicy**: `kubectl get mutatingadmissionpolicies,mutatingadmissionpolicybindings`（1.35 では `the server doesn't have a resource type` になる。§2.5）と、etcd の `/registry/mutatingadmissionpolicies/`・`/registry/mutatingadmissionpolicybindings/` のキーの数（`storage-versions.sh` の `prefixes.txt`）

### 2.3 VIP と LoadBalancer、etcd の health を見る

段 6 の手順書 §2.3 と同じ監視（VIP と gated-v4 の 1 秒ごと、etcd の health の 2 秒ごと）を、作業端末で流しておく（読み取り）。ログはタスクディレクトリの `notes/stage-7/` に `stage-7-probe.log`、`stage-7-etcd-<IP>.log` として足していく（`tee -a`、`>>`）。中身のコマンドは段 1 の手順書 §2.3（VIP と LB）と段 5 の手順書 §2.3（etcd の health）のものを、ログのファイル名を替えて使う。

**監視の起動の形を変える。** dev の段 7 では、監視を `nohup … &` でバックグラウンドに起動したところ、起動した shell が終わったときにサンドボックスに止められ、`install kubernetes` の間の監視が欠けた（dev の記録の「流れ」の注）。本番の段 7 では次のとおりにする。

- **監視のスクリプトを `nohup` や `&` で起動しない。** worker のハーネスのバックグラウンド実行（pi の `bg_run`）で、**監視ごとに 1 つのジョブとして**起動する（VIP と LB で 1 つ、etcd の health は .111 と .112 で 1 つずつ。合わせて 3 つ）。ジョブの中のコマンドは前景のループのまま（`&` を付けない）にする
- 起動したら、ジョブの一覧（`bg_list`）に 3 つが居ることと、ログに行が足されていく（VIP と LB は 1 分ごとの `ok` の行、etcd は 2 秒ごとの行）ことを確かめてから §3.2 に入る。**`install kubernetes` の前に、3 つのログの最後の行の時刻が 1 分以内であること**
- 止めるときはジョブを止める（`bg_kill`）。**`ssh -n` ではノードの側の while は ssh を止めても残る**（段 5 の本番）。止めた後に .111 と .112 で `pgrep -af 'while :'` を見て、残っていれば PID を確かめて kill する
- 作業の途中で、ログの最後の行の時刻を節目（§3.2 の前と後、§4 の各台の前、§5 の各台の前）ごとに見て、監視が止まっていないことを確かめる。止まっていたら、その時刻を記録して起動し直す
- 流す期間: VIP と LB は `install kubernetes` の前から最後の worker の確認まで。etcd の health は `install kubernetes` の前から control-plane の 3 台目の確認の後まで（段 6 と同じ）

段 6 の本番では、VIP の FAIL は `install kubernetes` の .113 の apiserver の入れ替えの 1 回だけ、LB は 0 回、etcd の unhealthy は起き直す台の 1〜2 サンプルだけだった（`results/stage-6/summary.md` §2.5）。

### 2.4 etcd のバックアップ（段の前） ✋

`install kubernetes` の前に、porkadot 0.36.0 で取る（計画 §6.1 の 5）。段 6 の手順書 §2.4 と同じ形。

```sh
porkadot etcd backup
ls -l ./backup/
```

- 0.36.0 の `etcd backup` は 0.35.0 と同じ（ノードの `/opt/bin/etcdctl` 3.6.15 の `snapshot save`）
- 手元のファイルは `./backup/etcd-<日時>.db`、モード 0600。`./backup/` は `.gitignore` で除外してある。スナップショットには Secret が平文で入っているので、`git add -f` などで追加しない
- **worktree で流したときは、`./backup/` は worktree の中にできる。** worktree を片付ける前に、coordinator がメインの checkout の `backup/` へ移す（段 1〜6 と同じ）
- 時刻、ファイル名、サイズ、sha256 を記録する。段 6 のバックアップは 2 つとも 55,107,616 バイトだった。桁が違えば止める
- **このバックアップは「段の前」のもの**（1.35 の control-plane、CoreDNS v1.13.2）で、§7.4 の restore の第一の候補になる。段 7 が終わり、健全性を確かめるまで消さない

### 2.5 storage version と MutatingAdmissionPolicy（書き直しは無い）

段 7 では storage version の書き直しは無い。

**1.36 の `ResourceEncodingOverrides`**（v1.36.5 の `pkg/kubeapiserver/default_storage_factory_builder.go`）は、1.35.9 のものから次が変わる（dev の見つけたことの 3。ソースを読んで確かめた）。

| リソース | 1.35 の保存の版 | 1.36 の保存の版 | discovery の preferred（1.36） | 本番のオブジェクト |
|---|---|---|---|---|
| `mutatingadmissionpolicies`、`mutatingadmissionpolicybindings` | `v1beta1`（1.35 では beta で既定では出ない） | **`v1beta1`**（1.36 で GA。`TODO: remove in 1.37`） | `v1` | **無い**（下） |
| `volumeattributesclasses` | `v1beta1`（1.34 で GA） | **override が外れて `v1`** | `v1` | 無い |
| `workloads` | `v1alpha1` | `v1alpha2` | — | 無い（既定では出ない） |
| `resourcepoolstatusrequests`、`podgroups` | — | `v1alpha3`、`v1alpha2`（新） | — | 無い（既定では出ない） |

ほか（`leasecandidates`、`clustertrustbundles`、`podcertificaterequests`、`storagemigrations`、`devicetaintrules`）は 1.35 と同じで、どれも既定では出ない beta・alpha の API で、本番にオブジェクトが無い。

- MutatingAdmissionPolicy は 1.36 では `v1` で提供され、`v1beta1` で保存される。こうしたオブジェクトがあると、直す前の `tools/storage-versions.sh`（discovery の preferred の `v1` を期待値にする）は `OLD` と数えていた。**この PR で、1.36 のときは `overrides.tsv` に `/registry/mutatingadmissionpolicies/`・`/registry/mutatingadmissionpolicybindings/` の `admissionregistration.k8s.io/v1beta1` を入れる**ようにした。同じく 1.33〜1.35 の VolumeAttributesClass の `v1beta1` も入れた（`storage-versions.md` §3.2）
- **本番に MutatingAdmissionPolicy・MutatingAdmissionPolicyBinding は無い**（2026-10-21 12:35Z の読み取り。1.35 の apiserver はこのリソースを提供していない（`kubectl get mutatingadmissionpolicies` は `the server doesn't have a resource type`、`admissionregistration.k8s.io` の版は `v1` だけ）。etcd の `/registry/` の下に `mutatingadmissionpolicies`・`mutatingadmissionpolicybindings`・`volumeattributesclasses` のキーは 0 個）。ValidatingAdmissionPolicy も 0 個
- 1.36 の apiserver が保存した MutatingAdmissionPolicy は、1.35 に戻しても読める（override の目的がそれ。§7.2）

確かめること:

1. `install kubernetes` の前（§2.2 の 20）: `tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` が `volumeattributesclasses` の 1 行（1.35）。**違えば止める**
2. `install kubernetes` の後（§3.3 の 16）: 同じ `OLD: 0`。`overrides.tsv` が `mutatingadmissionpolicies`・`mutatingadmissionpolicybindings` の 2 行（1.36）。**新しい prefix `/registry/peerserverleases/`（core の `v1` の `Endpoints`、apiserver ごとに 1 つ。§8.18）が出るのは想定どおり**で、`ok` に数えられる。`OLD` が出たら止めて調べる
3. FlowSchema は 11 個のまま（dev で 1.36 でも 11 個のまま）

### 2.6 render の差分（この手順書と同じ PR）

計画 §6.1 の 6〜7。2026-10-21 12:34Z に、porkadot 0.36.0（`7247f15`。§1.4 の独立の clone）で、このリポジトリのルートを cwd にして `render kubelet` / `render etcd` / `render bootstrap` / `render kubernetes` を流した（`render all` と `render certs` は使っていない。4 つとも rc 0）。secrets は §1.6 のとおり本番と一致していることを確かめてから使った。`porkadot.yaml` は変えていない。

前の render は master の `9d4898a` にある（段 6 の porkadot 0.35.0 の render）。差分は次の 25 ファイルで、**これ以外の差分は無い**（新しくできたファイル、消えたファイルも無い）。dev の記録の「render の差分」と同じ形。

| ファイル | 変わったもの | 由来 |
|---|---|---|
| `kubernetes/manifests/kube-apiserver.yaml`・`kube-controller-manager.yaml`・`kube-scheduler.yaml`・`kube-proxy.yaml` | イメージ v1.35.9 → v1.36.5、`app.kubernetes.io/version` のラベル | K8s の版（porkadot#58） |
| `kubernetes/manifests/kube-apiserver.secrets.yaml`・`kube-controller-manager.secrets.yaml`（sops） | Secret の `app.kubernetes.io/version` のラベルだけ（`v1.35.9` → `v1.36.5`、2 か所と 1 か所）。data は同じ（HEAD と作業ツリーを復号して、キーごとの sha256 を比べた。13 キーと 3 キー） | 同上 |
| `kubernetes/manifests/porkadot.yaml` | Service `porkadot-kubernetes-latest` の selector の `app.kubernetes.io/version` | 同上 |
| `kubernetes/manifests/addons/coredns/coredns.yaml` | イメージ `coredns:v1.13.2` → `v1.14.7`（1 行） | porkadot#58 |
| `bootstrap/manifests/*.bootstrap.yaml`（4 つ） | イメージ v1.35.9 → v1.36.5、版のラベル | porkadot#58（段 7 では bootstrap は使わない） |
| `kubelet-default/install-deps.sh` | `RELEASE`（kubelet・kubectl）v1.35.9 → v1.36.5、`CRICTL_VER` v1.35.0 → v1.36.0（2 行） | porkadot#58 |
| `kubelet/<8 台>/bootstrap.crt`、`bootstrap/kubelet/bootstrap.crt` | 作り直し（同じ鍵、同じ subject・issuer・SAN・用途、assets の CA で検証が通る。期限が 2027-10-21 12:34Z に延びる） | render のたびに作り直される（§8.2） |
| `kubelet/192.168.1.11{1,2,3}/addons/etcd/etcd.crt`（sops） | 同上（同じ鍵、同じ etcd の CA、同じ subject・SAN） | 同上 |

- 平文のマニフェスト（証明書と sops の Secret を除く）の `-` の行はどれも v1.35.9・v1.35.0・v1.13.2 を、`+` の行はどれも v1.36.5・v1.36.0・v1.14.7 を含む（ほかの行の変化は 0）。`app.kubernetes.io/version` が変わったのは 23 行（dev の記録と同じ数）
- **変わらないもの**: `kubelet/192.168.1.11{1,2,3}/addons/etcd/etcd-server.yaml`（etcd 3.6.15-0 とフラグ）、etcd の `install.sh`・`etcd.env`・`etcd.key`、`kubernetes/install.sh`（apiserver を先に入れる形）、`kubelet-default/install-pkgs.sh`・`setup-containerd.sh`、`install-deps.sh` の `ETCD_VER`（3.6.15）と `CNI_VERSION`（v1.9.1）、`kubelet/<ノード>/config.yaml`・`kubelet.service`・`bootstrap-kubelet.conf`・`metadata.json`・**`initiatorname.iscsi`**、CoreDNS の Corefile・RBAC・引数・securityContext、cnidaria（v0.1.1）・MetalLB・kubelet-serving-cert-approver のマニフェスト
- Deployment と DaemonSet の `spec.selector` には `app.kubernetes.io/version` が入っていない（段 1〜6 と同じ）
- 作り直した証明書は、作業の当日に render し直すとまた変わる。**当日は render しない**。この PR の `assets/` で流す

確かめ方（読み取り。どれも平文をディスクに書かない）は段 6 の手順書 §2.6 と同じ。スクリプトと出力はタスクディレクトリの `notes/runbook-stage-7/`（`render.diff`、`secrets-yaml-cmp.txt`、`cert-cmp.txt`）。

### 2.7 drain しない理由と、Longhorn・iSCSI の前提

**drain しない理由**（§2.1 の 3）は段 6 の手順書 §2.7 と同じで、段 7 の根拠は次のとおり。

- 1.36 の kubelet でも、dev の 7 台でコンテナが 1 つも再起動しなかった（etcd の static Pod を除く）。drain しないでアタッチしたままの Longhorn v1.13.0 のボリュームは、faulted・remount・I/O エラーにならず、書き込みも途切れなかった（dev の記録の「Longhorn と iSCSI」）
- 0.36.0 の `install-pkgs.sh` は 0.35.0 と同じで、`initiatorname.iscsi` が同じなら iscsid を再起動しない（dev の 7 台で PID が同じ）。この PR の render は `initiatorname.iscsi` を変えていない
- 段 3〜6 の本番でも、drain しないで 8 台を流し、コンテナの再起動・`install kubelet` による iscsid の再起動・古いセッションは 1 つも無かった（`results/stage-3/summary.md`〜`results/stage-6/summary.md`）

iscsid と iSCSI のセッションの確認は、段 6 の手順書 §2.7 のとおり続ける（2026-10-21 のユーザーの判断）。

- 各台の `install kubelet` の前と後に `tools/node-state.sh` を取り、iscsid の MainPID・ActiveEnterTimestamp、セッション（sid・portal・target）、エンジンの起動の時刻を比べる
- **`install kubelet` の間に iscsid の PID が変わったら止めて報告する**（0.36.0 の `install-pkgs.sh` は再起動しないはずなので、変われば想定外）。前に変わっていた（§2.11 の unattended-upgrades など）ものは、前の `node-state.sh` との比べで分かる
- 古いセッション（そのノードの今の instance-manager の IP でない portal へのもの）があれば止める
- `older-than-iscsid` のエンジン（iscsid が後から再起動したもの）は、エンジンが v1.13.0 なら止める理由にしない。数を記録する

**各ノードの iSCSI と Longhorn**（2026-10-21 12:36Z の `tools/node-state.sh`。当日に読み直す）:

| ノード | iscsid の MainPID（起動の時刻） | Longhorn のセッション | `older-than-iscsid` のエンジン | needrestart による再起動（§2.11） |
|---|---|---|---|---|
| 192.168.1.111 | 90734（2026-10-19 07:31:09Z） | 0 | — | **まだ**（liblzma5 0.3。次は 10-21 21:10Z） |
| 192.168.1.112 | 89578（2026-10-19 07:27:57Z） | 0 | — | **まだ**（同上。次は 10-21 21:33Z） |
| 192.168.1.113 | 290821（2026-10-20 21:30:04Z） | 0 | — | 済み（10-20 21:30:04Z） |
| braque | 271131（2026-10-21 06:23:32Z） | 0 | — | 済み（10-21 06:23:32Z） |
| chirico | 4447（2026-10-19 09:17:30Z） | 9 | 0 | **まだ**（liblzma5 0.3。次は 10-22 06:32Z） |
| duchamp | 2695716（2026-10-21 06:08:00Z） | 4 | 4 | 済み（10-21 06:08:00Z） |
| oeilvert | 6334（2026-10-19 09:04:34Z） | 2 | 0 | **まだ**（liblzma5 0.3。次は 10-22 06:35Z） |
| pablo | 4114921（2026-10-21 06:40:42Z） | 1 | 1 | 済み（10-21 06:40:42Z） |

- portal はどれもそのノードの今の instance-manager の IP で、古いセッションは無い（段 6 の完了の確認と同じ）
- 8 台の `/etc/iscsi/initiatorname.iscsi` の md5 は、段 6 の完了の確認と同じ（この PR の render は `initiatorname.iscsi` を変えていない）

### 2.8 MetalLB の告知ノードを読む

段 6 の手順書 §2.8 と同じ読み方。段 6 の完了の確認（`results/stage-6/summary.md` §2）では、VIP pablo、gated-v4 chirico、gated-v6 oeilvert、`::131`・`::134` .112、`::132` .111、`::133` duchamp だった。当日に読み直す。

### 2.9 cgroup v2 の確認

段 6 の手順書 §2.9 と同じ（1.35 から、kubelet は cgroup v1 のノードでは起動しない）。段 6 の完了の確認で 8 台とも `cgroup2fs` だった。当日、§3.1 の承認の前に同じコマンドで流し直す。`tmpfs` の台があれば止める。

### 2.10 CoreDNS の upstream の resolv.conf

段 6 の手順書 §2.10 と同じ（8 台とも、CoreDNS が forward する `/run/systemd/resolve/resolv.conf` に kube-dns の 10.254.0.10 が入っている。前からのもので、段 7 は止めない）。v1.13.2 でも `loop` は出ていない（`results/stage-6/summary.md`）。v1.14.7 の `forward` は接続の試行回数の上限が入る（coredns/coredns#8365）が、ふだんの答えには出ない（dev の記録）。§3.3 の 13 で v1.14.7 でも答えが同じこと、ログに `loop` が出ないことを見る。

### 2.11 unattended-upgrades による iscsid の再起動

段 6 の手順書 §2.11 と同じ（unattended-upgrades の needrestart が、iscsid の使うライブラリ（liblzma5 など）の更新の後に iscsid を `systemctl restart` する。open-iscsi の hold とは関係なく起きる）。**作業は unattended-upgrades の時間帯を避ける**: worker は **06:00〜07:00Z**、control-plane は **21:00〜22:00Z**（ホストの時刻の 06:00 + 最大 60 分）。

**段 6 の後に残っていた 4 台（.111・.112・chirico・oeilvert）の、needrestart による iscsid の再起動は、2026-10-21 12:36Z の時点ではまだ済んでいない**（読み取り）。

- 4 台とも `liblzma5` は `5.6.1+really5.4.5-1ubuntu0.3` のままで、`apt list --upgradable` に `liblzma5`・`xz-utils` の `0.4`（`noble-security`）がある。unattended-upgrades の `Allowed-Origins` に `noble-security` が入っているので、次の実行で入る
- 直近の実行（.111 と .112 は 10-20 21:34Z、chirico 10-21 06:21Z、oeilvert 06:28Z）は `python3-jwt` だけを入れた（oeilvert は何も入れていない）。その時点のその台の apt の index に `liblzma5` 0.4 がまだ無かったものと見ている（index を更新する `apt-daily.timer` の時刻は台ごとに違う。例えば .111 はその実行の前の更新が 10-20 10:10Z、次が 10-21 03:05Z。確かめきってはいない）。今は 4 台とも index に 0.4 がある
- 次の実行の時刻（`apt-daily-upgrade.timer`）: .111 10-21 21:10Z、.112 10-21 21:33Z、chirico 10-22 06:32Z、oeilvert 10-22 06:35Z。どれも時間帯の中。`unattended-upgrades-dpkg.log` の `systemctl restart … iscsid.service` は 4 台とも 0 回で、0.4 が入れば、ほかの 4 台と同じく iscsid が再起動する見込み
- chirico（セッション 9）と oeilvert（2）は、アタッチされたボリュームのある台で iscsid が再起動することになる。duchamp（4）と pablo（1）では、iscsid が既存のセッションを `operational after recovery` で引き取り、エンジンは `older-than-iscsid` になったが、ボリュームは attached healthy のままだった（エンジンは v1.13.0。段 6 の記録）
- **段 7 の作業の日が 10-22 以降なら**、§2.2 の 28 でこの 4 台の iscsid の PID が変わっているかを読み、変わっていれば `/var/log/apt/history.log` と `unattended-upgrades-dpkg.log` で needrestart によるものと見分けて、ベースラインに記録する（止めない）。**作業の日が 10-21 の 21:00Z より前なら**、4 台はまだ再起動していないので、作業の時間が 21:00Z〜22:00Z（control-plane）と 06:00Z〜07:00Z（worker）に重ならないようにする
- 本番の段 6 では、`install kubelet` の `daemon-reload` で `apt-daily-upgrade.timer` の次の時刻が 8 台とも引き直された（段 6 の手順書 §2.11）。時間帯は変わらないが、作業の前に読んだ「次の時刻」は当てにしない
- 1 台の前と後の間に iscsid の PID が変わったときは、止めてから、`journalctl -u iscsid`、`/var/log/apt/history.log`、`/var/log/unattended-upgrades/unattended-upgrades-dpkg.log` を見て、porkadot の `install kubelet` によるものか、unattended-upgrades の needrestart によるものかを記録して報告する。続けるかはユーザーが決める
- unattended-upgrades を止める・apt を手で流すのは、runbook の外の操作（§0）。段 7 では止めない
- 2026-10-21 12:3xZ の `apt list --upgradable` には、ほかに glib、snapd、ubuntu-pro-client、cloud-init、tmux、ca-certificates（4 台）、apparmor（.112）などがあり、`noble-security` のもの（ca-certificates、liblzma5、xz-utils）は次の実行で入る。oeilvert の `docker-ce` の更新は Docker のリポジトリのもので、`Allowed-Origins`（Ubuntu の `noble`・`noble-security`・ESM だけ）に入らないので、自動では入らない

### 2.12 StrictIPCIDRValidation（読み取り）

1.36 で `StrictIPCIDRValidation` が beta・既定 on になる。拒否されるのは、新しく作るとき（削除して作り直すときを含む）と、update で新しい値を入れるときの、次の 3 つの形だけ（dev の記録の「StrictIPCIDRValidation」）。

| 理由 | 形 | 例 |
|---|---|---|
| `leading-0` | 先頭に 0 がある IPv4 の数、prefix の長さ | `010.0.0.1`、`10.0.0.0/08` |
| `ipv4-mapped` | IPv4-mapped IPv6 | `::ffff:10.0.0.1` |
| `host-bits` | CIDR の prefix の長さより後ろのビットが立っている（CIDR として検証されるフィールドだけ） | `10.1.2.3/8` |

正規形でない IPv6（`non-canonical`）は warning だけで拒否しない。既存のオブジェクトは壊れず、値を変えない update（GitOps の apply し直しを含む）は通る。

**上げる前に**（§2.2 の 30）、`tools/ipcidr-scan.py` を流す（読み取り）。

```sh
kubectl --context fraction get services,endpoints,endpointslices,networkpolicies,nodes,pods,ingresses,servicecidrs,ipaddresses -A -o json \
  | python3 -I docs/k8s-upgrade/tools/ipcidr-scan.py
```

出力は 1 件ずつ `kind ns/name path 値 理由` と、最後に件数。**該当（`leading-0`・`ipv4-mapped`・`host-bits`）があっても段は止めない**（§0）。見つかったら、そのオブジェクトの持ち主（Flux の Kustomization、Helm の release、手で apply したもの、controller が作るもの）を `metadata.labels`・`annotations`・`managedFields` で調べ、作り直す可能性のあるものを `results/stage-7/baseline.md` に記録して coordinator に知らせる。

**2026-10-21 12:36Z の本番の結果: 該当は 0**（`# findings: 0`、`non-canonical` も 0）。見た値は EndpointSlice 157、Endpoints 154、IPAddress 74、Ingress 66、Node 35、Pod 832、Service 167、ServiceCIDR 2 の 1,487 個。NetworkPolicy は 6 個あるが、どれも `ipBlock` を使っていない（IP・CIDR の値が 0 個）。MetalLB の `IPAddressPool` `first-pool`（`192.168.1.101/32`、`192.168.1.190-192.168.1.254`、`2405:6581:8580:301:ace::/96`）も同じスクリプトで 0（CRD は 1.36 の厳しい検証の対象ではないが、念のため見た）。出力はタスクディレクトリの `notes/runbook-stage-7/ipcidr/`。

§6 でもう一度流し、0 のままであることを確かめる。

### 2.13 CoreDNS が置かれるノード（arm64 の control-plane に載るか）

段 6 の申し送りで、本番の CoreDNS の 2 つは amd64 の worker に載っていて、arm64 のイメージは本番ではまだ動いていない。段 7 の rollout で arm64 の control-plane に載りうるかを読み取りで確かめた（2026-10-21 12:37Z）。

- Deployment `coredns` の Pod の template は、`nodeSelector` が `kubernetes.io/os: linux` だけ、`affinity` は無い、`tolerations` は `CriticalAddonsOnly`（`Exists`）だけ。`priorityClassName` は `system-cluster-critical`。replicas 2、`RollingUpdate`（maxSurge 25%、maxUnavailable 1）
- control-plane の 3 台は `node-role.kubernetes.io/master:NoSchedule` の taint を持ち、braque は `unstable.cloud/storage:NoSchedule` を持つ。CoreDNS はどちらも許さない
- **したがって CoreDNS の Pod は control-plane（arm64）にも braque にも載らない。** 載るのは taint の無い amd64 の worker 4 台（chirico、duchamp、oeilvert、pablo）だけで、段 7 でも arm64 の CoreDNS は本番では動かない。v1.14.7 の arm64 のイメージがあることは §1.7 で確かめてある
- この Pod の template はこの PR の render で変わらない（変わるのはイメージのタグだけ）

### 2.14 MetalLB の CRD と webhook

計画 §7 の段 7 の注意（「MetalLB の CRD を apply し直すことになるので、dev で `install kubernetes` が通ることを見る」）は、dev で通った（dev の記録の「本番の段 7 の runbook に効くこと」）。`install kubernetes` の 2 段目で MetalLB の CRD と `validatingwebhookconfiguration…/metallb-webhook-configuration` が apply し直され（マニフェストは変わらないので `unchanged` か `configured`）、rc 0 になる。本番の段 6 でも `metallb-webhook-configuration` は `configured` と出て、generation は変わらなかった（段 6 の手順書 §3.3 の注）。

## 3. control-plane のマニフェストを上げる（`install kubernetes`）

### 3.1 事前確認

✋✋ **段 7 の開始の承認を取る。** §2.6 の表と PR の差分、§2.7 の drain しない理由と止める条件、§2.9 の cgroup の確認の結果、§2.5 の storage version と MutatingAdmissionPolicy の結果、§2.12 の StrictIPCIDRValidation の結果、§2.11 の unattended-upgrades の時刻と 4 台の iscsid の状態、§2.2 のベースライン（22 の Completed の Pod で消すもの、§0）、§2.4 のバックアップ、§2.8 の告知ノード、§1.4 の porkadot の置き場、§7 のロールバックの形を示す。承認を得て PR をマージし、マージした master で §3.2 に入る。

- §2.2 のベースライン、§2.4 のバックアップ、§2.9 の cgroup の確認、§2.12 の `ipcidr-scan.py` が済んでいる。§2.3 の 3 つの監視がハーネスのバックグラウンドのジョブとして動き、ログの最後の行が 1 分以内
- `tools/storage-versions.sh` が `OLD: 0`（§2.5 の 1）
- 全台 Ready、etcd 3/3 healthy、VIP の `/readyz` が `ok`
- checkout が §2.6 の PR をマージした master で、`git status --short assets porkadot.yaml` が空
- §1.4 の SSH の確かめで 8 台とも通る。`git -C $P describe --tags` が `v0.36.0`
- 作業の時間が §2.11 の unattended-upgrades の時間帯と重ならない

### 3.2 流す ✋

```sh
porkadot install kubernetes --node 192.168.1.111
```

- **`--node` を必ず付ける。** 付けないと bootstrap ノード（pablo）で `kubectl apply` を流し、`127.0.0.1:6443` に届かず rc 1 になる
- **0.36 の `install kubernetes` は 0.34・0.35 と同じ 2 段で流れる**（`assets/kubernetes/install.sh` は変わらない）: CRD と kube-apiserver のものを先に apply し、DaemonSet `kube-apiserver` の rollout の完了を待ち（`--apiserver-timeout`、既定 600 秒。完了するとログに `daemon set "kube-apiserver" successfully rolled out`）、全体を apply する。KCM・scheduler・kube-proxy が v1.36.5 で、**CoreDNS が v1.14.7 で** rollout する。kubelet-serving-cert-approver・cnidaria はマニフェストが変わらないので動かない。MetalLB の CRD・webhook は apply し直される（§2.14）
- 本番の段 6 では、全体で約 3 分（06:48:33Z → 06:51:38Z、rc 0）、VIP の FAIL は 1 回だった。dev の段 7 では apiserver の 3 台の入れ替えに約 2 分（12:00:42〜12:02:43）、`install kubernetes` は約 3 分（12:00:04〜12:02:58）、全部の rollout の完了まで約 4 分
- 時刻と rc を記録する。ログの `successfully rolled out` の時刻と、その後の `configured` の行を記録する
- rc 1 のときの扱い（`The kube-apiserver rollout did not finish in 600s`、`dial tcp 127.0.0.1:6443: connect: connection refused`、ほかのエラー）は段 5 の手順書 §3.2 と同じ
- **0.35.0 以前の porkadot で 1.36 に上げない**（0.35.0 の render では 1.35.9 になるので、そもそも上がらない。0.36.0 の置き場を §1.4 で確かめる）
- 流した直後（全体の apply の後の 1 分ほど）に、§2.3 の 3 つの監視のログが続いていることを確かめる

### 3.3 rollout の完了を確かめる

段 6 の手順書 §3.3 と同じ（版を v1.36.5 に読み替える）。CoreDNS の項目を替え、storage version を段 7 の期待値にする。

```sh
kubectl --context fraction -n kube-system rollout status daemonset/kube-apiserver --timeout=10m
kubectl --context fraction -n kube-system rollout status deployment/kube-controller-manager --timeout=10m
kubectl --context fraction -n kube-system rollout status deployment/kube-scheduler --timeout=10m
kubectl --context fraction -n kube-system rollout status daemonset/kube-proxy --timeout=10m
kubectl --context fraction -n kube-system rollout status deployment/coredns --timeout=10m
kubectl --context fraction version
```

| # | 確認 | 合格基準 |
|---|---|---|
| 1〜12 | 段 1 の手順書 §3.3 の 1〜12 | 同じ。Server が v1.36.5、apiserver・KCM・scheduler・kube-proxy が v1.36.5。Node は 8 台 Ready で kubelet は v1.35.9 のまま（apiserver 1.36 と kubelet 1.35 は skew policy の範囲）。DaemonSet `kube-apiserver` の generation が 1 つ増える（2026-10-21 は 29）。**KCM と scheduler のログに `Failed to watch`・`failed to list` が続いていない**（dev は 0）。**`E… options.go:…] The manifest file is empty, ignoring.` の 1 行は想定どおり**（§8.17） |
| 13 | CoreDNS | **v1.14.7 に rollout する**。Deployment `coredns` の generation が 1 つ増える（2026-10-21 は 12）、2/2、Pod のイメージが `registry.k8s.io/coredns/coredns:v1.14.7`。2 つの Pod は amd64 の worker に置かれる（§2.13）。ログに `CoreDNS-1.14.7`（`linux/amd64`）があり、`[ERROR]`・`[WARNING]`・`loop` の行が無い。古い v1.13.2 の Pod は消える。**`tools/dns-check.sh` の答えが §2.2 の 23 と同じ**（段 6 の手順書 §3.3 の 13 の表と同じ形。kube-dns の Endpoint の Pod の IP は新しい Pod のものに替わる） |
| 14 | approver | `kubelet-serving-cert-approver` が `0.12.1` のまま 1/1。generation が変わらない |
| 15 | CSR | 新しい CSR が無い（段 4 の手順書 §3.3 の 15） |
| 16 | storage version | `tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`。`overrides.tsv` が 1.36 の 2 行（`mutatingadmissionpolicies`・`mutatingadmissionpolicybindings`）。`/registry/peerserverleases/` が core の `v1` の `ok` で出る（§2.5 の 2） |
| 17 | ServiceCIDR と IPAddress | `servicecidrs` に `kubernetes` が 1 つで Ready、CIDRS が `10.254.0.0/24,fd20:afc2:7c09::/108`。IPAddress の数が §2.2 の 24 の数。`ClusterIPNotAllocated` の event が出ない |
| 18 | v1 Endpoints の warning | 段 4 の手順書 §3.3 の 18 と同じ（記録だけ。`removed_release` が `1.36` 以前のものが出ていないこと） |
| 19 | FlowSchema | §2.2 の 29 と同じ 11 個。generation が変わっていれば記録する |
| 20（新） | CoreDNS のプロセス（読み取り。置かれたノードで） | `crictl inspect` か `/proc/<PID>/status` で `Uid: 65532`、`CapEff` が `NET_BIND_SERVICE`（`0000000000000400`）。dev の記録の「CoreDNS」と同じ |

- CoreDNS の入れ替えの間（新しい Pod の Ready まで数秒）に、名前の問い合わせが 1〜2 回失敗するのは想定内（Deployment の rolling update）
- `install kubernetes` の出力の `configured` に、マニフェストの変わらない `poddisruptionbudget.policy/kube-controller-manager`・`kube-scheduler`、`validatingwebhookconfiguration…/metallb-webhook-configuration` が出るのは前から（段 5・段 6 の本番）。generation が変わらなければ想定内
- apiserver の rollout の途中に、controller-manager の `FailedToUpdateEndpoint` などが 1 回ずつ出ることがある（段 4 の手順書 §3.3 の注）。続かなければ想定内。dev では、入れ替わりの直後の apiserver のログに `grpc: addrConn.createTransport failed to connect to {… :2379 …}` と、etcd の遅れの直後の `http: Handler timeout` が出た（dev の記録の「`install kubernetes` の順番」）
- **`install kubernetes` の直後（全体の apply の後の 1 分ほど）に etcd の health と VIP を特に見る**（§8.13）
- ここで問題があれば、kubelet にまだ触っていないので、§7.2 で control-plane だけを戻せる

## 4. control-plane の kubelet を上げる（192.168.1.113 → .112 → .111）

### 4.1 何が起きるか

段 6 の手順書 §4.1 と同じ（版を読み替える）。`install kubelet --node <IP>` は、`install-deps.sh`（kubelet・kubectl・crictl を落として張り替える。etcd の tarball は版が同じなので落とさない、CNI plugins は版の印が v1.9.1 で同じなので展開しない）、`install-pkgs.sh`（`apt-get install --no-upgrade`、iscsid は `systemctl start` だけ）、`install.sh`（addon の `dns`、`multipathd`、`etcd`）を root で流し、kubelet を v1.36.5 で再起動する。

- **etcd は 3.6.15 のまま**（`etcd-server.yaml` は変わらない）。ただし新しい kubelet が etcd の mirror Pod を作り直す（1.32〜1.36 と同じ）。最初のコンテナは古い etcd が 2380 番を離す前に起きて `bind: address already in use` で落ち、次で起きる（dev の段 7 は 3 台とも restartCount 1。本番の段 6 も 3 台とも 1）。その間ほかの 2 台で quorum を保つ
- `/etc/etcd/pki` の証明書と鍵を root 0600 で置き直す。`etcd.crt` は作り直したもの（同じ鍵、同じ CA。§2.6）に替わる
- `dns` の addon は `systemd-networkd` を再起動するので、cnidaria の `no route` のログが出る（§8.1）
- control-plane には Longhorn のボリュームが無く、iscsid は動いていてセッションは無い（§2.7）

### 4.2 2 つ目のバックアップ

1. ✋ etcd のバックアップを取る（§2.4 と同じ形）。**1.36 の control-plane、CoreDNS v1.14.7、kubelet はまだ 1.35** の状態。§7.4 の restore で、段の前（§2.4）の代わりに使える
2. 承認の節目は無い（§0）。§3.3 が合格なら、そのまま §4.3 に入る

### 4.3 1 台の手順

段 6 の手順書 §4.3 と同じ（1. 読み取りの確認と `snap`・`tools/node-state.sh` の控え、2. ✋ リーダーなら `move-leader`、3. ✋ `porkadot install kubelet --node <IP>`、4. kubelet の起動から 1 分ほど待って §4.4）。

- 2026-10-21 12:37Z のリーダーは .113（`57ec6f12ac7b683e`）。このままなら、.113 の作業の前に .111（`21ab2aeb56731588`）か .112（`fbb0c648cf5852a5`）へ移す。その後も、各台の作業の前にリーダーを読み、対象がリーダーなら移す（dev では .112、.111 の前に移した）
- 1 台ずつ、§4.4 の確認が済んだら次の台に入る
- 段 6 の本番では 1 台 24 秒〜44 秒だった

### 4.4 1 台ごとの確認と、次の 1 台へ進む条件

段 6 の手順書 §4.4 と同じ。次を読み替える。

| # | 確認 | 合格基準（段 6 から変わるところ） |
|---|---|---|
| 1 | Node | VERSION が v1.36.5。kubelet が起きている |
| 2 | バイナリ | 向き先が `kubelet-v1.36.5`、`kubectl-v1.36.5`、`crictl-v1.36.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`（変わらない）。CNI の印と 4 つのプラグインは `v1.9.1` のまま。前の版のファイル（`kubelet-v1.35.9` など）も残っている（§7 の戻しで使う） |
| 4 | etcd | 3/3 healthy、リーダーが居る、raft index がそろう。3 台とも 3.6.15。`member list -w table` が 3 つとも `started` |
| 5 | etcd の Pod | 1/1 Running、`etcd:3.6.15-0`。mirror Pod の UID が変わる。**restartCount 1〜2 は想定どおり**。3 以上、または CrashLoopBackOff が 1 分を超えたら止める |
| 7 | Pod の再起動 | **差分は `kube-system/etcd-<IP>` の UID と restartCount だけ**。ほかに UID・restartCount が変わったものがあれば止める |
| 8 | iscsid | MainPID と ActiveEnterTimestamp が前（§4.3 の 1 の `node-state.sh`）と同じ。変わっていたら止める（§2.7、§2.11） |
| 16 | etcd の版 | 3 台の `/version` が `{"etcdserver":"3.6.15","etcdcluster":"3.6.0","storage":"3.6.0"}` のまま |
| 17 | etcd のフラグ | 段 6 の手順書 §4.4 の 17 と同じ |
| 18 | etcd のログ | 段 6 の手順書 §4.4 の 18 と同じ（想定どおりのものの一覧も同じ）。起動の直後の `failed to publish local member to cluster through raft` は、数回から 100 回ほど出ることがある（本番の段 7 の .112 は 103 回で、2.5 ミリ秒の間に収まり、直後に `published local member to cluster through raft`）。回数ではなく、`published` が出て続かないことを見る。ほかの warn・error の種類が増えたら記録し、続くものがあれば止める |
| 19（新） | kubelet のログ | 起動の直後の項目は段 6 と同じ（etcd の mirror Pod の `already exists`、`Flag --container-runtime-endpoint has been deprecated` など）。dev では止まる前の古い kubelet が `missing content for CA bundle "client-ca-bundle::/etc/kubernetes/pki/ca.crt"` を出した台がある（害は無い）。ほかに増えたものは記録する |

次の 1 台へ進む条件も段 6 の手順書 §4.4 と同じ（すべて合格、全 8 台 Ready、etcd 3/3 healthy で raft index がそろう、Running / Completed 以外の Pod がベースラインから増えていない）。

- 1 台の kubelet が 1.36 で起きないときは、**次の台に進まず、止めて報告する**（§7.3 で、その台を 1.35 に戻すかをユーザーが決める）

### 4.5 control-plane の 3 台の後

- 3 台の `/version` と `etcdctl endpoint status --cluster -w table` が §2.2 の 4 と同じ版（3.6.15、3.6.0）で、リーダーが居る
- §2.3 の etcd の health の監視（2 つのジョブ）を止める（ノードの側の while も止める）

## 5. worker の kubelet を上げる（1 台ずつ、drain しない）

### 5.1 順番

アタッチされた Longhorn のボリュームが少ない台から多い台へ並べる（段 6 の手順書 §5.1 と同じ考え方）。2026-10-21 12:37Z のアタッチの数（pablo 1、oeilvert 2、duchamp 4、chirico 9）は段 6 と同じなので、**pablo → braque → oeilvert → duchamp → chirico** にする。当日の読み取りでアタッチの数が変わっていれば並べ直してよい。braque はどこに入れてもよい（§5.4 の時間帯を避ける）。

- 最初の worker の pablo は API の VIP を告知している（段 6 の完了の確認）。段 6 の本番では pablo の `install kubelet` の間も VIP は途切れなかった
- worker には etcd が無い。`/opt/bin` の etcdctl と etcdutl は 3.6.15 のまま

### 5.2 1 台の手順

段 6 の手順書 §5.2 と同じ（§8.12 の Pod の削除も同じ扱い）。段 6 の本番では 1 台 20 秒〜26 秒だった。

### 5.3 1 台ごとの確認

段 6 の手順書 §5.3 と同じ。次を読み替える。

| # | 確認 | 合格基準（段 6 から変わるところ） |
|---|---|---|
| 1 | Node | VERSION が v1.36.5 |
| 2 | バイナリ | 向き先が `kubelet-v1.36.5`、`kubectl-v1.36.5`、`crictl-v1.36.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と 4 つのプラグインは `v1.9.1` のまま。`kubelet-v1.35.9` なども残っている |
| 3 | iscsid | **MainPID と ActiveEnterTimestamp が前と同じ**。変わっていたら止める（§2.7、§2.11） |
| 4 | iSCSI のセッション | 同じ sid・portal・target。portal がそのノードの今の instance-manager の IP。古いセッションが無い |
| 5 | エンジン | 同じボリューム、同じ起動の時刻。`older-than-iscsid` の数が前と同じ |
| 7 | Pod の再起動 | **差分が無い**（名前・UID・restartCount が同じ）。1 つでもコンテナの再起動があれば、ここで止めて報告する（§2.1 の 3） |

ほか（Longhorn の node の一瞬の `is down`・`Waiting for disk`、`FailedMount` の `no Pending workload pods`）は段 6 の手順書 §5.3 と同じ。

### 5.4 braque の手順

段 6 の手順書 §5.4 と同じ（バックアップの CronJob の時間帯を避ける）。

### 5.5 次の 1 台へ進む条件

段 6 の手順書 §5.5 と同じ（版を読み替える。終えたノードが v1.36.5、まだのノードが v1.35.9）。

- **最初の worker（pablo）の後に、✋ `netcheck.sh` と §1.9 の NetworkPolicy の確認を流す**（1.36 の apiserver と、1.36 の kubelet のノードを含む形で、cnidaria の NetworkPolicy の処理が動くこと）

## 6. 段 7 の完了の確認

8 台を終えたら、計画 §6.3 の項目がすべて成り立つことを確かめ、`results/stage-7/summary.md` に残す。段 6 の手順書 §6 と同じ項目で、次を読み替える・足す。

- 8 台が Ready、全台 v1.36.5、CONTAINER-RUNTIME が `containerd://2.3.6`。どのノードも SchedulingDisabled でない
- 8 台の `/opt/bin` が `kubelet-v1.36.5`、`kubectl-v1.36.5`、`crictl-v1.36.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と 4 つのプラグインが `v1.9.1`
- **etcd**: 3/3 healthy、全メンバーが 3.6.15、cluster version・storage とも 3.6.0、リーダーが居る、raft index がそろう。3 台の動いている etcd のフラグに `--experimental-` が無い。3 台の `/etc/etcd/pki` が `600 root:root`
- VIP の `/livez` が `ok`、`/version` が v1.36.5
- **CoreDNS が v1.14.7 で 2/2 Running**（amd64 の worker）。ログにエラーと `loop` が無い。`tools/dns-check.sh` をもう一度流し、§2.2 の 23 と同じ答え
- **全 Pod の restartCount が、ベースライン（§2.2 の 5）から増えていない**（control-plane の etcd の mirror Pod は UID が変わり restartCount 1〜2。`install kubernetes` で作り直された Pod（apiserver 3、KCM 2、scheduler 2、kube-proxy 8、CoreDNS 2）は新しい UID で 0）
- **storage version**: `tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` が 1.36 の 2 行
- **StrictIPCIDRValidation**: `tools/ipcidr-scan.py` が `# findings: 0` のまま（§2.12）
- **ServiceCIDR と IPAddress**: `servicecidrs` が `kubernetes` の 1 つで Ready、IPAddress の数が ClusterIP の数と同じ。FlowSchema が 11 個
- **cgroup**: 8 台とも `cgroup2fs` のまま、kubelet が 8 台とも動いている
- Longhorn、Longhorn の設定、iSCSI（8 台の iscsid の PID とセッションがベースラインと同じか、変わったものは §2.11 の見分けの結果）、cnidaria（✋ `netcheck.sh`、✋ §1.9 の NetworkPolicy の確認）、MetalLB、braque の NFS、`registry.fraction.jp`、CSR、§2.3 の監視の FAIL、leader election で再起動した controller: 段 6 の手順書 §6 と同じ。**K8s 1.36 は Longhorn v1.13.0 の要件（1.34 以上）に入る**（§1.10）
- `kubectl --context fraction top nodes` が応答し、Prometheus のスクレイプが落ちていない（`up == 0` が 0 個。`kube-etcd` の 3 つを含む）。`count(etcd_server_has_leader)` が 3
- `apiserver_requested_deprecated_apis` を記録する（`removed_release` が `1.36` 以前のものが出ていれば止めて調べる）。v1 Endpoints の warning の出どころも段 6 と同じ形で記録する（段 6 では Longhorn v1.13.0 の longhorn-manager・longhorn-global-manager と prometheus-operator v0.90.1）
- kubelet の起動時の warning は `Flag --container-runtime-endpoint has been deprecated` のほかに増えていない（計画 §10 の KubeletConfiguration への移行の対象。段 8 で直す）
- 新しい warning のイベント・ログ（kubelet、apiserver、kube-proxy、cnidaria、etcd、Longhorn、CoreDNS）が増えていない（§8 のもの、v1 Endpoints の warning は除く）
- etcd のバックアップ（§2.4、§4.2 の 2 つ）を worktree からメインの checkout の `backup/` へ移した（worktree で流した場合。coordinator）

## 7. ロールバック

**戻すのは runbook から外れる操作なので、その都度ユーザーの承認を取る。** 戻すと決める目安は段 1 の手順書 §7 と同じ（rollout が終わらない、VIP が 1 分を超えて応答しない、Node が 5 分たっても Ready にならない、etcd が 2/3 を下回る、Pod の再起動が続く、Longhorn のボリュームが degraded のまま戻らない、1.36 や CoreDNS v1.14.7 に固有と見られる問題）。

**段 7 は etcd を変えないので、戻し方は段 6 と同じ形**（etcd のデータの版の制約が無い）。**ただし、どの形も dev で流していない**（dev の記録の「本番の段 7 の runbook に効くこと」）。

| どこまで進んだか | 戻し方 | dev で確かめたか |
|---|---|---|
| `install kubernetes` の後（kubelet はまだ 1.35） | §7.2（0.35.0 で `install kubernetes`） | 確かめていない |
| control-plane・worker の kubelet の途中・全部の後 | kubelet を §7.3 で 1.35 に戻してから（新しい順に）、§7.2 で control-plane を戻す | 確かめていない |
| どの時点でも（最後の手段） | §7.4 の `etcd restore`（段の前か §4.2 の backup） | restore そのものは段 5 の dev で確かめた（0.34.1。0.35.0・0.36.0 は同じ実装）。1.36 からの restore は確かめていない |

### 7.1 戻すための材料

- **前の版**: この PR の前の master（`9d4898a`）の `assets/` と `porkadot.yaml`、**porkadot 0.35.0**（`v0.35.0`、`e4aa3e6`）。この `assets/` は本番が今動いているもの（段 6 の 0.35.0 の render）
- **porkadot 0.35.0 の置き場**: §1.4 の `worktrees/porkadot-v0-35-0`（段 6 で使ったもの。`bundle install` 済み。2026-10-21 12:3xZ に `porkadot help` が動くことを確かめた）
- **etcd のバックアップ**: §2.4（段の前、1.35 の control-plane、CoreDNS v1.13.2）、§4.2（1.36 の control-plane、CoreDNS v1.14.7、kubelet は 1.35）

用意の仕方（作業端末で。ノードには触らない。段 6 の手順書 §7.1 と同じ形）:

```sh
P_OLD=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-35-0   # git -C $P_OLD describe --tags が v0.35.0
git clone <このリポジトリの checkout> /tmp/fraction-stage-6
git -C /tmp/fraction-stage-6 checkout 9d4898a
cd /tmp/fraction-stage-6
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

- `git worktree add` は元の clone の `.git` に書き込むので、サンドボックスでは拒否される。`/tmp` に clone して使う
- 始める前に `grep VERSION $P_OLD/lib/porkadot/version.rb` が 0.35.0 で、`BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot help` が動くことを確かめておく

0.35.0 の `install kubelet` について:

- `/opt/bin/<名前>` の向き先で判定して張り替える。前の版のバイナリ（`kubelet-v1.35.9`、`crictl-v1.35.0`）はノードに残っているので、落とし直さずに向き先を戻す。etcd・etcdutl・CNI は同じ版なので変わらない
- **control-plane の etcd のマニフェストは、0.35.0 と 0.36.0 で同じ**（3.6.15-0、同じフラグ。§2.6）。戻しても etcd は 3.6.15 のまま（static Pod は作り直される）
- `install-pkgs.sh` は 0.36.0 と同じ（iscsid は `initiatorname.iscsi` が変わったときだけ再起動する）
- 1.36 → 1.35 の kubelet の戻しでコンテナが再起動するかは、dev で確かめていない。**Longhorn のボリュームがアタッチされた台を戻すときは、再起動する前提で drain してから流す**（段 6 の手順書 §7.1 と同じ。drain の後・`install kubelet` の前と後に `iscsiadm -m session` を見る）
- 0.35.0 の SSH は 0.36.0 と同じで、サンドボックスの中で流せる

### 7.2 control-plane のマニフェストを戻す ✋

```sh
cd /tmp/fraction-stage-6
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml
```

- **kubelet が 1.36 の台が残っているうちは流さない**（kubelet は apiserver より新しくてはいけない。先に §7.3 で戻す）
- 0.35.0 の `install.sh` も apiserver を先に入れて rollout を待つので、**apiserver が先に 1.35.9 になり、その間 1.36 の KCM・scheduler が 1.35 の apiserver と話す**。この向きは dev で確かめていない。新しい Pod のスケジュールが止まったまま進まないときは、止めて報告する（段 6 の手順書 §7.2 と同じ）
- apiserver・KCM・scheduler・kube-proxy が v1.35.9 に、**CoreDNS が v1.13.2 に戻る**
- storage version: 1.36 の apiserver は本番にあるオブジェクトの storage の版を変えない（§2.5）ので、1.35 に戻しても `OLD` は出ない見込み。1.36 が書いた `/registry/peerserverleases/` のキーは etcd に残り、1.35 の apiserver（peer proxy は既定で off）は使わない（害は無い見込み。確かめていない）
- FlowSchema: 1.36 は消さない・足さない見込み（dev で 11 個のまま）なので、11 個のまま
- rc 1（`connection refused`）なら rollout を待って流し直す（段 5 の手順書 §3.2 と同じ）
- §3.3 と同じ確認を、版を読み替えて行う（CoreDNS は v1.13.2、`tools/dns-check.sh` の答えが §2.2 の 23 と同じ、`overrides.tsv` は 1.35 の 1 行）

### 7.3 kubelet を戻す（1 台） ✋

```sh
cd /tmp/fraction-stage-6
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubelet --node <ノード> --config ./porkadot.yaml
```

- `/opt/bin` の向き先が `kubelet-v1.35.9`、`kubectl-v1.35.9`、`crictl-v1.35.0` に戻る（etcdctl・etcdutl は 3.6.15、CNI は v1.9.1 のまま）。確かめる
- **Longhorn のボリュームがアタッチされた台は、drain してから流す**（§7.1）
- control-plane の台は、リーダーなら先に `move-leader` する（etcd の static Pod が作り直される）
- 戻した台でも、§4.4 または §5.3 の確認を、版を読み替えて行う。iscsid は再起動しない見込み（0.35.0 の `install-pkgs.sh`）なので、「PID が同じ」をそのまま見る

### 7.4 `porkadot etcd restore` ✋

段 6 の手順書 §7.4 と同じ形（使う backup だけを別のディレクトリに置き、`porkadot etcd restore --path ./backup-restore`。ログの `restored revision` が `current revision` + 10 億以上であることを確かめる。所要時間は dev で約 4 分、API は約 2〜3 分止まる）。**restore は最後の手段**で、API の中身が backup の時点に戻る（Longhorn の CR を含む）。

- **0.36.0 の `etcd restore` は 0.35.0・0.34.1 と同じ実装**（0.35.0 → 0.36.0 の差分に restore の変更は無い）。どちらで流してもよい。0.34.0 は使わない（段 5 の手順書 §7.4）
- 3 台の control-plane に `/opt/bin/etcdutl` → `etcdutl-3.6.15` があること（2026-10-21 12:36Z は 8 台ともある）
- etcd は 3.6.15 のまま戻る（段 7 では etcd の版が変わらないので、版の制約は無い）

| backup | API の中身 | restore の後 |
|---|---|---|
| §2.4（段の前） | 1.35 の control-plane、CoreDNS v1.13.2 | kubelet が control-plane を 1.35.9 に入れ替える。**kubelet を 1.36 にした台があれば、kubelet が apiserver より新しい（skew policy の外）**。続けて §7.3 で kubelet を戻すか、0.36.0 の `install kubernetes` で上げ直すかを、その時点でユーザーと決める |
| §4.2（control-plane の kubelet の前） | 1.36 の control-plane、CoreDNS v1.14.7 | control-plane は 1.36.5 のまま。失われる変更が少ない |

### 7.5 段 7 全体をやめる

kubelet は kube-apiserver より新しくてはいけないので、**kubelet を先に戻し、control-plane を最後に戻す。** worker を上げた順の逆に §7.3 で戻し、control-plane の kubelet を上げた順の逆（.111 → .112 → .113）に §7.3 で戻し、最後に §7.2 で control-plane のマニフェストを戻す。

戻し終えたら、§6 の確認を版を読み替えて行い、`results/stage-7/` に戻した経緯を残す。

## 8. 既知の問題と注意

### 8.1 `install kubelet` のたびの cnidaria の `no route`

段 6 の手順書 §8.1 と同じ。段 6 の本番では各台で error が 6〜8 件ずつ、1 秒ほど（oeilvert は 0）。unattended-upgrades の needrestart が systemd-networkd を再起動したとき（§2.11）にも同じものが出うる。

### 8.2 render が証明書を作り直す

段 6 の手順書 §8.2 と同じ。当日に render し直さない。

### 8.3 `install kubernetes` の rc 1

段 6 の手順書 §8.3 と同じ（`connection refused` の rc 1、apiserver の rollout の timeout）。0.36.0 では apiserver が先に 1.36 になり、dev のログに `Failed to watch` が 0 だった。戻しの向きは §7.2。

### 8.4 1.36 の kubelet ではコンテナが再起動しない

段 6 の手順書 §8.4 と同じ。dev の 7 台で、`install kubelet` の前と後の Pod の UID と restartCount が同じだった。control-plane の etcd の static Pod は作り直される（restartCount 1〜2）。ほかのコンテナが 1 つでも再起動したら止める。

### 8.5〜8.9

段 6 の手順書 §8.5〜§8.9 と同じ。CSR は段 7 の間も出ない見込み（dev でも出なかった）。

### 8.10 iscsid と iSCSI のセッション

段 6 の手順書 §8.10 と同じ。drain に切り替える台が出たら、drain の後・`install kubelet` の前と後に `sudo iscsiadm -m session` を見て、Longhorn のセッションが残っていないことを確かめる。残っていたら止めて報告する（logout は §0 の runbook から外れる操作）。

### 8.11 CNI plugins

段 7 では変えない（段 6 の手順書 §8.11 と同じ。`CNI plugins v1.9.1 already installed`）。

### 8.12 Longhorn の `no Pending workload pods`（longhorn/longhorn#8072 の形）

段 6 の手順書 §8.12 と同じ（段の開始の承認の範囲の ✋。消す前に名前を知らせる）。**JST 05:30 より後に作業するなら、当たる前提で §2.2 の 22 で洗い出す**。段 6 の本番では、duchamp の前に 6 つ、chirico の前に 1 つ消した。

### 8.13 etcd の遅れと、1 台が止まる間の quorum

段 6 の手順書 §8.13 と同じ。dev の段 7 でも、`install kubernetes` の直後（12:03:10〜12:03:35Z、7 台が新しい kube-proxy のイメージなどを pull・展開していた時刻）に、3 台とも `apply request took too long`（最大 0.98 秒）、.111 に `slow fdatasync`（2.6 秒）が出た（`leader failed to send out heartbeat on time` は無い）。netcheck が DaemonSet を作った時刻にも同じものが出て、etcd の health が 1 サンプル unhealthy、VIP が 1 サンプル 000 になった（dev の見つけたことの 4）。7 台の VM が同じホストのディスクを使う dev に特有と見ている。本番の段 6 では、`install kubernetes` の直後も 3 台とも healthy だった（`results/stage-6/summary.md` §2.5）。§2.3 の etcd の health の監視で見る。

- control-plane の `install kubelet` の間は、その台の etcd が十数秒止まる（§4.1）。ほかの 2 台が unhealthy にならないこと
- 本番で VIP が 15 秒を超えて応答しないときは、etcd のログ（`slow fdatasync`、`apply request took too long`、`heartbeat`）を見て記録する。1 分を超えたら §7 の目安に当たる

### 8.14 storage version

`storage-versions.md`。§2.5 のとおり、段 7 では書き直しは無い。`install kubernetes` の前と後に `OLD` が出たら止めて調べる。MutatingAdmissionPolicy・…Binding（1.36 は `v1beta1` で保存する）は、この PR の `tools/storage-versions.sh` が `OLD` と数えない。

### 8.15 metrics

1.36 で、kube-controller-manager の metrics `volume_operation_total_errors` が `volume_operation_errors_total` に改名される（計画 §7 の段 7）。本番の PrometheusRule と ConfigMap（Grafana のダッシュボードを含む）に、どちらの名前も 0 件（2026-10-21 12:4xZ の読み取り）なので、影響は無い。ほかに本番の kube-prometheus（chart 85.2.1）のダッシュボードとルールが使う metrics に影響する変更は、この手順書を書いたときに見つけていない。§6 で `up == 0` と `count(etcd_server_has_leader)` を見る。出なくなったものがあれば記録し、段 8 の後の kube-prometheus-stack の更新（計画 §8）で扱う。段の更新は止めない。

### 8.16 CoreDNS の upstream に kube-dns が入っている

段 6 の手順書 §8.16 と同じ。CoreDNS のログに `loop`（`Loop (…) detected for zone "."`）が出て CoreDNS が落ちたら、止めて報告する（v1.12.4・v1.13.2 では出ていない）。

### 8.17 1.36 の control-plane の `The manifest file is empty, ignoring.`

1.36 の kube-apiserver・kube-controller-manager・kube-scheduler は、起動のたびに `E… options.go:205] The manifest file is empty, ignoring.` を error のレベルで 1 行出す（dev の見つけたことの 1）。`k8s.io/component-base/metrics` の `Apply()` が、`--allow-metric-labels` も `--allow-metric-labels-manifest` も渡されていないとき（porkadot は渡さない）に出すもの（v1.36.5 の `staging/src/k8s.io/component-base/metrics/options.go`）で、害は無い。**止める理由にしない。** ログの `E` の行を数えるときは、この 1 行を除いて数える。

### 8.18 `UnknownVersionInteroperabilityProxy`（apiserver の peer proxy）

1.36 で `UnknownVersionInteroperabilityProxy` が beta・既定 on になり、apiserver が etcd に `/registry/peerserverleases/<apiserver の ID>`（core の `v1` の `Endpoints`、apiserver ごとに 1 つ）を書く（dev の見つけたことの 2）。dev ではエラーは出ていない（`--peer-ca-file` は渡していない）。

- **段 7 では働かない。** peer proxy は、版の違う apiserver が並ぶ間に、自分が提供しない API への要求をその API を提供する peer へ回すもの。段 7 の `install kubernetes` は 1.35 → 1.36 の入れ替えで、1.35 の apiserver はこの機能が既定で off なので peer として振る舞わない。入れ替え後は 3 台とも 1.36 で版がそろう
- `tools/storage-versions.sh` では `/registry/peerserverleases/` は core の `v1` の `ok` として数えられる（§2.5 の 2）
- **段 8 への申し送り**: 段 8 の `install kubernetes`（1.36 → 1.37）では、apiserver の入れ替えの間に 1.36 と 1.37 の apiserver が並び、両方でこの機能が働く。peer の間の TLS（`--peer-ca-file`、`--peer-advertise-ip`・`--peer-advertise-port`）を porkadot が渡していないときの振る舞い（要求の転送の失敗のログ、503 など）と、`/registry/peerserverleases/` の数を、段 8 の dev の検証で見る

## 9. 記録

`results/stage-7/` に、ベースライン（`baseline.md`。§2.4 のバックアップ、§2.5 の storage version と MutatingAdmissionPolicy、§2.9 の cgroup、§2.10 の resolv.conf、§2.11 の unattended-upgrades の時刻と 4 台の iscsid、§2.12 の StrictIPCIDRValidation も）、`install kubernetes`（`control-plane.md`。§3.3 の 13〜20 と CoreDNS の答え、§4.2 のバックアップも）、各台（`<ノード>.md`。control-plane は `192.168.1.11N.md`）、全体のまとめ（`summary.md`。§6 の v1 Endpoints の warning の出どころの表と metrics の確認も）を残す。各台の雛形は `results/stage-7/template.md`。
時刻（UTC。control-plane のホストの JST の時刻は直して書く）、読み取りの結果、実行したコマンドと出力の要点、Pod の再起動の有無、iscsid の PID とセッションの前と後、etcd の版と健全性、監視の FAIL（VIP・LB と etcd の health）と監視が止まっていた時間、leader election で再起動したもの、手順書との差を書く。`tools/node-state.sh` と `snap` の出力、監視のログ（`stage-7-probe.log`、`stage-7-etcd-*.log`）、`tools/storage-versions.sh`・`tools/dns-check.sh`・`tools/ipcidr-scan.py` の出力、`endpoints-warnings.tsv` はタスクディレクトリの `notes/stage-7/` に置き、要点を記録に写す。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（同じ PR か、記録の PR で）。

## 10. 段 7 の後

- 健全性を確かめてから段 8（1.37）へ。段 8 は etcd のマイナー更新（3.7）を含むので、計画 §9.6 の目安で 1 日ほど様子を見る
- 段 6 の etcd のバックアップ（`etcd-2026-10-21T06:46:11+00:00.db`、`…T06:56:16…`）は、段 7 に入ったので戻しの材料としては使わない。消すかはユーザーが決める
- 段 8 の注意（計画 §7）: etcd 3.7（`--experimental-*` が残ると起動しない）、kube-proxy の `mode` の明示、CoreDNS の最新と Corefile の `cache` の改善、kubelet の `--container-runtime-endpoint` を KubeletConfiguration へ移す（kubelet の起動時の warning の `Flag --container-runtime-endpoint has been deprecated` はそれまで残る）。1.37 の apiserver が MutatingAdmissionPolicy の `v1beta1` の override を外すかを見て、`tools/storage-versions.sh` の 1.37 の場合を決める（本番にオブジェクトが無ければ書き直しは要らない）
- 段 8 の `install kubernetes` の間の peer proxy（§8.18）を dev で見る
- 申し送り（段 7 の範囲の外）: 段 6 の手順書 §2.10 の CoreDNS の upstream に kube-dns が入る件（porkadot の `dns` の addon と Corefile）。§2.11 の unattended-upgrades の needrestart による iscsid の再起動（作業の時間帯を避けるために続けて見る）。cnidaria-cni-dev の `notes/fraction-runbook/common.sh` の `IMAGE`（`v0.1.0`。§1.8）を、今の DaemonSet のイメージかノードの nft で読む形に直すこと（別のタスクのスクリプト）
