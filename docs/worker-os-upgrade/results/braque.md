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
| ZFS | `tank1`（raidz1、7.3T×3）は ONLINE、2026-10-11 の scrub はエラー 0。vdev は `/dev/disk/by-partlabel/zfs-tank1-{0,1,2}`。`tank1/export` を `/export`（5.1T 使用、9.4T 空き）。**`zfs-import-cache` は disabled**、`zfs-import-scan`、`zfs-mount`、`zfs.target`、`zfs-zed` は enabled（この読み取りの時点では見落とした。§3.4 を参照）。`zfsutils-linux` 2.1.5-1ubuntu6~22.04.7 |
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

## 2. cordon と drain（runbook §3.3）

23:37Z にユーザーがコンソールを用意し、23:3xZ に §3.3 の braque の事前確認（`registry.fraction.jp` のイメージを使うデプロイをしない、`fs/*-restore` はそのままにする、nfsd のイメージを控える）に答えた。

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 23:37:59 | ✋ `infra-admin` のトークンを発行（3h） | 作業端末の 600 のファイルに置いた。`auth can-i patch nodes` が yes |
| 23:38:07 | ✋ `cordon braque` | Ready,SchedulingDisabled |
| 23:38:07 | ✋ `concurrent-replica-rebuild-per-node-limit` を `0`、`replica-auto-balance` を `disabled`（§2.5） | 直前の値は `5`、`least-effort`。読み直して変わり、APPLIED true。braque には replica が無いので `node-drain-policy` は変えていない（§2.4） |
| 23:38:10 | ✋ `drain braque --ignore-daemonsets --delete-emptydir-data --timeout=20m` | 同じ秒に `node/braque drained`（rc 0）。DaemonSet の Pod（cnidaria、kube-proxy、node-exporter、smart-exporter、nfsd）だけなので、動いた Pod は無い。コントローラを持たない Pod は無い |

## 3. 22.04 のまま containerd を置き換える（runbook §3.4）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 23:38:19 | ✋ 0: `/root` で `apt-get download containerd.io=1.6.8-1` | sha256 `74ce6b6b440073b6…`（chirico、duchamp と同じ） |
| 23:38:2x | ✋ nfsd のイメージを控える（runbook に無い。ユーザーが承認）: `ctr -n k8s.io images export /root/volume-nfs-0.8.tar gcr.io/google_containers/volume-nfs:0.8` | 87MB。消えたときは `ctr -n k8s.io images import` で戻す |
| 23:38:30 | ✋ 1: `docker.list` を `docker.list.disabled-20261017` に名前を変え、`apt-get update` | `containerd.io` の候補は 1.6.8-1、`containerd` の候補は 2.2.1-0ubuntu1~22.04.2 |
| 23:39:25〜23:45:1x | ✋ 2: `apt-get full-upgrade` | rc 0。109 upgraded、8 newly installed、0 removed、0 not upgraded（下の 3.1） |
| 23:45:26 | ✋ 3: `apt-get install containerd` | 先に `-s` で、消えるのが `containerd.io` だけであることを確かめた。`containerd` 2.2.1-0ubuntu1~22.04.2 と `runc` 1.3.4-0ubuntu1~22.04.1 が入り、`containerd.io` は `rc` |
| 23:45:4x | 4: `config.toml` を `config.toml.porkadot-bak.20261017` に名前を変える | `containerd config default` は `version = 3` |
| 23:45:53〜23:45:56 | ✋ 5: `porkadot setup-containerd --config ./porkadot.yaml --node braque`（porkadot 4fa3a0f、asset はこのブランチの base 4a30bb2） | rc 0。`ERROR`、`Unsupported containerd config version`、`HostKeyMismatch` は無い |
| 23:46:03 | ✋ 7: `systemctl restart kubelet` | Ready,SchedulingDisabled、`containerd://2.2.1`、OS-IMAGE は `Ubuntu 22.04.5 LTS`。DaemonSet の Pod 5 つが Running（restart 0） |
| 23:46:38 | ✋ 8: dns addon の修正を (b) で当てる | 下の 3.3 |

