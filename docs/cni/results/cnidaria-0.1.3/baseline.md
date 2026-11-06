# cnidaria v0.1.3 のベースライン

本番 `fraction` の cnidaria を v0.1.2 から v0.1.3 にする（porkadot 0.37.6 → 0.37.7。`porkadot.yaml` は変えない）前に取った、読み取りの結果と、イメージの事前 pull、etcd のバックアップ、監視と一時的な名前空間の起動の記録。手順は `../../runbook-cnidaria-0.1.3.md`（以下 runbook）。
時刻は UTC。`snap.sh`・`nodes.sh`・`verify-nodes.sh`・`check-apps.sh`・`dns-check.sh` の出力は、タスクディレクトリの `notes/cnidaria-0-1-3/base/` に置いた（リポジトリには入れない）。

## 1. 前提（runbook §1。2026-11-06 12:07Z）

| 項目 | 結果 |
|---|---|
| 本番の今の姿（§1.1） | 8 台 Ready・schedulable、v1.37.2、`containerd://2.3.6`。etcd 3/3 healthy。Pod 176 個（Running 145、Succeeded 31）で、Running / Completed 以外は 0 個。cnidaria は v0.1.2 の DaemonSet（generation 4、8/8 Ready、updated 8） |
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor`。作業端末の kubectl は v1.37.1 |
| SSH（§1.3） | サンドボックスの中から、8 台に IP で `nodes.sh`・`verify-nodes.sh`・`prepull.sh`・`df`・`etcdctl endpoint status`（読み取り）を流せた |
| porkadot（§1.4） | `worktrees/porkadot-v0-37-7` は `git describe --tags` が `v0.37.7`、作業ツリーに変更が無い。`porkadot help` が動く。§6 の戻しの `worktrees/porkadot-v0-37-6` は `v0.37.6`。cwd は worktree `cnidaria-0-1-3-prod`（`a496b92`。PR #75 をマージした master `718a0c2` と tree が同じ）。`git status --short assets porkadot.yaml` は空、`grep -n image_tag porkadot.yaml` は何も返さない、`cnidaria.yaml` のイメージは `v0.1.3` |
| 入れる版（§1.5。12:08Z） | `ghcr.io/yuanying/cnidaria-cni:v0.1.3` の index は `sha256:f77ec3210c82…`、linux/amd64 `sha256:641753ac…`、linux/arm64 `sha256:998e105f…`、ほかに `unknown/unknown` が 2 つ。runbook の表と同じ |
| 時間帯（§2.7） | 12:07Z に始めた（10:00〜17:30Z の中） |
| `env-fraction.sh` の `FRACTION` | 既定の worktree `cnidaria-0-1-3-prod` で流した（`FRACTION_CHECKOUT` は使っていない） |
| dev の確認 | していない（runbook の冒頭。2026-11-06 のユーザー判断） |

## 2. ベースライン（runbook §2.2。12:07:13Z の `snap.sh`、12:07:44Z の `nodes.sh`）

runbook §2.2 の表の値（09:48〜09:5xZ）と、すべての項目で同じだった。`cni-bin.txt`・`conflist.txt`・8 台の `nft-<ノード>.txt`・`volumes.tsv`・`gens.tsv`・`revisions.txt`・`lb-nfs.txt`・`dns-check.txt` は 09:4xZ の出力（`notes/runbook-cnidaria-0-1-3/base-20261106/`）とバイトまで同じ。`netpol.txt` の差は AGE の列だけ。

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node | 8 台 Ready、v1.37.2、`containerd://2.3.6`、cordon されたものは無い |
| 2 | 全 Pod | 176 個（Running 145、Succeeded 31）。Running / Completed 以外は 0 個。名前・UID・restartCount は `base/pods.tsv` |
| 3 | DaemonSet `cnidaria` | generation 4（observed 4）、desired・ready・updated・available 8。イメージ `ghcr.io/yuanying/cnidaria-cni:v0.1.2`。ほかの項目も runbook §2.2 の 3 のとおり |
| 4 | cnidaria の Pod | 8 つとも v0.1.2・Ready、`controller-revision-hash` `74cd464ffc`。restartCount は duchamp の `cnidaria-h4jf8` が 3、ほかの 7 つは 0 |
| 5 | containerd の cnidaria-cni のイメージ | v0.1.3 は 8 台とも無い。v0.1.2 と v0.1.1 は 8 台にある |
| 6 | ControllerRevision | 5 つ（revision 1〜5） |
| 7 | cnidaria のログ | 25,880 行、info 25,771、**error 109**、ほかは 0。error の数は runbook を書いたとき（09:4xZ）から増えていない |
| 8 | NetworkPolicy | 10 個（`longhorn-system` の 6 つと `argocd` の 4 つ） |
| 9 | `/opt/cni/bin` | 8 台とも runbook §2.2 の 9 とバイトまで同じ。cnidaria のバイナリは無い |
| 10 | conflist | 8 台とも runbook §2.2 の 10 と同じ |
| 11 | nftables | 8 台とも `table inet cnidaria` がある。行の数は control-plane 3 台と braque が 110、duchamp・oeilvert・pablo が 265、chirico が 1017 |
| 12 | 経路 | 8 台とも proto 200 の経路が v4 7・v6 7。`verify-nodes.sh` は PASS 64 / 64、FAIL 0、rc 0 |
| 13 | kubelet | .111 MainPID 1430706、.112 599120、.113 1268238、braque 1727331、chirico 3885703、duchamp 719754、oeilvert 3129443、pablo 3100833。NRestarts は 8 台とも 0 |
| 14 | host-local の割り当て | .111 6、.112 6、.113 2、braque 2、chirico 90、duchamp 36、oeilvert 53、pablo 28 |
| 15 | Longhorn | ボリューム 17、すべて attached・healthy |
| 16 | LoadBalancer・VIP・NFS・etcd | gated-v4・gated-v6 が 404、VIP の `/readyz` が 200、`::131`〜`::134` の 3222 が SSH のバナー、`registry.fraction.jp/v2/` が 401、oeilvert の NFS が読める。etcd 3/3 healthy。`check-apps.sh` は duplicates 0 |
| 17 | ディスク（`/var/lib/containerd`。pull の後） | .111 7%、.112 6%、.113 6%、braque 12%、chirico 16%、duchamp 26%、oeilvert 28%、pablo 18% |
| 18 | DNS | `dns-check.sh` の出力が runbook を書いたときのものと同じ |

