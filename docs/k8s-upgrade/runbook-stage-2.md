# 段 2 の手順書: K8s を 1.30.14 から 1.31.14 へ上げる（本番 `fraction`）

本番クラスタ `fraction` の Kubernetes を v1.30.14 から v1.31.14 へ上げる手順。porkadot を 0.30.0 から 0.31.0 に替える。etcd と CoreDNS は据え置く。
計画は同じディレクトリの `plan.md`（以下「計画」）の §6（骨子）と §7 の段 2 の行、決まったことは §9 にある。前の段は `runbook-stage-1.md`（以下「段 1 の手順書」）で、この手順書はそれを下敷きにし、**段 1 から変わる点を中心に書く**。drain の手順は `runbook-stage-c.md`（以下「段 C の手順書」）のものを使う。

| | 更新前 | 更新後 |
|---|---|---|
| porkadot | 0.30.0 | **0.31.0**（`62d8821`、タグ `v0.31.0`） |
| kube-apiserver、kube-controller-manager、kube-scheduler、kube-proxy | v1.30.14 | **v1.31.14** |
| kubelet、kubectl（ノードの `/opt/bin`） | v1.30.14 | **v1.31.14** |
| crictl（ノードの `/opt/bin`） | v1.30.1 | **v1.31.1** |
| kubelet-serving-cert-approver | `:main`（`imagePullPolicy: Always`） | **`0.12.1`**（`IfNotPresent`。startupProbe と toleration を上流に合わせる） |
| etcd（control-plane の static Pod）、etcdctl | 3.5.34 | 変えない |
| CoreDNS | v1.11.3 | 変えない |
| containerd、runc | 段 C の 2.3.6、1.5.1 | 変えない |
| cnidaria、MetalLB、CNI plugins（v1.4.1） | — | 変えない（マニフェストの差分が無い） |
| kubelet の `config.yaml`・`kubelet.service` | — | 変えない |
| Longhorn | v1.11.2 | 変えない（要件は K8s 1.25 以上。計画 §4） |

porkadot 0.31.0 に入った PR は 3 つ。

- porkadot#28: K8s v1.31.14、crictl v1.31.1
- porkadot#29: SSH。`connection.keys` の既定（`~/.ssh/id_rsa`、`~/.ssh/id_dsa`）を外し、ed25519 の鍵を読めるようにした（`ed25519`、`bcrypt_pbkdf` の gem）。known_hosts を net-ssh の parser で読む（SSHKit の parser は hashed の行の最初の 1 行しか返さなかった）。SSH の失敗を `SshError` の 1 つのメッセージで出す
- porkadot#31: kubelet-serving-cert-approver を `:main`／`Always` から `0.12.1`／`IfNotPresent` に固定する

この手順は dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で先に通してある（2026-10-19）。記録は porkadot-dev の `docs/k8s-upgrade/verification-0.31-rc.md`（以下「dev の記録」。porkadot-dev の main（#9、`3cf5e96`））。dev で分かったことのうち、段 1 と違うものは次のとおり。

- **1.31 の kubelet に上げると、そのノードのコンテナがすべて 1 回再起動する。** Pod は作り直されず（UID は同じ）、restartCount が 1 増える。kubelet は `Container <名前> definition changed, will be restarted` を出す。1.31 でコンテナの hash の計算が変わったため（kubernetes#124220。kubeadm の upgrade の文書にも「All containers are restarted after upgrade, because the container spec hash value is changed」とある）。段 1 では 1 つも再起動しなかった
- **drain しないと、Longhorn のボリュームがアタッチされているノードでは、ボリュームが faulted になり、使っている Pod に 1〜2 分 I/O エラーが出る。** instance-manager のコンテナも再起動し、engine と replica のプロセスが落ちるため。Longhorn が自分で戻した（fsync したデータは失われなかった）が、アプリから見るとディスクが急に消えるのと同じ。**drain すれば、ボリュームは faulted にならず、Pod が普通に止まって別のノードで起き直すだけで済む**（書き込みの途切れ 19 秒）
- control-plane では、各台の apiserver が 30 秒ほど ready でなくなる。etcd は 2 秒で起き直し、ほかのメンバーから見て一度も unhealthy にならなかった。VIP は、VIP を告知しているノードを上げたときに 1 回（2 秒以内）だけ応答しなかった
- `install kubernetes` は `--node` を付けないと bootstrap ノードで `kubectl apply` を流して失敗する（段 1 と同じ。`--node 192.168.1.111` で流す）
- kubelet の更新で新しい CSR は出なかった（serving の証明書は期限まで使われる）。1.31 の apiserver での CN の検査は、証明書を消して出させた CSR が approver 0.12.1 で 1 秒以内に Approved,Issued になったことで確かめた
- porkadot のコマンドはすべて pi のサンドボックスの中（ssh-agent に届かない）で通った

これを受けて、**本番の段 2 では Longhorn のノードの worker 4 台（pablo、duchamp、chirico、oeilvert）を cordon + drain してから `install kubelet` し、braque と control-plane の 3 台は drain しない**（2026-10-19 のユーザーの承認。§2.1 の 3）。計画 §9.3 の「K8s の段は drain しない」は、段 2 ではこの形に替わる。

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **arm64 の control-plane での全コンテナの再起動**。dev の段 2 は amd64 の VM で通した。arm64 のイメージとバイナリが配布されていることは確かめてある（§1.7）
- **本番の Longhorn のノードの drain**。replica 1 のボリューム（prometheus の 2 つ、MinIO の 4 つ）を止めて drain する形は、段 C の本番の 5 台で通したもの（§2.6）。dev の drain は 1 台・2 つのボリュームだけ
- **braque の nfsd の再起動**。dev に nfsd は無い。braque の nfsd（DaemonSet の Pod、hostNetwork）のコンテナも 1 回再起動するので、NFS が短く止まる（§5.4）
- **approver の入れ替え**（`:main` → `0.12.1`）の後に、本番の kubelet の serving の CSR が承認されること。本番では段 2 の間に CSR が出ない見込みなので、§6 で CSR を見て、次に出たとき（証明書の更新）に確かめる（§8.10）

## 0. 役割と約束ごと

- **承認の節目は 1 つだけ**（計画 §9.1「本番の各段の開始（render の差分を見せてから `install kubernetes` を流す前）」）。この手順書では ✋✋ を付けた。
  - ✋✋ **段 2 の開始**: render の差分（§2.5。この手順書と同じ PR）を見せ、PR をマージしてから、`install kubernetes` を流す前（§3.2 の前）
- 段 2 は etcd を変えないので、control-plane の kubelet の前の節目は無い（その節目はマイナー更新を含む段 5 と段 8 だけ）。
- **節目の間の手順は、ユーザーに知らせるだけで進めてよい。** drain、cordon、uncordon、Longhorn の設定の切り替え、Prometheus と MinIO を止めて戻すことも、この手順書に書いた形なら ✋（知らせてから行う操作）で、1 つずつ承認を取るものではない。
- **runbook から外れる操作（ロールバック、想定外の対処、controller の無い Pod の `--force`、Pod の削除）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認（`kubectl --context fraction get`、SSH での状態確認）は、知らせずに行ってよい。
- **1 台ずつ行う。** 1 台を終えて「次の 1 台へ進む条件」（§4.3、§5.6）を満たすまで、次のノードに手を付けない。
- 時刻はすべて UTC で記録する。worker のホストの時刻は UTC だが、**control-plane（192.168.1.111〜113）のホストの時刻は Asia/Tokyo（JST）** である。control-plane の `journalctl` や `ls -l` の時刻は 9 時間ずらして読む。

## 1. 前提

### 1.1 段 1 が終わっていること

始める前に次を確かめる。

- 段 1 の完了の確認（段 1 の手順書 §6）が `results/stage-1/summary.md` に残っている
- 8 台すべてが v1.30.14、CONTAINER-RUNTIME が `containerd://2.3.6`、etcd が 3.5.34

2026-10-19 05:50Z ごろの読み取りでは、8 台 Ready、全台 v1.30.14、`containerd://2.3.6`、etcd 3/3 が 3.5.34（リーダーは .113 の `57ec6f12ac7b683e`）だった。

### 1.2 kubeconfig の運用

確認は `kubectl --context fraction`（`fraction-auditor`、read-only）で行う。作業を始める前に `kubectl --context fraction auth can-i delete pods -A` が `no` であることを確かめる。

**段 2 では `infra-admin` の短命トークンが要る**（段 1 では要らなかった）。drain する worker の 4 台で、cordon、drain、uncordon、Longhorn の設定の切り替え、Prometheus と MinIO を止めて戻すことに使う。発行と破棄は段 C の手順書 §1.1 と同じ。

```sh
umask 077
kubectl --context fraction create token infra-admin -n kube-system --duration=3h > /tmp/k8u-stage2-admin-token
ADMIN_TOKEN=$(cat /tmp/k8u-stage2-admin-token)
kubectl --context fraction --token="$ADMIN_TOKEN" auth can-i patch nodes            # yes
kubectl --context fraction --token="$ADMIN_TOKEN" auth can-i create pods --subresource=eviction -A   # yes
```

- 1 台ごとに 2〜3 時間の期限で発行し、その台の後始末（§5.5）で破棄する（`unset ADMIN_TOKEN` とファイルの削除）。SA のトークンは 1 つだけを失効させられないので、サーバーの側では期限で切れる
- 以下、変更系のコマンドを `kubectl-admin` と書く（`kubectl --context fraction --token="$ADMIN_TOKEN"` のこと）
- トークンのファイルができる前に変更系のコマンドを流さない（段 C の oeilvert で、`fraction-auditor` の権限で流して `Forbidden` になった。変更は無かった）
- control-plane と braque は drain しないので、runbook どおりならトークンは要らない

### 1.3 SSH

| ノード | 入り方 |
|---|---|
| worker（braque、chirico、duchamp、oeilvert、pablo） | `ssh yuanying@<IP>` |
| control-plane（192.168.1.111〜113、rasp01〜03） | `ssh ubuntu@<IP>` |

porkadot も同じ形で入る（`porkadot.yaml` の `connection`）。`connection.keys` は本番の `porkadot.yaml` に無い（§2.5 の最後）。

### 1.4 porkadot の流し方

porkadot 0.31.0 の checkout（`porkadot-dev/porkadot` の `v0.31.0`）を使い、**このリポジトリのルートを cwd にして** 流す。形は段 1 の手順書 §1.4 と同じ。

