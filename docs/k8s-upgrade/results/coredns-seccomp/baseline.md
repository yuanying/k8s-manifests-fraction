# CoreDNS の seccomp のベースライン

本番 `fraction` の CoreDNS を RuntimeDefault の seccomp で動かす（porkadot 0.37.3 → 0.37.4、イメージ v1.14.7 と Corefile は変わらない）前に取った、読み取りの結果と etcd のバックアップ、scale の server dry-run の記録。手順は `../../runbook-coredns-seccomp.md`（以下 runbook）。
時刻は UTC。`snap.sh`・`node-state.sh`・`endpoints.sh`・`seccomp.sh`・`dns-check.sh` の出力は、タスクディレクトリの `notes/coredns-seccomp/base/` に置いた（リポジトリには入れない）。

## 1. 前提（runbook §1。2026-10-26 06:55〜07:01Z）

| 項目 | 結果 |
|---|---|
| 本番の今の姿（§1.1） | 8 台 Ready・schedulable、v1.37.1。Pod 170 個（Running 146、Succeeded 24）で、Running / Succeeded 以外は 0 個。autoscaler は v1.11.0 の 1 つ（oeilvert の `kube-dns-autoscaler-5959bf78f6-pnh8z`、restart 0）で、ログは起動の 6 行だけ |
| kubeconfig（§1.2） | `kubectl --context fraction auth whoami` は `system:serviceaccount:kube-system:infra-auditor`。`auth can-i update deployments/scale -n kube-system`・`auth can-i patch deployments -n kube-system` は `no`。作業端末の kubectl は v1.37.1 |
| SSH（§1.3） | サンドボックスの中から、8 台に IP で `node-state.sh`、chirico・duchamp に `seccomp.sh`、oeilvert に `endpoints.sh`・`dns-check.sh`・`dns-watch.sh`、chirico・duchamp・oeilvert・pablo に resolv.conf の読み取りを流せた |
| porkadot（§1.4） | `worktrees/porkadot-v0-37-4` は `git describe --tags` が `v0.37.4`（`d0d84c9`）、`lib/porkadot/version.rb` が 0.37.4、作業ツリーに変更が無い。GitHub の `refs/tags/v0.37.4` は tag object `59c82ba`、`^{}` は `d0d84c9` で一致。`porkadot help` が動く。§7 の戻しの `worktrees/porkadot-v0-37-3` は `v0.37.3`（`121a264`、tag object `91a366b`）、変更なし。cwd は worktree `coredns-seccomp-prod`（base は PR #63 をマージした master の `96df273`）。`git status --short assets porkadot.yaml` は空。`e52d04b` との `assets/`・`porkadot.yaml` の差分は `assets/kubernetes/manifests/addons/coredns/coredns.yaml` の 1 ファイルだけ |
| 入れる版（§1.5。06:55Z） | `coredns/coredns:v1.14.7` は manifest list で amd64・arm・arm64・loong64・ppc64le・riscv64・s390x。v1.15.0 は 404 |
| 時間帯（§2.6） | 07:01Z に始めた。worker 4 台（chirico・duchamp・oeilvert・pablo）で unattended-upgrades・apt のプロセスは動いていない（`unattended-upgrade-shutdown --wait-for-signal` だけ） |

## 2. ベースライン（runbook §2.2。07:01:11Z の `snap.sh`、07:01:23Z の `node-state.sh`、07:01:26Z の `endpoints.sh`）

