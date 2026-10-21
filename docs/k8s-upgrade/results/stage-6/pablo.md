# pablo の段 6 の作業記録

pablo（192.168.1.134）の kubelet を、porkadot 0.35.0 の `install kubelet --node` で v1.35.9 に上げた記録。手順は `../../runbook-stage-6.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 1 台目。前は `192.168.1.111.md`、次は `braque.md`。読み取りの出力はタスクディレクトリの `notes/stage-6/pablo/`。

## 1. 事前の読み取り（2026-10-21 07:04:20Z）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.35.9 のノード: .111、.112、.113。v1.34.12 のノード: worker 5 台。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー .113、3 台とも 3.6.15・3.6.0。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 16、detached 1（`homegallery/cg-data`） |
| Longhorn の設定 | `baseline.md` §2 の 14 と同じ |
| MetalLB の告知ノード | `baseline.md` §2 と同じ（VIP は pablo） |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.34.12、`containerd://2.3.6`、cgroup: `cgroup2fs` |
| `/opt/bin` の向き先、CNI | `kubelet-v1.34.12`、`kubectl-v1.34.12`、`crictl-v1.34.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` |
| iscsid | 4114921、10-21 06:40:42Z（unattended-upgrades の needrestart。`baseline.md` §5。ベースラインから変わらない） |
| iSCSI のセッション | 1（sid 3、10.244.4.131 = 今の instance-manager `-17a539db…`） |
| `older-than-iscsid` のエンジン | 1（`pvc-c6fbd833…`、iscsid の 06:40:42Z の再起動より前の 03:08:33Z に起動） |
| アタッチされたボリュームと robustness | `fs/sites`（`pvc-c6fbd833…`）attached healthy |
| §8.12 の Pod | なし（同じ PVC を使う Succeeded の Pod は NFS の `aphrael/aphrael-2` の `tumblr-like` だけ） |
| Pod の控え | `pods-pre.tsv`、17 個 |
| そのノードが告知している LoadBalancer | API の VIP（192.168.1.101） |
| apt-daily-upgrade | inactive |

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`

- 開始 07:04:39Z、終わり 07:05:00Z（21 秒）、rc 0。サンドボックスの中で流した。`git status --short assets porkadot.yaml` は前も後も空
- `install-deps.sh` 5.7 秒、`install-pkgs.sh` 8.5 秒、`install.sh` 3.7 秒。apt は何も入れていない（`/var/log/apt/history.log` の最後は 06:40Z の unattended-upgrades）。CNI の plugins は展開していない
- kubelet の再起動 07:05:00Z

## 4. 確認（07:05:50Z）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.35.9 |
| 2 | バイナリ、CNI | `kubelet-v1.35.9`、`kubectl-v1.35.9`、`crictl-v1.35.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` のまま。`kubelet-v1.34.12` なども残っている |
| 3 | iscsid | 4114921、ActiveEnterTimestamp も同じ |
| 4 | iSCSI のセッション | 同じ sid 3・portal 10.244.4.131・target。古いセッションなし |
| 5 | エンジン | 同じボリューム、同じ起動の時刻。`older-than-iscsid` は 1 のまま |
| 6 | Longhorn | `fs/sites` は attached healthy のまま。ボリューム・instance-manager の一覧は前と同じ。Longhorn の node 4 つとも Ready。カーネルの I/O エラーなし |
| 7 | Pod の再起動 | **差分なし**（17 個の名前・UID・restartCount が同じ） |
| 10 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。pablo の error 6 → 12、`no route` 32 → 38（runbook §8.1）。ほかの 7 台の `no route` は 2 ずつ増えた |
| 11 | kubelet のログ | 起動のときの `node "pablo" not found`（1 回）など。続くエラーなし。`FailedMount` なし |
| 12 | 監視の FAIL | なし |
| 13 | leader election で再起動した controller | なし |
| 14 | 告知していた LoadBalancer | API の VIP は途切れず、`/readyz` は `ok`。告知は pablo のまま |
| 15 | CSR | なし |

NetworkPolicy と Pod 間通信の確認（runbook §5.5。1.35 の apiserver と、1.35 の kubelet のノード 4 台を含む形）:

- ✋ `netcheck.sh`（up → run → down、07:06:23Z〜07:06:41Z）: **168/168 PASS**（8 pods、21 targets each）、名前空間 `cnidaria-netcheck` は NotFound
- `infra-admin` の 1 時間のトークンを発行（07:06:52Z。`auth can-i create daemonsets -n k8u-npcheck` は `yes`）
- ✋ `npcheck.sh`（07:06:52Z〜07:09:25Z）: `nft` は up の前 8 台とも 0、up の後 8 台とも 9、`run` は **`OK 56, not OK 0`**、down の後 8 台とも 0。`k8u-npcheck` は NotFound
- トークンのファイルを消した（07:09:25Z）

## 5. 監視の FAIL と、その原因

なし。

## 6. 次の 1 台へ進む条件

すべて合格（§5.3 の項目、8 台 Ready、etcd 3/3 healthy、Running / Completed 以外の Pod 0、NetworkPolicy の確認）。

## 7. 手順書との差、気づいたこと

- なし
