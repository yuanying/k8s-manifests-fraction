# kube-dns-autoscaler v1.11.0 の記録

本番 `fraction` の kube-dns-autoscaler を `registry.k8s.io/cluster-proportional-autoscaler-amd64:1.7.1` から `registry.k8s.io/cpa/cluster-proportional-autoscaler:v1.11.0` へ上げた（porkadot 0.37.2 → 0.37.3）。手順は `../../runbook-dns-autoscaler-1.11.md`（以下 runbook）、前提とベースラインは `baseline.md`。
時刻は UTC。2026-10-25 10:18:05Z の `install kubernetes` から 10:20:51Z の監視の停止まで。監視のログ、`snap.sh`・`node-state.sh`・`seccomp.sh` の出力、`install kubernetes` の出力、autoscaler のイベントとログの写しは、タスクディレクトリの `notes/dns-autoscaler-1-11/` に置いた（リポジトリには入れない）。

**結果: runbook §4.2 の 14 項目と §4.3 はすべて合格した。** 新しい Pod は oeilvert で起動から 2 秒で Ready になり、同時に古い Pod が止まった。CoreDNS の replicas と Pod は変わらず、1 秒ごとの DNS の問い合わせ（240 サンプル）は 1 度も落ちなかった。autoscaler 以外の Pod と 8 台の kubelet は変わっていない。

## 1. 流れ

| 時刻 | 何をしたか | 結果 |
|---|---|---|
| 10:16:03〜10:16:39 | §1・§2.2 の前提とベースライン（読み取り） | `baseline.md` |
| 10:16:47 | §2.3 の監視（`dns-watch.sh`、`dns-replicas-watch.sh`）をジョブとして起動 | — |
| 10:16:55〜10:16:58 | ✋ §2.4 の etcd backup | rc 0。`baseline.md` §4 |
| 10:17:55 | §3.1 の事前確認 | 8 台 Ready、`coredns` 2/2、autoscaler 1/1、監視の最後の行が 1 秒以内で FAIL 0、`git status --short assets porkadot.yaml` が空、porkadot が `v0.37.3` |
| 10:18:05〜10:18:29 | ✋ §3.2 の `install kubernetes --node 192.168.1.111` | **1 回目で rc 0**（24.5 秒） |
| 10:18:21〜10:18:23 | §4.1 の入れ替わり | §3 |
| 10:18:34 | `rollout status` | `successfully rolled out` |
| 10:18:41〜10:19:20 | §4.2 の `snap.sh`・`node-state.sh`・`seccomp.sh`（`after`）、`:8080` | §4 |
| 10:20:46 | §4.3 の 2 分後のログと replicas | §4 の 7・8 |
| 10:20:51 | 監視を止めた（`watch.stop`） | 2 つのジョブとも終わった |

## 2. `install kubernetes`（runbook §3.2）

`porkadot install kubernetes --node 192.168.1.111`（porkadot 0.37.3、cwd は worktree `dns-autoscaler-prod`、master `a1f11db` の assets）。10:18:05.032Z〜10:18:29.574Z、rc 0。流す前と後で `git status --short` は空。

- `configured`: **`deployment.apps/kube-dns-autoscaler`**、DaemonSet `kube-apiserver`（2 回）、PDB `kube-controller-manager`・`kube-scheduler`、ValidatingWebhookConfiguration `metallb-webhook-configuration`。runbook §3.2 の組と同じ
- ServiceAccount・ClusterRole・ClusterRoleBinding `kube-dns-autoscaler`、`coredns`、ConfigMap `coredns` は `unchanged`。`unchanged` は 61 行
- **`pruned` の行は無い**。`created`・`deleted` も無い

## 3. 入れ替わり（runbook §4.1）

autoscaler の events と `dns-replicas.log`（2 秒ごと）から。

