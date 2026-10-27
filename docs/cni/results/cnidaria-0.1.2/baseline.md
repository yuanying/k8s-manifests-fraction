# cnidaria v0.1.2 のベースライン

本番 `fraction` の cnidaria を v0.1.1 から v0.1.2 にする（porkadot 0.37.4 → 0.37.5、`porkadot.yaml` の `addons.cnidaria.image_tag` の pin を外す）前に取った、読み取りの結果と、イメージの事前 pull、etcd のバックアップ、監視と一時的な名前空間の起動の記録。手順は `../../runbook-cnidaria-0.1.2.md`（以下 runbook）。
時刻は UTC。`snap.sh`・`nodes.sh`・`verify-nodes.sh`・`check-apps.sh`・`dns-check.sh` の出力は、タスクディレクトリの `notes/cnidaria-0-1-2/base/` に置いた（リポジトリには入れない）。

## 1. 前提（runbook §1。2026-10-27 10:37Z）

| 項目 | 結果 |
|---|---|
| 本番の今の姿（§1.1） | 8 台 Ready・schedulable、v1.37.1、`containerd://2.3.6`。etcd 3/3 healthy。Pod 160 個（Running 136、Succeeded 24）で、Running / Completed 以外は 0 個。cnidaria は v0.1.1 の DaemonSet（generation 3、8/8 Ready、updated 8） |
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor`。作業端末の kubectl は v1.37.1 |
| SSH（§1.3） | サンドボックスの中から、8 台に IP で `nodes.sh`・`verify-nodes.sh`・`prepull.sh`・`df` を流せた |
| porkadot（§1.4） | `worktrees/porkadot-v0-37-5` は `git describe --tags` が `v0.37.5`（`aacfba7`）、作業ツリーに変更が無い。`porkadot help` が動く。§6 の戻しの `worktrees/porkadot-v0-37-4` は `v0.37.4`、変更なし。cwd は worktree `cnidaria-0-1-2-prod`（base は PR #67 をマージした master の `f9d976e`）。`git status --short assets porkadot.yaml` は空、`grep -n image_tag porkadot.yaml` は何も返さない、`cnidaria.yaml` のイメージは `v0.1.2` |
| 入れる版（§1.5。10:37Z） | `ghcr.io/yuanying/cnidaria-cni:v0.1.2` の index は `sha256:68756535d44a…`、linux/amd64 `sha256:6d70ce4d…`（config `497c4354be2d`）、linux/arm64 `sha256:93374551…`（config `726fe8469ab5`）、ほかに `unknown/unknown` が 2 つ。runbook の表と同じ |
| 時間帯（§2.7） | 10:37Z に始めた（10:00〜17:30Z の中） |
| `env-fraction.sh` の `FRACTION` | 既定の `worktrees/runbook-cnidaria-0-1-2` はもう無い（#67 の後に片付けた）。`FRACTION_CHECKOUT` をこの worktree にして流した（runbook を直した） |

## 2. ベースライン（runbook §2.2。10:37:36Z の `snap.sh`、10:38:07Z の `nodes.sh`）

runbook §2.2 の表の値（03:1xZ）と、すべての項目で同じだった。`cni-bin.txt`・`conflist.txt`・8 台の `nft-<ノード>.txt`・`state.txt`・`dns-check.txt`・`gens.tsv` は 03:1xZ の出力（`notes/runbook-cnidaria-0-1-2/base-20261027/`）とバイトまで同じ。`pods.tsv` の差は `aphrael/tumblr-like` の CronJob の Pod 3 つの入れ替わりと、`fs/data-backup` の Pod 1 つが消えたことだけ。

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node | 8 台 Ready、v1.37.1、`containerd://2.3.6`、cordon されたものは無い |
| 2 | 全 Pod | 160 個（Running 136、Succeeded 24）。Running / Completed 以外は 0 個。名前・UID・restartCount は `base/pods.tsv` |
| 3 | DaemonSet `cnidaria` | generation 3（observed 3）、desired・ready・updated・available 8。イメージ `ghcr.io/yuanying/cnidaria-cni:v0.1.1`。`updateStrategy` は RollingUpdate（`maxSurge: 0`・`maxUnavailable: 1`）。ほかの項目も runbook §2.2 の 3 のとおり |
| 4 | cnidaria の Pod | 8 つとも v0.1.1・Ready、2026-10-20 05:04:47〜05:04:58Z の起動、`controller-revision-hash` `69d47f6475`。imageID は amd64 が `sha256:effbb078…`、arm64 が `sha256:0657905b…`。restartCount は `cnidaria-bs2vm`（.112）と `cnidaria-s2zpl`（oeilvert）が 2、ほかの 6 つは 0 |
| 5 | containerd の cnidaria-cni のイメージ | v0.1.2 は 8 台とも無い。v0.1.1 は 8 台にある。v0.1.0 は oeilvert のほかの 7 台にある |
| 6 | ControllerRevision | 4 つ（revision 1〜4。`5454fc8457`・`548546d767`・`69d47f6475`・`74d46565f`） |
| 7 | cnidaria のログ | 17,033 行、info 16,812、**error 221**、ほかは 0。error の最後は 2026-10-23 22:44:40Z（段 8 の kubelet の再起動のとき）。10-24 以降の error は 0 |
| 8 | NetworkPolicy | 6 つ、すべて `longhorn-system` |
| 9 | `/opt/cni/bin` | 8 台とも 21 ファイル、版の印 `v1.9.1`、4 つの plugins は `CNI … plugin v1.9.1`。cnidaria のバイナリは無い。sha256 は runbook §2.2 の表と同じ |
| 10 | conflist | 8 台とも `/etc/cni/net.d/10-cnidaria.conflist` の 1 つだけ。sha256 は runbook §2.2 の 10 と同じ |
| 11 | nftables | 8 台とも `table inet cnidaria` がある。行の数は control-plane 3 台と braque が 110、chirico・duchamp・oeilvert・pablo が 265（`longhorn-system/` のコメントの行が 47） |
| 12 | 経路 | 8 台とも proto 200 の経路が v4 7・v6 7。`verify-nodes.sh` は PASS 64 / 64、FAIL 0、rc 0 |
| 13 | kubelet | .111 MainPID 752609・NRestarts 0、.112 1028・1、.113 612672・0、braque 541944・0、chirico 3237977・0、duchamp 202232・0、oeilvert 916805・51、pablo 3509679・0 |
| 14 | host-local の割り当て | .111 6、.112 2、.113 6、braque 2、chirico 78、duchamp 40、oeilvert 43、pablo 28 |
| 15 | Longhorn | ボリューム 14、すべて attached・healthy（アタッチ先は chirico 10、duchamp 2、oeilvert 2） |
| 16 | LoadBalancer・VIP・NFS・etcd | gated-v4・gated-v6 が 404、VIP の `/readyz` が 200、`::131`〜`::134` の 3222 が SSH のバナー、`registry.fraction.jp/v2/` が 401、oeilvert の `/home/yuanying/shared/nfs` が `192.168.1.131:/` の nfs4 で読める。etcd 3/3 healthy。`check-apps.sh` は duplicates 0 |
| 17 | ディスク（`/var/lib/containerd`） | .111 10%、.112 9%、.113 9%、braque 18%、chirico 26%、duchamp 41%、**oeilvert 82%（残り 82 GB）**、pablo 32% |