### 3.1 full-upgrade

- duchamp、oeilvert と同じく非対話で流した: `systemd-run --unit=full-upgrade-20261017` の中で、`DEBIAN_FRONTEND=noninteractive`、`UCF_FORCE_CONFFOLD=1`、dpkg の `--force-confdef --force-confold`。ログはノードの `/root/full-upgrade-20261017.log`
- 先に `apt-get -s full-upgrade` で、削除されるものが無いことを確かめた。kernel（5.15.0-198 は入っている）、ZFS、systemd は更新に含まれていなかった。multipath-tools は 0.8.8-1ubuntu1.22.04.4 に上がった
- conffile: `/etc` の `*.dpkg-*` と `*.ucf-*` は前後で変わらなかった（前からあるのは `ca-certificates.conf.dpkg-old`、`containerd/config.toml.dpkg-dist`、`default/grub.ucf-dist`、`ssh/sshd_config.ucf-dist`）。fwupd などの使われなくなった conffile は消された
- 終わった後: `/var/run/reboot-required` あり（前から）。cnidaria の経路（proto 200）は v4・v6 とも 7 本。kubelet、containerd、multipathd は active。`sudo -n true` が通る。nftables は 1.0.2-1ubuntu3.1、systemd は 249.11-0ubuntu3.23 のまま

### 3.2 containerd の確認（runbook §3.4 の 6・7）

- `containerd --version` が 2.2.1。`/etc/containerd/config.toml` は `version = 3`、`sandbox = 'registry.k8s.io/pause:3.10.1'`、`[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]` の下に `SystemdCgroup = true`
- `sudo /opt/bin/crictl info` が応答する。`crictl images` は 27 個で、nfsd の `volume-nfs:0.8` も残っている
- `setup-containerd` で再起動した後（23:45:55 以降）の containerd の journal に、migrate の警告と `Ignoring unknown key` は無い（その前、古い config で起動した 23:45:40 の分にはあった）。`ctr deprecations list` は空
- DaemonSet の Pod は、containerd の置き換えでも kubelet の再起動でも再起動しなかった（ほかの 3 台と同じ）

### 3.3 dns addon の修正（runbook §3.4 の 8、(b)）

- unit は、このブランチの `assets/kubelet-default/addons/dns/install.sh` の quoted heredoc を `sed` で取り出して使った。oeilvert の今の unit と 1 文字も違わないことを `diff` で確かめた
- 元の unit は `/root/cluster-dns.service.bak-20261017` に写した。`daemon-reload`、`reenable`、`restart` を流した。`reenable` は ほかのノードと同じ `non-existent unit` の警告を出した（害はない）
- `cluster-dns` は active。`resolvectl status porka-dummy01` は DNS Servers 10.254.0.10、DNS Domain `cluster.local default.svc.cluster.local svc.cluster.local`。cnidaria の経路（proto 200）は v4・v6 とも 7 本のまま

### 3.4 22.04 の再起動（runbook §3.4 の 9・10）と ZFS の取り込み漏れ

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 23:47:40 | 9: `systemctl reboot`（ユーザーがコンソールをつないでから承認） | journal は 23:47:45 に止まった。kernel の起動は 23:48:14（`uptime -s`）。23:50:34 に SSH が上がり、Ready |
| 23:50:4x | 10: 確認 | **ZFS の `tank1` が取り込まれず、`/export` がマウントされていなかった**（下）。ほかは問題なし |
| 23:53:04 | ✋ `zpool import tank1`（runbook に無い。ユーザーが承認） | rc 0。`all pools are healthy`、`tank1/export` が `/export` にマウントされ、データがある |
| 23:53:10 | ✋ nfsd の Pod（`nfsd/nfsd-mg9pv`）を消す（runbook に無い。ユーザーが承認） | 23:53:17 に新しい Pod（`nfsd-wxsnb`）が Running。コンテナの `/exports` は `tank1/export` |
| 23:53:1x | ✋ `systemctl enable zfs-import-cache.service`（runbook に無い。ユーザーが承認） | enabled |
| 23:54:01 | NFS を使う Pod の回復を確かめる | Running / Completed 以外の Pod は 0 個。`registry.fraction.jp/v2/` は 401（認証が要るという応答で、正常） |

