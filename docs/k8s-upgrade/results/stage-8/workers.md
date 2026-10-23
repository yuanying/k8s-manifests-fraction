# worker 5 台の段 8 の作業記録（8 台に流れた `install kubelet` と oeilvert の `cpu_manager_state`）

worker 5 台（pablo、braque、oeilvert、duchamp、chirico）の kubelet を v1.37.1 にした記録。手順は `../../runbook-stage-8.md`（以下 runbook）の §5。
**runbook どおりの 1 台ずつではなく、1 回の `install kubelet` で 8 台（control-plane の 3 台を含む）に同時に流れた**（§1）。そのとき oeilvert の 1.37 の kubelet が古い `cpu_manager_state` を読めずに起きず、ユーザーの承認を得てファイルを退避して直した（§3）。各台の確認は、runbook §5.3 の項目でまとめて行った（§4）。
時刻は UTC。前は `192.168.1.111.md`。読み取りの出力はタスクディレクトリの `notes/stage-8/<ノード>/`（`*-all.txt`）と `notes/stage-8/incident-allnodes/`。

## 1. 8 台に流れた `install kubelet`（runbook から外れたこと）

- 22:44:00Z に、最初の worker の pablo のつもりで **`porkadot install kubelet --node 192.168.1.134 --config ./porkadot.yaml`** を流した（✋、直前に coordinator に知らせた）。22:44:45Z に rc 0
- **`porkadot.yaml` の worker のキーはノードの名前（`pablo`、`braque`、`oeilvert`、`duchamp`、`chirico`）で、`192.168.1.134` はどのキーにも一致しない。porkadot は一致しない `--node` をはじかず、全ノードに流した**（ログの SSH 先が 8 台）。control-plane はキーが IP（`192.168.1.111`〜`113`）なので、§4 の 3 台は 1 台ずつ流れていた。runbook は「`--node <ノード>`」と書くだけで、何を渡すかを書いていなかった（この PR で §1.4 と §5.2 を直した）
- 結果として、runbook の禁止の「`--node` なしの `install kubelet`」と同じことが起きた。飛ばしたもの: worker を 1 台ずつ流して各台の後に確かめること、pablo の後の `netcheck.sh` と NetworkPolicy の確認（§5.5。§5 で後から流した）、duchamp と chirico の前の runbook §8.12 の Succeeded の Pod の削除（§6）
- 22:45:40Z に 8 台が v1.37.1 で並んでいることに気づいて止め、coordinator に報告した

各台で流れたもの（porkadot のログ。秒）:

| ノード | `install-deps.sh` | `install-pkgs.sh` | `install.sh` | kubelet の再起動 |
|---|---|---|---|---|
| 192.168.1.111〜113 | 0.1（版が同じで落とさない） | 4.9〜5.1 | 2.7〜2.8 | 22:44:11Z（3 台とも。2 回目） |
| pablo | 18.2 | 12.2 | 4.0 | 22:44:38Z |
| braque | 18.7 | 15.9 | 6.6 | 22:44:45Z |
| oeilvert | 9.7 | 9.95 | 2.4 | 22:44:25Z → 起きない（§2） |
| duchamp | 17.5 | 12.4 | 6.5 | 22:44:40Z |
| chirico | 16.9 | 9.3 | 4.4 | 22:44:34Z |

## 2. oeilvert の 1.37 の kubelet が起きなかった

- oeilvert の新しい kubelet は、22:44:25Z から 10 秒おきに起動しては `cpu_manager.go:249] "Could not initialize checkpoint manager, please drain node and remove policy state file" err="could not restore state from checkpoint: checkpoint is corrupted, please drain this node and delete the CPU manager checkpoint file \"/var/lib/kubelet/cpu_manager_state\" before restarting Kubelet"` → `Failed to start ContainerManager` で exit 1 した（22:53Z までに 51 回）
- `/var/lib/kubelet/cpu_manager_state` は **2020-06-22 に書かれたもの**（`{"policyName":"none","defaultCpuSet":"","checksum":3242152201}`、62 バイト）。中身はほかの台（pablo は `{"policyName":"none","defaultCpuSet":"","checksum":1353318690}`）と同じで、checksum だけが違う（古い kubelet の checksum の計算）。1.36 までの kubelet はこれを読めていたが、1.37 の kubelet は v4 → v3 → v2 のどの形でも読めなかった。ほかの 7 台は v2 → v3 → v4 に移せた
- `memory_manager_state` も 2022-04-03 の古いもの（`{"policyName":"None","machineState":{},"checksum":4236770233}`）だったが、1.37 の kubelet は `V2 checkpoint for memory manager is corrupt, falling back to V1` の後に v1 → v2 → v3 へ移せた（ほかの 7 台も同じ `E` の行を 1 回出す）
- その間、oeilvert のコンテナは動き続け、Node は Ready のままだった（22:47Z の読み取り。kubelet が起動のたびに状態を送っていたと見ている）。Pod の退避は起きなかった
- oeilvert の iscsid は、`install-pkgs.sh` の `systemctl start iscsid.service` で 22:44:23Z に起動した（`MainPID=0` → 912599。`journalctl -u iscsid` は `Starting` → `Started` だけで `Stopping` は無い。runbook §2.7 の想定どおりの起動）
- apiserver（.113、.111）に、oeilvert の kubelet が起動のたびに流す `DELETE /apis/resource.k8s.io/v1/resourceslices?fieldSelector=spec.nodeName=oeilvert` の `Timeout or abort while handling`・`Handler timeout` が 22:46〜22:47Z に数行出た

