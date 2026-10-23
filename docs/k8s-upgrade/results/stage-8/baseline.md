# 段 8 のベースライン

本番 `fraction` の段 8（K8s 1.36.5 → 1.37.1、etcd 3.6.15 → 3.7.3、porkadot 0.37.0）に入る前に取った、クラスタ全体の読み取りの結果、etcd のバックアップ、storage version、cgroup、resolv.conf と CoreDNS、unattended-upgrades と iscsid、kubelet の設定の確認の記録。手順は `../../runbook-stage-8.md`（以下 runbook）。
時刻は UTC。1 台ごとの確認は、この記録と比べる。読み取りの出力はタスクディレクトリの `notes/stage-8/baseline/` に置いた（リポジトリには入れない）。全 Pod の名前・UID・restartCount の控えは同じ場所の `pods.tsv`、8 台の `tools/node-state.sh` の出力は `node-<ノード>-before.txt`、etcd の詳細は `etcd*.txt`、8 台の OS の読み取り（cgroup、resolv.conf、unattended-upgrades、iscsid、kubelet の設定）は `notes/stage-8/node-os-1.txt`。

## 1. 前提（runbook §1）

| 項目 | 結果 |
|---|---|
| 段 7（§1.1） | `results/stage-7/summary.md` に完了の確認がある。8 台 v1.36.5、`containerd://2.3.6`、etcd 3/3 が 3.6.15（cluster version・storage とも 3.6.0）、Longhorn v1.13.0（engine image は `longhorn-engine:v1.13.0` だけが deployed、17 本ともエンジンが v1.13.0） |
| 段 7 の後に変わったこと（§1.1） | runbook §1.1 の表のとおりの姿（MetalLB の pool と v6 の LB は新しいプレフィックス、oeilvert の iscsid は動いていない、名前空間 `minio` は無い、CoreDNS の restartCount 7 と 4） |
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor` |
| porkadot（§1.4） | 独立の clone `worktrees/porkadot-v0-37-0` が `v0.37.0`、`lib/porkadot/version.rb` が 0.37.0、作業ツリーに変更が無い。`porkadot help` が動く。cwd は段 8 の worktree（`stage-8-k8s-1-37` のブランチ。base は PR #52 をマージした master の `ef8d556`）。`git status --short assets porkadot.yaml` は空。§7 の戻しに使う `worktrees/porkadot-v0-36-0` は `v0.36.0` で、作業ツリーに変更が無く、`porkadot help` が動く |
| SSH（§1.3、§1.4。22:08Z） | サンドボックスの中から、porkadot 0.37.0 を `require` した SSHKit と `ssh -n` の両方で 8 台に `hostname` を流し、8 台とも `rasp01`〜`rasp03`、`pablo`、`duchamp`、`braque`、`chirico`、`oeilvert` を返した（`notes/stage-8/ssh-check.txt`） |
| 入れる版（§1.7。22:17Z） | `stable-1.37.txt` も `stable.txt` も v1.37.1。etcd の 3.7 の最新は v3.7.3。kubelet v1.37.1（arm64、amd64）、`crictl-v1.37.0-linux-arm64.tar.gz`、`etcd-v3.7.3-linux-{arm64,amd64}.tar.gz` は 200（`notes/stage-8/versions.txt`） |
| 作業端末の kubectl | v1.36.5 |
| 監視（§2.3） | 22:17:02Z に、ハーネスのバックグラウンド実行で 3 つのジョブとして起動した（bg1: VIP と LB、bg2: etcd の health を .111 から、bg3: 同じく .112 から）。ジョブの中は前景のループ（`nohup`・`&` なし）。ログはタスクディレクトリの `notes/stage-8/stage-8-probe.log`、`stage-8-etcd-192.168.1.11{1,2}.log` |

## 2. クラスタ全体のベースライン（runbook §2.2。2026-10-23 22:09Z〜22:17Z）

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node、版 | 8 台 Ready。全台 v1.36.5、`containerd://2.3.6`。Server Version v1.36.5 |
| 2 | `tools/node-state.sh` の `bin` と `cni`（22:09Z） | 8 台とも `kubelet-v1.36.5`、`kubectl-v1.36.5`、`crictl-v1.36.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI の印と bridge・host-local・portmap・loopback が 8 台とも `v1.9.1` |
| 3 | `/etc/etcd/pki` | 3 台とも `ca.crt`・`etcd.crt`・`etcd.key` が `600 root:root` |
| 4 | etcd、VIP | 3/3 healthy、3 台とも 3.6.15、STORAGE VERSION 3.6.0、DB 55 MB（in use 16 MB）。リーダーは **192.168.1.113（`57ec6f12ac7b683e`）**。raft term 23125、raft index 1404898374 でそろう。`header.revision` は **1,239,252,954**（§7.4 の restore の目安）。ID は .111 `21ab2aeb56731588`、.112 `fbb0c648cf5852a5`。`member list` は 3 つとも `started`。VIP の `/readyz` は `ok`、`/version` は v1.36.5 |
| 4 | etcd の `/version` | 3 台とも `{"etcdserver":"3.6.15","etcdcluster":"3.6.0","storage":"3.6.0"}` |
| 4 | 動いている etcd のフラグ | 3 台とも `--feature-gates=InitialCorruptCheck=true`、`--watch-progress-notify-interval=5s`、`--snapshot-count=10000` があり、`--experimental-` で始まるものは無い。プロセスの環境に `ETCD_*` は無い |
| 4 | etcd の Pod のログの warn の種類 | 3 台とも `check file permission`、`Running http and grpc server on single port`、`simple token is not cryptographically signed`、`found invalid file under data directory`、`apply request took too long`（.111 12、.112 23、.113 7）、`request stats`（3）。.112 は段 7 の起き直しのときの `failed to publish local member to cluster through raft`（103）など、.113 は `lost TCP streaming connection`（6）・`peer became inactive`（2）。.111 に `rejected connection on client endpoint` が 1 行（段 7 のベースラインに無かったもの。1 回だけ）。error は無い。etcd の Pod は 3 つとも restartCount 1（段 7 の `bind: address already in use`） |
| 5 | Running / Completed 以外の Pod | 0 個 |
| 5 | 全 Pod の名前・UID・restartCount | `notes/stage-8/baseline/pods.tsv` に控えた（169 個。Running 145、Completed 24。§6 で「増えていない」ことを見る元）。CoreDNS の 2 つは restartCount が `-469lz` 7、`-shdgn` 4（10-23 02:1xZ のもの。runbook §2.10） |
| 6 | Longhorn のボリューム | attached healthy 16、detached unknown 1（`homegallery/cg-data`。以前から）。degraded は 0。17 本ともエンジンが `longhorn-engine:v1.13.0` |
| 6 | Longhorn の replica | chirico 11（running 10、stopped 1）、duchamp 12（running 12）、oeilvert 8（running 7、stopped 1）、pablo 1（running 1） |
| 6 | instance-manager、engine image、node | instance-manager 5 つとも running（pablo 10.244.4.197、chirico 10.244.8.216（v1.11.2）・10.244.8.60、duchamp 10.244.5.186、oeilvert 10.244.7.224。runbook §1.10 のとおり）。engine image は `longhorn-engine:v1.13.0`（`ei-2f3240cb`）だけが deployed。Longhorn の node 4 つとも Ready、schedulable |
| 7 | cnidaria | `verify-nodes.sh`（nft を流すイメージを `v0.1.1` にした写し。runbook §1.8）は 64 PASS、FAIL 0。cnidaria の Pod のログの error / `no route` は .111 31/79、.112 30/78、.113 32/80、braque 27/76、chirico 23/73、duchamp 28/77、oeilvert 0/0、pablo 20/68（前のもの。各台の前と後の差で見る）。`check-apps.sh`（写しの `CHECK_URLS` を新しいプレフィックスにした）: nodes 8/8、Running でない Pod 0、IP の重複 0、Longhorn 16 attached healthy・1 detached unknown、192.168.1.200 と `[…ace::200]` は 404、VIP の `/version` は 200 |
| 7 | NetworkPolicy | `longhorn-system` の 6 つ（Longhorn v1.13.0 のもの）だけ |
| 8 | MetalLB | gated の `192.168.1.200` と `[2405:6580:6740:ac01:ace::200]` の 80 は 404（応答あり）。`::131`〜`::134` の 3222 は SSH のバナーを返す |
| 9 | NFS | oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で、中身が読める。braque は 2049 を listen している。`registry.fraction.jp/v2/` は 401（応答あり） |
| 10 | metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個 |
| 11、15 | controller-manager と scheduler | controller-manager は .111（`-h9fg6`、リーダー）と .112（`-nlvtq`）。scheduler は .111（`-5vqks`、リーダー）と .112（`-ntsf7`）。段 7 の完了の確認と同じ |
| 12 | CSR | 無い |
| 12 | kubelet の serving の証明書 | 8 台とも subject `O = system:nodes, CN = system:node:<ノード名>`。期限は段 7 と同じ（CP 3 台が 2027-10-16、braque 2027-08-18、chirico 2027-06-23、duchamp 2027-09-06、oeilvert 2027-03-20、pablo 2027-08-08） |
| 13 | kube-system の Deployment と DaemonSet、approver | 下の表。approver は `kubelet-serving-cert-approver`（1/1、`0.12.1`） |
| 14 | Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit` `5`、`replica-auto-balance` `disabled`、`node-drain-policy` `block-if-contains-last-replica`、`default-data-locality` `best-effort`、`replica-replenishment-wait-interval` `6000`、`current-longhorn-version` v1.13.0。どれも APPLIED が true |
| 16 | MetalLB の告知ノード | 下の表 |
| 17 | leader election を使う controller の再起動回数 | `gated-system/gated` の 2 つと `longhorn-system` の CSI sidecar 12 個のうち、`gated-…-g7rjz`（chirico）、`csi-attacher-…-ljnvb`（duchamp）、`csi-provisioner-…-zbz7c`（chirico）、`csi-resizer-…-w7sb2`（duchamp）、`csi-snapshotter-…-2mm6v`（chirico）が 1（段 7 の後のもの）、ほかの 9 個は 0 |
| 18 | Longhorn のボリュームのアタッチ先と iSCSI | 下の表 |
| 20 | storage version（22:14Z〜22:16Z） | `prefixes: 66, keys: 2280, OLD: 0, CRDs with more than one stored version: 0`。`overrides.tsv` は 1.36 の 2 行（`/registry/mutatingadmissionpolicies/`・`/registry/mutatingadmissionpolicybindings/` の `admissionregistration.k8s.io/v1beta1`）。1.37 の override の 4 種（`clustertrustbundles`、`podcertificaterequests`、`storageversionmigrations`、`devicetaintrules`）と `workloads`・`podgroups` のキーは 0。`kubectl get clustertrustbundles` は `the server doesn't have a resource type`（1.36 では beta で既定 off）。出力はタスクディレクトリの `notes/stage-8/sv-baseline/`。runbook §2.5 の 1 のとおりで、止める条件に当たらない |
| 21 | `apiserver_requested_deprecated_apis` | `endpoints`（v1）と `metallb.io/v1beta1 addresspools`。`removed_release` はどれも空 |
| 22 | Longhorn の PVC を使う Running と Completed の Pod（runbook §8.12） | **当たるものがある**: duchamp に natsumi の 3 つの CronJob の Succeeded の Pod が 9 つ（`natsumi-backup-*`・`natsumi-backup-aki-*`・`natsumi-backup-myao-*` が 3 つずつ。PVC `natsumi`・`natsumi-aki`・`natsumi-myao` で、Running の `natsumi-0`・`natsumi-aki-0`・`natsumi-myao-0` と同じ）、chirico に `deep-researcher-backup-*` の Succeeded の Pod が 3 つ（PVC `data-deep-researcher-0`、Running の `deep-researcher-0` と同じ）。duchamp と chirico の `install kubelet` の前に消す（段の開始の承認の範囲の ✋。消す前に名前を知らせる）。`aphrael/tumblr-like-*` の 3 つ（oeilvert）は NFS の PV（`aphrael-2`）で当たらない。natsumi と deep-researcher のバックアップの次の実行は 10-24 20:30Z・21:00Z で、段 8 の作業の間には走らない見込み |
| 23 | CoreDNS の答え（v1.14.7、`cache 30`。22:16Z） | `tools/dns-check.sh` の出力は `notes/stage-8/baseline/dns-check.txt`。Service（10.254.0.10）と 2 つの Pod（10.244.5.210 duchamp、10.244.8.74 chirico）で同じ答え。2 つの Pod のログは `CoreDNS-1.14.7` と `Running configuration SHA512 = ba67fe90…` だけで、`[ERROR]`・`[WARNING]`・`loop` は無い。**TTL の確かめ**（runbook §3.3 の 13 の形。pablo から各 Pod に 3 秒おいて 2 回）: 2 回目の TTL は `kubernetes.default.svc.cluster.local` 23 と 13、`kubernetes.default.svc.fraction.cluster` 20 と 10、`github.com` 17 と 8（どれも 30 より小さい。cache から。`dns-ttl.txt`）。Corefile は `cache 30`（`Corefile.txt`） |
| 24 | Service の数 | 77 個。ClusterIP を持つもの 69 個、ClusterIP の数 72。IPAddress 72。ServiceCIDR は `kubernetes`（`10.254.0.0/24,fd20:afc2:7c09::/108`）の 1 つ。`ClusterIPNotAllocated` の event は無い |
| 25 | Prometheus のスクレイプ | `count by (job) (up)` の `apiserver` 3、`kube-etcd` 3、`coredns` 2 など（段 7 と同じ 14 の job）。`count(etcd_server_has_leader)` 3 |
| 26 | cgroup（runbook §2.9） | §3 |
| 27 | resolv.conf（runbook §2.10） | §4 |
| 28 | unattended-upgrades（runbook §2.11） | §5 |
| 29 | FlowSchema | 11 個。`system-leader-election` が generation 8、ほかの 10 個は 1 |
| 30 | kubelet の設定 | §6 |
| 31 | MetalLB の pool | `first-pool` の `addresses` は `192.168.1.101/32`、`192.168.1.190-192.168.1.254`、`2405:6580:6740:ac01:ace::/96`。render 済みの `assets/kubernetes/manifests/addons/metallb/metallb.config.yaml` と同じ |
| 32 | apiserver の grpc の warning | 直近 10 分の `operation was canceled` は `kube-apiserver-dnkpz`（.113）39、`-pvvmc`（.111）35、`-vtv8d`（.112）40（runbook §8.19 のとおり 1 分に約 4 行） |