- **止めてから kernel が起動するまで約 30 秒**（chirico 約 5 分、duchamp 約 17 分、oeilvert 約 2 分）。ただし起動は 2 分 43 秒かかった（firmware 10.9s、loader 10.6s、kernel 7.3s、userspace 2min 14.7s）。userspace のほとんどは `systemd-networkd-wait-online.service`（2 分で時間切れで failed。更新前からの失敗。調査 §2.1）
- 起動の後: kernel 5.15.0-198-generic、`containerd://2.2.1`、config は `version = 3` のまま。containerd の journal に migrate の警告や `Ignoring unknown key` は無い。`ctr deprecations list` は空。DaemonSet の Pod 5 つが Running（restart が 1 回ずつ増えた）。Pending の CSR は無い
- runbook §3.7 の 8〜13: iSCSI のセッションは無い。multipathd と `iscsid.socket` は active。`sudo -n true` が通る。`cluster-dns` は active で `porka-dummy01` に 10.254.0.10 と検索ドメイン。`systemctl --failed` は `systemd-networkd-wait-online.service` だけ（更新前から。`fwupd-refresh` は消えた）。`ordering cycle` は 0。cnidaria の経路は v4・v6 とも 7 本。`/var/run/reboot-required` は無い

#### ZFS の取り込み漏れ

- 原因は更新前からの設定である。`zfs-import-cache.service` が **disabled** で、`zfs-import-scan.service` は enabled だが `ConditionFileNotEmpty=!/etc/zfs/zpool.cache`（cache file があると動かない）で飛ばされた。起動時に pool を取り込む unit が無かった。`zfs-mount.service` は走ったが、pool が無いので何もマウントしなかった
- 前の起動（2026-01-10）でも同じだったと見られる。その journal には、起動の 3 分後に手で `sudo zpool import -a` を流した記録がある
- vdev は partlabel（`/dev/disk/by-partlabel/zfs-tank1-*`）なので、起動で `sd*` の名前が変わっても（`zfs-tank1-0` が sdd1 → sdb1）影響は無い。`zpool import` は `tank1` を ONLINE で取り込めると示した
- **その間、nfsd の Pod は root のディスクの空の `/export` を公開していた**（hostPath の `/export`。中身は nfsd が起動時に書く `index.html` だけ）。braque の NFS は 23:47:40〜23:53:17 の間、止まっているか、別のディレクトリを見せていた
  - nfsd の Pod は、`/export` を取り込みの前にバインドしているので、取り込んだ後も古いディレクトリを見続ける。そのため Pod を消して作り直させた
  - 下に隠れた root のディスクの `/export/index.html` は残っている（害は無いので消していない）
- NFS を使う Pod への影響: `carib2`、`pondo2`、`shja2` の movies は liveness probe で再起動して CrashLoopBackOff に、`docker/registry`（pablo）は `stale NFS file handle` でコンテナを作れず CrashLoopBackOff になった。どれも作り直した nfsd の Pod が上がった後、手を加えずに Running に戻った（23:54:01 に 0 個）。oeilvert のホストの `shared/nfs` と `fs/*-restore` の 3 つは読めた
- `zfs-import-cache.service` を enable したので、24.04 の再起動（§3.5 の 4）では起動時に取り込まれる見込み

## 4. `do-release-upgrade`（runbook §3.5）

