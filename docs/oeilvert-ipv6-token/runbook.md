# oeilvert の IPv6 を RA + トークン `::183` にする（本番 `fraction`）

k8s の worker oeilvert（192.168.1.82）の IPv6 を、netplan の静的設定から RA + トークン `::183` に切り替える手順。
委譲プレフィックス（jumelle が DHCPv6-PD で受け取る /56）が変わっても、oeilvert のアドレスと既定経路が自動で新しい /64 に付き直るようにする。

背景: 2026-10-23 に委譲プレフィックスが `2405:6581:8580:300::/56` から `2405:6580:6740:ac00::/56` に変わった。
ほかの worker 7 台は RA の SLAAC で追随したが、oeilvert だけは静的設定のため追随せず、手で直した
（llm-wiki `wiki/topics/delegated-prefix-change-2026-10.md` の「oeilvert は `netplan apply` を使わずに直した」）。

| | 今 | 切り替え後 |
|---|---|---|
| IPv6 アドレス | 静的 `2405:6580:6740:ac01::183/64`（`addresses:` に直書き） | RA の /64 + トークン `::183`（今の値は同じ `…:ac01::183`） |
| IPv6 の既定経路 | 静的 `via 2405:6580:6740:ac01::1` | RA の送り手（jumelle の `br-lan` のリンクローカル `fe80::a8dd:cff:fe37:73d3`） |
| `accept-ra` | `false`（networkd は `IPv6AcceptRA=no`） | `true`（`IPv6AcceptRA=yes`） |
| IPv4・DNS | 192.168.1.82/16、192.168.1.182/16、既定経路 192.168.0.1、DNS 192.168.0.1 | 変えない |

interface ID `::183` は変えない。jumelle の firewall（アドレスセット `ipv6-mosh-group`。oeilvert の devbox の mosh / ssh）と
`mosh.fraction.jp` の AAAA が `::183` を参照している。

ファイル:

| パス | 中身 |
|---|---|
| `before/00-installer-config.yaml` | 今の `/etc/netplan/00-installer-config.yaml`（2026-10-23 03:03 に手で新しいプレフィックスへ書き換えた版） |
| `before/10-netplan-enp2s0.network` | 今 networkd が読んでいる `/run/systemd/network/10-netplan-enp2s0.network`。**中身は旧プレフィックス（`301::183`）のまま**（§1.1） |
| `after/00-installer-config.yaml` | **新しい netplan のファイル**。`/etc/netplan/00-installer-config.yaml` をこれに置き換える |
| `after/10-netplan-enp2s0.network` | 新しいファイルから netplan が生成する networkd の設定（§2.2 の検証で得たもの） |

## 1. 調べた事実（2026-10-23、読み取りのみ）

### 1.1 oeilvert

- Ubuntu 24.04、systemd 255（255.4-1ubuntu8.18）、netplan.io 1.1.2-8ubuntu1~24.04.3。backend は networkd
- `/etc/netplan/` は `00-installer-config.yaml`（10-23 に手で直した版）と、その前の版の `00-installer-config.yaml.bak-20261023`（旧プレフィックス）。
  netplan は `*.yaml` しか読まないので、`.bak-*` は無視される
- **`/run/systemd/network/10-netplan-enp2s0.network` は旧プレフィックスのまま。** 10-23 は `netplan apply` も `netplan generate` もせず、
  実行時を `ip` コマンドで合わせたため。今のアドレスと既定経路は、networkd の設定ではなく手で入れたもの
  （`ip -6 route` の既定経路に `proto` が無い = `boot`）。netplan の generator は `systemctl daemon-reload` のたびに `/run` を作り直すが、
  networkd はそれだけでは読み直さない
- 最後の起動は 2026-10-19 09:02（UTC）。unattended-upgrades の自動再起動（04:00 UTC、`52local-reboot.conf`）が有効
- sysctl: `net.ipv6.conf.all.forwarding=1`（cnidaria が立てる）、`net.ipv6.conf.enp2s0.accept_ra=0`
- `enp2s0` の global な IPv6 は `…:ac01::183/64`（`valid_lft forever`）だけ
- cnidaria の Pod 経路（`proto 200`）が 7 本、ほかのノードの SLAAC アドレスを next hop にして入っている
- ノードの注釈 `cnidaria.unstable.cloud/node-ipv6` は `2405:6580:6740:ac01::183`
- ICMPv6 の RA は受け取れる: ip6tables の INPUT は policy ACCEPT、`netfilter-persistent` の `rules.v6`（2021 年）は filter が空で docker0 の MASQUERADE だけ。
  cnidaria の `inet cnidaria` の input チェインは `nd-router-advert` を accept している
