# braque の作業記録

braque（192.168.1.131）を Ubuntu 22.04 → 24.04.5、containerd 1.6.8（Docker の `containerd.io`）→ 2.2.1（Ubuntu の `containerd`）にした記録。手順は `../runbook.md`（以下 runbook）。
4 台目で、前の 3 台の記録は `chirico.md`、`duchamp.md`、`oeilvert.md`。時刻は UTC（braque のホストの時刻も UTC）。

## 1. 事前の読み取り（2026-10-17 23:31Z〜23:34Z）

### 1.1 kubeconfig、cnidaria-cni-dev、CronJob（runbook §1.2、§2.2、§2.1.1）

- `kubectl --context fraction auth can-i delete pods -A`: `no`
- cnidaria-cni-dev の STATE.md: 走っている作業単位は無い
- `ds/cnidaria`: `ghcr.io/yuanying/cnidaria-cni:v0.1.1`、8/8 が更新済みで Ready
- `kubectl get cronjobs -A` の schedule と timeZone は runbook §2.1.1 の表と同じ。`fraction-agents/deep-researcher-backup` は 21:00Z に初めて動き、5 秒で終わった
- braque を止めてよいのは JST 07:00〜14:30。§3.3 の cordon から §3.8 で NFS が戻るまでを 05:15Z までに終える

### 1.2 クラスタのベースライン（runbook §2.3）

oeilvert の作業後（`oeilvert.md` §6、§7）と同じだった。

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node | 8 台 Ready。control-plane 3 台、chirico、duchamp、oeilvert は 24.04.5 / `containerd://2.2.1`。braque と pablo は 22.04 / 5.15 / `containerd://1.6.8` |
| 2 | Running / Completed 以外の Pod | 0 個 |
| 3 | Longhorn | attached healthy 23、detached unknown 2（`myao/myao`、`homegallery/cg-data`）。replica は 45 個（chirico 17、duchamp 10、oeilvert 17、pablo 1） |
| 4 | etcd、VIP | 3/3 healthy（leader は 192.168.1.112、raft index は 3 台で同じ）。`https://192.168.1.101:6443/readyz` は `ok` |
| 5 | cnidaria | `verify-nodes.sh` は 64 PASS、FAIL 0。cnidaria のログは errors 0。`check-apps.sh`: nodes 8/8、Running でない Pod 0、IP の重複 0、Longhorn は 3 と同じ、hedgedoc の db-postgresql-0 は Running（chirico）、192.168.1.200 と v6 の LB は 404、VIP の `/version` は 200 |
| 6 | `cluster-dns.service` | braque は修正前の版（`After=systemd-resolved.service` だけ） |

Longhorn の設定（変える前の値）:

| 設定 | 値 |
|---|---|
| `concurrent-replica-rebuild-per-node-limit` | `5` |
| `replica-auto-balance` | `least-effort` |
| `node-drain-policy` | `block-if-contains-last-replica` |
| `replica-replenishment-wait-interval` | `6000` |

### 1.3 braque の状態（runbook §3.3 の 1）

