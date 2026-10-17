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

## 2. cordon と drain（runbook §3.3）

22:2xZ にユーザーが §3.3 の事前確認（devbox を使っている人がいない、作業端末が devbox でない（作業端末は boucherie）、04:00 UTC の自動再起動に当たらない）に答えた。いまの devbox の中には、SSH と mosh のセッションは無かった。

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 22:21:42 | ✋ `infra-admin` のトークンを発行（3h） | 作業端末の 600 のファイルに置いた。`auth can-i patch nodes` が yes |
| 22:21:47 | ✋ `cordon oeilvert` | Ready,SchedulingDisabled |
| 22:21:48 | ✋ `concurrent-replica-rebuild-per-node-limit` を `0`、`replica-auto-balance` を `disabled`（§2.5）、`node-drain-policy` を `allow-if-replica-is-stopped`（§2.4） | 直前の値は `5`、`least-effort`、`block-if-contains-last-replica`。読み直して変わり、APPLIED true |
| 22:21:59 | ✋ `minio/minio` の StatefulSet を 4 → 0（§2.4 の 2） | 22:22:41 に 4 つのボリュームが detached、oeilvert の 4 つの replica が stopped |
| 22:22:45 | ✋ `drain oeilvert --ignore-daemonsets --delete-emptydir-data --timeout=20m` | 22:23:26 に `node/oeilvert drained`（rc 0）。コントローラを持たない Pod が無いので `--force` は付けていない |

- drain は oeilvert の instance-manager の PDB で 4 回（5 秒ずつ）待ってから進んだ。時間切れは無く、Prometheus は oeilvert には関係しなかった（§2.4 のとおり 0 にしていない）
- 退いた Pod は、22:25 までにすべて Running に戻った。ただし **`homegallery/api` は Deployment の `nodeSelector` が `kubernetes.io/hostname: oeilvert` なので、uncordon まで Pending のまま**になる。ユーザーの判断で、そのままにした（runbook には無かった）
- 22:24 の Longhorn: oeilvert でアタッチしているボリュームは無い。attached degraded 15（oeilvert に replica がある 2 replica のボリューム）、attached healthy 4、detached 6（myao、cg-data、MinIO の 4 つ）
- replica は 45 個で、drain の前と同じ数（oeilvert の 20 は全部 stopped）。ほかのノードに新しい replica は作られていない
- iSCSI のセッションが 7 つ残った（退いた instance-manager の 10.244.7.230 へ）。マウントはされていない。chirico と duchamp と同じく §3.4 の 9 の再起動で片付ける
- replica が止まったのは 22:23 ごろ。`replica-replenishment-wait-interval`（100 分）の内側で設定を戻すには、00:03 ごろまでに §3.8 の 3 を行う

## 3. 22.04 のまま containerd と Docker を置き換える（runbook §3.4、§3.4.1）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 22:25:52 | ✋ 0: chirico の `/root/containerd.io_1.6.8-1_amd64.deb` を oeilvert の `/root/` に写す | sha256 `74ce6b6b440073b6…` が chirico と一致。oeilvert の apt のキャッシュには無かった |
| — | 1: Docker の apt リポジトリを外す | oeilvert には無いので飛ばした。`apt-cache policy` で `containerd.io` と `docker-ce` の候補が入っている版だけ（`/var/lib/dpkg/status`）であることを確かめた |
| 22:26:29〜22:29:1x | ✋ 2: `apt-get update` → `apt-get full-upgrade` | rc 0。92 upgraded、8 newly installed、0 removed、1 not upgraded（下の 3.1） |
| 22:33:35 | ✋ §3.4.1 の 2・3: `systemctl stop devbox`、`systemctl stop docker docker.socket` | devbox のコンテナは消えた（`--rm`）。止まったコンテナ 2 つは残っている |
| 22:33:55〜22:34:21 | ✋ §3.4.1 の 4: `apt-get install containerd docker.io docker-ce-rootless-extras- docker-scan-plugin-` | rc 0（下の 3.2） |
| 22:34:29 | 4: `config.toml` を `config.toml.porkadot-bak.20261017` に名前を変える | `containerd config default` は `version = 3` |
| 22:34:54〜22:34:57 | ✋ 5: `porkadot setup-containerd --config ./porkadot.yaml --node oeilvert`（porkadot 4fa3a0f、asset はこのブランチの base 2b41485） | rc 0。`ERROR`、`Unsupported containerd config version`、`HostKeyMismatch` は無い |
| 22:35:12 | ✋ 7: `systemctl restart kubelet`、§3.4.1 の 5: `systemctl restart docker` | Ready,SchedulingDisabled、`containerd://2.2.1`、OS-IMAGE は `Ubuntu 22.04.5 LTS`。DaemonSet の Pod 8 つが Running |
| 22:36:11 | ✋ §3.4.1 の 7: `systemctl start devbox` | 下の 3.4 |
| — | 8: dns addon の修正 | oeilvert は当たっているので何もしない |

