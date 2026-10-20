# 段 5 のベースライン

本番 `fraction` の段 5（K8s 1.33.13 → 1.34.12、etcd 3.5.34 → 3.6.15、porkadot 0.34.1）に入る前に取った、クラスタ全体の読み取りの結果、etcd のバックアップ、v2store の確認、storage version の確認の記録。手順は `../../runbook-stage-5.md`（以下 runbook）。
時刻は UTC。1 台ごとの確認は、この記録と比べる。読み取りの出力はタスクディレクトリの `notes/stage-5/baseline/` に置いた（リポジトリには入れない）。全 Pod の名前・UID・restartCount の控えは同じ場所の `pods.tsv`、8 台の `tools/node-state.sh` の出力は `node-<ノード>-before.txt`、etcd の詳細は `etcd-*-base.txt`。

## 1. 前提（runbook §1）

| 項目 | 結果 |
|---|---|
| 段 4 と、その後の 2 つの作業（§1.1） | `results/stage-4/summary.md` に完了の確認がある。cnidaria の入れ替え（`docs/cni/cnidaria-no-plugin-copy.md`）と Longhorn の ownerReference・orphan（`docs/longhorn/results/2026-10-20.md`）は master にある。8 台とも v1.33.13、`containerd://2.3.6`、etcd 3.5.34 |
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor` |
| porkadot（§1.4） | `porkadot-dev/porkadot` が `v0.34.1`（`060a687`）、`lib/porkadot/version.rb` が 0.34.1。Ruby 4.0.7。`porkadot help` が動く。cwd は段 5 の worktree（`stage-5-k8s-1-34` のブランチ。base は PR #40 をマージした master の `deef235`）。`git status --short assets porkadot.yaml` は空 |
| SSH（§1.3、§1.4。08:43Z） | サンドボックスの中（`ssh-add -l` は `Error connecting to agent: Operation not permitted`）から、porkadot 0.34.1 を `require` した SSHKit で 8 台に `hostname` を流し、8 台とも `rasp01`〜`rasp03`、`pablo`、`duchamp`、`braque`、`chirico`、`oeilvert` を返した |
| 入れる版（§1.7。08:43Z） | `stable-1.34.txt` は v1.34.12（`stable.txt` は v1.37.1）。etcd の 3.6 の最新は v3.6.15 |
| 作業端末の kubectl | v1.33.13 |
| 監視（§2.3） | 08:45:03Z に作業端末で VIP と LB の監視を開始。ログはタスクディレクトリの `notes/stage-5/stage-5-probe.log`。etcd の health の監視は §4 の前に始める |

## 2. クラスタ全体のベースライン（runbook §2.2。2026-10-20 08:45Z〜08:46Z）

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node、版 | 8 台 Ready。全台 v1.33.13、`containerd://2.3.6`。Server Version v1.33.13 |
| 2 | `tools/node-state.sh` の `bin` と `cni` | 8 台とも `kubelet-v1.33.13`、`kubectl-v1.33.13`、`crictl-v1.33.0`、`etcdctl-3.5.34`、`etcdutl:none`。CNI の印と bridge・host-local・portmap・loopback が 8 台とも `v1.9.1` |
| 3 | `/etc/etcd/pki` | 3 台とも `ca.crt`・`etcd.crt`・`etcd.key` が `600 root:root` |
| 4 | etcd、VIP | 3/3 healthy、3 台とも 3.5.34、DB 55 MB（in use 約 16 MB）。リーダーは **192.168.1.113（`57ec6f12ac7b683e`）**。raft term 23120、raft index 1403104776〜779 でそろう。`header.revision` は **1,237,780,103**（§7.4 の restore の目安）。ID は .111 `21ab2aeb56731588`、.112 `fbb0c648cf5852a5`。`member list` は 3 つとも `started`。VIP の `/readyz` は `ok`、`/version` は v1.33.13 |
| 4 | etcd の `/version` | 3 台とも `{"etcdserver":"3.5.34","etcdcluster":"3.5.0"}` |
| 4 | 動いている etcd のフラグ | 3 台とも `--experimental-initial-corrupt-check=true`、`--experimental-watch-progress-notify-interval=5s`、`--snapshot-count=10000` があり、`--enable-v2` は無い。プロセスの環境に `ETCD_*` は無い |
| 4 | etcd の Pod のログの warn の種類 | 3 台とも `check file permission`、`Running http and grpc server on single port`、`simple token is not cryptographically signed`、`found invalid file under data directory`。.112 は `ignored file in WAL directory`（§5 の `.wal.broken`）。ほかに起動の時の `lost TCP streaming connection`・`peer became inactive`・`closed TCP streaming connection`（.112、.113）、`apply request took too long`（.111 2、.112 1）、`request stats`（.111 1）。error は無い |
| 5 | Running / Completed 以外の Pod | 0 個 |
| 5 | 全 Pod の名前・UID・restartCount | `notes/stage-5/baseline/pods.tsv` に控えた（150 個。§6 で「増えていない」ことを見る元） |
| 6 | Longhorn のボリューム | attached healthy 16、detached unknown 1（`homegallery/cg-data`。以前から）。degraded は 0 |
| 6 | Longhorn の replica | chirico 11（running 10、stopped 1）、duchamp 9（running 8、stopped 1）、oeilvert 11（running 10、stopped 1）、pablo 2（running 2） |
| 6 | instance-manager、engine image、node | instance-manager 4 つとも running: pablo `-17a539db…`（10.244.4.131）、chirico `-4128231c…`（10.244.8.216）、duchamp `-4df00b8c…`（10.244.5.112）、oeilvert `-d5905a9e…`（10.244.7.116）。engine image `longhorn-engine:v1.11.2` が deployed。Longhorn の node 4 つとも Ready、schedulable |
| 7 | cnidaria | `verify-nodes.sh` は 8 台とも exit 0。cnidaria の Pod のログの error は chirico の 1 つ（05:07:13Z の `routes` の `list addresses: results may be incomplete or inconsistent`。cnidaria の入れ替えの後、段 5 の前のもの）だけで、`no route` は 8 台とも 0（cnidaria の入れ替えで Pod が新しくなった）。`check-apps.sh`: nodes 8/8、Running でない Pod 0、IP の重複 0、Longhorn 16 attached healthy・1 detached unknown、192.168.1.200 と v6 の LB は 404、VIP の `/version` は 200 |
| 7 | NetworkPolicy | 1 つも無い。確かめるのは §1.9 の一時的な名前空間で |
| 8 | MetalLB | LoadBalancer の Service 11 個がアドレスを持つ。gated の `192.168.1.200` と `[...:ace::200]` の 80 は 404（応答あり）。`::131`〜`::134` の 3222 は SSH のバナーを返す |
| 9 | NFS | oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で、中身が読める。braque は 2049 を listen している。`registry.fraction.jp/v2/` は 401（応答あり） |
| 10 | metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個 |
| 11、15 | controller-manager と scheduler | controller-manager は .111（`-9wqgd`）と .113（`-fw4lb`、リーダー）。scheduler は .112（`-8kt9t`、リーダー）と .113（`-l2qfv`）。runbook §1.1 のとおり |
| 12 | CSR | 無い |
| 12 | kubelet の serving の証明書 | 8 台とも段 4 と同じ（subject `O = system:nodes, CN = system:node:<ノード名>`、期限も同じ） |
| 13 | kube-system の Deployment と DaemonSet、approver | 下の表。approver は `kubelet-serving-cert-approver-7d5f768656-hls26`（oeilvert） |
| 14 | Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit` `5`、`replica-auto-balance` `disabled`、`node-drain-policy` `block-if-contains-last-replica`、`default-data-locality` `best-effort`、`replica-replenishment-wait-interval` `6000`、`current-longhorn-version` v1.11.2。どれも APPLIED が true |
| 16 | MetalLB の告知ノード | 下の表 |
| 17 | leader election を使う controller の再起動回数 | `gated-system/gated` の 2 つ（chirico、oeilvert）、`longhorn-system` の CSI sidecar 12 個とも 0 |
| 18 | Longhorn のボリュームのアタッチ先と iSCSI | 下の表 |
| 19 | FlowSchema の generation | `system-leader-election` が 8、ほかの 12 個は 1（`endpoint-controller`・`workload-leader-election` も 1） |
| 20 | storage version | `prefixes: 65, keys: 2200, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は 1.33 の 2 行（`/registry/ipaddresses/`・`/registry/servicecidrs/` が `networking.k8s.io/v1beta1`）。IPAddress 74 と ServiceCIDR 1 が `networking.k8s.io/v1beta1` の `ok`。CRD は 47 個とも `ok`。出力はタスクディレクトリの `notes/stage-5/sv-20261020T0845Z/` |
| 21 | `apiserver_requested_deprecated_apis` | `endpoints`（3 台）、`metallb.io/v1beta1 addresspools`（.111、.112）、`componentstatuses`（.111）。`removed_release` はどれも空。runbook §1.1 と同じ |
| 22 | Longhorn の PVC を使う Running と Completed の Pod（runbook §8.12） | **無い**。Running と Succeeded が同じ PVC を使うのは `aphrael/aphrael-2` だけ（NFS の PV。Succeeded の 3 つは CronJob `aphrael/tumblr-like` のもので、duchamp にある） |
| 23 | CoreDNS の答え（v1.12.4。08:45Z） | 下の表。段 4 の完了の確認と同じ形 |
| 24 | Service の数 | 79 個。ClusterIP を持つもの 71 個（うち dual-stack 3 個）、ClusterIP の数 74。IPAddress 74。ServiceCIDR は `kubernetes`（`10.254.0.0/24,fd20:afc2:7c09::/108`）の 1 つ |
| 25 | Prometheus のスクレイプ | `count by (job) (up)` の `apiserver` 3、`kube-etcd` 3、`count(etcd_server_has_leader)` 3 |

