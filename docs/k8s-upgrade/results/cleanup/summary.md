# 片付けの記録（本番 `fraction`、単位 A・B）

一覧 `../../cleanup.md`（以下 一覧）の §12 の単位 A（本番の Kubernetes のリソース）と単位 B（ノード）を、一覧のとおりに行った記録。ユーザーの承認と判断は 2026-10-27（単位 A・B を一覧のとおり、`ml-study` も消す、`kagent` は残す、cilium の Secret は控えずに消す、sealed-secrets の鍵は消してよい、`000-namespaces/` を消す）。

- 控え（Secret を除く yaml）: タスクディレクトリの `notes/cleanup/`（一覧 §11.1）。Secret は控えていない
- 書き込みは `infra-admin` の 1 時間のトークン（`/tmp/k8u-cleanup-admin-token`、0600。作業の後に消した）

## 1. 単位 A

### 1.1 消す前の確かめ（2026-10-27 12:07〜12:09Z）

| 項目 | 一覧 | 結果 |
|---|---|---|
| `istio-system`・`metallb` の中身 | 0 | 0 |
| `ml-study` の中身 | SA・Role・RoleBinding `developer` の 3 つ | 同じ 3 つ |
| `kagent` | 中身 0、残す | 中身 0（残した） |
| `crawl4ai`・`minio-system`・`homegallery` | 無い | 無い |
| NFD の CRD 3 つの件数 | 0、conversion なし | 0、`None`、`v1alpha1` だけ |
| rook の CSIDriver を使う PV・VolumeAttachment・StorageClass | 0 | 0 |
| ClusterRoleBinding 33 個の subjects の SA | 無い（`pod-checkpointer` は SA があり、一緒に消す） | 同じ（`kube-system/pod-checkpointer` だけある） |
| ClusterRole 33 個がほかから参照されるか | されない | されない（ほかの ClusterRoleBinding・RoleBinding から 0） |
| kube-system の名残 10 個 | ある。`tiller-deploy` の endpoint 0 | ある。endpoint 0。どの Pod もその SA を使わない |
| PriorityClass `kubevirt-cluster-critical` を使う Pod | 0 | 0 |
| ノードの kubevirt のラベルと注釈 | `kubevirt.io/schedulable`（chirico・oeilvert）、`cpumanager`・`kubevirt.io/heartbeat`（chirico・duchamp・oeilvert） | 同じ |
| cilium の Secret 3 つ | ある | ある |
| **sealed-secrets の鍵** | **23 個（2023-03-26〜2024-12-15）** | **39 個（2023-03-26〜2026-05-10）**。下の 1.3 |

消す前の Pod: 161 個（Running 137、Succeeded 24）。Longhorn のボリューム 14 個、すべて attached・healthy。

### 1.2 消したもの（12:09:42〜12:10:03Z）

| 対象 | 件数 |
|---|---|
| 名前空間 `istio-system`・`metallb`・`ml-study`（`ml-study` の SA・Role・RoleBinding `developer` を含む） | 3 |
| CRD `nodefeatures`・`nodefeaturerules`・`nodefeaturegroups`（`nfd.k8s-sigs.io`） | 3 |
| CSIDriver `rook-ceph.rbd.csi.ceph.com`・`rook-ceph.cephfs.csi.ceph.com` | 2 |
| ClusterRoleBinding（一覧 §5.3 の `$CRB`） | 33 |
| ClusterRole（一覧 §5.3 の `$CR`） | 33 |
| kube-system の SA・ConfigMap・Role・RoleBinding `pod-checkpointer`、Service `tiller-deploy`、ConfigMap `core-dns`・`kube-keepalived`・`kube-flannel-cni-sh`、Job `update-storage-objects`、SA `storage-objects-updater` | 10 |
| PriorityClass `kubevirt-cluster-critical` | 1 |
| ノードのラベル `kubevirt.io/schedulable`（chirico・oeilvert）・`cpumanager`（3 台）、注釈 `kubevirt.io/heartbeat`（3 台） | 8 |
| kube-system の Secret `cilium-ca`・`cilium-cli-helm-values`・`hubble-server-certs`（控えなし） | 3 |

### 1.3 sealed-secrets の鍵

