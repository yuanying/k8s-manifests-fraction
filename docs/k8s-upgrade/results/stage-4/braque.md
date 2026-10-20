# braque の段 4 の作業記録

braque（192.168.1.131）の kubelet を、porkadot 0.33.0 の `install kubelet --node` で v1.33.13 に上げた記録。手順は `../../runbook-stage-4.md`（以下 runbook）の §5.2〜§5.4。drain していない。
時刻は UTC。worker の 3 台目。前の台は `pablo.md`。読み取りの出力はタスクディレクトリの `notes/stage-4/braque/`。

## 1. 事前の読み取り（2026-10-20 02:29Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.33.13 のノード: control-plane 3 台、duchamp、pablo、v1.32.13 のノード: braque、oeilvert、chirico。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー: 192.168.1.113（`57ec6f12ac7b683e`）、raft term 23120。版: 3.5.34。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 |
| Longhorn | attached healthy 16、detached（ベースラインのもの）: `homegallery/cg-data` |
| Longhorn の設定 | `5`、`disabled`、`block-if-contains-last-replica` |
| controller-manager と scheduler の置き場所とリーダー | controller-manager .111・.113（リーダー）、scheduler .113・.112（リーダー） |
| MetalLB の告知ノード | VIP: pablo、gated-v4: chirico、gated-v6: oeilvert、`h2-sshd`: .112、`natsumi-sshd`: .111、`natsumi-sshd-myao`: duchamp、`natsumi-sshd-aki`: .112 |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.32.13、`containerd://2.3.6` |
| `tools/node-state.sh`（ファイル名） | `node-state-pre.txt` |
| `/opt/bin` の向き先、CNI の印と 4 つのプラグイン | `kubelet-v1.32.13`、`kubectl-v1.32.13`、`crictl-v1.32.0`、`etcdctl-3.5.34`。印 `v1.9.1`、4 つとも v1.9.1 |
| iscsid（MainPID、ActiveEnterTimestamp） | 85966、2026-10-19 08:06:03Z |
| iSCSI のセッション | 0 |
| `older-than-iscsid` のエンジン | なし |
| アタッチされたボリュームと robustness | なし（Longhorn のノードではない） |
| 同じ Longhorn の PVC を使う Completed / Succeeded の Pod | なし |
| Pod の控え | `pods-pre.tsv`、5 個（cnidaria、kube-proxy、node-exporter、smart-exporter、`nfsd/nfsd-vt5k2`） |
| そのノードが告知している LoadBalancer | なし |
| cnidaria のログの error の数（8 台） | .111 15、.112 15、.113 16、braque 7、chirico 8、duchamp 14、oeilvert 0、pablo 15 |
| braque: 時間帯、nfsd の restartCount | 02:29Z（JST 11:29）。runbook §5.4 のバックアップの CronJob の時間帯の外（次は JST 14:30）。CronJob は 8 個でベースラインと同じ。`nfsd/nfsd-vt5k2` は Running、`nfsd=2`。2049 を listen している |

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`

- 開始 02:30:01Z、終わり 02:30:22Z、rc 0。サンドボックスの中で流した。前と後の `git status --short assets porkadot.yaml` は空
- 出力の要点: SSHKit のコマンド 7 つがすべて `successful`。`install-deps.sh` 6.5 秒、`install-pkgs.sh` 6.5 秒、`install.sh` 4.9 秒
- kubelet の再起動の時刻: 02:30:22Z

## 4. 確認（02:31Z〜）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.33.13、`containerd://2.3.6` |
| 2 | バイナリ、CNI | `kubelet-v1.33.13`、`kubectl-v1.33.13`、`crictl-v1.33.0`、`etcdctl-3.5.34`。CNI の印 `v1.9.1`、4 つとも v1.9.1（変わらない） |
| 3 | iscsid | MainPID 85966、ActiveEnterTimestamp 08:06:03Z。**前と同じ** |
| 4 | iSCSI のセッション | 0 のまま |
| 5 | エンジン | なし |
| 6 | Longhorn | なし（Longhorn のノードではない）。16 attached healthy のまま。カーネルの I/O エラーは無い |
| 7 | Pod の再起動 | **`pods-pre.tsv` と `pods-post.tsv` の差分は無い**（5 個とも名前・UID・restartCount が同じ。`nfsd/nfsd-vt5k2` も `nfsd=2` のまま） |
| 8 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。braque の cnidaria の error が 7 件増えた（`no route`、runbook §8.1）。ほかの 7 台は `no route` の行が 2 件ずつ増えた（info） |
| 9 | kubelet のログ | 起動の直後の `node "braque" not found`（lister）、`Image garbage collection failed once`、`InvalidDiskCapacity`、crio の factory、checkpoint、eviction manager の imagefs、info の `Failed to trigger a manual run probe="Readiness"`（02:30:32Z、02:30:34Z）だけ。続くエラーは無い |
| 10 | 監視の FAIL | 無い |
| 11 | 告知していた LoadBalancer | なし。ほかの LB も応答する |
| 12 | CSR | 無い |

braque の追加の確認（runbook §5.4。02:31Z）:

- nfsd は Running で restartCount が同じ（`nfsd=2`）。braque は 2049 を v4・v6 で listen している
- oeilvert のホストの `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で、中身（`aki`、`backups`、`codimd` …）が読める
- `registry.fraction.jp/v2/` は 401（応答あり）
- 作業端末（LAN）から kube-dns（10.254.0.10）で `kubernetes.default.svc.cluster.local`（10.254.0.1）、`h2.fs.svc.cluster.local`（10.254.0.170）、`kubernetes.default.svc.fraction.cluster`（10.254.0.1）が引ける

## 5. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因 |
|---|---|---|
| — | — | 無かった |

## 6. 次の 1 台へ進む条件（runbook §5.5）

| 条件 | 結果 |
|---|---|
| §5.3 がすべて合格 | はい |
| 全 8 台の Node が Ready、SchedulingDisabled でない | はい。v1.33.13: control-plane 3 台、duchamp、pablo、braque、v1.32.13: oeilvert、chirico |
| etcd 3/3 healthy、VIP が応答する | はい |
| Running / Completed 以外の Pod がベースラインから増えていない | 0 のまま |
| Longhorn のボリュームが healthy | 16 attached healthy、`cg-data` は detached のまま |
| Longhorn の設定がベースラインのまま | `5`、`disabled`、`block-if-contains-last-replica` |
| `check-apps.sh` | ベースラインと同じ |

## 7. 手順書との差、気づいたこと

- 無い。nfsd も再起動しなかった（段 3 と同じ）
