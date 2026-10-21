# 段 6 の手順書: K8s を 1.34.12 から 1.35.9 へ上げる（本番 `fraction`）

本番クラスタ `fraction` の Kubernetes を v1.34.12 から v1.35.9 へ上げ、**CoreDNS を v1.12.4 から v1.13.2 へ上げる**手順。porkadot を 0.34.1 から 0.35.0 に替える。etcd（3.6.15）と CNI plugins（v1.9.1）は据え置く。
計画は同じディレクトリの `plan.md`（以下「計画」）の §6（骨子）と §7 の段 6 の行、決まったことは §9 にある。前の段は `runbook-stage-5.md`（以下「段 5 の手順書」）で、この手順書はそれを下敷きにし、**段 5 から変わる点を中心に書く**。段 3〜5 と同じく drain しない。

| | 更新前 | 更新後 |
|---|---|---|
| porkadot | 0.34.1（`060a687`、タグ `v0.34.1`） | **0.35.0**（`e4aa3e6`、タグ `v0.35.0`） |
| kube-apiserver、kube-controller-manager、kube-scheduler、kube-proxy | v1.34.12 | **v1.35.9** |
| kubelet、kubectl（ノードの `/opt/bin`） | v1.34.12 | **v1.35.9** |
| crictl（ノードの `/opt/bin`） | v1.34.0 | **v1.35.0** |
| CoreDNS | v1.12.4 | **v1.13.2**（Corefile・RBAC・引数は変えない） |
| etcd（control-plane の static Pod）、etcdctl・etcdutl（ノードの `/opt/bin`） | 3.6.15-0、3.6.15 | 変えない（マニフェストも変わらない） |
| CNI plugins（ノードの `/opt/cni/bin`） | v1.9.1 | 変えない（版の印が同じなので展開しない） |
| `install-pkgs.sh`、`initiatorname.iscsi` | iscsid は `initiatorname.iscsi` が変わったときだけ再起動 | 変えない |
| cnidaria、MetalLB、kubelet-serving-cert-approver | v0.1.1（init container なし）、v0.14.5、0.12.1 | 変えない（マニフェストの差分が無い） |
| kubelet の `config.yaml`・`kubelet.service` | — | 変えない（`failCgroupV1` は書かない。既定の true のまま） |
| containerd、runc | 段 C の 2.3.6、1.5.1 | 変えない |
| Longhorn | v1.13.0（段 5 の後に 1.11.2 → 1.12.1 → 1.13.0。17 本ともエンジンは v1.13.0） | 変えない（§1.10） |

porkadot 0.35.0 に入った PR は porkadot#56（K8s v1.35.9、crictl v1.35.0、CoreDNS v1.12.4 → v1.13.2（`6d00ac7`）。kubelet の `failCgroupV1` は既定（true）のままにし、文書とテストを足す（`bea90ff`）。etcd 3.6.15-0 は据え置き）と、porkadot#57（版を 0.35.0 にする）。0.34.1 から 0.35.0 の間には Renovate の週ごとのリリースの仕組み（#55。CI と `renovate.json` だけで、render には効かない）も入っている。`etcd backup`・`etcd restore` の実装は 0.34.1 と同じ。

この手順は dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で先に通してある（2026-10-21）。記録は porkadot-dev の `docs/k8s-upgrade/verification-0.35-rc.md`（以下「dev の記録」。porkadot-dev の main `d59be4a`、porkadot-dev#16）。dev は #56 の `bea90ff` で通したもので、0.35.0 との違いは版の番号（#57）だけ。dev で分かったことは次のとおり。

- **1.35 の kubelet に上げても、コンテナは再起動しなかった**（1.32〜1.34 と同じ）。7 台すべてで Pod の UID・restartCount が変わらず、変わったのは control-plane の etcd の static Pod だけ。**iscsid も 7 台とも PID が変わらなかった。** Longhorn v1.13.0 のボリュームをアタッチしたまま `install kubelet` した 2 台で、ボリュームは `attached`・`healthy` のまま、セッションとエンジンも変わらず、書き込みに途切れは無く、detach の後にセッションは残らなかった
- **cgroup v2**: 上げる前に 7 台とも `cgroup2fs`。1.35 の kubelet は 7 台とも起動した（`failCgroupV1` の既定 true で止まらない）
- **`install kubernetes` は 1 回目で rc 0**。apiserver の 3 台の入れ替えに約 2 分半、全部の rollout の完了まで約 4 分。1.35 の scheduler・KCM のログに `Failed to watch` / `failed to list` は 0（1.34 の apiserver の返さない API を待つ形は無かった。apiserver が先に 1.35 になる）
- **CoreDNS は v1.13.2 で 2/2 で起きた**。クラスタ内の名前（A・AAAA）、Service の PTR（v4・v6）、外の名前（A・AAAA）、NXDOMAIN の答えが上げる前と同じ。ログにエラーは無い
- **storage version は変わらない**。1.35 の apiserver の `ResourceEncodingOverrides` は 1.34 のものに `scheduling/workloads`（v1alpha1、既定では出ない）を足しただけで、`overrides.tsv` は空のまま、`OLD` は増えない。FlowSchema も消されない
- **etcd は 3.6.15 のまま 3/3 healthy**。control-plane の `install kubelet` で static Pod が作り直され、最初のコンテナは古い etcd が 2380 番を離す前に起きて `bind: address already in use` で落ち、次で起きる（restartCount 1〜2）
- dev では、`install kubernetes` の直後に etcd のディスクが詰まり API が約 20 秒途切れたことが 1 回あった（7 台の VM が同じホストのディスクを使う dev に特有と見ている。§8.13）
- CSR は 1 つも出なかった。作業端末の kubectl v1.34.12 で 1.35 の server を問題なく使えた。porkadot のコマンドとノードへの `ssh` は、すべて pi のサンドボックスの中で流した

これを受けて、**本番の段 6 でも、どのノードも drain しない**（§2.7）。止める条件は段 5 のまま使う（etcd の static Pod の作り直しは想定どおりとして除く）。

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **arm64 の control-plane での 1.35 の kubelet と CoreDNS v1.13.2**。dev は amd64 の VM。arm64 のイメージとバイナリが配布されていることは確かめてある（§1.7）
- **本番の Longhorn のボリュームがアタッチされたままの `install kubelet`**（2026-10-21 06:1xZ は chirico 9 本、duchamp 4 本、oeilvert 2 本、pablo 1 本）。段 3〜5 の本番では同じ形で問題が無かった。Longhorn v1.13.0 のエンジンでの本番の `install kubelet` は段 6 が初めて
- **ロールバック**（§7）。1.35 → 1.34 の戻しは、どの形も dev で流していない

## 0. 役割と約束ごと

段 5 の手順書 §0 と同じ。違いは次のとおり。

- **承認の節目は 1 つ**（計画 §9.1「本番の各段の開始」。段 6 は etcd のマイナー更新を含まないので、control-plane の kubelet の前の節目は無い）。この手順書では ✋✋ を付けた。
  - ✋✋ **段 6 の開始**: render の差分（§2.6。この手順書と同じ PR）、drain しないこと（§2.7）、cgroup v2 の確認の結果（§2.9）、resolv.conf の読み取りの結果（§2.10）、ベースライン（§2.2）とバックアップ（§2.4）、porkadot 0.35.0 の置き場（§1.4）を見せ、PR をマージしてから、`install kubernetes` を流す前（§3.1）
- **節目の間の手順は、ユーザーに知らせるだけで進めてよい。** etcd のバックアップ、etcd のリーダーの移動、`install kubelet`、`install kubernetes` の流し直し（§3.2）、一時的な DaemonSet・NetworkPolicy の確認（`netcheck.sh`、`npcheck.sh`）は、この手順書に書いた形なら ✋（知らせてから行う操作）で、1 つずつ承認を取るものではない。
- **§8.12 の Completed / Succeeded の Pod の削除は、段の開始の承認の範囲の ✋ とする**（段 5 と同じ。消す前に対象の名前を知らせる）。段 6 には storage version の書き直しは無い（§2.5）。
- **runbook から外れる操作（ロールバック、`etcd restore`、drain への切り替え、想定外の対処、上のほかの Pod の削除、iSCSI のセッションの logout、unattended-upgrades の止め・手での apt の操作）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認は、知らせずに行ってよい。**1 台ずつ行う。** 時刻はすべて UTC で記録する（control-plane のホストの時刻は JST）。

## 1. 前提

### 1.1 段 5 と Longhorn の更新が終わっていること

始める前に次を確かめる。

- 段 5 の完了の確認（段 5 の手順書 §6）が `results/stage-5/summary.md` に残っている
- 段 5 の後の Longhorn の 2 回の更新（`docs/longhorn/runbook-upgrade-1.12-1.13.md`、記録は `docs/longhorn/results/upgrade-1.12-1.13/`）が終わり、`current-longhorn-version` が v1.13.0、17 本とも `status.currentImage` が `longhorn-engine:v1.13.0`
- **Longhorn の片付け（スナップショット `lh1121-pre-*`・`lh1130-pre-*` と、空になる BackupVolume の削除。work-longhorn-cleanup-prod）が終わっている**。段 6 の作業と Longhorn の CR の変更を重ねない（§2.2 の 18 のベースラインと、§7.4 の restore の判断を単純にするため）。終わっていなければ、終わるのを待つ
- 8 台すべてが v1.34.12、CONTAINER-RUNTIME が `containerd://2.3.6`、etcd が 3/3 で 3.6.15（cluster version・storage とも 3.6.0）

2026-10-21 06:1xZ の読み取り（この手順書を書いたとき）:

- 8 台 Ready、全台 v1.34.12、`containerd://2.3.6`。etcd 3/3 が 3.6.15（cluster version・storage とも 3.6.0。3 台の `/version` が `{"etcdserver":"3.6.15","etcdcluster":"3.6.0","storage":"3.6.0"}`）、リーダーは .112（`fbb0c648cf5852a5`）、raft term 23122、DB 55 MB（in use 17 MB）。Pod は 165 個で、Running / Completed 以外は 0 個
- generation: DaemonSet `kube-apiserver` 28、Deployment `kube-controller-manager` 27、`kube-scheduler` 26、DaemonSet `kube-proxy` 24、Deployment `coredns` 11（v1.12.4、2/2。chirico と duchamp）、DaemonSet `cnidaria` 3（`cnidaria-cni:v0.1.1`）。FlowSchema は 11 個
- Longhorn は v1.13.0。ボリュームは 17（attached healthy 16、detached unknown 1 の `homegallery/cg-data`）。アタッチ先は chirico 9、duchamp 4、oeilvert 2、pablo 1（段 5 のときから入れ替わっている。当日に読み直す）
- `tools/storage-versions.sh` は `prefixes: 65, keys: 2550, OLD: 0, CRDs with more than one stored version: 0`、`overrides.tsv` は空。IPAddress 74、Service 79
- 8 台の `tools/node-state.sh`: `/opt/bin` は `kubelet-v1.34.12`、`kubectl-v1.34.12`、`crictl-v1.34.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と 4 つのプラグインは `v1.9.1`。iSCSI と iscsid は §2.7
- 8 台とも `cgroup2fs`（§2.9）。8 台とも kubelet の `resolvConf`（`/run/systemd/resolve/resolv.conf`）に kube-dns の 10.254.0.10 が入っている（§2.10）

### 1.2 kubeconfig の運用

段 5 の手順書 §1.2 と同じ（確認は `fraction-auditor`、変更系は `infra-admin` の 1 時間のトークンと `kubectl-admin`）。

**段 6 で `infra-admin` のトークンを使うのは、§1.9 の NetworkPolicy の確認と、§8.12 の Pod の削除だけ**（`netcheck.sh` はトークンを使わず、cnidaria の手順書の `kadmin.sh` で sops の admin の kubeconfig を使う。段 5 と同じ）。トークンのファイル名は `/tmp/k8u-stage6-admin-token` にする。

### 1.3 SSH

段 5 の手順書 §1.3 と同じ（worker は `ssh yuanying@<IP>`、control-plane は `ssh ubuntu@<IP>`。サンドボックスの中で通る。control-plane には `unset LC_ALL` してから入る）。2026-10-21 にこの手順書を書いたとき、8 台ともサンドボックスの中から `tools/node-state.sh` を流せた。

### 1.4 porkadot の置き場と流し方

**元の clone（`/home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot`）は v0.34.1 のまま**で、v0.35.0 のタグもまだ fetch されていない（2026-10-21）。サンドボックスの中からは、元の clone に書き込めない（`.git` も作業ツリーもサンドボックスの外）。当日に使う 0.35.0 の置き場は、次のどちらかにする。

- **(a) 推奨: タスクディレクトリの独立の clone を使う。** `/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-35-0`。元の clone から `git clone` し、GitHub の `refs/tags/v0.35.0` を fetch して、`e4aa3e6` を detached で checkout してある（origin は `https://github.com/yuanying/porkadot.git`。push しない）。`bundle install` 済み（Ruby 4.0.7）で、2026-10-21 06:09Z にこの clone で §2.6 の render を流した。**元の clone は v0.34.1 のまま残るので、§7 の戻しの porkadot 0.34.1 にそのまま使える**
- (b) 元の clone を v0.35.0 にする。サンドボックスの外の書き込みなので、**ユーザーが行うか、承認を取ってから流す**:

  ```sh
  P=/home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot
  git -C $P fetch origin --tags
  git -C $P checkout v0.35.0                 # e4aa3e6（detached）
  (cd $P && bundle install)
  ```

  この形にすると、§7 の戻しに使う 0.34.1 は別に `/tmp` などへ clone する（段 5 の手順書 §7.1 と同じ形）

どちらの置き場でも、**このリポジトリのルートを cwd にして** 流す。形は段 5 の手順書 §1.4 と同じ。

```sh
P=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-35-0   # (a)。(b) なら元の clone
git -C $P describe --tags          # v0.35.0（lib/porkadot/version.rb も 0.35.0）
cd <このリポジトリの checkout>     # §2.6 の PR をマージした master
BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

以下、この形を `porkadot <サブコマンド>` と書く。

- 始める前に `BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot help` が動くことを確かめる
- 作業ツリーの `assets/` と `porkadot.yaml` に PR の外の変更が無いこと（`git status --short assets porkadot.yaml` が空）。メインの checkout にほかの作業があれば、master の別の worktree を作ってそこで流す
- 段 6 で流す porkadot のコマンドは、`etcd backup`、`install kubernetes --node 192.168.1.111`、`install kubelet --node <ノード>` の 3 つだけ。**`install all`、`--node` なしの `install kubelet` と `install kubernetes`、`render`（特に `render all` と `render certs`）、`setup-node`、`setup-containerd`、`etcd restore`（§7.4 の承認を得たときだけ）は流さない**
- **ノードに入る porkadot のコマンドもサンドボックスの中で流す**（0.35.0 の SSH は 0.34 と同じ）。当日の流す前の確かめ方は段 2 の手順書 §1.4 のスクリプト（`P` を 0.35.0 の置き場にする）。8 台とも hostname を返すこと

### 1.5 etcdctl の使い方

段 5 の手順書 §1.5 と同じ。8 台ともノードの `/opt/bin/etcdctl` は 3.6.15 で、段 6 では変わらない。

### 1.6 render に使った secrets と、本番との突き合わせ

secrets の在りかと扱いは段 1 の手順書 §1.6 と同じ（`assets/` の中に sops の binary 形式で暗号化してある。`assets/secrets.tar.asc` を展開しない。平文をディスクに書かない）。
段 6 の render（§2.6）の前に、同じ形で本番と突き合わせ直した（2026-10-21 06:08Z。読み取りだけ。復号をパイプで流してハッシュだけを比べた。`docs/cni/cnidaria-no-plugin-copy.md` §3 と同じスクリプト）。

| 比べたもの | 本番の側 | 結果 |
|---|---|---|
| `assets/certs/kubernetes/ca.crt` | ConfigMap `default/kube-root-ca.crt` | 一致（SHA-256 `AB:5A:49:9E:…`。段 1〜5 と同じ） |
| `assets/certs/kubernetes/apiserver.crt` | VIP と 192.168.1.111〜113 の 6443 が返す証明書 | 4 つとも一致（`4A:E8:7B:B3:…`） |
| `assets/certs/kubernetes/` の 10 ファイル | .111 の kube-apiserver の Pod（`kube-apiserver-56jg7`）にマウントされた Secret `kube-apiserver` | 10 ファイルとも sha256 が一致 |
| `assets/certs/etcd/{ca.crt,etcd-client.crt,etcd-client.key}` | 同じく Secret `etcd-tls` | 3 ファイルとも一致 |
| `assets/kubelet/192.168.1.11{1,2,3}/addons/etcd/{ca.crt,etcd.crt,etcd.key}`（render の前） | 3 台の `/etc/etcd/pki/` | 9 ファイルとも一致（`etcd.crt` は段 5 の render のもの） |
| CA の鍵と証明書（kubernetes、front-proxy、etcd） | — | 3 組とも公開鍵が一致 |

当日に確かめ直すときの形は段 1 の手順書 §1.6 と同じ。どれかが食い違えば、render の差分も assets も信用せず、止めて調べる。

### 1.7 入れる版を確かめる

作業の当日に確かめ直す（読み取り）。

```sh
curl -fsSL https://dl.k8s.io/release/stable-1.35.txt     # v1.35.9
```

2026-10-21 の時点:

- `stable-1.35.txt` は v1.35.9。`stable.txt` は v1.37.1
- registry.k8s.io の `kube-apiserver`・`kube-controller-manager`・`kube-scheduler`・`kube-proxy` の v1.35.9、`coredns/coredns:v1.13.2`、`etcd:3.6.15-0` は、どれも amd64 と arm64 を含む（manifest list を読んだ）
- `dl.k8s.io` の kubelet と kubectl の v1.35.9（amd64、arm64）、cri-tools の `crictl-v1.35.0-linux-{amd64,arm64}.tar.gz` は、どれも 200 を返す。cri-tools の 1.35 系は v1.35.0 だけ
- etcd 3.6.15 と CNI plugins v1.9.1 はノードに入っているもので、変わらない
- CoreDNS の最新は v1.15.0（v1.14.7 の後に出た）。段 6 は porkadot 0.35.0 の v1.13.2 にする（計画 §2。段 8 で最新を確かめ直す）
- **作業端末の kubectl は v1.34.12**。1.34 にも 1.35 にも ±1 に入る（dev でも v1.34.12 で使えた）

### 1.8 確認に使うスクリプト

段 5 の手順書 §1.8 と同じ（cnidaria の手順書の `verify-nodes.sh`・`netcheck.sh`・`check-apps.sh`、`tools/node-state.sh`、`tools/storage-versions.sh`）。

- **`tools/dns-check.sh` をこの PR で足した**（読み取り）。kube-dns の Service（10.254.0.10）に作業端末から、各 CoreDNS の Pod にノード（既定は pablo）から、同じ問い合わせ（クラスタ内の名前の A・AAAA、Service の IP と Pod の IP の PTR、外の名前の A・AAAA、NXDOMAIN）を流す。Pod の IP は作業端末からは届かないので、Pod への問い合わせはノードの `dig` で流す。§2.2 の 23 と §3.3 の 13 で使う

  ```sh
  docs/k8s-upgrade/tools/dns-check.sh > <ファイル>          # 引数でノードを替えられる（既定は yuanying@192.168.1.134）
  ```

- `tools/node-state.sh`・`tools/storage-versions.sh` は段 5 のまま。1.35 でも `overrides.tsv` は空のまま（dev の見つけたことの 4）
- **cnidaria の手順書の `verify-nodes.sh` は、nft を `cnidaria-cni:v0.1.0` のイメージで流す**（cnidaria-cni-dev の `notes/fraction-runbook/common.sh` の `IMAGE`）。本番の段 6 の当日、oeilvert の containerd からこのイメージが kubelet の image GC で消えていて、oeilvert だけ `FAIL nft table inet cnidaria exists (image nft)`（`ctr: image … not found`）になった（`results/stage-6/baseline.md` §8）。スクリプトを作業端末の `/tmp` に写し、`IMAGE` を今の DaemonSet の `v0.1.1` にして流す（元のスクリプトは別のタスクのものなので書き換えない）

### 1.9 NetworkPolicy の確認（一時的な名前空間） ✋

段 5 の手順書 §1.9 と同じ（`tools/npcheck.sh` と `tools/npcheck.yaml`）。合格は、`up` の後の `nft` が 8 台とも 1 以上、`run` が `OK 56, not OK 0`、`down` の後の `nft` が 8 台とも 0、名前空間 `k8u-npcheck` が NotFound。段 5 の本番では、`up` の後の `nft` は 8 台とも 9 だった。

流すのは、最初の worker の後（§5.5）と、段 6 の完了の確認（§6）。

### 1.10 Longhorn と K8s 1.35

Longhorn v1.13.0 の要件は **Kubernetes >= v1.34**（上流の文書の Installation Requirements「Longhorn requires Kubernetes >= v1.34.」、v1.13.0 の release notes の「Kubernetes v1.34 Minimum Version」。CSI の external-provisioner を v6.3.0 にしたため）。**上限の表明は無い**（文書にも release notes にも、上限や検証した版の一覧は無い。計画 §4.1）。1.35.9 は下限を満たすので、段 6 では Longhorn を変えない。計画 §4.3 の経路 A のとおり、段 6〜8 は 1.13.x で走る。dev の段 6 も Longhorn v1.13.0 で通した。

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 順序 | `install kubernetes --node 192.168.1.111` → rollout の完了 → control-plane の `install kubelet --node` を 1 台ずつ（.113 → .112 → .111）→ worker を 1 台ずつ（§5.1） | 計画 §6.2、dev の記録 |
| 2 | etcd のリーダー | `install kubelet` の前に、対象がリーダーなら `move-leader` で別のメンバーへ移す（etcd の static Pod が作り直されるため） | 計画 §6.2、dev の記録 |
| 3 | drain | **どのノードも drain しない**（§2.7）。**ただし、どの台の後でも、Pod のコンテナの再起動（restartCount の増加、UID の変化。control-plane の etcd の mirror Pod を除く）が 1 つでも出たら止める。** 特に最初の worker と、Longhorn のボリュームが多い台の前に見る。止めた後、残りの Longhorn のノードを drain に切り替えるかはユーザーが決める（§8.10） | dev の記録、段 3〜5 の本番、2026-10-19 のユーザーの方針 |
| 4 | drain の基準 | 「短時間の途切れ」より「Longhorn のボリュームの安全（データ、degraded のまま戻らないこと）」を重く見る。短時間の障害は許容する | 2026-10-19 のユーザーの方針 |
| 5 | iSCSI | **段 6 以降も、各台の `install kubelet` の前と後に `tools/node-state.sh` で iscsid の PID と iSCSI のセッションを見る**。`install kubelet` で iscsid の PID が変わったら止める。古いセッションがあれば止める（§2.7、§5.3）。unattended-upgrades による iscsid の再起動との見分け方は §2.11 | 2026-10-21 のユーザーの判断、Longhorn の手順書 §5.3、計画 §4.4 |
| 6 | cgroup | 上げる前に 8 台で `cgroup2fs` を確かめる。`tmpfs`（cgroup v1）の台があれば止める（§2.9） | 計画 §7 の段 6、dev の記録 |
| 7 | ノードの再起動 | しない | 計画 §9.3 |
| 8 | コンテナの再起動 | 1.35 の kubelet では起きないことを前提にする（§8.4）。control-plane の etcd の static Pod だけは作り直される（restartCount 1〜2 は想定どおり） | dev の記録 |
| 9 | Longhorn の設定 | 変えない | 段 1 の手順書 §2.6 |
| 10 | etcd | 変えない（3.6.15 のまま。マニフェストも変わらない）。control-plane の各台の後に 3/3 healthy、raft index がそろうことを見る | dev の記録 |
| 11 | etcd のバックアップ | 2 回取る: 段の前（`install kubernetes` の前。§2.4）と、`install kubernetes` の後・control-plane の `install kubelet` の前（§4.2） | 計画 §6.1 の 5 |
| 12 | storage version | 書き直しは無い。`install kubernetes` の前と後に `OLD: 0` を確かめる（§2.5） | dev の記録 |
| 13 | CoreDNS | `install kubernetes` で v1.13.2 に rollout する。名前の答えが上げる前と同じことを確かめる（§3.3 の 13） | dev の記録 |
| 14 | Completed / Succeeded の Pod | Running の Pod と同じ Longhorn の PVC を使うものは、`install kubelet` の前に消す（§8.12。段の開始の承認の範囲の ✋。§0） | 段 3 の本番 |
| 15 | v1 Endpoints の warning | 段の更新を止める理由にしない。出どころを記録する（段 4 の手順書 §8.15） | 段 4 の本番 |
| 16 | leader election を使う controller の 1 回の再起動と、gated の LoadBalancer の 1 回の途切れ | 許容する。記録して、Running に戻ったことを確かめる（§8.8） | 段 C、ユーザーの判断 |
| 17 | 停止時間 | いつでもよい。braque は念のためバックアップの CronJob の時間帯を避ける（§5.4）。**unattended-upgrades の時間帯（worker は 06:00〜07:00Z、control-plane は 21:00〜22:00Z）も避ける**（§2.11） | 計画 §9.6 |
| 18 | resolv.conf の kube-dns | 8 台とも CoreDNS の upstream に 10.254.0.10 が入っている（前から）。段 6 は止めない。記録だけ（§2.10） | 指示（2026-10-21） |

### 2.2 クラスタ全体のベースライン

作業の当日、`install kubernetes` の前に次を取り、`results/stage-6/baseline.md` に残す（すべて読み取り）。段 5 の手順書 §2.2 と同じもので、次を読み替える・足す。

- 1: 全台 v1.34.12
- 2: 8 台の `tools/node-state.sh` の出力（ファイルに残す）。`/opt/bin` の向き先が `kubelet-v1.34.12`、`kubectl-v1.34.12`、`crictl-v1.34.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と 4 つのプラグインが `v1.9.1`
- 4: **etcd**: `etcdctl endpoint status --cluster -w table`（版、STORAGE VERSION、DB SIZE、リーダー、raft term・index）と、`-w json` の `header.revision`（§7.4 の restore の revision の目安）、3 台の `/version`、3 台の動いている etcd のフラグ（`--feature-gates=InitialCorruptCheck=true`・`--watch-progress-notify-interval=5s`・`--snapshot-count=10000` があり、`--experimental-` が無い）、3 台の etcd の Pod のログの warning の種類
- 5: **全 Pod の名前・UID・restartCount を控える**（§6 で「増えていない」ことを見る元になる）
- 14: Longhorn の設定（段 5 と同じ項目。v1.13.0 になったので `current-longhorn-version` が v1.13.0）
- 18: Longhorn のボリュームの state・robustness・アタッチ先、replica の置き場所、engine の `currentImage`（17 本とも v1.13.0）
- 20: **storage version**: `tools/storage-versions.sh` の結果。`OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` が空
- 21: Prometheus の `apiserver_requested_deprecated_apis`（読み方は段 4 の手順書 §2.2 の 21）
- 22: Longhorn のボリュームを使う Pod と、同じ PVC を使う Completed / Succeeded の Pod（段 4 の手順書 §2.2 の 22 と同じ）
- 23: **CoreDNS の答え**: `tools/dns-check.sh` の出力（§1.8）。v1.12.4 の答えとして、§3.3 の 13 の比べる元にする
- 24: Service の数と ClusterIP の数、IPAddress の数（2026-10-21 06:1xZ は Service 79 個、IPAddress 74）
- 25: Prometheus の etcd と apiserver のスクレイプ（`count by (job) (up)` の `kube-etcd` が 3、`apiserver` が 3、`count(etcd_server_has_leader)` が 3）
- 26（新）: **cgroup**: 8 台の `stat -fc %T /sys/fs/cgroup`（§2.9）
- 27（新）: **resolv.conf**: 8 台の `/run/systemd/resolve/resolv.conf` の nameserver（§2.10）
- 28（新）: **unattended-upgrades**: 8 台の `apt list --upgradable`、`systemctl list-timers apt-daily-upgrade.timer` の次の時刻、`liblzma5` などの iscsid の使うライブラリが上がる予定か（§2.11）
- 29（新）: FlowSchema の名前と generation（11 個。1.35 では変わらない見込み）

