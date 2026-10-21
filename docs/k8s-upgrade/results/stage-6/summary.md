# 段 6 のまとめと完了の確認

本番 `fraction` の Kubernetes を v1.34.12 から v1.35.9 へ、CoreDNS を v1.12.4 から v1.13.2 へ上げた段 6（porkadot 0.34.1 → 0.35.0、crictl v1.35.0。etcd 3.6.15・CNI plugins v1.9.1 は据え置き）の、全体のまとめと完了の確認（runbook §6）の記録。手順は `../../runbook-stage-6.md`（以下 runbook）。
時刻は UTC。作業の前のクラスタ全体、cgroup・resolv.conf・unattended-upgrades の確認、段の前の etcd のバックアップは `baseline.md`、`install kubernetes` と 2 つ目のバックアップは `control-plane.md`、各台の記録は `<ノード>.md`（control-plane は `192.168.1.11N.md`）。読み取りの出力はタスクディレクトリの `notes/stage-6/`（完了の確認は `final/`）。

## 1. 作業（2026-10-21）

porkadot のコマンドとノードへの `ssh` は、すべてサンドボックスの中（ssh-agent なし、porkadot は runbook §1.4 の (a) の独立の clone `worktrees/porkadot-v0-35-0`）で流し、SSH の失敗は一度も無かった。どのノードも drain していない。承認の節目は 1 つ（段 6 の開始）で、ユーザーが承認した（PR #46 のマージ）。

| 順 | 対象 | 流した時刻（開始 → 終わり） | Pod の再起動 | 監視の FAIL | 記録 |
|---|---|---|---|---|---|
| — | pablo の unattended-upgrades（作業の前。iscsid の再起動） | 06:40:24 → 06:40:51 | — | — | `baseline.md` §5 |
| — | `etcd backup`（段の前） | 06:46:11 → 06:46:15 | — | — | `baseline.md` §6 |
| 1 | `install kubernetes --node 192.168.1.111` | 06:48:33 → 06:51:38（**rc 0、1 回目で通った**） | 作り直し 17 個のほかは無い | VIP 1 回 | `control-plane.md` |
| — | `etcd backup`（1.35 の control-plane） | 06:56:16 → 06:56:19 | — | — | `control-plane.md` §5 |
| 2 | 192.168.1.113 | 06:57:08 → 06:57:52 | etcd の mirror Pod だけ | etcd 1 サンプル | `192.168.1.113.md` |
| 3 | 192.168.1.112（リーダーを .113 へ移した） | 06:59:56 → 07:00:27 | etcd の mirror Pod だけ | etcd 2 サンプル | `192.168.1.112.md` |
| 4 | 192.168.1.111 | 07:02:10 → 07:02:34 | etcd の mirror Pod だけ | 0 | `192.168.1.111.md` |
| 5 | pablo（API の VIP を告知。netcheck と NetworkPolicy の確認） | 07:04:39 → 07:05:00 | 無い | 0 | `pablo.md` |
| 6 | braque（JST 16:09。バックアップの時間帯の外） | 07:09:55 → 07:10:21 | 無い（nfsd も） | 0 | `braque.md` |
| 7 | oeilvert | 07:12:01 → 07:12:23 | 無い | 0 | `oeilvert.md` |
| 8 | duchamp（§8.12 の Pod 6 つを削除） | 07:14:21 → 07:14:44 | 無い | 0 | `duchamp.md` |
| 9 | chirico（§8.12 の Pod 1 つを削除） | 07:16:42 → 07:17:02 | 無い | 0 | `chirico.md` |

- `install kubernetes` から最後の worker まで約 29 分。1 台の `install kubelet` は 20 秒〜44 秒
- ロールバック（runbook §7）は一度も行っていない。runbook の止める条件（etcd の mirror Pod のほかのコンテナの再起動、`install kubelet` による iscsid の PID の変化、古い iSCSI のセッション、storage version の `OLD`、cgroup v1 のノード、etcd の unhealthy が続く、CoreDNS の `loop`）には一度も当たらなかった
- runbook から外れた操作は無い。runbook §8.12 の Succeeded の Pod の削除（段の開始の承認の範囲の ✋）は 7 つ（duchamp の前に natsumi のバックアップの 6 つ、chirico の前に deep-researcher のバックアップの 1 つ）。どれも消す前に名前を coordinator に知らせた