kube-system の Deployment と DaemonSet（§2.2 の 13）:

| KIND | NAME | GEN | IMAGE |
|---|---|---|---|
| Deployment | coredns | 13 | `coredns/coredns:v1.14.7` |
| Deployment | kube-controller-manager | 29 | `kube-controller-manager:v1.36.5` |
| Deployment | kube-dns-autoscaler | 4 | `cluster-proportional-autoscaler-amd64:1.7.1` |
| Deployment | kube-scheduler | 28 | `kube-scheduler:v1.36.5` |
| Deployment | metrics-server | 1 | `metrics-server/metrics-server:v0.7.2` |
| DaemonSet | cnidaria | 3 | `ghcr.io/yuanying/cnidaria-cni:v0.1.1` |
| DaemonSet | kube-apiserver | 30 | `kube-apiserver:v1.36.5` |
| DaemonSet | kube-proxy | 26 | `kube-proxy:v1.36.5` |

MetalLB の告知ノード（speaker のログの直近 72 時間の、新しいプレフィックスと v4 のアドレスごとの最後の `serviceAnnounced`。runbook §2.8 の 14:2xZ の読み取りから、gated-v4・`::131`・`::132`・`::134` が移っている）:

| Service | アドレス | 告知ノード（最後の `serviceAnnounced`） |
|---|---|---|
| `kube-system/porkadot-kubernetes`（API の VIP） | 192.168.1.101 | **pablo**（14:39:55Z） |
| `gated-system/gated-v4` | 192.168.1.200 | chirico（20:01:19Z） |
| `gated-system/gated-v6` | `::200` | pablo（14:39:55Z） |
| `fs/h2-sshd` | `::131` | 192.168.1.113（21:52:45Z） |
| `natsumi/natsumi-sshd` | `::132` | duchamp（18:32:15Z） |
| `natsumi/natsumi-sshd-myao` | `::133` | oeilvert（06:29:30Z） |
| `natsumi/natsumi-sshd-aki` | `::134` | duchamp（18:32:15Z） |

