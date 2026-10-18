# worker の OS 更新手順書（本番 `fraction`）

本番クラスタ `fraction` の worker 5 台（braque、chirico、duchamp、oeilvert、pablo）を、1 台ずつ in-place で更新する手順。

| | 更新前 | 更新後 |
|---|---|---|
| OS | Ubuntu 22.04 系 | Ubuntu 24.04.5（`do-release-upgrade`） |
| kernel | 5.15 | 6.8（24.04 の GA） |
| containerd | 1.6.8（Docker の `containerd.io`） | 2.2.1（Ubuntu の `containerd`） |
| containerd の config | version 2（containerd 1.6 の既定値） | version 3（containerd 2.x の既定値 + `SystemdCgroup = true`） |
| K8s | v1.29.8 | v1.29.8（このタスクでは上げない） |

更新前の状態と、この手順の判断の根拠は、同じディレクトリの `survey-2026-10.md`（以下「調査」）にある。

22.04 → 24.04 の in-place 更新と containerd の置き換えは、dev クラスタ（porkadot-dev の KVM の VM、context `test`）で、この手順の順のまま通してある（2026-10-17）。
記録は porkadot-dev の `docs/worker-os-upgrade/verification-results.md`（以下「dev の検証結果」）にある。

dev で確かめていないものは次のとおり。**本番の 1 台目（chirico）では、ここを特に注意して見る。**

- `do-release-upgrade` の対話モード（SSH 越しの予備の sshd と `screen`、conffile の質問）。dev は非対話（`DistUpgradeViewNonInteractive`、`systemd-run` の unit）で流した。dev のノードには、conffile の質問が出るファイルが無かった。
  chirico で対話モードを通し（`results/chirico.md` §4）、2 台目からは非対話で流すことにした（§3.5）
- Longhorn、NFS、iSCSI を持つノード（chirico、duchamp、pablo、oeilvert、braque）。ZFS（braque、oeilvert）
- docker-ce から `docker.io` への移行（oeilvert。§3.4.1）。oeilvert で通した（`results/oeilvert.md` §3）

## 0. 役割と約束ごと

- **本番への変更系の操作は、1 つずつユーザーの承認を得てから行う。** この手順書では承認を取る箇所に ✋ を付けた。
  読み取りの確認（`kubectl get`、SSH での状態確認）は承認なしで行ってよい。
- **物理作業はユーザーが行う。** コンソールの操作、電源の操作。オペレーター（人または agent）は手順を示し、ユーザーの完了の報告を待つ。
- **1 台ずつ行う。** 1 台を終えて「次の 1 台へ進む条件」（§3.9）を満たすまで、次のノードに手を付けない。
- 想定外のことが起きたら、その場で止めてユーザーに報告する。復旧の方針（§4）は、どの段階にいるかで変わる。
- **porkadot の `setup-node` や `install kubelet` を流すと、`/etc/systemd/system/cluster-dns.service` と `/etc/multipath.conf` が、このリポジトリの addon（`assets/kubelet-default/addons/`）の版で書き直される**（`install kubelet` も中で `setup-node.sh` を呼ぶ）。
  `cluster-dns.service` の依存の不足（2026-07 に oeilvert で起動時のレースを起こしたもの）は、dns addon の修正（k8s-manifests-fraction#10、マージ済み）で直した。oeilvert には当ててあり、ほかの 4 台には各ノードの手順で当てる（§1.5）。

## 1. 前提

### 1.1 porkadot の版と使い方

- porkadot は 0.29.1 以降（master の e9379eb 以降）。containerd v1/v2 の両対応（porkadot#13）が入っていること。
- porkadot の使い方の注意は control-plane の手順書（`docs/cp-replacement/runbook.md` §1.1）と同じである。
  - **k8s-manifests-fraction のリポジトリルートを cwd にして実行する。** asset の置き場 `./assets` が cwd から決まる。
  - `--config ./porkadot.yaml` はサブコマンドの後ろに置く。
  - **porkadot はエラーでも終了コード 0 を返す。** 成否は出力を読んで判断する。
  - `--node` には `porkadot.yaml` の `nodes` のキー（`braque`、`chirico`、`duchamp`、`oeilvert`、`pablo`）を渡す。
- 使う asset は、`master` の `assets/kubelet-default/setup-containerd.sh`（#13 の版）。この手順では render をしない。

### 1.2 kubeconfig の運用

`porkadot-dev/CLAUDE.md` の「本番クラスタ（fraction）の kubeconfig 運用」に従う。

- 確認は `kubectl --context fraction`（`fraction-auditor`、read-only）で行う。作業を始める前に `kubectl --context fraction auth can-i delete pods -A` が `no` であることを確かめる。
- 変更（cordon、drain、uncordon、Longhorn の設定）は `infra-admin` の短命トークンで行う。1 台ごとに 2〜3 時間の期限で発行し、終わったら破棄する。chirico では cordon から uncordon まで約 3 時間かかり、3 時間のトークンが切れる前に発行し直した。途中で切れそうなら、§3.8 の前に発行し直す。
  以下、変更系のコマンドを `kubectl-admin` と書く（`kubectl --context fraction --token="$ADMIN_TOKEN"` のこと）。

### 1.3 作業端末とアクセス

- 5 台とも `ssh yuanying@<IP>` で入れて、パスワードなしで sudo できること（`porkadot.yaml` の `connection.user` は全体で `yuanying`）。
- `do-release-upgrade` は SSH 越しに、systemd の unit の中で非対話で流す（§3.5）。途中で新しい SSH の接続が 8 分ほどできなくなる。上がってこないときのために、ノードごとにコンソール（モニターとキーボード）で入れるかをユーザーに確認しておく。

### 1.4 cnidaria の手順書のスクリプト

更新後の CNI の確認には、cnidaria-cni-dev のタスクの手順書のスクリプト（`/home/yuanying/.local/state/herdr-tasks/cnidaria-cni-dev/notes/fraction-runbook/`）を使う。

- `verify-nodes.sh`: 全ノードの経路・nft のテーブル・conflist などを確かめる。ホストの nft ではなく、イメージの nft を一時コンテナで動かす（`image_nft`）
- `netcheck.sh`: Pod 間通信（v4 / v6、ノード間）を確かめる
- `check-apps.sh`: LoadBalancer、VIP、Longhorn、アプリの応答を確かめる

使い方はそのタスクの手順書（`notes/fraction-runbook.md`）に従う。`netcheck.sh` は一時的な DaemonSet を作るので ✋。

### 1.5 dns addon の修正

`assets/kubelet-default/addons/dns/install.sh` が書く `cluster-dns.service` には、`porka-dummy01` のデバイスと `systemd-networkd` への依存が無かった。
oeilvert では 2026-07-24 に手で足したが、2026-10-17 の cnidaria 移行の `install kubelet` で addon の版に書き直されて消えた（調査 §2.6）。
起動時に `porka-dummy01` ができる前に `cluster-dns.service` が走ると、クラスタ DNS が登録されず、oeilvert では NFS のマウントと kubelet の起動に波及する（Wiki `entities/oeilvert` の 2026-07-24 の記録）。

dns addon の修正（k8s-manifests-fraction#10、`master` の aa1b8b6）で、`cluster-dns.service` に次の依存が入った。

- `BindsTo=` と `After=` に `sys-subsystem-net-devices-porka\x2ddummy01.device`
- `Wants=` と `After=` に `systemd-networkd.service`
- `[Install]` の `WantedBy=` に同じ device ユニット

当たっているかどうか（2026-10-17 時点）:

| ノード | 状態 |
|---|---|
| oeilvert | **当たっている**。#10 のマージ後に unit を置き換えた（元の unit は `/root/cluster-dns.service.bak-20261017`） |
| braque、chirico、duchamp、pablo | OS 更新の各ノードの手順の中で当てた（§3.4 の 8。2026-10-18 に pablo で 5 台すべてに当たった） |

この手順は、porkadot を `master` の aa1b8b6 以降の asset で動かす（`git log` で確かめる）。
修正が入った asset なら、`setup-node` や `install kubelet` を流しても `cluster-dns.service` は修正済みの版で書き直されるので、問題にならない。

## 2. 事前準備

### 2.1 ユーザーと合意すること

次の点はユーザーと決めてある（2026-10-17）。要判断の点は残っていない。

| # | 内容 | 決定 |
|---|---|---|
| 1 | 更新する順番 | §3.1 の順（chirico → duchamp → oeilvert → braque → pablo） |
| 2 | **replica 1 のボリューム**（MinIO の 4 つ、prometheus の 2 つ） | **重要ではないので、作業中に止まってよい**。replica は増やさない。drain の扱いは §2.4。oeilvert の作業中は MinIO 全体が止まる（replica がすべて oeilvert にある） |
| 3 | **oeilvert の Docker** | **docker-ce（focal 版）から Ubuntu の `docker.io` に移す**。Ubuntu の `containerd` に置き換えると docker-ce は依存が切れて削除されるため。手順は §3.4.1 |
| 4 | **braque の停止時間** | **バックアップの CronJob の時間帯に重ならなければ、いつ止めてもよい**。止めてよい時間帯は §2.1.1 |
| 5 | **ほかのノードの停止時間**（chirico、duchamp、oeilvert、pablo） | **いつ止めてもよい** |

作業の時間帯を決めるときに気をつけること（決定ではなく注意）:

- 1 台あたり 1.5〜2.5 時間の見込み（§3.2）。
- oeilvert: devbox（`mosh.fraction.jp`）は oeilvert の Docker で動いている。oeilvert の作業中は devbox に入れない。**作業端末が devbox なら、oeilvert の作業は別の端末から行う。** unattended-upgrades の自動再起動（04:00）の時間帯を避ける（§5.5）。
- pablo: `registry.fraction.jp`（Pod は pablo から他のノードに移る）、fs の h2（NFS）、homegallery の RWX（share-manager）が、Pod が移る間の数分止まる。

### 2.1.1 braque を止めてよい時間帯

braque の NFS（192.168.1.131）を使うバックアップの CronJob（2026-10-17 の読み取り）:

| CronJob | schedule | timeZone | 実行時刻（JST） | 実行時刻（UTC） | 所要時間（直近 3 回） |
|---|---|---|---|---|---|
| `natsumi/natsumi-backup`、`-aki`、`-myao` | `30 5 * * *` | Asia/Tokyo | 05:30 | 20:30 | 1 分未満 |
| `fraction-agents/deep-researcher-backup` | `0 6 * * *` | Asia/Tokyo | 06:00 | 21:00 | 未実行（実績なし） |
| `fs/h2-backup` | `44 5 * * *` | なし（UTC） | 14:44 | 05:44 | 約 2 分 |
| `fs/sites-backup` | `53 7 * * *` | なし（UTC） | 16:53 | 07:53 | 1 分未満 |
| `fs/data-backup` | `3 9 * * *` | なし（UTC） | 18:03 | 09:03 | 約 2 分 |

