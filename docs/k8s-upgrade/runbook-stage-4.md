# 段 4 の手順書: K8s を 1.32.13 から 1.33.13 へ上げる（本番 `fraction`）

本番クラスタ `fraction` の Kubernetes を v1.32.13 から v1.33.13 へ上げる手順。porkadot を 0.32.0 から 0.33.0 に替える。etcd と CNI plugins は据え置き、CoreDNS を上げる。
計画は同じディレクトリの `plan.md`（以下「計画」）の §6（骨子）と §7 の段 4 の行、決まったことは §9 にある。前の段は `runbook-stage-3.md`（以下「段 3 の手順書」）で、この手順書はそれを下敷きにし、**段 3 から変わる点を中心に書く**。段 3 と同じく drain しない。

| | 更新前 | 更新後 |
|---|---|---|
| porkadot | 0.32.0 | **0.33.0**（`8beb3b4`、タグ `v0.33.0`） |
| kube-apiserver、kube-controller-manager、kube-scheduler、kube-proxy | v1.32.13 | **v1.33.13** |
| kubelet、kubectl（ノードの `/opt/bin`） | v1.32.13 | **v1.33.13** |
| crictl（ノードの `/opt/bin`） | v1.32.0 | **v1.33.0** |
| CoreDNS | v1.11.4 | **v1.12.4**（Corefile は変わらない） |
| etcd（control-plane の static Pod）、etcdctl | 3.5.34 | 変えない |
| CNI plugins（ノードの `/opt/cni/bin`） | v1.9.1 | 変えない（8 台とも 4 つのプラグインが v1.9.1。段 3 でそろった） |
| `install-pkgs.sh`（`install kubelet` が流す） | iscsid は `initiatorname.iscsi` が変わったときだけ再起動、`apt-get install --no-upgrade` | 変えない |
| kubelet-serving-cert-approver | `0.12.1` | 変えない |
| containerd、runc | 段 C の 2.3.6、1.5.1 | 変えない |
| cnidaria、MetalLB | v0.1.1、v0.14.5 | 変えない（マニフェストの差分が無い） |
| kubelet の `config.yaml`・`kubelet.service` | — | 変えない |
| Longhorn | v1.11.2 | 変えない（要件は K8s 1.25 以上。計画 §4） |

porkadot 0.33.0 に入った PR は porkadot#46 だけ（K8s v1.33.13、crictl v1.33.0、CoreDNS v1.11.4 → v1.12.4）。#47 は版の数字の更新で、render の結果を変えない。

**CoreDNS を v1.12.4 にする理由**（計画 §2。kubeadm 1.33 の既定は v1.12.0）: v1.12.0 には、v1.11.4 で入った coredns#6898（hostname のある Endpoint だけに PTR を作る）の回帰が残っていて、v1.12.1 で revert された（coredns#7194）。v1.12.1〜v1.12.3 の修正も入る。段 5 の kubeadm の既定（v1.12.1）より新しいので、段 5 では据え置く。

この手順は dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で先に通してある（2026-10-20）。記録は porkadot-dev の `docs/k8s-upgrade/verification-0.33-rc.md`（以下「dev の記録」。porkadot-dev#12）。dev で分かったことは次のとおり。

- **1.33 の kubelet に上げても、コンテナは再起動しなかった**（1.32 と同じ）。7 台すべてで、`install kubelet` の前と、Ready の 20 秒後・60 秒後の Pod の名前・UID・restartCount が同じだった。例外は control-plane の etcd の static Pod で、mirror Pod が作り直された（UID が変わり、restartCount は同じ）
- **`install kubelet` で iscsid は再起動しなかった**（7 台とも PID が同じ）。Longhorn のボリュームをアタッチしたまま `install kubelet` した 2 台（.122、.121）で、セッションの番号とエンジンのプロセスが変わらず、ボリュームは `attached`・`healthy` のままで、書き込みに空きは無く、I/O エラーも無かった。detach の後にセッションは残らなかった
- `install kubernetes --node <CP>` は 1 回目で rc 0 だった（apiserver の rollout が .112 から始まった）。段 3 の dev の記録の rc 1（rollout が .111 から始まったとき）は今回も起こりうる（§3.2、§8.3）
- **CoreDNS v1.12.4** は 2/2 Ready で、ログは起動の行（`CoreDNS-1.12.4`）だけ。Service と Pod の名前、Service の IP と Endpoint の Pod の IP の逆引き（v4・v6）、外の名前が引けた。**hostname の無い Endpoint の Pod の IP も逆引きできる**（v1.11.4 の coredns#6898 の回帰が直っている。§3.3 の 13）
- **1.33 の apiserver は ServiceCIDR と、Service の ClusterIP ごとの IPAddress を作る**（`MultiCIDRServiceAllocator` が 1.33 で GA になり既定で有効）。移行のときに Service ごとに `ClusterIPNotAllocated` の Warning の event が 1〜2 回出た。この 2 種は `networking.k8s.io/v1beta1` で etcd に保存される（§2.5、§8.14）
- **v1 Endpoints の非推奨**: 1.33 の apiserver に替わった直後から、`apiserver_requested_deprecated_apis{resource="endpoints",version="v1"}` が 3 台とも 1 になった。control-plane 自身が Endpoints を使い続けるので、0 にはならない。ログに warning を出していたのは longhorn-manager（v1.11.2）だけだった（§6、§8.15）
- dev では、`install kubelet` の 30 秒後に etcd の apply が 20 秒ほど遅くなり、VIP が 1 回応答しなかったことがあった（`slow fdatasync` は無い。7 台の VM が同じホストのディスクを使うためと見ている。確かめていない）。§8.13
- 作業端末の kubectl v1.32.13 で問題なく使えた。CSR は 1 つも出なかった。porkadot のコマンドとノードへの `ssh` は、すべて pi のサンドボックスの中で流した

これを受けて、**本番の段 4 でも、どのノードも drain しない**（§2.7）。止める条件（Pod の UID・restartCount の変化、iscsid の PID の変化、古いセッション）は段 3 のまま使う。

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **arm64 の control-plane での 1.33 の kubelet**。dev の段 4 は amd64 の VM で通した。arm64 のイメージとバイナリが配布されていることは確かめてある（§1.7）
- **本番の数の Service での ServiceCIDR・IPAddress への移行**（ClusterIP のある Service 71 個、うち dual-stack 3 個で、IPAddress は 74 個の見込み。dev は 13 個・16 個）。§3.3 の 17
- **dev に無いクライアントの v1 Endpoints の利用**（kube-prometheus、ingress-nginx、gated など）。warning が出るだけで振る舞いは変わらない（§8.15）
- **本番の Longhorn のボリュームがアタッチされたままの `install kubelet`**（chirico 10 本、oeilvert 5 本、pablo 1 本。2026-10-20）。段 3 の本番では同じ形で問題が無かった

## 0. 役割と約束ごと

段 3 の手順書 §0 と同じ。違いは次のとおり。

- **承認の節目は 1 つだけ**（計画 §9.1「本番の各段の開始（render の差分を見せてから `install kubernetes` を流す前）」）。この手順書では ✋✋ を付けた。
  - ✋✋ **段 4 の開始**: render の差分（§2.6。この手順書と同じ PR）、drain しないこと（§2.7）を見せ、PR をマージしてから、`install kubernetes` を流す前（§3.1）
- 段 4 は storage version の書き直しが無い（§2.5）。etcd も変えないので、control-plane の kubelet の前の節目も無い。
- **節目の間の手順は、ユーザーに知らせるだけで進めてよい。** etcd のリーダーの移動、`install kubelet`、`install kubernetes` の流し直し（§3.2）、一時的な DaemonSet・NetworkPolicy の確認（`netcheck.sh`、`npcheck.sh`）は、この手順書に書いた形なら ✋（知らせてから行う操作）で、1 つずつ承認を取るものではない。
- **§8.12 の Completed / Succeeded の Pod の削除は、段の開始の承認の範囲の ✋ とする。** 対象はこの手順書に書いた条件（Running の Pod と同じ Longhorn の PVC を使う Completed / Succeeded の Pod。ノードは問わない）に当たるものだけで、消す前に対象の名前を知らせる。段 3 では runbook から外れる操作として、oeilvert と chirico の前に台ごとに承認を取った（4 つ。`results/stage-3/oeilvert.md` §1.3、`chirico.md` §1.3）が、段 4 では段の開始の承認のときに、§2.2 の 22 で洗い出したものと、当日に新しく当たるものを消すことの承認を取る。条件に当たらないもの（Job・CronJob・Running の Pod、NFS の PV のもの）には触らない。
- **runbook から外れる操作（ロールバック、drain への切り替え、想定外の対処、上のほかの Pod の削除、iSCSI のセッションの logout）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認は、知らせずに行ってよい。**1 台ずつ行う。** 時刻はすべて UTC で記録する（control-plane のホストの時刻は JST）。

## 1. 前提

### 1.1 段 3 が終わっていること

始める前に次を確かめる。

- 段 3 の完了の確認（段 3 の手順書 §6）が `results/stage-3/summary.md` に残っている
- 8 台すべてが v1.32.13、CONTAINER-RUNTIME が `containerd://2.3.6`、etcd が 3.5.34

2026-10-20 00:5xZ〜01:0xZ の読み取り（この手順書を書いたとき）では、段 3 の完了の確認から変わっていない。

