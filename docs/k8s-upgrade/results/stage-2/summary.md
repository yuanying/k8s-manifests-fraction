# 段 2 のまとめと完了の確認

本番 `fraction` の Kubernetes を v1.30.14 から v1.31.14 へ上げた段 2（porkadot 0.30.0 → 0.31.0、crictl v1.31.1、kubelet-serving-cert-approver `:main` → `0.12.1`。etcd 3.5.34・CoreDNS v1.11.3 は据え置き）の、全体のまとめと完了の確認（runbook §6）の記録。手順は `../../runbook-stage-2.md`（以下 runbook）。
時刻は UTC。作業の前のクラスタ全体と etcd のバックアップは `baseline.md`、`install kubernetes` は `control-plane.md`、各台の記録は `<ノード>.md`（control-plane は `192.168.1.11N.md`）、drain の後の iSCSI の件は `iscsi-stale-sessions.md`。

## 1. 作業（2026-10-19）

porkadot のコマンドは、すべてサンドボックスの中（ssh-agent なし）で流し、SSH の失敗は一度も無かった（runbook §8.9 の 0.31.0 の直しが効いた）。

| 順 | 対象 | 流した時刻（開始 → 終わり） | drain / 再起動 | 監視の FAIL | 記録 |
|---|---|---|---|---|---|
| — | `etcd backup`（.111） | 07:16:20 → 07:16:24 | — | — | `baseline.md` §3 |
| 1 | `install kubernetes --node 192.168.1.111` | 07:18:08 → 07:18:35（rollout の終わり 07:21:07） | — | 0 | `control-plane.md` |
| 2 | 192.168.1.113（etcd のリーダーを .111 へ移した） | 07:23:21 → 07:24:24 | — | 0 | `192.168.1.113.md` |
| 3 | 192.168.1.112 | 07:27:29 → 07:28:00 | — | 0 | `192.168.1.112.md` |
| 4 | 192.168.1.111（etcd のリーダーを .113 へ移した） | 07:30:52 → 07:31:11 | — | **VIP 9** | `192.168.1.111.md` |
| 5 | pablo | 07:38:54 → 07:39:14 | drain 6 秒 | 0 | `pablo.md` |
| 6 | duchamp | 07:45:51 → 07:47:02 | drain 32 秒 | 0 | `duchamp.md` |
| 7 | braque（drain しない。JST 17:05 まで待った） | 08:05:40 → 08:06:10 | — | 0 | `braque.md` |
| 8 | chirico（Prometheus を止めた） | 08:11:32 → 08:12:33 | drain 41 秒 | **LB 1**（drain） | `chirico.md` |
| 9 | oeilvert（MinIO を止めた） | 08:58:11 → 08:58:28 | drain 7 分、再起動 09:00:36 | 0 | `oeilvert.md` |
| 10 | chirico の再起動（Prometheus を止めた） | — | drain 34 秒、再起動 09:13:36 | 0 | `iscsi-stale-sessions.md` §5 |
| 11 | duchamp の再起動 | — | drain 37 秒、再起動 09:37:34 | 0 | `iscsi-stale-sessions.md` §5 |

- ロールバック（runbook §7）は一度も行っていない
- runbook から外れた操作・判断（どれもユーザーの判断で承認を取った）:
  - .111 の `install kubelet` の後の、そのノードの controller-manager +3・cnidaria・speaker +2 の再起動と VIP の FAIL 9 回を、一時的な障害として許容した（`192.168.1.111.md` §5.1。runbook §4.3 の 7 に例外を足した）
  - oeilvert の drain の後、chirico の古い iSCSI のセッションで 4 つのボリュームが faulted を繰り返した。chirico を cordon して 4 つの Pod を消し、ほかのノードでアタッチさせた。oeilvert は uncordon の前に再起動し、chirico と duchamp も drain して再起動した（`iscsi-stale-sessions.md`。runbook §5.2 の 9、§8.12 を足した）
- runbook の中での決め直し: oeilvert で止めるものを MinIO だけにした（Prometheus の replica 1 のボリュームが chirico の作業で移っていたため。runbook §5.1）

