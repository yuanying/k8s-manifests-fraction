# 段 1 の手順書: K8s を 1.29.8 から 1.30.14 へ上げる（本番 `fraction`）

本番クラスタ `fraction` の Kubernetes を v1.29.8 から v1.30.14 へ上げる手順。porkadot を 0.29.2 から 0.30.0 に替え、etcd をパッチ更新（3.5.12 → 3.5.34）する。
計画は同じディレクトリの `plan.md`（以下「計画」）の §6（骨子）と §7 の段 1 の行、決まったことは §9 にある。前の段は `runbook-stage-c.md`（以下「段 C の手順書」）。

| | 更新前 | 更新後 |
|---|---|---|
| porkadot | 0.29.2 | **0.30.0**（`7d607a7`、タグ `v0.30.0`） |
| kube-apiserver、kube-controller-manager、kube-scheduler、kube-proxy | v1.29.8 | **v1.30.14** |
| kubelet、kubectl（ノードの `/opt/bin`） | v1.29.8 | **v1.30.14** |
| etcd（control-plane の static Pod） | 3.5.12-0 | **3.5.34-0**（パッチ更新） |
| etcdctl（ノードの `/opt/bin`） | 3.5.12 | 3.5.34 |
| crictl（ノードの `/opt/bin`） | v1.28.0 | **v1.30.1**（1.29 で上げ忘れていた分） |
| CoreDNS | v1.10.1 | **v1.11.3** |
| control-plane の `/etc/etcd/pki` | root 0644 | **root 0600**（porkadot#25） |
| etcd の `ETCD_UNSUPPORTED_ARCH=arm64` | あり | **なし**（計画 §10） |
| containerd、runc | 段 C の 2.3.x、1.5.x | 変えない |
| cnidaria、MetalLB、kubelet-serving-cert-approver、CNI plugins（v1.4.1） | — | 変えない（マニフェストの差分が無い） |
| kubelet の `config.yaml`・`kubelet.service` | — | 変えない |
| Longhorn | v1.11.2 | 変えない（要件は K8s 1.25 以上。計画 §4） |

この手順は dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で先に通してある（2026-10-18）。記録は porkadot-dev の次の 2 つ（以下「dev の記録」）。

- `docs/k8s-upgrade/verification-1.30.md`: 段 C の後の dev で、porkadot#23 を使い 1.29.8 → 1.30.14 を通した。ロールバックも 1 台で通した
- `docs/k8s-upgrade/verification-0.30-rc.md`: 0.30.0 に入れる 4 つの PR（#23〜#26）をまとめた形で、`etcd backup`、pki のモード、`--force` なしの戻しと上げ直しを確かめた

dev では、どの段階でも API・DNS・Pod 間通信・LoadBalancer は途切れず、**kubelet の更新で Pod は 1 つも再起動しなかった**（etcd の static Pod が新しいイメージで作り直されるだけ）。ノードの再起動は無い。

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **arm64 の control-plane**。dev の段 1 は amd64 の VM で通した。arm64 のイメージ（kube-* v1.30.14、etcd 3.5.34-0、CoreDNS v1.11.3）とバイナリ（kubelet・kubectl v1.30.14、etcd v3.5.34、crictl v1.30.1）が配布されていることは確かめてある（§1.7）
- **Longhorn のボリュームの多い worker**（chirico、duchamp、oeilvert は 13〜17 の replica を持つ）。dev は 2 つのボリュームだけだった。drain しないので、Pod とボリュームが動き続けることを 1 台ごとに見る
- **control-plane のマニフェストの戻し**（`install kubernetes` を前の版でやり直す。§7.2）。dev の戻しは kubelet と etcd だけで、control-plane のマニフェストは戻していない

## 0. 役割と約束ごと

- **承認の節目は 1 つだけ**（計画 §9.1「本番の各段の開始（render の差分を見せてから `install kubernetes` を流す前）」）。この手順書では ✋✋ を付けた。
  - ✋✋ **段 1 の開始**: render の差分（§2.5。この手順書と同じ PR）を見せ、PR をマージしてから、`install kubernetes` を流す前（§3.2 の前）
- 段 1 は etcd のパッチ更新なので、control-plane の kubelet の前の節目は無い（その節目はマイナー更新を含む段 5 と段 8 だけ）。
- **節目の間の手順は、ユーザーに知らせるだけで進めてよい。** 変更系の操作には ✋ を付けてあるが、これは「知らせてから行う操作」の印で、1 つずつ承認を取る印ではない。
- **runbook から外れる操作（ロールバック、想定外の対処、drain、cordon）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認（`kubectl --context fraction get`、SSH での状態確認）は、知らせずに行ってよい。
- **1 台ずつ行う。** 1 台を終えて「次の 1 台へ進む条件」（§4.3、§5.3）を満たすまで、次のノードに手を付けない。
- 時刻はすべて UTC で記録する。

## 1. 前提

### 1.1 段 C が終わっていること

段 1 は段 C（containerd を Docker の `containerd.io` 2.3 系に置き換える）の後に行う（計画 §5.3）。始める前に次を確かめる。

- 段 C の完了の確認（段 C の手順書 §6）が `results/stage-c/summary.md` に残っている
- 8 台すべての CONTAINER-RUNTIME が `containerd://2.3.x`（全台同じ版）
- 段 C の後、1 日ほど様子を見た（計画 §9.6。目安で、必須ではない）

### 1.2 kubeconfig の運用

段 C の手順書 §1.1 と同じ。確認は `kubectl --context fraction`（`fraction-auditor`、read-only）で行う。

段 1 の変更は porkadot が行う（porkadot は `assets/kubernetes/kubeconfig.yaml` の admin の証明書を使い、ノードの上で `kubectl apply` する）。drain も cordon もしないので、**runbook どおりに進む限り `infra-admin` のトークンは要らない。**
ロールバックや想定外の対処で `kubectl` の変更系の操作が要るときだけ、`infra-admin` の短命トークンを発行する（`kubectl-admin` と書く）。

### 1.3 SSH

| ノード | 入り方 |
|---|---|
| worker（braque、chirico、duchamp、oeilvert、pablo） | `ssh yuanying@<IP>` |
| control-plane（192.168.1.111〜113、rasp01〜03） | `ssh ubuntu@<IP>` |

porkadot も同じ形で入る（`porkadot.yaml` の `connection`）。作業端末から 8 台に鍵で入れることを始める前に確かめる。

### 1.4 porkadot の流し方

porkadot 0.30.0 の checkout（`porkadot-dev/porkadot` の `v0.30.0`）を使い、**このリポジトリのルートを cwd にして** 流す。