- devbox（Docker の bridge、`docker.io`）は 3222/tcp と 60000〜60010/udp を `[::]` で公開している。待ち受けはアドレスに依存しない

### 1.2 比較: chirico（192.168.1.83）

- 同じ版（systemd 255、netplan.io 1.1.2）。netplan は `dhcp4: true`、`dhcp6: true`（`accept-ra` は書いていない = networkd の既定）
- **kernel の `accept_ra` は 0、`forwarding` は 1 のままで、RA から既定経路を得ている**:
  `default via fe80::a8dd:cff:fe37:73d3 dev eno1 proto ra metric 100`。アドレスは SLAAC（EUI-64）の `…:ac01:5a47:caff:fe70:1019`
- networkd は RA を kernel ではなく自分で（ユーザー空間で）処理し、kernel の `accept_ra` を 0 にする。kernel の
  「`forwarding=1` だと `accept_ra=1` では RA を無視する（`accept_ra=2` が要る）」という制約は、networkd の `IPv6AcceptRA=` には当たらない。
  cnidaria の Wiki の `accept_ra=2` の注意は kernel に RA を処理させる場合の話で、**oeilvert で `accept_ra=2` にする必要は無い**（ほかの 7 台もしていない）

### 1.3 jumelle の RA

- `br-lan` の networkd（regied が書く `50-regied-lan.network`）: `IPv6SendRA=yes`、`[IPv6SendRA] Managed=no`、`OtherInformation=yes`、`EmitDNS=no`
- chirico で見えた寿命: router lifetime 約 1800 秒、prefix の valid 約 3600 秒・preferred 約 1800 秒
- `OtherInformation=yes` なので、RA を受けた networkd は DHCPv6 の information-request を送る（netplan の `dhcp6: false` でも、
  networkd の `[IPv6AcceptRA] DHCPv6Client=` は既定で yes）。jumelle の dnsmasq（`/etc/regied/dnsmasq/dnsmasq.conf`）は IPv4 の `dhcp-range` しか持たず、
  DHCPv6 には答えない見込み。答えがあれば DNS が増えるだけで、アドレスは増えない（`Managed=no`）

### 1.4 cnidaria のアドレスの選び方

cnidaria の ADR 0006: IPv6 の InternalIP が無いノード（本番は全部）は、IPv4 の InternalIP を持つインターフェースの global な IPv6 のうち、
tentative・DAD 失敗・deprecated・一時アドレスでないものを選び、**複数あれば最も小さいもの**を注釈に書く。reconcile（タイマーを含む）のたびに見直す。
networkd などに消された経路は、kernel のイベントで入れ直す（ADR 0010）。

## 2. 新しいファイル

### 2.1 変更点

`before/00-installer-config.yaml` との違いは次のとおり。ほかの行（IPv4、DNS、`dhcp4` / `dhcp6`）は同じ。

- `accept-ra: false` → `accept-ra: true`
- `ipv6-address-token: "::183"` を足す
- `addresses:` から `2405:6580:6740:ac01::183/64` を消す
- `routes:` から IPv6 の既定経路（`via 2405:6580:6740:ac01::1`）を消す

これでプレフィックスのリテラルはファイルから無くなる。

### 2.2 検証（2026-10-23、実機の設定は変えていない）

oeilvert 上で一時ディレクトリを root にして、netplan の generator（`/usr/libexec/netplan/generate --root-dir <一時ディレクトリ>`）を
一般ユーザーで流した。`before` と `after` の両方を生成して比べ、一時ディレクトリは消した。

- どちらも終了コード 0、警告なし
- `after` の生成物（`after/10-netplan-enp2s0.network`）: `[Network]` に `IPv6Token=static:::183` と `IPv6AcceptRA=yes`。
  IPv6 の `Address=` と `[Route] Destination=::/0` は無い。IPv4 の `Address=` 2 つと既定経路、`DNS=192.168.0.1` は `before` と同じ