一覧は 23 個・最後が 2024-12-15 としていたが、実際は 39 個あった。2025-01〜2026-05 にも毎月 1 個ずつ増えていて、いちばん新しいのは `2026-05-10T06:01:04Z`（managedFields の manager は `controller`）。2026-01 からは作られた時刻が 12:10Z から 06:01Z に変わっている。つまり sealed-secrets のコントローラは 2026-05 まで動いていた（今は Pod・Deployment・CRD・APIService のどれも無い）。一覧と違うのでいったん止めて coordinator に報告した。

ユーザーが 39 個とも消してよいと承認した（2026-10-27、控えなし）。消す直前に、件数が 39（ラベル `sealedsecrets.bitnami.com/sealed-secrets-key` でも名前でも、全名前空間でも 39）であること、CRD・APIService・api-resources に sealed-secrets が無いこと（したがって SealedSecret も無い）、`sealed` を含む Pod・Deployment・StatefulSet・DaemonSet・ReplicaSet・Job・CronJob・Service が無いことを確かめた。**2026-10-27 12:21:07〜12:21:18Z に 39 個を消した。** 残り 0、Pod は変化なし

### 1.4 消した後の確かめ

- 名前空間 3 つが NotFound。Terminating の名前空間は無い
- `nfd` の CRD 0（CRD は 66 → 63）。CSIDriver は `driver.longhorn.io` だけ
- 一覧の ClusterRoleBinding・ClusterRole は 66 個とも NotFound。PriorityClass は `longhorn-critical`・`system-*` の 3 つ
- ノードに kubevirt の名前の付いたラベル・注釈と `cpumanager` が残っていない
- Pod は消す前と同じ 161 個で、phase と restart の回数がすべて同じ。Running / Succeeded 以外の Pod は 0
- subjects のいない binding を出し直すと、一覧 §5.1 の既定の RBAC 5 つのほかに 2 つ出た（下の 1.5）

### 1.5 一覧に無かったもの（消していない）

- **ClusterRoleBinding `remora:pod-checkpointer`（2017-10-10）・`update-storage-objects`（2018-10-19）。** どちらも `cluster-admin` を kube-system の SA `pod-checkpointer`・`storage-objects-updater` に結び付けている。一覧は SA が残っていたのでこの 2 つを検出していなかった。今回 SA を消したので subjects のいない binding になった。一覧に無かったのでいったん残して報告した（同じ名前の SA を作り直すとその SA が `cluster-admin` になる）。**ユーザーの承認（2026-10-27）を得て、13:11:08Z に 2 つとも消した。** 消す直前に subjects の SA 2 つが NotFound であることを確かめ、控えを `notes/cleanup/clusterrolebindings-orphaned.yaml` に取った。消した後、subjects のいない binding を出し直すと、一覧 §5.1 の既定の RBAC の 5 つだけになった。Pod・ノード・Longhorn に変化は無い
- **ClusterRoleBinding `tiller-cluster-rule`（2017-10-10）** は `cluster-admin` を `kube-system/default` に与えている。kube-apiserver の DaemonSet の Pod（3 つ）がこの SA で動いている。Tiller の名残だが、使っている Pod があるので片付けの範囲の外。報告に書いた

## 2. 単位 B（ノード）

### 2.1 やり方

1 台ずつ、一覧 §7.3 の順（rasp01 → rasp02 → rasp03 → braque → pablo → duchamp → oeilvert → chirico）。使った道具は `tools/`。

1. `collect.sh` でノードの `crictl images`・`crictl ps -a`・`crictl pods`・`ctr -n k8s.io containers ls` のイメージ・containerd の `sandbox`・`df`・`ls -la /opt/bin` とリンクを取る
2. `plan.py` が `../cleanup-survey/images-plan.tsv` と突き合わせ、**イメージのすべてのタグがそのノードで「消す」（タグの無いものは `<none>` の「消す」）で、どのコンテナ（終わったものと sandbox を含む）も使っておらず、containerd の `sandbox` でもないもの** だけを ID で並べる。一覧に無いタグ・「残す」のタグを 1 つでも持つイメージは消さない（duchamp の autoscaler 1.7.1 の 2 つのタグは残った）
3. `plan_optbin.py` が `/opt/bin` の `kubelet`・`kubectl`・`crictl`・`etcdctl`・`etcdutl` の版つきのファイルから、今の版と 1 つ前（`v1.37.1`・`v1.36.5`、`crictl-v1.37.0`・`v1.36.0`、`3.7.3`・`3.6.15`）を除いたものを並べる。リンクが今の版を指していなければ止める
4. coordinator に件数を知らせた後、`run_node.sh delete` が 1 と 2 を取り直し、イメージの一覧が同じでなければ止める。同じなら `crictl rmi <ID>` を 1 つずつ流し、`/opt/bin` は `sudo rm -v -- <名前を並べる>`
5. 1〜1.5 分おいて、もう一度 1 を取り、Running のコンテナの数、残したイメージがすべてあること、消した ID が残っていないこと、リンク、`kubelet`・`containerd` が active、`df`、クラスタのノード・Pod・Longhorn を見る

