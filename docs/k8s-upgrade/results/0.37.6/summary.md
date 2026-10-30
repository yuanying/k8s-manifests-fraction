# porkadot 0.37.6 on fraction: まとめ

本番 `fraction` の Kubernetes を v1.37.1 → **v1.37.2**、CoreDNS を v1.14.7 → **v1.15.0** へ上げた（porkadot 0.37.5 → 0.37.6、`../../runbook-0.37.6.md` のとおり）。drain はしていない。時刻は UTC。各段の記録は `baseline.md`、`control-plane.md`、`192.168.1.11{3,2,1}.md`、`pablo.md`・`braque.md`・`oeilvert.md`・`duchamp.md`・`chirico.md`。出力はタスクディレクトリの `notes/0-37-6/`（`final/` が完了の確認）。

## 1. 流れ

| 時刻 | 何をしたか | 結果 |
|---|---|---|
| 11:05〜11:09 | ベースライン（読み取り） | runbook §2.2 と全項目同じ |
| 11:09:21〜11:10:23 | ✋ イメージの事前 pull（8 台） | 15 の pull がすべて rc 0 |
| 11:10:29 | ✋ etcd のバックアップ（1 回目） | rc 0、74,612,768 B |
| 11:10:4x | 監視 7 つをジョブで起動 | — |
| 11:12:17〜11:15:04 | ✋ `install kubernetes --node 192.168.1.111` | rc 0。11:15:44Z に 5 つの rollout が完了 |
| 11:15〜11:20 | §3.3 の確認 | 合格（別タスクの natsumi-penelope は `control-plane.md` §6） |
| 11:21:08 | ✋ etcd のバックアップ（2 回目） | rc 0、74,612,768 B |
| 11:21:30・11:21:38〜11:22:00 | ✋ move-leader（.113 → .111）、✋ `install kubelet --node 192.168.1.113` | rc 0 |
| 11:23:35〜11:24:08 | ✋ `install kubelet --node 192.168.1.112` | rc 0（iscsid は 0 → 新しい PID の起動） |
| 11:25:44・11:25:58〜11:26:20 | ✋ move-leader（.111 → .113）、✋ `install kubelet --node 192.168.1.111` | rc 0 |
| 11:28:27〜11:28:47 | ✋ `install kubelet --node pablo` | rc 0 |
| 11:30:20〜11:33:04 | ✋ netcheck と npcheck | 168/168、OK 56 / not OK 0 |
| 11:33:14〜11:33:44 | ✋ `install kubelet --node braque` | rc 0 |
| 11:34:57〜11:35:11 | ✋ `install kubelet --node oeilvert` | rc 0 |
| 11:36:24〜11:36:47 | ✋ `install kubelet --node duchamp` | rc 0 |
| 11:38:01〜11:38:19 | ✋ `install kubelet --node chirico` | rc 0 |
| 11:39:48〜11:46:20 | §6 の完了の確認、✋ netcheck と npcheck、監視を止めた | 合格 |

`install kubernetes` から最後の `install kubelet` まで 26 分。どの porkadot の操作も、流す前と後で `git status --short assets porkadot.yaml` は空、SSH 先はその台だけだった。runbook §6 の止める条件には一度も当たらなかった。

