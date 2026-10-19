# 段 1 のまとめと完了の確認

本番 `fraction` の Kubernetes を v1.29.8 から v1.30.14 へ上げた段 1（porkadot 0.29.2 → 0.30.0、etcd 3.5.12 → 3.5.34、CoreDNS v1.10.1 → v1.11.3）の、全体のまとめと完了の確認（runbook §6）の記録。手順は `../../runbook-stage-1.md`（以下 runbook）。
時刻は UTC。作業の前のクラスタ全体と etcd のバックアップは `baseline.md`、`install kubernetes` は `control-plane.md`、各台の記録は `<ノード>.md`（control-plane は `192.168.1.11N.md`）。

## 1. 作業（2026-10-19）

| 順 | 対象 | 流した時刻（開始 → 終わり） | 監視の FAIL | 記録 |
|---|---|---|---|---|
| — | `etcd backup`（.111） | 00:45:32 → 00:45:35 | — | `baseline.md` §3 |
| 1 | `install kubernetes --node 192.168.1.111` | 00:47:50 → 00:48:18（rollout の終わり 00:51:02） | 0 | `control-plane.md` |
| 2 | 192.168.1.113（etcd のリーダーを .111 へ移した） | 01:03:05 → 01:03:58（00:52:56 と 00:58:49 の 2 回は SSH の接続で失敗。ノードは変わっていない） | 0 | `192.168.1.113.md` |
| 3 | 192.168.1.112 | 01:06:40 → 01:08:20 | 0 | `192.168.1.112.md` |
| 4 | 192.168.1.111（etcd のリーダーを .113 へ移した） | 01:10:18 → 01:10:47 | 0 | `192.168.1.111.md` |
| 5 | pablo | 01:12:52 → 01:13:39 | 0 | `pablo.md` |
| 6 | duchamp | 01:15:24 → 01:15:56 | 0 | `duchamp.md` |
| 7 | braque | 01:17:38 → 01:18:19 | 0 | `braque.md` |
| 8 | chirico | 01:20:08 → 01:20:35 | 0 | `chirico.md` |
| 9 | oeilvert | 01:34:09 → 01:34:36 | 0 | `oeilvert.md` |

- どの台でも、`install kubelet` でそのノードの Pod は再起動しなかった（control-plane では etcd の static Pod が新しいイメージで作り直されただけ）。Longhorn の replica は動かなかった。drain・cordon・ノードの再起動はしていない
- ロールバック（runbook §7）は一度も行っていない
- runbook から外れた操作（どれもユーザーの判断で承認を取った）:
  - `install kubelet` をサンドボックスの外で流した（.113 の 3 回目から全台。runbook §8.10）
  - coordinator が作業端末の `~/.ssh/known_hosts` の .112・.113 の行を並べ替えた（runbook §8.10）
  - `infra-admin` の短命トークンで、Completed の Pod を 7 つ消した（chirico の前後で 3 つ、oeilvert の前に 2 つ、後に 2 つ。runbook §8.11、`chirico.md` §4.1、`oeilvert.md` §1.3・§4.1）

## 2. 完了の確認（runbook §6。2026-10-19 01:41Z〜01:44Z）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready、全台 v1.30.14、CONTAINER-RUNTIME が 8 台とも `containerd://2.3.6`（段 C の版） |
| etcd | 3/3 healthy、全メンバーが 3.5.34、リーダー .113（`57ec6f12ac7b683e`）、raft term 23114、raft index 1402546238 でそろう。3 台の `/etc/etcd/pki` の 3 つのファイルが `600 root:root` |
| VIP | `/livez` `ok`、`/version` v1.30.14 |
| apiserver、controller-manager、scheduler、kube-proxy | kube-apiserver の DaemonSet 3/3（v1.30.14）。controller-manager 2/2（.111 の `-6pg99`、.113 の `-jg62c`。リーダー `-jg62c`）、scheduler 2/2（.111 の `-lffqk`、.112 の `-nbklj`。リーダー `-lffqk`）。同じ master に同じ component が 2 つ載っていない。kube-proxy 8/8、8 つともログに `Using iptables Proxier` |
| CoreDNS | v1.11.3、2/2 Running（duchamp、oeilvert） |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached unknown 2（`myao/myao`、`homegallery/cg-data`。ベースラインのとおり）。instance-manager 4 つとも running、engine image `longhorn-engine:v1.11.2` deployed、Longhorn の node 4 つとも Ready・schedulable。K8s 1.30 は Longhorn 1.11 の要件（1.25 以上）に入る |
| Longhorn の replica の置き場所 | ベースラインと同じ。ただし、ベースラインで duchamp にあった `natsumi/natsumi-aki`（pvc-e224cffa）の **stopped の replica `r-c01f02dd` が無くなった**。Longhorn が 01:21:21Z に `failed too long ago to be useful during a rebuild` として片付けた（前のタスクから stopped のままだった replica。段 C の `baseline.md` §2 の 5）。ボリュームは healthy、running の replica 2（chirico、oeilvert）、`numberOfReplicas` 2 |
| Longhorn の設定 | ベースラインのまま（`concurrent-replica-rebuild-per-node-limit` `5`、`replica-auto-balance` `disabled`、`node-drain-policy` `block-if-contains-last-replica`、`default-data-locality` `best-effort`、`current-longhorn-version` v1.11.2） |
| cnidaria | 8 台の Pod が 1/1。`verify-nodes.sh` 64 PASS、FAIL 0。`netcheck.sh` 168/168 PASS（01:41:15Z〜01:41:32Z。up → run → down）。chirico の `table inet cnidaria` に `hedgedoc/db-postgresql` を含む行が 10（ベースラインと同じ） |
| MetalLB | gated の `192.168.1.200` と `[...:ace::200]` の 80 は 404（応答あり）。`h2-sshd`（`::131`）、`natsumi-sshd`（`::132`）、`natsumi-sshd-myao`（`::133`）、`natsumi-sshd-aki`（`::134`）の 3222 が SSH のバナーを返す。minecraft は UDP なので確かめていない（ベースラインと同じ）。告知ノードはベースラインと同じ（段 1 の間に移ったものは無い） |
| NFS | braque の nfsd の Pod `nfsd-vt5k2` が Running。NFS の PV は Bound 14、Released 3（ベースラインのとおり）。oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で、中身が読める。`registry.fraction.jp/v2/` は 401（応答あり） |
| metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個。`apiserver_requested_deprecated_apis` は `metallb.io/v1beta1 addresspools`（`removed_release` なし）だけ（ベースラインと同じ） |
| CSR | 無い（段の間に新しい CSR は出ていない。kubelet は証明書を持ち越した） |
| 監視 | 下の 2.2 |
| leader election で再起動した controller | 無い（2.1） |

