# 段 4 のまとめと完了の確認

本番 `fraction` の Kubernetes を v1.32.13 から v1.33.13 へ上げた段 4（porkadot 0.32.0 → 0.33.0、crictl v1.33.0、CoreDNS v1.11.4 → v1.12.4。etcd 3.5.34・CNI plugins v1.9.1 は据え置き）の、全体のまとめと完了の確認（runbook §6）の記録。手順は `../../runbook-stage-4.md`（以下 runbook）。
時刻は UTC。作業の前のクラスタ全体、etcd のバックアップ、storage version の確認は `baseline.md`、`install kubernetes` は `control-plane.md`、各台の記録は `<ノード>.md`（control-plane は `192.168.1.11N.md`）。読み取りの出力はタスクディレクトリの `notes/stage-4/`（完了の確認は `final/`）。

## 1. 作業（2026-10-20）

porkadot のコマンドとノードへの `ssh` は、すべてサンドボックスの中（ssh-agent なし）で流し、SSH の失敗は一度も無かった。どのノードも drain していない。

| 順 | 対象 | 流した時刻（開始 → 終わり） | Pod の再起動 | 監視の FAIL | 記録 |
|---|---|---|---|---|---|
| — | `etcd backup`（.111） | 02:00:34 → 02:00:38 | — | — | `baseline.md` §3 |
| 1 | `install kubernetes --node 192.168.1.111` | 02:02:18 → 02:02:37（**rc 1**、runbook §8.3）。rollout の終わり 02:05:19。流し直し 02:05:35 → 02:06:02（rc 0、2 回目の rollout なし） | 作り直し 17 個のほかは無い | 0 | `control-plane.md` |
| 2 | 192.168.1.113（etcd のリーダーを .111 へ移した） | 02:11:33 → 02:12:24 | etcd の mirror Pod だけ | 0 | `192.168.1.113.md` |
| 3 | 192.168.1.112 | 02:14:59 → 02:15:21 | etcd の mirror Pod だけ | 0 | `192.168.1.112.md` |
| 4 | 192.168.1.111（etcd のリーダーを .113 へ移した） | 02:17:54 → 02:18:10 | etcd の mirror Pod だけ | 0 | `192.168.1.111.md` |
| 5 | duchamp（netcheck と NetworkPolicy の確認） | 02:20:57 → 02:21:13 | 無い | 0 | `duchamp.md` |
| 6 | pablo（API の VIP を告知） | 02:27:29 → 02:27:47 | 無い | 0 | `pablo.md` |
| 7 | braque（JST 11:30。バックアップの時間帯の外） | 02:30:01 → 02:30:22 | 無い（nfsd も） | 0 | `braque.md` |
| 8 | oeilvert | 02:32:15 → 02:32:32 | 無い | 0 | `oeilvert.md` |
| 9 | chirico | 02:35:19 → 02:35:35 | 無い | 0 | `chirico.md` |

- `install kubernetes` の 1 回目は rc 1 だった。apiserver の rollout が .111 から始まり、.111 の上の `kubectl apply` の残り（MetalLB の `L2Advertisement` と `ValidatingWebhookConfiguration`）が `127.0.0.1:6443` の `connection refused` になった（runbook §8.3 の形）。runbook §3.2 のとおり rollout の完了を待って流し直し、rc 0 で、DaemonSet `kube-apiserver` の generation は 27 のままだった
- ロールバック（runbook §7）は一度も行っていない。runbook の止める条件（etcd の mirror Pod のほかのコンテナの再起動、iscsid の PID の変化、古い iSCSI のセッション、storage version の想定外の OLD）には一度も当たらなかった
- runbook から外れた操作は無い。runbook §8.12 の Completed / Succeeded の Pod の削除は、当たるものが無かったので行っていない（どの台でも、当たったのは NFS の `aphrael/aphrael-2` の `tumblr-like` の Pod だけ）
- 192.168.1.112 の `install kubelet` の前の coordinator への知らせ（✋）は、herdr を複合コマンドに入れたためサンドボックスで拒否されて届かず、事後に送った（`192.168.1.112.md` §3）

