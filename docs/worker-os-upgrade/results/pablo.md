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