### 2.3 VIP と LoadBalancer、etcd の health を見る

段 5 の手順書 §2.3 と同じ監視を、`install kubernetes` の前から最後の worker の確認まで、作業端末で流しておく（読み取り）。ログは `./stage-6-probe.log` に足していく（`tee -a`）。段 5 の本番では、VIP の FAIL は `install kubernetes` の apiserver の入れ替えの 2 回だけ、LB は 0 回だった。

**etcd の health の 2 秒ごとの監視**（段 5 の手順書 §2.3 の形。ログは `./stage-6-etcd-<IP>.log`）は、**`install kubernetes` の前から control-plane の 3 台目の確認の後まで**流す（dev では `install kubernetes` の直後に etcd が詰まったことがある。§8.13）。止めた後に各ノードで `pgrep -af 'while :'` を見て、残っていれば PID を確かめて kill する（`ssh -n` ではノードの側の while が残る。段 5 の本番）。

### 2.4 etcd のバックアップ（段の前） ✋

`install kubernetes` の前に、porkadot 0.35.0 で取る（計画 §6.1 の 5）。段 5 の手順書 §2.4 と同じ形。

```sh
porkadot etcd backup
ls -l ./backup/
```

- 0.35.0 の `etcd backup` は 0.34.1 と同じ（ノードの `/opt/bin/etcdctl` 3.6.15 の `snapshot save`）
- 手元のファイルは `./backup/etcd-<日時>.db`、モード 0600。`./backup/` は `.gitignore` で除外してある。スナップショットには Secret が平文で入っているので、`git add -f` などで追加しない
- **worktree で流したときは、`./backup/` は worktree の中にできる。** worktree を片付ける前に、coordinator がメインの checkout の `backup/` へ移す（段 1〜5 と同じ）
- 時刻、ファイル名、サイズ、sha256 を記録する。段 5 のバックアップは 3 つとも 55,107,616 バイトだった。桁が違えば止める
- **このバックアップは「段の前」のもの**（1.34 の control-plane、CoreDNS v1.12.4）で、§7.4 の restore の第一の候補になる。段 6 が終わり、健全性を確かめるまで消さない

### 2.5 storage version（書き直しは無い）

段 6 では storage version の書き直しは無い。

1. `install kubernetes` の前（§2.2 の 20）: `tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` が空。**違えば止める**
2. `install kubernetes` の後（§3.3 の 16）: 同じ結果であること。1.35 の apiserver の `ResourceEncodingOverrides`（v1.35.9 の `pkg/kubeapiserver/default_storage_factory_builder.go`）は、1.34 のもの（`leasecandidates`、`mutatingadmissionpolicies`・`…bindings`、`clustertrustbundles`、`podcertificaterequests`、`volumeattributesclasses`、`storagemigrations`、`devicetaintrules`）に `scheduling/workloads`（v1alpha1、既定では出ない）を足しただけで、どれも本番にオブジェクトが無い（dev の見つけたことの 4）。`OLD` が出たら止めて調べる
3. FlowSchema は 11 個のまま（1.34 のように消されるものは無い。dev の見つけたことの 4）

### 2.6 render の差分（この手順書と同じ PR）

計画 §6.1 の 6〜7。2026-10-21 06:09Z に、porkadot 0.35.0（`e4aa3e6`。§1.4 の (a) の独立の clone）で、このリポジトリのルートを cwd にして `render kubelet` / `render etcd` / `render bootstrap` / `render kubernetes` を流した（`render all` と `render certs` は使っていない。4 つとも rc 0）。secrets は §1.6 のとおり本番と一致していることを確かめてから使った。`porkadot.yaml` は変えていない。

