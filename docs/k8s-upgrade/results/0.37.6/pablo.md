# porkadot 0.37.6: pablo（192.168.1.134）

runbook §5 の記録。時刻は UTC。出力はタスクディレクトリの `notes/0-37-6/pablo/`。

- `node-step.sh before` の後、`install kubelet --node pablo`: 11:28:27Z〜11:28:47Z、rc 0。SSH 先は `yuanying@192.168.1.134` だけ。流す前と後で `git status --short assets porkadot.yaml` は空
- 約 1 分後に `node-step.sh after`、Longhorn のボリューム、events、監視を見た

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | v1.37.2、Ready |
| 2 | バイナリ | `kubelet-v1.37.2`、`kubectl-v1.37.2`。crictl・etcdctl・etcdutl・CNI は変わらない。node-state の差は `bin` と kubelet（MainPID 3509679 → 3100833）だけ |
| 3 | iscsid | MainPID 4114921、ActiveEnterTimestamp（10-21 06:40:42Z）とも前と同じ |
| 4・5 | iSCSI のセッション、エンジン | セッション 0、エンジン 0（前と同じ） |
| 6 | Longhorn | 17 本とも attached healthy のまま（アタッチ先も同じ） |
| 7 | Pod の再起動 | 全体の Pod の名前・UID・restartCount が前と同じ（`node-step.sh` の「その台の Pod」は、worker のノード名を IP で引いていて空だった。全体の比較に含まれる） |
| 8 | `FailedMount` | その台の Pod は Running / Completed だけ。`FailedMount`・`FailedAttach`・`BackOff`・`Killing`・`Unhealthy` の event は無い |
| 11 | kubelet のログ | 起動の直後の `V2 checkpoint for memory manager is corrupt, falling back to V1`、`node "pablo" not found`（2 行）、`Skipping pod synchronization`（2 行）、`eviction manager: failed to check if we have separate container filesystem` が 1 行ずつ。`Effective KubeletConfiguration` が 1 行。ほかに止まる前の古い kubelet の `Failed to update lease … connection reset by peer`（11:28:47Z、`dns` の addon の `systemd-networkd` の再起動の間。段 7 の pablo・braque にもある形）。VIP（.101）を告知している台だが、`probe.log` の VIP は途切れなかった。`no_turbo` 1 のまま（前からの値） |
| 14 | 監視 | VIP・各 apiserver・gated v4/v6、2 か所の DNS とも FAIL 0 |
| 20 | `containerRuntimeEndpoint` | `kubelet.service` にフラグが無い、`config.yaml` の 20 行目にある、`crictl version` が `containerd v2.3.6`、`deprecated` の行が無い |

## netcheck と NetworkPolicy の確認（§5.5、§1.8）

- 11:30:20Z に `infra-admin` のトークン（`--duration=1h`）を発行し、`/tmp/k8u-0376-admin-token`（モード 0600）に置いた
- ✋ `netcheck.sh`（cnidaria の手順書のもの。`RUNBOOK_ENV` は `notes/runbook-cnidaria-0-1-2/scripts/env-fraction.sh` で、`FRACTION_CHECKOUT` をこの worktree、`CNIDARIA_NFT_IMAGE` を `cnidaria-cni:v0.1.2` にした）: `up` 11:30:21〜24Z（8/8 Ready）、`run` が **`PASS 168 / 168, pods 8/8`**、`down` で `cnidaria-netcheck` を消した（11:30:40Z）
- ✋ `tools/npcheck.sh`: `up` 11:30:4xZ（server・allowed・denied とも 8/8）、`up` の後の `nft` が 8 台とも 9、`run` が **`OK 56, not OK 0`**、`down` の後の `nft` が 8 台とも 0。11:33:04Z に `k8u-npcheck`・`cnidaria-netcheck` とも NotFound
