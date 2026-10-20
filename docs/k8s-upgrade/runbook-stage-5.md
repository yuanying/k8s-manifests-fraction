# 段 5 の手順書: K8s を 1.33.13 から 1.34.12 へ、etcd を 3.5.34 から 3.6.15 へ上げる（本番 `fraction`）

本番クラスタ `fraction` の Kubernetes を v1.33.13 から v1.34.12 へ上げ、**etcd を 3.5.34 から 3.6.15 へマイナー更新する**手順。porkadot を 0.33.1 から 0.34.1 に替える。CoreDNS と CNI plugins は据え置く。
計画は同じディレクトリの `plan.md`（以下「計画」）の §6（骨子）と §7 の段 5 の行、決まったことは §9 にある。前の段は `runbook-stage-4.md`（以下「段 4 の手順書」）で、この手順書はそれを下敷きにし、**段 4 から変わる点を中心に書く**。段 3・段 4 と同じく drain しない。

| | 更新前 | 更新後 |
|---|---|---|
| porkadot | 0.33.1（段 4 の 0.33.0 に cnidaria の直しを足したもの） | **0.34.1**（`060a687`、タグ `v0.34.1`） |
| kube-apiserver、kube-controller-manager、kube-scheduler、kube-proxy | v1.33.13 | **v1.34.12** |
| kubelet、kubectl（ノードの `/opt/bin`） | v1.33.13 | **v1.34.12** |
| crictl（ノードの `/opt/bin`） | v1.33.0 | **v1.34.0** |
| etcd（control-plane の static Pod） | 3.5.34-0 | **3.6.15-0**（マイナー更新。フラグの名前が変わる） |
| etcdctl（ノードの `/opt/bin`） | 3.5.34 | **3.6.15** |
| etcdutl（ノードの `/opt/bin`） | 無い | **3.6.15**（新しく置かれる。`etcd restore` が使う） |
| CoreDNS | v1.12.4 | 変えない（段 4 で上げた。計画 §2） |
| CNI plugins（ノードの `/opt/cni/bin`） | v1.9.1 | 変えない（版の印が同じなので展開しない） |
| `install-pkgs.sh`、`initiatorname.iscsi` | iscsid は `initiatorname.iscsi` が変わったときだけ再起動 | 変えない |
| cnidaria、MetalLB、kubelet-serving-cert-approver | v0.1.1（init container なし）、v0.14.5、0.12.1 | 変えない（マニフェストの差分が無い） |
| kubelet の `config.yaml`・`kubelet.service` | — | 変えない |
| containerd、runc | 段 C の 2.3.6、1.5.1 | 変えない |
| Longhorn | v1.11.2 | 変えない。**段 5 の後に 1.12.x → 1.13.x へ上げる**（§10、計画 §4.3） |

porkadot 0.34.0 に入った PR は porkadot#50（K8s v1.34.12、crictl v1.34.0、etcd 3.6.15 とフラグの出し分け、etcdutl を置き `etcd restore` を etcdutl に、bootstrap の kube-proxy の `serviceAccountName` の削除、`install kubernetes` で kube-apiserver を先に入れて rollout を待つ、restore で revision を上げて compacted にし control-plane を入れ替える）、0.34.1 は porkadot#52（restore の revision の上げ幅を max(10 億、今 − snapshot + 10 億) にする。`--bump-revision`）。

この手順は dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で先に通してある（2026-10-20）。記録は porkadot-dev の `docs/k8s-upgrade/verification-0.34-rc.md`（以下「dev の記録」。porkadot-dev の main `a7eb8dc`、porkadot-dev#14）。dev で分かったことは次のとおり。

- **1.34 の kubelet に上げても、コンテナは再起動しなかった**（1.32・1.33 と同じ）。7 台すべてで Pod の UID・restartCount が変わらず、変わったのは control-plane の etcd の mirror Pod だけ。**iscsid も 7 台とも PID が変わらなかった。** Longhorn のボリュームをアタッチしたまま `install kubelet` した 2 台で、ボリュームは `attached`・`healthy` のまま、セッションとエンジンも変わらず、detach の後にセッションは残らなかった
- **0.34.0 より前の形（apiserver と KCM・scheduler を同時に上げる）では `install kubernetes` がデッドロックした**（dev の見つけたことの 1。§3.2）。0.34 では kube-apiserver を先に入れて rollout を待つので、1 回目で rc 0 になった
- **etcd は control-plane の `install kubelet` で 1 台ずつ 3.6.15 になり、混在中も 3/3 healthy だった。** 3 台目の後に cluster version と storage が 3.6.0 になった（§4）
- **全台が 3.6 になった後でも、上げる前（3.5）の backup を 0.34.1 の `etcd restore` で戻せた**（etcd は 3.6.15 のまま起き、API の中身が backup の時点に戻る。§7.4）
- **1.34 で IPAddress が v1beta1 のまま `OLD` になり、書き直しで v1 になった。** ServiceCIDR は 1.34 の apiserver が自分で v1 に書き直した（§2.5、§3.4）
- **3.6.15 の etcdutl には `check v2store` が無い。** 3.5 の etcdutl で上げる前に流す（§2.9）
- dev では、1 台の etcd が止まる間に残りの 2 台のディスクが詰まり、API が約 20 秒止まったことが 1 回あった（7 台の VM が同じホストのディスクを使う dev に特有と見ている。§8.13）
- CSR は 1 つも出なかった。作業端末の kubectl v1.33.13 で 1.34 の server を問題なく使えた。porkadot のコマンドとノードへの `ssh` は、すべて pi のサンドボックスの中で流した

これを受けて、**本番の段 5 でも、どのノードも drain しない**（§2.7）。止める条件（Pod の UID・restartCount の変化、iscsid の PID の変化、古いセッション）は段 4 のまま使う。

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **arm64 の control-plane での etcd 3.6.15 と 1.34 の kubelet**。dev の段 5 は amd64 の VM で通した。arm64 のイメージとバイナリが配布されていることは確かめてある（§1.7）
- **本番の etcd のデータ**（2020 年から使っている。DB 55 MB、revision は dev より桁が大きい）での 3.6 への更新。v2store の確認（§2.9）を先に流す
- **混在中の etcd を 3.5 に戻すこと**（§7.3）と、**全台 3.6 の後に kubelet まで 1.33 に戻すこと**（§7.5）。どちらも dev では流していない
- **本番の数の IPAddress の書き直し**（74 個の見込み。dev は 16 個）
- **本番の Longhorn のボリュームがアタッチされたままの `install kubelet`**（chirico 10 本、oeilvert 5 本、pablo 1 本。2026-10-20）。段 3・段 4 の本番では同じ形で問題が無かった

## 0. 役割と約束ごと

段 4 の手順書 §0 と同じ。違いは次のとおり。

- **承認の節目は 2 つ**（計画 §9.1「本番の各段の開始」と「etcd のマイナー更新を含む段（5 と 8）の control-plane の kubelet の更新の前」）。この手順書では ✋✋ を付けた。
  - ✋✋ **段 5 の開始**: render の差分（§2.6。この手順書と同じ PR）、drain しないこと（§2.7）、v2store の確認の結果（§2.9）、ベースライン（§2.2）とバックアップ（§2.4）を見せ、PR をマージしてから、`install kubernetes` を流す前（§3.1）
  - ✋✋ **control-plane の kubelet（etcd 3.6）の前**: `install kubernetes` の結果（§3.3）と IPAddress の書き直しの結果（§3.4）、2 つ目のバックアップ（§4.2）、ロールバックの形（§7。全台 3.6 の後は restore だけになること）を見せてから、最初の control-plane（.113）の `install kubelet` の前（§4.2）
- **節目の間の手順は、ユーザーに知らせるだけで進めてよい。** etcd のバックアップ、v2store の確認（§2.9）、IPAddress の書き直し（§3.4）、etcd のリーダーの移動、`install kubelet`、`install kubernetes` の流し直し（§3.2）、一時的な DaemonSet・NetworkPolicy の確認（`netcheck.sh`、`npcheck.sh`）は、この手順書に書いた形なら ✋（知らせてから行う操作）で、1 つずつ承認を取るものではない。
- **§3.4 の IPAddress の書き直しと、§8.12 の Completed / Succeeded の Pod の削除は、段の開始の承認の範囲の ✋ とする。** §8.12 の対象は段 4 の手順書 §0 と同じ条件のものだけで、消す前に対象の名前を知らせる。
- **runbook から外れる操作（ロールバック、`etcd restore`、drain への切り替え、想定外の対処、上のほかの Pod の削除、iSCSI のセッションの logout）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認は、知らせずに行ってよい。**1 台ずつ行う。** 時刻はすべて UTC で記録する（control-plane のホストの時刻は JST）。

## 1. 前提

### 1.1 段 4 が終わっていること

始める前に次を確かめる。

- 段 4 の完了の確認（段 4 の手順書 §6）が `results/stage-4/summary.md` に残っている
- 段 4 の後の 2 つの作業が終わっている: cnidaria の DaemonSet の入れ替え（porkadot 0.33.1、`docs/cni/cnidaria-no-plugin-copy.md`）と、Longhorn の古い ownerReference の書き換えと orphan の削除（`docs/longhorn/results/2026-10-20.md`）
- 8 台すべてが v1.33.13、CONTAINER-RUNTIME が `containerd://2.3.6`、etcd が 3.5.34

2026-10-20 08:2xZ の読み取り（この手順書を書いたとき）では、どれも変わっていない。

- 8 台 Ready、全台 v1.33.13、`containerd://2.3.6`。etcd 3/3 が 3.5.34（リーダーは .113 の `57ec6f12ac7b683e`、raft term 23120）、DB 55 MB。各メンバーの `/version` は `{"etcdserver":"3.5.34","etcdcluster":"3.5.0"}`。Pod は 150 個で、Running / Completed 以外は 0 個
- controller-manager は Deployment の generation 26（リーダー `-fw4lb`）、scheduler は 25（リーダー `-8kt9t`）、CoreDNS は v1.12.4 の 2/2（generation 11）、kube-apiserver の DaemonSet の generation は 27、cnidaria の DaemonSet は generation 3（init container なし、`cnidaria-cni:v0.1.1`、8/8 Ready）
- Longhorn のボリュームは 17（attached healthy 16、detached unknown 1 の `homegallery/cg-data`）。アタッチ先は chirico 10、oeilvert 5、pablo 1
- `tools/storage-versions.sh` は `prefixes: 65, keys: 2200, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は 1.33 の 2 行で、IPAddress 74 と ServiceCIDR 1 が `networking.k8s.io/v1beta1` の `ok`
- 8 台の `tools/node-state.sh`（この PR で `etcdutl` を足したもの。§1.8）: `/opt/bin` は `kubelet-v1.33.13`、`kubectl-v1.33.13`、`crictl-v1.33.0`、`etcdctl-3.5.34`、`etcdutl:none`（8 台とも etcdutl は無い）。CNI の印と 4 つのプラグインは `v1.9.1`。iscsid の PID は段 4 の手順書 §2.7 の表と同じ。Longhorn のセッションは pablo 1、oeilvert 5、chirico 10 で、どれもそのノードの今の instance-manager の IP へのもの。`older-than-iscsid` のエンジンは chirico の 1 つ（段 4 と同じ）。8 台の `/etc/iscsi/initiatorname.iscsi` は、この PR の `assets/kubelet/<ノード>/initiatorname.iscsi` と同じ
- `apiserver_requested_deprecated_apis` は `endpoints`（3 台）、`metallb.io/v1beta1 addresspools`、`componentstatuses`（.111 だけ。段 4 の完了の確認の後に誰かが `kubectl get componentstatuses` を流したものと見ている。`removed_release` は空）
- 同じ PVC を Running の Pod と共有する Succeeded の Pod は `aphrael/tumblr-like` の 3 つだけで、NFS の PV（`aphrael/aphrael-2`）なので §8.12 には当たらない

### 1.2 kubeconfig の運用

段 4 の手順書 §1.2 と同じ（確認は `fraction-auditor`、変更系は `infra-admin` の 1 時間のトークンと `kubectl-admin`）。

**段 5 で `infra-admin` のトークンを使うのは、§3.4 の IPAddress の書き直し、`netcheck.sh`・§1.9 の NetworkPolicy の確認、§8.12 の Pod の削除だけ**（cordon・drain・Longhorn の設定の切り替えは無い）。トークンのファイル名は `/tmp/k8u-stage5-admin-token` にする。

### 1.3 SSH

段 4 の手順書 §1.3 と同じ（worker は `ssh yuanying@<IP>`、control-plane は `ssh ubuntu@<IP>`。サンドボックスの中で通る。control-plane には `unset LC_ALL` してから入る）。2026-10-20 にこの手順書を書いたとき、8 台ともサンドボックスの中から `tools/node-state.sh` を流せた。

### 1.4 porkadot の流し方

porkadot 0.34.1 の checkout（`porkadot-dev/porkadot` の `v0.34.1`、`060a687`）を使い、**このリポジトリのルートを cwd にして** 流す。形は段 4 の手順書 §1.4 と同じ。

```sh
P=/home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot
git -C $P describe --tags          # v0.34.1（lib/porkadot/version.rb も 0.34.1）
cd <このリポジトリの checkout>     # §2.6 の PR をマージした master
BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