消したタグ・ID と `/opt/bin` のファイルの一覧は、タスクディレクトリの `notes/cleanup/rmi-<ノード>.txt`。

### 2.2 イメージと `/opt/bin`

| ノード | rmi | GiB（crictl の size） | `/opt/bin` | GiB | 使用（前） | 使用（後） | 空いた GiB（`df`） | 消した時刻（Z） | Running のコンテナ |
|---|---|---|---|---|---|---|---|---|---|
| rasp01 | 29 | 0.71 | 23 | 1.18 | 11G (10%) | 6.1G (6%) | 4.2 | 12:17:49〜12:17:53 | 9 → 9 |
| rasp02 | 31 | 0.74 | 23 | 1.18 | 9.8G (9%) | 5.5G (5%) | 4.3 | 12:19:32〜12:19:36 | 7 → 7 |
| rasp03 | 30 | 0.73 | 23 | 1.18 | 9.7G (9%) | 5.5G (5%) | 4.2 | 12:21:39〜12:21:43 | 9 → 9 |
| braque | 30 | 1.07 | 43 | 2.45 | 19G (18%) | 12G (12%) | 6.5 | 12:23:12〜12:23:19 | 5 → 5 |
| pablo | 100 | 7.69 | 43 | 2.45 | 69G (32%) | 37G (18%) | 31.6 | 12:26:49〜12:27:14 | 21 → 21 |
| duchamp | 134 | 14.56 | 43 | 2.45 | 88G (41%) | 31G (15%) | 57.1 | 12:29:33〜12:30:14 | 30 → 30 |
| oeilvert | 12 | 2.13 | 57 | 3.40 | 122G (29%) | 111G (26%) | 11.2 | 12:31:59〜12:32:04 | 37 → 37 |
| chirico | 212 | 20.23 | 39 | 2.23 | 112G (26%) | 36G (9%) | 75.7 | 12:33:38〜12:34:48 | 54 → 54 |
| 計 | 578 | 47.86 | 294 | 16.52 | | | 194.7 | | |

- イメージの件数と大きさは、一覧 §7.1 の「うち消す案」（計約 48 GiB）と合う。`/opt/bin` の件数は §7.6 と同じ（23・43・39・57）
- `df` で空いた量（194.7 GiB）は crictl の size よりずっと大きい。crictl の size は圧縮した大きさで、展開した snapshot のぶんも空いたため。oeilvert は Docker（`/var/lib/docker`）に触っていない
- どのノードも、残したイメージはすべてあり、消した ID は 0、リンクは今の版（`kubelet-v1.37.1`・`kubectl-v1.37.1`・`crictl-v1.37.0`・`etcdctl-3.7.3`・`etcdutl-3.7.3`）のまま、`kubelet`・`containerd` は active、クラスタの Pod の phase と restart の回数は変わらない（各台の後に確かめた）
- pablo の 1 回目は、消す直前に取り直した一覧が並び順だけ違っていて（`crictl images` の並びは毎回同じではない）照合が止めた。何も消していない。照合を並べ替えてから比べる形に直してやり直した
- pablo の `ghcr.io/open-webui/open-webui:0.7.2` と duchamp の `0.6.5`（どちらも約 1.5 GiB）は `crictl rmi` が失敗を返したが、もう一度 `rmi` すると `no such image` で、消えていた（crictl の時間切れ。上の表の rmi の件数に含めた）
- `k8s.gcr.io/pause:3.6`（worker 4 台）は containerd の `pinned` の印が残っていたが、containerd の `sandbox` は `registry.k8s.io/pause:3.10.1` で、`ctr containers ls` でもどの sandbox も 3.6 を使っていなかったので、一覧のとおり消した
- pablo の `/opt/bin/gojq` は一覧に無いので残した
- 消した後、`aphrael/tumblr-like` の CronJob が 12:38Z に動いて Completed になった（使うのは `ghcr.io/yuanying/tumblr-like:0.4.0`。消した `docker.io/yuanying/tumblr-like:v0.3.0` ではない）

