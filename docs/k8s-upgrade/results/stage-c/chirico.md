# chirico の段 C の作業記録

chirico（192.168.1.83）の containerd を、Ubuntu の `containerd` 2.2.1 から Docker の `containerd.io` 2.3.6 に置き換えた記録。手順は `../../runbook-stage-c.md`（以下 runbook）。
時刻は UTC。段 C の 1 台目。クラスタ全体のベースラインと戻すための控えは `baseline.md`。

## 1. 事前の読み取り（2026-10-18 06:35Z〜）

### 1.1 クラスタ（runbook §2.3、§3.12）

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。2.3.x のノード: なし、2.2.1 のノード: 8 台 |
| etcd、VIP | 3/3 healthy、リーダー: 192.168.1.112、raft index: 1402195343（3 台同じ）。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached（ベースラインのもの）: `myao/myao`、`homegallery/cg-data` |
| Longhorn の設定 | `concurrent-replica-rebuild-per-node-limit`: `5`、`replica-auto-balance`: `least-effort`、`node-drain-policy`: `block-if-contains-last-replica` |
| controller-manager と scheduler の置き場所 | （worker なので無し） |

### 1.2 対象のノード（runbook §3.3）

| 項目 | 値 |
|---|---|
| Node | Ready、`containerd://2.2.1`、6.8.0-147-generic、uptime 17:27 |
| `containerd --version` / `runc --version` | 2.2.1 / 1.3.4-0ubuntu1~24.04.1 |
| `/etc/containerd/config.toml` | `version = 3`、md5: `665fb78e3b80c49c14575c184b3c5bcf` |
| 控え（`/root/k8u-stage-c/`） | config.toml.before（md5 同じ）、`containerd_2.2.1-0ubuntu1~24.04.3_amd64.deb`、`runc_1.3.4-0ubuntu1~24.04.1_amd64.deb`（sha256 は `baseline.md`） |
| `apt-cache policy containerd containerd.io runc` | `containerd` と `runc` は Ubuntu の版で入っている。`containerd.io` は候補なし（`1.6.8-1 -1`、`/var/lib/dpkg/status` だけ） |
| `dpkg -l containerd.io docker-ce` | `containerd.io` 1.6.8-1 が `rc`。`docker-ce` は無い |
| `/etc/apt/sources.list.d/`、`preferences.d/`、`keyrings/` | `docker.list.disabled-20261017`、`ubuntu.sources` / `ubuntu-pro-esm-apps`、`ubuntu-pro-esm-infra` / `docker.gpg`（runbook のとおり） |
| 当たっていない Ubuntu の更新 | 0 |
| イメージの数（`crictl images -q`） | 317 |
| `systemctl --failed` | 空 |
| Pod と再起動回数（控え） | 57 個、すべて Running |
| 最後の replica を持つボリューム（runbook §2.6） | `monitoring/prometheus-kube-prometheus-db-prometheus-kube-prometheus-1`（pvc-99c35b80、Pod も chirico）。`minio/export-minio-2` は Pod が chirico、replica は oeilvert。コントローラを持たない Pod は無い |

## 2. 入れ替え（runbook §3.4〜§3.7）

### 2.1 リポジトリ、鍵、pin（06:35:56Z〜06:36:00Z）

- 鍵の fingerprint: `9DC858229FC7DD38854AE2D88D81803C0EBFCD88`（一致）
- `docker.sources` の `Architectures` は `amd64`
- `apt-cache policy containerd.io` の Candidate と優先度: `2.3.6-1~ubuntu.24.04~noble`。2.3 系の行（2.3.3-1〜2.3.6-1）が 1001、2.4 系の行は 500
- `gpg --show-keys` が root の `~/.gnupg` を新しく作った（`gpg: directory '/root/.gnupg' created`）。害はない

### 2.2 `containerd.io` を入れる（06:36:11Z〜06:36:22Z）

