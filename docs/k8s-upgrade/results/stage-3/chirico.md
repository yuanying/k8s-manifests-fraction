# chirico の段 3 の作業記録

chirico（192.168.1.83）の kubelet を、porkadot 0.32.0 の `install kubelet --node` で v1.32.13 に上げた記録。手順は `../../runbook-stage-3.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 5 台目（最後）。前の台は `oeilvert.md`。読み取りの出力はタスクディレクトリの `notes/stage-3/chirico/`。

## 1. 事前の読み取り（2026-10-19 23:48Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.32.13 のノード: chirico のほかの 7 台、v1.31.14 のノード: chirico。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー: 192.168.1.113。版: 3.5.34。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 |
| Longhorn | attached healthy 16、detached（ベースラインのもの）: `homegallery/cg-data` |
| Longhorn の設定 | `5`、`disabled`、`block-if-contains-last-replica` |
| controller-manager と scheduler の置き場所とリーダー | controller-manager .112（リーダー）・.113、scheduler .112（リーダー）・.111 |
| MetalLB の告知ノード | `duchamp.md` と同じ（gated-v4: **chirico**） |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.31.14、`containerd://2.3.6` |
| `/opt/bin` の向き先、CNI の印と 4 つのプラグイン | `kubelet-v1.31.14`、`kubectl-v1.31.14`、`crictl-v1.31.1`、`etcdctl-3.5.34`。印 `v1.4.1`、bridge・host-local・portmap v1.9.1、loopback v1.4.1 |
| iscsid（MainPID、ActiveEnterTimestamp） | 4447、09:17:30Z |
| iSCSI のセッション | 10（sid 1〜5、7〜11、すべて `10.244.8.216:3260` = 今の instance-manager `-4128231c…` の IP） |
| `older-than-iscsid` のエンジン | 1（`pvc-625c8825…` = `monitoring/prometheus-…-0`、09:17:28Z 起動。iscsid の起動の 2 秒前で、セッション（sid 1）がある。ベースライン・runbook §2.7 の注と同じ形なので、記録して進めた） |
| アタッチされたボリュームと robustness | 10 とも attached healthy（`homegallery/tumblr-data`・`ero-data`、`fs/data`・`h2`、`natsumi/natsumi-myao`、`monitoring/prometheus-…-0`（replica 1）、`fraction-agents` の 4 つ） |
| 同じ Longhorn の PVC を使う Completed / Succeeded の Pod（runbook §8.12） | **2 つ**: `fraction-agents/deep-researcher-backup-29874060-hg5hn`（PVC `data-deep-researcher-0`）、`natsumi/natsumi-backup-myao-29874030-bxqpd`（PVC `natsumi-myao`）。どちらも Job の Succeeded の Pod、PV は `driver.longhorn.io`。`aphrael/aphrael-2` の組は NFS なので当たらない。下の §1.3 で消した |
| Pod の控え | `pods-pre.tsv`、46 個（§1.3 の削除の後に取り直した） |
| そのノードが告知している LoadBalancer | `gated-system/gated-v4`（192.168.1.200） |
| cnidaria のログの error の数（8 台） | .111 8、.112 7、.113 8、duchamp 6、pablo 7、braque 7（それぞれの `install kubelet` のもの）、oeilvert・chirico 0 |

### 1.3 Completed の Pod の削除（runbook §8.12。ユーザー承認）

- 承認と手順は `oeilvert.md` §1.3 と同じ。一覧（上の 2 つ）を coordinator に知らせ、見込み（deep-researcher・natsumi-myao のバックアップの Job の Pod）と同じことを確かめた
- 23:48Z に `infra-admin` の 1 時間のトークンを発行し、23:48:36Z に 2 つを `kubectl delete pod`（rc 0）。トークンのファイルは直後に消した
- 読み直すと、chirico で当たるものは無くなった

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`

- 開始 23:48:49Z、終わり 23:49:13Z、rc 0。サンドボックスの中で流した
- 出力の要点: SSHKit のコマンド 7 つがすべて `successful`。`install-pkgs.sh` 8.3 秒、`install.sh` 4.1 秒
- kubelet の再起動の時刻: 23:49:13Z

## 4. 確認（23:50Z〜）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.32.13、`containerd://2.3.6` |
| 2 | バイナリ、CNI | `kubelet-v1.32.13`、`kubectl-v1.32.13`、`crictl-v1.32.0`。CNI の印 `v1.9.1`、4 つとも v1.9.1 |
| 3 | iscsid | MainPID 4447、09:17:30Z。**前と同じ** |
| 4 | iSCSI のセッション | 10 とも同じ sid・portal（`10.244.8.216:3260`）・target。**前と同じ** |
| 5 | エンジン | 10 とも同じ起動の時刻で動いている（`older-than-iscsid` は前と同じ 1 つで、増えていない） |
| 6 | Longhorn | 10 とも attached healthy のまま（remount の要求の時刻は前からのもので、新しいものは無い）。instance-manager `-4128231c…` は running、IP 10.244.8.216 のまま。Longhorn の node は Ready。カーネルの I/O エラーは無い |
| 7 | Pod の再起動 | **差分は無い**（46 個とも名前・UID・restartCount が同じ。prometheus-0、`fs` の Pod、instance-manager、longhorn-manager、CSI、CoreDNS の 1 つも再起動していない） |
| 8 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。chirico の cnidaria が `Reconciler error` を 8 件、23:49:10Z〜23:49:11Z に出した。ほかの 7 台は info を 2 件ずつ |
| 9 | kubelet のログ | 起動の直後の `node "chirico" not found`、crio、`Image garbage collection failed once`、eviction manager と、info の `Failed to trigger a manual run probe="Readiness"`（23:49:17Z〜24Z の 6 件）だけ。`FailedMount` は無い |
| 10 | 監視の FAIL | 無い（chirico が告知する gated-v4 も途切れなかった） |
| 11 | 告知していた LoadBalancer | gated-v4（192.168.1.200）は 404（応答あり）。告知は移らない。speaker が 23:49:17Z〜38Z に gated-v6（oeilvert）、`::133`（duchamp）、192.168.1.200（chirico）を再び `serviceAnnounced` した（告知ノードは同じ） |
| 12 | CSR | 無い |

## 5. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因 |
|---|---|---|
| — | — | 無かった |

## 6. 次へ進む条件（runbook §5.5）

| 条件 | 結果 |
|---|---|
| §5.3 がすべて合格 | はい |
| 全 8 台の Node が Ready、SchedulingDisabled でない | はい。8 台とも v1.32.13 |
| etcd 3/3 healthy、VIP が応答する | はい |
| Running / Completed 以外の Pod がベースラインから増えていない | 0 のまま |
| Longhorn のボリュームが healthy | 16 attached healthy |
| Longhorn の設定がベースラインのまま | はい |
| `check-apps.sh`、`netcheck.sh` | ベースラインと同じ。`netcheck.sh` は §6 で流した（`summary.md`） |

## 7. 手順書との差、気づいたこと

- アタッチの最も多い台（10 本）でも、Longhorn のボリューム・セッション・エンジンはそのままだった（runbook の冒頭の「dev で確かめていないもの」の 2 つ目）