各ノードの iscsid、iSCSI のセッション、エンジン（`tools/node-state.sh`、22:09Z）:

| ノード | iscsid（MainPID、起動） | セッション（portal） | `older-than-iscsid` | アタッチされたボリューム |
|---|---|---|---|---|
| 192.168.1.111 | 522641、10-21 21:51:36Z | 0 | — | なし |
| 192.168.1.112 | 414810、10-21 21:42:12Z | 0 | — | なし |
| 192.168.1.113 | 290821、10-20 21:30:04Z | 0 | — | なし |
| braque | 271131、10-21 06:23:32Z | 0 | — | なし |
| pablo | 4114921、10-21 06:40:42Z | 0 | — | なし |
| oeilvert | **0（動いていない。`iscsid.socket` は active・enabled。`ActiveState=inactive`）** | 0 | — | なし |
| duchamp | 2695716、10-21 06:08:00Z | 5（10.244.5.186 = 今の instance-manager） | 4 | 5 |
| chirico | 3144486、10-22 06:20:27Z | 11（8 つが 10.244.8.216、3 つが 10.244.8.60。どちらも今の instance-manager） | 9 | 11 |

- runbook §2.7 の表（14:23Z の読み取り）と同じ。古いセッション（今の instance-manager の IP でない portal）は無い
- oeilvert の `journalctl -u iscsid` の最後は 10-23 06:26:27Z の `Stopping`・`Stopped`（ノードの再起動の前）で、その後の起動は無い
- `initiatorname.iscsi` の md5 は 8 台とも段 7 と同じ
- アタッチ先: chirico 11（`homegallery/tumblr-data`・`ero-data`、`fs/data`・`fs/h2`、`monitoring/prometheus-…-1`、`fraction-agents` の 6 つ）、duchamp 5（`natsumi/natsumi`・`natsumi-aki`・`natsumi-myao`、`monitoring/prometheus-…-0`、`fs/sites`）、oeilvert 0、pablo 0
- worker の順は runbook §5.1 のまま **pablo → oeilvert → braque → duchamp → chirico**（アタッチの数 0、0、0、5、11）