```sh
P=/home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot
git -C $P describe --tags          # v0.31.0（lib/porkadot/version.rb も 0.31.0）
cd <このリポジトリの checkout>     # §2.5 の PR をマージした master
BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

以下、この形を `porkadot <サブコマンド>` と書く。

- cwd はこのリポジトリのルートにする（段 1 の手順書 §1.4、§8.7）。`--config` はサブコマンドの後ろに置く
- secrets は `assets/` の中に sops（age）で暗号化してある（§1.6）。作業端末に age の鍵（`~/.config/sops/age/keys.txt`）が要る
- 作業ツリーの `assets/` と `porkadot.yaml` に PR の外の変更が無いこと（`git status --short assets porkadot.yaml` が空）。メインの checkout にほかの作業があれば、master の別の worktree を作ってそこで流す（段 1 はそうした）
- 段 2 で流す porkadot のコマンドは、`etcd backup`、`install kubernetes --node 192.168.1.111`、`install kubelet --node <ノード>` の 3 つだけ。**`install all`、`--node` なしの `install kubelet` と `install kubernetes`、`render`（特に `render all` と `render certs`）、`setup-node`、`setup-containerd` は流さない**
- `install kubelet` は `/opt/bin/<名前>` の向き先で判定して張り替える（porkadot#26）。`--force` は要らない
- 0.31.0 の Gemfile.lock は sshkit 1.25.1、net-ssh 7.3.6、ed25519 1.4.0、bcrypt_pbkdf 1.1.2。clone の `bundle install` は 2026-10-19 に済んでいる。始める前に `BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot help` が動くことを確かめる

**0.31.0 では、ノードに入る porkadot のコマンドもサンドボックスの中で流す**（§8.9）。段 1 では、SSHKit の known_hosts の扱いとサンドボックスの ssh-agent のため、サンドボックスの外で流した。0.31.0 は ssh-agent なしに `~/.ssh/id_ed25519` で入り、known_hosts の行の並びにも左右されない。
2026-10-19 に、0.31.0 の SSHKit の設定（porkadot を `require` した形）で 8 台に `hostname` を流し、サンドボックスの中（`ssh-add -l` は `Error connecting to agent: Operation not permitted`）で 8 台とも通ることを確かめた（読み取り）。段 1 の並べ替えの前の known_hosts（`~/.ssh/known_hosts.bak-k8u-stage1-20261019`。.112・.113 は rsa の行が ecdsa の行より前）を読ませても、.112・.113 に入れた。

当日の流す前の確かめ方（読み取り。作業端末で）:

```sh
BUNDLE_GEMFILE=$P/Gemfile bundle exec ruby -I$P/lib -e '
require "porkadot"
%w[ubuntu@192.168.1.111 ubuntu@192.168.1.112 ubuntu@192.168.1.113 yuanying@192.168.1.134 yuanying@192.168.1.135
   yuanying@192.168.1.131 yuanying@192.168.1.83 yuanying@192.168.1.82].each do |h|
  out = nil
  SSHKit::Coordinator.new([SSHKit::Host.new(h)]).each(in: :sequence) { out = capture(:hostname) }
  puts "#{h} #{out}"
rescue => e
  puts "#{h} FAIL #{(e.cause || e).message.lines.first}"
