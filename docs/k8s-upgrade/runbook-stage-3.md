# 段 3 の手順書: K8s を 1.31.14 から 1.32.13 へ上げる（本番 `fraction`）

本番クラスタ `fraction` の Kubernetes を v1.31.14 から v1.32.13 へ上げる手順。porkadot を 0.31.0 から 0.32.0 に替える。etcd は据え置き、CoreDNS と CNI plugins を上げる。
計画は同じディレクトリの `plan.md`（以下「計画」）の §6（骨子）と §7 の段 3 の行、決まったことは §9 にある。前の段は `runbook-stage-2.md`（以下「段 2 の手順書」）で、この手順書はそれを下敷きにし、**段 2 から変わる点を中心に書く**。段 3 は段 1 と同じく drain しないので、1 台の流れは `runbook-stage-1.md`（以下「段 1 の手順書」）に近い。

| | 更新前 | 更新後 |
|---|---|---|
| porkadot | 0.31.0 | **0.32.0**（`0fece0a`、タグ `v0.32.0`） |
| kube-apiserver、kube-controller-manager、kube-scheduler、kube-proxy | v1.31.14 | **v1.32.13** |
| kubelet、kubectl（ノードの `/opt/bin`） | v1.31.14 | **v1.32.13** |
| crictl（ノードの `/opt/bin`） | v1.31.1 | **v1.32.0** |
| CNI plugins（ノードの `/opt/cni/bin`） | v1.4.1（3 台の bridge・host-local・portmap は cnidaria が置いた v1.9.1。§8.11） | **v1.9.1** |
| CoreDNS | v1.11.3 | **v1.11.4** |
| `install-pkgs.sh`（`install kubelet` が流す） | 毎回 `systemctl restart iscsid.service`、`apt-get install` が入っているパッケージを上げうる | iscsid は `initiatorname.iscsi` が変わったときだけ再起動、`apt-get install --no-upgrade` |
| etcd（control-plane の static Pod）、etcdctl | 3.5.34 | 変えない |
| kubelet-serving-cert-approver | `0.12.1` | 変えない |
| containerd、runc | 段 C の 2.3.6、1.5.1 | 変えない |
| cnidaria、MetalLB | v0.1.1、v0.14.5 | 変えない（マニフェストの差分が無い） |
| kubelet の `config.yaml`・`kubelet.service` | — | 変えない |
| Longhorn | v1.11.2 | 変えない（要件は K8s 1.25 以上。計画 §4） |

porkadot 0.32.0 に入った PR は次のとおり。

- porkadot#39: K8s v1.32.13、crictl v1.32.0
- porkadot#43: `install-pkgs.sh` が iscsid を再起動するのを、`/etc/iscsi/initiatorname.iscsi` の中身が変わったときだけにする（同じなら `systemctl start iscsid.service` だけ）。パッケージを `apt-get install -y --no-upgrade` で入れる（計画 §4.4）
- porkadot#38（Renovate）: CNI plugins の既定 v1.4.1 → v1.9.1
- Renovate の #34: CoreDNS の既定 v1.11.3 → v1.11.4。#37: cnidaria の既定 v0.1.1（本番は `addons.cnidaria.image_tag: v0.1.1` を書いているので効かない）
- #40（CI）、#35（`.ruby-version` 4.0.7）は render の結果を変えない

この手順は dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で先に通してある（2026-10-19）。記録は porkadot-dev の `docs/k8s-upgrade/verification-0.32-rc.md`（以下「dev の記録」。porkadot-dev#11）。dev で分かったことのうち、段 2 と違うものは次のとおり。

- **1.32 の kubelet に上げても、コンテナは再起動しなかった。** 7 台すべてで、`install kubelet` の前と、kubelet の起動の 20 秒後・60 秒後の Pod の名前・UID・restartCount が同じだった（`definition changed` のイベントも無い）。例外は control-plane の etcd の static Pod で、mirror Pod が作り直され（UID が変わる）、etcd のコンテナが新しい sandbox で 2 秒で起き直した（段 1・段 2 と同じ）
- **`install kubelet` で iscsid は再起動しなかった**（7 台とも iscsid の PID が同じ）。Longhorn のボリュームをアタッチしたまま `install kubelet` した台（drain しない .122・.121）でも、エンジンのプロセスとセッションはそのままで、I/O エラー・faulted は無く、その後の drain・detach でも古いセッションは残らなかった
- `initiatorname.iscsi` を違うものにした台では、iscsid が再起動してファイルが porkadot の IQN に戻った（本番の 8 台は今のファイルが render の結果と同じ。§2.7）
- `install kubernetes --node <CP>` の 1 回目は rc 1 だった。apiserver の DaemonSet の rollout が同じノードの apiserver を先に入れ替え、apply の残り（MetalLB の `L2Advertisement` と `ValidatingWebhookConfiguration`）が `127.0.0.1:6443` で `connection refused` になった。rollout の完了を待って流し直すと rc 0 になり、2 回目の rollout は起きなかった（§3.2、§8.3）
- CNI plugins: cnidaria のクラスタでは、bridge・host-local・portmap は cnidaria の init container が置いた v1.9.1 を同じ v1.9.1 で上書きするだけで、実際に版が変わる使用中のプラグインは `loopback` だけだった。新しい Pod の ADD/DEL、hostPort（iptables の portmap）が通った
- CoreDNS v1.11.4 は 2 つとも Ready で、Pod から名前が引けた
- control-plane の `install kubelet` で、段 2 のような apiserver の 30 秒の ready の喪失は無かった（コンテナが再起動しないため）
- dev では、porkadot の操作の間に etcd のディスクの書き込みが 1〜6 秒止まり（`slow fdatasync`）、VIP が数秒〜15 秒応答しないことがあった。7 台の VM が同じホストのディスクを使うためと見ている（確かめていない）。0.31 の rc の dev でも本番の段 2 でも起きていない（§8.13）
- CSR は 1 つも出なかった。porkadot のコマンドとノードへの `ssh` は、すべて pi のサンドボックスの中で流した

これを受けて、**本番の段 3 では、どのノードも drain しない**（§2.7）。段 2 で worker 4 台を drain したのは、1.31 の kubelet が全コンテナを 1 回再起動させ、instance-manager の再起動で Longhorn のエンジンが落ちるためだった（段 2 の手順書 §8.4）。1.32 の kubelet ではその再起動が起きず、0.32.0 の `install kubelet` は iscsid も再起動しないので、drain する理由が無い。**ただし、本番で最初の worker の後にコンテナの再起動が出たら止める**（§2.1 の 3、§5.3 の 7）。

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **arm64 の control-plane での 1.32 の kubelet**。dev の段 3 は amd64 の VM で通した。arm64 のイメージとバイナリが配布されていることは確かめてある（§1.7）
- **本番の Longhorn のボリュームがアタッチされたままの `install kubelet`**（chirico 10 本、oeilvert 5 本、pablo 1 本。2026-10-19）。dev はアタッチしたまま流したのが 3 本だけ
- **iscsid が動いていないノード**（duchamp。ソケット起動で、ボリュームが無いので起動していない）。0.32.0 の `install-pkgs.sh` の `systemctl start iscsid.service` で iscsid が起動する見込み（§8.10）
- **storage version の書き直し**（§2.5）。dev では流していない

## 0. 役割と約束ごと

- **承認の節目は 1 つだけ**（計画 §9.1「本番の各段の開始（render の差分を見せてから `install kubernetes` を流す前）」）。この手順書では ✋✋ を付けた。
  - ✋✋ **段 3 の開始**: render の差分（§2.6。この手順書と同じ PR）、drain しないこと（§2.7）、storage version の書き直し（§2.5）を見せ、PR をマージしてから、§2.5 の書き直しと `install kubernetes` を流す前（§3.1）
- 段 3 は etcd を変えないので、control-plane の kubelet の前の節目は無い。
- **節目の間の手順は、ユーザーに知らせるだけで進めてよい。** §2.5 の storage version の書き直し（中身を変えない replace）、etcd のリーダーの移動、`install kubelet` も、この手順書に書いた形なら ✋（知らせてから行う操作）で、1 つずつ承認を取るものではない。
- **runbook から外れる操作（ロールバック、drain への切り替え、想定外の対処、Pod の削除、iSCSI のセッションの logout）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認（`kubectl --context fraction get`、SSH での状態確認、§1.8 のスクリプト）は、知らせずに行ってよい。
- **1 台ずつ行う。** 1 台を終えて「次の 1 台へ進む条件」（§4.3、§5.5）を満たすまで、次のノードに手を付けない。
- 時刻はすべて UTC で記録する。worker のホストの時刻は UTC だが、**control-plane（192.168.1.111〜113）のホストの時刻は Asia/Tokyo（JST）** である。control-plane の `journalctl` や `systemctl show` の時刻は 9 時間ずらして読む。

## 1. 前提

### 1.1 段 2 が終わっていること

始める前に次を確かめる。

- 段 2 の完了の確認（段 2 の手順書 §6）が `results/stage-2/summary.md` に残っている
- 8 台すべてが v1.31.14、CONTAINER-RUNTIME が `containerd://2.3.6`、etcd が 3.5.34

2026-10-19 13:00Z ごろの読み取りでは、8 台 Ready、全台 v1.31.14、`containerd://2.3.6`、etcd 3/3 が 3.5.34（リーダーは .113 の `57ec6f12ac7b683e`）、Running / Completed 以外の Pod は 0 個だった。

**段 2 の後に本番で変わったこと**（2026-10-19 12:0xZ ごろ、ユーザーが不要なアプリを消した）。段 2 の手順書の表と数が違うので、当日のベースライン（§2.2）で読み直す。

- MinIO・open-webui・hedgedoc の名前空間は無い。`minio/minio` の StatefulSet を止める手順、`hedgedoc/db-postgresql` の NetworkPolicy の確認は、段 3 には無い
- Longhorn のボリュームは 17（attached healthy 16、detached 1 の `homegallery/cg-data`）。前の detached の `myao/myao` も無くなった。replica は 34
- **NetworkPolicy は 1 つも無い**。確かめるときは一時的な名前空間に作る（§1.9）
- PV は 31 で、すべて Bound（Released の PV は無い）

### 1.2 kubeconfig の運用

確認は `kubectl --context fraction`（`fraction-auditor`、read-only）で行う。作業を始める前に `kubectl --context fraction auth can-i delete pods -A` が `no` であることを確かめる。

**段 3 で `infra-admin` の短命トークンを使うのは、§2.5 の storage version の書き直しだけ**（drain しないので、cordon・drain・Longhorn の設定の切り替えは無い）。発行と破棄は段 C の手順書 §1.1 と同じ。

```sh
umask 077
kubectl --context fraction create token infra-admin -n kube-system --duration=1h > /tmp/k8u-stage3-admin-token
ADMIN_TOKEN=$(cat /tmp/k8u-stage3-admin-token)
kubectl --context fraction --token="$ADMIN_TOKEN" auth can-i update flowschemas.flowcontrol.apiserver.k8s.io   # yes
kubectl --context fraction --token="$ADMIN_TOKEN" auth can-i update endpointslices.discovery.k8s.io -A         # yes
```

- `infra-admin` は `cluster-admin` に bind されている（2026-10-19 の読み取り）
- 以下、変更系のコマンドを `kubectl-admin` と書く（`kubectl --context fraction --token="$ADMIN_TOKEN"` のこと）。§2.5 はパイプと `while` の中で使うので、関数にしておく: `kubectl-admin() { kubectl --context fraction --token="$ADMIN_TOKEN" "$@"; }`
- §2.5 の後で破棄する（`unset ADMIN_TOKEN` とファイルの削除）。サーバーの側では期限で切れる
- runbook から外れる操作（§8.10 の drain への切り替え、§8.12 の Pod の削除など）でトークンが要るときは、その承認を取ってから発行し直す

