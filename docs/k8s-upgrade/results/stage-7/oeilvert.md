# oeilvert の段 7 の作業記録

oeilvert（192.168.1.82）の kubelet を、porkadot 0.36.0 の `install kubelet --node` で v1.36.5 に上げた記録。手順は `../../runbook-stage-7.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 3 台目。前は `braque.md`、次は `duchamp.md`。読み取りの出力はタスクディレクトリの `notes/stage-7/oeilvert/`。項目の形は `pablo.md` と同じで、違うところだけを書く。

## 1. 事前の読み取り（2026-10-21 13:27:05Z）

| 項目 | 結果 |
|---|---|
| クラスタ | 8 台 Ready（control-plane の 3 台、pablo、braque が v1.36.5）。etcd 3/3 healthy。`/readyz` は `ok`。Running / Completed 以外の Pod は 0。Longhorn 16 + 1。告知ノードは `pablo.md` と同じ |
| 対象のノード | v1.35.9、`cgroup2fs`。`/opt/bin` は 1.35 の向き先、CNI は `v1.9.1`。iscsid 6334、10-19 09:04:34Z（needrestart はまだ。liblzma5 は 0.3。`baseline.md` §5）。セッション 2 つ（sid 3・4、10.244.7.116:3260 = 今の instance-manager）、エンジン 2 つ（03:05:54Z・03:06:11Z 起動、`older-than-iscsid` 0）。アタッチされたボリュームは `fraction-agents` の 2 つ（attached healthy）。§8.12 の Pod なし。Pod 37 個。告知している LoadBalancer は gated-v6（`::200`）。`apt-daily-upgrade.service` は inactive |

## 3. `install kubelet`

- 開始 13:27:22Z、終わり 13:27:44Z（22 秒）、rc 0。サンドボックスの中で流した
- `install-deps.sh` 7.4 秒、`install-pkgs.sh` 8.4 秒、`install.sh` 4.0 秒。apt は何も入れていない（`history.log` の最後は 10-20 06:14Z）。CNI の plugins は展開していない
- kubelet の起動 13:27:44Z

## 4. 確認（13:28:34Z）

| # | 確認 | 結果 |
|---|---|---|
| 1、2 | Node、バイナリ | v1.36.5。`kubelet-v1.36.5`、`kubectl-v1.36.5`、`crictl-v1.36.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` のまま |
| 3 | iscsid | 6334、10-19 09:04:34Z のまま |
| 4 | iSCSI のセッション | 同じ 2 つ（sid・portal・target）。古いセッションは無い |
| 5 | エンジン | 同じ 2 つ、同じ起動の時刻。`older-than-iscsid` は 0 のまま |
| 6 | Longhorn | ボリューム・instance-manager はベースラインと同じ。Longhorn の node 4 つとも Ready。カーネルの I/O エラーなし |
| 7 | Pod の再起動 | **差分なし**（37 個） |
| 10 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。oeilvert の error 0、`no route` は 8 台とも増えていない（段 6 と同じく oeilvert は 0） |
| 11 | kubelet のログ | 起動の直後の `Error getting the current node from lister`、crio の factory、eviction manager の imagefs だけ |
| 12 | 監視 | FAIL は増えていない |
| 14 | 告知していた LoadBalancer | gated-v6 は 404 を返す。告知の移動なし |
| 9、13、15 | ほか | leader election の再起動なし、CSR なし |

## 5. 監視の FAIL と、その原因

なし。

## 6. 次の 1 台へ進む条件

すべて合格。

## 7. 手順書との差、気づいたこと

- なし