- 8 台 Ready、全台 v1.32.13、`containerd://2.3.6`。etcd 3/3 が 3.5.34（リーダーは .113 の `57ec6f12ac7b683e`、raft term 23118）、DB 55 MB。Pod は 148 個で、Running / Completed 以外は 0 個
- controller-manager は .112（`-9cxxw`、リーダー）と .113（`-qmv4n`）、scheduler は .112（`-c5dxt`、リーダー）と .111（`-wf5xr`）。CoreDNS は v1.11.4 の 2/2（chirico、duchamp。generation 10）、kube-apiserver の DaemonSet の generation は 26
- Longhorn のボリュームは 17（attached healthy 16、detached 1 の `homegallery/cg-data`）。replica は chirico 11、duchamp 10、oeilvert 11、pablo 2
- `tools/storage-versions.sh` は `prefixes: 64, keys: 2150, OLD: 0, CRDs with more than one stored version: 0`（§2.5 で直したスクリプトで流した）
- `apiserver_requested_deprecated_apis` は `metallb.io/v1beta1 addresspools` だけ

### 1.2 kubeconfig の運用

確認は `kubectl --context fraction`（`fraction-auditor`、read-only）で行う。作業を始める前に `kubectl --context fraction auth can-i delete pods -A` が `no` であることを確かめる。

**段 4 で `infra-admin` の短命トークンを使うのは、`netcheck.sh`・§1.9 の NetworkPolicy の確認と、§8.12 の Pod の削除だけ**（storage version の書き直しも、cordon・drain・Longhorn の設定の切り替えも無い）。発行と破棄は段 3 の手順書 §1.2 と同じで、確かめるのは次の 2 つ。

```sh
umask 077
kubectl --context fraction create token infra-admin -n kube-system --duration=1h > /tmp/k8u-stage4-admin-token
ADMIN_TOKEN=$(cat /tmp/k8u-stage4-admin-token)
kubectl --context fraction --token="$ADMIN_TOKEN" auth can-i create daemonsets -n k8u-npcheck   # yes
kubectl --context fraction --token="$ADMIN_TOKEN" auth can-i delete pods -A                     # yes
```

- 変更系のコマンドは `kubectl-admin() { kubectl --context fraction --token="$ADMIN_TOKEN" "$@"; }` で流す
- 使い終えたらすぐ破棄する（`unset ADMIN_TOKEN` とファイルの削除）。段 3 では使う場面ごとに 1 時間の期限で発行し直した

### 1.3 SSH

段 3 の手順書 §1.3 と同じ（worker は `ssh yuanying@<IP>`、control-plane は `ssh ubuntu@<IP>`。サンドボックスの中で通る。control-plane には `unset LC_ALL` してから入る）。2026-10-20 にこの手順書を書いたとき、8 台ともサンドボックスの中から `tools/node-state.sh` を流せた。

### 1.4 porkadot の流し方

porkadot 0.33.0 の checkout（`porkadot-dev/porkadot` の `v0.33.0`、`8beb3b4`）を使い、**このリポジトリのルートを cwd にして** 流す。形は段 3 の手順書 §1.4 と同じ。

