# porkadot 0.37.6: duchamp（192.168.1.135）

runbook §5 の記録。時刻は UTC。出力はタスクディレクトリの `notes/0-37-6/duchamp/`。

- `node-step.sh before` の後、`install kubelet --node duchamp`: 11:36:24Z〜11:36:47Z、rc 0。SSH 先は `yuanying@192.168.1.135` だけ。流す前と後で `git status --short assets porkadot.yaml` は空
- 約 1 分後に `node-step.sh after`、Longhorn のボリューム、events、監視を見た

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | v1.37.2、Ready |
| 2 | バイナリ | `kubelet-v1.37.2`、`kubectl-v1.37.2`。crictl・etcdctl・etcdutl・CNI は変わらない。node-state の差は `bin` と kubelet（MainPID 1303（NRestarts 1） → 719754（NRestarts 0））だけ |
| 3 | iscsid | MainPID 3589、ActiveEnterTimestamp（10-27 23:33:23Z）とも前と同じ |
| 4・5 | iSCSI のセッション、エンジン | セッション 6（sid 1〜6、portal `10.244.5.89`）、6 本のエンジンの起動の時刻とも同じ。`older-than-iscsid` は `pvc-3a665d04` の 1 本のまま。古いセッションは無い |
| 6 | Longhorn | 17 本とも attached healthy のまま（アタッチ先も同じ） |
| 7 | Pod の再起動 | 全体の Pod の名前・UID・restartCount が前と同じ（`node-step.sh` の「その台の Pod」は、worker のノード名を IP で引いていて空だった。全体の比較に含まれる） |
| 8 | `FailedMount` | その台の Pod は Running / Completed だけ。`FailedMount`・`FailedAttach`・`BackOff`・`Killing`・`Unhealthy` の event は無い |
| 11 | kubelet のログ | 起動の直後の `V2 checkpoint for memory manager is corrupt, falling back to V1`、`node "duchamp" not found`（2 行）、`Skipping pod synchronization`（2 行）、`eviction manager: failed to check if we have separate container filesystem` が 1 行ずつ。`Effective KubeletConfiguration` が 1 行。CoreDNS の `-lsjhk` が載っている台。**CPU（§5.3 の 21）: `no_turbo` は前も後も 1、最高温度は 56℃ → 57℃** |
| 14 | 監視 | VIP・各 apiserver・gated v4/v6、2 か所の DNS とも FAIL 0 |
| 20 | `containerRuntimeEndpoint` | `kubelet.service` にフラグが無い、`config.yaml` の 20 行目にある、`crictl version` が `containerd v2.3.6`、`deprecated` の行が無い |
