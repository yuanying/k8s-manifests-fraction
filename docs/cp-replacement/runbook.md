# control-plane の Raspberry Pi 交換手順書（本番 `fraction`）

本番クラスタ `fraction` の control-plane 3 台（192.168.1.111〜113）を、Raspberry Pi 4 から Raspberry Pi 5 へ 1 台ずつ交換する手順。
方式は **A2「etcd のデータディレクトリを持ち越すローリング交換」** である。IP（.111〜.113）と etcd のメンバー名（node111〜node113）は引き継ぐ。

| | 旧機 | 新機 |
|---|---|---|
| 機体 | Raspberry Pi 4 Model B（4GB）、SD | Raspberry Pi 5（8GB）、NVMe SSD |
| OS | Ubuntu 20.04.6 | Ubuntu 24.04.5（第一候補。E2 の結果で確定） |
| containerd | 1.6.20（Docker の containerd.io） | 2.2 系（Ubuntu の containerd） |
| cgroup | v1 | v2 |
| K8s | v1.29.8 | v1.29.8（このタスクでは上げない） |

方式の選定と根拠は porkadot-dev の `docs/cp-replacement/` にある。

- `method-comparison.md`: A1 / A2 / B1 / B2 の机上比較
- `verification-results.md`: dev クラスタ（E1）と本番の読み取り（E3）での検証結果。この手順書で「V7」などと書くのは、この文書の項目である
- `rehearsal/`: 交換中の影響を測るプローブ

> **E2 の結果待ち**: Raspberry Pi 5 での確認（V1〜V3、A2 の arm64 版）はまだ終わっていない。
> E2 の結果で変わりうる箇所には「**E2 待ち**」と書いた。E2 の結果が出たら、その箇所を更新してから本番に入る。

## 0. 役割と約束ごと

- **物理作業はユーザーが行う。** EEPROM の更新、NVMe への書き込み、cloud-init の配置、機体の電源操作、LAN ケーブルの抜き差し、ルーター（jumelle）の設定。
  オペレーター（人または agent）は手順を示し、ユーザーの完了の報告を待つ。
- **本番への変更系の操作は、1 つずつユーザーの承認を得てから行う。** この手順書では承認を取る箇所に ✋ を付けた。
  読み取りの確認（`kubectl get`、SSH での状態確認）は承認なしで行ってよい。
- 1 台を交換し終えて「次の 1 台へ進む条件」（§3.9）を満たすまで、次の機体に手を付けない。
- 想定外のことが起きたら、その場で止めてユーザーに報告する。ロールバック（§4）は、どの段階にいるかで手順が変わる。

## 1. 前提

### 1.1 porkadot の版

次の 2 つの PR が porkadot の master にマージされていること。マージ後の master のコミットを作業記録に書く。

| PR | 内容 | 要る理由 |
|---|---|---|
| yuanying/porkadot#13 | `setup-containerd` の containerd v1/v2 両対応 | containerd 2.x の config version 3 で `SystemdCgroup = true` を効かせる。containerd.io 同梱 config（`version` 行なし）の扱いも直っている |
| yuanying/porkadot#14 | `porkadot etcd backup/stop/start/restore` の修正 | `--node` が `porkadot.yaml` の接続設定（`user: ubuntu`）で接続する。`etcd stop` の退避先が `/opt/porkadot/etcd-server.yaml` になる |

porkadot の使い方の注意:

- **porkadot は k8s-manifests-fraction のリポジトリルートを cwd にして実行する。** asset の置き場（`local.assets_dir`）の既定値 `./assets` は cwd から解決されるため、
  別のディレクトリで実行すると、本番の `assets/` ではない場所を読み書きする。
  porkadot 本体（`porkadot-dev/porkadot`）の bundle を使うなら、`BUNDLE_GEMFILE` で porkadot の Gemfile を指して `bundle exec <porkadot>/exe/porkadot` を呼ぶ。
  この手順書では、そのコマンドを `porkadot` と書く。
- `--config ./porkadot.yaml` はサブコマンドの**後ろ**に置く（前に置くと Thor が引数を取り違える）。
- porkadot はエラーでも終了コード 0 を返す。**成否は出力を読んで判断する。**
- `--node` には `porkadot.yaml` の `nodes` のキーを渡す。control-plane はキーが IP（`192.168.1.111` など）、bootstrap ノードはキーが `pablo`。

### 1.2 kubeconfig の運用

`porkadot-dev/CLAUDE.md` の「本番クラスタ（fraction）の kubeconfig 運用」に従う。

- 確認は普段どおり `kubectl --context fraction`（`fraction-auditor`、read-only）で行う。
  作業を始める前に `kubectl --context fraction auth can-i delete pods -A` が `no` であることを確かめる。
- 変更（ラベル、Pod や Node の削除）は `infra-admin` の短命トークンで行う。1 台の交換ごとに、作業時間に見合う期限（1〜2 時間）で発行し、終わったら破棄する。

```bash
ADMIN_TOKEN=$(kubectl --context fraction create token infra-admin -n kube-system --duration=2h)
# 変更系: kubectl --context fraction --token="$ADMIN_TOKEN" ...
unset ADMIN_TOKEN
```