ほかに読んだもの:

- Warning のイベントは、`carib2`・`shja2` の `movies` の probe の失敗（21:2xZ）と、oeilvert の Pod の `DNSConfigForming`（`Nameserver limits were exceeded`。oeilvert の resolv.conf に 192.168.0.1 が 2 つあるため。§4）。どちらも段 8 の作業の前のもので、各台の前と後で増えたものを見る
- CronJob は `notes/stage-8/baseline/cronjobs.txt`

## 3. cgroup（runbook §2.9。22:09Z〜22:11Z）

8 台とも `stat -fc %T /sys/fs/cgroup` が **`cgroup2fs`**、systemd は 255。止める条件（`tmpfs`）に当たらない。`/var/lib/kubelet` と `/var/lib/containerd` は 8 台とも ext4（runbook §2.12 の ZFS の件は当たらない見込み）。

## 4. resolv.conf と CoreDNS（runbook §2.10。22:09Z〜22:11Z）

8 台とも kubelet の `resolvConf` は `/run/systemd/resolve/resolv.conf` で、nameserver は 192.168.0.1、`2405:6580:6740:ac01::1`、10.254.0.10（.113 は 10.254.0.10 が先頭）。**oeilvert は 192.168.0.1 が 2 つ**（`192.168.0.1 192.168.0.1 2405:6580:6740:ac01::1 10.254.0.10`。10-23 の netplan の変更の後のものと見ている）で、kubelet が 3 つに切り詰めるので、oeilvert の `dnsPolicy: Default` の Pod は kube-dns の 10.254.0.10 を持たない（`DNSConfigForming` の warning）。CoreDNS は chirico と duchamp にあり、oeilvert の resolv.conf は使っていない。前からのもので、段 8 は止めない。

