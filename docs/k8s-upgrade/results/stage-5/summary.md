# 段 5 のまとめと完了の確認

本番 `fraction` の Kubernetes を v1.33.13 から v1.34.12 へ、etcd を 3.5.34 から 3.6.15 へ上げた段 5（porkadot 0.33.1 → 0.34.1、crictl v1.34.0、etcdutl 3.6.15 を新しく置く。CoreDNS v1.12.4・CNI plugins v1.9.1 は据え置き）の、全体のまとめと完了の確認（runbook §6）の記録。手順は `../../runbook-stage-5.md`（以下 runbook）。
時刻は UTC。作業の前のクラスタ全体、段の前の etcd のバックアップ、v2store の確認は `baseline.md`、`install kubernetes` と IPAddress の書き直しと 2 つ目のバックアップは `control-plane.md`、各台の記録は `<ノード>.md`（control-plane は `192.168.1.11N.md`。3 つ目のバックアップは `192.168.1.111.md` §4.5）。読み取りの出力はタスクディレクトリの `notes/stage-5/`（完了の確認は `final/`）。

## 1. 作業（2026-10-20）

porkadot のコマンドとノードへの `ssh` は、すべてサンドボックスの中（ssh-agent なし）で流し、SSH の失敗は一度も無かった。どのノードも drain していない。承認の節目は 2 つ（段 5 の開始、control-plane の kubelet = etcd 3.6 の前）で、どちらもユーザーが承認した。

| 順 | 対象 | 流した時刻（開始 → 終わり） | Pod の再起動 | 監視の FAIL | 記録 |
|---|---|---|---|---|---|
| — | `etcd backup`（段の前） | 09:08:38 → 09:08:41 | — | — | `baseline.md` §3 |
| — | v2store の確認（3.5.34 の etcdutl、3 台） | 09:08:59 → 09:09:10 | — | — | `baseline.md` §5 |
| 1 | `install kubernetes --node 192.168.1.111` | 09:11:14 → 09:14:19（**rc 0、1 回目で通った**） | 作り直し 15 個のほかは無い | VIP 2 回 | `control-plane.md` |
| — | IPAddress 74 と ServiceCIDR 1 の書き直し | 09:18:45 → 09:18:46 | — | 0 | `control-plane.md` §5 |
| — | `etcd backup`（etcd 3.5 の最後） | 09:20:45 → 09:20:48 | — | — | `control-plane.md` §6 |
| — | ✋✋ control-plane の kubelet の前の承認 | 09:3xZ | — | — | — |
| 2 | 192.168.1.113（リーダーを .111 へ移した） | 10:04:59 → 10:05:46 | etcd の mirror Pod だけ | etcd 1 サンプル | `192.168.1.113.md` |
| 3 | 192.168.1.112 | 10:07:41 → 10:08:11 | etcd の mirror Pod だけ | etcd 2 サンプル | `192.168.1.112.md` |
| 4 | 192.168.1.111（リーダーを .112 へ移した。cluster version 3.6.0） | 10:09:58 → 10:10:25 | etcd の mirror Pod だけ | etcd 1 サンプル | `192.168.1.111.md` |
| — | `etcd backup`（3.6 の etcdctl） | 10:11:45 → 10:11:48 | — | — | `192.168.1.111.md` §4.5 |
| 5 | duchamp（netcheck と NetworkPolicy の確認） | 10:14:49 → 10:15:16 | 無い | 0 | `duchamp.md` |
| 6 | pablo（API の VIP を告知） | 10:20:16 → 10:20:44 | 無い | 0 | `pablo.md` |
| 7 | braque（JST 19:22。バックアップの時間帯の外） | 10:22:25 → 10:23:04 | 無い（nfsd も） | 0 | `braque.md` |
| 8 | oeilvert | 10:24:37 → 10:25:00 | 無い | 0 | `oeilvert.md` |
| 9 | chirico | 10:26:55 → 10:27:18 | 無い | 0 | `chirico.md` |