### 3.1 full-upgrade

- duchamp と同じく非対話で流した: `systemd-run --unit=full-upgrade-20261017` の中で、`DEBIAN_FRONTEND=noninteractive`、`UCF_FORCE_CONFFOLD=1`、dpkg の `--force-confdef --force-confold`。ログはノードの `/root/full-upgrade-20261017.log`
- 先に `apt-get -s full-upgrade` で、削除されるものが無いことを確かめた。systemd、openssh、kernel は更新に含まれていなかった
- conffile: `/etc` の `*.dpkg-*` と `*.ucf-*` は前後で変わらなかった（前からあるのは `ca-certificates.conf.dpkg-old`、`containerd/config.toml.dpkg-dist`、`cron.daily/bsdmainutils.dpkg-remove`、`default/grub.ucf-dist`、`ssh/sshd_config.ucf-dist`、`ssh/sshd_config.ucf-old`、`sudoers.dpkg-dist`、`systemd/resolved.conf.dpkg-dist`）。fwupd と ubuntu-advantage の使われなくなった conffile は消された
- 更新されなかったもの: `open-vm-tools`（phased update。chirico と同じ）。systemd 本体は 249.11-0ubuntu3.23 のまま。nftables 1.0.2-1ubuntu3.1、multipath-tools 0.8.8-1ubuntu1.22.04.4、qemu 1:6.2+dfsg-2ubuntu6.31
- 終わった後: **`/var/run/reboot-required` は立たなかった**（kernel が更新に含まれていないため。oeilvert は 9 日前に 5.15.0-198 で起動している）。cnidaria の経路（proto 200）は v4・v6 とも 7 本。kubelet、containerd、docker、devbox、multipathd は active。`sudo -n true` が通り、`/etc/multipath.conf` は addon の版のまま

### 3.2 containerd と docker.io を入れる（§3.4.1 の 4）

先に `apt-get -s install containerd docker.io` を流したところ、runbook と 2 点違った。

- 削除されるのは `docker-ce`、`docker-ce-cli`、`containerd.io` の 3 つだけだった。`docker-ce-rootless-extras` と `docker-scan-plugin` は docker-ce に依存しないので残る（runbook は 4 つが消えると書いていた）
- `docker.io` の Recommends で `ubuntu-fan` も入る（`bridge-utils` と `dnsmasq-base` は libvirt のために入っている）

ユーザーの判断: 残る 2 つは要らないので一緒に消す。`ubuntu-fan` は入れる（`--no-install-recommends` は付けない）。

- debconf の `docker.io/restart` は、先に `true` を入れておいた（runbook の「はい」）
- 非対話（`DEBIAN_FRONTEND=noninteractive`、`--force-confdef --force-confold`）で流した。ログはノードの `/root/apt-docker-20261017.log`
- 消えたもの（remove。purge はしていない）: `docker-ce`、`docker-ce-cli`、`docker-ce-rootless-extras`、`docker-scan-plugin`、`containerd.io`。`containerd.io` と `docker-ce` は設定ファイルが残る `rc` の状態
- 入ったもの: `containerd` 2.2.1-0ubuntu1~22.04.2、`runc` 1.3.4-0ubuntu1~22.04.1、`docker.io` 29.1.3-0ubuntu3~22.04.2、`ubuntu-fan` 0.12.16
- `/etc/containerd/config.toml`（version 2）は残った。Ubuntu の `containerd` は `config.toml.dpkg-dist`（2022-08 から残っているもの）に触らない
- `docker.io` は入れた時点で自動で起動した。containerd は古い version 2 の config で起動し、migrate の警告と `Ignoring unknown key` を出した（4 で config を退避する前のこと）
- `ubuntu-fan` は `/etc/network/fan`（FAN の対応表。コメントになっていない例の行がある）と `ubuntu-fan.service` を置く。FAN を有効にするのは `/etc/network/interfaces` か `fanctl config` だけなので、`ubuntu-fan.service` は何もせずに終わった。fan のブリッジ、250〜254 の経路、NAT の規則は無い