```sh
P=/home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot
git -C $P describe --tags          # v0.33.0（lib/porkadot/version.rb も 0.33.0）
cd <このリポジトリの checkout>     # §2.6 の PR をマージした master
BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

以下、この形を `porkadot <サブコマンド>` と書く。

- 0.33.0 は Ruby 4.0.7。clone の `bundle install` は済んでいる（2026-10-20 に、この checkout で §2.6 の render を流した）。始める前に `BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot help` が動くことを確かめる
- 作業ツリーの `assets/` と `porkadot.yaml` に PR の外の変更が無いこと（`git status --short assets porkadot.yaml` が空）。メインの checkout にほかの作業があれば、master の別の worktree を作ってそこで流す
- 段 4 で流す porkadot のコマンドは、`etcd backup`、`install kubernetes --node 192.168.1.111`、`install kubelet --node <ノード>` の 3 つだけ。**`install all`、`--node` なしの `install kubelet` と `install kubernetes`、`render`（特に `render all` と `render certs`）、`setup-node`、`setup-containerd` は流さない**
- **ノードに入る porkadot のコマンドもサンドボックスの中で流す**（0.33.0 の SSH は 0.32.0 と同じ）。当日の流す前の確かめ方は段 2 の手順書 §1.4 のスクリプト（`P` を 0.33.0 の checkout にする）。8 台とも hostname を返すこと

### 1.5 etcdctl の使い方

段 2 の手順書 §1.5 と同じ（sudo で流す。`move-leader` は `unset ETCDCTL_ENDPOINTS` してから `--endpoints` を渡す）。以下、この形を `etcdctl ...` と書く。

### 1.6 render に使った secrets と、本番との突き合わせ

secrets の在りかと扱いは段 1 の手順書 §1.6 と同じ（`assets/` の中に sops の binary 形式で暗号化してある。`assets/secrets.tar.asc` を展開しない。平文をディスクに書かない）。
段 4 の render（§2.6）の前に、同じ形で本番と突き合わせ直した（2026-10-20 00:5xZ。読み取りだけ。復号をパイプで流してハッシュだけを比べた）。

| 比べたもの | 本番の側 | 結果 |
|---|---|---|
| `assets/certs/kubernetes/ca.crt` | ConfigMap `default/kube-root-ca.crt` | 一致（SHA-256 `AB:5A:49:9E:…:A0:3E`。段 1〜3 と同じ） |
| `assets/certs/kubernetes/apiserver.crt` | VIP と 192.168.1.111〜113 の 6443 が返す証明書 | 4 つとも一致（`4A:E8:7B:B3:…:97:63`） |
| `assets/certs/kubernetes/` の 10 ファイル（`ca.crt`、`apiserver.{crt,key}`、`front-proxy-ca.crt`、`front-proxy-client.{crt,key}`、`kubelet-client.{crt,key}`、`sa.{key,pub}`） | .111 の kube-apiserver の Pod（`kube-apiserver-z2pdq`）にマウントされた Secret `kube-apiserver` | 10 ファイルとも sha256 が一致 |
| `assets/certs/etcd/{ca.crt,etcd-client.crt,etcd-client.key}` | 同じく Secret `etcd-tls` | 3 ファイルとも一致 |
| `assets/kubelet/192.168.1.11{1,2,3}/addons/etcd/{ca.crt,etcd.crt,etcd.key}`（render の前） | 3 台の `/etc/etcd/pki/` | 9 ファイルとも一致（`etcd.crt` は段 3 の render のもの） |
| CA の鍵と証明書（kubernetes、front-proxy、etcd） | — | 3 組とも公開鍵が一致 |

当日に確かめ直すときの形は段 1 の手順書 §1.6 と同じ。どれかが食い違えば、render の差分も assets も信用せず、止めて調べる。

### 1.7 入れる版を確かめる

作業の当日に確かめ直す（読み取り）。

```sh
curl -fsSL https://dl.k8s.io/release/stable-1.33.txt     # v1.33.13
```

2026-10-20 の時点:

- `stable-1.33.txt` は v1.33.13。`stable.txt` は v1.37.1
- registry.k8s.io の `kube-apiserver`・`kube-controller-manager`・`kube-scheduler`・`kube-proxy` の v1.33.13 は、どれも amd64 と arm64 を含む（manifest list を読んだ）。`coredns/coredns:v1.12.4` も amd64 と arm64 を含む
- `dl.k8s.io` の kubelet と kubectl の v1.33.13（amd64、arm64）、cri-tools の `crictl-v1.33.0-linux-{amd64,arm64}.tar.gz` は、どれも 200 を返す。cri-tools の 1.33 系は v1.33.0 だけ
- etcd 3.5.34 と CNI plugins v1.9.1 はノードに入っているもので、変わらない
- **作業端末の kubectl は v1.33.13**（2026-10-20 に上げた）。1.32 にも 1.33 にも ±1 に入る（計画 §6.1 の 4）

### 1.8 確認に使うスクリプト

段 3 の手順書 §1.8 と同じ（cnidaria の手順書の `verify-nodes.sh`・`netcheck.sh`・`check-apps.sh`、`tools/node-state.sh`、`tools/storage-versions.sh`）。

- **`tools/storage-versions.sh` はこの PR で直した**（§2.5）。1.33 の kube-apiserver が v1beta1 で保存する `ipaddresses`・`servicecidrs` を、サーバーの版が 1.33 のときだけ v1beta1 と比べる。1.32 で流したときの結果は前と同じ（2026-10-20 に本番で `OLD: 0`）

### 1.9 NetworkPolicy の確認（一時的な名前空間） ✋

段 3 の手順書 §1.9 と同じ（`tools/npcheck.sh` と `tools/npcheck.yaml`。`nft` → `up` → `nft` → `run` → `down` → `nft`）。合格は、`up` の後の `nft` が 8 台とも 1 以上、`run` が `OK 56, not OK 0`、`down` の後の `nft` が 8 台とも 0、名前空間 `k8u-npcheck` が NotFound。段 3 の本番では、`up` の後の `nft` は 8 台とも 9 だった。

流すのは、最初の worker の後（§5.5）と、段 4 の完了の確認（§6）。

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 順序 | `install kubernetes --node 192.168.1.111` → rollout の完了 → control-plane の `install kubelet --node` を 1 台ずつ（.113 → .112 → .111）→ worker を 1 台ずつ（§5.1） | 計画 §6.2 |
| 2 | etcd のリーダー | `install kubelet` の前に、対象がリーダーなら `move-leader` で別のメンバーへ移す | 計画 §6.2、dev の記録 |
| 3 | drain | **どのノードも drain しない**（§2.7）。**ただし、どの台の後でも、Pod のコンテナの再起動（restartCount の増加、UID の変化。control-plane の etcd の mirror Pod を除く）が 1 つでも出たら止める。** 特に最初の worker（duchamp）と、Longhorn のボリュームがアタッチされた最初の worker（pablo）の後に見る。止めた後、残りの Longhorn のノードを drain に切り替えるかはユーザーが決める（§8.10） | dev の記録、段 3 の本番、2026-10-19 のユーザーの方針（下の 4） |
| 4 | drain の基準 | 「短時間の途切れ」より「Longhorn のボリュームの安全（データ、degraded のまま戻らないこと）」を重く見る。短時間の障害は許容する | 2026-10-19 のユーザーの方針 |
| 5 | iSCSI | 各台の `install kubelet` の前と後に `tools/node-state.sh` で iscsid の PID と iSCSI のセッションを見る。iscsid の PID が変わったら止める。古いセッション（今の instance-manager の IP でない portal へのもの）があれば止める（§2.7、§5.3） | 計画 §4.4、dev の記録 |
| 6 | ノードの再起動 | しない | 計画 §9.3 |
| 7 | コンテナの再起動 | 1.33 の kubelet では起きないことを前提にする（§8.4）。control-plane の etcd の static Pod だけは作り直される | dev の記録 |
| 8 | Longhorn の設定 | 変えない（drain しないので、切り替えも Prometheus を止めることも無い） | 段 1 の手順書 §2.6 |
| 9 | storage version | 書き直すものは無い（§2.5）。`install kubernetes` の前に `OLD: 0` を確かめる。後では、1.33 の apiserver が v1beta1 で作る ServiceCIDR と IPAddress を、直した `tools/storage-versions.sh` が `ok` と数え、`OLD: 0` のままであることを見る（§3.3 の 16、§6） | 計画 §6.4、dev の記録 |
| 10 | Completed / Succeeded の Pod | Running の Pod と同じ Longhorn の PVC を使うものは、`install kubelet` の前に消す（§8.12。段の開始の承認の範囲の ✋。§0） | 段 3 の本番 |
| 11 | v1 Endpoints の warning | 段の更新を止める理由にしない。出どころを記録する（§6、§8.15） | dev の記録 |
| 12 | leader election を使う controller の 1 回の再起動と、gated の LoadBalancer の 1 回の途切れ | 許容する。記録して、Running に戻ったことを確かめる（§8.8） | 段 C、ユーザーの判断 |
| 13 | 停止時間 | いつでもよい。braque は念のためバックアップの CronJob の時間帯を避ける（§5.4）。早朝（JST 05:30・06:00）のバックアップの後は §8.12 の Pod が残る | 計画 §9.6、段 3 の本番 |
| 14 | 段 4 の後 | 健全性を確かめてから段 5 へ（間隔は必須ではない） | 計画 §9.6 |

### 2.2 クラスタ全体のベースライン

作業の当日、`install kubernetes` の前に次を取り、`results/stage-4/baseline.md` に残す（すべて読み取り）。段 3 の手順書 §2.2 と同じもので、次を読み替える・足す。

- 1: 全台 v1.32.13
- 2: 8 台の `tools/node-state.sh` の出力（ファイルに残す）。`/opt/bin` の向き先が `kubelet-v1.32.13`、`kubectl-v1.32.13`、`crictl-v1.32.0`、`etcdctl-3.5.34`。CNI の印と 4 つのプラグインが `v1.9.1`
- 5: **全 Pod の名前・UID・restartCount を控える**（§6 で「増えていない」ことを見る元になる）
- 14: Longhorn の設定（2026-10-20 は段 3 と同じ。`5`、`disabled`、`block-if-contains-last-replica`、`best-effort`、`6000`、v1.11.2）
- 18: Longhorn のボリュームの state・robustness・アタッチ先、replica の置き場所（§2.7 の表を当日に読み直す）
- 20: **storage version**: `tools/storage-versions.sh`（この PR で直したもの）の結果。`OLD: 0`、`CRDs with more than one stored version: 0` であること（段 3 の後なので。違えば止める。§2.5）。`overrides.tsv` が空であること（サーバーが 1.32 なので）
- 21: Prometheus の `apiserver_requested_deprecated_apis`（2026-10-20 は `metallb.io/v1beta1 addresspools` だけ）。読み方は次のとおり（`fraction-auditor` で読める）

  ```sh
  kubectl --context fraction get --raw '/api/v1/namespaces/monitoring/services/http:kube-prometheus-prometheus:9090/proxy/api/v1/query?query=apiserver_requested_deprecated_apis' | jq -r '.data.result[].metric | [.instance,.group,.version,.resource,.removed_release] | @tsv'
  ```

- 22: Longhorn のボリュームを使う Pod と、同じ PVC を使う Completed / Succeeded の Pod（§8.12 のコマンドを、ノードを絞らずに流す）。2026-10-20 01:0xZ は、Longhorn の PVC で当たるものは無い（Running と Succeeded が同じ PVC を使うのは `aphrael/aphrael-2` だけで、これは NFS の静的な PV。Succeeded の 3 つは CronJob `aphrael/tumblr-like` のもの）。**JST 05:30・06:00 のバックアップの CronJob の後に作業するなら、当たるものが出る前提で洗い出し、段の開始の承認のときに対象として示す**（§0、§8.12）
- 23（新）: **CoreDNS の答え**（§3.3 の 13 の前の値）。作業端末から kube-dns の Service の IP（10.254.0.10）に問い合わせる（下）。2026-10-20 01:0xZ の v1.11.4 では、Service の名前（`cluster.local`・`fraction.cluster`）、Service の IP の逆引き（v4・v6）、外の名前は引けたが、**hostname の無い Endpoint の Pod の IP の逆引きは NXDOMAIN** だった（kube-dns の Endpoint の `10.244.8.7`・`10.244.5.119`、`fs/h2` の Endpoint の `10.244.8.246`・`fde7:4ad6:425d:3::4b1f`。coredns#6898 の回帰）
- 24（新）: Service の数。2026-10-20 は 79 個で、ClusterIP を持つもの 71 個（うち dual-stack 3 個: `fs/data`、`fs/h2`、`fs/sites`）、headless 8 個。ClusterIP の数は 74（§3.3 の 17 の IPAddress の見込みの数）

  ```sh
  kubectl --context fraction get svc -A -o json | jq -r '[.items[] | select(.spec.clusterIP!="None" and .spec.clusterIP!=null and .spec.type!="ExternalName")] | "services with ClusterIP: \(length), dual: \([.[]|select((.spec.clusterIPs|length)==2)]|length), ips: \([.[].spec.clusterIPs[]]|length)"'
  ```

### 2.3 VIP と LoadBalancer を 1 秒ごとに見る

段 3 の手順書 §2.3 と同じ監視を、`install kubernetes` の前から最後の worker の確認まで、作業端末で流しておく（読み取り）。ログは `./stage-4-probe.log` に足していく（`tee -a`）。段 3 の本番では FAIL は 0 回だった。

### 2.4 etcd のバックアップ ✋

`install kubernetes` の前に、porkadot 0.33.0 で取る（計画 §6.1 の 5）。

```sh
porkadot etcd backup
ls -l ./backup/
```

- 0.33.0 の `etcd backup` は 0.32.0 と同じ（dev で rc 0）
- 手元のファイルは `./backup/etcd-<日時>.db`、モード 0600。`./backup/` は `.gitignore` で除外してある。スナップショットには Secret が平文で入っているので、`git add -f` などで追加しない
- **worktree で流したときは、`./backup/` は worktree の中にできる。** worktree を片付ける前に、coordinator がメインの checkout の `backup/` へ移す（段 1〜3 と同じ）
- 時刻、ファイル名、サイズ、sha256 を記録する。段 3 のバックアップ（`etcd-2026-10-19T23:13:51+00:00.db`）は 55,107,616 バイトだった（DB SIZE は 2026-10-20 も 55 MB）。桁が違えば止める
- 段 4 が終わるまで消さない

### 2.5 storage version（書き直しは無い）

段 4 では、`install kubernetes` の前に書き直すものは無い。段 3 の §2.5 で FlowSchema・PriorityLevelConfiguration・EndpointSlice を v1 に書き直し、段 3 の完了の確認で `OLD: 0` だった。1.33 で storage の版が変わる組み込みのリソースのうち、本番にオブジェクトがあるものは無い。

1. `install kubernetes` の前（§2.2 の 20）: `tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`。**違えば止める**（段 3 の後に何かが古い版で書いたことになる）
2. `install kubernetes` の後（§3.3 の 16）と完了の確認（§6）: 1.33 の apiserver が ServiceCIDR（`/registry/servicecidrs/kubernetes`）と IPAddress（`/registry/ipaddresses/`。Service の ClusterIP ごと、dual-stack の Service は 2 つ）を作り、どれも `networking.k8s.io/v1beta1` で保存される。**これは 1.33 では正しい保存の形なので、書き直さない**（書き直しても v1beta1 で保存される）

なぜ v1beta1 か: 1.33 の kube-apiserver は、`ipaddresses` と `servicecidrs` を v1beta1 で保存する（`pkg/kubeapiserver/default_storage_factory_builder.go` の `ResourceEncodingOverrides`、v1.33.13。「ipaddresses and servicecidrs are v1 in 1.33 / remove them in 1.34 when all apiserver understand the v1 version」）。1 つ前の 1.32 の apiserver が v1 を知らないので、1.32 に戻しても読めるようにするためである。discovery の `preferredVersion` は v1 なので、**直す前の `tools/storage-versions.sh` はこれらを `OLD` と数えていた**（dev の記録の見つけたことの 4。`storage-versions.md` §3 の最後の「`preferredVersion` と storage の版がずれる」場合）。

**この PR で `tools/storage-versions.sh` を直した**（合格基準を「`OLD` はこの 2 つの prefix だけ」にするのではなく、スクリプトの期待値に 1.33 の override を足した）。

- スクリプトはサーバーの版（`kubectl version` の minor）を読み、1.33 のときだけ `/registry/ipaddresses/` と `/registry/servicecidrs/` の期待値を `networking.k8s.io/v1beta1` にする（`overrides.tsv` に書き出す）。ほかの版では空で、前と同じに `preferredVersion` と比べる
- こうした理由: `OLD` の意味を「今の apiserver の storage の版と違う＝書き直しが要る」のまま保ち、各段の合格基準を `OLD: 0` のままにできる。合格基準の側で prefix を除くと、除いた prefix に本当に古いものがあっても見落とし、1.34 で override が外れたときに基準を戻し忘れる。スクリプトの側なら、1.34 の apiserver で流すと override が無くなるので、この 2 種が自然に `OLD` に出て、段 5 の書き直しの対象として洗い出せる（計画 §7 の段 5）
- 段 3 の使い方は変わらない（1.32 では `overrides.tsv` が空。2026-10-20 に本番の 1.32 で流して `OLD: 0`）。`install kubernetes` の rollout の途中（1.32 と 1.33 の apiserver が混ざる間）に流すと、VIP の先の apiserver の版で期待値が決まるので、rollout の完了（§3.3 の 1〜12）を待ってから流す

### 2.6 render の差分（この手順書と同じ PR）

計画 §6.1 の 6〜7。2026-10-20 00:57Z に、porkadot 0.33.0（`8beb3b4`）で、このリポジトリのルートを cwd にして `render kubelet` / `render etcd` / `render bootstrap` / `render kubernetes` を流した（`render all` と `render certs` は使っていない）。secrets は §1.6 のとおり本番と一致していることを確かめてから使った。`porkadot.yaml` は変えていない。

前の render は段 3 の porkadot 0.32.0（`0fece0a`）のもので、master の `421869b` にある。差分は次の 25 ファイルで、**これ以外の差分は無い**（新しくできたファイル、消えたファイルも無い）。

| ファイル | 変わったもの | 由来 |
|---|---|---|
| `kubernetes/manifests/kube-apiserver.yaml`・`kube-controller-manager.yaml`・`kube-scheduler.yaml`・`kube-proxy.yaml` | イメージ v1.32.13 → v1.33.13、`app.kubernetes.io/version` のラベル | K8s の版（porkadot#46） |
| `kubernetes/manifests/kube-apiserver.secrets.yaml`・`kube-controller-manager.secrets.yaml`（sops） | Secret の `app.kubernetes.io/version` のラベルだけ。data は同じ（復号して、キーごとの sha256 を比べた。13 キーと 3 キー） | 同上 |
| `kubernetes/manifests/porkadot.yaml` | Service `porkadot-kubernetes-latest` の selector の `app.kubernetes.io/version`（VIP の Service `porkadot-kubernetes` の selector には版が入っていない） | 同上 |
| `bootstrap/manifests/*.bootstrap.yaml`（4 つ） | イメージ v1.32.13 → v1.33.13、版のラベル | 同上（段 4 では使わない） |
| `kubelet-default/install-deps.sh` | `RELEASE`（kubelet・kubectl）v1.32.13 → v1.33.13、`CRICTL_VER` v1.32.0 → v1.33.0 | porkadot#46 |
| `kubernetes/manifests/addons/coredns/coredns.yaml` | イメージ `coredns:v1.11.4` → `v1.12.4`。Corefile は同じ | porkadot#46 |
| `kubelet/<8 台>/bootstrap.crt`、`bootstrap/kubelet/bootstrap.crt` | 作り直し（同じ鍵、同じ subject・issuer・SAN・用途、assets の CA で検証が通る。期限が 2027-10-20 00:57Z に延びる） | render のたびに作り直される（§8.2） |
| `kubelet/192.168.1.11{1,2,3}/addons/etcd/etcd.crt`（sops） | 同上（同じ鍵、同じ etcd の CA、同じ SAN） | 同上 |

- `app.kubernetes.io/version` が変わったのは平文のマニフェストで 23 行（dev の記録と同じ数）
- 変わらないもの: `kubelet-default/install-pkgs.sh`・`setup-containerd.sh`、`kubelet/<ノード>/config.yaml`・`kubelet.service`・`bootstrap-kubelet.conf`・`metadata.json`・**`initiatorname.iscsi`**、etcd の `etcd-server.yaml`（3.5.34-0）・`install.sh`・`etcd.env`・`etcd.key`、`install-deps.sh` の `CNI_VERSION`（v1.9.1）、CoreDNS の Corefile と RBAC、cnidaria・MetalLB・kubelet-serving-cert-approver のマニフェスト
- Deployment と DaemonSet の `spec.selector` には `app.kubernetes.io/version` が入っていない（段 1〜3 と同じ）
- 作り直した証明書は、作業の当日に render し直すとまた変わる。**当日は render しない**。この PR の `assets/` で流す

### 2.7 drain しない理由と、Longhorn・iSCSI の前提

**drain しない理由**（§2.1 の 3）は段 3 の手順書 §2.7 と同じで、段 4 の根拠は次のとおり。

- 1.33 の kubelet でも、dev の 7 台でコンテナが 1 つも再起動しなかった（etcd の static Pod を除く。dev の記録の見つけたことの 1）。drain しないでアタッチしたままのボリュームは、faulted・remount・I/O エラーにならなかった
- 0.33.0 の `install-pkgs.sh` は 0.32.0 と同じで、`initiatorname.iscsi` が同じなら iscsid を再起動しない（dev の 7 台で PID が同じ）。本番の 8 台の `/etc/iscsi/initiatorname.iscsi` は、この PR の `assets/kubelet/<ノード>/initiatorname.iscsi` と同じ（下の表。render はこのファイルを変えていない）
- 段 3 の本番でも、drain しないで 8 台を流し、コンテナの再起動・iscsid の再起動・古いセッションは 1 つも無かった（`results/stage-3/summary.md`）

**各ノードの iSCSI と Longhorn（2026-10-20 01:0xZ の読み取り。当日に `tools/node-state.sh` で読み直す）**:

| ノード | iscsid（MainPID、起動の時刻） | Longhorn のセッション（portal） | iscsid より前に起動したエンジン | アタッチされたボリューム | `initiatorname.iscsi` |
|---|---|---|---|---|---|
| 192.168.1.111 | 90734（16:31:09 JST = 07:31:09Z） | 0 | 0 | なし（Longhorn のノードではない） | assets と同じ |
| 192.168.1.112 | 89578（16:27:57 JST = 07:27:57Z） | 0 | 0 | なし | 同じ |
| 192.168.1.113 | 95423（16:24:21 JST = 07:24:21Z） | 0 | 0 | なし | 同じ |
| braque | 85966（08:06:03Z） | 0 | 0 | なし（Longhorn のノードではない） | 同じ |
| pablo | 1194943（07:39:11Z） | 1（10.244.4.131 = 今の instance-manager） | 0 | `fs/sites` | 同じ |
| duchamp | 663628（23:33:45Z。段 3 の `install kubelet` で起動） | 0 | 0 | なし | 同じ |
| oeilvert | 6334（09:04:34Z） | 5（すべて 10.244.7.116 = 今の instance-manager） | 0 | 5 | 同じ |
| chirico | 4447（09:17:30Z） | 10（すべて 10.244.8.216 = 今の instance-manager） | **1**（`prometheus-…-0` の pvc-625c8825、09:17:28Z） | 10 | 同じ |

- **古いセッションは無い**（どのセッションも、そのノードの今の instance-manager の IP へのもの）。段 3 の完了の確認から変わっていない
- chirico の `older-than-iscsid` の 1 つは、段 3 の手順書 §2.7 の注のもの（iscsid がソケット起動された 1〜2 秒前に起動したエンジンで、動いている iscsid の PID を持っている）。当日も同じ形なら、記録して進める。新しく増えていたら止める
- Longhorn のボリュームのアタッチ先: chirico 10（`tumblr-data`、`ero-data`、`fs/data`、`fs/h2`、`natsumi-myao`、`prometheus-…-0`、`fraction-agents` の 4 つ）、oeilvert 5（`natsumi`、`natsumi-aki`、`prometheus-…-1`、`fraction-agents` の 2 つ）、pablo 1（`fs/sites`）。replica は chirico 11、duchamp 10、oeilvert 11、pablo 2
- replica 1 のボリューム: `prometheus-…-0`（replica もアタッチも chirico）、`prometheus-…-1`（replica もアタッチも oeilvert）。drain しないので、止めない

### 2.8 MetalLB の告知ノードを読む

段 1 の手順書 §2.7 と同じ読み方（speaker のログの最後の `serviceAnnounced`。アドレスで分ける）。2026-10-20 01:0xZ は、段 3 の手順書 §2.8 の表と同じだった。

| Service | `externalTrafficPolicy` | アドレス | 告知ノード |
|---|---|---|---|
| `kube-system/porkadot-kubernetes`（API の VIP） | Cluster | 192.168.1.101 | **pablo** |
| `gated-system/gated-v4` | Local | 192.168.1.200 | chirico |
| `gated-system/gated-v6` | Local | `::200` | oeilvert |
| `fs/h2-sshd` | Cluster | `::131` | 192.168.1.112 |
| `natsumi/natsumi-sshd` | Cluster | `::132` | 192.168.1.111 |
| `natsumi/natsumi-sshd-myao` | Cluster | `::133` | duchamp |
| `natsumi/natsumi-sshd-aki` | Cluster | `::134` | 192.168.1.112 |
| `minecraft/bds-v4`、`minecraft*/bds` | Cluster / Local | 192.168.1.223、`::999{1,2,3}` | 当日に読む |

段 4 では speaker のコンテナが再起動しない見込みなので、告知は移らない見込み（段 3 の本番でも移らなかった）。

- 本番の段 4 では、chirico の `install kubelet` の間に gated-v4（`externalTrafficPolicy: Local`）の告知が 1 秒ほど oeilvert へ移って chirico に戻った（監視の FAIL は 0。`results/stage-4/chirico.md` §4 の注）。告知が戻ったことを記録する
- 「最後の `serviceAnnounced`」を時刻で並べて読むとき、同じ秒に `serviceWithdrawn`（`notOwner`）と `serviceAnnounced` が並ぶことがある。そのときは時刻で並べ替えず、speaker のログの順で読む（段 4 の chirico では、時刻と文字の順で並べると取り下げが最後に見えたが、ログの順では告知が最後だった）

## 3. control-plane のマニフェストを上げる（`install kubernetes`）

### 3.1 事前確認

✋✋ **段 4 の開始の承認を取る。** §2.6 の表と PR の差分、§2.7 の drain しない理由と止める条件、§2.2 のベースライン（22 の Completed の Pod で消すもの、§0）、§2.4 のバックアップ、§2.8 の告知ノードを示す。承認を得て PR をマージし、マージした master で §3.2 に入る。

- §2.2 のベースラインと §2.4 のバックアップが済んでいる。§2.3 の監視が動いている
- `tools/storage-versions.sh` が `OLD: 0`（§2.5 の 1）
- 全台 Ready、etcd 3/3 healthy、VIP の `/readyz` が `ok`
- checkout が §2.6 の PR をマージした master で、`git status --short assets porkadot.yaml` が空
- §1.4 の SSH の確かめで 8 台とも通る

### 3.2 流す ✋

```sh
porkadot install kubernetes --node 192.168.1.111
```

- **`--node` を必ず付ける。** 付けないと bootstrap ノード（pablo）で `kubectl apply` を流し、`127.0.0.1:6443` に届かず rc 1 になる
- apiserver（DaemonSet）、controller-manager、scheduler、kube-proxy が v1.33.13 で rollout し、CoreDNS が v1.12.4 で rollout する。kubelet-serving-cert-approver、cnidaria、MetalLB はマニフェストが変わらないので動かない
- 時刻と rc を記録する。段 3 の本番では 24 秒で rc 0、rollout の完了まで 3 分ほどだった
- **rc 1 で、出力の最後が `dial tcp 127.0.0.1:6443: connect: connection refused` なら、§3.3 の `rollout status` で apiserver の rollout の完了を待ってから、同じコマンドをもう一度流してよい**（§8.3）。流し直しは ✋ で、承認は要らない。流し直した時刻と rc、DaemonSet `kube-apiserver` の generation が流し直しの前と後で同じこと（2 回目の rollout が起きていないこと）を記録する。rc 1 でほかのエラーなら止める。流し直しても rc 1 なら止める

### 3.3 rollout の完了を確かめる

段 3 の手順書 §3.3 と同じ（版を v1.33.13 に読み替える）。CoreDNS と storage version の項目を次に替え、17・18 を足す。

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
| 1〜12 | 段 1 の手順書 §3.3 の 1〜12 | 同じ。Server が v1.33.13、apiserver・KCM・scheduler・kube-proxy が v1.33.13。Node は 8 台 Ready で kubelet は v1.32.13 のまま（apiserver 1.33 と kubelet 1.32 は skew policy の範囲）。DaemonSet `kube-apiserver` の generation が 1 つ増える（段 3 の後は 26） |
| 13 | CoreDNS | Deployment `coredns` が 2/2、Pod のイメージが `registry.k8s.io/coredns/coredns:v1.12.4`、2 つの Pod のログに `CoreDNS-1.12.4` があり（`maxprocs`・`.:53`・設定の SHA512 の行の後。v1.11.4 と同じ並び）、ほかにエラーの行が無い。generation が 1 つ増える（段 3 の後は 10）。名前の答えは下の表（§2.2 の 23 と同じ問い合わせ） |
| 14 | approver | `kubelet-serving-cert-approver` が `0.12.1` のまま 1/1。generation が変わらない |
| 15 | CSR | `kubectl --context fraction get csr` に新しい CSR が無い（出ていれば、kubelet の serving のものは approver が Approved,Issued にしていること） |
| 16 | storage version | `tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`。`overrides.tsv` が 2 行（`/registry/ipaddresses/`、`/registry/servicecidrs/`）で、`summary.tsv` にこの 2 つの prefix が `networking.k8s.io/v1beta1` の `ok` で出る（IPAddress は 17 の数、ServiceCIDR は 1）。2 つのほかに増えた prefix が無い（Event などの数は変わってよい） |
| 17 | ServiceCIDR と IPAddress | `kubectl --context fraction get servicecidrs` に `kubernetes` が 1 つで、CIDRS が本番の `service_subnet`（`10.254.0.0/24,fd20:afc2:7c09::/108`）。`kubectl --context fraction get ipaddresses --no-headers \| wc -l` が §2.2 の 24 の ClusterIP の数（2026-10-20 は 74）。Service ごとの `ClusterIPNotAllocated`（`Cluster IP [IPv4]: ... is not allocated; repairing`）の Warning の event は想定どおり（Service ごとに 1〜2 回、apiserver の入れ替えの直後だけ）。数と時刻の幅を記録する。数分たっても新しく出続けるなら止める |
| 18 | v1 Endpoints の warning | `apiserver_requested_deprecated_apis`（§2.2 の 21 の読み方）に `resource="endpoints",version="v1"` が出る（control-plane 自身が使うので必ず出る。§8.15）。**合格基準にはしない。記録だけ**。`metallb.io/v1beta1 addresspools` のほかに、`removed_release` が `1.33` 以前のものが出ていないこと（出ていれば、それは使えなくなった API なので止めて調べる） |

13 の名前の確かめ方（作業端末から。読み取り）:

```sh
D=10.254.0.10
q() { echo "$* -> $(dig -4 +short @$D "$@" | tr '\n' ' ')$(dig -4 @$D "$@" | grep -o 'status: [A-Z]*')"; }
q kubernetes.default.svc.cluster.local
q kubernetes.default.svc.fraction.cluster
q www.google.com A
q -x 10.254.0.1                       # Service の IP（v4）
q -x fd20:afc2:7c09::521              # Service の IP（v6。fs/h2）
kubectl --context fraction -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}'
kubectl --context fraction -n fs get endpointslices -l kubernetes.io/service-name=h2 -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}'
q -x <kube-dns の Endpoint の Pod の IP>     # 新しい CoreDNS の Pod の IP
q -x <fs/h2 の Endpoint の Pod の IP（v4 と v6）>
```

| 問い合わせ | v1.11.4（§2.2 の 23） | v1.12.4 の合格 |
|---|---|---|
| `kubernetes.default.svc.cluster.local`、`kubernetes.default.svc.fraction.cluster` | `10.254.0.1` | 同じ |
| `www.google.com` | 外のアドレス | 同じ |
| PTR `10.254.0.1`、`fd20:afc2:7c09::521` | `kubernetes.default.svc.cluster.local.`、`h2.fs.svc.cluster.local.` | 同じ |
| PTR の、hostname の無い Endpoint の Pod の IP（kube-dns、`fs/h2` の v4・v6） | NXDOMAIN（coredns#6898） | **`<IP をハイフンでつないだもの>.kube-dns.kube-system.svc.cluster.local.`、`….h2.fs.svc.cluster.local.`**（dev の記録の見つけたことの 3） |

- 1 つの Pod を複数の Service が Endpoint に持つときは、Service ごとの名前が返る（本番の段 4 では、CoreDNS の Pod に `kube-prometheus-coredns.kube-system` の名前も、`fs/h2` の v6 に `h2-sshd.fs` の名前も返った。`results/stage-4/control-plane.md` §3）
- PTR の Pod の IP の答えが NXDOMAIN のままでも、ほかが合格なら止めない（v1.11.4 と同じ振る舞いで、本番で困っていない）。記録して報告する
- 作業端末の `dig` の `socket(): Operation not permitted` は、サンドボックスが IPv6 の socket を塞いだもので、`-4` の問い合わせの結果には関係ない
- LAN から Service の IP と `fraction.cluster` の名前が引けることは、braque の確認（§5.4）でも見る
- rollout が途中で 30 秒ほど止まって見えることがある（controller-manager のリーダーの交代。段 1 の手順書 §3.3 の注）
- apiserver の rollout が .111 から始まると（§8.3）、古い apiserver が止まりかける間に、controller-manager の `FailedToUpdateEndpoint`・`FailedToUpdateEndpointSlices`、DaemonSet `kube-proxy` の `FailedCreate`（どれも `dial tcp 10.254.0.1:443: connect: connection refused`）と、新しい controller-manager の `FailedMount`（`failed to sync secret cache`）が 1 回ずつ出る（本番の段 4。`results/stage-4/control-plane.md` §7）。続かず、Pod が再起動しなければ想定内
- ここで問題があれば、kubelet にまだ触っていないので、§7.2 で control-plane だけを戻せる

## 4. control-plane の kubelet を上げる（192.168.1.113 → .112 → .111）

### 4.1 何が起きるか

`install kubelet --node <IP>` は、`install-deps.sh`（kubelet・kubectl・crictl を落として張り替える。CNI plugins は版の印が v1.9.1 で同じなので展開しない。etcdctl は同じ版なので落とさない）、`install-pkgs.sh`（`apt-get install --no-upgrade`、iscsid は `systemctl start` だけ）、`install.sh`（addon の `dns`、`multipathd`、`etcd`）を root で流し、kubelet を v1.33.13 で再起動する。

**コンテナは再起動しない見込み**（dev の記録、段 3 の本番と同じ）。etcd の static Pod の mirror Pod だけが作り直され、etcd のコンテナが新しい sandbox で起き直す（段 3 の手順書 §4.1 の表）。リーダーなら先に移す。

- `etcd` の addon は `/etc/etcd/pki` の証明書と鍵を root 0600 で置き直す。`etcd.crt` は作り直したもの（同じ鍵、同じ CA。§2.6）に替わる
- `dns` の addon は `systemd-networkd` を再起動するので、cnidaria の `no route` のログが出る（§8.1）
- control-plane には Longhorn のボリュームが無く、iscsid は動いていてセッションは無い（§2.7）

### 4.2 1 台の手順

段 3 の手順書 §4.2 と同じ（1. 読み取りの確認と `snap`・`tools/node-state.sh` の控え、2. ✋ リーダーなら `move-leader`、3. ✋ `porkadot install kubelet --node <IP>`、4. kubelet の起動から 1 分ほど待って §4.3）。

- 2026-10-20 のリーダーは .113（`57ec6f12ac7b683e`）。このままなら、.113 の作業の前に .111（`21ab2aeb56731588`）へ移し、.111 の作業の前に .113 か .112（`fbb0c648cf5852a5`）へ移す（段 3 の本番と同じ形）
- 段 3 の本番では 1 台 21 秒〜1 分 9 秒だった。段 4 は CNI plugins を落とさないので、同じか短い見込み

### 4.3 1 台ごとの確認と、次の 1 台へ進む条件

段 3 の手順書 §4.3 の 1〜15 と同じ。次を読み替える。

| # | 確認 | 合格基準（段 3 から変わるところ） |
|---|---|---|
| 1 | Node | VERSION が v1.33.13 |
| 2 | バイナリ | 向き先が `kubelet-v1.33.13`、`kubectl-v1.33.13`、`crictl-v1.33.0`、`etcdctl-3.5.34`（変わらない）。CNI の印と 4 つのプラグインは `v1.9.1` のまま。前の版のファイル（`kubelet-v1.32.13` など）も残っている（§7 の戻しで使う） |
| 7 | Pod の再起動 | **差分は `kube-system/etcd-<IP>` の UID だけ**（restartCount は同じ）。ほかに UID・restartCount が変わったものがあれば止める |
| 8 | iscsid | MainPID と ActiveEnterTimestamp が同じ（§2.7 の表）。PID が変わっていたら止める |
| 11 | kubelet のログ | 段 3 の手順書 §4.3 の 11 のものに加え、起動の直後の `object "<ns>"/"kube-root-ca.crt" not registered`（kubelet の informer がそろう前の 1 回。その Pod は再起動しない。本番の段 4 では control-plane の 3 台とも、speaker の `"metallb-system"/"memberlist"`・`"metallb-excludel2"` でも同じ形が出た）と、止まる前の古い kubelet の `missing content for CA bundle "client-ca-bundle::/etc/kubernetes/pki/ca.crt"`（1 回）は想定内（dev の記録の見つけたことの 7）。続くエラーが無い |

次の 1 台へ進む条件も段 3 の手順書 §4.3 と同じ（1〜15 がすべて合格、全 8 台 Ready、etcd 3/3 healthy で raft index がそろう、Running / Completed 以外の Pod がベースラインから増えていない）。

## 5. worker の kubelet を上げる（1 台ずつ、drain しない）

### 5.1 順番

段 3 と同じ順にする（段 3 の手順書 §5.1）。

| 順 | ノード | アタッチされたボリューム（2026-10-20） | iSCSI のセッション | 理由・注意 |
|---|---|---|---|---|
| 1 | duchamp | なし | 0（iscsid は段 3 で起動したもの） | Longhorn のノードで、ボリュームがアタッチされていない。1.33 の kubelet で longhorn-manager・instance-manager・CSI のプラグインが再起動しないことを、ボリュームを危険にさらさずに確かめる。`natsumi-sshd-myao` を告知している |
| 2 | pablo | 1（`fs/sites`） | 1 | **API の VIP を告知している。** ボリュームのアタッチされた最初の台。bootstrap ノード |
| 3 | braque | なし（Longhorn のノードではない） | 0 | nfsd が載っている（§5.4）。バックアップの CronJob の時間帯を避ける |
| 4 | oeilvert | 5（`prometheus-…-1` の replica 1 を含む） | 5 | gated-v6 を告知している |
| 5 | chirico | 10（`prometheus-…-0` の replica 1 を含む） | 10 | アタッチされたボリュームが最も多いので最後にする。gated-v4 を告知している。iscsid より前に起動したエンジンが 1 つ（§2.7） |

当日の読み取りで、アタッチされたボリュームの数が変わっていれば、少ない台から多い台へ並べ直してよい。braque はどこに入れてもよい。

### 5.2 1 台の手順

段 3 の手順書 §5.2 と同じ（1. 読み取りの確認: Node、`snap`、`tools/node-state.sh`、古いセッションが無いこと、`older-than-iscsid` のエンジン、アタッチされたボリュームの robustness、§8.12 の Pod、告知している LoadBalancer。2. ✋ `porkadot install kubelet --node <ノード>`。3. kubelet の起動から 1 分ほど待って §5.3）。違いは次のとおり。

- 1 の §8.12 のコマンドで当たるもの（Running の Pod と同じ Longhorn の PVC を使う Completed / Succeeded の Pod）があれば、✋ 名前を知らせてから `install kubelet` の前に消す（§0。段の開始の承認の範囲）。`infra-admin` のトークンが要る（§1.2）

  ```sh
  kubectl-admin -n <ns> delete pod <Pod>
  ```

- 段 3 の本番では 1 台 24 秒〜57 秒だった

### 5.3 1 台ごとの確認

段 3 の手順書 §5.3 の 1〜12 と同じ。次を読み替える。

| # | 確認 | 合格基準（段 3 から変わるところ） |
|---|---|---|
| 1 | Node | VERSION が v1.33.13 |
| 2 | バイナリ | 向き先が `kubelet-v1.33.13`、`kubectl-v1.33.13`、`crictl-v1.33.0`。CNI の印と 4 つのプラグインは `v1.9.1` のまま。`kubelet-v1.32.13` なども残っている |
| 3 | iscsid | **MainPID と ActiveEnterTimestamp が同じ**（duchamp も、段 3 で起動した iscsid が動いているので同じであること）。PID が変わっていたら止める |
| 6 | Longhorn | 段 3 の手順書と同じ。kubelet の再起動の数秒の間の Longhorn の node のイベント `Node <ノード> is down: manager pod ... is not running`・`Waiting for disk ... to be ready / schedulable` は想定内（段 3 の本番の 4 台、段 4 の本番の pablo・oeilvert・chirico で出た）。同じ間に、そのノードの Longhorn の orphan（古い replica のデータの置き場所）の CR が `OrphanCleanupCompleted` で片付けられ、同じ名前で作り直されることがある（段 4 の oeilvert で 3 つ。`orphan-resource-auto-deletion` が空なのでデータは消えない。`results/stage-4/oeilvert.md` §4 の注）。今の replica とボリュームに変化が無ければ想定内 |
| 7 | Pod の再起動 | **差分が無い**（名前・UID・restartCount が同じ）。1 つでもコンテナの再起動があれば、ここで止めて報告する（§2.1 の 3） |
| 9 | kubelet のログ | §4.3 の 11 と同じものは想定内。続くエラーが無い。Longhorn のボリュームの `FailedMount`（`no Pending workload pods`）が続いていない（§8.12） |

7 で再起動が出たときと、3〜5 で iscsid の PID が変わった・セッションが消えた・エンジンが止まったときの扱いは、段 3 の手順書 §5.3 の注と同じ（それ以上の台に進まず、報告する。§8.10）。

### 5.4 braque の手順

段 3 の手順書 §5.4 と同じ（nfsd が Running で restartCount が同じ、2049 を listen している、oeilvert のホストの `/home/yuanying/shared/nfs` が読める、`registry.fraction.jp/v2/` が応答する、LAN から Service の IP（10.254.0.0/16）と `fraction.cluster` の名前が引ける）。

- **バックアップの CronJob の時間帯を避ける**（止めてはいけない時間帯（JST）: 05:15〜06:45、14:30〜15:00、16:45〜17:05、17:55〜18:15）。2026-10-20 の CronJob は段 3 と同じ（`fs/h2-backup` 05:44、`natsumi/natsumi-backup*` 05:30、`fraction-agents/deep-researcher-backup` 06:00、`fs/sites-backup` 07:53、`fs/data-backup` 09:03、`aphrael/tumblr-like` 3 時間ごとの 38 分）。作業の前に `kubectl --context fraction get cronjobs -A` で見直す
- 段 3 の本番の braque は JST 08:42 に流し、nfsd も再起動しなかった

### 5.5 次の 1 台へ進む条件

段 3 の手順書 §5.5 と同じ（版を読み替える。終えたノードが v1.33.13、まだのノードが v1.32.13）。

- **最初の worker（duchamp）の後に、✋ `netcheck.sh` と §1.9 の NetworkPolicy の確認を流す**（1.33 の apiserver と、1.33 の kubelet のノードを含む形で、cnidaria の NetworkPolicy の処理が動くこと）

## 6. 段 4 の完了の確認

8 台を終えたら、計画 §6.3 の項目がすべて成り立つことを確かめ、`results/stage-4/summary.md` に残す。段 3 の手順書 §6 と同じ項目で、次を読み替える・足す。

- 8 台が Ready、全台 v1.33.13、CONTAINER-RUNTIME が `containerd://2.3.6`。どのノードも SchedulingDisabled でない
- 8 台の `/opt/bin` が `kubelet-v1.33.13`、`kubectl-v1.33.13`、`crictl-v1.33.0`、`etcdctl-3.5.34`。CNI の印と 4 つのプラグインが `v1.9.1`
- VIP の `/livez` が `ok`、`/version` が v1.33.13
- **CoreDNS が v1.12.4 で 2/2 Running**。ログにエラーが無い。§3.3 の 13 の問い合わせをもう一度流し、同じ答え
- **全 Pod の restartCount が、ベースライン（§2.2 の 5）から増えていない**（control-plane の etcd の mirror Pod は UID が変わる。`install kubernetes` で作り直された Pod は新しい UID で 0）
- **storage version**: `tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`（47 個の CRD の `status.storedVersions` が 1 つ）。`/registry/ipaddresses/` と `/registry/servicecidrs/` が `networking.k8s.io/v1beta1` の `ok`（§2.5）。結果のファイルの要点（prefix の数、キーの数、`OLD`、`MULTI`、`overrides.tsv`）を記録する
- **ServiceCIDR と IPAddress**: `servicecidrs` が `kubernetes` の 1 つで Ready、IPAddress の数が ClusterIP の数と同じ（段の間に Service が増減していれば、当日の数と比べる）。`ClusterIPNotAllocated` の event が `install kubernetes` の直後のほかに出ていない
- Longhorn、Longhorn の設定、iSCSI、cnidaria（✋ `netcheck.sh`、✋ §1.9 の NetworkPolicy の確認）、MetalLB、braque の NFS、`registry.fraction.jp`、CSR、§2.3 の監視の FAIL、leader election で再起動した controller: 段 3 の手順書 §6 と同じ。iSCSI は、8 台の iscsid の PID が段の前と同じ（duchamp も）、古いセッションが無い、`older-than-iscsid` のエンジンが段の前から増えていない
- `kubectl --context fraction top nodes` が応答し、Prometheus のスクレイプが落ちていない（`up == 0` が 0 個）
- **`apiserver_requested_deprecated_apis` を記録する**（§2.2 の 21 の読み方）。`resource="endpoints",version="v1"` は必ず出る（§8.15）ので、**合格基準にしない**。`removed_release` が `1.33` 以前のものが出ていれば止めて調べる
- **v1 Endpoints の warning の出どころを記録する**（下）。dev では longhorn-manager v1.11.2 だけだった。本番には dev に無いもの（kube-prometheus、ingress-nginx、gated、metrics-server など）がある。出たものは、Pod・コンテナ・行の数・その製品と版を `summary.md` に表で書き、段 8 の後の非クリティカルなコンポーネントの更新（計画 §8）の材料にする。**warning は振る舞いを変えないので、段の更新を止める理由にはしない**（v1 Endpoints は 1.33 で非推奨になっただけで、削除の予定は無い）
- 新しい warning のイベント・ログ（kubelet、apiserver、kube-proxy、cnidaria、etcd、Longhorn、CoreDNS）が増えていない（§8 のもの、`ClusterIPNotAllocated`、v1 Endpoints の warning は除く）
- etcd のバックアップ（§2.4）を worktree からメインの checkout の `backup/` へ移した（worktree で流した場合。coordinator）

