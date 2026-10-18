# 段 C の手順書: containerd を Docker の `containerd.io` 2.3 系へ置き換える（本番 `fraction`）

本番クラスタ `fraction` の 8 台で、Ubuntu の `containerd` 2.2.1 を Docker の apt リポジトリの `containerd.io` 2.3 系に置き換える手順。K8s は v1.29.8 のまま変えない。
計画は同じディレクトリの `plan.md`（以下「計画」）の §5、決まったことは §9 にある。

| | 更新前 | 更新後 |
|---|---|---|
| containerd | 2.2.1（Ubuntu の `containerd` 2.2.1-0ubuntu1~24.04.3） | 2.3 系（Docker の `containerd.io`。2026-10-18 は 2.3.6-1~ubuntu.24.04~noble） |
| runc | 1.3.4（Ubuntu の `runc` 1.3.4-0ubuntu1~24.04.1） | `containerd.io` に同梱の 1.5 系（2.3.6 では 1.5.1） |
| containerd の config | version 3 | **version 3 のまま**（containerd 2.3 は読み込むときに version 4 へ移す。ファイルは変えない） |
| apt | Ubuntu の archive だけ | Docker の noble のリポジトリを足し、`containerd.io` を 2.3 系に pin する |
| oeilvert の Docker | Ubuntu の `docker.io` 29.1.3 | Docker の `docker-ce` / `docker-ce-cli`（2026-10-18 は 29.9.1） |
| K8s、porkadot、etcd | v1.29.8、0.29.2、3.5.12 | 変えない |

この手順は、dev クラスタ（porkadot-dev の KVM の VM 7 台、context `test`）で先に通してある（2026-10-18）。
記録は porkadot-dev の `docs/k8s-upgrade/verification-stage-c.md`（porkadot-dev#7。以下「dev の記録」）にある。dev では 7 台とも 2.3.6 で Ready になり、ロールバックも通った。

dev で確かめていないものは次のとおり。**ここを本番で特に注意して見る。**

- **arm64**。dev の段 C は amd64 の VM 7 台で通した。arm64 の `containerd.io`（Raspberry Pi 5 の control-plane）を入れるのは、本番の 192.168.1.113 が初めてになる。Docker の noble のリポジトリに arm64 の 2.3.6 があることは確かめてある（§1.6）
- **oeilvert の `docker.io` から `docker-ce` への移行と devbox**（§4）。dev では、192.168.22.124 を oeilvert に似せて（`docker.io`、イメージ、volume、restart policy のコンテナ、devbox 型の unit、IPv6 の daemon.json）§4.2 と §7.3 を通した。本番の oeilvert の大きな `/var/lib/docker`（約 232G）と、本物の devbox では通していない
- Longhorn のボリュームの多いノード、replica 1 のボリューム、ZFS、NFS。これらは前タスクの OS 更新と同じ扱い（drain と Longhorn の設定の切り替え）にする

## 0. 役割と約束ごと

- **承認の節目は 2 つだけ**（計画 §9.1）。この手順書では ✋✋ を付けた。
  1. ✋✋ **段 C の開始**: 1 台目（chirico）で Docker のリポジトリを足す前（§3.3 の前）
  2. ✋✋ **oeilvert の Docker の入れ替え**: oeilvert で Docker を止める前（§4.2 の前）
- **節目の間の手順は、ユーザーに知らせるだけで進めてよい。** 変更系の操作には ✋ を付けてあるが、これは「知らせてから行う操作」の印で、1 つずつ承認を取る印ではない。
- **runbook から外れる操作（ロールバック、想定外の対処、controller の無い Pod の `--force`）は、その都度ユーザーの承認を取る。** 想定外のことが起きたら、その場で止めて報告する。
- 読み取りの確認（`kubectl --context fraction get`、SSH での状態確認）は、知らせずに行ってよい。
- **物理作業はユーザーが行う。** コンソール、電源。
- **1 台ずつ行う。** 1 台を終えて「次の 1 台へ進む条件」（§3.12）を満たすまで、次のノードに手を付けない。
- 時刻はすべて UTC で記録する。worker のホストの時刻は UTC だが、**control-plane（192.168.1.111〜113）のホストの時刻は Asia/Tokyo（JST）** である。control-plane の `journalctl` や `ls -l` の時刻は 9 時間ずらして読む。

## 1. 前提

### 1.1 kubeconfig の運用

`porkadot-dev/CLAUDE.md` の「本番クラスタ（fraction）の kubeconfig 運用」に従う。前タスクの `docs/worker-os-upgrade/runbook.md`（以下「OS 更新の手順書」）§1.2 と同じ。

- 確認は `kubectl --context fraction`（`fraction-auditor`、read-only）で行う。作業を始める前に `kubectl --context fraction auth can-i delete pods -A` が `no` であることを確かめる。
- 変更（cordon、drain、uncordon、Pod の削除、Longhorn の設定、StatefulSet と Prometheus の replicas）は、`infra-admin` の短命トークンで行う。1 台ごとに 2〜3 時間の期限で発行し、終わったら破棄する。
  以下、変更系のコマンドを `kubectl-admin` と書く（`kubectl --context fraction --token="$ADMIN_TOKEN"` のこと）。

### 1.2 SSH

| ノード | 入り方 |
|---|---|
| worker（braque、chirico、duchamp、oeilvert、pablo） | `ssh yuanying@<IP>` |
| control-plane（192.168.1.111〜113、rasp01〜03） | `ssh ubuntu@<IP>` |

どちらもパスワードなしで sudo できる。以下、ノードの上のコマンドは `sudo` を付けて書く。

### 1.3 porkadot は流さない

段 C では porkadot のコマンドを流さない（計画 §5.4）。

- porkadot は containerd を入れない。`setup-containerd` は config を書くだけで、version 行のある config は作り直さない
- config は今の version 3 のまま使う。containerd 2.3 は version 3 を読み、読み込むときに version 4 へ移す。2.2.1 は version 4 を読めないので、version 3 のままにしておけば、戻すときに config に触らずに済む
- このリポジトリの `assets/kubelet-default/setup-containerd.sh` は、porkadot が version 4 に対応する前の render である。段 C では流さない
- `install kubelet` と `setup-node` も流さない。kubelet のバイナリ、`kubelet.service`、証明書は、containerd を置き換えても変わらない

### 1.4 cnidaria の手順書のスクリプト

確認には、前タスクと同じく cnidaria-cni-dev のタスクの手順書のスクリプト（`/home/yuanying/.local/state/herdr-tasks/cnidaria-cni-dev/notes/fraction-runbook/`）を使う（OS 更新の手順書 §1.4）。

- `verify-nodes.sh`: 全ノードの経路、nft のテーブル、conflist、FORWARD の先頭
- `netcheck.sh`: Pod 間通信（v4 / v6、ノード間）。一時的な DaemonSet を作るので ✋
- `check-apps.sh`: LoadBalancer、VIP、Longhorn、アプリの応答

### 1.5 etcdctl の使い方

control-plane のノードには `/opt/bin/etcdctl` と、接続情報を入れた `/etc/etcd/etcd.env` がある（`docs/cp-replacement/runbook.md` §1）。

```sh
ssh ubuntu@<control-plane> 'sudo bash -c ". /etc/etcd/etcd.env && /opt/bin/etcdctl endpoint status --cluster -w table"'
ssh ubuntu@<control-plane> 'sudo bash -c ". /etc/etcd/etcd.env && /opt/bin/etcdctl endpoint health --cluster -w table"'
```

以下、この形を `etcdctl ...` と書く。

- `etcd.env` は `ETCDCTL_ENDPOINTS=https://127.0.0.1:2379` を export する。**`ETCDCTL_ENDPOINTS` が残ったまま `--endpoints` を渡すと、etcdctl 3.5.12 は `conflicting environment variable is shadowed by corresponding command-line flag` で止まる**（dev の 192.168.22.112 で `move-leader` が止まった）
- ほかのメンバーを見るときは `--cluster` を使う（メンバー一覧から全員に問い合わせる）。特定のエンドポイントに向けるとき（`move-leader`）は、`unset ETCDCTL_ENDPOINTS` してから `--endpoints` を渡す（§5.2 の 4）

### 1.6 入れる版を確かめる

Docker の noble のリポジトリに、2.3 系の新しいパッチが出ていないかを、作業の当日に確かめる（読み取り。作業端末で）。

```sh
for a in amd64 arm64; do
  for p in containerd.io docker-ce; do
    echo "== $a $p"
    curl -fsSL https://download.docker.com/linux/ubuntu/dists/noble/stable/binary-$a/Packages \
      | awk -v want="$p" '/^Package: /{p=$2} /^Version: /{if (p==want) print p, $2}' | sort -V | tail -6
  done
done
```

- パッケージごとに流す。2 つを 1 つの `sort -V | tail` に流すと、後ろに並ぶ `docker-ce` の行で埋まり、`containerd.io` の行が出ない（2026-10-18 の本番の作業で気づいた）

2026-10-18 の時点:

| パッケージ | amd64 | arm64 |
|---|---|---|
| `containerd.io` 2.3 系 | 2.3.4-2、2.3.5-1、**2.3.6-1**（`~ubuntu.24.04~noble`） | 同じ |
| `containerd.io` 2.4 系（入れない） | 2.4.1-2、2.4.2-1、2.4.2-2 | 同じ |
| `docker-ce` | 5:29.9.1-1（最新） | 同じ |

- **全台で同じ版を入れる。** 作業の途中で 2.3 系の新しいパッチが出ても、段 C の間は 1 台目と同じ版にそろえる（`apt-get install containerd.io=<版>` で指定する）。新しいパッチは段 C の後に計画 §5.8 で扱う
- `containerd.io` 2.3.6 は `Provides: containerd, runc`、`Conflicts: containerd, runc`、`Replaces: containerd, runc`。Ubuntu の `containerd` と `runc` を外して入る
- Docker のリポジトリの鍵の fingerprint は `9DC8 5822 9FC7 DD38 854A  E2D8 8D81 803C 0EBF CD88`（k8s-env#7 の `raspi/` と同じ鍵）

### 1.7 作業端末

- devbox（`mosh.fraction.jp`）は oeilvert の Docker で動いている。**oeilvert の作業（§4）は devbox 以外の端末から行う。**
- 作業端末から、VIP と LoadBalancer を 1 秒ごとに見る（§2.4）。

## 2. 事前準備

### 2.1 決まっていること