| 時刻 | できごと |
|---|---|
| 10:18:21 | ReplicaSet `kube-dns-autoscaler-5959bf78f6` を 0 → 1。Pod `kube-dns-autoscaler-5959bf78f6-pnh8z` を作り、**oeilvert** に割り当て |
| 10:18:22〜10:18:23 | v1.11.0 の pull（898 ms、14,293,336 B）、コンテナの作成・起動 |
| 10:18:23 | 新しい Pod が Ready。同じ秒に古い Pod `kube-dns-autoscaler-cc5758b6f-dhc95`（chirico）の `Killing`、`cc5758b6f` を 1 → 0 |
| 10:18:25 | `dns-replicas.log` から古い Pod が消えた（10:18:22 の行が両方の Pod の最後） |

- 作られてから Running まで 2 秒（dev では 4 秒で入れ替わり）。2 分の止める条件に近づくことは無かった
- その間も前後も、`dns-replicas.log` の 108 行（10:16:47〜10:20:50）はすべて `coredns(spec/ready/status)=2/2/2` で、CoreDNS の Pod は `coredns-76d7d8dc86-469lz`（duchamp、restart 7）と `coredns-76d7d8dc86-shdgn`（chirico、restart 5）のまま

### 3.1 途切れ

| 監視 | サンプル | FAIL |
|---|---|---|
| `in=`（`kubernetes.default.svc.cluster.local`） | 240（10:16:48〜10:21:10） | **0** |
| `dns=`（`kube-dns.kube-system.svc.cluster.local`） | 240 | **0** |
| `ext=`（`www.google.com`） | 240 | **0** |

`install kubernetes` から §4.3 の終わりまで（10:18:05〜10:20:46）は 147 サンプルで、FAIL は 0。`ssh rc=` の行は無く、サンプルの間隔は最大 1.8 秒。

## 4. 確認（runbook §4.2、§4.3）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Deployment | generation 4 → **5**（observedGeneration 5）、revision 2 → **3**。1/1、updated 1。テンプレートのイメージが `registry.k8s.io/cpa/cluster-proportional-autoscaler:v1.11.0`、securityContext は `fsGroup: 65534`・`seccompProfile.type: RuntimeDefault`・`supplementalGroups: [65534]`、テンプレートの注釈は無い（`seccomp.security.alpha.kubernetes.io/pod` が消えた）。コンテナの引数・resources（イメージ以外）、tolerations・nodeSelector・affinity はベースラインと同じ |
| 2 | Pod | **1 つだけ。`kube-dns-autoscaler-5959bf78f6-pnh8z`（UID `d3cc78ff-4a69-4a5b-b8be-283542b727eb`）、v1.11.0 で Running、Ready、restart 0**、2026-10-25 10:18:21Z 起動、Pod IP `10.244.7.26`。imageID は `registry.k8s.io/cpa/cluster-proportional-autoscaler@sha256:c1eac1db4ad72c27bbaf411d8a9a6a609e513bd09d72308027f24058f78ed6ad`。古い Pod は無い |
| 3 | 配置 | **oeilvert**（taint の無い worker。control-plane と braque には無い） |
| 4 | ReplicaSet | `kube-dns-autoscaler-5959bf78f6` が 1/1。`cc5758b6f` と `64bc6d94b9` は 0 で残る |
| 5 | seccomp（`seccomp.sh 192.168.1.82`） | CRI の config の `security_context.seccomp` が `{}`（`profile_type` 0 = RuntimeDefault）、OCI spec に `linux.seccomp`（`defaultAction: SCMP_ACT_ERRNO`、syscall の規則 14）がある、**`/proc/<pid>/status` が `Seccomp: 2`、`Seccomp_filters: 1`**、`NoNewPrivs: 0`。`status.seccomp` は `None`（dev と同じ。§5） |
| 6 | `:8080` | oeilvert から `http://10.244.7.26:8080/healthz` と `/last-poll` が **200** |
| 7 | ログ | 10:18:23 の起動の 6 行だけ: `Scaling Namespace: kube-system, Target: deployment/coredns`、`Set control mode to linear`、`ConfigMap version change (old:  new: 901196490)`、`Params from apiserver:` に `{"coresPerReplica":256,"nodesPerReplica":16,"preventSinglePointFailure":true}`、`Defaulting min replicas count to 1`。**`E`・`W` で始まる行、`Forbidden`、`Cluster status`、`Replicas are not as expected` は無い**（10:20:46 に取ったログ。`notes/dns-autoscaler-1-11/after/autoscaler-2min.log`） |
| 8 | CoreDNS | `coredns` の generation 13 のまま、replicas 2、2/2。Deployment の yaml はベースラインとまったく同じ。**Pod 2 つの名前・UID・restartCount がベースラインと同じ**。`coredns` の events は無い（`ScalingReplicaSet` も無い） |
| 9 | ConfigMap | `kube-dns-autoscaler` の yaml がベースラインとまったく同じ（`data`、resourceVersion `901196490`） |
| 10 | RBAC | ClusterRole・ClusterRoleBinding・ServiceAccount の yaml がベースラインとまったく同じ（resourceVersion も同じ） |
| 11 | ほかの Pod | autoscaler の Pod を除いた全 Pod の名前・UID・restartCount・phase がベースラインと同じ。168 個（Running 145、Succeeded 23）で、10:20:51 に Running / Completed 以外は 0 |
| 12 | kubelet | 8 台の MainPID・NRestarts・ActiveEnterTimestamp がベースラインと同じ。containerd のイメージは oeilvert に `cpa/cluster-proportional-autoscaler:v1.11.0`（`d591393a79c94`、14.3 MB）が増えただけ |
| 13 | 監視の FAIL | §3.1。0 |
| 14 | 健全性 | 8 台 Ready、`https://192.168.1.101:6443/readyz` が 200（10:20:51） |