kube-system の Deployment と DaemonSet（§2.2 の 13）:

| KIND | NAME | GEN | IMAGE |
|---|---|---|---|
| Deployment | coredns | 11 | `coredns/coredns:v1.12.4` |
| Deployment | kube-controller-manager | 26 | `kube-controller-manager:v1.33.13` |
| Deployment | kube-dns-autoscaler | 4 | `cluster-proportional-autoscaler-amd64:1.7.1` |
| Deployment | kube-scheduler | 25 | `kube-scheduler:v1.33.13` |
| Deployment | metrics-server | 1 | `metrics-server/metrics-server:v0.7.2` |
| DaemonSet | cnidaria | 3 | `ghcr.io/yuanying/cnidaria-cni:v0.1.1` |
| DaemonSet | kube-apiserver | 27 | `kube-apiserver:v1.33.13` |
| DaemonSet | kube-proxy | 23 | `kube-proxy:v1.33.13` |

MetalLB の告知ノード（speaker のログの IP ごとの最後の `serviceAnnounced`）。runbook §2.8 と同じ:

| Service | アドレス | 告知ノード |
|---|---|---|
| `kube-system/porkadot-kubernetes`（API の VIP） | 192.168.1.101 | **pablo** |
| `gated-system/gated-v4` | 192.168.1.200 | chirico |
| `gated-system/gated-v6` | `::200` | oeilvert |
| `fs/h2-sshd` | `::131` | 192.168.1.112 |
| `natsumi/natsumi-sshd` | `::132` | 192.168.1.111 |
| `natsumi/natsumi-sshd-myao` | `::133` | duchamp |
| `natsumi/natsumi-sshd-aki` | `::134` | 192.168.1.112 |

