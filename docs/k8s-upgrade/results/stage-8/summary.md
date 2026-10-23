# 段 8 のまとめと完了の確認

本番 `fraction` の Kubernetes を v1.36.5 から v1.37.1 へ、etcd を 3.6.15 から 3.7.3 へ上げた段 8（porkadot 0.36.0 → 0.37.0、crictl v1.37.0、kubelet の `containerRuntimeEndpoint`、CoreDNS の Corefile の `cache`。CoreDNS v1.14.7・CNI plugins v1.9.1 は据え置き）の、全体のまとめと完了の確認（runbook §6）の記録。計画の最後の段。手順は `../../runbook-stage-8.md`（以下 runbook）。
時刻は UTC。段の前は `baseline.md`、`install kubernetes` と 2 つ目のバックアップは `control-plane.md`、control-plane の各台と etcd 3.7 は `192.168.1.11N.md`、worker の 5 台（と、8 台に流れた `install kubelet`、oeilvert の `cpu_manager_state`）は `workers.md`。読み取りの出力はタスクディレクトリの `notes/stage-8/`（完了の確認は `final/`）。

## 1. 作業（2026-10-23）

porkadot のコマンドとノードへの `ssh` は、すべてサンドボックスの中（porkadot は runbook §1.4 の独立の clone `worktrees/porkadot-v0-37-0`）で流し、SSH の失敗は無かった。どのノードも drain していない。承認の節目は 2 つで、どちらもユーザーが承認した（段 8 の開始は 22:05Z の PR #52 のマージ、control-plane の kubelet = etcd 3.7 は 22:3xZ）。✋ の操作は、どれも流す直前に coordinator に知らせた。

| 順 | 対象 | 流した時刻（開始 → 終わり） | Pod の再起動 | 監視の FAIL | 記録 |
|---|---|---|---|---|---|
| — | `etcd backup`（段の前） | 22:17:11 → 22:17:14 | — | — | `baseline.md` §7 |
| 1 | `install kubernetes --node 192.168.1.111` | 22:19:51 → 22:22:52（**rc 0、1 回目で通った**） | 作り直し 15 個と、CoreDNS の `loop` の 1 回 | VIP 1 回 | `control-plane.md` |
| — | `etcd backup`（1.37 の control-plane、etcd 3.6） | 22:27:19 → 22:27:23 | — | — | `control-plane.md` §6 |
| 2 | 192.168.1.113（リーダーを .111 へ移した） | 22:34:44 → 22:35:05 | etcd の mirror Pod だけ | etcd 1 サンプル | `192.168.1.113.md` |
| 3 | 192.168.1.112 | 22:36:42 → 22:36:57 | etcd の mirror Pod だけ | etcd 2 サンプル | `192.168.1.112.md` |
| 4 | 192.168.1.111（リーダーを .113 へ移した。この後 cluster version 3.7.0） | 22:39:41 → 22:39:59 | etcd の mirror Pod だけ | etcd 2 サンプル | `192.168.1.111.md` |
| — | `etcd backup`（全台 3.7、3.7 の etcdctl） | 22:41:23 → 22:41:26 | — | — | `192.168.1.111.md` §4.5 |
| 5 | **worker 5 台（pablo のつもりの `--node 192.168.1.134` が 8 台に流れた）** | 22:44:00 → 22:44:45 | 無い | LB 1 回 | `workers.md` §1 |
| — | oeilvert の 1.37 の kubelet が起きない → `cpu_manager_state` の退避（ユーザーの承認） | 22:44:25 → 22:53:21 | 無い | 0 | `workers.md` §2・§3 |

- `install kubernetes` から最後の確認まで約 45 分（22:19Z〜23:06Z）
- **runbook から外れたこと**（どちらも `workers.md`）:
  1. **pablo の `install kubelet` に IP（`--node 192.168.1.134`）を渡したため、8 台すべてに流れた**（`porkadot.yaml` の worker のキーは名前で、porkadot は一致しない `--node` を全ノードとして扱う）。worker の 5 台が同時に上がり、control-plane の 3 台にも 2 回目が流れた。止めて報告し、各台の確認を後からまとめて行って合格した
  2. **oeilvert の 1.37 の kubelet が、2020 年の `cpu_manager_state` を読めずに起きなかった**。ユーザーの承認（22:48Z）を得てファイルを `cpu_manager_state.bak-k8u8` に退避し、kubelet が自動再起動で起きた。その間、oeilvert の Node は Ready のままで、Pod の退避も再起動も無かった
