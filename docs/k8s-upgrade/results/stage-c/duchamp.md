# duchamp の段 C の作業記録

duchamp（192.168.1.135）の containerd を、Ubuntu の `containerd` 2.2.1 から Docker の `containerd.io` 2.3.6 に置き換えた記録。手順は `../../runbook-stage-c.md`（以下 runbook）。
時刻は UTC。段 C の 2 台目。1 台目は `chirico.md`、クラスタ全体のベースラインと戻すための控えは `baseline.md`。

## 1. 事前の読み取り（2026-10-18 07:50Z〜）

### 1.1 クラスタ（runbook §2.3、§3.12）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。2.3.x のノード: chirico（`containerd://2.3.6`）、2.2.1 のノード: ほかの 7 台 |
| etcd、VIP | 3/3 healthy、リーダー: 192.168.1.112、raft term 23111、raft index: 1402224058〜059（そろっている）。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached（ベースラインのもの）: `myao/myao`、`homegallery/cg-data` |
| Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit`: `5`、`replica-auto-balance`: `least-effort`、`node-drain-policy`: `block-if-contains-last-replica`（`replica-replenishment-wait-interval` は `6000`、`default-data-locality` は `best-effort`） |
| controller-manager と scheduler の置き場所 | （worker なので無し） |
| `auth can-i delete pods -A`（`fraction-auditor`） | `no` |
| `containerd.io` の版（runbook §1.6） | 2.3 系の最新は 2.3.6-1 のまま（1 台目と同じ版を入れる） |

### 1.2 対象のノード（runbook §3.3）

| 項目 | 値 |
|---|---|
| Node | Ready、`containerd://2.2.1`、6.8.0-147-generic、起動 2026-10-17 15:33:46Z |
| `containerd --version` / `runc --version` | 2.2.1 / 1.3.4-0ubuntu1~24.04.1 |
| `/etc/containerd/config.toml` | `version = 3`、md5: `665fb78e3b80c49c14575c184b3c5bcf` |
| 控え（`/root/k8u-stage-c/`） | config.toml.before（md5 同じ）、`containerd_2.2.1-0ubuntu1~24.04.3_amd64.deb`、`runc_1.3.4-0ubuntu1~24.04.1_amd64.deb`（sha256 は `baseline.md` と同じ） |
| `apt-cache policy containerd containerd.io runc` | `containerd` と `runc` は Ubuntu の版で入っている。`containerd.io` は候補なし（`1.6.8-1 -1`、`/var/lib/dpkg/status` だけ） |
| `dpkg -l containerd.io docker-ce` | `containerd.io` 1.6.8-1 が `rc`。`docker-ce` は無い |
| `/etc/apt/sources.list.d/`、`preferences.d/`、`keyrings/` | `docker.list.disabled-20261017`、`ubuntu.sources` / `ubuntu-pro-esm-apps`、`ubuntu-pro-esm-infra` / `docker.gpg`（runbook のとおり） |
| 当たっていない Ubuntu の更新 | 0 |
| イメージの数（`crictl images -q`） | 239 |
| `systemctl --failed` | 空 |
| Pod と再起動回数（控え） | 42 個、すべて Running。コントローラを持たない Pod は無い |
| ターボ（冷却ファンの故障による運用。Wiki の duchamp の節） | `/sys/devices/system/cpu/intel_pstate/no_turbo` が `1`。Package 62℃。止める設定を永続化するもの（unit、tmpfiles、cron）は無い |
| 最後の replica を持つボリューム（runbook §2.6） | **無い**。replica 1 のボリュームの置き場所は、prometheus-0 が chirico、prometheus-1 と MinIO の 4 つが oeilvert（chirico の後に data locality で動いたまま）。duchamp の replica は 13 個（どれも 2 replica のボリュームの片方、または以前から stopped のもの）。`minio-1` の Pod は duchamp で動いているが、replica は oeilvert にある |

最後の replica が無いので、duchamp の drain では `node-drain-policy` を変えず、Prometheus も止めない（runbook §2.6 の表の pablo・braque と同じ扱い）。`concurrent-replica-rebuild-per-node-limit` と `replica-auto-balance` だけを切り替える。