end'
```

8 台とも `rasp01`〜`rasp03`、`pablo`、`duchamp`、`braque`、`chirico`、`oeilvert` を返すこと。`FAIL` が出たら、メッセージ（0.31.0 は原因を 1 つのメッセージで出す。§8.9）を読んで止める。サンドボックスの外で流すことは、§8.9 の理由があるときだけ、ユーザーの判断で行う。

### 1.5 etcdctl の使い方

段 1 の手順書 §1.5 と同じ。`/etc/etcd/pki` は段 1 で root 0600 になったので、sudo で流す。

```sh
ssh ubuntu@<control-plane> 'sudo bash -c ". /etc/etcd/etcd.env && /opt/bin/etcdctl endpoint status --cluster -w table"'
ssh ubuntu@<control-plane> 'sudo bash -c ". /etc/etcd/etcd.env && /opt/bin/etcdctl endpoint health --cluster -w table"'
```

以下、この形を `etcdctl ...` と書く。特定のエンドポイントに向けるとき（`move-leader`）は `unset ETCDCTL_ENDPOINTS` してから `--endpoints` を渡す。control-plane には en_US.UTF-8 のロケールが無いので、`unset LC_ALL` してから SSH する。

### 1.6 render に使った secrets と、本番との突き合わせ

secrets の在りかと扱いは段 1 の手順書 §1.6 と同じ（`assets/` の中に sops の binary 形式で暗号化してある。`assets/secrets.tar.asc` を展開しない。平文をディスクに書かない）。
段 2 の render（§2.5）の前に、同じ形で本番と突き合わせ直した（2026-10-19 05:50Z ごろ。読み取りだけ。復号をパイプで流してハッシュだけを比べた）。

| 比べたもの | 本番の側 | 結果 |
|---|---|---|
| `assets/certs/kubernetes/ca.crt` | ConfigMap `default/kube-root-ca.crt` | 一致（SHA-256 `AB:5A:49:9E:…:A0:3E`。段 1 と同じ） |
| `assets/certs/kubernetes/apiserver.crt` | VIP と 192.168.1.111〜113 の 6443 が返す証明書 | 4 つとも一致（`4A:E8:7B:B3:…:97:63`） |
| `assets/certs/kubernetes/` の 10 ファイル（`ca.crt`、`apiserver.{crt,key}`、`front-proxy-ca.crt`、`front-proxy-client.{crt,key}`、`kubelet-client.{crt,key}`、`sa.{key,pub}`） | .111 の kube-apiserver の Pod（`kube-apiserver-nm6fc`）にマウントされた Secret `kube-apiserver` | 10 ファイルとも sha256 が一致 |
| `assets/certs/etcd/{ca.crt,etcd-client.crt,etcd-client.key}` | 同じく Secret `etcd-tls` | 3 ファイルとも一致 |
| `assets/kubelet/192.168.1.111/addons/etcd/{ca.crt,etcd.crt,etcd.key}`（render の前） | .111 の `/etc/etcd/pki/` | 3 ファイルとも一致（`etcd.crt` は段 1 の render のものが入っている） |
| CA の鍵と証明書（kubernetes、front-proxy、etcd） | — | 3 組とも公開鍵が一致 |

当日に確かめ直すときの形は段 1 の手順書 §1.6 と同じ。どれかが食い違えば、render の差分も assets も信用せず、止めて調べる。

### 1.7 入れる版を確かめる

作業の当日に確かめ直す（読み取り）。

```sh
curl -fsSL https://dl.k8s.io/release/stable-1.31.txt     # v1.31.14
```

2026-10-19 の時点:

- `stable-1.31.txt` は v1.31.14（1.31 は EOL なので、これより新しいパッチは出ない見込み）
- registry.k8s.io の `kube-apiserver`・`kube-controller-manager`・`kube-scheduler`・`kube-proxy` の v1.31.14 は、どれも amd64 と arm64 を含む（manifest list を読んだ）
- `dl.k8s.io` の kubelet と kubectl の v1.31.14（amd64、arm64）、cri-tools の `crictl-v1.31.1-linux-{amd64,arm64}.tar.gz` は、どれも 200 を返す。cri-tools の 1.31 系の最新は v1.31.1
- `ghcr.io/alex1989hu/kubelet-serving-cert-approver:0.12.1` は amd64 と arm64 を含み、digest は `sha256:445a8e5584f6…`（dev の記録と同じ）。approver は control-plane を避けるので、使うのは amd64
- etcd 3.5.34、CoreDNS v1.11.3 は段 1 で入れたもので、変わらない
- 作業端末の kubectl は v1.30.14（段 1 で asdf の v1.30.14 にした）。1.31 の ±1 に入る（計画 §6.1 の 4）

### 1.8 cnidaria の手順書のスクリプト

段 C の手順書 §1.4 と同じ（`verify-nodes.sh`、`netcheck.sh`、`check-apps.sh`）。`netcheck.sh` は一時的な DaemonSet を作るので ✋。

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 順序 | `install kubernetes --node 192.168.1.111` → rollout の完了 → control-plane の `install kubelet --node` を 1 台ずつ（.113 → .112 → .111）→ worker を 1 台ずつ（§5.1） | 計画 §6.2 |
| 2 | etcd のリーダー | `install kubelet` の前に、対象がリーダーなら `move-leader` で別のメンバーへ移す（etcd のコンテナも 1 回再起動する） | 計画 §6.2、dev の記録 |
| 3 | drain | **Longhorn のノードの worker 4 台（pablo、duchamp、chirico、oeilvert）は cordon + drain してから `install kubelet` し、確認の後に uncordon する。braque と control-plane の 3 台は drain しない** | 2026-10-19 のユーザーの承認（TASK.md の現在地）、dev の記録 |
| 4 | drain の基準 | 「短時間の途切れ」より「Longhorn のボリュームの安全（データ、degraded のまま戻らないこと）」を重く見る。短時間の障害は許容する | 2026-10-19 のユーザーの方針 |
| 5 | drain のやり方 | 段 C の手順をそのまま使う（`concurrent-replica-rebuild-per-node-limit` を `0`、最後の replica のあるノードでは `node-drain-policy` を `allow-if-replica-is-stopped` にして、Prometheus と MinIO を止める）。§2.6 | 段 C の手順書 §2.6、§3.7〜§3.8、§3.11 |
| 6 | ノードの再起動 | **しない** | dev の記録 |
| 7 | コンテナの再起動 | 1.31 の kubelet で、そのノードの全コンテナが 1 回再起動することを前提にする（§8.4）。drain しないノード（braque、control-plane）の Pod も 1 回ずつ再起動する | dev の記録 |
| 8 | Longhorn の `replica-auto-balance` | 普段から `disabled`。段 2 でも `disabled` であることを確かめる（段 1 の手順書 §2.6） | ユーザーの判断（2026-10-18） |
| 9 | leader election を使う controller の 1 回の再起動と、gated の LoadBalancer の 1 回の途切れ | 許容する。記録して、Running に戻ったことを確かめる（§8.8） | 段 C、ユーザーの判断 |
| 10 | 停止時間 | いつでもよい。braque だけはバックアップの CronJob の時間帯を避ける（§5.4） | 計画 §9.6 |
| 11 | 段 2 の後 | 健全性を確かめてから段 3 へ（間隔は必須ではない）。段 3 以降の drain の要否は、その段の dev の検証で同じことが起きるかを見て決める | 計画 §9.6、ユーザーの承認 |

### 2.2 クラスタ全体のベースライン

作業の当日、`install kubernetes` の前に次を取り、`results/stage-2/baseline.md` に残す（すべて読み取り）。段 1 の手順書 §2.2 の 1〜17 と同じもので、版の読み替えと次の差がある。

- 1: 全台 v1.30.14
- 2: 8 台の `ls -l /opt/bin/kubelet /opt/bin/kubectl /opt/bin/etcdctl /opt/bin/crictl`（向き先が `kubelet-v1.30.14`、`kubectl-v1.30.14`、`etcdctl-3.5.34`、`crictl-v1.30.1`）、`cat /opt/cni/bin/.porkadot-cni-plugins-version`（`v1.4.1`）
- 3: control-plane の `/etc/etcd/pki` は 3 台とも `600 root:root`
- 4: etcd は 3.5.34
- 5: **全 Pod の名前・UID・restartCount を控える**（段 2 では全コンテナが 1 回再起動するので、比べる元になる）

  ```sh
  kubectl --context fraction get pods -A -o json | jq -r '.items[] | [.metadata.namespace+"/"+.metadata.name, .spec.nodeName, .metadata.uid,
    ([.status.containerStatuses[]? | .name+"="+(.restartCount|tostring)] | join(","))] | @tsv' | sort > baseline-pods.tsv
  ```

- 12: `kubectl --context fraction get csr`（2026-10-19 は無い）。加えて 8 台の kubelet の serving の証明書の subject と期限（§8.10）

  ```sh
  for h in 192.168.1.111 192.168.1.112 192.168.1.113 192.168.1.131 192.168.1.83 192.168.1.135 192.168.1.82 192.168.1.134; do
    printf "%s " $h; echo | openssl s_client -connect $h:10250 2>/dev/null | openssl x509 -noout -subject -enddate | tr '\n' ' '; echo
  done
  ```

- 13: kube-system の Deployment と DaemonSet の generation と image に加え、`kubelet-serving-cert-approver` の Deployment の image と、その Pod の置き場所
- 14: Longhorn の設定。2026-10-19 は `concurrent-replica-rebuild-per-node-limit` `5`、`replica-auto-balance` `disabled`、`node-drain-policy` `block-if-contains-last-replica`、`default-data-locality` `best-effort`、`replica-replenishment-wait-interval` `6000`
- 18（新）: **replica 1 のボリュームの replica の置き場所**と、worker ごとの replica の数（§2.6 の表を当日に読み直す）
- 19（新）: drain する 4 台の、controller の無い Pod、emptyDir を使う Pod、PDB（§2.6）
- 20（新）: **braque と control-plane に Longhorn のボリュームがアタッチされていないこと**（§8.11）

### 2.3 VIP と LoadBalancer を 1 秒ごとに見る

段 1 の手順書 §2.3 と同じ監視を、§3.2 の `install kubernetes` の前から最後の worker の確認まで、作業端末で流しておく（読み取り）。ログは `./stage-2-probe.log` に足していく（`tee -a`）。

- dev では、VIP は VIP を告知しているノードを上げたときに 1 回（2 秒以内）だけ失敗した。本番では pablo が VIP を告知している（§2.7）ので、pablo の `install kubelet` で 1〜数回の失敗を見込む
- 段 2 では、drain で gated の Pod が退いて gated-v4 の告知が移るとき（chirico、duchamp）と、control-plane の apiserver が止まりかける間（§8.8）にも失敗がありうる。どれも記録したうえで許容する

### 2.4 etcd のバックアップ ✋

`install kubernetes` の前に、porkadot 0.31.0 で取る（計画 §6.1 の 5）。

```sh
porkadot etcd backup
ls -l ./backup/
```

- 0.31.0 の `etcd backup` は 0.30.0 と同じ（最初の etcd のメンバー 192.168.1.111 で root として `etcdctl snapshot save` を流し、0600 で手元に写し、ノードのものを消す）。dev ではサンドボックスの中で通った
- 手元のファイルは `./backup/etcd-<日時>.db`、モード 0600。`./backup/` は `.gitignore` で除外してある。スナップショットには Secret が平文で入っているので、`git add -f` などで追加しない
- **worktree で流したときは、`./backup/` は worktree の中にできる。** worktree を片付ける前に、メインの checkout の `backup/` へ移す（段 1 と同じ。`results/stage-1/summary.md` §3）
- 時刻、ファイル名、サイズ、sha256 を記録する。段 1 のバックアップ（`etcd-2026-10-19T00:45:32+00:00.db`）は 55,107,616 バイトだった。桁が違えば止める
- 段 2 が終わるまで消さない

### 2.5 render の差分（この手順書と同じ PR）

計画 §6.1 の 6〜7。2026-10-19 05:54Z に、porkadot 0.31.0（`62d8821`）で、このリポジトリのルートを cwd にして `render kubelet` / `render etcd` / `render bootstrap` / `render kubernetes` を流した（`render all` と `render certs` は使っていない）。secrets は §1.6 のとおり本番と一致していることを確かめてから使った。`porkadot.yaml` は変えていない。

前の render は段 1 の porkadot 0.30.0（`7d607a7`）のもので、master の `34b15e3` にある。差分は次のとおりで、**これ以外の差分は無い**（新しくできたファイル、消えたファイルも無い）。

| ファイル | 変わったもの | 由来 |
|---|---|---|
| `kubernetes/manifests/kube-apiserver.yaml`・`kube-controller-manager.yaml`・`kube-scheduler.yaml`・`kube-proxy.yaml` | イメージ v1.30.14 → v1.31.14、`app.kubernetes.io/version` のラベル | K8s の版（porkadot#28） |
| `kubernetes/manifests/kube-apiserver.secrets.yaml`・`kube-controller-manager.secrets.yaml`（sops） | Secret の `app.kubernetes.io/version` のラベルだけ。data は同じ（復号して比べた） | 同上 |
| `kubernetes/manifests/porkadot.yaml` | Service `porkadot-kubernetes-latest` の selector の `app.kubernetes.io/version`（VIP の Service `porkadot-kubernetes` の selector には版が入っていない） | 同上 |
| `bootstrap/manifests/*.bootstrap.yaml`（4 つ） | イメージ v1.30.14 → v1.31.14、版のラベル | 同上（段 2 では使わない） |
| `kubelet-default/install-deps.sh` | `RELEASE`（kubelet・kubectl）v1.30.14 → v1.31.14、`CRICTL_VER` v1.30.1 → v1.31.1 | porkadot#28 |
| `kubernetes/manifests/addons/kubelet-serving-cert-approver/src.yaml` | イメージ `:main` → `:0.12.1`、`imagePullPolicy` `Always` → `IfNotPresent`、startupProbe（`/healthz`、10 秒ごと、30 回）、`node.cloudprovider.kubernetes.io/uninitialized` の toleration、冒頭のコメント（上流の v0.12.1 の `standalone-install.yaml` を元にしたこと） | porkadot#31 |
| `kubelet/<8 台>/bootstrap.crt`、`bootstrap/kubelet/bootstrap.crt` | 作り直し（同じ鍵、同じ subject・issuer・SAN・用途、assets の CA で検証が通る。期限が 2027-10-19 に延びる） | render のたびに作り直される（段 1 の手順書 §8.2） |
| `kubelet/192.168.1.11{1,2,3}/addons/etcd/etcd.crt`（sops） | 同上（同じ鍵、同じ etcd の CA、同じ SAN） | 同上 |

- `app.kubernetes.io/version` が変わったのは平文のマニフェストで 23 行（dev の記録と同じ数）
- 変わらないもの: `kubelet/<ノード>/config.yaml`・`kubelet.service`・`bootstrap-kubelet.conf`・`metadata.json`、etcd の `etcd-server.yaml`（3.5.34-0）・`install.sh`・`etcd.env`、CoreDNS（v1.11.3）、cnidaria・MetalLB のマニフェスト、CNI plugins の版（v1.4.1）、`kubelet-default/setup-containerd.sh`
- porkadot#29（SSH）は render の結果を変えない
- Deployment と DaemonSet の `spec.selector` には `app.kubernetes.io/version` が入っていない（段 1 と同じ）。approver の Deployment の selector も変わらない
- 作り直した証明書は、作業の当日に render し直すとまた変わる。**当日は render しない**。この PR の `assets/` で流す

**`porkadot.yaml` は変えない。** 0.31.0 は `default.yaml` の `connection.keys`（0.30.0 までは `["~/.ssh/id_rsa", "~/.ssh/id_dsa"]`）を外した。本番の `porkadot.yaml` は `connection.keys` を設定していない（トップレベルの `connection` は `user: yuanying` だけ、各ノードの `connection` は `user` と `hostname` だけ）ので、0.31.0 では net-ssh の既定になる（ssh-agent、`~/.ssh/config` の `IdentityFile`、無ければ `~/.ssh/id_ed25519`・`id_rsa`・`id_dsa`・`id_ecdsa`）。作業端末の `~/.ssh/config` には、ノードに当たる `IdentityFile` は無い。§1.4 のとおり、この形でサンドボックスの中から 8 台に入れることを確かめた。

### 2.6 drain と Longhorn の設定

drain する 4 台（pablo、duchamp、chirico、oeilvert）では、段 C の手順書のやり方をそのまま使う（§2.6、§3.7 の 1〜2、§3.8、§3.11 の 2〜4。元は前タスクの OS 更新の手順書 §2.4、§2.5、§3.3、§3.8）。段 C と違うのは、drain の後にするのがノードの再起動ではなく `install kubelet` であることと、`replica-auto-balance` が初めから `disabled` であることだけ。

1 台の流れ（§5.2）:

1. ✋ `concurrent-replica-rebuild-per-node-limit` を `0` にする（クラスタ全体。その台の後始末で必ず `5` に戻す）
2. ✋ 対象のノードに最後の replica を持つボリュームがあるときだけ、`node-drain-policy` を `allow-if-replica-is-stopped` にし、そのボリュームを使う workload（Prometheus、MinIO）を止めて detach を待つ
3. ✋ cordon、drain
4. 対象のノードにアタッチされた Longhorn のボリュームが 0 になったことを確かめる
5. ✋ `install kubelet`
6. 確認（§5.3）
7. ✋ uncordon、止めた workload を戻す、Longhorn の node が Ready・schedulable に戻ってから設定を戻す、再同期を待つ（§5.5）

段 C から変えない理由と、段 2 での見込み:

- **`concurrent-replica-rebuild-per-node-limit` を `0` にする**: drain で止まった対象のノードの replica を、ほかのノードに作り直させないため（段 C と同じ）。止まった replica はディスクに残り、uncordon の後にそのまま再同期する。段 2 では drain から uncordon までが段 C より短い（再起動が無く、`install kubelet` は 30〜60 秒）ので、`replica-replenishment-wait-interval`（6000 秒 = 100 分）に届く心配は段 C より小さい。逆に `0` にしないと、data locality（`best-effort`）や eviction で、drain の間に replica のコピーが走る
- **`node-drain-policy` は `block-if-contains-last-replica` のままでは drain が終わらない**: 最後の replica を持つボリュームがあると、Longhorn は instance-manager の PDB を外さない。dev では、Longhorn が最後の replica を別のノードに作り直して（1 GiB で 80 秒）から通した。本番では rebuild-limit が `0` なので作り直されず、drain が止まる（作り直させるとしても、prometheus の 20 GiB、MinIO の 100 GiB × 4 のコピーになる）。そこで、使う workload を止めて replica を stopped にし、`allow-if-replica-is-stopped` で通す（段 C の 5 台で通した形）。`always-allow` は使わない
- **replica 1 のボリュームは止まってよい**（段 C の手順書 §2.1 の 6。OS 更新のときからの決定）。replica は増やさない
- `replica-auto-balance` は普段から `disabled`（段 1 の手順書 §2.6）。段 2 で切り替えることも戻すことも無い

**replica 1 のボリュームの置き場所（2026-10-19 06:00Z ごろの読み取り）**。段 C の後から変わっていない。**data locality で Pod に付いて動くので、drain の前に必ず読み直す**（段 C では chirico と oeilvert の作業で prometheus の 2 つが入れ替わった）。

| ノード | 最後の replica を持つボリューム | 使っている Pod（2026-10-19） | drain の前に止めるもの |
|---|---|---|---|
| chirico | `monitoring/prometheus-kube-prometheus-db-prometheus-kube-prometheus-1`（pvc-99c35b80、20 GiB） | prometheus-1（chirico） | Prometheus リソース `monitoring/kube-prometheus` の `spec.replicas` を 0 |
| oeilvert | `monitoring/prometheus-kube-prometheus-db-prometheus-kube-prometheus-0`（pvc-625c8825、20 GiB）、`minio/export-minio-0`〜`3`（100 GiB × 4、data locality `disabled`） | prometheus-0（oeilvert）、minio-0（oeilvert）、minio-1（chirico）、minio-2（pablo）、minio-3（duchamp） | Prometheus の `spec.replicas` を 0、`minio/minio` の StatefulSet を 0 |
| pablo、duchamp | なし | — | なし（`node-drain-policy` も変えない） |
| braque | なし（Longhorn のノードではない） | — | drain しない |

replica の数（2026-10-19）: chirico 15、duchamp 10、oeilvert 17、pablo 3（段 1 の後に duchamp の古い stopped の replica が 1 つ片付いた。`results/stage-1/summary.md` §2）。

読み直し方は段 C の手順書 §2.6 と同じ。

```sh
kubectl --context fraction -n longhorn-system get volumes.longhorn.io \
  -o custom-columns=N:.metadata.name,NS:.status.kubernetesStatus.namespace,PVC:.status.kubernetesStatus.pvcName,S:.status.state,R:.status.robustness,NR:.spec.numberOfReplicas,NODE:.status.currentNodeID
kubectl --context fraction -n longhorn-system get replicas.longhorn.io \
  -o custom-columns=V:.spec.volumeName,NODE:.spec.nodeID,S:.status.currentState
```

**drain で止まるもの・動くもの（2026-10-19 の読み取り）**:

| 項目 | 結果 | 扱い |
|---|---|---|
| controller の無い Pod | どのノードにも無い | 当日に読み直す。あれば `--force` の前にユーザーに確かめる（段 C の手順書 §3.8 の 3） |
| PDB | `kube-system` の controller-manager・scheduler（control-plane だけ）、Longhorn の `csi-attacher`・`csi-provisioner`（ALLOWED 2）、各 instance-manager（ALLOWED 0）、`minio/minio`（maxUnavailable 1） | instance-manager の evict は、Longhorn がボリュームを外し終えるまで数回 `Cannot evict pod` になってから通る（段 C の本番で 3〜7 回、dev で 16 回。時間切れにはならなかった） |
| nodeSelector で 1 台に固定されたもの | `homegallery/api`（`kubernetes.io/hostname: oeilvert`） | **oeilvert の drain から uncordon まで Pending になる**。止まってよいことは OS 更新のときにユーザーが決めている（段 C の `results/stage-c/oeilvert.md` §3） |
| emptyDir を使う Pod（DaemonSet を除く） | chirico 11（aphrael ×2、`hedgedoc/db-postgresql-0`、metrics-server、llm-wiki、longhorn-ui、alertmanager-1、grafana、prometheus-1、`natsumi-myao-0`、searxng）、duchamp 3（aphrael、longhorn-ui、alertmanager-0）、oeilvert 3（prometheus-0、`natsumi-0`、`natsumi-aki-0`）、pablo 1（aphrael） | `--delete-emptydir-data` で消える。段 C でも同じ形で drain した（作業用の中身。消えてよい扱い） |
| 1 replica の Deployment | metrics-server、`kube-dns-autoscaler`、MetalLB の controller、kubelet-serving-cert-approver など | 退いてほかのノードで起き直すまで、数十秒止まる |
| gated（2 replica、chirico と duchamp） | PDB は無い | chirico・duchamp の drain で 1 つが退く。gated-v4・v6（`Local`）の告知は残った gated の Pod のノードへ移る（段 C の oeilvert） |
| CoreDNS（2 replica、PDB なし） | 2026-10-19 は duchamp と oeilvert | 1 つが退く間も、もう 1 つが答える |

### 2.7 MetalLB の告知ノードを読む

段 1 の手順書 §2.7 と同じ読み方。2026-10-19 06:00Z ごろ（speaker のログの最後の `serviceAnnounced`）は次のとおり。告知先は動くので、当日と各台の前に読み直す。

| Service | `externalTrafficPolicy` | アドレス | 告知ノード |
|---|---|---|---|
| `kube-system/porkadot-kubernetes`（API の VIP） | Cluster | 192.168.1.101 | **pablo** |
| `gated-system/gated-v4`、`gated-v6` | Local | 192.168.1.200、`::200` | chirico |
| `fs/h2-sshd` | Cluster | `::131` | 192.168.1.112 |
| `natsumi/natsumi-sshd` | Cluster | `::132` | 192.168.1.111 |
| `natsumi/natsumi-sshd-myao` | Cluster | `::133` | duchamp |
| `natsumi/natsumi-sshd-aki` | Cluster | `::134` | 192.168.1.112 |
| `minecraft/bds-v4`、`minecraft*/bds` | Cluster / Local | 192.168.1.223、`::999{1,2,3}` | 当日に読む |

段 1 と違い、段 2 では**各台の `install kubelet` でそのノードの speaker のコンテナが 1 回再起動する**ので、そのノードが告知している `Cluster` の LoadBalancer は、ほかの speaker が引き取るまで途切れる見込み（dev では VIP が 1 回、2 秒以内）。
`Local` のもの（gated）は、drain で gated の Pod が退いた時点で、残った Pod のノードへ移る。

- **pablo**（VIP）: drain では speaker は退かない（DaemonSet）。`install kubelet` で speaker が再起動するときに VIP が途切れる見込み。告知を先にほかのノードへ移す操作はしない（runbook から外れる）
- **.111、.112**（`natsumi-sshd`、`h2-sshd`、`natsumi-sshd-aki`）: その control-plane の `install kubelet` の後に `check-apps.sh` で応答を見る
- **duchamp**（`natsumi-sshd-myao`）、**chirico**（gated-v4・v6）: 同じく、その台の後に応答を見る

## 3. control-plane のマニフェストを上げる（`install kubernetes`）

### 3.1 事前確認

✋✋ **段 2 の開始の承認を取る。** §2.5 の表と PR の差分、§2.2 のベースライン、§2.4 のバックアップ、§2.6 の replica 1 の置き場所と止めるもの、§2.7 の告知ノードを示す。承認を得て PR をマージし、マージした master で §3.2 に入る。

- §2.2 のベースラインと §2.4 のバックアップが済んでいる。§2.3 の監視が動いている
- Longhorn の `replica-auto-balance` が `disabled`
- 全台 Ready、etcd 3/3 healthy、VIP の `/readyz` が `ok`
- checkout が §2.5 の PR をマージした master で、`git status --short assets porkadot.yaml` が空
- §1.4 の SSH の確かめで 8 台とも通る

### 3.2 流す ✋

```sh
porkadot install kubernetes --node 192.168.1.111
```

- **`--node` を必ず付ける。** 付けないと bootstrap ノード（pablo）で `kubectl apply` を流し、`127.0.0.1:6443` に届かず rc 1 になる（dev の記録の見つけたことの 6。何も変わらない）
- apiserver（DaemonSet）、controller-manager、scheduler、kube-proxy が v1.31.14 で rollout し、kubelet-serving-cert-approver が `0.12.1` で入れ替わる。CoreDNS、cnidaria、MetalLB はマニフェストが変わらないので動かない
- kubelet はまだ 1.30 なので、ここでコンテナの hash の件（§8.4）は起きない。rollout で入れ替わる Pod のほかは再起動しない見込み
- 時刻と rc を記録する。dev では `install kubernetes` から rollout の完了まで 3 分ほど、段 1 の本番では 3 分 12 秒だった

### 3.3 rollout の完了を確かめる

段 1 の手順書 §3.3 と同じ（版を v1.31.14 に読み替える。CoreDNS は v1.11.3 のまま）。加えて approver を見る。

```sh
kubectl --context fraction -n kube-system rollout status daemonset/kube-apiserver --timeout=10m
kubectl --context fraction -n kube-system rollout status deployment/kube-controller-manager --timeout=10m
kubectl --context fraction -n kube-system rollout status deployment/kube-scheduler --timeout=10m
kubectl --context fraction -n kube-system rollout status daemonset/kube-proxy --timeout=10m
kubectl --context fraction -n kubelet-serving-cert-approver rollout status deployment/kubelet-serving-cert-approver --timeout=10m
kubectl --context fraction version
```

| # | 確認 | 合格基準 |
|---|---|---|
| 1〜12 | 段 1 の手順書 §3.3 の 1〜12 | 同じ。Server が v1.31.14、apiserver・KCM・scheduler・kube-proxy が v1.31.14。CoreDNS は v1.11.3 のままで generation も変わらない。Node は 8 台 Ready で kubelet は v1.30.14 のまま（apiserver 1.31 と kubelet 1.30 は skew policy の範囲） |
| 13 | approver | `kubelet-serving-cert-approver` の Deployment が 1/1。Pod のイメージが `ghcr.io/alex1989hu/kubelet-serving-cert-approver:0.12.1`、`imagePullPolicy: IfNotPresent`、imageID が `sha256:445a8e5584f6…`。startupProbe を通って Ready。ログに `Successfully connected to Kubernetes API Server`、`Starting workers` |
| 14 | CSR | `kubectl --context fraction get csr` に新しい CSR が無い（出ていれば、kubelet の serving のものは approver が Approved,Issued にしていること。§8.10） |

```sh
kubectl --context fraction -n kubelet-serving-cert-approver get pods -o wide \
  -o custom-columns=N:.metadata.name,NODE:.spec.nodeName,IMAGE:.spec.containers[0].image,POLICY:.spec.containers[0].imagePullPolicy,ID:.status.containerStatuses[0].imageID,READY:.status.containerStatuses[0].ready