- `systemd-networkd-wait-online` の drop-in（`-i enp2s0:degraded`、`--any -o routable -i enp2s0`）と udev の規則は `before` と同じ
- netplan 1.1.2 は token を `[Network] IPv6Token=` で書く。systemd 255 では `[IPv6AcceptRA] Token=` の互換の名前として残っている
  （oeilvert の `systemd-networkd` のバイナリに `Network.IPv6Token` と `IPv6AcceptRA.Token` の両方のキーがあることを確かめた）

実機の networkd に読ませての確認は、反映（§4）のときに行う。

## 3. `netplan apply` を使わない理由

- oeilvert は k8s のノードで、cnidaria が Pod 間の経路（`proto 200`）を入れている。`netplan apply` は networkd に設定を読み直させる。
  networkd（systemd 255）は `ManageForeignRoutes=` が既定で yes で、自分が作っていない経路を消すことがある。
  2026-10-17 には別のノードでネットワークマネージャーの再起動が cnidaria の経路を全部消し、数分間ノードをまたぐ Pod 通信が止まった（cnidaria ADR 0006 / 0010）
- **再起動なら、networkd は cnidaria より先に上がり、cnidaria が起動してから経路を入れる。** 経路を消される順にならない
- どのみちノードは drain する（Longhorn の detach を伴うので、無停止では入れない）。drain するなら再起動のほうが状態がきれいに揃う
- 同じ理由で `networkctl reload` / `systemctl restart systemd-networkd` も使わない

## 4. 反映手順 ✋

**実機への反映は、ユーザーの承認を得てから行う。** ✋ の箇所は 1 つずつ承認を取る。
drain と uncordon の詳細（kubeconfig、Longhorn の設定、MinIO）は、OS 更新の手順書 `docs/worker-os-upgrade/runbook.md` の
§1.2、§2.4、§2.5、§3.3、§3.8 に従う。2026-10-17 の oeilvert の記録は `docs/worker-os-upgrade/results/oeilvert.md`。

アクセス: oeilvert には IPv4（`ssh yuanying@192.168.1.82`）で入る。IPv6 が壊れても作業の経路は失わない。

### 4.1 事前確認（読み取り）

1. 時間帯: unattended-upgrades の自動再起動（04:00 UTC）と、止めてはいけない CronJob の時間帯（OS 更新の手順書 §2.1.1）を避ける
2. devbox を使っている人がいないことをユーザーに確かめる（再起動で devbox が止まる）
3. 今の状態を控える: `ip -6 addr show enp2s0`、`ip -6 route`（`proto 200` の本数）、`networkctl status enp2s0`、
   ノードの注釈 `cnidaria.unstable.cloud/node-ipv6`、`/etc/netplan/` の一覧と `00-installer-config.yaml` の中身
4. `/etc/netplan/00-installer-config.yaml` が `before/00-installer-config.yaml` と同じであること（違えば止めて、差分を見て判断する）
5. ほかの worker で、IPv6 の既定経路が RA（`proto ra`）から入っていること（jumelle の RA が出ていること）

### 4.2 drain ✋

OS 更新の手順書 §3.3 の 3〜9 と同じ。oeilvert では次を含む。

1. ✋ `infra-admin` のトークンを発行する
2. ✋ cordon
3. ✋ Longhorn の `concurrent-replica-rebuild-per-node-limit` を `0`、`replica-auto-balance` を `disabled` に（変える前の値を記録）
4. ✋ Longhorn の `node-drain-policy` を `allow-if-replica-is-stopped` に
5. ✋ `minio/minio` の StatefulSet を 0 にし、4 つのボリュームが detach されるのを待つ（replica がすべて oeilvert にある）
6. ✋ `drain oeilvert --ignore-daemonsets --delete-emptydir-data --timeout=20m`。
   `homegallery/api` は `nodeSelector` が oeilvert なので、uncordon まで Pending になる（止まってよい）

### 4.3 ファイルの置き換え ✋

**置き換えたら、すぐに §4.4 の再起動まで進める。** 置いたまま放置すると、04:00 の自動再起動などで drain 無しに反映される。