### 2.3 小さい控えと古い Docker の apt のファイル（12:37:26〜12:37:35Z）

| ノード | 消したもの |
|---|---|
| rasp01・rasp02 | `/root/netplan.bak.20261016210442`・`/root/netplan.bak.20261016205015`（中身は `50-cloud-init.yaml` 1 つ。ファイルを消してから `rmdir`） |
| rasp03 | `/root/netplan.bak.20261016{201641,202543,202723,203554}`（同上、各 1 つ） |
| braque | `/root/cluster-dns.service.bak-20261017`、`/root/zfs.prom.bak-20261026`、`/etc/apt/sources.list.d/docker.list.disabled-20261017`、`/etc/apt/keyrings/docker.gpg` |
| pablo | `/root/cluster-dns.service.bak-20261018`、`/etc/apt/sources.list.d/docker.list.disabled-20261018`、`/etc/apt/keyrings/docker.gpg` |
| duchamp・chirico | `/root/cluster-dns.service.bak-20261017`、`/etc/apt/sources.list.d/docker.list.disabled-20261017`、`/etc/apt/keyrings/docker.gpg` |
| oeilvert | `/root/cluster-dns.service.bak-20261017`、`/var/lib/kubelet/cpu_manager_state.bak-k8u8` |

計 21 個（`netplan.bak` のディレクトリ 6 つを 1 個と数える）。一覧との違いは 2 つで、coordinator が案どおりと判断した（一覧 §11 を直した）。

- `cluster-dns.service.bak` は一覧の「worker 4 台」ではなく 5 台（oeilvert にもあった）
- 古い Docker の鍵は一覧の `/usr/share/keyrings/docker.gpg` ではなく `/etc/apt/keyrings/docker.gpg`（braque・pablo・duchamp・chirico）。消す直前に、`/etc/apt` の下で `docker.gpg` を参照するのが `docker.list.disabled-*` だけで、`docker.sources` は `docker.asc` を使うことを確かめた

消した後: 8 台とも `/etc/apt` の下に `docker.gpg` への参照が 0、`/etc/apt/keyrings/docker.asc` がある。**段 C の控え（`/root/k8u-stage-c/`、worker 5 台の `/etc/containerd/config.toml.porkadot-bak.*`）は containerd の config v4 まで残すので、残っていることを確かめた。**

### 2.4 一覧のとおり残したもの

- 各台の段 C の控え、apt の `rc` のパッケージ（一覧 §11）
- oeilvert の Docker（coordinator が 10-27 11:4xZ に整理済み。触っていない）
- replicas 0 の ReplicaSet（一覧 §8）、kube-prometheus の CRD の last-applied の注釈（§6）、名前空間 `kagent`（§2）

## 3. 終わった後の本番（2026-10-27 12:40Z）

- `kubectl --context fraction get nodes`: 8 台とも Ready、v1.37.1
- Running / Succeeded 以外の Pod: 0。消す前（12:09Z）の Pod の一覧と比べて違うのは `aphrael/tumblr-like` の CronJob の Pod の入れ替わり（12:38Z の実行）だけで、restart の回数はどれも変わらない
- Longhorn のボリューム: 14 個とも attached・healthy
- `infra-admin` のトークンのファイルは消した（単位 A の後と sealed-secrets の後に `rm -f /tmp/k8u-cleanup-admin-token`。トークンは 1 時間で切れる）

## 4. このリポジトリの `000-namespaces/`

一覧 §9.3 のとおり、`000-namespaces/`（`kustomization.yaml` と名前空間 6 つ）を消した。`bases: ../base/000-namespaces` の submodule は `2d22dd4` で外れていて、`kubectl kustomize` が通らなかった。本番の名前空間はどれも変えていない（`aphrael`・`comics`・`sites` は fleet-infra の `infrastructure/namespace/ns.yaml` が持ち主）。
