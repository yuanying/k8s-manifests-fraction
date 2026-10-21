# pablo の段 7 の作業記録

pablo（192.168.1.134）の kubelet を、porkadot 0.36.0 の `install kubelet --node` で v1.36.5 に上げた記録。手順は `../../runbook-stage-7.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 1 台目。前は `192.168.1.111.md`、次は `braque.md`。読み取りの出力はタスクディレクトリの `notes/stage-7/pablo/`。

## 1. 事前の読み取り（2026-10-21 13:19:11Z）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.36.5: control-plane の 3 台。v1.35.9: worker の 5 台。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー .113。3 台とも 3.6.15・3.6.0。`/readyz` は `ok` |
| Running / Completed 以外の Pod | 0 |
| Longhorn | attached healthy 16、detached unknown 1（`cg-data`） |
| Longhorn の設定 | ベースラインのまま |
| controller-manager と scheduler | どちらも .111（リーダー）と .112 |
| MetalLB の告知ノード | VIP pablo、gated-v4 chirico、gated-v6 oeilvert、`::131`・`::134` .112、`::132` .111、`::133` duchamp |
| 監視 | VIP と LB のログの最後の行は 13:19:20Z（`ok 1320`）。etcd の health の監視は runbook §4.5 のとおり止めてある |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.35.9、`containerd://2.3.6`、`cgroup2fs` |
| `/opt/bin`、CNI | `kubelet-v1.35.9`、`kubectl-v1.35.9`、`crictl-v1.35.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` |
| iscsid | MainPID 4114921、10-21 06:40:42Z（ベースラインと同じ。unattended-upgrades の needrestart。段 6 の前から） |
| iSCSI のセッション | 1 つ（sid 3、10.244.4.131:3260 = 今の instance-manager、`pvc-c6fbd833…`） |
| エンジン | `pvc-c6fbd833…`（`fs/sites`）、03:08:33Z 起動、`older-than-iscsid` 1（段 6 の前から） |
| アタッチされたボリューム | `fs/sites`、attached healthy |
| §8.12 の Pod | なし（`aphrael/aphrael-2` の `tumblr-like` の 3 つは NFS の PV で当たらない） |
| Pod の控え | `pods-pre.tsv`、17 個 |
| 告知している LoadBalancer | API の VIP（192.168.1.101） |
| unattended-upgrades | `apt-daily-upgrade.service` は inactive |

## 2. etcd のリーダー

worker なので無い。

## 3. `install kubelet`

- 開始 13:19:29Z、終わり 13:19:53Z（24 秒）、rc 0。サンドボックスの中で流した
- `install-deps.sh` 8.4 秒、`install-pkgs.sh` 9.5 秒、`install.sh` 4.0 秒。apt は何も入れていない（`history.log` の最後は 10-21 06:40Z の unattended-upgrades）。`/opt/cni/bin` の mtime は 2026-03-16 のままで、CNI の plugins は展開していない
- kubelet の起動 13:19:53Z

## 4. 確認（13:20:43Z）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.36.5 |
| 2 | バイナリ、CNI | `kubelet-v1.36.5`、`kubectl-v1.36.5`、`crictl-v1.36.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` のまま |
| 3 | iscsid | 4114921、10-21 06:40:42Z のまま |
| 4 | iSCSI のセッション | 同じ（sid 3、10.244.4.131:3260、同じ target）。古いセッションは無い |
| 5 | エンジン | 同じボリューム、同じ起動の時刻（03:08:33Z）。`older-than-iscsid` は 1 のまま |
| 6 | Longhorn | ボリューム・instance-manager はベースラインと同じ（diff なし）、`fs/sites` は attached healthy。Longhorn の node 4 つとも Ready。カーネルの I/O エラーなし |
| 7 | Pod の再起動 | **差分なし**（17 個の名前・UID・restartCount が同じ） |
| 10 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。pablo の error 12 → 20、`no route` 50 → 58（runbook §8.1）。ほかの 7 台の `no route` は 2 ずつ増えた |
| 11 | kubelet のログ | 止まる前の古い kubelet の `Failed to update lease`（13:19:50Z、`dns` の addon の `systemd-networkd` の再起動の間。段 3 の braque と同じ形）、起動の直後の `Error getting the current node from lister`、crio の factory、eviction manager の imagefs。`Flag --` は `--container-runtime-endpoint` の 1 つだけ |
| 12 | 監視 | VIP・LB の FAIL は増えていない（pablo は VIP を告知しているが、途切れなかった） |
| 13 | leader election で再起動した controller | 無い |
| 14 | 告知していた LoadBalancer | VIP は pablo のまま（告知の移動なし）、`/readyz` は `ok` |
| 15 | CSR | 無い |

NetworkPolicy の確認と netcheck（runbook §5.5、§1.9。1.36 の apiserver と 1.36 の kubelet の 4 台を含む形）:

- ✋ `netcheck.sh`（13:21:17Z〜13:21:37Z。cnidaria の手順書の `kadmin.sh` の admin の kubeconfig）: **PASS 168 / 168**、pods 8/8。`cnidaria-netcheck` は消した。出力は `notes/stage-7/pablo/netcheck/`
- ✋ `tools/npcheck.sh`（13:21:55Z〜13:24:24Z。`infra-admin` の 1 時間のトークンを 13:21:43Z に発行して `/tmp/k8u-stage7-admin-token`（モード 600）に置き、13:24:28Z に消した）: up の前の `nft` は 8 台とも 0、**up の後は 8 台とも 9**、`run` は **`OK 56, not OK 0`**、down の後は 8 台とも 0、`k8u-npcheck` は NotFound。出力は `notes/stage-7/pablo/npcheck.txt`

## 5. 監視の FAIL と、その原因

なし。

## 6. 次の 1 台へ進む条件

すべて合格（全 8 台 Ready、終えたノードが v1.36.5・まだのノードが v1.35.9、etcd 3/3 healthy、Running / Completed 以外の Pod 0、netcheck と NetworkPolicy の確認が合格）。

## 7. 手順書との差、気づいたこと

- なし
