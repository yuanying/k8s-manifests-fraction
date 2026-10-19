# oeilvert の段 3 の作業記録

oeilvert（192.168.1.82）の kubelet を、porkadot 0.32.0 の `install kubelet --node` で v1.32.13 に上げた記録。手順は `../../runbook-stage-3.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 4 台目。前の台は `braque.md`。読み取りの出力はタスクディレクトリの `notes/stage-3/oeilvert/`。

## 1. 事前の読み取り（2026-10-19 23:45Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.32.13 のノード: control-plane 3 台、duchamp、pablo、braque、v1.31.14 のノード: oeilvert、chirico。SchedulingDisabled のノード: なし |
| etcd、VIP | 3/3 healthy、リーダー: 192.168.1.113。版: 3.5.34。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 |
| Longhorn | attached healthy 16、detached（ベースラインのもの）: `homegallery/cg-data` |
| Longhorn の設定 | `5`、`disabled`、`block-if-contains-last-replica` |
| controller-manager と scheduler の置き場所とリーダー | controller-manager .112（リーダー）・.113、scheduler .112（リーダー）・.111 |
| MetalLB の告知ノード | `duchamp.md` と同じ（gated-v6: **oeilvert**） |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.31.14、`containerd://2.3.6` |
| `/opt/bin` の向き先、CNI の印と 4 つのプラグイン | `kubelet-v1.31.14`、`kubectl-v1.31.14`、`crictl-v1.31.1`、`etcdctl-3.5.34`。印 `v1.4.1`、bridge・host-local・portmap v1.9.1、loopback v1.4.1 |
| iscsid（MainPID、ActiveEnterTimestamp） | 6334、09:04:34Z |
| iSCSI のセッション | 5（sid 3〜7、すべて `10.244.7.116:3260` = 今の instance-manager `-d5905a9e…` の IP） |
| `older-than-iscsid` のエンジン | なし（エンジン 5 つは 09:12:23Z〜09:17:27Z 起動） |
| アタッチされたボリュームと robustness | 5 つとも attached healthy: `fraction-agents/data-wiki-keeper-0`（pvc-092a74ed）、`natsumi/natsumi`（pvc-6b8f51fa）、`monitoring/prometheus-…-1`（pvc-99c35b80、replica 1）、`fraction-agents/data-gmail-agent-0`（pvc-aee2ec0e）、`natsumi/natsumi-aki`（pvc-e224cffa） |
| 同じ Longhorn の PVC を使う Completed / Succeeded の Pod（runbook §8.12） | **2 つ**: `natsumi/natsumi-backup-29874030-7m9fw`（PVC `natsumi`）、`natsumi/natsumi-backup-aki-29874030-tf9gj`（PVC `natsumi-aki`）。どちらも Job（CronJob の JST 05:30 の分）の Succeeded の Pod、PV は `driver.longhorn.io`。ほかに `aphrael/aphrael-2` の組が出るが NFS の PV なので当たらない。下の §1.3 で消した |
| Pod の控え | `pods-pre.tsv`、39 個（§1.3 の削除の後に取り直した） |
| そのノードが告知している LoadBalancer | `gated-system/gated-v6`（`::200`） |
| cnidaria のログの error の数（8 台） | .111 8、.112 7、.113 8、duchamp 6、pablo 7、braque 7（それぞれの `install kubelet` のもの）、oeilvert・chirico 0 |

### 1.3 Completed の Pod の削除（runbook §8.12。ユーザー承認）

