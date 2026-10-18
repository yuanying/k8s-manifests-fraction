# duchamp の段 C の作業記録

duchamp（192.168.1.135）の containerd を、Ubuntu の `containerd` 2.2.1 から Docker の `containerd.io` 2.3.6 に置き換えた記録。手順は `../../runbook-stage-c.md`（以下 runbook）。
時刻は UTC。段 C の 2 台目。1 台目は `chirico.md`、クラスタ全体のベースラインと戻すための控えは `baseline.md`。

## 1. 事前の読み取り（2026-10-18 07:50Z〜）

### 1.1 クラスタ（runbook §2.3、§3.12）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。2.3.x のノード: chirico（`containerd://2.3.6`）、2.2.1 のノード: ほかの 7 台 |
| etcd、VIP | 3/3 healthy、リーダー: 192.168.1.112、raft term 23111、raft index: 1402224058〜059（そろっている）。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached（ベースラインのもの）: `myao/myao`、`homegallery/cg-data` |
| Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit`: `5`、`replica-auto-balance`: `least-effort`、`node-drain-policy`: `block-if-contains-last-replica`（`replica-replenishment-wait-interval` は `6000`、`default-data-locality` は `best-effort`） |
| controller-manager と scheduler の置き場所 | （worker なので無し） |
| `auth can-i delete pods -A`（`fraction-auditor`） | `no` |
| `containerd.io` の版（runbook §1.6） | 2.3 系の最新は 2.3.6-1 のまま（1 台目と同じ版を入れる） |

### 1.2 対象のノード（runbook §3.3）

| 項目 | 値 |
|---|---|
| Node | Ready、`containerd://2.2.1`、6.8.0-147-generic、起動 2026-10-17 15:33:46Z |
| `containerd --version` / `runc --version` | 2.2.1 / 1.3.4-0ubuntu1~24.04.1 |
| `/etc/containerd/config.toml` | `version = 3`、md5: `665fb78e3b80c49c14575c184b3c5bcf` |
| 控え（`/root/k8u-stage-c/`） | config.toml.before（md5 同じ）、`containerd_2.2.1-0ubuntu1~24.04.3_amd64.deb`、`runc_1.3.4-0ubuntu1~24.04.1_amd64.deb`（sha256 は `baseline.md` と同じ） |
| `apt-cache policy containerd containerd.io runc` | `containerd` と `runc` は Ubuntu の版で入っている。`containerd.io` は候補なし（`1.6.8-1 -1`、`/var/lib/dpkg/status` だけ） |
| `dpkg -l containerd.io docker-ce` | `containerd.io` 1.6.8-1 が `rc`。`docker-ce` は無い |
| `/etc/apt/sources.list.d/`、`preferences.d/`、`keyrings/` | `docker.list.disabled-20261017`、`ubuntu.sources` / `ubuntu-pro-esm-apps`、`ubuntu-pro-esm-infra` / `docker.gpg`（runbook のとおり） |
| 当たっていない Ubuntu の更新 | 0 |
| イメージの数（`crictl images -q`） | 239 |
| `systemctl --failed` | 空 |
| Pod と再起動回数（控え） | 42 個、すべて Running。コントローラを持たない Pod は無い |
| ターボ（冷却ファンの故障による運用。Wiki の duchamp の節） | `/sys/devices/system/cpu/intel_pstate/no_turbo` が `1`。Package 62℃。止める設定を永続化するもの（unit、tmpfiles、cron）は無い |
| 最後の replica を持つボリューム（runbook §2.6） | **無い**。replica 1 のボリュームの置き場所は、prometheus-0 が chirico、prometheus-1 と MinIO の 4 つが oeilvert（chirico の後に data locality で動いたまま）。duchamp の replica は 13 個（どれも 2 replica のボリュームの片方、または以前から stopped のもの）。`minio-1` の Pod は duchamp で動いているが、replica は oeilvert にある |