v1 Endpoints の warning の探し方（読み取り。`<since>` は `install kubernetes` の時刻を RFC 3339 で。2026-10-20 に、このループが本番で動くことを確かめた。Running のコンテナ 177 個に 20 秒ほど）:

```sh
since=<YYYY-MM-DDThh:mm:ssZ>
kubectl --context fraction get pods -A -o json | jq -r '.items[] | select(.status.phase=="Running") | [.metadata.namespace, .metadata.name, ([.spec.containers[].name]|join(","))] | @tsv' |
while IFS=$'\t' read -r ns pod cs; do for c in $(echo "$cs" | tr , ' '); do
  n=$(kubectl --context fraction -n "$ns" logs "$pod" -c "$c" --since-time="$since" 2>/dev/null | grep -c 'v1 Endpoints is deprecated')
  printf '%s/%s\t%s\t%s\n' "$ns" "$pod" "$c" "$n"
done; done > endpoints-warnings.tsv
awk -F'\t' '$3 > 0' endpoints-warnings.tsv
```

- 1 行の形は `warnings.go:...] "Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice"`（client-go）。warning をログに出さないクライアントもあるので、出なかったものが Endpoints を使っていないとは限らない（dev の記録の見つけたことの 5）
- `install kubernetes` の後に作り直されたコンテナ（kube-system の rollout したもの）は、作り直された後のログだけになる