```sh
P=/home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot
git -C $P describe --tags          # v0.30.0（lib/porkadot/version.rb も 0.30.0）
cd ~/src/github.com/yuanying/k8s-manifests-fraction   # このリポジトリ。§2.5 の PR をマージした master
BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

以下、この形を `porkadot <サブコマンド>` と書く。

- **cwd はこのリポジトリのルートにする。** porkadot は `local.assets_dir`（既定 `./assets`）を cwd から解決する。porkadot のディレクトリで流すと、そこにある `assets/` を見てしまう（2026-10-18 の render では、porkadot-dev/porkadot の古い `assets/secrets` を見て `Legacy secrets layout found` で止まった。何も書かれなかった）
- `--config` はサブコマンドの後ろに置く（前に置くと Thor のエラーになる）
- secrets は `assets/` の中に sops（age）で暗号化してある（§1.6）。porkadot は読むときに sops で復号するので、作業端末に age の鍵（`~/.config/sops/age/keys.txt`）が要る
- このリポジトリの作業ツリーの `assets/` と `porkadot.yaml` に、PR の外の変更が無いこと（`git status --short assets porkadot.yaml` が空）。メインの checkout にほかの作業（staged の変更、未追跡のディレクトリ）があれば、master の別の worktree を作ってそこで流す
- 段 1 で流す porkadot のコマンドは、`etcd backup`、`install kubernetes --node 192.168.1.111`、`install kubelet --node <ノード>` の 3 つだけ。**`install all`、`--node` なしの `install kubelet`、`render`（特に `render all` と `render certs`）、`setup-node`、`setup-containerd` は流さない**
- 0.30.0 の `install kubelet` は `/opt/bin/<名前>` の向き先で判定して張り替えるので、**`--force` は要らない**（porkadot#26。dev の記録の `verification-0.30-rc.md`）。0.29.2 で要った `--force` の注意（`verification-1.30.md` の結論の 2）は 0.30.0 では当たらない

### 1.5 etcdctl の使い方

段 C の手順書 §1.5 と同じ。

```sh
ssh ubuntu@<control-plane> 'sudo bash -c ". /etc/etcd/etcd.env && /opt/bin/etcdctl endpoint status --cluster -w table"'
ssh ubuntu@<control-plane> 'sudo bash -c ". /etc/etcd/etcd.env && /opt/bin/etcdctl endpoint health --cluster -w table"'
```

以下、この形を `etcdctl ...` と書く。

- `etcd.env` が export する `ETCDCTL_ENDPOINTS` を残したまま `--endpoints` を渡すと止まる。特定のエンドポイントに向けるとき（`move-leader`）は `unset ETCDCTL_ENDPOINTS` してから渡す（§4.2 の 2）
- **`install kubelet` の後、そのノードの `/etc/etcd/pki` は root 0600 になる**（§8.5）。今は 0644 なので sudo なしでも読めるが、この手順では初めから sudo で流す
- `install kubelet` の後、そのノードの `/opt/bin/etcdctl` は 3.5.34 を指す

### 1.6 render に使った secrets と、本番との突き合わせ

前のタスクでは devbox の `assets/secrets` が古く、本番と食い違っていた（`docs/cp-replacement/runbook.md` §2.1）。段 1 の render（§2.5）では、次のようにして本番と同じ secrets を使ったことを確かめた（2026-10-18）。

**secrets の在りか**: porkadot 0.29 から secrets は `assets/` の中にある（`a73232d` の `porkadot migrate-secrets`）。ファイルごとに sops の binary 形式で暗号化してあり、`.sops.yaml` の age の受け手（`age13qtla9ypuh29eky4slttd5ydczq97fng5cyfqyngnanw3sglsucq0cl6af`）の鍵で復号する。render は git にある暗号化されたファイルを porkadot が sops で復号して読むので、**別の場所から secrets を持ってくる手順は無い**。

- `assets/secrets.tar.asc` は sops に移す前の GPG の書庫で、porkadot 0.30.0 は読まない。**展開して `assets/secrets/` を作らない**（porkadot が `Legacy secrets layout found` で止まる）
- 秘密の平文はディスクに書かない。下の確認も、復号をパイプで流してハッシュだけを比べた

**本番との突き合わせ**（読み取りだけ。2026-10-18 の結果）:

| 比べたもの | 本番の側 | 結果 |
|---|---|---|
| `assets/certs/kubernetes/ca.crt` | ConfigMap `default/kube-root-ca.crt` | 一致（SHA-256 `AB:5A:49:9E:…:A0:3E`） |
| `assets/certs/kubernetes/front-proxy-ca.crt` | ConfigMap `kube-system/extension-apiserver-authentication` の `requestheader-client-ca-file` | 4 つ並ぶ CA のうち最新（2026-06-13 発行）と一致。残りの 3 つは前の CA が積み重なったもの |
| `assets/certs/kubernetes/apiserver.crt` | 192.168.1.111〜113 と VIP の 6443 が返す証明書 | 4 つとも一致 |
| `assets/certs/kubernetes/` の 10 ファイル（`ca.crt`、`apiserver.{crt,key}`、`front-proxy-*`、`kubelet-client.*`、`sa.{key,pub}`） | .111 の kube-apiserver の Pod にマウントされた Secret `kube-apiserver` | 10 ファイルとも sha256 が一致 |
| `assets/certs/etcd/{ca.crt,etcd-client.crt,etcd-client.key}` | 同じく Secret `etcd-tls` | 3 ファイルとも一致 |
| `assets/kubelet/192.168.1.111/addons/etcd/{ca.crt,etcd.crt,etcd.key}`（render の前） | .111 の `/etc/etcd/pki/` | 3 ファイルとも一致 |
| CA の鍵と証明書（kubernetes、front-proxy、etcd） | — | 3 組とも公開鍵が一致（render が署名に使う鍵が CA と対になっている） |

作業の当日に確かめ直すときの形（作業端末で。読み取り）:

```sh
d() { sops -d --input-type binary --output-type binary "$1"; }
d assets/certs/kubernetes/ca.crt | openssl x509 -noout -fingerprint -sha256
kubectl --context fraction -n default get cm kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' | openssl x509 -noout -fingerprint -sha256
d assets/certs/kubernetes/apiserver.crt | openssl x509 -noout -fingerprint -sha256
echo | openssl s_client -connect 192.168.1.101:6443 2>/dev/null | openssl x509 -noout -fingerprint -sha256
```

どれかが食い違えば、render の差分も assets も信用せず、止めて調べる。

### 1.7 入れる版を確かめる

作業の当日に確かめ直す（読み取り）。

```sh
curl -fsSL https://dl.k8s.io/release/stable-1.30.txt     # v1.30.14
```

2026-10-18 の時点:

- `stable-1.30.txt` は v1.30.14（1.30 の最終パッチ。1.30 は EOL なので、これより新しいパッチは出ない見込み）
- registry.k8s.io の `kube-apiserver`・`kube-controller-manager`・`kube-scheduler`・`kube-proxy` の v1.30.14、`etcd:3.5.34-0`、`coredns/coredns:v1.11.3` は、どれも amd64 と arm64 を含む
- `dl.k8s.io` の kubelet と kubectl の v1.30.14（amd64、arm64）、etcd の `etcd-v3.5.34-linux-arm64.tar.gz`、crictl の v1.30.1（amd64、arm64）は、どれも 200 を返す
- 作業端末の kubectl は v1.29.8（1.30 の ±1 に入る。計画 §6.1 の 4）

### 1.8 cnidaria の手順書のスクリプト

段 C の手順書 §1.4 と同じ（`verify-nodes.sh`、`netcheck.sh`、`check-apps.sh`）。`netcheck.sh` は一時的な DaemonSet を作るので ✋。

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 順序 | `install kubernetes --node 192.168.1.111` → rollout の完了 → control-plane の `install kubelet --node` を 1 台ずつ（.113 → .112 → .111）→ worker を 1 台ずつ | 計画 §6.2 |
| 2 | etcd のリーダー | `install kubelet` の前に、対象がリーダーなら `move-leader` で別のメンバーへ移す | 計画 §6.2、dev の記録 |
| 3 | drain、cordon | **どちらもしない**（control-plane も worker も） | 計画 §9.3、dev の記録（Pod の再起動 0） |
| 4 | worker の順 | Longhorn の replica 1 のボリュームが少ない順、oeilvert は最後（§5.1） | 計画 §6.2 |
| 5 | ノードの再起動 | **しない** | dev の記録 |
| 6 | 停止時間 | いつでもよい。braque も Pod が止まらない見込みなので時間帯を問わない（§5.1） | 計画 §9.6 |
| 7 | 段 1 の後 | 健全性を確かめてから段 2 へ（間隔は必須ではない） | 計画 §9.6 |

### 2.2 クラスタ全体のベースライン

作業の当日、`install kubernetes` の前に次を取り、`results/stage-1/baseline.md` に残す（すべて読み取り）。計画 §6.5 の項目と、段 C の手順書 §2.3 と同じもの。1 台ごとの確認は、このベースラインと比べる。

1. `kubectl --context fraction get nodes -o wide`、`kubectl --context fraction version`: 8 台 Ready、全台 v1.29.8、`containerd://2.3.x`
2. 8 台の `ls -l /opt/bin/kubelet /opt/bin/kubectl /opt/bin/etcdctl /opt/bin/crictl`（向き先が 1.29 の版。etcdctl は control-plane だけ）、`ls /opt/cni/bin/.porkadot-cni-plugins-version`（0.29.x で入れたノードには無い。§8.4）、`systemctl is-active kubelet`
3. control-plane の 3 台の `sudo stat -c '%a %U:%G %n' /etc/etcd/pki/*`（2026-10-18 は .111 で 3 つとも `644 root:root`）
4. `etcdctl endpoint status --cluster -w table`、`etcdctl endpoint health --cluster -w table`: 3/3 healthy、リーダー、raft index、版が 3.5.12。VIP の `https://192.168.1.101:6443/readyz` が `ok`
5. Running / Completed 以外の Pod の一覧。再起動回数の多い Pod
6. Longhorn: `volumes.longhorn.io`（state、robustness、replica 数、アタッチ先）、`replicas.longhorn.io`（ノードと state）、`instancemanagers`、`engineimages`、`nodes.longhorn.io`。更新前から healthy でないもの（`myao/myao`、`homegallery/cg-data` の detached）を記録する
7. cnidaria: `verify-nodes.sh`、`check-apps.sh` の結果。`hedgedoc/db-postgresql` の NetworkPolicy がノードの nftables に入っていること。8 台の cnidaria の Pod のログの error の数（§8.1 で比べる）
8. MetalLB: LoadBalancer の Service がアドレスを持ち、応答する（gated の 192.168.1.200 / `::200`、`h2-sshd`、`natsumi-sshd`、minecraft）
9. NFS: braque の NFS を使う PV と Pod が Running、oeilvert のホストの `/home/yuanying/shared/nfs` が読める
10. `kubectl --context fraction top nodes` が応答する。Prometheus の `apiserver_requested_deprecated_apis`
11. controller-manager と scheduler の Pod の置き場所（段 C の手順書 §2.3 の 11 のコマンド）
12. `kubectl --context fraction get csr`（§6 で、段の間に新しい CSR が出ていないことを見る）
13. kube-system の Deployment と DaemonSet の generation と image（§3.3 で rollout を確かめるため）

    ```sh
    kubectl --context fraction -n kube-system get deploy,ds \
      -o custom-columns=KIND:.kind,NAME:.metadata.name,GEN:.metadata.generation,IMAGE:.spec.template.spec.containers[0].image
    ```

