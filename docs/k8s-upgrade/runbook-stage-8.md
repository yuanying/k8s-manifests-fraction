# 段 8 の手順書: K8s を 1.36.5 から 1.37.1 へ、etcd を 3.6.15 から 3.7.3 へ上げる（本番 `fraction`）

本番クラスタ `fraction` の Kubernetes を v1.36.5 から v1.37.1 へ上げ、**etcd を 3.6.15 から 3.7.3 へマイナー更新する**手順。porkadot を 0.36.0 から 0.37.0 に替える。あわせて、kubelet の `--container-runtime-endpoint` を KubeletConfiguration の `containerRuntimeEndpoint` へ移し、CoreDNS の Corefile の `cache` に `disable success/denial cluster.local` を足す。CoreDNS のイメージ（v1.14.7）と CNI plugins（v1.9.1）は据え置く。これで計画の最後の段になる。
計画は同じディレクトリの `plan.md`（以下「計画」）の §6（骨子）と §7 の段 8 の行、決まったことは §9 にある。前の段は `runbook-stage-7.md`（以下「段 7 の手順書」）で、この手順書はそれを下敷きにし、**段 7 から変わる点を中心に書く**。etcd のマイナー更新の部分（承認の 2 つ目の節目、混在中の確かめ方、restore のロールバック）は `runbook-stage-5.md`（以下「段 5 の手順書」）の形にする。段 3〜7 と同じく drain しない。

| | 更新前 | 更新後 |
|---|---|---|
| porkadot | 0.36.0（`7247f15`、タグ `v0.36.0`） | **0.37.0**（`4e8827b`、タグ `v0.37.0`） |
| kube-apiserver、kube-controller-manager、kube-scheduler、kube-proxy | v1.36.5 | **v1.37.1** |
| kubelet、kubectl（ノードの `/opt/bin`） | v1.36.5 | **v1.37.1** |
| crictl（ノードの `/opt/bin`） | v1.36.0 | **v1.37.0** |
| etcd（control-plane の static Pod） | 3.6.15-0 | **3.7.3-0**（マイナー更新。フラグは変わらない） |
| etcdctl・etcdutl（ノードの `/opt/bin`） | 3.6.15 | **3.7.3** |
| kubelet の `config.yaml`・`kubelet.service` | `kubelet.service` に `--container-runtime-endpoint=/run/containerd/containerd.sock` | **`config.yaml` に `containerRuntimeEndpoint: unix:///run/containerd/containerd.sock`、`kubelet.service` からフラグを外す** |
| CoreDNS | v1.14.7、Corefile の `cache 30` | **v1.14.7 のまま**。Corefile の `cache 30` に `disable success cluster.local`・`disable denial cluster.local` を足す（Pod は作り直さず `reload` で読む） |
| CNI plugins（ノードの `/opt/cni/bin`） | v1.9.1 | 変えない（版の印が同じなので展開しない） |
| `install-pkgs.sh`、`initiatorname.iscsi` | iscsid は `initiatorname.iscsi` が変わったときだけ再起動（変わらなければ `systemctl start` だけ） | 変えない |
| cnidaria、MetalLB（pool を含む）、kubelet-serving-cert-approver | v0.1.1、v0.14.5、0.12.1 | 変えない（マニフェストの差分が無い。MetalLB の CRD・webhook は apply し直されるが中身は同じ） |
| kube-proxy の `mode` | `iptables` | 変えない（ConfigMap に `mode: iptables` があるので、1.37 の kube-proxy の mode の warning は出ない） |
| containerd、runc | 段 C の 2.3.6、1.5.1 | 変えない（2.3 は 1.37 の推奨表に入る。計画 §5.1） |
| Longhorn | v1.13.0（17 本ともエンジンは v1.13.0） | 変えない（§1.10） |

porkadot 0.37.0 に入った PR は porkadot#61（マージ `48d33bf`。`007c5a5` で K8s v1.37.1、crictl v1.37.0、etcd 3.6.15-0 → 3.7.3-0、CoreDNS の Corefile の `cache`。`c57e656` で `containerRuntimeEndpoint`）と、porkadot#62（`e52782a`。版を 0.37.0 にする）。0.36.0 から 0.37.0 の差分は `lib/porkadot/default.yaml`（`kubernetes_version`・`crictl_version`・`etcd.image_tag`・`kubelet.config.containerRuntimeEndpoint`）、`kubelet.service.erb`（フラグの削除）、`coredns.yaml.erb`（`cache` の block）、`version.rb`、文書とテストの 11 ファイルで、**`install`・`etcd backup`・`etcd restore` の実装は 0.36.0 と同じ**（`etcd restore` は 0.34.1 から変わっていない）。

この手順は dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で先に通してある（2026-10-23 13:04〜13:58Z）。記録は porkadot-dev の `docs/k8s-upgrade/verification-0.37-rc.md`（以下「dev の記録」。porkadot-dev の main `af1a5de`、porkadot-dev#18）。dev は #61 の `c57e656` で通したもので、0.37.0 との違いは版の番号（#62）だけ。dev で分かったことは次のとおり。

- **1.37 の kubelet に上げても、コンテナは再起動しなかった**（1.32〜1.36 と同じ）。7 台すべてで Pod の UID・restartCount が変わらず、変わったのは control-plane の etcd の static Pod だけ。**iscsid も 7 台とも PID が変わらなかった。** Longhorn v1.13.0 のボリュームをアタッチしたまま `install kubelet` した 2 台で、ボリュームは `attached`・`healthy` のまま、セッション・iscsid の PID も変わらず、detach の後にセッションは残らなかった
- **`install kubernetes` は 1 回目で rc 0**（約 3 分。apiserver の 3 台の入れ替えに約 2 分半、全部の rollout の完了まで約 4 分）。1.37 の scheduler・KCM のログに `Failed to watch` / `failed to list` は 0（1.36 の apiserver の返さない API を待つ形は無かった。全部の apiserver が 1.37 になってから入るため）
- **1.36 と 1.37 の apiserver が並ぶ間**、503 は出ず、1.37 だけの API を VIP 経由で読むと振り先によって NotFound か 200 になった（porkadot は `--peer-ca-file` を渡さないので peer proxy は働かない）
- **etcd は control-plane の `install kubelet` で 1 台ずつ 3.7.3 になり、混在中も各台の後に 3/3 healthy だった。** 3 台目の後に cluster version と storage が 3.7.0 になった（§4）。フラグは 3.6 と同じで、`unknown flag` は無い
- **全台 3.7 の後でも、上げる前（3.6）の backup を 0.37 の `etcd restore` で戻せた**（etcd は 3.7.3 のまま起き、API の中身が backup の時点に戻る。§7.4）
- **`containerRuntimeEndpoint`**: 7 台とも `kubelet.service` からフラグが消え、`config.yaml` に入り、kubelet が containerd に繋がった。起動時の `Flag --container-runtime-endpoint has been deprecated` は消えた
- **CoreDNS は Pod を作り直さず `reload` で新しい Corefile を読み**、答えは上げる前と同じ。クラスタ内の名前は cache されなくなった（作ったすぐ後に引け、消したすぐ後に NXDOMAIN）
- **1.37 の KCM が ClusterTrustBundle を 1 つ作り、apiserver は `certificates.k8s.io/v1beta1` で保存する**（dev の見つけたことの 1）。この PR で `tools/storage-versions.sh` に 1.37 の override を足した（§2.5）
- **CoreDNS の `loop` plugin が、Corefile の reload のときに FATAL で 1 回 exit した**（restore の後の reload。dev の見つけたことの 2。§8.16）
- **3.7 の etcdctl の `-w table` は罫線が Unicode**（`┌`、`│`）。`|` で grep しない（dev の見つけたことの 3。§1.5）
- 1.37 の apiserver は、3.6 のメンバーに当たる間 `RangeStream` を使わず、黙って fallback する（dev の見つけたことの 4。§8.21）
- CSR は 1 つも出なかった。作業端末の kubectl v1.36.5 で 1.36 と 1.37 の server を問題なく使えた。porkadot のコマンドとノードへの `ssh` は、すべてサンドボックスの中で流した。監視はハーネスのバックグラウンド実行で 1 つずつ起動し、最後まで欠けずに取れた

これを受けて、**本番の段 8 でも、どのノードも drain しない**（§2.7）。止める条件は段 7 のまま使う（etcd の static Pod の作り直しは想定どおりとして除く）。

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **arm64 の control-plane での etcd 3.7.3 と 1.37 の kubelet**。dev は amd64 の VM。arm64 のイメージとバイナリが配布されていることは確かめてある（§1.7）
- **本番の etcd のデータ**（2020 年から使っている。DB 55 MB、revision 12 億台）での 3.7 への更新
- **混在中の etcd を 3.6 に戻すこと**（§7.3）と、**全台 3.7 の後に kubelet まで 1.36 に戻すこと**（§7.5）。どちらも dev では流していない
- **0.36 の `install kubernetes` だけで control-plane を戻すこと**（§7.2）。1.37 の scheduler・KCM が 1.36 の apiserver の返さない `v1` の API を待ちうる（porkadot#61 の本文）
- **本番の Longhorn のボリュームがアタッチされたままの `install kubelet`**（2026-10-23 14:2xZ は chirico 11 本、duchamp 5 本）。段 3〜7 の本番では同じ形で問題が無かった
- **braque の 1.37 の kubelet**（1.37 の kubelet の cAdvisor は ZFS の扱いを一度落として戻した。§2.12）

## 0. 役割と約束ごと

段 7 の手順書 §0 と同じ。違いは次のとおり。

- **承認の節目は 2 つ**（計画 §9.1「本番の各段の開始」と「etcd のマイナー更新を含む段（5 と 8）の control-plane の kubelet の更新の前」）。この手順書では ✋✋ を付けた。
  - ✋✋ **段 8 の開始**: render の差分（§2.6。この手順書と同じ PR）、drain しないこと（§2.7）、storage version の読み取りの結果（§2.5）、unattended-upgrades と jumelle の時刻（§2.11）、ベースライン（§2.2）とバックアップ（§2.4）、porkadot 0.37.0 の置き場（§1.4）、ロールバックの形（§7）を見せ、PR をマージしてから、`install kubernetes` を流す前（§3.1）
  - ✋✋ **control-plane の kubelet（etcd 3.7）の前**: `install kubernetes` の結果（§3.3）、2 つ目のバックアップ（§4.2）、ロールバックの形（§7。**etcd の cluster version が 3.7.0 になった後は 3.6 に戻せず、restore だけになること**）を見せてから、最初の control-plane（.113）の `install kubelet` の前（§4.2）
- **節目の間の手順は、ユーザーに知らせるだけで進めてよい。** etcd のバックアップ、etcd のリーダーの移動、`install kubelet`、`install kubernetes` の流し直し（§3.2）、一時的な DaemonSet・NetworkPolicy の確認（`netcheck.sh`、`npcheck.sh`）は、この手順書に書いた形なら ✋（知らせてから行う操作）で、1 つずつ承認を取るものではない。
- **§8.12 の Completed / Succeeded の Pod の削除は、段の開始の承認の範囲の ✋ とする**（段 7 と同じ。消す前に対象の名前を知らせる）。段 8 には storage version の書き直しは無い（§2.5）。
- **runbook から外れる操作（ロールバック、`etcd restore`、drain への切り替え、想定外の対処、上のほかの Pod の削除、iSCSI のセッションの logout、unattended-upgrades の止め・手での apt の操作）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認は、知らせずに行ってよい。**1 台ずつ行う。** 時刻はすべて UTC で記録する（control-plane のホストの時刻は JST）。

## 1. 前提

### 1.1 段 7 が終わっていること、段 7 の後に変わったこと

始める前に次を確かめる。

- 段 7 の完了の確認（段 7 の手順書 §6）が `results/stage-7/summary.md` に残っている
- 8 台すべてが v1.36.5、CONTAINER-RUNTIME が `containerd://2.3.6`、etcd が 3/3 で 3.6.15（cluster version・storage とも 3.6.0）
- Longhorn が v1.13.0 で、17 本とも `status.currentImage` が `longhorn-engine:v1.13.0`

**段 7 の後（2026-10-21 13:4xZ〜）に、このタスクの外で本番が変わった**（タスクディレクトリの `notes/stage-8-premises-20261023.md`）。この手順書のベースラインと止める条件は、変わった後の姿を前提にする。

| 変わったこと | 時期 | 段 8 での扱い |
|---|---|---|
| **IPv6 の委譲プレフィックス**が `2405:6580:6740:ac00::/56` に変わり、宅内の /64 は `2405:6580:6740:ac01::/64`。MetalLB の `first-pool` の IPv6 は `2405:6580:6740:ac01:ace::/96` に、IPv6 の LoadBalancer 8 つの `loadBalancerIP` も新しい値に（k8s-manifests-fraction#50、fleet-infra#200）。`porkadot.yaml` と render 済みの `metallb.config.yaml` も直し済み | 10-23 02:1x〜 | **render の差分に pool が出ないこと**を確かめた（§2.6）。`install kubernetes` は今の pool を入れ直すだけ。ロールバックの assets は #50 の後の master（`6bfaab0`）を使う（§7.1）。監視（VIP と gated-v4）は IPv4 なのでそのまま。v6 の LB を確かめるなら gated-v6 の `[2405:6580:6740:ac01:ace::200]` |
| **oeilvert の netplan を RA + トークン `::183`** に（k8s-manifests-fraction#51）。cordon → drain → 再起動 → uncordon | 10-23 06:23〜06:34Z | oeilvert のノードの IPv6 は `2405:6580:6740:ac01::183`（dynamic）。drain で oeilvert のボリュームは chirico に移り、**oeilvert のアタッチは 0、iscsid は動いていない**（ソケット起動。§2.7） |
| **使っていないアプリの削除**（`2d22dd4`、`7716d7b`。minio、fs の sites 以外の一部、ほか） | 10-23 04:22Z | 名前空間 `minio` は無い。ベースラインは今の姿で取る（Pod 165 個、Longhorn 17 本） |
| **iscsid の needrestart の再起動**（段 7 の §2.11 で残っていた 4 台。.112 10-21 21:42Z、.111 21:51Z、chirico 10-22 06:20Z、oeilvert は 10-23 の再起動） | 〜10-23 | 8 台とも liblzma5 が 0.4。**段 7 の手順書 §2.11 の 4 台の件は閉じる**。今の PID を比べ先にする（§2.7） |
| **jumelle（ルーター）の unattended-upgrades** が有効に（毎日 18:00〜18:30Z、`reboot-required` なら 19:00Z に自動再起動） | 10-22〜 | **18:00〜19:30Z を避ける**（§2.11） |
| **CoreDNS が 10-23 02:14〜02:26Z に再起動を繰り返した**（`plugin/loop` の FATAL と OOMKilled。プレフィックスの切り替えで上流の DNS が答えなかった間） | 10-23 02:1xZ | restartCount は 7 と 4 のまま Running。ベースラインの値として控える（§2.10、§8.16） |

2026-10-23 14:2xZ の読み取り（この手順書を書いたとき）:

- 8 台 Ready、全台 v1.36.5、`containerd://2.3.6`。etcd 3/3 が 3.6.15（cluster version・storage とも 3.6.0）、リーダーは .113（`57ec6f12ac7b683e`）、raft term 23125、raft index 1404725884、`header.revision` 1,239,114,847、DB 55 MB（in use 16 MB）。member list は 3 つとも `started`。Pod は 165 個で、Running / Completed 以外は 0 個
- generation: DaemonSet `kube-apiserver` 30、Deployment `kube-controller-manager` 29、`kube-scheduler` 28、DaemonSet `kube-proxy` 26、Deployment `coredns` 13（v1.14.7、2/2。chirico と duchamp。restartCount 4 と 7）、DaemonSet `cnidaria` 3（`cnidaria-cni:v0.1.1`）
- Longhorn は v1.13.0。ボリュームは 17（attached healthy 16、detached unknown 1 の `homegallery/cg-data`）。**アタッチ先は chirico 11、duchamp 5、oeilvert 0、pablo 0**（段 7 の chirico 9、duchamp 4、oeilvert 2、pablo 1 から、oeilvert の drain とアプリの削除で変わった）
- `tools/storage-versions.sh`（この PR で直したもの）は `prefixes: 66, keys: 2256, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は 1.36 の 2 行。1.37 の override の 4 種（§2.5）のキーは 0
- 8 台の `tools/node-state.sh`: `/opt/bin` は `kubelet-v1.36.5`、`kubectl-v1.36.5`、`crictl-v1.36.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と 4 つのプラグインは `v1.9.1`。iSCSI と iscsid は §2.7
- 8 台の `/var/lib/kubelet/config.yaml` と `/etc/systemd/system/kubelet.service` は、この PR の前の master の `assets/kubelet/<ノード>/` と同じ（md5 で比べた）。`kubelet.service` に `--container-runtime-endpoint` があり、`config.yaml` に `containerRuntimeEndpoint` は無い
- 3 台の動いている etcd のフラグは `--feature-gates=InitialCorruptCheck=true`、`--watch-progress-notify-interval=5s`、`--snapshot-count=10000` を含み、`--experimental-` で始まるものは無い（3.7 の前提。計画 §7 の段 8）

### 1.2 kubeconfig の運用

段 7 の手順書 §1.2 と同じ（確認は `fraction-auditor`、変更系は `infra-admin` の 1 時間のトークンと `kubectl-admin`）。