### 1.3 SSH

段 2 の手順書 §1.3 と同じ。

| ノード | 入り方 |
|---|---|
| worker（braque、chirico、duchamp、oeilvert、pablo） | `ssh yuanying@<IP>` |
| control-plane（192.168.1.111〜113、rasp01〜03） | `ssh ubuntu@<IP>` |

ノードへの `ssh` はサンドボックスの中で通る（2026-10-19 に 8 台で確かめた）。control-plane には en_US.UTF-8 のロケールが無いので、`unset LC_ALL` してから SSH する。

### 1.4 porkadot の流し方

porkadot 0.32.0 の checkout（`porkadot-dev/porkadot` の `v0.32.0`、`0fece0a`）を使い、**このリポジトリのルートを cwd にして** 流す。形は段 2 の手順書 §1.4 と同じ。

```sh
P=/home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot
git -C $P describe --tags          # v0.32.0（lib/porkadot/version.rb も 0.32.0）
cd <このリポジトリの checkout>     # §2.6 の PR をマージした master
BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

以下、この形を `porkadot <サブコマンド>` と書く。

- cwd はこのリポジトリのルートにする（段 1 の手順書 §8.7）。`--config` はサブコマンドの後ろに置く
- 0.32.0 は Ruby 4.0.7（`.ruby-version`）。clone の `bundle install` は 2026-10-19 に済んでいる（`Gemfile.lock` は porkadot 0.32.0）。始める前に `BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot help` が動くことを確かめる
- secrets は `assets/` の中に sops（age）で暗号化してある（§1.6）。作業端末に age の鍵（`~/.config/sops/age/keys.txt`）が要る
- 作業ツリーの `assets/` と `porkadot.yaml` に PR の外の変更が無いこと（`git status --short assets porkadot.yaml` が空）。メインの checkout にほかの作業があれば、master の別の worktree を作ってそこで流す
- 段 3 で流す porkadot のコマンドは、`etcd backup`、`install kubernetes --node 192.168.1.111`、`install kubelet --node <ノード>` の 3 つだけ。**`install all`、`--node` なしの `install kubelet` と `install kubernetes`、`render`（特に `render all` と `render certs`）、`setup-node`、`setup-containerd` は流さない**
- `install kubelet` は `/opt/bin/<名前>` の向き先と CNI の版の印で判定して張り替える（porkadot#26）。`--force` は要らない
- **ノードに入る porkadot のコマンドもサンドボックスの中で流す**（段 2 と同じ。0.32.0 の SSH は 0.31.0 と同じ）。当日の流す前の確かめ方は段 2 の手順書 §1.4 のスクリプト（`P` を 0.32.0 の checkout にする）。8 台とも hostname を返すこと。`FAIL` が出たら、メッセージを読んで止める

### 1.5 etcdctl の使い方

段 2 の手順書 §1.5 と同じ（sudo で流す。`move-leader` は `unset ETCDCTL_ENDPOINTS` してから `--endpoints` を渡す）。以下、この形を `etcdctl ...` と書く。

### 1.6 render に使った secrets と、本番との突き合わせ

secrets の在りかと扱いは段 1 の手順書 §1.6 と同じ（`assets/` の中に sops の binary 形式で暗号化してある。`assets/secrets.tar.asc` を展開しない。平文をディスクに書かない）。
段 3 の render（§2.6）の前に、同じ形で本番と突き合わせ直した（2026-10-19 13:10Z ごろ。読み取りだけ。復号をパイプで流してハッシュだけを比べた）。

| 比べたもの | 本番の側 | 結果 |
|---|---|---|
| `assets/certs/kubernetes/ca.crt` | ConfigMap `default/kube-root-ca.crt` | 一致（SHA-256 `AB:5A:49:9E:…:A0:3E`。段 1・段 2 と同じ） |
| `assets/certs/kubernetes/apiserver.crt` | VIP と 192.168.1.111〜113 の 6443 が返す証明書 | 4 つとも一致（`4A:E8:7B:B3:…:97:63`） |
| `assets/certs/kubernetes/` の 10 ファイル（`ca.crt`、`apiserver.{crt,key}`、`front-proxy-ca.crt`、`front-proxy-client.{crt,key}`、`kubelet-client.{crt,key}`、`sa.{key,pub}`） | .111 の kube-apiserver の Pod（`kube-apiserver-v7wdz`）にマウントされた Secret `kube-apiserver` | 10 ファイルとも sha256 が一致 |
| `assets/certs/etcd/{ca.crt,etcd-client.crt,etcd-client.key}` | 同じく Secret `etcd-tls` | 3 ファイルとも一致 |
| `assets/kubelet/192.168.1.11{1,2,3}/addons/etcd/{ca.crt,etcd.crt,etcd.key}`（render の前） | 3 台の `/etc/etcd/pki/` | 9 ファイルとも一致（`etcd.crt` は段 2 の render のもの） |
| CA の鍵と証明書（kubernetes、front-proxy、etcd） | — | 3 組とも公開鍵が一致 |

当日に確かめ直すときの形は段 1 の手順書 §1.6 と同じ。どれかが食い違えば、render の差分も assets も信用せず、止めて調べる。

### 1.7 入れる版を確かめる

作業の当日に確かめ直す（読み取り）。

```sh
curl -fsSL https://dl.k8s.io/release/stable-1.32.txt     # v1.32.13
```

2026-10-19 の時点:

- `stable-1.32.txt` は v1.32.13（1.32 は EOL なので、これより新しいパッチは出ない見込み）。`stable.txt` は v1.37.1
- registry.k8s.io の `kube-apiserver`・`kube-controller-manager`・`kube-scheduler`・`kube-proxy` の v1.32.13 は、どれも amd64 と arm64 を含む（manifest list を読んだ）。`coredns/coredns:v1.11.4` も amd64 と arm64 を含む
- `dl.k8s.io` の kubelet と kubectl の v1.32.13（amd64、arm64）、cri-tools の `crictl-v1.32.0-linux-{amd64,arm64}.tar.gz`、CNI plugins の `cni-plugins-linux-{amd64,arm64}-v1.9.1.tgz` は、どれも 200 を返す。cri-tools の 1.32 系は v1.32.0 だけ
- etcd 3.5.34 は段 1 で入れたもので、変わらない
- 作業端末の kubectl は v1.31.14（段 2 の間に替わった）。1.32 の ±1 に入る（計画 §6.1 の 4）。dev でも v1.31.14 で問題なく使えた

### 1.8 確認に使うスクリプト

- cnidaria の手順書のスクリプト（`verify-nodes.sh`、`netcheck.sh`、`check-apps.sh`）: 段 C の手順書 §1.4 と同じ。`netcheck.sh` は一時的な DaemonSet を作るので ✋
  - **`netcheck.sh` は NetworkPolicy を作らない。** 確かめるのは、Pod 間（v4 / v6、ノード間）、Service（v4 / v6、名前）、外への ping だけである（`netcheck.sh`・`netcheck.yaml` を読んだ）。本番に NetworkPolicy が 1 つも無いので、NetworkPolicy は §1.9 の一時的な名前空間で確かめる
- `tools/node-state.sh`（この PR で足した。読み取り）: 1 台の `/opt/bin` の向き先、CNI の版の印と 4 つのプラグインの `--version`、iscsid の PID と起動の時刻、iSCSI のセッション（sid、portal、target）、Longhorn のエンジンの起動の時刻（iscsid より前に起動したものには `older-than-iscsid`）、`initiatorname.iscsi` の md5 を出す

  ```sh
  ssh <user>@<IP> 'sudo bash -s' < docs/k8s-upgrade/tools/node-state.sh > node-<ノード>-before.txt
  ```

- `tools/storage-versions.sh`（この PR で足した。読み取り）: etcd に古い版で保存されたオブジェクトを洗い出す（`storage-versions.md` §4）

### 1.9 NetworkPolicy の確認（一時的な名前空間） ✋

本番には NetworkPolicy が 1 つも無い（2026-10-19。hedgedoc が消えた）ので、段 1・段 2 の「`hedgedoc/db-postgresql` の規則がノードの nftables に入っている」の確認が使えない。代わりに、一時的な名前空間 `k8u-npcheck` に NetworkPolicy と Pod を作り、cnidaria が規則を入れて、許した通信が通り、許していない通信が止まり、消すと規則も消えることを確かめる。`netcheck.sh` の一時的な DaemonSet と同じ扱い（✋。作って消すまでを 1 回の操作として知らせる）。

- マニフェスト `tools/npcheck.yaml`: 名前空間 `k8u-npcheck`、全ノードに 1 つずつの DaemonSet 3 つ（`npcheck-server`: busybox の httpd を 8080 と 9090 で、`npcheck-allowed`: `role: allowed` のクライアント、`npcheck-denied`: `role: denied` のクライアント。どれも全 taint を許す）、NetworkPolicy `allow-8080`（`app: npcheck-server` への Ingress を、`role: allowed` の Pod から TCP 8080 だけ許す）。イメージは `netcheck.yaml` と同じ `busybox:1.36`
- スクリプト `tools/npcheck.sh`: `dry-run`（`kubectl apply --dry-run=client`。読み取り）、`up`・`down`（作る・消す。✋）、`run`（`kubectl exec` で確かめる）、`nft`（各ノードに SSH して `sudo nft list table inet cnidaria` の `k8u-npcheck/allow-8080` の行を数える。読み取り）。`up`・`run`・`down` は `ADMIN_TOKEN`（§1.2）が要る
- `run` が見るもの（**ノードをまたぐ形**。各ノードのクライアントから、ノード名の順で次のノードのサーバーへ、v4 と v6 の両方）:

  | 向き | 合格 |
  |---|---|
  | `allowed` のクライアント → サーバーの 8080 | 通る（PASS） |
  | `allowed` のクライアント → サーバーの 9090 | 止まる（BLOCK。ポートが許されていない） |
  | `denied` のクライアント → サーバーの 8080 | 止まる（BLOCK。相手が許されていない） |
  | 各サーバー → 自分の 9090（127.0.0.1） | 通る（9090 が listen していて、BLOCK がポリシーによるものだと分かる） |

  8 ノードで 8 + 8 × 6 = 56 の確かめ。止まるものは `wget -T 3` の時間切れを待つので、数分かかる

流し方（✋。`ADMIN_TOKEN` を発行してから）:

```sh
export ADMIN_TOKEN
T=docs/k8s-upgrade/tools/npcheck.sh
$T nft     # 8 台とも 0（前に残っていない）
$T up      # 3 つの DaemonSet が 8/8 Ready になるまで待つ（最大 3 分）
$T nft     # 8 台とも 1 以上（cnidaria が規則を入れた。サーバーの Pod が載るノードに入る）
$T run     # 最後の行が「OK 56, not OK 0」、rc 0
$T down    # 名前空間を消す
$T nft     # 8 台とも 0（規則が消えた）
kubectl --context fraction get ns k8u-npcheck   # NotFound
```

- 合格: `up` の後の `nft` が 8 台とも 1 以上、`run` が `not OK 0`、`down` の後の `nft` が 8 台とも 0、名前空間が消えた
- `up` の直後は cnidaria が規則を入れるまで少しかかることがある。`nft` が 0 のノードがあれば、数秒おいて読み直してから `run` を流す
- 合格しなければ、`down` で消してから止めて報告する（`run` の全出力は `/tmp/npcheck-<時刻>.txt`）。消せないときも止める
- **2026-10-19 は `dry-run` だけを `fraction-auditor` で流した**（5 つとも `created (dry run)`）。`nft` も読み取りで流し、8 台とも 0 だった。`up`・`run`・`down` は本番で流していない。`run` の判定（PASS / BLOCK と期待の比べ）は作業端末で確かめた
- 流すのは、最初の worker の後（§5.5）と、段 3 の完了の確認（§6）

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 順序 | §2.5 の storage version の書き直し → `install kubernetes --node 192.168.1.111` → rollout の完了 → control-plane の `install kubelet --node` を 1 台ずつ（.113 → .112 → .111）→ worker を 1 台ずつ（§5.1） | 計画 §6.2 |
| 2 | etcd のリーダー | `install kubelet` の前に、対象がリーダーなら `move-leader` で別のメンバーへ移す（etcd の static Pod は作り直され、コンテナが 2 秒ほど止まる） | 計画 §6.2、dev の記録 |
| 3 | drain | **どのノードも drain しない**（§2.7）。**ただし、どの台の後でも、Pod のコンテナの再起動（restartCount の増加、UID の変化。control-plane の etcd の mirror Pod を除く）が 1 つでも出たら止める。** 特に最初の worker（duchamp）と、Longhorn のボリュームがアタッチされた最初の worker（pablo）の後に見る。止めた後、残りの Longhorn のノードを drain に切り替えるかはユーザーが決める（§8.10） | dev の記録、2026-10-19 のユーザーの方針（下の 4） |
| 4 | drain の基準 | 「短時間の途切れ」より「Longhorn のボリュームの安全（データ、degraded のまま戻らないこと）」を重く見る。短時間の障害は許容する | 2026-10-19 のユーザーの方針 |
| 5 | iSCSI | 各台の `install kubelet` の前と後に `tools/node-state.sh` で iscsid の PID と iSCSI のセッションを見る。iscsid が動いていた台で PID が変わったら止める。古いセッション（今の instance-manager の IP でない portal へのもの）があれば止める（§2.7、§5.3） | 計画 §4.4、dev の記録 |
| 6 | ノードの再起動 | しない（段 2 の drain した台の再起動は段 2 だけのもの。段 2 の手順書 §8.12 の末尾） | 計画 §9.3 |
| 7 | コンテナの再起動 | 1.32 の kubelet では起きないことを前提にする（§8.4）。control-plane の etcd の static Pod だけは作り直される | dev の記録 |
| 8 | Longhorn の設定 | 変えない（drain しないので、`concurrent-replica-rebuild-per-node-limit`、`node-drain-policy` の切り替えも、Prometheus を止めることも無い）。`replica-auto-balance` は普段から `disabled` | 段 1 の手順書 §2.6 |
| 9 | storage version | `install kubernetes` の前に、古い版で保存された組み込みのオブジェクトを、中身を変えずに書き直す（§2.5）。段 3 の完了の確認で、古い版のオブジェクトが 0 で、CRD の `storedVersions` が 1 つであることを見る（§6） | 2026-10-19 のユーザー指示 |
| 10 | leader election を使う controller の 1 回の再起動と、gated の LoadBalancer の 1 回の途切れ | 許容する。記録して、Running に戻ったことを確かめる（§8.8） | 段 C、ユーザーの判断 |
| 11 | 停止時間 | いつでもよい。braque は念のためバックアップの CronJob の時間帯を避ける（§5.4） | 計画 §9.6 |
| 12 | 段 3 の後 | 健全性を確かめてから段 4 へ（間隔は必須ではない） | 計画 §9.6 |

### 2.2 クラスタ全体のベースライン

作業の当日、`install kubernetes` の前に次を取り、`results/stage-3/baseline.md` に残す（すべて読み取り）。段 2 の手順書 §2.2 と同じもので、次を読み替える・足す。

- 1: 全台 v1.31.14
- 2: 8 台の `tools/node-state.sh` の出力（ファイルに残す）。`/opt/bin` の向き先が `kubelet-v1.31.14`、`kubectl-v1.31.14`、`crictl-v1.31.1`、`etcdctl-3.5.34`。CNI の印は `v1.4.1`
- 4: etcd は 3.5.34
- 5: **全 Pod の名前・UID・restartCount を控える**（段 2 の手順書 §2.2 の 5 のコマンド。段 3 ではコンテナが再起動しない見込みなので、§6 で「増えていない」ことを見る元になる）
- 12: CSR と、8 台の kubelet の serving の証明書の subject と期限（段 2 の手順書 §2.2 の 12）
- 14: Longhorn の設定。2026-10-19 は `concurrent-replica-rebuild-per-node-limit` `5`、`replica-auto-balance` `disabled`、`node-drain-policy` `block-if-contains-last-replica`、`default-data-locality` `best-effort`、`replica-replenishment-wait-interval` `6000`、`current-longhorn-version` v1.11.2
- 18: Longhorn のボリュームの state・robustness・アタッチ先、replica の置き場所（§2.7 の表を当日に読み直す）
- 20（新）: **storage version**: `tools/storage-versions.sh` の結果（§2.5 の書き直しの前）。2026-10-19 は `OLD: 32`、`CRDs with more than one stored version: 0`
- 21（新）: Prometheus の `apiserver_requested_deprecated_apis`（段 2 の後は `metallb.io/v1beta1 addresspools` だけ。`flowcontrol.apiserver.k8s.io/v1beta3` を使うクライアントが無いこと）
- 22（新）: Longhorn のボリュームを使う Pod と、同じ PVC を使う Completed / Succeeded の Pod（§8.12 のコマンド。2026-10-19 は無い）

### 2.3 VIP と LoadBalancer を 1 秒ごとに見る

段 1 の手順書 §2.3 と同じ監視を、§2.5 の書き直しの前から最後の worker の確認まで、作業端末で流しておく（読み取り）。ログは `./stage-3-probe.log` に足していく（`tee -a`）。

- 段 3 では speaker のコンテナが再起動しない見込みなので、告知ノードの `install kubelet` で VIP が途切れることは無い見込み（dev では、etcd のディスクの止まりのほかは途切れなかった）
- 失敗は、`install kubernetes` の apiserver の rollout の間と、control-plane の etcd の起き直しの直後（dev の .112 で VIP が 1 回）にありうる。記録したうえで許容する

### 2.4 etcd のバックアップ ✋

`install kubernetes` の前に、porkadot 0.32.0 で取る（計画 §6.1 の 5）。§2.5 の書き直しより前に取る。

```sh
porkadot etcd backup
ls -l ./backup/
```

- 0.32.0 の `etcd backup` は 0.31.0 と同じ（最初の etcd のメンバー 192.168.1.111 で root として `etcdctl snapshot save` を流し、0600 で手元に写し、ノードのものを消す）。dev ではサンドボックスの中で通った
- 手元のファイルは `./backup/etcd-<日時>.db`、モード 0600。`./backup/` は `.gitignore` で除外してある。スナップショットには Secret が平文で入っているので、`git add -f` などで追加しない
- **worktree で流したときは、`./backup/` は worktree の中にできる。** worktree を片付ける前に、coordinator がメインの checkout の `backup/` へ移す（段 1・段 2 と同じ）
- 時刻、ファイル名、サイズ、sha256 を記録する。段 2 のバックアップ（`etcd-2026-10-19T07:16:21+00:00.db`）は 55,107,616 バイトだった。アプリを消した後も etcd の DB SIZE は 55 MB（2026-10-19 13:1xZ、compact・defrag の前なので減らない）。桁が違えば止める
- 段 3 が終わるまで消さない

### 2.5 storage version の書き直し ✋

古い版で保存された組み込みのオブジェクトを、中身を変えずに読んで書き戻し、今の storage の版で保存し直させる。調べ方と、なぜ書き直すかは `storage-versions.md` にある。**§3.1 の段の開始の承認の後、`install kubernetes` の前に流す。**

2026-10-19 の洗い出し（`storage-versions.md` §2.1）では 32 個。当日に `tools/storage-versions.sh` で洗い出し直し、`old.tsv` にあるものを対象にする。

| 対象 | 保存された版 → 書き直した後の版 | 数（2026-10-19） |
|---|---|---|
| FlowSchema（全部） | `flowcontrol.apiserver.k8s.io/v1beta3` → `v1` | 13 |
| PriorityLevelConfiguration（全部） | `flowcontrol.apiserver.k8s.io/v1beta3` → `v1` | 8 |
| EndpointSlice | `discovery.k8s.io/v1beta1` → `v1` | 11 |

1. 読み取りで洗い出し直す。

   ```sh
   SV=/tmp/storage-versions-$(date -u +%Y%m%dT%H%MZ)
   docs/k8s-upgrade/tools/storage-versions.sh $SV
   cut -f1,2 $SV/old.tsv
   ```

   - `old.tsv` に上の 3 種のほかのものが出たら、止めて調べる（何を、なぜ書き直すかを決め直す）
   - `crds.tsv` に `MULTI` が出たら、止めて調べる（§8.14）
2. ✋ `infra-admin` のトークンを発行する（§1.2）。
3. ✋ FlowSchema と PriorityLevelConfiguration を書き直す。

   ```sh
   kubectl --context fraction get flowschemas,prioritylevelconfigurations \
     -o custom-columns=KIND:.kind,N:.metadata.name,GEN:.metadata.generation,RV:.metadata.resourceVersion,AUTO:'.metadata.annotations.apf\.kubernetes\.io/autoupdate-spec' > $SV/apf-before.txt
   kubectl-admin get flowschemas,prioritylevelconfigurations -o json | kubectl-admin replace --dry-run=server -f -   # 21 行の replaced (server dry run)
   kubectl-admin get flowschemas,prioritylevelconfigurations -o json | kubectl-admin replace -f -
   ```

   - `--dry-run=client` の形は 2026-10-19 に `fraction-auditor` で流し、FlowSchema 13・PriorityLevelConfiguration 8 の 21 個と EndpointSlice が `replaced (dry run)` になることを確かめた（`--dry-run=server` は `fraction-auditor` では Forbidden）

   - 21 行の `replaced` が出る。`the object has been modified`（resourceVersion の衝突。kube-apiserver の毎分の保守と重なったとき）が出たものは、その名前だけ同じ形で流し直す
   - **kube-apiserver が管理しているものだが、replace してよい。** K8s の文書（API Priority and Fairness の「Maintenance of the Mandatory and Suggested Configuration Objects」）: kube-apiserver は mandatory の 2 つ（`exempt`、`catch-all`）について「the object exists and, if it does, has the proper spec」を保ち、「refuses to allow a creation or update with a spec that is inconsistent with the server's guardrail behavior」。suggested のもの（ほかの 19）は、`apf.kubernetes.io/autoupdate-spec: "true"` なら kube-apiserver が spec を自分の値に保つ。中身を変えない replace は spec を変えないので、どちらの規則にも当たらず、`autoupdate-spec` も `"true"` のまま、`metadata.generation` も変わらない（spec が変わったときだけ増える）。21 個とも `autoupdate-spec` は `"true"`（2026-10-19）
4. ✋ EndpointSlice を書き直す（1 の `old.tsv` の名前を使う。2026-10-19 は次の 11 個）。

   ```sh
   grep '^/registry/endpointslices/' $SV/old.tsv | cut -f1 | awk -F/ '{print $4, $5}' |
   while read -r ns name; do
     kubectl-admin -n "$ns" get endpointslice "$name" -o json | kubectl-admin replace -f -
   done
   ```

   流す前に、`replace -f -` を `replace --dry-run=server -f -` にした形で 1 回流して、11 行の `replaced (server dry run)` を見てもよい。

   `default/nginx-1-xhkzq`、`homegallery/cg-w8dmk`、`kube-system/kube-prometheus-kubelet-96ktq`、`kube-system/tiller-deploy-jgh7c`、`longhorn-system/longhorn-conversion-webhook-5nz8j`、`longhorn-system/pvc-c9f006ad-fe37-48c0-9a4a-c3f7831fbd46-5smvq`、`minecraft/bds-mc4cm`、`minecraft/bds-v4-gz7rk`、`minecraft2/bds-m99wf`、`minecraft3/bds-5ttnf`、`nfsd/nfs-ntht8`

   - どれも EndpointSlice の controller（`kube-prometheus-kubelet` は mirroring の controller）が管理するもの。中身を変えないので、controller が書き直し返すことは無い。resourceVersion の衝突が出たものは流し直す
   - `nfsd/nfs` の EndpointSlice は braque の NFS の Service のもの。中身（endpoint 1 つ）は変わらないので、NFS は途切れない
5. 書き直した後を確かめる（読み取り）。

   ```sh
   docs/k8s-upgrade/tools/storage-versions.sh $SV-after
   # ... OLD: 0, CRDs with more than one stored version: 0
   kubectl --context fraction get flowschemas,prioritylevelconfigurations \
     -o custom-columns=KIND:.kind,N:.metadata.name,GEN:.metadata.generation,RV:.metadata.resourceVersion,AUTO:'.metadata.annotations.apf\.kubernetes\.io/autoupdate-spec' > $SV/apf-after.txt
   diff $SV/apf-before.txt $SV/apf-after.txt     # RV だけが変わる
   ```

   - `OLD: 0` になったこと。FlowSchema・PriorityLevelConfiguration の generation と `autoupdate-spec` が変わっていないこと
   - VIP の `/readyz` が `ok`。§2.3 の監視に失敗が出ていないこと
   - 書き直しで本番の振る舞いは変わらない見込み（中身が同じ）。何かが変わったら止める
6. トークンを破棄する（`unset ADMIN_TOKEN`、ファイルの削除）。
7. 時刻、`OLD` の数の前と後、衝突で流し直したものを `results/stage-3/baseline.md` に記録する（値は書かない。prefix・キー・版だけ）。

**kube-storage-version-migrator や StorageVersionMigration を使わない理由**は `storage-versions.md` §5（対象が 32 個で手で足りる。StorageVersionMigration は 1.31〜1.36 では既定で無効で、使うには feature gate と `--runtime-config` を porkadot で変えることになる。kube-storage-version-migrator は本番に新しい Deployment と CRD と強い権限を足すことになる）。

- 書き直しは 1.32 に上げる前に行う。書き直した v1 は 1.31 の kube-apiserver の storage の版そのものなので、§7 で 1.31 に戻しても読める
- 古い版のまま 1.32 に上げても、1.32 の kube-apiserver は flowcontrol の v1beta3 と discovery の v1beta1 を scheme に残しているので読める（`storage-versions.md` §1）。§2.5 が途中で止まっても、`install kubernetes` を止める理由にはならない（止めて報告し、続けるかはユーザーが決める）

### 2.6 render の差分（この手順書と同じ PR）

計画 §6.1 の 6〜7。2026-10-19 13:12Z に、porkadot 0.32.0（`0fece0a`）で、このリポジトリのルートを cwd にして `render kubelet` / `render etcd` / `render bootstrap` / `render kubernetes` を流した（`render all` と `render certs` は使っていない）。secrets は §1.6 のとおり本番と一致していることを確かめてから使った。`porkadot.yaml` は変えていない。

前の render は段 2 の porkadot 0.31.0（`62d8821`）のもので、master の `1761f1d` にある。差分は次のとおりで、**これ以外の差分は無い**（新しくできたファイル、消えたファイルも無い）。

| ファイル | 変わったもの | 由来 |
|---|---|---|
| `kubernetes/manifests/kube-apiserver.yaml`・`kube-controller-manager.yaml`・`kube-scheduler.yaml`・`kube-proxy.yaml` | イメージ v1.31.14 → v1.32.13、`app.kubernetes.io/version` のラベル | K8s の版（porkadot#39） |
| `kubernetes/manifests/kube-apiserver.secrets.yaml`・`kube-controller-manager.secrets.yaml`（sops） | Secret の `app.kubernetes.io/version` のラベルだけ。data は同じ（復号して、キーごとの sha256 を比べた） | 同上 |
| `kubernetes/manifests/porkadot.yaml` | Service `porkadot-kubernetes-latest` の selector の `app.kubernetes.io/version`（VIP の Service `porkadot-kubernetes` の selector には版が入っていない） | 同上 |
| `bootstrap/manifests/*.bootstrap.yaml`（4 つ） | イメージ v1.31.14 → v1.32.13、版のラベル | 同上（段 3 では使わない） |
| `kubelet-default/install-deps.sh` | `RELEASE`（kubelet・kubectl）v1.31.14 → v1.32.13、`CRICTL_VER` v1.31.1 → v1.32.0、`CNI_VERSION` v1.4.1 → v1.9.1 | porkadot#39、#38 |
| `kubelet-default/install-pkgs.sh` | `apt-get install -y --no-upgrade`。`initiatorname.iscsi` を `cmp` で比べ、同じなら `systemctl start iscsid.service`、違うときだけ置き直して `systemctl restart iscsid.service`。`/etc` を `${PORKADOT_ETC_DIR:-/etc}`（テストのためのもの）にした | porkadot#43 |
| `kubernetes/manifests/addons/coredns/coredns.yaml` | イメージ `coredns:v1.11.3` → `v1.11.4` | Renovate の #34 |
| `kubelet/<8 台>/bootstrap.crt`、`bootstrap/kubelet/bootstrap.crt` | 作り直し（同じ鍵、同じ subject・issuer・SAN・用途、assets の CA で検証が通る。期限が 2027-10-19 13:12Z に延びる） | render のたびに作り直される（段 1 の手順書 §8.2） |
| `kubelet/192.168.1.11{1,2,3}/addons/etcd/etcd.crt`（sops） | 同上（同じ鍵、同じ etcd の CA、同じ SAN） | 同上 |

- `app.kubernetes.io/version` が変わったのは平文のマニフェストで 23 行（dev の記録と同じ数）
- 変わらないもの: `kubelet/<ノード>/config.yaml`・`kubelet.service`・`bootstrap-kubelet.conf`・`metadata.json`・**`initiatorname.iscsi`**、etcd の `etcd-server.yaml`（3.5.34-0）・`install.sh`・`etcd.env`、cnidaria（`image_tag: v0.1.1`。#37 の既定の変更は効かない）・MetalLB・kubelet-serving-cert-approver のマニフェスト、`kubelet-default/setup-containerd.sh`
- 1.32 で提供されなくなる `flowcontrol.apiserver.k8s.io/v1beta3` は、render の結果に無い
- Deployment と DaemonSet の `spec.selector` には `app.kubernetes.io/version` が入っていない（段 1・段 2 と同じ）
- 作り直した証明書は、作業の当日に render し直すとまた変わる。**当日は render しない**。この PR の `assets/` で流す

### 2.7 drain しない理由と、Longhorn・iSCSI の前提

**drain しない理由**（§2.1 の 3）:

- 段 2 で Longhorn のノードを drain したのは、1.31 の kubelet がそのノードの全コンテナ（instance-manager を含む）を 1 回再起動させ、drain しないとエンジンが落ちてボリュームが faulted になり、Pod に 1〜2 分 I/O エラーが出るためだった（段 2 の手順書 §8.4、dev の `verification-0.31-rc.md`）
- 1.32 の kubelet では、dev の 7 台でコンテナが 1 つも再起動しなかった（etcd の static Pod を除く。dev の記録の見つけたことの 1）。drain しない台でアタッチしたままのボリュームも、faulted・remount・I/O エラーにならなかった（同 4）
- 段 2 の後に分かった古い iSCSI のセッションの原因は、drain ではなく `install kubelet` の iscsid の再起動だった（計画 §4.4）。0.32.0 の `install kubelet` は、`initiatorname.iscsi` が同じなら iscsid を再起動しない。本番の 8 台の `/etc/iscsi/initiatorname.iscsi` は、この PR の `assets/kubelet/<ノード>/initiatorname.iscsi` と同じ（下の表。2026-10-19 に coordinator と、13:1xZ にこの手順書の作成のときに md5 で比べた）
- drain しないので、Longhorn の設定の切り替え、Prometheus を止めること、cordon・uncordon、replica の再同期の待ちも要らない。drain で別のノードへ移ったボリュームが古いセッションに当たること（段 2 の oeilvert の後の件）も起きない
- 短時間の途切れより Longhorn のボリュームの安全を重く見る方針（§2.1 の 4）でも、drain しないほうが動くものが少ない

**各ノードの iSCSI と Longhorn（2026-10-19 13:1xZ の読み取り。当日に `tools/node-state.sh` で読み直す）**:

| ノード | iscsid | Longhorn のセッション（portal） | iscsid より前に起動したエンジン | アタッチされたボリューム | `initiatorname.iscsi` |
|---|---|---|---|---|---|
| 192.168.1.111〜113 | 動いている（16:24〜16:31 JST = 07:24〜07:31Z、段 2 の `install kubelet`） | 0 | 0 | なし（Longhorn のノードではない） | assets と同じ |
| braque | 動いている（08:06:03Z） | 0 | 0 | なし | 同じ |
| pablo | 動いている（07:39:11Z、段 2 の `install kubelet`） | 1（10.244.4.131 = 今の instance-manager） | 0 | `fs/sites` | 同じ |
| duchamp | **動いていない**（`iscsid.socket` だけが listen。09:42Z の再起動の後、アタッチが無いので起動していない） | 0 | 0 | なし | 同じ |
| chirico | 動いている（09:17:30Z、再起動の後のソケット起動） | 10（すべて 10.244.8.216 = 今の instance-manager） | **1**（`prometheus-…-0` の pvc-625c8825、09:17:28Z。下の注） | 10 | 同じ |
| oeilvert | 動いている（09:04:34Z） | 5（すべて 10.244.7.116 = 今の instance-manager） | 0 | 5 | 同じ |

- **古いセッションは無い**（どのセッションも、そのノードの今の instance-manager の IP へのもの）
- **chirico の `older-than-iscsid` の 1 つは、iscsid がソケット起動された同じ秒（1〜2 秒前）に起動したエンジンで、害は無い見込み。** v1.11.2 のエンジンは、`nsenter` に使う iscsid の PID を、iscsid のプロセスを探して決める（go-common-libs の `proc.GetProcessNamespaceDirectory`。見つからなければ executor を作れない）。このエンジンは 09:17:30Z に iSCSI に login できているので、動いている iscsid（09:17:29Z 起動、PID 4446・4447。その後再起動していない）の PID を持っている。iscsid が再起動しない限り、detach のときに logout できる。当日も同じ形（エンジンの起動が iscsid の起動の数秒前で、セッションがある）なら、記録して進める。数秒より前のものは止める
- duchamp では、0.32.0 の `install-pkgs.sh` の `systemctl start iscsid.service` で iscsid が起動する見込み（§8.10）。ボリュームもセッションも無いので害は無い
- Longhorn のボリュームのアタッチ先（data locality で動く）。chirico 10（`tumblr-data`、`fs/data`、`fs/h2`、`ero-data`、`natsumi-myao`、`prometheus-…-0`、`fraction-agents` の 4 つ）、oeilvert 5（`natsumi`、`natsumi-aki`、`prometheus-…-1`、`fraction-agents` の 2 つ）、pablo 1（`fs/sites`）。replica は chirico 11、duchamp 10、oeilvert 11、pablo 2
- replica 1 のボリューム: `prometheus-…-0`（pvc-625c8825、replica は chirico、アタッチも chirico）、`prometheus-…-1`（pvc-99c35b80、replica は oeilvert、アタッチも oeilvert）。drain しないので、止めない

### 2.8 MetalLB の告知ノードを読む

段 1 の手順書 §2.7 と同じ読み方。2026-10-19 13:2xZ（speaker のログの最後の `serviceAnnounced`。どれも 09:43:19Z）は次のとおり。告知先は動くので、当日と各台の前に読み直す。

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

段 3 では speaker のコンテナが再起動しない見込みなので、告知は移らない見込み。各台の後に、告知していた LoadBalancer の応答を `check-apps.sh` で見る。

## 3. control-plane のマニフェストを上げる（`install kubernetes`）

### 3.1 事前確認

✋✋ **段 3 の開始の承認を取る。** §2.6 の表と PR の差分、§2.7 の drain しない理由と止める条件、§2.5 の書き直しの対象、§2.2 のベースライン、§2.4 のバックアップ、§2.8 の告知ノードを示す。承認を得て PR をマージし、マージした master で §2.5 の書き直しを流してから §3.2 に入る。

- §2.2 のベースラインと §2.4 のバックアップが済んでいる。§2.3 の監視が動いている
- §2.5 の書き直しの後、`tools/storage-versions.sh` が `OLD: 0`
- Longhorn の `replica-auto-balance` が `disabled`
- 全台 Ready、etcd 3/3 healthy、VIP の `/readyz` が `ok`
- checkout が §2.6 の PR をマージした master で、`git status --short assets porkadot.yaml` が空
- §1.4 の SSH の確かめで 8 台とも通る

### 3.2 流す ✋

```sh
porkadot install kubernetes --node 192.168.1.111
```

- **`--node` を必ず付ける。** 付けないと bootstrap ノード（pablo）で `kubectl apply` を流し、`127.0.0.1:6443` に届かず rc 1 になる（段 2 と同じ）
- apiserver（DaemonSet）、controller-manager、scheduler、kube-proxy が v1.32.13 で rollout し、CoreDNS が v1.11.4 で rollout する。kubelet-serving-cert-approver、cnidaria、MetalLB はマニフェストが変わらないので動かない
- 時刻と rc を記録する。段 2 の本番では、流してから rollout の完了まで 3 分ほどだった
- **rc 1 で、出力の最後が `dial tcp 127.0.0.1:6443: connect: connection refused` なら、§3.3 の `rollout status` で apiserver の rollout の完了を待ってから、同じコマンドをもう一度流してよい**（dev の記録の見つけたことの 2。§8.3）。流し直しは ✋ で、承認は要らない。流し直した時刻と rc、DaemonSet `kube-apiserver` の generation が流し直しの前と後で同じこと（2 回目の rollout が起きていないこと）を記録する。rc 1 でほかのエラーなら止める。流し直しても rc 1 なら止める

### 3.3 rollout の完了を確かめる

段 2 の手順書 §3.3 と同じ（版を v1.32.13 に読み替える）。CoreDNS と approver の項目を次に替える。

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
| 1〜12 | 段 1 の手順書 §3.3 の 1〜12 | 同じ。Server が v1.32.13、apiserver・KCM・scheduler・kube-proxy が v1.32.13。Node は 8 台 Ready で kubelet は v1.31.14 のまま（apiserver 1.32 と kubelet 1.31 は skew policy の範囲） |
| 13 | CoreDNS | Deployment `coredns` が 2/2、Pod のイメージが `registry.k8s.io/coredns/coredns:v1.11.4`、ログの最初に `CoreDNS-1.11.4`。Pod から `kubernetes.default.svc.cluster.local` と外の名前が引ける（`netcheck.sh` の「svc by name (DNS)」でもよい）。generation が 1 つ増える（段 2 の後は 9） |
| 14 | approver | `kubelet-serving-cert-approver` が `0.12.1` のまま 1/1。generation が変わらない |
| 15 | CSR | `kubectl --context fraction get csr` に新しい CSR が無い（出ていれば、kubelet の serving のものは approver が Approved,Issued にしていること） |
| 16 | storage version | `tools/storage-versions.sh` が `OLD: 0`、`CRDs with more than one stored version: 0`（1.32 の kube-apiserver が新しく古い版で書くものが無いこと） |

- rollout が途中で 30 秒ほど止まって見えることがある（controller-manager のリーダーの交代。段 1 の手順書 §3.3 の注）
- ここで問題があれば、kubelet にまだ触っていないので、§7.2 で control-plane だけを戻せる

## 4. control-plane の kubelet を上げる（192.168.1.113 → .112 → .111）

### 4.1 何が起きるか

`install kubelet --node <IP>` は、`install-deps.sh`（kubelet・kubectl・crictl を落として張り替え、CNI plugins の v1.9.1 の tarball を `/opt/cni/bin` に展開する。etcdctl は同じ版なので落とさない）、`install-pkgs.sh`（`apt-get install --no-upgrade`、iscsid は `systemctl start` だけ）、`install.sh`（addon の `dns`、`multipathd`、`etcd`）を root で流し、kubelet を v1.32.13 で再起動する。

**段 2 と違い、コンテナは再起動しない見込み**（dev の記録）。

| コンテナ | 見込み |
|---|---|
| etcd（static Pod） | `etcd` の addon が `etcd-server.yaml` を置き直し（中身は同じ）、新しい kubelet が `Deleted mirror pod as it didn't match the static Pod` を出して mirror Pod を作り直す。etcd のコンテナは新しい sandbox で起き直す（dev では 2 秒。ほかのメンバーから見た unhealthy は 2 秒の間隔で 0〜3 回）。リーダーなら先に移す（§4.2 の 2） |
| kube-apiserver、controller-manager、scheduler、kube-proxy、cnidaria、speaker、node-exporter、smart-exporter | 再起動しない（UID と restartCount が同じ） |

- `etcd` の addon は `/etc/etcd/pki` の証明書と鍵を root 0600 で置き直す。`etcd.crt` は作り直したもの（同じ鍵、同じ CA。§2.6）に替わり、起き直した etcd が読む
- `dns` の addon は `systemd-networkd` を再起動するので、cnidaria の `no route` のログが出る（§8.1）
- control-plane には Longhorn のボリュームが無く、iscsid は動いていてセッションは無い（§2.7）。iscsid は再起動しない見込み
- drain も cordon もしない。controller-manager と scheduler も移さない

### 4.2 1 台の手順

1. 読み取りの確認。段 2 の手順書 §4.2 の 1 と同じもの（etcd のリーダー、対象のノードの Pod の名前・UID・restartCount、`/etc/etcd/pki`、cnidaria のログの error の数、controller-manager と scheduler の置き場所とリーダー、告知している LoadBalancer）に加え、`tools/node-state.sh` を控える。Pod の控えはファイルに取る（§4.3 の 7 で diff する）。

   ```sh
   snap() { kubectl --context fraction get pods -A --field-selector spec.nodeName=$1 -o json | jq -r '.items[] |
     [.metadata.namespace+"/"+.metadata.name, .metadata.uid,
      ([.status.initContainerStatuses[]?, .status.containerStatuses[]? | .name+"="+(.restartCount|tostring)] | join(","))] | @tsv' | sort; }
   snap <IP> > pods-<IP>-before.tsv
   ssh ubuntu@<IP> 'sudo bash -s' < docs/k8s-upgrade/tools/node-state.sh > node-<IP>-before.txt
   ```

   2026-10-19 は、controller-manager が .111（`-2blbx`）と .112（`-2ffhd`、リーダー）、scheduler が .112（`-vb2lz`）と .113（`-mp2ld`、リーダー）。
2. ✋ 対象が etcd のリーダーなら、リーダーを移す（段 1 の手順書 §4.2 の 2 と同じ形）。
   - 2026-10-19 のリーダーは .113（`57ec6f12ac7b683e`）。このままなら、.113 の作業の前に .111（`21ab2aeb56731588`）へ移し、.111 の作業の前に .113 か .112（`fbb0c648cf5852a5`）へ移す（段 1・段 2 と同じ形）
   - 移せなかったときは止める
3. ✋ 流す。

   ```sh
   porkadot install kubelet --node <IP>
   ```

   時刻（開始と終わり）と rc を記録する。段 2 の本番では 1 台 19 秒〜1 分だった。段 3 は CNI plugins の tarball も落とすので、少し長くなりうる。
4. kubelet の起動から 1 分ほど待ってから、§4.3 の確認。

### 4.3 1 台ごとの確認と、次の 1 台へ進む条件

| # | 確認 | 方法 | 合格基準 |
|---|---|---|---|
| 1 | Node | `kubectl --context fraction get node <IP> -o wide` | Ready、VERSION が v1.32.13、CONTAINER-RUNTIME が `containerd://2.3.6` |
| 2 | バイナリ | `tools/node-state.sh` の `bin` と `cni`、`/opt/bin/kubelet --version` | 向き先が `kubelet-v1.32.13`、`kubectl-v1.32.13`、`crictl-v1.32.0`、`etcdctl-3.5.34`（変わらない）。**CNI の印が `v1.9.1`、bridge・host-local・portmap・loopback の 4 つとも v1.9.1**。前の版のファイル（`kubelet-v1.31.14` など）も残っている（§7 の戻しで使う） |
| 3 | etcd の pki | `sudo stat -c '%a %U:%G %n' /etc/etcd/pki/*` | 3 つとも `600 root:root` |
| 4 | etcd | `etcdctl endpoint status --cluster -w table`、`etcdctl endpoint health --cluster -w table` | 3/3 healthy、リーダーが居る、raft index がそろう。3 台とも 3.5.34 |
| 5 | etcd の Pod | `kubectl --context fraction -n kube-system get pod etcd-<IP> -o wide`、ログの `error` | 1/1 Running、`etcd:3.5.34-0`。mirror Pod の UID が変わる。起き直しの直後のほかのメンバーの `lost TCP streaming connection`・`peer became inactive` は数秒で止まる |
| 6 | apiserver | 対象のノードの `kube-apiserver` の Pod | 1/1 Ready。**UID も restartCount も同じ**。VIP の `/readyz` が `ok` |
| 7 | Pod の再起動 | `snap <IP> > pods-<IP>-after.tsv; diff pods-<IP>-before.tsv pods-<IP>-after.tsv` | **差分は `kube-system/etcd-<IP>` の UID だけ**（restartCount は同じ）。ほかに UID・restartCount が変わったもの、CrashLoopBackOff、Running に戻らないものがあれば止める（§2.1 の 3） |
| 8 | iscsid | `tools/node-state.sh` の `iscsid` と `session` を 1 の控えと比べる | **MainPID と ActiveEnterTimestamp が同じ**。Longhorn のセッションは 0 のまま。PID が変わっていたら止める（§8.10） |
| 9 | cnidaria | 全ノードの cnidaria の Pod が Ready。`verify-nodes.sh` | 全 PASS。ログは §8.1 のとおり |
| 10 | KCM と scheduler | `kubectl --context fraction -n kube-system get pods -o wide -l 'app.kubernetes.io/component in (kube-controller-manager,kube-scheduler)'`、lease の holder | 2/2 ずつ Ready。restartCount は同じ。リーダーが移ったかを記録する |
| 11 | kubelet のログ | ノードで `sudo journalctl -u kubelet --since '-10min' --no-pager \| grep -iE 'error\|fail' \| tail` | 起動の直後の `InvalidDiskCapacity`（§8.5）、`ContainerStatus ... NotFound`、`RemoveStaleState`、`Image garbage collection failed once`、etcd の mirror Pod の `already exists`・`couldn't parse as pod`（古い kubelet が書き換えの途中を読んだもの）のほかに、続くエラーが無い |
| 12 | §2.3 の監視 | — | 失敗があれば、§2.8 の告知ノードと 13 の再起動と突き合わせて記録する（§8.8。数回までは許容） |
| 13 | leader election を使う controller | 段 2 の手順書 §8.8 のコマンド（時刻は 4.2 の 3 の開始） | 再起動したものが無い。あれば記録し、Running に戻り、再起動が続いていないこと |
| 14 | 告知していた LoadBalancer | §2.8 の読み方と `check-apps.sh` | 応答する |
| 15 | CSR | `kubectl --context fraction get csr` | 新しい CSR が無い。出ていれば Approved,Issued（§8.9） |

次のすべてを満たしてから、次の 1 台に入る。

- 上の 1〜15 がすべて合格
- 全 8 台の Node が Ready
- etcd 3/3 healthy、raft index がそろっている
- Running / Completed 以外の Pod がベースラインから増えていない

## 5. worker の kubelet を上げる（1 台ずつ、drain しない）

### 5.1 順番

| 順 | ノード | アタッチされたボリューム（2026-10-19） | iSCSI のセッション | 理由・注意 |
|---|---|---|---|---|
| 1 | duchamp | なし | 0（iscsid は動いていない） | **Longhorn のノードで、ボリュームがアタッチされていない。** longhorn-manager・instance-manager・CSI のプラグインが載っているので、1.32 の kubelet でそれらが再起動しないことを、ボリュームを危険にさらさずに確かめられる。冷却ファンが故障中（ターボ停止運用）だが、再起動しないので `no_turbo` はそのまま。`natsumi-sshd-myao` を告知している |
| 2 | pablo | 1（`fs/sites`） | 1 | **API の VIP を告知している。** ボリュームのアタッチされた最初の台。bootstrap ノード |
| 3 | braque | なし（Longhorn のノードではない） | 0 | nfsd が載っている（§5.4）。他の worker が健全な状態で、バックアップの CronJob の時間帯を避けて行う |
| 4 | oeilvert | 5（`prometheus-…-1` の replica 1 を含む） | 5 | gated-v6 を告知している。`homegallery/api` は oeilvert に固定（drain しないので止まらない） |
| 5 | chirico | 10（`prometheus-…-0` の replica 1 を含む） | 10 | アタッチされたボリュームが最も多いので最後にする。gated-v4 を告知している。iscsid より前に起動したエンジンが 1 つ（§2.7） |

- 段 2 は pablo を最初にしたが、段 3 では duchamp を最初にする。drain しないので、最初の worker で Longhorn の DaemonSet の Pod が再起動しないことを、ボリュームの無い台で先に確かめる（§2.1 の 3）
- 当日の読み取りで、アタッチされたボリュームの数が変わっていれば（data locality で動く）、少ない台から多い台へ並べ直してよい。braque はどこに入れてもよい
- 計画 §6.2 は oeilvert を worker の最後にしていた（MinIO の 4 つの replica のため）。MinIO は消えたので、アタッチの多い chirico を最後にする

### 5.2 1 台の手順

1. 読み取りの確認。
   - `kubectl --context fraction get node <ノード> -o wide`: Ready、v1.31.14
   - 対象のノードの Pod の名前・UID・restartCount を控える（§4.2 の 1 の `snap`）
   - `tools/node-state.sh` を控える（iscsid の PID、セッション、エンジンの起動の時刻、CNI、`/opt/bin`）
   - **古い iSCSI のセッションが無いこと**: すべてのセッションの portal が、そのノードの今の instance-manager の IP であること（`kubectl --context fraction -n longhorn-system get instancemanagers -o custom-columns=N:.metadata.name,NODE:.spec.nodeID,S:.status.currentState,IP:.status.ip`）。違う IP へのセッションがあれば止める（§8.10）
   - **`older-than-iscsid` のエンジン**: 無いこと。あれば §2.7 の chirico の注のとおり判断する（iscsid の起動の数秒前で、セッションがあるものだけ記録して進める）
   - Longhorn: 対象のノードにアタッチされたボリュームと、その robustness（`kubectl --context fraction -n longhorn-system get volumes.longhorn.io -o custom-columns=N:.metadata.name,S:.status.state,R:.status.robustness,NODE:.status.currentNodeID`）。degraded のボリュームが無い（ベースラインのものを除く）
   - 対象のノードの Running の Pod と同じ Longhorn の PVC を使う Completed / Succeeded の Pod（§8.12 のコマンド）。あれば、`install kubelet` の前に消してよいかをユーザーに確かめる（runbook から外れる扱い）
   - そのノードが告知している LoadBalancer（§2.8）
2. ✋ 流す。

   ```sh
   porkadot install kubelet --node <ノード>
   ```

   - `<ノード>` は `porkadot.yaml` の `nodes` のキー（`duchamp`、`pablo`、`braque`、`oeilvert`、`chirico`）
   - 時刻（開始と終わり）と rc を記録する。段 2 の本番では 1 台 17 秒〜1 分 11 秒だった
3. kubelet の起動から 1 分ほど待ってから、§5.3 の確認。

### 5.3 1 台ごとの確認

| # | 確認 | 方法 | 合格基準 |
|---|---|---|---|
| 1 | Node | `kubectl --context fraction get node <ノード> -o wide` | Ready、VERSION が v1.32.13、CONTAINER-RUNTIME が `containerd://2.3.6` |
| 2 | バイナリ | `tools/node-state.sh` の `bin` と `cni` | 向き先が `kubelet-v1.32.13`、`kubectl-v1.32.13`、`crictl-v1.32.0`。**CNI の印が `v1.9.1`、4 つのプラグインとも v1.9.1**。`kubelet-v1.31.14` なども残っている |
| 3 | iscsid | `tools/node-state.sh` の `iscsid` を §5.2 の 1 の控えと比べる | **MainPID と ActiveEnterTimestamp が同じ。** duchamp のように前に動いていなかった台は、`install kubelet` の時刻に起動していてよい（`systemctl start`。§8.10）。動いていた iscsid の PID が変わっていたら止める |
| 4 | iSCSI のセッション | `tools/node-state.sh` の `session` を控えと比べる | 同じ sid・portal・target が、同じ数だけある（dev では、セッションの番号は変わらなかった） |
| 5 | エンジン | `tools/node-state.sh` の `engine` を控えと比べる | 同じボリュームのエンジンが、同じ起動の時刻で動いている（エンジンのプロセスが止まっていない） |
| 6 | Longhorn | 対象のノードにアタッチされたボリュームの state・robustness、instance-manager、Longhorn の node | アタッチされたボリュームが `attached`・`healthy` のまま（faulted・degraded・remount が無い）。instance-manager が `running` で名前と IP が同じ。Longhorn の node が Ready。ノードで `sudo journalctl -k --since '-10min' \| grep -iE 'I/O error\|blk_update_request\|EXT4-fs error'` が空 |
| 7 | Pod の再起動 | `snap <ノード> > pods-<ノード>-after.tsv; diff pods-<ノード>-before.tsv pods-<ノード>-after.tsv` | **差分が無い**（名前・UID・restartCount が同じ）。1 つでもコンテナの再起動があれば、ここで止めて報告する（§2.1 の 3。特に instance-manager、longhorn-manager、longhorn-csi-plugin、engine-image） |
| 8 | cnidaria | 対象のノードの cnidaria が 1/1 Ready。`verify-nodes.sh` | 全 PASS。ログは §8.1 |
| 9 | kubelet のログ | ノードで `sudo journalctl -u kubelet --since '-10min' --no-pager \| grep -iE 'error\|fail' \| tail` | 起動の直後の `InvalidDiskCapacity` などのほかに、続くエラーが無い。Longhorn のボリュームの `FailedMount`（`no Pending workload pods`）が続いていない（§8.12） |
| 10 | §2.3 の監視 | — | 失敗があれば、§2.8 の告知ノードと突き合わせて記録する |
| 11 | 告知していた LoadBalancer | §2.8 の読み方と `check-apps.sh` | 応答する。告知が移ったかを記録する |
| 12 | CSR | `kubectl --context fraction get csr` | 新しい CSR が無い。出ていれば Approved,Issued（§8.9） |

- 7 で再起動が出たときは、それ以上の台に進まない。出たのが Longhorn のボリュームのアタッチされた台なら、ボリュームの robustness と Pod の I/O エラーを見て報告する。残りの台をどうするか（drain に切り替えるか）はユーザーが決める（§8.10 に drain する場合の手順）
- 3〜5 で、iscsid の PID が変わった・セッションが消えた・エンジンが止まった、のどれかが出たら止める。iscsid が再起動した台は、計画 §4.4 の 1 回目の状態（そのとき動いていたエンジンは logout できない）になっているので、そのボリュームを detach する前に対処を決める（§8.10）

### 5.4 braque の手順

braque には DaemonSet の Pod（cnidaria、kube-proxy、node-exporter、smart-exporter）と、nfsd の DaemonSet の Pod（`nfsd/nfsd-*`、hostNetwork）が載っている。Longhorn のノードではない（§2.7）。

- 段 2 では nfsd のコンテナが 1 回再起動して NFS が短く止まったが、**段 3 では nfsd も再起動しない見込み**（コンテナが再起動しないため）
- `dns` の addon の `systemd-networkd` の再起動は段 1・段 2 と同じく起きる。段 1 の braque では古い kubelet の `Failed to update lease` が 1 回出た（`results/stage-1/braque.md` §7）
- **念のため、バックアップの CronJob の時間帯を避ける**（段 2 の手順書 §5.4。止めてはいけない時間帯（JST）: 05:15〜06:45、14:30〜15:00、16:45〜17:05、17:55〜18:15）。作業の前に `kubectl --context fraction get cronjobs -A` で見直す
- 手順は §5.2・§5.3 と同じ（iSCSI のセッション・エンジン・Longhorn の項目は「なし」）。加えて、nfsd が Running で restartCount が同じ、2049 を listen している、oeilvert のホストの `/home/yuanying/shared/nfs` が読める、`registry.fraction.jp/v2/` が応答する（401 でよい）、LAN から Service の IP（10.254.0.0/16）と `fraction.cluster` の名前が引けることを見る

### 5.5 次の 1 台へ進む条件

次の **すべて** を満たしてから、次のノードに入る。

- §5.3 がすべて合格
- 全 8 台の Node が Ready、どれも SchedulingDisabled でない。終えたノードが v1.32.13、まだのノードが v1.31.14
- etcd 3/3 healthy、VIP が応答する
- Running / Completed 以外の Pod がベースラインから増えていない
- Longhorn のボリュームが healthy（ベースラインのものを除く）
- Longhorn の設定がベースラインのまま（`5`、`disabled`、`block-if-contains-last-replica`）
- `check-apps.sh` がベースラインと同じ。`netcheck.sh` は最初の worker の後と最後の台の後に流す（✋）
- **最初の worker（duchamp）の後に、✋ §1.9 の NetworkPolicy の確認を流す**（1.32 の apiserver と、1.32 の kubelet のノードを含む形で、cnidaria の NetworkPolicy の処理が動くこと）

30 分おいて様子を見る条件は置かない。

## 6. 段 3 の完了の確認

8 台を終えたら、計画 §6.3 の項目がすべて成り立つことを確かめ、`results/stage-3/summary.md` に残す。段 2 の手順書 §6 と同じ項目で、次を読み替える・足す。

- 8 台が Ready、全台 v1.32.13、CONTAINER-RUNTIME が `containerd://2.3.6`。どのノードも SchedulingDisabled でない
- 8 台の `/opt/bin` が `kubelet-v1.32.13`、`kubectl-v1.32.13`、`crictl-v1.32.0`、`etcdctl-3.5.34`。**CNI の印が `v1.9.1` で、8 台とも bridge・host-local・portmap・loopback が v1.9.1**
- etcd 3/3 healthy、全メンバーが 3.5.34、リーダーが居る、raft index がそろう。3 台の `/etc/etcd/pki` が root 0600
- VIP の `/livez` が `ok`、`/version` が v1.32.13
- apiserver 3/3、controller-manager と scheduler が 2/2（置き場所とリーダーを記録する）。kube-proxy が 8/8 で iptables。**CoreDNS が v1.11.4 で 2/2 Running**
- kubelet-serving-cert-approver が `0.12.1` で Running
- Running / Completed 以外の Pod が無い（ベースラインのものを除く）
- **全 Pod の restartCount が、ベースライン（§2.2 の 5）から増えていない**（control-plane の etcd の mirror Pod は UID が変わる。`install kubernetes` で作り直された Pod は新しい UID で 0）。増えたものは理由を書いて分ける
- **storage version**: `tools/storage-versions.sh` が `OLD: 0`（古い版で保存された組み込みのオブジェクトが無い）、`CRDs with more than one stored version: 0`（47 個の CRD の `status.storedVersions` が 1 つ）。結果のファイルの要点（prefix の数、キーの数、`OLD`、`MULTI`）を記録する
- Longhorn: attached のボリュームが全部 healthy（detached の `homegallery/cg-data` はベースラインのとおり）、instance-manager が 4 つとも running で段の前と同じ名前、engine image は v1.11.2 のまま。K8s 1.32 は Longhorn 1.11 の要件（1.25 以上）に入る。replica の置き場所
- Longhorn の設定: ベースラインのまま（`5`、`disabled`、`block-if-contains-last-replica`、`best-effort`）
- **iSCSI**: 8 台の `tools/node-state.sh` で、iscsid の PID が段の前と同じ（duchamp は段の間に起動したもの）、Longhorn のセッションはどれも今の instance-manager の IP へのもので、古いセッションが無い、`older-than-iscsid` のエンジンが段の前から増えていない
- cnidaria: 8 台の Pod が Ready、`verify-nodes.sh` が全 PASS（`table inet cnidaria` を含む）、✋ `netcheck.sh` が全 PASS。**✋ §1.9 の NetworkPolicy の確認が合格**（`up` の後に 8 台の `table inet cnidaria` に `k8u-npcheck/allow-8080` の規則が入り、ノードをまたぐ v4・v6 で許した通信が通り許していない通信が止まり、`down` の後に 8 台とも規則が消える）。計画 §6.3 の「NetworkPolicy（`hedgedoc/db-postgresql`）」の項目は、hedgedoc が消えたのでこれで代える
- MetalLB: LoadBalancer の Service が応答する（gated、`h2-sshd`、`natsumi-sshd*`、minecraft）。告知ノードを記録する
- braque の NFS が応答する。`registry.fraction.jp` が応答する
- `kubectl --context fraction top nodes` が応答し、Prometheus のスクレイプが落ちていない。`apiserver_requested_deprecated_apis` を記録する（1.32 の後に `flowcontrol.apiserver.k8s.io/v1beta3` を使うクライアントがあれば、それは 404 を受けているので調べる）
- `kubectl --context fraction get csr`: 段の間に出た CSR が無いか、出ていれば Approved,Issued。kubelet の serving の証明書の subject と期限が §2.2 の 12 と同じ
- 新しい warning のイベント・ログ（kubelet、apiserver、kube-proxy、cnidaria、etcd、Longhorn、CoreDNS）が増えていない（§8 のものは除く）
- §2.3 の監視の FAIL を集計し、原因ごとに分けて記録する
- 段 3 の間に leader election で再起動した controller の一覧（§8.8）
- etcd のバックアップ（§2.4）を worktree からメインの checkout の `backup/` へ移した（worktree で流した場合。coordinator）

## 7. ロールバック

**戻すのは runbook から外れる操作なので、その都度ユーザーの承認を取る。** 戻すと決める目安は段 1 の手順書 §7 と同じ（rollout が終わらない、VIP が 1 分を超えて応答しない、Node が 5 分たっても Ready にならない、etcd が 2/3 を下回る、Pod の再起動が続く、Longhorn のボリュームが degraded のまま戻らない、1.32 に固有と見られる問題）。

### 7.1 戻すための材料

前の版は、**この PR の前の master（`1761f1d`）の `assets/` と `porkadot.yaml`** と、**porkadot 0.31.0**（`v0.31.0`、`62d8821`）を使う。この `assets/` は 0.31.0 で render したもので、本番は今これで動いている。

- 0.31.0 の `install kubelet` は `/opt/bin/<名前>` の向き先と CNI の版の印で判定して張り替える。前の版のバイナリ（`kubelet-v1.31.14` など）はノードに残っているので、落とし直さずに向き先を戻す。CNI plugins は版の印が違うので v1.4.1 の tarball を落として展開し直す（bridge・host-local・portmap も v1.4.1 に戻る。cnidaria の Pod が作り直されると、また v1.9.1 になる。§8.11）
- **0.31.0 の `install-pkgs.sh` は、毎回 `systemctl restart iscsid.service` を流す。** Longhorn のボリュームがアタッチされた台で 0.31.0 の `install kubelet` を流すと、そのとき動いているエンジンは logout できなくなり（計画 §4.4 の 1 回目）、後の detach で古いセッションを残す。**Longhorn のボリュームがアタッチされた台を戻すときは、drain してから流す**（§8.10 の drain する場合の手順。drain の後・`install kubelet` の前に古いセッションを logout し、`install kubelet` の後に空を確かめる）。アタッチされたボリュームの無い台（control-plane、braque、当日の duchamp など）は drain しなくてよい
- 0.31.0 の SSH は 0.32.0 と同じで、サンドボックスの中で流せる（段 2 で通した）
- 1.32 → 1.31 の kubelet の戻しで、コンテナが再起動するかは dev で確かめていない（1.31 で hash の計算が変わったのは 1.30 → 1.31 のとき。段 2 の手順書 §8.4）。再起動する前提で、Longhorn のノードは drain してから戻す（上の iscsid の件と同じ扱い）

用意の仕方（作業端末で。ノードには触らない）:

```sh
git -C /home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot worktree add /tmp/porkadot-0.31.0 v0.31.0
P_OLD=/tmp/porkadot-0.31.0
git -C <このリポジトリ> worktree add /tmp/fraction-stage-2 1761f1d
cd /tmp/fraction-stage-2
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

- `bundle install` が要ることがある（0.31.0 の Gemfile.lock）。Ruby は cwd（このリポジトリ）から決まる作業端末のもの（2026-10-19 は 4.0.7）。始める前に `grep VERSION $P_OLD/lib/porkadot/version.rb` が 0.31.0 で、`BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot help` が動くことを確かめておく
- secrets は前の版も同じ（sops の同じ鍵。§1.6）

### 7.2 `install kubernetes` の後、kubelet はまだ前の版 ✋

```sh
cd /tmp/fraction-stage-2
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml
```

- apiserver・KCM・scheduler・kube-proxy が v1.31.14 に、CoreDNS が v1.11.3 に戻る。§3.2 と同じく、rc 1（`connection refused`）なら rollout を待って流し直す
- dev では確かめていない。§3.3 と同じ確認を、版を読み替えて行う
- storage の版: §2.5 で書き直した v1 は 1.31 の storage の版なので読める。1.32 で新しく storage の版が変わるリソースのオブジェクトは本番に無い（`storage-versions.md` §3）。**段 3 の間に、1.32 で新しく使えるようになった API のオブジェクトを作らない**。戻した後に `tools/storage-versions.sh` で `OLD` を見る

### 7.3 kubelet を戻す（1 台） ✋

```sh
cd /tmp/fraction-stage-2
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubelet --node <ノード> --config ./porkadot.yaml
```

- `/opt/bin` の向き先が `kubelet-v1.31.14`、`kubectl-v1.31.14`、`crictl-v1.31.1` に、CNI の印が `v1.4.1` に戻る（etcdctl は 3.5.34 のまま）。確かめる
- **Longhorn のボリュームがアタッチされた台は、drain してから流す**（§7.1）
- control-plane では、戻す台が etcd のリーダーなら先に §4.2 の 2 でリーダーを移す
- 戻した台でも、§4.3 または §5.3 の確認を、版を読み替えて行う。iscsid は再起動する（0.31.0 の `install-pkgs.sh`）ので、§5.3 の 3 の「PID が同じ」は当たらない。代わりに、drain した台では `install kubelet` の後に Longhorn のセッションが無いこと

### 7.4 段 3 全体をやめる

kubelet は kube-apiserver より新しくてはいけないので、**kubelet を先に戻し、control-plane を最後に戻す。**

1. worker を、上げた順の逆に §7.3 で戻す
2. control-plane の kubelet を、上げた順の逆（.111 → .112 → .113）に §7.3 で戻す
3. §7.2 で control-plane のマニフェストを戻す

戻し終えたら、§6 の確認を版を読み替えて行い、`results/stage-3/` に戻した経緯を残す。etcd のバックアップ（§2.4）からの restore は最後の手段で、段 1 の手順書 §7.4 と同じ扱い（その時点でユーザーと決める）。§2.5 の書き直しは戻さない（戻す必要が無い）。

## 8. 既知の問題と注意

### 8.1 `install kubelet` のたびの cnidaria の `no route`

段 1 の手順書 §8.1 と同じ。`dns` の addon が `systemd-networkd` を再起動するたびに、対象のノードの cnidaria が `Reconciler error ... no route` を数件、1 秒ほど出し、ほかのノードの cnidaria が info の `no route for a family` を数件出す。段 3 では cnidaria のコンテナは再起動しない見込みなので、同じコンテナのログで読む。1 秒を超えて続く、ほかの error が出る、`verify-nodes.sh` が FAIL する、のどれかなら止める。

### 8.2 render が証明書を作り直す

段 1 の手順書 §8.2 と同じ。`bootstrap.crt`（9 つ）と master の `addons/etcd/etcd.crt`（3 つ）は render のたびに作り直される（同じ鍵、同じ CA）。当日に render し直さない。

### 8.3 `install kubernetes` の rc 1（`127.0.0.1:6443` の `connection refused`）

dev の記録の見つけたことの 2。`install kubernetes --node 192.168.1.111` は、.111 の上で `kubectl apply` を順に流す。apiserver の DaemonSet の rollout が .111 の apiserver を最初に入れ替えると、同じノードで流れている `kubectl apply` の接続先（`127.0.0.1:6443`）が消え、残りの apply が失敗して rc 1 になる。それより前のもの（Deployment、DaemonSet、ConfigMap など）は apply されている。

- dev の段 3 では、残った 2 つ（MetalLB の `L2Advertisement` と `ValidatingWebhookConfiguration`）が失敗した。どちらも中身は変わっていないものなので、失敗しても実害は無いが、流し直して rc 0 を得る
- rollout の完了を待って同じコマンドを流し直すと rc 0 になり、DaemonSet の generation は変わらない（2 回目の rollout は無い）
- 0.31 の rc（dev）と本番の段 2 では rc 0 だった。rollout がどのノードから始まるかと、apply の残りの時間の競争と見ている（確かめていない）

### 8.4 1.32 の kubelet ではコンテナが再起動しない

段 2 の 1.31 の kubelet での全コンテナの 1 回の再起動（kubernetes#124220。段 2 の手順書 §8.4）は、1.30 の kubelet が作ったコンテナの hash が 1.31 で合わなくなったためだった。1.31 の kubelet が作ったコンテナは、1.32 の kubelet でも同じ hash になる（dev の 7 台で、`definition changed` のイベントも restartCount の増加も無かった）。

- control-plane の etcd の static Pod は作り直される（§4.1）。ほかのコンテナが 1 つでも再起動したら、それは dev で見ていないことなので止める（§2.1 の 3、§5.3 の 7）

### 8.5 kubelet の再起動の直後の `InvalidDiskCapacity`

段 1 の手順書 §8.6 と同じ。想定内。

### 8.6 porkadot を流す場所

段 1 の手順書 §8.7 と同じ。cwd はこのリポジトリのルートにする。

### 8.7 段 2 の .111 の件（apiserver が SIGTERM の後に Endpoints に残った）

段 2 の本番の .111 では、kubelet の更新で apiserver のコンテナが SIGTERM で止まりかける間、6443 を閉じたまま Endpoints に 30 秒ほど残り、同じノードの API を使うコンテナ（controller-manager、cnidaria、speaker）が `https://10.254.0.1:443` の `connection refused` で数回落ち、VIP が 18 秒の間に 9 回失敗した（`results/stage-2/192.168.1.111.md` §5.1、段 2 の手順書 §4.3 の 7）。

- 段 3 では apiserver のコンテナが再起動しない見込みなので、起こりにくい
- 起きたら、段 2 と同じく、apiserver が起き直した後に Running に戻り、それ以上再起動が増えなければ許容し、回数を記録する（2026-10-19 のユーザーの判断）。ただし段 3 では「apiserver のコンテナが再起動した」こと自体が §8.4 の想定外なので、その台で止めて報告する

### 8.8 apiserver が止まりかける間の leader election の controller の再起動

段 2 の手順書 §8.8 と同じ扱い（ユーザーの判断で許容。記録して、Running に戻ったことと、再起動が続いていないことを確かめる）。段 3 で apiserver が止まりかけるのは、`install kubernetes` の rollout の間だけの見込み。

### 8.9 kubelet の serving の証明書と CSR

段 2 の手順書 §8.10 と同じ。kubelet の更新では既存の serving の証明書がそのまま使われ、段 3 の間は CSR が出ない見込み（dev でも出なかった）。次に CSR が出るのは、kubelet が証明書を更新するとき（いちばん早いのは oeilvert、期限 2027-03-20）。段 3 の間に CSR が出て Pending のまま残ったら、止めて報告する。

### 8.10 iscsid と古い iSCSI のセッション（Longhorn v1.11.2）

計画 §4.4 と porkadot-dev の `docs/longhorn/iscsi-stale-sessions.md`（以下「iSCSI の記録」）のもの。Longhorn のエンジンが直る版（v1.12.1 以上、各ボリュームのエンジンを新しいイメージにしたもの）になるまで、**Longhorn の iSCSI のセッションが残ったノードで、iscsid を再起動しない。**

**段 3 で見ること**（§5.2 の 1、§5.3 の 3〜5）:

- 0.32.0 の `install kubelet` は、`/etc/iscsi/initiatorname.iscsi` が `assets/kubelet/<ノード>/initiatorname.iscsi` と同じなら、iscsid を再起動しない（`systemctl start iscsid.service` だけ。動いていれば何もしない）。本番の 8 台は同じ（§2.7）。違うノードがあったら、`install kubelet` で iscsid が再起動するので、そのノードは drain してから流す（下）
- iscsid が動いていないノード（2026-10-19 は duchamp。`iscsid.socket` で、iSCSI を使うときに起動する）では、`systemctl start` で iscsid が起動する。前に動いていなかったので、logout できなくなるエンジンは無い
- iscsid が動いていて PID が変わったら、それは再起動である。そのとき動いていたエンジン（`tools/node-state.sh` の `engine`）は、以後 detach のときに logout できない（iSCSI の記録の結論の 1）。止めて報告し、そのボリュームを detach する前に、そのノードを drain して古いセッションを logout する（下の 3）か、そのままにして次に iscsid を再起動する前に片付けるかを決める
- open-iscsi は 0.32.0 の `apt-get install --no-upgrade` で上がらない。Longhorn のノード 4 台では unattended-upgrades からも外してある（`/etc/apt/apt.conf.d/51fraction-hold-open-iscsi`。計画 §4.4）

**drain する場合の手順**（§5.3 で再起動が出て drain に切り替えるとき、§7 で 0.31.0 に戻すとき、`initiatorname.iscsi` が違うノード。どれも runbook から外れるので承認を取る）:

1. drain の前（読み取り）: `tools/node-state.sh` で、セッションと `older-than-iscsid` のエンジンを控える（drain の後に残るセッションの数の見込みになる）
2. Longhorn の設定の切り替えと drain は段 2 の手順書 §5.2 の 2〜6 と同じ（`concurrent-replica-rebuild-per-node-limit` を `0`、最後の replica を持つボリュームのある台では `node-drain-policy` を `allow-if-replica-is-stopped` にして Prometheus を止める。MinIO は無い）
3. ✋ **drain の後、`install kubelet` の前に、ノードで `sudo iscsiadm -m session` を見る。** drain したノードには instance-manager もアタッチされたボリュームも無いので、Longhorn の iqn（`iqn.2019-10.io.longhorn:`）のセッションは全部古いもの。残っていれば logout する（dev では 11 本が 1 秒）

   ```sh
   ssh <user>@<IP> 'sudo sh -s' < docs/k8s-upgrade/tools/iscsi-logout-stale.sh
   ```

   最後に `iscsiadm: No active sessions.` が出ること。`FAILED`（error 32）が出たら、iscsid がすでに再起動した後で logout できない状態なので、止める（消し方は iSCSI の記録の §4.3。drain したまま iscsid に諦めさせる。11 本に約 4 分）
4. `install kubelet`
5. `install kubelet` の後にもう一度 `sudo iscsiadm -m session` が `No active sessions.` であることを確かめて、**再起動せずに** uncordon する。設定を戻すのは段 2 の手順書 §5.5 と同じ

### 8.11 CNI plugins: porkadot と cnidaria が `/opt/cni/bin` を互いに上書きする

タスクの notes の `cni-plugins-survey.md`（coordinator の確認、2026-10-19）。

- cnidaria の DaemonSet の init container（`install-cni-plugins`）は、cnidaria v0.1.1 のイメージに入れた CNI plugins v1.9.1 の bridge・host-local・portmap を `/opt/cni/bin` に置く。porkadot の `install-deps.sh` は、版の印（`/opt/cni/bin/.porkadot-cni-plugins-version`）が `CNI_VERSION` と違うときに、tarball の 18 個のプラグインを全部展開する
- そのため、段 2 の後の本番は版が混ざっている。段 2 の後に再起動した 3 台（duchamp、chirico、oeilvert）は、cnidaria の Pod が作り直されて init container が流れたので bridge・host-local・portmap が v1.9.1、loopback が v1.4.1。ほかの 5 台は 4 つとも v1.4.1（段 1 の 0.30.0 の最初の `install kubelet` が v1.4.1 で上書きした）。印は 8 台とも `v1.4.1`（2026-10-19 13:1xZ の `tools/node-state.sh`）
- 段 3 の `install kubelet` で、印が `v1.4.1` → `v1.9.1` になり、tarball を展開し直す。**全台・4 つとも v1.9.1 になる**（porkadot と cnidaria の版がそろい、上書きの揺れが無くなる）。実際に版が変わる使用中のプラグインは、3 台では loopback だけ、5 台では 4 つとも
- 展開の数秒の間に、そのノードで Pod の作成・削除が重なると、CNI の ADD/DEL が一時的に失敗して再試行になりうる。既存の Pod には触らない（CNI は ADD/DEL/CHECK のときだけ呼ばれる）
- 新しい Pod の eth0 は `tx_queue_len` 1000、`keep_addr_on_down` 1 になる（古い Pod は 0 と 0。害は無い。dev の記録の見つけたことの 5）。portmap は iptables の backend のまま

### 8.12 Longhorn の `no Pending workload pods`（longhorn/longhorn#8072 の形）

段 1 の手順書 §8.11 のもの。drain しないので、段 1 と同じく当たりうる。kubelet は再起動の後、動いている Pod のボリュームにも `NodePublishVolume` をやり直し、Longhorn v1.11.2 の CSI は、同じ PVC を使う Succeeded（Completed）の Pod があると（ノードを問わない）、`Aborted: no Pending workload pods ...` で断り続ける（Pod は動き続ける）。

- 2026-10-19 13:2xZ は、Longhorn の PVC で当たるものは無い（Running と Succeeded が同じ PVC を使うのは `aphrael/aphrael-2` だけで、これは NFS の静的な PV）
- CronJob（`fs/*-backup`、`natsumi/natsumi-backup*`、`fraction-agents/deep-researcher-backup` など）が、動いている Pod と同じ PVC を使う Completed の Pod を残すことがある。§5.2 の 1 で、次のコマンドで洗い出す（読み取り）。出たら、消してよいかをユーザーに確かめてから消す（Job・CronJob・Running の Pod には触らない。`infra-admin` のトークンが要る）

  ```sh
  kubectl --context fraction get pods -A -o json | jq -r --arg n <ノード> '
    [.items[] | . as $p | .spec.volumes[]? | select(.persistentVolumeClaim)
     | {pvc: ($p.metadata.namespace+"/"+.persistentVolumeClaim.claimName), pod: ($p.metadata.namespace+"/"+$p.metadata.name), phase: $p.status.phase, node: $p.spec.nodeName}]
    | group_by(.pvc)[] | select(any(.phase=="Running" and .node==$n) and any(.phase=="Succeeded" or .phase=="Failed"))
    | .[] | select(.phase!="Running") | [.pvc, .pod, .phase, .node] | @tsv'
  ```

  出た PVC が Longhorn のもの（`kubectl --context fraction get pv <PV> -o jsonpath='{.spec.csi.driver}'` が `driver.longhorn.io`）かを確かめる。NFS の PV なら当たらない
- dev の段 3 では、アタッチしたまま `install kubelet` した 2 台で当たらなかった（Completed の Pod が無かった）

### 8.13 dev の etcd のディスクの止まり

dev の記録の見つけたことの 3。dev では、porkadot の操作の間に etcd の `slow fdatasync`（最大 6.3 秒）が 3 台に同時に出て、VIP と 3 台の `/readyz` が数秒〜15 秒応答しなかった。7 台の VM が同じホストのディスクを使うためと見ている。本番の etcd は Raspberry Pi 5 の 3 台で別々のディスクなので、同じ形では起きない見込み。本番でも VIP が 15 秒を超えて応答しないときは、etcd のログの `slow fdatasync` と `leader failed to send out heartbeat on time` を見て記録する。1 分を超えたら §7 の目安に当たる。

### 8.14 storage version

`storage-versions.md`。§2.5 の書き直しの前の洗い出しで、上の 3 種のほかの `OLD`、または CRD の `MULTI` が出たときは止める。

- CRD の `storedVersions` に古い版が残るのは、CRD の storage の版を変える更新（Longhorn・kube-prometheus・MetalLB などの CRD の更新。計画 §4・§8）の後である。そのときは、その CRD のカスタムリソースを全部新しい storage の版で書き直してから、`status.storedVersions` から古い版を外す（計画 §6.4）。段 3 では CRD の更新は無い

## 9. 記録

`results/stage-3/` に、ベースライン（`baseline.md`。§2.5 の書き直しも）、`install kubernetes`（`control-plane.md`）、各台（`<ノード>.md`。control-plane は `192.168.1.11N.md`）、全体のまとめ（`summary.md`）を残す。各台の雛形は `results/stage-3/template.md`。
時刻（UTC。control-plane のホストの JST の時刻は直して書く）、読み取りの結果、実行したコマンドと出力の要点、Pod の再起動の有無、iscsid の PID とセッションの前と後、監視の FAIL、leader election で再起動したもの、手順書との差を書く。`tools/node-state.sh` と `snap` の出力、監視のログ（`./stage-3-probe.log`）、`tools/storage-versions.sh` の出力（キーと版だけで値は無い）はタスクディレクトリの `notes/stage-3/` に置き、要点を記録に写す。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（同じ PR か、記録の PR で）。