| # | 内容 | 決定 | 出典 |
|---|---|---|---|
| 1 | 順番 | chirico → duchamp → pablo → braque → oeilvert → 192.168.1.113 → .112 → .111 | 計画 §5.5 |
| 2 | worker の drain | **drain する。ただし、入れ替えと kubelet の再起動は drain せずに行い、ノードの再起動の前に drain する**（§2.2） | 計画 §9.3、dev の記録 |
| 3 | control-plane の drain | **drain しない**。cordon し、controller-manager と scheduler の Pod を 1 つずつ別の master へ移す（§5） | 計画 §9.3、§5.5 |
| 4 | oeilvert の Docker | **`docker-ce` / `docker-ce-cli` に移す**。devbox は入れ替えの間止まる | 計画 §9.4 |
| 5 | 停止時間 | **いつでもよい**。braque だけはバックアップの CronJob の時間帯を避ける（§2.5） | 計画 §9.6 |
| 6 | replica 1 のボリューム（MinIO の 4 つ、prometheus の 2 つ） | 作業中に止まってよい。replica は増やさない | OS 更新の手順書 §2.1 の 2 |
| 7 | 段 C の後 | 1 日ほど様子を見てから段 1 へ進む | 計画 §9.6 |

### 2.2 worker の drain を再起動の前にする理由

dev では、**`containerd.io` の入れ替えと kubelet の再起動では、drain しなくても Pod は 1 つも再起動しなかった**（192.168.22.123 では、Longhorn の instance-manager、CSI、Longhorn のボリュームに書き込み続ける Pod を含む 23 個。書き込みに 8 秒を超える空きも無かった）。2.2.1 に戻すときも同じだった（.122）。
dpkg と needrestart が containerd を再起動しても、動いているコンテナの shim はそのまま動き続け、新しい containerd がそれに繋ぎ直すためである。

drain が要るのは、その後の**ノードの再起動**（§3.9）のほうである。再起動は計画 §5.5 の 8 のとおり行う。古い shim（2.2.1 のもの）を入れ替え、2.3 で起動から上がることを確かめるためで、再起動ではそのノードの Pod が全部止まり、Longhorn のボリュームもそのノードから外れる。

そこで、worker は次の形にする（dev の .123 で通した形）。

1. drain せずに、Docker のリポジトリを足し、`containerd.io` を入れる（§3.3〜§3.6）
2. Longhorn の `concurrent-replica-rebuild-per-node-limit` と `replica-auto-balance` を切り替えてから、kubelet を再起動する（§3.7）
3. 確認が済んでから、前タスクの手順で最後の replica を使う workload を止めて drain し（§3.8）、再起動する（§3.9）

Longhorn の 2 つの設定を kubelet の再起動の前に切り替えるのは、**kubelet の再起動で Node が一瞬 NotReady になり、Longhorn がそのノードの replica を退かそうとする**ためである。本番の duchamp では、kubelet の再起動（07:52:37Z）で Node に `NodeNotReady` が出て、Longhorn の node も 07:52:45Z まで Ready でなくなった。その間に `replica-auto-balance`（`least-effort`）が `Node duchamp is not ready or schedulable, replica ... could get evicted` として、2 つのボリュームの replica を pablo に作り直した（`results/stage-c/duchamp.md` §3.1）。chirico では起きなかった

この形にした理由:

- **Longhorn の設定を切り替えている時間と、replica 1 のボリュームが止まる時間が短くなる。** 切り替えはクラスタ全体にかかり、その間はほかのノードで replica が壊れても作り直されない（OS 更新の手順書 §2.5）。止まった replica は 100 分（`replica-replenishment-wait-interval`）以内に再同期させたい。切り替えから戻すまでを、kubelet の再起動と drain・再起動とその確認だけにできる（入れ替えは切り替えの前に済ませる）
- **入れ替えでつまずいたら、drain する前に止まれる。** そのときは workload を一度も動かさずに戻せる（ロールバックも drain は要らない。§7）
- drain そのものは計画 §9.3 の決定どおり行い、手順は前タスクのものをそのまま使う

再起動を省けば drain そのものが要らなくなるが、その場合は Pod が作り直されるまで 2.2.1 の shim が残り（dev では確かめていない）、2.3 で起動から上がることを確かめないまま次の段へ進むことになる。この手順では取らない。

### 2.3 クラスタ全体のベースライン

作業の当日、1 台目に入る前に次を取り、`results/stage-c/baseline.md` に残す（すべて読み取り。雛形は `results/stage-c/template.md`）。計画 §6.5 の項目と同じもの。1 台ごとの確認は、このベースラインと比べる。

1. `kubectl --context fraction get nodes -o wide`、`kubectl --context fraction version`: 8 台 Ready、全台 v1.29.8、`containerd://2.2.1`
2. 8 台の `containerd --version`、`runc --version`、`head -1 /etc/containerd/config.toml`（`version = 3`）、`md5sum /etc/containerd/config.toml`、`dpkg -l containerd runc containerd.io`、`ls /etc/apt/sources.list.d/ /etc/apt/preferences.d/ /etc/apt/keyrings/`
3. `etcdctl endpoint status --cluster -w table`、`etcdctl endpoint health --cluster -w table`: 3/3 healthy、リーダー、raft index。VIP の `https://192.168.1.101:6443/readyz` が `ok`
4. Running / Completed 以外の Pod の一覧。再起動回数の多い Pod
5. Longhorn: `volumes.longhorn.io`（state、robustness、replica 数、アタッチ先）、`replicas.longhorn.io`（ノードと state。running 以外）、`instancemanagers`、`engineimages`、`nodes.longhorn.io`。更新前から healthy でないもの（2026-10-18 は `myao/myao` と `homegallery/cg-data` が detached）を記録する
6. Longhorn の設定: `concurrent-replica-rebuild-per-node-limit`、`replica-auto-balance`、`node-drain-policy`、`replica-replenishment-wait-interval`（2026-10-18 は `5`、`least-effort`、`block-if-contains-last-replica`、`6000`）
7. cnidaria: `verify-nodes.sh`、`check-apps.sh` の結果。`hedgedoc/db-postgresql` の NetworkPolicy がノードの nftables に入っていること
8. MetalLB: LoadBalancer の Service がアドレスを持ち、応答する（gated の 192.168.1.200 / `::200`、`h2-sshd`、`natsumi-sshd`、minecraft）
9. NFS: braque の NFS を使う PV と Pod が Running、oeilvert のホストの `/home/yuanying/shared/nfs` が読める
10. `kubectl --context fraction top nodes` が応答する。Prometheus の `apiserver_requested_deprecated_apis`
11. **control-plane の controller-manager と scheduler の Pod の置き場所。同じ master に同じ component が 2 つ載っていないか**（§5.1）。

    ```sh
    kubectl --context fraction -n kube-system get pods -o wide \
      -l 'app.kubernetes.io/component in (kube-controller-manager,kube-scheduler)'
    ```

    2026-10-18 は、どちらも .112 と .113 に 1 つずつで、.111 には無い。同じ master に 2 つ載っていても、§5.2 の 3 で 1 つずつ移せば問題ないが、記録しておく

### 2.4 VIP と LoadBalancer を 1 秒ごとに見る

段 C の間（1 台目の入れ替えから最後の uncordon まで）、作業端末で次を流しておく（読み取り）。dev で使ったものと同じ形で、**失敗しても止まらずに続く**。
control-plane の再起動の間は VIP が数十秒ところどころ失敗する（§5.3）ので、この監視も、ほかの監視や `kubectl` の確認も、失敗で止まる形にしない。

```sh
n=0
while true; do
  t=$(date -u +%FT%TZ)
  curl -sk -m 2 -o /dev/null -w '%{http_code}' https://192.168.1.101:6443/livez | grep -q 200 || echo "$t FAIL vip"
  curl -s  -m 2 -o /dev/null http://192.168.1.200/ || echo "$t FAIL lb"
  n=$((n+1)); (( n % 60 == 0 )) && echo "$t ok $n"
  sleep 1
done | tee -a ./stage-c-probe.log
```

- `http://192.168.1.200/` は gated。ホスト名が無いと 404 を返すが、届けば `curl` は成功する（`-f` を付けない）
- 1 分ごとに `ok` の行が出る。止まっていないことはこれで分かる
- FAIL の時刻は、各台の記録に写す
- 1 台ずつ別の作業で進める場合は、その台の §3.3 の前に流し始め、§3.12 を確かめた後に止める。ログは同じファイルに足していく（`tee -a`）

### 2.5 braque を止めてよい時間帯

OS 更新の手順書 §2.1.1 と同じ。作業の前に `kubectl --context fraction get cronjobs -A` で schedule が変わっていないかを見直す（2026-10-18 に見直し、変わっていなかった）。

- **止めてはいけない時間帯（JST）**: 05:15〜06:45、14:30〜15:00、16:45〜17:05、17:55〜18:15
- **止めてよい時間帯（JST）**: 07:00〜14:30 と 18:15〜翌 05:15

braque の drain から uncordon まで（§3.8〜§3.10）は 30 分前後の見込み（braque の drain で動く Pod は無い）。これが止めてよい時間帯に収まるように始める。入れ替え（§3.3〜§3.7）は braque を止めないので、時間帯を問わない。
braque が止まる間の影響（NFS、`registry.fraction.jp`、LAN から Service の IP 10.254.0.0/16 と `fraction.cluster` の名前が使えない）は OS 更新の手順書 §2.1.1 のとおりで、再起動の前にユーザーに伝える。

### 2.6 drain と Longhorn の設定

前タスクの手順をそのまま使う（OS 更新の手順書 §2.4、§2.5、§3.3 の 5〜9、§3.8 の 2〜4）。要点:

- kubelet の再起動（§3.7）の前に、`concurrent-replica-rebuild-per-node-limit` を `0`、`replica-auto-balance` を `disabled` にする（control-plane は Longhorn の node ではないので要らない。クラスタ全体にかかる。1 台の作業の間だけ。途中でやめても必ず戻す）
- 最後の replica を持つノードでは、`node-drain-policy` を `allow-if-replica-is-stopped` にし、その replica を使う workload を止めてから drain する
- uncordon して Longhorn の node が Ready / schedulable に戻ってから、設定を元に戻す。`replica-replenishment-wait-interval`（6000 秒 = 100 分）以内に戻せば、止まった replica をそのまま再同期する

**replica 1 のボリュームの置き場所（2026-10-18 の読み取り）**。前タスクの頃から変わっている（prometheus の 0 と 1 の置き場所が入れ替わり、pablo の replica は 0 になった）。drain の前に必ず読み直す。

