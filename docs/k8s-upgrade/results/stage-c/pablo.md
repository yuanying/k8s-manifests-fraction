# pablo の段 C の作業記録

pablo（192.168.1.134）の containerd を、Ubuntu の `containerd` 2.2.1 から Docker の `containerd.io` 2.3.6 に置き換えた記録。手順は `../../runbook-stage-c.md`（以下 runbook）。
時刻は UTC。段 C の 3 台目。1 台目は `chirico.md`、2 台目は `duchamp.md`、クラスタ全体のベースラインと戻すための控えは `baseline.md`。

## 1. 事前の読み取り（2026-10-18 08:35Z〜）

### 1.1 クラスタ（runbook §2.3、§3.12）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。2.3.x のノード: chirico、duchamp（`containerd://2.3.6`）、2.2.1 のノード: ほかの 6 台 |
| etcd、VIP | 3/3 healthy、リーダー: 192.168.1.112、raft term 23111、raft index: 1402241523（そろっている）。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached（ベースラインのもの）: `myao/myao`、`homegallery/cg-data` |
| Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit`: `5`、`replica-auto-balance`: `least-effort`、`node-drain-policy`: `block-if-contains-last-replica`（`replica-replenishment-wait-interval` は `6000`、`default-data-locality` は `best-effort`） |
| controller-manager と scheduler の置き場所 | （worker なので無し） |
| `auth can-i delete pods -A`（`fraction-auditor`） | `no` |
| `containerd.io` の版（runbook §1.6） | 2.3 系の最新は 2.3.6-1 のまま（1 台目と同じ版を入れる） |
| `verify-nodes.sh` | 64 PASS、FAIL 0 |
| PDB | `minio/minio`（maxUnavailable 1、ALLOWED 1）、各 instance-manager（ALLOWED 0）、controller-manager・scheduler・CSI。ベースラインと同じ形 |

### 1.2 対象のノード（runbook §3.3）

| 項目 | 値 |
|---|---|
| Node | Ready、`containerd://2.2.1`、6.8.0-147-generic、起動 2026-10-18 01:25:23Z |
| `containerd --version` / `runc --version` | 2.2.1 / 1.3.4-0ubuntu1~24.04.1 |
| `/etc/containerd/config.toml` | `version = 3`、md5: `665fb78e3b80c49c14575c184b3c5bcf` |
| 控え（`/root/k8u-stage-c/`） | config.toml.before（md5 同じ）、`containerd_2.2.1-0ubuntu1~24.04.3_amd64.deb`、`runc_1.3.4-0ubuntu1~24.04.1_amd64.deb`（sha256 は `baseline.md` と同じ） |
| `apt-cache policy containerd containerd.io runc` | `containerd` と `runc` は Ubuntu の版で入っている。`containerd.io` は候補なし（`1.6.8-1 -1`、`/var/lib/dpkg/status` だけ） |
| `dpkg -l containerd.io docker-ce` | `containerd.io` 1.6.8-1 が `rc`。`docker-ce` は無い |
| `/etc/apt/sources.list.d/`、`preferences.d/`、`keyrings/` | `docker.list.disabled-20261018`、`ubuntu.sources` / `ubuntu-pro-esm-apps`、`ubuntu-pro-esm-infra` / `docker.gpg`（runbook のとおり） |
| 当たっていない Ubuntu の更新 | 0 |
| イメージの数（`crictl images -q`） | 194 |
| `systemctl --failed` | 空 |
| iSCSI | `iscsid.socket`・`iscsid`・`multipathd` が active。セッションは 3 つで、どれも pablo にアタッチしているボリューム（`export-minio-2`、`data-news-agent-0`、`data-wiki-keeper-0`）のもの。Wiki の「消えたエンジン IP へ再接続し続けるセッション」は無い |
| Pod と再起動回数（控え） | 26 個（Running 23、CronJob の Completed 3）。コントローラを持たない Pod は無い |
| 最後の replica を持つボリューム（runbook §2.6） | **無い**。pablo の replica は 3 つで、どれも 2 replica のボリュームの片方（`data-wiki-keeper-0`、`data-news-agent-0`、`ero-data`）。どれもほかのノードに running の replica がある。replica 1 のボリュームの置き場所は duchamp の後と同じ（prometheus-0 が chirico、prometheus-1 と MinIO の 4 つが oeilvert）。`minio-2` の Pod は pablo で動いているが、replica は oeilvert にある |

最後の replica が無いので、`node-drain-policy` を変えず、workload も止めない（duchamp と同じ扱い）。`concurrent-replica-rebuild-per-node-limit` と `replica-auto-balance` だけを切り替える。