以下、この形を `porkadot <サブコマンド>` と書く。

- 0.34.1 は Ruby 4.0.7。clone の `bundle install` は済んでいる（2026-10-20 に、この checkout で §2.6 の render を流した）。始める前に `BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot help` が動くことを確かめる
- 作業ツリーの `assets/` と `porkadot.yaml` に PR の外の変更が無いこと（`git status --short assets porkadot.yaml` が空）。メインの checkout にほかの作業があれば、master の別の worktree を作ってそこで流す
- 段 5 で流す porkadot のコマンドは、`etcd backup`、`install kubernetes --node 192.168.1.111`、`install kubelet --node <ノード>` の 3 つだけ。**`install all`、`--node` なしの `install kubelet` と `install kubernetes`、`render`（特に `render all` と `render certs`）、`setup-node`、`setup-containerd`、`etcd restore`（§7.4 の承認を得たときだけ）は流さない**
- **`install kubernetes` は 0.33.1 以前の porkadot で流さない**（§3.2。1.34 の scheduler がデッドロックする）
- **ノードに入る porkadot のコマンドもサンドボックスの中で流す**（0.34.1 の SSH は 0.33 と同じ）。当日の流す前の確かめ方は段 2 の手順書 §1.4 のスクリプト（`P` を 0.34.1 の checkout にする）。8 台とも hostname を返すこと

### 1.5 etcdctl の使い方

段 2 の手順書 §1.5 と同じ（sudo で流す。`move-leader` は `unset ETCDCTL_ENDPOINTS` してから `--endpoints` を渡す）。以下、この形を `etcdctl ...` と書く。

- **ノードの `/opt/bin/etcdctl` を使う。** その台の `install kubelet` で 3.6.15 に替わる。dev では、3.6 の etcdctl で 3.5 のメンバーも問題なく読めた。3.5 の etcdctl でも、混在中の 3 台の health を見られた（dev の 2 秒ごとの監視）
- 3.6 の etcdctl の `endpoint status -w table` は、STORAGE VERSION・DB SIZE IN USE・QUOTA などの列が増える
- メンバーの版は `/version` でも読む（読み取り。`etcdcluster` が cluster version、3.6 では `storage` も出る）

  ```sh
  ssh ubuntu@<control-plane> 'sudo bash -c "for h in 192.168.1.111 192.168.1.112 192.168.1.113; do echo \$h \$(curl -s --cacert /etc/etcd/pki/ca.crt --cert /etc/etcd/pki/etcd.crt --key /etc/etcd/pki/etcd.key https://\$h:2379/version); done"'
  ```

- 動いている etcd のフラグは `sudo tr '\0' ' ' < /proc/$(pgrep -x etcd)/cmdline` で読む

### 1.6 render に使った secrets と、本番との突き合わせ

secrets の在りかと扱いは段 1 の手順書 §1.6 と同じ（`assets/` の中に sops の binary 形式で暗号化してある。`assets/secrets.tar.asc` を展開しない。平文をディスクに書かない）。
段 5 の render（§2.6）の前に、同じ形で本番と突き合わせ直した（2026-10-20 08:22Z。読み取りだけ。復号をパイプで流してハッシュだけを比べた。`docs/cni/cnidaria-no-plugin-copy.md` §3 と同じスクリプト）。

| 比べたもの | 本番の側 | 結果 |
|---|---|---|
| `assets/certs/kubernetes/ca.crt` | ConfigMap `default/kube-root-ca.crt` | 一致（SHA-256 `AB:5A:49:9E:…`。段 1〜4 と同じ） |
| `assets/certs/kubernetes/apiserver.crt` | VIP と 192.168.1.111〜113 の 6443 が返す証明書 | 4 つとも一致（`4A:E8:7B:B3:…`） |
| `assets/certs/kubernetes/` の 10 ファイル | .111 の kube-apiserver の Pod（`kube-apiserver-6kv5q`）にマウントされた Secret `kube-apiserver` | 10 ファイルとも sha256 が一致 |
| `assets/certs/etcd/{ca.crt,etcd-client.crt,etcd-client.key}` | 同じく Secret `etcd-tls` | 3 ファイルとも一致 |
| `assets/kubelet/192.168.1.11{1,2,3}/addons/etcd/{ca.crt,etcd.crt,etcd.key}`（render の前） | 3 台の `/etc/etcd/pki/` | 9 ファイルとも一致（`etcd.crt` は段 4 の render のもの） |
| CA の鍵と証明書（kubernetes、front-proxy、etcd） | — | 3 組とも公開鍵が一致 |

当日に確かめ直すときの形は段 1 の手順書 §1.6 と同じ。どれかが食い違えば、render の差分も assets も信用せず、止めて調べる。

### 1.7 入れる版を確かめる

作業の当日に確かめ直す（読み取り）。

```sh
curl -fsSL https://dl.k8s.io/release/stable-1.34.txt     # v1.34.12
gh api repos/etcd-io/etcd/releases --jq '.[] | select(.tag_name|test("^v3\\.6\\.")) | .tag_name' | head -1   # v3.6.15
```

2026-10-20 の時点:

- `stable-1.34.txt` は v1.34.12。`stable.txt` は v1.37.1
- etcd の 3.6 の最新パッチは v3.6.15（2026-09-22）。3.7 へは 3.6.11 以上から上げられる（計画 §2）ので、段 8 の前の条件も満たす
- registry.k8s.io の `kube-apiserver`・`kube-controller-manager`・`kube-scheduler`・`kube-proxy` の v1.34.12 と `etcd:3.6.15-0` は、どれも amd64 と arm64 を含む（manifest list を読んだ）
- `dl.k8s.io` の kubelet と kubectl の v1.34.12（amd64、arm64）、cri-tools の `crictl-v1.34.0-linux-{amd64,arm64}.tar.gz`、etcd の `etcd-v3.6.15-linux-{amd64,arm64}.tar.gz` は、どれも 200 を返す。cri-tools の 1.34 系は v1.34.0 だけ
- §2.9 で使う `etcd-v3.5.34-linux-arm64.tar.gz` と `SHA256SUMS` も 200 を返す
- CoreDNS v1.12.4 と CNI plugins v1.9.1 はクラスタとノードに入っているもので、変わらない
- **作業端末の kubectl は v1.33.13**。1.33 にも 1.34 にも ±1 に入る（計画 §6.1 の 4。dev でも v1.33.13 で使えた）

### 1.8 確認に使うスクリプト

段 4 の手順書 §1.8 と同じ（cnidaria の手順書の `verify-nodes.sh`・`netcheck.sh`・`check-apps.sh`、`tools/node-state.sh`、`tools/storage-versions.sh`）。

- **`tools/node-state.sh` はこの PR で直した**。`bin` の行に `/opt/bin/etcdutl` の向き先を足した（無いときは `etcdutl:none`）。0.34.1 の `install kubelet` が etcdutl を置くので、前と後でこれが `etcdutl:none` → `etcdutl-3.6.15` に変わる。ほかの行は前と同じ（2026-10-20 に 8 台で流した）
- `tools/storage-versions.sh` は段 4 のまま。1.34 では `overrides.tsv` が空になり、1.33 の apiserver が v1beta1 で保存した IPAddress が `OLD` に出る（§2.5。dev で確かめた）

### 1.9 NetworkPolicy の確認（一時的な名前空間） ✋

段 4 の手順書 §1.9 と同じ（`tools/npcheck.sh` と `tools/npcheck.yaml`。`nft` → `up` → `nft` → `run` → `down` → `nft`）。合格は、`up` の後の `nft` が 8 台とも 1 以上、`run` が `OK 56, not OK 0`、`down` の後の `nft` が 8 台とも 0、名前空間 `k8u-npcheck` が NotFound。段 4 の本番と cnidaria の入れ替えでは、`up` の後の `nft` は 8 台とも 9 だった。

流すのは、最初の worker の後（§5.5）と、段 5 の完了の確認（§6）。

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 順序 | `install kubernetes --node 192.168.1.111` → rollout の完了 → IPAddress の書き直し → ✋✋ → control-plane の `install kubelet --node` を 1 台ずつ（.113 → .112 → .111）→ worker を 1 台ずつ（§5.1） | 計画 §6.2、dev の記録 |
| 2 | etcd のリーダー | `install kubelet` の前に、対象がリーダーなら `move-leader` で別のメンバーへ移す（3.5 から 3.6 のメンバーへも移せる。dev の .111 の前） | 計画 §6.2、dev の記録 |
| 3 | drain | **どのノードも drain しない**（§2.7）。**ただし、どの台の後でも、Pod のコンテナの再起動（restartCount の増加、UID の変化。control-plane の etcd の mirror Pod を除く）が 1 つでも出たら止める。** 特に最初の worker（duchamp）と、Longhorn のボリュームがアタッチされた最初の worker（pablo）の後に見る。止めた後、残りの Longhorn のノードを drain に切り替えるかはユーザーが決める（§8.10） | dev の記録、段 3・段 4 の本番、2026-10-19 のユーザーの方針 |
| 4 | drain の基準 | 「短時間の途切れ」より「Longhorn のボリュームの安全（データ、degraded のまま戻らないこと）」を重く見る。短時間の障害は許容する | 2026-10-19 のユーザーの方針 |
| 5 | iSCSI | 各台の `install kubelet` の前と後に `tools/node-state.sh` で iscsid の PID と iSCSI のセッションを見る。iscsid の PID が変わったら止める。古いセッションがあれば止める（§2.7、§5.3） | 計画 §4.4、dev の記録 |
| 6 | ノードの再起動 | しない | 計画 §9.3 |
| 7 | コンテナの再起動 | 1.34 の kubelet では起きないことを前提にする（§8.4）。control-plane の etcd の static Pod だけは作り直される（3.6.15 で起き直す） | dev の記録 |
| 8 | Longhorn の設定 | 変えない | 段 1 の手順書 §2.6 |
| 9 | etcd の更新 | control-plane の `install kubelet` で 1 台ずつ 3.6.15 にする。**3 台を続けて流し、混在の時間を短くする**（dev では .113 から .111 まで約 6 分）。各台の後に 3/3 healthy と版を見る（§4.4） | dev の記録、etcd の公式の文書（Upgrade etcd from v3.5 to v3.6） |
| 10 | v2store | 上げる前に、3.5.34 の etcdutl で各メンバーの `check v2store` を流す。`No custom content found in both v2store and WAL records.` でなければ止める（§2.9） | etcd の公式の文書、dev の記録 |
| 11 | etcd のバックアップ | 3 回取る: 段の前（`install kubernetes` の前。§2.4）、control-plane の `install kubelet` の前（§4.2）、全台 3.6 の後（3.6 の etcdctl で。§4.5） | 計画 §6.1 の 5、dev の記録 |
| 12 | storage version | `install kubernetes` の前に `OLD: 0` を確かめる。後で、1.33 の apiserver が v1beta1 で保存した IPAddress を v1 に書き直す（§3.4。段の開始の承認の範囲の ✋）。ServiceCIDR は、dev では 1.34 の apiserver が自分で v1 に書き直したが、本番では書き直さなかったので一緒に書き直した | dev の記録、計画 §6.4、本番の段 5 |
| 13 | Completed / Succeeded の Pod | Running の Pod と同じ Longhorn の PVC を使うものは、`install kubelet` の前に消す（§8.12。段の開始の承認の範囲の ✋。§0） | 段 3 の本番 |
| 14 | v1 Endpoints の warning | 段の更新を止める理由にしない。出どころを記録する（段 4 の手順書 §8.15） | 段 4 の本番 |
| 15 | leader election を使う controller の 1 回の再起動と、gated の LoadBalancer の 1 回の途切れ | 許容する。記録して、Running に戻ったことを確かめる（§8.8） | 段 C、ユーザーの判断 |
| 16 | 停止時間 | いつでもよい。braque は念のためバックアップの CronJob の時間帯を避ける（§5.4）。早朝（JST 05:30・06:00）のバックアップの後は §8.12 の Pod が残ることがある | 計画 §9.6 |
| 17 | 段 5 の後 | 1 日ほど様子を見てから、Longhorn の更新（計画 §4.3）に進む（§10） | 計画 §9.6 |

### 2.2 クラスタ全体のベースライン

作業の当日、`install kubernetes` の前に次を取り、`results/stage-5/baseline.md` に残す（すべて読み取り）。段 4 の手順書 §2.2 と同じもので、次を読み替える・足す。