前の render は master の `f5873e6` にある（段 5 の porkadot 0.34.1 の render。その後の Longhorn の更新は `assets/` を変えていない）。差分は次の 25 ファイルで、**これ以外の差分は無い**（新しくできたファイル、消えたファイルも無い）。dev の記録の「render の差分」と同じ形。

| ファイル | 変わったもの | 由来 |
|---|---|---|
| `kubernetes/manifests/kube-apiserver.yaml`・`kube-controller-manager.yaml`・`kube-scheduler.yaml`・`kube-proxy.yaml` | イメージ v1.34.12 → v1.35.9、`app.kubernetes.io/version` のラベル | K8s の版（porkadot#56） |
| `kubernetes/manifests/kube-apiserver.secrets.yaml`・`kube-controller-manager.secrets.yaml`（sops） | Secret の `app.kubernetes.io/version` のラベルだけ（`v1.34.12` → `v1.35.9`、3 か所と 1 か所）。data は同じ（HEAD と作業ツリーを復号して、キーごとの sha256 を比べた。13 キーと 3 キー） | 同上 |
| `kubernetes/manifests/porkadot.yaml` | Service `porkadot-kubernetes-latest` の selector の `app.kubernetes.io/version` | 同上 |
| `kubernetes/manifests/addons/coredns/coredns.yaml` | イメージ `coredns:v1.12.4` → `v1.13.2`（1 行） | porkadot#56（`6d00ac7`） |
| `bootstrap/manifests/*.bootstrap.yaml`（4 つ） | イメージ v1.34.12 → v1.35.9、版のラベル | porkadot#56（段 6 では bootstrap は使わない） |
| `kubelet-default/install-deps.sh` | `RELEASE`（kubelet・kubectl）v1.34.12 → v1.35.9、`CRICTL_VER` v1.34.0 → v1.35.0（2 行） | porkadot#56 |
| `kubelet/<8 台>/bootstrap.crt`、`bootstrap/kubelet/bootstrap.crt` | 作り直し（同じ鍵、同じ subject・issuer・SAN・用途、assets の CA で検証が通る。期限が 2027-10-21 06:09Z に延びる） | render のたびに作り直される（§8.2） |
| `kubelet/192.168.1.11{1,2,3}/addons/etcd/etcd.crt`（sops） | 同上（同じ鍵、同じ etcd の CA、同じ subject・SAN） | 同上 |

- `app.kubernetes.io/version` が変わったのは平文のマニフェストで 23 行（dev の記録と同じ数）
- **変わらないもの**: `kubelet/192.168.1.11{1,2,3}/addons/etcd/etcd-server.yaml`（etcd 3.6.15-0 とフラグ）、etcd の `install.sh`・`etcd.env`・`etcd.key`、`kubernetes/install.sh`（0.34 の apiserver を先に入れる形）、`kubelet-default/install-pkgs.sh`・`setup-containerd.sh`、`install-deps.sh` の `ETCD_VER`（3.6.15）と `CNI_VERSION`（v1.9.1）、`kubelet/<ノード>/config.yaml`（`failCgroupV1` は無い）・`kubelet.service`・`bootstrap-kubelet.conf`・`metadata.json`・**`initiatorname.iscsi`**、CoreDNS の Corefile・RBAC・引数、cnidaria（v0.1.1、init container なし）・MetalLB・kubelet-serving-cert-approver のマニフェスト
- Deployment と DaemonSet の `spec.selector` には `app.kubernetes.io/version` が入っていない（段 1〜5 と同じ）
- 作り直した証明書は、作業の当日に render し直すとまた変わる。**当日は render しない**。この PR の `assets/` で流す

確かめ方（読み取り。どれも平文をディスクに書かない）: 平文のマニフェストは `git diff` の `+`・`-` の行を数えた。sops の Secret は、`git show HEAD:<ファイル>` と作業ツリーのファイルを `sops -d` でパイプに流し、data の値を sha256 に置き換えた YAML どうしを diff した。証明書は、HEAD と作業ツリーの公開鍵の sha256、subject・issuer・SAN・keyUsage・extendedKeyUsage、assets の CA での `openssl verify` を比べた。スクリプトと出力はタスクディレクトリの `notes/runbook-stage-6/`。

### 2.7 drain しない理由と、Longhorn・iSCSI の前提

**drain しない理由**（§2.1 の 3）は段 5 の手順書 §2.7 と同じで、段 6 の根拠は次のとおり。

- 1.35 の kubelet でも、dev の 7 台でコンテナが 1 つも再起動しなかった（etcd の static Pod を除く）。drain しないでアタッチしたままの Longhorn v1.13.0 のボリュームは、faulted・remount・I/O エラーにならず、書き込みも途切れなかった（dev の記録の「Longhorn と iSCSI」）
- 0.35.0 の `install-pkgs.sh` は 0.34.1 と同じで、`initiatorname.iscsi` が同じなら iscsid を再起動しない（dev の 7 台で PID が同じ）。この PR の render は `initiatorname.iscsi` を変えていない
- 段 3〜5 の本番でも、drain しないで 8 台を流し、コンテナの再起動・`install kubelet` による iscsid の再起動・古いセッションは 1 つも無かった（`results/stage-3/summary.md`〜`results/stage-5/summary.md`）

**Longhorn のエンジンは直った版になっている**（v1.13.0。計画 §4.4 の直しの go-common-libs `b3e1f44` が入っている）。iscsid が再起動しても、エンジンは iscsid の PID を引き直して logout できる（Longhorn の手順書 §5.3、porkadot-dev の Longhorn の検証）。Longhorn の手順書 §5.3 は「段 6 以降の手順書では、iscsid の PID の確認を止める条件から外してよい」としたが、**ユーザーは 2026-10-21 に、段 6 以降も iscsid と iSCSI のセッションの確認を続けると決めた**（TASK.md の現在地）。この手順書では次のとおりにする。

- 各台の `install kubelet` の前と後に `tools/node-state.sh` を取り、iscsid の MainPID・ActiveEnterTimestamp、セッション（sid・portal・target）、エンジンの起動の時刻を比べる
- **`install kubelet` の間に iscsid の PID が変わったら止めて報告する**（0.35.0 の `install-pkgs.sh` は再起動しないはずなので、変われば想定外）。前に変わっていた（§2.11 の unattended-upgrades など）ものは、前の `node-state.sh` との比べで分かる
- 古いセッション（そのノードの今の instance-manager の IP でない portal へのもの）があれば止める
- `older-than-iscsid` のエンジン（iscsid が後から再起動したもの）は、エンジンが v1.13.0 なら止める理由にしない。数を記録する

**各ノードの iSCSI と Longhorn**（2026-10-21 06:11Z の `tools/node-state.sh`。当日に読み直す）:

| ノード | iscsid の MainPID（起動の時刻） | Longhorn のセッション（portal） | `older-than-iscsid` のエンジン |
|---|---|---|---|
| 192.168.1.111 | 90734（2026-10-19 07:31:09Z） | 0 | — |
| 192.168.1.112 | 89578（2026-10-19 07:27:57Z） | 0 | — |
| 192.168.1.113 | **290821（2026-10-20 21:30:04Z。unattended-upgrades。§2.11）** | 0 | — |
| braque | 85966（2026-10-19 08:06:03Z） | 0 | — |
| chirico | 4447（2026-10-19 09:17:30Z） | 9（10.244.8.216 と 10.244.8.60） | 0 |
| duchamp | **2695716（2026-10-21 06:08:00Z。unattended-upgrades。§2.11）** | 4（10.244.5.186） | **4**（iscsid の再起動の前に起動したもの） |
| oeilvert | 6334（2026-10-19 09:04:34Z） | 2 | 0 |
| pablo | 1194943（2026-10-19 07:39:11Z） | 1（10.244.4.131） | 0 |

- portal はどれもそのノードの今の instance-manager の IP で、古いセッションは無い
- 8 台の `/etc/iscsi/initiatorname.iscsi` の md5 は、どれもこの PR の `assets/kubelet/<ノード>/initiatorname.iscsi` と同じ（この PR の render は変えていない）
- Longhorn のボリュームのアタッチ先: chirico 9、duchamp 4、oeilvert 2、pablo 1。段 5 のとき（chirico 10、oeilvert 5、pablo 1）から入れ替わっている。replica 1 のボリューム（`prometheus-…-0`・`-1`）の置き場所は当日に読み直す

### 2.8 MetalLB の告知ノードを読む

段 5 の手順書 §2.8 と同じ読み方。段 5 の完了の確認（`results/stage-5/summary.md` §2）では、VIP pablo、gated-v4 chirico、gated-v6 oeilvert、`::131`・`::134` .112、`::132` .111、`::133` duchamp だった。当日に読み直す。

### 2.9 cgroup v2 の確認

**1.35 の kubelet は cgroup v1 のノードでは起動しない**（KubeletConfiguration の `failCgroupV1` の既定が true。porkadot 0.35.0 はこれを書かず、既定のまま。porkadot#56 の `bea90ff`）。8 台で読み取りで確かめる。

```sh
for h in ubuntu@192.168.1.111 ubuntu@192.168.1.112 ubuntu@192.168.1.113 yuanying@192.168.1.131 yuanying@192.168.1.83 yuanying@192.168.1.135 yuanying@192.168.1.82 yuanying@192.168.1.134; do
  echo "$h $(ssh -n $h 'stat -fc %T /sys/fs/cgroup; grep -o "systemd.unified_cgroup_hierarchy[^ ]*" /proc/cmdline || echo none' | tr '\n' ' ')"
done
```

**合格**: 8 台とも `cgroup2fs`。**`tmpfs` の台があれば止める**（その台の kubelet は 1.35 で起きない。`kubernetes.kubelet.config` で `failCgroupV1: false` を渡すこともできるが、porkadot.yaml を変えて render し直すことになるので、その時点でユーザーと決める）。

2026-10-21 06:1xZ の結果: **8 台とも `cgroup2fs`**。systemd は 8 台とも 255（255.4-1ubuntu8.18）、kernel の引数に `systemd.unified_cgroup_hierarchy` は無い（Ubuntu 24.04 の既定。計画 §7 の 2026-10-18 の調査と同じ）。当日、§3.1 の承認の前に流し直す。

### 2.10 CoreDNS の upstream の resolv.conf（読み取り）

CoreDNS の Pod は `dnsPolicy: Default` で、kubelet の `resolvConf`（本番の 8 台とも `/run/systemd/resolve/resolv.conf`。`/var/lib/kubelet/config.yaml`）を `/etc/resolv.conf` として受け取り、Corefile の `forward . /etc/resolv.conf` でそこへ転送する。dev では、この resolv.conf に kube-dns 自身（dev の 10.252.0.10）が入っていた（タスクの `notes/backlog.md`、2026-10-21）。