### 4.1 前提の確認（§3.5 の 1）

- `apt list --upgradable` は空。`/var/run/reboot-required` は無い。`/` の空きは 87G。`sources.list.d` は `docker.list.disabled-20261017` だけ
- `Prompt=lts`、`ubuntu-release-upgrader-core` は 1:22.04.21。`do-release-upgrade -c` は `New release '24.04.5 LTS' available`
- 手元で変わっている conffile は chirico、duchamp と同じ: dpkg の md5 が合わないのは `/etc/sudoers`、`/etc/multipath.conf`、`/etc/containerd/config.toml`（`containerd.io` の `rc` の残り）。ucf で合わないのは `/etc/ssh/sshd_config`

### 4.2 実行（非対話）

| 時刻（UTC） | 出来事 |
|---|---|
| 23:54:21 | `systemd-run --unit=release-upgrade --setenv=DEBIAN_FRONTEND=noninteractive --setenv=UCF_FORCE_CONFFOLD=1 do-release-upgrade -f DistUpgradeViewNonInteractive` |
| 23:59:33 | パッケージの入れ替えが始まった（`history.log`） |
| 23:59:40、00:03:08〜00:11:49 | **作業端末から新しい SSH の接続ができなかった**。20 秒ごとに見て、00:03〜00:11 の約 9 分続いた |
| 00:08:43 | `/etc/sudoers` の conffile の質問に `no`（手元の版を残す）と答えた（`main.log`） |
| 00:14:30〜00:14:55 | 不要になったパッケージの purge |
| 00:15:03 | `confirmRestart() called`（main.log の最後）。unit は `Result=success`、`ExecMainStatus=0`。再起動はしていない |

所要時間は約 21 分。

### 4.3 再起動の前の確認（§3.5 の 3）

conffile の扱い:

| ファイル | 結果 |
|---|---|
| `/etc/sudoers` | 手元の版のまま（`%sudo ALL=(ALL:ALL) NOPASSWD:ALL`）。`sudo -n true` が通る。メンテナの版は `/etc/sudoers.dpkg-dist` に置かれた |
| `/etc/ssh/sshd_config`（ucf） | 手元の版のまま（末尾に `PasswordAuthentication no`） |
| `/etc/multipath.conf` | 質問は出ず、addon の版のまま（multipath-tools 0.9.4-5ubuntu8.2） |
| `/etc/default/nfs-common`（ucf） | 手元の版のまま。`.ucf-dist` が新しく置かれた |
| `/etc/containerd/config.toml` | §3.4 で作った version 3 のまま |

削除されたもの（`/var/log/dist-upgrade/history.log`。Remove 48 個、Purge 60 個）:

- `Remove:` は、24.04 で名前が変わったライブラリの古い名前（`libcurl4`、`libext2fs2` など）と、`gpg-wks-server`、`python3-distutils`、`usrmerge`
- `Purge:` は 5.15.0-164 の kernel 一式、python3.10、`perl-modules-5.34`、**`irqbalance`**、`isc-dhcp-client`、`isc-dhcp-common`、`binutils` 一式、`policykit-1`、`pkexec`、`ubuntu-advantage-tools` など（chirico、duchamp と同じ）
- **Remove と Purge のどちらにも入っていないもの**: `containerd`、`runc`、`zfsutils-linux`、`zfs-zed`、`open-iscsi`、`nfs-common`、`multipath-tools`、`sudo`、`openssh-server`、`ufw`。どれも 24.04 の版で入っている。`ufw` は消えなかった（`iptables-persistent` が無いため。runbook §3.5 の 3 の見込みどおり）