- トークンが発行できないとき（SA 署名鍵の不整合など）だけ、緊急用の `~/.kube/fraction-admin.conf` を使う。

以下、変更系のコマンドは `kubectl-admin` と書く（`kubectl --context fraction --token="$ADMIN_TOKEN"` のこと）。

### 1.3 作業端末とアクセス

- 作業端末から control-plane に `ssh ubuntu@192.168.1.11N` で入れること。porkadot（net-ssh）は `~/.ssh/known_hosts` を検証する。
- etcd の確認は control-plane のノード上で `etcdctl` を使う。ノードには `/opt/bin/etcdctl` と、接続情報を入れた `/etc/etcd/etcd.env`（`ETCDCTL_*`）がある。
  以下の `etcdctl ...` は、次の形で実行する意味である（`<ノード>` は交換対象でない control-plane）。

```bash
ssh ubuntu@<ノード> 'sudo bash -c ". /etc/etcd/etcd.env && /opt/bin/etcdctl member list -w table"'
```

## 2. 事前準備

交換作業の前日までに済ませておく。2.1〜2.3 は 3 台分まとめて 1 回でよい。2.4 と 2.5 は機体ごと。

### 2.1 asset の再生成（`render kubelet`）✋

#13 の `setup-containerd.sh` を asset に取り込むため、**`render kubelet` を `--node` なしで 1 回だけ**流す。

- `render certs` と `render all` は**使わない**。CA が作り直され、既存のクラスタと食い違う。
- `render kubelet --node ...` も使わない。`--node` を付けると `kubelet-default/`（`setup-containerd.sh` などの共通の asset）が作られない。
- `render etcd` / `render bootstrap` / `render kubernetes` は要らない。IP、メンバー名、K8s の版が変わらないため（検証結果「render のグループと順序」）。

手順:

1. `assets/secrets/`（CA と各証明書の鍵）がローカルにあることを確かめる。無ければ `assets/secrets.tar.asc` を復号して `assets/secrets/` を戻す
   （展開する前に `tar -t` で中身のパスを確かめる）。`assets/secrets/` と `secrets.tar` は git の管理対象外である。
2. k8s-manifests-fraction で作業ブランチを切り、`porkadot render kubelet --config ./porkadot.yaml` を流す。
3. `git status` と `git diff --stat` で差分を確かめる。**期待する差分は次の 2 種類だけ**である。
   - `assets/kubelet-default/setup-containerd.sh`（containerd v1/v2 の判定が入る）
   - `assets/kubelet/<各ノード>/bootstrap.crt`（同じ鍵と同じ CA で署名し直される。有効期限が延びる）
4. それ以外の差分（`ca.crt`、etcd のマニフェスト、`kubelet.service`、`config.yaml` など）が出たら、**コミットせずに止めて**原因を調べる。
5. 再署名された `bootstrap.crt` の有効期限を確かめる（`openssl x509 -noout -enddate -in assets/kubelet/192.168.1.111/bootstrap.crt`）。
   切れていると新機が TLS bootstrap できない。
6. 差分をコミットして PR を出す。本番の交換は、この asset で行う。

既存のノードは手持ちのクライアント証明書を使い続けるので、`bootstrap.crt` の再署名は既存ノードに影響しない（検証結果「render のグループと順序」）。

### 2.2 etcd のバックアップの置き場

- `porkadot etcd backup` は、`--path` で渡したディレクトリに `etcd-<日時>.db` を作る。既定値は cwd の `./backup`。
- **保存先は k8s-manifests-fraction の `./backup/`** とする（これまでのバックアップもここにある）。
  このディレクトリは `.gitignore` で除外してある。snapshot には Secret が平文で入っているので、`git add -f` などで追加しないこと。
- 交換が終わるまで、各回のバックアップを消さない。必要なら作業端末の外（暗号化したストレージ）にも写す。

### 2.3 ルーター（jumelle）の DHCP の確認（ユーザー作業）

- 旧機の MAC アドレスで、192.168.1.111〜113 の静的 DHCP 割り当てが jumelle に残っていないかを確かめる。
- 新機は IP を固定で持つので割り当てが無くても動く。旧機を戻したとき（ロールバック）に混乱しないよう、残っているものを把握しておく。消すかどうかはユーザーが決める。

### 2.4 新しい Pi 5 を仮の IP で用意する（機体ごと、ユーザー作業を含む）

**etcd を止めている時間を短くするため、新機は交換の前に仮の IP で cloud-init を済ませておく**（V7 の発見 2）。
cloud-init は `apt upgrade` と再起動まで含めて 15 分ほどかかる。これを交換中にやると、etcd が 1 メンバー欠けた状態が長引く。

手順は k8s-env の `raspi/README.md` に従う。違うのは、IP を本番のものではなく仮の空きアドレスにすることだけである。