## 2. 完了の確認（runbook §6。2026-10-20 02:38Z〜02:46Z）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready、全台 v1.33.13、CONTAINER-RUNTIME が 8 台とも `containerd://2.3.6`。SchedulingDisabled のノードは無い |
| `/opt/bin`、CNI | 8 台とも `kubelet-v1.33.13`、`kubectl-v1.33.13`、`crictl-v1.33.0`、`etcdctl-3.5.34`。CNI の印と bridge・host-local・portmap・loopback が 8 台とも `v1.9.1` |
| etcd | 3/3 healthy、全メンバーが 3.5.34、リーダー .113（`57ec6f12ac7b683e`）、raft term 23120、raft index がそろう。DB 55 MB。3 台の `/etc/etcd/pki` の 3 つのファイルが `600 root:root` |
| VIP | `/readyz` `ok`、`/livez` 200（監視）、`/version` v1.33.13 |
| apiserver、controller-manager、scheduler、kube-proxy | kube-apiserver の DaemonSet 3/3（v1.33.13、generation 27。`-6kv5q` .111、`-mjvwf` .112、`-g9jhl` .113、restartCount 0）。controller-manager 2/2（.111 `-9wqgd`、.113 `-fw4lb` リーダー）、scheduler 2/2（.113 `-l2qfv`、.112 `-8kt9t` リーダー）。kube-proxy 8/8（v1.33.13）、8 つともログに `Using iptables Proxier` |
| CoreDNS | **v1.12.4、2/2 Running**（chirico `-bt9pk`、duchamp `-fj8j8`、generation 11）。ログは起動の行だけでエラーは無い。runbook §3.3 の 13 の問い合わせ（02:39Z）は `control-plane.md` §3 と同じ答えで、hostname の無い Endpoint の Pod の IP の逆引きも引ける |
| kubelet-serving-cert-approver | `0.12.1`、1/1 Running（oeilvert、restartCount 0） |
| Running / Completed 以外の Pod | 0 |
| restartCount | §2.1 |
| storage version | `tools/storage-versions.sh`: `prefixes: 66, keys: 2601, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は 2 行（`/registry/ipaddresses/`、`/registry/servicecidrs/` が `networking.k8s.io/v1beta1`）、`summary.tsv` の IPAddress 74 と ServiceCIDR 1 は v1beta1 の `ok`。47 個の CRD の `status.storedVersions` が 1 つ（`crds.tsv` が 47 行とも `ok`）。prefix は `install kubernetes` の後から増えていない |
| ServiceCIDR と IPAddress | `servicecidrs` は `kubernetes` の 1 つ（`10.254.0.0/24,fd20:afc2:7c09::/108`、`Ready=True`）。IPAddress は 74 で、ClusterIP の数（Service 79 個、ClusterIP を持つもの 71 個、dual-stack 3 個）と同じ。`ClusterIPNotAllocated` の event は 71 件で、どれも 02:03:24Z〜02:03:25Z（`install kubernetes` の直後）のもの。その後は出ていない |
| Longhorn | attached healthy 16、detached unknown 1（`homegallery/cg-data`。ベースラインのとおり）。instance-manager 4 つとも running で段の前と同じ名前・IP。engine image `longhorn-engine:v1.11.2` が deployed。Longhorn の node 4 つとも Ready、schedulable。replica は chirico 11（running 10）、duchamp 10（running 8）、oeilvert 11（running 10）、pablo 2（ベースラインと同じ）。K8s 1.33 は Longhorn 1.11 の要件（1.25 以上）に入る |
| Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit` `5`、`replica-auto-balance` `disabled`、`node-drain-policy` `block-if-contains-last-replica`、`default-data-locality` `best-effort`、`replica-replenishment-wait-interval` `6000`（ベースラインのまま） |
| iSCSI | 8 台の `tools/node-state.sh`（`notes/stage-4/final/node-<ノード>-after.txt`）で、`bin` の行のほか（iscsid の MainPID と起動の時刻、セッション、エンジン、`initiatorname.iscsi` の md5）が 8 台ともベースラインと同じ（duchamp も段 3 で起動した PID 663628 のまま）。Longhorn のセッションは pablo 1、oeilvert 5、chirico 10 で、どれもそのノードの今の instance-manager の IP へのもの。古いセッションは無い。`older-than-iscsid` のエンジンは chirico の 1 つ（ベースラインと同じ）で増えていない |
| cnidaria | 8 台の Pod が Ready（restartCount はベースラインと同じ）。`verify-nodes.sh` 64 PASS、FAIL 0（cnidaria のログの error は各台の `install kubelet` の `no route` の 7〜8 件ずつ。oeilvert は 0。runbook §8.1）。✋ `netcheck.sh`（02:42:35Z〜02:42:54Z）168/168 PASS |
| NetworkPolicy（runbook §1.9） | ✋ `npcheck.sh`（02:43:01Z〜02:45:37Z）: up の前の `nft` は 8 台とも 0、up の後は 8 台とも 9、`run` は `OK 56, not OK 0`（PASS 24、BLOCK 32）、down の後は 8 台とも 0、`k8u-npcheck` は NotFound。duchamp の後（02:23Z〜02:26Z）にも同じ結果 |
| MetalLB | gated の `192.168.1.200` と `[...:ace::200]` は 404（応答あり）。`h2-sshd`（`::131`）、`natsumi-sshd`（`::132`）、`natsumi-sshd-myao`（`::133`）、`natsumi-sshd-aki`（`::134`）は SSH のバナーを返す。告知ノードは段の前と同じ（VIP pablo、gated-v4 chirico、gated-v6 oeilvert、`::131`・`::134` .112、`::132` .111、`::133` duchamp）。gated-v4 は chirico の `install kubelet` の間に 1 秒ほど oeilvert へ移って戻った（`chirico.md` §4 の注。途切れは無い）。minecraft は UDP なので確かめていない |
| NFS、registry | oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で中身が読める。braque は 2049 を listen している。`registry.fraction.jp/v2/` は 401（応答あり） |
| metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個 |
| `apiserver_requested_deprecated_apis` | `endpoints` `v1`（`removed_release` なし。3 台の apiserver とも。runbook §8.15 のとおり control-plane 自身も使う）と、`metallb.io/v1beta1 addresspools`（`removed_release` なし）だけ。`removed_release` が 1.33 以前のものは無い |
| v1 Endpoints の warning の出どころ | §2.3 |
| CSR | 段の間に出た CSR は無い。8 台の kubelet の serving の証明書の subject と期限はベースラインと同じ |