版（再起動の前）: `containerd` 2.2.1-0ubuntu1~24.04.3、`runc` 1.3.4-0ubuntu1~24.04.1、`zfsutils-linux` 2.2.2-0ubuntu9.5、`nftables` 1.0.9-1ubuntu0.1、`multipath-tools` 0.9.4-5ubuntu8.2、`open-iscsi` 2.1.9-3ubuntu5.5、`openssh-server` 1:9.6p1-3ubuntu13.20。kernel は 5.15.0-198 と 6.8.0-147。6.8.0-147 の modules に `zfs.ko`、`spl.ko`、`nfsd.ko` があることを確かめた。

apt の source は `ubuntu.sources`（noble）と、外した `docker.list.disabled-20261017`。`third-party.sources` はできなかった。
`zfs-import-cache.service` は enabled のまま。pool は healthy、`/export` はマウントされている。cnidaria の経路は 7 本のまま。

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 00:17:47 | 4: `systemctl reboot`（ユーザーが承認） | journal は 00:17:53 に止まった。kernel の起動は 00:18:30（`uptime -s`）。00:21:02 に SSH が上がり、Ready（SchedulingDisabled）、Ubuntu 24.04.5、6.8.0-147-generic、`containerd://2.2.1` |

- 止めてから kernel が起動するまで約 40 秒。起動は 3 分 2 秒（firmware 24.6s、loader 10.6s、kernel 5.6s、userspace 2min 21s）。userspace のほとんどは 22.04 のときと同じく `systemd-networkd-wait-online.service` の時間切れ
- **ZFS は起動時に取り込まれた**（`zfs-import-cache.service` が 00:18:49 に active）。`/export` は `tank1/export`。nfsd の Pod のコンテナの `/exports` も `tank1/export`

## 5. 24.04 での確認（runbook §3.6・§3.7）

版:

| 項目 | 値 |
|---|---|
| OS | Ubuntu 24.04.5 LTS |
| kernel | 6.8.0-147-generic |
| containerd | 2.2.1-0ubuntu1~24.04.3（`containerd://2.2.1`） |
| runc | 1.3.4-0ubuntu1~24.04.1 |
| nftables | 1.0.9 |
| zfsutils-linux | 2.2.2-0ubuntu9.5（pool は 2.1 のまま。`zpool upgrade` はしていない） |
| kubelet | v1.29.8 |
| irqbalance | 1.9.3-2ubuntu5（再起動の後に入れ直した） |

- §3.6: `/etc/containerd/config.toml` は §3.4 で作った version 3 のまま（`SystemdCgroup = true`、`registry.k8s.io/pause:3.10.1`）。migrate の警告や `Ignoring unknown key` は無い。`ctr deprecations list` は空。containerd と kubelet は active。kubelet は起動直後に 1 度 containerd の socket が無くて失敗し、やり直して上がった（ほかの 3 台と同じ）。`setup-containerd` の再実行は要らなかった
- 00:21:57: ✋ `apt-get install -y irqbalance`（§3.5 の 6）。1.9.3-2ubuntu5 が入り、active

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready,SchedulingDisabled。24.04.5、6.8.0-147-generic、`containerd://2.2.1`。ラベル（`metallb=speaker`、`nfsd.unstable.cloud/storage=yes`、`tgtd.unstable.cloud/storage`、`node-role.kubernetes.io/lapin`）と taint が残っている |
| 2 | CSR | Pending は無い |
| 3 | DaemonSet の Pod | cnidaria、kube-proxy、node-exporter、smart-exporter、nfsd が Running（kubelet の起動直後に cnidaria が `Unknown`、node-exporter が 0/1 だったが、30 秒ほどで Running になった） |
| 4 | ログ | cnidaria と nfsd のログが読める |
| 5 | cnidaria | `verify-nodes.sh` は 64 PASS、FAIL 0。cnidaria のログに error は無い |
| 6 | ホストの nft | 1.0.9。`nft list tables` は `inet cnidaria` を含めて rc 0 |
| 7 | iptables | v4・v6 とも FORWARD の policy は ACCEPT、`CNIDARIA-FWD` へのジャンプが先頭 |
| 8 | ディスク | `/` のみ（braque は Longhorn のノードでない） |
| 9 | ZFS | `all pools are healthy`。`tank1/export` が `/export` にマウントされている。`zpool upgrade` はしていない |
| 10 | multipath と iSCSI | `/etc/multipath.conf` は addon の版。multipathd と `iscsid.socket` は active。iSCSI のセッションは無い |
| 11 | sudo | `sudo -n true` が通る |
| 12 | DNS | `cluster-dns` は修正済みの版で active。`porka-dummy01` に 10.254.0.10 と検索ドメイン |
| 13 | 失敗している unit | `systemd-networkd-wait-online.service` だけ（更新前から）。`ordering cycle` は 0 |