### 3.3 containerd の確認（runbook §3.4 の 6・7）

- `containerd --version` が 2.2.1。`/etc/containerd/config.toml` は `version = 3`、`sandbox = 'registry.k8s.io/pause:3.10.1'`、`[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]` の下に `SystemdCgroup = true`
- `sudo /opt/bin/crictl info` が応答する。`crictl images` は 63 行で、イメージが引き継がれている
- `setup-containerd` で再起動した後（22:34:55 以降）の containerd の journal に、migrate の警告と `Ignoring unknown key` は無い。`ctr deprecations list` は空
- DaemonSet の Pod は、containerd の置き換えでも kubelet の再起動でも再起動しなかった（chirico、duchamp と同じ）

### 3.4 Docker と devbox の確認（runbook §3.4.1 の 6・7）

- `docker version` は client、server とも 29.1.3。`docker info` の Storage Driver は overlay2、Docker Root Dir は `/var/lib/docker`、Cgroup Driver は systemd
- イメージは `docker info` で 1212 個（前と同じ）。タグの付いたイメージは前の 199 個がすべて残っている。**`docker images` の行数は 590 から 202 に減ったが、これは Docker 29 の `docker images` がタグの無いイメージを既定で出さなくなったため**で、`docker images -a` は 1212 個を数える。devbox のイメージ（`registry.fraction.jp/yuanying/devbox-amd64:latest`、7a85bdaa2d28）は残っている
- ボリューム（名前の無い 1 つ）は残っている。`bridge` のネットワークは IPv6 が有効で、`fde0:17ad:84c5:82::/64`（daemon.json が読まれている）
- devbox: `systemctl start devbox` で起動し、ポート 3222、8080、9090（v4・v6）と 60000〜60010/udp が開いた。作業端末から port 3222 に SSH で入れた。`mosh.fraction.jp` での確認は、ユーザーが 24.04 の後に行う
- **iptables の FORWARD の順番が変わった。** Docker 29 は FORWARD の先頭に `DOCKER-USER` と `DOCKER-FORWARD` へのジャンプを入れ、`CNIDARIA-FWD` は 3 番目になった（v4・v6 とも）。policy は ACCEPT のまま。`DOCKER-USER` は `RETURN` だけで、`DOCKER-FORWARD` は docker のブリッジ向けの通信だけを扱うので、Pod の通信には影響しない見込み。更新前（Docker 20.10）は `CNIDARIA-FWD` が先頭だった

### 3.5 22.04 の再起動（runbook §3.4 の 9・10）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 22:40:27 | 9: `systemctl reboot`（ユーザーがコンソールで見られるようにしてから承認） | journal は 22:40:42 に止まった。kernel の起動は 22:42:51（`uptime -s`）。22:43:12 に SSH が上がり、Ready |

- 止めてから kernel が起動するまで約 2 分（chirico 約 5 分、duchamp 約 17 分）。起動は 42 秒（firmware 10.3s、loader 1.4s、kernel 4.2s、userspace 26.5s）
- 起動の後: kernel 5.15.0-198-generic（変わらず）、`containerd://2.2.1`、config は `version = 3` のまま。containerd の journal に migrate の警告や `Ignoring unknown key` は無い。`ctr deprecations list` は空
- kubelet は containerd の socket ができる前に起動に失敗し、systemd がやり直して上がった（chirico、duchamp と同じ）
- DaemonSet の Pod は 8 つとも Running（restart が 1 回ずつ増えた）。Pending の CSR は無い
- devbox は `devbox.service` で自動で起動した（22:43）
- runbook §3.7 の 8〜13 と oeilvert の確認:
  - `/var/lib/longhorn`（zvol、automount）と `/var/lib/longhorn2` がマウントされている。ZFS は `all pools are healthy`、`/export` は `tank/export`
  - **iSCSI の古いセッションは消えた**（`No active sessions`）。multipathd と `iscsid.socket` は active
  - `sudo -n true` が通る
  - `cluster-dns` は active。`porka-dummy01` に 10.254.0.10 と検索ドメイン
  - `systemctl --failed` は空。`ordering cycle` は 0。`home-yuanying-shared-data.automount`、`-h.automount`、`home-yuanying-shared-nfs.mount` は active
  - cnidaria の経路（proto 200）は v4・v6 とも 7 本。`/var/run/reboot-required` は無い