## 2. 入れ替え（runbook §3.4〜§3.7）

### 2.1 リポジトリ、鍵、pin（08:36:18Z〜08:36:34Z）

- 鍵の fingerprint: `9DC858229FC7DD38854AE2D88D81803C0EBFCD88`（一致）
- `docker.sources` の `Architectures` は `amd64`
- `apt-cache policy containerd.io` の Candidate と優先度: `2.3.6-1~ubuntu.24.04~noble`。2.3 系の行（2.3.3-1〜2.3.6-1）が 1001、2.4 系と 2.2 系の行は 500

### 2.2 `containerd.io` を入れる（08:36:41Z〜08:36:53Z）

- `apt-get install -s` の結果（Remv / Inst）: runbook §3.5 の 1 と同じ（`0 upgraded, 1 newly installed, 2 to remove`、Remv `containerd`・`runc`、Inst `containerd.io` 2.3.6）
- 入れた版: `containerd.io=2.3.6-1~ubuntu.24.04~noble`（版を指定した）。rc 0
- conffile の扱い: chirico・duchamp と同じく `Using current old file as you requested` は出ず、手元の config が残った（md5 が控えと同じ）
- needrestart が `systemctl restart containerd.service` を流し、`No containers need to be restarted.` と出した

### 2.3 ノードでの確認（runbook §3.6）

| 項目 | 結果 |
|---|---|
| `containerd --version` / `runc --version` | `containerd containerd v2.3.6 ee2735368117d2eb259779949d5e75cdafec9761` / `runc version 1.5.1` |
| config の先頭と md5（控えと同じか） | `version = 3`、`665fb78e3b80c49c14575c184b3c5bcf`（同じ） |
| `containerd config dump`（version、SystemdCgroup、sandbox） | `version = 4`、`SystemdCgroup = true`、`sandbox = 'registry.k8s.io/pause:3.10.1'` |
| journal の error / warning（§8.1 のもの以外） | 無い。`Configuration migrated from version 3` と `failed check for fsverity support` が containerd の起動ごと（08:36:47Z、08:36:50Z）に出た。`unmarshal sandbox spec` は 66 行。ほかに 08:29:05Z の `ContainerStatus ... NotFound` が 1 行あるが、入れる前の 2.2.1（pid 920）のもの |
| `ctr deprecations list` | 空 |
| `crictl info` / イメージの数（入れる前 → 後） | 応答する / 194 → 194 |
| `apt-cache policy containerd.io` | Installed と Candidate が 2.3.6-1、優先度 1001 |

### 2.4 Longhorn の設定の切り替えと kubelet の再起動（runbook §3.7）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 08:37:07 | ✋ `infra-admin` のトークンを発行（3h） | 作業端末の 600 のファイルに置いた。`auth can-i patch nodes` が yes |
| 08:37:12 | ✋ `concurrent-replica-rebuild-per-node-limit` を `0`、`replica-auto-balance` を `disabled` | 直前の値は `5`、`least-effort`。読み直して APPLIED true。`node-drain-policy` は変えない |
| 08:37:20 | ✋ `systemctl restart kubelet` | |

- Node と CONTAINER-RUNTIME: Ready、`containerd://2.3.6`（40 秒後に確認）
- Pod の再起動回数（控えとの差）: 26 個とも同じ（`diff` が空）
- kubelet の journal: 再起動の前の kubelet が、containerd の再起動の間（08:36:51Z）に `containerd.sock: connect: no such file or directory` と `server is not initialized yet` を出した。再起動の後の kubelet は、起動の直後（08:37:21Z）に `Image garbage collection failed once` と `Skipping pod synchronization` を出しただけ（duchamp と同じ）
- **Longhorn の replica は動かなかった**（kubelet の再起動の前後で `replicas.longhorn.io` の一覧が同じ）。Longhorn の node `pablo` は Ready / schedulable のまま。duchamp で起きた auto-balance による replica の移動（`duchamp.md` §3.1）は、設定を kubelet の再起動の前に切り替える順（PR #22）で避けられた
- 監視（runbook §2.4）の FAIL: 無い

## 3. drain（runbook §3.8）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| — | `node-drain-policy` の変更、workload の停止 | しない（§1.2 のとおり最後の replica が無い） |
| 08:38:13 | ✋ `cordon pablo` | |
| 08:38:13〜08:38:44 | ✋ `drain pablo --ignore-daemonsets --delete-emptydir-data --timeout=20m` | rc 0、`node/pablo drained`（31 秒）。`--force` は要らなかった |