1. **ユーザー**: EEPROM を更新し、NVMe から起動するようにする（README の 2）。
2. **ユーザー**: OS イメージ（24.04.5。**E2 待ち**で確定）を NVMe SSD に書く（README の 3）。
3. cloud-init の設定を生成する。ホスト名は本番のもの（rasp01〜03）、IP は仮の空きアドレスにする。
   `raspi/envs/rasp0N.sh` は IP を固定で持つので、`raspi/envs/verify.sh` にホスト名と仮の IP を渡す。

   ```bash
   NODE_HOSTNAME=rasp03 NODE_ADDRESS=192.168.1.<仮> bash raspi/generate-cloud-init.sh raspi/envs/verify.sh raspi/out/rasp03-tmp
   ```

   対応は rasp01 = .111、rasp02 = .112、rasp03 = .113。
4. **ユーザー**: 生成した `user-data` と `network-config` を boot パーティションに置き、初回起動する（README の 4、5）。
5. README の 6 の確認表をすべて確かめる（NVMe から起動、cgroup v2 と memory controller、containerd 2.2 系、4K ページ、時刻同期など）。
6. **本番の IP へ切り替える準備**（**E2 待ち**。E2 で手順を確かめる）:
   - `/etc/netplan/50-cloud-init.yaml` の仮の IP を本番の IP に置き換えたファイルを、新機の上に別名で用意しておく。
     交換のときは、これを本番の位置に置いて再起動するだけにする。
   - cloud-init が再起動のたびにネットワーク設定を書き戻さないよう、`/etc/cloud/cloud.cfg.d/` に `network: {config: disabled}` を置く。
   - 本番の IP に切り替えたあとは、旧機が動いている間は**絶対に起動しない**（IP が衝突する）。
7. **SSH のホスト鍵を旧機から引き継ぐ**（V10 の推奨）:
   - 旧機の `/etc/ssh/ssh_host_*`（秘密鍵を含む）を取り出し、新機の `/etc/ssh/` に同じ所有者とパーミッションで置いて `ssh` を再起動する。
   - 作業端末に一時的に置いたホスト鍵は、置き終えたらすぐ消す。
   - 新機の仮の IP の known_hosts は、鍵が変わるので `ssh-keygen -R 192.168.1.<仮>` で消す。
   - こうしておくと、本番の IP に切り替えたあとも `192.168.1.11N` の known_hosts をそのまま使える。ロールバックで旧機に戻したときも known_hosts を触らずに済む。
8. （任意）etcd を止めている時間をさらに縮めるため、次を事前に済ませておく（**E2 待ち**。効果は E2 で測る）。
   - `install kubelet` の中で流れる `install-pkgs.sh` と同じ apt パッケージ（`assets/kubelet-default/install-pkgs.sh` の一覧）を入れておく。
   - control-plane のイメージ（`registry.k8s.io/etcd:3.5.12-0`、`kube-apiserver` / `kube-controller-manager` / `kube-scheduler` / `kube-proxy` の `v1.29.8`、
     `flannel/flannel:v0.25.1`、`flannel/flannel-cni-plugin:v1.4.1-flannel1`、`quay.io/metallb/speaker:v0.14.5`）を
     `ctr -n k8s.io images pull` で取得しておく。`setup-containerd` が containerd を再起動しても、取得済みのイメージは残る。

### 2.5 交換の当日、最初に確かめること

1 台ごとの作業（§3）に入る前に、毎回確かめる。

| 確認 | 方法 | 合格基準 |
|---|---|---|
| Node | `kubectl --context fraction get nodes -o wide` | 全 8 台が Ready |
| etcd | `etcdctl member list -w table`、`etcdctl endpoint health --cluster`、`etcdctl endpoint status --cluster -w table` | 3 メンバーとも started / healthy。メンバー ID とリーダーを記録する |
| control-plane の Pod | `kubectl --context fraction -n kube-system get pods -o wide -l 'app.kubernetes.io/component in (kube-apiserver,kube-controller-manager,kube-scheduler)'` | apiserver 3 台が Running / Ready。controller-manager と scheduler の配置を記録する |
| VIP | `kubectl --context fraction get --raw '/readyz'` | `ok` |
| VIP の広告役 | `kubectl --context fraction -n kube-system describe svc porkadot-kubernetes` の Events（`nodeAssigned`） | 広告しているノードを記録する |
| MetalLB の speaker | `kubectl --context fraction -n metallb-system get pods -o wide` | braque 以外の 7 ノードで Running。.113 の speaker は再起動が多い（846 回、E3）ので、増えていないかも見る |
| workload の基準 | `kubectl --context fraction get pods -A -o wide` のうち Running / Completed 以外 | 交換前の一覧を保存する（交換後の比較に使う） |
| 新機 | 仮の IP で SSH、2.4 の 5 の確認表 | すべて期待どおり |

交換中の影響を測りたいときは、porkadot-dev の `docs/cp-replacement/rehearsal/external-probe.sh` で VIP の `/healthz` と LoadBalancer の Service を 1 秒ごとに叩いておく。

## 3. 1 台ごとの手順

### 3.1 交換の順序

既定の順序は **.113 → .112 → .111** とする。技術的に順序を縛る制約は無いので、次の 3 点で決めた。当日の配置を見て入れ替えてよい。