- etcd が 3.5 と 3.6 の混在だったのは 10:05:50Z（.113 の 3.6 の起動）から 10:10:30Z（cluster version 3.6.0）までの約 4 分半
- ロールバック（runbook §7）は一度も行っていない。runbook の止める条件（etcd の mirror Pod のほかのコンテナの再起動、iscsid の PID の変化、古い iSCSI のセッション、storage version の想定外の OLD、v2store の独自のデータ、etcd の unhealthy が続く）には一度も当たらなかった
- runbook から外れた操作は無い。runbook §8.12 の Completed / Succeeded の Pod の削除は、当たるものが無かったので行っていない（同じ PVC を使う Succeeded の Pod は NFS の `aphrael/aphrael-2` の `tumblr-like` だけ）
- 作業の途中で worker のセッションが認証のエラーで一度止まり（§2.4 の backup の前）、coordinator の指示で同じところから続けた。本番への操作の重なりや抜けは無い

## 2. 完了の確認（runbook §6。2026-10-20 10:28Z〜10:36Z）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready、全台 v1.34.12、CONTAINER-RUNTIME が 8 台とも `containerd://2.3.6`。SchedulingDisabled のノードは無い |
| `/opt/bin`、CNI | 8 台とも `kubelet-v1.34.12`、`kubectl-v1.34.12`、`crictl-v1.34.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と bridge・host-local・portmap・loopback が 8 台とも `v1.9.1` |
| etcd | 3/3 healthy、**全メンバーが 3.6.15、cluster version・storage とも 3.6.0**（3 台の `/version` が `{"etcdserver":"3.6.15","etcdcluster":"3.6.0","storage":"3.6.0"}`）。リーダー .112（`fbb0c648cf5852a5`）、raft term 23122、raft index 1403137934 でそろう。DB 55 MB（in use 19 MB）。`header.revision` 1,237,807,959。3 台の動いている etcd のフラグに `--experimental-` は無い（`--feature-gates=InitialCorruptCheck=true`、`--watch-progress-notify-interval=5s`）。3 台の `/etc/etcd/pki` の 3 つのファイルが `600 root:root`。**3 台の control-plane に `/opt/bin/etcdutl` → `etcdutl-3.6.15` がある**（runbook §7.4 の前提） |
| VIP | `/readyz` `ok`、`/livez` 200（監視）、`/version` v1.34.12 |
| apiserver、controller-manager、scheduler、kube-proxy | kube-apiserver の DaemonSet 3/3（v1.34.12、generation 28。`-56jg7` .111、`-srsxs` .112、`-5sgvj` .113、restartCount 0）。controller-manager 2/2（.111 `-cs97f`、.112 `-gz9wf` リーダー、generation 27）、scheduler 2/2（.111 `-xkbzx`、.113 `-mmpr7` リーダー、generation 26）。kube-proxy 8/8（v1.34.12、generation 24） |
| CoreDNS | **v1.12.4、2/2 Running、generation 11 のまま**（段 5 では動かない）。runbook §3.3 の 13 の問い合わせはベースラインと同じ答え（PTR の答えの並びと `www.google.com` の A の並びだけが違う）。ログにエラーは無い |
| kubelet-serving-cert-approver | 1/1 Running（oeilvert、restartCount 0、generation は変わらない） |
| Running / Completed 以外の Pod | 0 |
| restartCount | §2.1 |
| storage version | `tools/storage-versions.sh`: `prefixes: 65, keys: 2507, OLD: 0, CRDs with more than one stored version: 0`。**`overrides.tsv` は空**。`/registry/ipaddresses/`（74）と `/registry/servicecidrs/`（1）が `networking.k8s.io/v1` の `ok`。47 個の CRD の `status.storedVersions` が 1 つ（`crds.tsv` が 47 行とも `ok`） |
| ServiceCIDR と IPAddress | `servicecidrs` は `kubernetes` の 1 つ（`10.254.0.0/24,fd20:afc2:7c09::/108`、Ready）。IPAddress は 74 で、ClusterIP の数（Service 79 個、ClusterIP を持つもの 71 個、dual-stack 3 個）と同じ。`ClusterIPNotAllocated` の event は段 5 の間に一度も出ていない |
| FlowSchema | 11 個（1.34 の apiserver が `endpoint-controller`・`workload-leader-election` を消した。`control-plane.md` §4）。残りの generation は変わらない |
| Longhorn | attached healthy 16、detached unknown 1（`homegallery/cg-data`。ベースラインのとおり）。ボリュームのアタッチ先、instance-manager（4 つとも running で同じ名前・IP）、engine image（`longhorn-engine:v1.11.2` deployed）、Longhorn の node（4 つとも Ready、schedulable）がベースラインと同じ。replica は chirico 11（running 10）、duchamp 9（running 8）、oeilvert 11（running 10）、pablo 2。orphan は 0。K8s 1.34 は Longhorn 1.11 の要件（1.25 以上）に入る |
| Longhorn の設定 | ベースラインのまま（`5`、`disabled`、`block-if-contains-last-replica`、`best-effort`、`6000`、v1.11.2） |
| iSCSI | 8 台の `tools/node-state.sh`（`notes/stage-5/final/node-<ノード>-after.txt`）で、`bin` の行のほか（iscsid の MainPID と起動の時刻、セッション、エンジン、`initiatorname.iscsi` の md5）が 8 台ともベースラインと同じ。Longhorn のセッションは pablo 1、oeilvert 5、chirico 10 で、どれもそのノードの今の instance-manager の IP へのもの。**古いセッションは 0**。`older-than-iscsid` のエンジンは chirico の 1 つ（ベースラインと同じ）で増えていない |
| cnidaria | 8 台の Pod が Ready（restartCount はベースラインと同じ）。`verify-nodes.sh` 64 PASS、FAIL 0（cnidaria のログの error は各台の `install kubelet` の `no route` の 8 件ずつ。pablo は 1、oeilvert は 0。runbook §8.1）。✋ `netcheck.sh`（10:31:53Z〜10:32:13Z）**168/168 PASS** |
| NetworkPolicy（runbook §1.9） | ✋ `npcheck.sh`（10:32:14Z〜10:34:47Z）: up の前の `nft` は 8 台とも 0、up の後は 8 台とも 9、`run` は **`OK 56, not OK 0`**、down の後は 8 台とも 0、`k8u-npcheck` は NotFound。duchamp の後（10:17Z〜10:20Z）にも同じ結果 |
| MetalLB | gated の `192.168.1.200` と `[...:ace::200]` は 404（応答あり）。`::131`〜`::134` は SSH のバナーを返す。告知ノードは段の前と同じ（VIP pablo、gated-v4 chirico、gated-v6 oeilvert、`::131`・`::134` .112、`::132` .111、`::133` duchamp）。oeilvert と chirico の `install kubelet` の間に gated と `natsumi-sshd*` の告知が数秒揺れた（`oeilvert.md`、`chirico.md`。告知ノードは戻った、監視の FAIL は無い） |
| NFS、registry | oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で中身が読める。braque は 2049 を listen している。`registry.fraction.jp/v2/` は 401（応答あり） |
| metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個。`count by (job) (up)` の `kube-etcd` 3、`apiserver` 3 |
| metrics（runbook §8.15） | `count(etcd_server_has_leader)` は 3（etcd 3.6 でもサーバーの側の metrics が出る）。kube-prometheus のダッシュボードとルールは 1.34 でラベルの変わった metrics を使っていない（runbook §8.15 の読み取り）。Grafana の画面は開いて確かめていない |
| `apiserver_requested_deprecated_apis` | `endpoints` `v1`（3 台の apiserver とも）と `metallb.io/v1beta1 addresspools`（`removed_release` なし）だけ。`removed_release` が 1.34 以前のものは無い |
| v1 Endpoints の warning の出どころ | §2.3 |
| CSR | 段の間に出た CSR は無い。8 台の kubelet の serving の証明書の subject と期限はベースラインと同じ |

### 2.1 restartCount（ベースラインからの比べ）

- ベースラインの Pod（150 個）のうち、段 5 の間ずっと動き続けたもの（名前が同じもの）は、次の 2 つのほか **restartCount がすべて同じ**
  - control-plane の etcd の mirror Pod の 3 つ: UID が変わり restartCount が 1 → 0（etcd 3.6.15 での作り直し。runbook §4.1）
  - `carib2/movies-78dc5856b6-msfk2`・`shja2/movies-69bf4c594c-tmcwz`（oeilvert）、`pondo2/movies-75b8fb88bf-vqrpg`（chirico）: restartCount 7 → 8。終わった時刻は 09:07:05Z（exit 2）、09:09:05Z（OOMKilled）、09:21:10Z（exit 2）で、**どれもそのノードの `install kubelet` の前**（oeilvert は 10:24Z、chirico は 10:26Z）。3 つとも約 24 時間で 8 回、約 3 時間ごとに再起動している前からの形（`control-plane.md` §4）。段 5 の作業とは関係が無い。次は 12:07Z〜12:21Z ごろの見込み
- `install kubernetes` で作り直されたもの（apiserver 3、controller-manager 2、scheduler 2、kube-proxy 8）は、新しい名前・UID で 15 個とも restartCount 0
- ほかに入れ替わったのは CronJob の Job の Pod だけ（`aphrael/tumblr-like` が 1 つ入れ替わり、`fs/data-backup` が 1 つ増えた）。完了の確認の時点の Pod は 151 個
- **1.34 の kubelet への更新で、コンテナの再起動は 8 台で 1 つも無かった**（runbook §8.4 のとおり。arm64 の control-plane、Longhorn の instance-manager・longhorn-manager・CSI、アタッチされたままのボリュームを使う Pod（chirico 10 本、oeilvert 5 本、pablo 1 本）、nfsd、prometheus を含む）

### 2.2 warning のイベント・ログ

- runbook §8 にあるもの: 各台の `InvalidDiskCapacity`、置き換えられた古い apiserver の止まりかけの間の probe の失敗、各台の cnidaria の `no route`（error 8 件、1 秒ほど）、etcd の `lost TCP streaming connection`・`peer became inactive`・`leader found higher-versioned member`（混在中）・`failed to publish local member`（.111 で 43 回、同じミリ秒の間）、etcd の mirror Pod の `already exists`、Longhorn の node の `is down`・`Waiting for disk`（Longhorn のノード 4 台。kubelet の再起動の数秒）
- runbook に無かったもの（どれも一時的で、続かない。Pod の再起動も監視の FAIL も無い）:
  - .113 の etcd の起動の直後の `waiting for ReadIndex response took too long, retrying`・`ignored out-of-date read index response`（各 1 回、1 秒の間。`192.168.1.113.md` §4 の 18）
  - pablo の speaker の Liveness probe の失敗（10:20:40Z、`network is unreachable`、1 回。`pablo.md`）
  - controller-manager の `namespace_controller` の `deletion of namespace … failed`（38 件）と `daemon_controller` の `failed to construct revisions`（4 件）。`netcheck.sh`・`npcheck.sh` の名前空間の削除の間のもので、名前空間は消えた
  - kube-proxy の起動のときの `nodePortAddresses is unset`（8 つとも 1 回。前からの設定のもの）
- 段 4 で申し送った controller-manager の garbage collector の `longhorn.io/v1beta1` の REST mapping のエラーは、段 5 の controller-manager のログに出ていない（Longhorn の ownerReference は段 5 の前に v1beta2 に書き換えた。`docs/longhorn/results/2026-10-20.md`）
- CoreDNS と etcd の Pod のログに、10:12Z より後の error は無い（etcd の warn は .113 の `apply request took too long` 1 回、10:20:48Z、110 ms）

### 2.3 v1 Endpoints の warning の出どころ（runbook §6、§8.15）

`install kubernetes`（09:11:14Z）から 10:36Z までの、Running の 177 個のコンテナのログの `v1 Endpoints is deprecated` の行（タスクディレクトリの `notes/stage-5/final/endpoints-warnings.tsv`）。

| Pod（ノード） | コンテナ | 行の数 | 製品と版 |
|---|---|---|---|
| `longhorn-system/longhorn-manager-hgj47`（pablo） | longhorn-manager | 24 | Longhorn v1.11.2 |
| `longhorn-system/longhorn-manager-pzx5h`（duchamp） | longhorn-manager | 23 | 同上 |
| `longhorn-system/longhorn-manager-v6f2c`（chirico） | longhorn-manager | 26 | 同上 |
| `longhorn-system/longhorn-manager-wn5sl`（oeilvert） | longhorn-manager | 25 | 同上 |
| `monitoring/kube-prometheus-operator-658779c859-zcrzg`（pablo） | kube-prometheus | 56 | prometheus-operator v0.90.1 |

- 段 4 と同じ出どころ。段 4 で 1 行ずつ出た Prometheus の 2 つは、今回は 0 行
- warning は振る舞いを変えない（v1 Endpoints は非推奨で、削除の予定は無い）。Longhorn は段 5 の後の更新（runbook §10）で、prometheus-operator は段 8 の後の非クリティカルなコンポーネントの更新（計画 §8）で見直す

### 2.4 監視（runbook §2.3）の FAIL

- VIP と LB: 08:45:03Z から 10:35:30Z まで（`ok` の行が 6120 回目まで）流し、ログはタスクディレクトリの `notes/stage-5/stage-5-probe.log`。**FAIL は VIP の 2 回だけ**（09:11:30Z、09:12:21Z。`install kubernetes` の .112・.113 の apiserver の入れ替え）。LB は 0 回。etcd の更新・VIP と gated-v4 の告知ノードの `install kubelet` の間も途切れなかった
- etcd の health: 10:04:20Z から 10:11:53Z まで、.111 と .112 から 2 秒ごと（`notes/stage-5/stage-5-etcd-192.168.1.11{1,2}.log`）。unhealthy は 10:05:46Z（.113）、10:08:11Z と 10:08:15Z（.112）、10:10:25Z（.111）だけで、起き直す台だけ。ほかの 2 台が unhealthy になったことは無い

### 2.5 leader election で再起動した controller（runbook §8.8）

無い（`gated-system/gated` の 2 つ、`longhorn-system` の CSI sidecar 12 個とも restartCount 0 のまま）。controller-manager と scheduler は `install kubernetes` で作り直され、その後のリーダーは変わっていない。

## 3. 片付けと、残したこと

- 一時的な名前空間 `cnidaria-netcheck`・`k8u-npcheck` は消した（NotFound）
- `infra-admin` のトークン: IPAddress の書き直し（09:18Z）、duchamp の後の NetworkPolicy の確認（10:17Z）、完了の確認（10:32Z）で 1 時間の期限で発行し、どれも作業端末の `/tmp` のモード 600 のファイルに置いて、使い終えた直後に消した（サーバーの側では最も遅いもので 11:32Z ごろに期限が切れる）
- 監視は止めた（VIP と LB は 10:35Z、etcd の health は 10:11Z。ノードの側の while も止めた）
- v2store の確認で使ったデータの写しと etcdutl 3.5.34 は、3 台のノードと作業端末から消した
- etcd のバックアップは段 5 の worktree の `./backup/` にある（git には入れていない）。worktree を片付ける前に、メインの checkout の `backup/` へ移す（coordinator）。§2.4 と §4.2 の 3.5 のものは、Longhorn の更新が終わり段 6 に入るまで残す（runbook §10）

  | ファイル | 中身 | バイト | sha256 |
  |---|---|---|---|
  | `etcd-2026-10-20T09:08:38+00:00.db` | 段の前（1.33 の control-plane、etcd 3.5） | 55,107,616 | `762d90b31c3a02c40bab5812ac24cf34b9d6e06abfb74ce54c23b4bc88a4e675` |
  | `etcd-2026-10-20T09:20:45+00:00.db` | 1.34 の control-plane、IPAddress は v1、etcd 3.5 の最後 | 55,107,616 | `e70a304290fde754721d8c43ed9633ebe322343f56e9f7e1661b7b1b5f76a10f` |
  | `etcd-2026-10-20T10:11:45+00:00.db` | 全台 3.6 の後（3.6 の etcdctl） | 55,107,616 | `72d640e2b30d7353e157ba6f798da3343fc3ecf68578151eb352c68740f5907d` |

- 戻しの材料として作業端末の `/tmp/porkadot-0.33.1`（`v0.33.1`）と `/tmp/fraction-stage-4`（`b2edd42`）を clone した。どちらも秘密を含まない clone（`assets/` の secrets は sops で暗号化されたまま）で、使わなかった
- 申し送り（段 5 の範囲の外）:
  - runbook §10 のとおり、1 日ほど様子を見てから Longhorn の更新（1.11.2 → 1.12.x → 1.13.x）に進む
  - `movies` の 3 つ（carib2、shja2、pondo2）が約 3 時間ごとに liveness の失敗・OOMKilled で再起動している。K8s の更新とは関係が無いが、次の段のベースラインでも restartCount が増える
  - 次の段以降の手順書に引き継ぐこと: 1.34 の apiserver は suggested でなくなった FlowSchema を消す、ServiceCIDR は自動で v1 にならないことがある、`ssh -n` の監視はノードの側の while が残る