- 2026-10-19 にユーザーが承認（chirico と oeilvert の `install kubelet` の前に、そのノードの Running の Pod と同じ PVC を使う Completed / Succeeded の Pod を `infra-admin` のトークンで消してよい。一覧を coordinator に知らせ、見込みと大きく違えば止める）
- 一覧（上の 2 つ）を coordinator に知らせ、見込み（natsumi・natsumi-aki のバックアップの Job の Pod）と同じことを確かめた
- 23:45Z に `infra-admin` の 1 時間のトークンを発行し、23:45:31Z に `kubectl -n natsumi delete pod natsumi-backup-29874030-7m9fw natsumi-backup-aki-29874030-tf9gj`（rc 0）。トークンのファイルは直後に消した
- Job（`natsumi-backup-29874030`、`natsumi-backup-aki-29874030`）は Complete のままで、Pod は作り直されない。読み直すと、oeilvert で当たるものは無くなった（`aphrael` の NFS のものだけ）

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`

- 開始 23:45:45Z、終わり 23:46:11Z、rc 0。サンドボックスの中で流した
- 出力の要点: SSHKit のコマンド 7 つがすべて `successful`。`install-pkgs.sh` 8.6 秒、`install.sh` 4.8 秒
- kubelet の再起動の時刻: 23:46:11Z

## 4. 確認（23:47Z〜）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.32.13、`containerd://2.3.6` |
| 2 | バイナリ、CNI | `kubelet-v1.32.13`、`kubectl-v1.32.13`、`crictl-v1.32.0`。CNI の印 `v1.9.1`、4 つとも v1.9.1 |
| 3 | iscsid | MainPID 6334、09:04:34Z。**前と同じ** |
| 4 | iSCSI のセッション | sid 3〜7 の 5 つが、同じ portal（`10.244.7.116:3260`）と target で残っている。**前と同じ** |
| 5 | エンジン | 5 つとも同じ起動の時刻で動いている |
| 6 | Longhorn | 5 つとも attached healthy のまま（remount の要求の時刻は前からのもので、新しいものは無い）。instance-manager `-d5905a9e…` は running、IP 10.244.7.116 のまま。Longhorn の node は Ready。カーネルの I/O エラーは無い。kubelet の再起動の間に duchamp・pablo と同じ Longhorn の node のイベント（`Node oeilvert is down: manager pod ... is not running`、2 つのディスクの `Waiting for disk ...`）が出た |
| 7 | Pod の再起動 | **差分は無い**（39 個とも名前・UID・restartCount が同じ。`homegallery/api`、prometheus-1、instance-manager、longhorn-manager、CSI も再起動していない） |
| 8 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。oeilvert の cnidaria は error を出さず、23:46:07Z（`systemd-networkd` の再起動）に info の `installed a route` を出しただけ。ほかの 7 台も error・info を出さなかった（段 1・段 2 の oeilvert と同じ） |
| 9 | kubelet のログ | 起動の直後の `Image garbage collection failed once`、`node "oeilvert" not found`、crio、eviction manager と、info の `Failed to trigger a manual run probe="Readiness"`（23:46:14Z〜18Z の 11 件）だけ。`FailedMount` は無い |
| 10 | 監視の FAIL | 無い |
| 11 | 告知していた LoadBalancer | gated-v6（`[...:ace::200]`）は 404（応答あり）。告知は移らない。speaker が 23:46:18Z に `::132`（.111）と `::134`（.112）を再び `serviceAnnounced` した（告知ノードは同じ） |
| 12 | CSR | 無い |

## 5. 監視の FAIL と、その原因

| 時刻 | VIP / LB | 原因 |
|---|---|---|
| — | — | 無かった |

## 6. 次の 1 台へ進む条件（runbook §5.5）

| 条件 | 結果 |
|---|---|
| §5.3 がすべて合格 | はい |
| 全 8 台の Node が Ready、SchedulingDisabled でない | はい。v1.32.13: 7 台、v1.31.14: chirico |
| etcd 3/3 healthy、VIP が応答する | はい |
| Running / Completed 以外の Pod がベースラインから増えていない | 0 のまま |
| Longhorn のボリュームが healthy | 16 attached healthy |
| Longhorn の設定がベースラインのまま | はい |
| `check-apps.sh` | ベースラインと同じ |

## 7. 手順書との差、気づいたこと

- runbook §8.12 の Completed の Pod が、runbook の作成の後のバックアップの CronJob（JST 05:30）で残っていた。ユーザーの承認を得て消した（§1.3）
- kubelet の info の `Failed to trigger a manual run probe="Readiness"` は runbook に無いが、起動の直後の数秒だけで、Pod の Ready は変わらない