### 2.3 VIP と LoadBalancer を 1 秒ごとに見る

段 C の手順書 §2.4 と同じ監視を、§3.2 の `install kubernetes` から最後の worker の確認まで流しておく（ログは `./stage-1-probe.log`）。dev では段 1 の間、一度も失敗しなかった。失敗があれば時刻を各台の記録に写す。

### 2.4 etcd のバックアップ ✋

`install kubernetes` の前に、porkadot 0.30.0 で取る（計画 §6.1 の 5）。ノードの上でスナップショットを作って手元に写すだけで、クラスタの状態は変えない。

```sh
porkadot etcd backup
ls -l ./backup/
```

- 0.30.0 の `etcd backup` は、最初の etcd のメンバー（192.168.1.111）で root として `etcdctl snapshot save` を流し、スナップショットを接続ユーザーに chown して chmod 0600 にしてから手元に写し、ノードのものを消す（porkadot#25）。0.29.2 の `etcd backup` は root で流さないので失敗する（dev の記録の `verification-1.30.md` の結論の 1）
- 手元のファイルは `./backup/etcd-<日時>.db`、モード 0600。**`./backup/` は `.gitignore` で除外してある `assets/` の外の場所**で、これまでのバックアップもここにある（`docs/cp-replacement/runbook.md` §2.2）。スナップショットには Secret が平文で入っているので、`git add -f` などで追加しない
- メンバーを指定するときは `porkadot etcd backup --node 192.168.1.112`（`porkadot.yaml` の `nodes` のキー）
- 時刻、ファイル名、サイズ、sha256 を記録する。dev では 20〜23 MB だった。本番のサイズは前のバックアップ（`./backup/` の中）と比べ、桁が違えば止める
- 段 1 が終わるまで消さない。必要なら作業端末の外（暗号化したストレージ）にも写す

### 2.5 render の差分（この手順書と同じ PR）