- `apt-get install -s` の結果（Remv / Inst）: runbook §3.5 の 1 と同じ（`0 upgraded, 1 newly installed, 2 to remove`、Remv `containerd`・`runc`、Inst `containerd.io` 2.3.6）
- 入れた版: `containerd.io=2.3.6-1~ubuntu.24.04~noble`（版を指定した）。rc 0
- conffile の扱い: **`Using current old file as you requested` は出なかった。** dpkg は何も聞かずに手元の config を残した（md5 が控えと同じ）。
  2.3.6 の deb の `/etc/containerd/config.toml`（`disabled_plugins = ["cri"]`）の md5 は `1d862b12f2cb082816175b28ee501789` で、`rc` の 1.6.8 で dpkg に登録されていた md5 と同じだった。パッケージ側の conffile が変わっていないので、dpkg は手元で変えたファイルをそのまま残し、メッセージも出さない
- needrestart が `systemctl restart containerd.service` を流し、`No containers need to be restarted.` と出した

### 2.3 ノードでの確認（runbook §3.6）

| 項目 | 結果 |
|---|---|
| `containerd --version` / `runc --version` | `containerd containerd v2.3.6 ee2735368117d2eb259779949d5e75cdafec9761` / `runc version 1.5.1` |
| config の先頭と md5（控えと同じか） | `version = 3`、`665fb78e3b80c49c14575c184b3c5bcf`（同じ） |
| `containerd config dump`（version、SystemdCgroup、sandbox） | `version = 4`、`SystemdCgroup = true`、`sandbox = 'registry.k8s.io/pause:3.10.1'` |
| journal の error / warning（§8.1 のもの以外） | 無い。`Configuration migrated from version 3` と `failed check for fsverity support` が containerd の起動ごと（06:36:16Z、06:36:19Z）に出た。`unmarshal sandbox spec` は 126 行 |
| `ctr deprecations list` | 空 |
| `crictl info` / イメージの数（入れる前 → 後） | 応答する / 317 → 317 |
| `apt-cache policy containerd.io` | Installed と Candidate が 2.3.6-1、優先度 1001 |

### 2.4 kubelet の再起動（06:36:55Z。runbook §3.7）

- Node と CONTAINER-RUNTIME: Ready、`containerd://2.3.6`（40 秒後に確認）
- Pod の再起動回数（控えとの差）: 57 個とも Running、再起動回数は変わらない（`diff` が同じ）
- kubelet の journal: 起動の直後に `Registration of the crio container factory failed`、`Image garbage collection failed once`、`Failed to trigger a manual run` probe="Readiness" が出た（kubelet の起動のたびに出るもの）。06:37:10Z 以降の E の行は 0
- 監視（runbook §2.4）の FAIL: 無い

## 3. drain（runbook §3.8）

| 時刻（UTC） | 操作 | 結果 |
|---|---|---|
| 06:38:31 | ✋ `infra-admin` のトークンを発行（3h） | 作業端末の 600 のファイルに置いた。`auth can-i patch nodes` が yes |
| 06:38:36 | ✋ `concurrent-replica-rebuild-per-node-limit` を `0`、`replica-auto-balance` を `disabled`、`node-drain-policy` を `allow-if-replica-is-stopped` | 直前の値は `5`、`least-effort`、`block-if-contains-last-replica`。読み直して APPLIED true |
| 06:38:45 | ✋ `monitoring/kube-prometheus` の `spec.replicas` を 2 → 0 | 06:38:51 に pvc-99c35b80 が detached、chirico の replica が stopped。prometheus-0 の pvc-625c8825 も detached |
| 06:39:11 | ✋ `cordon chirico` | |
| 06:39:12〜06:40:22 | ✋ `drain chirico --ignore-daemonsets --delete-emptydir-data --timeout=20m` | rc 0、`node/chirico drained`。`--force` は要らなかった（コントローラを持たない Pod は無い） |