braque の追加の確認:

- nfsd の Pod が Running で、ポート 2049、111、20048 を v4・v6 で待っている。ホストで `nfsd` と `zfs` のモジュールが読み込まれている
- nfsd のログの `exportfs: / does not support NFS export` は、22.04 のとき（23:53 の起動）にも出ていた
- ほかのノードから NFS が読める: oeilvert のホストの `shared/nfs`、`fs/data-restore`・`h2-restore`・`sites-restore` の `/backup`、`docker/registry` の `/var/lib/registry`（`holyorder-preview`、`llm-wiki`、`yuanying` のリポジトリがある）
- `registry.fraction.jp/v2/` は 401（認証が要るという応答）。pull そのものは試していない（作業端末に認証情報を置いていないため）

### 5.1 LAN から Service の IP に届かなくなった

coordinator から、00:1xZ にユーザーの `ssh dev@h2.fs.svc.fraction.cluster` がつながらなくなったと知らされた（24.04 の再起動の間。braque が戻った後はつながった）。原因は NFS ではない。

- 家のルーター jumelle（net-fraction-private の `hosts/jumelle/config.yaml` の routes、`docs/requirements.md` §6）に、Service の CIDR 10.254.0.0/16 への静的ルートが via 192.168.1.131（braque）で入っている。LAN の dnsmasq は `fraction.cluster` を 10.254.0.10 に条件付きで転送している（ユーザーの指摘で分かった）
- そのため、braque が止まる間は、LAN から Service の IP（`h2.fs.svc.fraction.cluster` = 10.254.0.170 など）への接続と、LAN での `fraction.cluster` の名前解決ができなくなる。22.04 の再起動（§3.4）の間も同じだったはずである
- 作業端末の kubectl は API の VIP（192.168.1.101）を使うので影響は無かった
- 同じ時刻（00:18:04Z と 00:18:10Z）に MetalLB の `nodeAssigned` の event（`fs/h2-sshd` と `natsumi/natsumi-sshd-aki` が 192.168.1.112、`porkadot-kubernetes` が pablo）も出ていたが、braque には speaker が無く、ssh が切れたこととの関係は薄い
- runbook §2.1.1、§3.4 の 9、§3.5 の 4 に、braque の停止中は LAN から 10.254.0.0/16 と `fraction.cluster` の名前解決が使えないことを足した

## 6. uncordon と後始末（runbook §3.8）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 00:23:11 | ✋ `uncordon braque` | Ready |
| 00:23:11 | ✋ `concurrent-replica-rebuild-per-node-limit` を `5`、`replica-auto-balance` を `least-effort` に戻す | 読み直して `5`、`least-effort`、`block-if-contains-last-replica`、APPLIED true。braque には replica が無いので、再同期は無い |
| 00:23:19〜00:23:36 | ✋ `netcheck.sh up` → `run` → `down` | `PASS 168 / 168, pods 8/8`。namespace は消した |
| 00:23:4x | `check-apps.sh` | ベースラインと差が無い |
| 00:23:48 | トークンを破棄（作業端末のファイルを消した。トークン自体は 02:37 に失効する） | |