計画 §6.1 の 6〜7。2026-10-18 に、porkadot 0.30.0（`7d607a7`）で `render kubelet` / `render etcd` / `render bootstrap` / `render kubernetes` を流した（`render all` と `render certs` は使っていない）。同じ PR で `porkadot.yaml` から `etcd.extra_env` の `ETCD_UNSUPPORTED_ARCH=arm64` を消した（計画 §10。`etcd:` の節はほかに設定が無いので節ごと消した）。
secrets は §1.6 のとおり本番と一致していることを確かめてから使った。

前の render は porkadot `7f53e40`（0.29.1 より前の master）で、`a03cf9b` のもの。差分は次のとおりで、**これ以外の差分は無い**。

| ファイル | 変わったもの | 由来 |
|---|---|---|
| `kubernetes/manifests/kube-apiserver.yaml`・`kube-controller-manager.yaml`・`kube-scheduler.yaml`・`kube-proxy.yaml` | イメージ v1.29.8 → v1.30.14、`app.kubernetes.io/version` のラベル | K8s の版（porkadot#23） |
| `kubernetes/manifests/kube-apiserver.secrets.yaml`・`kube-controller-manager.secrets.yaml`（sops） | Secret の `app.kubernetes.io/version` のラベルだけ。data は同じ（復号して鍵ごとのハッシュで比べた） | 同上 |
| `kubernetes/manifests/porkadot.yaml` | Service `porkadot-kubernetes-latest` の selector の `app.kubernetes.io/version` | 同上 |
| `bootstrap/manifests/*.bootstrap.yaml`（4 つ） | イメージ v1.29.8 → v1.30.14、版のラベル | 同上（段 1 では使わない） |
| `kubernetes/manifests/addons/coredns/coredns.yaml` | CoreDNS v1.10.1 → v1.11.3 | 同上 |
| `kubelet/192.168.1.11{1,2,3}/addons/etcd/etcd-server.yaml` | etcd 3.5.12-0 → 3.5.34-0。`ETCD_UNSUPPORTED_ARCH` の env が消え、`env:` が空になる（dev と同じ形） | porkadot#23、`porkadot.yaml` の変更 |
| `kubelet/192.168.1.11{1,2,3}/addons/etcd/install.sh` | 証明書と鍵を `cp` から `install -m 0600 -o root -g root` に | porkadot#25 |
| `kubelet-default/install-deps.sh` | kubelet・kubectl v1.29.8 → v1.30.14、etcdctl 3.5.12 → 3.5.34、crictl v1.28.0 → v1.30.1。`<名前>-<版>` が無いときだけ落とし、`/opt/bin/<名前>` の向き先が違えば張り替える。CNI plugins は版の印で判定、`curl -fL`、`--force` | porkadot#23、#26 |
| `kubelet-default/setup-containerd.sh` | containerd の config version 4 に対応（2.3 以上かを見る） | porkadot 0.29.2（#21）。前の render が 0.29.2 より前だったため。**段 1 では流さない**（`install kubelet` は置くだけで実行しない。計画 §5.4） |
| `kubelet/<8 台>/bootstrap.crt`、`bootstrap/kubelet/bootstrap.crt` | 作り直し（同じ鍵、同じ CA、同じ subject。期限が 2027-10-18 に延びる） | render のたびに作り直される（dev の記録の結論の 6） |
| `kubelet/192.168.1.11{1,2,3}/addons/etcd/etcd.crt`（sops） | 同上（同じ鍵、同じ etcd の CA、同じ SAN） | 同上 |
| `porkadot.yaml` | `etcd.extra_env` の `ETCD_UNSUPPORTED_ARCH` を消した | 計画 §10 |

- `kubelet/<ノード>/config.yaml`・`kubelet.service`・`bootstrap-kubelet.conf`・`metadata.json`、cnidaria・MetalLB・kubelet-serving-cert-approver のマニフェスト、CNI plugins の版（v1.4.1）は変わらない
- Deployment と DaemonSet の `spec.selector` には `app.kubernetes.io/version` が入っていない（selector は変えられないので、入っていれば apply が失敗する。dev の記録）
- `ETCD_UNSUPPORTED_ARCH` は、etcd 3.5.12 でも 3.5.34 でも、arm64 では読まれない（etcd の `checkSupportArch` は amd64・arm64・ppc64le・s390x をそのまま通し、env を消してから進む）。消しても起動は変わらず、戻しで残っていても害は無い
- 作り直した証明書は、作業の当日に render し直すとまた変わる。**当日は render しない**。この PR の `assets/` で流す

✋✋ **段 1 の開始の承認を取る。** この表と PR の差分、§2.2 のベースライン、§2.4 のバックアップを示す。承認を得て PR をマージし、マージした master で §3 に入る。

## 3. control-plane のマニフェストを上げる（`install kubernetes`）

### 3.1 事前確認

- §2.2 のベースラインと §2.4 のバックアップが済んでいる。§2.3 の監視が動いている
- 全台 Ready、etcd 3/3 healthy、VIP の `/readyz` が `ok`
- このリポジトリの checkout が §2.5 の PR をマージした master で、`git status --short assets porkadot.yaml` が空（§1.4）

### 3.2 流す ✋

```sh
porkadot install kubernetes --node 192.168.1.111
```

- bootstrap ノード（pablo）は worker なので、`--node` で control-plane を指す（計画 §6.2 の 1）
- apiserver（DaemonSet）、controller-manager、scheduler、kube-proxy、CoreDNS が新しい版で rollout する。cnidaria、MetalLB、kubelet-serving-cert-approver はマニフェストが変わらないので動かない
- kube-proxy は kubelet より 3 マイナーまで新しくてよいので、ここで先に上がってよい（計画 §6.2）
- 時刻と rc を記録する。dev では `install kubernetes` から rollout の完了まで 2 分 42 秒だった

### 3.3 rollout の完了を確かめる

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
| 1 | `kubectl --context fraction version` | Server が v1.30.14 |
| 2 | §2.2 の 13 のコマンド | apiserver・KCM・scheduler・kube-proxy が v1.30.14、CoreDNS が v1.11.3。それ以外（cnidaria、MetalLB など）の generation と image がベースラインと同じ |
| 3 | apiserver | `kube-apiserver` の Pod が 3/3 Ready。VIP の `/readyz` が `ok`、`/version` が v1.30.14 |
| 4 | KCM と scheduler | 2/2 Ready。置き場所を記録する（別々の master に 1 つずつが望ましい。同じ master に寄っていても段 1 では直さない） |
| 5 | kube-proxy | 8 台で Running。ログに `Using iptables Proxier` |
| 6 | CoreDNS | Running。どこかのノードの Pod から名前が引ける（`check-apps.sh`） |
| 7 | Node | 8 台 Ready。kubelet は v1.29.8 のまま（apiserver 1.30 と kubelet 1.29 の組み合わせは skew policy の範囲） |
| 8 | Pod | Running / Completed 以外がベースラインから増えていない。rollout で入れ替わった Pod のほかに再起動が増えていない |
| 9 | Longhorn | ボリュームの state と robustness がベースラインと同じ |
| 10 | §2.3 の監視 | 失敗が無い（dev では apiserver の rollout の間も VIP は途切れなかった） |
| 11 | warning | `kubectl --context fraction get events -A --field-selector type=Warning` に、rollout の古い Pod の readiness の失敗のほかに新しいものが無い |

