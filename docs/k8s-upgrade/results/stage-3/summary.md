# 段 3 のまとめと完了の確認

本番 `fraction` の Kubernetes を v1.31.14 から v1.32.13 へ上げた段 3（porkadot 0.31.0 → 0.32.0、crictl v1.32.0、CNI plugins v1.9.1、CoreDNS v1.11.4。etcd 3.5.34 は据え置き）の、全体のまとめと完了の確認（runbook §6）の記録。手順は `../../runbook-stage-3.md`（以下 runbook）。
時刻は UTC。作業の前のクラスタ全体、etcd のバックアップ、storage version の書き直しは `baseline.md`、`install kubernetes` は `control-plane.md`、各台の記録は `<ノード>.md`（control-plane は `192.168.1.11N.md`）。読み取りの出力はタスクディレクトリの `notes/stage-3/`（完了の確認は `final/`）。

## 1. 作業（2026-10-19）

porkadot のコマンドとノードへの `ssh` は、すべてサンドボックスの中（ssh-agent なし）で流し、SSH の失敗は一度も無かった。どのノードも drain していない。

| 順 | 対象 | 流した時刻（開始 → 終わり） | Pod の再起動 | 監視の FAIL | 記録 |
|---|---|---|---|---|---|
| — | `etcd backup`（.111） | 23:13:51 → 23:13:55 | — | — | `baseline.md` §3 |
| — | storage version の書き直し（FlowSchema 13、PriorityLevelConfiguration 8、EndpointSlice 11） | 23:15:17 → 23:15:25 | — | 0 | `baseline.md` §4 |
| 1 | `install kubernetes --node 192.168.1.111` | 23:17:31 → 23:17:55（rc 0。rollout の終わり 23:20:29） | 作り直し 17 個のほかは無い | 0 | `control-plane.md` |
| 2 | 192.168.1.113（etcd のリーダーを .111 へ移した） | 23:25:03 → 23:26:12 | etcd の mirror Pod だけ | 0 | `192.168.1.113.md` |
| 3 | 192.168.1.112 | 23:28:20 → 23:28:42 | etcd の mirror Pod だけ | 0 | `192.168.1.112.md` |
| 4 | 192.168.1.111（etcd のリーダーを .113 へ移した） | 23:30:51 → 23:31:12 | etcd の mirror Pod だけ | 0 | `192.168.1.111.md` |
| 5 | duchamp（netcheck と NetworkPolicy の確認） | 23:33:17 → 23:33:48 | 無い | 0 | `duchamp.md` |
| 6 | pablo（API の VIP を告知） | 23:39:39 → 23:40:36 | 無い | 0 | `pablo.md` |
| 7 | braque（JST 08:42。バックアップの時間帯の外） | 23:42:45 → 23:43:20 | 無い（nfsd も） | 0 | `braque.md` |
| 8 | oeilvert（Completed の Pod を 2 つ消してから） | 23:45:45 → 23:46:11 | 無い | 0 | `oeilvert.md` |
| 9 | chirico（Completed の Pod を 2 つ消してから） | 23:48:49 → 23:49:13 | 無い | 0 | `chirico.md` |

- `install kubernetes` は 1 回目で rc 0 だった（apiserver の rollout が .112 から始まり、runbook §8.3 の `connection refused` に当たらなかった）
- ロールバック（runbook §7）は一度も行っていない。runbook の止める条件（etcd の mirror Pod のほかのコンテナの再起動、iscsid の PID の変化、古い iSCSI のセッション、storage version の書き直しで想定外のもの）には一度も当たらなかった
- runbook から外れた操作（ユーザーの承認を取った）: oeilvert と chirico の `install kubelet` の前に、Running の Pod と同じ Longhorn の PVC を使う Completed の Pod を 4 つ消した（runbook §8.12。`natsumi-backup-29874030-7m9fw`、`natsumi-backup-aki-29874030-tf9gj`、`deep-researcher-backup-29874060-hg5hn`、`natsumi-backup-myao-29874030-bxqpd`。どれもバックアップの CronJob の JST 05:30・06:00 の Job の Pod。`oeilvert.md` §1.3、`chirico.md` §1.3）

