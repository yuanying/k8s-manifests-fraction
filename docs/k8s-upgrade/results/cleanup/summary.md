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

### 1.3 sealed-secrets の鍵（保留）

一覧は 23 個・最後が 2024-12-15 としていたが、実際は 39 個あった。2025-01〜2026-05 にも毎月 1 個ずつ増えていて、いちばん新しいのは `2026-05-10T06:01:04Z`（managedFields の manager は `controller`）。2026-01 からは作られた時刻が 12:10Z から 06:01Z に変わっている。つまり sealed-secrets のコントローラは 2026-05 まで動いていた（今は Pod・Deployment・CRD・APIService のどれも無い）。一覧と違うので消さずに止め、coordinator に判断を仰いだ。

### 1.4 消した後の確かめ

- 名前空間 3 つが NotFound。Terminating の名前空間は無い
- `nfd` の CRD 0（CRD は 66 → 63）。CSIDriver は `driver.longhorn.io` だけ
- 一覧の ClusterRoleBinding・ClusterRole は 66 個とも NotFound。PriorityClass は `longhorn-critical`・`system-*` の 3 つ
- ノードに kubevirt の名前の付いたラベル・注釈と `cpumanager` が残っていない
- Pod は消す前と同じ 161 個で、phase と restart の回数がすべて同じ。Running / Succeeded 以外の Pod は 0
- subjects のいない binding を出し直すと、一覧 §5.1 の既定の RBAC 5 つのほかに 2 つ出た（下の 1.5）

### 1.5 一覧に無かったもの（消していない）

- **ClusterRoleBinding `remora:pod-checkpointer`（2017-10-10）・`update-storage-objects`（2018-10-19）。** どちらも `cluster-admin` を kube-system の SA `pod-checkpointer`・`storage-objects-updater` に結び付けている。一覧は SA が残っていたのでこの 2 つを検出していなかった。今回 SA を消したので subjects のいない binding になった。一覧に無いので消していない（ただし同じ名前の SA を作り直すとその SA が `cluster-admin` になるので、消すことを勧める）
- **ClusterRoleBinding `tiller-cluster-rule`（2017-10-10）** は `cluster-admin` を `kube-system/default` に与えている。kube-apiserver の DaemonSet の Pod（3 つ）がこの SA で動いている。Tiller の名残だが、使っている Pod があるので片付けの範囲の外。報告に書いた

## 2. このリポジトリの `000-namespaces/`

一覧 §9.3 のとおり、`000-namespaces/`（`kustomization.yaml` と名前空間 6 つ）を消した。`bases: ../base/000-namespaces` の submodule は `2d22dd4` で外れていて、`kubectl kustomize` が通らなかった。本番の名前空間はどれも変えていない（`aphrael`・`comics`・`sites` は fleet-infra の `infrastructure/namespace/ns.yaml` が持ち主）。