- 止まった Pod: pablo の `instance-manager-17a539db…` が PDB で 5 回 `Cannot evict pod` になり、ほかの Pod が退いた後に evict された（chirico・duchamp と同じ形）
- 退いた Pod は 18 個（`minio-2`、`fraction-agents` の `news-agent-0`・`wiki-keeper-0`、Longhorn の CSI の Deployment と `longhorn-ui`、`kube-dns-autoscaler`、`proxy/code`、`aphrael`、`shja`・`shja2`・`sites` の Deployment、CronJob の Completed 3 つ、instance-manager）
- drain の後: pablo でアタッチしているボリュームは 0。attached healthy 20、attached degraded 3（pablo に replica のある 3 つ）、detached 2（ベースラインのもの）。pablo の replica 3 つは stopped。replica の置き場所は drain の前と同じ（代わりの replica は作られていない）。Running / Completed 以外の Pod は 0
- 移った先: `minio-2` と `wiki-keeper-0` が duchamp、`news-agent-0` が chirico で Running。ボリュームもそれぞれのノードにアタッチされた
- pablo の追加の確認（OS 更新の手順書 §3.3）: share-manager（`pvc-0b28d049`、`pvc-baa41130`）、`fs/h2`、`docker/registry` は事前から oeilvert で動いていて、pablo には無かった（drain で動かない）
- iSCSI（Wiki の pablo の節）: drain の後の `iscsiadm -m session` は `No active sessions.`

## 4. 再起動（runbook §3.9）

- 08:39:02 に `systemctl reboot`。kernel の起動は 08:41:00（`uptime -s`）。SSH は 08:41:23 に戻った。Node は 08:41:24 に Ready（SchedulingDisabled）に戻った（Ready の lastTransitionTime）。再起動から Ready まで約 2 分 22 秒（前タスクの約 5 分より短い）
- 監視（runbook §2.4）の FAIL: **VIP が 2 回**（08:39:07Z、08:39:10Z）。LB（192.168.1.200）は 0。段 C の worker の作業で VIP が失敗したのは初めて

### 4.1 再起動で VIP が約 10 秒途切れた

VIP 192.168.1.101 は MetalLB の layer2 の LoadBalancer（`kube-system/porkadot-kubernetes`）で、作業の前は **pablo の speaker が告知していた**（告知するノードは、その Service の Pod の居るノードではなく、`metallb=speaker` のノードの中から MetalLB が選ぶ）。

| 時刻（UTC） | できごと |
|---|---|
| 08:39:02 | pablo を再起動 |
| 08:39:07、08:39:10 | 監視の VIP の `/livez` が失敗（2 回） |
| 08:39:14 | `nodeAssigned`: `announcing from node "192.168.1.113"`（告知が .113 に移った） |
| 08:41:46 | `nodeAssigned`: `announcing from node "pablo"`（pablo の speaker が戻り、告知も戻った。このときは失敗なし） |

- 告知しているノードが落ちてから、ほかの speaker が引き取るまで（memberlist で落ちたと分かるまで）の約 10 秒の途切れ。その後は失敗していない
- chirico・duchamp では起きなかった（VIP を告知していなかった）。作業の後（09:13Z）も VIP は pablo、gated-v4（監視の 192.168.1.200）は chirico、gated-v6 は oeilvert、`h2-sshd` と `natsumi-sshd-aki` は .112、`natsumi-sshd` は .111、`natsumi-sshd-myao` は duchamp が告知している
- runbook §3.9 に、再起動の前にそのノードが告知している LoadBalancer を読むことと、数秒〜10 秒ほど途切れる見込みを足した