| ノード | 最後の replica を持つボリューム | 使っている Pod | drain の前に止めるもの |
|---|---|---|---|
| chirico | `monitoring/prometheus-kube-prometheus-db-prometheus-kube-prometheus-1` | prometheus-1（chirico） | Prometheus リソース `monitoring/kube-prometheus` の `spec.replicas` を 0 |
| duchamp | `monitoring/prometheus-kube-prometheus-db-prometheus-kube-prometheus-0` | prometheus-0（duchamp） | 同上 |
| oeilvert | `minio/export-minio-0`〜`3`（4 つ） | minio-0・3（oeilvert）、minio-1（duchamp）、minio-2（chirico） | `minio/minio` の StatefulSet を 0 |
| pablo、braque | なし | — | なし |

replica の数（2026-10-18）: chirico 17、duchamp 10、oeilvert 18、pablo 0、braque 0（Longhorn のノードではない）。

**この表は 1 台ごとに変わる。** Longhorn の `default-data-locality` が `best-effort`（ボリュームの多くが `best-effort`）なので、drain で退いた Pod や uncordon の後に戻った Pod が別のノードで動くと、§3.11 で設定を戻した後に Longhorn がそのノードにローカルの replica を作り、ほかの replica を 1 つ消す。replica 1 のボリュームの replica も Pod に付いて動く。
本番の chirico の後（2026-10-18 07:02Z）は、Prometheus の 2 つの Pod が入れ替わって戻ったため、**prometheus-0 の replica が chirico、prometheus-1 の replica が oeilvert に移り、duchamp の最後の replica は無くなった**。pablo にも 2 replica のボリュームの replica が 2 つ載った（`results/stage-c/chirico.md` §6.1）。次のノードの drain の前に、下の読み直し方で「最後の replica を持つボリューム」と「止めるもの」を決め直す（表に無いノードに最後の replica があれば、そのノードでも `node-drain-policy` を変え、使う workload を止める）。

読み直し方:

```sh
kubectl --context fraction -n longhorn-system get volumes.longhorn.io \
  -o custom-columns=N:.metadata.name,NS:.status.kubernetesStatus.namespace,PVC:.status.kubernetesStatus.pvcName,S:.status.state,R:.status.robustness,NR:.spec.numberOfReplicas,NODE:.status.currentNodeID
kubectl --context fraction -n longhorn-system get replicas.longhorn.io \
  -o custom-columns=V:.spec.volumeName,NODE:.spec.nodeID,S:.status.currentState
```

### 2.7 戻すための控えを全台で取る ✋

**1 台目で Docker のリポジトリを足す前に、8 台すべてで** 取る（dev では 1 台だけ後から取ることになった。順番を守る）。ノードの上にファイルを作るだけなので、承認は要らない。

```sh
sudo mkdir -p /root/k8u-stage-c
sudo cp -a /etc/containerd/config.toml /root/k8u-stage-c/config.toml.before
sudo bash -c 'cd /root/k8u-stage-c && apt-get download containerd=2.2.1-0ubuntu1~24.04.3 runc=1.3.4-0ubuntu1~24.04.1'
# oeilvert だけ（§4.1）
sudo bash -c 'cd /root/k8u-stage-c && apt-get download docker.io=29.1.3-0ubuntu3~24.04.2'
sudo ls -la /root/k8u-stage-c; sudo sha256sum /root/k8u-stage-c/*.deb
```

- 版は `apt-cache policy containerd runc docker.io` の Installed と同じものにする（2026-10-18 は上のとおり、8 台とも同じ）。noble-updates に新しい版が出ると、古い版は archive から落とせなくなることがある。だから入れ替えの前に落としておく
- control-plane では arm64、worker では amd64 の deb が落ちる
- root で `apt-get download` すると `Download is performed unsandboxed as root ... couldn't be accessed by user '_apt'` と出るが、落とせていれば問題ない（dev でも出た）
- `config.toml.before` の md5 を、§2.3 の 2 の md5 と比べる
- Docker のリポジトリを足す前なので、ここで落ちる deb は必ず Ubuntu のものである

## 3. worker の手順（1 台ずつ）

### 3.1 順番

| 順 | ノード | 理由 |
|---|---|---|
| 1 | chirico | 前タスクと同じく、外から見える役割が無く、手順の確かめに向く。prometheus-1 の replica がある |
| 2 | duchamp | chirico と同じ。prometheus-0 の replica がある。冷却ファンが故障中（ターボ停止運用）。再起動に時間がかかったことがある（前タスクで約 17 分） |
| 3 | pablo | porkadot の bootstrap ノード。replica 1 のボリュームが無い |
| 4 | braque | NFS の停止が多くのものに波及する。drain から uncordon までを §2.5 の時間帯に行う |
| 5 | oeilvert | MinIO の 4 つの replica と、Docker の入れ替え（§4）を伴う。worker の最後にする |

oeilvert を braque の後にするので、oeilvert の作業中（devbox の作り直し）に `registry.fraction.jp`（保存先は braque の NFS）は動いている。

### 3.2 流れと所要時間の目安

| 段階 | 内容 | drain | dev（VM） | 本番の見込み |
|---|---|---|---|---|
| 3.3 | 事前確認 | なし | — | 5 分 |
| 3.4 | Docker のリポジトリ、鍵、pin | なし | 数秒 | 数分 |
| 3.5 | `containerd.io` を入れる | なし | 6 秒 | 1 分 |
| 3.6〜3.7 | 確認、Longhorn の 2 つの設定、kubelet の再起動 | なし | 1 分 | 5 分 |
| 3.8 | `node-drain-policy`、workload を止める、drain | する | 1 秒〜37 秒 | 10〜30 分（Longhorn の detach を待つ） |
| 3.9 | 再起動 | — | 2 分 | 2〜20 分（前タスクでは chirico 約 5 分、duchamp 約 17 分、oeilvert 約 2 分、braque 約 3 分、pablo 約 5 分） |
| 3.10 | 再起動の後の確認（cnidaria が Ready になるまで待つ） | — | 1〜2 分 | 15 分 |
| 3.11 | uncordon、Longhorn の設定を戻し、再同期を待つ | — | 1 分 | 10〜30 分 |

dev では 1 台が 3〜6 分で終わった。本番では、Longhorn のボリュームの多い worker の drain と再同期、ノードの再起動が長くなる。

### 3.3 事前確認

✋✋ **1 台目（chirico）では、§3.4 に入る前にユーザーの承認を取る（段 C の開始の節目）。** 承認を取るときに、§2.3 のベースラインと §2.7 の控えが済んでいることを示す。

対象のノードの読み取りの確認。

- `kubectl --context fraction get node <ノード> -o wide`: Ready、`containerd://2.2.1`
- ノードで `containerd --version`、`runc --version`、`head -1 /etc/containerd/config.toml`（`version = 3`）、`md5sum /etc/containerd/config.toml`
- `sudo ls /root/k8u-stage-c/`: §2.7 の控え（config と deb）がある
- `apt-cache policy containerd containerd.io runc`: `containerd` と `runc` が Ubuntu の版で入っていて、`containerd.io` は候補が無い
- `dpkg -l containerd.io docker-ce`: **worker の 5 台には、前タスクで外した Docker の `containerd.io` 1.6.8 が `rc`（removed, config-files）で残っている**（2026-10-18 の読み取り。oeilvert は `docker-ce` 20.10.18 も `rc`。control-plane には無い）。`rc` の `containerd.io` は `/etc/containerd/config.toml` を conffile として登録したままである。**`apt purge` も `apt autoremove --purge` もしない**（§8.7）
- `ls /etc/apt/sources.list.d/ /etc/apt/preferences.d/ /etc/apt/keyrings/`: 2026-10-18 は次のとおり。
  braque、chirico、duchamp、pablo は `docker.list.disabled-2026101X`（jammy の頃のもの。使わない）と `keyrings/docker.gpg`（古い鍵。使わない）が残っている。oeilvert は `third-party.sources`（jammy、`Enabled: no`）がある。どれも触らない（§8.5）
- `apt list --upgradable`: 当たっていない Ubuntu の更新があれば記録する。**この手順では Ubuntu の更新（`full-upgrade`）は当てない**。containerd の置き換えと混ぜないため
- 他のノードがすべて Ready で、Longhorn に degraded のボリュームが無いこと（ベースラインで healthy でないものを除く）
- 対象のノードの Pod と再起動回数を控える（§3.7 で比べる）。

  ```sh
  kubectl --context fraction get pods -A -o wide --field-selector spec.nodeName=<ノード> --no-headers \
    | awk '{print $1, $2, $4, $5}'
  ```

### 3.4 Docker のリポジトリ、鍵、pin を置く ✋

ノードで:

```sh
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo gpg --show-keys --with-colons /etc/apt/keyrings/docker.asc | grep '^fpr' | head -1
#   fpr:::::::::9DC858229FC7DD38854AE2D88D81803C0EBFCD88: であること。違えば止める

sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<SRC
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
SRC

sudo tee /etc/apt/preferences.d/containerd-io >/dev/null <<'PIN'
Package: containerd.io
Pin: version 2.3.*
Pin-Priority: 1001
PIN

sudo apt-get update
apt-cache policy containerd.io
```

- `apt-cache policy containerd.io` の **Candidate が 2.3 系**（2026-10-18 は `2.3.6-1~ubuntu.24.04~noble`）で、2.4 系ではないこと。Version table の 2.3 系の行の優先度が 1001 であること。違えば止める
  - **出力を `head` で切らない。** Pin-Priority の 1001 は Version table の各版の行に出るので、先頭の 3 行（Installed、Candidate、`Version table:`）だけでは見えない。全部を読むか、`apt-cache policy containerd.io | grep -B1 1001` で 2.3 系の版の行と 1001 の行を確かめる
- 鍵とリポジトリのファイル名は dev と同じ `docker.asc` と `docker.sources` にする。古い `keyrings/docker.gpg` と `docker.list.disabled-*` は触らない
- pin は `containerd.io` だけにかける。**oeilvert の `docker-ce` / `docker-ce-cli` は pin しない**（§4.4）
- pin の優先度 1001 は、2.3 系より新しい版（2.4 系）があっても 2.3 系を選ばせる。2.3 系の中では一番新しいパッチが候補になる。§1.6 で決めた版と候補が違う（作業の途中で新しいパッチが出た）場合は、§3.5 で版を指定する

### 3.5 `containerd.io` を入れる ✋

**oeilvert はこの節ではなく §4.2 の手順で入れる。**