1. **.113 から始める。** 2026-10-14 時点で .113 には controller-manager と scheduler の両方が載っている（E3）。
   ここを最初にすると、ステップ 0 で偏りを解消する練習を、ほかの 2 台が旧機のまま安定している状態で 1 回目にできる。
   .113 は speaker の再起動回数が際立って多く、機体を早く替えたい理由もある。
2. **etcd のリーダーは後回しにする。** 当日 2.5 で見たリーダーが対象なら、別のメンバーを先にするか、§3.4 の手順 1 でリーダーを移してから止める。
3. **controller-manager と scheduler の偏りは、毎回その場で確かめる。** 配置は Pod の再作成で変わる（V7 の発見 1）。順序よりもステップ 0 で担保する。

以下、対象を `192.168.1.11N`（メンバー名 `node11N`、ホスト名 `rasp0M`）と書く。

### 3.2 交換の流れと所要時間の目安

```
[3.3 ステップ 0] ─ 対象から apiserver / controller-manager / scheduler を退かせる      （etcd は 3/3 のまま）
[3.4 etcd 停止] ─ backup → etcd stop → /var/lib/etcd を取り出す                     ┐
[3.5 機体の入れ替え] ─ 旧機の電源断 → Node 削除 → 新機を本番 IP で起動               │ etcd 2/3 の区間
[3.6 新機の構築] ─ setup-node → setup-containerd → データ展開 → install kubelet  ┘ （短いほどよい）
[3.7 確認] ─ etcd 3/3、apiserver Ready、VIP、Node、speaker
```

dev（amd64 の VM）では、新機を事前に用意した場合、etcd を止めてから 3/3 に戻るまで 24〜70 秒、ステップ 0 から apiserver が Ready になるまで約 1〜2 分だった（V7）。
Pi 5 での所要時間は **E2 待ち**。`install kubelet` の中のダウンロード（kubelet、etcdctl、crictl、CNI）とイメージの取得で、dev より長くなる見込みである。

**etcd 2/3 の区間が 15 分を超えそうなら、そこで止めてユーザーと続行かロールバックかを決める。** この区間は、もう 1 台落ちると etcd が quorum を失う。

### 3.3 ステップ 0: 対象から control-plane の Pod を退かせる ✋

このステップを省くと、controller-manager や scheduler の 2 レプリカがどちらも対象に載っていた場合、対象を止めた時点で CSR の署名が止まり、新機が参加できなくなる（V7 の発見 1）。

1. infra-admin のトークンを発行する（§1.2）。
2. 対象の master ラベルを外す。

   ```bash
   kubectl-admin label node 192.168.1.11N k8s.unstable.cloud/master-
   ```

   - 確認: 対象の kube-apiserver の Pod が消え、`kubectl --context fraction -n kube-system get endpointslices -l kubernetes.io/service-name=porkadot-kubernetes` から対象の IP が外れる（dev では約 1 秒）。
3. 対象に載っている controller-manager と scheduler の Pod を消す。

   ```bash
   kubectl --context fraction -n kube-system get pods -o wide --field-selector spec.nodeName=192.168.1.11N
   kubectl-admin -n kube-system delete pod <controller-manager と scheduler の Pod>
   ```

   - 確認: 消した Pod の代わりが**ほかの master**で Running になる。controller-manager 2 台、scheduler 2 台がすべて対象以外にいる。
   - ラベルを外したので、対象には戻らない。PodDisruptionBudget は `delete pod` を妨げない。
4. 合格基準: 対象以外の 2 台で apiserver が Ready、controller-manager と scheduler がそれぞれ 2 台 Running、`get --raw /readyz` が `ok`。

**ここで止めて、ユーザーの承認を得てから 3.4 に進む。**
ここまでの戻し方は、ラベルを付け直すだけである（`kubectl-admin label node 192.168.1.11N k8s.unstable.cloud/master=`）。

### 3.4 旧機の etcd を止めてデータを取り出す ✋

ここから 3.6 の終わりまでが etcd 2/3 の区間である。止まらずに続けて進められるよう、3.5 と 3.6 のコマンドを手元に用意してから始める。

1. 対象が etcd のリーダーなら、ほかのメンバーへ移す。`etcdctl endpoint status --cluster -w table` でリーダーを確かめ、
   `etcdctl move-leader <移す先のメンバー ID>` を実行する（ID は 16 進）。
   `move-leader` はリーダーのエンドポイントに送る必要があるので、**対象（いまのリーダー）のノードの上で**実行する（`etcd.env` のエンドポイントは `127.0.0.1`）。
   移ったことを `endpoint status --cluster` で確かめる。
2. バックアップを取る。**`--node` には対象以外のメンバーを渡す。**

   ```bash
   porkadot etcd backup --node 192.168.1.<対象以外> --path ./backup --config ./porkadot.yaml
   ```

   - 確認: `./backup/etcd-<日時>.db` ができ、大きさが数十 MB（E3 の時点で DB は約 55 MB）。
   - 保存先をユーザーに伝える。