## 2. 入れ替え（runbook §3.4〜§3.7）

### 2.1 リポジトリ、鍵、pin（07:51:38Z〜07:51:52Z）

- 鍵の fingerprint: `9DC858229FC7DD38854AE2D88D81803C0EBFCD88`（一致）
- `docker.sources` の `Architectures` は `amd64`
- `apt-cache policy containerd.io` の Candidate と優先度: `2.3.6-1~ubuntu.24.04~noble`。2.3 系の行（2.3.3-1〜2.3.6-1）が 1001、2.4 系の行は 500

### 2.2 `containerd.io` を入れる（07:52:09Z〜07:52:23Z）

- `apt-get install -s` の結果（Remv / Inst）: runbook §3.5 の 1 と同じ（`0 upgraded, 1 newly installed, 2 to remove`、Remv `containerd`・`runc`、Inst `containerd.io` 2.3.6）
- 入れた版: `containerd.io=2.3.6-1~ubuntu.24.04~noble`（版を指定した）。rc 0
- conffile の扱い: chirico と同じく `Using current old file as you requested` は出ず、手元の config が残った（md5 が控えと同じ）
- needrestart が `systemctl restart containerd.service` を流し、`No containers need to be restarted.` と出した

### 2.3 ノードでの確認（runbook §3.6）

| 項目 | 結果 |
|---|---|
| `containerd --version` / `runc --version` | `containerd containerd v2.3.6 ee2735368117d2eb259779949d5e75cdafec9761` / `runc version 1.5.1` |
| config の先頭と md5（控えと同じか） | `version = 3`、`665fb78e3b80c49c14575c184b3c5bcf`（同じ） |
| `containerd config dump`（version、SystemdCgroup、sandbox） | `version = 4`、`SystemdCgroup = true`、`sandbox = 'registry.k8s.io/pause:3.10.1'` |
| journal の error / warning（§8.1 のもの以外） | 無い。`Configuration migrated from version 3` と `failed check for fsverity support` が containerd の起動ごと（07:52:17Z、07:52:21Z）に出た。`unmarshal sandbox spec` は 96 行 |
| `ctr deprecations list` | 空 |
| `crictl info` / イメージの数（入れる前 → 後） | 応答する / 239 → 239 |
| `apt-cache policy containerd.io` | Installed と Candidate が 2.3.6-1、優先度 1001 |

### 2.4 kubelet の再起動（07:52:37Z。runbook §3.7）

- Node と CONTAINER-RUNTIME: Ready、`containerd://2.3.6`（40 秒後に確認）
- Pod の再起動回数（控えとの差）: 42 個とも Running、再起動回数は変わらない（`diff` が同じ）
- kubelet の journal: 再起動の前の kubelet が、containerd の再起動の間（07:52:17〜22Z）に `containerd.sock: connect: no such file or directory` と `server is not initialized yet` を出した（dpkg と needrestart が containerd を再起動した間のもの）。再起動の後の kubelet は、起動の直後に `Registration of the crio container factory failed` と `Image garbage collection failed once` を出しただけで、07:52:40Z 以降の E の行は 0
- 監視（runbook §2.4）の FAIL: 無い

## 3. drain（runbook §3.8）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 07:54:21 | ✋ `infra-admin` のトークンを発行（3h） | 作業端末の 600 のファイルに置いた。`auth can-i patch nodes` が yes |
| 07:54:26 | ✋ `concurrent-replica-rebuild-per-node-limit` を `0`、`replica-auto-balance` を `disabled` | 直前の値は `5`、`least-effort`。読み直して APPLIED true。**`node-drain-policy` は変えず、Prometheus も止めなかった**（§1.2 のとおり最後の replica が無い） |
| 07:54:35 | ✋ `cordon duchamp` | |
| 07:54:35〜07:56:38 | ✋ `drain duchamp --ignore-daemonsets --delete-emptydir-data --timeout=20m` | rc 0、`node/duchamp drained`。`--force` は要らなかった（コントローラを持たない Pod は無い） |