## 3. 直し（ユーザーの判断 (a)、runbook から外れた操作）

- coordinator に、(a) `cpu_manager_state` を退避して kubelet に作り直させる、(b) 0.36.0 で oeilvert を 1.36.5 に戻す、(c) 何もしない、を示し、(a) を勧めた。ユーザーが (a) を承認した（22:48Z。承認は、この 1 ファイルの退避と kubelet の restart まで）
- 22:53:19Z に `sudo mv -n /var/lib/kubelet/cpu_manager_state /var/lib/kubelet/cpu_manager_state.bak-k8u8`（消していない。ノードに残っている）。kubelet は systemd の自動再起動で 22:53:21Z に起き（手での restart は要らなかった）、新しい `cpu_manager_state` を v4 の形（`{"policyName":"none","defaultCpuSet":"","checksum":1353318690,"data":"{\"policyName\":\"none\",\"defaultCpuSet\":\"\"}","dataChecksum":3028111495}`）で書いた
- oeilvert は Ready、v1.37.1。**Pod の差分はクラスタ全体で 0**（直す前の 22:53Z と直した後の 22:54Z、pablo の前の 22:43:39Z の控えのどれとも同じ。`homegallery/api` と DaemonSet の Pod も作り直されていない）。Running / Completed 以外の Pod は 0

## 4. 確認（runbook §5.3。22:54Z〜22:56Z。比べる元は `baseline.md` の 22:09Z の `tools/node-state.sh` と 22:43:39Z の Pod の控え）

| # | 確認 | pablo | braque | oeilvert | duchamp | chirico |
|---|---|---|---|---|---|---|
| 1 | Node | Ready、v1.37.1 | Ready、v1.37.1 | Ready、v1.37.1（22:53:21Z から） | Ready、v1.37.1 | Ready、v1.37.1 |
| 2 | バイナリ、CNI | `kubelet-v1.37.1`、`kubectl-v1.37.1`、`crictl-v1.37.0`、`etcdctl-3.7.3`、`etcdutl-3.7.3`、CNI は `v1.9.1` のまま（5 台とも） | 同左 | 同左 | 同左 | 同左 |
| 3 | iscsid | 4114921 のまま | 271131 のまま | 0 → 912599（22:44:23Z の起動。§2） | 2695716 のまま | 3144486 のまま |
| 4 | iSCSI のセッション | 0 | 0 | 0 | 5（同じ sid・portal 10.244.5.186・target） | 11（同じ sid・portal 10.244.8.216 / 10.244.8.60・target） |
| 5 | エンジン | — | — | — | 同じ 5 本、同じ起動の時刻、`older-than-iscsid` 4 | 同じ 11 本、同じ起動の時刻、`older-than-iscsid` 9 |
| 6 | Longhorn | attached healthy 16（chirico 11、duchamp 5）、detached 1。instance-manager 5 つとも同じ名前・IP で running。Longhorn の node 4 つとも Ready・schedulable。replica はベースラインと同じ数 |
| 7 | Pod の再起動 | **無い**（クラスタ全体で、22:43:39Z の控えと名前・UID・restartCount が同じ） |
| 20 | `containerRuntimeEndpoint` | 5 台とも `kubelet.service` にフラグなし、`config.yaml` に `containerRuntimeEndpoint: unix:///run/containerd/containerd.sock`、`crictl version` は containerd v2.3.6、新しい kubelet の起動の後の deprecated の warning 0、`Effective KubeletConfiguration` に `containerRuntimeEndpoint` |
| 10 | cnidaria（error / `no route`） | 20/68 → 27/112 | 27/76 → 35/118 | 0/0 → 8/44 | 28/77 → 35/116 | 23/73 → 24/111 |
| 11 | kubelet のログ | 起動の直後の `node not found`、`Skipping pod synchronization`、memory manager の checkpoint、`eviction manager`。止まる前の古い kubelet の `Missing actuated resource record` 9 行 | braque: 同じ形。**cAdvisor・ZFS の error は無い**（runbook §2.12） | §2 | pablo と同じ形 | pablo と同じ形と、古い kubelet の `Unable to write event`（`systemd-networkd` の再起動）1 行 |
| 14 | 告知していた LoadBalancer | VIP（`/version` 200）、gated-v6（404） | — | `::133`（SSH のバナー） | `::132`・`::134`（SSH のバナー） | gated-v4（404） |
| 15 | CSR | 無い |