### 2.1 restartCount（ベースラインからの比べ）

- ベースラインの Pod（148 個）のうち、段 4 の間ずっと動き続けたもの（名前が同じもの、131 個）は、**restartCount がすべて同じ**。UID が変わったのは control-plane の etcd の mirror Pod の 3 つだけ（restartCount は `etcd=1` のまま。runbook §4.1）
- `install kubernetes` で作り直されたもの（apiserver 3、controller-manager 2、scheduler 2、kube-proxy 8、CoreDNS 2）は、新しい名前・UID で 17 個とも restartCount 0
- 消えたもの: 上の 17 個の前の Pod だけ。完了の確認の時点の Pod は 148 個
- **1.33 の kubelet への更新で、コンテナの再起動は 8 台で 1 つも無かった**（runbook §8.4 のとおり。arm64 の control-plane、Longhorn の instance-manager・longhorn-manager・CSI、アタッチされたままのボリュームを使う Pod（chirico 10 本、oeilvert 5 本、pablo 1 本）、nfsd、prometheus を含む）

### 2.2 warning のイベント・ログ

- runbook §8 にあるもの: 各台の `InvalidDiskCapacity`、置き換えられた古い apiserver の止まりかけの間の probe の失敗、各台の cnidaria の `no route`（error 7〜8 件、1 秒ほど。oeilvert は 0）、etcd の `lost TCP streaming connection`・`peer became inactive`（1.1〜1.2 秒）、etcd の mirror Pod の `already exists`、`ClusterIPNotAllocated`（71 件、`install kubernetes` の直後だけ）、Longhorn の node の `is down`・`Waiting for disk`（Longhorn のノード 3 台。kubelet の再起動の数秒）
- runbook に無かったもの（どれも一時的で、続かない。Pod の再起動も監視の FAIL も無い）:
  - `install kubernetes` の apiserver の rollout が .111 から始まったときの、controller-manager の `FailedToUpdateEndpoint`（14 件）・`FailedToUpdateEndpointSlices`（1 件）・kube-proxy の DaemonSet の `FailedCreate`（9 回）（02:03:36Z〜37Z、`dial tcp 10.254.0.1:443: connect: connection refused`）と、新しい controller-manager の `FailedMount`（`failed to sync secret cache`、1 回）。`control-plane.md` §7
  - control-plane の kubelet の起動の直後の speaker の `object "metallb-system"/"memberlist"`・`"metallb-excludel2"`（・`"kube-root-ca.crt"`）`not registered`（3 台とも 1 回ずつ。`192.168.1.113.md` §4 の 11）
  - oeilvert の Longhorn の orphan の CR 3 つの片付けと作り直し（`OrphanCleanupCompleted`。ディスクのデータは残っていて、ボリュームに関係しない。`oeilvert.md` §4 の注）
  - oeilvert の kubelet の再起動の瞬間の apiserver の `v1beta1.metrics.k8s.io` の 503 と APIService の更新の衝突（02:32:37Z、1 回ずつ）、`netcheck.sh`・`npcheck.sh` の名前空間の削除の間の controller-manager のエラー、`kubectl exec` の間の apiserver の `use of closed network connection`（段 3 と同じ）