## 2. 完了の確認（runbook §6。2026-10-19 10:16Z〜10:18Z）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready、全台 v1.31.14、CONTAINER-RUNTIME が 8 台とも `containerd://2.3.6`。SchedulingDisabled のノードは無い。8 台の `/opt/bin` は `kubelet-v1.31.14`、`kubectl-v1.31.14`、`etcdctl-3.5.34`、`crictl-v1.31.1`、CNI の印 `v1.4.1` |
| etcd | 3/3 healthy、全メンバーが 3.5.34、リーダー .113（`57ec6f12ac7b683e`）、raft term 23116、raft index 1402717128 でそろう。3 台の `/etc/etcd/pki` の 3 つのファイルが `600 root:root` |
| VIP | `/readyz` `ok`、`/version` v1.31.14 |
| apiserver、controller-manager、scheduler、kube-proxy | kube-apiserver の DaemonSet 3/3（v1.31.14）。controller-manager 2/2（.111 の `-2blbx`、.112 の `-2ffhd`。リーダー `-2ffhd`）、scheduler 2/2（.112 の `-vb2lz`、.113 の `-mp2ld`。リーダー `-mp2ld`）。同じ master に同じ component が 2 つ載っていない。kube-proxy 8/8、8 つともログに `Using iptables Proxier` |
| CoreDNS | v1.11.3（generation 9 のまま）、Running |
| kubelet-serving-cert-approver | `0.12.1`、`IfNotPresent`、imageID `sha256:445a8e5584f6…`、1/1 Running（oeilvert） |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached unknown 2（`myao/myao`、`homegallery/cg-data`。ベースラインのとおり）。instance-manager 4 つとも running、engine image `longhorn-engine:v1.11.2` deployed、Longhorn の node 4 つとも Ready・schedulable。K8s 1.31 は Longhorn 1.11 の要件（1.25 以上）に入る |
| Longhorn の replica の置き場所 | data locality で多くが動いた（`duchamp.md` §6、`chirico.md` §6）。replica 1 のボリューム: `prometheus-...-0`（pvc-625c8825）は chirico、`prometheus-...-1`（pvc-99c35b80）は oeilvert、`export-minio-0`〜`3` は oeilvert。同じボリュームの replica が同じノードに 2 つ載っているものは無い |
| Longhorn の設定 | ベースラインのまま（`concurrent-replica-rebuild-per-node-limit` `5`、`replica-auto-balance` `disabled`、`node-drain-policy` `block-if-contains-last-replica`、`default-data-locality` `best-effort`、`current-longhorn-version` v1.11.2） |
| Prometheus、MinIO | Prometheus の `spec.replicas` 2（2/2 Running）、`minio/minio` 4（4/4 Running） |
| cnidaria | 8 台の Pod が 1/1、ログの error 0。`verify-nodes.sh` 64 PASS、FAIL 0。✋ `netcheck.sh` 168/168 PASS（10:15:52Z）。`hedgedoc/db-postgresql` の NetworkPolicy は、db の Pod のある pablo の `table inet cnidaria` に 10 行（ベースラインの chirico と同じ数） |
| MetalLB | gated の `192.168.1.200` と `[...:ace::200]` の 80 は 404（応答あり）。`h2-sshd`（`::131`）、`natsumi-sshd`（`::132`）、`natsumi-sshd-myao`（`::133`）、`natsumi-sshd-aki`（`::134`）の 3222 が SSH のバナーを返す。minecraft は UDP なので確かめていない。告知ノード: VIP pablo、gated-v4 chirico・v6 oeilvert、`h2-sshd`・`natsumi-sshd-aki` .112、`natsumi-sshd` .111、`natsumi-sshd-myao` duchamp |
| NFS | braque の nfsd が Running、2049 を listen。oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で読める。`registry.fraction.jp/v2/` は 401（応答あり） |
| metrics | `kubectl top nodes` が 8 台とも応答する。Prometheus の `up == 0` は 0 個。`apiserver_requested_deprecated_apis` は `metallb.io/v1beta1 addresspools`（`removed_release` なし）だけ（ベースラインと同じ。段 3 の 1.32 で消える `flowcontrol.apiserver.k8s.io/v1beta3` は使われていない） |
| CSR | 無い（段の間に新しい CSR は出ていない）。kubelet の serving の証明書の subject と期限は 8 台ともベースラインと同じ |
| iSCSI | drain・再起動した 4 台のホストのセッションは、今の instance-manager へのものだけ（`iscsi-stale-sessions.md` §5） |
| 監視 | 下の 2.3 |
| leader election で再起動した controller | 対象のノードの外では 0（2.2） |

### 2.1 restartCount の増え方（ベースラインからの比べ。`notes/stage-2/final/compare-baseline.tsv`）

ベースラインの Pod のうち、段 2 の間ずっと動き続けた（名前・UID が同じ）ものは 44 個。drain・rollout で作り直されたものは新しい UID・名前で 0 から数える。