本番の 8 台を読み取りで確かめた（2026-10-21 06:1xZ）。

```sh
ssh -n <ノード> 'grep -h "^resolvConf" /var/lib/kubelet/config.yaml; grep -v "^#" /run/systemd/resolve/resolv.conf | grep -v "^$"'
```

| ノード | `/run/systemd/resolve/resolv.conf` の nameserver（並び順） |
|---|---|
| 192.168.1.111、braque、pablo | 192.168.0.1、2405:6581:8580:301::1、**10.254.0.10** |
| 192.168.1.112、192.168.1.113、chirico、duchamp | **10.254.0.10**、192.168.0.1、2405:6581:8580:301::1 |
| oeilvert | 192.168.0.1、**10.254.0.10**、192.168.0.1 |

- **8 台とも、kube-dns の Service の IP（本番は 10.254.0.10）が入っている**。dev と同じ形で、出どころは porkadot の `dns` の addon（`assets/kubelet-default/addons/dns/install.sh`）。`porka-dummy01` の link に `resolvectl dns porka-dummy01 10.254.0.10` と `resolvectl domain … cluster.local` を設定するので、systemd-resolved がそれを `/run/systemd/resolve/resolv.conf` に並べる。ノード自身が `cluster.local` を引くための設定で、CoreDNS の upstream にも入ってしまう
- 今の CoreDNS の 2 つの Pod は chirico と duchamp にあり、どちらも 10.254.0.10 が先頭。`forward` の既定の policy は random なので、外の名前の問い合わせの一部は kube-dns（自分か、もう 1 つの CoreDNS）へ回る
- 2026-10-21 06:1xZ の CoreDNS（v1.12.4）の 2 つの Pod のログに `loop`・`[ERROR]`・`[WARNING]` は無く、restartCount は 0。§2.2 の 23 の答え（外の名前、NXDOMAIN を含む）は正しい
- **前からのもので、段 6 は止めない。** 記録して、§3.3 の 13 で v1.13.2 でも答えが同じこと、CoreDNS のログに `loop` が出ないことを見る。直すなら porkadot の側（CoreDNS の `forward` の先を `/etc/resolv.conf` 以外にする、または `porka-dummy01` の DNS を resolv.conf に載せない形にする）で、段 6 の範囲の外（申し送り）

### 2.11 unattended-upgrades による iscsid の再起動

2026-10-21 の読み取りで、unattended-upgrades が **iscsid を再起動していた**ことが分かった。`liblzma5`・`xz-utils` が 5.4.5-1ubuntu0.3 → 0.4 に上がった直後に、needrestart（8 台とも入っている。`/etc/needrestart/needrestart.conf` の既定で、unattended-upgrades の中では自動で再起動する）が、そのライブラリを使う iscsid（`ldd /usr/sbin/iscsid` に liblzma がある）、systemd-networkd、systemd-resolved などを `systemctl restart` した。

- .113: 2026-10-20 21:30:04Z（JST 10-21 06:30）。`/var/log/unattended-upgrades/unattended-upgrades-dpkg.log` に `systemctl restart iscsid.service … systemd-networkd.service systemd-resolved.service …`
- duchamp: 2026-10-21 06:08:00Z。アタッチされたボリュームが 4 本あり、iscsid が既存の 4 つのセッションを `operational after recovery` で引き取った。エンジンは 4 つとも `older-than-iscsid` になった。ボリュームは attached healthy のまま
- ほかの 6 台は、2026-10-21 06:1xZ の時点で liblzma5 が 0.3 のままで、次の unattended-upgrades で同じく iscsid が再起動する見込み（`unattended-upgrades-dpkg.log` に `NEEDRESTART-SVC: iscsid.service` が前からある）

open-iscsi の hold（`51fraction-hold-open-iscsi`）は 2026-10-21 に消した（Longhorn の手順書 §5.3）が、これは open-iscsi の更新ではなく、**ライブラリの更新による needrestart の再起動**なので、hold があっても起きていた。

**段 6 への効き方**:

- 段 6 の作業の途中に unattended-upgrades が流れると、`install kubelet` の前と後の `node-state.sh` の間に iscsid の PID が変わりうる。**作業は unattended-upgrades の時間帯を避ける**: `apt-daily-upgrade.timer` は 06:00 + 最大 60 分（`RandomizedDelaySec=60m`）。worker はホストの時刻が UTC なので **06:00〜07:00Z**、control-plane は JST なので **21:00〜22:00Z**。当日は §2.2 の 28 で各台の次の時刻を読み、作業の時間と重ならないことを確かめる
- 1 台の前と後の間に iscsid の PID が変わったときは、止めてから、`journalctl -u iscsid`、`/var/log/apt/history.log`、`/var/log/unattended-upgrades/unattended-upgrades-dpkg.log` を見て、**porkadot の `install kubelet` によるものか（`install-pkgs.sh` の出力と時刻）、unattended-upgrades の needrestart によるものか**を記録して報告する。続けるかはユーザーが決める（エンジンは v1.13.0 なので、needrestart によるものなら、セッションが今の instance-manager の IP のままでボリュームが healthy であることを確かめて続ける見込み）
- systemd-networkd の再起動は、cnidaria の `no route` のログ（§8.1）と同じものを出しうる。監視の FAIL と突き合わせるときに見る
- 本番の段 6 では、`install kubelet` の後に `apt-daily-upgrade.timer` の次の時刻が 8 台とも引き直されていた（`install kubelet` の `daemon-reload` で、systemd がランダムな遅れを選び直したものと見ている）。時間帯（06:00〜07:00 のホストの時刻）は変わらないが、作業の前に読んだ「次の時刻」は当てにしない（`results/stage-6/summary.md` §2.3）
- unattended-upgrades を止める・apt を手で流すのは、runbook の外の操作（§0）。段 6 では止めない

## 3. control-plane のマニフェストを上げる（`install kubernetes`）

### 3.1 事前確認

✋✋ **段 6 の開始の承認を取る。** §2.6 の表と PR の差分、§2.7 の drain しない理由と止める条件、§2.9 の cgroup v2 の確認の結果、§2.10 の resolv.conf の読み取りの結果、§2.11 の unattended-upgrades の時刻、§2.2 のベースライン（22 の Completed の Pod で消すもの、§0）、§2.4 のバックアップ、§2.8 の告知ノード、§1.4 の porkadot の置き場、§7 のロールバックの形を示す。承認を得て PR をマージし、マージした master で §3.2 に入る。

- §2.2 のベースライン、§2.4 のバックアップ、§2.9 の cgroup の確認が済んでいる。§2.3 の監視（VIP と LoadBalancer、etcd の health）が動いている
- `tools/storage-versions.sh` が `OLD: 0`（§2.5 の 1）
- 全台 Ready、etcd 3/3 healthy、VIP の `/readyz` が `ok`
- checkout が §2.6 の PR をマージした master で、`git status --short assets porkadot.yaml` が空
- §1.4 の SSH の確かめで 8 台とも通る。`git -C $P describe --tags` が `v0.35.0`
- 作業の時間が §2.11 の unattended-upgrades の時間帯と重ならない

### 3.2 流す ✋

```sh
porkadot install kubernetes --node 192.168.1.111
```

- **`--node` を必ず付ける。** 付けないと bootstrap ノード（pablo）で `kubectl apply` を流し、`127.0.0.1:6443` に届かず rc 1 になる
- **0.35 の `install kubernetes` は 0.34 と同じ 2 段で流れる**（`assets/kubernetes/install.sh` は変わらない。段 5 の手順書 §3.2）: CRD と kube-apiserver のもの（DaemonSet `kube-apiserver`、Service `porkadot-kubernetes`・`porkadot-kubernetes-latest` など）を先に apply し、DaemonSet `kube-apiserver` の rollout の完了を 5 秒ごとに見て待ち（`--apiserver-timeout`、既定 600 秒。完了するとログに `daemon set "kube-apiserver" successfully rolled out`）、全体を apply する。KCM・scheduler・kube-proxy が v1.35.9 で、**CoreDNS が v1.13.2 で** rollout する。kubelet-serving-cert-approver・cnidaria・MetalLB はマニフェストが変わらないので動かない
- 本番の段 5 では、apiserver の 3 台の入れ替えが約 2 分 10 秒（1 台約 50 秒）、全体で約 3 分（09:11:14Z → 09:14:19Z、rc 0）、VIP の FAIL は 2 回だった。dev の段 6 では apiserver の入れ替えに約 2 分半、全部の rollout の完了まで約 4 分
- 時刻と rc を記録する。ログの `successfully rolled out` の時刻と、その後の `configured` の行を記録する
- rc 1 のときの扱い（`The kube-apiserver rollout did not finish in 600s`、`dial tcp 127.0.0.1:6443: connect: connection refused`、ほかのエラー）は段 5 の手順書 §3.2 と同じ
- **0.34.1 以前の porkadot で 1.35 に上げない**（0.34.1 の render では 1.34.12 になるので、そもそも上がらない。0.35.0 の置き場を §1.4 で確かめる）

### 3.3 rollout の完了を確かめる

段 5 の手順書 §3.3 と同じ（版を v1.35.9 に読み替える）。CoreDNS の項目を替え、storage version と FlowSchema を段 6 の期待値にする。

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
| 1〜12 | 段 1 の手順書 §3.3 の 1〜12 | 同じ。Server が v1.35.9、apiserver・KCM・scheduler・kube-proxy が v1.35.9。Node は 8 台 Ready で kubelet は v1.34.12 のまま（apiserver 1.35 と kubelet 1.34 は skew policy の範囲）。DaemonSet `kube-apiserver` の generation が 1 つ増える（2026-10-21 は 28）。**KCM と scheduler のログに `Failed to watch`・`failed to list` が続いていない**（dev は 0。入れ替わりの直後の数行は想定内） |
| 13 | CoreDNS | **v1.13.2 に rollout する**。Deployment `coredns` の generation が 1 つ増える（2026-10-21 は 11）、2/2、Pod のイメージが `registry.k8s.io/coredns/coredns:v1.13.2`。2 つの Pod のログに `CoreDNS-1.13.2`（`linux/arm64` か `linux/amd64`）があり、`[ERROR]`・`[WARNING]`・`loop` の行が無い。古い v1.12.4 の Pod は消える。**`tools/dns-check.sh` の答えが §2.2 の 23 と同じ**（下） |
| 14 | approver | `kubelet-serving-cert-approver` が `0.12.1` のまま 1/1。generation が変わらない |
| 15 | CSR | 新しい CSR が無い（段 4 の手順書 §3.3 の 15） |
| 16 | storage version | `tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` が空のまま（§2.5 の 2）。`/registry/ipaddresses/` と `/registry/servicecidrs/` が `networking.k8s.io/v1` の `ok` |
| 17 | ServiceCIDR と IPAddress | `servicecidrs` に `kubernetes` が 1 つで Ready、CIDRS が `10.254.0.0/24,fd20:afc2:7c09::/108`。IPAddress の数が §2.2 の 24 の数。`ClusterIPNotAllocated` の event が出ない |
| 18 | v1 Endpoints の warning | 段 4 の手順書 §3.3 の 18 と同じ（記録だけ。`removed_release` が `1.35` 以前のものが出ていないこと） |
| 19 | FlowSchema | §2.2 の 29 と同じ 11 個。generation が変わっていれば記録する |