## 2. 完了の確認（runbook §6。11:39:48〜11:46Z）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready、全台 **v1.37.2**、`containerd://2.3.6`。SchedulingDisabled のノードは無い |
| `/opt/bin`、CNI | 8 台とも `kubelet-v1.37.2`、`kubectl-v1.37.2`、`crictl-v1.37.0`、`etcdctl-3.7.3`、`etcdutl-3.7.3`。CNI の印と 4 つのプラグインが 8 台とも `v1.9.1` |
| etcd | 3/3 healthy、3 台とも `{"etcdserver":"3.7.3","etcdcluster":"3.7.0","storage":"3.7.0"}`。リーダー .113、raft term 23129、raft index 3 台とも 1408405357。DB 75 MB。etcd の Pod の UID・restartCount とコンテナの ID・起動の時刻はベースラインと同じ（**作り直されていない**）。11:10Z からの warn 以上は `apply request took too long`（.111 29、.112 26、.113 7）と `request stats` 1 行ずつ |
| VIP | `/livez` `ok`、`/version` v1.37.2、`/readyz` 200 |
| apiserver、KCM、scheduler、kube-proxy | v1.37.2。`kube-apiserver` 3/3（generation 32）、KCM 2/2（31。.112 `-5zz9j`、.111 `-cv2bb` がリーダー）、scheduler 2/2（30。.112 `-5pfsh`、.111 `-7blnt` がリーダー）、kube-proxy 8/8（28）。どれも restartCount 0 |
| **CoreDNS** | **v1.15.0、2/2 Running**（chirico `coredns-74668cf466-4kjb5`、duchamp `coredns-74668cf466-lsjhk`）、generation 15、restart 0、前のコンテナは無い。2 つとも `Seccomp: 2`・`Seccomp_filters: 1`・`CapEff` `0x400`（`RuntimeDefault`）。ログは起動の行だけ（error・warn・fatal・loop 0）。`endpoints.sh` の rcode と答え（flags を除く）と `tools/dns-check.sh`（CoreDNS の Pod の IP を読み替え）はベースラインと同じ。`coredns_build_info{goversion="go1.27.3",revision="a6fde3f",version="1.15.0"}`。Corefile は resourceVersion `1239255997` のまま |
| autoscaler、approver、metrics-server | 変わらない（generation、Pod の UID・restart） |
| Running / Completed 以外の Pod | 0（Pod 165 個: Running 141、Succeeded 24） |
| restartCount | §3 |
| storage version | `prefixes: 70, keys: 2871, OLD: 0, CRDs with more than one stored version: 0` |
| ServiceCIDR、IPAddress、FlowSchema | `kubernetes`（`10.254.0.0/24,fd20:afc2:7c09::/108`）、IPAddress 68 で ClusterIP の数と同じ、FlowSchema 11（`control-plane.md` §5 の 14。11:1xZ） |
| cgroup | 8 台 `cgroup2fs` |
| `containerRuntimeEndpoint` | 8 台とも `kubelet.service` にフラグが無く `config.yaml` にある。`crictl version` は containerd v2.3.6。新しい kubelet の起動の `deprecated` の行は 0 |
| kube-proxy | 8 つのログに `Setting nf_conntrack_max` は 0（ベースラインは 8。v1.37.2 の #142198）。8 台の `nf_conntrack_max` はベースラインと同じ（131072 5 台、262144 2 台、524288 1 台） |
| Longhorn | 17 本とも attached healthy（chirico 10、duchamp 6、oeilvert 1）、エンジン v1.13.0。`natsumi-penelope` は別タスクがアタッチした（§4） |
| iSCSI | §3.2 |
| cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。cnidaria の `"level":"error"` 56 行は、どれも各台の `install kubelet` の分（その台の `systemd-networkd` の再起動の間の `Reconciler error routes: install …`。runbook §8.4）。✋ `netcheck.sh`（11:42Z）**PASS 168 / 168, pods 8/8**（pablo の後の 11:30Z にも 168/168） |
| NetworkPolicy | ✋ `npcheck.sh`（11:42〜11:45Z）: `up` の後の `nft` が 8 台とも 9、`run` が **`OK 56, not OK 0`**、`down` の後が 8 台とも 0。pablo の後（11:30〜11:33Z）も同じ。`k8u-npcheck`・`cnidaria-netcheck` は NotFound |
| MetalLB | `check-apps.sh` で gated v4・v6 が 404（応答あり）、VIP の `/version` 200、duplicates 0。`::131`〜`::135` の 3222 は SSH のバナーを返す。pool は変わらない |
| NFS、registry | oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で中身が読める。braque は 2049 を listen。`registry.fraction.jp/v2/` は 401（応答あり） |
| duchamp | `no_turbo` 1、最高温度 57℃ |
| metrics | `kubectl top nodes` が 8 台とも応答。Prometheus の `up == 0` は 0 個、`count(etcd_server_has_leader)` 3、`up{job="coredns"}` が新しい 2 つの Pod とも 1 |
| CSR | 作業の間に出た CSR は無い |