runbook §2.2 の表の値（06:4xZ）と、すべての項目で同じだった。

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node と taint | 8 台 Ready、v1.37.1、cordon されたものは無い。taint は control-plane 3 台が `node-role.kubernetes.io/master:NoSchedule`、braque が `unstable.cloud/storage:NoSchedule`、chirico・duchamp・oeilvert・pablo は無い |
| 2 | 全 Pod | 170 個（Running 146、Succeeded 24）。名前・UID・restartCount は `notes/coredns-seccomp/base/pods.txt` |
| 3 | `coredns` の Deployment | generation 13（observedGeneration 13）、revision 10、2/2（updated 2）。イメージ `registry.k8s.io/coredns/coredns:v1.14.7`、引数 `-conf /etc/coredns/Corefile`。テンプレートの注釈 `seccomp.security.alpha.kubernetes.io/pod: runtime/default`、Pod の securityContext は `{}`。コンテナの securityContext は `allowPrivilegeEscalation: false`・`capabilities: {add: [NET_BIND_SERVICE], drop: [all]}`・`readOnlyRootFilesystem: true`。readinessProbe `:8181/ready`（`periodSeconds: 10`、`initialDelaySeconds` なし）、livenessProbe `:8080/health`（`initialDelaySeconds: 60`、`failureThreshold: 5`）。resources は requests `cpu: 100m`・`memory: 70Mi`、limits `memory: 170Mi`。tolerations `CriticalAddonsOnly`、nodeSelector `kubernetes.io/os: linux`、affinity なし、`dnsPolicy: Default`、`terminationGracePeriodSeconds: 30`。strategy RollingUpdate（`maxSurge: 25%`・`maxUnavailable: 1`）、revisionHistoryLimit 10。PDB は `kube-controller-manager`・`kube-scheduler` だけ |
| 4 | CoreDNS の Pod | `coredns-76d7d8dc86-469lz`（duchamp、`10.244.5.210`、UID `f0d31e8b-b9da-44eb-9cb4-c2f1408780eb`、restart 7）と `coredns-76d7d8dc86-shdgn`（chirico、`10.244.8.74`、UID `a7417640-949a-4776-a343-78b1441ca1b6`、restart 5）。どちらも 2026-10-21 13:04:32Z 作成、imageID `registry.k8s.io/coredns/coredns@sha256:7efd3c635b03efd68c4e8398fc45f0d993d0e9ab016f72c1cefb0fd6d01aa286`。EndpointSlice `kube-dns-wr2s4` の endpoint はこの 2 つの IP。`coredns` の events は無い |
| 5 | `coredns` の ReplicaSet | `coredns-76d7d8dc86`（revision 10、2/2、v1.14.7）と、replicas 0 の 9 つ（revision 1〜9、`k8s.gcr.io/coredns:1.6.7` から v1.13.2）。どれも `seccompProfile` が無い |
| 6 | 今の Pod の seccomp（`seccomp.sh 192.168.1.135`・`192.168.1.83`） | 2 つとも CRI の config の `security_context.seccomp` が `{'profile_type': 1}`（Unconfined）、OCI spec に `linux.seccomp` が無い、`Seccomp: 0`・`Seccomp_filters: 0`。capabilities は bounding・effective・permitted とも `CAP_NET_BIND_SERVICE` だけ（`CapEff`・`CapBnd` が `0x400`）、`noNewPrivileges: true`（`NoNewPrivs: 1`）。**seccomp なしで動いている** |
| 7 | ConfigMap `kube-system/coredns` | resourceVersion `1239255997`。Corefile の SHA512 は `dbda5533…`、Pod のログの `Running configuration SHA512` は `78384ea2…` |
| 8 | CoreDNS のログと前の再起動 | `-469lz` の前のコンテナは 2026-10-23 02:19:56Z に exit 1（最後の行が `[FATAL] plugin/loop: Loop (10.244.5.1:39089 -> :53)`）。`-shdgn` は 2026-10-23 22:23:40Z に exit 1（`[FATAL] plugin/loop: Loop (10.244.5.210:47808 -> :53)`）。今のコンテナのログは、`-469lz` に `api.tumblr.com` の上流（192.168.0.1、10.254.0.10）への `i/o timeout` が 4 行（12 行のうち、`error|warn|fatal|loop` が 4）、`-shdgn` は起動の 5 行だけ（0） |
| 9 | 各 Pod の答え（`endpoints.sh`） | 2 つの Pod とも、UDP と TCP で同じ: `kubernetes.default.svc.cluster.local`・`kubernetes.default.svc.fraction.cluster` が `10.254.0.1`、`kube-dns.kube-system.svc.cluster.local` が `10.254.0.10`、SRV が 53 と 9153、`nosuch.default.svc.cluster.local`・`nosuch.invalid` が NXDOMAIN、PTR の `1.0.254.10`・`10.0.254.10` が `kubernetes.default.svc.cluster.local.`・`kube-dns.kube-system.svc.cluster.local.`、`www.google.com`・`example.com` が NOERROR。`:8080/health`・`:8181/ready`・`:9153/metrics` が 200、`coredns_build_info{goversion="go1.26.6",revision="427fc80",version="1.14.7"}` |
| 10 | autoscaler | v1.11.0 の 1/1。ConfigMap `kube-dns-autoscaler` の `data.linear` が `{"coresPerReplica":256,"nodesPerReplica":16,"preventSinglePointFailure":true}`、resourceVersion `901196490`。ログは 2026-10-25 10:18:23 の起動の 6 行で、seccomp の warning は 0 |
| 11 | kubelet（`node-state.sh`） | .111 MainPID 752609・NRestarts 0、.112 1028・1、.113 612672・0、braque 541944・0、chirico 3237977・0、duchamp 202232・0、oeilvert 916805・51、pablo 3509679・0（ActiveEnterTimestamp も runbook §2.2 の 11 と同じ） |
| 12 | containerd の CoreDNS のイメージ | `coredns:v1.14.7`（`97efff2babf85`、24.3 MB）は chirico と duchamp にだけある。pablo は v1.11.3 まで、oeilvert・braque・control-plane には CoreDNS のイメージが無い |
| 13 | ノードの resolv.conf | chirico・duchamp・pablo の `/run/systemd/resolve/resolv.conf` は 192.168.0.1、`2405:6580:6740:ac01::1`、10.254.0.10。oeilvert は 192.168.0.1、10.254.0.10、192.168.0.1、`2405:6580:6740:ac01::1`。4 台とも kube-dns が入っている |
| 14 | DNS | `tools/dns-check.sh yuanying@192.168.1.82` は Service（作業端末から）と 2 つの Pod（oeilvert から）で答えが同じ。§3 の `dns-watch.sh` の最初の 1 分で FAIL 0 |
| 15 | 権限 | §1 の kubeconfig のとおり |
| 16 | VIP | `https://192.168.1.101:6443/readyz` が 200 |