## 5. 再起動の後の確認（runbook §3.10）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready,SchedulingDisabled、v1.29.8、`containerd://2.3.6`。ラベルが残っている |
| 2 | cnidaria の Pod | `cnidaria-ss9v7` は起動の直後に 2 回落ち（restart 2 → 4）、08:41:52Z ごろには 1/1 Running。`--previous` のログは `dial tcp 10.254.0.1:443: connect: connection refused`（runbook の想定どおり） |
| 3 | `verify-nodes.sh` | 64 PASS、FAIL 0（ベースラインと同じ）。cnidaria のログの error は 0 |
| 4 | DaemonSet の Pod | 8 つとも Running。再起動回数は kube-proxy 3→4、engine-image 3→4、longhorn-manager 6→8、node-exporter 3→4、smart-exporter 3→4。speaker は 14→16（08:41:27Z に `10.254.0.1:443` の `connection refused` で落ちてから戻った）。`longhorn-csi-plugin` は 12→16。`node-driver-registrar` が `/csi/csi.sock` に繋がらず（longhorn-manager が上がる前）CrashLoopBackOff になり、08:42:40Z ごろまでに 3/3 Running に戻った（duchamp でも 11→14） |
| 5 | ストリーミング | `cnidaria`、`kube-proxy` のログが読める |
| 6 | iptables | v4・v6 とも FORWARD の policy ACCEPT、`CNIDARIA-FWD` へのジャンプが先頭 |
| 7 | ディスク、ZFS | `/var/lib/longhorn`（`/dev/sda`、1.8T、空き 1.7T）がマウントされている。ZFS は無い |
| 8 | iSCSI | `iscsid.socket` と `multipathd` が active、`iscsid.service` は inactive（chirico・duchamp と同じ）。`iscsiadm -m session` は `No active sessions.`（cordon のまま、アタッチしているボリュームが無い） |
| 9 | DNS | `porka-dummy01` に 10.254.0.10、検索ドメイン `default.svc.cluster.local svc.cluster.local cluster.local` |
| 10 | 失敗している unit | 空（ベースラインと同じ） |
| 11 | apt | Candidate `2.3.6-1~ubuntu.24.04~noble`、優先度 1001。`apt-get -s full-upgrade` は `0 upgraded, 0 newly installed, 0 to remove` |
| 12 | `unmarshal sandbox spec` の数 | 73（起動の後） |

ほかに見たもの: containerd は v2.3.6、runc 1.5.1、config は `version = 3` で md5 が控えと同じ。`config dump` は `version = 4`、`SystemdCgroup = true`、`pause:3.10.1`。`ctr deprecations list` は空。イメージは 194 のまま。起動の後の containerd の journal は、`unmarshal sandbox spec` のほかに、08:41:24Z の `ContainerStatus ... NotFound`（level=error）が 6 行（runbook §8.1 の再起動の直後のもの）。warning は `Configuration migrated from version 3` と `failed check for fsverity support` の 1 行ずつ。`RemoveContainer for` の 32 行はどれも level=info（kubelet の古いコンテナの片付け）。

Longhorn の node の condition で `Multipathd`（`MultipathdIsRunning`）と `KernelModulesLoaded`（`KernelModulesNotLoaded`）が False だが、chirico・duchamp・oeilvert も同じで、作業の前からのもの。

## 6. uncordon と後始末（runbook §3.11）

- uncordon の時刻: 08:43:27（cnidaria が Ready になり `verify-nodes.sh` が通った後）
- 戻した workload: なし（止めていない）
- Longhorn の node `pablo` が Ready、schedulable であることを確かめてから、08:43:35 に `concurrent-replica-rebuild-per-node-limit` を `5`、`replica-auto-balance` を `least-effort` に戻した（APPLIED true。`node-drain-policy` は `block-if-contains-last-replica` のまま）。切り替えから 6 分 23 秒
- **08:50:01 に `replica-auto-balance` だけを `disabled` に戻した**（coordinator からの指示の変更。ユーザーの提案で、段 C の間は auto-balance を止めたまま続ける方向。最終の扱いはユーザーと決める）。08:43:35〜08:50:01 の `least-effort` の間に、auto-balance による replica の移動は無かった（下の 6.1 の移動は data locality によるもの）
- 再同期が終わった時刻: 08:44:44（attached healthy 23、detached 2。degraded 0）。設定を戻してから 1 分 9 秒（pablo の stopped の replica 3 つをそのまま再利用した）
- Running / Completed 以外の Pod: 0 個
- `netcheck.sh`: 08:50:19〜08:50:36 に `up` → `run` → `down`。`PASS 168 / 168, pods 8/8`。namespace は消した
- `check-apps.sh`: duchamp の後（08:29Z）の出力と同じ（差が無い）
- トークンの破棄: 08:50:46 に作業端末のファイルを消した。SA のトークンは個別に失効できないので、サーバーの側では発行から 3 時間（11:37 ごろ）で切れる

### 6.1 Longhorn の replica の置き場所

再同期の後（08:49:53Z に 5 分間変わらないことを確かめた）、replica の数はノードごとに chirico 16 → 15、duchamp 10 → 11、oeilvert 17 → 17、pablo 3 → 3。事前の読み取り（§1.2）との差は、`fraction-agents/data-wiki-keeper-0`（pvc-092a74ed）の replica が chirico から duchamp に移ったことだけ（drain で `wiki-keeper-0` の Pod が duchamp に移り、data locality の `best-effort` でローカルの replica が作られた）。