- 1: 全台 v1.33.13
- 2: 8 台の `tools/node-state.sh` の出力（ファイルに残す）。`/opt/bin` の向き先が `kubelet-v1.33.13`、`kubectl-v1.33.13`、`crictl-v1.33.0`、`etcdctl-3.5.34`、`etcdutl:none`。CNI の印と 4 つのプラグインが `v1.9.1`
- 4: **etcd**（足すもの）: `etcdctl endpoint status --cluster -w table`（版、DB SIZE、リーダー、raft term・index）と、`-w json` の `header.revision`（§7.4 の restore の revision の目安）、3 台の `/version`、3 台の動いている etcd のフラグ（`--experimental-initial-corrupt-check=true`・`--experimental-watch-progress-notify-interval=5s` があり、`--enable-v2` が無い）、3 台の etcd の Pod のログの warning の種類（3.6 の後に増えたものを見分けるため。`check file permission`、`Running http and grpc server on single port`、`simple token is not cryptographically signed` は前から出ている見込み）
- 5: **全 Pod の名前・UID・restartCount を控える**（§6 で「増えていない」ことを見る元になる）
- 14: Longhorn の設定（2026-10-20 は段 4 と同じ。`5`、`disabled`、`block-if-contains-last-replica`、`best-effort`、`6000`、v1.11.2）
- 18: Longhorn のボリュームの state・robustness・アタッチ先、replica の置き場所（§2.7 の表を当日に読み直す）
- 20: **storage version**: `tools/storage-versions.sh` の結果。`OLD: 0`、`CRDs with more than one stored version: 0`。`overrides.tsv` が 1.33 の 2 行で、IPAddress と ServiceCIDR が `networking.k8s.io/v1beta1` の `ok`。IPAddress の数を控える（§3.4 の書き直しの数の元）
- 21: Prometheus の `apiserver_requested_deprecated_apis`（読み方は段 4 の手順書 §2.2 の 21）。2026-10-20 08:2xZ は §1.1 のとおり
- 22: Longhorn のボリュームを使う Pod と、同じ PVC を使う Completed / Succeeded の Pod（段 4 の手順書 §2.2 の 22 と同じ）
- 23: CoreDNS の答え（段 4 の手順書 §3.3 の 13 の問い合わせ）。段 4 の完了の確認と同じ答えであること（v1.12.4 のまま）
- 24: Service の数と ClusterIP の数（段 4 の手順書 §2.2 の 24）。2026-10-20 08:2xZ は Service 79 個、ClusterIP を持つもの 71 個（dual-stack 3 個）、ClusterIP の数 74、IPAddress 74
- 25（新）: **Prometheus の etcd と apiserver のスクレイプ**: `count by (job) (up)` の `kube-etcd` が 3、`apiserver` が 3、`count(etcd_server_has_leader)` が 3（§8.15 の metrics の確認の元）

### 2.3 VIP と LoadBalancer、etcd の health を見る

段 4 の手順書 §2.3 と同じ監視を、`install kubernetes` の前から最後の worker の確認まで、作業端末で流しておく（読み取り）。ログは `./stage-5-probe.log` に足していく（`tee -a`）。段 4 の本番では FAIL は 0 回だった。

**段 5 では、control-plane の `install kubelet`（§4）の間、etcd の health も 2 秒ごとに見る**（dev の記録の「本番の段 5 の runbook に効くこと」）。.111 と .112 の 2 台から、3 つのエンドポイントを明示して問い合わせる（自分の etcd が起き直している間も、ほかのメンバーを見られるように）。

```sh
for h in 192.168.1.111 192.168.1.112; do
  ssh -n ubuntu@$h 'while :; do sudo bash -c ". /etc/etcd/etcd.env && unset ETCDCTL_ENDPOINTS && /opt/bin/etcdctl --endpoints=https://192.168.1.111:2379,https://192.168.1.112:2379,https://192.168.1.113:2379 --command-timeout=2s endpoint health" 2>&1 | sed "s/^/$(date -u +%T) /"; sleep 2; done' >> ./stage-5-etcd-$h.log &
done
```

- 読み取りだけ。`unset LC_ALL` してから流す。§4 の前（§4.2 の ✋✋ の後）に始め、§4.5 の後に止める（`kill %1 %2`。ノードの側の while も ssh の切断で止まる）
- 合格の基準にはしない。unhealthy が出た時刻を、`install kubelet` の etcd の起き直し（§4.4 の 5）と突き合わせて記録する。起き直す台が数秒 unhealthy になるのは想定どおり（dev では 2〜5 秒）。**ほかの 2 台も unhealthy になり、VIP が止まるとき**は §8.13 を見る
- その台の etcdctl が 3.6.15 に替わっても、そのまま流れる

### 2.4 etcd のバックアップ（段の前） ✋

`install kubernetes` の前に、porkadot 0.34.1 で取る（計画 §6.1 の 5）。段 4 の手順書 §2.4 と同じ形。

```sh
porkadot etcd backup
ls -l ./backup/
```

- この時点の etcdctl は 3.5.34（0.34.1 の `etcd backup` は、ノードの `/opt/bin/etcdctl` の `snapshot save` を流す）
- 手元のファイルは `./backup/etcd-<日時>.db`、モード 0600。`./backup/` は `.gitignore` で除外してある。スナップショットには Secret が平文で入っているので、`git add -f` などで追加しない
- **worktree で流したときは、`./backup/` は worktree の中にできる。** worktree を片付ける前に、coordinator がメインの checkout の `backup/` へ移す（段 1〜4 と同じ）
- 時刻、ファイル名、サイズ、sha256 を記録する。段 4 と cnidaria の入れ替えのバックアップは 55,107,616 バイトだった。桁が違えば止める
- **このバックアップは「段の前」のもの**（1.33 の control-plane、etcd 3.5）で、§7.4 の restore の第一の候補になる。段 5 が終わり、1 日ほど様子を見るまで消さない

### 2.5 storage version（書き直しは `install kubernetes` の後）

`install kubernetes` の前に書き直すものは無い（段 3 で済み、段 4 の完了の確認でも `OLD: 0`）。

1. `install kubernetes` の前（§2.2 の 20）: `tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` が 1.33 の 2 行。**違えば止める**
2. `install kubernetes` の後（§3.3 の 16）: 1.34 の apiserver は `ipaddresses`・`servicecidrs` の v1beta1 の override を外している（`pkg/kubeapiserver/default_storage_factory_builder.go`、v1.34.12 で確かめた。1.34 の override は `leasecandidates`、`mutatingadmissionpolicies`・`…bindings`、`clustertrustbundles`、`podcertificaterequests`、`volumeattributesclasses`、`storagemigrations`、`devicetaintrules` で、どれも本番にオブジェクトが無い）。スクリプトの `overrides.tsv` は空になり、1.33 の apiserver が v1beta1 で保存した **IPAddress が `OLD` に出る**（数は §2.2 の 24 の ClusterIP の数。2026-10-20 は 74）。**ServiceCIDR は、dev では 1.34 の apiserver（servicecidr の controller が status を書く）が入るとすぐ v1 で書き直したが**（dev の見つけたことの 3）、**本番では書き直さず `OLD` のまま残った**。そのときは §3.4 で IPAddress と一緒に書き直す（本番の段 5 はそうした。`results/stage-5/control-plane.md`）
3. §3.4 で IPAddress を v1 に書き直し、`OLD: 0` に戻す。**control-plane の `install kubelet`（✋✋）の前に済ませる**（書き直しは 1.34 の apiserver が要るので、1.33 に戻すときに読めなくなることは無い: 1.33 の apiserver は v1 を知っている。§7.2）

1.34 の apiserver は、FlowSchema の `endpoint-controller`・`workload-leader-election` を消す。v1.34.12 の suggested の FlowSchema（`staging/src/k8s.io/apiserver/pkg/apis/flowcontrol/bootstrap/default.go` の `SuggestedFlowSchemas`）からこの 2 つが外れ、apiserver は `apf.kubernetes.io/autoupdate-spec: "true"` の付いた suggested のオブジェクトで自分の一覧に無いものを消すため。FlowSchema は 13 個から 11 個になる（dev も本番も同じ）。

### 2.6 render の差分（この手順書と同じ PR）

計画 §6.1 の 6〜7。2026-10-20 08:22Z に、porkadot 0.34.1（`060a687`）で、このリポジトリのルートを cwd にして `render kubelet` / `render etcd` / `render bootstrap` / `render kubernetes` を流した（`render all` と `render certs` は使っていない）。secrets は §1.6 のとおり本番と一致していることを確かめてから使った。`porkadot.yaml` は変えていない。

前の render は master の `b2edd42` にある（段 4 の porkadot 0.33.0 の render に、cnidaria の入れ替えの 0.33.1 の `render kubernetes` を足したもの）。差分は次の 28 ファイルで、**これ以外の差分は無い**（新しくできたファイル、消えたファイルも無い）。

| ファイル | 変わったもの | 由来 |
|---|---|---|
| `kubernetes/manifests/kube-apiserver.yaml`・`kube-controller-manager.yaml`・`kube-scheduler.yaml`・`kube-proxy.yaml` | イメージ v1.33.13 → v1.34.12、`app.kubernetes.io/version` のラベル | K8s の版（porkadot#50） |
| `kubernetes/manifests/kube-apiserver.secrets.yaml`・`kube-controller-manager.secrets.yaml`（sops） | Secret の `app.kubernetes.io/version` のラベルだけ。data は同じ（復号して、キーごとの sha256 を比べた。13 キーと 3 キー） | 同上 |
| `kubernetes/manifests/porkadot.yaml` | Service `porkadot-kubernetes-latest` の selector の `app.kubernetes.io/version` | 同上 |
| `kubernetes/install.sh` | kube-apiserver（`app.kubernetes.io/component=kube-apiserver` の DaemonSet と Service 2 つ）を先に apply し、`rollout status --watch=false` を 5 秒ごとに見て完了を待ってから（既定 600 秒）、全体を apply する（36 行の追加） | porkadot#50（`05d5060`） |
| `bootstrap/manifests/*.bootstrap.yaml`（4 つ） | イメージ v1.33.13 → v1.34.12、版のラベル。**`kube-proxy.bootstrap.yaml` から `serviceAccountName: kube-proxy` を削除** | porkadot#50（段 5 では bootstrap は使わない。下） |
| `kubelet-default/install-deps.sh` | `RELEASE`（kubelet・kubectl）v1.33.13 → v1.34.12、`ETCD_VER` 3.5.34 → 3.6.15、`CRICTL_VER` v1.33.0 → v1.34.0、`fetch_etcdctl` → `fetch_etcd` と **`install_bin etcdutl`** の追加。CNI plugins のコメント 3 行（porkadot 0.33.1 のもの。cnidaria の入れ替えでは `render kubelet` を流さなかったので、ここで入る） | porkadot#50、porkadot#48 |
| `kubelet/192.168.1.11{1,2,3}/addons/etcd/etcd-server.yaml` | イメージ `etcd:3.5.34-0` → `3.6.15-0`、`--experimental-initial-corrupt-check=true` → `--feature-gates=InitialCorruptCheck=true`、`--experimental-watch-progress-notify-interval=5s` → `--watch-progress-notify-interval=5s`（フラグの並びの最後へ） | porkadot#50 |
| `kubelet/<8 台>/bootstrap.crt`、`bootstrap/kubelet/bootstrap.crt` | 作り直し（同じ鍵、同じ subject・issuer・SAN・用途、assets の CA で検証が通る。期限が 2027-10-20 08:22Z に延びる） | render のたびに作り直される（§8.2） |
| `kubelet/192.168.1.11{1,2,3}/addons/etcd/etcd.crt`（sops） | 同上（同じ鍵、同じ etcd の CA、同じ SAN） | 同上 |

- `app.kubernetes.io/version` が変わったのは平文のマニフェストで 23 行（dev の記録と同じ数）
- 変わらないもの: `kubelet-default/install-pkgs.sh`・`setup-containerd.sh`、`kubelet/<ノード>/config.yaml`・`kubelet.service`・`bootstrap-kubelet.conf`・`metadata.json`・**`initiatorname.iscsi`**、etcd の `install.sh`・`etcd.env`・`etcd.key`、`install-deps.sh` の `CNI_VERSION`（v1.9.1）、CoreDNS（v1.12.4）・cnidaria（v0.1.1、init container なし）・MetalLB・kubelet-serving-cert-approver のマニフェスト
- Deployment と DaemonSet の `spec.selector` には `app.kubernetes.io/version` が入っていない（段 1〜4 と同じ）
- **bootstrap の kube-proxy の `serviceAccountName`**: 1.34 の kubelet は、API のオブジェクト（ServiceAccount など）を参照する static Pod を受け付けない（CHANGELOG-1.34 の Urgent Upgrade Notes、kubernetes#131837）。bootstrap はクラスタを作るときにしか使わないので、段 5 の更新には効かない。本番の static Pod は control-plane の etcd だけで、API のオブジェクトを参照しない
- 作り直した証明書は、作業の当日に render し直すとまた変わる。**当日は render しない**。この PR の `assets/` で流す

