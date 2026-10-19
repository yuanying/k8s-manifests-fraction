# braque の段 3 の作業記録

braque（192.168.1.131）の kubelet を、porkadot 0.32.0 の `install kubelet --node` で v1.32.13 に上げた記録。手順は `../../runbook-stage-3.md`（以下 runbook）の §5.2〜§5.4。drain していない。
時刻は UTC。worker の 3 台目。前の台は `pablo.md`。読み取りの出力はタスクディレクトリの `notes/stage-3/braque/`。

## 1. 事前の読み取り（2026-10-19 23:42Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.32.13 のノード: control-plane 3 台、duchamp、pablo、v1.31.14 のノード: braque、oeilvert、chirico。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー: 192.168.1.113。版: 3.5.34。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 |
| Longhorn | attached healthy 16、detached（ベースラインのもの）: `homegallery/cg-data` |
| Longhorn の設定 | `5`、`disabled`、`block-if-contains-last-replica` |
| controller-manager と scheduler の置き場所とリーダー | controller-manager .112（リーダー）・.113、scheduler .112（リーダー）・.111 |
| MetalLB の告知ノード | `duchamp.md` と同じ |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.31.14、`containerd://2.3.6` |
| `/opt/bin` の向き先、CNI の印と 4 つのプラグイン | `kubelet-v1.31.14`、`kubectl-v1.31.14`、`crictl-v1.31.1`、`etcdctl-3.5.34`。印 `v1.4.1`、4 つとも v1.4.1 |
| iscsid（MainPID、ActiveEnterTimestamp） | 85966、08:06:03Z |
| iSCSI のセッション、エンジン、アタッチされたボリューム | なし（Longhorn のノードではない） |
| 同じ Longhorn の PVC を使う Completed / Succeeded の Pod | なし |
| Pod の控え | `pods-pre.tsv`、5 個（cnidaria `-q8bhw`、kube-proxy、node-exporter、smart-exporter、`nfsd/nfsd-vt5k2`（restartCount `nfsd=2`）） |
| そのノードが告知している LoadBalancer | なし |
| cnidaria のログの error の数（8 台） | .111 8、.112 7、.113 8、duchamp 6、pablo 7（それぞれの `install kubelet` のもの）、ほか 0 |
| braque: 時間帯、nfsd | 23:42Z（JST 08:42）。runbook §5.4 のバックアップの CronJob の時間帯の外。CronJob は 8 個でベースラインと同じ。2049 を listen している。`systemctl --failed` は `systemd-networkd-wait-online.service` だけ（以前から） |

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`

- 開始 23:42:45Z、終わり 23:43:20Z、rc 0。サンドボックスの中で流した
- 出力の要点: SSHKit のコマンド 7 つがすべて `successful`。`install-pkgs.sh` 16.6 秒、`install.sh` 6.6 秒
- kubelet の再起動の時刻: 23:43:20Z

## 4. 確認（23:44Z〜）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.32.13、`containerd://2.3.6` |
| 2 | バイナリ、CNI | `kubelet-v1.32.13`、`kubectl-v1.32.13`、`crictl-v1.32.0`。CNI の印 `v1.9.1`、4 つとも v1.9.1 |
| 3 | iscsid | MainPID 85966、08:06:03Z。**前と同じ** |
| 4〜6 | iSCSI、エンジン、Longhorn | なし。16 attached healthy のまま |
| 7 | Pod の再起動 | **差分は無い**（5 個とも名前・UID・restartCount が同じ。`nfsd/nfsd-vt5k2` は `nfsd=2` のまま） |
| 8 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。braque の cnidaria が `Reconciler error` を 7 件、23:43:14Z の 1 秒に出した。ほかの 7 台は info を 2 件ずつ |
| 9 | kubelet のログ | 古い kubelet（v1.31.14）が 23:43:14Z に `Failed to update lease ... connection reset by peer` を 1 件（`systemd-networkd` の再起動。runbook §5.4、段 1 の braque と同じ）。新しい kubelet は起動の直後のもの（`node "braque" not found`、`Image garbage collection failed once`、crio、checkpoint、eviction manager）だけ |
| 10 | 監視の FAIL | 無い |
| 11 | 告知していた LoadBalancer | なし。ほかの LB も応答する |
| 12 | CSR | 無い |

braque の追加の確認（runbook §5.4）:

- nfsd は Running で restartCount が同じ（再起動していない）。braque は 2049 を v4・v6 で listen している
- oeilvert のホストの `/home/yuanying/shared/nfs` が読める（`aki`、`backups`、`codimd`…）
- `registry.fraction.jp/v2/` は 401（応答あり）
- 作業端末（LAN）から kube-dns（10.254.0.10）で `kubernetes.default.svc.cluster.local`（10.254.0.1）と `h2.fs.svc.cluster.local`（10.254.0.170）が引ける

## 5. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因 |
|---|---|---|
| — | — | 無かった |

## 6. 次の 1 台へ進む条件（runbook §5.5）

| 条件 | 結果 |
|---|---|
| §5.3 がすべて合格 | はい |
| 全 8 台の Node が Ready、SchedulingDisabled でない | はい。v1.32.13: 6 台、v1.31.14: oeilvert、chirico |
| etcd 3/3 healthy、VIP が応答する | はい |
| Running / Completed 以外の Pod がベースラインから増えていない | 0 のまま |
| Longhorn のボリュームが healthy | 16 attached healthy |
| Longhorn の設定がベースラインのまま | はい |
| `check-apps.sh` | ベースラインと同じ |

## 7. 手順書との差、気づいたこと

- 段 2 と違い、nfsd は再起動せず、NFS は途切れなかった（runbook §5.4 の見込みどおり）