3. 対象の etcd を止める。**`--node` を付け忘れると 3 台とも止まる。** コマンドを打つ前に `--node` を読み上げて確かめる。

   ```bash
   porkadot etcd stop --node 192.168.1.11N --config ./porkadot.yaml
   ```

   - porkadot は `etcd-server.yaml` を `/etc/kubernetes/manifests/` から `/opt/porkadot/` へ移し、etcd のコンテナが消えるまで待つ。
   - 確認: 対象で `sudo /opt/bin/crictl ps --name etcd` が空。`/opt/porkadot/etcd-server.yaml` がある。
     残りの 2 メンバーで `etcdctl endpoint health --cluster` を流すと、対象だけが unhealthy で、ほかの 2 台は healthy。
   - この時点から、apiserver の一部のリクエストが断続的にタイムアウトしうる（§5.2）。
4. 対象の `/var/lib/etcd` を tar で固めて手元へコピーする。所有者（root）とパーミッション（0700）を保つ。

   ```bash
   ssh ubuntu@192.168.1.11N 'sudo tar -C /var/lib -czpf - etcd' > ./backup/node11N-var-lib-etcd-<日時>.tar.gz
   ```

   - 確認: `tar -tzf` で `etcd/member/snap/db` と `etcd/member/wal/` が入っている。
   - これも Secret を含む。`./backup/` に置くので git には入らない。

### 3.5 機体を入れ替える（ユーザー作業を含む）

1. **ユーザー**: 旧機をシャットダウンし（`ssh ubuntu@192.168.1.11N sudo poweroff`）、電源を抜く。**旧機はこの交換が終わるまで起動しない。**
   - 確認: `ping 192.168.1.11N` が応答しない。
2. Node オブジェクトを消す ✋（V10 の推奨。新機の登録時に `porkadot.yaml` どおりのラベルと taint が付き、旧機の古い情報が残らない）。

   ```bash
   kubectl-admin delete node 192.168.1.11N
   ```

   - 旧機に割り当てられていた Pod（DaemonSet の Pod など）も消える。podCIDR は新機の登録時に振り直される（dev で flannel の経路と通信に問題が無いことを確かめた）。
3. 新機を本番の IP に切り替える（**E2 待ち**。2.4 の 6 で用意した方法を使う）。
   - 仮の IP で SSH し、用意したネットワーク設定を本番の位置に置いて再起動する。
   - 確認: `ping 192.168.1.11N` が応答する。`ssh ubuntu@192.168.1.11N` が known_hosts の警告なしで入れる（ホスト鍵を引き継いだため）。
     `hostname` が `rasp0M`、`ip -br addr show eth0` が `192.168.1.11N/16`。
   - ホスト鍵を引き継がなかった場合は、`ssh-keygen -R 192.168.1.11N` のあと、`ssh-keyscan 192.168.1.11N >> ~/.ssh/known_hosts` で全種類の鍵を入れ直す。
     `-H` を付けない。`ssh -o StrictHostKeyChecking=accept-new` で 1 回入るだけでは porkadot が通らない（V10）。

### 3.6 新機を構築して etcd を戻す ✋

1. `porkadot setup-node --node 192.168.1.11N --config ./porkadot.yaml`
   - etcd の証明書と `etcd-server.yaml` が置かれる。kubelet がまだ無いので、etcd は起動しない。
2. `porkadot setup-containerd --node 192.168.1.11N --config ./porkadot.yaml`
   - 確認: 新機で `sudo containerd config dump | grep SystemdCgroup` が `SystemdCgroup = true`。`/etc/containerd/config.toml` が config version 3。
3. **`install kubelet` より前に**、取り出した `/var/lib/etcd` を新機に展開する。

   ```bash
   ssh ubuntu@192.168.1.11N 'sudo test ! -e /var/lib/etcd/member && echo empty'
   cat ./backup/node11N-var-lib-etcd-<日時>.tar.gz | ssh ubuntu@192.168.1.11N 'sudo tar -C /var/lib -xzpf -'
   ```

   - 確認: `sudo ls -ld /var/lib/etcd` が `drwx------ root root`。`/var/lib/etcd/member/snap/db` がある。
   - この順を守れば、空のデータディレクトリで etcd が起動することは無い。空のまま起動すると `--initial-cluster-state=new` で別のクラスタを作ろうとして参加できない。
4. `porkadot install kubelet --node 192.168.1.11N --config ./porkadot.yaml`
   - kubelet のバイナリ、etcdctl、crictl、CNI をダウンロードし、apt のパッケージを入れ、kubelet を起動する。
   - kubelet は `bootstrap.crt` で TLS bootstrap し、クライアント証明書の CSR は自動で承認される（ほかの master の controller-manager が署名する）。
   - etcd の static pod が持ち越したデータで起動し、同じメンバーとしてクラスタに戻る。**ここから先のロールバックは §4.3 になる。**
5. 新機の Node は登録時にラベル（`k8s.unstable.cloud/master`、`etcd.unstable.cloud/member=node11N`）と taint（`node-role.kubernetes.io/master:NoSchedule`）が付く。
   ステップ 0 で外したラベルを手で戻す必要は無い。apiserver の DaemonSet の Pod も自動で起動する。