- 止まった Pod: chirico の `instance-manager-4128231c…` が PDB で数回 `Cannot evict pod` になり、ほかの Pod が退いた後に evict された（Longhorn が PDB を外すのを待つ形。前タスクのような時間切れにはならなかった）
- drain の後: chirico でアタッチしているボリュームは 0。attached healthy 7、attached degraded 14（chirico に replica がある 2 replica のもの）、detached 4（myao、cg-data、prometheus の 2 つ）。replica は 45 個で drain の前と同じ数（chirico の 17 は全部 stopped）。ほかのノードに新しい replica は作られていない
- 退いた Pod は他のノードで作り直され、06:41:24 に Running / Completed 以外の Pod が 0 になった（Longhorn のボリュームを使う `deep-researcher-0`、`hedgedoc/db-postgresql-0`、`natsumi-0`、`natsumi-myao-0`、`open-webui-pipelines` がアタッチを待って 1〜2 分かかった）

## 4. 再起動（runbook §3.9）

- 06:41:30 に `systemctl reboot`。journal は 06:41:35 に止まり、kernel の起動は 06:43:23（`uptime -s`）。Node は 06:42:11 に NotReady になり、06:43:49 に Ready（SchedulingDisabled）に戻った。再起動から Ready まで約 2 分 20 秒
- 監視（runbook §2.4）の FAIL（VIP / LB）: 無い

## 5. 再起動の後の確認（runbook §3.10）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready,SchedulingDisabled、v1.29.8、`containerd://2.3.6`。ラベル（`metallb=speaker`、`node-role.kubernetes.io/laga`、`kubevirt.io/schedulable=true` など）が残っている |
| 2 | cnidaria の Pod | `cnidaria-r7jbk` は 06:43:54 に CrashLoopBackOff（restart 4）、06:44:15 に 1/1 Running（restart 5。事前は 3）。`--previous` のログは `dial tcp 10.254.0.1:443: connect: connection refused`（runbook の想定どおり） |
| 3 | `verify-nodes.sh` | 64 PASS、FAIL 0（ベースラインと同じ）。cnidaria のログの error は 0 |
| 4 | DaemonSet の Pod | 8 つとも Running。再起動回数は再起動で 1 ずつ増えた（kube-proxy 2→3、engine-image 2→3、csi-plugin 7→10、longhorn-manager 5→7、node-exporter 2→3、smart-exporter 2→3）。speaker は 15→17（06:43:49 に `10.254.0.1:443` の `connection refused` で 1 回落ちてから戻った） |
| 5 | ストリーミング | `node-exporter` と `cnidaria` のログが読める |
| 6 | iptables | v4・v6 とも FORWARD の policy ACCEPT、`CNIDARIA-FWD` へのジャンプが先頭 |
| 7 | ディスク、ZFS | `/var/lib/longhorn`（`/dev/sda`、1.8T、空き 1.3T）がマウントされている。ZFS は無い |
| 8 | iSCSI | `multipathd` は active。**`iscsid.service` は inactive で、`iscsid.socket` が active（enabled）**。必要なときに socket から起動する形で、前タスクの記録（`docs/worker-os-upgrade/results/chirico.md` §3.5、§5 の 10）と同じ |
| 9 | DNS | `porka-dummy01` に 10.254.0.10、検索ドメイン `default.svc.cluster.local svc.cluster.local cluster.local` |
| 10 | 失敗している unit | 空（ベースラインと同じ） |
| 11 | apt | Candidate `2.3.6-1~ubuntu.24.04~noble`、優先度 1001。`apt-get -s full-upgrade` は `0 upgraded, 0 newly installed, 0 to remove` |
| 12 | `unmarshal sandbox spec` の数 | 60（起動の後） |

ほかに見たもの:

- containerd は v2.3.6、runc 1.5.1、config は `version = 3` で md5 が控えと同じ。`config dump` は `version = 4`、`SystemdCgroup = true`、`pause:3.10.1`。`ctr deprecations list` は空。イメージは 317 のまま。shim のプロセスは 8 つで、すべて起動の後のもの（`/usr/bin/containerd-shim-runc-v2` は `containerd.io` のもの）
- containerd の journal の error（`unmarshal sandbox spec` 以外）: 06:43:48 の 1 秒の間に、`ContainerStatus for "<id>" failed ... NotFound` が 10 行と `RemoveContainer for "<id>" failed ... container is already in removing state` が 2 行。kubelet の起動の直後に、再起動の前に消えたコンテナを問い合わせたもの。**2.2.1 で起動した前回（2026-10-17 13:08Z）の起動でも、同じ種類のものが 9 行と 1 行出ていた**ので、2.3 で新しく出たものではない。以後は出ていない
- kubelet は起動の直後に 1 度 `validate CRI v1 runtime API for endpoint "/run/containerd/containerd.sock"` で落ち、systemd がやり直して上がった（containerd の socket ができる前に起動したもの。前タスクの再起動でも同じ）

## 6. uncordon と後始末（runbook §3.11）

- uncordon の時刻: 06:45:39（cnidaria が Ready になり `verify-nodes.sh` が通った後）
- 戻した workload: 06:45:39 に Prometheus の `spec.replicas` を 0 → 2。06:46:17 に prometheus-0（chirico）と prometheus-1（oeilvert）が 2/2 Running、どちらのボリュームも attached healthy
- Longhorn の node `chirico` が Ready、schedulable であることを確かめてから、06:46:25 に設定を `5`、`least-effort`、`block-if-contains-last-replica` に戻した（APPLIED true）。切り替えから 7 分 49 秒
- 再同期が終わった時刻: 07:02:10（attached healthy 23、detached 2。degraded 0）
- Running / Completed 以外の Pod: 0 個
- `netcheck.sh`: 07:02:53〜07:03:30 に `up` → `run` → `down`。`PASS 168 / 168, pods 8/8`。namespace は消した
- `check-apps.sh`: ベースラインとの差は、hedgedoc の db-postgresql-0 が chirico から duchamp に移ったことだけ（drain による）
- トークンの破棄: 07:03:47 に作業端末のファイルを消した。SA のトークンは個別に失効できないので、サーバーの側では発行から 3 時間（09:38 ごろ）で切れる

### 6.1 Longhorn の replica が Pod に付いて動いた

再同期の後、replica の数はノードごとに chirico 17 → 13、duchamp 10 → 13、oeilvert 18 → 17、pablo 0 → 2 になった（合計 45 は同じ）。ボリュームごとの差:

| ボリューム | 前 | 後 |
|---|---|---|
| `monitoring/prometheus-kube-prometheus-db-prometheus-kube-prometheus-0`（replica 1） | duchamp | **chirico** |
| `monitoring/prometheus-kube-prometheus-db-prometheus-kube-prometheus-1`（replica 1） | chirico | **oeilvert** |
| `fraction-agents/data-wiki-keeper-0` | chirico、oeilvert | chirico、pablo |
| `fraction-agents/data-news-agent-0` | chirico、oeilvert | chirico、pablo |
| `fraction-agents/data-calendar-keeper-0` | chirico、oeilvert | chirico、duchamp |
| `fraction-agents/data-gmail-agent-0` | chirico、duchamp | duchamp、oeilvert |
| `natsumi/natsumi`、`natsumi/natsumi-myao`、`open-webui/open-webui-pipelines` | chirico、oeilvert | duchamp、oeilvert |