ここで問題があれば、kubelet にまだ触っていないので、§7.2 で control-plane だけを戻せる。

## 4. control-plane の kubelet と etcd を上げる（192.168.1.113 → .112 → .111）

### 4.1 何が起きるか

`install kubelet --node <IP>` は、`install-deps.sh`（kubelet・kubectl・etcdctl・crictl と CNI plugins）、`install-pkgs.sh`、`install.sh` を root で流す。

- kubelet が v1.30.14 で再起動する。dev では、バイナリを落とす初回で 40 秒ほど、その後 Ready で新しい版を報告するまで数秒
- `install.sh` は kubelet の addon も入れる。本番の addon は `dns`（`cluster-dns.service`）、`multipathd`、control-plane では `etcd`
  - `etcd` の addon: `/etc/etcd/pki` の証明書と鍵を root 0600 で置き直し（§8.5）、`etcd-server.yaml` を置く。**etcd の static Pod が 3.5.34 のイメージで作り直される**。証明書は作り直したもの（同じ鍵、同じ CA）に替わる
  - `dns` の addon: `systemd-networkd` を再起動する。そのたびに、**全ノードの cnidaria が v6 の経路の入れ直しで `Reconciler error ... no route` を 7〜10 件出し、1 秒ほどで収まる**（§8.1）
- 0.29.x で入れたノードには CNI plugins の版の印が無いので、0.30.0 での最初の `install kubelet` で CNI plugins を 1 回落とし直す（§8.4）
- dev では、control-plane の `install kubelet` で入れ替わった Pod は etcd の static Pod だけだった（新しい UID）。apiserver、cnidaria、kube-proxy、speaker、KCM、scheduler はそのまま
- drain も cordon もしない（§2.1）

### 4.2 1 台の手順

1. 読み取りの確認。
   - `etcdctl endpoint status --cluster -w table`、`etcdctl endpoint health --cluster -w table`: 3/3 healthy、raft index がそろっている。**リーダーがどれか**
   - 対象のノードの Pod の名前・UID・再起動回数を控える（§4.3 で比べる）。

     ```sh
     kubectl --context fraction get pods -A -o wide --field-selector spec.nodeName=<IP> --no-headers \
       -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,UID:.metadata.uid,RESTARTS:.status.containerStatuses[*].restartCount
     ```

   - ノードで `ls -l /opt/bin/{kubelet,kubectl,etcdctl,crictl}`、`sudo stat -c '%a %U:%G %n' /etc/etcd/pki/*`
   - 8 台の cnidaria の Pod のログの error の数（§8.1 で、この台の作業で増えた数を数える）
2. ✋ 対象が etcd のリーダーなら、リーダーを移す（段 C の手順書 §5.2 の 4 と同じ形。dev の .113・.111 でも通した）。

   ```sh
   # 1 の endpoint status で、リーダー（= 対象）のエンドポイントと、移す先の ID（16 進）を見る
   ssh ubuntu@<対象の IP> 'sudo bash -c ". /etc/etcd/etcd.env && unset ETCDCTL_ENDPOINTS && /opt/bin/etcdctl --endpoints=https://<対象の IP>:2379 move-leader <移す先の ID>"'
   etcdctl endpoint status --cluster -w table   # リーダーが移ったこと
   ```

   - 移す先は、すでに上げ終えたメンバーか、まだ上げていないメンバーのうち最後に作業するもの（.113 の作業なら .111、.111 の作業なら .113 か .112）。dev では .113 のリーダーを .111 へ、最後に .111 のリーダーを .112 へ移した
   - 移せなかったときは止める（`install kubelet` で etcd の Pod が作り直されると、選挙の分だけ書き込みが止まる）
3. ✋ 流す。

   ```sh
   porkadot install kubelet --node <IP>
   ```

   時刻（開始と終わり）と rc を記録する。
4. §4.3 の確認。

### 4.3 1 台ごとの確認と、次の 1 台へ進む条件

| # | 確認 | 方法 | 合格基準 |
|---|---|---|---|
| 1 | Node | `kubectl --context fraction get node <IP> -o wide` | Ready、VERSION が v1.30.14、CONTAINER-RUNTIME が段 C の版のまま |
| 2 | バイナリ | ノードで `ls -l /opt/bin/{kubelet,kubectl,etcdctl,crictl}`、`/opt/bin/kubelet --version`、`cat /opt/cni/bin/.porkadot-cni-plugins-version` | 向き先が `kubelet-v1.30.14`、`kubectl-v1.30.14`、`etcdctl-3.5.34`、`crictl-v1.30.1`。CNI の印が `v1.4.1`。前の版のファイル（`kubelet-v1.29.8` など）も残っている（§7 の戻しで使う） |
| 3 | etcd の pki | `sudo stat -c '%a %U:%G %n' /etc/etcd/pki/*` | 3 つとも `600 root:root` |
| 4 | etcd | `etcdctl endpoint status --cluster -w table`、`etcdctl endpoint health --cluster -w table` | 3/3 healthy、リーダーが居る、raft index がそろう。対象のメンバーの版が 3.5.34（ほかは 3.5.12 のままでよい。混在は dev で確かめた） |
| 5 | etcd の Pod | `kubectl --context fraction -n kube-system get pod etcd-<IP> -o wide`、`kubectl --context fraction -n kube-system logs etcd-<IP> \| grep -iE 'unsupported\|error' \| tail` | 1/1 Running、イメージが `etcd:3.5.34-0`。`unsupported architecture` のログが無い |
| 6 | apiserver | 対象のノードの `kube-apiserver` の Pod | 1/1 Ready。UID と再起動回数が 4.2 の 1 で控えたものと同じ（dev では再起動しなかった）。VIP の `/readyz` が `ok` |
| 7 | Pod の再起動 | 4.2 の 1 と同じコマンド | etcd の Pod のほかは、名前・UID・再起動回数が同じ |
| 8 | cnidaria | 全ノードの cnidaria の Pod が Ready。`verify-nodes.sh` | 全 PASS。ログの error の増え方は §8.1 のとおり（`no route` が 7〜10 件、1 秒ほどの間） |
| 9 | KCM と scheduler | `kubectl --context fraction -n kube-system get pods -o wide -l 'app.kubernetes.io/component in (kube-controller-manager,kube-scheduler)'` | 2/2 ずつ Ready |
| 10 | kubelet のログ | ノードで `sudo journalctl -u kubelet --since '-10min' --no-pager \| grep -iE 'error\|fail' \| tail` | 起動の直後の `InvalidDiskCapacity`（§8.6）のほかに、続くエラーが無い |
| 11 | §2.3 の監視 | — | 失敗が無い |