各ノードの iscsid、iSCSI のセッション、エンジン（`tools/node-state.sh`）。runbook §2.7 と同じ:

| ノード | iscsid（MainPID、起動） | セッション（portal） | `older-than-iscsid` | アタッチされたボリューム | `initiatorname.iscsi` |
|---|---|---|---|---|---|
| 192.168.1.111 | 90734、10-19 07:31:09Z | 0 | 0 | なし | assets と同じ（md5） |
| 192.168.1.112 | 89578、10-19 07:27:57Z | 0 | 0 | なし | 同じ |
| 192.168.1.113 | 95423、10-19 07:24:21Z | 0 | 0 | なし | 同じ |
| braque | 85966、10-19 08:06:03Z | 0 | 0 | なし | 同じ |
| pablo | 1194943、10-19 07:39:11Z | 1（10.244.4.131 = 今の instance-manager） | 0 | `fs/sites` | 同じ |
| duchamp | 663628、10-19 23:33:45Z | 0 | 0 | なし | 同じ |
| chirico | 4447、10-19 09:17:30Z | 10（すべて 10.244.8.216 = 今の instance-manager） | **1**（pvc-625c8825、09:17:28Z。runbook §2.7 の注のもの） | 10 | 同じ |
| oeilvert | 6334、10-19 09:04:34Z | 5（すべて 10.244.7.116 = 今の instance-manager） | 0 | 5 | 同じ |

- 古いセッションは無い。chirico の `older-than-iscsid` の 1 つは段 3 の前から同じもので、増えていない
- アタッチ先: chirico 10（`tumblr-data`、`ero-data`、`fs/data`、`fs/h2`、`natsumi-myao`、`prometheus-…-0`、`fraction-agents` の 4 つ）、oeilvert 5（`natsumi`、`natsumi-aki`、`prometheus-…-1`、`fraction-agents` の 2 つ）、pablo 1（`fs/sites`）。runbook §5.1 の順（duchamp → pablo → braque → oeilvert → chirico）のまま進める