13 の名前の答え（§1.8 の `tools/dns-check.sh`。2026-10-21 06:18Z の v1.12.4 の答え。Service と 2 つの Pod で同じ）:

| 問い合わせ | v1.12.4（§2.2 の 23） | v1.13.2 の合格 |
|---|---|---|
| `kubernetes.default.svc.cluster.local` A、`kubernetes.default.svc.fraction.cluster` A | `10.254.0.1` | 同じ |
| `kubernetes.default.svc.cluster.local` AAAA | 空の NOERROR（single-stack の Service） | 同じ |
| `h2.fs.svc.cluster.local` A・AAAA（dual-stack） | `10.254.0.170`、`fd20:afc2:7c09::521` | 同じ |
| PTR `10.254.0.1`、`10.254.0.10`、`fd20:afc2:7c09::521` | `kubernetes.default.svc.cluster.local.`、`kube-dns.kube-system.svc.cluster.local.`、`h2.fs.svc.cluster.local.` | 同じ |
| PTR の kube-dns の Endpoint の Pod の IP | `<IP>.kube-dns.kube-system.svc.cluster.local.` と `<IP>.kube-prometheus-coredns.kube-system.svc.cluster.local.` | 同じ形（Pod の IP は新しい Pod のものに替わる） |
| PTR の `fs/h2` の Endpoint の Pod の IP（v4・v6） | `….h2.fs.svc.cluster.local.`（v6 は `….h2-sshd.fs…` も） | 同じ |
| `www.google.com` A・AAAA、`github.com` A | 外のアドレス | 外のアドレス（並びと値は変わってよい） |
| `no-such-name.example.invalid`、`no-such-svc.default.svc.cluster.local` | NXDOMAIN | 同じ |

- CoreDNS v1.13.0 の「SERVFAIL・REFUSED のときに次の upstream へ切り替える」は、`forward` の `failover` を書いたときだけ働く（coredns/coredns#7458）。porkadot の Corefile は `forward . /etc/resolv.conf` だけなので、振る舞いは変わらない（dev の見つけたことの 1）。§2.10 の resolv.conf の形でも同じ
- CoreDNS の入れ替えの間（新しい Pod の Ready まで数秒）に、名前の問い合わせが 1〜2 回失敗するのは想定内（Deployment の rolling update。dev では途切れを見ていない）
- `install kubernetes` の出力の `configured` に、マニフェストの変わらない `poddisruptionbudget.policy/kube-controller-manager`・`kube-scheduler`、`validatingwebhookconfiguration…/metallb-webhook-configuration` が出るのは前から（段 5 の本番）。generation が変わらなければ想定内
- apiserver の rollout の途中に、controller-manager の `FailedToUpdateEndpoint` などが 1 回ずつ出ることがある（段 4 の手順書 §3.3 の注）。続かなければ想定内
- **`install kubernetes` の直後（全体の apply の後の 1 分ほど）に etcd の health と VIP を特に見る**（dev の見つけたことの 2。§8.13）
- ここで問題があれば、kubelet にまだ触っていないので、§7.2 で control-plane だけを戻せる

## 4. control-plane の kubelet を上げる（192.168.1.113 → .112 → .111）

### 4.1 何が起きるか

`install kubelet --node <IP>` は、`install-deps.sh`（kubelet・kubectl・crictl を落として張り替える。etcd の tarball は版が同じなので落とさない、CNI plugins は版の印が v1.9.1 で同じなので展開しない）、`install-pkgs.sh`（`apt-get install --no-upgrade`、iscsid は `systemctl start` だけ）、`install.sh`（addon の `dns`、`multipathd`、`etcd`）を root で流し、kubelet を v1.35.9 で再起動する。

- **etcd は 3.6.15 のまま**（`etcd-server.yaml` は変わらない）。ただし `etcd` の addon がマニフェストを置き直し、新しい kubelet が etcd の mirror Pod を作り直す（1.32〜1.35 と同じ。dev の見つけたことの 3）。最初のコンテナは古い etcd が 2380 番を離す前に起きて `bind: address already in use` で落ち、次で起きる（dev は .113 と .112 が restartCount 1、.111 が 2 で 10 秒の CrashLoopBackOff を挟み、etcd が止まっていたのは約 11 秒）。その間ほかの 2 台で quorum を保つ
- `/etc/etcd/pki` の証明書と鍵を root 0600 で置き直す。`etcd.crt` は作り直したもの（同じ鍵、同じ CA。§2.6）に替わる
- `dns` の addon は `systemd-networkd` を再起動するので、cnidaria の `no route` のログが出る（§8.1）
- control-plane には Longhorn のボリュームが無く、iscsid は動いていてセッションは無い（§2.7）

### 4.2 2 つ目のバックアップ

1. ✋ etcd のバックアップを取る（§2.4 と同じ形）。**1.35 の control-plane、CoreDNS v1.13.2、kubelet はまだ 1.34** の状態。§7.4 の restore で、段の前（§2.4）の代わりに使える
2. 承認の節目は無い（§0）。§3.3 が合格なら、そのまま §4.3 に入る

### 4.3 1 台の手順

段 5 の手順書 §4.3 と同じ（1. 読み取りの確認と `snap`・`tools/node-state.sh` の控え、2. ✋ リーダーなら `move-leader`、3. ✋ `porkadot install kubelet --node <IP>`、4. kubelet の起動から 1 分ほど待って §4.4）。

- 2026-10-21 のリーダーは .112（`fbb0c648cf5852a5`）。このままなら、.112 の作業の前に .111（`21ab2aeb56731588`）か .113（`57ec6f12ac7b683e`）へ移し、.111 の作業の前にリーダーが .111 なら .112 か .113 へ移す
- 1 台ずつ、§4.4 の確認が済んだら次の台に入る（段 5 のように混在を短くする理由は無いが、間を空ける理由も無い）
- 段 5 の本番では 1 台 27 秒〜47 秒だった（etcd の tarball を含む）。段 6 は etcd の tarball を落とさないので、同じか短い見込み

### 4.4 1 台ごとの確認と、次の 1 台へ進む条件

段 5 の手順書 §4.4 と同じ。次を読み替える。

| # | 確認 | 合格基準（段 5 から変わるところ） |
|---|---|---|
| 1 | Node | VERSION が v1.35.9。kubelet が起きている（cgroup v1 で起きないときは `failCgroupV1` のエラーを journal に出して起きない。§2.9） |
| 2 | バイナリ | 向き先が `kubelet-v1.35.9`、`kubectl-v1.35.9`、`crictl-v1.35.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`（変わらない）。CNI の印と 4 つのプラグインは `v1.9.1` のまま。前の版のファイル（`kubelet-v1.34.12` など）も残っている（§7 の戻しで使う） |
| 4 | etcd | 3/3 healthy、リーダーが居る、raft index がそろう。3 台とも 3.6.15。`member list -w table` が 3 つとも `started` |
| 5 | etcd の Pod | 1/1 Running、`etcd:3.6.15-0`。mirror Pod の UID が変わる。**restartCount 1〜2 は想定どおり**（`bind: address already in use` の 1〜2 回。§4.1）。3 以上、または CrashLoopBackOff が 1 分を超えたら止める |
| 7 | Pod の再起動 | **差分は `kube-system/etcd-<IP>` の UID と restartCount だけ**。ほかに UID・restartCount が変わったものがあれば止める |
| 8 | iscsid | MainPID と ActiveEnterTimestamp が前（§4.3 の 1 の `node-state.sh`）と同じ。変わっていたら止める（§2.7、§2.11） |
| 16 | etcd の版 | 3 台の `/version` が `{"etcdserver":"3.6.15","etcdcluster":"3.6.0","storage":"3.6.0"}` のまま |
| 17 | etcd のフラグ | 段 5 の手順書 §4.4 の 17 と同じ（`--feature-gates=InitialCorruptCheck=true`、`--watch-progress-notify-interval=5s`、`--snapshot-count=10000`、`--experimental-` が無い） |
| 18 | etcd のログ | 想定どおりのもの: 起き直しの直後の `bind: address already in use`（落ちたコンテナ）、ほかのメンバーの `lost TCP streaming connection`・`peer became inactive`（数秒）、前から出ている `check file permission`・`Running http and grpc server on single port`・`simple token is not cryptographically signed`。新しいコンテナの起動の直後の `failed to publish local member to cluster through raft`（同じミリ秒の間に数回。段 5 の手順書 §4.1）と、追いつく間の `request stats`・`apply request took too long`・`waiting for ReadIndex response took too long`・`ignored out-of-date read index response`（本番の段 6 の .112）。3.5 との混在のものは出ない。ほかの warn・error の種類が増えたら記録し、続くものがあれば止める |

次の 1 台へ進む条件も段 5 の手順書 §4.4 と同じ（すべて合格、全 8 台 Ready、etcd 3/3 healthy で raft index がそろう、Running / Completed 以外の Pod がベースラインから増えていない）。

- 1 台の kubelet が 1.35 で起きないときは、その台の Node が NotReady になり、etcd の static Pod も起き直さないことがある（etcd は前のコンテナのまま動いていることもある）。**次の台に進まず、止めて報告する**（§7.6 で、その台を 1.34 に戻すかをユーザーが決める）

### 4.5 control-plane の 3 台の後

- 3 台の `/version` と `etcdctl endpoint status --cluster -w table` が §2.2 の 4 と同じ版（3.6.15、3.6.0）で、リーダーが居る
- §2.3 の etcd の health の監視を止める（ノードの側の while も止める）

## 5. worker の kubelet を上げる（1 台ずつ、drain しない）

### 5.1 順番

アタッチされた Longhorn のボリュームが少ない台から多い台へ並べる（段 5 の手順書 §5.1 と同じ考え方）。2026-10-21 06:1xZ のアタッチの数（pablo 1、oeilvert 2、duchamp 4、chirico 9）からは、**pablo → braque → oeilvert → duchamp → chirico** にする。当日の読み取りでアタッチの数が変わっていれば並べ直してよい。braque はどこに入れてもよい（§5.4 の時間帯を避ける）。