- iptables の FORWARD: 起動では Docker が kubelet と cnidaria より後に上がり、`DOCKER-USER` と `DOCKER-FORWARD` へのジャンプを末尾に足した。v4・v6 とも `CNIDARIA-FWD` が先頭に戻った。
  **ip6tables の FORWARD の policy は `DROP` になった**（v4 は ACCEPT）。`netfilter-persistent` の `rules.v6`（2021 年）はどのチェーンも ACCEPT なので、Docker が設定したものである。runbook §3.7 の 7 で oeilvert について想定していた形で、Pod の通信は先頭の `CNIDARIA-FWD` で通る

## 4. `do-release-upgrade`（runbook §3.5）

### 4.1 前提の確認（§3.5 の 1）

- `apt list --upgradable` は `open-vm-tools`（phased update）だけ。`/var/run/reboot-required` は無い。`/` の空きは 83G。`sources.list.d` は空
- `Prompt=lts`、`ubuntu-release-upgrader-core` は 1:22.04.21（full-upgrade で 22.04.19 から上がった）。`do-release-upgrade -c` は `New release '24.04.5 LTS' available`
- dpkg の md5 が合わない conffile: `/etc/sudoers`、`/etc/multipath.conf`、`/etc/systemd/resolved.conf`、`/etc/containerd/config.toml`（`containerd.io` の `rc` の残り）
- ucf で合わないものは無い。**oeilvert の `/etc/ssh/sshd_config` には手が入っていない**（chirico、duchamp は末尾に `PasswordAuthentication no` があった）

### 4.2 実行（非対話）

| 時刻（UTC） | 出来事 |
|---|---|
| 22:44:51 | `systemd-run --unit=release-upgrade --setenv=DEBIAN_FRONTEND=noninteractive --setenv=UCF_FORCE_CONFFOLD=1 do-release-upgrade -f DistUpgradeViewNonInteractive` |
| 22:49:21 | パッケージの入れ替えが始まった（`history.log`） |
| 22:51:55〜23:01:56 | **作業端末から新しい SSH の接続ができなかった**（port 22 が `Connection refused`）。20 秒ごとに入ろうとして、約 10 分（chirico は約 8 分） |
| 22:59:45 | `/etc/sudoers` の conffile の質問に `no`（手元の版を残す）と答えた（`main.log`） |
| 23:03:19 | 不要になったパッケージの purge |
| 23:04:03 | `confirmRestart() called`（main.log の最後）。unit は `Result=success`、`ExecMainStatus=0`。再起動はしていない |

所要時間は約 19 分。

### 4.3 再起動の前の確認（§3.5 の 3）

conffile の扱い:

| ファイル | 結果 |
|---|---|
| `/etc/sudoers` | 手元の版のまま（`%sudo ALL=NOPASSWD:ALL`）。`sudo -n true` が通る |
| `/etc/systemd/resolved.conf` | 手元の版のまま（`DNS=192.168.0.1`、`Domains=default.svc.cluster.local svc.cluster.local cluster.local`）。質問は出なかった |
| `/etc/multipath.conf` | addon の版のまま（multipath-tools 0.9.4-5ubuntu8.2）。質問は出なかった |
| `/etc/ssh/sshd_config`（ucf） | 手を入れていない版なので、そのまま。`sshd_config.ucf-dist` が新しい版で置かれた |
| `/etc/nfs.conf`、`/etc/default/nfs-common`（ucf） | 手元の版のまま。`.ucf-dist` が新しく置かれた（違いはコメントの行だけ） |
| `/etc/containerd/config.toml` | §3.4 で作った version 3 のまま |
| `/etc/docker/daemon.json` | そのまま（conffile ではない） |

削除されたもの（`/var/log/dist-upgrade/history.log`。Remove と Purge で 236 個）:

- `Remove:` は、24.04 で名前が変わったライブラリの古い名前（`libssl3`、`libcurl4`、`libglib2.0-0` など）、`usrmerge`、`python3-distutils`、**`ufw`**
  - `ufw` は無効だった（`/etc/ufw/ufw.conf` が `ENABLED=no`）。noble の `ufw` は `iptables-persistent` と同時に入れられないので、`do-release-upgrade` が `Keeping iptables-persistent, and removing ufw as a result.` として消した。消すときは `Skip stopping firewall: ufw (not enabled)`。chirico と duchamp にも `ufw` は入っていたが、`iptables-persistent` が無いので消えていない