1. ✋ バックアップ: `/etc/netplan/00-installer-config.yaml` を `/etc/netplan/00-installer-config.yaml.bak-<YYYYMMDD>-static` にコピーする
   （`.yaml` で終わらない名前なので netplan は読まない。既存の `.bak-20261023` は残す）
2. ✋ `after/00-installer-config.yaml` を `/etc/netplan/00-installer-config.yaml` に置く（owner root:root、mode 600）
3. `sudo netplan generate` で生成し直し、`/run/systemd/network/10-netplan-enp2s0.network` が `after/10-netplan-enp2s0.network` と同じであることを確かめる。
   `netplan generate` は `/run` に書くだけで、networkd には読ませない。**`netplan apply` はしない**
4. `sudo netplan get` が IPv4 と token を含む新しい内容を返すこと

### 4.4 再起動 ✋

1. ✋ `sudo systemctl reboot`
2. IPv4 の SSH が戻るのを待つ

### 4.5 確認（uncordon の前）

| # | 確認 | 方法 | 合格基準 |
|---|---|---|---|
| 1 | アドレス | `ip -6 addr show enp2s0 scope global` | `<今の LAN の /64>::183/64` が 1 つだけ、`dynamic`（RA の寿命つき）。`forever` の静的アドレスが無い |
| 2 | 既定経路 | `ip -6 route show default` | `via fe80::a8dd:cff:fe37:73d3 dev enp2s0 proto ra`（jumelle の `br-lan` のリンクローカル。chirico と同じ）。静的な `via …::1` が無い |
| 3 | networkd | `networkctl status enp2s0` | `configured`、Gateway に `fe80::a8dd:cff:fe37:73d3` と `192.168.0.1` |
| 4 | kernel の sysctl | `sysctl net.ipv6.conf.enp2s0.accept_ra net.ipv6.conf.all.forwarding` | `0` と `1`（networkd が RA を処理するので `accept_ra` は 0 のままでよい。`2` にしない） |
| 5 | 外への IPv6 | `ping -6 -c 3 2606:4700:4700::1111`、`curl -6 -s https://api64.ipify.org` | ping が通る。curl の答えが `…::183` |
| 6 | IPv4 と DNS | `ping -4 -c 3 1.1.1.1`、`resolvectl status enp2s0`、`resolvectl status porka-dummy01` | 前と同じ。`enp2s0` の DNS は 192.168.0.1（IPv6 の DNS が増えていたら記録する）。`porka-dummy01` に 10.254.0.10 |
| 7 | cnidaria の注釈 | `kubectl --context fraction get node oeilvert -o jsonpath='{.metadata.annotations.cnidaria\.unstable\.cloud/node-ipv6}'` | `<今の LAN の /64>::183` |
| 8 | cnidaria の経路 | oeilvert で `ip -6 route show proto 200`、ほかのノードで oeilvert の Pod CIDR 宛ての経路 | oeilvert に 7 本。ほかのノードの next hop が `…::183`。OS 更新の手順書の `verify-nodes.sh` が PASS |
| 9 | ノードと DaemonSet | `kubectl --context fraction get node oeilvert`、`get pods -A -o wide --field-selector spec.nodeName=oeilvert` | Ready（SchedulingDisabled）。cnidaria、kube-proxy、Longhorn、MetalLB の speaker などが Running |
| 10 | ホストのサービス | `systemctl is-active cluster-dns docker devbox home-yuanying-shared-nfs.mount`、automount 2 つ | active（automount は `active (waiting)`）。`systemctl --failed` が増えていない |

### 4.6 uncordon と後始末 ✋

OS 更新の手順書 §3.8 と同じ。

1. ✋ uncordon
2. ✋ `node-drain-policy` を `block-if-contains-last-replica` に、`minio/minio` を 4 に戻す。MinIO の Pod が Running、ボリュームが healthy でアタッチされたこと
3. Longhorn の node が Ready / schedulable に戻ってから、✋ §4.2 の 3 の 2 つの設定を記録した値に戻す。再同期が終わるのを待つ
4. `homegallery/api` が oeilvert で Running に戻ること
5. ✋ `netcheck.sh`（OS 更新の手順書 §1.4。Pod 間の v4 / v6、ノード間。一時的な DaemonSet を作る）と `check-apps.sh` を流し、ベースラインと同じであること
6. devbox: 外（宅外の IPv6）から `mosh.fraction.jp` に ssh（3222）と mosh で入れること。jumelle の firewall（`ipv6-mosh-group`）を通る経路なので、ユーザーに確かめてもらう
7. `infra-admin` のトークンを破棄する
8. 作業記録を `results/` に書く（時刻、確認の結果、`/run` の生成物の差分）

