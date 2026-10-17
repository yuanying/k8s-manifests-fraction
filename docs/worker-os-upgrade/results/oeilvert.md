# oeilvert の作業記録

oeilvert（192.168.1.82）を Ubuntu 22.04.4 → 24.04.5、containerd 1.6.8（Docker の `containerd.io`）→ 2.2.1（Ubuntu の `containerd`）、docker-ce 20.10.18（focal 版）→ Ubuntu の `docker.io` にした記録。手順は `../runbook.md`（以下 runbook）。
3 台目で、前の 2 台の記録は `chirico.md` と `duchamp.md`。時刻は UTC（oeilvert のホストの時刻も UTC）。

## 1. 事前の読み取り（2026-10-17 22:13Z〜22:16Z）

### 1.1 kubeconfig と cnidaria-cni-dev（runbook §1.2、§2.2）

- `kubectl --context fraction auth can-i delete pods -A`: `no`
- cnidaria-cni-dev の STATE.md: 走っている作業単位は無い
- `ds/cnidaria`: `ghcr.io/yuanying/cnidaria-cni:v0.1.1`、8/8 が更新済みで Ready

### 1.2 クラスタのベースライン（runbook §2.3）

duchamp の作業後（`duchamp.md` §6、§7）と同じだった。

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node | 8 台 Ready。control-plane 3 台、chirico、duchamp は 24.04.5 / `containerd://2.2.1`。braque、oeilvert、pablo は 22.04 系 / 5.15 / `containerd://1.6.8` |
| 2 | Running / Completed 以外の Pod | 0 個 |
| 3 | Longhorn | attached healthy 23、detached unknown 2（`myao/myao`、`homegallery/cg-data`） |
| 4 | etcd、VIP | 3/3 healthy（leader は 192.168.1.112、raft index は 3 台でほぼ同じ）。`https://192.168.1.101:6443/readyz` は `ok` |
| 5 | cnidaria | `verify-nodes.sh` は 64 PASS、FAIL 0。cnidaria のログは errors 0、applied-nftables 1260。`check-apps.sh`: nodes 8/8、Running でない Pod 0、IP の重複 0、Longhorn は 3 と同じ、hedgedoc の db-postgresql-0 は Running（oeilvert）、192.168.1.200 と v6 の LB は 404、VIP の `/version` は 200 |
| 6 | `cluster-dns.service` | oeilvert は修正済みの版（`BindsTo=` / `Wants=` / `WantedBy=` に `porka-dummy01` と `systemd-networkd`） |

Longhorn の設定（変える前の値）:

| 設定 | 値 |
|---|---|
| `concurrent-replica-rebuild-per-node-limit` | `5` |
| `replica-auto-balance` | `least-effort` |
| `node-drain-policy` | `block-if-contains-last-replica` |
| `replica-replenishment-wait-interval` | `6000` |

`minio/minio` の StatefulSet は 4/4（minio-0 は oeilvert、minio-1 は pablo、minio-2 と minio-3 は chirico）。PDB は maxUnavailable 1。
Prometheus リソース `monitoring/kube-prometheus` の `spec.replicas` は `2`（oeilvert では変えない）。

### 1.3 oeilvert の状態（runbook §3.3 の 1）