## 2. 完了の確認（runbook §6。2026-10-21 07:18Z〜07:25Z）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready、全台 v1.35.9、CONTAINER-RUNTIME が 8 台とも `containerd://2.3.6`。SchedulingDisabled のノードは無い |
| `/opt/bin`、CNI | 8 台とも `kubelet-v1.35.9`、`kubectl-v1.35.9`、`crictl-v1.35.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と bridge・host-local・portmap・loopback が 8 台とも `v1.9.1`（`/opt/cni/bin` の mtime は 2026-03-16 のまま。展開していない） |
| etcd | 3/3 healthy、全メンバーが 3.6.15、cluster version・storage とも 3.6.0（3 台の `/version` が `{"etcdserver":"3.6.15","etcdcluster":"3.6.0","storage":"3.6.0"}`）。リーダー .113（`57ec6f12ac7b683e`）、raft term 23123、raft index 1403521207 でそろう。DB 55 MB（in use 19 MB）。3 台の動いている etcd のフラグに `--experimental-` は無い。3 台の `/etc/etcd/pki` の 3 つのファイルが `600 root:root`。`member list` は 3 つとも `started` |
| VIP | `/readyz` `ok`、`/livez` 200（監視）、`/version` v1.35.9 |
| apiserver、controller-manager、scheduler、kube-proxy | kube-apiserver の DaemonSet 3/3（v1.35.9、generation 29。`-wdw65` .111、`-82plt` .112、`-rbbgw` .113、restartCount 0）。controller-manager 2/2（.113 `-qjt9d` リーダー、.112 `-bvqcn`、generation 28）、scheduler 2/2（.112 `-zkslm` リーダー、.113 `-wb6t5`、generation 27）。kube-proxy 8/8（v1.35.9、generation 25） |
| CoreDNS | **v1.13.2、2/2 Running（chirico、duchamp）、generation 12**。ログは `CoreDNS-1.13.2` で、`[ERROR]`・`[WARNING]`・`loop` は無い。`tools/dns-check.sh` の答えは `baseline.md` §2 の 23 と同じ（Service と 2 つの Pod の 3 か所とも。違うのは kube-dns の Endpoint の Pod の IP が新しい Pod のものになったことだけ。`notes/stage-6/final/dns-check.txt`） |
| kubelet-serving-cert-approver | 1/1 Running（oeilvert、restartCount 0、generation は変わらない） |
| Running / Completed 以外の Pod | 0 |
| restartCount | §2.1 |
| storage version | `tools/storage-versions.sh`: `prefixes: 65, keys: 2573, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は空 |
| ServiceCIDR と IPAddress | `servicecidrs` は `kubernetes` の 1 つ（`10.254.0.0/24,fd20:afc2:7c09::/108`）。IPAddress は 74 で、ClusterIP の数と同じ。`ClusterIPNotAllocated` の event は段 6 の間に一度も出ていない |
| FlowSchema | 11 個、generation もベースラインと同じ |
| cgroup | 8 台とも `cgroup2fs` のまま、kubelet が 8 台とも動いている |
| Longhorn | attached healthy 16、detached unknown 1（`homegallery/cg-data`。ベースラインのとおり）。ボリュームのアタッチ先、replica（chirico 9、duchamp 12、oeilvert 9、pablo 2）、instance-manager（7 つとも同じ名前・IP で running）、engine image（`longhorn-engine:v1.13.0` だけが deployed）、Longhorn の node（4 つとも Ready、schedulable）がベースラインと同じ。K8s 1.35 は Longhorn v1.13.0 の要件（1.34 以上）に入る |
| Longhorn の設定 | ベースラインのまま（`5`、`disabled`、`block-if-contains-last-replica`、`best-effort`、`6000`、v1.13.0） |
| iSCSI | 8 台の `tools/node-state.sh`（`notes/stage-6/final/node-<ノード>-after.txt`）で、`bin` の行のほか（iscsid の MainPID と起動の時刻、セッション、エンジン、`initiatorname.iscsi` の md5）が 8 台ともベースラインと同じ。**`install kubelet` で iscsid の PID が変わった台は無い**。ベースラインの前に unattended-upgrades の needrestart で再起動していたのは .113（10-20 21:30:04Z）、braque（06:23:32Z）、duchamp（06:08:00Z）、pablo（06:40:42Z）の 4 台で、段 6 の作業の間には変わっていない（§2.3）。Longhorn のセッションは pablo 1、oeilvert 2、duchamp 4、chirico 9 で、どれもそのノードの今の instance-manager の IP へのもの。**古いセッションは 0**。`older-than-iscsid` のエンジンは pablo 1・duchamp 4（どちらも unattended-upgrades の iscsid の再起動による。エンジンは v1.13.0）で、増えていない |
| cnidaria | 8 台の Pod が Ready（restartCount はベースラインと同じ）。`verify-nodes.sh` 64 PASS、FAIL 0（nft を流すイメージを v0.1.1 にした写しで流した。`baseline.md` §8）。cnidaria のログの error は各台の `install kubelet` の `no route` の 6〜8 件ずつ（oeilvert は 0。runbook §8.1）。✋ `netcheck.sh`（07:22:26Z〜07:22:44Z）**168/168 PASS** |
| NetworkPolicy（runbook §1.9） | ✋ `npcheck.sh`（07:22:44Z〜07:25:16Z）: up の前の `nft` は 8 台とも 0、up の後は 8 台とも 9、`run` は **`OK 56, not OK 0`**、down の後は 8 台とも 0、`k8u-npcheck` は NotFound。pablo の後（07:06Z〜07:09Z）にも同じ結果 |
| MetalLB | gated の `192.168.1.200` と `[...:ace::200]` は 404（応答あり）。`::131`〜`::134` は SSH のバナーを返す。告知ノードは段の前と同じ（VIP pablo、gated-v4 chirico、gated-v6 oeilvert、`::131`・`::134` .112、`::132` .111、`::133` duchamp）。`install kubernetes` の apiserver の入れ替えの後に、同じノードで `serviceAnnounced` を出し直した |
| NFS、registry | oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で中身が読める。braque は 2049 を listen している。`registry.fraction.jp/v2/` は 401（応答あり） |
| metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個。`count by (job) (up)` の `kube-etcd` 3、`apiserver` 3、`count(etcd_server_has_leader)` 3 |
| `apiserver_requested_deprecated_apis` | `endpoints` `v1` と `metallb.io/v1beta1 addresspools`（`removed_release` なし）だけ。`removed_release` が 1.35 以前のものは無い |
| v1 Endpoints の warning の出どころ | §2.4 |
| CSR | 段の間に出た CSR は無い。8 台の kubelet の serving の証明書の subject と期限はベースラインと同じ |
| kubelet の起動時の warning | 8 台とも `Flag --container-runtime-endpoint has been deprecated` だけ（計画 §10 の KubeletConfiguration への移行の対象）。ほかに `Flag --`・deprecated の行は無い |