1. 先に、apt がすることを読む（読み取り）。

   ```sh
   sudo apt-get install -s -o Dpkg::Options::=--force-confold containerd.io | grep -E '^(Inst|Remv|Conf)|newly|upgraded'
   ```

   次のとおりであること（dev の 7 台で同じだった。control-plane は `[arm64]`）。これ以外のパッケージが消える・入る場合は止める。

   ```text
   0 upgraded, 1 newly installed, 2 to remove and 0 not upgraded.
   Remv containerd [2.2.1-0ubuntu1~24.04.3]
   Remv runc [1.3.4-0ubuntu1~24.04.1]
   Inst containerd.io (2.3.6-1~ubuntu.24.04~noble Docker CE:noble [amd64])
   Conf containerd.io (2.3.6-1~ubuntu.24.04~noble Docker CE:noble [amd64])
   ```

2. ✋ 入れる。

   ```sh
   sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::=--force-confold containerd.io
   # 版を指定するとき: ... containerd.io=2.3.6-1~ubuntu.24.04~noble
   ```

   - `containerd.io` は `disabled_plugins = ["cri"]` の `/etc/containerd/config.toml` を conffile として持つ。`--force-confold` で手元の version 3 の config を残す。control-plane（`containerd.io` の記録が無い）では、出力に `Configuration file '/etc/containerd/config.toml' ... ==> Using current old file as you requested.` が出る見込み
   - worker では `rc` の `containerd.io` 1.6.8 の上に 2.3 を入れることになる。dpkg は 1.6.8 の頃の conffile の記録と比べて「手元で変えたファイル」と見なし、手元の config を残す（dev で確かめた）。**worker では `Using current old file` は出ない**（本番の chirico）。2.3.6 の deb の conffile の md5（`1d862b12f2cb082816175b28ee501789`）が 1.6.8 で登録された md5 と同じで、パッケージ側が変わっていないので、dpkg は何も聞かずに手元のファイルを残す。どちらでも、入れた後に §3.6 の md5 の比較で、config が変わっていないことを必ず見る（メッセージの有無ではなく md5 で判断する）
   - dpkg が containerd を再起動し、続けて needrestart がもう一度 `systemctl restart containerd.service` を流す。どちらでも動いているコンテナは止まらない（needrestart は `No containers need to be restarted.` と出す）。dev では、ここでそのノードの Pod は 1 つも再起動しなかった
   - 入れた時刻を記録する

### 3.6 ノードで確かめる

```sh
containerd --version                               # containerd containerd.io 2.3.x（dev は v2.3.6）
runc --version | head -1                           # runc version 1.5.x（dev は 1.5.1）
head -1 /etc/containerd/config.toml                # version = 3
sudo md5sum /etc/containerd/config.toml /root/k8u-stage-c/config.toml.before   # 同じであること
sudo containerd config dump | grep -E '^version|SystemdCgroup|sandbox = '
#   version = 4（読み込むときに移した結果。ファイルは 3 のまま）、SystemdCgroup = true、sandbox = 'registry.k8s.io/pause:3.10.1'
systemctl is-active containerd
sudo journalctl -u containerd -b --since '-10min' --no-pager | grep -iE 'level=(error|warning)' | grep -v 'unmarshal sandbox spec'
sudo ctr deprecations list
sudo /opt/bin/crictl --runtime-endpoint unix:///run/containerd/containerd.sock info >/dev/null && echo crictl-info-ok
sudo /opt/bin/crictl --runtime-endpoint unix:///run/containerd/containerd.sock images -q | wc -l   # 入れる前と同じ（イメージが残っている）
apt-cache policy containerd.io                     # Installed と Candidate が同じ 2.3 系。2.3 系の行の優先度が 1001（head で切らない。§3.4）
```

- **`containerd config dump` が `version = 4` を示すのは正しい。** containerd 2.3 が version 3 の config を読み込むときに移した結果で、ディスクの `/etc/containerd/config.toml` は version 3 のまま（md5 も変わらない）。だから 2.2.1 に戻すときに config を触らずに済む（§7）
- `/etc/crictl.yaml` は無いので、`crictl` には `--runtime-endpoint` を付ける（付けないと既定の候補を順に試して warning を出す）
- journal に出てよいもの（dev で出た。§8.1）:
  - `failed to unmarshal sandbox spec for pod ...`（level=error）。2.2.1 が作った sandbox を 2.3 が読むときに出る
  - `Configuration migrated from version 3, use 'containerd config migrate' to avoid migration`（level=warning）
  - `failed check for fsverity support`（level=warning）
- それ以外の error、特に config、CRI、cgroup、CNI のものが出ていれば止める

### 3.7 kubelet を再起動する ✋

kubelet の再起動で Node が一瞬 NotReady になり、Longhorn が auto-balance でそのノードの replica をほかのノードへ作り直すことがある（§2.2。本番の duchamp で起きた）。だから、**kubelet を再起動する前に** Longhorn の 2 つの設定を切り替える。ここからノードの再起動の準備に入る。§2.6 のとおり、前タスクの手順をそのまま使う。

1. ✋ `infra-admin` のトークンを発行する。
2. ✋ Longhorn の設定を変える。変える前の値を記録してから。

   ```sh
   kubectl --context fraction -n longhorn-system get settings.longhorn.io \
     concurrent-replica-rebuild-per-node-limit replica-auto-balance node-drain-policy
   kubectl-admin -n longhorn-system patch settings.longhorn.io concurrent-replica-rebuild-per-node-limit --type=merge -p '{"value":"0"}'
   kubectl-admin -n longhorn-system patch settings.longhorn.io replica-auto-balance --type=merge -p '{"value":"disabled"}'
   kubectl --context fraction -n longhorn-system get settings.longhorn.io \
     concurrent-replica-rebuild-per-node-limit replica-auto-balance node-drain-policy   # APPLIED が true
   ```

   - ここで止めることになった（§3.7 の確認で問題が出て §7.1 で戻すなど）ときも、この 2 つは必ず元の値に戻す（§3.11 の 3）
3. ✋ kubelet を再起動する。

   ```sh
   sudo systemctl restart kubelet
   ```

30 秒ほど待ってから確かめる。

- `kubectl --context fraction get node <ノード> -o wide`: Ready、CONTAINER-RUNTIME が `containerd://2.3.x`
- `kubectl --context fraction get pods -A -o wide --field-selector spec.nodeName=<ノード>`: すべて Running。**§3.3 で控えた再起動回数から増えていない**（dev では増えなかった）。増えていれば止めて調べる
- `sudo journalctl -u kubelet --since '-5min' --no-pager | grep -iE 'error|fail' | tail`: CRI と cgroup のエラーが続いていない
- §2.4 の監視に、この間の失敗が無い（dev では入れ替えと kubelet の再起動の間に失敗は無かった）

ここで問題があれば、drain せずに §7.1 で戻せる。戻すときも、2 で切り替えた Longhorn の設定を元に戻す。

### 3.8 drain する ✋

§3.7 の 1 と 2（トークンと Longhorn の 2 つの設定）は済んでいる。

1. ✋ 対象のノードに最後の replica を持つボリュームがあるときだけ（§2.6 の表を読み直して決める。2026-10-18 の表では chirico、duchamp、oeilvert だったが、chirico の後に duchamp は無くなった）、`node-drain-policy` を変える。

   ```sh
   kubectl-admin -n longhorn-system patch settings.longhorn.io node-drain-policy --type=merge -p '{"value":"allow-if-replica-is-stopped"}'
   kubectl --context fraction -n longhorn-system get settings.longhorn.io node-drain-policy   # APPLIED が true
   ```

2. ✋ 最後の replica を使う workload を止める（§2.6 の表を読み直してから）。
   - chirico、duchamp: `kubectl-admin -n monitoring patch prometheus kube-prometheus --type=merge -p '{"spec":{"replicas":0}}'`。対象のノードの prometheus のボリュームが detach され、replica が stopped になるのを待つ
   - oeilvert: `kubectl-admin -n minio scale statefulset minio --replicas=0`。4 つのボリュームが detach されるのを待つ
3. ✋ cordon と drain。

   ```sh
   kubectl-admin cordon <ノード>
   # コントローラを持たない Pod（drain が --force なしでは止まる）を探す
   kubectl --context fraction get pods -A --field-selector spec.nodeName=<ノード> -o json \
     | jq -r '.items[] | select((.metadata.ownerReferences // []) | length == 0) | .metadata.namespace + "/" + .metadata.name'
   kubectl-admin drain <ノード> --ignore-daemonsets --delete-emptydir-data --timeout=20m
   ```

   - コントローラを持たない Pod が見つかったら、消してよいかをユーザーに確かめる（runbook から外れる扱い）。よければ `--force` を足す（dev の .123 でも `e2e-np/db` で止まった）
   - 止まったときの調べ方は OS 更新の手順書 §3.3 の 8 と同じ（`kubectl --context fraction get pdb -A`、longhorn-manager のログの `removing <ノード> PDB is blocked: replica ...`）
4. drain の後、対象のノードの Longhorn のボリュームが detach された（または他のノードへ移った）こと、対象のノードの replica の代わりがほかのノードに作られていないことを確かめる。drain の開始と終わりの時刻を記録する。

ノードごとの追加の確認は OS 更新の手順書 §3.3 の「ノードごとの追加の作業」と同じ（oeilvert の devbox と自動再起動の時間帯、braque の `zfs-import-cache` が enabled であることと §2.5 の時間帯、pablo の share-manager・fs の h2・`docker/registry` が他のノードで Running に戻ったこと）。

### 3.9 再起動する ✋

```sh
sudo systemctl reboot
```

- 古い shim（2.2.1）を 2.3 のものに入れ替え、2.3 で起動から上がることを確かめる（§2.2）
- 上がってくるまでの時間は §3.2 の表。20 分ほどは上がってこなくても慌てない
- **braque**: 再起動の前にユーザーに伝える（§2.5。NFS、LAN から 10.254.0.0/16 と `fraction.cluster` が使えない）。§2.5 の止めてよい時間帯であることを確かめる
- **duchamp**: 冷却ファンが故障中で、ターボを止めて運用している（`/sys/devices/system/cpu/intel_pstate/no_turbo` を `1`。Wiki の `wiki/topics/自宅クラスター.md` の duchamp の節）。この設定は再起動で戻り、永続化するものは無い。再起動の前に温度（`cat /sys/class/hwmon/hwmon*/temp1_input`）と `no_turbo` を記録し、**SSH が戻ったらすぐに**（cnidaria の Ready を待たずに）`echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo` で止め直し、`cat` で `1` を確かめる（2026-10-18 のユーザー承認）。高温のまま再起動するとキー入力待ちで止まることがあるので、10 分たっても SSH が戻らなければ止めて報告する（物理作業が要る）
- 再起動の時刻と、Node が Ready に戻った時刻を記録する

