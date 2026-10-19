# braque の段 2 の作業記録

braque（192.168.1.131）の kubelet を、porkadot 0.31.0 の `install kubelet --node` で v1.31.14 に上げた記録。手順は `../../runbook-stage-2.md`（以下 runbook）§5.4。
時刻は UTC。worker の 3 台目（drain しない台）。前は `duchamp.md`。

## 1. 事前の読み取り（2026-10-19 08:01Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.31.14 のノード: .111、.112、.113、pablo、duchamp、v1.30.14 のノード: braque、chirico、oeilvert。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー .113、raft term 23116。3.5.34。`/readyz` `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached 2 |
| Longhorn の設定（runbook §2.6） | `5`、`disabled`、`block-if-contains-last-replica` |
| Prometheus の `spec.replicas`、`minio/minio` | 2、4 |
| MetalLB の告知ノード（runbook §2.7） | VIP: pablo、gated-v4: chirico、gated-v6: oeilvert、`h2-sshd`: .112、`natsumi-sshd`: .111、`natsumi-sshd-myao`: duchamp、`natsumi-sshd-aki`: .112 |
| Longhorn のボリュームがアタッチされたノード（runbook §8.11） | chirico 15、oeilvert 9、pablo 1。**braque には無い**（longhorn-csi-plugin も載っていない） |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.30.14、`containerd://2.3.6` |
| `/opt/bin` の向き先 | kubelet: `kubelet-v1.30.14`、kubectl: `kubectl-v1.30.14`、crictl: `crictl-v1.30.1`。CNI の印: `v1.4.1` |
| Pod の名前・UID・restartCount（控え） | 5 個: `cnidaria-q8bhw`（3）、`kube-proxy-8ccz6`（0）、`node-exporter-bp7zj`（3）、`smart-exporter-dpfg8`（3）、`nfsd/nfsd-vt5k2`（1）。控えは `notes/stage-2/braque/pre/` |
| そのノードが告知している LoadBalancer | なし |
| braque: 時間帯 | 08:00Z（JST 17:00）の時点ではバックアップの時間帯（JST 16:45〜17:05）の中だった（`fs/sites-backup` が 07:53Z に走って終わっていた）。**08:05Z（JST 17:05）まで待ってから始めた**。走っている Job は無かった。CronJob の schedule はベースラインと同じ |
| braque: NFS の PV を使う Pod の restartCount | `carib/nginx`（chirico、0）、`carib2/movies`（chirico、8）、`docker/registry`（chirico、0）、`pondo/nginx`（chirico、0）、`pondo2/movies`（chirico、7）、`shja/nginx`（chirico、0）、`shja2/movies`（oeilvert、0。duchamp の drain で移ったもの） |
| cnidaria のログの error の数（8 台） | braque 8、chirico 8、ほかは 0 |

## 2. etcd のリーダー

なし（worker）。

## 3. drain

なし（braque は drain しない。runbook §5.4）。

## 4. `install kubelet`（runbook §5.4 の 2）

- 開始 08:05:40Z、終わり 08:06:10Z、rc 0。サンドボックスの中で流した
- 出力の要点: `install-deps.sh` 6.4 秒、`install-pkgs.sh` 13.0 秒、`install.sh` 6.6 秒。すべて `successful`
- kubelet の再起動の時刻: 08:06:10Z