### 2.7 drain しない理由と、Longhorn・iSCSI の前提

**drain しない理由**（§2.1 の 3）は段 4 の手順書 §2.7 と同じで、段 5 の根拠は次のとおり。

- 1.34 の kubelet でも、dev の 7 台でコンテナが 1 つも再起動しなかった（etcd の static Pod を除く。dev の記録の「Longhorn と iSCSI」）。drain しないでアタッチしたままのボリュームは、faulted・remount・I/O エラーにならなかった
- 0.34.1 の `install-pkgs.sh` は 0.33 と同じで、`initiatorname.iscsi` が同じなら iscsid を再起動しない（dev の 7 台で PID が同じ）。本番の 8 台の `/etc/iscsi/initiatorname.iscsi` は、この PR の `assets/kubelet/<ノード>/initiatorname.iscsi` と同じ（§1.1。render はこのファイルを変えていない）
- 段 3・段 4 の本番でも、drain しないで 8 台を流し、コンテナの再起動・iscsid の再起動・古いセッションは 1 つも無かった（`results/stage-3/summary.md`、`results/stage-4/summary.md`）

**各ノードの iSCSI と Longhorn**（2026-10-20 08:2xZ の `tools/node-state.sh`。当日に読み直す）は段 4 の手順書 §2.7 の表と同じ（iscsid の MainPID と起動の時刻、Longhorn のセッションの数と portal、`older-than-iscsid` のエンジンが chirico の 1 つ、`initiatorname.iscsi` が assets と同じ）。

- 古いセッションは無い（pablo の 1 は 10.244.4.131、oeilvert の 5 は 10.244.7.116、chirico の 10 は 10.244.8.216 で、どれもそのノードの今の instance-manager）
- chirico の `older-than-iscsid` の 1 つは段 3 の手順書 §2.7 の注のもの。当日も同じ形なら、記録して進める。新しく増えていたら止める
- Longhorn のボリュームのアタッチ先: chirico 10（`homegallery/tumblr-data`・`ero-data`、`fs/data`、`fs/h2`、`natsumi/natsumi-myao`、`prometheus-…-0`、`fraction-agents` の 4 つ）、oeilvert 5（`natsumi/natsumi`・`natsumi-aki`、`prometheus-…-1`、`fraction-agents` の 2 つ）、pablo 1（`fs/sites`）
- replica 1 のボリューム: `prometheus-…-0`（replica もアタッチも chirico）、`prometheus-…-1`（replica もアタッチも oeilvert）。drain しないので、止めない

### 2.8 MetalLB の告知ノードを読む

段 4 の手順書 §2.8 と同じ読み方。段 4 の完了の確認（`results/stage-4/summary.md` §2）では、VIP pablo、gated-v4 chirico、gated-v6 oeilvert、`::131`・`::134` .112、`::132` .111、`::133` duchamp だった。当日に読み直す。

### 2.9 v2store の確認 ✋

etcd 3.6 は v2store の独自のデータ（membership 以外のもの）を持ったまま上げられない（`--v2-deprecation` の既定が `write-only` になり、起動を止める）。etcd の公式の文書（Upgrade etcd from v3.5 to v3.6）は、「`--enable-v2` または `ETCD_ENABLE_V2="true"` をどのメンバーかで使っている（または使ったことがある）なら、v3.6 に上げる前に v2store を片付けなければならない」とし、3.5.32 以降の etcdutl の `check v2store`（v2 の snapshot に加えて WAL も見る）を各メンバーで流すことを求めている。**3.6.15 の etcdutl には `check` が無い**（dev の見つけたことの 6）。

**本番の前提**（2026-10-20 08:1xZ の読み取り）:

- 3 台の etcd の static Pod のマニフェストと、動いている etcd のフラグ（`/proc/<pid>/cmdline`）に `--enable-v2` が無く、プロセスの環境に `ETCD_*` が無い。`porkadot.yaml` に `etcd.extra_env` は無い（段 1 で `ETCD_UNSUPPORTED_ARCH` を消した）
- .111 の最新の v2 snapshot（`/var/lib/etcd/member/snap/*.snap`）のパスは `/0/members/…`（3 メンバー）、`/0/version`、空の `/1` だけで、独自のキー（`/1/…`）は無い（`strings` でパスだけを数えた）
- ただし、このクラスタの etcd のデータは 2020 年から引き継いでいる（`/var/lib/etcd/member.tar.gz` が 2020-04-30）。当時の etcd の版と `--enable-v2` の既定（3.3 までは有効）を確かめる手段が無く、WAL の中は見ていない。**「使ったことがない」とは言い切れないので、文書の求める `check v2store` を流す**

**流し方**（各メンバーで。ノードの `/tmp` に一時的なファイルを置いて消すので ✋）:

1. 作業端末で 3.5.34 の arm64 の etcdutl を取り出し、`SHA256SUMS` と突き合わせる（展開したものは専用の空のディレクトリに置く）。

   ```sh
   W=$(mktemp -d /tmp/k8u-etcdutl-XXXX); cd $W
   curl -fsSLO https://github.com/etcd-io/etcd/releases/download/v3.5.34/etcd-v3.5.34-linux-arm64.tar.gz
   curl -fsSL https://github.com/etcd-io/etcd/releases/download/v3.5.34/SHA256SUMS | grep ' etcd-v3.5.34-linux-arm64.tar.gz$' | sha256sum -c -
   tar xzf etcd-v3.5.34-linux-arm64.tar.gz etcd-v3.5.34-linux-arm64/etcdutl
   cd -
   ```

2. ✋ 3 台それぞれで、データディレクトリの `member` を `/tmp` に写し、写しに対して流して、消す（etcd が開いている本物のディレクトリには触らない。写しは root の 0700 のまま）。

   ```sh
   for h in 192.168.1.111 192.168.1.112 192.168.1.113; do
     scp $W/etcd-v3.5.34-linux-arm64/etcdutl ubuntu@$h:/tmp/k8u-etcdutl-3.5.34
     ssh ubuntu@$h 'sudo bash -c "set -e; d=\$(mktemp -d /tmp/k8u-v2check-XXXX); cp -a /var/lib/etcd/member \$d/member; /tmp/k8u-etcdutl-3.5.34 version | head -1; /tmp/k8u-etcdutl-3.5.34 check v2store --data-dir \$d; rm -rf \$d /tmp/k8u-etcdutl-3.5.34"'
   done
   rm -rf $W
   ```

   - `member` は 1 台 420〜490 MB（2026-10-20）。ノードの `/` は 105 GB 空いている。写すのに数秒かかる（読むだけなので etcd は止まらない）
   - 2026-10-20 にはまだ流していない（この手順書では読み取りだけにした）。当日、§3.1 の承認の前に流し、結果を承認のときに示す

**合格**: 3 台とも `No custom content found in both v2store and WAL records.`（dev の .113 の写しと同じ出力）。

- `detected custom content in v2store` / `detected custom v2 content in WAL records` / 両方が出たら、**止めて報告する**。片付け方（v2 のデータの移行・手での削除・`--v2-deprecation=write-only-skip-check`、WAL のものは次の v2 snapshot で消える）は文書にあるが、どれも porkadot の外の操作になるので、その時点でユーザーと決める
- 写しの WAL の末尾が書きかけで読めない、などのエラーが出たら、もう一度写して流す。2 回続けば止めて報告する

## 3. control-plane のマニフェストを上げる（`install kubernetes`）

### 3.1 事前確認

✋✋ **段 5 の開始の承認を取る。** §2.6 の表と PR の差分、§2.7 の drain しない理由と止める条件、§2.2 のベースライン（22 の Completed の Pod で消すもの、§0）、§2.4 のバックアップ、§2.8 の告知ノード、§2.9 の v2store の確認の結果、§3.4 の IPAddress の書き直し、§7 のロールバックの形（etcd が全台 3.6 になった後は restore だけになること）を示す。承認を得て PR をマージし、マージした master で §3.2 に入る。

- §2.2 のベースライン、§2.4 のバックアップ、§2.9 の v2store の確認が済んでいる。§2.3 の監視（VIP と LoadBalancer）が動いている
- `tools/storage-versions.sh` が `OLD: 0`（§2.5 の 1）
- 全台 Ready、etcd 3/3 healthy、VIP の `/readyz` が `ok`
- checkout が §2.6 の PR をマージした master で、`git status --short assets porkadot.yaml` が空
- §1.4 の SSH の確かめで 8 台とも通る。`git -C $P describe --tags` が `v0.34.1`

### 3.2 流す ✋

```sh
porkadot install kubernetes --node 192.168.1.111
```

- **`--node` を必ず付ける。** 付けないと bootstrap ノード（pablo）で `kubectl apply` を流し、`127.0.0.1:6443` に届かず rc 1 になる
- **0.34 の `install kubernetes` は 2 段で流れる**（`assets/kubernetes/install.sh`）:
  1. CRD を apply し、`app.kubernetes.io/component=kube-apiserver` のもの（DaemonSet `kube-apiserver`、Service `porkadot-kubernetes`・`porkadot-kubernetes-latest` など）だけを apply する
  2. DaemonSet `kube-apiserver` の rollout の完了を 5 秒ごとに `rollout status --watch=false` で見て待つ（`--apiserver-timeout`、既定 600 秒）。完了するとログに `daemon set "kube-apiserver" successfully rolled out` が出る
  3. 全体を apply する。KCM・scheduler・kube-proxy が v1.34.12 で rollout する。CoreDNS・kubelet-serving-cert-approver・cnidaria・MetalLB はマニフェストが変わらないので動かない
- dev では、apiserver の DaemonSet が入ってから 3 台の新しい apiserver の Ready がそろうまで約 2 分（06:22:25〜06:24:29）、その 4〜6 秒後に KCM・scheduler・kube-proxy が入り、全部の rollout の完了まで約 3 分だった。VIP は apiserver の入れ替えの間に 2 サンプル 000 になった
- 時刻と rc を記録する。ログの `successfully rolled out` の時刻と、その後の `configured` の行を記録する
- **rc 1 で、`The kube-apiserver rollout did not finish in 600s` が出たとき**: KCM・scheduler・kube-proxy には何も apply されていない（apiserver だけが新しいか、rollout の途中）。`kubectl --context fraction -n kube-system get pods -l app.kubernetes.io/component=kube-apiserver -o wide` で Pending や CrashLoopBackOff の Pod を見て、**止めて報告する**。Pod が Ready になり rollout が終わったことを確かめてから同じコマンドを流し直すのは ✋ でよい（1 回まで）。Pending のまま動かない（scheduler が割り当てない）なら、§8.3 のデッドロックの形でないかを見る
- **rc 1 で、出力の最後が `dial tcp 127.0.0.1:6443: connect: connection refused` なら**、段 4 の手順書 §3.2 と同じ扱い（`rollout status` で全部の rollout の完了を待ってから、同じコマンドをもう一度流してよい。✋）。0.34 では apiserver の rollout を待ってから全体を apply するので、起きにくくなる見込み（dev では 1 回目で rc 0。§8.3）。流し直した時刻と rc、DaemonSet `kube-apiserver` の generation が流し直しの前と後で同じことを記録する
- rc 1 でほかのエラーなら止める。流し直しても rc 1 なら止める

**0.33.1 以前の porkadot で流してはいけない理由**（dev の見つけたことの 1）: 0.33 までの `install kubernetes` は apiserver と KCM・scheduler を同時に apply する。1.34 の kube-scheduler は `DynamicResources` の plugin のために `resource.k8s.io/v1`（ResourceSlice・DeviceClass・ResourceClaim。1.34 で GA）の informer の同期を待つが、1.33 の apiserver はこれを返さない。dev では、scheduler の接続が 1.33 の apiserver に張り付いて leader election に進まず、apiserver の DaemonSet（maxUnavailable 1、maxSurge 0）は .112 の古い Pod を消したところで、新しい Pod が Pending のまま止まった（DaemonSet の Pod も default scheduler が割り当てる）。その間、クラスタ全体で新しい Pod がスケジュールされない。0.34 の `install.sh` は apiserver を先に入れて rollout を待つので、新しい scheduler が入るときには 3 台とも 1.34 の apiserver になっている。

### 3.3 rollout の完了を確かめる

段 4 の手順書 §3.3 と同じ（版を v1.34.12 に読み替える）。次を読み替え、19 を足す。

```sh
kubectl --context fraction -n kube-system rollout status daemonset/kube-apiserver --timeout=10m
kubectl --context fraction -n kube-system rollout status deployment/kube-controller-manager --timeout=10m
kubectl --context fraction -n kube-system rollout status deployment/kube-scheduler --timeout=10m
kubectl --context fraction -n kube-system rollout status daemonset/kube-proxy --timeout=10m
kubectl --context fraction version
```

