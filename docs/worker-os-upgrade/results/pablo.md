# pablo の作業記録

pablo（192.168.1.134）を Ubuntu 22.04 → 24.04.5、containerd 1.6.8（Docker の `containerd.io`）→ 2.2.1（Ubuntu の `containerd`）にした記録。手順は `../runbook.md`（以下 runbook）。
5 台目（最後）で、前の 4 台の記録は `chirico.md`、`duchamp.md`、`oeilvert.md`、`braque.md`。時刻は UTC（pablo のホストの時刻も UTC）。

## 1. 事前の読み取り（2026-10-18 00:39Z〜00:44Z）

### 1.1 kubeconfig、cnidaria-cni-dev、nfsd の別タスク（runbook §1.2、§2.2）

- `kubectl --context fraction auth can-i delete pods -A`: `no`
- cnidaria-cni-dev の STATE.md: 走っている作業単位は無い
- `ds/cnidaria`: `ghcr.io/yuanying/cnidaria-cni:v0.1.1`、8/8 が更新済みで Ready
- 別タスク `fraction-nfsd-to-fleet-infra` の STATE.md（00:39Z）: 作業単位 `nfsd-moved-to-fleet-infra` の worker が作業中で、本番の nfsd の diff と server の dry-run の承認と、`pods/exec` の扱いの判断を待っていた。braque の nfsd が入れ替えで止まると、drain で移る `docker/registry` と fs の Pod が上がれないので、作業を重ねない

### 1.2 クラスタのベースライン（runbook §2.3）

braque の作業後（`braque.md` §6、§7）と同じだった。

| # | 項目 | 結果 |
|---|---|---|
| 1 | Node | 8 台 Ready。pablo だけが 22.04 / 5.15.0-194-generic / `containerd://1.6.8`。ほかの 7 台は 24.04.5 / `containerd://2.2.1` |
| 2 | Running / Completed 以外の Pod | 0 個 |
| 3 | Longhorn | attached healthy 23、detached unknown 2（`myao/myao`、`homegallery/cg-data`）。replica は 45 個（chirico 17、duchamp 10、oeilvert 17、pablo 1。stopped は chirico 2、duchamp 2、oeilvert 1） |
| 4 | etcd、VIP | 3/3 healthy（leader は 192.168.1.112、raft index は 3 台で同じ）。`https://192.168.1.101:6443/readyz` は `ok` |
| 5 | cnidaria | `verify-nodes.sh` は 64 PASS、FAIL 0。cnidaria のログは errors 0。`check-apps.sh`: nodes 8/8、Running でない Pod 0、IP の重複 0、Longhorn は 3 と同じ、hedgedoc の db-postgresql-0 は Running（chirico）、192.168.1.200 と v6 の LB は 404、VIP の `/version` は 200 |
| 6 | `cluster-dns.service` | pablo は修正前の版（`After=systemd-resolved.service` だけ） |

Longhorn の設定（変える前の値）:

| 設定 | 値 |
|---|---|
| `concurrent-replica-rebuild-per-node-limit` | `5` |
| `replica-auto-balance` | `least-effort` |
| `node-drain-policy` | `block-if-contains-last-replica` |
| `replica-replenishment-wait-interval` | `6000` |

`monitoring/kube-prometheus` の `spec.replicas` は 2、`minio/minio` は 4/4（pablo では変えない）。

### 1.3 pablo の状態（runbook §3.3 の 1）

