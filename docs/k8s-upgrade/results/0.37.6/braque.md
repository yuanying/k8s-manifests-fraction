# porkadot 0.37.6: braque（192.168.1.131）

runbook §5 の記録。時刻は UTC。出力はタスクディレクトリの `notes/0-37-6/braque/`。

- `node-step.sh before` の後、`install kubelet --node braque`: 11:33:14Z〜11:33:44Z、rc 0。SSH 先は `yuanying@192.168.1.131` だけ。流す前と後で `git status --short assets porkadot.yaml` は空
- 約 1 分後に `node-step.sh after`、Longhorn のボリューム、events、監視を見た

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | v1.37.2、Ready |
| 2 | バイナリ | `kubelet-v1.37.2`、`kubectl-v1.37.2`。crictl・etcdctl・etcdutl・CNI は変わらない。node-state の差は `bin` と kubelet（MainPID 541944 → 1727331）だけ |
| 3 | iscsid | MainPID 271131、ActiveEnterTimestamp（10-21 06:23:32Z）とも前と同じ |
| 4・5 | iSCSI のセッション、エンジン | セッション 0（Longhorn のノードでない） |
| 6 | Longhorn | 17 本とも attached healthy のまま（アタッチ先も同じ） |
| 7 | Pod の再起動 | 全体の Pod の名前・UID・restartCount が前と同じ（`node-step.sh` の「その台の Pod」は、worker のノード名を IP で引いていて空だった。全体の比較に含まれる） |
| 8 | `FailedMount` | その台の Pod は Running / Completed だけ。`FailedMount`・`FailedAttach`・`BackOff`・`Killing`・`Unhealthy` の event は無い |
| 11 | kubelet のログ | 起動の直後の `V2 checkpoint for memory manager is corrupt, falling back to V1`、`node "braque" not found`（2 行）、`Skipping pod synchronization`（2 行）、`eviction manager: failed to check if we have separate container filesystem` が 1 行ずつ。`Effective KubeletConfiguration` が 1 行。ほかに `Failed to read data from checkpoint` と、pablo と同じ古い kubelet の `Failed to update lease`（11:33:4xZ）が 1 行。**cAdvisor・ZFS の error は無い**。fs のバックアップの CronJob の時間帯の外。braque の監視（`dns2-192.168.1.131.log`）も FAIL 0 |
| 14 | 監視 | VIP・各 apiserver・gated v4/v6、2 か所の DNS とも FAIL 0 |
| 20 | `containerRuntimeEndpoint` | `kubelet.service` にフラグが無い、`config.yaml` の 20 行目にある、`crictl version` が `containerd v2.3.6`、`deprecated` の行が無い |