### 2.1 restartCount（ベースラインからの比べ）

- ベースラインの Pod（165 個）のうち、段 6 の間ずっと動き続けたもの（名前が同じもの）は、control-plane の etcd の mirror Pod の 3 つのほか **restartCount がすべて同じ**
  - etcd の mirror Pod の 3 つ: UID が変わり restartCount 0 → 1（最初のコンテナが古い etcd の 2380 番の解放の前に起きて `bind: address already in use` で落ちたもの。runbook §4.1 のとおり、3 台とも 1 回）
- `install kubernetes` で作り直されたもの（apiserver 3、controller-manager 2、scheduler 2、kube-proxy 8、CoreDNS 2）は、新しい名前・UID で 17 個とも restartCount 0
- ほかに減ったのは §8.12 で消した Succeeded の Pod 7 つだけ。完了の確認の時点の Pod は 158 個
- **1.35 の kubelet への更新で、コンテナの再起動は 8 台で 1 つも無かった**（runbook §8.4 のとおり。arm64 の control-plane、Longhorn の instance-manager・longhorn-manager・CSI、アタッチされたままのボリュームを使う Pod（chirico 9 本、duchamp 4 本、oeilvert 2 本、pablo 1 本。replica 1 の prometheus の 2 つを含む）、nfsd、CoreDNS を含む）
- ベースラインの前から約 3 時間ごとに再起動していた `movies` の 3 つ（carib2、shja2、pondo2）は、段 6 の間には再起動していない

### 2.2 warning のイベント・ログ

- runbook §8 にあるもの: 置き換えられた古い apiserver の止まりかけの間の probe の失敗、各台の cnidaria の `no route`（error 6〜8 件、1 秒ほど。ほかのノードの cnidaria でも `no route` が 2〜3 件ずつ増える）、etcd の `bind: address already in use`（落ちた最初のコンテナ）・`lost TCP streaming connection`・`closed TCP streaming connection`・`peer became inactive`、etcd の mirror Pod の `already exists`
- runbook に無かったもの（どれも一時的で、続かない。Pod の再起動も監視の FAIL も無い）:
  - .112 の新しい etcd の起動の直後の `failed to publish local member to cluster through raft`（5 回、同じミリ秒の間）と、追いつく間の `request stats`・`apply request took too long`・`waiting for ReadIndex response took too long`・`ignored out-of-date read index response`。前者は段 5 の 3.6 の起動でも出たもの（段 5 の手順書 §4.1）。runbook §4.4 の 18 に足した
  - braque の node-exporter の Readiness probe の失敗（07:10:16Z、`network is unreachable`、1 回。`dns` の addon の systemd-networkd の再起動の間。`braque.md`）
  - duchamp の kubelet の `Failed to trigger a manual run`（Info、起動の直後に 3 回）
  - controller-manager の `namespace_controller` の `Deletion of namespace failed`（37 件）と `daemon_controller` の `Unhandled Error`（27 件）。`netcheck.sh`・`npcheck.sh` の名前空間の削除の間のもので、名前空間は消えた（段 5 と同じ）
  - kube-proxy の起動のときの `Kube-proxy configuration may be incomplete or incorrect`（`nodePortAddresses` が無い。8 つとも 1 回。前からの設定のもの）
