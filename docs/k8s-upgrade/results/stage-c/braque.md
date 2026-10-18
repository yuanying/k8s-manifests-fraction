# braque の段 C の作業記録

braque（192.168.1.131）の containerd を、Ubuntu の `containerd` 2.2.1 から Docker の `containerd.io` 2.3.6 に置き換えた記録。手順は `../../runbook-stage-c.md`（以下 runbook）。
時刻は UTC。段 C の 4 台目。1 台目は `chirico.md`、2 台目は `duchamp.md`、3 台目は `pablo.md`、クラスタ全体のベースラインと戻すための控えは `baseline.md`。

braque は ZFS（`tank1`）と NFS の nfsd（DaemonSet `nfsd/nfsd`）を持つ。taint `unstable.cloud/storage:NoSchedule` で DaemonSet 以外の Pod は載らず、Longhorn の node でもない。

## 1. 事前の読み取り（2026-10-18 09:16Z〜）

### 1.1 クラスタ（runbook §2.3、§3.12）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。2.3.x のノード: chirico、duchamp、pablo（`containerd://2.3.6`）、2.2.1 のノード: ほかの 5 台 |
| etcd、VIP | 3/3 healthy、リーダー: 192.168.1.112、raft term 23111、raft index: 1402255311（そろっている）。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached（ベースラインのもの）: `myao/myao`、`homegallery/cg-data` |
| Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit`: `5`、`replica-auto-balance`: `disabled`（pablo の作業からの扱い。段 C の間は止めたまま）、`node-drain-policy`: `block-if-contains-last-replica`（`replica-replenishment-wait-interval` は `6000`、`default-data-locality` は `best-effort`） |
| controller-manager と scheduler の置き場所 | （worker なので無し） |
| `auth can-i delete pods -A`（`fraction-auditor`） | `no` |
| `containerd.io` の版（runbook §1.6） | 2.3 系の最新は 2.3.6-1 のまま（1 台目と同じ版を入れる） |
| `verify-nodes.sh` | 64 PASS、FAIL 0。cnidaria のログの error 0 |
| `check-apps.sh` | pablo の後（`pablo.md` §6）の出力と同じ |
| `minio/minio`、Prometheus の `spec.replicas` | 4/4、2 |
| CronJob の schedule（runbook §2.5） | ベースラインから変わっていない |

### 1.2 対象のノード（runbook §3.3）

| 項目 | 値 |
|---|---|
| Node | Ready、`containerd://2.2.1`、6.8.0-147-generic、起動 2026-10-18 00:18:30Z。taint `unstable.cloud/storage:NoSchedule` |
| `containerd --version` / `runc --version` | 2.2.1 / 1.3.4-0ubuntu1~24.04.1 |
| `/etc/containerd/config.toml` | `version = 3`、md5: `665fb78e3b80c49c14575c184b3c5bcf` |
| 控え（`/root/k8u-stage-c/`） | config.toml.before（md5 同じ）、`containerd_2.2.1-0ubuntu1~24.04.3_amd64.deb`、`runc_1.3.4-0ubuntu1~24.04.1_amd64.deb`（sha256 は `baseline.md` と同じ） |
| `apt-cache policy containerd containerd.io runc` | `containerd` と `runc` は Ubuntu の版で入っている。`containerd.io` は候補なし（`1.6.8-1 -1`、`/var/lib/dpkg/status` だけ） |
| `dpkg -l containerd.io docker-ce` | `containerd.io` 1.6.8-1 が `rc`。`docker-ce` は無い |
| `/etc/apt/sources.list.d/`、`preferences.d/`、`keyrings/` | `docker.list.disabled-20261017`、`ubuntu.sources` / `ubuntu-pro-esm-apps`、`ubuntu-pro-esm-infra` / `docker.gpg`（runbook のとおり） |
| 当たっていない Ubuntu の更新 | 0 |
| イメージの数（`crictl images -q`） | 29 |
| `systemctl --failed` | `systemd-networkd-wait-online.service`（ベースラインと同じ） |
| ZFS、NFS | `zfs-import-cache.service` は enabled、`zpool status -x` は `all pools are healthy`、`/export` は `tank1/export`（zfs）。nfsd は `nfsd-vt5k2` が Running（イメージ `registry.k8s.io/e2e-test-images/volume/nfs:1.6.0`） |
| iSCSI | `iscsid.socket`・`multipathd` が active。セッションは無い |
| Pod と再起動回数（控え） | 5 個（`cnidaria`、`kube-proxy`、`node-exporter`、`smart-exporter` が再起動 2、`nfsd` が 0）。コントローラを持たない Pod は無い |
| 最後の replica を持つボリューム（runbook §2.6） | **無い**。braque は Longhorn の node ではなく、replica は 0。replica の数は chirico 15、duchamp 11、oeilvert 17、pablo 3（pablo の後と同じ） |
| MetalLB の告知 | braque に speaker の Pod は無い（ラベル `metallb=speaker` はあるが taint で載らない）。告知しているノード: VIP（`porkadot-kubernetes`）は pablo、gated-v4 は chirico、gated-v6 は oeilvert、`h2-sshd`・`natsumi-sshd-aki` は .112、`natsumi-sshd` は .111、`natsumi-sshd-myao` は duchamp |