kubectl --context fraction -n kubelet-serving-cert-approver logs deploy/kubelet-serving-cert-approver | tail
```

- rollout が途中で 30 秒ほど止まって見えることがある（controller-manager のリーダーの交代。段 1 の手順書 §3.3 の注）
- ここで問題があれば、kubelet にまだ触っていないので、§7.2 で control-plane だけを戻せる

## 4. control-plane の kubelet を上げる（192.168.1.113 → .112 → .111）

### 4.1 何が起きるか

`install kubelet --node <IP>` は、`install-deps.sh`（kubelet・kubectl・crictl を落として張り替える。etcdctl と CNI plugins は同じ版なので落とさない）、`install-pkgs.sh`、`install.sh`（addon の `dns`、`multipathd`、`etcd`）を root で流し、kubelet を v1.31.14 で再起動する。

**段 1 と違い、kubelet が上がると、そのノードのコンテナがすべて 1 回再起動する**（§8.4）。control-plane では次のものになる。

| コンテナ | 見込み |
|---|---|
| etcd（static Pod） | `etcd-server.yaml` は変わらないが、hash の件でコンテナが 1 回再起動する（mirror Pod は作り直され UID が変わる）。dev では 2 秒で起き直し、ほかのメンバーから見て unhealthy にならなかった。リーダーなら先に移す（§4.2 の 2） |
| kube-apiserver（DaemonSet） | SIGTERM の後、30 秒ほど ready を返さずに残ってから止まり、起き直す（dev）。ほかの 2 台が ready なので VIP は応答し続けた |
| kube-controller-manager、kube-scheduler | 1 回再起動する。リーダーなら lease がほかの Pod に移るまで（15〜30 秒）controller や scheduling が止まる |
| kube-proxy、cnidaria | 1 回再起動する。cnidaria は起動のときに経路と nftables の規則を入れ直す |
| MetalLB の speaker | 1 回再起動する。そのノードが告知している `Cluster` の LoadBalancer が途切れる（§2.7） |
| node-exporter、smart-exporter | 1 回再起動する |

- 再起動の数は、**kubelet の起動から 1 分ほど待って数える**。SIGTERM で止まらないコンテナ（apiserver など）は 30 秒の猶予の後に kill され、順に再起動する（dev の記録）
- `etcd` の addon は `/etc/etcd/pki` の証明書と鍵を root 0600 で置き直す。`etcd.crt` は作り直したもの（同じ鍵、同じ CA。§2.5）に替わり、再起動した etcd が読む
- `dns` の addon は `systemd-networkd` を再起動するので、cnidaria の `no route` のログが出る（§8.1）
- drain も cordon もしない。controller-manager と scheduler も移さない（段 1 の手順書 §4.1 の理由に加え、コンテナはどのみち 1 回再起動するので、移しても得るものが無い）
- **apiserver が止まりかける間、ほかのノードの leader election を使う controller が 1 回再起動することがある**（§8.8）。コンテナの再起動では Pod は消されず Terminating にならないので、apiserver の Pod が Endpoints から外れるのは readiness の失敗が数えられてからになる。その間に `kubernetes` Service（10.254.0.1）の要求の一部が止まりかけた apiserver に振り分けられうる（見込み。dev では途切れを見ていない）

### 4.2 1 台の手順

1. 読み取りの確認。段 1 の手順書 §4.2 の 1 と同じ（etcd のリーダー、対象のノードの Pod の名前・UID・restartCount、`/opt/bin`、`/etc/etcd/pki`、cnidaria のログの error の数、controller-manager と scheduler の置き場所とリーダー、告知している LoadBalancer）。
   2026-10-19 は、controller-manager が .111（`-6pg99`）と .113（`-jg62c`、リーダー）、scheduler が .111（`-lffqk`、リーダー）と .112（`-nbklj`）。
2. ✋ 対象が etcd のリーダーなら、リーダーを移す（段 1 の手順書 §4.2 の 2 と同じ形）。
   - 2026-10-19 のリーダーは .113（`57ec6f12ac7b683e`）。このままなら、.113 の作業の前に .111（`21ab2aeb56731588`）へ移し、.111 の作業の前に .113 か .112（`fbb0c648cf5852a5`）へ移す（段 1 と同じ形）
   - 移せなかったときは止める
3. ✋ 流す。

   ```sh
   porkadot install kubelet --node <IP>
   ```

   時刻（開始と終わり）と rc を記録する。段 1 の本番では 1 台 29 秒〜1 分 40 秒だった。
4. kubelet の起動から 1 分ほど待ってから、§4.3 の確認。

### 4.3 1 台ごとの確認と、次の 1 台へ進む条件

| # | 確認 | 方法 | 合格基準 |
|---|---|---|---|
| 1 | Node | `kubectl --context fraction get node <IP> -o wide` | Ready、VERSION が v1.31.14、CONTAINER-RUNTIME が `containerd://2.3.6` |
| 2 | バイナリ | ノードで `ls -l /opt/bin/{kubelet,kubectl,etcdctl,crictl}`、`/opt/bin/kubelet --version`、`cat /opt/cni/bin/.porkadot-cni-plugins-version` | 向き先が `kubelet-v1.31.14`、`kubectl-v1.31.14`、`etcdctl-3.5.34`（変わらない）、`crictl-v1.31.1`。CNI の印が `v1.4.1`。前の版のファイル（`kubelet-v1.30.14` など）も残っている（§7 の戻しで使う） |
| 3 | etcd の pki | `sudo stat -c '%a %U:%G %n' /etc/etcd/pki/*` | 3 つとも `600 root:root` |
| 4 | etcd | `etcdctl endpoint status --cluster -w table`、`etcdctl endpoint health --cluster -w table` | 3/3 healthy、リーダーが居る、raft index がそろう。3 台とも 3.5.34 |
| 5 | etcd の Pod | `kubectl --context fraction -n kube-system get pod etcd-<IP> -o wide`、ログの `error` | 1/1 Running、`etcd:3.5.34-0`。再起動の直後のほかのメンバーの `lost TCP streaming connection`・`peer became inactive` は数秒で止まる（段 1 と同じ形） |
| 6 | apiserver | 対象のノードの `kube-apiserver` の Pod | 1/1 Ready。**UID は同じで、restartCount が 1 増える**。VIP の `/readyz` が `ok` |
| 7 | Pod の再起動 | 段 1 の手順書 §4.2 の 1 と同じコマンド | **名前と UID が同じ（etcd の mirror Pod は除く）、各コンテナの restartCount がちょうど 1 増える**。2 以上増えたもの、CrashLoopBackOff、Running に戻らないものがあれば止める。**例外（control-plane）**: apiserver が SIGTERM の後に 6443 を閉じたまま Endpoints に残る間（最長 30 秒）、そのノードで起き直した API を使うコンテナ（controller-manager、cnidaria、speaker など）が `https://10.254.0.1:443` の `connection refused` で数回落ち、10 秒ほど CrashLoopBackOff になり、§2.3 の監視の VIP が数十秒ところどころ失敗しうる（段 2 の .111。`results/stage-2/192.168.1.111.md` §5.1）。apiserver が起き直した後に Running に戻り、それ以上再起動が増えなければ許容する（2026-10-19 のユーザーの判断）。回数を記録する |
| 8 | cnidaria | 全ノードの cnidaria の Pod が Ready。`verify-nodes.sh` | 全 PASS。ログは §8.1 のとおり（対象のノードの cnidaria は再起動したので、起動の後のログで見る） |
| 9 | KCM と scheduler | `kubectl --context fraction -n kube-system get pods -o wide -l 'app.kubernetes.io/component in (kube-controller-manager,kube-scheduler)'`、lease の holder | 2/2 ずつ Ready。対象のノードのものは restartCount が 1 増える。リーダーが移ったかを記録する |
| 10 | kubelet のログ | ノードで `sudo journalctl -u kubelet --since '-10min' --no-pager \| grep -iE 'error\|fail' \| tail` | 起動の直後の `InvalidDiskCapacity`（§8.5）、`crio` の factory、`node not found`（lister）、etcd の mirror Pod の `already exists`、古いコンテナの `ContainerStatus ... NotFound` のほかに、続くエラーが無い。`definition changed, will be restarted` は journal ではなくイベント（reason `Killing`）に出る |
| 11 | §2.3 の監視 | — | 失敗があれば、§2.7 の告知ノードと 12 の再起動と突き合わせて記録する（§8.8。数回までは許容） |
| 12 | leader election を使う controller | §8.8 のコマンド（時刻は 4.2 の 3 の開始） | **ほかのノードの** `gated` や Longhorn の CSI sidecar が 1 回再起動していてもよい。Running に戻り、再起動が続いていない。何が再起動したかを記録する |
| 13 | 告知していた LoadBalancer | §2.7 の読み方と `check-apps.sh` | 応答する。告知が移ったか、戻ったかを記録する |
| 14 | CSR | `kubectl --context fraction get csr` | 新しい CSR が無い。出ていれば Approved,Issued（§8.10） |