- 最初の worker の pablo は API の VIP を告知している（段 5 の完了の確認）。段 5 の本番では pablo の `install kubelet` の間も VIP は途切れなかった
- worker には etcd が無い。`/opt/bin` の etcdctl と etcdutl は 3.6.15 のまま

### 5.2 1 台の手順

段 5 の手順書 §5.2 と同じ（§8.12 の Pod の削除も同じ扱い）。段 5 の本番では 1 台 23 秒〜39 秒だった。

### 5.3 1 台ごとの確認

段 5 の手順書 §5.3 と同じ。次を読み替える。

| # | 確認 | 合格基準（段 5 から変わるところ） |
|---|---|---|
| 1 | Node | VERSION が v1.35.9 |
| 2 | バイナリ | 向き先が `kubelet-v1.35.9`、`kubectl-v1.35.9`、`crictl-v1.35.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と 4 つのプラグインは `v1.9.1` のまま。`kubelet-v1.34.12` なども残っている |
| 3 | iscsid | **MainPID と ActiveEnterTimestamp が前と同じ**。変わっていたら止める（§2.7、§2.11） |
| 4 | iSCSI のセッション | 同じ sid・portal・target。portal がそのノードの今の instance-manager の IP。古いセッションが無い |
| 5 | エンジン | 同じボリューム、同じ起動の時刻。`older-than-iscsid` の数が前と同じ |
| 7 | Pod の再起動 | **差分が無い**（名前・UID・restartCount が同じ）。1 つでもコンテナの再起動があれば、ここで止めて報告する（§2.1 の 3） |

ほか（Longhorn の node の一瞬の `is down`・`Waiting for disk`、`FailedMount` の `no Pending workload pods`）は段 5 の手順書 §5.3 と同じ。

### 5.4 braque の手順

段 5 の手順書 §5.4 と同じ（バックアップの CronJob の時間帯を避ける）。

### 5.5 次の 1 台へ進む条件

段 5 の手順書 §5.5 と同じ（版を読み替える。終えたノードが v1.35.9、まだのノードが v1.34.12）。

- **最初の worker（pablo）の後に、✋ `netcheck.sh` と §1.9 の NetworkPolicy の確認を流す**（1.35 の apiserver と、1.35 の kubelet のノードを含む形で、cnidaria の NetworkPolicy の処理が動くこと）

## 6. 段 6 の完了の確認

8 台を終えたら、計画 §6.3 の項目がすべて成り立つことを確かめ、`results/stage-6/summary.md` に残す。段 5 の手順書 §6 と同じ項目で、次を読み替える・足す。

- 8 台が Ready、全台 v1.35.9、CONTAINER-RUNTIME が `containerd://2.3.6`。どのノードも SchedulingDisabled でない
- 8 台の `/opt/bin` が `kubelet-v1.35.9`、`kubectl-v1.35.9`、`crictl-v1.35.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と 4 つのプラグインが `v1.9.1`
- **etcd**: 3/3 healthy、全メンバーが 3.6.15、cluster version・storage とも 3.6.0、リーダーが居る、raft index がそろう。3 台の動いている etcd のフラグに `--experimental-` が無い。3 台の `/etc/etcd/pki` が `600 root:root`
- VIP の `/livez` が `ok`、`/version` が v1.35.9
- **CoreDNS が v1.13.2 で 2/2 Running**。ログにエラーと `loop` が無い。`tools/dns-check.sh` をもう一度流し、§2.2 の 23 と同じ答え
- **全 Pod の restartCount が、ベースライン（§2.2 の 5）から増えていない**（control-plane の etcd の mirror Pod は UID が変わり restartCount 1〜2。`install kubernetes` で作り直された Pod（apiserver 3、KCM 2、scheduler 2、kube-proxy 8、CoreDNS 2）は新しい UID で 0）
- **storage version**: `tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` が空
- **ServiceCIDR と IPAddress**: `servicecidrs` が `kubernetes` の 1 つで Ready、IPAddress の数が ClusterIP の数と同じ。FlowSchema が 11 個
- **cgroup**: 8 台とも `cgroup2fs` のまま、kubelet が 8 台とも動いている
- Longhorn、Longhorn の設定、iSCSI（8 台の iscsid の PID とセッションがベースラインと同じか、変わったものは §2.11 の見分けの結果）、cnidaria（✋ `netcheck.sh`、✋ §1.9 の NetworkPolicy の確認）、MetalLB、braque の NFS、`registry.fraction.jp`、CSR、§2.3 の監視の FAIL、leader election で再起動した controller: 段 5 の手順書 §6 と同じ。**K8s 1.35 は Longhorn v1.13.0 の要件（1.34 以上）に入る**（§1.10）
- `kubectl --context fraction top nodes` が応答し、Prometheus のスクレイプが落ちていない（`up == 0` が 0 個。`kube-etcd` の 3 つを含む）。`count(etcd_server_has_leader)` が 3
- `apiserver_requested_deprecated_apis` を記録する（`removed_release` が `1.35` 以前のものが出ていれば止めて調べる）。v1 Endpoints の warning の出どころも段 5 と同じ形で記録する（段 5 では longhorn-manager v1.11.2 と prometheus-operator。Longhorn は v1.13.0 になったので、出なくなっているかを見る）
- kubelet の起動時の warning は `Flag --container-runtime-endpoint has been deprecated` のほかに増えていない（計画 §10 の KubeletConfiguration への移行の対象。段 8 で直す）
- 新しい warning のイベント・ログ（kubelet、apiserver、kube-proxy、cnidaria、etcd、Longhorn、CoreDNS）が増えていない（§8 のもの、v1 Endpoints の warning は除く）
- etcd のバックアップ（§2.4、§4.2 の 2 つ）を worktree からメインの checkout の `backup/` へ移した（worktree で流した場合。coordinator）

## 7. ロールバック

**戻すのは runbook から外れる操作なので、その都度ユーザーの承認を取る。** 戻すと決める目安は段 1 の手順書 §7 と同じ（rollout が終わらない、VIP が 1 分を超えて応答しない、Node が 5 分たっても Ready にならない、etcd が 2/3 を下回る、Pod の再起動が続く、Longhorn のボリュームが degraded のまま戻らない、1.35 や CoreDNS v1.13.2 に固有と見られる問題）。

**段 6 は etcd を変えないので、戻し方は段 3・段 4 の形に近い**（etcd のデータの版の制約が無い）。**ただし、どの形も dev で流していない**（dev の記録の「本番の段 6 の runbook に効くこと」）。

| どこまで進んだか | 戻し方 | dev で確かめたか |
|---|---|---|
| `install kubernetes` の後（kubelet はまだ 1.34） | §7.2（0.34.1 で `install kubernetes`） | 確かめていない |
| control-plane・worker の kubelet の途中・全部の後 | kubelet を §7.3 で 1.34 に戻してから（新しい順に）、§7.2 で control-plane を戻す | 確かめていない |
| どの時点でも（最後の手段） | §7.4 の `etcd restore`（段の前か §4.2 の backup） | restore そのものは段 5 の dev で確かめた（0.34.1。0.35.0 は同じ実装）。1.35 からの restore は確かめていない |

### 7.1 戻すための材料

- **前の版**: この PR の前の master（`f5873e6`）の `assets/` と `porkadot.yaml`、**porkadot 0.34.1**（`v0.34.1`、`060a687`）。この `assets/` は本番が今動いているもの（段 5 の 0.34.1 の render）
- **porkadot 0.34.1 の置き場**: §1.4 の (a) にしたなら、**元の clone（`porkadot-dev/porkadot`）が v0.34.1 のまま**なので、それを使う（`bundle install` は段 5 で済んでいる）。(b) にしたなら、`/tmp` に clone する（段 5 の手順書 §7.1 の形で、タグを `v0.34.1` にする）
- **etcd のバックアップ**: §2.4（段の前、1.34 の control-plane、CoreDNS v1.12.4）、§4.2（1.35 の control-plane、CoreDNS v1.13.2、kubelet は 1.34）

用意の仕方（作業端末で。ノードには触らない。段 5 の手順書 §7.1 と同じ形）:

```sh
P_OLD=/home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot      # (a) のとき。git -C $P_OLD describe --tags が v0.34.1
git clone <このリポジトリの checkout> /tmp/fraction-stage-5
git -C /tmp/fraction-stage-5 checkout f5873e6
cd /tmp/fraction-stage-5
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

- `git worktree add` は元の clone の `.git` に書き込むので、サンドボックスでは拒否される。`/tmp` に clone して使う
- 始める前に `grep VERSION $P_OLD/lib/porkadot/version.rb` が 0.34.1 で、`BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot help` が動くことを確かめておく

0.34.1 の `install kubelet` について:

- `/opt/bin/<名前>` の向き先で判定して張り替える。前の版のバイナリ（`kubelet-v1.34.12`、`crictl-v1.34.0`）はノードに残っているので、落とし直さずに向き先を戻す。etcd・etcdutl・CNI は同じ版なので変わらない
- **control-plane の etcd のマニフェストは、0.34.1 と 0.35.0 で同じ**（3.6.15-0、同じフラグ。§2.6）。戻しても etcd は 3.6.15 のまま（static Pod は作り直される）。段 5 の §7.5 のような etcd の制約は無い
- `install-pkgs.sh` は 0.35.0 と同じ（iscsid は `initiatorname.iscsi` が変わったときだけ再起動する）
- 1.35 → 1.34 の kubelet の戻しでコンテナが再起動するかは、dev で確かめていない。**Longhorn のボリュームがアタッチされた台を戻すときは、再起動する前提で drain してから流す**（段 5 の手順書 §7.1 と同じ。Longhorn のエンジンは v1.13.0 なので、drain の後の古いセッションは残らない見込みだが、`install kubelet` の前と後に `iscsiadm -m session` を見る）
- 0.34.1 の SSH は 0.35.0 と同じで、サンドボックスの中で流せる

### 7.2 control-plane のマニフェストを戻す ✋

```sh
cd /tmp/fraction-stage-5
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml
```

- **kubelet が 1.35 の台が残っているうちは流さない**（kubelet は apiserver より新しくてはいけない。先に §7.3 で戻す）
- 0.34.1 の `install.sh` も apiserver を先に入れて rollout を待つので、**apiserver が先に 1.34.12 になり、その間 1.35 の KCM・scheduler が 1.34 の apiserver と話す**。上げる向きの dev では、1.35 の scheduler・KCM は 1.35 の apiserver としか話していないので、1.35 の scheduler が 1.34 の apiserver の返さない API を待つかは**確かめていない**（段 5 の dev の見つけたことの 1 と逆の向き）。待つ形になったら、KCM と scheduler の Deployment の rollout が 2 段目で 1.34 に替わるまでの間、新しい Pod のスケジュールが止まりうる。apiserver の DaemonSet の Pod は 1 台ずつ入れ替わるので、Pending のまま止まったら段 5 の手順書 §8.3 の立て直しの形を見て、止めて報告する
- apiserver・KCM・scheduler・kube-proxy が v1.34.12 に、**CoreDNS が v1.12.4 に戻る**
- storage version: 1.35 は storage の版を変えないので（§2.5）、1.34 に戻しても `OLD` は出ない見込み
- FlowSchema: 1.35 は消さない・足さない見込みなので、11 個のまま
- rc 1（`connection refused`）なら rollout を待って流し直す（段 5 の手順書 §3.2 と同じ）
- §3.3 と同じ確認を、版を読み替えて行う（CoreDNS は v1.12.4、`tools/dns-check.sh` の答えが §2.2 の 23 と同じ）