最後の replica が無いので、duchamp の drain では `node-drain-policy` を変えず、Prometheus も止めない（runbook §2.6 の表の pablo・braque と同じ扱い）。`concurrent-replica-rebuild-per-node-limit` と `replica-auto-balance` だけを切り替える。

## 2. 入れ替え（runbook §3.4〜§3.7）

### 2.1 リポジトリ、鍵、pin（07:51:38Z〜07:51:52Z）

- 鍵の fingerprint: `9DC858229FC7DD38854AE2D88D81803C0EBFCD88`（一致）
- `docker.sources` の `Architectures` は `amd64`
- `apt-cache policy containerd.io` の Candidate と優先度: `2.3.6-1~ubuntu.24.04~noble`。2.3 系の行（2.3.3-1〜2.3.6-1）が 1001、2.4 系の行は 500

### 2.2 `containerd.io` を入れる（07:52:09Z〜07:52:23Z）

- `apt-get install -s` の結果（Remv / Inst）: runbook §3.5 の 1 と同じ（`0 upgraded, 1 newly installed, 2 to remove`、Remv `containerd`・`runc`、Inst `containerd.io` 2.3.6）
- 入れた版: `containerd.io=2.3.6-1~ubuntu.24.04~noble`（版を指定した）。rc 0
- conffile の扱い: chirico と同じく `Using current old file as you requested` は出ず、手元の config が残った（md5 が控えと同じ）
- needrestart が `systemctl restart containerd.service` を流し、`No containers need to be restarted.` と出した

### 2.3 ノードでの確認（runbook §3.6）

| 項目 | 結果 |
|---|---|
| `containerd --version` / `runc --version` | `containerd containerd v2.3.6 ee2735368117d2eb259779949d5e75cdafec9761` / `runc version 1.5.1` |
| config の先頭と md5（控えと同じか） | `version = 3`、`665fb78e3b80c49c14575c184b3c5bcf`（同じ） |
| `containerd config dump`（version、SystemdCgroup、sandbox） | `version = 4`、`SystemdCgroup = true`、`sandbox = 'registry.k8s.io/pause:3.10.1'` |
| journal の error / warning（§8.1 のもの以外） | 無い。`Configuration migrated from version 3` と `failed check for fsverity support` が containerd の起動ごと（07:52:17Z、07:52:21Z）に出た。`unmarshal sandbox spec` は 96 行 |
| `ctr deprecations list` | 空 |
| `crictl info` / イメージの数（入れる前 → 後） | 応答する / 239 → 239 |
| `apt-cache policy containerd.io` | Installed と Candidate が 2.3.6-1、優先度 1001 |

### 2.4 kubelet の再起動（07:52:37Z。runbook §3.7）

- Node と CONTAINER-RUNTIME: Ready、`containerd://2.3.6`（40 秒後に確認）
- Pod の再起動回数（控えとの差）: 42 個とも Running、再起動回数は変わらない（`diff` が同じ）
- kubelet の journal: 再起動の前の kubelet が、containerd の再起動の間（07:52:17〜22Z）に `containerd.sock: connect: no such file or directory` と `server is not initialized yet` を出した（dpkg と needrestart が containerd を再起動した間のもの）。再起動の後の kubelet は、起動の直後に `Registration of the crio container factory failed` と `Image garbage collection failed once` を出しただけで、07:52:40Z 以降の E の行は 0
- 監視（runbook §2.4）の FAIL: 無い

## 3. drain（runbook §3.8）

## 4. 再起動（runbook §3.9）

## 5. 再起動の後の確認（runbook §3.10）

## 6. uncordon と後始末（runbook §3.11）

## 7. 次の 1 台へ進む条件（runbook §3.12）

## 8. 手順書との差、気づいたこと

- §2.6: chirico の後の読み直しで、duchamp には最後の replica が無かった。runbook §3.8 の 2 の「chirico、duchamp、oeilvert だけ」は 2026-10-18 の表に基づくもので、読み直した表に従う
