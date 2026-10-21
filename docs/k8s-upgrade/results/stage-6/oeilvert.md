# oeilvert の段 6 の作業記録

oeilvert（192.168.1.82）の kubelet を、porkadot 0.35.0 の `install kubelet --node` で v1.35.9 に上げた記録。手順は `../../runbook-stage-6.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 3 台目。前は `braque.md`、次は `duchamp.md`。読み取りの出力はタスクディレクトリの `notes/stage-6/oeilvert/`。項目の形は `pablo.md` と同じで、違うところだけを書く。

## 1. 事前の読み取り（2026-10-21 07:11:42Z）

| 項目 | 結果 |
|---|---|
| クラスタ | 8 台 Ready（CP 3 台・pablo・braque が v1.35.9、ほかは v1.34.12）。etcd 3/3 healthy。`/readyz` は `ok`。Running / Completed 以外の Pod は 0。Longhorn 16 + 1 |
| 対象のノード | v1.34.12、`cgroup2fs`。CNI は `v1.9.1`。iscsid 6334、10-19 09:04:34Z（今日の unattended-upgrades では liblzma5 が上がらず、再起動していない。`baseline.md` §5） |
| iSCSI のセッション | 2（sid 3・4、どちらも 10.244.7.116 = 今の instance-manager `-d5905a9e…`）。`older-than-iscsid` 0 |
| アタッチされたボリューム | `fraction-agents/data-gmail-agent-0`（`pvc-aee2ec0e…`）、`data-wiki-keeper-0`（`pvc-092a74ed…`）。どちらも attached healthy |
| §8.12 の Pod | なし（Running の Pod のある PVC で当たるものは無い。oeilvert の上にある natsumi のバックアップの Succeeded の Pod は、Running の Pod が duchamp なので duchamp の前に消す） |
| ほか | Pod 41 個。告知している LoadBalancer は gated-v6（`::200`）。apt-daily-upgrade は inactive |

## 3. `install kubelet`

- 開始 07:12:01Z、終わり 07:12:23Z（22 秒）、rc 0。サンドボックスの中で流した
- `install-deps.sh` 5.1 秒、`install-pkgs.sh` 10.1 秒、`install.sh` 4.0 秒。apt は何も入れていない。CNI の plugins は展開していない
- kubelet の再起動 07:12:23Z

## 4. 確認（07:13:13Z）

| # | 確認 | 結果 |
|---|---|---|
| 1、2 | Node、バイナリ | v1.35.9。`kubelet-v1.35.9`、`kubectl-v1.35.9`、`crictl-v1.35.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` のまま |
| 3 | iscsid | 6334 のまま |
| 4 | iSCSI のセッション | 同じ sid 3・4、portal、target。古いセッションなし |
| 5 | エンジン | 同じボリューム、同じ起動の時刻。`older-than-iscsid` 0 のまま |
| 6 | Longhorn | 2 本とも attached healthy のまま。ボリューム・instance-manager の一覧は前と同じ。カーネルの I/O エラーなし |
| 7 | Pod の再起動 | **差分なし**（41 個） |
| 10 | cnidaria | 64 PASS、FAIL 0。error・`no route` の数は 8 台とも増えていない（段 5 の oeilvert と同じく、oeilvert では出ない） |
| 11 | kubelet のログ | 起動のときのものだけ。`FailedMount` なし |
| 14 | 告知していた LoadBalancer | `[::200]` の 80 は 404（応答あり）。告知は oeilvert のまま |
| 12、13、15 | 監視の FAIL、leader election、CSR | なし |

## 5. 監視の FAIL と、その原因

なし。

## 6. 次の 1 台へ進む条件

すべて合格。

## 7. 手順書との差、気づいたこと

- なし
