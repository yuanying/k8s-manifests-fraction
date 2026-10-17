# chirico の作業記録

chirico（192.168.1.83）を Ubuntu 22.04.1 → 24.04.5、containerd 1.6.8（Docker の `containerd.io`）→ 2.2.1（Ubuntu の `containerd`）にした記録。手順は `../runbook.md`（以下 runbook）。
時刻は UTC。

## 1. 事前の読み取り（2026-10-17 10:00Z 前後）

### 1.1 kubeconfig と cnidaria-cni-dev（runbook §1.2、§2.2）

- `kubectl --context fraction auth can-i delete pods -A`: `no`（`fraction-auditor` は read-only）
- cnidaria-cni-dev の STATE.md: 走っている作業単位は無い。本番の移行は済んでいて、残りは Longhorn の replica 1 つの再構築の完了確認だけ（下の 1.2 の natsumi-aki を参照）
- `ds/cnidaria`: `ghcr.io/yuanying/cnidaria-cni:v0.1.1`、8/8 が更新済みで Ready

### 1.2 クラスタのベースライン（runbook §2.3）

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node | 8 台 Ready。control-plane 3 台は 24.04.5 / 6.8.0-1065-raspi / containerd 2.2.1。worker 5 台は 22.04 系 / 5.15 / containerd 1.6.8（chirico は 22.04.1、5.15.0-164-generic） |
| 2 | Running / Completed 以外の Pod | 0 個 |
| 3 | Longhorn | attached healthy 23、detached unknown 2（`myao/myao`、`homegallery/cg-data`。使う Pod が無い） |
| 4 | etcd、VIP | 3/3 healthy（leader は 192.168.1.112、raft index は 3 台とも同じ）。`https://192.168.1.101:6443/readyz` は `ok` |
| 5 | cnidaria | `verify-nodes.sh` は 8 台とも全項目 PASS（64 PASS、FAIL 0）。`check-apps.sh`: nodes 8/8、Running でない Pod 0、IP の重複 0、Longhorn は 3 と同じ、hedgedoc の db-postgresql-0 は Running、192.168.1.200 と v6 の LB は 404（応答あり）、VIP の `/version` は 200 |
| 6 | `cluster-dns.service` | oeilvert だけが修正済みの版（`BindsTo=` / `Wants=` / `WantedBy=` に `porka-dummy01` と `systemd-networkd`）。braque、chirico、duchamp、pablo は修正前の版（`After=systemd-resolved.service` だけ） |

Longhorn の replica の配置で、ベースラインとして記録しておくもの:

- `natsumi/natsumi-aki`（pvc-e224cffa、replica 2）に、duchamp の replica が 1 つ stopped で残っている（failedAt 2026-10-17T01:21:10Z、cnidaria 移行の時刻）。chirico と oeilvert の 2 つは running で、ボリュームは healthy（調査 §3.4 と同じ）
- detached の 2 つ（myao、cg-data）は、chirico にも stopped の replica を持っている

Longhorn の設定（変える前の値。runbook §2.5、§2.4）:

| 設定 | 値 |
|---|---|
| `concurrent-replica-rebuild-per-node-limit` | `5` |
| `replica-auto-balance` | `least-effort` |
| `node-drain-policy` | `block-if-contains-last-replica` |
| `replica-replenishment-wait-interval` | `6000` |
| `current-longhorn-version` | `v1.11.2` |

### 1.3 chirico の状態（runbook §3.3 の 1）

| 項目 | 値 |
|---|---|
| Node | Ready、`containerd://1.6.8`、kernel 5.15.0-164-generic |
| OS | Ubuntu 22.04.1 LTS |
| containerd | `containerd.io` 1.6.8-1。apt の候補は Docker の 2.4.2-2~ubuntu.22.04~jammy（`docker.list` があるため）。Ubuntu の `containerd` の候補は 2.2.1-0ubuntu1~22.04.2 |
| `/etc/containerd/config.toml` | `version = 2`、`sandbox_image = "k8s.gcr.io/pause:3.6"`、`SystemdCgroup = true` |
| apt の hold | 無い |
| `/etc/apt/sources.list.d/` | `docker.list` だけ（`deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable`） |
| 更新できるパッケージ | 134 個（`apt list --upgradable`） |
| `/var/run/reboot-required` | **既にある**（2026-10-07 から。unattended-upgrades の libc6 と kernel 5.15.0-168〜198）。runbook §3.4 の 9 の再起動で解消する |
| kernel のパッケージ | 5.15.0-164（起動中）と 5.15.0-198 |
| uptime | 280 日（2026-01 から再起動していない） |
| ディスク | `/` は 457G で空き 322G。`/var/lib/longhorn`（`/dev/sda`、1.8T）は空き 1.3T |
| メモリ | 62G |
| ネットワーク | `eno1` は DHCP（v4 と v6）で 192.168.1.83。`wlp2s0` は DOWN |
| iSCSI | セッションは 7 つ（chirico の instance-manager の 2 つの IP へ。drain の後に消えることを確かめる） |
| `systemctl --failed` | `snap-core20-*.mount` 3 つと `snap-lxd-38800.mount`（not-found）、`fwupd-refresh.service`、`systemd-networkd-wait-online.service` |