| # | 確認 | 合格基準 |
|---|---|---|
| 1〜12 | 段 1 の手順書 §3.3 の 1〜12 | 同じ。Server が v1.34.12、apiserver・KCM・scheduler・kube-proxy が v1.34.12。Node は 8 台 Ready で kubelet は v1.33.13 のまま（apiserver 1.34 と kubelet 1.33 は skew policy の範囲）。DaemonSet `kube-apiserver` の generation が 1 つ増える（2026-10-20 は 27）。**KCM と scheduler のログに `Failed to watch` が続いていない**（入れ替わりの直後の数行は想定内。dev は rollout の完了の後 0） |
| 13 | CoreDNS | **動かない**。Deployment `coredns` の generation が変わらない（2026-10-20 は 11）、2/2、`coredns:v1.12.4`。名前の答えが §2.2 の 23 と同じ |
| 14 | approver | `kubelet-serving-cert-approver` が `0.12.1` のまま 1/1。generation が変わらない |
| 15 | CSR | 新しい CSR が無い（段 4 の手順書 §3.3 の 15） |
| 16 | storage version | `tools/storage-versions.sh` で、`overrides.tsv` が空、`OLD` が **`/registry/ipaddresses/` の `networking.k8s.io/v1beta1` だけ**（数は 17 の IPAddress の数）。`/registry/servicecidrs/` は `networking.k8s.io/v1` の `ok`（1.34 の apiserver が書き直したもの）。ほかの `OLD` と CRD の `MULTI` が無い。ServiceCIDR が v1beta1 の `OLD` のまま出ていれば、§3.4 で一緒に書き直す |
| 17 | ServiceCIDR と IPAddress | `servicecidrs` に `kubernetes` が 1 つで Ready、CIDRS が `10.254.0.0/24,fd20:afc2:7c09::/108`。IPAddress の数が §2.2 の 24 の ClusterIP の数（2026-10-20 は 74）。1.34 の apiserver への入れ替えで `ClusterIPNotAllocated` の event は出ない見込み（1.33 で移行が済んでいる）。出たら数と時刻を記録する |
| 18 | v1 Endpoints の warning | 段 4 の手順書 §3.3 の 18 と同じ（記録だけ。`removed_release` が `1.34` 以前のものが出ていないこと） |
| 19 | FlowSchema | `kubectl --context fraction get flowschemas -o custom-columns=N:.metadata.name,GEN:.metadata.generation` を §2.2 と比べる。`endpoint-controller`・`workload-leader-election` が消え、13 個から 11 個になる（1.34 の apiserver の既定の変更。§2.5）。残りの 11 個の generation が変わっていれば記録する |

- `install kubernetes` の出力の `configured` に、マニフェストの変わらない `poddisruptionbudget.policy/kube-controller-manager`・`kube-scheduler`、`validatingwebhookconfiguration…/metallb-webhook-configuration` が出るのは前から（`docs/cni/cnidaria-no-plugin-copy.md` §2）。generation が変わらなければ想定内
- 入れ替わりのとき、古い 1.33 の KCM の Pod が 1 つ `Error` で終わることがある（dev。すぐに消える）
- apiserver の rollout の途中に、controller-manager の `FailedToUpdateEndpoint` などが 1 回ずつ出ることがある（段 4 の手順書 §3.3 の注）。続かなければ想定内
- ここで問題があれば、kubelet にも etcd にもまだ触っていないので、§7.2 で control-plane だけを戻せる

### 3.4 IPAddress の書き直し ✋

1.33 の apiserver が `networking.k8s.io/v1beta1` で保存した IPAddress を、中身を変えずに読んで書き戻し、1.34 の storage の版（v1）で保存し直させる。形は段 3 の手順書 §2.5 と同じ。**段の開始の承認の範囲の ✋**で、§4.2 の ✋✋ の前に済ませる。

1. §3.3 の 16 の結果を使う（`SV` はそのディレクトリ）。`old.tsv` が `/registry/ipaddresses/` だけ（と、出ていれば `/registry/servicecidrs/` の 1 つ）であること。ほかのものが出ていれば止めて調べる
2. ✋ `infra-admin` のトークンを発行する（§1.2）。
3. ✋ 書き直す。

   ```sh
   kubectl --context fraction get ipaddresses -o custom-columns=N:.metadata.name,GEN:.metadata.generation,RV:.metadata.resourceVersion,PARENT:'.spec.parentRef.namespace',PNAME:'.spec.parentRef.name' --no-headers | sort > $SV/ip-before.txt
   kubectl-admin get ipaddresses -o json | kubectl-admin replace --dry-run=server -f -   # IPAddress の数だけ replaced (server dry run)
   kubectl-admin get ipaddresses -o json | kubectl-admin replace -f -
   ```

   - IPAddress の数だけ `replaced` が出る。`the object has been modified`（その間に Service が作られた・消された）が出たものは、その名前だけ同じ形で流し直す。`NotFound` は Service が消えたもので、流し直さない
   - IPAddress は apiserver（ClusterIP の割り当て）が作って消すもので、ほかに書くものは無い。中身を変えない replace は、名前・generation・`parentRef` を変えない（dev で 16 個とも確かめた）
   - ServiceCIDR が `OLD` に出ていれば、同じ形で `servicecidrs` も書き直す（1 つ）
4. 書き直した後を確かめる（読み取り）。

   ```sh
   docs/k8s-upgrade/tools/storage-versions.sh $SV-after
   # ... OLD: 0, CRDs with more than one stored version: 0
   kubectl --context fraction get ipaddresses -o custom-columns=N:.metadata.name,GEN:.metadata.generation,RV:.metadata.resourceVersion,PARENT:'.spec.parentRef.namespace',PNAME:'.spec.parentRef.name' --no-headers | sort > $SV/ip-after.txt
   diff <(awk '{print $1,$2,$4,$5}' $SV/ip-before.txt) <(awk '{print $1,$2,$4,$5}' $SV/ip-after.txt)   # 何も出ない
   ```

   - `OLD: 0` になったこと。IPAddress の名前・generation・`parentRef` が変わっていないこと（resourceVersion だけが変わる）
   - Service の ClusterIP の割り当てが動いていること: `kubectl --context fraction get events -A --field-selector reason=ClusterIPNotAllocated` に新しいものが無い。dev では書き直しの後に一時的な Service の作成と削除で、新しい IPAddress が v1 で保存された
   - VIP の `/readyz` が `ok`。§2.3 の監視に失敗が出ていないこと
5. トークンを破棄する（`unset ADMIN_TOKEN`、ファイルの削除）。
6. 時刻、`OLD` の数の前と後、衝突で流し直したものを `results/stage-5/control-plane.md` に記録する（値は書かない。prefix・キー・版だけ）。

- 書き直しは 1.34 の apiserver で行う。v1 は 1.33 の apiserver も読める（1.33 で v1 は served。1.33 が v1beta1 で書いていたのは 1.32 に戻すためだった）ので、§7.2 で 1.33 に戻しても読める
- 書き直さずに進めても 1.34 は v1beta1 を読める。§3.4 が途中で止まっても、それだけで段を止める理由にはならない（止めて報告し、続けるかはユーザーが決める）

## 4. control-plane の kubelet と etcd を上げる（192.168.1.113 → .112 → .111）

### 4.1 何が起きるか

`install kubelet --node <IP>` は、`install-deps.sh`（kubelet・kubectl・crictl を落として張り替え、**etcd 3.6.15 の tarball から etcdctl と etcdutl を張り替え・置く**。CNI plugins は版の印が v1.9.1 で同じなので展開しない）、`install-pkgs.sh`（`apt-get install --no-upgrade`、iscsid は `systemctl start` だけ）、`install.sh`（addon の `dns`、`multipathd`、`etcd`）を root で流し、kubelet を v1.34.12 で再起動する。

**`etcd` の addon が `etcd-server.yaml` を 3.6.15 のものに置き換えるので、その台の etcd がここで 3.6.15 になる。** 新しい kubelet が mirror Pod を作り直し、etcd のコンテナが 3.6.15 のイメージで起き直す。ほかのコンテナは再起動しない見込み（dev の記録）。

| 段階 | etcd の版（.111 / .112 / .113） | cluster version・storage | 見込み |
|---|---|---|---|
| 前 | 3.5.34 / 3.5.34 / 3.5.34 | 3.5.0 | — |
| .113 の後 | 3.5.34 / 3.5.34 / **3.6.15** | 3.5.0 | 3.5 のリーダーが `leader found higher-versioned member` を出し続ける（想定どおり） |
| .112 の後 | 3.5.34 / **3.6.15** / 3.6.15 | 3.5.0 | 同上 |
| .111 の後 | **3.6.15** / 3.6.15 / 3.6.15 | **3.6.0** | リーダーのログに `updated cluster version`（`from 3.5 to 3.6`）。この後は 3.5 には戻せない（§7.4） |

- 3.6 の etcd は、起動の直後に `failed to publish local member to cluster through raft`（`etcdserver: too many requests`）を数十〜百回、数ミリ秒の間に出してから `published local member` になる（dev の見つけたことの 4。続かない）
- 3.6 の `--snapshot-count` の既定は 10000 になったが、本番は前から `--snapshot-count=10000` を渡している（変わらない）
- `/etc/etcd/pki` の証明書と鍵を root 0600 で置き直す。`etcd.crt` は作り直したもの（同じ鍵、同じ CA。§2.6）に替わる
- `dns` の addon は `systemd-networkd` を再起動するので、cnidaria の `no route` のログが出る（§8.1）
- control-plane には Longhorn のボリュームが無く、iscsid は動いていてセッションは無い（§2.7）

### 4.2 節目と、2 つ目のバックアップ

1. ✋ etcd のバックアップを取る（§2.4 と同じ形）。**IPAddress を書き直した後の、etcd 3.5 の最後の状態**（1.34 の control-plane）。§7.4 の restore で、段の前（§2.4）の代わりに使える
2. ✋✋ **control-plane の kubelet（etcd 3.6）の前の承認を取る。** §3.3 と §3.4 の結果、1 のバックアップ、§2.9 の v2store の確認、§7 のロールバックの形（混在中は 3.5 のイメージに戻す（dev で確かめていない）、全台 3.6 の後は restore だけ）を示す
3. §2.3 の etcd の health の監視を始める

### 4.3 1 台の手順

段 4 の手順書 §4.2 と同じ（1. 読み取りの確認と `snap`・`tools/node-state.sh` の控え、2. ✋ リーダーなら `move-leader`、3. ✋ `porkadot install kubelet --node <IP>`、4. kubelet の起動から 1 分ほど待って §4.4）。足すもの:

- 1 で、etcd のリーダーと各メンバーの `/version`、その台の動いている etcd のフラグを控える
- 2026-10-20 のリーダーは .113（`57ec6f12ac7b683e`）。このままなら、.113 の作業の前に .111（`21ab2aeb56731588`）へ移し、.111 の作業の前に .113 か .112（`fbb0c648cf5852a5`、どちらも 3.6）へ移す（dev は .112 → .111 → .112 と移した）
- **3 台を続けて流す**（§2.1 の 9）。1 台ごとの §4.4 の確認は省かないが、確認が済んだらすぐ次の台に入る
- 段 4 の本番では 1 台 16 秒〜51 秒だった。段 5 は etcd の tarball（arm64 で 23 MB）も落とすので、少し長くなりうる

### 4.4 1 台ごとの確認と、次の 1 台へ進む条件

段 3 の手順書 §4.3 の 1〜15 と同じ。次を読み替え、16〜18 を足す。

| # | 確認 | 合格基準（段 4 から変わるところ） |
|---|---|---|
| 1 | Node | VERSION が v1.34.12 |
| 2 | バイナリ | 向き先が `kubelet-v1.34.12`、`kubectl-v1.34.12`、`crictl-v1.34.0`、**`etcdctl-3.6.15`、`etcdutl-3.6.15`（`etcdutl:none` から）**。CNI の印と 4 つのプラグインは `v1.9.1` のまま。前の版のファイル（`kubelet-v1.33.13`、`etcdctl-3.5.34` など）も残っている（§7 の戻しで使う） |
| 4 | etcd | 3/3 healthy、リーダーが居る、raft index がそろう。**その台が 3.6.15、ほかはまだ上げていないものが 3.5.34**。`member list -w table` が 3 つとも `started` |
| 5 | etcd の Pod | 1/1 Running、`etcd:3.6.15-0`。mirror Pod の UID が変わる。起き直しの直後のほかのメンバーの `lost TCP streaming connection`・`peer became inactive` は数秒で止まる |
| 7 | Pod の再起動 | **差分は `kube-system/etcd-<IP>` の UID だけ**（restartCount は同じ）。ほかに UID・restartCount が変わったものがあれば止める |
| 8 | iscsid | MainPID と ActiveEnterTimestamp が同じ。PID が変わっていたら止める |
| 11 | kubelet のログ | 段 4 の手順書 §4.3 の 11 のもの（`object "<ns>"/"kube-root-ca.crt" not registered`、speaker の `"metallb-system"/"memberlist"`・`"metallb-excludel2"` の 1 回、止まる前の古い kubelet の `missing content for CA bundle`）は想定内。続くエラーが無い |
| 16（新） | etcd の版 | その台の `/version` が `{"etcdserver":"3.6.15","etcdcluster":"3.5.0","storage":"3.5.0"}`（3 台目の後は §4.5）。まだの台は `{"etcdserver":"3.5.34","etcdcluster":"3.5.0"}` |
| 17（新） | etcd のフラグ | その台の動いている etcd の cmdline に `--feature-gates=InitialCorruptCheck=true`、`--watch-progress-notify-interval=5s`、`--snapshot-count=10000` があり、`--experimental-` で始まるものが無い。`kubectl --context fraction -n kube-system logs etcd-<IP> \| grep -iE 'unknown flag\|invalid'` が何も出さない |
| 18（新） | etcd のログ | 想定どおりのもの: 3.5 のリーダーの `leader found higher-versioned member`（混在中ずっと）、3.6 の起動の直後の `failed to publish local member to cluster through raft`（`too many requests`、数ミリ秒の間だけ）、前から出ている `check file permission`（`/var/lib/etcd` が 755）・`Running http and grpc server on single port`・`simple token is not cryptographically signed`。ほかの warn・error の種類が増えたら記録し、続くものがあれば止める |