| 項目 | 値 |
|---|---|
| Node | Ready、`containerd://1.6.8`、kernel 5.15.0-194-generic。ラベルは `metallb=speaker` だけ（ほかは既定のもの）。taint は無い |
| OS | Ubuntu 22.04 LTS |
| containerd | `containerd.io` 1.6.8-1。apt の候補は Docker の 2.4.2-2~ubuntu.22.04~jammy（`docker.list` があるため）。Ubuntu の `containerd` の候補は 2.2.1-0ubuntu1~22.04.2 |
| `/etc/containerd/config.toml` | `version = 2`、`sandbox_image = "k8s.gcr.io/pause:3.6"`、`SystemdCgroup = true` |
| apt の hold | 無い |
| `/etc/apt/sources.list.d/` | `docker.list` だけ（ほかの 3 台と同じ内容） |
| 更新できるパッケージ | 110 個 |
| `/var/run/reboot-required` | **既にある**（2026-10-07 から。`linux-image-5.15.0-198-generic` と `linux-base`）。kernel は 5.15.0-194（起動中）と 5.15.0-198 |
| uptime | 14 日 |
| ディスク | `/`（`/dev/sdb2`）は 229G で空き 141G。`/var/lib/longhorn`（`/dev/sda`、1.8T）は空き 1.6T |
| メモリ | 31G |
| ネットワーク | `eno1` は DHCP（v4）で 192.168.1.134。`wlp58s0` は DOWN |
| sshd_config | 末尾に `PasswordAuthentication no`（chirico、duchamp、braque と同じ） |
| sudoers | `%sudo ALL=(ALL:ALL) NOPASSWD:ALL` |
| `irqbalance` | 1.8.0-1build1 |
| `ufw` | 0.36.1-4build1（inactive。`iptables-persistent` は無い） |
| `ubuntu-release-upgrader-core` | 1:22.04.10、`Prompt=lts` |
| iptables | FORWARD の policy は ACCEPT。v4・v6 とも `CNIDARIA-FWD` へのジャンプが先頭 |
| cnidaria の経路 | proto 200 は v4・v6 とも 7 本 |
| `journalctl -b 0` の `ordering cycle` | 0 |
| iSCSI | セッションは 5 つ（すべて pablo の instance-manager の 10.244.4.46 へ）。そのうち `pvc-beb6e798`（`minio/export-minio-1`）は duchamp でアタッチしているボリュームで、古いセッションである |
| `systemctl --failed` | `fwupd-refresh.service` |

手元で変わっている conffile: dpkg の md5 が合わないのは `/etc/sudoers`、`/etc/multipath.conf`、`/etc/containerd/config.toml`。ucf で合わないのは `/etc/ssh/sshd_config`（chirico、duchamp、braque と同じ）。

pablo に載っている Pod は 26 個（DaemonSet を含む）。コントローラを持たない Pod は無い。`nodeSelector` や affinity で pablo に固定された Deployment / StatefulSet は無い。
DaemonSet 以外の主なもの: `docker/registry`（`registry.fraction.jp`）、`fs/h2`、`holyorder-preview/preview`、`minio/minio-3`、share-manager 2 つ（`homegallery/tumblr-data`、`homegallery/ero-data` の RWX）、`monitoring/alertmanager-kube-prometheus-0`、`kube-prometheus-operator`、`kube-state-metrics`、Longhorn の CSI のコントローラ 4 つ、`aphrael`、`comics-webdav`、`gated-demo`、`searxng`。

Longhorn のボリュームで pablo にアタッチしているのは `fs/h2`（replica 2）、`homegallery/tumblr-data`・`ero-data`（RWX、replica 2）、`minio/export-minio-3`（replica 1、replica は oeilvert）。
pablo にある replica は `fs/h2` の 1 つだけ（running）で、最後の replica を pablo に持つボリュームは無い（runbook §2.4 の表と同じ）。`node-drain-policy` は変えない。

### 1.4 控えた設定（runbook §3.3 の 2）

タスクディレクトリの `notes/hosts/pablo-20261018/` に保存した（リポジトリには入れない）:
`containerd-config.toml`、`etc-apt-sources.tar`、`kubelet.service.txt`、`cluster-dns.service`、`multipath.conf`、`sudoers`、`sudoers.d-ls.txt`、`sshd_config`、`netplan.tar`、`dpkg-selections.txt`、`dpkg-l.txt`、`ip.txt`、`iptables.txt`、`mounts-units.txt`、`iscsi-lsblk.txt`、`conffiles-modified.txt`、pablo の Pod の一覧、Longhorn の volume と replica の JSON、ベースラインの `verify-nodes.sh` と `check-apps.sh` の出力。