- control-plane の 3 台にも 2 回目の `install kubelet` が流れた（版は同じ。kubelet が 22:44:11Z に再起動）。etcd の mirror Pod の UID と restartCount は変わらず（22:43:39Z の控えと同じ）、etcd は 3/3 healthy、3.7.3・3.7.0 のまま。`node-state.sh` の差はベースラインから `bin` の行だけ、iscsid の PID も同じ
- cnidaria の `no route` は、8 台の `systemd-networkd` が一度に再起動したので、各台のログに 8 台ぶんが出て段 7（0〜8 件）より多い。どれも `warning: no route for a family: node … has the IPv6 pod CIDR … but no IPv6 InternalIP or annotated address` の info の行で、22:59Z の時点で直近 10 分は 8 台とも 0（runbook §8.1）
- chirico の新しい kubelet は、`monitoring/alertmanager-kube-prometheus-1` の `config-reloader` と `fraction-agents/news-agent-0` の `host` について `kuberuntime_manager.go:748] "Missing actuated resource record"` を 1 分に 1〜2 行出し続けている（止まる前の 1.36 の kubelet も同じ行を出していた）。コンテナの再起動は無い。記録だけ（§7）
- braque の nfsd（`nfsd/nfsd-vt5k2`）は restartCount 2 のまま。oeilvert の NFS のマウントは中身が読め、braque は 2049 を listen している。`registry.fraction.jp/v2/` は 401
- oeilvert のノードの IPv6 は `2405:6580:6740:ac01::183` のまま（cnidaria の注釈）
- leader election を使う controller の restartCount はベースラインと同じ

## 5. cnidaria と NetworkPolicy（runbook §5.5。✋、直前に coordinator に知らせた）

- `netcheck.sh`（22:56:10Z〜22:56:30Z）: `up` → `run` が **`PASS 168 / 168, pods 8/8`** → `down`。名前空間 `cnidaria-netcheck` は NotFound
- NetworkPolicy の確認（runbook §1.9。22:56:36Z に `infra-admin` の 1 時間のトークンを `/tmp/k8u-stage8-admin-token` に発行）: `up` の前の `nft` は 8 台とも 0、`up` の後は 8 台とも 9、`run` は **`OK 56, not OK 0`**、`down` の後は 8 台とも 0、`k8u-npcheck` は NotFound（22:59:13Z）
- runbook §3.3 の 13 の任意の確かめ（Service を作ってすぐ引ける）は流していない

## 6. runbook §8.12 の Succeeded の Pod

- duchamp の natsumi の 9 つと chirico の `deep-researcher-backup` の 3 つ（`baseline.md` §2 の 22）は、`install kubelet` の前に消す予定だったが、§1 で消す前に kubelet が上がった。kubelet はそのまま上がり、Running の natsumi・deep-researcher の Pod は再起動せず、`FailedMount` の event も出ていない
- **消していない**（coordinator の指示。kubelet の更新が済んだので、消す理由が無くなった）

## 7. 手順書との差、気づいたこと

- §1: `--node` には `porkadot.yaml` の `nodes` のキーを渡す（control-plane は IP、worker は名前）。一致しない値を渡すと全ノードに流れる。runbook §1.4・§5.2 に書いた。porkadot の側で、一致しない `--node` をはじくようにするのがよい（申し送り）
- §2・§3: 1.37 の kubelet は、古い kubelet の checksum の `cpu_manager_state` を読めずに起きない。`install kubelet` の前に各台の `cpu_manager_state` を読み、ほかの台と同じ形（`{"policyName":"none","defaultCpuSet":"","checksum":1353318690}`）でなければ止める確かめを runbook §2.2・§8.23 に足した。dev の VM は新しく、この形のファイルを持っていない
- chirico の `Missing actuated resource record` は、段 8 の後に 1 日ほど様子を見るときに続いているかを見る