- Longhorn: attached healthy 23、detached unknown 2（myao、cg-data。ベースラインと同じ）。replica は 45 個のまま
- Running / Completed 以外の Pod は 0 個

## 7. 次の 1 台へ進む条件（runbook §3.9。30 分の様子見を除く）

| 条件 | 結果 |
|---|---|
| 全 8 台が Ready。braque が 24.04.5 と `containerd://2.2.1` | 満たす |
| etcd 3/3 healthy、VIP が応答 | 満たす（`/readyz` は `ok`） |
| Running / Completed 以外の Pod がベースラインから増えていない | 満たす（0 個） |
| Longhorn のボリュームが healthy、再構築が終わっている | 満たす（braque には replica が無い） |
| `verify-nodes.sh`、`netcheck.sh`、`check-apps.sh` がベースラインと同じ | 満たす（64 PASS、168/168、差なし） |
| Longhorn の設定が元に戻っている | 満たす（`5`、`least-effort`、`block-if-contains-last-replica`） |
| LoadBalancer | TCP のものはすべて応答（gated v4/v6 の 80・443、h2-sshd、natsumi-sshd の 3 つ、VIP の 6443）。minecraft は UDP なので確かめていない |
| braque の確認（runbook §3.7） | 満たす（nfsd、ほかのノードから NFS が読める、ZFS） |
| 30 分の様子見 | この記録の時点では 24.04 で起動してから約 6 分 |

## 8. runbook を直した点

- §2.1.1: braque の NFS を使うものに `fs/*-restore` の 3 つを足した。braque が戻った後、NFS を使う Pod が CrashLoopBackOff から自分で戻ること
- §3.3: braque では、ZFS の pool を起動時に取り込む unit が enable されているかを確かめる
- §3.4 の 0: braque の nfsd のイメージを控えたこと
- §2.1.1、§3.4 の 9、§3.5 の 4: **braque が止まっている間は、LAN から Service の IP（10.254.0.0/16）に届かず、`fraction.cluster` の名前を引けない**（ルーターの静的ルートが braque 経由）
- §3.4 の 9: braque での起動の時間
- §3.4 の 10: braque では、まず `tank1` が取り込まれていることを確かめ、取り込まれていなければ取り込んで nfsd の Pod を作り直す
- §3.5 の 3: braque では `ufw` が消えなかった
- §3.7 の braque: nfsd のコンテナの `/exports` が `tank1/export` であること。`exportfs` の警告は前から
- §5.7: braque は対処なしで通った

## 9. 申し送り

- braque の `/root` に `containerd.io_1.6.8-1_amd64.deb`、`volume-nfs-0.8.tar`、`cluster-dns.service.bak-20261017`、`full-upgrade-20261017.log` が、`/etc/apt/sources.list.d/docker.list.disabled-20261017` と `/etc/containerd/config.toml.porkadot-bak.20261017` が残っている（runbook §6.2 で全台の後に片付ける。`volume-nfs-0.8.tar` は nfsd のイメージを置き換えるまで残すほうがよい）。`containerd.io` は `rc` の状態
- root のディスクの `/export`（ZFS の下に隠れたディレクトリ）に、nfsd が書いた `index.html` が残っている
- `zfs-import-cache.service` を enable した（ユーザーの承認）。これで起動時に `tank1` が取り込まれる
- nfsd のイメージ `gcr.io/google_containers/volume-nfs:0.8` は containerd 2.x では pull し直せない。braque の containerd の中のイメージが消えると nfsd が上がらなくなる（`/root/volume-nfs-0.8.tar` を `ctr -n k8s.io images import` で戻す）。別のイメージへの置き換えは、このタスクの範囲外
- `systemd-networkd-wait-online.service` が毎回 2 分待って失敗し、起動を遅らせている（更新前から）
- LAN から Service の CIDR（10.254.0.0/16）への経路が braque 1 台に依存している（§5.1）。braque を止めるたびに、Service の名前で LAN から入るものが切れる