名前空間 `homegallery` とそのボリュームは無い（ユーザーが意図して消した。2026-10-27 に確認済み）。

## 3. イメージの事前 pull（runbook §2.4。10:38:46〜10:39:25Z）

`prepull.sh` を 1 台ずつ流した（出力は `notes/cnidaria-0-1-2/prepull.txt`）。8 台とも `rc=0`。

| ノード | 秒 | イメージ ID |
|---|---|---|
| 192.168.1.111 | 4 | `726fe8469ab50`（55.5 MB） |
| 192.168.1.112 | 3 | 同上 |
| 192.168.1.113 | 3 | 同上 |
| braque | 6 | `497c4354be2dd`（57.3 MB） |
| chirico | 3 | 同上 |
| duchamp | 3 | 同上 |
| oeilvert | 2 | 同上 |
| pablo | 4 | 同上 |

イメージ ID は runbook §1.5 の config と同じ。pull の後の oeilvert の `/var/lib/containerd` は 82%（353 GB 使用、残り 82 GB）で変わらない。

## 4. etcd のバックアップ（runbook §2.5。10:39:31〜10:39:35Z）

porkadot 0.37.5 の `etcd backup` を worktree のルートで流した（rc 0。出力は `notes/cnidaria-0-1-2/etcd-backup.log`）。流す前と後で `git status --short` は空。

| ファイル | 置き場所 | バイト | sha256 |
|---|---|---|---|
| `etcd-2026-10-27T10:39:31+00:00.db`（モード 0600） | worktree `cnidaria-0-1-2-prod` の `./backup/`（git には入れない） | 68,919,328 | `e25ea63730e171b7d1da117fa2b1314131b5dd78df04314702a84c074ebd340e` |

メインの checkout の前のもの（`backup/etcd-2026-10-26T07:02:07+00:00.db`、66,986,016 B）より 1,933,312 B（3%）大きい。桁は同じなので、runbook §2.5 の止める条件には当たらない。worktree を片付ける前に、メインの checkout の `backup/` へ写す（coordinator）。

## 5. 監視と一時的な名前空間（runbook §2.3）

- 10:39:4xZ に、ハーネスのバックグラウンド実行で 2 つのジョブとして起動した（bg1: `dswatch.sh`、bg2: `probe.sh`）。`nohup`・`&` は使っていない。ログはタスクディレクトリの `notes/cnidaria-0-1-2/logs/`。最初の行は `ready=8`・`lh healthy=14`、`vip=200 gated4=404 gated6=404 h2sshd=OK`
- 10:39:54Z に `infra-admin` の 1 時間のトークンを `/tmp/k8u-cni012-admin-token`（0600）に発行した
- 10:39:55Z に `watch.sh up`（srv-a は pablo の `10.244.4.237`・`fde7:4ad6:425d:2::1:802e`、srv-b は .113 の `10.244.0.101`・`fde7:4ad6:425d:4::65`）、10:39:56Z に `watch.sh clients`（cli-a は pablo、cli-b・cli-deny は chirico）。どれも 1〜2 秒で Ready
- 10:41:02Z の `watch.sh logs $L/pre`: cli-a・cli-b・cli-deny とも 63 行、最後の行は 10:41:00〜01。`FAIL` は cli-a・cli-b の作った直後の 1 行（10:39:57・10:39:58。許可がまだ効く前）だけで、その後は 0。`OPEN` は 0
- 10:41:06Z に `newpods.sh $L 300` をジョブ（bg3）として起動した。最初の 8 Pod は 8 台とも 0〜1 秒で Ready、8080 に 1〜2 秒で届き、9090 は `BLOCKED`