- 止まった Pod: duchamp の `instance-manager-4df00b8c…` が PDB で 7 回 `Cannot evict pod` になり、ほかの Pod が退いた後に evict された（chirico と同じ形）
- drain の後: duchamp でアタッチしているボリュームは 0。attached healthy 13、attached degraded 10、detached 2（ベースラインのもの）。duchamp の replica 13 個は全部 stopped。Running / Completed 以外の Pod は 0
- 退いた Pod は 34 個（hedgedoc の `db-postgresql-0`、`fraction-agents` の `deep-researcher-0`・`calendar-keeper-0`、`gated`、`coredns`、Longhorn の CSI の Deployment など）

### 3.1 kubelet の再起動で replica が 2 つ動いた（想定外）

drain の後の replica の置き場所を §1.2 の読み取りと比べたところ、drain の前（Longhorn の設定を切り替える前）に、2 つのボリュームの replica が pablo に作られていた。

- 原因: §2.4 の kubelet の再起動（07:52:37Z）で Node に `NodeNotReady` のイベントが出て、Longhorn の node `duchamp` も 07:52:45Z まで Ready でなくなった。その間に、まだ `least-effort` だった `replica-auto-balance` が動いた（longhorn-manager のログ 07:52:45Z: `Node duchamp is not ready or schedulable, replica ... could get evicted`、`Found 1 node available for auto-balance duplicates`、`Schedule replica to node pablo`）
- `fraction-agents/data-deep-researcher-0`（pvc-9aae4b86、2 replica、アタッチ先 chirico）: pablo に新しい replica を作って 07:53:15Z に再構築を終え、chirico の replica を消した。drain で duchamp の replica が止まった後は、pablo の 1 つだけが running の degraded だった
- `homegallery/ero-data`（pvc-baa41130、2 replica、data locality `disabled`、アタッチ先 oeilvert）: pablo に 3 つ目の replica を作って 07:55:31Z に再構築を終えた。drain の後は oeilvert と pablo の 2 つが RW で healthy、duchamp の replica は 07:55:10Z に failed
- attached のボリュームはどれも running の replica が 1 つ以上あり、データは失っていない。chirico では起きなかった
- ユーザーの判断で、このまま再起動に進んだ。runbook は、Longhorn の 2 つの設定を kubelet の再起動の前に切り替える順序に直した（§8）

## 4. 再起動（runbook §3.9）

- 再起動の前: Package 66℃、`no_turbo` は `1`（07:57:57Z）
- 07:59:25 に `systemctl reboot`。kernel の起動は 08:01:17（`uptime -s`）。SSH が戻った 08:01:41 に `echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo` でターボを止め直した（`cat` で `1`。2026-10-18 のユーザー承認）。Node は 08:01:45 に Ready（SchedulingDisabled）に戻った。再起動から Ready まで約 2 分 20 秒（前タスクの約 17 分のような遅れは無かった）
- 温度: 08:02:36Z に 63〜65℃、08:29Z に 54〜60℃（ターボ停止で安定）
- 監視（runbook §2.4）の FAIL（VIP / LB）: 無い

## 5. 再起動の後の確認（runbook §3.10）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready,SchedulingDisabled、v1.29.8、`containerd://2.3.6`。ラベル（`metallb=speaker`、`node-role.kubernetes.io/assassin` など）が残っている |
| 2 | cnidaria の Pod | `cnidaria-2jx6x` は 08:01:50 に Error（restart 6）、08:02:00 に CrashLoopBackOff、08:02:10 に 1/1 Running（restart 7。事前は 5）。`--previous` のログは `dial tcp 10.254.0.1:443: connect: connection refused`（runbook の想定どおり） |
| 3 | `verify-nodes.sh` | 64 PASS、FAIL 0（ベースラインと同じ）。cnidaria のログの error は 0 |
| 4 | DaemonSet の Pod | 8 つとも Running。再起動回数は kube-proxy 3→4、engine-image 3→4、csi-plugin 11→14、longhorn-manager 6→8、node-exporter 3→4、smart-exporter 3→4。speaker は 13→15（08:01:47 に `10.254.0.1:443` の `connection refused` で落ちてから戻った） |
| 5 | ストリーミング | `cnidaria` のログが読める |
| 6 | iptables | v4・v6 とも FORWARD の policy ACCEPT、`CNIDARIA-FWD` へのジャンプが先頭 |
| 7 | ディスク、ZFS | `/var/lib/longhorn`（`/dev/sdb`、1.8T、空き 1.6T）がマウントされている。ZFS は無い |
| 8 | iSCSI | `iscsid.socket` と `multipathd` が active、`iscsid.service` は inactive（chirico と同じ） |
| 9 | DNS | `porka-dummy01` に 10.254.0.10、検索ドメイン `default.svc.cluster.local svc.cluster.local cluster.local` |
| 10 | 失敗している unit | 空（ベースラインと同じ） |
| 11 | apt | Candidate `2.3.6-1~ubuntu.24.04~noble`、優先度 1001。`apt-get -s full-upgrade` は `0 upgraded, 0 newly installed, 0 to remove` |
| 12 | `unmarshal sandbox spec` の数 | 54（起動の後） |