### 1.5 known_hosts（runbook §5.7）

porkadot を流す前に対処した。

- 作業端末の `~/.ssh/known_hosts` には、192.168.1.134 の行がハッシュした ED25519 の 1 行だけある。porkadot の checkout（4fa3a0f）で `SSHKit::Backend::Netssh::KnownHosts.new.search_for("192.168.1.134", {})` は空を返した（runbook の見込みどおり）
- runbook §5.7 の ED25519 の行しか無いときの確かめ方を使った:
  - ノードの `/etc/ssh/ssh_host_ed25519_key.pub`（2022-09-16 のまま）の fingerprint `SHA256:yAGbJ59XzBF/dF3tTMFKJNPxu9oSIwY13f16K191oII` が known_hosts の ED25519 と一致する。この SSH の接続で `/etc/ssh/ssh_host_ecdsa_key.pub` を読んだ
  - その fingerprint `SHA256:7A2BEcF62bN52r9n+Zc5iAsSb1ynbFGyjvTGFO5cDFA` が、`ssh-keyscan -t ecdsa 192.168.1.134` の fingerprint と一致する
- 00:43Z: `known_hosts.bak-20261018-pablo` に控えを取り、ハッシュしない 1 行を足した（サンドボックスの外での実行をユーザーが承認）。足した後、sshkit は `ecdsa-sha2-nistp256` を返す

## 2. cordon と drain（runbook §3.3）

00:4xZ にユーザーが、別タスクの braque の nfsd の本番の入れ替え（apply）を pablo の作業中に行わないことを了承した。

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 00:46:07 | ✋ `infra-admin` のトークンを発行（3h） | 作業端末の 600 のファイルに置いた。`auth can-i patch nodes` が yes |
| 00:46:12 | ✋ `cordon pablo` | Ready,SchedulingDisabled |
| 00:46:12 | ✋ `concurrent-replica-rebuild-per-node-limit` を `0`、`replica-auto-balance` を `disabled`（§2.5） | 直前の値は `5`、`least-effort`。読み直して変わり、APPLIED true。pablo には最後の replica を持つボリュームが無いので、`node-drain-policy` は変えていない（§2.4） |
| 00:46:22 | ✋ `drain pablo --ignore-daemonsets --delete-emptydir-data --timeout=20m` | 00:46:49 に `node/pablo drained`（rc 0）。pablo の instance-manager の PDB で 2 回（5 秒ずつ）待っただけ。コントローラを持たない Pod が無いので `--force` は付けていない |

- 退いた Pod は、すべて oeilvert で起動した（`docker/registry`、`fs/h2`、share-manager の 2 つ、`minio-3`、`holyorder-preview/preview`、`alertmanager-kube-prometheus-0`、`comics-webdav`、`aphrael` など）。`aphrael` はイメージの pull で 2 分ほど ContainerCreating だった。00:48 に Running / Completed 以外の Pod は 0 個
- drain の後の確認（runbook §3.3 の pablo）: share-manager の 2 つ、`fs/h2`、`docker/registry` は oeilvert で Running。oeilvert のホストの `/home/yuanying/shared/h`（`h2.fs.svc.cluster.local:/`）が読める。`registry.fraction.jp/v2/` は 401（認証が要るという応答）
- Longhorn: pablo でアタッチしているボリュームは無い。attached healthy 22、attached degraded 1（`fs/h2`。pablo の replica が stopped）、detached 2。replica は 45 個で、drain の前と同じ数（pablo の 1 つは stopped）。ほかのノードに新しい replica は作られていない
- iSCSI のセッションが 2 つ残った（`TRANSPORT WAIT`）。行き先は退いた pablo の instance-manager（10.244.4.46）で、`fs/h2` と、drain の前からあった `minio/export-minio-1` の古いセッション。マウントはされていない。ほかのノードと同じく §3.4 の 9 の再起動で片付ける
- pablo の replica が止まったのは 00:46 ごろ。`replica-replenishment-wait-interval`（100 分）の内側で設定を戻すには、02:26 ごろまでに §3.8 の 3 を行う