### 3.10 再起動の後の確認

§3.6 と §3.7 の確認（版、config、journal、Node、kubelet）をもう一度行う。加えて次を確かめる。**すべて uncordon の前（cordon のまま）に行う。**

**再起動の直後、そのノードの cnidaria と MetalLB の speaker が数回 CrashLoopBackOff になることがある**（dev の 192.168.22.113 で cnidaria 3 回・speaker 3 回、.112・.123・.122 で speaker が数回。前タスクでも speaker で見た）。
起動の直後、そのノードの kube-proxy が `kubernetes` Service の規則を入れる前に、API（本番では `https://10.254.0.1:443`）へ繋ごうとして `connect: connection refused` で落ちる。kubelet の CrashLoopBackOff の待ち（10 秒、20 秒、40 秒…）が重なるので、cnidaria が動き出すまで 1 分強かかる。
**cnidaria が動き出すまで、そのノードには Pod の経路と nftables の規則が無い。** そのノードの Pod が Ready になって Service の Endpoints に入ると、ほかのノードからそこへ振り分けられた通信が失敗する（dev の .113 の直後に、ほかの 4 ノードの Pod から Service への要求が 6 回失敗した）。
だから、**そのノードの cnidaria の Pod が Ready になり、`verify-nodes.sh` が通ってから uncordon し、次の 1 台へ進む。**

| # | 確認 | 方法 | 合格基準 |
|---|---|---|---|
| 1 | Node | `kubectl --context fraction get node <ノード> -o wide --show-labels` | Ready（SchedulingDisabled）。CONTAINER-RUNTIME が `containerd://2.3.x`、VERSION が v1.29.8。ラベルが残っている |
| 2 | cnidaria | `kubectl --context fraction -n kube-system get pods -o wide --field-selector spec.nodeName=<ノード> -l app.kubernetes.io/name=cnidaria` | **1/1 Running（Ready）**。CrashLoopBackOff になっていたら、`kubectl --context fraction -n kube-system logs <Pod> --previous` を記録し、Ready になるまで待つ。ログが `dial tcp 10.254.0.1:443: connect: connection refused` で、数分のうちに Ready に戻れば想定どおり。ほかのエラーか、5 分たっても戻らなければ止める |
| 3 | cnidaria の経路と規則 | `verify-nodes.sh` | 全項目 PASS（ベースラインと同じ）。cnidaria のログに、2 の起動の直後のもの以外の error が無い |
| 4 | DaemonSet の Pod | `kubectl --context fraction get pods -A -o wide --field-selector spec.nodeName=<ノード>` | 全部 Running。再起動の分だけ再起動回数が 1 増えるのはよい。MetalLB の speaker は 2 と同じ理由で数回 CrashLoopBackOff になってから戻る。数分待って Running に戻らなければ止める |
| 5 | ストリーミング | 対象のノードの Pod に `kubectl --context fraction logs` | ログが読める |
| 6 | iptables | ノードで `sudo iptables -S FORWARD \| head -3`、`sudo ip6tables -S FORWARD \| head -3` | `CNIDARIA-FWD` へのジャンプが先頭（oeilvert は §4.3） |
| 7 | ディスク、ZFS | `lsblk`、`df`。braque と oeilvert は `sudo zpool status`、`findmnt /export`（braque） | Longhorn のディスクがマウントされている。pool が ONLINE。**braque は `tank1` が取り込まれ、`/export` が `tank1/export` であることを真っ先に見る**（OS 更新の手順書 §3.4 の 10） |
| 8 | iSCSI | `systemctl is-active iscsid.socket multipathd` | active。`iscsid.service` は socket から必要なときに起動するので、再起動の直後は inactive でよい（本番の chirico） |
| 9 | DNS | `resolvectl status porka-dummy01` | 10.254.0.10 がある |
| 10 | 失敗している unit | `systemctl --failed` | ベースラインから増えていない |
| 11 | apt | `apt-cache policy containerd.io`、`sudo apt-get -s full-upgrade \| grep -E 'containerd\|runc\|upgraded'` | Candidate が 2.3 系で、2.3 系の行の優先度が 1001（`head` で切らない。§3.4）。`full-upgrade` の模擬で `containerd.io` が 2.4 系に上がらない（dev では `0 upgraded`。当たっていない Ubuntu の更新があれば、それは出てよい） |
| 12 | journal | `sudo journalctl -u containerd -b --no-pager \| grep -c 'unmarshal sandbox spec'` | 出ていてよい（§8.1）。数を記録する |

ノードごとの追加の確認は OS 更新の手順書 §3.7 の「ノードごとの追加の確認」と同じ（braque の nfsd と `registry.fraction.jp`、pablo の fs の h2・`docker/registry`・share-manager）。oeilvert は §4.3。

### 3.11 uncordon と後始末 ✋

OS 更新の手順書 §3.8 と同じ。

1. ✋ `kubectl-admin uncordon <ノード>`（§3.10 の 2 と 3 が通ってから）。
2. ✋ §3.8 の 2 で止めたものを戻す。chirico・duchamp は Prometheus リソースの `spec.replicas` を 2 に、oeilvert は `minio/minio` を 4 に。Pod が Running になり、ボリュームが healthy でアタッチされたことを確かめる。
3. Longhorn の node（`kubectl --context fraction -n longhorn-system get nodes.longhorn.io <ノード>`）が Ready で schedulable に戻ったことを確かめてから、✋ Longhorn の設定を §3.7 の 2 で記録した値に戻す（2026-10-18 は `5`、`least-effort`、`block-if-contains-last-replica`。`node-drain-policy` は §3.8 の 1 で変えたときだけ）。読み直して APPLIED が true であること。切り替えてから戻すまでの時間を記録する（100 分を過ぎると、止まった replica を使わずに作り直すことがある）。
4. Longhorn: 対象のノードの replica が running に戻り、再同期が終わるまで待つ。degraded のボリュームがベースラインから増えていないこと。本番の chirico では、設定を戻してから全部 healthy になるまで 16 分かかった。data locality で replica の置き場所が変わることがある（§2.6）ので、終わった後の replica の置き場所を記録し、同じボリュームの replica が同じノードに 2 つ載っていないことを見る（`kubectl --context fraction -n longhorn-system get replicas.longhorn.io -o json | jq -r '.items[]|.spec.volumeName+" "+.spec.nodeID' | sort | uniq -d` が空）。
5. Running / Completed 以外の Pod が、ベースラインから増えていないこと。
6. ✋ `netcheck.sh` と `check-apps.sh` を流す。ベースラインと同じであること。
7. `infra-admin` のトークンを破棄する（`unset ADMIN_TOKEN`）。
8. `results/stage-c/<ノード>.md` に記録する（§9）。

### 3.12 次の 1 台へ進む条件

次の **すべて** を満たしてから、次のノードの §3.3（control-plane は §5.2）に入る。

- 全 8 台の Node が Ready。終えたノードが `containerd://2.3.x`、まだのノードが `containerd://2.2.1`
- 終えたノードの cnidaria の Pod が Ready で、`verify-nodes.sh` が全 PASS
- etcd 3/3 healthy、VIP が応答する
- Running / Completed 以外の Pod が、ベースラインから増えていない
- Longhorn のボリュームが healthy（ベースラインのものを除く）。再同期が終わっている
- Longhorn の 3 つの設定が元の値に戻っている。`minio/minio` が 4、Prometheus の `spec.replicas` が 2
- `netcheck.sh`、`check-apps.sh` がベースラインと同じ
- 終えたノードが、少なくとも 30 分、再起動や NotReady なしで動いている。1 台目（chirico）と、control-plane の 1 台目（.113）の後は長めに見る

節目（§0）以外では、次の 1 台へ進むことをユーザーに知らせてから進む。

## 4. oeilvert: `docker.io` を `docker-ce` に移す ✋✋

oeilvert では、§3.3 と §3.4（リポジトリ、鍵、pin）までは他の worker と同じに行い、§3.5〜§3.7（入れ替えと kubelet の再起動）をこの節の手順で行う。§3.8（drain）以降は他の worker と同じ。

Ubuntu の `docker.io` は `containerd (>= 1.2.6-0ubuntu1~)` に版つきで依存する。`containerd.io` は `Provides: containerd` だが版の無い Provides なので、版つきの依存を満たさない。`containerd.io` を入れると `docker.io` が外れる。
そこで、`containerd.io` と一緒に Docker の `docker-ce`（`Depends: containerd.io (>= 2.1.5), docker-ce-cli, iptables, nftables`、`Conflicts: docker.io`）と `docker-ce-cli` を入れる。前タスクの OS 更新の手順書 §3.4.1（`docker-ce` から `docker.io` へ移した手順）の逆向きである。

### 4.1 移す前の状態と控え（読み取り）

2026-10-18 の読み取り:

| 項目 | 値 |
|---|---|
| パッケージ | `docker.io` 29.1.3-0ubuntu3~24.04.2、`containerd` 2.2.1-0ubuntu1~24.04.3、`runc` 1.3.4-0ubuntu1~24.04.1。`docker.io` の Recommends で入った `ubuntu-fan`、`pigz`、`bridge-utils`。`containerd.io` 1.6.8 と `docker-ce` 20.10.18 は `rc`（設定だけ残っている） |
| apt のリポジトリ | `ubuntu.sources` と `third-party.sources`（Docker の jammy、`Enabled: no`） |
| `/etc/docker/daemon.json` | `ipv6: true`、`fixed-cidr-v6: fde0:17ad:84c5:82::/64`。どのパッケージの conffile でもないので残る |
| devbox | `devbox.service`（`Requires=docker.service`、`ExecStart=/home/yuanying/dotfiles/devbox/start-daemon`）。`docker run --rm -d --name devbox --privileged`、`/var/run/docker.sock` を渡し、3222・8080・9090・60000〜60010/udp を公開する。イメージは `registry.fraction.jp/yuanying/devbox-amd64` |
| Docker のストレージ | `docker info` の Storage Driver が **overlay2**（graphdriver。containerd のイメージストアではない） |
| restart policy | `devbox`（動いている）と、止まった 2 つのコンテナは、どれも restart policy が `no` |
| ディスク | `/` の空きは 82G |
| 自動再起動 | unattended-upgrades の自動再起動が 04:00（UTC）。作業の時間帯をずらす |