### 3.7 確認

各項目を上から順に確かめる。すべて合格してから 3.8 へ進む。

| # | 確認 | 方法 | 合格基準 |
|---|---|---|---|
| 1 | etcd のメンバー | `etcdctl member list -w table`（新機の上でも、ほかのノードでもよい） | 3 メンバー started。**メンバー ID、名前、peer URL が 2.5 で記録したものと同じ** |
| 2 | etcd の健全性 | `etcdctl endpoint health --cluster`、`etcdctl endpoint status --cluster -w table` | 3/3 healthy。対象の raft index がほかのメンバーに追いついている |
| 3 | CSR | `kubectl --context fraction get csr` | 新機のクライアント証明書とサービング証明書の CSR が Approved,Issued。Pending が残っていない |
| 4 | Node | `kubectl --context fraction get node 192.168.1.11N -o wide --show-labels` | Ready。OS-IMAGE が Ubuntu 24.04.x、CONTAINER-RUNTIME が `containerd://2.2.x`。master と etcd member のラベル、master の taint がある |
| 5 | cgroup | 新機で `stat -fc %T /sys/fs/cgroup` | `cgroup2fs` |
| 6 | apiserver | control-plane の Pod の一覧（2.5 と同じコマンド） | 新機の kube-apiserver が Running / Ready。3 台とも Ready |
| 7 | VIP | `kubectl --context fraction get --raw '/readyz'`、porkadot-kubernetes の EndpointSlice | `ok`。EndpointSlice に 3 台の IP が ready で入っている |
| 8 | 新機の Pod | `kubectl --context fraction get pods -A -o wide --field-selector spec.nodeName=192.168.1.11N` | kube-proxy、flannel、MetalLB の speaker、監視の DaemonSet（node-exporter など）が Running |
| 9 | ストリーミング | 新機の Pod に `kubectl --context fraction -n kube-system logs` | ログが読める（kubelet のサービング証明書が効いている） |
| 10 | kubelet のログ | 新機で `journalctl -u kubelet --since '10 min ago'` | cgroup と CRI のエラーが続いていない（起動直後の `PLEG is not healthy` などの一時的なものは除く） |
| 11 | workload | `kubectl --context fraction get pods -A` のうち Running / Completed 以外 | 2.5 で保存した一覧から増えていない。LoadBalancer の Service が外から応答する |

### 3.8 後始末と配置の確認

1. controller-manager と scheduler の配置を確かめる。2 レプリカが同じ master に偏っていれば、片方の Pod を消して散らす ✋。
   新機にはまだ載っていないことが多い。次の対象に両方が載っている場合は、次の回のステップ 0 で動かすので、ここでは無理に動かさなくてよい。
2. infra-admin のトークンを破棄する（`unset ADMIN_TOKEN`）。期限が来れば失効する。
3. 作業記録に、所要時間（ステップ 0 の開始、etcd 停止、install kubelet 完了、3/3 healthy の時刻）、バックアップのファイル名、新機の OS と containerd の版を書く。

### 3.9 次の 1 台へ進む条件

次の **すべて** を満たしてから、次の機体のステップ 0 に入る。

- etcd の 3 メンバーが healthy で、メンバー ID が交換前と同じ。
- kube-apiserver の Pod が 3 台とも Ready で、VIP の EndpointSlice に 3 台が入っている。
- 全 8 台の Node が Ready。
- controller-manager と scheduler がそれぞれ 2 台 Running。
- 3.7 の 11（workload）に問題が無い。
- 新機が少なくとも 10 分、再起動や NotReady なしで動いている。急がない場合は 1 日置いてもよい
  （新旧の混在状態は dev で確かめてあり、そのまま置いても問題ない。V6）。
- **ユーザーが次の 1 台へ進むことを承認した。**

3 台目を終えたら §6 に進む。

## 4. ロールバック

どこまで進んだかで戻し方が変わる。境目は「**新機の etcd が一度でも起動したか**」、つまり 3.6 の 4（`install kubelet`）を流したかどうかである。

### 4.1 ステップ 0 だけ済ませた段階（3.3）

- master ラベルを付け直す: `kubectl-admin label node 192.168.1.11N k8s.unstable.cloud/master=`
- apiserver の Pod が対象に戻り、Ready になることを確かめる。controller-manager と scheduler は戻さなくてよい。

### 4.2 新機の etcd を起動する前（3.4〜3.6 の 3 まで）

旧機を戻すだけでよい。dev では約 1 分で戻った（V11a）。

1. 新機が本番の IP で起動していれば、**ユーザー**が新機の電源を切る。
2. **ユーザー**が旧機の電源を入れる。
3. 旧機で、etcd のマニフェストが `/opt/porkadot/etcd-server.yaml` にあり、`/etc/kubernetes/manifests/` に無いことを確かめる。
4. `porkadot etcd start --node 192.168.1.11N --config ./porkadot.yaml`
5. Node を消していた場合は、旧機の kubelet が手持ちのクライアント証明書で Node を登録し直す。ラベルと taint は登録時に付く。
   Node を消していない場合は、master ラベルを付け直す（4.1）。