## 3. 22.04 のまま containerd を置き換える（runbook §3.4）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 00:48:5x | ✋ 0: `/root` で `apt-get download containerd.io=1.6.8-1` | `/root/containerd.io_1.6.8-1_amd64.deb`（28.1MB、sha256 `74ce6b6b440073b6…`、ほかの 4 台と同じ） |
| 00:48:55 | ✋ 1: `docker.list` を `docker.list.disabled-20261018` に名前を変え、`apt-get update` | `containerd.io` の候補は 1.6.8-1、`containerd` の候補は 2.2.1-0ubuntu1~22.04.2 |
| 00:49:27〜00:52:3x | ✋ 2: `apt-get full-upgrade` | rc 0。109 upgraded、8 newly installed、0 removed（下の 3.1） |
| 00:52:48 | ✋ 3: `apt-get install containerd` | 先に `-s` で、消えるのが `containerd.io` だけであることを確かめた。`containerd` 2.2.1-0ubuntu1~22.04.2 と `runc` 1.3.4-0ubuntu1~22.04.1 が入り、`containerd.io` は `rc` |
| 00:53:0x | 4: `config.toml` を `config.toml.porkadot-bak.20261018` に名前を変える | `containerd config default` は `version = 3` |
| 00:53:15〜00:53:19 | ✋ 5: `porkadot setup-containerd --config ./porkadot.yaml --node pablo`（porkadot 4fa3a0f、asset はこのブランチの base a157440） | rc 0。`ERROR`、`Unsupported containerd config version`、`HostKeyMismatch` は無い |
| 00:53:31 | ✋ 7: `systemctl restart kubelet` | Ready,SchedulingDisabled、`containerd://2.2.1`、OS-IMAGE は `Ubuntu 22.04.5 LTS`。DaemonSet の Pod 8 つが Running |
| 00:54:26 | ✋ 8: dns addon の修正を (b) で当てる | 下の 3.3 |

### 3.1 full-upgrade

- ほかの 3 台と同じく非対話で流した: `systemd-run --unit=full-upgrade-20261018` の中で、`DEBIAN_FRONTEND=noninteractive`、`UCF_FORCE_CONFFOLD=1`、dpkg の `--force-confdef --force-confold`。ログはノードの `/root/full-upgrade-20261018.log`
- 先に `apt-get -s full-upgrade` で、削除されるものが無いことを確かめた。kernel（5.15.0-198 は入っている）と systemd は更新に含まれていなかった
- conffile: `/etc` の `*.dpkg-*` と `*.ucf-*` は前後で変わらなかった（前からあるのは `ca-certificates.conf.dpkg-old`、`default/grub.ucf-dist`、`ssh/sshd_config.ucf-dist`）。`/etc/sudoers`（`NOPASSWD`、`sudo -n true` が通る）と `/etc/multipath.conf`（addon の版）はそのまま
- 更新されなかったもの: `open-vm-tools`（phased update。chirico、oeilvert と同じ）。systemd 本体は 249.11-0ubuntu3.23 のまま。nftables 1.0.2-1ubuntu3.1、multipath-tools 0.8.8-1ubuntu1.22.04.4
- 終わった後: `/var/run/reboot-required` あり（10-07 から）。cnidaria の経路（proto 200）は v4・v6 とも 7 本。kubelet、containerd、multipathd は active

### 3.2 containerd の確認（runbook §3.4 の 6・7）

- `containerd --version` が 2.2.1。`/etc/containerd/config.toml` は `version = 3`、`sandbox = 'registry.k8s.io/pause:3.10.1'`、`[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]` の下に `SystemdCgroup = true`
- `sudo /opt/bin/crictl info` が応答する。`crictl images` は 188 行で、イメージが引き継がれている
- `setup-containerd` で再起動した後の containerd の journal に、migrate の警告と `Ignoring unknown key` は無い。`ctr deprecations list` は空
- DaemonSet の Pod は、containerd の置き換えでも kubelet の再起動でも再起動しなかった（ほかの 4 台と同じ）