- replica 1 のボリュームの置き場所は変わらない（prometheus-0 が chirico、prometheus-1 と MinIO の 4 つが oeilvert）。`minio-2` の Pod は duchamp に移ったが、MinIO のボリュームは data locality が `disabled` なので replica は oeilvert のまま
- 同じボリュームの replica が同じノードに 2 つ載ったものは無い
- running 以外の replica は事前と同じ: `myao`・`cg-data` の stopped（detached のボリューム）、`ero-data`（pvc-baa41130）と `natsumi-aki`（pvc-e224cffa）の duchamp の failed の replica（`duchamp.md` §6.1。`staleReplicaTimeout` で Longhorn が消す見込み）

## 7. 次の 1 台へ進む条件（runbook §3.12）

3 台目なので、runbook の既定の 30 分をおいて、2026-10-18 09:12Z に確かめた。**すべて満たした**（Longhorn の `replica-auto-balance` は、指示の変更のとおり `disabled` を正しい値として扱う。§6）。

| 条件 | 結果 |
|---|---|
| 全 8 台の Node が Ready。終えたノードが `containerd://2.3.x`、まだのノードが `containerd://2.2.1` | 8 台 Ready。chirico、duchamp、pablo が `containerd://2.3.6`（v1.29.8）、ほかの 5 台が `containerd://2.2.1` |
| 終えたノードの cnidaria の Pod が Ready で、`verify-nodes.sh` が全 PASS | `cnidaria-ss9v7` 1/1 Running（restart 4 のまま）。64 PASS、cnidaria のログの error 0 |
| etcd 3/3 healthy、VIP が応答する | 3/3 healthy、リーダー .112、raft term 23111、index 1402253855 でそろっている。`/readyz` は `ok` |
| Running / Completed 以外の Pod が、ベースラインから増えていない | 0 個 |
| Longhorn のボリュームが healthy。再同期が終わっている | attached healthy 23、detached 2（ベースラインのもの）。replica の置き場所は 08:49Z から変わらない |
| Longhorn の設定。`minio/minio` が 4、Prometheus の `spec.replicas` が 2 | `concurrent-replica-rebuild-per-node-limit` `5`、`node-drain-policy` `block-if-contains-last-replica`（元の値）。`replica-auto-balance` は `disabled`（指示どおり）。MinIO 4/4、Prometheus 2 |
| `netcheck.sh`、`check-apps.sh` がベースラインと同じ | netcheck 168/168（08:50Z）。`check-apps.sh` は duchamp の後と同じ |
| 終えたノードが 30 分以上、再起動や NotReady なしで動いている | Ready は 08:41:24Z から変わらない（約 31 分）。起動は 08:41:00Z、boot id も同じ。pablo の DaemonSet の Pod の再起動回数は 08:42Z から増えていない |

監視（runbook §2.4）は 08:36:04Z から 09:12:49Z まで流し、FAIL は VIP の 2 回（§4.1。pablo の再起動の直後）だけ。入れ替え・kubelet の再起動・drain・uncordon の間は 0。pablo の作業の終わりで止めた。

## 8. 手順書との差、気づいたこと

- §3.7: Longhorn の 2 つの設定を kubelet の再起動の前に切り替える順（PR #22 で直したもの）で、kubelet の再起動の間に replica は動かなかった（duchamp の §3.1 は再現しない）
- §3.11 の 3: coordinator からの指示の変更で、`replica-auto-balance` は `least-effort` に戻さず `disabled` のままにした（§6）。段 C の残りの台でどう扱うか（runbook の §3.11 の 3 と §3.12 の「3 つの設定が元の値」を直すか）は、ユーザーと決めた後に runbook に反映する。この PR では runbook のその部分は変えていない
- 再起動の直後の `longhorn-csi-plugin` の CrashLoopBackOff（`node-driver-registrar` が `csi.sock` を待つ）は、duchamp でも起きていた（restart 11→14）。1 分ほどで戻る。runbook §3.10 の 4 に足した
- iSCSI のセッションは drain の後も再起動の後も 0 で、Wiki にある pablo の古いセッションの件は再現しなかった
- §3.9: pablo が VIP を告知していたので、再起動で VIP が約 10 秒途切れた（§4.1）。runbook は「worker の作業の間は VIP は失敗しない」と読めたので、§3.9 と §5.3 に MetalLB の layer2 の告知の移り変わりによる途切れを足した。残りの台では、oeilvert が gated-v6（`2405:6581:8580:301:ace::200`）を、control-plane が `h2-sshd`・`natsumi-sshd` などを告知している（09:13Z の読み取り。告知先は動くので、各台の再起動の前に読み直す）