**段 8 で `infra-admin` のトークンを使うのは、§1.9 の NetworkPolicy の確認（と、その中の §3.3 の 13 の任意の確かめ）と、§8.12 の Pod の削除だけ**（`netcheck.sh` はトークンを使わず、cnidaria の手順書の `kadmin.sh` で sops の admin の kubeconfig を使う。段 7 と同じ）。トークンのファイル名は `/tmp/k8u-stage8-admin-token` にする。

### 1.3 SSH

段 7 の手順書 §1.3 と同じ（worker は `ssh yuanying@<IP>`、control-plane は `ssh ubuntu@<IP>`。**サンドボックスの中で流す**。control-plane には `unset LC_ALL` してから入る）。**名前ではなく IP で入る**（chirico・duchamp は名前で入ると known_hosts が合わない。oeilvert は名前が引けない）。2026-10-23 14:23Z にこの手順書を書いたとき、8 台ともサンドボックスの中から `tools/node-state.sh` を流せた。

### 1.4 porkadot の置き場と流し方

元の clone（`/home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot`）はサンドボックスの中からは書き込めない。段 6・段 7 と同じく、タスクディレクトリの独立の clone を使う。

| 用途 | 置き場 | 版 |
|---|---|---|
| **段 8 の当日**（`etcd restore` を含む） | `/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-0` | v0.37.0（`4e8827b`、detached） |
| **§7 の戻し** | `/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-36-0`（段 7 で使ったもの。触らずに残す） | v0.36.0（`7247f15`、detached） |

- 0.37.0 の clone は、元の clone から `git clone` し、origin を `https://github.com/yuanying/porkadot.git` にして tag `v0.37.0` を fetch し、detached で checkout した（push しない）。`git ls-remote` で GitHub の `refs/tags/v0.37.0`（tag object `96c5277`）と `^{}`（`4e8827b`）が手元と一致することを確かめた。`lib/porkadot/version.rb` は 0.37.0。`bundle install` 済み（Ruby 4.0.7）で、2026-10-23 14:20Z にこの clone で §2.6 の render を流した
- 0.36.0 の clone は、2026-10-23 に `git describe --tags` が `v0.36.0` であることを確かめた。当日の前に `porkadot help` が動くことを確かめる

**このリポジトリのルートを cwd にして** 流す。形は段 7 の手順書 §1.4 と同じ。

```sh
P=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-37-0
git -C $P describe --tags          # v0.37.0（lib/porkadot/version.rb も 0.37.0）
cd <このリポジトリの checkout>     # §2.6 の PR をマージした master
BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

以下、この形を `porkadot <サブコマンド>` と書く。

- 始める前に `BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot help` が動くことを確かめる
- 作業ツリーの `assets/` と `porkadot.yaml` に PR の外の変更が無いこと（`git status --short assets porkadot.yaml` が空）。メインの checkout にほかの作業があれば、master の別の worktree を作ってそこで流す
- **`install kubelet --node` には `porkadot.yaml` の `nodes` のキーを渡す**: control-plane は IP（`192.168.1.111`〜`113`）、worker は名前（`pablo`、`oeilvert`、`braque`、`duchamp`、`chirico`）。**worker に IP を渡してはいけない。** porkadot 0.37.0 の `install kubelet` は、キーに無い `--node` をはじかず（`KubeletList#[]` が nil を返し、`install hosts: nil` が全ノードを選ぶ）、`--node` なしと同じく全ノードに流す。本番の段 8 では、pablo に `--node 192.168.1.134` を渡して 8 台に流れた（`results/stage-8/workers.md` §1）。流す前に `grep -nE '^  [^ ]+:$' porkadot.yaml` でキーを確かめる
- 段 8 で流す porkadot のコマンドは、`etcd backup`、`install kubernetes --node 192.168.1.111`、`install kubelet --node <ノードのキー>` の 3 つだけ。**`install all`、`--node` なしの `install kubelet` と `install kubernetes`、`render`（特に `render all` と `render certs`）、`setup-node`、`setup-containerd`、`etcd restore`（§7.4 の承認を得たときだけ）は流さない**
- **0.36.0 以前の porkadot で `install kubelet` を流さない**（etcd のマニフェストが 3.6.15 になる。§7）
- **ノードに入る porkadot のコマンドもサンドボックスの中で流す**（0.37.0 の SSH は 0.36.0 と同じ）。当日の流す前の確かめ方は段 2 の手順書 §1.4 のスクリプト（`P` を 0.37.0 の置き場にする）。8 台とも hostname を返すこと

### 1.5 etcdctl の使い方

段 5 の手順書 §1.5 と同じ（sudo で流す。`move-leader` は `unset ETCDCTL_ENDPOINTS` してから `--endpoints` を渡す。メンバーの版は `/version` でも読む。動いている etcd のフラグは `/proc/<pid>/cmdline`）。

- **ノードの `/opt/bin/etcdctl` は、その台の `install kubelet` で 3.7.3 に替わる。** dev では、3.7 の etcdctl で 3.6 のメンバーも問題なく読めた
- **3.7 の etcdctl の `-w table` は罫線を Unicode（`┌`、`│`）で出す**（dev の見つけたことの 3）。目で読むのはよいが、**`|` で grep・awk して数えない**。数えるときは `-w json` を使う（`Status.header.revision`、`Status.header.member_id`、`Status.leader`、`Status.version` の形は 3.6 と同じ）
- `endpoint health`（`-w` なし）の行の形は 3.6 と同じで、§2.3 の監視はそのまま流れる

### 1.6 render に使った secrets と、本番との突き合わせ

secrets の在りかと扱いは段 1 の手順書 §1.6 と同じ（`assets/` の中に sops の binary 形式で暗号化してある。`assets/secrets.tar.asc` を展開しない。平文をディスクに書かない）。
段 8 の render（§2.6）の前に、段 7 の手順書 §1.6 と同じ形で本番と突き合わせ直した（2026-10-23 14:20Z。読み取りだけ。復号をパイプで流してハッシュだけを比べた。スクリプトはタスクディレクトリの `notes/runbook-stage-8/scripts/secrets-check.sh`。段 7 のものと同じ）。**28 項目すべて一致した。**

| 比べたもの | 本番の側 | 結果 |
|---|---|---|
| `assets/certs/kubernetes/ca.crt` | ConfigMap `default/kube-root-ca.crt` | 一致（SHA-256 `AB:5A:49:9E:…`。段 1〜7 と同じ） |
| `assets/certs/kubernetes/apiserver.crt` | VIP と 192.168.1.111〜113 の 6443 が返す証明書 | 4 つとも一致（`4A:E8:7B:B3:…`） |
| `assets/certs/kubernetes/` の 10 ファイル | .111 の kube-apiserver の Pod（`kube-apiserver-pvvmc`）にマウントされた Secret `kube-apiserver` | 10 ファイルとも sha256 が一致 |
| `assets/certs/etcd/{ca.crt,etcd-client.crt,etcd-client.key}` | 同じく Secret `etcd-tls` | 3 ファイルとも一致 |
| `assets/kubelet/192.168.1.11{1,2,3}/addons/etcd/{ca.crt,etcd.crt,etcd.key}`（render の前） | 3 台の `/etc/etcd/pki/` | 9 ファイルとも一致（`etcd.crt` は段 7 の render のもの） |
| CA の鍵と証明書（kubernetes、front-proxy、etcd） | — | 3 組とも公開鍵が一致 |

当日に確かめ直すときの形は段 1 の手順書 §1.6 と同じ。どれかが食い違えば、render の差分も assets も信用せず、止めて調べる。

### 1.7 入れる版を確かめる

作業の当日に確かめ直す（読み取り）。

```sh
curl -fsSL https://dl.k8s.io/release/stable-1.37.txt     # v1.37.1
gh api repos/etcd-io/etcd/releases --jq '.[] | select(.tag_name|test("^v3\\.7\\.")) | .tag_name' | head -1   # v3.7.3
```

2026-10-23 14:21Z の時点（タスクディレクトリの `notes/runbook-stage-8/versions.txt`）:

- `stable-1.37.txt` も `stable.txt` も v1.37.1（1.37 系は v1.37.0 と v1.37.1）
- registry.k8s.io の `kube-apiserver`・`kube-controller-manager`・`kube-scheduler`・`kube-proxy` の v1.37.1、`etcd:3.7.3-0`、`coredns/coredns:v1.14.7` は、どれも amd64 と arm64 を含む（manifest list を読んだ）。etcd 3.7 は arch ごとのタグを出さないが、porkadot は multi-arch のタグを使う
- `dl.k8s.io` の kubelet と kubectl の v1.37.1（amd64、arm64）、cri-tools の `crictl-v1.37.0-linux-{amd64,arm64}.tar.gz`、etcd の `etcd-v3.7.3-linux-{amd64,arm64}.tar.gz` は、どれも 200 を返す。cri-tools の 1.37 系は v1.37.0 だけ。etcd の 3.7 の最新は v3.7.3
- **etcd 3.7 へは 3.6.11 以上からしか上げられない**（[upgrade_3_7](https://etcd.io/docs/v3.7/upgrades/upgrade_3_7/)）。本番は 3.6.15。`--experimental-*` のフラグが残っていると 3.7 は起動しないが、本番の 3 台には無い（§1.1）
- **CoreDNS は v1.14.7 のまま**（2026-10-23 のユーザー判断）。最新は v1.15.0（2026-10-21）だが、registry.k8s.io の `coredns/coredns` のタグは v1.14.7 まで（v1.15.0 は無い）。v1.15 は段 8 の後の非クリティカルの更新で扱う（§10）
- CNI plugins v1.9.1 はノードに入っているもので、変わらない
- **作業端末の kubectl は v1.36.5**。1.36 にも 1.37 にも ±1 に入る（dev でも v1.36.5 で使えた）

### 1.8 確認に使うスクリプト

段 7 の手順書 §1.8 と同じ（cnidaria の手順書の `verify-nodes.sh`・`netcheck.sh`・`check-apps.sh`、`tools/node-state.sh`、`tools/storage-versions.sh`、`tools/dns-check.sh`、`tools/ipcidr-scan.py`）。違いは次のとおり。

- **`tools/storage-versions.sh` をこの PR で直した**。`overrides.tsv` に 1.37 の場合（4 行）を足した（§2.5、`storage-versions.md` §3.2）。1.36 の 2 行は 1.37 では出ない。合格の基準は `OLD: 0` のまま
- **cnidaria の手順書の `verify-nodes.sh` は、段 7 と同じく写しの `IMAGE` を `cnidaria-cni:v0.1.1` にして流す**（段 7 の手順書 §1.8）。**`check-apps.sh` の `CHECK_URLS` の v6 も古いプレフィックス（`2405:6581:8580:301:ace::200`）のままなので、`http://[2405:6580:6740:ac01:ace::200]/` に替える**。本番の段 8 では、`common.sh` を書き換えず、`RUNBOOK_ENV` に `IMAGE`・`CHECK_URLS`・`FRACTION` を上書きする env のファイルを渡して流した
- `tools/ipcidr-scan.py` は、段 8 では §6 で 1 回流して `# findings: 0` のままであることを見るだけ（StrictIPCIDRValidation は 1.36 から。段 7 の手順書 §2.12）

### 1.9 NetworkPolicy の確認（一時的な名前空間） ✋

段 7 の手順書 §1.9 と同じ（`tools/npcheck.sh` と `tools/npcheck.yaml`）。合格は、`up` の後の `nft` が 8 台とも 1 以上、`run` が `OK 56, not OK 0`、`down` の後の `nft` が 8 台とも 0、名前空間 `k8u-npcheck` が NotFound。段 7 の本番では、`up` の後の `nft` は 8 台とも 9 だった。

流すのは、最初の worker の後（§5.5）と、段 8 の完了の確認（§6）。

### 1.10 Longhorn と K8s 1.37

Longhorn v1.13.0 の要件は **Kubernetes >= v1.34**（上流の文書 `https://longhorn.io/docs/1.13.0/deploy/install/` の Installation Requirements の「Kubernetes >= v1.34」と Kubernetes Version の「Longhorn requires Kubernetes >= v1.34.」、v1.13.0 の release notes の「Kubernetes v1.34 Minimum Version」）。**上限の表明は無い**（文書にも release notes にも、上限や検証した版の一覧は無い。2026-10-23 14:2xZ に読み直した。計画 §4.1）。1.37.1 は下限を満たすので、段 8 では Longhorn を変えない。計画 §4.3 の経路 A のとおり、段 6〜8 は 1.13.x で走る。v1.13 系の release は v1.13.0（2026-09-29）だけ（ほかは v1.12.2-rc1 が出ている）。dev の段 8 も Longhorn v1.13.0 で通した。

- 1.37 で削除される GA の API は無い（1.37 で消える API は `scheduling.k8s.io/v1alpha2` だけで、既定では出ない alpha の API。本番にオブジェクトは無い。§2.12）。Longhorn の使う API（CSI、`storage.k8s.io/v1`、`coordination.k8s.io/v1`、`discovery.k8s.io/v1`、v1 Endpoints）は 1.37 でも提供される。v1 Endpoints の warning は段 7 と同じく出る（§6）
- 本番の chirico には instance-manager が 2 つある（`longhorn-instance-manager:v1.11.2` の `-4128231c…`（10.244.8.216）と v1.13.0 の `-ed03b277…`（10.244.8.60））。v1.11.2 のほうは、Longhorn の更新のときに live upgrade したエンジン（イメージは v1.13.0）を動かしたまま残っているもので、段 7 のときと同じ。段 7 のベースラインでは pablo・chirico・oeilvert に 2 つずつ、duchamp に 1 つの 7 つだったが、10-23 に pablo の `fs/sites` が duchamp に移り、oeilvert が再起動して、pablo と oeilvert は 1 つずつ（pablo 10.244.4.197、oeilvert 10.244.7.224）、今は 5 つ。**chirico のセッションの portal は、この 2 つのどちらかの IP なら今のもの**（§2.7）

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 順序 | `install kubernetes --node 192.168.1.111` → rollout の完了 → 2 つ目のバックアップ → ✋✋ → control-plane の `install kubelet --node` を 1 台ずつ（.113 → .112 → .111）→ 3 つ目のバックアップ → worker を 1 台ずつ（§5.1） | 計画 §6.2、dev の記録 |
| 2 | etcd のリーダー | `install kubelet` の前に、対象がリーダーなら `move-leader` で別のメンバーへ移す（3.6 から 3.7 のメンバーへも移せる。dev の .111 の前） | 計画 §6.2、dev の記録 |
| 3 | drain | **どのノードも drain しない**（§2.7）。**ただし、どの台の後でも、Pod のコンテナの再起動（restartCount の増加、UID の変化。control-plane の etcd の mirror Pod を除く）が 1 つでも出たら止める。** 特に最初の worker と、Longhorn のボリュームが多い台の前に見る。止めた後、残りの Longhorn のノードを drain に切り替えるかはユーザーが決める（§8.10） | dev の記録、段 3〜7 の本番、2026-10-19 のユーザーの方針 |
| 4 | drain の基準 | 「短時間の途切れ」より「Longhorn のボリュームの安全（データ、degraded のまま戻らないこと）」を重く見る。短時間の障害は許容する | 2026-10-19 のユーザーの方針 |
| 5 | iSCSI | **各台の `install kubelet` の前と後に `tools/node-state.sh` で iscsid の PID と iSCSI のセッションを見る**。`install kubelet` で iscsid の PID が変わったら止める。**ただし、前が `MainPID=0`（動いていない）の台で、`install-pkgs.sh` の `systemctl start` で起きた「0 → 新しい PID」は想定どおり**（§2.7）。古いセッションがあれば止める | 2026-10-21 のユーザーの判断、段 7 の手順書 §2.7 |
| 6 | cgroup | 上げる前に 8 台で `cgroup2fs` を確かめる（段 7 と同じ。§2.9） | 段 6 の手順書 §2.9 |
| 7 | ノードの再起動 | しない | 計画 §9.3 |
| 8 | コンテナの再起動 | 1.37 の kubelet では起きないことを前提にする（§8.4）。control-plane の etcd の static Pod だけは作り直される（restartCount 1〜2 は想定どおり）。**CoreDNS の `plugin/loop` による 1 回の exit は §3.3 の 13 の条件で想定どおりとして扱う**（§8.16） | dev の記録 |
| 9 | Longhorn の設定 | 変えない | 段 1 の手順書 §2.6 |
| 10 | etcd の更新 | control-plane の `install kubelet` で 1 台ずつ 3.7.3 にする。各台の後に 3/3 healthy と版を見る（§4.4）。**混在の時間を急ぐ理由は無い**（1 台ずつの確認を省かない。dev は .113 から .111 まで約 11 分） | dev の記録、etcd の公式の文書（Upgrade etcd from v3.6 to v3.7） |
| 11 | etcd のバックアップ | 3 回取る: 段の前（`install kubernetes` の前。§2.4）、control-plane の `install kubelet` の前（§4.2）、全台 3.7 の後（3.7 の etcdctl で。§4.5） | 計画 §6.1 の 5、段 5 の手順書 §2.1 の 11 |
| 12 | storage version | 書き直しは無い。`install kubernetes` の前と後に `OLD: 0` を確かめる（後は、この PR の 1.37 の override で ClusterTrustBundle が `ok` になる。§2.5） | dev の記録 |
| 13 | CoreDNS | `install kubernetes` で ConfigMap だけが変わり、Pod は作り直さず `reload` で読む。名前の答えが上げる前と同じことと、クラスタ内の名前が cache されないことを確かめる（§3.3 の 13） | dev の記録、2026-10-23 のユーザー判断 |
| 14 | `containerRuntimeEndpoint` | 各台の `install kubelet` の後に、`kubelet.service` にフラグが無い、`config.yaml` にある、`crictl version` が通る、起動時の非推奨の warning が無い、を見る（§4.4 の 20、§5.3 の 20） | dev の記録 |
| 15 | Completed / Succeeded の Pod | Running の Pod と同じ Longhorn の PVC を使うものは、`install kubelet` の前に消す（§8.12。段の開始の承認の範囲の ✋。§0） | 段 3 の本番 |
| 16 | v1 Endpoints の warning | 段の更新を止める理由にしない。出どころを記録する（段 4 の手順書 §8.15） | 段 4 の本番 |
| 17 | leader election を使う controller の 1 回の再起動と、gated の LoadBalancer の 1 回の途切れ | 許容する。記録して、Running に戻ったことを確かめる（§8.8） | 段 C、ユーザーの判断 |
| 18 | 停止時間 | いつでもよい。ただし次の時間帯を避ける（§2.11）: **worker の unattended-upgrades 06:00〜07:00Z、control-plane の unattended-upgrades 21:00〜22:00Z、jumelle の unattended-upgrades と自動再起動 18:00〜19:30Z**。braque はバックアップの CronJob の時間帯も避ける（§5.4） | 計画 §9.6、段 7 の手順書 §2.11、前提のメモ §4 |
| 19 | resolv.conf の kube-dns | 8 台とも CoreDNS の upstream に 10.254.0.10 が入っている（前から。§2.10）。段 8 は止めない。CoreDNS の `loop` の扱いは §8.16 | 段 6 の手順書 §2.10、dev の見つけたことの 2 |
| 20 | control-plane のログの `The manifest file is empty, ignoring.`、apiserver の grpc の `operation was canceled` | 止める理由にしない（§8.17、§8.19） | 段 7 の手順書 §8.17、§8.19、dev の記録 |

### 2.2 クラスタ全体のベースライン

作業の当日、`install kubernetes` の前に次を取り、`results/stage-8/baseline.md` に残す（すべて読み取り）。段 7 の手順書 §2.2 と同じもので、次を読み替える・足す。

- 1: 全台 v1.36.5
- 2: 8 台の `tools/node-state.sh` の出力（ファイルに残す）。`/opt/bin` の向き先が `kubelet-v1.36.5`、`kubectl-v1.36.5`、`crictl-v1.36.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と 4 つのプラグインが `v1.9.1`
- 4: **etcd**: 段 5 の手順書 §2.2 の 4 と同じ（`endpoint status --cluster -w table` と `-w json` の `header.revision`（§7.4 の restore の revision の目安）、3 台の `/version`、3 台の動いている etcd のフラグ（`--experimental-` が無いこと）、3 台の etcd の Pod のログの warning の種類、`member list`）
- 5: **全 Pod の名前・UID・restartCount を控える**（§6 で「増えていない」ことを見る元になる）。CoreDNS の 2 つの Pod は restartCount が 0 でない（2026-10-23 14:2xZ は `-469lz` 7、`-shdgn` 4。§2.10）
- 14・18: Longhorn の設定とボリューム（`current-longhorn-version` が v1.13.0、17 本ともエンジンが v1.13.0）、ボリュームのアタッチ先と replica の置き場所、instance-manager（名前・ノード・IP・イメージ）
- 20: **storage version**: この PR の `tools/storage-versions.sh` の結果。`OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` が 1.36 の 2 行
- 21: Prometheus の `apiserver_requested_deprecated_apis`
- 22: Longhorn のボリュームを使う Pod と、同じ PVC を使う Completed / Succeeded の Pod（§8.12）
- 23: **CoreDNS の答え**: `tools/dns-check.sh` の出力（§3.3 の 13 の比べる元）。加えて **cache の確かめ**（§3.3 の 13 の TTL の形。上げる前は、クラスタ内の名前の 2 回目の答えの TTL が 30 より小さい（cache から）こと）と、今の Corefile（`cache 30`）
- 24: Service の数と ClusterIP の数、IPAddress の数
- 25: Prometheus の etcd と apiserver のスクレイプ（`kube-etcd` 3、`apiserver` 3、`count(etcd_server_has_leader)` 3）
- 26: cgroup（8 台の `stat -fc %T /sys/fs/cgroup`）
- 27: resolv.conf（8 台の `/run/systemd/resolve/resolv.conf` の nameserver。新しいプレフィックスの `2405:6580:6740:ac01::1` と 10.254.0.10 が入っている）
- 28: **unattended-upgrades**: 8 台の `apt list --upgradable`（`-security` のもの）、`systemctl list-timers apt-daily-upgrade.timer` の次の時刻、`/var/log/apt/history.log` の最後の実行（§2.11）。**jumelle の次の自動更新の時刻**（18:00Z〜）と、`/var/run/reboot-required` の有無（jumelle の持ち主のタスクの手順で読む。読めなければ時間帯を避けるだけでよい）
- 29: FlowSchema の名前と generation（11 個）
- 30（新）: **kubelet の設定**: 8 台の `/etc/systemd/system/kubelet.service` に `--container-runtime-endpoint` がある、`/var/lib/kubelet/config.yaml` に `containerRuntimeEndpoint` が無い、この 2 つのファイルの md5 が PR の前の master の `assets/kubelet/<ノード>/` と同じ、`journalctl -u kubelet -b` の `Flag --container-runtime-endpoint has been deprecated` の数（§4.4 の 20 の比べる元）
- 31（新）: **MetalLB の pool**: `kubectl get ipaddresspools.metallb.io -n metallb-system first-pool -o yaml` の `addresses` が `192.168.1.101/32`、`192.168.1.190-192.168.1.254`、`2405:6580:6740:ac01:ace::/96` で、`assets/kubernetes/manifests/addons/metallb/metallb.config.yaml` と同じ（§2.8）
- 32（新）: **apiserver の grpc の warning**: 3 台の apiserver のログの直近 10 分の `operation was canceled` の数（段 7 の手順書 §8.19。2026-10-23 14:2xZ は 37〜39 行。1 分に 4 行）
- 33（新。本番の段 8 で足した）: **kubelet の `cpu_manager_state`**: 8 台の `sudo cat /var/lib/kubelet/cpu_manager_state` と `ls -l` の日付。policy が `none` のとき、1.36 の kubelet の書いた形は `{"policyName":"none","defaultCpuSet":"","checksum":1353318690}`。**checksum が違う（古い kubelet の書いたもの）台があれば、その台の `install kubelet` の前に止める**（1.37 の kubelet が読めずに起きない。§8.23）

### 2.3 VIP と LoadBalancer、etcd の health を見る

段 7 の手順書 §2.3 と同じ監視（VIP と gated-v4 の 1 秒ごと、etcd の health の 2 秒ごと）を、同じ起動の形で流す（読み取り）。ログはタスクディレクトリの `notes/stage-8/` に `stage-8-probe.log`、`stage-8-etcd-<IP>.log` として足していく（`tee -a`、`>>`）。中身のコマンドは段 1 の手順書 §2.3（VIP と LB）と段 5 の手順書 §2.3（etcd の health）のものを、ログのファイル名を替えて使う。

- **監視のスクリプトを `nohup` や `&` で起動しない。** worker のハーネスのバックグラウンド実行で、**監視ごとに 1 つのジョブとして**起動する（VIP と LB で 1 つ、etcd の health は .111 と .112 で 1 つずつ。合わせて 3 つ）。ジョブの中のコマンドは前景のループのまま（`&` を付けない）にする
- 起動したら、ジョブの一覧に 3 つが居ることと、ログに行が足されていくことを確かめてから §3.2 に入る。**`install kubernetes` の前に、3 つのログの最後の行の時刻が 1 分以内であること**
- 止めるときはジョブを止める。**`ssh -n` ではノードの側の while は ssh を止めても残る**（段 5・段 7 の本番）。止めた後に .111 と .112 で `pgrep -af 'while :'` を見て、残っていれば PID を確かめて kill する
- 作業の途中で、ログの最後の行の時刻を節目（§3.2 の前と後、§4 の各台の前、§5 の各台の前）ごとに見て、監視が止まっていないことを確かめる。止まっていたら、その時刻を記録して起動し直す
- 流す期間: VIP と LB は `install kubernetes` の前から最後の worker の確認まで。**etcd の health は `install kubernetes` の前から、control-plane の 3 台目の後の §4.5 の確認まで**（段 7 と同じ）
- etcd の health の監視は、その台の etcdctl が 3.7.3 に替わってもそのまま流れる（`endpoint health` の行の形は 3.6 と同じ。§1.5）
- 任意で、`RangeStream` の切り替わり（§8.21）を見る監視を足してよい（30 秒ごとに 3 台の apiserver の `apiserver_storage_list_duration_seconds_count` を `streamed` ごとに読む。`kubectl get --raw /metrics` は VIP の先の 1 台しか読めないので、`--server https://192.168.1.11N:6443` で 1 台ずつ）。合格の基準にはしない

段 7 の本番では、VIP の FAIL は `install kubernetes` の .112 の apiserver の入れ替えの 1 回、LB は chirico の `systemd-networkd` の再起動の 1 回、etcd の unhealthy は起き直す台の 1 サンプルだけだった（`results/stage-7/summary.md` §2.5）。

### 2.4 etcd のバックアップ（段の前） ✋

`install kubernetes` の前に、porkadot 0.37.0 で取る（計画 §6.1 の 5）。段 7 の手順書 §2.4 と同じ形。

```sh
porkadot etcd backup
ls -l ./backup/
```

- この時点の etcdctl は 3.6.15（0.37.0 の `etcd backup` は、ノードの `/opt/bin/etcdctl` の `snapshot save` を流す。0.36.0 と同じ実装）
- 手元のファイルは `./backup/etcd-<日時>.db`、モード 0600。`./backup/` は `.gitignore` で除外してある。スナップショットには Secret が平文で入っているので、`git add -f` などで追加しない
- **worktree で流したときは、`./backup/` は worktree の中にできる。** worktree を片付ける前に、ユーザー（または coordinator）がメインの checkout の `backup/` へ写す（段 1〜7 と同じ）
- 時刻、ファイル名、サイズ、sha256 を記録する。段 7 のバックアップは 2 つとも 55,107,616 バイトだった。桁が違えば止める
- **このバックアップは「段の前」のもの**（1.36 の control-plane、etcd 3.6、Corefile の `cache 30`）で、§7.4 の restore の第一の候補になる。段 8 が終わり、1 日ほど様子を見るまで消さない

### 2.5 storage version（書き直しは無い）

段 8 では storage version の書き直しは無い。

**1.37 の `ResourceEncodingOverrides`**（v1.37.1 の `pkg/kubeapiserver/default_storage_factory_builder.go`。2026-10-23 に読んだ）は、1.36.5 のものから次が変わる（dev の見つけたことの 1）。

| リソース | 1.36 の保存の版 | 1.37 の保存の版 | discovery の preferred（1.37） | 本番のオブジェクト |
|---|---|---|---|---|
| `clustertrustbundles` | `v1beta1`（既定では出ない） | **`v1beta1`**（1.37 で GA・既定 on。`TODO: remove in 1.38`） | `v1` | 今は無い。**1.37 の KCM が 1 つ作る**（下） |
| `podcertificaterequests` | `v1beta1`（既定では出ない） | **`v1beta1`**（1.37 で GA） | `v1` | 無い |
| `storageversionmigrations` | `v1beta1`（既定では出ない） | **`v1beta1`**（1.37 で GA） | `v1` | 無い |
| `devicetaintrules` | `v1beta2`（既定では出ない） | **`v1beta2`**（1.37 で GA） | `v1` | 無い |
| `mutatingadmissionpolicies`、`mutatingadmissionpolicybindings` | `v1beta1` | **override が外れて `v1`** | `v1` | 無い |

ほかの 1.37 の override（`leasecandidates`、`resourcepoolstatusrequests`、`workloads`・`podgroups`・`compositepodgroups`、`evictions`・`evictionrequests`）は既定では出ない API で、本番にオブジェクトができない。

- **1.37 の KCM（`kube-apiserver-serving-clustertrustbundle-publisher-controller`）は、ClusterTrustBundle `kubernetes.io:kube-apiserver-serving:<ハッシュ>` を 1 つ作る**（dev は KCM が leader を取った 2 秒後）。apiserver はそれを `certificates.k8s.io/v1beta1` で保存する。直す前の `tools/storage-versions.sh`（discovery の preferred の `v1` を期待値にする）は、これを `OLD: 1` と数えた（dev）
- **この PR で、1.37 のときは `overrides.tsv` に上の 4 行（`/registry/clustertrustbundles/`・`/registry/podcertificaterequests/` の `certificates.k8s.io/v1beta1`、`/registry/storageversionmigrations/` の `storagemigration.k8s.io/v1beta1`、`/registry/devicetaintrules/` の `resource.k8s.io/v1beta2`）を入れる**ようにした（`storage-versions.md` §3.2）。dev の段 8 の後の出力に当てて、ClusterTrustBundle が `ok` になることを確かめた
- override どおりの版なので、書き直しは要らない。1.36 に戻すと ClusterTrustBundle は API に出なくなる（1.36 では beta で既定 off）が、etcd のキーは残る（§7.2）
- 1.37 では discovery の preferred に `storagemigration.k8s.io v1` が増える（`expected.tsv`）
- **2026-10-23 14:25Z の本番には、上の 4 種のオブジェクトのキーは無い**（`prefixes.txt`）。1.37 で消える `scheduling.k8s.io/v1alpha2` の `workloads`・`podgroups` のキーも無い

確かめること:

1. `install kubernetes` の前（§2.2 の 20）: `tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` が 1.36 の 2 行。**違えば止める**
2. `install kubernetes` の後（§3.3 の 16）: 同じく `OLD: 0`。`overrides.tsv` が 1.37 の 4 行。**`/registry/clustertrustbundles/` が `certificates.k8s.io/v1beta1` の `ok` で 1 キー**出るのは想定どおり（KCM が作るまでは 0 キー。KCM の leader が決まってから流す）。`OLD` が出たら止めて調べる
3. FlowSchema は 11 個のまま

### 2.6 render の差分（この手順書と同じ PR）

計画 §6.1 の 6〜7。2026-10-23 14:20Z に、porkadot 0.37.0（`4e8827b`。§1.4 の独立の clone）で、このリポジトリのルートを cwd にして `render kubelet` / `render etcd` / `render bootstrap` / `render kubernetes` を流した（`render all` と `render certs` は使っていない。4 つとも rc 0）。secrets は §1.6 のとおり本番と一致していることを確かめてから使った。`porkadot.yaml` は変えていない。

前の render は master の `6bfaab0` にある（段 7 の porkadot 0.36.0 の render に、k8s-manifests-fraction#50 の MetalLB の pool の直しを足したもの）。差分は次の 46 ファイルで、**これ以外の差分は無い**（新しくできたファイル、消えたファイルも無い）。dev の記録の「render の差分」と同じ形（dev の pool の直しを除く）。

| ファイル | 変わったもの | 由来 |
|---|---|---|
| `kubernetes/manifests/kube-apiserver.yaml`・`kube-controller-manager.yaml`・`kube-scheduler.yaml`・`kube-proxy.yaml` | イメージ v1.36.5 → v1.37.1、`app.kubernetes.io/version` のラベル | K8s の版（porkadot#61） |
| `kubernetes/manifests/kube-apiserver.secrets.yaml`・`kube-controller-manager.secrets.yaml`（sops） | Secret の `app.kubernetes.io/version` のラベルだけ（`v1.36.5` → `v1.37.1`、2 か所と 1 か所）。data は同じ（HEAD と作業ツリーを復号して、キーごとの sha256 を比べた。13 キーと 3 キー） | 同上 |
| `kubernetes/manifests/porkadot.yaml` | Service `porkadot-kubernetes-latest` の selector の `app.kubernetes.io/version` | 同上 |
| `kubernetes/manifests/addons/coredns/coredns.yaml` | Corefile の `cache 30` → `cache 30 {` `disable success cluster.local` `disable denial cluster.local` `}`（4 行）。イメージ（v1.14.7）は変わらない | porkadot#61 |
| `bootstrap/manifests/*.bootstrap.yaml`（4 つ） | イメージ v1.36.5 → v1.37.1、版のラベル | porkadot#61（段 8 では bootstrap は使わない） |
| `kubelet-default/install-deps.sh` | `RELEASE`（kubelet・kubectl）v1.36.5 → v1.37.1、`ETCD_VER` 3.6.15 → 3.7.3、`CRICTL_VER` v1.36.0 → v1.37.0（3 行） | porkadot#61 |
| `kubelet/192.168.1.11{1,2,3}/addons/etcd/etcd-server.yaml` | イメージ `etcd:3.6.15-0` → `3.7.3-0`（1 行。**フラグは変わらない**） | porkadot#61 |
| `kubelet/<8 台>/config.yaml`、`bootstrap/kubelet/config.yaml` | `containerRuntimeEndpoint: unix:///run/containerd/containerd.sock` を足す（1 行。9 ファイルとも同じ） | porkadot#61（`c57e656`） |
| `kubelet/<8 台>/kubelet.service`、`bootstrap/kubelet/kubelet.service` | `--container-runtime-endpoint=/run/containerd/containerd.sock \` を外す（1 行。9 ファイルとも同じ） | 同上 |
| `kubelet/<8 台>/bootstrap.crt`、`bootstrap/kubelet/bootstrap.crt` | 作り直し（同じ鍵、同じ subject・issuer・SAN・用途、assets の CA で検証が通る。期限が 2027-10-23 14:20Z に延びる） | render のたびに作り直される（§8.2） |
| `kubelet/192.168.1.11{1,2,3}/addons/etcd/etcd.crt`（sops） | 同上（同じ鍵、同じ etcd の CA、同じ subject・SAN） | 同上 |

- 平文のマニフェスト（証明書と sops の Secret を除く）の `-` と `+` の行は、版の数字（v1.36.5 → v1.37.1、v1.36.0 → v1.37.0、3.6.15 → 3.7.3）、`containerRuntimeEndpoint` の 9 行と `--container-runtime-endpoint` の 9 行、Corefile の `cache` の 5 行だけ。`app.kubernetes.io/version` が変わったのは 23 行（dev の記録と同じ数）
- **MetalLB の pool（`addons/metallb/metallb.config.yaml`）に差分は無い**（`2405:6580:6740:ac01:ace::/96` のまま。本番の `first-pool` と同じ。§2.2 の 31）
- **変わらないもの**: etcd のフラグ（`--feature-gates=InitialCorruptCheck=true`、`--watch-progress-notify-interval=5s`、`--snapshot-count=10000`。`--experimental-` は無い）、etcd の `install.sh`・`etcd.env`・`etcd.key`、`kubernetes/install.sh`（apiserver を先に入れる形）、`kubelet-default/install-pkgs.sh`・`setup-containerd.sh`、`install-deps.sh` の `CNI_VERSION`（v1.9.1）、`kubelet/<ノード>/bootstrap-kubelet.conf`・`metadata.json`・**`initiatorname.iscsi`**、`kubelet.service` のほかのフラグ（`--bootstrap-kubeconfig`、`--kubeconfig`、`--config`、`--hostname-override`、`--node-labels`）、kube-proxy の ConfigMap（`mode: iptables`）、CoreDNS のイメージ・RBAC・引数・securityContext・Deployment、cnidaria（v0.1.1）・MetalLB・kubelet-serving-cert-approver のマニフェスト
- Deployment と DaemonSet の `spec.selector` には `app.kubernetes.io/version` が入っていない（段 1〜7 と同じ）
- 作り直した証明書は、作業の当日に render し直すとまた変わる。**当日は render しない**。この PR の `assets/` で流す

確かめ方（読み取り。どれも平文をディスクに書かない）は段 7 の手順書 §2.6 と同じ。スクリプトと出力はタスクディレクトリの `notes/runbook-stage-8/`（`render.diff`、`secrets-yaml-cmp.txt`、`cert-cmp.txt`）。

### 2.7 drain しない理由と、Longhorn・iSCSI の前提

**drain しない理由**（§2.1 の 3）は段 7 の手順書 §2.7 と同じで、段 8 の根拠は次のとおり。

- 1.37 の kubelet でも、dev の 7 台でコンテナが 1 つも再起動しなかった（etcd の static Pod を除く）。drain しないでアタッチしたままの Longhorn v1.13.0 のボリュームは、faulted・remount・I/O エラーにならなかった（dev の記録の「Longhorn と iSCSI」。.121 で書き込みに 7 秒の空きが 1 回あったが、同じ時刻に dev の etcd も遅れていて、7 台の VM が同じホストのディスクを使う dev に特有と見ている。dev の見つけたことの 5）
- 0.37.0 の `install-pkgs.sh` は 0.36.0 と同じで、`initiatorname.iscsi` が同じなら iscsid を再起動しない（dev の 7 台で PID が同じ）。この PR の render は `initiatorname.iscsi` を変えていない
- 段 3〜7 の本番でも、drain しないで 8 台を流し、コンテナの再起動・`install kubelet` による iscsid の再起動・古いセッションは 1 つも無かった（`results/stage-3/summary.md`〜`results/stage-7/summary.md`）
- `containerRuntimeEndpoint` への移しは、kubelet が同じソケットに繋ぐだけで、containerd もコンテナも触らない（dev で 7 台ともコンテナの再起動は 0）

iscsid と iSCSI のセッションの確認は、段 7 の手順書 §2.7 のとおり続ける（2026-10-21 のユーザーの判断）。

- 各台の `install kubelet` の前と後に `tools/node-state.sh` を取り、iscsid の MainPID・ActiveEnterTimestamp、セッション（sid・portal・target）、エンジンの起動の時刻を比べる
- **`install kubelet` の間に、動いていた iscsid の PID が変わったら止めて報告する**（0.37.0 の `install-pkgs.sh` は再起動しないはずなので、変われば想定外）
- 古いセッション（そのノードの今の instance-manager の IP でない portal へのもの）があれば止める。chirico の portal は 2 つの instance-manager（§1.10）のどちらかなら今のもの
- `older-than-iscsid` のエンジンは、エンジンが v1.13.0 なら止める理由にしない。数を記録する

**iscsid が動いていない台（`MainPID=0`）の見分け方**（段 8 で新しく要る）:

- iscsid は `iscsid.socket` のソケット起動で、8 台とも `iscsid.socket` は `active`・`enabled`。アタッチされたボリュームが無く、誰も iscsid を呼んでいなければ、iscsid は動いていない（`MainPID=0`、`ActiveState=inactive`）。**2026-10-23 14:2xZ は oeilvert がこの状態**（10-23 06:28Z の再起動の後、アタッチが 0 のまま）
- **0.37.0 の `install kubelet` は、`install-pkgs.sh` で `systemctl start iscsid.service` を流す**（`initiatorname.iscsi` が同じとき。動いていれば何もしない）。なので、`MainPID=0` の台では **`install kubelet` の後に iscsid が新しい PID で動いているのが想定どおり**（再起動ではなく起動。セッションは 0 のまま）。`ActiveEnterTimestamp` が `install-pkgs.sh` の時刻で、`journalctl -u iscsid` にその時刻の `Started iscsid.service` があり、その前に `Stopping`・`Stopped` の行が無いこと（起動であって再起動ではないこと）を確かめて記録する
- **`install kubelet` の前に「0 → 新しい PID」になっていることもありうる**（作業の前に、Longhorn がそのノードにボリュームをアタッチし、`iscsiadm` がソケットから iscsid を起こした場合）。これは porkadot のせいではない。`journalctl -u iscsid` の起動の時刻と、そのノードへのアタッチの時刻（`kubectl get volumes.longhorn.io -n longhorn-system` の `currentNodeID` と、Longhorn の event か instance-manager のログのエンジンの起動の時刻、`tools/node-state.sh` の `engine` の行）が合うことを見て、ベースラインか各台の記録に書く。止めない
- pablo もアタッチは 0 だが、iscsid は 10-21 06:40:42Z から動いている（PID 4114921）。動いている台は、ふつうの「PID が同じ」を見る

**各ノードの iSCSI と Longhorn**（2026-10-23 14:23Z の `tools/node-state.sh`。当日に読み直す）:

| ノード | iscsid の MainPID（起動の時刻） | Longhorn のセッション | `older-than-iscsid` のエンジン | 最後の iscsid の再起動の理由 |
|---|---|---|---|---|
| 192.168.1.111 | 522641（2026-10-21 21:51:36Z） | 0 | — | needrestart（liblzma5 0.4） |
| 192.168.1.112 | 414810（2026-10-21 21:42:12Z） | 0 | — | 同上 |
| 192.168.1.113 | 290821（2026-10-20 21:30:04Z） | 0 | — | 同上 |
| braque | 271131（2026-10-21 06:23:32Z） | 0 | — | 同上 |
| chirico | 3144486（2026-10-22 06:20:27Z） | **11**（portal 10.244.8.216 に 8、10.244.8.60 に 3） | 9 | 同上 |
| duchamp | 2695716（2026-10-21 06:08:00Z） | 5（10.244.5.186） | 4 | 同上 |
| oeilvert | **0（動いていない。`iscsid.socket` は active）** | 0 | — | 10-23 06:28Z のノードの再起動の後、起動していない |
| pablo | 4114921（2026-10-21 06:40:42Z） | 0 | — | needrestart（liblzma5 0.4） |

- portal はどれもそのノードの今の instance-manager の IP で、古いセッションは無い
- 8 台の `/etc/iscsi/initiatorname.iscsi` の md5 は段 7 と同じ（この PR の render は `initiatorname.iscsi` を変えていない）
- 8 台とも `51fraction-hold-open-iscsi` は無い（2026-10-21 に消した）。open-iscsi は 2.1.9-3ubuntu5.5

### 2.8 MetalLB の告知ノードと IPv6

段 7 の手順書 §2.8 と同じ読み方（speaker のログの最後の `serviceAnnounced`。アドレスで分ける）。2026-10-23 14:2xZ の speaker のログ（直近 72 時間）の最後の `serviceAnnounced` は、VIP（192.168.1.101）pablo、gated-v4（192.168.1.200）chirico、gated-v6（`…ace::200`）pablo、`::131` .113、`::132`・`::134` duchamp、`::133` oeilvert だった。**プレフィックスの切り替えと oeilvert の再起動で、段 7 の表から変わっている。当日に読み直す。**

- 本番の LoadBalancer は 11 個（v4 3、v6 8）。v6 の 8 つはどれも `2405:6580:6740:ac01:ace::` の下（`::131`〜`::134`、`::200`、`::9991`〜`::9993`）
- **この手順書の確認で、古いプレフィックス（`2405:6581:8580:3…`）のアドレスを使わない。** v6 の LB を確かめるときは gated-v6 の `http://[2405:6580:6740:ac01:ace::200]/`（404 が返れば応答あり）か、`::131`〜`::134` の SSH のバナー。speaker のログには 10-23 02:21Z ごろまでの古いアドレスの `serviceAnnounced`・`serviceWithdrawn` が残っているので、告知ノードを読むときは新しいアドレスの行だけを見る
- oeilvert のノードの IPv6 は RA + トークン `::183`（`2405:6580:6740:ac01::183`、dynamic）。cnidaria の注釈 `cnidaria.unstable.cloud/node-ipv6` も新しい値。`install kubelet` の `dns` の addon が `systemd-networkd` を再起動しても、netplan の設定は変わらないので同じアドレスに戻る（§5.3 の 14 で見る）

### 2.9 cgroup v2 の確認

段 7 の手順書 §2.9 と同じ。2026-10-23 14:2xZ の読み取りで 8 台とも `cgroup2fs`。当日、§3.1 の承認の前に流し直す。`tmpfs` の台があれば止める。

### 2.10 CoreDNS の upstream の resolv.conf と `loop`

段 7 の手順書 §2.10 と同じ（8 台とも、CoreDNS が forward する `/run/systemd/resolve/resolv.conf` に kube-dns の 10.254.0.10 が入っている。前からのもの）。2026-10-23 14:2xZ の 8 台の nameserver は 192.168.0.1、`2405:6580:6740:ac01::1`、10.254.0.10（並びは台による）。CoreDNS の Deployment は `dnsPolicy: Default` で、ノードのこの resolv.conf を使う。

**段 7 の後に、本番でこの形の害が出た**（読み取りで確かめた。Prometheus の `kube_pod_container_status_restarts_total` と、Pod の `lastState`）:

- 2026-10-23 02:14〜02:26Z（IPv6 のプレフィックスの切り替えの最中）に、CoreDNS の 2 つの Pod が再起動を繰り返した（`-469lz` 0 → 7、`-shdgn` 0 → 4）。最後の終わり方は、`-469lz` が `[FATAL] plugin/loop: Loop (10.244.5.1:39089 -> :53) detected for zone "."`（exit 1）、`-shdgn` が `OOMKilled`（limit 170Mi）。止まる前のログには、上流（192.168.0.1、古いプレフィックスの `…:301::1`、10.254.0.10）への `i/o timeout` が並んでいた
- 上流の DNS が答えない間、`forward` が上流の 1 つの 10.254.0.10（自分たち）へ回し、問い合わせが CoreDNS の間で回って膨らみ（OOM）、起き直しの `loop` の確かめでは HINFO が自分に返って FATAL になったと見ている
- 02:26Z の後は Running のまま（restartCount 7 と 4）。ログに `loop`・`[ERROR]` は無い（14:2xZ）

段 8 への効き方:

- **`install kubernetes` で Corefile が変わり、CoreDNS は `reload` で読み直す。そのときの `loop` の確かめで FATAL になり、Pod が 1 回再起動しうる**（dev の見つけたことの 2。§3.3 の 13、§8.16）。restartCount が 1 増えてログに `plugin/loop` があり、起き直して Ready なら想定どおりとして記録して進める。CrashLoopBackOff になったら止める
- **上流の DNS が止まる時間帯（jumelle の自動再起動の 19:00Z 前後）に `install kubernetes` を重ねない**（§2.11）。上流が答えない間の reload・起き直しは、10-23 と同じく再起動が続きうる
- resolv.conf の kube-dns を外す直し（porkadot の `dns` の addon と Corefile）は段 8 の範囲の外。§10 の申し送り

### 2.11 unattended-upgrades と jumelle の時間帯

段 7 の手順書 §2.11 と同じ（unattended-upgrades の needrestart が、iscsid の使うライブラリの更新の後に iscsid を `systemctl restart` する。open-iscsi の hold とは関係なく起きる）。**作業は次の時間帯を避ける。**

| 時間帯（UTC） | 何が起きるか | 避ける理由 |
|---|---|---|
| **06:00〜07:00** | worker 5 台の unattended-upgrades（`apt-daily-upgrade.timer`、ホストの時刻の 06:00 + 最大 60 分） | needrestart の iscsid の再起動を、porkadot によるものと取り違えないため |
| **21:00〜22:00** | control-plane 3 台の unattended-upgrades（ホストの時刻は JST の 06:00〜07:00） | 同上 |
| **18:00〜19:30** | **jumelle の unattended-upgrades（18:00〜18:30）と、`/var/run/reboot-required` があるときの自動再起動（19:00）** | jumelle が落ちると、宅内の IPv4 の外向き（DS-Lite）・名前解決・IPv6 が止まる。段 8 はイメージ（registry.k8s.io）とバイナリ（dl.k8s.io、github.com）を落とすので、pull と `install-deps.sh` が失敗する。CoreDNS の上流も止まる（§2.10） |

- braque は、念のためバックアップの CronJob の時間帯も避ける（§5.4）。natsumi のバックアップ（20:30Z）と deep-researcher のバックアップ（21:00Z）は §8.12 の Pod を作る
- **段 7 の手順書 §2.11 の 4 台（.111・.112・chirico・oeilvert）の件は閉じた。** 2026-10-23 14:2xZ の読み取りで 8 台とも liblzma5 は `0.4`、`unattended-upgrades-dpkg.log` の `restart … iscsid` は 8 台とも 1 回（§2.7 の表の再起動）
- 2026-10-23 14:2xZ の `apt list --upgradable` の `-security` のものは、.113 と braque の `zlib1g`（`1:1.3.dfsg-3.1ubuntu2.3`）だけ（ほかの台は apt の index がまだ古い見込み。次の実行で 8 台とも入りうる）。**iscsid は libz を読み込んでいない**（braque の `/proc/<iscsid>/maps` と `ldd /usr/sbin/iscsid` で確かめた。iscsid が読むのは libzstd・liblzma・liblz4・libcrypto・libsystemd・libkmod など）ので、zlib1g の更新で needrestart が iscsid を再起動することは無い見込み。ほかの更新で再起動することはありうるので、時間帯を避けるのは変えない
- 次の実行（`apt-daily-upgrade.timer`）は、control-plane が 10-23 21:23〜21:36Z、worker が 10-24 06:09〜06:41Z（2026-10-23 14:2xZ）。**`install kubelet` の `daemon-reload` で次の時刻が引き直される**（段 6・段 7 の本番）ので、作業の前に読んだ時刻は当てにしない。時間帯で避ける
- 1 台の前と後の間に、動いていた iscsid の PID が変わったときは、止めてから、`journalctl -u iscsid`、`/var/log/apt/history.log`、`/var/log/unattended-upgrades/unattended-upgrades-dpkg.log` を見て、porkadot の `install kubelet` によるものか、unattended-upgrades の needrestart によるものかを記録して報告する。続けるかはユーザーが決める
- unattended-upgrades（ノードと jumelle）を止める・apt を手で流すのは、runbook の外の操作（§0）。段 8 では止めない

### 2.12 1.37 の変更で本番に当たるもの（読み取り）

porkadot#61 の本文（CHANGELOG-1.37 と k8s-updates の 1.37 のまとめを読んだもの）に加えて、本番に当たるものを読み取りで確かめた（2026-10-23 14:2xZ）。

| 1.37 の変更 | 本番 | 段 8 での扱い |
|---|---|---|
| kubelet の内蔵 cAdvisor が `cadvisor/lib` に替わり、非推奨の cAdvisor のフラグを渡すと kubelet が起きない | `kubelet.service` のフラグは `--bootstrap-kubeconfig`、`--kubeconfig`、`--config`、`--hostname-override`、`--node-labels` だけ（§2.6）。cAdvisor のフラグは無い | 当たらない |
| 同じく、`/metrics/cadvisor` の `container_cpu_load_average_10s`・`container_cpu_load_d_average_10s`・`container_tasks_state` と `container_application_*` が出なくなる | 全名前空間の PrometheusRule（37 個）と全名前空間の ConfigMap（Grafana のダッシュボードを含む）に、どの名前も 0 件 | 当たらない（§8.15） |
| 同じく、ZFS の扱いが一度外れて戻された（kubernetes#138587、1.37.0 で直った） | braque は ZFS を持つが、`/var/lib/kubelet` と `/var/lib/containerd` は 8 台とも ext4 | 当たらない見込み。braque の kubelet の起動のログに cAdvisor・ZFS の error が無いことを §5.3 で見る（dev には ZFS が無い） |
| `metrics.k8s.io` が `v1` に上がる（中身は同じ）。`kubectl top` が `v1` も使う | metrics-server v0.7.2 は `v1beta1.metrics.k8s.io` だけを出す（`Available`）。HPA は 0 個 | 当たらない。`kubectl top`（作業端末の v1.36.5）は v1beta1 を使う。metrics-server は段 8 の後に上げる（§10） |
| `scheduling.k8s.io/v1alpha2`（Workload、PodGroup）が消える。上げる前に `v1alpha2` のオブジェクトを消せ（ACTION REQUIRED） | 既定では出ない alpha の API で、etcd に `workloads`・`podgroups` のキーは無い | 当たらない |
| `SELinuxMount` が GA・既定 on（ACTION REQUIRED） | 8 台とも Ubuntu で SELinux は無効 | 当たらない |
| kubelet の `eventRecordQPS: 0` が「無制限」の意味に（ACTION REQUIRED） | porkadot の KubeletConfiguration は `eventRecordQPS` を書かない（既定の 50） | 当たらない |
| kubelet が起動のときに実効の設定をログに出す（ACTION REQUIRED。`nodes/logs` の権限を絞れ） | 新しく出るのは `Effective KubeletConfiguration` の 1 行。中身は `config.yaml` と同じで秘密は無い | 記録だけ（§4.4 の 19） |
| kube-proxy が `mode` の無いときに warning を出す | ConfigMap に `mode: iptables` がある | 当たらない。kube-proxy のログに `Using iptables Proxier` があり、mode の warning が無いことを §3.3 で見る |
| `UnknownVersionInteroperabilityProxy`（1.36 から既定 on）の混在の扱い | porkadot は `--peer-ca-file` を渡さない | §8.18 |
| `EtcdRangeStream`（beta・既定 on） | etcd 3.6 は `RangeStream` を返さない | §8.21 |

### 2.13 CoreDNS が置かれるノード

段 7 の手順書 §2.13 と同じ（CoreDNS の Pod は taint の無い amd64 の worker 4 台（chirico、duchamp、oeilvert、pablo）にしか載らない。arm64 の control-plane と braque には載らない）。段 8 では Deployment の template が変わらないので、Pod は作り直されず、置き場所も変わらない（2026-10-23 14:2xZ は chirico と duchamp）。

### 2.14 MetalLB の CRD と webhook

段 7 の手順書 §2.14 と同じ。`install kubernetes` の 2 段目で MetalLB の CRD と `validatingwebhookconfiguration…/metallb-webhook-configuration` が apply し直され（`unchanged` か `configured`）、rc 0 になる（dev の段 8 でも通った）。**`IPAddressPool` `first-pool` も apply し直されるが、中身は今の本番と同じ**（§2.2 の 31）。`ipaddresspool.metallb.io/first-pool` が `unchanged` と出ることを見る。`configured` と出たら、`addresses` が §2.2 の 31 と同じかを読み、違えば止める。

## 3. control-plane のマニフェストを上げる（`install kubernetes`）

### 3.1 事前確認

✋✋ **段 8 の開始の承認を取る。** §2.6 の表と PR の差分、§2.7 の drain しない理由と止める条件（iscsid の 0 の台の見分け方を含む）、§2.9 の cgroup の確認の結果、§2.5 の storage version の結果、§2.10 の CoreDNS の `loop` の扱い、§2.11 の時間帯、§2.12 の 1.37 の変更の読み取り、§2.2 のベースライン（22 の Completed の Pod で消すもの、§0）、§2.4 のバックアップ、§2.8 の告知ノード、§1.4 の porkadot の置き場、§7 のロールバックの形（**etcd の cluster version が 3.7.0 になった後は restore だけになること**）を示す。承認を得て PR をマージし、マージした master で §3.2 に入る。

- §2.2 のベースライン、§2.4 のバックアップ、§2.9 の cgroup の確認が済んでいる。§2.3 の 3 つの監視がハーネスのバックグラウンドのジョブとして動き、ログの最後の行が 1 分以内
- `tools/storage-versions.sh` が `OLD: 0`（§2.5 の 1）
- 全台 Ready、etcd 3/3 healthy、VIP の `/readyz` が `ok`
- checkout が §2.6 の PR をマージした master で、`git status --short assets porkadot.yaml` が空
- §1.4 の SSH の確かめで 8 台とも通る。`git -C $P describe --tags` が `v0.37.0`
- 作業の時間が §2.11 の時間帯と重ならない。**`install kubernetes` から control-plane の 3 台目まで（段 7 の本番で約 15 分、dev の段 8 で約 20 分）と、worker の 5 台（約 15 分）が、どれも時間帯の外に収まる**こと

### 3.2 流す ✋

```sh
porkadot install kubernetes --node 192.168.1.111
```

- **`--node` を必ず付ける。** 付けないと bootstrap ノード（pablo）で `kubectl apply` を流し、`127.0.0.1:6443` に届かず rc 1 になる
- **0.37 の `install kubernetes` は 0.34〜0.36 と同じ 2 段で流れる**（`assets/kubernetes/install.sh` は変わらない）: CRD と kube-apiserver のものを先に apply し、DaemonSet `kube-apiserver` の rollout の完了を待ち（`--apiserver-timeout`、既定 600 秒。完了するとログに `daemon set "kube-apiserver" successfully rolled out`）、全体を apply する。KCM・scheduler・kube-proxy が v1.37.1 で rollout する。**ConfigMap `coredns` が `configured` になる**（Deployment `coredns` は `unchanged`）。kubelet-serving-cert-approver・cnidaria はマニフェストが変わらないので動かない。MetalLB の CRD・webhook・pool は apply し直される（§2.14）
- 本番の段 7 では、全体で約 3 分（13:01:39Z → 13:04:41Z、rc 0）、VIP の FAIL は 1 回だった。dev の段 8 では apiserver の 3 台の入れ替えに約 2 分半（13:12:52〜13:15:21）、`install kubernetes` は約 3 分（13:12:41〜13:15:30）、全部の rollout の完了まで約 4 分
- 時刻と rc を記録する。ログの `successfully rolled out` の時刻と、その後の `configured` の行を記録する
- rc 1 のときの扱い（`The kube-apiserver rollout did not finish in 600s`、`dial tcp 127.0.0.1:6443: connect: connection refused`、ほかのエラー）は段 5 の手順書 §3.2 と同じ
- **0.36.0 以前の porkadot で 1.37 に上げない**（0.36.0 の render では 1.36.5 になるので、そもそも上がらない。0.37.0 の置き場を §1.4 で確かめる）
- 流した直後（全体の apply の後の 1 分ほど）に、§2.3 の 3 つの監視のログが続いていることを確かめる
- **apiserver の入れ替えの間（1.36 と 1.37 が並ぶ間）**: VIP 経由の 1.37 だけの API（`/apis/resource.k8s.io/v1/devicetaintrules` など）は、振り先によって NotFound か 200 になる。503 は出ない見込み（§8.18）。作業端末からこうした API を読まない

### 3.3 rollout の完了を確かめる

段 7 の手順書 §3.3 と同じ（版を v1.37.1 に読み替える）。CoreDNS の項目を替え、storage version を段 8 の期待値にする。

```sh
kubectl --context fraction -n kube-system rollout status daemonset/kube-apiserver --timeout=10m
kubectl --context fraction -n kube-system rollout status deployment/kube-controller-manager --timeout=10m
kubectl --context fraction -n kube-system rollout status deployment/kube-scheduler --timeout=10m
kubectl --context fraction -n kube-system rollout status daemonset/kube-proxy --timeout=10m
kubectl --context fraction version
```

| # | 確認 | 合格基準 |
|---|---|---|
| 1〜12 | 段 1 の手順書 §3.3 の 1〜12 | 同じ。Server が v1.37.1、apiserver・KCM・scheduler・kube-proxy が v1.37.1。Node は 8 台 Ready で kubelet は v1.36.5 のまま（apiserver 1.37 と kubelet 1.36 は skew policy の範囲）。DaemonSet `kube-apiserver` の generation が 1 つ増える（2026-10-23 は 30）。**KCM と scheduler のログに `Failed to watch`・`failed to list` が続いていない**（dev は 0）。**`The manifest file is empty, ignoring.` の 1 行は想定どおり**（§8.17）。kube-proxy のログに `Using iptables Proxier` があり、`mode` の warning が無い |
| 13 | CoreDNS | **Pod は作り直されない**: Deployment `coredns` の generation が変わらない（2026-10-23 は 13）、2/2、`coredns:v1.14.7`、Pod の名前と UID が §2.2 の 5 と同じ。**ConfigMap `coredns` の Corefile に `cache 30 {` `disable success cluster.local` `disable denial cluster.local` `}` が入る。1〜2 分のうちに 2 つの Pod のログに `[INFO] Reloading` → `Reloading complete` が出る。** restartCount は変わらないのが基本。**1 増えて、前のコンテナのログ（`--previous`）の最後が `[FATAL] plugin/loop: Loop (…) detected for zone "."` で、起き直して Ready（新しい Corefile の SHA512 の `Running configuration`）なら、想定どおりとして記録して進める**（§8.16）。2 以上増える、または CrashLoopBackOff になったら止める。`tools/dns-check.sh` の答えが §2.2 の 23 と同じ。**クラスタ内の名前が cache されないこと**（下の TTL の確かめ） |
| 14 | approver | `kubelet-serving-cert-approver` が `0.12.1` のまま 1/1。generation が変わらない |
| 15 | CSR | 新しい CSR が無い（段 4 の手順書 §3.3 の 15） |
| 16 | storage version | KCM の leader が決まってから（ClusterTrustBundle ができてから）、`tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`。`overrides.tsv` が 1.37 の 4 行。`/registry/clustertrustbundles/` が `certificates.k8s.io/v1beta1` の `ok` で 1 キー（§2.5 の 2）。`kubectl --context fraction get clustertrustbundles` に `kubernetes.io:kube-apiserver-serving:<ハッシュ>` が 1 つ |
| 17 | ServiceCIDR と IPAddress | 段 7 の手順書 §3.3 の 17 と同じ（`servicecidrs` に `kubernetes` が 1 つで Ready、CIDRS が `10.254.0.0/24,fd20:afc2:7c09::/108`、IPAddress の数が §2.2 の 24、`ClusterIPNotAllocated` の event が出ない） |
| 18 | v1 Endpoints の warning | 段 4 の手順書 §3.3 の 18 と同じ（記録だけ。`removed_release` が `1.37` 以前のものが出ていないこと） |
| 19 | FlowSchema | §2.2 の 29 と同じ 11 個。generation が変わっていれば記録する |
| 20 | MetalLB | `install kubernetes` の出力の `ipaddresspool.metallb.io/first-pool` が `unchanged`。pool の `addresses` が §2.2 の 31 と同じ（§2.14） |

**CoreDNS の cache の確かめ方**（13。読み取り。dev の記録の「CoreDNS」の TTL の形）: ノード（pablo）から、2 つの CoreDNS の Pod の IP に直接、同じ名前を 3 秒おいて 2 回問い合わせ、2 回目の答えの TTL を見る。

```sh
for ip in $(kubectl --context fraction -n kube-system get pods -l k8s-app=kube-dns -o jsonpath='{.items[*].status.podIP}'); do
  ssh yuanying@192.168.1.134 "for n in kubernetes.default.svc.cluster.local kubernetes.default.svc.fraction.cluster github.com; do dig +noall +answer @$ip \$n A >/dev/null; sleep 3; echo $ip \$(dig +noall +answer @$ip \$n A | head -1); done"
done
```

- 上げた後: `kubernetes.default.svc.cluster.local` の TTL は **30 のまま**（毎回 kubernetes plugin が答える。cache されない）。`kubernetes.default.svc.fraction.cluster` は **30 より小さい**（`additional_domains` の `fraction.cluster` は `disable` の対象の外で、30 秒 cache される。2026-10-23 のユーザー判断のとおり）。`github.com` は上流の TTL から減る（cache される）
- 上げる前（§2.2 の 23）: `cluster.local` の名前も 30 より小さい（cache から）
- 任意（✋）: §5.5 の NetworkPolicy の確認の間に、一時的な名前空間 `k8u-npcheck` に ClusterIP の Service を `kubectl-admin create service clusterip k8u-dns --tcp=80:80` で作り、すぐに `k8u-dns.k8u-npcheck.svc.cluster.local` が 2 つの Pod から引けること、`kubectl-admin delete service` の直後に NXDOMAIN になることを見てよい（dev の `dns-cache-test.sh` の形。上げる前は 19〜30 秒かかった）。名前空間ごと `npcheck.sh down` で消える

その他の注:

- `install kubernetes` の出力の `configured` に、マニフェストの変わらない `poddisruptionbudget.policy/kube-controller-manager`・`kube-scheduler`、`validatingwebhookconfiguration…/metallb-webhook-configuration` が出るのは前から（段 5〜7 の本番）。generation が変わらなければ想定内
- apiserver の rollout の途中に、controller-manager の `FailedToUpdateEndpoint` などが 1 回ずつ出ることがある（段 4 の手順書 §3.3 の注）。続かなければ想定内。dev では、止められる古い KCM の status の PUT が `http: Handler timeout` を 3 回出した（dev の見つけたことの 6）
- 段 7 の本番では、.111 の新しい apiserver の起動の直後に `error resolving kube-system/metrics-server` と KCM の rollout の終わりの `read version … is not as new as written version` が出た（`results/stage-7/summary.md` §2.2）。同じものは想定内として記録する
- **`install kubernetes` の直後（全体の apply の後の 1 分ほど）に etcd の health と VIP を特に見る**（§8.13）
- ここで問題があれば、kubelet にも etcd にもまだ触っていないので、§7.2 で control-plane だけを戻せる（ただし §7.2 の注）

## 4. control-plane の kubelet と etcd を上げる（192.168.1.113 → .112 → .111）

### 4.1 何が起きるか

`install kubelet --node <IP>` は、`install-deps.sh`（kubelet・kubectl・crictl を落として張り替え、**etcd 3.7.3 の tarball から etcdctl と etcdutl を張り替える**。CNI plugins は版の印が v1.9.1 で同じなので展開しない）、`install-pkgs.sh`（`apt-get install --no-upgrade`、iscsid は `systemctl start` だけ）、`install.sh`（addon の `dns`、`multipathd`、`etcd`）を root で流し、**新しい `kubelet.service`（フラグなし）と `config.yaml`（`containerRuntimeEndpoint` あり）を置いて `daemon-reload` し**、kubelet を v1.37.1 で再起動する。

**`etcd` の addon が `etcd-server.yaml` を 3.7.3 のものに置き換えるので、その台の etcd がここで 3.7.3 になる。** 新しい kubelet が mirror Pod を作り直し、etcd のコンテナが 3.7.3 のイメージで起き直す。ほかのコンテナは再起動しない見込み（dev の記録）。

| 段階 | etcd の版（.111 / .112 / .113） | cluster version・storage | 見込み |
|---|---|---|---|
| 前 | 3.6.15 / 3.6.15 / 3.6.15 | 3.6.0 | — |
| .113 の後 | 3.6.15 / 3.6.15 / **3.7.3** | 3.6.0 | 3.6 のリーダーが `leader found higher-versioned member` を出し続ける（想定どおり）。**ここまでなら 3.6 に戻せる**（§7.3） |
| .112 の後 | 3.6.15 / **3.7.3** / 3.7.3 | 3.6.0 | 同上 |
| .111 の後 | **3.7.3** / 3.7.3 / 3.7.3 | **3.7.0** | リーダーのログに `updated cluster version`（`from 3.6 to 3.7`）と `updated storage version`。**この後は 3.6 には戻せない**（§7.4） |

- 3.7 の etcd は、起動の直後に `failed to publish local member to cluster through raft` を数十〜百回、数ミリ秒の間に出してから `published local member` になる（dev は .113 で 102 回、.112 で 110 回、.111 で 55 回。段 7 の本番の 3.6 の .112 は 103 回）。回数ではなく、`published` が出て続かないことを見る
- 最初のコンテナは古い etcd が 2380 番を離す前に起きて `bind: address already in use` で落ち、次で起きることがある（段 7 の本番は 3 台とも restartCount 1。dev の段 8 は 0）。その間ほかの 2 台で quorum を保つ
- `/etc/etcd/pki` の証明書と鍵を root 0600 で置き直す。`etcd.crt` は作り直したもの（同じ鍵、同じ CA。§2.6）に替わる
- `dns` の addon は `systemd-networkd` を再起動するので、cnidaria の `no route` のログが出る（§8.1）
- control-plane には Longhorn のボリュームが無く、iscsid は動いていてセッションは無い（§2.7）
- 1.37 の apiserver は、3.6 のメンバーに当たる間は `RangeStream` を使わず、全台 3.7 になってから最長 10 分で切り替わる（§8.21）。混在中にエラーは出ない見込み

### 4.2 節目と、2 つ目のバックアップ

1. ✋ etcd のバックアップを取る（§2.4 と同じ形）。**1.37 の control-plane、Corefile の新しい `cache`、etcd 3.6 の最後の状態**（kubelet はまだ 1.36）。§7.4 の restore で、段の前（§2.4）の代わりに使える
2. ✋✋ **control-plane の kubelet（etcd 3.7）の前の承認を取る。** §3.3 の結果（CoreDNS の reload と `loop` の有無、storage version、ClusterTrustBundle を含む）、1 のバックアップ、§7 のロールバックの形を示す。**示すこと: 混在中（.113・.112 の後）は 0.36.0 の `install kubelet` でその台を 3.6.15 に戻せる見込み（dev で確かめていない）。.111 の後に cluster version が 3.7.0 になると 3.6 のメンバーには戻せず、戻すのは §2.4 か 1 のバックアップの 0.37 の `etcd restore` だけになる（dev で確かめた。API が約 2 分止まり、バックアップの後の変更は失われる）**
3. §2.3 の etcd の health の監視が動いていることを確かめる（`install kubernetes` の前から動かしている）

### 4.3 1 台の手順

段 7 の手順書 §4.3 と同じ（1. 読み取りの確認と `snap`・`tools/node-state.sh` の控え、2. ✋ リーダーなら `move-leader`、3. ✋ `porkadot install kubelet --node <IP>`、4. kubelet の起動から 1 分ほど待って §4.4）。足すもの:

- 1 で、etcd のリーダーと各メンバーの `/version`、その台の動いている etcd のフラグ、`systemctl cat kubelet` と `/var/lib/kubelet/config.yaml` の `containerRuntimeEndpoint` の有無を控える
- 2026-10-23 14:2xZ のリーダーは .113（`57ec6f12ac7b683e`）。このままなら、.113 の作業の前に .111（`21ab2aeb56731588`）か .112（`fbb0c648cf5852a5`）へ移す。その後も、各台の作業の前にリーダーを読み、対象がリーダーなら移す（dev では .112、.111 の前に移した。3.7 のメンバーへ移すのでもよい）
- 1 台ずつ、§4.4 の確認が済んだら次の台に入る。**混在の時間を急ぐ理由は無い**（§2.1 の 10）
- 段 7 の本番では 1 台 24 秒〜35 秒だった。段 8 は etcd の tarball（arm64 で 22 MB）も落とすので、少し長くなりうる

### 4.4 1 台ごとの確認と、次の 1 台へ進む条件

段 7 の手順書 §4.4 と同じ。次を読み替え、20 を足す。

| # | 確認 | 合格基準（段 7 から変わるところ） |
|---|---|---|
| 1 | Node | VERSION が v1.37.1。kubelet が起きている |
| 2 | バイナリ | 向き先が `kubelet-v1.37.1`、`kubectl-v1.37.1`、`crictl-v1.37.0`、**`etcdctl-3.7.3`、`etcdutl-3.7.3`**。CNI の印と 4 つのプラグインは `v1.9.1` のまま。前の版のファイル（`kubelet-v1.36.5`、`etcdctl-3.6.15` など）も残っている（§7 の戻しで使う） |
| 4 | etcd | 3/3 healthy、リーダーが居る、raft index がそろう（**`-w json` で比べる**。§1.5）。**その台が 3.7.3、ほかはまだ上げていないものが 3.6.15**。`member list` が 3 つとも `started` |
| 5 | etcd の Pod | 1/1 Running、`etcd:3.7.3-0`。mirror Pod の UID が変わる。**restartCount 0〜2 は想定どおり**。3 以上、または CrashLoopBackOff が 1 分を超えたら止める。起き直しの直後のほかのメンバーの `lost TCP streaming connection`・`peer became inactive` は数秒で止まる |
| 7 | Pod の再起動 | **差分は `kube-system/etcd-<IP>` の UID と restartCount だけ**。ほかに UID・restartCount が変わったものがあれば止める |
| 8 | iscsid | MainPID と ActiveEnterTimestamp が前（§4.3 の 1 の `node-state.sh`）と同じ。変わっていたら止める（§2.7、§2.11） |
| 16 | etcd の版 | その台の `/version` が `{"etcdserver":"3.7.3","etcdcluster":"3.6.0","storage":"3.6.0"}`（3 台目の後は §4.5）。まだの台は `{"etcdserver":"3.6.15","etcdcluster":"3.6.0","storage":"3.6.0"}` |
| 17 | etcd のフラグ | その台の動いている etcd の cmdline に `--feature-gates=InitialCorruptCheck=true`、`--watch-progress-notify-interval=5s`、`--snapshot-count=10000` があり、`--experimental-` で始まるものが無い（3.6 と同じ）。`kubectl --context fraction -n kube-system logs etcd-<IP> \| grep -iE 'unknown flag\|invalid'` が何も出さない |
| 18 | etcd のログ | 想定どおりのもの: 3.6 のリーダーの `leader found higher-versioned member`（混在中ずっと）、3.7 の起動の直後の `failed to publish local member to cluster through raft`（数ミリ秒の間だけで、`published local member` が続く）、`bind: address already in use`（落ちた最初のコンテナ）、前から出ている `check file permission`（`/var/lib/etcd` が 755）・`Running http and grpc server on single port`・`simple token is not cryptographically signed`、起き直しの直後の `apply request took too long`・`request stats`・`waiting for ReadIndex response took too long`・`ignored out-of-date read index response`（段 7 の本番）。ほかの warn・error の種類が増えたら記録し、続くものがあれば止める |
| 19 | kubelet のログ | 起動の直後の項目は段 7 と同じ（etcd の mirror Pod の `already exists`、`DeleteContainer returned error`、`Failed to read data from checkpoint`、`could not load v4 checkpoint`、止まる前の古い kubelet の `missing content for CA bundle` など）。**1.37 の kubelet は起動のときに `Effective KubeletConfiguration` を 1 行出す**（§2.12）。ほかに増えたものは記録する |
| 20（新） | `containerRuntimeEndpoint` | `systemctl cat kubelet` の `ExecStart` に `--container-runtime-endpoint` が無い。`/var/lib/kubelet/config.yaml` に `containerRuntimeEndpoint: unix:///run/containerd/containerd.sock` がある。`sudo /opt/bin/crictl version` が `RuntimeName: containerd`、`RuntimeVersion: v2.3.6` を返す。新しい kubelet の起動の後の `journalctl -u kubelet` に `Flag --container-runtime-endpoint has been deprecated` が無い（段 7 まではどの台も出ていた。§2.2 の 30）。`Effective KubeletConfiguration` の行に `containerRuntimeEndpoint` がある |

次の 1 台へ進む条件も段 7 の手順書 §4.4 と同じ（すべて合格、全 8 台 Ready、etcd 3/3 healthy で raft index がそろう、Running / Completed 以外の Pod がベースラインから増えていない）。

- 1 台の etcd が 3.7 で起きない（CrashLoopBackOff、`unknown flag`、データのエラー）ときは、ほかの 2 台で quorum が保たれている。**次の台に進まず、止めて報告する**（§7.3 で、その台を 3.6 に戻すかをユーザーが決める）
- 1 台の kubelet が 1.37 で起きない（containerd に繋がらないなど）ときも、次の台に進まず、止めて報告する

### 4.5 control-plane の 3 台の後

.111 の §4.4 の後に、次を確かめる。

- 3 台の `/version` が `{"etcdserver":"3.7.3","etcdcluster":"3.7.0","storage":"3.7.0"}`
- 3 台のどれかのログに `updated cluster version`（`from 3.6 to 3.7`）、続いて `cluster version differs from storage version.` の後に `updated storage version`（dev の記録の「etcd 3.7」）
- `etcdctl endpoint status --cluster -w json` の 3 つとも `Status.version` が 3.7.3、リーダーが居る、raft index がそろう
- ✋ etcd のバックアップを取る（§2.4 と同じ形。**3.7 の etcdctl の `snapshot save` で取れること**を確かめる。porkadot#61 で、3.7 の `endpoint status -w json` の `header.revision` と `snapshot save` の形が変わらないことは確かめてある）。時刻、サイズ、sha256 を記録する
- §2.3 の etcd の health の監視（2 つのジョブ）を止める（ノードの側の while も止める）
- 任意: 全台 3.7 になってから 10 分ほどの後に、3 台の apiserver の `apiserver_storage_list_duration_seconds_count{streamed="true"}` が増えていること（§8.21）

## 5. worker の kubelet を上げる（1 台ずつ、drain しない）

### 5.1 順番

アタッチされた Longhorn のボリュームが少ない台から多い台へ並べる（段 7 の手順書 §5.1 と同じ考え方）。2026-10-23 14:2xZ のアタッチの数（pablo 0、oeilvert 0、duchamp 5、chirico 11）から、**pablo → oeilvert → braque → duchamp → chirico** にする。当日の読み取りでアタッチの数が変わっていれば並べ直してよい。braque はどこに入れてもよい（§5.4 の時間帯を避ける）。

- 最初の worker の pablo は API の VIP（と gated-v6）を告知している（§2.8）。段 7 の本番でも pablo の `install kubelet` の間、VIP は途切れなかった
- oeilvert は iscsid が動いていない（§2.7）。`install kubelet` の後に iscsid が新しい PID で動いているのは想定どおり（§5.3 の 3）
- worker には etcd が無い。`/opt/bin` の etcdctl と etcdutl も 3.7.3 に替わる（使わない）

### 5.2 1 台の手順

段 7 の手順書 §5.2 と同じ（§8.12 の Pod の削除も同じ扱い）。段 7 の本番では 1 台 20 秒〜35 秒だった。段 8 は etcd の tarball も落とすので、少し長くなりうる。

- **`--node` にはノードの名前を渡す**（`porkadot install kubelet --node pablo`。IP ではない。§1.4）。流した後に porkadot のログの SSH 先（`as yuanying@<IP>`）がその台だけであることを確かめる
- 流す前に、その台の `cpu_manager_state` が §2.2 の 33 の形であることを確かめる（§8.23）
- 本番の段 8 では、pablo に IP を渡して 5 台が同時に上がった。各台の確認は後からまとめて行い、合格した（`results/stage-8/workers.md`）

### 5.3 1 台ごとの確認

段 7 の手順書 §5.3 と同じ。次を読み替え、20 を足す。

| # | 確認 | 合格基準（段 7 から変わるところ） |
|---|---|---|
| 1 | Node | VERSION が v1.37.1 |
| 2 | バイナリ | 向き先が `kubelet-v1.37.1`、`kubectl-v1.37.1`、`crictl-v1.37.0`、`etcdctl-3.7.3`、`etcdutl-3.7.3`。CNI の印と 4 つのプラグインは `v1.9.1` のまま。`kubelet-v1.36.5` なども残っている |
| 3 | iscsid | **MainPID と ActiveEnterTimestamp が前と同じ**。変わっていたら止める（§2.7、§2.11）。**前が `MainPID=0` の台（oeilvert）は、`install-pkgs.sh` の時刻に起きた新しい PID が想定どおり**（`journalctl -u iscsid` に `Started` があり、`Stopping`・`Stopped` が無いこと。§2.7） |
| 4 | iSCSI のセッション | 同じ sid・portal・target。portal がそのノードの今の instance-manager の IP（chirico は 2 つのどちらか。§1.10）。古いセッションが無い |
| 5 | エンジン | 同じボリューム、同じ起動の時刻。`older-than-iscsid` の数が前と同じ |
| 7 | Pod の再起動 | **差分が無い**（名前・UID・restartCount が同じ）。1 つでもコンテナの再起動があれば、ここで止めて報告する（§2.1 の 3） |
| 11 | kubelet のログ | §4.4 の 19 と同じ。**braque は、cAdvisor・ZFS の error が無い**（§2.12） |
| 14 | 告知していた LoadBalancer | 段 7 と同じ（応答する）。v6 は新しいプレフィックスのアドレスで見る（§2.8）。oeilvert はノードの IPv6 が `2405:6580:6740:ac01::183` のまま |
| 20（新） | `containerRuntimeEndpoint` | §4.4 の 20 と同じ |

ほか（Longhorn の node の一瞬の `is down`・`Waiting for disk`、`FailedMount` の `no Pending workload pods`）は段 7 の手順書 §5.3 と同じ。

### 5.4 braque の手順

段 7 の手順書 §5.4 と同じ（バックアップの CronJob の時間帯を避ける。2026-10-23 の CronJob は `fs/h2-backup` 05:44Z、`fs/sites-backup` 07:53Z、`fs/data-backup` 09:03Z、`natsumi` の 3 つ 20:30Z、`fraction-agents/deep-researcher-backup` 21:00Z、`aphrael/tumblr-like` 3 時間ごとの :38）。

### 5.5 次の 1 台へ進む条件

段 7 の手順書 §5.5 と同じ（版を読み替える。終えたノードが v1.37.1、まだのノードが v1.36.5）。

- **最初の worker（pablo）の後に、✋ `netcheck.sh` と §1.9 の NetworkPolicy の確認を流す**（1.37 の apiserver と、1.37 の kubelet のノードを含む形で、cnidaria の NetworkPolicy の処理が動くこと）。§3.3 の 13 の任意の確かめ（Service を作ってすぐ引ける・消してすぐ NXDOMAIN）は、ここで流してよい

## 6. 段 8 の完了の確認

8 台を終えたら、計画 §6.3 の項目がすべて成り立つことを確かめ、`results/stage-8/summary.md` に残す。**計画の最後の段なので、TASK の完了条件の本番の項目もここで確かめる。** 段 7 の手順書 §6 と同じ項目で、次を読み替える・足す。

- 8 台が Ready、全台 v1.37.1、CONTAINER-RUNTIME が `containerd://2.3.6`。どのノードも SchedulingDisabled でない
- 8 台の `/opt/bin` が `kubelet-v1.37.1`、`kubectl-v1.37.1`、`crictl-v1.37.0`、`etcdctl-3.7.3`、`etcdutl-3.7.3`。CNI の印と 4 つのプラグインが `v1.9.1`
- **etcd**: 3/3 healthy、全メンバーが 3.7.3、cluster version・storage とも 3.7.0（§4.5）、リーダーが居る、raft index がそろう。3 台の動いている etcd のフラグに `--experimental-` が無い。3 台の `/etc/etcd/pki` が `600 root:root`
- VIP の `/livez` が `ok`、`/version` が v1.37.1
- **CoreDNS が v1.14.7 で 2/2 Running**（amd64 の worker）。Corefile が新しい `cache`。ログにエラーが無い（§3.3 の 13 で想定どおりとした `loop` の 1 回を除く）。`tools/dns-check.sh` をもう一度流し、§2.2 の 23 と同じ答え。§3.3 の 13 の TTL の確かめが同じ結果
- **全 Pod の restartCount が、ベースライン（§2.2 の 5）から増えていない**（control-plane の etcd の mirror Pod は UID が変わり restartCount 0〜2。`install kubernetes` で作り直された Pod（apiserver 3、KCM 2、scheduler 2、kube-proxy 8）は新しい UID で 0。CoreDNS の `loop` の 1 回は §3.3 の 13 に記録したもの）
- **storage version**: `tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` が 1.37 の 4 行、`/registry/clustertrustbundles/` が `ok` で 1 キー
- **StrictIPCIDRValidation**: `tools/ipcidr-scan.py` が `# findings: 0` のまま（段 7 の手順書 §2.12）
- **ServiceCIDR と IPAddress**: `servicecidrs` が `kubernetes` の 1 つで Ready、IPAddress の数が ClusterIP の数と同じ。FlowSchema が 11 個
- **cgroup**: 8 台とも `cgroup2fs` のまま、kubelet が 8 台とも動いている
- **`containerRuntimeEndpoint`**: 8 台とも `kubelet.service` にフラグが無く、`config.yaml` にある。**kubelet の起動時の warning（`Flag --… has been deprecated`）が 8 台とも 0**（段 7 までの `--container-runtime-endpoint` の warning が消えた。計画 §10）
- Longhorn、Longhorn の設定、iSCSI（8 台の iscsid の PID とセッションがベースラインと同じか、変わったものは §2.7・§2.11 の見分けの結果）、cnidaria（✋ `netcheck.sh`、✋ §1.9 の NetworkPolicy の確認）、MetalLB（v4 と、v6 は新しいプレフィックスのアドレス。§2.8）、braque の NFS、`registry.fraction.jp`、CSR、§2.3 の監視の FAIL、leader election で再起動した controller: 段 7 の手順書 §6 と同じ。**K8s 1.37 は Longhorn v1.13.0 の要件（1.34 以上）に入る**（§1.10）
- `kubectl --context fraction top nodes` が応答し、Prometheus のスクレイプが落ちていない（`up == 0` が 0 個。`kube-etcd` の 3 つを含む）。`count(etcd_server_has_leader)` が 3。Grafana の etcd のダッシュボードが値を出す（etcd 3.7 のサーバーの metrics。段 5 の手順書 §8.15）
- `apiserver_requested_deprecated_apis` を記録する（`removed_release` が `1.37` 以前のものが出ていれば止めて調べる）。v1 Endpoints の warning の出どころも段 7 と同じ形で記録する（段 7 では Longhorn v1.13.0 の longhorn-manager・longhorn-global-manager と prometheus-operator v0.90.1）
- 新しい warning のイベント・ログ（kubelet、apiserver、kube-proxy、cnidaria、etcd、Longhorn、CoreDNS）が増えていない（§8 のもの、v1 Endpoints の warning は除く）
- etcd のバックアップ（§2.4、§4.2、§4.5 の 3 つ）を worktree からメインの checkout の `backup/` へ写した（worktree で流した場合）

## 7. ロールバック

**戻すのは runbook から外れる操作なので、その都度ユーザーの承認を取る。** 戻すと決める目安は段 1 の手順書 §7 と同じ（rollout が終わらない、VIP が 1 分を超えて応答しない、Node が 5 分たっても Ready にならない、etcd が 2/3 を下回る、Pod の再起動が続く、Longhorn のボリュームが degraded のまま戻らない、1.37 や etcd 3.7 に固有と見られる問題）。

**段 8 は etcd のマイナー更新を含むので、戻し方がどこまで進んだかで大きく変わる**（段 5 と同じ形）。

| どこまで進んだか | etcd | 戻し方 | dev で確かめたか |
|---|---|---|---|
| `install kubernetes` の後（kubelet と etcd はまだ前の版） | 3/3 が 3.6.15 | §7.2（0.36.0 で `install kubernetes`） | **確かめていない**（1.37 の scheduler・KCM が 1.36 の apiserver の返さない API を待ちうる。§7.2） |
| control-plane の kubelet の途中（混在中） | 3.6 と 3.7、cluster version 3.6.0 | 上げた台を §7.3 で 3.6 に戻す | **確かめていない**（etcd の公式の文書と porkadot#61 の手元の確かめは、混在中ならイメージを戻せるとしている） |
| control-plane の 3 台の後（cluster version 3.7.0） | 3/3 が 3.7.3 | **イメージを戻すだけでは戻せない。** §2.4（段の前）か §4.2 の backup へ §7.4 の restore で戻す | **dev で確かめた**（0.37 の restore。3.7.3 のまま 3.6 の snapshot を戻せた） |
| worker の途中・全部の後 | 3/3 が 3.7.3 | kubelet だけなら §7.6 で worker を 1.36 に戻せる。control-plane（1.36）まで戻すなら §7.4 と §7.5 | kubelet の 1.37 → 1.36 は確かめていない |

### 7.1 戻すための材料

- **前の版**: この PR の前の master（**`6bfaab0`**）の `assets/` と `porkadot.yaml`、**porkadot 0.36.0**（`v0.36.0`、`7247f15`）。この `assets/` は本番が今動いているもの（段 7 の 0.36.0 の render に、k8s-manifests-fraction#50 の MetalLB の pool の直しを足したもの）。**段 7 の render のコミット（`db2da8e`、`fd09aac`）を使わない**（MetalLB の pool が古いプレフィックスの `…:301:ace::/96` に戻る）
- **porkadot 0.36.0 の置き場**: §1.4 の `worktrees/porkadot-v0-36-0`（段 7 で使ったもの。`bundle install` 済み）
- **restore**: 今の版（この PR をマージした master の `assets/`）と **porkadot 0.37.0**（§1.4）。0.37.0 の `etcd restore` は 0.34.1〜0.36.0 と同じ実装で、3.7.3 の etcdutl を使う
- **etcd のバックアップ**: §2.4（段の前、1.36 の control-plane、etcd 3.6、Corefile の `cache 30`）、§4.2（1.37 の control-plane、新しい Corefile、etcd 3.6）、§4.5（全台 3.7 の後）

用意の仕方（作業端末で。ノードには触らない。段 7 の手順書 §7.1 と同じ形）:

```sh
P_OLD=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/worktrees/porkadot-v0-36-0   # git -C $P_OLD describe --tags が v0.36.0
git clone <このリポジトリの checkout> /tmp/fraction-stage-7
git -C /tmp/fraction-stage-7 checkout 6bfaab0
cd /tmp/fraction-stage-7
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

- `git worktree add` は元の clone の `.git` に書き込むので、サンドボックスでは拒否される。`/tmp` に clone して使う
- 始める前に `grep VERSION $P_OLD/lib/porkadot/version.rb` が 0.36.0 で、`BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot help` が動くこと、`/tmp/fraction-stage-7/assets/kubernetes/manifests/addons/metallb/metallb.config.yaml` の pool が `2405:6580:6740:ac01:ace::/96` であることを確かめておく

0.36.0 の `install kubelet` について:

- `/opt/bin/<名前>` の向き先で判定して張り替える。前の版のバイナリ（`kubelet-v1.36.5`、`crictl-v1.36.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`）はノードに残っているので、落とし直さずに向き先を戻す
- **`kubelet.service` に `--container-runtime-endpoint` が戻り、`config.yaml` から `containerRuntimeEndpoint` が消える**（フラグは config より優先するので、どちらの形でも kubelet は containerd に繋がる。porkadot#61 の本文）
- **control-plane では etcd のマニフェストを 3.6.15 に戻す。** 混在中（cluster version 3.6.0）なら、その台の etcd は 3.6.15 で起き直す見込み（§7.3）。**全台 3.7 の後に流すと、3.7 のデータ（storage 3.7.0）では 3.6.15 の etcd は起きない見込み**（dev の記録。確かめていない）。全台 3.7 の後に 0.36.0 の `install kubelet` を control-plane に流さない（§7.5）
- `install-pkgs.sh` は 0.37.0 と同じ（iscsid は `initiatorname.iscsi` が変わったときだけ再起動する）
- 1.37 → 1.36 の kubelet の戻しでコンテナが再起動するかは、dev で確かめていない。**Longhorn のボリュームがアタッチされた台を戻すときは、再起動する前提で drain してから流す**（段 7 の手順書 §7.1 と同じ。drain の後・`install kubelet` の前と後に `iscsiadm -m session` を見る）
- 0.36.0 の SSH は 0.37.0 と同じで、サンドボックスの中で流せる

### 7.2 `install kubernetes` の後、kubelet と etcd はまだ前の版 ✋

```sh
cd /tmp/fraction-stage-7
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml
```

- **kubelet が 1.37 の台が残っているうちは流さない**（kubelet は apiserver より新しくてはいけない。先に §7.6 で戻す。etcd が 3.7 の台があるときは §7.4 か §7.5）
- 0.36.0 の `install.sh` も apiserver を先に入れて rollout を待つので、**apiserver が先に 1.36.5 になり、その間 1.37 の KCM・scheduler が 1.36 の apiserver と話す**。1.37 の scheduler・KCM は、1.36 の apiserver の返さない `resource.k8s.io/v1` の DeviceTaintRules、`certificates.k8s.io/v1` の PodCertificateRequests、`storagemigration.k8s.io/v1` を watch する（porkadot#61 の本文）。同期済みのものは watch のエラーを出すだけだが、**その間に再起動した 1.37 の scheduler・KCM は、1.36 のものに替わるまでこれらを待って動かない**（段 5 の手順書 §3.2 のデッドロックと同じ形。新しい Pod のスケジュールが止まる）。DaemonSet `kube-apiserver` の rollout は 1.37 の scheduler が Pod を割り当てないと進まないので、**dev で流していない**。新しい Pod のスケジュールが止まったまま進まないときは、止めて報告する（立て直しは段 5 の手順書 §8.3 の形。runbook から外れる操作）。止める理由が 1.37 の control-plane に固有でなく、kubelet・etcd にまだ触っていないなら、§7.4 の restore（§2.4 の backup）のほうが確かめた道（dev）であることも示す
- apiserver・KCM・scheduler・kube-proxy が v1.36.5 に、**Corefile が `cache 30` に戻る**（CoreDNS が reload する。§8.16 の `loop` が出うる）
- storage version: 1.37 の KCM が作った ClusterTrustBundle の etcd のキー（`certificates.k8s.io/v1beta1`）は残り、1.36 の apiserver は ClusterTrustBundle を提供しない（既定 off）ので、API には出ない。`tools/storage-versions.sh`（1.36 の期待値）は、そのキーを `certificates.k8s.io` の preferred の `v1` と比べて `OLD: 1` と数える（1.36 の override には入っていない）。害は無い見込み（確かめていない）。記録して、ほかの `OLD` が無いことを見る
- FlowSchema: 1.37 は消さない・足さない見込み（dev で 11 個のまま）
- rc 1（`connection refused`）なら rollout を待って流し直す（段 5 の手順書 §3.2 と同じ）
- §3.3 と同じ確認を、版を読み替えて行う（Corefile は `cache 30`、`tools/dns-check.sh` の答えが §2.2 の 23 と同じ、`overrides.tsv` は 1.36 の 2 行）

### 7.3 control-plane の kubelet の途中（etcd が混在） ✋

etcd の公式の文書（Upgrade etcd from v3.6 to v3.7）と porkadot#61 の本文は、「少なくとも 1 つのメンバーが 3.6 のまま残る混在の状態なら、クラスタは 3.6 の cluster version で動き、イメージを戻せる」としている。porkadot#61 では手元で 3.6.15 → 3.7.3 の 1 台ずつの入れ替えを確かめたが、**混在中に 3.6 に戻すことは dev でも手元でも確かめていない。**

戻すときは、3.7 にした台を、上げた順の逆に 1 台ずつ戻す。

```sh
cd /tmp/fraction-stage-7
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubelet --node <3.7 にした台> --config ./porkadot.yaml
```

- **cluster version が 3.6.0 のままであること**（どれかの台の `/version` の `etcdcluster`）を、流す前に確かめる。3.7.0 になっていたら §7.4
- 戻す台が etcd のリーダーなら、先に 3.6 のメンバーへリーダーを移す（§4.3）
- その台の etcd が 3.6.15 で起き、3/3 healthy、raft index がそろうこと。`/version` が `{"etcdserver":"3.6.15","etcdcluster":"3.6.0","storage":"3.6.0"}`。kubelet は v1.36.5、etcdctl・etcdutl は 3.6.15、`kubelet.service` にフラグが戻る
- 起きなければ、ほかの 2 台で quorum が保たれている間に止めて報告する（そのメンバーを外して入れ直す、または §7.4。その時点でユーザーと決める）
- kubelet が 1.36 に戻るので、apiserver（1.37）より古い。skew policy の範囲

### 7.4 etcd が全台 3.7 になった後: `porkadot etcd restore` ✋

**cluster version が 3.7.0 になった後は、3.6 のメンバーには戻せない**（etcd の公式の文書。上げた後に 3.6 に戻すには、上げる前に取った snapshot から戻すか、公式の downgrade の手順に従う）。段 8 の戻しは、上げる前に取った backup（3.6 の etcdctl で取ったもの）を、**0.37.0 の `porkadot etcd restore`** で戻すことになる。etcd は 3.7.3 のまま起き、cluster version・storage とも 3.7.0 になる（dev の記録の「上げる前の backup への restore」）。

形は段 5 の手順書 §7.4 と同じ（使う backup だけを別のディレクトリに置き、`porkadot etcd restore --path ./backup-restore`。流れ、ログの `restored revision` が `current revision` + 10 億以上であること、Longhorn の CR も backup の時点に戻ること、流した後に確かめること）。**restore は最後の手段**で、API の中身（すべてのオブジェクト）が backup の時点に戻り、backup の後の変更は失われる。

- **0.37.0 の `etcd restore` は 0.34.1〜0.36.0 と同じ実装**で、ノードの `/opt/bin/etcdutl`（3.7.3）を使う。3 台の control-plane に `/opt/bin/etcdutl` → `etcdutl-3.7.3` があること（全台 3.7 の後なら 3 台とも 0.37.0 の `install kubelet` を流しているので、ある）
- dev では、2 分 25 秒で rc 0。etcd は 3.7.3 のまま起き（`{"etcdserver":"3.7.3","etcdcluster":"3.7.0","storage":"3.7.0"}`）、revision は今の revision より 10 億上がり（dev は 2001686902 → 3001686902）、restore の前の resourceVersion からの watch は 410 になった。API（VIP）は約 2 分止まり、その後の porkadot の apiserver の入れ替えの間にも数サンプル落ちた。LoadBalancer は途切れなかった。KCM・scheduler・Longhorn の CSI のサイドカー・longhorn-global-manager が API を失って再起動した（段 5 と同じ）
- 本番の revision は 2026-10-23 14:2xZ に 1,239,114,847。当日の値は §2.2 の 4 で控える
- **Longhorn の CR も backup の時点に戻る**（段 5 の手順書 §7.4）。restore の前に、backup の後で Longhorn に変化が無かったか（§2.2 の 18 とその後の各台の記録）を確かめ、変化があればユーザーに示す
- **Corefile も backup の時点に戻り、CoreDNS が reload する**（§2.4 の backup なら `cache 30`）。§8.16 の `loop` が出うる（dev では restore の後の reload で .122 の Pod が 1 回 exit した）
- 3 台の control-plane の `/var/lib/etcd` には `member` のほかに `member.tar.gz`（2020 年）、.111 には `member.2024-05-19` もある（1 台 0.45〜0.86 GB）。restore はディレクトリごと `/opt/porkadot/data-<時刻>` へ移すので、これらもそこへ移る。`/` は 103 GB 以上空いている

**使う backup**:

| backup | API の中身 | restore の後 |
|---|---|---|
| §2.4（段の前） | 1.36 の control-plane、Corefile `cache 30`、ClusterTrustBundle は無い | kubelet が control-plane を 1.36.5 に入れ替える（dev の記録）。kubelet と etcd は 1.37.1・3.7.3 のまま（kubelet が apiserver より新しい、skew policy の外）。dev ではこの形で健全だった |
| §4.2（control-plane の kubelet の前） | 1.37 の control-plane、新しい Corefile、ClusterTrustBundle 1 つ | control-plane は 1.37.1 のまま。kubelet・etcd とも 1.37.1・3.7.3 で skew policy の中。失われる変更が少ない |

どちらにするかは、戻す理由（1.37 に固有の問題か、etcd 3.7 か、データか）で、その時点でユーザーと決める。

**続けて何を流すか**（その時点でユーザーと決める）:

- **進める（1.37 に揃える）**: §2.4 の backup に戻したときは、0.37.0 の `install kubernetes`（§3.2）で control-plane を 1.37.1 に上げ直す（dev で確かめた。1 回目で rc 0。KCM が ClusterTrustBundle を作り直した）。kubelet と etcd はそのまま
- **1.36 に戻す**: §7.5

`/opt/porkadot/data-<時刻>` には restore の前のデータディレクトリが残る（dev では 330〜450 MB）。段 8 が落ち着くまで残し、消すときはユーザーの承認を取る。

**公式の downgrade の手順**（`etcdctl downgrade validate/enable 3.6` で cluster version を下げてから 3.6 のイメージに替える）も 3.7 にはあるが、porkadot は扱わず、dev でも確かめていない。使うならその時点でユーザーと決める。

### 7.5 全台 3.7 の後に、1.36 まで戻す ✋

API（control-plane）を 1.36 に戻すと、kubelet は apiserver より新しくてはいけないので、**全ノードの kubelet を 1.36 に戻す**ことになる。etcd は 3.7.3 のまま残す（3.6 には戻せない）。

- worker は §7.6 で戻せる（etcd が無いので、0.36.0 の `install kubelet` で足りる）
- **control-plane は、0.36.0 の `install kubelet` をそのまま流してはいけない**（etcd のマニフェストが 3.6.15 になり、3.7 のデータでは起きない見込み）。`porkadot.yaml` の `etcd.image_tag` を `3.7.3-0` に上書きし、0.36.0 で `render kubelet` / `render etcd` をし直した assets で流すことになる（0.36.0 の etcd のテンプレートは `image_tag` の major.minor でフラグを選ぶので、3.7 でも 3.6 と同じ新しい名前のフラグを出す。`install-deps.sh` の `ETCD_VER` も 3.7.3 になる。porkadot#61 の本文）。**dev では確かめていない**ので、流す前に render の差分を見せて、その時点でユーザーと決める
- 順番は §7.7 と同じ（kubelet を先に、control-plane のマニフェストを最後に。§7.2 の注のとおり、1.37 の scheduler・KCM が 1.36 の apiserver に当たる間の形は確かめていない）

### 7.6 kubelet を戻す（1 台） ✋

```sh
cd /tmp/fraction-stage-7
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubelet --node <ノード> --config ./porkadot.yaml
```

- worker と、etcd が混在中の control-plane（§7.3）だけに使う。**全台 3.7 の後の control-plane には流さない**（§7.5）
- `/opt/bin` の向き先が `kubelet-v1.36.5`、`kubectl-v1.36.5`、`crictl-v1.36.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15` に戻る（CNI は v1.9.1 のまま）。`kubelet.service` にフラグが戻り、`config.yaml` から `containerRuntimeEndpoint` が消える。確かめる
- **Longhorn のボリュームがアタッチされた台は、drain してから流す**（§7.1）
- 戻した台でも、§4.4 または §5.3 の確認を、版を読み替えて行う。iscsid は再起動しない見込み（0.36.0 の `install-pkgs.sh`）なので、「PID が同じ」をそのまま見る

### 7.7 段 8 全体をやめる

kubelet は kube-apiserver より新しくてはいけないので、**kubelet を先に戻し、control-plane を最後に戻す。**

- **etcd がまだ全台 3.6 か、混在中**: worker を上げた順の逆に §7.6 で戻し、control-plane の kubelet を上げた順の逆（.111 → .112 → .113）に §7.6 / §7.3 で戻し、最後に §7.2 で control-plane のマニフェストを戻す
- **etcd が全台 3.7**: §7.4 で restore するか、§7.5 の形で kubelet を戻してから §7.2 で control-plane のマニフェストを戻す（etcd は 3.7.3 のまま）。どちらもその時点でユーザーと決める

戻し終えたら、§6 の確認を版を読み替えて行い、`results/stage-8/` に戻した経緯を残す。

## 8. 既知の問題と注意

### 8.1 `install kubelet` のたびの cnidaria の `no route`

段 7 の手順書 §8.1 と同じ。段 7 の本番では各台で error が 0〜8 件ずつ、1 秒ほど。

### 8.2 render が証明書を作り直す

段 7 の手順書 §8.2 と同じ。当日に render し直さない。

### 8.3 `install kubernetes` の rc 1

段 7 の手順書 §8.3 と同じ（`connection refused` の rc 1、apiserver の rollout の timeout）。0.37.0 では apiserver が先に 1.37 になり、dev のログに `Failed to watch` が 0 だった。戻しの向きは §7.2。

### 8.4 1.37 の kubelet ではコンテナが再起動しない

段 7 の手順書 §8.4 と同じ。dev の 7 台で、`install kubelet` の前と後の Pod の UID と restartCount が同じだった。control-plane の etcd の static Pod は作り直される。ほかのコンテナが 1 つでも再起動したら止める。`containerRuntimeEndpoint` への移しも、kubelet の繋ぐ先は同じソケットで、コンテナには触らない。

### 8.5〜8.9

段 7 の手順書 §8.5〜§8.9 と同じ。CSR は段 8 の間も出ない見込み（dev でも出なかった）。

### 8.10 iscsid と iSCSI のセッション

段 7 の手順書 §8.10 と同じ。drain に切り替える台が出たら、drain の後・`install kubelet` の前と後に `sudo iscsiadm -m session` を見て、Longhorn のセッションが残っていないことを確かめる。残っていたら止めて報告する（logout は §0 の runbook から外れる操作）。iscsid の `MainPID=0` の台の扱いは §2.7。

### 8.11 CNI plugins

段 8 では変えない（段 7 の手順書 §8.11 と同じ。`CNI plugins v1.9.1 already installed`）。

### 8.12 Longhorn の `no Pending workload pods`（longhorn/longhorn#8072 の形）

段 7 の手順書 §8.12 と同じ（段の開始の承認の範囲の ✋。消す前に名前を知らせる）。**JST 05:30（20:30Z）より後に作業するなら、当たる前提で §2.2 の 22 で洗い出す**。2026-10-23 14:2xZ には、duchamp に natsumi の 3 つの CronJob の Succeeded の Pod が 6 つ（`natsumi`、`natsumi-aki`、`natsumi-myao` の PVC。Running の natsumi の Pod と同じ PVC）、chirico に `deep-researcher-backup` の Succeeded の Pod が 2 つ（`data-deep-researcher-0`）ある。段 6 の本番では、duchamp の前に 6 つ、chirico の前に 1 つ消した。`aphrael/tumblr-like` の 3 つは NFS の PV（`aphrael-2`）で当たらない。fs の 3 つのバックアップの Pod は PVC を持たない

### 8.13 etcd の遅れと、1 台が止まる間の quorum

段 7 の手順書 §8.13 と同じ。dev の段 8 では、`install kubernetes` の後に `apply request took too long`（最大 0.38 秒）、.113 の tarball の展開の時刻と .121 の apt の時刻に etcd の 3 台の unhealthy が 1〜3 サンプル出た（dev の見つけたことの 5・6。7 台の VM が同じホストのディスクを使う dev に特有と見ている）。本番の段 7 では、`install kubernetes` の直後も 3 台とも healthy だった。

- control-plane の `install kubelet` の間は、その台の etcd が十数秒止まる（§4.1）。ほかの 2 台が unhealthy にならないこと
- 本番で VIP が 15 秒を超えて応答しないときは、etcd のログ（`slow fdatasync`、`apply request took too long`、`heartbeat`）を見て記録する。1 分を超えたら §7 の目安に当たる。**混在中に止まったときも、次の台に進まない**

### 8.14 storage version

`storage-versions.md`。§2.5 のとおり、段 8 では書き直しは無い。`install kubernetes` の前と後に `OLD` が出たら止めて調べる。1.37 の ClusterTrustBundle（`v1beta1` で保存する）は、この PR の `tools/storage-versions.sh` が `OLD` と数えない。`install kubernetes` の後に `overrides.tsv` が 1.36 の 2 行のままなら、スクリプトがサーバーの版を 1.37 と読めていない（rollout の途中に流していないか、`kubectl --context fraction version` を見直す）。

### 8.15 metrics

1.37 で、kubelet の `/metrics/cadvisor` の `container_cpu_load_average_10s`・`container_cpu_load_d_average_10s`・`container_tasks_state` と `container_application_*` が出なくなる（§2.12）。本番の PrometheusRule と ConfigMap（Grafana のダッシュボードを含む）に、どの名前も 0 件（2026-10-23 14:2xZ の読み取り）なので、影響は無い。§6 で `up == 0` と `count(etcd_server_has_leader)` を見る。出なくなったものがあれば記録し、段 8 の後の kube-prometheus-stack の更新（計画 §8）で扱う。段の更新は止めない。

### 8.16 CoreDNS の upstream に kube-dns が入っている（`loop`）

段 7 の手順書 §8.16 を、段 8 では次のとおりに改める。

- **CoreDNS の `loop` plugin は、起動と Corefile の reload のたびに、上流へ HINFO を投げて自分に返るかを確かめる。** 上流は `forward . /etc/resolv.conf` の中から random に選ばれ、ノードの resolv.conf には kube-dns（10.254.0.10）が入っているので、kube-dns に当たると CoreDNS 自身（どちらかの Pod）に返り、`[FATAL] plugin/loop: Loop (…) detected for zone "."` で exit 1 する（dev の見つけたことの 2）。起き直したときの確かめで当たらなければ通る
- **段 8 は Corefile を変えるので、`install kubernetes` の reload で 1 回再起動しうる**（dev は段 8 の reload では 2 つとも通り、restore の後の reload で 1 つが exit した）。§3.3 の 13 の条件（restartCount が 1 増え、前のコンテナのログに `plugin/loop`、起き直して Ready）なら想定どおりとして記録して進める。**CrashLoopBackOff になったら止めて報告する**
- 本番では 2026-10-23 02:14〜02:26Z に、上流が答えない間に `loop` の FATAL と OOMKilled で再起動を繰り返した（§2.10）。上流（jumelle）が止まる時間帯に段 8 を重ねない（§2.11）
- resolv.conf の kube-dns を外す直しは、段 8 の範囲の外（§10）

### 8.17 control-plane の `The manifest file is empty, ignoring.`

段 7 の手順書 §8.17 と同じ。1.37 の apiserver・KCM・scheduler も、起動のたびに 1 行出す（dev の記録）。止める理由にしない。

### 8.18 `UnknownVersionInteroperabilityProxy`（apiserver の peer proxy）と apiserver の混在

段 7 の手順書 §8.18 の申し送り（段 8 の `install kubernetes` で 1.36 と 1.37 の apiserver が並ぶ間の振る舞い）は、dev で確かめた（dev の記録の「1.36 と 1.37 の apiserver の混在」）。

- porkadot は `--peer-ca-file` を渡さないので、peer proxy の handler は組まれない（apiserver の FLAG のログに `--peer-ca-file=""`）。版の違う apiserver へ要求を回すことは無く、**503 は出ない**
- 1.37 だけの API（`/apis/resource.k8s.io/v1/devicetaintrules` など）を VIP 経由で読むと、振り先によって NotFound（1.36）か 200（1.37）になる。入れ替えが終われば 3 台とも 200
- Lease `kube-system/apiserver-<ハッシュ>` はホスト名ごとの 3 つのまま。holder の UUID が新しい apiserver のものに替わり、注釈 `kubernetes.io/peer-advertise-address` が付く。`/registry/peerserverleases/` は core の `v1` の `ok`（段 7 と同じ）

### 8.19 apiserver の grpc の `operation was canceled`

段 7 の手順書 §8.19 と同じ。2026-10-23 14:2xZ にも、1.36 の 3 台の apiserver が 10 分に 37〜39 行（1 分に 4 行）出していた（段 7 の後も続いている）。**本番の段 8 では、1.37 の apiserver は出さなかった**（`install kubernetes` の後と §6 の完了の確認の時点で、3 台とも 0 行）。止める理由にしない。apiserver のログの `W`・`E` の行を数えるときは、etcd の起き直しの時刻のものと分けて数える。

### 8.20 etcd 3.7 の etcdctl の出力

§1.5。`-w table` の罫線が Unicode になる。この手順書の確認は、数えるときは `-w json`、目で読むときは `-w table` にする。`tools/storage-versions.sh` は `etcdctl get -w json` を使うので変わらない（dev で 3.7 の後に流せた）。

### 8.21 `EtcdRangeStream`（1.37 の apiserver と etcd の混在）

1.37 の apiserver は `EtcdRangeStream`（beta・既定 on）で、watch cache の初期化と list を etcd 3.7 の `RangeStream` で読む。etcd 3.6 は `Unimplemented` を返すので、apiserver は従来の paginated `Range` に戻り、`RangeStream` を使えないと覚えて 10 分ごとに試し直す（porkadot#61 の本文、v1.37.1 の `staging/src/k8s.io/apiserver/pkg/storage/etcd3`）。

- **fallback のログは出ない**（`klog.V(4)`）。見えるのは apiserver の metrics `apiserver_storage_list_duration_seconds_count{streamed="true|false"}` と、etcd 3.7 のメンバーの `grpc_server_handled_total{grpc_method="RangeStream"}`（dev の見つけたことの 4）
- dev では、混在中は `streamed=false` だけ（3.7 のメンバーに当たった試し直しで一時的に `true`）、全台 3.7 になって試し直しが明けた後は `streamed=true` だけになった。混在中のエラーは無い
- 本番では確かめるのは任意（§2.3、§4.5）。段の合否には使わない

### 8.22 `containerRuntimeEndpoint`

- `config.yaml` の `containerRuntimeEndpoint` は `unix://` の scheme 付き（`unix:///run/containerd/containerd.sock`）。フラグのときは scheme なしのパスだった。kubelet はどちらでも同じソケットに繋ぐ
- `kubelet.service` の変更は、`install kubelet` が `daemon-reload` してから kubelet を再起動するので、その場で効く
- 戻すと（0.36.0 の `install kubelet`）フラグが戻り、config の値より優先する（§7.1）
- フラグは 1.38 で削除される見込み（計画 §7）。段 8 の後の kubelet の起動時の warning は 0 になる（§6）

### 8.23 古い `cpu_manager_state` で 1.37 の kubelet が起きない（本番の段 8 で見つけたもの）

- 本番の oeilvert の `/var/lib/kubelet/cpu_manager_state` は 2020-06-22 に書かれたもの（`{"policyName":"none","defaultCpuSet":"","checksum":3242152201}`）で、中身はほかの台と同じだが checksum が古い kubelet の計算のものだった。1.36 までの kubelet は読めていたが、**1.37.1 の kubelet は v4・v3・v2 のどの形でも読めず、`Could not initialize checkpoint manager … checkpoint is corrupted, please drain this node and delete the CPU manager checkpoint file` → `Failed to start ContainerManager` で起動と exit を繰り返した**（`results/stage-8/workers.md` §2）。ほかの 7 台（`checksum` 1353318690）は v2 → v3 → v4 に移せた
- 直し方（runbook から外れる操作。本番の段 8 ではユーザーの承認を得て流した）: `sudo mv -n /var/lib/kubelet/cpu_manager_state /var/lib/kubelet/cpu_manager_state.bak-<印>`。kubelet は systemd の自動再起動（10 秒おき）で起き、policy `none` の空の状態を v4 の形で書き直す。コンテナは再起動しない（本番の段 8 で Pod の差分 0）
- 起きない間もコンテナは動き続けるが、長引けば Node が NotReady になり Pod が退避されうる。§2.2 の 33 で前もって見つけて、その台の `install kubelet` の前に退避の承認を取る
- `memory_manager_state` は古い形（2022 年）でも、1.37 の kubelet は `V2 checkpoint for memory manager is corrupt, falling back to V1` の後に v1 → v3 へ移せる（8 台とも、この `E` の行を 1 回出す。害は無い）
- dev の VM は新しく、古い形のファイルを持っていないので、dev では起きなかった

### 8.24 etcd の mirror Pod の作り直しが遅れることがある（本番の段 8 で見つけたもの）

本番の .112 では、新しい kubelet が古い mirror Pod を消した後、新しい mirror Pod が API に現れるまで約 87 秒かかった（kubelet の次の同期まで。`results/stage-8/192.168.1.112.md` の注）。その間も etcd のコンテナは動いていて、3/3 healthy だった。§4.4 の 5・7 で mirror Pod が無いときは、1〜2 分待って読み直す。また、本番の段 8 では 3 台とも etcd 3.7.3 の最初のコンテナが落ちずに起き、restartCount は 0 だった

## 9. 記録

`results/stage-8/` に、ベースライン（`baseline.md`。§2.4 のバックアップ、§2.5 の storage version、§2.7 の iscsid（`MainPID=0` の台を含む）、§2.9 の cgroup、§2.10 の resolv.conf と CoreDNS の restartCount、§2.11 の unattended-upgrades と jumelle の時刻、§2.2 の 30〜32 も）、`install kubernetes`（`control-plane.md`。§3.3 の 13〜20 と CoreDNS の reload・TTL の確かめ、§4.2 のバックアップも）、各台（`<ノード>.md`。control-plane は `192.168.1.11N.md`。§4.5 のバックアップと etcd の版の移り変わりも）、全体のまとめ（`summary.md`。§6 の v1 Endpoints の warning の出どころの表と metrics の確認も）を残す。各台の雛形は `results/stage-8/template.md`。
時刻（UTC。control-plane のホストの JST の時刻は直して書く）、読み取りの結果、実行したコマンドと出力の要点、Pod の再起動の有無、iscsid の PID とセッションの前と後、etcd の版と cluster version、`containerRuntimeEndpoint` の確認、監視の FAIL（VIP・LB と etcd の health）と監視が止まっていた時間、leader election で再起動したもの、手順書との差を書く。`tools/node-state.sh` と `snap` の出力、監視のログ（`stage-8-probe.log`、`stage-8-etcd-*.log`）、`tools/storage-versions.sh`・`tools/dns-check.sh`・`tools/ipcidr-scan.py` の出力、`endpoints-warnings.tsv` はタスクディレクトリの `notes/stage-8/` に置き、要点を記録に写す。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（同じ PR か、記録の PR で）。

## 10. 段 8 の後

段 8 で K8s の段は終わる。次は計画 §8・§10 の作業で、**ここでは順を書くだけで、実施しない**。どれも本番への変更なので、それぞれ手順を書いて承認を取ってから行う（計画 §9.1）。

1. **1 日ほど様子を見る**（計画 §9.6。etcd のマイナー更新を含む段なので）。etcd のログに新しい warn・error が増えていないこと、Prometheus の etcd のパネル、Longhorn のボリュームが healthy のままであること、CoreDNS の restartCount が増えていないことを見る
2. **非クリティカルなコンポーネントを最新へ**（計画 §8。1 つずつ。上げる時点で最新を確かめ直す）
   - kube-prometheus-stack（fleet-infra。chart 85.2.1 → 最新。operator は v1 Endpoints の warning の出どころの 1 つ）
   - metrics-server（fleet-infra。v0.7.2 → v0.9.x。`metrics.k8s.io/v1` を出すかも見る。§2.12）
   - MetalLB（porkadot の addon。v0.14.5 → v0.16.x。API の VIP を持つので dev で先に通す。残っている `addresspools` の CRD を片付ける。**IPv6 の pool を porkadot から外す案**（プレフィックスに追随する仕組みを本番への CD の別タスクで作る。前提のメモ §1）と同時に動かさない）
   - kube-dns-autoscaler（porkadot の addon。マルチアーキの cpa へ）
   - **CoreDNS v1.15**（registry.k8s.io に出てから。porkadot の addon。v1.15.0 は `cache`・`forward` の振る舞いが変わる（porkadot#61 の本文）。2026-10-23 のユーザー判断で段 8 の後に回した）
3. **containerd の config を version 4 に作り直す**（計画 §10。1 台ずつ、`setup-containerd --node`。以後は 2.2.1 へ戻すときに退避した version 3 の config が要る）
4. **片付け**（計画 §10）: 中身の無い名前空間、残っている CRD（`nfd.k8s-sigs.io`、MetalLB の `addresspools` は MetalLB の更新と一緒に）、CSIDriver `rook-ceph.*`、private と k8s-env の古いマニフェスト。**2026-10-23 にユーザーが使っていないアプリ（minio など）を消したので、対象を読み直してから**示す。chirico の v1.11.2 の instance-manager は手で消さない（pablo と oeilvert の古いものは、その上のエンジンが無くなったときに消えた。§1.10）
5. **Wiki の更新**（llm-wiki。`wiki/synthesis/cluster-upgrade-plan-2026.md`、`wiki/topics/自宅クラスター.md`、`wiki/entities/porkadot.md`。作業記録を `raw/memos/` に）
6. etcd のバックアップの扱い: 段 7 の 2 つ（`etcd-2026-10-21T12:59:15+00:00.db`、`…T13:08:44…`）は段 8 に入ったので戻しの材料としては使わない。段 8 の 3 つは段 8 が落ち着くまで残す。消すかはユーザーが決める
7. 申し送り（段 8 の範囲の外）:
   - **CoreDNS の upstream に kube-dns が入る件**（§2.10、§8.16）。2026-10-23 に上流の停止で CoreDNS が再起動を繰り返した。porkadot の `dns` の addon（ノードの resolv.conf に kube-dns を入れる）か、CoreDNS の `forward` の先を直す。porkadot の PR と dev の検証が要る
   - apiserver の grpc の `operation was canceled`（§8.19）。1.35 でも出ていたかは確かめていない
   - unattended-upgrades の needrestart による iscsid の再起動（§2.11）。Longhorn のエンジンは直った版なので、害は無い見込み
   - cnidaria-cni-dev の `notes/fraction-runbook/common.sh` の `IMAGE`（`v0.1.0`。§1.8）