### 3.3 dns addon の修正（runbook §3.4 の 8、(b)）

- unit は、このブランチの `assets/kubelet-default/addons/dns/install.sh` の quoted heredoc を `sed` で取り出して使った。oeilvert の今の unit と 1 文字も違わないことを `diff` で確かめた
- 元の unit は `/root/cluster-dns.service.bak-20261018` に写した。`daemon-reload`、`reenable`、`restart` を流した。`reenable` はほかのノードと同じ `non-existent unit` の警告を出した（害はない）
- `cluster-dns` は active。`resolvectl status porka-dummy01` は DNS Servers 10.254.0.10、DNS Domain `cluster.local default.svc.cluster.local svc.cluster.local`。cnidaria の経路（proto 200）は v4・v6 とも 7 本のまま

### 3.4 22.04 の再起動（runbook §3.4 の 9・10）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 01:00:11 | 9: `systemctl reboot`（ユーザーが承認） | journal は 01:00:15 に止まった。kernel の起動は 01:05:02（`uptime -s`）。01:05:55 に SSH が上がり、01:06 に Ready |

- 止めてから kernel が起動するまで約 5 分（chirico 約 5 分、duchamp 約 17 分、oeilvert 約 2 分、braque 約 30 秒）。起動は 47 秒（kernel 21.6s、userspace 25.2s）
- 起動の後: kernel 5.15.0-198-generic、`containerd://2.2.1`、config は `version = 3` のまま。containerd の journal に migrate の警告や `Ignoring unknown key` は無い。`ctr deprecations list` は空。`registry.k8s.io/pause:3.10.1` は pull 済み
- kubelet は containerd の socket ができる前に起動に失敗し、systemd がやり直して上がった（ほかの 4 台と同じ）
- DaemonSet の Pod は 8 つとも Running（restart が 1〜3 回増えた）。Pending の CSR は無い
- runbook §3.7 の 8〜13: `/var/lib/longhorn` はマウントされている。**iSCSI の古いセッションは消えた**（`No active sessions`）。multipathd と `iscsid.socket` は active。`sudo -n true` が通る。`cluster-dns` は active で `porka-dummy01` に 10.254.0.10 と検索ドメイン。`systemctl --failed` は空（事前の `fwupd-refresh` も消えた）。`ordering cycle` は 0。cnidaria の経路は v4・v6 とも 7 本。`/var/run/reboot-required` は無い

## 4. `do-release-upgrade`（runbook §3.5）

### 4.1 前提の確認（§3.5 の 1）

- `apt list --upgradable` は `open-vm-tools`（phased update）だけ。`/var/run/reboot-required` は無い。`/` の空きは 141G。`sources.list.d` は `docker.list.disabled-20261018` だけ
- `Prompt=lts`、`ubuntu-release-upgrader-core` は 1:22.04.21（full-upgrade で 22.04.10 から上がった）。`do-release-upgrade -c` は `New release '24.04.5 LTS' available`
- 手元で変わっている conffile は chirico、duchamp、braque と同じ: dpkg の md5 が合わないのは `/etc/sudoers`、`/etc/multipath.conf`、`/etc/containerd/config.toml`（`containerd.io` の `rc` の残り）。ucf で合わないのは `/etc/ssh/sshd_config`

### 4.2 実行（非対話）

| 時刻（UTC） | 出来事 |
|---|---|
| 01:06:54 | `systemd-run --unit=release-upgrade --setenv=DEBIAN_FRONTEND=noninteractive --setenv=UCF_FORCE_CONFFOLD=1 do-release-upgrade -f DistUpgradeViewNonInteractive` |
| 01:11:36 | パッケージの入れ替えが始まった（`history.log`） |
| 01:12:51〜01:20:12 | **作業端末から新しい SSH の接続ができなかった**（port 22 が `Connection refused`）。20 秒ごとに見て、約 8 分 |
| 01:18:29 | `/etc/sudoers` の conffile の質問に `no`（手元の版を残す）と答えた（`main.log`） |
| 01:21:55〜01:22:11 | 不要になったパッケージの purge |
| 01:22:15 | `confirmRestart() called`（main.log の最後）。unit は `Result=success`、`ExecMainStatus=0`。再起動はしていない |