- 段 4 と関係なく前からあると見ているもの: controller-manager の garbage collector の `unable to get REST mapping for longhorn.io/v1beta1/Volume`・`…/ShareManager`（`longhorn-system` の Service などの ownerReference が、いまは served でない `longhorn.io/v1beta1` を指している。CRD の `volumes.longhorn.io` は v1beta2 だけを served。K8s の版には依らない）。新しい controller-manager の起動から 02:42Z までに 156 行、間隔を空けて繰り返している。1.32 の controller-manager のログは作り直しで残っていないので、前からあったかは確かめていない。§3 の申し送り
- kube-proxy、CoreDNS、etcd の Pod のログに、02:20Z より後の error は無い

### 2.3 v1 Endpoints の warning の出どころ（runbook §6、§8.15）

`install kubernetes`（02:02:18Z）から 02:41Z までの、Running の 177 個のコンテナのログの `v1 Endpoints is deprecated` の行（タスクディレクトリの `notes/stage-4/final/endpoints-warnings.tsv`）。

| Pod（ノード） | コンテナ | 行の数 | 製品と版 |
|---|---|---|---|
| `longhorn-system/longhorn-manager-hgj47`（pablo） | longhorn-manager | 14 | Longhorn v1.11.2（`longhornio/longhorn-manager:v1.11.2`） |
| `longhorn-system/longhorn-manager-pzx5h`（duchamp） | longhorn-manager | 12 | 同上 |
| `longhorn-system/longhorn-manager-v6f2c`（chirico） | longhorn-manager | 13 | 同上 |
| `longhorn-system/longhorn-manager-wn5sl`（oeilvert） | longhorn-manager | 11 | 同上 |
| `monitoring/kube-prometheus-operator-658779c859-zcrzg`（pablo） | kube-prometheus | 24 | prometheus-operator v0.90.1（client-go v0.35.2。`level=info`） |
| `monitoring/prometheus-kube-prometheus-0`（chirico） | prometheus | 1 | Prometheus v3.11.3（`component=k8s_client_runtime`、`level=INFO`） |
| `monitoring/prometheus-kube-prometheus-1`（oeilvert） | prometheus | 1 | 同上 |