- ロールバック（runbook §7）と `etcd restore` は行っていない。runbook の止める条件（etcd の mirror Pod のほかのコンテナの再起動、`install kubelet` による iscsid の再起動、古い iSCSI のセッション、storage version の `OLD`、cgroup v1、etcd の unhealthy が続く、CoreDNS の CrashLoopBackOff）には当たらなかった
- runbook §8.12 の Succeeded の Pod（duchamp の natsumi の 9 つ、chirico の `deep-researcher-backup` の 3 つ）は、上の 1 で消す前に kubelet が上がった。kubelet の更新が済んだので消していない（coordinator の指示。`workers.md` §6）

## 2. 完了の確認（runbook §6。2026-10-23 22:59Z〜23:06Z）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready、全台 v1.37.1、CONTAINER-RUNTIME が 8 台とも `containerd://2.3.6`。SchedulingDisabled のノードは無い |
| `/opt/bin`、CNI | 8 台とも `kubelet-v1.37.1`、`kubectl-v1.37.1`、`crictl-v1.37.0`、`etcdctl-3.7.3`、`etcdutl-3.7.3`。CNI の印と 4 つのプラグインが 8 台とも `v1.9.1` |
| etcd | 3/3 healthy、**全メンバーが 3.7.3、cluster version・storage とも 3.7.0**（3 台の `/version` が `{"etcdserver":"3.7.3","etcdcluster":"3.7.0","storage":"3.7.0"}`）。リーダー .113、raft term 23127、raft index 1404921642〜643 でそろう。DB 55 MB。3 台の動いている etcd のフラグに `--experimental-` は無い（3.6 と同じフラグ）。3 台の `/etc/etcd/pki` が `600 root:root`。`member list` は 3 つとも `started`。etcd の Pod は 3 つとも `etcd:3.7.3-0`、restartCount 0。22:42Z の後の warn は .111 の `apply request took too long` 1 行だけ |
| VIP | `/readyz` `ok`、`/livez` 200（監視）、`/version` v1.37.1 |
| apiserver、controller-manager、scheduler、kube-proxy | kube-apiserver の DaemonSet 3/3（v1.37.1、generation 31）。controller-manager 2/2（.113 `-fn94h` リーダー、.111 `-2xdnl`、generation 30）、scheduler 2/2（.113 `-4g4gg` リーダー、.111 `-9p84r`、generation 29）。kube-proxy 8/8（v1.37.1、generation 27）。どれも restartCount 0 |
| CoreDNS | **v1.14.7、2/2 Running（duchamp `-469lz`、chirico `-shdgn`）、generation 13**。Corefile は `cache 30 {` `disable success cluster.local` `disable denial cluster.local` `}`。restartCount は `-469lz` 7（ベースラインのまま）、`-shdgn` 5（`install kubernetes` の reload の `loop` の 1 回。`control-plane.md` §4 の 13）。今のコンテナのログに `[ERROR]`・`FATAL`・`loop` は無い。`tools/dns-check.sh` の答えは `baseline.md` §2 の 23 と同じ（Service と 2 つの Pod の 3 か所とも、diff 0 行）。**TTL**: `kubernetes.default.svc.cluster.local` は 2 つの Pod とも 30（cache されない）、`kubernetes.default.svc.fraction.cluster` は 20 と 10、`github.com` は 18 と 8（`control-plane.md` と同じ形） |
| kubelet-serving-cert-approver | 1/1、`0.12.1`、generation は変わらない |
| Running / Completed 以外の Pod | 0 |
| restartCount | §2.1 |
| storage version | `tools/storage-versions.sh`: `prefixes: 67, keys: 2561, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は 1.37 の 4 行。`/registry/clustertrustbundles/` は `certificates.k8s.io/v1beta1` の `ok` で 1 キー（`kubernetes.io:kube-apiserver-serving:e861f40efa6f73a9415ecb89`） |
| StrictIPCIDRValidation | `tools/ipcidr-scan.py` は `# findings: 0`。見た値は EndpointSlice 153、Endpoints 150、IPAddress 72、Ingress 62、Node 35、Pod 838、Service 163、ServiceCIDR 2 |
| ServiceCIDR と IPAddress | `servicecidrs` は `kubernetes` の 1 つ（`10.254.0.0/24,fd20:afc2:7c09::/108`）。Service 77、ClusterIP の数 72、IPAddress 72。`ClusterIPNotAllocated` の event は無い |
| FlowSchema | 11 個、generation もベースラインと同じ |
| cgroup | 8 台とも `cgroup2fs` のまま、kubelet が 8 台とも active |
| `containerRuntimeEndpoint` | 8 台とも `kubelet.service` に `--container-runtime-endpoint` が無く、`config.yaml` に `containerRuntimeEndpoint: unix:///run/containerd/containerd.sock` がある。`crictl version` は containerd v2.3.6。`Effective KubeletConfiguration` に `containerRuntimeEndpoint`。**新しい kubelet の起動の後の `Flag --… has been deprecated` は 8 台とも 0**（段 7 までの `--container-runtime-endpoint` の warning が消えた。計画 §10） |
| `cpu_manager_state` | 8 台とも `{"policyName":"none","defaultCpuSet":"","checksum":1353318690…}` の形（oeilvert は退避の後に作り直されたもの。退避した古いファイルは oeilvert の `/var/lib/kubelet/cpu_manager_state.bak-k8u8` に残っている） |
| Longhorn | attached healthy 16（chirico 11、duchamp 5）、detached unknown 1（`homegallery/cg-data`。ベースラインのとおり）。replica（chirico 11、duchamp 12、oeilvert 8、pablo 1）、instance-manager（5 つとも同じ名前・IP で running）、engine image（`longhorn-engine:v1.13.0` だけが deployed）、Longhorn の node（4 つとも Ready、schedulable）がベースラインと同じ。**K8s 1.37 は Longhorn v1.13.0 の要件（1.34 以上）に入る**（runbook §1.10） |
| Longhorn の設定 | ベースラインのまま（`5`、`disabled`、`block-if-contains-last-replica`、`best-effort`、`6000`、v1.13.0） |
| iSCSI | §2.3 |
| cnidaria | 8 台の Pod が Ready（restartCount はベースラインと同じ）。`verify-nodes.sh` 64 PASS、FAIL 0。✋ `netcheck.sh`（23:02:33Z〜23:02:53Z）**168/168 PASS**（pablo の後に代わる 22:56Z にも 168/168）。cnidaria のログの error / `no route` の増えは、各台の `systemd-networkd` の再起動の間の info の行（`workers.md` §4） |
| NetworkPolicy（runbook §1.9） | ✋ `npcheck.sh`（23:02:53Z〜23:05:30Z）: up の前の `nft` は 8 台とも 0、up の後は 8 台とも 9、`run` は **`OK 56, not OK 0`**、down の後は 8 台とも 0、`k8u-npcheck` は NotFound。22:56Z〜22:59Z にも同じ結果 |
| MetalLB | gated の `192.168.1.200` と `[2405:6580:6740:ac01:ace::200]` は 404（応答あり）。`::131`〜`::134` は SSH のバナーを返す。告知ノードは段の前と同じ（VIP と gated-v6 は pablo、gated-v4 chirico、`::131` .113、`::132`・`::134` duchamp、`::133` oeilvert）。pool は `baseline.md` §2 の 31 と同じ |
| NFS、registry | oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で中身が読める。braque は 2049 を listen している。`registry.fraction.jp/v2/` は 401（応答あり） |
| metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個。`count by (job) (up)` はベースラインと同じ（`kube-etcd` 3、`apiserver` 3 など 14 の job）、`count(etcd_server_has_leader)` 3（etcd 3.7 のサーバーの metrics が取れている） |
| `apiserver_requested_deprecated_apis` | `endpoints` `v1` と `metallb.io/v1beta1 addresspools`（`removed_release` なし）だけ。`removed_release` が 1.37 以前のものは無い |
| v1 Endpoints の warning の出どころ | §2.4 |
| CSR | 段の間に出た CSR は無い。8 台の kubelet の serving の証明書の subject と期限はベースラインと同じ |
| apiserver の grpc の `operation was canceled` | **1.37 の apiserver は出していない**（3 台とも直近 10 分で 0 行。1.36 では 10 分に 35〜40 行。runbook §8.19 を直した） |