次のすべてを満たしてから、次の 1 台に入る。

- 上の 1〜14 がすべて合格
- 全 8 台の Node が Ready
- etcd 3/3 healthy、raft index がそろっている
- Running / Completed 以外の Pod がベースラインから増えていない

## 5. worker の kubelet を上げる（1 台ずつ）

### 5.1 順番

段 1 と同じ順にする。braque は drain しない（§5.4）。

| 順 | ノード | drain | replica 1 のボリューム（2026-10-19） | replica の数 | 理由・注意 |
|---|---|---|---|---|---|
| 1 | pablo | する | なし | 3 | 手順の確かめに向く。**API の VIP を告知している**（§2.7）。Pod は 7 つ（DaemonSet を除く）で、minio-2 が載っている |
| 2 | duchamp | する | なし | 10 | 冷却ファンが故障中（ターボ停止運用）。再起動はしないので `no_turbo` はそのまま。gated の 1 つ、CoreDNS の 1 つ、minio-3 が載っている |
| 3 | braque | **しない** | なし（Longhorn のノードではない） | 0 | nfsd のコンテナが 1 回再起動する（§5.4）。他の worker が健全な状態で、バックアップの CronJob の時間帯を避けて行う |
| 4 | chirico | する | `prometheus-...-1` | 15 | Pod が最も多い（55）。gated-v4・v6 を告知している。minio-1、approver（`install kubernetes` の前の置き場所） |
| 5 | oeilvert | する | `prometheus-...-0`、`export-minio-0`〜`3` | 17 | 最後の replica が最も多い。worker の最後にする（計画 §6.2）。`homegallery/api` が Pending になる |

- 当日の読み取りで replica 1 の置き場所が変わっていれば、止めるものを決め直す（§2.6）。oeilvert は最後のままにする
- drain で Pod がほかのノードへ寄るので、後のノードほど載っている Pod が増えていることがある（段 C の pablo の Pod はすべて oeilvert に移った）。1 台ごとに読み直す

### 5.2 drain する 4 台（pablo、duchamp、chirico、oeilvert）の手順

1. 読み取りの確認。
   - `kubectl --context fraction get node <ノード> -o wide`: Ready、v1.30.14
   - 対象のノードの Pod の名前・UID・restartCount を控える（§4.2 の 1 のコマンド。`spec.nodeName=<ノード>`）。DaemonSet の Pod は drain の後も残るので、§5.3 で比べる
   - Longhorn: §2.6 の読み直し（最後の replica を持つボリュームと止めるもの）、**全ボリュームの replica の置き場所**、対象のノードの replica の数。degraded のボリュームが無い（ベースラインのものを除く）
   - Longhorn の設定: `replica-auto-balance` が `disabled`、`concurrent-replica-rebuild-per-node-limit` が `5`、`node-drain-policy` が `block-if-contains-last-replica`（前の台で戻し忘れていないこと）
   - controller の無い Pod（下の 5 のコマンド）、PDB（`kubectl --context fraction get pdb -A`）
   - そのノードが告知している LoadBalancer（§2.7）
   - ノードで `ls -l /opt/bin/{kubelet,kubectl,crictl}`