次のすべてを満たしてから、次の 1 台に入る。

- 上の 1〜11 がすべて合格
- 全 8 台の Node が Ready
- etcd 3/3 healthy、raft index がそろっている
- Running / Completed 以外の Pod がベースラインから増えていない

### 4.4 3 台を終えたら

- etcd の全メンバーが 3.5.34。3/3 healthy、raft index がそろう
- 3 台の `/etc/etcd/pki` が root 0600
- control-plane の 3 台が v1.30.14 で Ready

etcd の全メンバーが 3.5.34 になっても、パッチ更新なので前のイメージ（3.5.12）に戻せる（§7.3）。

## 5. worker の kubelet を上げる（1 台ずつ）

### 5.1 順番

replica 1 のボリューム（最後の replica）の置き場所を、作業の当日に読み直して決める（段 C の手順書 §2.6 のコマンド）。2026-10-18 の読み取り（段 C の chirico の作業の後）では次のとおりで、段 C の手順書の表から変わっている。

| 順 | ノード | replica 1 のボリューム | replica の数 | 理由 |
|---|---|---|---|---|
| 1 | pablo | なし | 2 | 手順の確かめに向く。porkadot の bootstrap ノード（段 1 では bootstrap を使わない） |
| 2 | duchamp | なし | 13 | 冷却ファンが故障中（ターボ停止運用）。再起動はしないので影響は小さい |
| 3 | braque | なし（Longhorn のノードではない） | 0 | NFS と `registry.fraction.jp` の保存先。他の worker が健全な状態で行う（計画 §6.2） |
| 4 | chirico | `prometheus-...-0` | 13 | |
| 5 | oeilvert | `prometheus-...-1`、`export-minio-0`〜`3` | 17 | 最後の replica が最も多い。worker の最後にする（計画 §6.2） |

- 当日の読み取りで replica 1 の置き場所が変わっていれば、少ない順に並べ直す。oeilvert は最後のままにする
- drain しないので、replica 1 のボリュームも止まらない見込み（dev では、Longhorn のボリュームを使う Pod も instance-manager も再起動しなかった）。止まった場合は §5.3 で止める
- braque: kubelet の再起動で Pod は止まらない見込みなので、段 C の手順書 §2.5 の時間帯（NFS を使うバックアップの CronJob）を避ける必要は無い。念のため、CronJob の時刻（JST 05:15〜06:45、14:30〜15:00、16:45〜17:05、17:55〜18:15）を外して始める

### 5.2 1 台の手順

1. 読み取りの確認。
   - `kubectl --context fraction get node <ノード> -o wide`: Ready、v1.29.8
   - 対象のノードの Pod の名前・UID・再起動回数を控える（§4.2 の 1 のコマンド。`spec.nodeName=<ノード>`）
   - Longhorn: 対象のノードの replica とアタッチされたボリューム。degraded のボリュームが無い（ベースラインのものを除く）
   - ノードで `ls -l /opt/bin/{kubelet,kubectl,crictl}`
2. ✋ 流す。

   ```sh
   porkadot install kubelet --node <ノード>
   ```

   - `<ノード>` は `porkadot.yaml` の `nodes` のキー（`pablo`、`duchamp`、`braque`、`chirico`、`oeilvert`）
   - 時刻（開始と終わり）と rc を記録する。dev では 1 台 20〜30 秒だった
3. §5.3 の確認。

### 5.3 1 台ごとの確認と、次の 1 台へ進む条件

| # | 確認 | 方法 | 合格基準 |
|---|---|---|---|
| 1 | Node | `kubectl --context fraction get node <ノード> -o wide` | Ready、VERSION が v1.30.14 |
| 2 | バイナリ | ノードで `ls -l /opt/bin/{kubelet,kubectl,crictl}`、`cat /opt/cni/bin/.porkadot-cni-plugins-version` | 向き先が `kubelet-v1.30.14`、`kubectl-v1.30.14`、`crictl-v1.30.1`。CNI の印が `v1.4.1`。etcdctl も落ちてくるが worker では使わない |
| 3 | Pod の再起動 | §5.2 の 1 と同じコマンド | **名前・UID・再起動回数がすべて同じ**（dev では再起動 0）。増えていれば止めて調べる |
| 4 | Longhorn | 対象のノードの replica が running、ボリュームの state と robustness が §5.2 の 1 と同じ。`instancemanagers` の対象のノードのものが running で、作り直されていない | 同じ |
| 5 | cnidaria | 全ノードの cnidaria の Pod が Ready。`verify-nodes.sh` | 全 PASS。ログの error は §8.1 のとおり |
| 6 | MetalLB | 対象のノードの speaker が Running（2026-10-18 は chirico、duchamp、oeilvert、pablo と control-plane の 3 台に載る。braque には無い） | 再起動回数が同じ |
| 7 | kubelet のログ | ノードで `sudo journalctl -u kubelet --since '-10min' --no-pager \| grep -iE 'error\|fail' \| tail` | 起動の直後の `InvalidDiskCapacity` のほかに、続くエラーが無い |
| 8 | §2.3 の監視 | — | 失敗が無い |

ノードごとの追加の確認:

- **braque**: nfsd が動き、NFS の PV を使う Pod が Running。oeilvert のホストの `/home/yuanying/shared/nfs` が読める。`registry.fraction.jp` が応答する
- **oeilvert**: MinIO の 4 つの Pod と prometheus の Pod が Running で、ボリュームが healthy。devbox（`mosh.fraction.jp`）は Docker で動いていて kubelet と関係ないが、`docker ps` に devbox があることを見る
- **pablo**: share-manager、fs の h2、`docker/registry` が Running（Pod が載っていれば）

次のすべてを満たしてから、次の 1 台に入る。

- 上の 1〜8 とノードごとの確認がすべて合格
- 全 8 台の Node が Ready。終えたノードが v1.30.14、まだのノードが v1.29.8
- etcd 3/3 healthy、VIP が応答する
- Running / Completed 以外の Pod がベースラインから増えていない
- Longhorn のボリュームが healthy（ベースラインのものを除く）

## 6. 段 1 の完了の確認

8 台を終えたら、計画 §6.3 の項目がすべて成り立つことを確かめ、`results/stage-1/summary.md` に残す。