作業の当日に控える（読み取り。作業端末に保存する）: `sudo docker info`（特に Storage Driver と Docker Root Dir）、restart policy（`sudo docker ps -a --format '{{.Names}}' | xargs -r -n1 sudo docker inspect -f '{{.Name}} {{.HostConfig.RestartPolicy.Name}} {{.State.Status}}'`）、`sudo docker images`（タグの一覧）、`sudo docker images -a | wc -l`、`sudo docker volume ls`、`sudo docker ps -a`、`/etc/docker/daemon.json`、`dpkg -l | grep -iE 'docker|containerd|runc'`、`df -h /`。

`docker.io` の deb は §2.7 で控えてある（`/root/k8u-stage-c/docker.io_29.1.3-0ubuntu3~24.04.2_amd64.deb`）。

### 4.2 入れ替える ✋✋

✋✋ **ここに入る前にユーザーの承認を取る（oeilvert の Docker の入れ替えの節目）。** devbox を使っている人がいないことも確かめる。

1. 先に、apt がすることを読む（読み取り。§3.4 の後）。

   ```sh
   sudo apt-get install -s --no-install-recommends -o Dpkg::Options::=--force-confold \
     containerd.io docker-ce docker-ce-cli | grep -E '^(Inst|Remv|Conf)|newly|upgraded'
   ```

   - **削除されるのが `containerd`、`runc`、`docker.io` の 3 つだけ**、入るのが `containerd.io`（2.3 系）、`docker-ce`、`docker-ce-cli` の 3 つだけであること。違えば止める
   - `--no-install-recommends` で、Recommends の `docker-ce-rootless-extras`、`docker-buildx-plugin`、`docker-compose-plugin` を入れない。今の `docker.io` の構成（rootless も buildx も compose も無い）に合わせる。前タスクで `docker-ce-rootless-extras` を「要らない」として外したのと同じ判断。要るなら別途入れる
   - `docker-ce` の版を記録する（2026-10-18 の候補は 5:29.9.1-1~ubuntu.24.04~noble）
2. ✋ devbox と Docker を止める。

   ```sh
   sudo systemctl stop devbox
   sudo systemctl stop docker docker.socket
   ```

   restart policy のあるコンテナがあると、止めるのに時間がかかる（dev では 21 秒）。

   devbox は `--rm` なので、コンテナは消える。作業内容はホストの `/home/yuanying` にある。
3. ✋ 入れ替える。

   ```sh
   sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
     -o Dpkg::Options::=--force-confold containerd.io docker-ce docker-ce-cli
   ```

   - **purge しない**（remove のまま）。`/var/lib/docker` と `/etc/docker/` を残す
   - `docker-ce` は入れた時点で `docker.service` を起動する。**restart policy（`always`、`unless-stopped` など）の付いたコンテナは、その時点で起動する**（dev で確かめた）。devbox（`--rm`、unit から起動）は 7 の `systemctl start` まで起動しない。2026-10-18 の本番の oeilvert には restart policy の付いたコンテナは無い。4.1 の控えで restart policy の付いたコンテナが増えていれば、入れ替えの途中で上がることを先に伝える
   - **`apt purge` も `apt autoremove --purge` もしない**（§8.7）。`rc` の `containerd.io` 1.6.8 を purge すると `/etc/containerd/config.toml` が消える。`rc` の `docker-ce` 20.10.18 も、まとめて purge する片付けをしない
   - `ubuntu-fan`、`pigz`、`bridge-utils` は自動で入ったものなので、apt が `autoremove` を勧める。**`autoremove` は流さない**（片付けは段 C の後にユーザーと決める）
4. §3.6 の確認を行う。
5. ✋ §3.7 の 1〜3（トークン、Longhorn の 2 つの設定の切り替え、`sudo systemctl restart kubelet`）。Pod の再起動回数が増えていないこと。
6. Docker を確かめる。
   - `docker version` のサーバーが `docker-ce` の版、Docker Root Dir が `/var/lib/docker`、Cgroup Driver が systemd、containerd の版が 2.3.x
   - **`docker info` の Storage Driver が 4.1 の控えと同じ（2026-10-18 は overlay2）**。Docker 29 は、新しく入れたときの既定が containerd のイメージストア（dev で新しく入れた Docker では overlayfs になった）なので、変わっていないことを必ず見る。変わっていると、`/var/lib/docker` の overlay2 のイメージが見えなくなる。変わっていたら devbox を起こさずに止め、ユーザーと決める（dev では `/etc/docker/daemon.json` に `"features": {"containerd-snapshotter": false}` を足して overlay2 にした。runbook から外れる操作）
   - `docker info` の Images の数と、`docker images` のタグの一覧が 4.1 の控えと同じ。`docker volume ls` に元のボリュームがある
   - `docker network inspect bridge` で IPv6 が有効で、`fixed-cidr-v6` の範囲がある（daemon.json が読まれている）
   - `sudo iptables -S FORWARD | head -5` と `sudo ip6tables -S FORWARD | head -5`。この時点では Docker が `DOCKER-USER` と `DOCKER-FORWARD` へのジャンプを先頭に入れ、`CNIDARIA-FWD` が 3 番目になることがある（前タスクの oeilvert と同じ）。Pod の通信は通る。再起動の後は `CNIDARIA-FWD` が先頭に戻る
7. ✋ `sudo systemctl start devbox`。
   - `docker ps` に devbox がある。ポートが開いている（`ss -ltnu | grep -E ':(3222|8080|9090|6000[0-9]|60010)\b'`）
   - ユーザーに、`mosh.fraction.jp` に SSH（3222）と mosh で入れることを確かめてもらう
   - devbox のイメージが無くなっていれば、`registry.fraction.jp` から pull し直す（レジストリの保存先の braque は §3.1 の順で先に終えて動いている）
8. 以降は §3.8（drain）から他の worker と同じ。再起動の後、`devbox.service` が自動で上がること、`mosh.fraction.jp` に入れることを §4.3 で確かめる。

devbox が止まるのは 2 から 7 まで（dev の 1 台の入れ替えは 6 秒だった）と、§3.9 の再起動の間である。

### 4.3 oeilvert の再起動の後の確認

§3.10 に加えて:

- `systemctl is-active docker devbox`、`docker ps` に devbox がある。ユーザーに `mosh.fraction.jp` に入れることを確かめてもらう
- `sudo journalctl -b 0 | grep "ordering cycle"` が空。`cluster-dns.service` に `porka-dummy01` と `systemd-networkd` への依存がある（OS 更新の手順書 §1.5）
- `home-yuanying-shared-data.automount` と `-h.automount` が `active (waiting)`、`home-yuanying-shared-nfs.mount` が active
- iptables: `CNIDARIA-FWD` が FORWARD の先頭。ip6tables の FORWARD の policy は Docker が DROP にするが、`CNIDARIA-FWD` が先頭にあって `netcheck.sh` が通ること（OS 更新の手順書 §3.7 の 7）
- MinIO の 4 つの Pod が Running で、ボリュームが healthy（§3.11 の 2 の後）

### 4.4 注意

- `docker-ce` は pin しない。Docker の origin は unattended-upgrades の対象ではないので、自動では上がらない。**手で `apt full-upgrade` を流すと `docker-ce` も上がり、Docker が再起動して devbox が止まる**（`--rm` なので消え、`devbox.service` は active のまま残る。`sudo systemctl restart devbox` で戻す）。oeilvert で `full-upgrade` を流すときは、このことを先に伝える
- `docker-ce` は Docker の 30 系が出ても上がる。major を止めたくなったら、`containerd.io` と同じ形で pin を足す（段 C の範囲外）
- 作業中に `docker system prune` などでイメージを消さない
- 戻すときは §7.3

## 5. control-plane の手順（192.168.1.113 → .112 → .111）

### 5.1 worker との違い

- **drain しない。** control-plane に載るのは DaemonSet（kube-apiserver、cnidaria、kube-proxy、MetalLB の speaker、監視）と static Pod（etcd）と、Deployment の kube-controller-manager と kube-scheduler（各 2 replica、`k8s.unstable.cloud/master` の nodeSelector、ホスト名で分ける **preferred** の anti-affinity、PDB は minAvailable 1）だけである
- **cordon し、controller-manager と scheduler の Pod を 1 つずつ別の master へ移す。** dev の 192.168.22.113 では、controller-manager と scheduler の Pod が 2 つずつ .113 に載っていた（anti-affinity は preferred なので、同じ master に寄ることがある）。まとめて消したところ、**scheduler が 1 つも居なくなり、代わりの Pod は割り当てる scheduler が無いので Pending のままになった**（dev では Binding API で 1 つを .111 に手で割り当てて戻した）。代わりの Pod を置くのは残っている scheduler なので、消すのは 1 つずつにし、代わりが別の master で Running になってから次を消す
- **etcd のリーダーなら、先に別のメンバーへ移す。**
- Longhorn は control-plane に載っていない（Longhorn の node ではない）ので、Longhorn の設定は変えない
- 再起動の間、VIP が数十秒、ところどころ失敗する（§5.3）

### 5.2 手順

1. 読み取りの確認。
   - §3.3 のうち、Node、containerd、config、控え、apt の項目と、Pod の再起動回数の控え（ノードは `ssh ubuntu@<IP>`）
   - `etcdctl endpoint status --cluster -w table`、`etcdctl endpoint health --cluster -w table`: 3/3 healthy、raft index がそろっている、リーダーがどれか
   - controller-manager と scheduler の置き場所（§2.3 の 11 のコマンド）。**同じ master に同じ component が 2 つ載っていないか**。載っていても 3 のとおり 1 つずつ移せばよいが、その master の作業では 2 つとも移すことになるので、時間を見ておく
   - `kubectl --context fraction get pods -A -o wide --field-selector spec.nodeName=<IP>`: 2026-10-18 は .113 に cnidaria、etcd、kube-apiserver、kube-controller-manager、kube-proxy、kube-scheduler、speaker、node-exporter、smart-exporter が載っている