### 7.3 kubelet を戻す（1 台） ✋

```sh
cd /tmp/fraction-stage-5
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubelet --node <ノード> --config ./porkadot.yaml
```

- `/opt/bin` の向き先が `kubelet-v1.34.12`、`kubectl-v1.34.12`、`crictl-v1.34.0` に戻る（etcdctl・etcdutl は 3.6.15、CNI は v1.9.1 のまま）。確かめる
- **Longhorn のボリュームがアタッチされた台は、drain してから流す**（§7.1）
- control-plane の台は、リーダーなら先に `move-leader` する（etcd の static Pod が作り直される）
- 戻した台でも、§4.4 または §5.3 の確認を、版を読み替えて行う。iscsid は再起動しない見込み（0.34.1 の `install-pkgs.sh`）なので、「PID が同じ」をそのまま見る

### 7.4 `porkadot etcd restore` ✋

段 5 の手順書 §7.4 と同じ形（使う backup だけを別のディレクトリに置き、`porkadot etcd restore --path ./backup-restore`。ログの `restored revision` が `current revision` + 10 億以上であることを確かめる。所要時間は dev で約 4 分、API は約 2〜3 分止まる）。**restore は最後の手段**で、API の中身が backup の時点に戻る（Longhorn の CR を含む。段 5 の手順書 §7.4 の注意）。

- **0.35.0 の `etcd restore` は 0.34.1 と同じ実装**（0.34.1 → 0.35.0 の差分に restore の変更は無い）。どちらで流してもよい。0.34.0 は使わない（段 5 の手順書 §7.4）
- 3 台の control-plane に `/opt/bin/etcdutl` → `etcdutl-3.6.15` があること（2026-10-21 は 8 台ともある）
- etcd は 3.6.15 のまま戻る（段 6 では etcd の版が変わらないので、段 5 のような版の制約は無い）

| backup | API の中身 | restore の後 |
|---|---|---|
| §2.4（段の前） | 1.34 の control-plane、CoreDNS v1.12.4 | kubelet が control-plane を 1.34.12 に入れ替える。**kubelet を 1.35 にした台があれば、kubelet が apiserver より新しい（skew policy の外）**。続けて §7.3 で kubelet を戻すか、0.35.0 の `install kubernetes` で上げ直すかを、その時点でユーザーと決める |
| §4.2（control-plane の kubelet の前） | 1.35 の control-plane、CoreDNS v1.13.2 | control-plane は 1.35.9 のまま。失われる変更が少ない |

### 7.5 段 6 全体をやめる

kubelet は kube-apiserver より新しくてはいけないので、**kubelet を先に戻し、control-plane を最後に戻す。** worker を上げた順の逆に §7.3 で戻し、control-plane の kubelet を上げた順の逆（.111 → .112 → .113）に §7.3 で戻し、最後に §7.2 で control-plane のマニフェストを戻す。

戻し終えたら、§6 の確認を版を読み替えて行い、`results/stage-6/` に戻した経緯を残す。

## 8. 既知の問題と注意

### 8.1 `install kubelet` のたびの cnidaria の `no route`

段 5 の手順書 §8.1 と同じ。段 5 の本番では各台で error が 8 件ずつ、1 秒ほど（pablo は 1、oeilvert は 0）。unattended-upgrades の needrestart が systemd-networkd を再起動したとき（§2.11）にも同じものが出うる。

### 8.2 render が証明書を作り直す

段 5 の手順書 §8.2 と同じ。当日に render し直さない。

### 8.3 `install kubernetes` の rc 1

段 5 の手順書 §8.3 と同じ（`connection refused` の rc 1、apiserver の rollout の timeout）。デッドロック（0.33.1 以前で 1.34 に上げたときの形）は、0.35.0 では apiserver が先に 1.35 になるので起きない見込み（dev のログに `Failed to watch` が 0）。戻しの向きは §7.2。

### 8.4 1.35 の kubelet ではコンテナが再起動しない

段 5 の手順書 §8.4 と同じ。dev の 7 台で、`install kubelet` の前と後の Pod の UID と restartCount が同じだった。control-plane の etcd の static Pod は作り直される（restartCount 1〜2）。ほかのコンテナが 1 つでも再起動したら止める。

### 8.5〜8.9

段 5 の手順書 §8.5〜§8.9 と同じ。CSR は段 6 の間も出ない見込み（dev でも出なかった）。

### 8.10 iscsid と iSCSI のセッション

Longhorn のエンジンは v1.13.0 で、計画 §4.4 の問題（iscsid の再起動の後に logout できない）は直っている。ユーザーの判断（2026-10-21）で、確認は段 6 以降も続ける（§2.7）。drain に切り替える台が出たら、drain の後・`install kubelet` の前と後に `sudo iscsiadm -m session` を見て、Longhorn のセッションが残っていないこと（v1.13.0 のエンジンなら detach でセッションが消える）を確かめる。残っていたら止めて報告する（logout は §0 の runbook から外れる操作）。

### 8.11 CNI plugins

段 6 では変えない。8 台とも、porkadot の版の印と、bridge・host-local・portmap・loopback が v1.9.1 にそろっている（§1.1）。0.35.0 の `install-deps.sh` は、版の印が `v1.9.1` で同じなので tarball を展開しない（`CNI plugins v1.9.1 already installed`）。

### 8.12 Longhorn の `no Pending workload pods`（longhorn/longhorn#8072 の形）

段 5 の手順書 §8.12 と同じ（段の開始の承認の範囲の ✋。消す前に名前を知らせる）。**JST 05:30 より後に作業するなら、当たる前提で §2.2 の 22 で洗い出す**。

### 8.13 etcd の遅れと、1 台が止まる間の quorum

段 5 の手順書 §8.13 と同じ。dev の段 6 では、`install kubernetes` の直後（全体の apply の後、7 台が kube-proxy・KCM・scheduler・CoreDNS のイメージを同時に pull・展開していた時刻）に、etcd が 3 台とも unhealthy、VIP に 000 が 4 回（約 20 秒）出た（dev の見つけたことの 2。`slow fdatasync` 最大 4.1 秒、`leader failed to send out heartbeat on time`）。7 台の VM が同じホストのディスクを使う dev に特有と見ている。本番の etcd は Raspberry Pi 5 の 3 台で別々の NVMe で、段 5 の本番の `install kubernetes` では、VIP の FAIL は apiserver の入れ替えの 2 回だけで、全体の apply の後には出なかった（そのときは etcd の health の監視を流していない）。§2.3 の etcd の health の監視で見る。

- control-plane の `install kubelet` の間は、その台の etcd が十数秒止まる（§4.1）。ほかの 2 台が unhealthy にならないこと
- 本番で VIP が 15 秒を超えて応答しないときは、etcd のログ（`slow fdatasync`、`apply request took too long`、`heartbeat`）を見て記録する。1 分を超えたら §7 の目安に当たる

### 8.14 storage version

`storage-versions.md`。§2.5 のとおり、段 6 では書き直しは無い。`install kubernetes` の前と後に `OLD` が出たら止めて調べる。

### 8.15 metrics

1.35 で、本番の kube-prometheus（chart 85.2.1）のダッシュボードとルールが使う metrics に影響する変更は、この手順書を書いたときに見つけていない（段 5 の手順書 §8.15 の 1.34 の変更は、段 5 で影響が無いことを確かめた）。§6 で `up == 0` と `count(etcd_server_has_leader)` を見る。出なくなったものがあれば記録し、段 8 の後の kube-prometheus-stack の更新（計画 §8）で扱う。段の更新は止めない。

### 8.16 CoreDNS の upstream に kube-dns が入っている

§2.10。前からのもので、段 6 は止めない。CoreDNS のログに `loop`（`Loop (…) detected for zone "."`）が出て CoreDNS が落ちたら、止めて報告する（v1.12.4 では出ていない）。

## 9. 記録

`results/stage-6/` に、ベースライン（`baseline.md`。§2.4 のバックアップ、§2.5 の storage version、§2.9 の cgroup、§2.10 の resolv.conf、§2.11 の unattended-upgrades の時刻も）、`install kubernetes`（`control-plane.md`。§3.3 の 13〜19 と CoreDNS の答え、§4.2 のバックアップも）、各台（`<ノード>.md`。control-plane は `192.168.1.11N.md`）、全体のまとめ（`summary.md`。§6 の v1 Endpoints の warning の出どころの表と metrics の確認も）を残す。各台の雛形は `results/stage-6/template.md`。
時刻（UTC。control-plane のホストの JST の時刻は直して書く）、読み取りの結果、実行したコマンドと出力の要点、Pod の再起動の有無、iscsid の PID とセッションの前と後、etcd の版と健全性、監視の FAIL（VIP・LB と etcd の health）、leader election で再起動したもの、手順書との差を書く。`tools/node-state.sh` と `snap` の出力、監視のログ（`./stage-6-probe.log`、`./stage-6-etcd-*.log`）、`tools/storage-versions.sh` の出力、`tools/dns-check.sh` の出力、`endpoints-warnings.tsv` はタスクディレクトリの `notes/stage-6/` に置き、要点を記録に写す。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（同じ PR か、記録の PR で）。

## 10. 段 6 の後

- 健全性を確かめてから段 7（1.36）へ（間隔は必須ではない。計画 §9.6）
- 段 5 の 3.5 の etcd のバックアップ（`etcd-2026-10-20T09:08:38+00:00.db`、`…T09:20:45…`）は、段 6 に入ったので戻しの材料としては使わない（段 5 の手順書 §10）。消すかはユーザーが決める
- 段 7 の注意（計画 §7）: `gitRepo` volume が無効になる（使っていない）、KCM の metrics の改名、MetalLB の CRD を apply し直すことになるので dev で `install kubernetes` が通ることを見る
- 申し送り（段 6 の範囲の外）: §2.10 の CoreDNS の upstream に kube-dns が入る件（porkadot の `dns` の addon と Corefile）、§2.11 の unattended-upgrades の needrestart による iscsid の再起動（Longhorn のエンジンが直った後も、作業の時間帯を避けるために続けて見る）