- `kubectl --context fraction get nodes -o wide` で 8 台が Ready、全台 v1.30.14、CONTAINER-RUNTIME が段 C の版
- etcd 3/3 healthy、全メンバーが 3.5.34、リーダーが居る、raft index がそろう。3 台の `/etc/etcd/pki` が root 0600
- VIP の `/livez` が `ok`、`/version` が v1.30.14
- apiserver 3/3、controller-manager と scheduler が 2/2（置き場所を記録する）。kube-proxy が 8/8 で iptables
- CoreDNS が v1.11.3 で Running
- Running / Completed 以外の Pod が無い（ベースラインのものを除く）
- Longhorn: attached のボリュームが全部 healthy（detached の 2 つはベースラインのとおり）、instance-manager が全部 running、engine image は v1.11.2 のまま。K8s 1.30 は Longhorn 1.11 の要件（1.25 以上）に入る
- cnidaria: 8 台の Pod が Ready、`verify-nodes.sh` が全 PASS、✋ `netcheck.sh` が全 PASS、`hedgedoc/db-postgresql` の NetworkPolicy がノードの nftables に入っている
- MetalLB: LoadBalancer の Service が応答する（gated、`h2-sshd`、`natsumi-sshd`、minecraft）
- braque の NFS が応答する
- `kubectl --context fraction top nodes` が応答し、Prometheus のスクレイプが落ちていない。`apiserver_requested_deprecated_apis` を記録する（段 2 以降で消える API が増えていないか）
- `kubectl --context fraction get csr` に、段の間に出た新しい CSR が無い（dev では kubelet の証明書を持ち越し、新しい CSR は出なかった）。出ていれば Approved,Issued であること
- 新しい warning のイベント・ログ（kubelet、apiserver、kube-proxy、cnidaria、etcd）が増えていない（§8 のものは除く）
- §2.3 の監視の FAIL を集計する（dev では 0）

## 7. ロールバック

**戻すのは runbook から外れる操作なので、その都度ユーザーの承認を取る。** 戻すと決める目安:

- `install kubernetes` の後、apiserver・KCM・scheduler・kube-proxy・CoreDNS の rollout が終わらない、VIP が 1 分を超えて応答しない
- `install kubelet` の後、Node が 5 分たっても Ready にならない、kubelet が起動しない
- etcd が 2/3 を下回る、対象のメンバーが 5 分たっても healthy に戻らない、raft index が追いつかない
- Pod の再起動が続く、Longhorn のボリュームが degraded のまま戻らない
- 1.30 に固有と見られる問題が出る

### 7.1 戻すための材料

前の版は、**この PR の前の master（`8fbd1b4`）の `assets/` と `porkadot.yaml`** を使う。この `assets/` は porkadot `7f53e40`（0.29.x）で render したもので、本番は今これで動いている。

- **porkadot は 0.29.2 を使う**（`v0.29.2` の checkout。前の版の assets を前の版の porkadot で流す）。dev の記録（`verification-1.30.md` の「ロールバック」）は、この組み合わせで .113 を戻した
- 0.29.2 の `install kubelet` は、`/opt/bin/kubelet-<版>` のファイルがあると `install-deps.sh` を飛ばす。前の版のバイナリ（`kubelet-v1.29.8` など）はノードに残っているので、**0.29.2 で戻すときは `--force` を付ける**（付けないと etcd の static Pod だけが戻り、kubelet は v1.30.14 のまま。dev の記録の結論の 2）
- 0.30.0 の `install kubelet` は `--force` なしで前の版へ戻せる（porkadot#26）。ただし dev でこれを確かめたのは、0.30.0 で古い版を指定して render し直した assets でのこと（`verification-0.30-rc.md`）。この PR の前の assets（古い `install-deps.sh`）と 0.30.0 の組み合わせは確かめていないので、使わない

用意の仕方（作業端末で。ノードには触らない）:

```sh
# 前の版の porkadot
git -C /home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot worktree add /tmp/porkadot-0.29.2 v0.29.2
P_OLD=/tmp/porkadot-0.29.2
# 前の版の assets と porkadot.yaml（このリポジトリの PR の前の master）
git -C ~/src/github.com/yuanying/k8s-manifests-fraction worktree add /tmp/fraction-stage-0 8fbd1b4
cd /tmp/fraction-stage-0
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot <サブコマンド> --config ./porkadot.yaml
```

- `bundle install` が要ることがある（0.29.2 の Gemfile.lock）。始める前に `grep VERSION $P_OLD/lib/porkadot/version.rb` が 0.29.2 で、`BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot help` が動くことを確かめておく
- secrets は前の版も同じ（sops の同じ鍵。§1.6）
- 前の版の `porkadot.yaml` には `ETCD_UNSUPPORTED_ARCH` が残っているが、害は無い（§2.5）

### 7.2 `install kubernetes` の後、kubelet はまだ前の版 ✋

```sh
cd /tmp/fraction-stage-0
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubernetes --node 192.168.1.111 --config ./porkadot.yaml
```

- apiserver・KCM・scheduler・kube-proxy・CoreDNS が v1.29.8・v1.10.1 に戻る。etcd はまだ変わっていない
- **dev では確かめていない**（dev の戻しは kubelet と etcd だけ）。§3.3 と同じ確認を、版を読み替えて行う
- apiserver を前のマイナーへ戻すと、新しい版で書かれた storage の版があると読めなくなる恐れがある（計画 §6.4）。組み込みの資源の storage の版が 1.30 で変わるかは、この手順書では一つずつ確かめていない。確かめたのは次の 1 つだけ：1.30 で GA になり既定で有効になる ValidatingAdmissionPolicy（`admissionregistration.k8s.io/v1`）は、1.29 の本番では提供されていない（2026-10-18 に `kubectl api-resources` で確かめた。オブジェクトが無い）。**段 1 の間に ValidatingAdmissionPolicy を作らない**。戻すのは、上げてから間もなく問題が出たときに限る

### 7.3 kubelet と etcd を戻す（1 台） ✋

control-plane でも worker でも、戻す台に前の版の assets で `install kubelet --node` を流す。

```sh
cd /tmp/fraction-stage-0
BUNDLE_GEMFILE=$P_OLD/Gemfile bundle exec $P_OLD/exe/porkadot install kubelet --node <ノード> --force --config ./porkadot.yaml
```