## 5. 確認（runbook §5.4 の 3。08:06:10Z〜08:08:30Z）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready（SchedulingDisabled ではない）、v1.31.14、`containerd://2.3.6` |
| 2 | バイナリ | `kubelet-v1.31.14`、`kubectl-v1.31.14`、`crictl-v1.31.1`。`Kubernetes v1.31.14`。CNI の印 `v1.4.1`。`kubelet-v1.30.14` なども残っている |
| 3 | Pod の再起動 | 5 つの Pod は名前・UID が同じで、**各コンテナの restartCount がちょうど 1 増えた**（cnidaria、kube-proxy、node-exporter、smart-exporter、nfsd）。`definition changed` のイベント 5 件 |
| 4 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。braque の cnidaria の再起動の前のコンテナに `no route` の error が 7 件増えた（08:06:04Z。runbook §8.1）。再起動の後は 0 |
| 5 | nfsd | `nfsd-vt5k2` は 08:06:11Z に `definition changed`、前のコンテナは 08:06:16Z に exit 0（Completed。SIGTERM で 5 秒で止まった）、同じ秒に起き直して Running。2049 を listen している |
| 6 | NFS | oeilvert のホストの `/home/yuanying/shared/nfs` の `ls`（5 秒ごと、`timeout 5`）は 08:06:16Z と 08:06:27Z の 2 回が失敗し、08:06:37Z から読めた（**止まっていたのは 20 秒ほど**）。NFS の PV を使う 7 つの Pod は再起動していない（restartCount は前と同じ）。`carib2`・`pondo2`・`shja2` の `movies` の liveness・readiness が 08:06:28〜34Z に 1〜3 回失敗したが、再起動にはならなかった（段 C の braque では liveness で 1 回ずつ再起動した） |
| 7 | `registry.fraction.jp` | `/v2/` は作業の間ずっと 401 を返した（5 秒ごと） |
| 8 | LAN から Service の IP と名前 | 作業端末から `http://10.254.0.53:9090/-/ready`（Prometheus）が 200。braque のホストから `dig @10.254.0.10 kubernetes.default.svc.cluster.local` が `10.254.0.1`、`kube-prometheus-prometheus.monitoring.svc.fraction.cluster` が `10.254.0.53` |
| 9 | kubelet のログ | 古い kubelet の `Failed to update lease`（`connection reset by peer`。段 1 の braque と同じ形）、起動の直後の `InvalidDiskCapacity`・`crio`・`node not found`・checkpoint、cadvisor の `RecentStats` だけ |
| 10 | 監視の FAIL | 0（累計 9 のまま） |
| 11 | leader election で再起動した controller（対象のノードの外） | 無い |
| 12 | 告知していた LoadBalancer | なし。`check-apps.sh` の LB と VIP、`::131`〜`::134` の SSH のバナーが応答する |
| 13 | Longhorn | attached healthy 23、detached 2。braque にアタッチされたボリュームは無い |
| 14 | CSR | 無い |

etcd 3/3 healthy（リーダー .113、raft term 23116、raft index 1402659474 でそろう）。warning のイベントは上の `movies` の probe の失敗、`InvalidDiskCapacity`、node-exporter の readiness の 1 回（起き直す間）だけ。

## 6. uncordon と後始末

なし（drain していない。トークンも発行していない）。

## 7. 監視の FAIL と、その原因

なし（FAIL 0）。

## 8. 次の 1 台へ進む条件（runbook §5.6）

| 条件 | 結果 |
|---|---|
| §5.4 の 3 がすべて合格 | 合格 |
| 全 8 台が Ready、SchedulingDisabled でない。終えたノードが v1.31.14 | 合格（chirico、oeilvert のほかは v1.31.14） |
| etcd 3/3 healthy、VIP が応答する | 合格 |
| Running / Completed 以外の Pod がベースラインから増えていない | 合格（0 個） |
| Longhorn のボリュームが healthy | 合格（23 + 2） |
| Longhorn の設定が元の値、Prometheus 2、MinIO 4 | 合格 |
| `netcheck.sh`、`check-apps.sh` | `check-apps.sh` はベースラインと同じ。`netcheck.sh` は braque では流していない（drain しない台。runbook §5.4 の 3 の項目に無い） |

## 9. 手順書との差、気づいたこと

- nfsd は SIGTERM で 5 秒で止まり、すぐ起き直した。NFS の途切れは 20 秒ほどで、runbook §5.4 の見込み（最長 30 秒と起き直すまで）の内
- 時間帯の制約で 5 分待った