| 増え方 | Pod | 理由 |
|---|---|---|
| 各コンテナ +1 | 21 個（control-plane・braque・pablo の DaemonSet など） | 1.31 の kubelet での 1 回の再起動（runbook §8.4） |
| +2 | chirico・duchamp・oeilvert の engine-image、longhorn-csi-plugin、longhorn-manager、node-exporter、smart-exporter（15 個）。.111 の cnidaria、speaker | 再起動した 3 台: kubelet の更新で 1 回、ノードの再起動で 1 回。.111: §1 の .111 の件 |
| +3 | chirico・duchamp・oeilvert の cnidaria、speaker（6 個） | ノードの再起動の直後に API に繋がらず 1 回落ちる（段 C の手順書 §3.10 の形） |

`install kubernetes` で作り直された Pod のうち、.111 の `kube-controller-manager-...-2blbx` は 3（.111 の件。`192.168.1.111.md` §5.1）、ほかの controller-manager・scheduler・apiserver は 1。CrashLoopBackOff が続いているもの、Running に戻らないものは無い。

### 2.2 warning のイベント・ログ

- runbook §8 にあるもの: 各台の `InvalidDiskCapacity`、`definition changed, will be restarted`（イベントの reason `Killing`）、apiserver の止まりかけの間の probe の失敗、対象のノードの cnidaria の `no route`（6〜8 件、1 秒ほど。oeilvert は 0）、etcd の `peer became inactive`（1.3〜3 秒）、Longhorn の node の一瞬の not ready、engine-image の起き直しの間の probe の失敗、`node-driver-registrar` の `FailedPreStopHook`（イメージに `/bin/sh` が無い）、古い kubelet の `Failed to update lease`（`systemd-networkd` の再起動）
- braque の nfsd の再起動の間の `movies` の probe の失敗（再起動にはならなかった）
- .111 の件と、oeilvert の後の iSCSI の件（§1）
- 09:50Z より後の warning のイベントは無い。kubelet、apiserver、kube-proxy、cnidaria、etcd、Longhorn のログに、上のもの以外の新しい warning は見ていない

### 2.3 監視（runbook §2.3）の FAIL

監視は 07:14Z から 10:16Z まで（`ok` の行が 10080 回目まで）流し、ログはタスクディレクトリの `notes/stage-2/stage-2-probe.log` に置いた。

| 原因 | VIP | LB |
|---|---|---|
| apiserver の止まりかけ（.111 の 6443 が閉じたまま Endpoints に残った。07:31:14〜32Z） | 9 | 0 |
| gated の Pod の移動（chirico の drain。08:09:56Z） | 0 | 1 |
| 告知ノードの speaker の再起動（pablo を含む） | 0 | 0 |
| ノードの再起動（oeilvert、chirico、duchamp） | 0 | 0 |
| それ以外 | 0 | 0 |

## 3. 片付けと、残したこと

- `infra-admin` のトークン: pablo（07:38Z）、duchamp（07:44Z）、chirico（08:09Z）、oeilvert〜duchamp の再起動（08:33Z）で 3 時間の期限で発行し、どれも作業端末の `/tmp` のモード 600 のファイルに置いて、台の後始末で消した（最後は 10:16:09Z。サーバーの側では 11:33Z に期限が切れる）
- 監視は 10:16Z に止めた
- etcd のバックアップ `etcd-2026-10-19T07:16:21+00:00.db`（55,107,616 バイト、sha256 `328bcd5dee9196b28457a14c7174c99841b9b2f5e460d0c9808672661dcdaa91`）は段 2 の worktree の `./backup/` にある。worktree を片付ける前に、メインの checkout の `backup/` へ移す（coordinator）
- 作業端末の kubectl は、確認の時点で v1.31.14 になっていた（段 2 の間に替わった）
- 様子見: 次に kubelet の serving の証明書が更新されるとき（いちばん早いのは oeilvert、期限 2027-03-20）、CSR が approver 0.12.1 で Approved,Issued になることを見る（runbook §8.10）
- 段 3 以降の手順書に引き継ぐこと: drain した台は uncordon の前に再起動する（runbook §8.12）、control-plane の `install kubelet` での同じノードの controller の数回の再起動（runbook §4.3 の 7、§8.8）、replica 1 のボリュームが data locality で動くので各台の前に読み直すこと（runbook §5.1）、`definition changed` はイベントで見ること（§4.3 の 10）
- バックログ: 再起動せずに古い iSCSI のセッションを消す方法を dev で確かめる。.111 の apiserver だけが SIGTERM の直後に 6443 を閉じた理由