CoreDNS の 2 つの Pod は restartCount 7（`-469lz`、duchamp）と 4（`-shdgn`、chirico）、最後の再起動は 10-23 02:2xZ（runbook §2.10）。この後は Running のままで、ログに `loop`・`[ERROR]` は無い。

## 5. unattended-upgrades と iscsid（runbook §2.11。22:09Z〜22:11Z）

| ノード | `apt-daily-upgrade.service` | 最後の実行（`history.log`） | `-security` の upgradable | 次の `apt-daily-upgrade.timer`（UTC） |
|---|---|---|---|---|
| 192.168.1.111 | inactive | 10-23 21:25:29Z（今日の分。終わっている） | なし | 10-24 21:08:08Z |
| 192.168.1.112 | inactive | 10-22 21:48:38Z（今日の 21:36:27Z の実行は何も入れていない） | なし | 10-24 21:28:44Z |
| 192.168.1.113 | inactive | 10-23 21:23:37Z（今日の分。終わっている） | なし | 10-24 21:37:08Z |
| braque | inactive | 10-22 06:24:30Z | `zlib1g` | 10-24 06:13:19Z |
| chirico | inactive | 10-23 06:48:47Z | なし（`zlib1g` は 2.2 のまま。index が古い見込み） | 10-24 06:41:45Z |
| duchamp | inactive | 10-23 06:09:59Z | なし | 10-24 06:09:08Z |
| oeilvert | inactive | 10-23 06:20:30Z | なし | 10-24 06:21:24Z |
| pablo | inactive | 10-23 06:50:29Z | なし | 10-24 06:15:12Z |