## 3. Pod の再起動と iSCSI

### 3.1 restartCount（ベースラインからの比べ）

- ベースラインの Pod（164 個）のうち、変わったのは `install kubernetes` で作り直された 17 個（apiserver 3、KCM 2、scheduler 2、kube-proxy 8、CoreDNS 2。新しい名前・UID で restartCount 0）だけ。ほかに増えたのは別タスクの `natsumi/natsumi-penelope-0`（§4）
- **`install kubelet` で、8 台ともコンテナの再起動は 0**（各台の前と後の全 Pod の名前・UID・restartCount が同じ）。**etcd の static Pod も作り直されていない**（段 8 と違うところ。`etcd-server.yaml` が変わらないため。runbook §4.1 のとおり）
- CoreDNS の `loop` による再起動は無かった

### 3.2 iscsid の PID とセッション

| ノード | 前（11:05Z） | 後（11:39Z） | 見分け |
|---|---|---|---|
| 192.168.1.111 | 522641 | 522641 | 変わらない |
| 192.168.1.112 | 0（`iscsid.socket` だけ） | **598791**（11:24:05Z） | `install-pkgs.sh` の `systemctl start` による起動（`Starting` → `Started` だけで `Stopping` は無い）。runbook §2.7 の想定どおり |
| 192.168.1.113 | 290821 | 290821 | 変わらない |
| braque | 271131 | 271131 | 変わらない |
| chirico | 3144486（セッション 9） | 3144486（セッション 10） | 変わらない。増えた 1 つ（sid 36）は別タスクの `natsumi-penelope`（11:10:07Z、`install kubernetes` の前） |
| duchamp | 3589（セッション 6） | 3589（セッション 6） | 変わらない |
| oeilvert | 912599（セッション 1） | 912599（セッション 1） | 変わらない |
| pablo | 4114921 | 4114921 | 変わらない |

- 8 台の `node-state.sh` の差はベースラインから `bin` の行（と .112 の iscsid、chirico の `natsumi-penelope` のセッションとエンジン）だけ。portal はどれもそのノードの今の instance-manager の IP。古いセッションは 0。`older-than-iscsid` は duchamp の 1 本のまま

### 3.3 監視（runbook §2.3）の FAIL

11:10:42Z 〜 11:46:20Z（`probe.log` 1682 行、`dns2-192.168.1.131.log` 1680 サンプル、`dns2-192.168.1.82.log` 1797 サンプル、`etcd-probe` は .111・.112 から 1046・1045 行）。

- **DNS**: braque・oeilvert とも **FAIL 0**（CoreDNS の入れ替わり、kube-proxy の 8 台の入れ替わり、各台の `systemd-networkd` の再起動の間を含む）
- **CoreDNS の ready**: 0 になった行は無い。1 になったのは 11:14:56Z の 1 行だけ（新しい `-4kjb5` が Ready になる前）
- **VIP**: 000 は 11:13:21Z の 1 サンプル（`install kubernetes` の .112 の apiserver の入れ替え。段 8 の本番も 1 回）。`dns-replicas-watch.sh` の kubectl も 11:14:03Z に 1 回 `connection refused`（.111 の入れ替え）
- 各 apiserver の `/readyz` の 000・403・500 は、その台の apiserver の入れ替えの間だけ（.113 11:12:30〜11:13:06Z、.112 11:13:21〜11:13:59Z、.111 11:14:04〜11:14:41Z）
- **LB**（gated v4・v6）: FAIL 0
- **etcd**: unhealthy 0