CoreDNS の答え（§2.2 の 23。作業端末から kube-dns の 10.254.0.10 へ。v1.12.4）:

| 問い合わせ | 答え |
|---|---|
| `kubernetes.default.svc.cluster.local`、`kubernetes.default.svc.fraction.cluster` | `10.254.0.1` |
| `www.google.com` A | 外のアドレス（8 つ） |
| PTR `10.254.0.1` | `kubernetes.default.svc.cluster.local.` |
| PTR `fd20:afc2:7c09::521` | `h2.fs.svc.cluster.local.` |
| PTR の、kube-dns の Endpoint の Pod の IP（`10.244.5.129`、`10.244.8.16`） | `<IP>.kube-dns.kube-system.svc.cluster.local.` と `<IP>.kube-prometheus-coredns.kube-system.svc.cluster.local.` |
| PTR の、`fs/h2` の Endpoint の Pod の IP（`10.244.8.246`、`fde7:4ad6:425d:3::4b1f`） | `<IP>.h2.fs.svc.cluster.local.`（v6 は `h2-sshd` も） |

ほかに読んだもの:

- CronJob は 8 個（`notes/stage-5/baseline/cronjobs.txt`）。runbook §5.4 のとおり
- Warning のイベントは無い

## 3. etcd のバックアップ（runbook §2.4。段の前）

| 項目 | 値 |
|---|---|
| コマンド | `porkadot etcd backup --config ./porkadot.yaml`（porkadot 0.34.1、etcdctl 3.5.34。サンドボックスの中で 09:08:38Z〜09:08:41Z、rc 0、6 つとも `successful`） |
| 取ったメンバー | 192.168.1.111（写したあと、ノードのものを消した） |
| ファイル | `etcd-2026-10-20T09:08:38+00:00.db`、モード 0600、55,107,616 バイト |
| sha256 | `762d90b31c3a02c40bab5812ac24cf34b9d6e06abfb74ce54c23b4bc88a4e675` |
| 置き場所 | 段 5 の worktree の `./backup/`（`.gitignore` で除外。git には入れていない）。worktree を片付ける前に、メインの checkout の `backup/` へ移す（coordinator） |
| 前のバックアップとの比較 | メインの checkout の `backup/` の `etcd-2026-10-20T05:04:14+00:00.db`（55,107,616）と同じサイズ |

このバックアップは 1.33 の control-plane、etcd 3.5 の状態で、runbook §7.4 の restore の第一の候補。

## 4. storage version（runbook §2.5）

`install kubernetes` の前の確認（§2.5 の 1）は §2 の 20 のとおり `OLD: 0`、`CRDs with more than one stored version: 0`、`overrides.tsv` は 1.33 の 2 行で、止める条件に当たらない。`install kubernetes` の後に IPAddress（74 個）を書き直す（§3.4）。

## 5. v2store の確認（runbook §2.9）

09:08:59Z〜09:09:10Z。3.5.34 の arm64 の etcdutl（`etcd-v3.5.34-linux-arm64.tar.gz`、`SHA256SUMS` と一致）を各台の `/tmp` に置き、`/var/lib/etcd/member` を `/tmp` の `mktemp -d` に `cp -a` した写しに `check v2store --data-dir` を流し、写しと etcdutl を消した（3 台とも `/tmp/k8u-*` が残っていないことを確かめた）。出力はタスクディレクトリの `notes/stage-5/v2store-check.txt`。

| メンバー | 写しの大きさ | 結果 |
|---|---|---|
| 192.168.1.111 | 426 MB | `No custom content found in both v2store and WAL records.`（rc 0） |
| 192.168.1.112 | 484 MB | `No custom content found in both v2store and WAL records.`（rc 0）。その前に `ignored file in WAL directory`（`0000000000004c11-000000004febac26.wal.broken`）の warn が 2 行 |
| 192.168.1.113 | 420 MB | `No custom content found in both v2store and WAL records.`（rc 0） |

**3 台とも合格**（runbook §2.9 の合格の形）。

- .112 の `member/wal/` には `0000000000004c11-000000004febac26.wal.broken`（64 MB、`644 root:root`、2026-05-11 13:18Z）がある。etcd が壊れた WAL の末尾を直したときに前のファイルを残すもので、今回の作業の前からある（動いている 3.5.34 の etcd も起動のときに同じ `ignored file in WAL directory` を出している。§2 の 4）。etcd も `check v2store` も `.wal` でないファイルとして読まない。.111 と .113 には無い
- ノードの `/` はどれも 105 GB 空いていた