**§4.3 の計算の確かめ**: 新しい Pod の起動（10:18:23）から 2 分 23 秒後の 10:20:46 に、ログに `Cluster status`・`Replicas are not as expected` が無く（poll 14 回）、`coredns` が 2/2/2 のまま。v1.11.0 が本番の ConfigMap を読み（7）、8 台・52 cores で今の replicas と同じ 2 を計算している（`baseline.md` §2 の 9）。ConfigMap は書き換えていない。

## 5. 手順書との差

- **runbook §4.2 の 5 の「`status.seccomp` が RuntimeDefault（dev では `profile_type` 0）」は誤り。** containerd 2.3.6 の `crictl inspect` には `status.seccomp` が無く、dev でも本番でも `None` になる。dev の `profile_type` は CRI の config の `info.config.linux.security_context.seccomp` で、v1.11.0 は `{}`（0 = RuntimeDefault。JSON で 0 が省かれる）、dev の 1.7.1 は `{'profile_type': 1}`（Unconfined）。本番のタスクディレクトリの `seccomp.sh` はこの項目を出していなかったので、出すように直して `after` を取り直した（ベースラインの 1.7.1 の値は取っていない。1.7.1 が seccomp なしで動いていたことは、OCI spec に `linux.seccomp` が無いことと `Seccomp: 0` で確かめてある）。runbook の §1.6 と §4.2 の 5 を直した（この PR）
- Pod の数は runbook を書いたとき（06:0xZ）の 166 個から 168 個に増えていた。どれも Running か Succeeded で、作業の前後で変わっていない
- 新しい Pod は oeilvert（DNS の監視のノード）に載った。runbook §2.7 のとおり監視（dig）には関わらず、FAIL は 0
- そのほかは runbook のとおり（`install kubernetes` の `configured` の組、入れ替わりの形、ログ、`:8080`）

## 6. 片付けと、残したこと

- 一時的なリソース・名前空間は作っていない。`infra-admin` のトークンは発行していない（runbook §1.2）
- 監視は 10:20:51Z に止めた（2 つのジョブとも終わった）
- etcd のバックアップは worktree の `./backup/etcd-2026-10-25T10:16:55+00:00.db`（55,107,616 B、sha256 `3a928c55a66a1d53ebe06480ae94ebacd40458f9b9f95607015977f3e53107bd`）。git には入れていない。worktree を片付ける前に、メインの checkout の `backup/` へ写す（coordinator）
- runbook §10 の片付けの対象（古い ReplicaSet `kube-dns-autoscaler-64bc6d94b9`・`cc5758b6f`、ノードの 1.7.1 のイメージ、`coredns` の古い ReplicaSet）と CoreDNS の seccomp（runbook §8.3）には触っていない