## 7. ロールバック

**戻すのは runbook から外れる操作なので、その都度ユーザーの承認を取る。** 戻すと決める目安は段 1 の手順書 §7 と同じ（rollout が終わらない、VIP が 1 分を超えて応答しない、Node が 5 分たっても Ready にならない、etcd が 2/3 を下回る、Pod の再起動が続く、Longhorn のボリュームが degraded のまま戻らない、1.33 に固有と見られる問題）。

### 7.1 戻すための材料

前の版は、**この PR の前の master（`421869b`）の `assets/` と `porkadot.yaml`** と、**porkadot 0.32.0**（`v0.32.0`、`0fece0a`）を使う。この `assets/` は 0.32.0 で render したもので、本番は今これで動いている。

- 0.32.0 の `install kubelet` は `/opt/bin/<名前>` の向き先で判定して張り替える。前の版のバイナリ（`kubelet-v1.32.13` など）はノードに残っているので、落とし直さずに向き先を戻す。CNI plugins は同じ v1.9.1 なので触らない
- **0.32.0 の `install-pkgs.sh` は 0.33.0 と同じ**（iscsid は `initiatorname.iscsi` が変わったときだけ再起動する）。段 2 の 0.31.0 のような「戻すと iscsid が再起動する」問題は無いので、Longhorn のボリュームがアタッチされた台も、iscsid の件では drain しなくてよい
- 1.33 → 1.32 の kubelet の戻しで、コンテナが再起動するかは dev で確かめていない。**Longhorn のボリュームがアタッチされた台を戻すときは、再起動する前提で drain してから流す**（§8.10 の drain する場合の手順。drain の後・`install kubelet` の前に古いセッションを logout し、`install kubelet` の後に空を確かめる）。アタッチされたボリュームの無い台（control-plane、braque、当日の duchamp など）は drain しなくてよい
- 0.32.0 の SSH は 0.33.0 と同じで、サンドボックスの中で流せる（段 3 で通した）