所要時間は約 15 分。

### 4.3 再起動の前の確認（§3.5 の 3）

conffile の扱い:

| ファイル | 結果 |
|---|---|
| `/etc/sudoers` | 手元の版のまま（`%sudo ALL=(ALL:ALL) NOPASSWD:ALL`）。`sudo -n true` が通る。メンテナの版は `/etc/sudoers.dpkg-dist` に置かれた |
| `/etc/ssh/sshd_config`（ucf） | 手元の版のまま（2022-09-16 の版、末尾に `PasswordAuthentication no`）。`sshd_config.ucf-dist` が新しい版で置かれた |
| `/etc/multipath.conf` | 質問は出ず、addon の版のまま（multipath-tools 0.9.4-5ubuntu8.2） |
| `/etc/nfs.conf`、`/etc/default/nfs-common`（ucf） | 手元の版のまま。`.ucf-dist` が新しく置かれた（oeilvert、braque と同じ） |
| `/etc/containerd/config.toml` | §3.4 で作った version 3 のまま |

削除されたもの（`/var/log/dist-upgrade/history.log`。Remove 48 個、Purge 60 個。braque と同じ数）:

- `Remove:` は、24.04 で名前が変わったライブラリの古い名前（`libcurl4`、`libapt-pkg6.0`、`libelf1` など）と、`gpg-wks-server`、`python3-distutils`、`usrmerge`
- `Purge:` は 5.15.0-194 の kernel 一式、python3.10、`perl-modules-5.34`、**`irqbalance`**、`isc-dhcp-client`、`isc-dhcp-common`、`binutils` 一式、`policykit-1`、`pkexec`、`ubuntu-advantage-tools` など（ほかの台と同じ）
- **Remove と Purge のどちらにも入っていないもの**: `containerd`、`runc`、`open-iscsi`、`nfs-common`、`multipath-tools`、`sudo`、`openssh-server`、`ufw`。どれも 24.04 の版で入っている。`ufw` は消えなかった（`iptables-persistent` が無いため。braque と同じ）

版（再起動の前）: `containerd` 2.2.1-0ubuntu1~24.04.3、`runc` 1.3.4-0ubuntu1~24.04.1、`nftables` 1.0.9-1ubuntu0.1、`multipath-tools` 0.9.4-5ubuntu8.2、`open-iscsi` 2.1.9-3ubuntu5.5、`nfs-common` 1:2.6.4-3ubuntu5.1、`openssh-server` 1:9.6p1-3ubuntu13.20、`ufw` 0.36.2-6。kernel は 5.15.0-198 と 6.8.0-147。

apt の source は `ubuntu.sources`（noble）と、外した `docker.list.disabled-20261018`。`third-party.sources` はできなかった。
再起動の前、cnidaria の経路は 7 本のままだった。

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 01:23:34 | 4: `systemctl reboot`（ユーザーが承認） | journal は 01:23:38 に止まった。kernel の起動は 01:25:23（`uptime -s`）。01:25:56 に SSH が上がり、01:26 に Ready（SchedulingDisabled）、Ubuntu 24.04.5、6.8.0-147-generic、`containerd://2.2.1` |

- 止めてから kernel が起動するまで約 2 分。起動は 21 秒（kernel 2.9s、userspace 17.9s）

## 5. 24.04 での確認（runbook §3.6・§3.7）

版:

| 項目 | 値 |
|---|---|
| OS | Ubuntu 24.04.5 LTS |
| kernel | 6.8.0-147-generic |
| containerd | 2.2.1-0ubuntu1~24.04.3（`containerd://2.2.1`） |
| runc | 1.3.4-0ubuntu1~24.04.1 |
| nftables | 1.0.9 |
| kubelet | v1.29.8 |
| irqbalance | 1.9.3-2ubuntu5（再起動の後に入れ直した） |