### 2.1 restartCount（ベースラインからの比べ）

- ベースラインの Pod（169 個）のうち、`install kubernetes` で作り直された 15 個（apiserver 3、KCM 2、scheduler 2、kube-proxy 8。新しい名前・UID で restartCount 0）のほかに変わったのは次の 4 つだけ
  - etcd の mirror Pod の 3 つ: UID が変わり、restartCount 1 → 0（3.7.3 の最初のコンテナが落ちずに起きた）
  - CoreDNS の `-shdgn`: restartCount 4 → 5（`install kubernetes` の Corefile の reload の直後の `[FATAL] plugin/loop`。runbook §3.3 の 13 の想定どおり。CrashLoopBackOff にはならず、その後は増えていない）
- 消えた Pod・増えた Pod はほかに無い。完了の確認の時点の Pod は 169 個
- **1.37 の kubelet への更新で、コンテナの再起動は 8 台で 1 つも無かった**（runbook §8.4 のとおり。arm64 の control-plane、Longhorn の instance-manager・longhorn-manager・CSI、アタッチされたままのボリュームを使う Pod（chirico 11 本、duchamp 5 本。replica 1 の prometheus の 2 つを含む）、nfsd、CoreDNS を含む）。oeilvert の kubelet が 9 分起きなかった間も、oeilvert のコンテナは動き続けた