- `Purge:` は kernel 5.15.0-194 と 5.4.0-125 の一式、python3.10、python3.8、`libperl5.30`・`5.34` などの古いライブラリ、**`irqbalance`**、`isc-dhcp-client`、`isc-dhcp-common`、`policykit-1`、`pkexec`、`ubuntu-advantage-tools`、`slirp4netns`、`cgroupfs-mount`、`aufs-tools` など
- **Remove と Purge のどちらにも入っていないもの**（再起動の前に確かめた）: `containerd`、`runc`、`docker.io`、`libvirt-daemon`、`qemu-system-x86`、`zfsutils-linux`、`open-iscsi`、`nfs-common`、`multipath-tools`、`sudo`、`openssh-server`、`ubuntu-fan`。どれも 24.04 の版で入っている

版（再起動の前）: `containerd` 2.2.1-0ubuntu1~24.04.3、`runc` 1.3.4-0ubuntu1~24.04.1、`docker.io` 29.1.3-0ubuntu3~24.04.2、`zfsutils-linux` 2.2.2-0ubuntu9.5、`libvirt-daemon` 10.0.0-2ubuntu8.19、`qemu-system-x86` 1:8.2.2+ds-0ubuntu1.18、`nftables` 1.0.9-1ubuntu0.1、`multipath-tools` 0.9.4-5ubuntu8.2、`open-iscsi` 2.1.9-3ubuntu5.5、`openssh-server` 1:9.6p1-3ubuntu13.20。kernel は 5.15.0-198 と 6.8.0-147。

apt の source は `ubuntu.sources`（noble）と、`third-party.sources`。後者は、もとの `sources.list` にあったコメントアウト済みの Docker の行（`# deb [arch=amd64] https://download.docker.com/linux/ubuntu jammy stable # disabled on upgrade to jammy`）を、`do-release-upgrade` が deb822 の形に移したもので、`Enabled: no` になっている。

再起動の前、cnidaria の経路は 7 本のままだった。

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 23:06:01 | 4: `systemctl reboot`（ユーザーがコンソールで見られることを確かめてから承認） | |

- journal は 23:06:16 に止まった。kernel の起動は 23:07:59（`uptime -s`）。23:08:35 に SSH が上がり、Ready（SchedulingDisabled）、Ubuntu 24.04.5、6.8.0-147-generic、`containerd://2.2.1`
- 止めてから kernel が起動するまで約 2 分。起動は 36 秒（firmware 10.3s、loader 1.4s、kernel 2.6s、userspace 22.1s）

## 5. 24.04 での確認（runbook §3.6・§3.7）

版:

| 項目 | 値 |
|---|---|
| OS | Ubuntu 24.04.5 LTS |
| kernel | 6.8.0-147-generic |
| containerd | 2.2.1-0ubuntu1~24.04.3（`containerd://2.2.1`） |
| runc | 1.3.4-0ubuntu1~24.04.1 |
| docker.io | 29.1.3-0ubuntu3~24.04.2 |
| nftables | 1.0.9 |
| zfsutils-linux | 2.2.2-0ubuntu9.5 |
| kubelet | v1.29.8 |
| irqbalance | 1.9.3-2ubuntu5（再起動の後に入れ直した） |

