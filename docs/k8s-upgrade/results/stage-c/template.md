# <ノード> の段 C の作業記録

<ノード>（192.168.1.XX）の containerd を、Ubuntu の `containerd` 2.2.1 から Docker の `containerd.io` 2.3.x に置き換えた記録。手順は `../../runbook-stage-c.md`（以下 runbook）。
時刻は UTC。<何台目か。前の台の記録へのリンク>

この雛形を `<ノード>.md`（control-plane は `192.168.1.11N.md`）として写して使う。当てはまらない節は「なし」と書いて残す。

## 1. 事前の読み取り（YYYY-MM-DD hh:mmZ〜）

### 1.1 クラスタ（runbook §2.3、§3.12）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。2.3.x のノード: 、2.2.1 のノード: |
| etcd、VIP | 3/3 healthy、リーダー: 、raft index: 。`/readyz`: |
| Running / Completed 以外の Pod | |
| Longhorn | attached healthy N、detached（ベースラインのもの）: |
| Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit`: 、`replica-auto-balance`: 、`node-drain-policy`: |
| controller-manager と scheduler の置き場所 | （control-plane の作業のとき） |

### 1.2 対象のノード（runbook §3.3）

| 項目 | 値 |
|---|---|
| Node | Ready、`containerd://2.2.1` |
| `containerd --version` / `runc --version` | |
| `/etc/containerd/config.toml` | `version = 3`、md5: |
| 控え（`/root/k8u-stage-c/`） | config.toml.before（md5: ）、deb と sha256: |
| `apt-cache policy containerd containerd.io runc` | |
| `/etc/apt/sources.list.d/`、`preferences.d/`、`keyrings/` | |
| 当たっていない Ubuntu の更新 | |
| Pod と再起動回数（控え） | |
| 最後の replica を持つボリューム（runbook §2.6） | |

## 2. 入れ替え（runbook §3.4〜§3.7。oeilvert は §4.2）

### 2.1 リポジトリ、鍵、pin（hh:mm:ssZ）

- 鍵の fingerprint:
- `apt-cache policy containerd.io` の Candidate と優先度:

### 2.2 `containerd.io` を入れる（hh:mm:ssZ）

- `apt-get install -s` の結果（Remv / Inst）:
- 入れた版:
- conffile の扱い（`Using current old file as you requested` が出たか）:

### 2.3 ノードでの確認（runbook §3.6）

| 項目 | 結果 |
|---|---|
| `containerd --version` / `runc --version` | |
| config の先頭と md5（控えと同じか） | |
| `containerd config dump`（version、SystemdCgroup、sandbox） | |
| journal の error / warning（§8.1 のもの以外） | |
| `ctr deprecations list` | |
| `crictl info` / イメージの数（入れる前 → 後） | |

### 2.4 kubelet の再起動（hh:mm:ssZ。runbook §3.7）

- Node と CONTAINER-RUNTIME:
- Pod の再起動回数（控えとの差）:
- 監視（runbook §2.4）の FAIL:

## 3. drain（runbook §3.8。control-plane は §5.2 の 3〜4）

- トークンの発行:
- Longhorn の設定を変えた時刻と値:
- 止めた workload と、detach を確かめた時刻:
- cordon / drain の開始と終わり:
- 止まった Pod、`--force` の要否:
- control-plane: 移した Pod と、代わりの Pod の置き場所・Running になった時刻。etcd のリーダーと `move-leader` の結果

## 4. 再起動（runbook §3.9）

- 再起動の時刻、Node が Ready に戻った時刻:
- 監視（runbook §2.4）の FAIL（VIP / LB）:

## 5. 再起動の後の確認（runbook §3.10。oeilvert は §4.3、control-plane は §5.2 の 10）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | |
| 2 | cnidaria の Pod（CrashLoopBackOff の回数、Ready になった時刻、`--previous` のログ） | |
| 3 | `verify-nodes.sh` | |
| 4 | DaemonSet の Pod（speaker の CrashLoopBackOff の回数） | |
| 5 | ストリーミング | |
| 6 | iptables | |
| 7 | ディスク、ZFS | |
| 8 | iSCSI | |
| 9 | DNS | |
| 10 | 失敗している unit | |
| 11 | apt（Candidate、`full-upgrade` の模擬） | |
| 12 | `unmarshal sandbox spec` の数 | |
| — | control-plane: etcd、apiserver、`/readyz` | |
| — | oeilvert: Docker、devbox、`mosh.fraction.jp` | |

## 6. uncordon と後始末（runbook §3.11）

- uncordon の時刻:
- 戻した workload（Prometheus / MinIO）と、Running・healthy を確かめた時刻:
- Longhorn の設定を戻した時刻（drain から何分）と値:
- 再同期が終わった時刻:
- Running / Completed 以外の Pod:
- `netcheck.sh`、`check-apps.sh`:
- トークンの破棄:

## 7. 手順書との差、気づいたこと

-