- 原因は Longhorn の data locality。`default-data-locality` が `best-effort` で、25 のボリュームのうち 17 が `best-effort`。drain で退いた Pod が別のノードで動き続け、Prometheus の 2 つの Pod は uncordon の後に入れ替わって戻った（prometheus-0 が chirico、prometheus-1 が oeilvert）。設定を戻した後、Longhorn は Pod の居るノードにローカルの replica を作り、ほかの replica を 1 つ消した
- どのボリュームも healthy で、同じボリュームの replica が同じノードに 2 つ載ったものは無い（`replica-soft-anti-affinity` は `false`）
- pablo の 2 つは別々のボリューム（`data-wiki-keeper-0` の pvc-092a74ed と `data-news-agent-0` の pvc-bf2d7ef2）の 1 つずつで、どちらも相方は chirico、アタッチ先は pablo
- このため、runbook §2.6 の「最後の replica を持つボリューム」の表は変わった（07:02Z の読み取り）: **chirico が prometheus-0（Pod も chirico）、oeilvert が prometheus-1（Pod も oeilvert）と MinIO の 4 つ、duchamp は無し**。pablo には replica が 2 つあるが、最後の replica ではない

## 7. 次の 1 台へ進む条件（runbook §3.12）

1 台目なので、Ready に戻ってから約 1 時間おいて、2026-10-18 07:45Z に確かめた。**すべて満たした。**

| 条件 | 結果 |
|---|---|
| 全 8 台の Node が Ready。終えたノードが `containerd://2.3.x`、まだのノードが `containerd://2.2.1` | 8 台 Ready。chirico が `containerd://2.3.6`（v1.29.8）、ほかの 7 台が `containerd://2.2.1` |
| 終えたノードの cnidaria の Pod が Ready で、`verify-nodes.sh` が全 PASS | `cnidaria-r7jbk` 1/1 Running。64 PASS、cnidaria のログの error 0 |
| etcd 3/3 healthy、VIP が応答する | 3/3 healthy、リーダー .112、raft term 23111、index はそろっている。`/readyz` は `ok` |
| Running / Completed 以外の Pod が、ベースラインから増えていない | 0 個 |
| Longhorn のボリュームが healthy。再同期が終わっている | attached healthy 23、detached 2（ベースラインのもの）。同じノードに同じボリュームの replica が 2 つ載ったものは無い |
| Longhorn の 3 つの設定が元の値。`minio/minio` が 4、Prometheus の `spec.replicas` が 2 | `5`、`least-effort`、`block-if-contains-last-replica`。MinIO 4/4、Prometheus 2 |
| `netcheck.sh`、`check-apps.sh` がベースラインと同じ | netcheck 168/168（07:03Z）。`check-apps.sh` は 07:03Z と 07:45Z で同じ（ベースラインとの差は db-postgresql-0 の移動だけ） |
| 終えたノードが 30 分以上、再起動や NotReady なしで動いている | Ready は 06:43:48Z から変わらない（約 62 分）。起動は 06:43:23Z のまま。chirico の Pod の再起動回数は 06:45Z から増えていない |

監視（runbook §2.4）は 06:32Z から 07:46Z まで流し、FAIL は 0（VIP も LB も、入れ替え・kubelet の再起動・drain・再起動の間を通して）。chirico の作業の終わりで止めた。次のノードの作業を始めるときに流し直す。

## 8. 手順書との差、気づいたこと

- §3.5: worker では `Using current old file as you requested` が出ない（2.2 の conffile の説明）。runbook を直した
- §3.10 の 8: 24.04 の chirico では `iscsid.service` は inactive で、`iscsid.socket` が active。runbook の合格基準を直した
- §3.10 の後の containerd の journal に、kubelet の起動の直後の `ContainerStatus ... NotFound` と `RemoveContainer ... already in removing state` が出る（2.2.1 でも出るもの）。runbook §8.1 に足した
- §2.6、§3.11: data locality で replica が Pod に付いて動くことと、次のノードの前に §2.6 の表を読み直すことを、runbook に足した
- drain は 70 秒で終わった（前タスクの chirico は Prometheus を止める前に drain して時間切れになった。今回は runbook のとおり先に止めたので詰まらなかった）