- §3.6: `/etc/containerd/config.toml` は §3.4 で作った version 3 のまま（`SystemdCgroup = true`、`registry.k8s.io/pause:3.10.1`）。migrate の警告や `Ignoring unknown key` は無い。`ctr deprecations list` は空。containerd と kubelet は active。kubelet の journal には、起動の直後（23:08:26）に、もう無い古いコンテナの `ContainerStatus ... NotFound` が並んだが、その後は続いていない。`setup-containerd` の再実行は要らなかった
- 23:09:17: ✋ `apt-get install -y irqbalance`（§3.5 の 6）。1.9.3-2ubuntu5 が入り、active

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready,SchedulingDisabled。24.04.5、6.8.0-147-generic、`containerd://2.2.1`。ラベル `node-role.kubernetes.io/simone`、`role=worker`、`tgtd.unstable.cloud/storage`、`zfs.unstable.cloud/storage` が残っている |
| 2 | CSR | Pending は無い |
| 3 | DaemonSet の Pod | cnidaria、kube-proxy、engine-image、longhorn-csi-plugin、longhorn-manager、speaker、node-exporter、smart-exporter が Running |
| 4 | ログ | cnidaria と kube-proxy のログが読める |
| 5 | cnidaria | `verify-nodes.sh` は 64 PASS、FAIL 0。cnidaria のログに error は無い。23:08:28 に nft のテーブルを適用した |
| 6 | ホストの nft | 1.0.9。`nft list tables` は `inet cnidaria` を含めて rc 0 |
| 7 | iptables | v4・v6 とも `CNIDARIA-FWD` へのジャンプが先頭。v4 の policy は ACCEPT、**v6 の policy は DROP**（Docker が設定。§3.5 を参照）。Pod の通信は先頭の `CNIDARIA-FWD` で通る（§6 の `netcheck.sh` で確かめた） |
| 8 | ディスク | `/var/lib/longhorn`（zvol `zd0`、automount）と `/var/lib/longhorn2`（`sdb1`）がマウントされている |
| 9 | ZFS | `all pools are healthy`。`tank/export` が `/export` にマウントされている。`zpool upgrade` はしていない |
| 10 | multipath と iSCSI | `/etc/multipath.conf` は addon の版。multipathd と `iscsid.socket` は active。iSCSI のセッションは無い |
| 11 | sudo | `sudo -n true` が通る |
| 12 | DNS | `cluster-dns` は修正済みの版で active。`porka-dummy01` に 10.254.0.10 と検索ドメイン |
| 13 | 失敗している unit | 無い |

oeilvert の追加の確認:

- `journalctl -b 0 | grep "ordering cycle"` は 0
- `cluster-dns.service` に `porka-dummy01` のデバイスと `systemd-networkd` への依存が入っている
- `home-yuanying-shared-data.automount`、`-h.automount`、`home-yuanying-shared-nfs.mount` は active
- `/etc/systemd/resolved.conf` は手元の版のまま
- `docker`、`devbox`、`netfilter-persistent` は active。`docker ps` に devbox がある
- unattended-upgrades の自動再起動（`52local-reboot.conf`、04:00）は残っている。`/var/run/reboot-required` は無い

## 6. uncordon と後始末（runbook §3.8）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 23:10:09 | ✋ `uncordon oeilvert`。`node-drain-policy` を `block-if-contains-last-replica` に戻す。`minio/minio` の StatefulSet を 4 に戻す | Longhorn の node の oeilvert は Ready で schedulable |
| 23:12:14 | ✋ `concurrent-replica-rebuild-per-node-limit` を `5`、`replica-auto-balance` を `least-effort` に戻す | 読み直して `5`、`least-effort`、`block-if-contains-last-replica`、APPLIED true。drain で replica が止まってから約 49 分 |
| 23:12:26〜23:16:59 | 再同期を待つ | degraded は 15 → 0 |
| 23:17:49〜23:18:13 | ✋ `netcheck.sh up` → `run` → `down` | `PASS 168 / 168, pods 8/8`。namespace は消した |
| 23:18 | `check-apps.sh` | ベースラインとの差は、hedgedoc の db-postgresql-0 が oeilvert から chirico に移ったことだけ（drain による） |
| 23:18:35 | トークンを破棄（作業端末のファイルを消した。トークン自体は 01:21 に失効する） | |

- uncordon の後、MinIO の 4 つ（minio-0 は oeilvert、minio-1 は duchamp、minio-2 は chirico、minio-3 は pablo）と `homegallery/api`（oeilvert）は Running に戻った。Running / Completed 以外の Pod は 0 個
- Longhorn: attached healthy 23、detached unknown 2（myao、cg-data。ベースラインと同じ）。replica は 45 個のまま
- 止まっていた replica のほとんどは再利用された。ただし data locality（`best-effort`）で 4 つの replica が chirico に移った。どれも 2 replica のボリュームで、drain で Pod が chirico に移ったため（duchamp と同じ現象。runbook §3.8 の 3）:
  - `natsumi/natsumi`（pvc-6b8f51fa）: pablo → chirico
  - `hedgedoc/data-db-postgresql-0`（pvc-8eb75c08）: oeilvert → chirico
  - `fraction-agents/data-deep-researcher-0`（pvc-9aae4b86）: oeilvert → chirico
  - `fraction-agents/data-gmail-agent-0`（pvc-aee2ec0e）: oeilvert → chirico
  - その結果、ノードごとの running の数は chirico 15、duchamp 8、oeilvert 17、pablo 1 になった（ベースラインは 11、8、19、2）。どのボリュームも healthy
