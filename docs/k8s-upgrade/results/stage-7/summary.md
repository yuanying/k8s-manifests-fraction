# 段 7 のまとめと完了の確認

本番 `fraction` の Kubernetes を v1.35.9 から v1.36.5 へ、CoreDNS を v1.13.2 から v1.14.7 へ上げた段 7（porkadot 0.35.0 → 0.36.0、crictl v1.36.0。etcd 3.6.15・CNI plugins v1.9.1 は据え置き）の、全体のまとめと完了の確認（runbook §6）の記録。手順は `../../runbook-stage-7.md`（以下 runbook）。
時刻は UTC。作業の前のクラスタ全体、cgroup・resolv.conf・unattended-upgrades・StrictIPCIDRValidation・MutatingAdmissionPolicy の確認、段の前の etcd のバックアップは `baseline.md`、`install kubernetes` と 2 つ目のバックアップは `control-plane.md`、各台の記録は `<ノード>.md`（control-plane は `192.168.1.11N.md`）。読み取りの出力はタスクディレクトリの `notes/stage-7/`（完了の確認は `final/`）。

## 1. 作業（2026-10-21）

porkadot のコマンドとノードへの `ssh` は、すべてサンドボックスの中（porkadot は runbook §1.4 の独立の clone `worktrees/porkadot-v0-36-0`）で流し、SSH の失敗は一度も無かった。どのノードも drain していない。承認の節目は 1 つ（段 7 の開始）で、ユーザーが承認した（PR #48 のマージ）。✋ の操作は、どれも流す直前に coordinator に知らせた。

| 順 | 対象 | 流した時刻（開始 → 終わり） | Pod の再起動 | 監視の FAIL | 記録 |
|---|---|---|---|---|---|
| — | `etcd backup`（段の前） | 12:59:15 → 12:59:18 | — | — | `baseline.md` §6 |
| 1 | `install kubernetes --node 192.168.1.111` | 13:01:39 → 13:04:41（**rc 0、1 回目で通った**） | 作り直し 17 個のほかは無い | VIP 1 回 | `control-plane.md` |
| — | `etcd backup`（1.36 の control-plane） | 13:08:44 → 13:08:47 | — | — | `control-plane.md` §5 |
| 2 | 192.168.1.113（リーダーを .111 へ移した） | 13:09:21 → 13:09:56 | etcd の mirror Pod だけ | 0 | `192.168.1.113.md` |
| 3 | 192.168.1.112 | 13:11:44 → 13:12:08 | etcd の mirror Pod だけ | etcd 1 サンプル | `192.168.1.112.md` |
| 4 | 192.168.1.111（リーダーを .113 へ移した） | 13:13:58 → 13:14:22 | etcd の mirror Pod だけ | 0 | `192.168.1.111.md` |
| 5 | pablo（API の VIP を告知。netcheck と NetworkPolicy の確認） | 13:19:29 → 13:19:53 | 無い | 0 | `pablo.md` |
| 6 | braque（JST 22:24。バックアップの時間帯の外） | 13:24:52 → 13:25:26 | 無い（nfsd も） | 0 | `braque.md` |
| 7 | oeilvert | 13:27:22 → 13:27:44 | 無い | 0 | `oeilvert.md` |
| 8 | duchamp | 13:29:16 → 13:29:41 | 無い | 0 | `duchamp.md` |
| 9 | chirico | 13:31:11 → 13:31:31 | 無い | LB 1 回 | `chirico.md` |

- `install kubernetes` から最後の worker まで約 30 分。1 台の `install kubelet` は 20 秒〜35 秒
- ロールバック（runbook §7）は一度も行っていない。runbook の止める条件（etcd の mirror Pod のほかのコンテナの再起動、`install kubelet` による iscsid の PID の変化、古い iSCSI のセッション、storage version の `OLD`、cgroup v1 のノード、etcd の unhealthy が続く、CoreDNS の `loop`）には一度も当たらなかった
- runbook から外れた操作は無い。runbook §8.12 に当たる Pod は無かった（同じ PVC を使う Running と Succeeded の組は `aphrael/aphrael-2` の NFS の PV だけ。natsumi と deep-researcher のバックアップは段 6 で消してあり、次の実行は 20:30Z・21:00Z）。Pod は 1 つも消していない