- scheduler の 2 つのログに `E` の行は無い。CoreDNS のログに error は無い。etcd の 3 台のログに、07:05Z より後の warn・error は無い

### 2.3 iscsid の PID の変化とその見分け（runbook §2.11）

| ノード | ベースラインの前の変化 | 段 6 の作業の間 |
|---|---|---|
| 192.168.1.113 | 10-20 21:30:04Z に再起動（unattended-upgrades が liblzma5・xz-utils を 0.4 にした直後の needrestart。`/var/log/apt/history.log` と `unattended-upgrades-dpkg.log` の `systemctl restart … iscsid.service …`） | 変わらない（290821） |
| braque | 10-21 06:23:32Z に再起動（同じ） | 変わらない（271131） |
| duchamp | 10-21 06:08:00Z に再起動（同じ。アタッチされた 4 本のセッションを `operational after recovery` で引き取った） | 変わらない（2695716） |
| pablo | 10-21 06:40:42Z に再起動（同じ。作業の直前。アタッチされた `fs/sites` のセッションを引き取った） | 変わらない（4114921） |
| .111、.112、chirico、oeilvert | 再起動していない（今日の実行で liblzma5 が上がらなかった） | 変わらない |

- **porkadot の `install kubelet` による iscsid の再起動は 8 台で 0**（0.35.0 の `install-pkgs.sh` は `initiatorname.iscsi` が同じなら再起動しない。`install-pkgs.sh` の apt は何も入れていない）
- 完了の確認の時点（07:18Z〜07:19Z）でも 8 台とも `apt-daily-upgrade.service` は inactive。`install kubelet` の後、`apt-daily-upgrade.timer` の次の時刻が引き直されていた（CP は 10-21 21:10Z〜21:42Z、worker は 10-22 06:13Z〜06:42Z）。`install kubelet` の `daemon-reload` で systemd がタイマーのランダムな遅れを選び直したものと見ている。.111・.112・chirico・oeilvert は次の実行で liblzma5 が 0.4 になり、iscsid が再起動する見込み

### 2.4 v1 Endpoints の warning の出どころ（runbook §6、§8.15）

`install kubernetes`（06:48:33Z）から 07:2xZ までの、Running の 183 個のコンテナのログの `v1 Endpoints is deprecated` の行（タスクディレクトリの `notes/stage-6/final/endpoints-warnings.tsv`）。

| Pod（ノード） | コンテナ | 行の数 | 製品と版 |
|---|---|---|---|
| `longhorn-system/longhorn-manager-f9f8v`（pablo） | longhorn-manager | 6 | Longhorn v1.13.0 |
| `longhorn-system/longhorn-manager-lz9m4`（oeilvert） | longhorn-manager | 6 | 同上 |
| `longhorn-system/longhorn-manager-mc82c`（chirico） | longhorn-manager | 8 | 同上 |
| `longhorn-system/longhorn-manager-vdh56`（duchamp） | longhorn-manager | 5 | 同上 |
| `longhorn-system/longhorn-global-manager-…-98kkj`（duchamp） | longhorn-global-manager | 8 | 同上 |
| `longhorn-system/longhorn-global-manager-…-n8cl4`（chirico） | longhorn-global-manager | 5 | 同上 |
| `longhorn-system/longhorn-global-manager-…-td2h4`（oeilvert） | longhorn-global-manager | 7 | 同上 |
| `monitoring/kube-prometheus-operator-658779c859-zcrzg`（pablo） | kube-prometheus | 22 | prometheus-operator v0.90.1 |

- Longhorn は v1.13.0 になっても v1 Endpoints を読んでいる（v1.13.0 で増えた `longhorn-global-manager` も）。段 5（v1.11.2）より行の数は少ないが、見ていた時間が短い（段 5 は約 85 分、段 6 は約 35 分）
- warning は振る舞いを変えない（v1 Endpoints は非推奨で、削除の予定は無い）。prometheus-operator は段 8 の後の非クリティカルなコンポーネントの更新（計画 §8）で見直す