## 2. 完了の確認（runbook §6。2026-10-19 23:50Z〜23:56Z）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready、全台 v1.32.13、CONTAINER-RUNTIME が 8 台とも `containerd://2.3.6`。SchedulingDisabled のノードは無い |
| `/opt/bin`、CNI | 8 台とも `kubelet-v1.32.13`、`kubectl-v1.32.13`、`crictl-v1.32.0`、`etcdctl-3.5.34`。**CNI の印が 8 台とも `v1.9.1`、bridge・host-local・portmap・loopback が 8 台とも v1.9.1**（porkadot と cnidaria の版がそろった。runbook §8.11） |
| etcd | 3/3 healthy、全メンバーが 3.5.34、リーダー .113（`57ec6f12ac7b683e`）、raft term 23118、raft index がそろう。DB 55 MB。3 台の `/etc/etcd/pki` の 3 つのファイルが `600 root:root` |
| VIP | `/readyz` `ok`、`/version` v1.32.13 |
| apiserver、controller-manager、scheduler、kube-proxy | kube-apiserver の DaemonSet 3/3（v1.32.13、generation 26。`-z2pdq` .111、`-2nccn` .112、`-hksh7` .113、restartCount 0）。controller-manager 2/2（.112 `-9cxxw` リーダー、.113 `-qmv4n`）、scheduler 2/2（.112 `-c5dxt` リーダー、.111 `-wf5xr`）。kube-proxy 8/8（v1.32.13）、8 つともログに `Using iptables Proxier` |
| CoreDNS | **v1.11.4、2/2 Running**（chirico `-8jmd5`、duchamp `-v6zg8`、generation 10） |
| kubelet-serving-cert-approver | `0.12.1`、1/1 Running（oeilvert、restartCount 0） |
| Running / Completed 以外の Pod | 0 |
| restartCount | §2.1 |
| storage version | `tools/storage-versions.sh`: `prefixes: 64, keys: 2428, OLD: 0, CRDs with more than one stored version: 0`。47 個の CRD の `status.storedVersions` が 1 つ（`crds.tsv` が 47 行とも `ok`）。`v1beta3.flowcontrol.apiserver.k8s.io` の APIService は 1.32 の apiserver で消えた（`control-plane.md` §3 の 16） |
| Longhorn | attached healthy 16、detached unknown 1（`homegallery/cg-data`。ベースラインのとおり）。instance-manager 4 つとも running で段の前と同じ名前・IP。engine image `longhorn-engine:v1.11.2` が deployed。Longhorn の node 4 つとも Ready、schedulable。replica は chirico 11（running 10）、duchamp 10（running 8）、oeilvert 11（running 10）、pablo 2（ベースラインと同じ）。K8s 1.32 は Longhorn 1.11 の要件（1.25 以上）に入る |
| Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit` `5`、`replica-auto-balance` `disabled`、`node-drain-policy` `block-if-contains-last-replica`、`default-data-locality` `best-effort`、`replica-replenishment-wait-interval` `6000`（ベースラインのまま） |
| iSCSI | 8 台の `tools/node-state.sh`（`notes/stage-3/final/node-<ノード>-after.txt`）で、iscsid の MainPID と起動の時刻がベースラインと同じ（duchamp は 23:33:45Z の `install kubelet` で起動した PID 663628）。Longhorn のセッションは pablo 1、oeilvert 5、chirico 10 で、どれもそのノードの今の instance-manager の IP へのもの。古いセッションは無い。`older-than-iscsid` のエンジンは chirico の 1 つ（ベースラインと同じ）で増えていない。`initiatorname.iscsi` の md5 は 8 台とも同じ |
| cnidaria | 8 台の Pod が Ready（restartCount はベースラインと同じ）。`verify-nodes.sh` 64 PASS、FAIL 0（`cnidaria logs: errors=51` は各台の `install kubelet` の `no route` の 6〜8 件の合計。runbook §8.1）。✋ `netcheck.sh`（23:50Z）168/168 PASS |
| NetworkPolicy（runbook §1.9） | ✋ `npcheck.sh`（23:51:02Z〜23:53:32Z）: up の前の `nft` は 8 台とも 0、up の後は 8 台とも 9、`run` は `OK 56, not OK 0`、down の後は 8 台とも 0、`k8u-npcheck` は NotFound。duchamp の後（23:36Z〜23:38Z）にも同じ結果 |
| MetalLB | gated の `192.168.1.200` と `[...:ace::200]` は 404（応答あり）。`h2-sshd`（`::131`）、`natsumi-sshd`（`::132`）、`natsumi-sshd-myao`（`::133`）、`natsumi-sshd-aki`（`::134`）は SSH のバナーを返す。告知ノードは段の前と同じ（VIP pablo、gated-v4 chirico、gated-v6 oeilvert、`::131`・`::134` .112、`::132` .111、`::133` duchamp）。minecraft は UDP なので確かめていない |
| NFS、registry | oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で中身が読める。braque は 2049 を listen している。`registry.fraction.jp/v2/` は 401（応答あり） |
| metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個。`apiserver_requested_deprecated_apis` は `metallb.io/v1beta1 addresspools`（`removed_release` なし）だけ（`flowcontrol.apiserver.k8s.io/v1beta3` を使うクライアントは無い） |
| CSR | 段の間に出た CSR は無い。8 台の kubelet の serving の証明書の subject と期限はベースラインと同じ |

### 2.1 restartCount（ベースラインからの比べ）

- ベースラインの Pod（152 個）のうち、段 3 の間ずっと動き続けたもの（名前が同じもの）は、**restartCount がすべて同じ**。UID が変わったのは control-plane の etcd の mirror Pod の 3 つだけ（restartCount は `etcd=1` のまま。runbook §4.1）
- `install kubernetes` で作り直されたもの（apiserver 3、controller-manager 2、scheduler 2、kube-proxy 8、CoreDNS 2）は、新しい名前・UID で 17 個とも restartCount 0
- 消えたもの: 上の 17 個の前の Pod と、§1 で消した Completed の Pod 4 つ
- **1.32 の kubelet への更新で、コンテナの再起動は 8 台で 1 つも無かった**（runbook §8.4 のとおり。Longhorn の instance-manager、longhorn-manager、CSI、nfsd、prometheus を含む）

### 2.2 warning のイベント・ログ

- runbook §8 にあるもの: 各台の `InvalidDiskCapacity`、置き換えられた古い apiserver の止まりかけの間の probe の失敗、各台の cnidaria の `no route`（error 6〜8 件、1 秒ほど。oeilvert は 0）、etcd の `lost TCP streaming connection`・`peer became inactive`（1.1〜1.2 秒）、etcd の mirror Pod の `already exists`、古い kubelet の `Failed to update lease`（braque。`systemd-networkd` の再起動）
- runbook に無かったもの（どれも一時的で、続かない）:
  - Longhorn の node のイベント `Node <ノード> is down: manager pod ... is not running` と `Waiting for disk ... to be ready / schedulable`（duchamp・pablo・oeilvert・chirico の kubelet の再起動の数秒。longhorn-manager は再起動していない）
  - kubelet の起動の直後の `Error getting the current node from lister`、cadvisor の `RecentStats: unable to find data in memory cache`（.111）、info の `Failed to trigger a manual run probe="Readiness"`（oeilvert、chirico）
  - apiserver の `Error on socket receive: ... use of closed network connection`（`netcheck.sh`・`npcheck.sh` の `kubectl exec` の間だけ。VIP を告知する pablo から来る接続）、pablo の `systemd-networkd` の再起動のときの watch の `connection reset by peer`、23:46Z の `v1beta1.metrics.k8s.io` の APIService の更新の衝突（1 回）
- kube-proxy、CoreDNS、etcd の Pod のログに、23:21Z より後の error は無い

### 2.3 監視（runbook §2.3）の FAIL

監視は 23:00Z から 23:56Z まで（`ok` の行が 3120 回目まで）流し、ログはタスクディレクトリの `notes/stage-3/stage-3-probe.log` に置いた。**FAIL は VIP・LB とも 0 回**（`install kubernetes` の apiserver の rollout、etcd の起き直し、VIP と gated-v4 の告知ノードの `install kubelet` の間も途切れなかった）。

### 2.4 leader election で再起動した controller（runbook §8.8）

無い（`gated-system/gated` の 2 つ、`longhorn-system` の CSI sidecar 12 個とも restartCount 0 のまま。controller-manager と scheduler のリーダーも `install kubernetes` の後から変わっていない）。

## 3. 片付けと、残したこと

- 一時的な名前空間 `cnidaria-netcheck`・`k8u-npcheck` は消した（NotFound）
- `infra-admin` のトークン: storage version の書き直し（23:15Z）、duchamp の後の NetworkPolicy の確認（23:35Z）、oeilvert（23:45Z）、chirico（23:48Z）、完了の確認（23:51Z）で 1 時間の期限で発行し、どれも作業端末の `/tmp` のモード 600 のファイルに置いて、使い終えた直後に消した（最後は 23:53Z。サーバーの側では最も遅いもので 00:51Z に期限が切れる）
- 監視は 23:56Z に止めた
- etcd のバックアップ `etcd-2026-10-19T23:13:51+00:00.db`（55,107,616 バイト、sha256 `e716b97366c9a14b9ddf6a6dab07734e6c0f33415020b6e6c1e6fe72443c157e`）は段 3 の worktree の `./backup/` にある。worktree を片付ける前に、メインの checkout の `backup/` へ移す（coordinator）
- duchamp の iscsid は段 3 で起動したまま（`iscsid.socket` のソケット起動の後と同じ状態。ボリュームもセッションも無い）
- 段 4 以降の手順書に引き継ぐこと: 早朝（JST 05:30・06:00）のバックアップの CronJob の後は runbook §8.12 の Completed の Pod が残る（段 3 では承認を取って消した）、Longhorn の node の一瞬の down のイベントは kubelet の再起動で出る、`install kubernetes` の rc は apiserver の rollout の順で変わる