### 2.2 warning のイベント・ログ

- runbook §8 にあるもの: 置き換えられた古い apiserver の `Readiness probe failed … connection refused`、各台の cnidaria の `no route`、etcd の起き直しの直後の `failed to publish local member to cluster through raft`（.112 102 回、.111 46 回、.113 0 回。どれも 0.2 秒以内に `published`）・`lost`/`closed TCP streaming connection`・`peer became inactive`・`apply request took too long`、3.6 のリーダーの `leader found higher-versioned member`（混在中だけ）、etcd の mirror Pod の `already exists`、1.37 の apiserver・KCM・scheduler の `The manifest file is empty, ignoring.`（各 Pod 1 行）、CoreDNS の `plugin/loop` の 1 回
- 前の段の記録にあるもの: kube-proxy の `nodePortAddresses is unset`、KCM の rollout の終わりの `read version … is not as new as written version`、.111 の新しい apiserver の `error resolving kube-system/metrics-server`、`netcheck.sh`・`npcheck.sh` の名前空間の削除の間の KCM の `Deletion of namespace failed`・`Unhandled Error`
- 段 8 で新しく出たもの（害は無い）:
  - 1.37 の kubelet の起動の `V2 checkpoint for memory manager is corrupt, falling back to V1`（8 台とも 1 回。memory manager の checkpoint の形の移し替え）と、複数行の `Effective KubeletConfiguration`（runbook §2.12）
  - 止まる前の 1.36 の kubelet と、chirico の新しい kubelet の `Missing actuated resource record`（chirico は `alertmanager-kube-prometheus-1` の `config-reloader` と `news-agent-0` の `host` で 1 分に 1〜2 行続いている。コンテナの再起動は無い）
  - oeilvert の kubelet が起きなかった間の `cpu_manager.go` の error（§1）と、apiserver の `DELETE resourceslices` の timeout（22:46〜22:47Z、数行）
  - .112 の etcd の mirror Pod が約 87 秒 API に無かったこと（`192.168.1.112.md` の注。runbook §8.24 に足した）

### 2.3 iscsid の PID とセッション（runbook §2.7、§2.11）