次の 1 台へ進む条件も段 3 の手順書 §4.3 と同じ（1〜18 がすべて合格、全 8 台 Ready、etcd 3/3 healthy で raft index がそろう、Running / Completed 以外の Pod がベースラインから増えていない）。

- 1 台の etcd が 3.6 で起きない（CrashLoopBackOff、`unknown flag`、データのエラー）ときは、ほかの 2 台で quorum が保たれている。**次の台に進まず、止めて報告する**（§7.3 で、その台を 3.5 に戻すかをユーザーが決める）

### 4.5 全台の後

.111 の §4.4 の後に、次を確かめる。

- 3 台の `/version` が `{"etcdserver":"3.6.15","etcdcluster":"3.6.0","storage":"3.6.0"}`
- 3 台のどれかのログに `updated cluster version`（`from 3.5 to 3.6`）、続いて `cluster version differs from storage version` の後に storage が 3.6.0 になったこと（dev の記録の「etcd 3.6」）
- `etcdctl endpoint status --cluster -w table` の 3 行とも VERSION と STORAGE VERSION が 3.6.x
- ✋ etcd のバックアップを取る（§2.4 と同じ形。**3.6 の etcdctl の `snapshot save` で取れること**を確かめる。dev では rc 0）。時刻、サイズ、sha256 を記録する
- §2.3 の etcd の health の監視を止める

## 5. worker の kubelet を上げる（1 台ずつ、drain しない）

### 5.1 順番

段 4 と同じ順にする（段 4 の手順書 §5.1。duchamp → pablo → braque → oeilvert → chirico）。当日の読み取りで、アタッチされたボリュームの数が変わっていれば、少ない台から多い台へ並べ直してよい。braque はどこに入れてもよい。

worker には etcd が無い。`install kubelet` で `/opt/bin` の etcdctl と etcdutl も 3.6.15 になる（使わない）。

### 5.2 1 台の手順

段 4 の手順書 §5.2 と同じ（§8.12 の Pod の削除も同じ扱い）。段 4 の本番では 1 台 16 秒〜21 秒だった。段 5 は etcd の tarball も落とすので、少し長くなりうる。

### 5.3 1 台ごとの確認

段 4 の手順書 §5.3 と同じ。次を読み替える。

| # | 確認 | 合格基準（段 4 から変わるところ） |
|---|---|---|
| 1 | Node | VERSION が v1.34.12 |
| 2 | バイナリ | 向き先が `kubelet-v1.34.12`、`kubectl-v1.34.12`、`crictl-v1.34.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と 4 つのプラグインは `v1.9.1` のまま。`kubelet-v1.33.13` なども残っている |
| 3 | iscsid | **MainPID と ActiveEnterTimestamp が同じ**。PID が変わっていたら止める |
| 7 | Pod の再起動 | **差分が無い**（名前・UID・restartCount が同じ）。1 つでもコンテナの再起動があれば、ここで止めて報告する（§2.1 の 3） |

ほか（Longhorn の node の一瞬の `is down`・`Waiting for disk`、orphan の CR の作り直しが起こりうること（段 4 の oeilvert。2026-10-20 に orphan を消したので、今は orphan が無い）、`FailedMount` の `no Pending workload pods`）は段 4 の手順書 §5.3 と同じ。

### 5.4 braque の手順

段 4 の手順書 §5.4 と同じ（バックアップの CronJob の時間帯を避ける。2026-10-20 の CronJob は段 4 と同じ）。

### 5.5 次の 1 台へ進む条件

段 4 の手順書 §5.5 と同じ（版を読み替える。終えたノードが v1.34.12、まだのノードが v1.33.13）。

- **最初の worker（duchamp）の後に、✋ `netcheck.sh` と §1.9 の NetworkPolicy の確認を流す**（1.34 の apiserver と、1.34 の kubelet のノードを含む形で、cnidaria の NetworkPolicy の処理が動くこと）

## 6. 段 5 の完了の確認

8 台を終えたら、計画 §6.3 の項目がすべて成り立つことを確かめ、`results/stage-5/summary.md` に残す。段 4 の手順書 §6 と同じ項目で、次を読み替える・足す。

- 8 台が Ready、全台 v1.34.12、CONTAINER-RUNTIME が `containerd://2.3.6`。どのノードも SchedulingDisabled でない
- 8 台の `/opt/bin` が `kubelet-v1.34.12`、`kubectl-v1.34.12`、`crictl-v1.34.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と 4 つのプラグインが `v1.9.1`
- **etcd**: 3/3 healthy、全メンバーが 3.6.15、cluster version・storage とも 3.6.0（§4.5）、リーダーが居る、raft index がそろう。3 台の動いている etcd のフラグに `--experimental-` が無い（段 8 の etcd 3.7 の前提。計画 §7 の段 8）。3 台の `/etc/etcd/pki` が `600 root:root`
- VIP の `/livez` が `ok`、`/version` が v1.34.12
- CoreDNS が v1.12.4 で 2/2 Running（段 5 では動かない）。§3.3 の 13 の問い合わせが同じ答え
- **全 Pod の restartCount が、ベースライン（§2.2 の 5）から増えていない**（control-plane の etcd の mirror Pod は UID が変わる。`install kubernetes` で作り直された Pod は新しい UID で 0）
- **storage version**: `tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` が空。`/registry/ipaddresses/` と `/registry/servicecidrs/` が `networking.k8s.io/v1` の `ok`。結果のファイルの要点を記録する
- **ServiceCIDR と IPAddress**: `servicecidrs` が `kubernetes` の 1 つで Ready、IPAddress の数が ClusterIP の数と同じ
- Longhorn、Longhorn の設定、iSCSI、cnidaria（✋ `netcheck.sh`、✋ §1.9 の NetworkPolicy の確認）、MetalLB、braque の NFS、`registry.fraction.jp`、CSR、§2.3 の監視の FAIL、leader election で再起動した controller: 段 4 の手順書 §6 と同じ。K8s 1.34 は Longhorn 1.11 の要件（1.25 以上）に入る
- `kubectl --context fraction top nodes` が応答し、Prometheus のスクレイプが落ちていない（`up == 0` が 0 個。`kube-etcd` の 3 つを含む）
- **metrics**: §8.15 の確認（`count(etcd_server_has_leader)` が 3、kube-prometheus のダッシュボードの etcd と apiserver のパネルが値を出す）
- `apiserver_requested_deprecated_apis` を記録する（段 4 の手順書 §6。`removed_release` が `1.34` 以前のものが出ていれば止めて調べる）。v1 Endpoints の warning の出どころも段 4 と同じ形で記録する（段 4 では longhorn-manager、prometheus-operator、Prometheus）
- 新しい warning のイベント・ログ（kubelet、apiserver、kube-proxy、cnidaria、etcd、Longhorn、CoreDNS）が増えていない（§8 のもの、v1 Endpoints の warning は除く）
- etcd のバックアップ（§2.4、§4.2、§4.5 の 3 つ）を worktree からメインの checkout の `backup/` へ移した（worktree で流した場合。coordinator）

## 7. ロールバック

**戻すのは runbook から外れる操作なので、その都度ユーザーの承認を取る。** 戻すと決める目安は段 1 の手順書 §7 と同じ（rollout が終わらない、VIP が 1 分を超えて応答しない、Node が 5 分たっても Ready にならない、etcd が 2/3 を下回る、Pod の再起動が続く、Longhorn のボリュームが degraded のまま戻らない、1.34 や etcd 3.6 に固有と見られる問題）。

**段 5 は etcd のマイナー更新を含むので、戻し方がどこまで進んだかで大きく変わる。**

| どこまで進んだか | etcd | 戻し方 | dev で確かめたか |
|---|---|---|---|
| `install kubernetes` の後、§3.4 の前後（kubelet と etcd はまだ前の版） | 3/3 が 3.5.34 | §7.2（0.33.1 で `install kubernetes`） | dev で戻した（`90863e9` の立て直しの後に 0.33.1 で `install kubernetes`。1 回目 rc 1、流し直して rc 0） |
| control-plane の kubelet の途中（混在中） | 3.5 と 3.6 | 上げた台を §7.3 で 3.5 に戻す | **確かめていない**（etcd の公式の文書は、混在中なら 3.5 のイメージに戻せるとしている） |
| control-plane の 3 台の後（cluster version 3.6.0） | 3/3 が 3.6.15 | **イメージを戻すだけでは戻せない。** 段の前の backup（3.5）へ §7.4 の restore で戻す | dev で確かめた（0.34.1 の restore、3.6.15 のまま 3.5 の snapshot を戻せた） |
| worker の途中・全部の後 | 3/3 が 3.6.15 | kubelet だけなら §7.6 で worker を 1.33 に戻せる。control-plane（1.33）まで戻すなら §7.4 と §7.5 | kubelet の 1.34 → 1.33 は確かめていない |

### 7.1 戻すための材料

- **前の版**: この PR の前の master（`b2edd42`）の `assets/` と `porkadot.yaml`、**porkadot 0.33.1**（`v0.33.1`、`1b6a671`）。この `assets/` は本番が今動いているもの（段 4 の 0.33.0 の render に、cnidaria の 0.33.1 の `render kubernetes` を足したもの）
- **restore**: 今の版（この PR をマージした master の `assets/`）と **porkadot 0.34.1**。0.34.0 は使わない（restore を 2 回続けて古い snapshot に戻すと informer が止まる。dev の見つけたことの 9）
- **etcd のバックアップ**: §2.4（段の前、1.33 の control-plane、etcd 3.5）、§4.2（IPAddress を書き直した後、1.34 の control-plane、etcd 3.5）、§4.5（全台 3.6 の後）

0.33.1 の `install kubelet` について:

- `/opt/bin/<名前>` の向き先で判定して張り替える。前の版のバイナリ（`kubelet-v1.33.13`、`etcdctl-3.5.34` など）はノードに残っているので、落とし直さずに向き先を戻す。**0.33.1 は etcdutl を知らないので、`/opt/bin/etcdutl` は 3.6.15 のまま残る**（害は無い）
- **control-plane では etcd のマニフェストを 3.5.34（`--experimental-*` のフラグ）に戻す。** 混在中なら、その台の etcd は 3.5.34 で起き直す見込み（§7.3）。**全台 3.6 の後に流すと、3.6 のデータでは 3.5.34 の etcd は起きない見込み**（dev の記録の申し送り。確かめていない）。全台 3.6 の後に 0.33.1 の `install kubelet` を control-plane に流さない（§7.5）
- `install-pkgs.sh` は 0.34.1 と同じ（iscsid は `initiatorname.iscsi` が変わったときだけ再起動する）
- 1.34 → 1.33 の kubelet の戻しでコンテナが再起動するかは、dev で確かめていない。**Longhorn のボリュームがアタッチされた台を戻すときは、再起動する前提で drain してから流す**（段 4 の手順書 §7.1 と同じ。drain の後・`install kubelet` の前に古いセッションを logout し、`install kubelet` の後に空を確かめる。§8.10）
- 0.33.1 の SSH は 0.34.1 と同じで、サンドボックスの中で流せる

用意の仕方（作業端末で。ノードには触らない。段 4 の手順書 §7.1 と同じ形）:

```sh
git clone /home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot /tmp/porkadot-0.33.1
git -C /tmp/porkadot-0.33.1 checkout v0.33.1
P_OLD=/tmp/porkadot-0.33.1
git clone <このリポジトリの checkout> /tmp/fraction-stage-4
git -C /tmp/fraction-stage-4 checkout b2edd42
cd /tmp/fraction-stage-4
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