## 2. 完了の確認（runbook §6。2026-10-21 13:32Z〜13:41Z）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready、全台 v1.36.5、CONTAINER-RUNTIME が 8 台とも `containerd://2.3.6`。SchedulingDisabled のノードは無い |
| `/opt/bin`、CNI | 8 台とも `kubelet-v1.36.5`、`kubectl-v1.36.5`、`crictl-v1.36.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と bridge・host-local・portmap・loopback が 8 台とも `v1.9.1`（`/opt/cni/bin` の mtime は 2026-03-16 のまま） |
| etcd | 3/3 healthy、全メンバーが 3.6.15、cluster version・storage とも 3.6.0（3 台の `/version` が `{"etcdserver":"3.6.15","etcdcluster":"3.6.0","storage":"3.6.0"}`）。リーダー .113（`57ec6f12ac7b683e`）、raft term 23125、raft index 1403647919 でそろう。3 台の動いている etcd のフラグに `--experimental-` は無い。3 台の `/etc/etcd/pki` の 3 つのファイルが `600 root:root`。`member list` は 3 つとも `started` |
| VIP | `/readyz` `ok`、`/livez` 200（監視）、`/version` v1.36.5 |
| apiserver、controller-manager、scheduler、kube-proxy | kube-apiserver の DaemonSet 3/3（v1.36.5、generation 30。`-pvvmc` .111、`-vtv8d` .112、`-dnkpz` .113、restartCount 0）。controller-manager 2/2（.111 `-h9fg6` リーダー、.112 `-nlvtq`、generation 29）、scheduler 2/2（.111 `-5vqks` リーダー、.112 `-ntsf7`、generation 28）。kube-proxy 8/8（v1.36.5、generation 26） |
| CoreDNS | **v1.14.7、2/2 Running（chirico、duchamp。amd64）、generation 13、restartCount 0**。ログは `CoreDNS-1.14.7` で、`[ERROR]`・`[WARNING]`・`loop` は無い。プロセスは `Uid 65532`、`CapEff 0x400`（`control-plane.md` §4 の 20）。`tools/dns-check.sh` の答えは `baseline.md` §2 の 23 と同じ（Service と 2 つの Pod の 3 か所とも。違うのは kube-dns の Endpoint の Pod の IP が新しい Pod のものになったことだけ。`notes/stage-7/final/dns-check.txt`） |
| kubelet-serving-cert-approver | 1/1 Running（oeilvert、restartCount 0、generation 2 のまま） |
| Running / Completed 以外の Pod | 0 |
| restartCount | §2.1 |
| storage version | `tools/storage-versions.sh`: `prefixes: 66, keys: 2504, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は 1.36 の 2 行（`mutatingadmissionpolicies`・`mutatingadmissionpolicybindings` の `admissionregistration.k8s.io/v1beta1`）。`/registry/peerserverleases/` は core の `v1` の `Endpoints` 3 キーで `ok`（runbook §8.18） |
| StrictIPCIDRValidation | `tools/ipcidr-scan.py` は `# findings: 0` のまま（`non-canonical` も 0）。見た値の数は EndpointSlice 157、Endpoints 154、IPAddress 74、Ingress 66、Node 35、Pod 823、Service 167、ServiceCIDR 2（Pod の値は spec と status のすべての文字列を数えるので、Pod の数が同じでも 835 から変わる） |
| ServiceCIDR と IPAddress | `servicecidrs` は `kubernetes` の 1 つ（`10.254.0.0/24,fd20:afc2:7c09::/108`）。IPAddress は 74 で、ClusterIP の数と同じ。`ClusterIPNotAllocated` の event は段 7 の間に一度も出ていない |
| FlowSchema | 11 個、generation もベースラインと同じ |
| cgroup | 8 台とも `cgroup2fs` のまま、kubelet が 8 台とも動いている |
| Longhorn | attached healthy 16、detached unknown 1（`homegallery/cg-data`。ベースラインのとおり）。ボリュームのアタッチ先、replica（chirico 9、duchamp 12、oeilvert 9、pablo 2）、instance-manager（7 つとも同じ名前・IP で running）、engine image（`longhorn-engine:v1.13.0` だけが deployed）、Longhorn の node（4 つとも Ready、schedulable）がベースラインと同じ。**K8s 1.36 は Longhorn v1.13.0 の要件（1.34 以上）に入る**（runbook §1.10） |
| Longhorn の設定 | ベースラインのまま（`5`、`disabled`、`block-if-contains-last-replica`、`best-effort`、`6000`、v1.13.0） |
| iSCSI | 8 台の `tools/node-state.sh`（`notes/stage-7/final/node-<ノード>-after.txt`）で、`bin` の行のほか（iscsid の MainPID と起動の時刻、セッション、エンジン、`initiatorname.iscsi` の md5）が 8 台ともベースラインと同じ（diff 0 行）。**iscsid の PID が変わった台は無い**（§2.3）。Longhorn のセッションは pablo 1、oeilvert 2、duchamp 4、chirico 9 で、どれもそのノードの今の instance-manager の IP へのもの。**古いセッションは 0**。`older-than-iscsid` のエンジンは pablo 1・duchamp 4（段 6 の前の unattended-upgrades の iscsid の再起動による。エンジンは v1.13.0）で、増えていない |
| cnidaria | 8 台の Pod が Ready（restartCount はベースラインと同じ）。`verify-nodes.sh` 64 PASS、FAIL 0（nft を流すイメージを v0.1.1 にした写し。runbook §1.8）。cnidaria のログの error は各台の `install kubelet` の `no route`（runbook §8.1。oeilvert は 0、chirico は 1）。✋ `netcheck.sh`（13:35:44Z〜13:36:03Z）**168/168 PASS** |
| NetworkPolicy（runbook §1.9） | ✋ `npcheck.sh`（13:36:03Z〜13:38:34Z）: up の前の `nft` は 8 台とも 0、up の後は 8 台とも 9、`run` は **`OK 56, not OK 0`**、down の後は 8 台とも 0、`k8u-npcheck` は NotFound。pablo の後（13:21Z〜13:24Z）にも同じ結果 |
| MetalLB | gated の `192.168.1.200` と `[...:ace::200]` は 404（応答あり）。`::131`〜`::134` は SSH のバナーを返す。告知ノードは段の前と同じ（VIP pablo、gated-v4 chirico、gated-v6 oeilvert、`::131`・`::134` .112、`::132` .111、`::133` duchamp）。`install kubernetes` の apiserver の入れ替えの後に、同じノードで `serviceAnnounced` を出し直した |
| NFS、registry | oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で中身が読める。braque は 2049 を listen している。`registry.fraction.jp/v2/` は 401（応答あり） |
| metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個。`count by (job) (up)` はベースラインと同じ（`kube-etcd` 3、`apiserver` 3 など）、`count(etcd_server_has_leader)` 3 |
| `apiserver_requested_deprecated_apis` | `endpoints` `v1` と `metallb.io/v1beta1 addresspools`（`removed_release` なし）だけ。`removed_release` が 1.36 以前のものは無い |
| v1 Endpoints の warning の出どころ | §2.4 |
| CSR | 段の間に出た CSR は無い。8 台の kubelet の serving の証明書の subject と期限はベースラインと同じ |
| kubelet の起動時の warning | 8 台とも `Flag --container-runtime-endpoint has been deprecated` だけ（計画 §10 の KubeletConfiguration への移行の対象。段 8 で直す）。ほかに `Flag --`・deprecated の行は無い |