2. ✋ `infra-admin` のトークンを発行する（§1.2）。
3. ✋ Longhorn の設定を変える。変える前の値を記録してから。

   ```sh
   kubectl --context fraction -n longhorn-system get settings.longhorn.io \
     concurrent-replica-rebuild-per-node-limit replica-auto-balance node-drain-policy
   kubectl-admin -n longhorn-system patch settings.longhorn.io concurrent-replica-rebuild-per-node-limit --type=merge -p '{"value":"0"}'
   # 最後の replica を持つボリュームがあるときだけ（2026-10-19 の表では chirico、oeilvert）
   kubectl-admin -n longhorn-system patch settings.longhorn.io node-drain-policy --type=merge -p '{"value":"allow-if-replica-is-stopped"}'
   kubectl --context fraction -n longhorn-system get settings.longhorn.io \
     concurrent-replica-rebuild-per-node-limit replica-auto-balance node-drain-policy   # APPLIED が true
   ```

   ここで止めることになったときも、変えた設定は必ず元の値に戻す（§5.5 の 3）。
4. ✋ 最後の replica を使う workload を止める（1 の読み直しで決めたものだけ）。
   - chirico: `kubectl-admin -n monitoring patch prometheus kube-prometheus --type=merge -p '{"spec":{"replicas":0}}'`
   - oeilvert: 上の Prometheus と、`kubectl-admin -n minio scale statefulset minio --replicas=0`
   - 対象のボリュームが detached になり、対象のノードの replica が stopped になるのを待つ（段 C の本番では 6〜44 秒）。Prometheus は 2 つとも止まり、MinIO は 4 つとも止まる（止まってよい。§2.6）
5. ✋ cordon と drain。

   ```sh
   kubectl-admin cordon <ノード>
   kubectl --context fraction get pods -A --field-selector spec.nodeName=<ノード> -o json \
     | jq -r '.items[] | select((.metadata.ownerReferences // []) | length == 0) | .metadata.namespace + "/" + .metadata.name'
   kubectl-admin drain <ノード> --ignore-daemonsets --delete-emptydir-data --timeout=20m
   ```

   - controller の無い Pod が見つかったら、消してよいかをユーザーに確かめる（runbook から外れる扱い）。よければ `--force` を足す
   - instance-manager の evict が PDB で数回待たされるのは想定どおり（§2.6）
   - 止まったときの調べ方は段 C の手順書 §3.8 の 3 と同じ（`kubectl --context fraction get pdb -A`、longhorn-manager のログの `removing <ノード> PDB is blocked: replica ...`）。止まった理由が §2.6 の表に無いボリュームなら、止めて報告する
   - 開始と終わりの時刻を記録する（段 C の本番では 1 秒〜2 分）
6. drain の後の確認（読み取り）。**ここが合格するまで `install kubelet` に入らない。**
   - 対象のノードに Longhorn のボリュームがアタッチされていない

     ```sh
     kubectl --context fraction get volumeattachments -o custom-columns=N:.metadata.name,NODE:.spec.nodeName,A:.status.attached | grep -w <ノード>   # 空
     kubectl --context fraction -n longhorn-system get volumes.longhorn.io -o json \
       | jq -r --arg n <ノード> '.items[] | select(.status.currentNodeID == $n) | .metadata.name'                   # 空
     kubectl --context fraction -n longhorn-system get pods -o wide --field-selector spec.nodeName=<ノード> | grep instance-manager  # 無い
     ```

   - 対象のノードの replica はすべて stopped で、ほかのノードに代わりの replica が作られていない（rebuild-limit が `0` のため。`replicas.longhorn.io` のボリュームとノードの組が 1 と同じ）
   - 対象のノードに残っているのは DaemonSet の Pod だけ
   - 退いた Pod がほかのノードで Running に戻りつつある（Longhorn のボリュームを使うものはアタッチを待って 1〜2 分かかる。段 C の chirico）。Running / Completed 以外の Pod は、退いて作り直している途中のものと、oeilvert の `homegallery/api`（Pending）だけ
7. ✋ 流す。

   ```sh
   porkadot install kubelet --node <ノード>
   ```

   - `<ノード>` は `porkadot.yaml` の `nodes` のキー（`pablo`、`duchamp`、`chirico`、`oeilvert`）
   - 時刻（開始と終わり）と rc を記録する。段 1 の本番では 1 台 27〜47 秒だった
8. kubelet の起動から 1 分ほど待ってから、§5.3 の確認。
9. §5.5 の uncordon と後始末。

### 5.3 drain した台の確認（uncordon の前）

**すべて cordon のまま行う。**

| # | 確認 | 方法 | 合格基準 |
|---|---|---|---|
| 1 | Node | `kubectl --context fraction get node <ノード> -o wide` | Ready,SchedulingDisabled、VERSION が v1.31.14、CONTAINER-RUNTIME が `containerd://2.3.6` |
| 2 | バイナリ | ノードで `ls -l /opt/bin/{kubelet,kubectl,crictl}`、`cat /opt/cni/bin/.porkadot-cni-plugins-version` | 向き先が `kubelet-v1.31.14`、`kubectl-v1.31.14`、`crictl-v1.31.1`。CNI の印が `v1.4.1`。`kubelet-v1.30.14` なども残っている |
| 3 | 残った Pod の再起動 | §5.2 の 1 と同じコマンド | DaemonSet の Pod（cnidaria、kube-proxy、speaker、longhorn-manager、longhorn-csi-plugin、engine-image、node-exporter、smart-exporter など）の**名前と UID が同じで、各コンテナの restartCount がちょうど 1 増える**。2 以上増えたもの、CrashLoopBackOff、Running に戻らないものがあれば止める（下の注） |
| 4 | cnidaria | 対象のノードの cnidaria が 1/1 Ready。`verify-nodes.sh` | 全 PASS。ログは §8.1 |
| 5 | Longhorn | 対象のノードにアタッチされたボリュームが無い。対象のノードの replica は stopped のまま、ほかのノードに replica が足されていない。Longhorn の node（`nodes.longhorn.io <ノード>`）が Ready に戻った（longhorn-manager の再起動で一瞬 not ready になる） | 同じ。replica が動いていたら止めて報告する |
| 6 | kubelet のログ | ノードで `sudo journalctl -u kubelet --since '-10min' --no-pager \| grep -iE 'error\|fail' \| tail` | 起動の直後の `InvalidDiskCapacity` と `definition changed`・`Killing` のほかに、続くエラーが無い |
| 7 | §2.3 の監視 | — | 失敗があれば、§2.7 の告知ノードと突き合わせて記録する。pablo では VIP が 1〜数回失敗しうる（許容） |
| 8 | 告知していた LoadBalancer | §2.7 の読み方と `check-apps.sh` | 応答する。告知が移ったかを記録する |
| 9 | CSR | `kubectl --context fraction get csr` | 新しい CSR が無い。出ていれば Approved,Issued（§8.10） |

- longhorn-csi-plugin は、longhorn-manager が上がるまで `node-driver-registrar` が CSI の socket に繋がらず、数回 CrashLoopBackOff になってから戻ることがある（段 C の duchamp・pablo。ノードの再起動のときのもの）。そのときは 3 の「ちょうど 1」を「数回、数分で 3/3 Running に戻る」と読み替え、回数を記録する。5 分たっても戻らなければ止める
- speaker と cnidaria も、起動の直後に API に繋がらず 1 回落ちることがある（段 C の手順書 §3.10。ノードの再起動のときのもの。kubelet の更新では dev で見ていない）。同じく回数を記録し、数分で戻ればよい

### 5.4 braque の手順（drain しない）

braque には DaemonSet の Pod（cnidaria、kube-proxy、node-exporter、smart-exporter）と、**nfsd の DaemonSet の Pod（`nfsd/nfsd-*`、hostNetwork、privileged、`registry.k8s.io/e2e-test-images/volume/nfs:1.6.0`、終了の猶予 30 秒）**だけが載っている（2026-10-19）。Longhorn のノードではなく、longhorn-csi-plugin も載らないので、Longhorn のボリュームはアタッチされない（§8.11）。
drain しても退く Pod が無い（段 C の braque の drain は 1 秒で、Pod は 1 つも退かなかった）ので、drain しない。

**`install kubelet` で nfsd のコンテナも 1 回再起動し、NFS が短く止まる。** 止まる時間は、nfsd が SIGTERM で止まるまで（最長 30 秒）と、起き直すまで。NFSv4 の grace period で、起き直した後もしばらく新しい open や lock が待たされることがある（dev に nfsd が無いので確かめていない）。

- 影響を受けるもの（2026-10-19 の読み取り）: braque の NFS（192.168.1.131）の PV を使う Pod（`carib`・`pondo`・`shja` の nginx、`carib2`・`pondo2`・`shja2` の `movies`、`docker/registry`（`registry.fraction.jp`）、`hedgedoc` の backup）、fs の Service 経由のもの（`aphrael`、`comics`、`sites`、`homegallery` の web など。fs の h2・sites は Longhorn のボリュームを fs の Pod が NFS で出しているもので、braque の nfsd とは別）、oeilvert のホストの `/home/yuanying/shared/nfs`
- 段 C の braque の再起動では、`carib2`・`pondo2`・`shja2` の `movies` の Pod が NFS が戻ったところで liveness で 1 回ずつ再起動した（`results/stage-c/braque.md` §5）。段 2 でも起こりうる。Running に戻っていればよい
- **バックアップの CronJob の時間帯を避ける**（段 C の手順書 §2.5。2026-10-19 に schedule を見直し、変わっていなかった）。止めてはいけない時間帯（JST）: 05:15〜06:45、14:30〜15:00、16:45〜17:05、17:55〜18:15。作業の前に `kubectl --context fraction get cronjobs -A` で見直す
- 始める前にユーザーに伝える（NFS と `registry.fraction.jp` が短く止まる）

手順:

1. 読み取りの確認。§5.2 の 1 のうち、Node、Pod の名前・UID・restartCount、`/opt/bin`、告知している LoadBalancer。加えて、braque にアタッチされた Longhorn のボリュームが無いこと（§8.11 のコマンド）、NFS の PV を使う Pod の restartCount、時間帯
2. ✋ `porkadot install kubelet --node braque`。時刻と rc を記録する
3. kubelet の起動から 1 分ほど待ってから確かめる
   - §5.3 の 1、2、4、6〜9（Ready、`SchedulingDisabled` ではない）
   - braque の Pod の名前と UID が同じで、各コンテナの restartCount がちょうど 1 増える。nfsd が Running で、2049 を listen している
   - NFS の PV を使う Pod が Running。liveness で 1 回再起動したものがあれば記録する（2 回以上、CrashLoopBackOff なら止める）
   - oeilvert のホストの `/home/yuanying/shared/nfs` が読める。`registry.fraction.jp/v2/` が応答する（401 でよい）
   - LAN から Service の IP（10.254.0.0/16）と `fraction.cluster` の名前が引ける（braque の kube-proxy と `dns` の addon も再起動する。段 1 の braque で、`systemd-networkd` の再起動で古い kubelet の `Failed to update lease` が 1 回出た。`results/stage-1/braque.md` §7）