- `git worktree add` は元の clone の `.git` に書き込むので、サンドボックスでは拒否される。`/tmp` に clone して使う
- 始める前に `grep VERSION $P_OLD/lib/porkadot/version.rb` が 0.33.1 で、`BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot help` が動くことを確かめておく（`bundle install` が要ることがある）

### 7.2 `install kubernetes` の後、kubelet と etcd はまだ前の版 ✋

```sh
cd /tmp/fraction-stage-4
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml
```

- apiserver・KCM・scheduler・kube-proxy が v1.33.13 に戻る。0.33.1 は全体を同時に apply するが、**1.34 → 1.33 の向きではデッドロックしない**（1.33 の scheduler は 1.34 の apiserver が返す API だけを使う。dev の戻しで確かめた）。rc 1（`connection refused`）なら rollout を待って流し直す（dev の戻しでも 1 回目 rc 1、流し直して rc 0）
- **IPAddress と ServiceCIDR**: 1.33 の apiserver は、v1 で保存されたものも読める。§3.4 で書き直した後に戻すと、`tools/storage-versions.sh`（1.33 の期待値は v1beta1）は書き直したもの（v1）を `OLD` と数える。dev の戻し（IPAddress の書き直しの前）では、1.33 の apiserver が ServiceCIDR を v1beta1 に書き戻した。IPAddress は、書かれるまで v1 のまま残る見込み（確かめていない）。読めるので害は無い。記録して、ほかの `OLD` が無いことを見る
- 1.34 の apiserver が消した FlowSchema の 2 つ（`endpoint-controller`、`workload-leader-election`）は、1.33 の apiserver が suggested のものとして作り直す見込み（確かめていない）。戻した後に FlowSchema が 13 個あることを見る
- §3.3 と同じ確認を、版を読み替えて行う

### 7.3 control-plane の kubelet の途中（etcd が混在） ✋

etcd の公式の文書（Upgrade etcd from v3.5 to v3.6 の「Rollback」）は、「少なくとも 1 つのメンバーが v3.5 のまま残る混在の状態なら、v3.5 のバイナリ（イメージ）に戻すか、snapshot から戻せる。この状態ではクラスタは v3.5 のクラスタとして動き続けるので、正式な downgrade の手順なしに戻せる」としている。**dev では確かめていない。**

戻すときは、3.6 にした台を、上げた順の逆に 1 台ずつ戻す。

```sh
cd /tmp/fraction-stage-4
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubelet --node <3.6 にした台> --config ./porkadot.yaml
```

- **cluster version が 3.5.0 のままであること**（どれかの台の `/version` の `etcdcluster`）を、流す前に確かめる。3.6.0 になっていたら §7.4
- 戻す台が etcd のリーダーなら、先に 3.5 のメンバーへリーダーを移す（§4.3）
- その台の etcd が 3.5.34 で起き、3/3 healthy、raft index がそろうこと。`/version` が `{"etcdserver":"3.5.34","etcdcluster":"3.5.0"}`、フラグが `--experimental-*` に戻ること。kubelet は v1.33.13、etcdctl は 3.5.34、etcdutl は 3.6.15 のまま
- 起きなければ、ほかの 2 台で quorum が保たれている間に止めて報告する（そのメンバーを外して入れ直す、または §7.4。その時点でユーザーと決める）
- kubelet が 1.33 に戻るので、apiserver（1.34）より古い。skew policy の範囲

### 7.4 etcd が全台 3.6 になった後: `porkadot etcd restore` ✋

**cluster version が 3.6.0 になった後は、3.5 のメンバーには戻せない**（etcd の公式の文書。上げた後に 3.5 に戻すには、上げる前に取った snapshot から戻すか、公式の downgrade の手順に従う）。段 5 の戻しは、上げる前に取った backup（3.5 の etcdctl で取ったもの）を、**0.34.1 の `porkadot etcd restore`** で戻すことになる。etcd は 3.6.15 のまま起き、cluster version・storage とも 3.6.0 になる（dev の記録の「上げる前の backup への restore」）。

**restore は最後の手段。** API の中身（すべてのオブジェクト）が backup の時点に戻り、backup の後の変更は失われる。

- **Longhorn の CR（Volume・Engine・Replica・InstanceManager など）も backup の時点に戻る。** backup の後に replica の作り直し・アタッチ先の変化・ボリュームの作成や削除があると、Longhorn の CR とノードの実際（replica のデータ、エンジンのプロセス）が食い違う。dev はボリュームを detach した状態で restore したので、アタッチされたボリュームでの振る舞いは確かめていない。**restore の前に、backup の後で Longhorn に変化が無かったか**（§2.2 の 18 とその後の各台の記録）を確かめ、変化があればユーザーに示す
- ほかに、backup の後に作られた Job の Pod や Secret、MetalLB・cnidaria の状態なども戻る。restore の後に kubelet が API の Pod と突き合わせ直し、API に無い Pod を止める（dev の見つけたことの 9・10）

**使う backup**:

| backup | API の中身 | restore の後 |
|---|---|---|
| §2.4（段の前） | 1.33 の control-plane、IPAddress は v1beta1 | kubelet が control-plane を 1.33.13 に入れ替える（dev の見つけたことの 10）。kubelet と etcd は 1.34.12・3.6.15 のまま（kubelet が apiserver より新しい、skew policy の外）。dev ではこの形で約 5 分、健全だった |
| §4.2（control-plane の kubelet の前） | 1.34 の control-plane、IPAddress は v1 | control-plane は 1.34.12 のまま。kubelet・etcd とも 1.34.12・3.6.15 で skew policy の中。失われる変更が少ない |

どちらにするかは、戻す理由（1.34 に固有の問題か、etcd 3.6 か、データか）で、その時点でユーザーと決める。

**前提**:

- **3 台の control-plane に `/opt/bin/etcdutl`（→ `etcdutl-3.6.15`）があること**（`tools/node-state.sh` の `bin`）。0.34.1 の restore は、全メンバーで etcd を止めてデータディレクトリを移した後に、各台の `/opt/bin/etcdutl snapshot restore` を流す。**どれかの台に etcdutl が無いと、その台はデータを移した後に restore が失敗する。** 全台 3.6 の後なら 3 台とも 0.34.1 の `install kubelet` を流しているので、ある
- 全メンバーの etcd が動いていること（0.34.1 は止める前に今の revision を読む。どれも答えないと、etcd に触る前にエラーで止まり、`--bump-revision` を手で渡すよう求める。そのときは止めて報告する）
- 監視（§2.3）が動いていること

**流し方**:

```sh
mkdir -m 700 ./backup-restore
cp -p ./backup/etcd-<使う backup の日時>.db ./backup-restore/
ls -l ./backup-restore/          # 1 つだけ
porkadot etcd restore --path ./backup-restore
```

- `etcd restore` は `--path` の**いちばん新しい** `etcd-*.db` を使う。`./backup/` には §4.5 の 3.6 の backup のほうが新しくあるので、使うものだけを別のディレクトリに置く（dev と同じ）
- 流れ（0.34.1）: 全メンバーの今の revision を読む → 3 台の etcd を止める（マニフェストを `/opt/porkadot/` へ移し、止まるのを待つ）→ 3 台で snapshot を置き、`/var/lib/etcd` を `/opt/porkadot/data-<時刻>` へ移し、`etcdutl snapshot restore … --bump-revision <幅> --mark-compacted` → マニフェストを戻す → 全メンバーの health を待つ → master ごとに 1 台ずつ kube-apiserver を crictl で止めて、起き直しと `127.0.0.1:6443/readyz` を待つ → KCM → scheduler（`--timeout`、既定 600 秒）
- ログに `etcd revisions: 192.168.1.111=…, 192.168.1.112=…, 192.168.1.113=…` と `Restore with --bump-revision <幅>: current revision <今>, snapshot revision <snapshot>, restored revision <後>` が出る。**`<後>` が `<今>` + 10 億以上であること**を確かめる（10 億 = 0.34.1 の余裕）。本番の revision は 2026-10-20 08:3xZ に 1,237,778,005（dev の約 60 万より桁が大きい。revision は int64 なので、数十億を足しても余裕がある）。当日の値は §2.2 の 4 で控える
- 所要時間（dev の 4 回目）: 約 4 分。API（VIP）は約 2〜3 分止まり、kube-apiserver の入れ替えでもう一度 10 秒ほど 000 になりうる（dev の見つけたことの 8）。LoadBalancer は途切れなかった。時間の大半は、kubelet が etcd の static Pod を起こすまでの待ち（mirror Pod の削除の timeout。dev の見つけたことの 7）
- 想定どおりの再起動: KCM・scheduler（API を失って exit する）、Longhorn の CSI のサイドカー（csi-attacher・provisioner・resizer・snapshotter。leader election）、ほかの leader election の controller（§8.8）
- 本番の `/var/lib/etcd` には、`member` のほかに `member.tar.gz`（2020 年）と、.111 には `member.2024-05-19` がある（1 台 0.4〜0.9 GB）。restore はディレクトリごと `/opt/porkadot/data-<時刻>` へ移すので、これらもそこへ移る。`/` は 105 GB 空いている

**流した後に確かめること**（dev の記録の「本番の段 5 の runbook に効くこと」の `etcd restore` の項目）:

- etcd 3/3 healthy、3.6.15、cluster version・storage とも 3.6.0。cluster ID が restore の前と同じ
- 3 台の apiserver が同じ中身を返す（apiserver ごとに `--server https://192.168.1.11N:6443` で Pod・ConfigMap・Service・EndpointSlice・Node・Lease・Longhorn のボリュームの一覧を取って比べる）
- restore の前の resourceVersion からの watch が `410 Expired` になる（`kubectl get --raw '/api/v1/namespaces/default/configmaps?watch=1&resourceVersion=<前の RV>'` を数秒で切る）
- kube-proxy の規則と EndpointSlice、各ノードの kubelet の Pod と `crictl pods` の ready の Pod が同じ
- Longhorn: ボリュームの state・robustness・アタッチ先、replica と engine が running。§2.2 の 18 と比べる
- 健全性（§6 の項目）

**続けて何を流すか**（その時点でユーザーと決める）:

- **進める（1.34 に揃える）**: §2.4 の backup に戻したときは、0.34.1 の `install kubernetes`（§3.2）で control-plane を 1.34.12 に上げ直し、§3.4 の IPAddress の書き直しをもう一度流す（dev で確かめた）。kubelet と etcd はそのまま
- **1.33 に戻す**: §7.5

`/opt/porkadot/data-<時刻>` には restore の前のデータディレクトリが残る。etcd を止めて `/var/lib/etcd` と入れ替えれば restore の前に戻せる見込み（dev では試していない）。段 5 が落ち着くまで残し、消すときはユーザーの承認を取る。

**restore を 2 回以上流すとき**: 0.34.0 の固定の幅（snapshot + 10 億）では、restore の後にそれより古い snapshot へもう一度戻すと、revision がクライアントの見た値より下になり、informer が止まった（dev の見つけたことの 9。エラーもイベントも返らず、kubelet が API の Pod と突き合わせ直さなかった）。0.34.1 は幅を max(10 億、今 − snapshot + 10 億) にするので、2 回目以降も restore 後の revision がそれまでの最大より上になる。**0.34.1 以外で restore を流さない。** 2 回目以降も、ログの `restored revision` が `current revision` + 10 億以上であることを確かめる。

**公式の downgrade の手順**（`etcdctl downgrade validate/enable 3.5` で cluster version を下げてから 3.5 のイメージに替える）も 3.6 にはあるが、porkadot は扱わず、dev でも確かめていない。使うならその時点でユーザーと決める。

### 7.5 全台 3.6 の後に、1.33 まで戻す ✋

API（control-plane）を 1.33 に戻すと、kubelet は apiserver より新しくてはいけないので、**全ノードの kubelet を 1.33 に戻す**ことになる。etcd は 3.6.15 のまま残す（3.5 には戻せない）。

- worker は §7.6 で戻せる（etcd が無いので、0.33.1 の `install kubelet` で足りる）
- **control-plane は、0.33.1 の `install kubelet` をそのまま流してはいけない**（etcd のマニフェストが 3.5.34 になり、3.6 のデータでは起きない見込み）。`porkadot.yaml` の `etcd.image_tag` を `3.6.15-0` に上書きし、0.33.1 で `render kubelet` / `render etcd` をし直した assets で流すことになる（0.33.1 の etcd のテンプレートは `--experimental-*` のフラグを出すが、3.6 はそれを非推奨のまま受け付ける。`install-deps.sh` の `ETCD_VER` も 3.6.15 になる）。**dev では確かめていない**ので、流す前に render の差分を見せて、その時点でユーザーと決める
- 順番は §7.7 と同じ（kubelet を先に、control-plane を最後に）

### 7.6 kubelet を戻す（1 台） ✋