| 項目 | 値 |
|---|---|
| Node | Ready、`containerd://1.6.8`、kernel 5.15.0-164-generic。taint `unstable.cloud/storage:NoSchedule`。ラベル `metallb=speaker`、`nfsd.unstable.cloud/storage=yes`、`tgtd.unstable.cloud/storage`、`node-role.kubernetes.io/lapin` |
| OS | Ubuntu 22.04 LTS |
| containerd | `containerd.io` 1.6.8-1。apt の候補は Docker の 2.4.2-2~ubuntu.22.04~jammy（`docker.list` があるため）。Ubuntu の `containerd` の候補は 2.2.1-0ubuntu1~22.04.2。apt のキャッシュに deb は無い |
| `/etc/containerd/config.toml` | `version = 2` |
| apt の hold | 無い |
| `/etc/apt/sources.list.d/` | `docker.list` だけ |
| `/var/run/reboot-required` | **既にある**（kernel 5.15.0-168〜 と libc6 の更新から） |
| uptime | 280 日 |
| ディスク | `/`（`/dev/sda2`）は 109G で空き 88G |
| メモリ | 15G |
| ZFS | `tank1`（raidz1、7.3T×3）は ONLINE、2026-10-11 の scrub はエラー 0。vdev は `/dev/disk/by-partlabel/zfs-tank1-{0,1,2}`。`tank1/export` を `/export`（5.1T 使用、9.4T 空き）。`zfs-import-cache`、`zfs-mount`、`zfs.target`、`zfs-zed` は enabled（`zfs-import-scan` は disabled）。`zfsutils-linux` 2.1.5-1ubuntu6~22.04.7 |
| NFS サーバー | ホストには `nfs-kernel-server` が無い。DaemonSet `nfsd/nfsd`（`gcr.io/google_containers/volume-nfs:0.8`、hostNetwork、privileged、`/export` を hostPath）。ホストで `nfsd` と `lockd` のモジュールが読み込まれている |
| sshd_config | 末尾に `PasswordAuthentication no`（chirico、duchamp と同じ） |
| `irqbalance` | 1.8.0-1build1 |
| `ufw` | 0.36.1-4build1（`iptables-persistent` は無い） |
| iptables | FORWARD の policy は ACCEPT。v4・v6 とも `CNIDARIA-FWD` へのジャンプが先頭 |
| cnidaria の経路 | proto 200 は v4・v6 とも 7 本 |
| iSCSI | セッションは無い |
| multipath | `/etc/multipath.conf` は addon の版。マップは無い |
| `systemctl --failed` | `fwupd-refresh.service`、`systemd-networkd-wait-online.service`（調査 §2.1 と同じ） |

手元で変わっている conffile: dpkg の md5 が合わないのは `/etc/sudoers`、`/etc/multipath.conf`、`/etc/containerd/config.toml`。ucf で合わないのは `/etc/ssh/sshd_config`（chirico、duchamp と同じ）。

braque に載っている Pod は 5 個（cnidaria、kube-proxy、node-exporter、smart-exporter、nfsd）で、すべて DaemonSet。MetalLB の speaker は載っていない（taint を許容していない）。
braque は Longhorn のノードではなく、replica は無い。

#### nfsd のイメージ

`gcr.io/google_containers/volume-nfs:0.8` は、レジストリが Docker の schema 1（`application/vnd.docker.distribution.manifest.v1+prettyjws`）でしか返さない。containerd 2.x は schema 1 のイメージを pull できない。
braque の containerd には、1.6 が pull の時に変換した OCI の形（`application/vnd.oci.image.manifest.v1+json`、83.1 MiB）で入っている。`/var/lib/containerd` は引き継がれるので、置き換えの後もそのまま動く見込み。消えると pull し直せない。

### 1.4 braque の NFS を使っているもの

runbook §2.1.1 の一覧のほかに、`fs/data-restore`、`fs/h2-restore`、`fs/sites-restore`（`sleep infinity` の Pod。chirico と duchamp）が、`192.168.1.131` を inline の NFS ボリュームでマウントしている。braque の停止中は、これらのマウントが応答しなくなる。

`registry.fraction.jp` のイメージを使う Pod（runbook §2.1.1）: `llm-wiki/llm-wiki`（chirico）と `holyorder-preview/preview`（pablo）。どちらも `imagePullPolicy: IfNotPresent`（runbook の記述と同じ）。

### 1.5 控えた設定（runbook §3.3 の 2）

タスクディレクトリの `notes/hosts/braque-20261017/` に保存した（リポジトリには入れない）:
`containerd-config.toml`、`etc-apt-sources.tar`、`kubelet.service.txt`、`cluster-dns.service`、`multipath.conf`、`sudoers`、`sudoers.d-ls.txt`、`sshd_config`、`netplan.tar`、`dpkg-selections.txt`、`dpkg-l.txt`、`ip.txt`、`zfs.txt`、`mounts-units.txt`、`iscsi-lsblk.txt`、`iptables.txt`、`conffiles-modified.txt`、ベースラインの `verify-nodes.sh` と `check-apps.sh` の出力。

### 1.6 known_hosts（runbook §5.7）

- porkadot の checkout（4fa3a0f）で `SSHKit::Backend::Netssh::KnownHosts.new.search_for("192.168.1.131", {})` は `ecdsa-sha2-nistp256` を返した
- その鍵の fingerprint `SHA256:tTvaJA2uUeg3/Cw5r9/DQNUVBJmmVb7cLHf8bZqQdGU` は、ノードの `/etc/ssh/ssh_host_ecdsa_key.pub` と同じ
- 対処は要らない（known_hosts は変えていない）