### 5.5 uncordon と後始末 ✋（drain した台）

段 C の手順書 §3.11 と同じ。

1. ✋ `kubectl-admin uncordon <ノード>`（§5.3 が通ってから）。
2. ✋ §5.2 の 4 で止めたものを戻す。Prometheus リソースの `spec.replicas` を 2 に、oeilvert では `minio/minio` を 4 に。Pod が Running になり、ボリュームが attached になったことを確かめる。oeilvert では `homegallery/api` が oeilvert で Running に戻ったことも見る。
3. Longhorn の node（`kubectl --context fraction -n longhorn-system get nodes.longhorn.io <ノード>`）が Ready で schedulable に戻ったことを確かめてから、✋ 設定を §5.2 の 3 で記録した値に戻す（`concurrent-replica-rebuild-per-node-limit` を `5`、変えたときだけ `node-drain-policy` を `block-if-contains-last-replica`）。読み直して APPLIED が true であること。切り替えてから戻すまでの時間を記録する。
4. Longhorn: uncordon の後に Longhorn が instance-manager を作り直し、対象のノードの stopped の replica が再同期するのを待つ。degraded のボリュームがベースラインから増えていないこと。段 C では、設定を戻してから全部 healthy になるまで 16 分ほどかかった。終わった後の replica の置き場所を記録し、同じボリュームの replica が同じノードに 2 つ載っていないことを見る（`kubectl --context fraction -n longhorn-system get replicas.longhorn.io -o json | jq -r '.items[]|.spec.volumeName+" "+.spec.nodeID' | sort | uniq -d` が空）。data locality で replica の置き場所が変わることがある（§2.6）ので、次の台の前に §2.6 の表を読み直す。
5. Running / Completed 以外の Pod が、ベースラインから増えていないこと。退いた Pod は uncordon しても戻らない（ほかのノードで動き続ける）。
6. ✋ `netcheck.sh` と `check-apps.sh` を流す。ベースラインと同じであること（Pod の置き場所の違いのほか）。
7. `infra-admin` のトークンを破棄する（`unset ADMIN_TOKEN`、ファイルの削除）。
8. `results/stage-2/<ノード>.md` に記録する（§9）。

### 5.6 次の 1 台へ進む条件

次の **すべて** を満たしてから、次のノードに入る。

- §5.3（braque は §5.4 の 3）がすべて合格
- 全 8 台の Node が Ready、どれも SchedulingDisabled でない。終えたノードが v1.31.14、まだのノードが v1.30.14
- etcd 3/3 healthy、VIP が応答する
- Running / Completed 以外の Pod がベースラインから増えていない
- Longhorn のボリュームが healthy（ベースラインのものを除く）。**再同期が終わっている**
- Longhorn の設定が元の値（`5`、`disabled`、`block-if-contains-last-replica`）。Prometheus の `spec.replicas` が 2、`minio/minio` が 4
- `netcheck.sh`、`check-apps.sh` がベースラインと同じ

段 C と違い、ノードを再起動しないので、30 分おいて様子を見る条件は置かない。

## 6. 段 2 の完了の確認

8 台を終えたら、計画 §6.3 の項目がすべて成り立つことを確かめ、`results/stage-2/summary.md` に残す。段 1 の手順書 §6 と同じ項目で、次を読み替える・足す。

- 8 台が Ready、全台 v1.31.14、CONTAINER-RUNTIME が `containerd://2.3.6`。どのノードも SchedulingDisabled でない
- etcd 3/3 healthy、全メンバーが 3.5.34、リーダーが居る、raft index がそろう。3 台の `/etc/etcd/pki` が root 0600
- VIP の `/livez` が `ok`、`/version` が v1.31.14
- apiserver 3/3、controller-manager と scheduler が 2/2（置き場所とリーダーを記録する）。kube-proxy が 8/8 で iptables。CoreDNS が v1.11.3 で Running
- kubelet-serving-cert-approver が `0.12.1` で Running
- Running / Completed 以外の Pod が無い（ベースラインのものを除く）
- **全 Pod の restartCount の、ベースライン（§2.2 の 5）からの増え方**: 段 2 の間に動き続けた Pod は、各コンテナがちょうど 1 増えている（drain で作り直された Pod は新しい UID で 0）。2 以上増えたものは、理由（leader election、NFS の liveness、CrashLoopBackOff の回数など）を書いて分ける
- Longhorn: attached のボリュームが全部 healthy（detached の 2 つはベースラインのとおり）、instance-manager が全部 running、engine image は v1.11.2 のまま。K8s 1.31 は Longhorn 1.11 の要件（1.25 以上）に入る。replica の置き場所（data locality で動いたものを記録する）
- Longhorn の設定: ベースラインのまま（`5`、`disabled`、`block-if-contains-last-replica`、`best-effort`）。Prometheus 2、MinIO 4
- cnidaria: 8 台の Pod が Ready、`verify-nodes.sh` が全 PASS、✋ `netcheck.sh` が全 PASS、`hedgedoc/db-postgresql` の NetworkPolicy がノードの nftables に入っている
- MetalLB: LoadBalancer の Service が応答する（gated、`h2-sshd`、`natsumi-sshd*`、minecraft）。告知ノードを記録する
- braque の NFS が応答する。`registry.fraction.jp` が応答する
- `kubectl --context fraction top nodes` が応答し、Prometheus のスクレイプが落ちていない。`apiserver_requested_deprecated_apis` を記録する（段 3 の 1.32 で `flowcontrol.apiserver.k8s.io/v1beta3` が消える。計画 §7）
- `kubectl --context fraction get csr`: 段の間に出た CSR が無いか、出ていれば Approved,Issued。kubelet の serving の証明書の subject と期限が §2.2 の 12 と同じ（§8.10）
- 新しい warning のイベント・ログ（kubelet、apiserver、kube-proxy、cnidaria、etcd、Longhorn）が増えていない（§8 のものは除く）
- §2.3 の監視の FAIL を集計し、原因（告知ノードの speaker の再起動、gated の Pod の移動、apiserver の止まりかけ、gated の再起動、それ以外）ごとに分けて記録する
- 段 2 の間に leader election で再起動した controller の一覧（§8.8）。どれも Running に戻っている
- etcd のバックアップ（§2.4）を worktree からメインの checkout の `backup/` へ移した（worktree で流した場合）

## 7. ロールバック

**戻すのは runbook から外れる操作なので、その都度ユーザーの承認を取る。** 戻すと決める目安は段 1 の手順書 §7 と同じ（rollout が終わらない、VIP が 1 分を超えて応答しない、Node が 5 分たっても Ready にならない、etcd が 2/3 を下回る、Pod の再起動が続く、Longhorn のボリュームが degraded のまま戻らない、1.31 に固有と見られる問題）。加えて、**コンテナの再起動が 1 回で収まらない**（同じコンテナが 2 回以上、CrashLoopBackOff）。

### 7.1 戻すための材料

前の版は、**この PR の前の master（`34b15e3`）の `assets/` と `porkadot.yaml`** と、**porkadot 0.30.0**（`v0.30.0`、`7d607a7`）を使う。この `assets/` は 0.30.0 で render したもので、本番は今これで動いている。

- 0.30.0 の `install kubelet` は `/opt/bin/<名前>` の向き先で判定して張り替える（porkadot#26）。前の版のバイナリ（`kubelet-v1.30.14` など）はノードに残っているので、落とし直さずに向き先を戻す。**`--force` は要らない**。0.30.0 で render した assets を 0.30.0 で流す組み合わせは、dev の `verification-0.30-rc.md` で `--force` なしの戻しと上げ直しを通したものと同じ形である
- **0.30.0 の SSH は段 1 のときの制約のまま**（§8.9）。サンドボックスの中では ssh-agent が使えずに認証で落ちるので、戻しの porkadot はサンドボックスの外で流す（ユーザーの判断。段 1 と同じ）。known_hosts の .112・.113 の行は段 1 で並べ替えてあるので、mismatch は出ない見込み。流す前に段 1 の手順書 §8.10 の確かめ方（0.30.0 の bundle で）を流す
- **1.31 → 1.30 の kubelet の戻しでも、コンテナの hash の計算が変わるので、そのノードの全コンテナがもう一度 1 回再起動する見込み**（dev では確かめていない）。Longhorn のノードは、上げるときと同じく drain してから戻す（§5.2 の 2〜6 と §5.5）

用意の仕方（作業端末で。ノードには触らない）:

```sh
git -C /home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot worktree add /tmp/porkadot-0.30.0 v0.30.0
P_OLD=/tmp/porkadot-0.30.0
git -C <このリポジトリ> worktree add /tmp/fraction-stage-1 34b15e3
cd /tmp/fraction-stage-1
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

- `bundle install` が要ることがある（0.30.0 の Gemfile.lock）。始める前に `grep VERSION $P_OLD/lib/porkadot/version.rb` が 0.30.0 で、`BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot help` が動くことを確かめておく
- secrets は前の版も同じ（sops の同じ鍵。§1.6）

### 7.2 `install kubernetes` の後、kubelet はまだ前の版 ✋

```sh
cd /tmp/fraction-stage-1
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml
```

- apiserver・KCM・scheduler・kube-proxy が v1.30.14 に戻る。**approver は `:main`／`Always` に戻り、上流の `main` を取りに行く**（段 1 までと同じ状態）
- dev では確かめていない（段 1 の §7.2 と同じ）。§3.3 と同じ確認を、版を読み替えて行う
- apiserver を前のマイナーへ戻すと、新しい版で書かれた storage の版があると読めなくなる恐れがある（計画 §6.4）。組み込みの資源の storage の版が 1.31 で変わるかは、この手順書では一つずつ確かめていない。**段 2 の間に、1.31 で新しく使えるようになった API のオブジェクトを作らない**。戻すのは、上げてから間もなく問題が出たときに限る

### 7.3 kubelet を戻す（1 台） ✋

```sh
cd /tmp/fraction-stage-1
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubelet --node <ノード> --config ./porkadot.yaml
```

- `/opt/bin` の向き先が `kubelet-v1.30.14`、`kubectl-v1.30.14`、`crictl-v1.30.1` に戻る（etcdctl は 3.5.34 のまま）。確かめる
- Longhorn のノード（pablo、duchamp、chirico、oeilvert）は、§5.2 の 2〜6 のとおり drain してから流し、§5.3 と §5.5 で戻す
- control-plane では、戻す台が etcd のリーダーなら先に §4.2 の 2 でリーダーを移す。etcd のイメージは変わらない（3.5.34 のまま）ので、段 1 の戻しの 2380 番の重なり（段 1 の手順書 §8.3）は当たらない見込み
- 戻した台でも、§4.3 または §5.3 の確認を、版を読み替えて行う

### 7.4 段 2 全体をやめる

kubelet は kube-apiserver より新しくてはいけないので、**kubelet を先に戻し、control-plane を最後に戻す。**

1. worker を、上げた順の逆に §7.3 で戻す
2. control-plane の kubelet を、上げた順の逆（.111 → .112 → .113）に §7.3 で戻す
3. §7.2 で control-plane のマニフェストを戻す

戻し終えたら、§6 の確認を版を読み替えて行い、`results/stage-2/` に戻した経緯を残す。etcd のバックアップ（§2.4）からの restore は最後の手段で、段 1 の手順書 §7.4 と同じ扱い（その時点でユーザーと決める）。

## 8. 既知の問題と注意

### 8.1 `install kubelet` のたびの cnidaria の `no route`

段 1 の手順書 §8.1 と同じ。`dns` の addon が `systemd-networkd` を再起動するたびに、対象のノードの cnidaria が `Reconciler error ... no route` を数件、1 秒ほど出し、ほかのノードの cnidaria が info の `no route for a family` を数件出す（段 1 の本番では 6〜8 件。oeilvert だけは出なかった）。
段 2 では、続けて対象のノードの cnidaria のコンテナ自身が 1 回再起動する（§8.4）。再起動の前のログは `--previous` で読む。1 秒を超えて続く、ほかの error が出る、`verify-nodes.sh` が FAIL する、のどれかなら止める。

### 8.2 render が証明書を作り直す

段 1 の手順書 §8.2 と同じ。`bootstrap.crt`（9 つ）と master の `addons/etcd/etcd.crt`（3 つ）は render のたびに作り直される（同じ鍵、同じ CA）。当日に render し直さない。

### 8.3 戻しの etcd の 2380 番の重なり

段 1 の手順書 §8.3。段 2 は etcd のイメージを変えないので、上げるときも戻すときも当たらない見込み。etcd のコンテナは hash の件で 1 回再起動するが、dev では 2 秒で起き直した。

### 8.4 1.31 の kubelet での全コンテナの 1 回の再起動（kubernetes#124220）

K8s 1.31 で kubelet のコンテナの hash の計算が変わった（CHANGELOG-1.31 の「Kubelet will not restart the container when fields other than image in the pod spec change」）。1.30 の kubelet が作ったコンテナは、1.31 の kubelet から見ると hash が合わないので、`Container <名前> definition changed, will be restarted` として 1 回ずつ作り直される。

- Pod は作り直されない（UID は同じ）。restartCount が 1 増え、`lastState.terminated` は、SIGTERM で止まるものは kubelet の起動の 1〜2 秒後に Completed / Error、止まらないものは 30 秒の猶予の後に Error 137（dev の記録）
- static Pod（etcd）は mirror Pod が作り直される（UID が変わる）
- 同じ版の kubelet の再起動では起きない（dev の #31 の確かめ）。段 3 以降で同じことが起きるかは、その段の dev の検証で見る
- **Longhorn のボリュームがアタッチされたノードで drain せずに起きると、instance-manager も再起動して engine と replica が落ち、ボリュームが faulted になる**（dev の記録の「Longhorn」）。そのため Longhorn のノードは drain する（§2.1 の 3）
- drain しても、そのノードに残る DaemonSet の Pod は 1 回ずつ再起動する。drain では避けられない

### 8.5 kubelet の再起動の直後の `InvalidDiskCapacity`

段 1 の手順書 §8.6 と同じ。想定内。

### 8.6 porkadot を流す場所

段 1 の手順書 §8.7 と同じ。cwd はこのリポジトリのルートにする。

### 8.7 全台が止まったとき

段 1 の手順書 §8.8 と同じ。段 2 ではノードを再起動しないので当たらない。

### 8.8 apiserver が止まりかける間の leader election の controller の再起動

段 1 の手順書 §8.9 と同じ扱い（ユーザーの判断で許容。記録して、Running に戻ったことと、再起動が続いていないことを確かめる）。段 1 の本番では一度も起きなかったが、段 2 では control-plane の `install kubelet` で apiserver のコンテナが止まる（§4.1）ので、段 C の control-plane の再起動と同じことが起こりうる。

```sh
kubectl --context fraction get pods -A -o json | jq -r '.items[] | .metadata.namespace as $ns | .metadata.name as $n | .spec.nodeName as $node
  | .status.containerStatuses[]? | select(.lastState.terminated.finishedAt > "<操作を始めた時刻（UTC）>")
  | [$ns+"/"+$n, $node, .name, .restartCount, .lastState.terminated.exitCode, .lastState.terminated.finishedAt] | @tsv'
```

- 段 2 では、対象のノードのコンテナは全部このコマンドに出る（§8.4）。**対象のノードの外のもの**を拾って記録する
- 同じ controller が 2 回以上再起動している、Running に戻らない、のどちらかなら止める

### 8.9 porkadot の SSH（0.30.0 までの問題）

段 1 の .113 の `install kubelet` が、SSH の接続で 2 回止まった（`Net::SSH::HostKeyMismatch`。`results/stage-1/192.168.1.113.md` §3.1）。原因は 2 つで、どちらも **porkadot 0.30.0 まで**のもの。

- **SSHKit 1.25.0 の known_hosts の parser**（`SSHKit::Backend::Netssh::KnownHostsKeys`）は、hashed の行では最初に一致した 1 行の鍵だけを返し、ed25519 の行は捨てる。作業端末の `~/.ssh/known_hosts` で、あるノードの rsa の行が ecdsa の行より前にあると、サーバーが出す ECDSA の鍵と合わずに止まった。段 1 では、coordinator が .112・.113 の行を並べ替えた（控え `~/.ssh/known_hosts.bak-k8u-stage1-20261019`）
- **pi のサンドボックスの中では ssh-agent のソケットが塞がれ**、net-ssh は `~/.ssh/id_ed25519` を読もうとして `ed25519` の gem が無いので認証で落ちた。段 1 では、ノードに入る porkadot のコマンドをサンドボックスの外で流した

**0.31.0（porkadot#29）ではどちらも当たらない。**

- `SSHKit::Backend::Netssh` の known_hosts を net-ssh の `Net::SSH::KnownHosts` にした。同じファイルの一致する行をすべて返す
- `ed25519` と `bcrypt_pbkdf` を依存に足し、`default.yaml` の `connection.keys` を外した。ssh-agent が無くても `~/.ssh/id_ed25519` で入れる
- SSH の失敗は、ノード・原因・確かめ方を 1 つのメッセージにして rc 1 で出す（backtrace は出ない）。host key の食い違いなら `Compare ssh-keygen -F <host> with ssh-keyscan <host>`、認証の失敗なら ssh-agent の状態と試した鍵が出る

2026-10-19 に本番の 8 台で確かめたこと（§1.4。読み取り）: サンドボックスの中から 0.31.0 の SSHKit の設定で 8 台に入れる。並べ替えの前の known_hosts を読ませても .112・.113 に入れる。dev の記録では、`etcd backup`、`install kubernetes`、`install kubelet`（7 台）がサンドボックスの中で通った。

- 戻し（§7）で 0.30.0 を使うときは、上の 2 つがまた当たる。サンドボックスの外で流し、known_hosts の並べ替えは戻さない
- 0.31.0 でも `FAIL` が出たら、メッセージを読んで止める。別の書き方で回避しない

### 8.10 kubelet の serving の証明書と CSR（計画 §7 の段 2 の行）

K8s 1.31 では、kubelet の serving の証明書の CSR を、apiserver（Node の admission）が CN とノード名の一致で検査する（計画 §7）。本番の kubelet-serving-cert-approver は `install kubernetes` で `0.12.1` に入れ替わる（§3.3 の 13）。

- **段 2 の間は、kubelet の serving の CSR は出ない見込み。** kubelet の更新では既存の serving の証明書がそのまま使われる（dev の記録）。段 1 でも出なかった
- 2026-10-19 の 8 台の serving の証明書は、どれも subject の CN が `system:node:<ノード名>`（`192.168.1.111`〜`113`、`braque`、`chirico`、`duchamp`、`oeilvert`、`pablo`）で、Node の名前と一致する（porkadot は kubelet に `--hostname-override=<ノード名>` を渡す）。issuer は `kube-ca`。期限は 2027-03-20（oeilvert）〜2027-10-16（control-plane）
- dev では、証明書をノードの中で退避して kubelet を再起動し、出させた CSR が approver 0.12.1 で 1 秒以内に Approved,Issued になった。本番では証明書を消して試すことはしない（runbook から外れる）
- 次に本番で CSR が出るのは、kubelet が証明書を更新するとき（期限の 7〜9 割を過ぎたころ。いちばん早いのは oeilvert）。そのとき `kubectl --context fraction get csr` で Approved,Issued になることを見る。段 2 の後の様子見の項目として `results/stage-2/summary.md` に残す
- 段 2 の間に CSR が出て Pending のまま残ったら、止めて報告する（`kubectl logs` / `exec` がそのノードで使えなくなる）

### 8.11 Longhorn の `no Pending workload pods`（longhorn/longhorn#8072 の形）

段 1 の手順書 §8.11 のもの。kubelet の再起動の後、動き続けている Pod のボリュームの `NodePublishVolume` を Longhorn の CSI が断り続けた（同じ PVC の Completed の Pod があるとき）。

段 2 では当たらない見込み。

- drain する 4 台では、Longhorn のボリュームを使う Pod は `install kubelet` の前に退いている。退いた Pod はほかのノードで新しい Pod（Pending から始まる）として作り直されるので、Longhorn は mount を受け付ける
- drain しないノード（braque、control-plane）には Longhorn のボリュームがアタッチされない（longhorn-csi-plugin が載っていない。2026-10-19 の VolumeAttachment は chirico 15、duchamp 5、oeilvert 4、pablo 1 で、ほかのノードには無い）。§2.2 の 20 と各台の前に確かめる

  ```sh
  kubectl --context fraction get volumeattachments -o custom-columns=NODE:.spec.nodeName,A:.status.attached --no-headers | sort | uniq -c
  kubectl --context fraction -n longhorn-system get pods -o wide -l app=longhorn-csi-plugin
  ```

- dev では、drain せずに上げたノードで同じ形が出たが、Longhorn が remount のために Pod を消して 1 分ほどで自然に止まった（dev の記録の見つけたことの 4）

それでも、ある台の後に Longhorn のボリュームの `FailedMount`（`no Pending workload pods`）が 5 分を超えて続いたら、段 1 の手順書 §8.11 のとおり、同じ PVC の Completed / Succeeded の Pod（ノードを問わない）を洗い出し、承認を取って消す。

## 9. 記録

`results/stage-2/` に、ベースライン（`baseline.md`）、`install kubernetes`（`control-plane.md`）、各台（`<ノード>.md`。control-plane は `192.168.1.11N.md`）、全体のまとめ（`summary.md`）を残す。各台の雛形は `results/stage-2/template.md`。
時刻（UTC。control-plane のホストの JST の時刻は直して書く）、読み取りの結果、実行したコマンドと出力の要点、コンテナの再起動の数、drain と Longhorn の設定の時刻、監視の FAIL、leader election で再起動したもの、手順書との差を書く。監視のログ（`./stage-2-probe.log`）はタスクディレクトリの `notes/stage-2/` に置き、要点を記録に写す。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（同じ PR か、記録の PR で）。