| ノード | 段の前（22:09Z） | 完了の確認（23:06Z） | 見分け |
|---|---|---|---|
| 192.168.1.111 | 522641 | 522641 | 変わらない |
| 192.168.1.112 | 414810 | 414810 | 変わらない |
| 192.168.1.113 | 290821 | 290821 | 変わらない |
| braque | 271131 | 271131 | 変わらない |
| chirico | 3144486（セッション 11） | 3144486（セッション 11） | 変わらない |
| duchamp | 2695716（セッション 5） | 2695716（セッション 5） | 変わらない |
| oeilvert | 0（`iscsid.socket` だけ） | **912599**（22:44:23Z） | `install-pkgs.sh` の `systemctl start iscsid.service` による起動（`Starting` → `Started` だけで `Stopping` は無い。アタッチは 0 のまま）。runbook §2.7 の想定どおり |
| pablo | 4114921 | 4114921 | 変わらない |

- **porkadot の `install kubelet` による iscsid の再起動は 8 台で 0**。unattended-upgrades も段 8 の間には流れていない（8 台とも `apt-daily-upgrade.service` は inactive）
- 8 台の `tools/node-state.sh` の差はベースラインから `bin` の行（と oeilvert の iscsid）だけ。セッションは同じ sid・portal・target で、portal はどれもそのノードの今の instance-manager の IP。**古いセッションは 0**。`older-than-iscsid` のエンジンは duchamp 4、chirico 9 のまま（エンジンは v1.13.0）
- `install kubelet` の後、`apt-daily-upgrade.timer` の次の時刻が引き直された（例: chirico 10-24 06:11Z、duchamp 06:29Z、.113 10-24 21:29Z）

### 2.4 v1 Endpoints の warning の出どころ（runbook §6）

`install kubernetes`（22:19:51Z）から 23:0xZ までの、Running のコンテナのログの `v1 Endpoints is deprecated` の行（タスクディレクトリの `notes/stage-8/final/endpoints-warnings.tsv`）。

| Pod（ノード） | コンテナ | 行の数 | 製品と版 |
|---|---|---|---|
| `longhorn-system/longhorn-manager-f9f8v`（pablo） | longhorn-manager | 8 | Longhorn v1.13.0 |
| `longhorn-system/longhorn-manager-lz9m4`（oeilvert） | longhorn-manager | 6 | 同上 |
| `longhorn-system/longhorn-manager-mc82c`（chirico） | longhorn-manager | 6 | 同上 |
| `longhorn-system/longhorn-manager-vdh56`（duchamp） | longhorn-manager | 8 | 同上 |
| `longhorn-system/longhorn-global-manager-…-98kkj`（duchamp） | longhorn-global-manager | 7 | 同上 |
| `longhorn-system/longhorn-global-manager-…-jgpsn`（pablo） | longhorn-global-manager | 10 | 同上 |
| `longhorn-system/longhorn-global-manager-…-n8cl4`（chirico） | longhorn-global-manager | 7 | 同上 |
| `monitoring/kube-prometheus-operator-658779c859-zcrzg`（pablo） | kube-prometheus | 30 | prometheus-operator v0.90.1 |

- 段 7 と同じ製品（longhorn-global-manager の 1 つは oeilvert から pablo に移っている）。v1 Endpoints は 1.37 でも提供される。prometheus-operator は段 8 の後の非クリティカルなコンポーネントの更新（計画 §8）で見直す

### 2.5 監視（runbook §2.3）の FAIL

- VIP と LB: 22:17:02Z から 23:05:4xZ まで（`ok` の行が 2700 回目まで。ログはタスクディレクトリの `notes/stage-8/stage-8-probe.log`）。**FAIL は VIP の 1 回**（22:21:45Z。`install kubernetes` の apiserver の入れ替え）と **LB の 1 回**（22:44:31Z。gated-v4 を告知する chirico の `systemd-networkd` の再起動）。VIP を告知する pablo の `install kubelet` の間も VIP は途切れなかった
- etcd の health: 22:17:03Z から 22:41:27Z まで、.111 と .112 から 2 秒ごと（`notes/stage-8/stage-8-etcd-192.168.1.11{1,2}.log`）。unhealthy は起き直す台の 1〜2 サンプルだけ（22:35:06Z .113、22:36:57Z・22:37:01Z .112、22:39:59Z・22:40:03Z .111）。ほかの 2 台が unhealthy になったことは無い。`install kubernetes` の直後も 3 台とも healthy
- 止めた後、ノードの側の `while :` が .111 と .112 に残っていたので、PID を確かめて kill した