用意の仕方（作業端末で。ノードには触らない）:

```sh
git clone /home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot /tmp/porkadot-0.32.0
git -C /tmp/porkadot-0.32.0 checkout v0.32.0
P_OLD=/tmp/porkadot-0.32.0
git clone <このリポジトリの checkout> /tmp/fraction-stage-3
git -C /tmp/fraction-stage-3 checkout 421869b
cd /tmp/fraction-stage-3
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

- `git worktree add` は元の clone の `.git` に書き込むので、サンドボックスでは拒否される（dev の記録の「porkadot」の節）。`/tmp` に clone して使う
- `bundle install` が要ることがある（0.32.0 の Gemfile.lock）。始める前に `grep VERSION $P_OLD/lib/porkadot/version.rb` が 0.32.0 で、`BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot help` が動くことを確かめておく
- secrets は前の版も同じ（sops の同じ鍵。§1.6）。clone の `assets/` は暗号化されたままで、作業端末の age の鍵で porkadot が復号する

### 7.2 `install kubernetes` の後、kubelet はまだ前の版 ✋

```sh
cd /tmp/fraction-stage-3
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml
```

- apiserver・KCM・scheduler・kube-proxy が v1.32.13 に、CoreDNS が v1.11.4 に戻る。§3.2 と同じく、rc 1（`connection refused`）なら rollout を待って流し直す
- dev では確かめていない。§3.3 と同じ確認を、版を読み替えて行う
- **ServiceCIDR と IPAddress**: 1.33 の apiserver が作ったものは etcd に v1beta1 で残る。1.32 の apiserver は `MultiCIDRServiceAllocator` が既定で無効（beta）で、ClusterIP を前の bitmap（`/registry/ranges/serviceips`）で割り当てる。1.33 の apiserver も bitmap に書き続けている（`DisableAllocatorDualWrite` が 1.33 で既定で無効。`pkg/features/kube_features.go`、v1.33.13）ので、戻しても ClusterIP の割り当ては食い違わない見込み。残った ServiceCIDR と IPAddress は 1.32 では使われない。1.32 で流した `tools/storage-versions.sh` は、これらを `OLD` と数える（1.32 には override が無いので `preferredVersion` の v1 と比べる）。戻した後はこの 2 つの prefix の `OLD` を記録し、ほかの `OLD` が無いことを見る。消すかどうかは、その時点でユーザーと決める
- storage の版: 1.33 で新しく storage の版が変わるリソースのオブジェクトは、上の 2 つのほかに本番に無い。**段 4 の間に、1.33 で新しく使えるようになった API のオブジェクトを作らない**

### 7.3 kubelet を戻す（1 台） ✋

```sh
cd /tmp/fraction-stage-3
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubelet --node <ノード> --config ./porkadot.yaml
```

- `/opt/bin` の向き先が `kubelet-v1.32.13`、`kubectl-v1.32.13`、`crictl-v1.32.0` に戻る（etcdctl は 3.5.34 のまま、CNI は v1.9.1 のまま）。確かめる
- **Longhorn のボリュームがアタッチされた台は、drain してから流す**（§7.1）
- control-plane では、戻す台が etcd のリーダーなら先に §4.2 の 2 でリーダーを移す
- 戻した台でも、§4.3 または §5.3 の確認を、版を読み替えて行う。iscsid は再起動しない見込み（0.32.0 の `install-pkgs.sh`）なので、§5.3 の 3 の「PID が同じ」をそのまま見る

### 7.4 段 4 全体をやめる

kubelet は kube-apiserver より新しくてはいけないので、**kubelet を先に戻し、control-plane を最後に戻す。**

1. worker を、上げた順の逆に §7.3 で戻す
2. control-plane の kubelet を、上げた順の逆（.111 → .112 → .113）に §7.3 で戻す
3. §7.2 で control-plane のマニフェストを戻す

戻し終えたら、§6 の確認を版を読み替えて行い、`results/stage-4/` に戻した経緯を残す。etcd のバックアップ（§2.4）からの restore は最後の手段で、段 1 の手順書 §7.4 と同じ扱い（その時点でユーザーと決める）。

## 8. 既知の問題と注意

### 8.1 `install kubelet` のたびの cnidaria の `no route`

段 3 の手順書 §8.1 と同じ。段 3 の本番では各台で error が 6〜8 件、1 秒ほど（oeilvert は 0）。

### 8.2 render が証明書を作り直す

段 3 の手順書 §8.2 と同じ。`bootstrap.crt`（9 つ）と master の `addons/etcd/etcd.crt`（3 つ）は render のたびに作り直される（同じ鍵、同じ CA）。当日に render し直さない。

### 8.3 `install kubernetes` の rc 1（`127.0.0.1:6443` の `connection refused`）

段 3 の手順書 §8.3 と同じ。apiserver の DaemonSet の rollout が .111 から始まると、.111 の上で流れている `kubectl apply` の接続先が消え、残りの apply が rc 1 になる。rollout の完了を待って流し直すと rc 0 になり、2 回目の rollout は起きない。

- 0.32 の rc（dev）で rc 1、本番の段 3 と 0.33 の rc（dev）では rc 0 だった。どちらの rc 0 も rollout が .112 から始まり、.111 の入れ替えは apply が終わった後だった。rollout の始まるノードによるので、段 4 でも起こりうる
- **本番の段 4（2026-10-20）は rc 1 だった。** apiserver の rollout が .111 から始まり（.111 → .112 → .113）、MetalLB の `L2Advertisement` と `ValidatingWebhookConfiguration` の apply が `connection refused` になった。§3.2 のとおり rollout の完了を待って流し直し、rc 0、generation は変わらなかった（`results/stage-4/control-plane.md` §2）

### 8.4 1.33 の kubelet ではコンテナが再起動しない

段 3 の手順書 §8.4 と同じ（1.31 の kubelet が作り直したコンテナは、1.32・1.33 の kubelet でも同じ hash になる）。dev の 7 台で、`install kubelet` の前と後の Pod の UID と restartCount が同じだった。control-plane の etcd の static Pod は作り直される。ほかのコンテナが 1 つでも再起動したら止める。

### 8.5〜8.9

段 3 の手順書 §8.5（`InvalidDiskCapacity`）、§8.6（porkadot を流す場所）、§8.7（段 2 の .111 の件）、§8.8（leader election の controller の再起動）、§8.9（kubelet の serving の証明書と CSR）と同じ。CSR は段 4 の間も出ない見込み（dev でも出なかった）。次に CSR が出るのは、kubelet が証明書を更新するとき（いちばん早いのは oeilvert、期限 2027-03-20）。

### 8.10 iscsid と古い iSCSI のセッション（Longhorn v1.11.2）

段 3 の手順書 §8.10 と同じ。Longhorn のエンジンが直る版（v1.12.1 以上、各ボリュームのエンジンを新しいイメージにしたもの。段 5 の後）になるまで、**Longhorn の iSCSI のセッションが残ったノードで、iscsid を再起動しない。** 段 4 で見ること（§5.2 の 1、§5.3 の 3〜5）と、drain する場合の手順（drain の後・`install kubelet` の前に `tools/iscsi-logout-stale.sh` で古いセッションを logout し、`install kubelet` の後に `No active sessions.` を確かめて、再起動せずに uncordon する）も同じ。

- 段 4 では、duchamp の iscsid は段 3 で起動したものが動いている（§2.7）。段 3 のような「前に動いていなかった」台は無い見込み。当日に動いていない台があれば、`systemctl start` で起動するのは想定内（段 3 の手順書 §8.10）

### 8.11 CNI plugins

段 4 では変えない。8 台とも、porkadot の版の印と、bridge・host-local・portmap・loopback が v1.9.1 にそろっている（段 3 の手順書 §8.11）。0.33.0 の `install-deps.sh` は印が同じなので tarball を展開しない。

### 8.12 Longhorn の `no Pending workload pods`（longhorn/longhorn#8072 の形）

段 3 の手順書 §8.12 と同じ。kubelet は再起動の後、動いている Pod のボリュームにも `NodePublishVolume` をやり直し、Longhorn v1.11.2 の CSI は、同じ PVC を使う Succeeded（Completed）の Pod があると（ノードを問わない）、`Aborted: no Pending workload pods ...` で断り続ける（Pod は動き続ける）。

- **段 3 の本番では、JST 05:30・06:00 のバックアップの CronJob の Pod が Completed で残り、oeilvert で 2 つ（`natsumi`、`natsumi-aki`）、chirico で 2 つ（`natsumi-myao`、`fraction-agents/data-deep-researcher-0`）当たった**（`results/stage-3/oeilvert.md` §1.3、`chirico.md` §1.3）。CronJob は `natsumi/natsumi-backup`・`-aki`・`-myao`（JST 05:30）と `fraction-agents/deep-researcher-backup`（JST 06:00）
- 2026-10-20 01:0xZ（JST 10:0x）は、当たるものは無い（段 3 で 4 つを消した後、次の Job はまだ流れていない）。**次の JST 05:30 より後に作業するなら、当たる前提で §2.2 の 22 で洗い出す**
- 段 4 では、当たったものの削除は段の開始の承認の範囲の ✋ にする（§0）。各台の §5.2 の 1 で同じコマンドを流し、当たったものの名前を知らせてから、`install kubelet` の前に消す。洗い出しのコマンドは段 3 の手順書 §8.12 のもの（`--arg n <ノード>` で、そのノードの Running の Pod の PVC に絞る）。出た PVC が Longhorn のもの（`kubectl --context fraction get pv <PV> -o jsonpath='{.spec.csi.driver}'` が `driver.longhorn.io`）であることを確かめる。NFS の PV（`aphrael/aphrael-2` など）は当たらないので消さない

### 8.13 dev の etcd の遅れ

段 3 の手順書 §8.13 と同じ扱い。0.33 の rc の dev でも、`install kubelet` の 30 秒後に etcd の `apply request took too long`（最大 0.6 秒）・`waiting for ReadIndex response took too long` が 20 秒ほど出て、VIP が 1 回応答しなかった（dev の記録の見つけたことの 6。`slow fdatasync` は無い）。本番の etcd は Raspberry Pi 5 の 3 台で別々のディスクなので、同じ形では起きない見込み（段 3 の本番でも起きていない）。本番で VIP が 15 秒を超えて応答しないときは、etcd のログを見て記録する。1 分を超えたら §7 の目安に当たる。

### 8.14 storage version

`storage-versions.md`。§2.5 のとおり、段 4 では書き直すものは無い。`install kubernetes` の前に `OLD` が出たら止める。後に、`/registry/ipaddresses/` と `/registry/servicecidrs/` のほかの prefix で `OLD` が出たら、または CRD の `MULTI` が出たら止めて調べる。

- `/registry/ipaddresses/` と `/registry/servicecidrs/` が `OLD` に出たら、スクリプトがサーバーの版を 1.33 と読めていない（`overrides.tsv` が空）。rollout の途中に流していないか、`kubectl --context fraction version` を見直す
- 1.34.0 のソースでは `ipaddresses`・`servicecidrs` の override が外れている（`default_storage_factory_builder.go`、v1.34.0）。段 5 の `install kubernetes` の後は、この 2 種が本当に古い版（v1beta1）になり、`OLD` に出る見込み。段 5 の dev で確かめ、段 5 の書き直しの対象に入れるかを決める（計画 §7 の段 5）

### 8.15 v1 Endpoints の非推奨と `apiserver_requested_deprecated_apis`

1.33 で core の v1 Endpoints が非推奨になった（KEP-4974。削除の予定は無い）。1.33 の apiserver は、Endpoints への要求に `Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice` の warning を返し、`apiserver_requested_deprecated_apis{group="",resource="endpoints",version="v1",removed_release=""}` を 1 にする。

- control-plane 自身が Endpoints を使い続ける（kube-controller-manager の endpoints controller が PUT し、apiserver が `default/kubernetes` の Endpoints を GET する）ので、このメトリクスは段 4 の後は必ず出て、0 にならない（dev の記録の見つけたことの 5）。段 3 の手順書 §2.2 の 21 の「ベースラインから増えていない」は、段 4 からは `endpoints` を除いて見る
- warning は振る舞いを変えない。出どころは §6 で記録し、段の更新は止めない
- dev では longhorn-manager v1.11.2 の 3 つが、`longhorn-system` の Endpoints の watch を張り直すたびに 2 行出した（19 分で 6 行ずつ）。本番の longhorn-manager も 4 つとも同じ形で出す見込み
- **本番の段 4 では**、longhorn-manager v1.11.2 の 4 つ（40 分で 11〜14 行）、prometheus-operator v0.90.1（24 行）、Prometheus v3.11.3 の 2 つ（1.33 の apiserver に替わった直後に 1 行ずつ）が出した（`results/stage-4/summary.md` §2.3）

## 9. 記録

`results/stage-4/` に、ベースライン（`baseline.md`。§2.4 のバックアップ、§2.5 の storage version も）、`install kubernetes`（`control-plane.md`。§3.3 の 13〜18 も）、各台（`<ノード>.md`。control-plane は `192.168.1.11N.md`）、全体のまとめ（`summary.md`。§6 の v1 Endpoints の warning の出どころの表も）を残す。各台の雛形は `results/stage-4/template.md`。
時刻（UTC。control-plane のホストの JST の時刻は直して書く）、読み取りの結果、実行したコマンドと出力の要点、Pod の再起動の有無、iscsid の PID とセッションの前と後、監視の FAIL、leader election で再起動したもの、手順書との差を書く。`tools/node-state.sh` と `snap` の出力、監視のログ（`./stage-4-probe.log`）、`tools/storage-versions.sh` の出力（キーと版だけで値は無い）、`endpoints-warnings.tsv` はタスクディレクトリの `notes/stage-4/` に置き、要点を記録に写す。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（同じ PR か、記録の PR で）。