### 2.1 restartCount（ベースラインからの比べ）

- ベースラインの Pod（160 個）のうち、名前が同じまま残ったものは、control-plane の etcd の mirror Pod の 3 つのほか **UID と restartCount がすべて同じ**
  - etcd の mirror Pod の 3 つ: UID が変わり、restartCount 1（新しい mirror Pod の最初のコンテナが古い etcd の 2380 番の解放の前に起きて `bind: address already in use` で落ちたもの。runbook §4.1 のとおり、3 台とも 1 回）
- `install kubernetes` で作り直されたもの（apiserver 3、controller-manager 2、scheduler 2、kube-proxy 8、CoreDNS 2）は、新しい名前・UID で 17 個とも restartCount 0
- 消えた Pod・増えた Pod はほかに無い。完了の確認の時点の Pod は 160 個
- **1.36 の kubelet への更新で、コンテナの再起動は 8 台で 1 つも無かった**（runbook §8.4 のとおり。arm64 の control-plane、Longhorn の instance-manager・longhorn-manager・CSI、アタッチされたままのボリュームを使う Pod（chirico 9 本、duchamp 4 本、oeilvert 2 本、pablo 1 本。replica 1 の prometheus の 2 つを含む）、nfsd、CoreDNS を含む）

### 2.2 warning のイベント・ログ