最後の replica が無いので、`node-drain-policy` を変えず、workload も止めない。`replica-auto-balance` は既に `disabled` なので、切り替えるのは `concurrent-replica-rebuild-per-node-limit` だけ。

## 2. 入れ替え（runbook §3.4〜§3.7）

### 2.1 リポジトリ、鍵、pin（09:18:00Z〜09:18:36Z）

- 鍵の fingerprint: `9DC858229FC7DD38854AE2D88D81803C0EBFCD88`（一致）
- `docker.sources` の `Architectures` は `amd64`
- `apt-cache policy containerd.io` の Candidate と優先度: `2.3.6-1~ubuntu.24.04~noble`。2.3 系の行（2.3.3-1〜2.3.6-1）が 1001、2.4 系と 2.2 系の行は 500

### 2.2 `containerd.io` を入れる（09:18:48Z〜09:19:05Z）

- `apt-get install -s` の結果（Remv / Inst）: runbook §3.5 の 1 と同じ（`0 upgraded, 1 newly installed, 2 to remove`、Remv `containerd`・`runc`、Inst `containerd.io` 2.3.6）
- 入れた版: `containerd.io=2.3.6-1~ubuntu.24.04~noble`（版を指定した）。rc 0
- conffile の扱い: ほかの worker と同じく `Using current old file as you requested` は出ず、手元の config が残った（md5 が控えと同じ）
- needrestart が `systemctl restart containerd.service` を流し、`No containers need to be restarted.` と出した

### 2.3 ノードでの確認（runbook §3.6）

| 項目 | 結果 |
|---|---|
| `containerd --version` / `runc --version` | `containerd containerd v2.3.6 ee2735368117d2eb259779949d5e75cdafec9761` / `runc version 1.5.1` |
| config の先頭と md5（控えと同じか） | `version = 3`、`665fb78e3b80c49c14575c184b3c5bcf`（同じ） |
| `containerd config dump`（version、SystemdCgroup、sandbox） | `version = 4`、`SystemdCgroup = true`、`sandbox = 'registry.k8s.io/pause:3.10.1'` |
| journal の error / warning（§8.1 のもの以外） | 無い。`Configuration migrated from version 3` と `failed check for fsverity support` が containerd の起動ごと（09:18:58Z、09:19:01Z）に出た。`unmarshal sandbox spec` は 18 行 |
| `ctr deprecations list` | 空 |
| `crictl info` / イメージの数（入れる前 → 後） | 応答する / 29 → 29 |
| `apt-cache policy containerd.io` | Installed と Candidate が 2.3.6-1、優先度 1001 |
| Pod の再起動回数 | 控えと同じ |

### 2.4 Longhorn の設定の切り替えと kubelet の再起動（runbook §3.7）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 09:19:19 | ✋ `infra-admin` のトークンを発行（3h） | 作業端末の 600 のファイルに置いた。`auth can-i patch nodes` が yes |
| 09:19:24 | ✋ `concurrent-replica-rebuild-per-node-limit` を `0` | 直前の値は `5`。読み直して APPLIED true。`replica-auto-balance` は既に `disabled`、`node-drain-policy` は変えない |
| 09:19:31 | ✋ `systemctl restart kubelet` | |

- Node と CONTAINER-RUNTIME: Ready、`containerd://2.3.6`（40 秒後に確認）
- Pod の再起動回数（控えとの差）: 5 個とも同じ（`diff` が空）
- kubelet の journal: 再起動の前の kubelet が、containerd の再起動の間（09:18:58Z〜09:19:01Z）に `containerd.sock: connect: no such file or directory` を出した。再起動の後の kubelet は、起動の直後（09:19:31Z）に `Error getting the current node from lister`、`Image garbage collection failed once`、crio の factory の登録の失敗（info）、`kubelet_internal_checkpoint` が無い（info）を出しただけ
- Longhorn の replica は動かなかった（kubelet の再起動の前後で `replicas.longhorn.io` の一覧が同じ）
- 監視（runbook §2.4）の FAIL: 無い

## 3. drain（runbook §3.8）

（作業中）

## 4. 再起動（runbook §3.9）

（作業中）

## 5. 再起動の後の確認（runbook §3.10）

（作業中）

## 6. uncordon と後始末（runbook §3.11）

（作業中）

## 7. 次の 1 台へ進む条件（runbook §3.12）

（作業中）

## 8. 手順書との差、気づいたこと

（作業中）