- **control-plane 3 台の今日の unattended-upgrades は終わっている**（3 台とも inactive）。.111・.113 は 21:2xZ に zlib1g などを入れたが、iscsid の PID は変わっていない（iscsid は libz を読み込まない。runbook §2.11）
- 8 台の iscsid の PID は runbook §2.7 の表（14:23Z）から変わっていない。`unattended-upgrades-dpkg.log` の `restart … iscsid` は 8 台とも 1 回（§2.7 の表の再起動）。liblzma5 は 8 台とも `0.4`、open-iscsi は 2.1.9-3ubuntu5.5。`51fraction-hold-open-iscsi` は 8 台とも無い
- 作業の開始は 22:17Z。control-plane の次の実行は 10-24 21:08Z から、worker は 10-24 06:09Z からで、段 8 の作業（worker の 06:00Z まで）は時間帯に重ならない見込み。`install kubelet` の `daemon-reload` で時刻が引き直されるので、時間帯で避ける（runbook §2.11）
- jumelle の自動更新（18:00〜18:30Z）と自動再起動（19:00Z）の時間帯の外。jumelle の `reboot-required` は読んでいない（時間帯を避けるだけ）

## 6. kubelet の設定（runbook §2.2 の 30。22:09Z〜22:11Z）

- 8 台とも `/etc/systemd/system/kubelet.service` に `--container-runtime-endpoint` が 1 行あり、`/var/lib/kubelet/config.yaml` に `containerRuntimeEndpoint` は無い
- 2 つのファイルの md5 は、8 台とも PR #52 の前の master（`6bfaab0`）の `assets/kubelet/<ノード>/` と同じ
- `journalctl -u kubelet -b` の `Flag --container-runtime-endpoint has been deprecated` は、.111・.112・.113・braque・pablo 9 行、chirico・duchamp 7 行、oeilvert 2 行（ブートの後の kubelet の起動のたびに 1 行と、ほかの形のもの。§4.4 の 20 では新しい kubelet の起動の後に 0 であることを見る）
- `crictl version` は 8 台とも containerd v2.3.6

## 7. etcd のバックアップ（runbook §2.4。段の前）

| 項目 | 値 |
|---|---|
| コマンド | `porkadot etcd backup --config ./porkadot.yaml`（porkadot 0.37.0、etcdctl 3.6.15。サンドボックスの中で 22:17:11Z〜22:17:14Z、rc 0） |
| 取ったメンバー | 192.168.1.111（写したあと、ノードのものを消した） |
| ファイル | `etcd-2026-10-23T22:17:11+00:00.db`、モード 0600、55,107,616 バイト |
| sha256 | `3bf146222c89a49b835c1634a4d8b3624b48f5ba5252abcfb258ab5cb3196c64` |
| 置き場所 | 段 8 の worktree の `./backup/`（`.gitignore` で除外。git には入れていない。`git status` に出ない）。worktree を片付ける前に、coordinator がメインの checkout の `backup/` へ移す |
| 前のバックアップとの比較 | 段 7 の `etcd-2026-10-21T13:08:44+00:00.db`（55,107,616）と同じサイズ |

このバックアップは 1.36 の control-plane、etcd 3.6、Corefile の `cache 30` の状態で、runbook §7.4 の restore の第一の候補。

## 8. 手順書との差、気づいたこと

- Pod は 169 個（runbook §1.1 の 14:2xZ は 165 個）。Completed が 24 個で、natsumi と deep-researcher の 20:30Z・21:00Z の CronJob の Pod が足されたもの
- runbook §2.8 の告知ノードは、gated-v4（chirico、20:01Z）、`::131`（.113、21:52Z）、`::132`・`::134`（duchamp、18:32Z）が 14:2xZ の後に移っている
- cnidaria の手順書の `check-apps.sh` の `CHECK_URLS` の v6 は古いプレフィックス（`2405:6581:8580:301:ace::200`）のまま。写しの env（`RUNBOOK_ENV`）で新しいプレフィックスに替えて流した（`IMAGE` の `v0.1.1` と同じ扱い）
- oeilvert の resolv.conf の 192.168.0.1 の重なり（§4）