- `--force` で kubelet・kubectl・etcdctl・crictl を落とし直し、`/opt/bin` の向き先が 1.29 の版（`kubelet-v1.29.8`、`kubectl-v1.29.8`、`etcdctl-3.5.12`、`crictl-v1.28.0`）になる。確かめる
- control-plane では etcd の static Pod が 3.5.12 に戻る。**新しい etcd の Pod が、古い Pod の 2380 番と重なって 1〜2 回落ちてから起動する**（`bind: address already in use`、数秒。§8.3）。戻した後は、etcd が 3/3 healthy に戻り、raft index が追いつくのを待つ
- 戻す台が etcd のリーダーなら、先に §4.2 の 2 でリーダーを移す
- etcd の全メンバーが 3.5.34 になった後でも、パッチ更新なので 3.5.12 に戻せる（計画 §6.4。etcd のマイナー更新を含む段 5・段 8 とは違う）。dev では 3.5.12 と 3.5.34 の混在で 3/3 healthy だった
- **`/etc/etcd/pki` は 0600 のまま残る。** 前の版の `install.sh` は `cp` なので、すでにあるファイルのモードを変えない。etcdctl は sudo で流しているので困らない
- **0.29.2 の `porkadot etcd backup` は、pki が 0600 になったノードでは `permission denied` で失敗する**（dev の記録の結論の 1）。戻した後にバックアップを取るときは、0.30.0 の `etcd backup` を使うか、ノードで `sudo bash -c '. /etc/etcd/etcd.env && /opt/bin/etcdctl snapshot save /root/<ファイル>'` を流して手元に写す
- CNI plugins の版の印（`/opt/cni/bin/.porkadot-cni-plugins-version`）は残るが、0.29.2 は読まないので害は無い
- 戻した台では、dev と同じく etcd の Pod のほかに再起動した Pod が無いことを確かめる（dev では無かった）

### 7.4 段 1 全体をやめる

kubelet は kube-apiserver より新しくてはいけないので、**kubelet を先に戻し、control-plane を最後に戻す。**

1. worker を、上げた順の逆に §7.3 で戻す
2. control-plane の kubelet と etcd を、上げた順の逆（.111 → .112 → .113）に §7.3 で戻す
3. §7.2 で control-plane のマニフェストを戻す

戻し終えたら、§6 の確認を版を読み替えて行い、`results/stage-1/` に戻した経緯を残す。etcd の backup（§2.4）からの restore は、etcd が壊れた場合の最後の手段で、バックアップ後の変更が失われる。restore は `docs/cp-replacement/runbook.md` の etcd の扱いと porkadot の手順書を見て、その時点でユーザーと決める。

## 8. 既知の問題と注意

### 8.1 `install kubelet` のたびの cnidaria の `no route`

`install kubelet` の kubelet の addon `dns` は `systemd-networkd` を再起動する。そのたびに、全ノードの cnidaria（v0.1.1）が v6 の経路を入れ直そうとして `Reconciler error ... no route` を 7〜10 件出し、1 秒ほどで収まる（dev の記録の結論の 5。前のタスクでも同じだった）。
想定内のログとして扱う。1 秒を超えて続く、ほかの error が出る、`verify-nodes.sh` が FAIL する、のどれかなら止める。

### 8.2 render が証明書を作り直す

`render kubelet` は各ノードの `bootstrap.crt` を、`render etcd` は master の `addons/etcd/etcd.crt` を作り直す（同じ鍵、同じ CA で署名し直す。dev の記録の結論の 6）。差分には出るが使える。

- `bootstrap.crt` は kubelet の TLS bootstrap にだけ使う。既存のノードは手持ちのクライアント証明書を使い続けるので、影響しない
- `etcd.crt` は `install kubelet` で `/etc/etcd/pki/etcd.crt` に置かれ、作り直された etcd の Pod が読む。鍵と CA は同じなので、ほかのメンバーとの peer の TLS も、apiserver からの接続も変わらない（dev でも混在の間 3/3 healthy だった）
- 作業の当日に render し直さない（§2.5）

### 8.3 戻しの etcd の 2380 番の重なり

戻すとき（3.5.34 → 3.5.12）、新しい etcd の Pod が古い Pod の 2380 番と重なって 1〜2 回落ちてから起動した（dev の記録の結論の 7、`verification-0.30-rc.md` の 5）。上げる向きでは起きていない。数秒で起動するので、戻した後は etcd が全メンバー healthy に戻るのを待つ。

### 8.4 0.30.0 の最初の `install kubelet` での CNI plugins の落とし直し

porkadot#26 は、CNI plugins の版を `/opt/cni/bin/.porkadot-cni-plugins-version` に記録して、同じ版なら落とさない。0.29.x で入れたノードには印が無いので、0.30.0 での最初の `install kubelet` で CNI plugins（v1.4.1、同じ版）を 1 回だけ落とし直し、`/opt/cni/bin` に上書きで展開する。dev では 2〜3 秒で、Pod に影響は無かった。2 回目からは飛ばす。

### 8.5 `/etc/etcd/pki` が root 0600 になる

本番の control-plane の `/etc/etcd/pki` は、今は root 0644 である（2026-10-18 に .111 で `ca.crt`、`etcd.crt`、`etcd.key` の 3 つとも 644 を確かめた。鍵が誰からでも読める）。
0.30.0 の etcd の `install.sh` は、証明書と鍵を `install -m 0600 -o root -g root` で置くので、`install kubelet` の後は root 0600 になる（porkadot#25。dev では 0644 にしておいた .113 が 0600 に戻り、etcd の Pod は再起動しなかった）。

- `/etc/etcd/pki` を hostPath で使う Pod は etcd の static Pod だけである（2026-10-18 に全 Pod の hostPath を読んで確かめた）。etcd は root で動く
- apiserver は etcd のクライアント証明書を Secret `etcd-tls` から読むので、影響しない
- ノードで etcdctl を使うときは sudo が要る（この手順では初めから sudo で流す。§1.5）

### 8.6 kubelet の再起動の直後の `InvalidDiskCapacity`

kubelet の再起動のたびに `invalid capacity 0 on image filesystem` の warning のイベントが出る（dev。起動の直後だけ）。想定内。

### 8.7 porkadot を流す場所

§1.4 のとおり、cwd はこのリポジトリのルートにする。porkadot のディレクトリで流すと、そこにある `assets/` を使ってしまう。`porkadot-dev/porkadot` には古い `assets/secrets` があるので `Legacy secrets layout found` で止まるが、止まらない checkout では別のクラスタの assets を使うことになる。

### 8.8 全台が止まったとき

全台を同時に止めて起動すると、クラスタは自力で戻らない（dev の記録。static Pod の etcd しか動かず、apiserver の DaemonSet も VIP を広告する MetalLB も起動できない）。段 1 ではノードを再起動しないので当たらない。起きたときは porkadot の `skills/porkadot/references/troubleshooting.md` の「クラスター再起動後に MetalLB が起動しない」に従う（0.30.0 の `install bootstrap cleanup` は、master の apiserver が EndpointSlice で ready になるのを待ってから bootstrap を消す。porkadot#24）。

## 9. 記録

`results/stage-1/` に、ベースライン（`baseline.md`）、`install kubernetes`（`control-plane.md`）、各台（`<ノード>.md`。control-plane は `192.168.1.11N.md`）、全体のまとめ（`summary.md`）を残す。
段 C の `results/stage-c/` と同じく、時刻（UTC）、読み取りの結果、実行したコマンドと出力の要点、手順書との差を書く。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（同じ PR か、記録の PR で）。