### 2.5 監視（runbook §2.3）の FAIL

- VIP と LB: 06:39:40Z から 07:25:25Z まで流し（`ok` の行が 2520 回目まで）、ログはタスクディレクトリの `notes/stage-6/stage-6-probe.log`。**FAIL は VIP の 1 回だけ**（06:49:39Z。`install kubernetes` の .113 の apiserver の入れ替え）。LB は 0 回。VIP と gated-v4 の告知ノードの `install kubelet` の間も途切れなかった
- etcd の health: 06:48:09Z から 07:03:5xZ まで、.111 と .112 から 2 秒ごと（`notes/stage-6/stage-6-etcd-192.168.1.11{1,2}.log`）。unhealthy は 06:57:55Z（.113）、07:00:30Z と 07:00:31Z（.112）だけで、起き直す台だけ。ほかの 2 台が unhealthy になったことは無い。`install kubernetes` の直後（全体の apply の後）も 3 台とも healthy（runbook §8.13 の dev の詰まりは本番では起きなかった）

### 2.6 leader election で再起動した controller（runbook §8.8）

無い（`gated-system/gated` の 2 つ、`longhorn-system` の CSI sidecar 12 個とも restartCount はベースラインのまま。`csi-attacher-…-s6fmv` の 1 は段 6 の前から）。controller-manager と scheduler は `install kubernetes` で作り直され、その後のリーダーは変わっていない。

## 3. 片付けと、残したこと

- 一時的な名前空間 `cnidaria-netcheck`・`k8u-npcheck` は消した（NotFound）
- `infra-admin` のトークン: pablo の後の NetworkPolicy の確認（07:06Z）、duchamp の前の Pod の削除（07:14Z）、chirico の前の Pod の削除（07:16Z）、完了の確認（07:22Z）で 1 時間の期限で発行し、どれも作業端末の `/tmp/k8u-stage6-admin-token`（モード 600）に置いて、使い終えた直後に消した（サーバーの側では最も遅いもので 08:22Z ごろに期限が切れる）
- 監視は止めた（VIP と LB は 07:25Z、etcd の health は 07:03Z。ノードの側の while も止めた）
- etcd のバックアップは段 6 の worktree の `./backup/` にある（git には入れていない）。worktree を片付ける前に、メインの checkout の `backup/` へ移す（coordinator）。段 6 が落ち着くまで消さない

  | ファイル | 中身 | バイト | sha256 |
  |---|---|---|---|
  | `etcd-2026-10-21T06:46:11+00:00.db` | 段の前（1.34 の control-plane、CoreDNS v1.12.4） | 55,107,616 | `39ca697a979b55d141afdff73b26a9e5240911807c241ca1f64940e2b84ed34f` |
  | `etcd-2026-10-21T06:56:16+00:00.db` | 1.35 の control-plane、CoreDNS v1.13.2、kubelet は 1.34 | 55,107,616 | `9a799412c697fd6f11a220b3c2b5c927f16c6833c6d4c7021684982874f20681` |

- 確認に使ったスクリプトの写し（作業端末の `/tmp/k8u6w/`。段 5 の worker のスクリプトの道筋を段 6 に替えたもの、cnidaria の手順書のスクリプトの写し）は秘密を含まない。ノードには何も残していない
- 申し送り（段 6 の範囲の外）:
  - **oeilvert の containerd から `cnidaria-cni:v0.1.0` のイメージが kubelet の image GC で消えた**ため、cnidaria-cni-dev の `notes/fraction-runbook/common.sh`（`IMAGE=…:v0.1.0`）の `verify-nodes.sh` が oeilvert で失敗する（`baseline.md` §8）。ほかのノードでも同じことが起こりうる。次の段の手順書では、今の DaemonSet のイメージ（v0.1.1）を使うか、ノードの nft（24.04 の nft 1.0.9）で読む形に直す
  - runbook §2.10 の CoreDNS の upstream に kube-dns が入る件（porkadot の `dns` の addon と Corefile）。v1.13.2 でも `loop` は出ていない
  - runbook §2.11 の unattended-upgrades の needrestart による iscsid の再起動。.111・.112・chirico・oeilvert はまだ liblzma5 が 0.3 で、次の実行（CP は 10-21 21:10Z〜、worker は 10-22 06:13Z〜）で再起動する見込み。段 7 の当日も時間帯と PID を読み直す
  - arm64 の CoreDNS v1.13.2 は本番では動いていない（2 つの Pod が amd64 の worker に置かれた。`control-plane.md` §7）