### 2.1 warning のイベント・ログ

- runbook §8 にあるもの: 各台の kubelet の再起動の直後の `InvalidDiskCapacity`（§8.6）と Node の `NodeNotReady`（kubelet の再起動のたびに 1 回）、対象のノードの cnidaria の `Reconciler error ... no route`（6〜8 件、1 秒ほど。§8.1。oeilvert だけは出なかった）とほかのノードの info の `no route for a family`
- `install kubernetes` の rollout で消える古い Pod の readiness の失敗（`connection refused`）
- etcd の Pod の作り直し（01:03:56Z、01:08:19Z、01:10:46Z）のときだけ: ほかの etcd の `lost TCP streaming connection with remote peer`、`peer became inactive`、apiserver の `watch chan error: … malformed header`。それぞれ数秒で止まった
- Longhorn の node の一瞬の not ready（`Node … is down: manager pod … is not running`、`Waiting for disk …`）。Longhorn のノード 4 台の kubelet の再起動の直後に 1 回ずつ。replica は動いていない（auto-balance `disabled`。runbook §2.6）
- **Longhorn の `no Pending workload pods`（longhorn/longhorn#8072 の形）**: chirico の `natsumi-myao-0`・`deep-researcher-0`、oeilvert の `natsumi-0`・`natsumi-aki-0` で、kubelet の再起動の後に FailedMount が続いた。同じ PVC の Completed の Pod を消して止めた。Pod は 4 つとも再起動していない（runbook §8.11、`chirico.md` §4.1、`oeilvert.md` §4.1）
- braque の古い kubelet の `Failed to update lease`（`systemd-networkd` の再起動で VIP への接続が reset された。1 回。`braque.md` §7）
- 段 1 の作業と結びつかないもの: `pondo2/movies-75b8fb88bf-67x2g`（chirico）が 01:01:27Z に OOMKilled で再起動した（3 時間動いた後。chirico の作業の前で、そのときはどのノードも触っていない）。`shja2`・`carib2` の `movies` の liveness・readiness の失敗と、`natsumi-aki-0` の runner の socket の liveness の失敗はベースラインの前から出ている
- kubelet、apiserver、kube-proxy、cnidaria、etcd のログに、上のもの以外の新しい warning は見ていない

### 2.2 監視（runbook §2.3）の FAIL

監視は 00:43:03Z から 01:43:36Z まで（`ok` の行が 3360 回目まで）流し、ログはタスクディレクトリの `notes/stage-1/stage-1-probe.log` に置いた。**段 1 の全体で VIP も LB（gated-v4）も FAIL 0**（dev と同じ。段 C の VIP 21、LB 2 とは違い、apiserver も告知しているノードも止まらなかった）。

| 原因 | VIP | LB |
|---|---|---|
| apiserver の入れ替わり（`install kubernetes`） | 0 | 0 |
| 告知ノード（pablo の kubelet の再起動） | 0 | 0 |
| gated の再起動 | 0 | 0 |
| それ以外 | 0 | 0 |

## 3. 片付けと、残したこと

- `infra-admin` のトークン: 01:30:19Z に 2 時間の期限で発行し、作業端末の `/tmp` のモード 600 のファイルに置いた。§2 の後にファイルを消した（トークンは 03:30Z に期限が切れる。TokenRequest のトークンは 1 つだけを失効させられない）
- 監視は止めた
- etcd のバックアップ `etcd-2026-10-19T00:45:32+00:00.db` は段 1 の worktree の `./backup/` にある。worktree を片付ける前に、メインの checkout の `backup/` へ移す（coordinator）
- 段 2 以降の手順書に引き継ぐこと: runbook §8.10（porkadot の SSH。SSHKit の known_hosts とサンドボックスの ssh-agent）、§8.11（kubelet の再起動の前に、同じ PVC の Completed の Pod をノードを問わず消す）、§8.1（cnidaria のログの形）
- 根本の対策（タスクのバックログ）: porkadot の SSHKit の known_hosts の扱い、Longhorn の #8072 の形（CronJob の `successfulJobsHistoryLimit` や Job の `ttlSecondsAfterFinished` で Completed の Pod を残さない、など）