- §3.6: `/etc/containerd/config.toml` は §3.4 で作った version 3 のまま（`SystemdCgroup = true`、`registry.k8s.io/pause:3.10.1`）。migrate の警告や `Ignoring unknown key` は無い。`ctr deprecations list` は空。containerd と kubelet は active。kubelet は起動直後に 1 度 containerd の socket が無くて失敗し、やり直して上がった（ほかの 4 台と同じ）。`setup-containerd` の再実行は要らなかった
- 01:27:01: ✋ `apt-get install -y irqbalance`（§3.5 の 6）。1.9.3-2ubuntu5 が入り、active

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready,SchedulingDisabled。24.04.5、6.8.0-147-generic、`containerd://2.2.1`。ラベル `metallb=speaker` が残っている |
| 2 | CSR | Pending は無い |
| 3 | DaemonSet の Pod | cnidaria、kube-proxy、engine-image、longhorn-csi-plugin、longhorn-manager、speaker、node-exporter、smart-exporter が Running |
| 4 | ログ | cnidaria のログが読める |
| 5 | cnidaria | `verify-nodes.sh` は 64 PASS、FAIL 0。cnidaria のログに error は無い。01:25:56 に経路を入れて nft のテーブルを適用した |
| 6 | ホストの nft | 1.0.9。`nft list tables` は `inet cnidaria` を含めて rc 0 |
| 7 | iptables | v4・v6 とも FORWARD の policy は ACCEPT、`CNIDARIA-FWD` へのジャンプが先頭 |
| 8 | ディスク | `/var/lib/longhorn`（`/dev/sda`、1.8T）がマウントされている |
| 9 | ZFS | pablo には無い |
| 10 | multipath と iSCSI | `/etc/multipath.conf` は addon の版。multipathd と `iscsid.socket` は active。iSCSI のセッションは無い |
| 11 | sudo | `sudo -n true` が通る |
| 12 | DNS | `cluster-dns` は修正済みの版で active。`porka-dummy01` に 10.254.0.10 と検索ドメイン |
| 13 | 失敗している unit | 無い。`ordering cycle` も 0 |

pablo の追加の確認（runbook §3.7）: `fs/h2`、`docker/registry`、share-manager の 2 つは、drain で移った oeilvert で Running のまま（uncordon の後も戻ってこない。§6）。

## 6. uncordon と後始末（runbook §3.8）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 01:27:16 | ✋ `uncordon pablo` | Ready。Longhorn の node の pablo は Ready で schedulable。`node-drain-policy` は変えていないので戻すものは無い |
| 01:27:26 | ✋ `concurrent-replica-rebuild-per-node-limit` を `5`、`replica-auto-balance` を `least-effort` に戻す | 読み直して `5`、`least-effort`、`block-if-contains-last-replica`、APPLIED true。drain で replica が止まってから約 41 分 |
| 01:27〜01:41:4x | 再同期を待つ | `fs/h2` の pablo の replica が再同期し、01:41 に healthy |
| 01:41:47〜02:12:0x | data locality による replica の移動 | 下 |
| 01:43:02〜01:43:19 | ✋ `netcheck.sh up` → `run` → `down` | `PASS 168 / 168, pods 8/8`。namespace は消した |
| 01:43 | `check-apps.sh` | ベースラインと差が無い |
| 02:12:32 | トークンを破棄（作業端末のファイルを消した。トークン自体は 03:46 に失効する） | |

- `fs/h2`（pvc-c4944b75、replica 2、data locality `best-effort`）は、drain で Pod が oeilvert に移ったので、Longhorn が oeilvert に新しい replica を作り（01:41:47。300G を全体コピー）、02:12 に終わった後、pablo の replica を消した。replica は chirico と oeilvert の 2 つになった（duchamp、oeilvert と同じ現象。runbook §3.8 の 3）。コピーの間もボリュームは healthy だった
  - その結果、**pablo に Longhorn の replica は 1 つも無くなった**。ノードごとの数は chirico 17、duchamp 10、oeilvert 18、pablo 0（ベースラインは 17、10、17、1）。replica は 45 個のまま
  - 古い replica を engine から外すときに `Removing unknown replica tcp://10.244.4.91:10000 in mode ERR from engine` の event が出た。消す replica を外す時のもので、ボリュームは healthy のまま