2. ✋ `infra-admin` のトークンを発行する。
3. ✋ cordon し、controller-manager と scheduler の Pod を 1 つずつ移す。

   ```sh
   kubectl-admin cordon <IP>
   kubectl --context fraction -n kube-system get pods -o wide \
     -l 'app.kubernetes.io/component in (kube-controller-manager,kube-scheduler)'
   ```

   対象のノードに載っている Pod を、**1 つずつ** 次のように移す（controller-manager を先に、scheduler を後に）。

   ```sh
   kubectl-admin -n kube-system delete pod <対象のノードに載っている Pod>
   kubectl --context fraction -n kube-system get pods -o wide -l app.kubernetes.io/component=<kube-controller-manager か kube-scheduler>
   ```

   - 代わりの Pod が **対象のノード以外の master で 1/1 Running** になり、その component の Running が 2 つにそろうまで待ってから、次の Pod を消す。dev では 1 つあたり 10〜20 秒だった
   - 代わりの Pod が Pending のままなら、次を消さずに止める（`kubectl --context fraction -n kube-system describe pod` の Events を見る）。消した Pod が scheduler のリーダーだった場合、残りの scheduler がリーダーを取るまで少し（lease の 15 秒ほど）かかることはある
   - cordon しているので、代わりの Pod は対象のノードには戻らない。.113 の作業では、今の配置なら .111 へ移る見込み（.111 にはどちらも無い）
4. ✋ 対象が etcd のリーダーなら、リーダーを移す。

   ```sh
   # 1 の endpoint status で、リーダー（= 対象）のエンドポイントと、移す先の ID（16 進）を見る
   ssh ubuntu@<対象の IP> 'sudo bash -c ". /etc/etcd/etcd.env && unset ETCDCTL_ENDPOINTS && /opt/bin/etcdctl --endpoints=https://<対象の IP>:2379 move-leader <移す先の ID>"'
   etcdctl endpoint status --cluster -w table   # リーダーが移ったこと
   ```

   - `move-leader` はリーダーに向けて流す。`etcd.env` の `ETCDCTL_ENDPOINTS` を読み込んだまま `--endpoints` を付けると止まるので（§1.5）、`unset ETCDCTL_ENDPOINTS` してから流す。この形は dev の .113・.111・.112 で通した
   - 移す先は、次に作業しないノードにする（.113 の作業なら .111）
   - 移せなかった場合も、再起動でリーダーは残りのメンバーへ移る（dev の .112 では `move-leader` が止まったまま進め、再起動でリーダーが .113 に移った。raft term が 1 つ進んだ）。ただし移るまでの選挙の分だけ書き込みが止まるので、移してから再起動するのを基本にする
5. ✋ §3.4（リポジトリ、鍵、pin）。arm64 なので、`docker.sources` の `Architectures` が `arm64`、`apt-cache policy containerd.io` の候補が `2.3.x` であること。
6. ✋ §3.5（`containerd.io` を入れる）。**arm64 で入れるのは .113 が初めてになる**（§8.4）。模擬の結果が amd64 と同じ形（`Remv containerd`、`Remv runc`、`Inst containerd.io ... [arm64]`）であることを読む。
7. §3.6 の確認。加えて `etcdctl endpoint health --cluster -w table` が 3/3 healthy（containerd の入れ替えで etcd と apiserver のコンテナは止まらない。dev で止まらなかった）。
8. ✋ §3.7（kubelet の再起動）。Node が Ready,SchedulingDisabled、`containerd://2.3.x`。Pod の再起動回数が増えていない。etcd 3/3 healthy。apiserver の Pod が 1/1。§2.4 の監視に失敗が無い（dev では入れ替えと kubelet の再起動の間、VIP の失敗は無かった）。
9. ✋ 再起動する（`sudo systemctl reboot`）。
   - **再起動の間、VIP が数十秒ところどころ失敗する**（§5.3）。この間は変更系の操作をしない。読み取りが失敗したら少し待ってやり直す
   - etcd はこの間 2/3 で動く。ほかの 2 台が healthy であることを 1 で確かめてあること
10. 再起動の後の確認。
    - §3.6 の確認と、§3.10 の 1〜6、9〜12。**cnidaria の Pod が Ready になり、`verify-nodes.sh` が通るまで待つ**（§3.10。dev の .113 では cnidaria が 3 回 CrashLoopBackOff になってから戻った）
    - etcd: `etcdctl endpoint health --cluster -w table` が 3/3 healthy、`endpoint status` の raft index がそろっている（dev では再起動の後 2 分ほどでそろった）
    - apiserver: 対象のノードの kube-apiserver の Pod が 1/1（dev では Running になってから Ready まで 10〜15 秒）。`curl -k https://192.168.1.101:6443/readyz` が `ok`
11. ✋ `kubectl-admin uncordon <IP>`。controller-manager と scheduler の Pod の置き場所を記録する（uncordon しても Pod は戻らない）。
12. §3.11 の 5〜8 と §3.12（Longhorn の設定は変えていないので、§3.11 の 2〜4 は無い）。

### 5.3 再起動の間の VIP の途切れ

dev では、control-plane の 1 台を再起動するたびに、VIP の `/livez` が **10〜35 秒の間に 2〜8 回** 失敗した（1 秒ごとの問い合わせ。192.168.22.113 は 3 回、.112（etcd のリーダー）は 8 回、.111 は 2 回）。containerd の入れ替え、kubelet の再起動、worker の作業の間は 1 回も失敗しなかった。LoadBalancer（gated に当たるもの）も一度も失敗しなかった。

原因: VIP は MetalLB の LoadBalancer の Service `kube-system/porkadot-kubernetes`（`externalTrafficPolicy: Cluster`、selector は kube-apiserver の Pod）である。
ノードを再起動し始めてから、そのノードの apiserver の Pod が Endpoints から外れるまでの間、kube-proxy がそこにも振り分けるので、要求の一部が失敗する。

段 C ではこれを受け入れる（数十秒で、`kubectl` はやり直せば通る。Pod の中から API を使うものは、client-go がやり直す）。§2.4 の監視と確認は、失敗しても続く形にしておく。
apiserver が止まりきってから外れるまで待つ方法は、段 C の範囲の外とした。候補を注記として残す。**どれも dev で確かめていないので、段 C では使わない。** 使うなら、K8s の段の dev の検証で確かめてから runbook に入れる。

- 再起動の前に kubelet を先に止める（`sudo systemctl stop kubelet`）。Node が NotReady になり、node lifecycle controller がそのノードの Pod を NotReady にして Endpoints から外すのを待ってから（`kubectl --context fraction -n kube-system get endpointslices -l kubernetes.io/service-name=porkadot-kubernetes` で対象の IP の `ready` が false になる）、再起動する。apiserver はその間も動いているので、失敗する時間がなくなる見込み。Node が NotReady の間（約 40 秒〜）に taint による Pod の退去（既定 300 秒）が始まらないうちに再起動すること
- kubelet の graceful node shutdown（KubeletConfiguration の `shutdownGracePeriod` と `shutdownGracePeriodCriticalPods`）。今の本番の kubelet の config には無い（無効）。porkadot の kubelet の config を変えることになるので、K8s の段の porkadot の PR で扱う
- kube-apiserver の `--shutdown-delay-duration` など、apiserver が自分から抜ける時間を作る設定。これも porkadot の変更になる

## 6. 段 C の完了の確認

8 台を終えたら、次がすべて成り立つことを確かめ、`results/stage-c/summary.md` に残す（計画 §5.6、§6.3）。

- 8 台すべてで `containerd --version` が 2.3.x（全台同じ版）、`runc --version` が 1.5.x、`kubectl --context fraction get nodes -o wide` の CONTAINER-RUNTIME が `containerd://2.3.x`、VERSION が v1.29.8
- `/etc/containerd/config.toml` が全台 version 3 で、`/root/k8u-stage-c/config.toml.before` と同じ。`containerd config dump` に `SystemdCgroup = true`
- 全台で `apt-cache policy containerd.io` の Candidate が 2.3 系で優先度が 1001、`apt-get -s full-upgrade` で `containerd.io` が上がらない（pin が効いている）
- etcd 3/3 healthy、リーダーが居る、raft index がそろっている。VIP の `/livez` が `ok`、`/version` が v1.29.8
- apiserver 3/3。controller-manager と scheduler が 2/2。置き場所を記録する（同じ master に同じ component が 2 つ載っていれば記録する。直すかは別途）
- Running / Completed 以外の Pod が無い（ベースラインのものを除く）
- Longhorn: attached のボリュームが全部 healthy（detached の 2 つはベースラインのとおり）、instance-manager が全部 running。設定が元の値。`minio/minio` が 4、Prometheus の `spec.replicas` が 2
- cnidaria: 8 台の Pod が Ready、`verify-nodes.sh` が全 PASS、`netcheck.sh` が全 PASS、`hedgedoc/db-postgresql` の NetworkPolicy がノードの nftables に入っている
- MetalLB: LoadBalancer の Service が応答する（gated、`h2-sshd`、`natsumi-sshd`、minecraft）
- braque の NFS が応答する
- `kubectl --context fraction top nodes` が応答し、Prometheus のスクレイプが落ちていない
- oeilvert の devbox（`mosh.fraction.jp`）が動く
- 新しい warning のイベント・ログ（kubelet、apiserver、kube-proxy、cnidaria、containerd）が増えていない（§8.1 のものは除く）
- §2.4 の監視の FAIL を集計し、control-plane の再起動の間のものと、それ以外を分けて記録する

その後、1 日ほど様子を見てから段 1 へ進む（計画 §9.6）。

## 7. ロールバック

**戻すのは runbook から外れる操作なので、その都度ユーザーの承認を取る。** 戻すと決める目安:

- 入れ替えの後、containerd か kubelet が上がらず、§3.6〜§3.7 の確認で原因が分からない
- Node が Ready に戻らない、DaemonSet の Pod が Running に戻らない、Pod の再起動が続く
- control-plane で etcd が 3/3 に戻らない、apiserver が Ready にならない
- 2.3 に固有と見られる問題（CRI、cgroup、CNI、イメージの pull）が出る

戻すのは問題の出たノードだけにする。ほかのノードは 2.3 のままでよい（2.2.1 と 2.3 の混在は、段 C の途中の状態と同じ）。

### 7.1 1 台を 2.2.1 に戻す ✋

dev の 192.168.22.122 で通した。**drain は要らない**（dev では drain せずに戻し、Pod の再起動は 0、40 秒後に Ready）。

```sh
sudo bash -c '
set -euo pipefail
d=/root/k8u-stage-c; a=$(dpkg --print-architecture)
DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades -o Dpkg::Options::=--force-confold \
  "$d/containerd_2.2.1-0ubuntu1~24.04.3_$a.deb" "$d/runc_1.3.4-0ubuntu1~24.04.1_$a.deb"
rm -f /etc/apt/preferences.d/containerd-io /etc/apt/sources.list.d/docker.sources
apt-get update
'
containerd --version; runc --version | head -1; head -1 /etc/containerd/config.toml
sudo md5sum /etc/containerd/config.toml /root/k8u-stage-c/config.toml.before
sudo systemctl restart kubelet
```