6. 3.7 の 1、2、4、6、7 を確かめる。メンバー ID が交換前と同じで 3/3 healthy なら完了。

旧機のデータディレクトリは etcd を止めた時点のままだが、新機の etcd は一度も起動していないので、古いデータで戻してよい。

### 4.3 新機の etcd を起動したあと（3.6 の 4 以降）

**旧機の古い `/var/lib/etcd` のまま旧機の etcd を起動してはいけない。**
新機のメンバーが受け取って応答したログを、旧機のデータは持っていない。そのまま起動すると、旧機の etcd は
`tocommit(...) is out of range [lastIndex(...)]. Was the raft log corrupted, truncated, or lost?` で panic し、再起動を繰り返す（V11c）。

戻すときは、**新機のデータを旧機へ持ち帰る**。dev では約 50 秒で戻った（V11b）。

1. `porkadot etcd stop --node 192.168.1.11N --config ./porkadot.yaml`（新機の etcd を止める。`--node` を必ず付ける）。
2. 新機の `/var/lib/etcd` を tar で手元へコピーする（3.4 の 4 と同じ方法。ファイル名に `new-` を付けて区別する）。
3. **ユーザー**が新機の電源を切る。
4. **ユーザー**が旧機の電源を入れる。
5. **旧機で etcd のマニフェストが `/opt/porkadot/` にあり、`/etc/kubernetes/manifests/` に無いことを確かめる。**
   これが崩れていると、旧機は起動しただけで古いデータの etcd を起動してしまう。3.4 の 3 の `etcd stop` を経ていれば、この状態になっている。
6. 旧機の `/var/lib/etcd` を退避し（消さずに別名へ移す）、新機から持ち帰ったデータを展開する。所有者とパーミッションを保つ。
7. `porkadot etcd start --node 192.168.1.11N --config ./porkadot.yaml`
8. 旧機の kubelet は、同じ名前の Node を更新する。ラベルが付いていなければ付け直す。
9. 3.7 の 1、2、4、6、7 を確かめる。

ほかの戻し方として、旧機のデータディレクトリを空にし、`etcdctl member remove` / `member add` と `--initial-cluster-state=existing` で入れ直す方法（方式 A1）もある。
dev では検証していないので、4.3 の手順が使えないときの最後の手段とする。

どの場合も、3.4 の 2 で取った `porkadot etcd backup` が最後の保険になる。
snapshot からの restore は watch cache の食い違いを起こすので（V9a）、使った場合は apiserver、controller-manager、scheduler の Pod を 1 台ずつ作り直す。

### 4.4 apiserver が全台止まったとき

A2 では起きない想定だが、もう 1 台が落ちて etcd が quorum を失った場合などに備える。全断からの復帰は V9b で確かめた。

1. 落ちた機体を戻し、etcd を 3/3 か少なくとも 2/3 に戻す。
2. `porkadot install bootstrap node --config ./porkadot.yaml` で、pablo に bootstrap 用の apiserver を立てる。`install bootstrap kubernetes` は要らない。
3. VIP（192.168.1.101）が応答しなければ、MetalLB の speaker の広告役が詰まっている（§5.1）。
4. VIP が戻り、control-plane の Pod が Running になったら、`porkadot install bootstrap cleanup --config ./porkadot.yaml`。
5. `porkadot install kubelet --node pablo --config ./porkadot.yaml` で、pablo の kubelet の向き先を VIP に戻す。
   **bootstrap が終わる前に `install kubelet` を全台へ流さない。**pablo の向き先が VIP に戻り、bootstrap が完了しなくなる。

## 5. 既知の問題と対処

### 5.1 MetalLB の L2 広告が詰まって VIP が応答しない

- 症状: apiserver は動いているのに、VIP（192.168.1.101）に誰も ARP で応答しない。
- 原因（V9b）: 広告役に選ばれた speaker が、API に届かなくなる前に受け取った「VIP の Service に ready な endpoint が無い」という古い情報のまま止まり、広告しない。
  speaker は API に VIP か `kubernetes` Service 経由で接続するので、VIP が落ちていると新しい情報を受け取れない。最新の情報を持つ speaker は広告役ではないので、これも広告しない。
- 対処: 最新の情報を持つノード（bootstrap の apiserver がいる pablo など）**以外**の speaker のコンテナを、各ノードで `sudo /opt/bin/crictl stop <speaker のコンテナ ID>` で止める。
  止めた speaker は memberlist から外れ、残った speaker が広告役になって VIP がすぐに戻る。API が戻ると、止めた speaker も自動で起動する。
- porkadot の troubleshooting.md の「クラスター再起動後に MetalLB が起動しない」（MetalLB の controller を bootstrap ノードへ動かす）は、controller が bootstrap ノード以外にいる場合の手順で、この症状とは別である。
- A2 では apiserver が 2 台残るので、dev では起きなかった。交換する機体が VIP の広告役でも、広告役の切り替えで途切れは観測されなかった（V12）。