### 2.6 leader election で再起動した controller（runbook §8.8）

無い（`gated-system/gated` の 2 つ、`longhorn-system` の CSI sidecar 12 個とも restartCount はベースラインのまま）。controller-manager と scheduler は `install kubernetes` で作り直され、その後のリーダー（どちらも .113 の Pod）は変わっていない。

## 3. 片付けと、残したこと

- 一時的な名前空間 `cnidaria-netcheck`・`k8u-npcheck` は消した（NotFound）
- `infra-admin` のトークン: 22:56:36Z に 1 時間の期限で発行し、作業端末の `/tmp/k8u-stage8-admin-token`（モード 600）に置いた。NetworkPolicy の確認の 2 回に使い、23:05:30Z にファイルを消した（サーバーの側では 23:56Z ごろに期限が切れる）。§8.12 の Pod の削除が無かったので、ほかには発行していない
- 監視は止めた（VIP と LB は 23:05:4xZ、etcd の health は 22:41:3xZ。ノードの側の while も止めた）
- oeilvert の `/var/lib/kubelet/cpu_manager_state.bak-k8u8`（2020 年の古いファイル）は残してある。消すかはユーザーが決める
- etcd のバックアップは段 8 の worktree の `./backup/` にある（git には入れていない）。worktree を片付ける前に、メインの checkout の `backup/` へ移す（coordinator）。段 8 が落ち着くまで消さない

  | ファイル | 中身 | バイト | sha256 |
  |---|---|---|---|
  | `etcd-2026-10-23T22:17:11+00:00.db` | 段の前（1.36 の control-plane、etcd 3.6、Corefile `cache 30`） | 55,107,616 | `3bf146222c89a49b835c1634a4d8b3624b48f5ba5252abcfb258ab5cb3196c64` |
  | `etcd-2026-10-23T22:27:19+00:00.db` | 1.37 の control-plane、新しい Corefile、etcd 3.6 | 55,107,616 | `34674bc8310100d9d7371e85c6842232185ba9379dcc76f0d591fcb2b7fa7104` |
  | `etcd-2026-10-23T22:41:23+00:00.db` | 全台 etcd 3.7.3（cluster 3.7.0）、worker の kubelet は 1.36 | 55,107,616 | `d27e68b6fc221cac41a5ee73abafad895bcd32b212965bf971c97b69aaaf32ac` |

- 確認に使ったスクリプトの写し（作業端末の `/tmp/k8u8w/`）は秘密を含まない。ノードには `cpu_manager_state.bak-k8u8` のほかは何も残していない
- runbook の直し（この PR）: §1.4・§5.2（`--node` には `porkadot.yaml` のキーを渡す。worker は名前）、§1.8（`check-apps.sh` の `CHECK_URLS` の v6）、§2.2 の 33 と §8.23（古い `cpu_manager_state`）、§8.19（1.37 の apiserver は grpc の warning を出さない）、§8.24（etcd の mirror Pod の作り直しの遅れ）
- 申し送り（段 8 の範囲の外）:
  - **porkadot の `install kubelet --node` が、`porkadot.yaml` のキーに無い値を全ノードとして扱う**（`KubeletList#[]` が nil を返し、`install hosts: nil` が全ノードを選ぶ）。一致しないときはエラーにする直しを porkadot に入れるのがよい
  - 古い `cpu_manager_state` の件は、段 8 の後に入れるノードや dev の手順書にも効く（1.37 以上の kubelet）
  - chirico の kubelet の `Missing actuated resource record`（§2.2）。1 日ほど様子を見るときに続いているかを見る
  - runbook §10 の申し送り（CoreDNS の upstream に kube-dns が入る件。段 8 でも `loop` で 1 回再起動した、など）
  - oeilvert の resolv.conf の 192.168.0.1 の重なり（`baseline.md` §4）