- runbook §8 にあるもの: 置き換えられた古い apiserver と古い CoreDNS の止まりかけの間の probe の失敗、各台の cnidaria の `no route`、etcd の `bind: address already in use`（落ちた最初のコンテナ）と起き直しの直後の `failed to publish local member to cluster through raft`（.112 で 103 回、2.5 ミリ秒の間。runbook §4.4 の 18 を直した）・`apply request took too long`・`request stats`・`waiting for ReadIndex response took too long`・`ignored out-of-date read index response`、etcd の mirror Pod の `already exists`、1.36 の apiserver・KCM・scheduler の `The manifest file is empty, ignoring.`（各 Pod 1 行。runbook §8.17）
- 前の段の記録にあるもの: braque の `InvalidDiskCapacity`（kubelet の起動の直後）、pablo と braque の古い kubelet の `Failed to update lease`（`systemd-networkd` の再起動の間）、kube-proxy の起動のときの `Kube-proxy configuration may be incomplete or incorrect`（`nodePortAddresses` が無い。8 つとも 1 回）、controller-manager の `namespace_controller` の `Deletion of namespace failed`（38 件）と `daemon_controller` の `Unhandled Error`（37 件）。後の 2 つは `netcheck.sh`・`npcheck.sh` の名前空間の削除の間のもので、名前空間は消えた（段 5・段 6 と同じ）
- runbook に無かったもの（どれも害は無い）:
  - .111 の新しい apiserver の起動の直後（13:03:20Z）の `error resolving kube-system/metrics-server: service "metrics-server" not found` 4 行と `Unhandled Error` 1 行（`control-plane.md` §4 の注）。その後は出ていない
  - KCM の rollout の終わりの `replica_set.go` の `read version … is not as new as written version` と `disruption.go` の PDB の競合 1 行ずつ（`control-plane.md` §4 の注）
  - chirico の新しい kubelet の `Unable to write event`・`Error updating node status, will retry` 1 回ずつ（`systemd-networkd` の再起動で API への接続が切れたもの。`chirico.md`）
  - **3 台の apiserver の grpc の warning `addrConn.createTransport failed to connect to {Addr: "192.168.1.111:2379"…} … operation was canceled` が、1 台につき 1 分に 4 行続いている**（§2.6）
- scheduler の 2 つと CoreDNS の 2 つのログに、ほかの `E` の行は無い。etcd の 3 台のログの 13:15Z より後の warn・error は `apply request took too long`（101〜150 ミリ秒）だけで、.112 の 13:21:18Z（7 行。`netcheck.sh up` の DaemonSet の作成）、13:22:07Z（3 行。`npcheck.sh up`）、.111 の 13:38:21Z（1 行。`npcheck.sh down`）。runbook §8.13 の dev の注と同じ形で、ずっと軽い（VIP の監視は落ちていない。etcd の health の監視はこのときもう止めていた）。error は無い

### 2.3 iscsid の PID の変化とその見分け（runbook §2.11）

| ノード | ベースラインの前の変化 | 段 7 の作業の間 |
|---|---|---|
| 192.168.1.113 | 10-20 21:30:04Z に再起動（unattended-upgrades の needrestart。段 6 の前） | 変わらない（290821） |
| braque | 10-21 06:23:32Z に再起動（同じ。段 6 の前） | 変わらない（271131） |
| duchamp | 10-21 06:08:00Z に再起動（同じ。段 6 の前） | 変わらない（2695716） |
| pablo | 10-21 06:40:42Z に再起動（同じ。段 6 の前） | 変わらない（4114921） |
| .111、.112、chirico、oeilvert | 再起動していない（liblzma5 は 0.3 のまま） | 変わらない（90734、89578、4447、6334） |

- **porkadot の `install kubelet` による iscsid の再起動は 8 台で 0**（0.36.0 の `install-pkgs.sh` は `initiatorname.iscsi` が同じなら再起動しない。8 台とも `install-pkgs.sh` の apt は何も入れていない）。unattended-upgrades も段 7 の間には流れていない（8 台とも `apt-daily-upgrade.service` は inactive、`history.log` の最後は段 7 の前）
- `install kubelet` の後、`apt-daily-upgrade.timer` の次の時刻が 8 台とも引き直されていた（段 6 と同じ）: CP は 10-21 21:41:40Z〜21:51:23Z、worker は 10-22 06:20:18Z〜06:56:06Z。.111・.112・chirico・oeilvert は次の実行で liblzma5 が 0.4 になり、iscsid が再起動する見込み（chirico 9 本、oeilvert 2 本のボリュームがアタッチされたまま。段 6 の duchamp・pablo と同じく、iscsid が既存のセッションを引き取る見込み）