- **deb のパスは `sudo bash -c` の中で組み立てる。** `/root/k8u-stage-c` は一般ユーザーから読めないので、`sudo apt-get install /root/k8u-stage-c/*.deb` のように書くと glob が sudo の前に展開されず、apt が `Unsupported file` で止まる（dev で起きた）。続けて `rm` を流すと、2.3 のまま pin とリポジトリだけが消える。`set -e` で、apt が失敗したら `rm` に進まないようにしてある
- apt が失敗したら、pin とリポジトリは残っている。原因を直してからやり直す

- `containerd.io` が外れ（remove）、Ubuntu の `containerd` 2.2.1 と `runc` 1.3.4 が入る。apt が containerd を再起動する
- **config は触らない。** version 3 のままなので 2.2.1 が読める。`md5sum` が `/root/k8u-stage-c/config.toml.before` と同じであることを確かめる。違っていたら、控えを戻してから containerd を再起動する
- dev では、2.2.1 に戻っている間の containerd のログに error も warning も無かった（2.3.6 が作った sandbox も読めた）
- **`containerd.io` を purge しない。** 外れた `containerd.io` は `rc` で残り、`/etc/containerd/config.toml` を conffile として持ち続ける。purge すると config が消える（§8.7）
- 確認は §3.6〜§3.7 と同じ（版は 2.2.1 と 1.3.4、CONTAINER-RUNTIME は `containerd://2.2.1`）
- 鍵（`/etc/apt/keyrings/docker.asc`）は残してよい
- 再起動するかは、戻した理由による。古い shim を入れ替えたいなら §3.8 から drain して再起動する

### 7.2 control-plane を戻す

7.1 と同じ。kubelet の再起動では apiserver と etcd は止まらない（dev）。再起動するなら §5.2 の 3、4、9〜11 に従う。

### 7.3 oeilvert を戻す ✋

`docker.io` と Ubuntu の `containerd` と `runc` を、控えた deb で入れ直す。`docker-ce` と `docker-ce-cli` と `containerd.io` が外れる。

```sh
sudo systemctl stop devbox
sudo systemctl stop docker docker.socket
sudo bash -c '
set -euo pipefail
d=/root/k8u-stage-c
echo "docker.io docker.io/restart boolean true" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades --no-install-recommends -o Dpkg::Options::=--force-confold \
  "$d/containerd_2.2.1-0ubuntu1~24.04.3_amd64.deb" "$d/runc_1.3.4-0ubuntu1~24.04.1_amd64.deb" \
  "$d/docker.io_29.1.3-0ubuntu3~24.04.2_amd64.deb" docker-ce- docker-ce-cli-
rm -f /etc/apt/preferences.d/containerd-io /etc/apt/sources.list.d/docker.sources
apt-get update
'
sudo md5sum /etc/containerd/config.toml /root/k8u-stage-c/config.toml.before
sudo systemctl restart kubelet
sudo systemctl start docker devbox
```

- 実行の前に、同じ `sudo bash -c` の中で `apt-get install -s` を流し、外れるのが `containerd.io`、`docker-ce`、`docker-ce-cli` だけであることを読む。deb のパスを `sudo bash -c` の中で組み立てる理由は §7.1
- `docker.io` の debconf の質問（アップグレード時に docker を自動で再起動するか）は、先に「はい」を入れておく（OS 更新の手順書 §3.4.1 の 4）
- `docker-ce` と `containerd.io` は `rc` で残る。**purge しない**（§8.7）
- 戻した後、`docker info` の Storage Driver が 4.1 の控えと同じで、イメージが見えることを確かめる
- dev（192.168.22.124 を oeilvert に似せたもの）で、この形で戻せることを確かめた（イメージ、volume、restart policy のコンテナ、devbox 型の unit、IPv6 の daemon.json が残り、K8s の Pod の再起動は 0）

### 7.4 段 C 全体をやめる

全台を 7.1〜7.3 で戻す。順番は入れ替えた順の逆（control-plane を先に、worker を後に）。Longhorn の設定を途中で変えていれば必ず戻す（§2.6）。

## 8. 既知の問題と注意

### 8.1 containerd 2.3 の journal に出るもの

dev で出たもの。どれも動作に影響しなかった。

- `level=error msg="failed to unmarshal sandbox spec for pod <id>" error="type with url : not found"`。**想定内のログ。** containerd 2.3.6 が、2.2.1 が作った sandbox を読むときに出る。dev の .122 で突き合わせたところ、出たのは 2.2.1 の頃に作られ、今は `SANDBOX_NOTREADY` の sandbox だけで、2.3.6 が作った `SANDBOX_READY` の sandbox には出ていない。動いている Pod にも影響しない。kubelet が古い sandbox を片付けるまで、containerd を起動するたびに出る
- `level=warning msg="Configuration migrated from version 3, use 'containerd config migrate' to avoid migration"`。version 3 の config を使う間、起動のたびに出る。config を version 4 に作り直すのは段 8 の後（計画 §10）
- `level=warning msg="failed check for fsverity support"`。ファイルシステムが fsverity に対応していないだけ
- ノードの再起動の直後（kubelet が上がった直後の 1 秒ほど）に、`level=error msg="ContainerStatus for \"<id>\" failed" error="rpc error: code = NotFound ..."` と `RemoveContainer for "<id>" failed ... container is already in removing state` が数行ずつ出る。kubelet が再起動の前に消えたコンテナを問い合わせたもの。本番の chirico では 2.3.6 で 10 行と 2 行、2.2.1 で起動した前回にも 9 行と 1 行あった。2.3 で新しく出たものではない

### 8.2 再起動の直後の DNS の失敗

dev では、各ノードの再起動の直後、そのノードの Pod から DNS の問い合わせが 1 回だけ失敗した（そのノードの Pod が起動した直後の最初の 1 回。ほかのノードからは失敗していない）。§3.10 の 2 の cnidaria が動き出すまでの間のものと見られる。cnidaria が Ready になってから uncordon すれば、ほかのノードには波及しない。

### 8.3 再起動の直後の cnidaria と speaker の CrashLoopBackOff

§3.10 の冒頭のとおり。起動の直後に `kubernetes` Service（本番では `10.254.0.1:443`）へ繋がらず `connection refused` で落ち、1 分ほどで戻る。containerd 2.3 で新しく出たものではない（前タスクの OS 更新でも speaker で見た）。
dev の 192.168.22.113 では、cnidaria が Ready になる前に uncordon した。その直後（05:20:56〜05:21:03Z）、.113 の Pod が Ready として Endpoints に入ったが、.113 の cnidaria がまだ動いていなかったので、ほかの 4 ノードの Pod から Service への要求が 6 回失敗した。この手順では、cnidaria が Ready になり `verify-nodes.sh` が通ってから uncordon する。

### 8.4 arm64

dev の段 C は amd64 の VM でだけ通した。Docker の noble のリポジトリに arm64 の `containerd.io` 2.3.6 があることは確かめた（§1.6）が、Raspberry Pi 5 の上で入れて動かすのは本番の 192.168.1.113 が初めてである。
**dev の Pi では試さず、本番の .113 を control-plane の 1 台目として進めることにした（2026-10-18 のユーザーの判断）。**
.113 では §5.2 の 6〜10 を特に注意して見る。.113 で問題が出たら、.112 と .111 に進まずに止める（.113 は §7.2 で戻せる）。

### 8.5 Docker の古いリポジトリと鍵

braque、chirico、duchamp、pablo には、前タスクで外した jammy の Docker のリポジトリ（`/etc/apt/sources.list.d/docker.list.disabled-2026101X`）と古い鍵（`/etc/apt/keyrings/docker.gpg`）が残っている。oeilvert には jammy の `third-party.sources`（`Enabled: no`）がある。
apt はどれも読まない（拡張子が `.list` / `.sources` でない、または `Enabled: no`）。この手順では触らない。片付けるかは段 C の後にユーザーと決める。

### 8.6 `containerd.io` の更新

- unattended-upgrades は Docker の origin を対象にしないので、`containerd.io` は自動では上がらない。手で `apt full-upgrade` を流すと、pin の範囲（2.3 系）の中で新しいパッチに上がり、containerd が再起動する。段 C の後のパッチの扱いは計画 §5.8
- OS の更新（`do-release-upgrade`）は、Docker のリポジトリが有効だと拒否されることがある（OS 更新の手順書 §3.4 の 1）。OS の更新はこのタスクの範囲外

### 8.7 purge と `autoremove --purge` をしない

`/etc/containerd/config.toml` は、Docker の `containerd.io` の conffile として dpkg に登録されている。

- worker の 5 台には、前タスクで外した `containerd.io` 1.6.8 が `rc`（removed, config-files）で残っている（2026-10-18 の読み取り。conffile の記録は `/etc/containerd/config.toml`）。oeilvert には `docker-ce` 20.10.18 も `rc` で残っている。control-plane には無い
- 段 C で `containerd.io` 2.3 を入れると、同じ conffile の持ち主になる。§7 で戻すと、`containerd.io` はまた `rc` で残る
- **`rc` か入っている `containerd.io` を purge すると、`/etc/containerd/config.toml` が消える**（dev で、ディレクトリの `/etc/containerd/` ごと消えた）。config が無いと、containerd は CRI の設定（`SystemdCgroup = true` など）なしで上がり、kubelet が動かなくなる
- だから、段 C の間もその後も、`apt purge containerd.io`、`apt autoremove --purge`、`dpkg -P` をしない。`rc` の記録を片付けたくなったら、先に `/etc/containerd/config.toml` を控え、ユーザーと決める
- 消してしまったら、`/root/k8u-stage-c/config.toml.before` を `/etc/containerd/config.toml` に戻し、containerd と kubelet を再起動する ✋

## 9. 記録

`results/stage-c/` に、ベースライン（`baseline.md`）、各台（`<ノード>.md`。control-plane は `192.168.1.11N.md`）、全体のまとめ（`summary.md`）を残す。
各台の記録の雛形は `results/stage-c/template.md`。前タスクの `docs/worker-os-upgrade/results/` と同じく、時刻（UTC）、読み取りの結果、実行したコマンドと出力の要点、手順書との差を書く。
手順書と実際の作業の差は、作業の後にこの手順書に反映する（同じ PR か、記録の PR で）。