## 4. 別タスクの natsumi-penelope

`install kubernetes` の直前から、別タスク natsumi-dev の coordinator が名前空間 `natsumi` に apply していた（StatefulSet `natsumi-penelope` の replicas 0 → 1）。11:10:05Z に Pod が chirico に作られ、11:13:23Z と 11:17:50Z に（readiness の失敗の後）STS が Pod を作り直した。どちらも chirico の `install kubelet`（11:38Z）の前で、この作業の操作によるものではない。coordinator の判断で、11:16Z の姿を新しいベースラインにした（詳しくは `control-plane.md` §6）。chirico の `install kubelet` の前と後で、`natsumi-penelope-0`（UID `a7c706df`）は再起動していない。

## 5. 片付けと、残したこと

- 一時的な名前空間 `cnidaria-netcheck`・`k8u-npcheck` は消した（NotFound）
- `infra-admin` のトークン: 11:30:20Z に 1 時間の期限で発行し、`/tmp/k8u-0376-admin-token`（モード 600）に置いた。NetworkPolicy の確認の 2 回に使い、11:45:10Z にファイルを消した（サーバーの側では 12:30Z ごろに期限が切れる）
- 監視: `probe.sh`・`dns-watch2.sh` 2 つ・`dns-replicas-watch.sh` は 11:46:20Z に `watch.stop` で止めた。`cp-watch.sh` は 11:46Z にジョブを止めた（作業端末の中だけのループ）。`etcd-probe.sh` の 2 つは、runbook §4.4 では .111 の後に止めるが、読み取りだけなので 1 時間で自分で終わるのに任せた（12:10:41Z が最後の行で、11:10:43Z からの 1749 行ずつに unhealthy は 0。12:10:48Z に .111・.112 で `pgrep -af 'etcdctl.*endpoint health'` が空で、ノードの側のループは残っていない）
- etcd のバックアップは worktree `0-37-6-prod` の `./backup/` にある（git には入れていない）。worktree を片付ける前に、メインの checkout の `backup/` へ写す（coordinator）

  | ファイル | 中身 | バイト | sha256 |
  |---|---|---|---|
  | `etcd-2026-10-30T11:10:29+00:00.db` | 作業の前（v1.37.1 の control-plane、CoreDNS v1.14.7） | 74,612,768 | `e1cdf191638d7bb80ef4e67f66d034e32dafe4b4640abe590bf89b8bd98c8360` |
  | `etcd-2026-10-30T11:21:08+00:00.db` | v1.37.2 の control-plane、CoreDNS v1.15.0、kubelet は v1.37.1 | 74,612,768 | `9dda69e146e22d9e2f9162f5f2d7f717b7bbbd4bc624a17d91bd9633190c9b6d` |

- ノードには、事前 pull のイメージと `/opt/bin` の `kubelet-v1.37.1`・`kubectl-v1.37.1`（戻しの材料）のほかは何も残していない
- runbook の直し（この PR）: §1.7（`node-step.sh` の「その台の Pod」は worker では空になる。cnidaria の手順書の `RUNBOOK_ENV` に `FRACTION_CHECKOUT` と `CNIDARIA_NFT_IMAGE` の上書きが要る）、§6（CoreDNS の scrape の job の名前は `coredns`）
- 申し送り（この作業の範囲の外）:
  - runbook §10 のとおり（1 日ほど CoreDNS の restartCount・`[ERROR]`・SERVFAIL を見る、計画 §8 と TASK の CoreDNS の記述を v1.15.0 に直す、ノードの resolv.conf の kube-dns、CoreDNS の `podAntiAffinity` と `initialDelaySeconds`、古い ReplicaSet とイメージの片付け、rasp02 の 10-24 の shutdown の理由、containerd の config v4）
  - タスクディレクトリの `notes/runbook-0-37-6/scripts/node-step.sh` は、worker の「その台の Pod」を引くのに IP ではなくノードの名前を使うよう直すとよい