- `timeZone` の無い CronJob は、kube-controller-manager の時刻（UTC）で動く。`fs/data-backup` の lastScheduleTime が 09:03Z で、schedule `3 9` と一致することで確かめた。
- `aphrael/tumblr-like`（3 時間ごと）は braque の NFS を使わない（`aphrael-2` は h2.fs の NFS）。
- deep-researcher-backup はまだ一度も動いていないので、所要時間が分からない。余裕を見て 30 分とした。

**止めてはいけない時間帯（JST）**: 05:15〜06:45、14:30〜15:00、16:45〜17:05、17:55〜18:15。

**止めてよい時間帯（JST）**: 07:00〜14:30 と 18:15〜翌 05:15。
braque の作業（§3.3〜§3.8、2 時間前後）は、まとめて片方の時間帯に収める。**推奨は JST 07:00〜14:00 に始めて 14:30 までに終える形、または 19:00 以降に始める形**。作業を始める前に `kubectl --context fraction get cronjobs -A` で schedule が変わっていないかを見直す。

braque の NFS は、バックアップのほかに次も使っている（調査 §2.3）。**これらが braque の停止中に止まってもよいことは、ユーザーに確認してある**（2026-10-17）。止まる間、それぞれ応答しなくなる。

- `docker/registry`（`registry.fraction.jp`）の保存先。braque が止まっている間は、イメージの pull と push ができない（下の注意）
- 動画のサイト（carib、carib2、pondo、pondo2、shja、shja2）の nginx と movies
- oeilvert のホストの `/home/yuanying/shared/nfs`（soft マウント）
- `fs/data-restore`、`fs/h2-restore`、`fs/sites-restore`（`sleep infinity` の Pod）の inline の NFS ボリューム（2026-10-17 の braque の作業で見つけた。`results/braque.md` §1.4）

braque の停止の後、NFS を使う Pod は自分で戻る。braque の作業では、動画のサイトの movies（carib2、pondo2、shja2）が liveness probe で、`docker/registry` が `stale NFS file handle` で CrashLoopBackOff になり、nfsd が戻った後、手を加えずに 1 分ほどで Running に戻った（`results/braque.md` §3.4）。

**注意: braque が止まっている間は、LAN から Service の IP（10.254.0.0/16）に届かず、LAN で `fraction.cluster` の名前を引けない。**

- 家のルーター jumelle（net-fraction-private の `hosts/jumelle/config.yaml` の routes、`docs/requirements.md` §6）に、Service の CIDR 10.254.0.0/16 への静的ルートが via 192.168.1.131（braque）で入っている。LAN の dnsmasq は `fraction.cluster` を 10.254.0.10（クラスタ DNS）に条件付きで転送している
- braque が止まる間（§3.4 の 9、§3.5 の 4 の再起動）、LAN から Service の名前や IP で入るもの（例: `ssh dev@h2.fs.svc.fraction.cluster`、10.254.0.170）は切れる。braque の作業中に実際に切れた（`results/braque.md` §5.1）
- 作業端末の kubectl は API の VIP（192.168.1.101）を使うので影響を受けない。MetalLB の LoadBalancer の IP（192.168.1.200 など）も Service の CIDR の外なので、この経路には依らない
- drain だけでは影響は無い（kube-proxy は DaemonSet で、braque は動いている）

**注意: braque を止めている間は、`registry.fraction.jp` からイメージを pull できない。**

- `registry.fraction.jp` のイメージを使う Pod（2026-10-17 の読み取りでは `llm-wiki/llm-wiki` と `holyorder-preview/preview`。どちらも `imagePullPolicy: IfNotPresent`）は、動いている間は影響を受けない。ただし、その間に別のノードへ移ると、移った先にイメージが無ければ `ImagePullBackOff` になる。braque が戻れば pull し直して上がる
- oeilvert の devbox（`registry.fraction.jp/yuanying/devbox-amd64`）も同じ。braque の作業中に devbox のイメージを pull し直す必要が出ないようにする（oeilvert の作業は braque より前に終わっている。§3.1）
- braque の作業中は、`registry.fraction.jp` のイメージを使うデプロイをしない。他のノードの drain も重ねない
- braque の作業の前に、上の Pod の一覧を `kubectl --context fraction get pods -A -o jsonpath` などで見直す（イメージ名に `registry.fraction.jp` を含むもの）

### 2.2 cnidaria-cni-dev の状態を確かめる

`/home/yuanying/.local/state/herdr-tasks/cnidaria-cni-dev/STATE.md` を読み、本番に触る作業が走っていないことを確かめる。
走っていれば、そのタスクの coordinator（`coord-cnidaria-cni-dev`）と、どちらを先にするかをユーザーに確認する。

あわせて、本番の cnidaria が **v0.1.1 以降**であることを確かめる（`kubectl --context fraction -n kube-system get ds cnidaria` のイメージのタグと、8/8 が更新済みであること）。
v0.1.1 では、`systemd-networkd` の再起動で消えた cnidaria の経路が数秒で入れ直される（dev で確認）。この手順はそれを前提にしている（§3.4 の 2 と 8、§3.5）。2026-10-17 の時点で本番は v0.1.1（8/8）である。

### 2.3 クラスタ全体のベースライン

作業の当日、1 台目に入る前に次を記録する（すべて読み取り）。1 台ごとの確認は、このベースラインと比べる。

1. `kubectl --context fraction get nodes -o wide`: 8 台 Ready、worker の OS と containerd の版
2. Running / Completed 以外の Pod の一覧（調査の時点では 0 個）
3. Longhorn のボリュームの state と robustness、replica の配置（調査 §3.4）。更新前から healthy でないものを記録する
4. etcd 3/3 healthy、VIP（192.168.1.101:6443 の `/readyz`）
5. cnidaria の `verify-nodes.sh` と `check-apps.sh` の結果（ベースラインとして保存する）
6. worker 5 台の `systemctl cat cluster-dns.service`: oeilvert は修正済みの版、ほかの 4 台は修正前の版であること（§1.5。4 台は各ノードの手順で当てる）

### 2.4 replica 1 のボリュームと drain

Longhorn の `node-drain-policy` は `block-if-contains-last-replica` である。対象のノードに「最後の健全な replica」があるボリュームがあると、Longhorn は instance-manager の PDB を外さず、drain が終わらない。

| ノード | 最後の replica を持つボリューム |
|---|---|
| chirico | `monitoring/prometheus-...-0` |
| duchamp | `monitoring/prometheus-...-1` |
| oeilvert | `minio/export-minio-0`〜`3`（4 つ） |
| braque、pablo | なし |

replica 1 のボリュームは止まってよい（§2.1 の 2）ので、replica は増やさず、次のように drain を通す。

1. **chirico、duchamp、oeilvert の drain の間だけ、`node-drain-policy` を `allow-if-replica-is-stopped` にする** ✋。drain と再起動が終わり、uncordon した後に `block-if-contains-last-replica` に戻す ✋（§3.8）。
2. **oeilvert では、drain の前に MinIO の StatefulSet を 0 にする** ✋。終わったら元の数（4）に戻す ✋（§3.8）。
3. **chirico、duchamp では、drain の前に Prometheus リソース（`monitoring/kube-prometheus`）の `spec.replicas` を 0 にする** ✋。uncordon の後に 2 に戻す ✋（§3.8）。prometheus は 2 台とも止まるが、止まってよい（§2.1 の 2）。

この形にした理由:

- `allow-if-replica-is-stopped` は、最後の replica が**止まっている**ときだけ drain を通す。drain で Pod が退いてボリュームが detach されると replica が止まるので、drain が進む。replica が動いている（データの書き込みが続いている）ボリュームは引き続き止めてくれる。
  `always-allow` は動いている replica があっても通すので、書き込み中の replica を止めて faulted にしうる。使わない
- 止まった replica のデータはそのノードのディスクに残り、ノードが戻ればそのまま使える。`replica-replenishment-wait-interval` が 6000 秒なので、100 分以内に戻れば、Longhorn は別のノードで作り直さずに元の replica を使う。この手順では、作業中は再構築そのものを止める（§2.5）ので、100 分を過ぎても作業中には作り直されない
- prometheus のボリュームは、使う Pod と replica が同じノードにある（prometheus-0 と chirico、prometheus-1 と duchamp）。しかし drain で Pod が退くと、StatefulSet がすぐに別のノードで作り直し、同じボリュームをそこでアタッチする。replica は対象のノードにしか無いので、replica が動いたままになり、drain が止まる。
  chirico ではこのとおりになった（`results/chirico.md` §2.1。longhorn-manager は `removing chirico PDB is blocked: replica ... has no pdb on another node` と出した）。Prometheus を 0 にすると、10 秒ほどで detach されて replica が止まり、drain が通った。
  StatefulSet を 1 にすると消えるのは番号の大きい prometheus-1 なので、どちらのノードでも 0 にする。変えるのは operator が見ている Prometheus リソースのほうで、StatefulSet を直接変えない
  2 に戻すのは、対象のノードが戻った後にする。先に戻すと、対象のノードの replica を使えずにアタッチできない
- MinIO の 4 つのボリュームは、replica が oeilvert にあり、Pod は別のノード（調査の時点では pablo、duchamp、chirico）でアタッチしている。oeilvert を drain しても、それらの Pod は退かないので、replica は動き続け、ポリシーを変えても drain が止まる。
  MinIO を止めてボリュームを detach させてから drain する。止める方法は、Pod を個別に消す（StatefulSet が作り直してアタッチし直す）より、StatefulSet を 0 にするほうが確実である
- 個別の Pod を消して進める形は、Pod がすぐ作り直されてアタッチし直すので取らない

注意: 上の 3 は、chirico で drain が止まったこと（この節の初めの版では「止まったら 0 にする」としていた）を受けて、drain の前に行う手順にした。

drain を始める前に、対象のノードの replica の配置をもう一度見る。replica 1 のボリュームで、replica が対象のノードにあり、Pod が別のノードにあるものが §2.4 の表のほかにあれば、それを使う workload も同じように止めるかをユーザーに確かめる。
drain が止まったら、`kubectl --context fraction get pdb -n longhorn-system` と drain の出力を見て、どのボリュームで止まっているかを調べる。

### 2.5 作業中は Longhorn の replica の再構築と自動の balance を止める