ほかに見たもの: containerd は v2.3.6、runc 1.5.1、config は `version = 3` で md5 が控えと同じ。`config dump` は `version = 4`、`SystemdCgroup = true`、`pause:3.10.1`。`ctr deprecations list` は空。イメージは 239 のまま。shim のプロセスは 8 つ。起動の後の containerd の journal は、`unmarshal sandbox spec` のほかに error は無く、warning は `Configuration migrated from version 3` と `failed check for fsverity support` の 1 行ずつ。

## 6. uncordon と後始末（runbook §3.11）

- uncordon の時刻: 08:02:51（cnidaria が Ready になり `verify-nodes.sh` が通った後）
- 戻した workload: なし（止めていない）
- Longhorn の node `duchamp` が Ready、schedulable であることを確かめてから、08:03:12 に設定を `5`、`least-effort` に戻した（APPLIED true。`node-drain-policy` は `block-if-contains-last-replica` のまま）。切り替えから 8 分 46 秒
- 再同期が終わった時刻: 08:15:37（attached healthy 23、detached 2。degraded 0）。設定を戻してから 12 分
- Running / Completed 以外の Pod: 0 個
- `netcheck.sh`: 08:28:50〜08:29:06 に `up` → `run` → `down`。`PASS 168 / 168, pods 8/8`。namespace は消した
- `check-apps.sh`: chirico の後（07:45Z）との差は、hedgedoc の db-postgresql-0 が duchamp から chirico に移ったことだけ（drain による）
- トークンの破棄: 08:32:43 に作業端末のファイルを消した。SA のトークンは個別に失効できないので、サーバーの側では発行から 3 時間（10:54 ごろ）で切れる

### 6.1 §3.1 の 2 つのボリュームの戻り

| 時刻（UTC） | data-deep-researcher-0（pvc-9aae4b86） | ero-data（pvc-baa41130） |
|---|---|---|
| 08:03:12（設定を戻した直前） | pablo running、duchamp stopped。degraded | oeilvert・pablo running、duchamp stopped（failed）。healthy |
| 08:03:23〜08:03:44 | **duchamp の stopped の replica が再利用され**、再構築して running に（`replica-replenishment-wait-interval` の 100 分の内）。healthy | 変わらない |
| 08:03:56〜08:04:29 | data locality（`best-effort`、アタッチ先 chirico）で chirico に新しい replica を作って再構築し、pablo の replica を消した | 変わらない |
| 08:15:37 以降 | **chirico・duchamp の 2 つで healthy**（numberOfReplicas 2 どおり） | **oeilvert・pablo の 2 つが running で healthy**（numberOfReplicas 2 どおり）。duchamp の replica は failed（failedAt 07:55:10Z）のまま残っている |

- ero-data の duchamp の replica は、running の replica が既に 2 つあるので再利用されない。Longhorn は failed の replica を `staleReplicaTimeout`（このボリュームは 2880 分）を過ぎてから消すので、2026-10-20 07:55Z ごろに自動で消える見込み。natsumi-aki（pvc-e224cffa）にも、2026-10-17 01:21Z から duchamp に同じ状態の replica が残っている（ベースラインのとき既にあった）。手で消すのは runbook の外なので消していない
- 同じボリュームの replica が同じノードに 2 つ載ったものは無い