- `natsumi/natsumi-aki` の duchamp の stopped の replica（cnidaria 移行の時刻のもの）はベースラインと同じく残っている

## 7. 次の 1 台へ進む条件（runbook §3.9。30 分の様子見を除く）

| 条件 | 結果 |
|---|---|
| 全 8 台が Ready。oeilvert が 24.04.5 と `containerd://2.2.1` | 満たす |
| etcd 3/3 healthy、VIP が応答 | 満たす（`/readyz` は `ok`） |
| Running / Completed 以外の Pod がベースラインから増えていない | 満たす（0 個） |
| Longhorn のボリュームが healthy、再構築が終わっている | 満たす（23:16:59 に degraded 0） |
| `verify-nodes.sh`、`netcheck.sh`、`check-apps.sh` がベースラインと同じ | 満たす（64 PASS、168/168、差は hedgedoc の Pod の置き場所だけ） |
| Longhorn の設定と MinIO が元に戻っている | 満たす（`5`、`least-effort`、`block-if-contains-last-replica`、MinIO 4/4） |
| LoadBalancer | TCP のものはすべて応答（gated v4/v6 の 80・443、h2-sshd、natsumi-sshd の 3 つ、VIP の 6443）。minecraft は UDP なので確かめていない |
| oeilvert の確認（runbook §3.7） | devbox、Docker、iptables は満たす。`mosh.fraction.jp` での SSH と mosh はユーザーが確かめる |
| 30 分の様子見 | この記録の時点では 24.04 で起動してから約 11 分 |

## 8. runbook を直した点

- §3.3: oeilvert の `homegallery/api` は `nodeSelector` で oeilvert に固定されているので、drain から uncordon まで Pending になる。自動再起動の 04:00 はホストの時刻（UTC）
- §3.4 の 0: oeilvert の apt のキャッシュには deb が無く、chirico の deb を写した
- §3.4 の 9: oeilvert では止めてから kernel が起動するまで約 2 分だった
- §3.4.1 の 4: `apt install containerd docker.io` では `docker-ce-rootless-extras` と `docker-scan-plugin` が残るので、末尾の `-` で一緒に消す。`ubuntu-fan` が Recommends で入る。debconf の `docker.io/restart` の答えを先に入れる
- §3.4.1 の 6: Docker 29 の `docker images` はタグの無いイメージを出さない。iptables の FORWARD の順番は、Docker の再起動では `DOCKER-*` が先頭になり、ノードの再起動で `CNIDARIA-FWD` が先頭に戻る。v6 の policy は再起動の後に DROP になる
- §3.5: SSH に新しく入れない時間は 8〜10 分。oeilvert では `ufw`（無効）が消えた。`third-party.sources`（`Enabled: no`）ができることがある。irqbalance は oeilvert でも purge された
- §3.7 の 7: ip6tables も見る
- §3.8 の 3: oeilvert での戻した時刻と、data locality で移った replica
- §5.7: oeilvert は対処済み。known_hosts に ECDSA の行が無いとき（oeilvert、pablo）の確かめ方。braque は sshkit が ECDSA を返すことを確かめた

## 9. 申し送り

- oeilvert の `/root` に `containerd.io_1.6.8-1_amd64.deb`、`cluster-dns.service.bak-20261017`、`full-upgrade-20261017.log`、`apt-docker-20261017.log` が、`/etc/containerd/` に `config.toml.porkadot-bak.20261017` が残っている（runbook §6.2 で全台の後に片付ける）。`containerd.io` と `docker-ce` は設定ファイルが残る `rc` の状態
- 作業端末の `~/.ssh/known_hosts.bak-20261017-oeilvert` は known_hosts の控え
- ip6tables の FORWARD の policy が DROP になった。Pod の通信は `CNIDARIA-FWD` で通る。oeilvert のホストが v6 で転送するほかの通信（libvirt の VM など。いまは VM は 0 台）は止まる。Docker の daemon.json の `ip-forward-no-drop` で DROP にさせないこともできるが、設定は変えていない（ユーザーの判断）
- `ubuntu-fan` が入っている（使っていない）。`docker.io` の Recommends で、ユーザーの判断で入れた
