# duchamp の作業記録

duchamp（192.168.1.135）を Ubuntu 22.04 → 24.04.5、containerd 1.6.8（Docker の `containerd.io`）→ 2.2.1（Ubuntu の `containerd`）にした記録。手順は `../runbook.md`（以下 runbook）。
2 台目で、1 台目の記録は `chirico.md`。時刻は UTC。

## 1. 事前の読み取り（2026-10-17 13:41Z〜13:43Z）

### 1.1 kubeconfig と cnidaria-cni-dev（runbook §1.2、§2.2）

- `kubectl --context fraction auth can-i delete pods -A`: `no`
- cnidaria-cni-dev の STATE.md: 走っている作業単位は無い。本番の移行は済んでいる
- `ds/cnidaria`: `ghcr.io/yuanying/cnidaria-cni:v0.1.1`、8/8 が更新済みで Ready

### 1.2 クラスタのベースライン（runbook §2.3）

chirico の作業後（`chirico.md` §6、§7）と同じだった。

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node | 8 台 Ready。control-plane 3 台と chirico は 24.04.5 / `containerd://2.2.1`。braque、duchamp、oeilvert、pablo は 22.04 系 / 5.15 / `containerd://1.6.8` |
| 2 | Running / Completed 以外の Pod | 0 個 |
| 3 | Longhorn | attached healthy 23、detached unknown 2（`myao/myao`、`homegallery/cg-data`） |
| 4 | etcd、VIP | 3/3 healthy（leader は 192.168.1.112、raft index は 3 台でほぼ同じ）。`https://192.168.1.101:6443/readyz` は `ok` |
| 5 | cnidaria | `verify-nodes.sh` は 64 PASS、FAIL 0。cnidaria のログは errors 0、applied-nftables 553。`check-apps.sh`: nodes 8/8、Running でない Pod 0、IP の重複 0、Longhorn は 3 と同じ、hedgedoc の db-postgresql-0 は Running、192.168.1.200 と v6 の LB は 404、VIP の `/version` は 200 |
| 6 | `cluster-dns.service` | duchamp は修正前の版（`After=systemd-resolved.service` だけ） |

Longhorn の設定（変える前の値）:

| 設定 | 値 |
|---|---|
| `concurrent-replica-rebuild-per-node-limit` | `5` |
| `replica-auto-balance` | `least-effort` |
| `node-drain-policy` | `block-if-contains-last-replica` |
| `replica-replenishment-wait-interval` | `6000` |

Prometheus リソース `monitoring/kube-prometheus` の `spec.replicas` は `2`。

### 1.3 duchamp の状態（runbook §3.3 の 1）

| 項目 | 値 |
|---|---|
| Node | Ready、`containerd://1.6.8`、kernel 5.15.0-164-generic |
| OS | Ubuntu 22.04 LTS |
| containerd | `containerd.io` 1.6.8-1。apt の候補は Docker の 2.4.2-2~ubuntu.22.04~jammy（`docker.list` があるため）。Ubuntu の `containerd` の候補は 2.2.1-0ubuntu1~22.04.2 |
| `/etc/containerd/config.toml` | `version = 2`（9 行目）、`sandbox_image = "k8s.gcr.io/pause:3.6"`、`SystemdCgroup = true` |
| apt の hold | 無い |
| `/etc/apt/sources.list.d/` | `docker.list` だけ（chirico と同じ内容） |
| 更新できるパッケージ | 111 個 |
| `/var/run/reboot-required` | **既にある**（2026-10-06 から）。kernel は 5.15.0-164（起動中）と 5.15.0-198 |
| uptime | 280 日 |
| ディスク | `/`（`/dev/sda2`）は 228G で空き 119G。`/var/lib/longhorn`（`/dev/sdb`、1.8T）は空き 1.5T |
| メモリ | 31G |
| ネットワーク | `eno1` は DHCP で 192.168.1.135。`wlp0s20f3` は DOWN |
| sshd_config | 末尾に `PasswordAuthentication no`（chirico と同じ） |
| sudoers | `%sudo ALL=(ALL:ALL) NOPASSWD:ALL` |
| `irqbalance` | 1.8.0-1build1 が入っている |
| iSCSI | セッションは 7 つ（duchamp の instance-manager の 2 つの IP、10.244.5.12 と 10.244.5.250 へ） |
| `systemctl --failed` | `snap-lxd-40115.mount`（not-found）、`fwupd-refresh.service` |

duchamp に載っている Pod は 39 個（DaemonSet を含む）。コントローラを持たない Pod は無い。
Longhorn のボリュームで duchamp にアタッチしているのは `fs/data`、`open-webui/open-webui-pipelines`（どちらも replica 2）、`monitoring/prometheus-...-1`、`minio/export-minio-2`、`minio/export-minio-3`（replica 1）。

replica 1 のボリュームで replica が duchamp にあるのは `monitoring/prometheus-...-1` だけ（runbook §2.4 の表と同じ）。MinIO の 2 つは replica が oeilvert にあるので、drain で Pod が他のノードに移ってアタッチし直す。

duchamp の replica は running 9、stopped 2。stopped の 2 つは、`natsumi/natsumi-aki`（pvc-e224cffa、failedAt 2026-10-17T01:21:10Z、cnidaria 移行の時刻。chirico のベースラインと同じ）と pvc-7383ef3e（detached のボリューム）。

### 1.4 控えた設定（runbook §3.3 の 2）

タスクディレクトリの `notes/hosts/duchamp-20261017/` に保存した（リポジトリには入れない）:
`containerd-config.toml`、`etc-apt-sources.tar`、`kubelet.service.txt`、`cluster-dns.service`、`multipath.conf`、`sudoers`、`sudoers.d-ls.txt`、`sshd_config`、`netplan.tar`、`dpkg-selections.txt`、`dpkg-l.txt`、`ip.txt`、ベースラインの `verify-nodes.sh` と `check-apps.sh` の出力、Longhorn の volume と replica の JSON。

### 1.5 known_hosts（runbook §5.7）

porkadot を流す前に対処した。

- 作業端末の `~/.ssh/known_hosts` には duchamp の ED25519、RSA、ECDSA がハッシュした別々の行にある。porkadot の checkout（4fa3a0f）で `SSHKit::Backend::Netssh::KnownHosts.new.search_for("192.168.1.135", {})` は `ssh-rsa` だけを返した（runbook の見込みどおり）
- ノードの `/etc/ssh/ssh_host_ecdsa_key.pub`（2022-09-16 のまま）の fingerprint `SHA256:c6bEx+8qxBP/Z1Ng64qvLN8ktlcpUEMAZqYI+mnD4ng` が、`ssh-keygen -F 192.168.1.135 -l` の ECDSA と一致することを確かめた
- 13:43Z: `known_hosts.bak-20261017-duchamp` に控えを取り、ハッシュしない 1 行を足した（サンドボックスの外での実行をユーザーが承認）。足した後、sshkit は `ecdsa-sha2-nistp256` を返す