### 6.2 Longhorn の replica の置き場所

再同期の後、replica の数はノードごとに chirico 13 → 16、duchamp 13 → 10、oeilvert 17 → 17、pablo 2 → 3。§1.2 の読み取りとの差は、6.1 の 2 つと、`natsumi/natsumi`、`natsumi/natsumi-myao`、`open-webui/open-webui-pipelines` の replica が duchamp から chirico に移ったこと（drain で Pod が chirico に移り、data locality で付いて動いた）。replica 1 のボリュームの置き場所は変わらない（prometheus-0 が chirico、prometheus-1 と MinIO の 4 つが oeilvert）。

## 7. 次の 1 台へ進む条件（runbook §3.12）

2 台目なので、runbook の既定の 30 分をおいて、2026-10-18 08:32Z に確かめた。**すべて満たした。**

| 条件 | 結果 |
|---|---|
| 全 8 台の Node が Ready。終えたノードが `containerd://2.3.x`、まだのノードが `containerd://2.2.1` | 8 台 Ready。chirico と duchamp が `containerd://2.3.6`（v1.29.8）、ほかの 6 台が `containerd://2.2.1` |
| 終えたノードの cnidaria の Pod が Ready で、`verify-nodes.sh` が全 PASS | `cnidaria-2jx6x` 1/1 Running（restart 7 のまま）。64 PASS、cnidaria のログの error 0 |
| etcd 3/3 healthy、VIP が応答する | 3/3 healthy、リーダー .112、raft term 23111、index 1402239698 でそろっている。`/readyz` は `ok` |
| Running / Completed 以外の Pod が、ベースラインから増えていない | 0 個 |
| Longhorn のボリュームが healthy。再同期が終わっている | attached healthy 23、detached 2（ベースラインのもの）。§3.1 の 2 つも numberOfReplicas どおりの running で healthy（§6.1） |
| Longhorn の 3 つの設定が元の値。`minio/minio` が 4、Prometheus の `spec.replicas` が 2 | `5`、`least-effort`、`block-if-contains-last-replica`。MinIO 4/4、Prometheus 2 |
| `netcheck.sh`、`check-apps.sh` がベースラインと同じ | netcheck 168/168（08:29Z）。`check-apps.sh` の差は db-postgresql-0 の移動だけ |
| 終えたノードが 30 分以上、再起動や NotReady なしで動いている | Ready は 08:01:45Z から変わらない（約 31 分）。起動は 08:01:17Z のまま。duchamp の DaemonSet の Pod の再起動回数は 08:02Z から増えていない。`no_turbo` は `1` のまま |

監視（runbook §2.4）は 07:51:14Z から 08:32:43Z まで流し、FAIL は 0（VIP も LB も、入れ替え・kubelet の再起動・drain・再起動の間を通して）。duchamp の作業の終わりで止めた。

## 8. 手順書との差、気づいたこと

- §2.6: chirico の後の読み直しで、duchamp には最後の replica が無かった。`node-drain-policy` を変えず、Prometheus も止めずに drain できた。runbook §3.8 の「chirico、duchamp だけ」を、読み直した表で決める形に直した
- §3.7: kubelet の再起動で Longhorn の auto-balance が replica を動かした（§3.1）。runbook を、Longhorn の `concurrent-replica-rebuild-per-node-limit` と `replica-auto-balance` を kubelet の再起動の前に切り替える順序に直した（§2.2、§2.6、§3.7、§3.8、§3.11、§4.2 の 5）
- §3.9: duchamp の再起動の後にターボを止め直すことを、runbook に足した
- 再起動から Ready まで約 2 分 20 秒。前タスクの duchamp の約 17 分より短かった（ターボ停止で温度が低いまま再起動したためと見られる）
- ero-data の duchamp の failed の replica は、`staleReplicaTimeout` で 2026-10-20 ごろに Longhorn が消す見込み（§6.1）。次のノードの §3.3 の Longhorn の読み取りで、running 以外の replica として出る