- Longhorn: attached healthy 23、detached unknown 2（myao、cg-data。ベースラインと同じ）
- Running / Completed 以外の Pod は 0 個
- drain で oeilvert に移った Pod（`docker/registry`、`fs/h2`、share-manager の 2 つ、`minio-3` など）は、uncordon の後も oeilvert で動いている。pablo の Pod は DaemonSet の 8 つと、Longhorn の instance-manager の 9 個

## 7. 完了の確認（runbook §3.9、§6.1。30 分の様子見を除く）

| 条件 | 結果 |
|---|---|
| 全 8 台が Ready。pablo が 24.04.5 と `containerd://2.2.1` | 満たす。**worker 5 台がすべて 24.04.5 / 6.8.0-147 / `containerd://2.2.1`** になった |
| etcd 3/3 healthy、VIP が応答 | 満たす（`/readyz` は `ok`） |
| Running / Completed 以外の Pod がベースラインから増えていない | 満たす（0 個） |
| Longhorn のボリュームが healthy、再構築が終わっている | 満たす（02:12 に data locality のコピーも終わった） |
| `verify-nodes.sh`、`netcheck.sh`、`check-apps.sh` がベースラインと同じ | 満たす（64 PASS、168/168、差なし） |
| Longhorn の設定が元に戻っている | 満たす（`5`、`least-effort`、`block-if-contains-last-replica`）。MinIO 4/4、Prometheus 2 は変えていない |
| LoadBalancer | TCP のものはすべて応答（gated v4/v6 の 80・443、h2-sshd、natsumi-sshd の 3 つ、VIP の 6443）。minecraft は UDP なので確かめていない |
| pablo の確認（runbook §3.7） | 満たす（`fs/h2`、`docker/registry`、share-manager が Running。oeilvert のホストの `shared/h` が読め、`registry.fraction.jp/v2/` は 401） |
| 30 分の様子見 | この記録の時点（02:12Z）で 24.04 で起動してから約 47 分、再起動や NotReady は無い |

## 8. runbook を直した点

- §1.5: dns addon の修正が 5 台すべてに当たったことを表に書いた
- §3.3 の pablo: drain で退いた Pod がすべて oeilvert に移り、uncordon しても戻らないこと
- §3.4 の 9: pablo での 22.04 の再起動で、止めてから kernel が起動するまでの時間（約 5 分）
- §3.8 の 3: pablo では、`fs/h2` の replica が data locality で oeilvert に移り、pablo に replica が残らなかったこと
- §5.7: pablo は対処済み

## 9. 申し送り

- pablo の `/root` に `containerd.io_1.6.8-1_amd64.deb`、`cluster-dns.service.bak-20261018`、`full-upgrade-20261018.log` が、`/etc/apt/sources.list.d/docker.list.disabled-20261018` と `/etc/containerd/config.toml.porkadot-bak.20261018` が残っている（runbook §6.2 で片付ける）。`containerd.io` は `rc` の状態
- 作業端末の `~/.ssh/known_hosts.bak-20261018-pablo` は known_hosts の控え
- **drain で pablo から退いた Pod は、すべて oeilvert に集まった**（`docker/registry`、`fs/h2`、share-manager の 2 つ、`minio-3`、`alertmanager-kube-prometheus-0`、`holyorder-preview`、`comics-webdav`、`aphrael` など）。uncordon しても Pod は戻らないので、oeilvert を止めると、これらが一度に止まる。pablo は DaemonSet のほかにほぼ何も載っていない状態である。散らすかどうかはユーザーの判断
- pablo に Longhorn の replica が無くなった（§6）。`replica-auto-balance` が `least-effort` なので、Longhorn が後で置くことがある