- longhorn-manager は dev と同じ形（watch を張り直すたびに出る）。prometheus-operator は約 1〜2 分ごと。Prometheus は 1.33 の apiserver に替わった直後（02:04:58Z）の 1 回だけ
- gated、metrics-server などのほかのコンテナでは 0 行（ingress-nginx の Pod は Running のコンテナの中に無かった）。warning をログに出さないクライアントもあるので、0 行のものが Endpoints を使っていないとは限らない
- warning は振る舞いを変えない（v1 Endpoints は 1.33 で非推奨になっただけで、削除の予定は無い）。段 8 の後の非クリティカルなコンポーネントの更新（計画 §8）の材料にする

### 2.4 監視（runbook §2.3）の FAIL

監視は 01:57:33Z から 02:45:23Z まで（`ok` の行が 2700 回目まで）流し、ログはタスクディレクトリの `notes/stage-4/stage-4-probe.log` に置いた。**FAIL は VIP・LB とも 0 回**（`install kubernetes` の apiserver の rollout、etcd の起き直し、VIP と gated-v4 の告知ノードの `install kubelet` の間も途切れなかった）。

### 2.5 leader election で再起動した controller（runbook §8.8）

無い（`gated-system/gated` の 2 つ、`longhorn-system` の CSI sidecar 12 個とも restartCount 0 のまま）。controller-manager と scheduler は `install kubernetes` で作り直され、その後のリーダーは変わっていない。

## 3. 片付けと、残したこと

- 一時的な名前空間 `cnidaria-netcheck`・`k8u-npcheck` は消した（NotFound）
- `infra-admin` のトークン: duchamp の後の NetworkPolicy の確認（02:23:15Z）と完了の確認（02:42:54Z）で 1 時間の期限で発行し、どれも作業端末の `/tmp` のモード 600 のファイルに置いて、使い終えた直後に消した（02:26Z、02:45Z。サーバーの側では最も遅いもので 03:42Z に期限が切れる）
- 監視は 02:45Z に止めた
- etcd のバックアップ `etcd-2026-10-20T02:00:34+00:00.db`（55,107,616 バイト、sha256 `766c2b60d508f52425c94544d168ff7f324e409a3e9512ffcd3d61e7480cefd7`）は段 4 の worktree の `./backup/` にある。worktree を片付ける前に、メインの checkout の `backup/` へ移す（coordinator）
- 申し送り（段 4 の範囲の外）:
  - controller-manager の garbage collector が、Longhorn の古い `longhorn.io/v1beta1` の ownerReference を引けずにエラーを繰り返している（§2.2）。Longhorn の更新（計画 §4。v1.12 系）の前後で、ownerReference の片付けが要るかを調べる
  - Longhorn の orphan（古い replica のデータの置き場所）が 12 個ある（oeilvert 8、duchamp 3、pablo 1。`orphan-resource-auto-deletion` は空）。消すかどうかは Longhorn の運用の判断
- 段 5 以降の手順書に引き継ぐこと: `install kubernetes` の rc は apiserver の rollout の始まるノードで変わる（.111 から始まると rc 1、そのとき controller-manager の一時的な `FailedToUpdateEndpoint` なども出る）、speaker の `not registered` は kubelet の起動の直後に出る、Longhorn の orphan の CR は kubelet の再起動の間に作り直される、告知ノードを speaker のログで読むときは同じ秒の行をログの順で読む