### 2.4 v1 Endpoints の warning の出どころ（runbook §6、§8.15）

`install kubernetes`（13:01:39Z）から 13:40Z までの、Running の 183 個のコンテナのログの `v1 Endpoints is deprecated` の行（タスクディレクトリの `notes/stage-7/final/endpoints-warnings.tsv`）。

| Pod（ノード） | コンテナ | 行の数 | 製品と版 |
|---|---|---|---|
| `longhorn-system/longhorn-manager-f9f8v`（pablo） | longhorn-manager | 8 | Longhorn v1.13.0 |
| `longhorn-system/longhorn-manager-lz9m4`（oeilvert） | longhorn-manager | 5 | 同上 |
| `longhorn-system/longhorn-manager-mc82c`（chirico） | longhorn-manager | 5 | 同上 |
| `longhorn-system/longhorn-manager-vdh56`（duchamp） | longhorn-manager | 5 | 同上 |
| `longhorn-system/longhorn-global-manager-…-98kkj`（duchamp） | longhorn-global-manager | 7 | 同上 |
| `longhorn-system/longhorn-global-manager-…-n8cl4`（chirico） | longhorn-global-manager | 6 | 同上 |
| `longhorn-system/longhorn-global-manager-…-td2h4`（oeilvert） | longhorn-global-manager | 9 | 同上 |
| `monitoring/kube-prometheus-operator-658779c859-zcrzg`（pablo） | kube-prometheus | 24 | prometheus-operator v0.90.1 |

- 段 6 と同じ 8 つのコンテナ。warning は振る舞いを変えない（v1 Endpoints は非推奨で、1.36 でも提供される）。prometheus-operator は段 8 の後の非クリティカルなコンポーネントの更新（計画 §8）で見直す

### 2.5 監視（runbook §2.3）の FAIL

- 監視は runbook §2.3 の新しい形（pi の `bg_run` で 1 つずつ、前景のループ）で起動し、**`install kubernetes` の間も止まらずに取れた**（dev の段 7 で欠けたもの）
- VIP と LB: 12:55:57Z から 13:41:4xZ まで流し（`ok` の行が 2520 回目まで）、ログはタスクディレクトリの `notes/stage-7/stage-7-probe.log`。**FAIL は VIP の 1 回**（13:02:42Z。`install kubernetes` の .112 の apiserver の入れ替え）と **LB の 1 回**（13:31:28Z。gated-v4 を告知する chirico の `systemd-networkd` の再起動。runbook §2.1 の 16 で許容）。VIP を告知する pablo の `install kubelet` の間も VIP は途切れなかった
- etcd の health: 12:56:2xZ から 13:15:4xZ まで、.111 と .112 から 2 秒ごと（`notes/stage-7/stage-7-etcd-192.168.1.11{1,2}.log`、1,721 サンプルずつ）。unhealthy は 13:12:10Z の .112 の 1 サンプル（起き直す台）だけ。ほかの 2 台が unhealthy になったことは無い。`install kubernetes` の直後（全体の apply の後）も 3 台とも healthy（runbook §8.13 の dev の遅れは本番では起きなかった）
- 止めた後、ノードの側の `while :` が .111 と .112 に残っていたので、PID を確かめて kill した（runbook §2.3 のとおり）

### 2.6 apiserver の grpc の `operation was canceled`（runbook に無かったもの）

1.36 の 3 台の apiserver が、`W… logging.go:55] [core] [Channel #N SubChannel #M] grpc: addrConn.createTransport failed to connect to {Addr: "192.168.1.111:2379", …}. Err: connection error: desc = "transport: Error while dialing: dial tcp 192.168.1.111:2379: operation was canceled"` を、1 台につき 1 分に 4 行（30 秒ごとに 2 行）出し続けている。