1 台の作業の間、Longhorn が replica を作り直したり、別のノードへ動かしたりしないようにする（ユーザーの指示、2026-10-17）。
対象のノードの replica は止まるだけでディスクに残るので、ノードが戻ったら、その replica を再同期して使えばよい。作業中に別のノードで作り直すと、データのコピーが増え、戻った後に余った replica の片付けと balance がまた走る。

作業の間だけ、次の 2 つの設定（`longhorn-system` の `settings.longhorn.io`）を変える。drain の前に変え（§3.3 の 5）、uncordon して Longhorn の node が Ready に戻った後に元に戻す（§3.8 の 3）。

| 設定 | 元の値（2026-10-17） | 作業中の値 | 効果 |
|---|---|---|---|
| `concurrent-replica-rebuild-per-node-limit` | `5`（既定値） | `0` | replica の再構築をしない |
| `replica-auto-balance` | `least-effort` | `disabled` | replica の自動の balance をしない |

Longhorn v1.11.2（本番の版）のドキュメント（[Settings](https://longhorn.io/docs/1.11.2/references/settings/)）での説明:

- Concurrent Replica Rebuild Per Node Limit（Danger Zone）: 「when the value is 0, it means disabling the replica rebuilding」。
  再構築を止めると「replica object replenishment will be directly skipped」、つまり足りない replica を作る処理自体が飛ばされる。
  「When the value is 0, the eviction and data locality feature won't work. But this shouldn't have any impact to any current replica rebuild and backup restore」。0 にした時点で走っている再構築は止まらない。
- Replica Auto Balance（Scheduling）: 値は `disabled`（既定値）、`least-effort`、`best-effort`。ボリュームごとの `spec.replicaAutoBalance` がグローバルの値より優先されるが、本番のボリュームはすべて `ignored`（グローバルの値に従う）である（2026-10-17 の読み取り）。

`longhorn-default-setting` の ConfigMap はこの 2 つを持っていない（`priority-class` と `disable-revision-counter` だけ）ので、手で変えた値が上書きされることはない。

変え方（✋。`node-drain-policy` も同じ形で変える）:

```sh
kubectl --context fraction -n longhorn-system get settings.longhorn.io \
  concurrent-replica-rebuild-per-node-limit replica-auto-balance node-drain-policy   # 変える前の値を作業記録に書く
kubectl-admin -n longhorn-system patch settings.longhorn.io concurrent-replica-rebuild-per-node-limit --type=merge -p '{"value":"0"}'
kubectl-admin -n longhorn-system patch settings.longhorn.io replica-auto-balance --type=merge -p '{"value":"disabled"}'
kubectl --context fraction -n longhorn-system get settings.longhorn.io \
  concurrent-replica-rebuild-per-node-limit replica-auto-balance                      # VALUE が変わり、APPLIED が true であること
```

元に戻すときは、記録した値（2026-10-17 の時点では `5` と `least-effort`）で同じように patch し、読み直して確かめる。

注意:

- **この 2 つの設定はクラスタ全体にかかる。** 0 にしている間は、対象のノードだけでなく、**ほかのノードで replica が壊れても作り直されない**。2 replica のボリュームは、その間 1 つの replica で動き続ける。
  変えておくのは 1 台の作業の間（§3.3 の 5 から §3.8 の 3 まで）だけにする。作業を途中でやめる場合も必ず戻す（§4）。次のノードに持ち越さない
- 0 の間は data locality（本番では `best-effort` のボリュームが 17 個ある）と eviction も動かない。作業の間だけなので問題にしない
- 元に戻すと、止まっていた replica の再同期が始まる。uncordon した後、Longhorn の node（`kubectl --context fraction -n longhorn-system get nodes.longhorn.io <ノード>`）が Ready で schedulable に戻ってから戻す。
  Ready になる前に戻すと、対象のノードの replica を使えず、ほかのノードで作り直されることがある
- `replica-replenishment-wait-interval` は 6000 秒（100 分）である。replica が止まってから 100 分を過ぎて元に戻すと、Longhorn は止まった replica を使わずに新しい replica を作ることがある（差分ではなく全体のコピーになる）。データは失わないので、時間がかかるだけである

## 3. 1 台ごとの手順

### 3.1 更新する順番

| 順 | ノード | 理由 |
|---|---|---|
| 1 | chirico | 外から見える役割が無い（MetalLB の controller、coredns の 1 つ、Longhorn の CSI などは他のノードへ移れる）。Pod は多いが、どれも Deployment か、replica が他にもある。手順の確かめに向く |
| 2 | duchamp | chirico と同じく、外から見える役割が無い。ddns は pablo でも動く |
| 3 | oeilvert | MinIO の全停止、devbox、fraction-agents などの StatefulSet があり、影響が大きい。2026-07 に起動時の systemd の依存で kubelet が上がらなかったこともある。2 台で手順が固まってから行う |
| 4 | braque | NFS の停止が多くのものに波及する（`registry.fraction.jp` の保存先も braque）。ZFS の取り込みもある |
| 5 | pablo | porkadot の bootstrap ノード。`registry.fraction.jp` の Pod と fs の h2 が載る。最後にして、他の 4 台で問題が無いことを確かめてから行う |

braque は §2.1.1 の止めてよい時間帯に行う。ほかのノードは、いつ行ってもよい（§2.1 の 5）。

### 3.2 流れと所要時間の目安

| 段階 | 内容 | 目安 |
|---|---|---|
| 3.3 | 事前確認、cordon、drain | 10〜30 分（Longhorn の detach を待つ） |
| 3.4 | 22.04 のまま、Docker のリポジトリを外し、更新を当て、containerd を Ubuntu の 2.2.1 に置き換える。再起動 | 20〜30 分 |
| 3.5 | `do-release-upgrade`、再起動 | 30〜60 分 |
| 3.6 | 24.04 での containerd と kubelet の確認 | 10 分 |
| 3.7 | 確認 | 15 分 |
| 3.8 | uncordon、Longhorn の再同期を待つ | 10〜30 分 |

containerd の置き換え（3.4）を `do-release-upgrade`（3.5）より先に行う（以下「A の順」）。dev では A の順（worker04）と逆の順（worker02、`do-release-upgrade` の後に置き換える「B の順」）の両方を通し、どちらも containerd 2.2.1 と kubelet 1.29.8 で Ready に戻った。A の順にした理由:

- containerd の切り替え（1.6 → 2.2）と OS の更新を別の段階に分けられる。問題が出たときにどちらが原因か切り分けられ、切り替えの直後はまだ 22.04 なので、`containerd.io` 1.6.8 にすぐ戻せる
- B の順では version 2 の config が残る。起動のたびに migrate の警告、v1 時代のキー 10 個の `Ignoring unknown key`、`tracing` の deprecation（containerd v2.3 で削除）が出て、pause も `k8s.gcr.io/pause:3.6` のまま。どのみち後で config を作り直すことになる。A の順なら version 3（`registry.k8s.io/pause:3.10.1`）になり、警告も deprecation も無い
- `do-release-upgrade` の時点で third-party のパッケージ（`containerd.io`）が無く、更新の計算に出てこない。B の順では `containerd.io` が「Obsolete」として残る

dev の A の順での版の動き: 22.04 で `containerd` 2.2.1-0ubuntu1~22.04.2 と `runc` 1.3.4-0ubuntu1~22.04.1 を入れ、`do-release-upgrade` で `containerd` 2.2.1-0ubuntu1~24.04.3 と `runc` 1.3.4-0ubuntu1~24.04.1 に上がった。config は version 3 のまま残った。

### 3.3 事前確認と drain ✋

1. 対象のノードの読み取りの確認。
   - `kubectl --context fraction get node <ノード> -o wide`: Ready
   - ノードで `cat /etc/os-release`、`containerd --version`、`apt-mark showhold`（空）、`ls /etc/apt/sources.list.d/`
   - 対象のノードに載っている Pod と、Longhorn の replica の配置（§2.4 の表と同じか）
   - Longhorn のボリュームで、対象のノード以外に replica が無い（healthy な replica が対象のノードだけにある）ものが §2.4 の表から増えていないか
   - 他のノードがすべて Ready で、Longhorn に degraded のボリュームが無いこと（ベースラインで degraded のものを除く）
2. 対象のノードの設定を控える（読み取り。作業端末に保存する）: `/etc/containerd/config.toml`、`/etc/apt/sources.list.d/`、`kubelet.service`、`/etc/systemd/system/cluster-dns.service`、`/etc/multipath.conf`、`/etc/sudoers`、netplan、`dpkg --get-selections`。
3. ✋ `infra-admin` のトークンを発行する。
4. ✋ `kubectl-admin cordon <ノード>`。
5. ✋ Longhorn の `concurrent-replica-rebuild-per-node-limit` を `0` に、`replica-auto-balance` を `disabled` にする（§2.5）。全ノードで行う。
   - 変える前に、2 つの設定と `node-drain-policy` の値を読んで作業記録に書く（2026-10-17 の時点では `5`、`least-effort`、`block-if-contains-last-replica`）。
   - 変えた後に値を読み直し、`0` と `disabled` になっていること（APPLIED が true）を確かめる。
6. ✋ chirico、duchamp、oeilvert では、Longhorn の `node-drain-policy` を `allow-if-replica-is-stopped` にする（§2.4）。
7. ✋ oeilvert では、`minio/minio` の StatefulSet を 0 にし、4 つの MinIO のボリュームが detach されるのを待つ（§2.4）。
   chirico、duchamp では、Prometheus リソース `monitoring/kube-prometheus` の `spec.replicas` を 0 にし、対象のノードの prometheus のボリュームが detach され、replica が stopped になるのを待つ（§2.4 の 3）。
8. ✋ `kubectl-admin drain <ノード> --ignore-daemonsets --delete-emptydir-data --timeout=20m`。
   - コントローラを持たない Pod（ownerReferences が無いもの）があると、drain は `--force` が無ければ止まる。drain の前に `kubectl --context fraction get pods -A --field-selector spec.nodeName=<ノード> -o json | jq -r '.items[] | select((.metadata.ownerReferences // []) | length == 0) | .metadata.namespace + "/" + .metadata.name'` で探す。
     見つかったら、消してよいかをユーザーに確かめ、よければ `--force` を足して drain する（その Pod は消え、作り直されない）。
     chirico には `default/dnsutils` と `tracing/dnsutils`（テスト用の agnhost）があり、ユーザーの判断で `--force` を付けて消すことにした（2026-10-17）。
   - `--timeout=20m` を付けて、止まったまま待ち続けないようにする。時間切れでも cordon は残り、退いた Pod は戻らない。原因を直してから同じ drain を流し直す
   - 止まったら、出力と `kubectl --context fraction get pdb -A` を見る。Longhorn の instance-manager の PDB で止まっているなら、longhorn-manager のログ（`removing <ノード> PDB is blocked: replica ...`）でどの replica かを調べ、そのボリュームを使う workload を止めるかをユーザーに確かめる（変更するなら ✋）。
   - MinIO の PDB（maxUnavailable 1）で止まるなら、他のノードの MinIO の Pod が Ready になるのを待つ。
9. drain の後、対象のノードの Longhorn のボリュームがすべて detach されたこと（または他のノードへ移ったこと）を確かめる。
   - 対象のノードの replica の代わりに、新しい replica がほかのノードに作られていないこと（§2.5 の設定が効いていること）。iSCSI のセッション（`sudo iscsiadm -m session`）を見る。
   - chirico では、退いた instance-manager へのセッションが 7 つ（`TRANSPORT WAIT` / `REOPEN`）残った。そのうち 5 つは drain の前からあった古いものだった。マウントされていなければ、そのまま進めて §3.4 の 9 の再起動で片付けてよい（chirico では再起動で消えた。§5.3）

ノードごとの追加の作業:

- **oeilvert**: devbox を使っている人がいないことをユーザーに確かめる。drain の前に、ホストの NFS マウント（`shared/data`、`shared/h`）を使うものが動いていないこと。unattended-upgrades の自動再起動（04:00。ホストの時刻は UTC）が作業中に来ない時間帯であること。
  `homegallery/api` は Deployment の `nodeSelector` が `kubernetes.io/hostname: oeilvert` なので、drain から uncordon まで Pending になる（ユーザーの判断で、止まってよい。`results/oeilvert.md` §2）
- **braque**: drain で動く Pod は無い（DaemonSet だけ）。NFS（nfsd の Pod）はこの段階では止まらない。
  ZFS の pool を起動時に取り込む unit が enable されていること（`systemctl is-enabled zfs-import-cache zfs-import-scan`）。braque では `zfs-import-cache` が disabled で、`zfs-import-scan` は `/etc/zfs/zpool.cache` があるので飛ばされ、22.04 の再起動で `tank1` が取り込まれなかった（§3.4 の 10。2026-10-17 に enable した。`results/braque.md` §3.4）。oeilvert は `zfs-import-cache` が enabled で、pablo には ZFS が無い
- **pablo**: share-manager（homegallery の RWX）と fs の h2、`docker/registry` が他のノードで Running に戻ったことを確かめる。oeilvert のホストの `shared/h` が読めること。
  pablo の drain は 30 秒ほどで終わり、退いた Pod はすべて oeilvert に移った（2026-10-18。`results/pablo.md` §2）。uncordon しても戻らない

### 3.4 22.04 のまま containerd を置き換える ✋

dev の worker04 でこの節の 1〜9 を通してある（dev の検証結果「worker04: A の順」）。

0. ✋ 戻すときのために、`containerd.io` 1.6.8 の deb を残す（braque、chirico、duchamp、pablo）。Docker のリポジトリを外す**前に**、`apt-get download containerd.io=1.6.8-1` でノードの上（例: `/root/`）に落としておく。
   - 24.04 用の Docker のリポジトリには 1.6.8 が無い（1.6.28 以降）。この deb があれば、24.04 の上でも `containerd.io` 1.6.8 に戻せる（dev で確認。§4.2）
   - oeilvert には Docker のリポジトリが無い。`/var/cache/apt/archives/` に `containerd.io_1.6.8-1_amd64.deb` が残っていればそれを控える。無ければ、ほかのノードで落とした deb を写しておく（oeilvert ではキャッシュに無く、chirico の `/root` の deb を写した。sha256 を比べる）
   - braque では、nfsd のイメージ（`gcr.io/google_containers/volume-nfs:0.8`）も控えた（`sudo ctr -n k8s.io images export /root/volume-nfs-0.8.tar gcr.io/google_containers/volume-nfs:0.8`）。レジストリが Docker の schema 1 でしか返さず、containerd 2.x では pull し直せないため。置き換えの後も containerd の中のイメージは残り、そのまま動いた（`results/braque.md` §1.3）
     - 2026-10-18 以降、nfsd は fleet-infra の `infrastructure/nfsd` で管理し、containerd 2.x で pull できるイメージ（`registry.k8s.io/e2e-test-images/volume/nfs:1.6.0`）に替えた（`docs/nfsd-to-fleet-infra/record.md`）。次からはこの控えは要らない
1. ✋ Docker の apt リポジトリを外す（braque、chirico、duchamp、pablo）。`/etc/apt/sources.list.d/docker.list` を、apt が読まない名前に変えて残す（戻せるように）。
   - これを先にしないと、次の `full-upgrade` で Docker の `containerd.io` 2.4.2 が入る（調査 §1）。
   - `containerd.io` を hold しても代わりにならない。dev では、hold していても Docker の jammy リポジトリに 2.4.2 があるため、`do-release-upgrade` が「Please install all available updates for your release before upgrading」で更新を拒否した。リポジトリを外して回避した。
     2.4.2 の `containerd config default` は config version 4 を出し、porkadot 0.29.1 の `setup-containerd` はそれに対応していない（§5.1）。**1 → 3 の順（リポジトリを外してから Ubuntu の `containerd` に置き換える）を崩さない。**
   - 外した後、`apt-cache policy containerd containerd.io` で、`containerd.io` の候補が 1.6.8（`/var/lib/dpkg/status` だけ）になり、`containerd` の候補が Ubuntu の 2.2.1-0ubuntu1~22.04.2 になっていることを確かめる。
2. ✋ `sudo apt update` → `sudo apt full-upgrade`。
   - conffile の質問が出たら、**手元の版を残す**（`N`、既定）。対象は調査 §2.2 の表（`sudoers`、`multipath.conf`、oeilvert の `resolved.conf`）。
   - `containerd.io` は候補が無くなるので更新されない（`apt-cache policy containerd.io` で候補が 1.6.8 であることを先に確かめる）。
   - 終わると `/var/run/reboot-required` が立つ（dev で確認）。再起動は 9 で行う。`do-release-upgrade`（§3.5）は再起動の後でないと進めない。
   - systemd が更新に含まれると、パッケージの更新の中で `systemd-networkd` が再起動することがある。cnidaria の経路（proto 200）はいったん消えるが、cnidaria v0.1.1 が数秒で入れ直す（§2.2）。
     終わったら `ip route show proto 200` で経路が戻っていることを見る。戻っていなければ 8 の「経路が戻らない場合」と同じく扱う。
3. ✋ containerd を置き換える。
   - `sudo apt install containerd`（Ubuntu の 2.2.1-0ubuntu1~22.04.2）。`containerd.io` が削除され、`runc` が入る。
     実行の前に、apt が入れる `containerd` の版が `~22.04` の付いた Ubuntu の版であることを確かめる（Docker の版を入れない）。
     `containerd.io` の削除で containerd が止まる。kubelet は containerd に繋がらなくなるが、drain 済みなので DaemonSet の Pod だけが止まる（dev では、22.04 での置き換えで DaemonSet の Pod が 1 回ずつ再起動した）。
     `containerd.io` は remove（purge ではない）なので、`/etc/containerd/config.toml` は残る。Ubuntu の `containerd` は `/etc/containerd/` に何も置かない。
   - **oeilvert**: docker-ce が `containerd.io` に依存しているので、同時に削除される。この 3 は §3.4.1 の手順で行い、`docker.io` も一緒に入れる。
   - apt が削除するパッケージの一覧を、**実行する前に読む**。`containerd.io`（oeilvert では docker-ce 一式も）以外が消える場合は止める。
4. ✋ 古い config を退避する。`/etc/containerd/config.toml` を `config.toml.porkadot-bak.<日時>` に名前を変える。
   - 今の config は version 2 で、`setup-containerd` は version 行のある config を作り直さない。退避しないと、containerd 1.6 の既定値（`k8s.gcr.io/pause:3.6` など、2.x で廃止された項目を含む）が残る。
   - porkadot 以外の書き足しは無いので（調査 §1）、作り直して失うものは無い。
5. ✋ `porkadot setup-containerd --config ./porkadot.yaml --node <ノード>`。
   - 流す前に、ノードで `containerd --version` が Ubuntu の 2.2.1 であること、`containerd config default | head` の `version` が **3** であることを確かめる（読み取り）。
     4 が出たら、Docker の containerd が入っている。**流さずに止める**（porkadot 0.29.1 は version 4 に対応していない。§5.1）。
   - config が無いので `containerd config default` で version 3 の config が作られ、`SystemdCgroup = true` が入り、containerd が再起動する。
   - 出力に `ERROR` や `Unsupported containerd config version` が無いことを確かめる（終了コードは当てにならない）。
   - `Net::SSH::HostKeyMismatch`（`fingerprint ... does not match`）で接続できないときは、§5.7 の known_hosts の問題である。§5.7 の対処をしてから流し直す。**duchamp、oeilvert、pablo は当たる見込みなので、流す前に対処しておく**
6. ノードで確かめる。
   - `containerd --version` が `2.2.1`
   - `/etc/containerd/config.toml` の先頭が **`version = 3`**（2 や 4 ではない）、`[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.runc.options]` の下に `SystemdCgroup = true`
   - `sudo /opt/bin/crictl info` が応答する。`sudo /opt/bin/crictl images` に既存のイメージがある（`/var/lib/containerd` が引き継がれている）。`crictl` は porkadot が `/opt/bin` に置いたもので、sudo の PATH には無い
   - CNI の設定は既定値のままでよい（`max_conf_num` の既定値で、cnidaria の conflist 1 つが読まれる。dev で verify-nodes と netcheck が通った）
   - 再起動の後、新しい pause（`registry.k8s.io/pause:3.10.1`）が pull される。`registry.k8s.io` に届くこと
7. ✋ `sudo systemctl restart kubelet`。ノードが Ready に戻り、DaemonSet の Pod（cnidaria、kube-proxy、Longhorn、MetalLB の speaker、監視）が Running になることを確かめる。
   - chirico では、DaemonSet の Pod は 3 でも 7 でも再起動しなかった。`containerd.io` 1.6.8 の shim のプロセスが動き続け、新しい containerd がそれに繋ぎ直すためである。shim は 9 の再起動で入れ替わる
   - `kubectl --context fraction get node <ノード> -o wide` の CONTAINER-RUNTIME が `containerd://2.2.1`
8. ✋ braque、chirico、duchamp、pablo では、dns addon の修正（§1.5）を当てる。oeilvert は当たっているので何もしない。当て方は次の 2 つのどちらか。

   > `systemd-networkd` を再起動すると cnidaria の経路（proto 200）がいったん消える。cnidaria v0.1.0 では約 5 分の定期 resync まで戻らなかったが、**v0.1.1 で解消した**（dev の測定では v4 が 0.2 秒以内、v6 が約 1 秒で戻った）。本番が v0.1.1 以降であること（§2.2）を前提に、(a) と (b) のどちらを使ってもよい。
   > **推奨は (b)**。触るもの（networkd、multipath）が少ない。dev では (a) も worker04 で流し、rc 0 で害は無かった。

   - (a) `porkadot setup-node --config ./porkadot.yaml --node <ノード>`（aa1b8b6 以降の asset）。
     dns addon が `cluster-dns.service` を修正済みの版にする。同時に `porka-dummy01` の networkd の設定と `/etc/multipath.conf` も addon の版で書き直し、**`systemd-networkd`**、`multipath-tools`、`cluster-dns` を再起動する。
   - (b) **unit だけを置き換える**（oeilvert に当てたのと同じ方法。networkd を再起動しない）。
     1. 今の `/etc/systemd/system/cluster-dns.service` を `/root/cluster-dns.service.bak-<日付>` に写す。
     2. `master`（aa1b8b6 以降）の `assets/kubelet-default/addons/dns/install.sh` の中の unit の内容で、`/etc/systemd/system/cluster-dns.service` を置き換える。中身を手で書き写さず、その heredoc の内容をそのまま使う（デバイス名の `\x2d` を崩さないため）。
     3. `sudo systemctl daemon-reload`、`sudo systemctl reenable cluster-dns.service`（`WantedBy=` に device ユニットが加わったので、enable のリンクを作り直す）、`sudo systemctl restart cluster-dns.service`。
        `cluster-dns` の再起動は `resolvectl` を流し直すだけで、ネットワークには触らない。

   どちらでも、`systemctl cat cluster-dns.service` で §1.5 の依存が入ったことと、`resolvectl status porka-dummy01` に 10.254.0.10 があることを確かめる。次の 9 の再起動で、修正した unit が起動時に正しく動くことも確かめられる。

   (a) の後は `ip route show proto 200` で経路が戻っていることを見る。経路が戻らない場合: このノードの Pod から他のノードへの通信が届かなくなる（drain 済みなので、影響は DaemonSet の Pod に限られる）。cnidaria-cni-dev の `verify-nodes.sh` で経路の不足を確かめ、このノードの cnidaria の Pod を消して作り直させるか ✋、そのまま 9 の再起動に進む（cnidaria は起動時に経路を入れ直す）。
9. ✋ ノードを再起動する（`sudo reboot`）。22.04 の更新の反映と、containerd 2.2.1 で起動から上がることの確認を兼ねる。
   - braque・chirico・duchamp は 2026-01 以来の再起動である。起動しない場合に備えて、コンソールを用意しておく。
   - 止めてから kernel が起動するまでに時間がかかる。chirico では約 5 分、duchamp では約 17 分、oeilvert（9 日前に再起動していた）では約 2 分かかった（どれも journal に残らない区間）。起動そのものは 30 秒ほどである。20 分ほどは上がってこなくても慌てない。
     braque では止めてから約 30 秒で kernel が起動したが、`systemd-networkd-wait-online.service` が 2 分待って失敗する（更新前から）ので、起動に 2 分 40 秒〜3 分かかった。pablo（14 日前に再起動していた）では約 5 分だった
   - **braque を再起動している間は、LAN から Service の IP（10.254.0.0/16）に届かず、LAN で `fraction.cluster` の名前を引けない。** 家のルーター（jumelle）に 10.254.0.0/16 への静的ルートが via 192.168.1.131（braque）で入っており、LAN の dnsmasq は `fraction.cluster` を 10.254.0.10 に転送しているため（§2.1.1）。再起動の前にユーザーに伝える
10. 再起動の後、6 と 7 の確認をもう一度行う。加えて §3.7 の 8〜13（ノードごとの確認）を行う。
    - **braque**: `zpool status` と `findmnt /export` で、`tank1` が取り込まれて `/export` が `tank1/export` であることを、真っ先に確かめる。
      取り込まれていなければ、nfsd の Pod は root のディスクの空の `/export` を公開してしまう。✋ `sudo zpool import tank1` で取り込み、✋ nfsd の Pod を消して作り直させる（Pod は取り込む前の `/export` をバインドしたままなので）。`zfs-import-cache.service` が disabled なら ✋ enable する（`results/braque.md` §3.4）

**porkadot で流すのは、5 の `setup-containerd --node` だけ**（8 で (a) を選んだ場合は `setup-node` も）。`install kubelet` は流さない。
kubelet のバイナリ（`/opt/bin/kubelet-v1.29.8`）、`kubelet.service`、`config.yaml`、証明書は、OS 更新でも containerd の置き換えでも変わらないので、流す理由が無い（dev では B の順で porkadot を一度も流さずに Ready に戻った）。
`install kubelet` は `kubelet.conf` を消して TLS bootstrap し直し、kubelet を再起動するので、要らない操作を増やさない。dev では更新後のノードで `setup-node` / `setup-containerd` / `install kubelet --node` を流しても、すべて rc 0 で Pod の再起動も無かったので、何かの理由で流すことになっても害は無い ✋。

### 3.4.1 oeilvert の Docker を `docker.io` に移す ✋

oeilvert では、§3.4 の 3（containerd の置き換え）をこの手順で行う。docker-ce（focal 版の 20.10.18）を削除し、Ubuntu の `docker.io`（jammy-updates の候補は 29.1.3）に移す（§2.1 の 3）。

移す前の状態（2026-10-17 の読み取り）:

| 項目 | 値 |
|---|---|
| パッケージ | docker-ce、docker-ce-cli、docker-ce-rootless-extras、docker-scan-plugin（いずれも focal 版）、containerd.io 1.6.8 |
| Docker の apt リポジトリ | **無い**（パッケージだけが残っている）。`docker.list` を外す作業は要らない |
| データ | `/var/lib/docker`（overlay2、約 232G、イメージ 1212 個、名前の無いボリューム 1 つ） |
| `/etc/docker/daemon.json` | `ipv6: true`、`fixed-cidr-v6: fde0:17ad:84c5:82::/64`。どのパッケージの conffile でもないので残る |
| コンテナ | `devbox`（動いている）と、3〜4 年前に止まった 2 つ |
| devbox | `devbox.service` が `/home/yuanying/dotfiles/devbox/start-daemon` を流す。`docker run --rm` なので、コンテナ自体に残す状態は無い。作業内容は `/home/yuanying`（ホスト）にある。イメージは `registry.fraction.jp/yuanying/devbox-amd64` |

手順:

1. 読み取りで控える: `sudo docker info`、`sudo docker images`、`sudo docker volume ls`、`sudo docker ps -a`、`/etc/docker/daemon.json`、`/var/lib/docker` の容量と `/` の空き（調査では 98G）。
   - Docker の apt リポジトリが無いことを確かめる（`apt-cache policy docker-ce containerd.io` が `/var/lib/dpkg/status` だけを示す）。
     リポジトリがあると、apt が Docker 版を選ぶことがある。ほかの 4 台の `docker.list` は §3.4 の 1 で外すが、oeilvert には無い。
2. devbox を使っている人がいないことをユーザーに確かめ、✋ `sudo systemctl stop devbox`。`--rm` なので devbox のコンテナは消える。
3. ✋ `sudo systemctl stop docker docker.socket`。
4. ✋ `sudo apt install containerd docker.io docker-ce-rootless-extras- docker-scan-plugin-`。
   - 実行する前に `apt-get -s` で削除の一覧を読む。削除されるのは `containerd.io` と docker-ce の 4 つ（`docker-ce`、`docker-ce-cli`、`docker-ce-rootless-extras`、`docker-scan-plugin`）だけであること。
     `apt install containerd docker.io` だけでは、依存が切れる `docker-ce`、`docker-ce-cli`、`containerd.io` の 3 つしか消えない。`docker-ce-rootless-extras` と `docker-scan-plugin` は docker-ce に依存しないので残る。要らないので末尾の `-` で一緒に消す（ユーザーの判断、`results/oeilvert.md` §3.2）
   - `docker.io` の Recommends で `ubuntu-fan` も入る（ユーザーの判断で入れた）。`/etc/network/fan` は FAN の対応表だけで、`/etc/network/interfaces` か `fanctl config` で有効にしないかぎり、ブリッジも経路も作らない
   - **purge しない**（remove のまま）。`/var/lib/docker` と `/etc/docker/` を残す。
   - debconf の「アップグレード時に docker を自動で再起動するか」は「はい」。非対話で流すなら、先に `echo "docker.io docker.io/restart boolean true" | sudo debconf-set-selections` で入れておく
   - `docker.io` は入れた時点で自動で起動する。containerd は 5 の前は古い version 2 の config で動き、migrate の警告を出す（5 の後には消える）
5. §3.4 の 4〜7（config の退避、`setup-containerd`、kubelet の再起動）を行う。`setup-containerd` は containerd を再起動するので、その後に ✋ `sudo systemctl restart docker`。
6. Docker を確かめる。
   - `docker version` のサーバーが 29 系。`docker info` の Storage Driver が overlay2、Docker Root Dir が `/var/lib/docker`、Cgroup Driver が systemd
   - `docker info` の Images の数が 1 の控えと大きく変わらない。`docker volume ls` に元のボリュームがある
     Docker 29 の `docker images` はタグの無いイメージを既定で出さないので、行数は 20.10 より減る（oeilvert では 590 行 → 202 行。タグはすべて残り、`docker images -a` は 1212 個）。タグの一覧で比べる
   - `docker network inspect bridge` で IPv6 が有効で、`fixed-cidr-v6` の範囲がある（daemon.json が読まれている）
   - `sudo iptables -S FORWARD | head` と `ip6tables` で、policy と `CNIDARIA-FWD` の位置を見る。
     この時点では、Docker 29 が `DOCKER-USER` と `DOCKER-FORWARD` へのジャンプを先頭に入れ、`CNIDARIA-FWD` は 3 番目になる（oeilvert）。どちらのチェーンも docker のブリッジ向けだけを扱うので、Pod の通信は通る。
     再起動の後は Docker が kubelet と cnidaria より後に上がるので、`CNIDARIA-FWD` が先頭に戻り、`verify-nodes.sh` の FORWARD の項目も PASS になる。**ip6tables の FORWARD の policy は、再起動の後に Docker が DROP にする**（§3.7 の 7）
7. ✋ `sudo systemctl start devbox`。
   - `docker ps` に devbox がある。ポート 3222、8080、9090、60000〜60010/udp が開いている
   - ユーザーに、`mosh.fraction.jp` に SSH（3222）と mosh で入れることを確かめてもらう
   - devbox のイメージが残っていなければ、`registry.fraction.jp` から pull し直す。レジストリは pablo の Pod で、保存先は braque の NFS である。oeilvert の作業の時点では、どちらも動いている（§3.1 の順）
8. 以降は §3.4 の 9（再起動）に進む。再起動の後、`devbox.service` が自動で上がること（`docker.service` の後、automount の後）を確かめる。

注意:

- 20.10 から 29 への更新では、Docker のデフォルトの設定がいくつか変わっている（ネットワークやファイアウォールの扱いなど）。devbox はホストのポートを公開するだけなので影響は小さい見込みだが、ポートが届かないときは `docker info` の警告と iptables を見る
- 作業中に `docker system prune` などでイメージを消さない。消すのは作業が終わってから、ユーザーの判断で
- `do-release-upgrade`（§3.5）で `docker.io` は noble の版に上がる。更新の後、§3.7 の oeilvert の確認で devbox をもう一度確かめる
- 戻す場合（§4.2）: docker-ce の focal 版は Docker のリポジトリが無いので入れ直せない。Docker のリポジトリ（jammy）を足して jammy 版の docker-ce と containerd.io を入れる形になる。その場でユーザーと決める

### 3.5 `do-release-upgrade` ✋

**2 台目からは、オペレーター（agent）が非対話で流す**（ユーザーの判断、2026-10-17）。chirico はユーザーが対話モードで流した（`results/chirico.md` §4）。
conffile の質問と「不要になったパッケージを削除するか」への答えは、chirico で決まった答えと非対話の答えが同じなので、手で答える理由が無い。

1. 前提の確認（読み取り）。
   - `apt list --upgradable` が空（3.4 で当たっている）。phased update で止められているもの（chirico では `open-vm-tools`）は残っていてよい。chirico では、それが残ったままでも `do-release-upgrade` は拒否しなかった
   - `/var/run/reboot-required` が無い
   - `/` の空きが 10G 以上（調査では最小 88G）
   - third-party のリポジトリが無い（`/etc/apt/sources.list.d/` が空か、無効にした名前のファイルだけ）。`docker.list` が残っていると、`containerd.io` 2.4.2 が「当たっていない更新」と見なされ、`do-release-upgrade` が拒否する（§3.4 の 1）
   - 手元で変わっている conffile を控える。dpkg の md5 が合わないもの（`dpkg-query -W -f='${Conffiles}\n'` の md5 で `md5sum -c`）と、ucf が管理するもので `/var/lib/ucf/hashfile` と合わないもの。
     chirico では `/etc/sudoers`、`/etc/multipath.conf`、`/etc/ssh/sshd_config`（ucf。末尾の `PasswordAuthentication no`）だった。`sshd_config` は調査 §2.2 の表に無かったので、ほかのノードでも確かめる
2. ✋ 非対話で流す。SSH が切れても止まらないように、systemd の unit の中で動かす。

   ```sh
   sudo systemd-run --unit=release-upgrade \
     --setenv=DEBIAN_FRONTEND=noninteractive --setenv=UCF_FORCE_CONFFOLD=1 \
     do-release-upgrade -f DistUpgradeViewNonInteractive
   ```

   - `DistUpgradeViewNonInteractive` は、dpkg の conffile の質問に `n`（手元の版を残す）と答え、Yes/No の質問（不要になったパッケージの削除を含む）には Yes と答え、**最後の再起動はしない**（24.04 の `DistUpgradeViewNonInteractive.py` の `conffile()`、`askYesNoQuestion()`、`confirmRestart()` で確かめた）。ucf の質問は `UCF_FORCE_CONFFOLD=1` で手元の版を残す
   - 進み具合は `/var/log/dist-upgrade/main.log` と `apt-term.log` で見る。終わりは `systemctl is-active release-upgrade` が inactive になったときで、`systemctl show release-upgrade -p Result -p ExecMainStatus` で結果を見る
   - **途中で 8〜10 分ほど、新しい SSH の接続ができなくなる。** oeilvert では 22:51:55〜23:01:56Z の約 10 分。chirico では 12:56〜13:04Z に、port 22 は `Connection refused`、予備の port 1022（対話モードのとき）は鍵交換で reset された。openssh-server と libssl（t64 の移行）が入れ替わる間である。ping と Node の Ready は続く。systemd の unit で流していれば、更新は止まらない。慌てて別の手を打たずに待つ
3. 終わったら、再起動の前に確かめる（読み取り）。
   - `/etc/os-release` が 24.04.5
   - 1 で控えた conffile が手元の版のまま。特に `/etc/sudoers` の `NOPASSWD`（`sudo -n true` が通ること）と `/etc/ssh/sshd_config`
   - `/var/log/dist-upgrade/history.log` の `Remove:` と `Purge:` に、`containerd`、`runc`、`open-iscsi`、`nfs-common`、`multipath-tools`、`zfsutils-linux`、`sudo`、`openssh-server`、oeilvert の `docker.io` と `libvirt`・`qemu` が無いこと。無くなっていたら、再起動の前に止めて報告する
     （chirico で消えたのは、t64 で名前が変わったライブラリの古い名前、5.15.0-164 の kernel、python3.10、`irqbalance`、`isc-dhcp-client`、`binutils`、`policykit-1` など。`results/chirico.md` §4.2）
     （oeilvert では、無効だった `ufw` も消えた。noble の `ufw` は `iptables-persistent` と同時に入れられないため。braque と pablo には `iptables-persistent` が無いので、消えない見込み。`results/oeilvert.md` §4.3。braque では消えなかった）
   - `/etc/apt/sources.list.d/` に `third-party.sources` ができることがある。もとの `sources.list` にあったコメントアウト済みの third-party の行を deb822 に移したもので、`Enabled: no` なら何もしない（oeilvert）
   - `dpkg -l containerd runc` が ~24.04 の版
4. ✋ 再起動する（`sudo systemctl reboot`）。再起動はユーザーに知らせ、コンソールで見られることを確かめてから行う。
   **braque** では、再起動の間、NFS に加えて、LAN から Service の IP（10.254.0.0/16）と `fraction.cluster` の名前解決が使えない（§2.1.1、§3.4 の 9）。ユーザーに伝えてから再起動する
5. 再起動の後、24.04 で上がってくることを確かめる。上がってこなければコンソールで見る（ユーザー作業）。
6. ✋ `irqbalance` を入れ直す（`sudo apt-get install -y irqbalance`）。`do-release-upgrade` が「不要になったパッケージ」として purge する（chirico、duchamp、oeilvert）。ユーザーの判断で 24.04 でも使う。3 の `history.log` の `Purge:` に `irqbalance` があることを確かめてから入れる

> `do-release-upgrade` は systemd を更新するので、途中で `systemd-networkd` が再起動し、cnidaria の経路（proto 200）がいったん消える。cnidaria v0.1.1 が数秒で入れ直す（§2.2）。
> 再起動の後、§3.7 の 5（`verify-nodes.sh`）で経路が揃っていることを確かめる。消えるのは Pod 向けの経路で、ホストの経路ではない。新しい SSH の接続ができなくなるのは、上の 2 の openssh-server の入れ替えのためである。

dev（worker04）では、`do-release-upgrade` は非対話で約 11 分かかった。`containerd` と `runc` は ~24.04 の版に上がり、`/etc/containerd/config.toml` は version 3 のまま残った。Obsolete に `containerd.io` は出ず、`setup-containerd` の再実行は要らなかった。
残った conffile は `/etc/ca-certificates.conf.dpkg-old` だけだった（dev のノードには手で変えた conffile が無いため。本番では調査 §2.2 のファイルで質問が出る）。apt の source は `ubuntu.sources`（noble）になる。

### 3.6 24.04 での containerd と kubelet の確認

1. ノードで確かめる。
   - `/etc/os-release` が 24.04.5、`uname -r` が 6.8 系
   - `containerd --version` が 2.2.1 系。`dpkg -l containerd runc` が `2.2.1-0ubuntu1~24.04.3` と `1.3.4-0ubuntu1~24.04.1`（またはそれ以降の noble の版）。`/etc/containerd/config.toml` が 3.4 で作った version 3 のまま
   - `sudo journalctl -u containerd -b` に migrate の警告や `Ignoring unknown key` が無い。`sudo ctr deprecations list` が空
   - `systemctl is-active containerd kubelet` が active
   - `sudo journalctl -u kubelet --since '10 min ago'`: cgroup と CRI のエラーが続いていない
2. config が置き換わっていた、または `SystemdCgroup` が消えていた場合は、✋ `porkadot setup-containerd --config ./porkadot.yaml --node <ノード>` を流して直す。

### 3.7 確認

各項目を上から順に確かめる。すべて合格してから 3.8 へ進む。1〜7 は uncordon の前（cordon のまま）、全体の workload は 3.8 の後にもう一度見る。

| # | 確認 | 方法 | 合格基準 |
|---|---|---|---|
| 1 | Node | `kubectl --context fraction get node <ノード> -o wide --show-labels` | Ready（SchedulingDisabled）。OS-IMAGE が Ubuntu 24.04.5、CONTAINER-RUNTIME が `containerd://2.2.1`、KERNEL が 6.8 系。ラベル（metallb、ddns、nfsd、tgtd、zfs など）が残っている |
| 2 | CSR | `kubectl --context fraction get csr` | Pending が残っていない（kubelet の証明書は持ち越すので、新しい CSR は出ない見込み） |
| 3 | DaemonSet の Pod | `kubectl --context fraction get pods -A -o wide --field-selector spec.nodeName=<ノード>` | cnidaria、kube-proxy、node-exporter、smart-exporter、Longhorn（manager、csi-plugin、engine-image。Longhorn ノードのみ）、MetalLB の speaker（ラベルのあるノード）、nfsd（braque のみ）が Running。restart が増え続けていない |
| 4 | ストリーミング | 対象のノードの Pod に `kubectl --context fraction logs` | ログが読める |
| 5 | cnidaria | `verify-nodes.sh` | 全項目 PASS（ベースラインと同じ）。cnidaria のログに error が無い |
| 6 | ホストの nft | ノードで `nft --version`、`sudo nft list tables` | 1.0.9 系。`inet cnidaria` が見え、segfault しない（22.04 の 1.0.2 では落ちた。調査 §3.5） |
| 7 | iptables | ノードで `sudo iptables -S FORWARD \| head`、`sudo ip6tables -S FORWARD \| head` | policy ACCEPT、または `CNIDARIA-FWD` へのジャンプが先頭にある。**oeilvert**: Docker（`docker.io`）が FORWARD の policy を DROP にしても、`CNIDARIA-FWD` が先頭にあって Pod の通信が通ること（oeilvert では v6 が DROP になり、`netcheck.sh` は 168/168 だった） |
| 8 | ディスクとマウント | `lsblk`、`df` | Longhorn のディスク（/var/lib/longhorn、oeilvert は /var/lib/longhorn2 も）がマウントされている |
| 9 | ZFS（braque、oeilvert） | `sudo zpool status`、`zfs list` | pool が ONLINE で、`/export` がマウントされている。**`zpool upgrade` はしない** |
| 10 | multipath と iSCSI | `cat /etc/multipath.conf`、`systemctl is-active iscsid multipathd` | multipathd addon の版のまま（`sd*` の blacklist）。iscsid が active |
| 11 | sudo | `sudo -n true` | パスワードを聞かれない（`/etc/sudoers` の `NOPASSWD` が残っている） |
| 12 | DNS | `systemctl cat cluster-dns`、`systemctl status cluster-dns`、`resolvectl status porka-dummy01` | dns addon の修正済みの版（§1.5）が当たっている。active。`porka-dummy01` に 10.254.0.10 と `svc.cluster.local` の検索ドメインがある |
| 13 | 失敗している unit | `systemctl --failed` | 調査 §2.1 の表に無いものが増えていない |

ノードごとの追加の確認:

- **oeilvert**:
  - `sudo journalctl -b 0 | grep "ordering cycle"` が空
  - `cluster-dns.service` に、`porka-dummy01` のデバイスと `systemd-networkd` への依存が入っている（dns addon の修正済みの版。§1.5）。入っていなければ止めて報告する
  - `home-yuanying-shared-data.automount` と `-h.automount` が `active (waiting)`、`home-yuanying-shared-nfs.mount` が active
  - `/etc/systemd/resolved.conf` が手元の版のまま
  - Docker と devbox: `systemctl is-active docker devbox`、`docker ps` に devbox がある。`mosh.fraction.jp` に SSH（3222）で入れる（ユーザーに確かめてもらう）
  - `netfilter-persistent` が 2021 年の `rules.v6` を読み込んでも、cnidaria の v6 の通信が通ること（`netcheck.sh` で見る）
- **braque**:
  - nfsd の Pod が Runningで、コンテナの `/exports` が `tank1/export` であること（`crictl exec <nfsd> df -h /exports`）。ほかのノードから NFS が読める（oeilvert のホストの `shared/nfs` で `ls`、braque の NFS を使う Pod のどれかで読み書き）
  - nfsd のログの `exportfs: / does not support NFS export` は更新の前から出ている（`volume-nfs` の起動スクリプトによるもの）
  - `registry.fraction.jp` から pull できる
- **pablo**:
  - fs の h2、`docker/registry`、share-manager が Running（uncordon 前は他のノードで動いている）

### 3.8 uncordon と後始末 ✋

1. ✋ `kubectl-admin uncordon <ノード>`。
2. §2.4 で変えたものを ✋ 元に戻す。`node-drain-policy` を `block-if-contains-last-replica` に、oeilvert では `minio/minio` の StatefulSet を 4 に、chirico と duchamp では Prometheus リソースの `spec.replicas` を 2 に戻す。
   MinIO と prometheus の Pod が Running になり、ボリュームが healthy でアタッチされたことを確かめる。
3. Longhorn の node（`kubectl --context fraction -n longhorn-system get nodes.longhorn.io <ノード>`）が Ready で schedulable に戻ったことを確かめてから、✋ §2.5 の 2 つの設定を元の値（§3.3 の 5 で記録した値）に戻す。
   - `concurrent-replica-rebuild-per-node-limit` を `5` に、`replica-auto-balance` を `least-effort` に戻す（2026-10-17 の時点の値）。
   - 戻した後に値を読み直して確かめる。
   - 戻すと、対象のノードの止まっていた replica の再同期が始まる。
   - drain で replica が止まってから 100 分（`replica-replenishment-wait-interval`）を過ぎて戻すと、止まった replica を使わずに新しい replica を作ることがある（§2.5 の注意）。replica の `spec.failedAt`（drain の時刻）を見て、戻す時刻を作業記録に書く。chirico では drain から 98 分、duchamp では 52 分、oeilvert では 49 分で戻した
   - Prometheus を 2 に戻すと、prometheus-0 と prometheus-1 が更新前と逆のノードで起動することがある（duchamp ではそうなった）。data locality（`best-effort`）で、replica 1 のボリュームの replica が Pod のあるノードへ丸ごとコピーされる。データは失わず、ボリュームは healthy のままである。drain で別のノードへ移った 2 replica のボリューム（duchamp では `open-webui-pipelines`、oeilvert では natsumi、hedgedoc の db、fraction-agents の deep-researcher と gmail-agent の 4 つ、pablo では `fs/h2`）も、同じ理由で replica が 1 つ移る。
     pablo では `fs/h2`（300G）の replica が oeilvert へ約 30 分かけて丸ごとコピーされ、pablo の replica は消えた。pablo に replica が 1 つも無くなった（`results/pablo.md` §6）
4. Longhorn: 対象のノードの replica が running に戻り、degraded のボリュームがベースラインから増えていないこと。**再同期（再構築）が終わるまで待つ**（§3.9 の条件）。
   - 再構築が始まらない、または対象のノードの replica ではなくほかのノードに新しい replica が作られた場合は、作業記録に書く（§2.5 の注意の 100 分を過ぎた場合など）。
   - faulted になったボリュームは自動では直らない。使っている Pod を消してアタッチし直すと auto-salvage が走る（Wiki `entities/oeilvert`）。Pod を消すのは ✋
   - 古い iSCSI セッションでアタッチできない場合は §5.3
5. Running / Completed 以外の Pod が、ベースラインから増えていないこと。
6. ✋ `netcheck.sh` と `check-apps.sh`（cnidaria の手順書のスクリプト）を流す。結果がベースラインと同じであること。LoadBalancer（gated、h2-sshd、natsumi-sshd、minecraft）と VIP が応答すること。
7. `infra-admin` のトークンを破棄する（`unset ADMIN_TOKEN`）。
8. 作業記録に、時刻（drain の開始、containerd の置き換え、再起動 2 回、uncordon）、conffile の質問とその答え、削除したパッケージ、OS / kernel / containerd の版を書く。

### 3.9 次の 1 台へ進む条件

次の **すべて** を満たしてから、次のノードの 3.3 に入る。

- 全 8 台の Node が Ready。更新したノードが Ubuntu 24.04.5 と `containerd://2.2.1`。
- etcd 3/3 healthy、VIP が応答する。
- Running / Completed 以外の Pod が、ベースラインから増えていない。
- Longhorn のボリュームが healthy（ベースラインで healthy でないものを除く）。再構築（§3.8 の 3 で設定を戻した後の再同期を含む）が終わっている。
- Longhorn の `concurrent-replica-rebuild-per-node-limit`、`replica-auto-balance`、`node-drain-policy` が元の値に戻っている（§2.5、§2.4）。
- cnidaria の `verify-nodes.sh`、`netcheck.sh`、`check-apps.sh` がベースラインと同じ。
- 更新したノードが、少なくとも 30 分、再起動や NotReady なしで動いている。1 台目（chirico）の後は、1 日置くことを推奨する。
- **ユーザーが次の 1 台へ進むことを承認した。**

5 台目を終えたら §6 に進む。

## 4. 失敗したときの復旧方針

`do-release-upgrade` は戻せない。どの段階で失敗したかで方針が変わる。どの場合も、その場で止めてユーザーに報告し、方針を決めてから動く。
ノードは drain 済みなので、Pod は他のノードで動き続ける。急がずに直せる（oeilvert の MinIO と braque の NFS は止まったままになる）。

**どの段階でやめる場合も、§2.5 の 2 つの設定（`concurrent-replica-rebuild-per-node-limit`、`replica-auto-balance`）を元の値に戻す** ✋。0 のままでは、クラスタ全体で replica が作り直されない。
対象のノードがすぐに戻らない（直すのに時間がかかる、入れ直す）場合は、ノードが戻るのを待たずに戻してよい。止まった replica の代わりに、ほかのノードで replica が作り直される。どちらにするかはユーザーと決める。

### 4.1 drain まで（3.3）

`kubectl-admin uncordon <ノード>` で戻す ✋。§2.4 で変えたもの（`node-drain-policy`、MinIO の StatefulSet、Prometheus の replicas）と、§2.5 の 2 つの設定を戻す ✋。

### 4.2 containerd の置き換え（3.4）で containerd か kubelet が上がらない

1. `journalctl -u containerd`、`journalctl -u kubelet` を読む。config の問題なら、退避した config と比べて直し、`setup-containerd` を流し直す ✋。
2. 戻す場合 ✋: §3.4 の 0 で残した deb を `sudo apt install ./containerd.io_1.6.8-1_amd64.deb` で入れる（Ubuntu の `containerd` と `runc` が削除される）。退避した `config.toml.porkadot-bak.<日時>`（version 2）を `config.toml` に戻し、containerd と kubelet を再起動する。containerd 1.6 は version 3 の config を読めないので、config は必ず戻す。
   - deb が無ければ、22.04 のうちは退避した `docker.list` を戻して `apt update` → `sudo apt install containerd.io=1.6.8-1` でもよい
   - dev では 24.04 の上でこの戻し方を通した。Pod が 1 回ずつ再起動し、MetalLB の speaker が 1 回 CrashLoopBackOff になってから 1 分ほどで戻った。24.04 に上げた後（§4.5）でも同じ方法で containerd だけを戻せる
   oeilvert は `docker.io` が Ubuntu の `containerd` に依存するので、`docker.io` のまま `containerd.io` だけを戻すことはできない。戻すなら Docker のリポジトリ（jammy）から docker-ce と containerd.io を入れる形になる（§3.4.1 の注意）。その場でユーザーと決める。
3. 22.04 + containerd 1.6.8 に戻ったら uncordon し、原因を調べてから出直す。

### 4.3 22.04 の再起動（3.4 の 9）で上がらない

コンソールで見る（ユーザー作業）。GRUB で前のカーネル（5.15.0-164 など、`full-upgrade` の前のもの）を選んで起動できるかを試す。
上がったら、何が原因かを調べる（ネットワーク、ZFS、マウント、systemd の依存）。oeilvert なら、7 月の障害（`cluster-dns.service` と automount の依存。`journalctl -b 0 | grep "ordering cycle"`）も疑う。

### 4.4 `do-release-upgrade` の途中で止まった

1. SSH が切れただけなら、入り直して `sudo screen -x`、または port 1022 の予備の sshd で入る。
2. パッケージの設定で止まった場合は、`sudo dpkg --configure -a` と `sudo apt -f install` で進める ✋。
3. 再起動の後に上がらない場合は、コンソールで GRUB の「Advanced options」から 5.15 のカーネル（残っていれば）で起動を試す。

### 4.5 24.04 で上がったが、kubelet や Pod が戻らない

1. §3.6 と §3.7 の項目のどこで外れるかを見る。containerd の config なら `setup-containerd` を流し直す ✋。
2. kubelet の設定や証明書の問題なら、`porkadot install kubelet --config ./porkadot.yaml --node <ノード>` を流す ✋。`cluster-dns.service` と `multipath.conf` は addon の版で書き直される（§1.5 の修正が入っていれば問題ない）。
3. cnidaria の問題なら、cnidaria-cni-dev の coordinator に相談する。cnidaria の切り戻し（`rollback.sh`）は全台に効くので、1 台の問題では使わない。

### 4.6 最後の手段: 24.04 を新しく入れ直す

in-place で直せない場合は、ユーザーと相談のうえで、24.04.5 を入れ直してノードを参加させ直す。

- Longhorn のディスク（chirico、duchamp、pablo の /var/lib/longhorn、oeilvert の /var/lib/longhorn2）と、ZFS の pool（braque の tank1、oeilvert の tank）は、OS のディスクとは別のディスクにある。**入れ直すのは OS のディスクだけにする。** 入れ直しの前に、どのディスクに入れるかをユーザーと確かめる
- ホスト名、IP、SSH ユーザー（`yuanying`、パスワードなしの sudo）を元と同じにする。netplan は 3.3 で控えた設定に合わせる（oeilvert は静的設定）
- Ubuntu の `containerd` を入れ、ZFS の pool を import し、Longhorn のディスクを元のパスにマウントしてから、porkadot の `setup-node`、`setup-containerd`、`install kubelet --node <ノード>` を流す ✋
- `/etc/multipath.conf` と `cluster-dns.service` は、`setup-node` でこのリポジトリの addon が書く。oeilvert の NFS のマウント、Docker と devbox、`resolved.conf` は手で戻す（Wiki `entities/oeilvert`）
- Longhorn は同じノード名とディスクの UUID で、既存の replica を認識する見込み。認識しない場合は replica を捨てて再構築させる（replica 1 のボリュームではデータを失うので、その前に止める）

## 5. 既知の問題と注意

### 5.1 Docker の `containerd.io` が意図せず上がる

Docker の apt リポジトリ（braque、chirico、duchamp、pablo）が残ったまま `apt full-upgrade` すると、`containerd.io` が 2.4.2（Docker 版）に上がる。§3.4 の 1 でリポジトリを先に外す。

**containerd.io 2.4.2 は config version 4 を出す。** dev の検証で、2.4.2 の `containerd config default` が config version 4 を出すことが分かった。
porkadot 0.29.1 の `setup-containerd` は version 2 と 3 にしか対応していないので、config が無いとき（またはこの手順のように退避したとき）や version 行が無いときに `Unsupported containerd config version: 4` で止まる。
Ubuntu の containerd 2.2.1 は version 3 を出すので問題ない。§3.4 の 1 → 3 の順を守り、§3.4 の 5 の前に `containerd config default` の version を確かめる。
porkadot は 0.29.2 で version 4 に対応した。ただしこの手順では Docker の containerd を使わないので、version 3 が出ることを確かめる手順はそのまま残す。
unattended-upgrades は Ubuntu の origin だけを対象にしているので、`containerd.io` を自動では上げない。

### 5.2 `setup-node` / `install kubelet` による上書き

`porkadot setup-node` と `porkadot install kubelet`（中で `setup-node.sh` を呼ぶ）は、`assets/kubelet-default/addons/` の install.sh を流す。この addon は porkadot の render が作るものではなく、このリポジトリに直接置いたものである。
dns addon は `/etc/systemd/system/cluster-dns.service` と `porka-dummy01` の networkd の設定を、multipathd addon は `/etc/multipath.conf` を書き直す。ノードの上で手で直しても、次に流したときに addon の版に戻る。
2026-10-17 の cnidaria 移行で `install kubelet` を全台に流したとき、oeilvert の `cluster-dns.service` の手修正（2026-07-24）が消えた（調査 §2.6）。
直し方は、ノードの上ではなく addon を直すことで、k8s-manifests-fraction#10 で直した（§1.5）。

### 5.3 古い iSCSI セッションで Longhorn のボリュームがアタッチできない

2026-10 に pablo で、消えたエンジンの IP への iSCSI セッションが再接続を続け、ログアウトできずにアタッチが失敗し続けた（Wiki `entities/oeilvert`）。iscsid の再起動では消えず、drain → 再起動で片付いた。
この手順では各ノードを drain して再起動するので、その時点で片付く。uncordon の後に同じ症状が出たら、そのノードを cordon して Pod を別のノードへ逃がし、ユーザーと相談する。

### 5.4 amd64 のホストの nft

22.04 のホストの nft（1.0.2）は、cnidaria のテーブルがあると `nft list` が segfault する。更新前のノードでは、ホストで nft を打たない（cnidaria の手順書のスクリプトはイメージの nft を使う）。
24.04 の nft（1.0.9）では Pi で落ちないことが分かっている。amd64 で落ちないかは、1 台目（chirico）の §3.7 の 6 で確かめる。

### 5.5 oeilvert の自動再起動

oeilvert は unattended-upgrades の自動再起動（`52local-reboot.conf`、04:00）が有効である。作業中に再起動が走らない時間帯で作業する。更新後も設定は残る（`apt.conf.d` の手元のファイル）。

### 5.6 MinIO の replica がすべて oeilvert にある

MinIO の 4 つのボリュームは replica 1 で、replica はすべて oeilvert の /var/lib/longhorn2 にある（調査 §3.4）。oeilvert 以外のノードを止めると、そのノードの MinIO の Pod 1 台が止まる（Pod は別のノードに移り、oeilvert の replica を使ってアタッチし直す）。oeilvert を止めると、MinIO 全体が止まる。
ユーザーの判断で、replica 1 のボリュームは止まってよい（§2.1 の 2）。この手順では replica を増やさず、oeilvert の作業中は MinIO を止める（§2.4）。

### 5.7 porkadot（sshkit）が known_hosts のホスト鍵を「一致しない」と言う

chirico で `setup-containerd` が `Net::SSH::HostKeyMismatch: fingerprint SHA256:... does not match for "192.168.1.83"` で止まった（`results/chirico.md` §3.2）。ホスト鍵は変わっていない。

- 原因は sshkit 1.25.0 の `KnownHostsKeys#keys_for`。名前をハッシュした行（`|1|...`）は、名前が一致した**最初の 1 行の鍵だけ**を返す。作業端末の `~/.ssh/known_hosts` では、1 つのホストの ED25519、RSA、ECDSA が別々のハッシュの行にある。
  ED25519 は ed25519 の gem が無いので読み飛ばされ、次の RSA の鍵だけが返る。サーバーとは ECDSA で鍵交換するので、「一致しない」になる。`ssh` と net-ssh 単体（`Net::SSH::KnownHosts`）は全部の行を読むので通る
- 2026-10-17 の時点で当たるノード: duchamp（192.168.1.135。RSA だけが返る）、oeilvert（.82）と pablo（.134。ハッシュの行が ED25519 の 1 つだけで、鍵が 1 つも返らない）。braque（.131）は ECDSA が返り、対処なしで通った（`results/braque.md` §1.6）。chirico、duchamp、oeilvert、pablo は下の対処をした（duchamp、oeilvert、pablo は porkadot を流す前にした。`results/duchamp.md` §1.5、`results/oeilvert.md` §1.5、`results/pablo.md` §1.5）
- 対処: そのノードの ECDSA の鍵を、名前をハッシュしない行で `~/.ssh/known_hosts` に足す。sshkit はハッシュしない行を先に見る。
  1. 鍵はノードの `/etc/ssh/ssh_host_ecdsa_key.pub` から取り、`<IP> ecdsa-sha2-nistp256 <鍵>` の形にする
  2. `ssh-keygen -lf` の fingerprint が、`ssh-keygen -F <IP> -l` の ECDSA の fingerprint と同じであることを確かめる。
     known_hosts に ECDSA の行が無いとき（oeilvert、pablo）は、代わりに次の 2 つを確かめる。ノードの `/etc/ssh/ssh_host_ed25519_key.pub` の fingerprint が `ssh-keygen -F <IP> -l` の ED25519 と一致すること（1 の鍵は、その ED25519 で認証した SSH で読んだものになる）。`ssh-keyscan -t ecdsa <IP> | ssh-keygen -lf -` が 1 の fingerprint と一致すること
  3. `~/.ssh/known_hosts` の控えを取ってから 1 行足す。`~/.ssh` は agent のサンドボックスの外なので、外での実行をユーザーに頼む
- 確かめ方（読み取り）: porkadot の checkout で、`SSHKit::Backend::Netssh::KnownHosts.new.search_for("<IP>", {})` が ECDSA の鍵を返すこと
- 根本の対処（sshkit の修正か、porkadot での回避）はこのタスクの範囲外で、申し送りにする

## 6. 完了後の確認と後片付け

### 6.1 完了の確認

TASK.md の完了条件を確かめる。

- `kubectl --context fraction get nodes -o wide` で 8 台すべてが Ready で、worker 5 台が Ubuntu 24.04.5 と `containerd://2.2.1`
- etcd 3/3 healthy、VIP 192.168.1.101:6443 が応答する
- Running / Completed 以外の Pod が無い（ベースラインのものは記録して区別する）
- Longhorn のボリュームが healthy（ベースラインで healthy でないものは記録して区別する）
- braque の NFS、MetalLB の LoadBalancer が応答する
- `node-drain-policy` が `block-if-contains-last-replica`、`concurrent-replica-rebuild-per-node-limit` が `5`、`replica-auto-balance` が `least-effort` に戻っている。`minio/minio` の StatefulSet が 4、Prometheus リソースの `spec.replicas` が 2

### 6.2 片付け

- 各ノードに退避したファイル（`docker.list` の退避、`config.toml.porkadot-bak.*`）は、全台が終わってしばらく問題が無ければ消してよい（消すのは ✋）
- Docker の apt の鍵（`/etc/apt/keyrings/docker.gpg`）も同じ

### 6.3 記録

- この手順書と実際の作業の差を、作業記録として残す（このディレクトリに追記するか、PR を分ける）
- Wiki（llm-wiki）の `wiki/synthesis/cluster-upgrade-plan-2026.md`、`wiki/topics/自宅クラスター.md`、各ノードの entity ページを更新する（タスクの作業単位 E）