chirico に載っている Pod は 54 個（DaemonSet を含む）。Longhorn のボリュームで chirico にアタッチしているのは `fs/data`、`open-webui/open-webui`、`monitoring/prometheus-...-0`（replica 1、replica も chirico）、`minio/export-minio-3`（replica 1、replica は oeilvert）。

replica 1 のボリュームで replica が chirico にあるのは `monitoring/prometheus-...-0` だけ（runbook §2.4 の表と同じ）。
`minio/export-minio-3` は Pod が chirico にあり、replica が oeilvert にあるので、drain で Pod が他のノードへ移ってアタッチし直す（MinIO の PDB は maxUnavailable 1）。

**コントローラを持たない Pod が 2 つある**: `default/dnsutils` と `tracing/dnsutils`（どちらも `registry.k8s.io/e2e-test-images/agnhost:2.39`、2026-01-12 に作成、ボリュームは service account のトークンだけ）。
`kubectl drain` は `--force` が無いとこれらで止まる。`--force` で drain すると消え、作り直されない。

### 1.4 控えた設定（runbook §3.3 の 2）

タスクディレクトリの `notes/hosts/chirico-20261017/` に保存した（リポジトリには入れない）:
`containerd-config.toml`、`etc-apt-sources.tar`（`sources.list` と `sources.list.d/`）、`kubelet.service.txt`、`cluster-dns.service`、`multipath.conf`、`sudoers`、`sudoers.d-ls.txt`、`netplan.tar`、`dpkg-selections.txt`、`dpkg-l.txt`、`ip.txt`。

## 2. cordon と drain（runbook §3.3）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 10:23:08 | ✋ `infra-admin` のトークンを発行（3h） | 作業端末の 600 のファイルに置いた。`auth can-i patch nodes` が yes |
| 10:23:45 | ✋ `cordon chirico` | Ready,SchedulingDisabled |
| 10:30:23 | ✋ `concurrent-replica-rebuild-per-node-limit` を `0`、`replica-auto-balance` を `disabled`（runbook §2.5） | 直前の値は `5` と `least-effort`。読み直して `0` と `disabled`、APPLIED true |
| 10:49:31 | ✋ `node-drain-policy` を `allow-if-replica-is-stopped`（runbook §2.4） | 読み直して APPLIED true |
| 10:53:37 | ✋ `drain chirico --ignore-daemonsets --delete-emptydir-data --force --timeout=20m` | 11:13:38 に時間切れ（rc 1）。下の 2.1 |

### 2.1 drain が instance-manager の PDB で止まった

DaemonSet 以外の Pod は 44 個とも退いた（`default/dnsutils` と `tracing/dnsutils` は `--force` で消えた）。残ったのは chirico の `instance-manager-4128231c…` の 1 つで、PDB を外されないまま 20 分の時間切れになった。

原因は runbook §2.4 の「注意」に書いたとおりだった。
`prometheus-kube-prometheus-0` は drain で退いた後に oeilvert で作り直され、replica 1 のボリューム pvc-625c8825（prometheus-0）を oeilvert でアタッチした。
replica は chirico にしか無いので、chirico の replica が running のまま残り、`allow-if-replica-is-stopped` でも drain は通らない。longhorn-manager のログ:

```
Node instance-manager-4128231ccb0c288ab5a27791d898e928 is marked unschedulable but removing chirico PDB is blocked: replica pvc-625c8825-4571-43d8-9119-c006a4a48399-r-222844ee has no pdb on another node
```

この時点で、ほかの Longhorn のボリュームはすべて healthy で、chirico 以外のノードでアタッチされていた。chirico にある 2 replica のボリュームの replica は running のままだったが、drain は止めていない。rebuild limit が 0 なので、新しい replica は作られていない。