- **時刻は、Prometheus の 2 つのレプリカがその apiserver の `/metrics` を scrape した時刻とミリ秒の単位で一致する**（例: .112 の apiserver は、`prometheus-kube-prometheus-0` の 13:40:31.877Z と `-1` の 13:40:38.529Z の scrape に対して、13:40:31.894Z と 13:40:38.533Z。.111・.113 も同じ）。`apiserver` の scrape の間隔は 30 秒で、`up` は 3 つとも 1
- apiserver は metrics を集めるたびに etcd の DB のサイズを読む短命の client を作って閉じる（`k8s.io/apiserver/pkg/storage/storagebackend/factory/factory.go` の `CreateMonitor` → `etcd3.go` の `newETCD3ProberMonitor`）。閉じるときに、まだつながっていない endpoint（`--etcd-servers` の先頭の .111）への dial が cancel され、grpc がそれを warning で書く
- **このコードは v1.35.9 と v1.36.5 で同じ**（`factory.go` は差が無く、`etcd3.go` の差は grpc の metrics の package の入れ替えだけ）。dev の 1.36 の apiserver には出ていないが、dev には Prometheus が無い。なので 1.36 で新しく出たものではなく、1.35 の本番でも出ていたものと見ている（1.35 の apiserver のログは入れ替えで消えたので、確かめていない）
- 害は無い（scrape は通り、etcd は 3/3 healthy）。段を止める理由にしていない。runbook §8.19 に足した。段 8 の前の dev の検証か、段 8 の本番の `install kubernetes` の前に、1.36 の apiserver のログで同じ形が出ていることを確かめられる

### 2.7 leader election で再起動した controller（runbook §8.8）

無い（`gated-system/gated` の 2 つ、`longhorn-system` の CSI sidecar 12 個とも restartCount はベースラインのまま。`csi-attacher-…-s6fmv` の 1 は段 6 の前から）。controller-manager と scheduler は `install kubernetes` で作り直され、その後のリーダー（どちらも .111 の Pod）は変わっていない。.111 の `install kubelet` の間もリーダーのまま。

## 3. 片付けと、残したこと

- 一時的な名前空間 `cnidaria-netcheck`・`k8u-npcheck` は消した（NotFound）
- `infra-admin` のトークン: pablo の後の NetworkPolicy の確認（13:21:43Z 発行、13:24:28Z にファイルを消した）と、完了の確認（13:36:03Z 発行、13:38:34Z にファイルを消した）の 2 回。どちらも 1 時間の期限で、作業端末の `/tmp/k8u-stage7-admin-token`（モード 600）に置いた。サーバーの側では最も遅いもので 14:36Z ごろに期限が切れる。§8.12 の Pod の削除が無かったので、ほかには発行していない
- 監視は止めた（VIP と LB は 13:41:4xZ、etcd の health は 13:15:4xZ。ノードの側の while も止めた）
- etcd のバックアップは段 7 の worktree の `./backup/` にある（git には入れていない）。worktree を片付ける前に、メインの checkout の `backup/` へ移す（coordinator）。段 7 が落ち着くまで消さない

  | ファイル | 中身 | バイト | sha256 |
  |---|---|---|---|
  | `etcd-2026-10-21T12:59:15+00:00.db` | 段の前（1.35 の control-plane、CoreDNS v1.13.2） | 55,107,616 | `a8e40ed48472f0e09c9028a9778b895a8a862104f36e4ddd5654984f4ef30875` |
  | `etcd-2026-10-21T13:08:44+00:00.db` | 1.36 の control-plane、CoreDNS v1.14.7、kubelet は 1.35 | 55,107,616 | `fd239f03267a6f5b48f5299c5b9398541371d9a575159c358c9c65ecba547f40` |

- 確認に使ったスクリプトの写し（作業端末の `/tmp/k8u7w/`。段 6 の worker のスクリプトの道筋を段 7 に替えたもの、cnidaria の手順書のスクリプトの写し）は秘密を含まない。ノードには何も残していない
- 申し送り（段 7 の範囲の外）:
  - §2.6 の apiserver の grpc の `operation was canceled`。1.35 でも出ていたかを確かめていない
  - runbook §2.11 の unattended-upgrades の needrestart による iscsid の再起動。.111・.112・chirico・oeilvert はまだ liblzma5 が 0.3 で、次の実行（CP は 10-21 21:41Z〜、worker は 10-22 06:20Z〜）で再起動する見込み。段 8 の当日も時間帯と PID を読み直す
  - runbook-stage-6 §2.10 の CoreDNS の upstream に kube-dns が入る件（porkadot の `dns` の addon と Corefile）。v1.14.7 でも `loop` は出ていない
  - arm64 の CoreDNS は本番ではまだ動いていない（2 つの Pod が amd64 の worker に置かれた。runbook §2.13 のとおり）
  - cnidaria-cni-dev の `notes/fraction-runbook/common.sh` の `IMAGE`（`v0.1.0`）。段 7 も写しを `v0.1.1` にして流した