| 項目 | 値 |
|---|---|
| Node | Ready、`containerd://1.6.8`、kernel 5.15.0-198-generic |
| OS | Ubuntu 22.04.4 LTS |
| containerd | `containerd.io` 1.6.8-1。`/var/cache/apt/archives/` に deb は無い |
| Docker | docker-ce、docker-ce-cli、docker-ce-rootless-extras（5:20.10.18~3-0~ubuntu-focal）、docker-scan-plugin（0.17.0~ubuntu-focal）。Storage Driver overlay2、Cgroup Driver systemd、Docker Root Dir `/var/lib/docker`。コンテナ 3 つ（`devbox` が動いていて、ほか 2 つは 3〜4 年前に止まったもの）、イメージ 1212 個（`docker images -q` で 590 行）、名前の無いボリューム 1 つ |
| `/etc/docker/daemon.json` | `ipv6: true`、`fixed-cidr-v6: fde0:17ad:84c5:82::/64` |
| `/etc/containerd/config.toml` | `version = 2`、`sandbox_image = "k8s.gcr.io/pause:3.2"`、`SystemdCgroup = true`、`max_conf_num = 1`、`docker.io` のミラー（調査 §1 のとおり、当時の既定値） |
| apt の hold | 無い |
| `/etc/apt/sources.list.d/` | 空（Docker のリポジトリは無い） |
| 更新できるパッケージ | 93 個 |
| `/var/run/reboot-required` | 無い |
| uptime | 9 日 |
| ディスク | `/`（`/dev/nvme0n1p2`、457G）の空きは 83G（調査の時点の 98G から減った）。`/var/lib/longhorn`（zvol `/dev/zd0`、251G、automount）の空き 207G、`/var/lib/longhorn2`（`/dev/sdb1`、1.8T）の空き 1.6T |
| メモリ | 60G |
| ZFS | `tank` は ONLINE（`all pools are healthy`）。`tank/export` を `/export`、`tank/longhorn` が zvol |
| NFS のホストマウント | `home-yuanying-shared-data.automount`、`-h.automount`、`home-yuanying-shared-nfs.mount`（braque）が active |
| `/etc/systemd/resolved.conf` | `DNS=192.168.0.1`、`Domains=default.svc.cluster.local svc.cluster.local cluster.local` |
| sshd_config | `PasswordAuthentication no` の行は無い（chirico、duchamp と違う） |
| `irqbalance` | 1.8.0-1ubuntu0.2 |
| libvirt、qemu | `libvirt-daemon` 8.0.0-1ubuntu7.21、`qemu-system-x86` 1:6.2+dfsg-2ubuntu6.30。VM は 0 台。`libvirtd` は enabled |
| `netfilter-persistent` | enabled |
| iptables | FORWARD の policy は ACCEPT。v4・v6 とも `CNIDARIA-FWD` へのジャンプが先頭 |
| cnidaria の経路 | proto 200 は v4・v6 とも 7 本 |
| `journalctl -b 0` の `ordering cycle` | 0 |
| iSCSI | セッションは 13 個（すべて oeilvert の instance-manager の 10.244.7.230 へ） |
| `systemctl --failed` | 無い |
| `ubuntu-release-upgrader-core` | 1:22.04.19、`Prompt=lts` |
| 自動再起動 | `52local-reboot.conf` で 04:00（ホストの時刻は UTC） |

oeilvert に載っている Pod は 69 個（DaemonSet と Completed の Job を含む）。コントローラを持たない Pod は無い。
Longhorn の replica は oeilvert に 20 個（running 19、stopped 1）で、すべて `/var/lib/longhorn2` にある。`/var/lib/longhorn`（zvol）には replica が無い。
最後の replica を oeilvert に持つボリュームは `minio/export-minio-0`〜`3` の 4 つだけ（runbook §2.4 の表と同じ）。

### 1.4 控えた設定（runbook §3.3 の 2）

タスクディレクトリの `notes/hosts/oeilvert-20261017/` に保存した（リポジトリには入れない）:
`containerd-config.toml`、`etc-apt-sources.tar`、`kubelet.service.txt`、`cluster-dns.service`、`multipath.conf`、`sudoers`、`sudoers.d-ls.txt`、`sshd_config`、`netplan.tar`、`resolved.conf`、`docker-daemon.json`、`docker-before.txt`（`docker info`、`images`、`volume ls`、`ps -a`）、`mounts-units.txt`（fstab と mount・devbox の unit）、`iptables-persistent.txt`、`zfs.txt`、`iscsi-lsblk.txt`、`dpkg-selections.txt`、`dpkg-l.txt`、`ip.txt`、ベースラインの `verify-nodes.sh` と `check-apps.sh` の出力、oeilvert の Pod の一覧、Longhorn の volume と replica の JSON。

### 1.5 known_hosts（runbook §5.7）

porkadot を流す前に対処した。

- 作業端末の `~/.ssh/known_hosts` には、192.168.1.82 の行がハッシュした ED25519 の 1 行だけある。porkadot の checkout（4fa3a0f）で `SSHKit::Backend::Netssh::KnownHosts.new.search_for("192.168.1.82", {})` は空を返した（runbook の見込みどおり）
- known_hosts に ECDSA の行が無いので、runbook §5.7 の 2 の比べ方（`ssh-keygen -F <IP> -l` の ECDSA と比べる）はできない。代わりに次で確かめた:
  - ノードの `/etc/ssh/ssh_host_ed25519_key.pub` の fingerprint `SHA256:315eEqChMAVr5X3S7jjIgZAkXEXZVLPMbUljIUlhgUg` が known_hosts の ED25519 と一致する。この SSH の接続で `/etc/ssh/ssh_host_ecdsa_key.pub`（2020-06-10 のまま）を読んだ
  - その fingerprint `SHA256:myW+xW9TzZoUe9m9ReptZ0LljmlDVJDfKiePrwf7wc4` が、`ssh-keyscan -t ecdsa 192.168.1.82` の fingerprint と一致する
- 22:16Z: `known_hosts.bak-20261017-oeilvert` に控えを取り、ハッシュしない 1 行を足した（サンドボックスの外での実行をユーザーが承認）。足した後、sshkit は `ecdsa-sha2-nistp256` を返す