## 3. イメージの事前 pull（runbook §2.4。12:08:09〜12:09:04Z）

`prepull.sh` を 1 台ずつ流した（出力は `notes/cnidaria-0-1-3/prepull.txt`）。8 台とも `rc=0`。

| ノード | 秒 | イメージ ID |
|---|---|---|
| 192.168.1.111 | 9 | `6320de424020c`（55.6 MB） |
| 192.168.1.112 | 6 | 同上 |
| 192.168.1.113 | 6 | 同上 |
| braque | 8 | `bc8ccf387a771`（57.3 MB） |
| chirico | 3 | 同上 |
| duchamp | 3 | 同上 |
| oeilvert | 3 | 同上 |
| pablo | 6 | 同上 |

イメージ ID は runbook §1.5 の config と同じ。`crictl pull` の出力は `Image is up to date for sha256:…` の形だが、12:07:44Z の `nodes.sh` では 8 台とも v0.1.3 は無かった（この出力は pull の後の定型）。

## 4. etcd のバックアップ（runbook §2.5。12:09:22〜12:09:27Z）

porkadot 0.37.7 の `etcd backup` を worktree のルートで流した（rc 0。出力は `notes/cnidaria-0-1-3/etcd-backup.log`）。

| ファイル | 置き場所 | バイト | sha256 |
|---|---|---|---|
| `etcd-2026-11-06T12:09:23+00:00.db`（モード 0600） | worktree `cnidaria-0-1-3-prod` の `./backup/`（git には入れない） | 125,042,720 | `f671b56bdaf9016b15c09a5244a3fb251432236930ef415de2d688758b7e1aa0` |

**前のもの（0.37.6 の本番の 2026-10-30 11:21Z、74,612,768 B）と桁が違った（9 桁と 8 桁）ので、runbook §2.5 に従い 12:10Z に止めて報告した。**

- 読み取りの `etcdctl endpoint status`: DB SIZE は .111 125 MB、.112 121 MB、.113 124 MB、IN USE は 3 台とも 40 MB（67〜69% が使われていないページ）。etcd 3.7.3、quota 2.1 GB。スナップショットの大きさは DB SIZE と合う
- ユーザーの判断（12:1xZ）: 大きさの差は、使われていないページ（defrag していない）で説明がつき、スナップショットは DB SIZE と合うので、続ける。バックアップは取り直さない。defrag はこの作業ではしない（別件）
- worktree を片付ける前に、メインの checkout の `backup/` へ写す（coordinator）

## 5. 監視と一時的な名前空間（runbook §2.3）

- 12:12:01Z に、ハーネスのバックグラウンド実行で 2 つのジョブとして起動した（bg1: `dswatch.sh`、bg2: `probe.sh`）。`nohup`・`&` は使っていない。ログはタスクディレクトリの `notes/cnidaria-0-1-3/logs/`。最初の行は `ready=8`・`lh healthy=17`、`vip=200 gated4=404 gated6=404 h2sshd=OK`
- 12:12:15Z に `infra-admin` の 1 時間のトークンを `/tmp/k8u-cni013-admin-token`（0600）に発行した
- 12:12:20Z に `watch.sh up`（srv-a は pablo の `10.244.4.48`・`fde7:4ad6:425d:2::1:806e`、srv-b は .113 の `10.244.0.163`・`fde7:4ad6:425d:4::a3`）、12:12:21Z に `watch.sh clients`（cli-a は pablo、cli-b・cli-deny は chirico）。どれも 1〜2 秒で Ready
- 12:13:32Z の `watch.sh logs $L/pre`: cli-a 67 行、cli-b・cli-deny 68 行、最後の行は 12:13:30〜31。`FAIL` は cli-a・cli-b の作った直後の 1 行（12:12:22・12:12:23）だけで、その後は 0。`OPEN` は 0
- 12:13:36Z に `newpods.sh $L 300` をジョブ（bg3）として起動した。最初の 8 Pod は 8 台とも 0〜1 秒で Ready、8080 に 1 秒で届き、9090 は `BLOCKED`