### 5.2 etcd を 1 メンバー止めている間の apiserver のタイムアウト

- 症状: 3.4 の 3 から 3.6 の 4 までの間、残りの apiserver のログに `http: Handler timeout` と、止めたメンバーへの `grpc: addrConn.createTransport failed to connect` が出る。
  VIP 経由のリクエストと、Pod からの API の両方で、数秒の失敗が断続的に起きる（V7 の発見 2）。
- 平常時には起きない。影響の大きさは etcd を止めている時間で決まる。
- 対処: 新機を事前に用意して（2.4）、etcd 2/3 の区間を短くする。区間が長引いたら（目安 15 分）止めてユーザーと判断する（§3.2）。
  クラスタ内の `kubernetes` Service 経由の API は、VIP より影響が小さかった。

### 5.3 SSH の fingerprint mismatch

- 症状: porkadot が `fingerprint ... does not match` で失敗する。
- 原因: 同じ IP で機体が変わってホスト鍵が変わった。net-ssh は known_hosts を厳密に照合する。
- 対処: ホスト鍵を引き継いでいれば起きない（2.4 の 7）。起きたら 3.5 の 3 の方法で known_hosts を入れ直す。

### 5.4 新機が参加できない（CSR が Pending）

- 症状: 新機の Node が登録されない。`kubectl get csr` に新機の CSR が Pending のまま残る。
- 原因: controller-manager が 1 台も動いていない（V7 の発見 1）。ステップ 0 を省いたか、対象以外の master でも controller-manager が落ちている。
- 対処: ほかの master で controller-manager が Running か確かめる。動いていなければ、controller-manager の Pod の定義を写して `nodeName` を健全な master に固定した Pod を手で作る
  （スケジューラーを通らずに起動する）。これが leader になって CSR に署名する。新機が参加したら、手で作った Pod を消す。

### 5.5 全断（方式 B）を採らない理由

本番では全断の方式を使わない。A2 が失敗したときの最終手段として 4.4 にだけ残す。

- `porkadot etcd restore`（#14 の版）は動くが、restore のあと apiserver の watch cache に消えたはずのデータが残る（V9a）。
  revision が snapshot の時点に戻ってから進み直すためで、全コンポーネントの再起動が要る。`etcdutl` が無いので `--bump-revision` も使えない。
- データを持ち越す全断（B2）でも、bootstrap の再実行が要り、MetalLB の L2 広告のデッドロック（§5.1）が起きた（V9b）。
- 全断の開始から復帰まで約 8 分かかり（調査の時間を除く）、A2 の 1 台あたり 1〜2 分より長い。詰まったときの影響もクラスタ全体に及ぶ。

## 6. 完了後の確認と後片付け

### 6.1 完了の確認

3 台目のあと、TASK.md の完了条件を確かめる。

| 確認 | 方法 | 合格基準 |
|---|---|---|
| control-plane の Node | `kubectl --context fraction get nodes -o wide` | 192.168.1.111〜113 が Ready で、OS-IMAGE が Ubuntu 24.04.x（E2 で 26.04 に変えた場合はその版）、CONTAINER-RUNTIME が `containerd://2.x` |
| etcd | `etcdctl endpoint health --cluster`、`etcdctl member list -w table` | 3 メンバーとも healthy。メンバー ID が交換前と同じ |
| control-plane の Pod | 2.5 と同じコマンド | kube-apiserver 3 台、controller-manager 2 台、scheduler 2 台が Running。controller-manager と scheduler がそれぞれ別の master に分かれている |
| VIP | `kubectl --context fraction get --raw '/readyz'` | `ok` |
| workload | `kubectl --context fraction get pods -A` のうち Running / Completed 以外、LoadBalancer の Service | 交換前の一覧から増えていない。外から応答する |

数日おいて、新機の上の Pod の再起動回数と、Node の Ready が続いていることをもう一度確かめる。

### 6.2 旧機の扱い

- 新機の etcd が起動した時点で、旧機の `/var/lib/etcd` は古くなっている。**旧機をそのままクラスタに戻すことはできない**（§4.3）。
  6.1 の確認が済んで数日たつまでは、旧機を電源断のまま、SD カードも含めて保管する（調査用）。
- 処分や再利用の前に、旧機の SD カードを消去する。SD には etcd のデータ（Secret を含む）、etcd と kubelet の証明書と鍵、SSH のホスト鍵（新機と同じ鍵）が入っている。
- 作業端末の `./backup/` にある `/var/lib/etcd` の tar も同じく機密である。交換が落ち着いたら、残すものを決めて消す。

### 6.3 リポジトリへの反映

- k8s-manifests-fraction: 2.1 の `render kubelet` の差分を PR でマージしておく。IP、メンバー名、ラベルは変わらないので、`porkadot.yaml` の変更は要らない。
  交換の作業記録（所要時間、版、起きたこと）を残すなら、この `docs/cp-replacement/` に追記する。
- 交換の結果は llm-wiki の Wiki（`topics/自宅クラスター` の OS 表記、`synthesis/cluster-upgrade-plan-2026` の進捗）にも反映する。これは別の作業単位で行う。