```sh
cd /tmp/fraction-stage-4
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubelet --node <ノード> --config ./porkadot.yaml
```

- worker と、etcd が混在中の control-plane（§7.3）だけに使う。**全台 3.6 の後の control-plane には流さない**（§7.5）
- `/opt/bin` の向き先が `kubelet-v1.33.13`、`kubectl-v1.33.13`、`crictl-v1.33.0`、`etcdctl-3.5.34` に戻る（`etcdutl` は 3.6.15 のまま、CNI は v1.9.1 のまま）。確かめる
- **Longhorn のボリュームがアタッチされた台は、drain してから流す**（§7.1）
- 戻した台でも、§4.4 または §5.3 の確認を、版を読み替えて行う。iscsid は再起動しない見込み（0.33.1 の `install-pkgs.sh`）なので、§5.3 の 3 の「PID が同じ」をそのまま見る

### 7.7 段 5 全体をやめる

kubelet は kube-apiserver より新しくてはいけないので、**kubelet を先に戻し、control-plane を最後に戻す。**

- **etcd がまだ全台 3.5 か、混在中**: worker を上げた順の逆に §7.6 で戻し、control-plane の kubelet を上げた順の逆（.111 → .112 → .113）に §7.6 / §7.3 で戻し、最後に §7.2 で control-plane のマニフェストを戻す
- **etcd が全台 3.6**: §7.4 で restore するか、§7.5 の形で kubelet を戻してから §7.2 で control-plane のマニフェストを戻す（etcd は 3.6.15 のまま）。どちらもその時点でユーザーと決める

戻し終えたら、§6 の確認を版を読み替えて行い、`results/stage-5/` に戻した経緯を残す。

## 8. 既知の問題と注意

### 8.1 `install kubelet` のたびの cnidaria の `no route`

段 4 の手順書 §8.1 と同じ。段 4 の本番では各台で error が 7〜8 件、1 秒ほど（oeilvert は 0）。

### 8.2 render が証明書を作り直す

段 4 の手順書 §8.2 と同じ。当日に render し直さない。

### 8.3 `install kubernetes` の rc 1 とデッドロック

- **`connection refused` の rc 1**（段 4 の手順書 §8.3）: 0.33 までは、apiserver の DaemonSet の rollout が .111 から始まると、.111 の上で流れている `kubectl apply` の接続先が消え、残りの apply が rc 1 になった（本番の段 4 で起きた）。0.34 の `install.sh` は、apiserver だけを apply して rollout の完了を待つ間、`rollout status` の失敗を数えずに 5 秒ごとに見直し、rollout が終わってから全体を apply する。全体の apply のときは .111 の apiserver も新しくなっているので、起きにくくなる見込み（dev では 1 回目で rc 0）。起きたら §3.2 のとおり流し直す
- **apiserver の rollout の timeout**（`--apiserver-timeout`、既定 600 秒）: rollout が終わらないと、KCM・scheduler・kube-proxy・addon を apply せずに rc 1 で止まる。メッセージは `The kube-apiserver rollout did not finish in 600s` と `kubectl -n kube-system get pods -l app.kubernetes.io/component=kube-apiserver -o wide` の案内。Raspberry Pi の 3 台で、1 台 40 秒前後の入れ替え（段 4 の本番は rollout の全体で約 3 分）なら、600 秒には収まる見込み
- **デッドロック**（0.33.1 以前で 1.34 に上げたとき。§3.2）: 起きたら止めて報告する。dev の立て直しは、KCM と scheduler の Deployment を前の版（v1.33.13）のイメージに戻し、新しい scheduler の Pod を 1 つだけ `kind: Binding` で master に手で割り当てて leader にし、残りの apiserver の Pod をスケジュールさせた（dev の記録の「デッドロックと立て直し・戻し」）。runbook から外れる操作なので、その時点でユーザーと決める

### 8.4 1.34 の kubelet ではコンテナが再起動しない

段 4 の手順書 §8.4 と同じ。dev の 7 台で、`install kubelet` の前と後の Pod の UID と restartCount が同じだった。control-plane の etcd の static Pod は作り直される（3.6.15 で起き直す）。ほかのコンテナが 1 つでも再起動したら止める。

### 8.5〜8.9

段 4 の手順書 §8.5〜§8.9 と同じ。CSR は段 5 の間も出ない見込み（dev でも出なかった）。

### 8.10 iscsid と古い iSCSI のセッション（Longhorn v1.11.2）

段 4 の手順書 §8.10 と同じ。Longhorn のエンジンが直る版（v1.12.1 以上、各ボリュームのエンジンを新しいイメージにしたもの。**段 5 の後の Longhorn の更新**。§10）になるまで、**Longhorn の iSCSI のセッションが残ったノードで、iscsid を再起動しない。**

### 8.11 CNI plugins

段 5 では変えない。8 台とも、porkadot の版の印と、bridge・host-local・portmap・loopback が v1.9.1 にそろっている（§1.1）。

- **本番の cnidaria の DaemonSet は init container を持たない**（generation 3、`cnidaria-cni:v0.1.1`。2026-10-20 の入れ替え。`docs/cni/cnidaria-no-plugin-copy.md`）。`/opt/cni/bin` の標準の plugins を置くのは porkadot の `install kubelet` だけ
- 0.34.1 の `install-deps.sh` は、版の印が `v1.9.1` で同じなので tarball を展開しない（`CNI plugins v1.9.1 already installed`）。`/opt/cni/bin` の中身と mtime が前と同じであることを、各台の `tools/node-state.sh` の `cni` の行で見る（`docs/cni/tools/cni-bin.sh` で sha256 と mtime まで見てもよい）
- `install-deps.sh` の差分のうち CNI に関わるのはコメント 3 行（§2.6）だけ

### 8.12 Longhorn の `no Pending workload pods`（longhorn/longhorn#8072 の形）

段 4 の手順書 §8.12 と同じ（段の開始の承認の範囲の ✋。消す前に名前を知らせる）。2026-10-20 08:2xZ（JST 17:2x）は、Longhorn の PVC で当たるものは無い。**次の JST 05:30 より後に作業するなら、当たる前提で §2.2 の 22 で洗い出す**。

### 8.13 etcd の遅れと、1 台が止まる間の quorum

- control-plane の `install kubelet` の間、その台の etcd は数秒止まり、ほかの 2 台で quorum を保つ。dev では、.112 が kubelet・kubectl・crictl・etcd の tarball を落として展開していた 20 秒の間に、ほかの 2 台に `slow fdatasync`（最大 4.7 秒）と `leader failed to send out heartbeat on time` が出て、etcd が 3 台とも unhealthy、VIP がほぼ 000 になった（dev の見つけたことの 5。7 台の VM が同じホストのディスクを使う dev に特有と見ている）
- 本番の etcd は Raspberry Pi 5 の 3 台で別々の NVMe なので、同じ形では起きない見込み（段 3・段 4 の本番でも起きていない）。§2.3 の etcd の health の監視で見る
- 本番で VIP が 15 秒を超えて応答しないときは、etcd のログ（`slow fdatasync`、`apply request took too long`、`heartbeat`）を見て記録する。1 分を超えたら §7 の目安に当たる。**混在中に止まったときも、次の台に進まない**

### 8.14 storage version

`storage-versions.md`。§2.5 と §3.4 のとおり。

- `install kubernetes` の前に `OLD` が出たら止める
- `install kubernetes` の後、`/registry/ipaddresses/`（と `/registry/servicecidrs/`）のほかの prefix で `OLD` が出たら、または CRD の `MULTI` が出たら止めて調べる
- `install kubernetes` の後に `overrides.tsv` が 1.33 の 2 行のままなら、スクリプトがサーバーの版を 1.34 と読めていない（rollout の途中に流していないか、`kubectl --context fraction version` を見直す）

### 8.15 1.34 の metrics のラベルの変更

1.34 の Urgent Upgrade Notes（kubernetes#131845）で、apiserver と etcd クライアントの metrics のラベルが変わる。

- `etcd_request_duration_seconds`・`etcd_requests_total`・`etcd_request_errors_total`: `type` → `resource` と `group`
- `apiserver_cache_list_*`: `resource_prefix` → `group` と `resource`
- `apiserver_watch_events_sizes`・`apiserver_watch_events_total`: `kind` → `resource`
- `apiserver_storage_*`、`apiserver_watch_cache_*`、`watch_cache_capacity*`、`etcd_bookmark_counts`、`storage_decode_errors_total` など: `resource` から API の group を外して `group` に分ける
- `apiserver_selfrequest_total` に `group` を足す
- ほかに、`apiserver_storage_objects` が非推奨になり `apiserver_resource_objects` に替わる（kubernetes#132965）。`scheduler_scheduler_cache_size` が消える（kubernetes#131425）

**本番の kube-prometheus（chart 85.2.1）には効かない**（2026-10-20 08:2xZ の読み取り）:

- `monitoring` の ConfigMap（35 個。うち `grafana_dashboard=1` のダッシュボードが 28 個。ほかの名前空間にダッシュボードの ConfigMap は無い）と、全名前空間の PrometheusRule（37 個）を読み、上の metrics の名前を探した。**どれも使っていない。** 使っている etcd の metrics は、etcd のサーバーの側のもの（`etcd_server_has_leader`、`etcd_server_leader_changes_seen_total`、`etcd_server_proposals_failed_total`、`etcd_disk_wal_fsync_duration_seconds_bucket`、`etcd_disk_backend_commit_duration_seconds_bucket`、`etcd_mvcc_db_total_size_in_bytes`、`etcd_mvcc_db_total_size_in_use_in_bytes`、`etcd_network_*`、`etcd_server_quota_backend_bytes`）で、1.34 の変更の対象ではない
- Prometheus は `apiserver`（3）と `kube-etcd`（3）をスクレイプしていて、`etcd_request_duration_seconds` も取り込んでいる（ダッシュボードとルールが使っていないだけ）
- etcd 3.6 でも、上の etcd のサーバーの metrics が出ることを §6 で確かめる（`count(etcd_server_has_leader)` が 3、Grafana の etcd のダッシュボードが値を出す）。出なくなったものがあれば記録し、段 8 の後の kube-prometheus-stack の更新（計画 §8）で扱う。段の更新は止めない
- 手で作ったダッシュボードやクエリがあれば、ラベルの変更の影響を受けうる（`grafana-dashboard-statefulset` は 2021 年の kube-prometheus のもので、上の metrics を使っていない）

## 9. 記録

`results/stage-5/` に、ベースライン（`baseline.md`。§2.4 のバックアップ、§2.5 の storage version、§2.9 の v2store の確認も）、`install kubernetes`（`control-plane.md`。§3.3 の 13〜19 と §3.4 の IPAddress の書き直しも）、各台（`<ノード>.md`。control-plane は `192.168.1.11N.md`。§4.2・§4.5 のバックアップと etcd の版の移り変わりも）、全体のまとめ（`summary.md`。§6 の v1 Endpoints の warning の出どころの表と metrics の確認も）を残す。各台の雛形は `results/stage-5/template.md`。
時刻（UTC。control-plane のホストの JST の時刻は直して書く）、読み取りの結果、実行したコマンドと出力の要点、Pod の再起動の有無、iscsid の PID とセッションの前と後、etcd の版と cluster version、監視の FAIL（VIP・LB と etcd の health）、leader election で再起動したもの、手順書との差を書く。`tools/node-state.sh` と `snap` の出力、監視のログ（`./stage-5-probe.log`、`./stage-5-etcd-*.log`）、`tools/storage-versions.sh` の出力（キーと版だけで値は無い）、`endpoints-warnings.tsv` はタスクディレクトリの `notes/stage-5/` に置き、要点を記録に写す。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（同じ PR か、記録の PR で）。

## 10. 段 5 の後

- **1 日ほど様子を見る**（計画 §9.6。etcd のマイナー更新を含む段なので）。その間に、etcd のログに新しい warn・error が増えていないこと、Prometheus の etcd のパネル、Longhorn のボリュームが healthy のままであることを見る
- **その後、計画 §4.3 の Longhorn の更新に進む**（1.11.2 → 1.12.x（v1.12.1 以上）→ 1.13.x。1.13 は K8s 1.34 以上を要求するので、段 5 の後にしか入らない）。手順は別の作業単位で書き、更新の前に別に承認を取る（計画 §9.1。`kubectl diff` と `--dry-run=server` を見せてから）。この手順書では扱わない
- Longhorn の更新で各ボリュームのエンジンが新しいイメージになったら、Longhorn のノード 4 台の `/etc/apt/apt.conf.d/51fraction-hold-open-iscsi` を消す（計画 §4.3、§4.4）。§8.10 の守ることもそこで終わる
- 段 6（1.35）の前に、全台が cgroup v2 であることを確かめる（計画 §7）
- etcd のバックアップのうち、§2.4 と §4.2 の 3.5 のものは、Longhorn の更新が終わり段 6 に入るまで残す（段 5 の戻しの材料）