## 5. 戻し方

**IPv6 が付かない・経路が入らない場合**（IPv4 は動いている）:

1. ✋ `/etc/netplan/00-installer-config.yaml.bak-<YYYYMMDD>-static` を `/etc/netplan/00-installer-config.yaml` に戻す
2. ✋ 再起動する（§3 と同じ理由で `netplan apply` はしない）。cordon したままなら、そのまま再起動してよい。uncordon 後に戻すなら §4.2 の drain からやり直す
3. §4.5 の 1・2・7・8 を、静的設定の期待値（`valid_lft forever` の `::183`、`via …::1`）で確かめる

**再起動できない・急いで IPv6 だけ戻したい場合**: 2026-10-23 と同じく、`ip -6 addr add <今の /64>::183/64 dev enp2s0` と
`ip -6 route add default via <今の /64>::1 dev enp2s0` で実行時だけ合わせる。ファイルはバックアップに戻しておき、次の再起動で揃える。

## 6. リスクと注意

- **RA に依存するようになる。** jumelle の RA が router lifetime（約 30 分）を超えて止まると既定経路が、prefix の valid lifetime（約 1 時間）を超えるとアドレスが消える。
  今の静的設定はこれに耐えていた。ほかの 7 台と同じ条件になる
- **プレフィックスが変わった直後は、新旧の `::183` が両方付く。** 旧い /64 の RA が止まると、旧い方は preferred lifetime（約 30 分）で deprecated になり、
  valid lifetime で消える。cnidaria は deprecated でない最小のアドレスを選ぶので、旧い方が deprecated になるまでは旧い方を選ぶことがある
  （`2405:6580…` と `2405:6581…` の大小による）。ほかの 7 台と同じ挙動
- oeilvert のアドレスが追随しても、`::183` を参照する jumelle の firewall（`ipv6-mosh-group`）と `mosh.fraction.jp` の AAAA は別に追随させる必要がある。
  これは regied 側（ADR 0021 / 0024）の作業単位で扱う
- netplan 1.1.2 は token を互換の名前 `[Network] IPv6Token=` で書く。systemd が将来この名前を落とすと token が効かなくなる。
  netplan と systemd を上げるときに、生成物（`/run/systemd/network/10-netplan-enp2s0.network`）と §4.5 の 1 を見直す
- `/etc/netplan/` に置いた時点で、次の `systemctl daemon-reload` が `/run` を生成し直す。networkd はそれだけでは読み直さないが、
  §4.3 と §4.4 の間を空けない
- `ipv6-address-token` を使うので、`ipv6-address-generation`（`eui64` / `stable-privacy`）は書かない（netplan では併用できない）

## 7. プレフィックスの変化を事前に確かめる方法（未実施）

必須ではない。本番に入れる前に「プレフィックスが変わると `::183` が新しい /64 に付き直る」ことを見たければ、検証 VM で次のように試せる。

- poissonnerie の libvirt に Ubuntu 24.04 の検証 VM（`prefix-lab*`、このタスクで作成・削除が認められている名前）を立てる。netplan.io 1.1.2 / systemd 255 にそろえる
- VM の中に netns を作り、veth の片側で RA を出す（systemd-networkd の `IPv6SendRA=` か radvd）。**RA は VM の中の netns に閉じ込め、br0（宅内 LAN）に出さない**
- VM 側の veth に `after/00-installer-config.yaml` と同じ設定（インターフェース名だけ替える）を置き、再起動して `::183` が 1 つ目の /64 に付くのを見る
- netns 側の RA のプレフィックスを替える（旧いプレフィックスは lifetime 0 で 1 度出してから止める、または止めるだけ）。新しい /64 の `::183` が付き、
  既定経路が RA から入り、旧いアドレスが deprecated → 消えることを見る
