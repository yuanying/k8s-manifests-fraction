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

## 2. cordon と drain（runbook §3.3）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 13:44:12 | ✋ `infra-admin` のトークンを発行（3h） | 作業端末の 600 のファイルに置いた。`auth can-i patch nodes` が yes |
| 13:44:15 | ✋ `cordon duchamp` | Ready,SchedulingDisabled |
| 13:44:19 | ✋ `concurrent-replica-rebuild-per-node-limit` を `0`、`replica-auto-balance` を `disabled`（§2.5）、`node-drain-policy` を `allow-if-replica-is-stopped`（§2.4） | 直前の値は `5`、`least-effort`、`block-if-contains-last-replica`。読み直して変わり、APPLIED true |
| 13:44:26 | ✋ `monitoring/kube-prometheus` の `spec.replicas` を 2 → 0（§2.4 の 3） | 13:44:32 に pvc-99c35b80（prometheus-1）が detached、duchamp の replica が stopped |
| 13:44:36 | ✋ `drain duchamp --ignore-daemonsets --delete-emptydir-data --timeout=20m` | 13:45:26 に `node/duchamp drained`（rc 0）。`--force` は要らなかった（コントローラを持たない Pod が無い） |

- drain は、duchamp の 2 つの instance-manager と `minio-2` の PDB で数十秒ずつ待ってから進んだ。chirico のような時間切れは無かった（Prometheus を先に 0 にしたため）
- 退いた Pod はすべて Running に戻った。`minio-2`、`minio-3`、`open-webui-pipelines` は chirico でアタッチし直した（13:46:48 に Running / Completed 以外の Pod が 0）

drain の後の確認（runbook §3.3 の 9）:

- Longhorn のボリューム: duchamp でアタッチしているものは無い。attached healthy 13、attached degraded 8（duchamp に replica がある 2 replica のボリューム）、detached 4（myao、cg-data、prometheus の 2 つ）
- replica は 45 個で、drain の前と同じ数（duchamp の 11 は全部 stopped）。ほかのノードに新しい replica は作られていない
- iSCSI のセッションが 4 つ残った（`TRANSPORT WAIT` / `FAILED`）。行き先は退いた duchamp の instance-manager（10.244.5.12 の 3 つ、10.244.5.250 の 1 つ）。ブロックデバイス（sdc〜sdf）は残っているが、マウントはされていない。chirico と同じく §3.4 の 9 の再起動で片付ける
- replica が止まったのは 13:45 ごろ。`replica-replenishment-wait-interval`（100 分）の内側で設定を戻すには、15:25 ごろまでに §3.8 の 3 を行う

## 3. 22.04 のまま containerd を置き換える（runbook §3.4）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 13:47:03 | ✋ 0: `/root` で `apt-get download containerd.io=1.6.8-1` | `/root/containerd.io_1.6.8-1_amd64.deb`（28.1MB、sha256 `74ce6b6b440073b6…`、chirico と同じ） |
| 13:47:05 | ✋ 1: `docker.list` を `docker.list.disabled-20261017` に名前を変え、`apt-get update` | `containerd.io` の候補は 1.6.8-1、`containerd` の候補は 2.2.1-0ubuntu1~22.04.2 |
| 13:47:31〜13:50:4x | ✋ 2: `apt-get full-upgrade` | rc 0。110 upgraded、8 newly installed、0 removed、0 not upgraded（下の 3.1） |
| 13:51:00 | ✋ 3: `apt-get install containerd` | 先に `-s` で、消えるのが `containerd.io` だけであることを確かめた。`containerd` 2.2.1-0ubuntu1~22.04.2 と `runc` 1.3.4-0ubuntu1~22.04.1 が入り、`containerd.io` は `rc` |
| 13:51:17 | 4: `config.toml` を `config.toml.porkadot-bak.20261017` に名前を変える | `containerd config default` は `version = 3` |
| 13:51:26 | ✋ 5: `porkadot setup-containerd --config ./porkadot.yaml --node duchamp`（porkadot 4fa3a0f、asset はこのブランチの base 0e5c6d6） | rc 0、13:51:30 に終わった。`ERROR` や `Unsupported containerd config version`、`HostKeyMismatch` は無い |
| 13:51:42 | ✋ 7: `systemctl restart kubelet` | Ready,SchedulingDisabled、`containerd://2.2.1`、OS-IMAGE は `Ubuntu 22.04.5 LTS`。DaemonSet の Pod 8 つが Running |
| 13:52:28 | ✋ 8: dns addon の修正を (b) で当てる | 下の 3.3 |

### 3.1 full-upgrade

- chirico と同じく非対話で流した: `systemd-run --unit=full-upgrade-20261017` の中で、`DEBIAN_FRONTEND=noninteractive`、`UCF_FORCE_CONFFOLD=1`、dpkg の `--force-confdef --force-confold`。ログはノードの `/root/full-upgrade-20261017.log`
- 先に `apt-get -s full-upgrade` で、削除されるものが無いことを確かめた
- conffile: `/etc` の `*.dpkg-*` と `*.ucf-*` は前後で変わらなかった（前からあるのは `ca-certificates.conf.dpkg-old`、`default/grub.ucf-dist`、`ssh/sshd_config.ucf-dist`）。`/etc/sudoers`（`NOPASSWD`）と `/etc/multipath.conf`（addon の版）はそのまま
- chirico と違い、`open-vm-tools` も上がった（`apt list --upgradable` は空になった）。systemd 本体は 249.11-0ubuntu3.23 のままで、`systemd-networkd` は再起動していない。nftables 1.0.2-1ubuntu3.1、multipath-tools 0.8.8-1ubuntu1.22.04.4
- 終わった後: `/var/run/reboot-required` あり（10-06 から）。cnidaria の経路（proto 200）は v4・v6 とも 7 本。kubelet、containerd、multipathd、iscsid は active

### 3.2 containerd の確認（runbook §3.4 の 6・7）

- `containerd --version` が 2.2.1。`/etc/containerd/config.toml` は `version = 3`、`sandbox = 'registry.k8s.io/pause:3.10.1'`、`[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]` の下に `SystemdCgroup = true`
- `sudo /opt/bin/crictl info` が応答する。`crictl images` は 228 行で、イメージが引き継がれている。`crictl` は endpoint の設定が無いので、既定の endpoint を順に試す警告（dockershim.sock が無い）を出すが、containerd には繋がる
- containerd の journal に migrate の警告と `Ignoring unknown key` は無い。`ctr deprecations list` は空
- DaemonSet の Pod は、containerd の置き換えでも kubelet の再起動でも再起動しなかった（chirico と同じ。古い shim が動き続けている）。`speaker` の restart 7 と `longhorn-csi-plugin` の 2 は、2026-05 と 2026-06 のもの

### 3.3 dns addon の修正（runbook §3.4 の 8、(b)）

- unit は、このブランチの `assets/kubelet-default/addons/dns/install.sh` の quoted heredoc を `sed` で取り出して使った。oeilvert の今の unit と 1 文字も違わないことを `diff` で確かめた
- 元の unit は `/root/cluster-dns.service.bak-20261017` に写した。`daemon-reload`、`reenable`、`restart` を流した
- `reenable` は chirico と同じく `... is added as a dependency to a non-existent unit sys-subsystem-net-devices-porka\x2ddummy01.device` と警告した（害はない。`chirico.md` §3.4）
- `cluster-dns` は active。`resolvectl status porka-dummy01` は DNS Servers 10.254.0.10、DNS Domain `cluster.local default.svc.cluster.local svc.cluster.local`。cnidaria の経路（proto 200）は v4・v6 とも 7 本のまま