## 3. 監視（runbook §2.3）

07:01:58Z に、ハーネスのバックグラウンド実行で 2 つのジョブとして起動した（bg2: `dns-watch.sh`、bg3: `dns-replicas-watch.sh`）。`nohup`・`&` は使っていない。ログはタスクディレクトリの `notes/coredns-seccomp/logs/`（`dns.log`、`dns-replicas.log`）。

## 4. etcd のバックアップ（runbook §2.4）

07:02:07Z〜07:02:11Z に、porkadot 0.37.4 の `etcd backup` を worktree のルートで流した（rc 0。出力は `notes/coredns-seccomp/etcd-backup.log`）。流す前と後で `git status --short` は空。

| ファイル | 置き場所 | バイト | sha256 |
|---|---|---|---|
| `etcd-2026-10-26T07:02:07+00:00.db`（モード 0600） | worktree `coredns-seccomp-prod` の `./backup/`（git には入れない） | 66,986,016 | `0642993b21e894013073835b8f6e17c81145b8a14b22597e9b2d1f53cf786b40` |

メインの checkout の前のもの（`backup/etcd-2026-10-25T10:16:55+00:00.db`、55,107,616 B）より 11,878,400 B（21%）大きい。桁は同じなので、runbook §2.4 の止める条件には当たらない。worktree を片付ける前に、メインの checkout の `backup/` へ写す（coordinator）。

## 5. scale の server dry-run（runbook §3.1）

07:02:36Z に `infra-admin` のトークン（`--duration=1h`）を発行し、`--dry-run=server` が付いていることを確かめてから流した。トークンは同じシェルの中で使い、すぐ `unset` した（ファイルには書いていない）。

```
Warning: spec.template.metadata.annotations[seccomp.security.alpha.kubernetes.io/pod]: non-functional in v1.27+; use the "seccompProfile" field instead
deployment.apps/coredns scaled (server dry run)
```

dev と同じ warning が出た。直後の `coredns` は replicas 2、generation 13 のまま（dry-run は何も変えていない）。
