# 片付けの一覧と手順（本番 `fraction`、計画 §10）

計画 `plan.md`（以下「計画」）§10 の **片付け** の対象を読み取りで確かめ、候補ごとに今の状態・参照・判断・消し方・確かめ方・戻し方をまとめたもの。K8s の段（段 8 で v1.37.1）と計画 §8 の非クリティカルなコンポーネントの更新（CoreDNS v1.15 を除く）が終わった後に書いた。

- **この文書では何も消していない。** 本番・ノード・リポジトリ・作業端末のどれにも書き込んでいない（`fraction-auditor` での `get`、ノードへの SSH での `crictl images`・`crictl ps -a`・`df`・`ls`・`du`・`dpkg -l`、リポジトリの `git grep` だけ）
- 消すのは、§12 の承認の単位ごとにユーザーの承認を取った後の、別の作業単位
- 読み取りの日時: 2026-10-27 11:00〜11:40Z ごろ。消す作業の直前に、各節の「消す前に確かめる」をもう一度流す（状態は動く）

## 0. 要約

| # | 候補 | 結論（案） | 単位 |
|---|---|---|---|
| 1 | 中身の無い名前空間 | `istio-system`・`metallb` は消す。`ml-study` はユーザーに聞く（fleet-infra にマニフェストが残る）。`kagent` は残す（fleet-infra の共通の名前空間の一覧にあり、消しても次の apply で戻る）。`crawl4ai`・`minio-system`・`homegallery` は既に無い | A |
| 2 | 持ち主のいない CRD | `nfd.k8s-sigs.io` の 3 つ（0 件）を消す。ほかの CRD は持ち主のコントローラがいる | A |
| 3 | CSIDriver・StorageClass | CSIDriver `rook-ceph.rbd.csi.ceph.com`・`rook-ceph.cephfs.csi.ceph.com` を消す。StorageClass はどれもマニフェストに持ち主がいるので残す | A |
| 4 | 古い RBAC など | subjects の ServiceAccount・名前空間が無い ClusterRoleBinding 32 個と、その ClusterRole 27 個（MetalLB の Tiller、`g0`・`p0`、rook、gpu-operator / NFD、kubevirt、tgtd・zfs-operator、kube-lego）を消す。ほかに kube-system の名残（`pod-checkpointer`、Service `tiller-deploy`、ConfigMap 4 つ、Job `update-storage-objects`、cilium の Secret）、PriorityClass `kubevirt-cluster-critical`、ノードの kubevirt のラベル | A（Secret はユーザー判断） |
| 5 | kube-prometheus の CRD 4 つの last-applied の注釈 | 残す（害が無く、apiserver が中身を新しく保っている）。消してもよいが得るものが小さい | — |
| 6 | ノードの containerd の古いイメージ | 使われていないものを `crictl rmi` で明示して消す（約 48 GiB）。戻しの材料（今の 1 つ前）は残す。kubelet の GC には任せない。**oeilvert の 82% は Docker（`/var/lib/docker` 236G）が原因で、containerd を片付けても 2 GiB しか空かない** | B |
| 6b | ノードの `/opt/bin` の古いバイナリ | 1 つ前より古い kubelet・kubectl・crictl・etcdctl を消す（1 台 1.2〜3.4 GiB） | B |
| 7 | replicas 0 の ReplicaSet | 消さない。どの Deployment も `revisionHistoryLimit` 以内で、`rollout undo` の材料 | — |
| 8 | private・k8s-env・このリポジトリの古いマニフェスト | 本番に無いものを消す PR、本番に今あるもの（private の `shja-base` の nginx）は残す。private の `metrics-server/` は fleet-infra に移ったので消す | C |
| 9 | 作業端末 | マージ済みのローカルのブランチ 109 本、独立の clone 2 つ、`backup/` の etcd のスナップショット（残す案あり）、`/tmp` の作業の clone | D |
| 10 | ほかの記録からの候補 | ノードの控え（`/root/k8u-stage-c/` など）は containerd の config v4 が終わるまで残す。fraction-auditor の `developer` の権限は fleet-infra の意図した設定 | B・— |

## 1. 調べ方

- Kubernetes: `kubectl --context fraction`（`fraction-auditor`）。名前空間は、list できる名前空間つきの型 89 種をすべて数え、`configmap/kube-root-ca.crt` と `serviceaccount/default` を除いた
- CRD: `kubectl get crd` の 66 個を 1 つずつ `kubectl get <crd> -A` で数えた（`results/cleanup-survey/crds.tsv`）
- RBAC: 全 ClusterRoleBinding・RoleBinding の subjects の ServiceAccount を、今ある ServiceAccount・名前空間と突き合わせた（`results/cleanup-survey/orphan-bindings.tsv`）
- ノード: 8 台に IP で SSH（worker は `yuanying@`、control-plane は `ubuntu@`）し、`/opt/bin/crictl --runtime-endpoint unix:///run/containerd/containerd.sock --image-endpoint unix:///run/containerd/containerd.sock images -o json`・`ps -a -o json`、`df -h`、`ls -la /opt/bin`。使われていないイメージ = どのコンテナ（終わったものを含む）の `imageRef` にも当たらないもの（`results/cleanup-survey/images-plan.tsv`）
- 参照の grep: 各リポジトリの既定のブランチ（k8s-manifests-fraction `27d29a9`、k8s-manifests-fraction-private `3df954d`、fleet-infra `e133a38`、k8s-env `60b5333`、porkadot `aacfba7`、porkadot-dev `dd17557`、fraction-agents `eaf9545`）。手元の clone の origin が古いもの（k8s-env、porkadot、porkadot-dev、fraction-agents）は `/tmp` に浅い clone を取って grep した。k8s-manifests-fraction が submodule で使っていた `yuanying/k8s-base`（`79c89dc`）も読んだ（§2）

## 2. 中身の無い名前空間

### 2.1 状態

| 名前空間 | 作成 | 中身 | 作った者 |
|---|---|---|---|
| `istio-system` | 2019-12-03 | 0（既定の 2 つだけ） | last-applied あり（ラベル `istio-injection: disabled`・`region: fraction`）。`yuanying/k8s-base` の `000-namespaces/istio.yaml`。k8s-base は k8s-manifests-fraction の submodule `base` だったが、`2d22dd4`（2026-10-23）で submodule ごと外れた |
| `metallb` | 2020-04-15 | 0 | last-applied あり（ラベル `region: fraction`）。k8s-base の `000-namespaces/metallb.yaml`。2018 年の Helm（Tiller）の MetalLB の名残（今の MetalLB は `metallb-system`） |
| `kagent` | 2026-09-23 | 0 | `kubectl-client-side-apply`。fleet-infra の `infrastructure/namespace/ns.yaml`（共通の名前空間の一覧。test にも prod にも apply する）。kagent のアプリは `apps/kagent/test` だけで prod の overlay は無い |
| `ml-study` | 2023-04-13 | ServiceAccount `developer`、Role `developer`、RoleBinding `developer` の 3 つ | `kubectl-client-side-apply`。fleet-infra の `apps/ml-study/`（poissonerie・uribo の Service・StatefulSet。どれも本番に無い）と `secrets/prod/docker-registry-key.enc.yaml`（ml-study 向けの Secret。本番に無い）。中身の 3 つ（Role `developer` = すべての権限、RoleBinding `developer` → `kube-system/infra-auditor`）は fleet-infra の `infrastructure/commons/rbac-base` と同じ形だが、ml-study 向けの overlay（`rbac-<名前空間>`）は無く、どのマニフェストにも無い（2023 年に手で apply、2024-06-08 に subjects を書き換え） |
| `crawl4ai`・`minio-system` | — | 名前空間ごと無い（既に消えた） | — |
| `homegallery` | — | 名前空間ごと無い | — |

ほかの名前空間は、どれも Pod などの中身がある（中身の数は aphrael 34 〜 longhorn-system 409）。`kube-public` は既定の Role・RoleBinding `system:controller:bootstrap-signer` だけで、K8s の既定なので対象外。

### 2.2 参照

- `istio-system`: マニフェストの参照は無い（fleet-infra の `apps/kagent/base/src.yaml` に kagent の例文として文字列が 1 つあるだけ）
- `metallb`: マニフェストの参照は無い。ClusterRoleBinding `mlb0-metallb:*` の subjects がこの名前空間の ServiceAccount を指す（§5。一緒に消す）。k8s-env の `docs/metallb.md` は 2018 年の Helm の手順
- `kagent`: fleet-infra の `infrastructure/namespace/ns.yaml` の 40 行目
- `ml-study`: fleet-infra の `apps/ml-study/`、`secrets/prod/docker-registry-key.enc.yaml`、`apps/natsumi/{aki,myao}/kustomization.yaml` のコメント（「`::151`・`::152`（ml-study）使用中」。本番に該当の Service は無い）

### 2.3 判断

- **`istio-system`・`metallb`: 消してよい。** 中身が 0 で、持ち主のマニフェスト（k8s-base）はこのリポジトリから外れている
- **`kagent`: 残す（案）。** 消しても、次に fleet-infra の `infrastructure/namespace/` を prod に apply すると戻る。消すなら先に fleet-infra で kagent を test だけの名前空間に移す PR が要る（単位 C。ユーザー判断）
- **`ml-study`: ユーザーに聞く。** 本番では中身のアプリが無く RBAC だけだが、fleet-infra にアプリのマニフェストと prod の Secret が残っている。ml-study（GPU ノード poissonerie・uribo の devbox）をもう使わないなら、名前空間を消し、fleet-infra から `apps/ml-study/` と `secrets/prod/docker-registry-key.enc.yaml` の ml-study の分を消す PR を出す（単位 C）。使うなら残す

### 2.4 消し方

```sh
umask 077
kubectl --context fraction create token infra-admin -n kube-system --duration=1h > /tmp/k8u-cleanup-admin-token
ADMIN_TOKEN=$(cat /tmp/k8u-cleanup-admin-token)
kubectl-admin() { kubectl --context fraction --token="$ADMIN_TOKEN" "$@"; }
NOTES=/home/yuanying/.local/state/herdr-tasks/fraction-k8s-upgrade/notes/cleanup   # 控えの置き場所（§11.1）
mkdir -p $NOTES

# 消す前に確かめる（中身が 0 であること。名前空間ごとに）
R=$(kubectl --context fraction api-resources --namespaced=true --verbs=list -o name | grep -v '^events' | paste -sd,)
for ns in istio-system metallb; do
  echo "$ns: $(kubectl --context fraction get $R -n $ns -o name 2>/dev/null | grep -v -x -E 'configmap/kube-root-ca.crt|serviceaccount/default' | wc -l)"
done
# どちらも 0 でなければ止める

# 控える（§11）
for ns in istio-system metallb; do kubectl --context fraction get ns $ns -o yaml > $NOTES/ns-$ns.yaml; done

kubectl-admin delete ns istio-system metallb
```

`ml-study` を消すと決まった場合は、同じ形で `ml-study`（中身は §2.1 の 3 つ。控えに含める）を消す。

### 2.5 消した後の確かめ

- `kubectl --context fraction get ns istio-system metallb` が NotFound（Terminating が数秒見えることがある）
- `kubectl --context fraction get ns` で Terminating のものが残らない

### 2.6 戻し方

控えた yaml から `metadata.uid`・`resourceVersion`・`creationTimestamp`・`status` を除いて `kubectl-admin apply -f`。中身が無いので、名前空間を作り直せば元どおり。

## 3. 持ち主のいない CRD

### 3.1 状態

66 個の CRD のうち、持ち主のコントローラがいないのは `nfd.k8s-sigs.io` の 3 つだけ。

| CRD | 作成 | 件数 | 作った者 |
|---|---|---|---|
| `nodefeatures.nfd.k8s-sigs.io` | 2023-09-02 | 0 | gpu-operator の Helm（NFD を同梱）。managedFields は `kubectl-client-side-apply`（2025-05-01）と `kube-apiserver` |
| `nodefeaturerules.nfd.k8s-sigs.io` | 2023-09-02 | 0 | 同上 |
| `nodefeaturegroups.nfd.k8s-sigs.io` | 2025-03-16 | 0 | 同上（gpu-operator の更新で増えた） |

ほかの CRD の持ち主: `longhorn.io` 30 個（Longhorn。0 件のものも Longhorn の chart が持つ）、`monitoring.coreos.com` 10 個（kube-prometheus-stack）、`metallb.io` 9 個（porkadot の MetalLB）、`aquasecurity.github.io` 13 個（trivy-operator、2026-10-26）、`gate.unstable.cloud` 3 個（gated）、`cnidaria.unstable.cloud` 1 個（cnidaria の `NodeNetworkPolicy`。porkadot が配る。0 件だが cnidaria が watch する）。MetalLB の古い `addresspools.metallb.io` は MetalLB の更新（runbook-metallb-0.16 §5）で消えている。kubevirt・cert-manager・sealed-secrets・istio の CRD は既に無い。

### 3.2 参照

`nfd.k8s-sigs.io`・`node-feature-discovery`・`gpu-operator` はどのリポジトリにも無い（fleet-infra の `apps/ml-study` の履歴に「Bump gpu-operator」`8ddd66e` があるだけで、今のマニフェストには無い）。NFD のコントローラ（gpu-operator の名前空間）は無い。

### 3.3 判断

消してよい。件数 0、conversion webhook なし（`v1alpha1` だけ）、watch するものがいない。gpu-operator / NFD の RBAC（§5）と一緒に消す。

### 3.4 消し方

```sh
for c in nodefeatures nodefeaturerules nodefeaturegroups; do
  echo "$c: $(kubectl --context fraction get $c.nfd.k8s-sigs.io -A -o name | wc -l)"   # どれも 0 でなければ止める
  kubectl --context fraction get crd $c.nfd.k8s-sigs.io -o yaml > $NOTES/crd-$c.nfd.k8s-sigs.io.yaml
done
kubectl-admin delete crd nodefeatures.nfd.k8s-sigs.io nodefeaturerules.nfd.k8s-sigs.io nodefeaturegroups.nfd.k8s-sigs.io
```

### 3.5 確かめ・戻し方

- `kubectl --context fraction get crd | grep nfd` が空
- 戻すときは控えた yaml を `kubectl-admin apply --server-side -f`（中身は 0 件なので CRD だけで元どおり）

## 4. CSIDriver・StorageClass

### 4.1 状態と参照

| 対象 | 作成 | 使われ方 | 判断 |
|---|---|---|---|
| CSIDriver `rook-ceph.rbd.csi.ceph.com` | 2020-10-29 | PV の `spec.csi.driver` に 0、VolumeAttachment の attacher に 0（14 個とも `driver.longhorn.io`）、StorageClass の provisioner に 0。rook の名前空間・Pod は無い | **消す** |
| CSIDriver `rook-ceph.cephfs.csi.ceph.com` | 2020-10-29 | 同上 | **消す** |
| CSIDriver `driver.longhorn.io` | 2026-10-21 | Longhorn | 残す |
| StorageClass `gold` | 2022-03-21 | PV・PVC 0 | 残す。fleet-infra の `infrastructure/longhorn/base/sc.yaml` に定義がある（消すならマニフェストから。今回は対象外） |
| StorageClass `longhorn-static` | 2026-05-21 | PV・PVC 0 | 残す。Longhorn が作るもの |
| StorageClass `silver`・`bronze`・`longhorn` | — | PV 12・2、PVC 3 | 残す |

rook の CSIDriver の作った者は managedFields が無く分からない（2020 年の rook v1.4 ごろの operator が作ったもの。k8s-env の `templates/templates/manifests/rook*/` は 2018 年の rook v0.8 の形で、CSI を含まない）。

### 4.2 消し方・確かめ・戻し方

```sh
kubectl --context fraction get pv -o jsonpath='{range .items[*]}{.spec.csi.driver}{"\n"}{end}' | grep -c rook   # 0 でなければ止める
kubectl --context fraction get volumeattachment -o jsonpath='{range .items[*]}{.spec.attacher}{"\n"}{end}' | grep -c rook   # 0
kubectl --context fraction get csidriver rook-ceph.rbd.csi.ceph.com rook-ceph.cephfs.csi.ceph.com -o yaml > $NOTES/csidriver-rook.yaml
kubectl-admin delete csidriver rook-ceph.rbd.csi.ceph.com rook-ceph.cephfs.csi.ceph.com
kubectl --context fraction get csidriver   # driver.longhorn.io だけ
```

戻すときは控えた yaml を `kubectl-admin apply -f`。

## 5. 古い RBAC と、ほかの名残のリソース

### 5.1 subjects のいない ClusterRoleBinding とその ClusterRole

subjects の ServiceAccount がすべて無い（名前空間ごと無いか、SA が無い）binding は 37 個。うち 5 つは apiserver の既定の RBAC（ラベル `kubernetes.io/bootstrapping: rbac-defaults`。`system:kube-dns`・`system:controller:route-controller`・`system:controller:selinux-warning-controller`・`system:aws-cloud-provider`、kube-system の RoleBinding `system:controller:cloud-provider`）で、**触らない**（apiserver が起動のたびに作り直す・持ち主が apiserver）。残りの 32 個（全一覧は `results/cleanup-survey/orphan-bindings.tsv`）を出どころでまとめると次のとおり。参照先の ClusterRole 27 個は、どれもこの 32 個のほかからは参照されていない。

| 出どころ | ClusterRoleBinding | ClusterRole | 作成 | 根拠 |
|---|---|---|---|---|
| MetalLB の Helm（Tiller、chart metallb-0.8.0、release `mlb0`） | `mlb0-metallb:controller`・`mlb0-metallb:speaker` | 同じ名前の 2 つ | 2018-11-21 | ラベル `heritage=Tiller`。subjects は名前空間 `metallb` の無い SA |
| Prometheus・Grafana の Helm（Tiller、`p0`・`g0`） | `p0-prometheus-kube-state-metrics`・`p0-prometheus-server`・`g0-grafana-clusterrolebinding` | `p0-prometheus-kube-state-metrics`・`p0-prometheus-server`・`g0-grafana-clusterrole` | 2018-11-25・26 | ラベル `heritage=Tiller`（chart prometheus-8.9.0・grafana-1.18.0）。名前空間 `prometheus`・`grafana` は無い。`runbook-kube-prometheus-92.md` §10、`results/kube-prometheus-92/baseline.md` の 17 |
| kube-lego の Helm（Tiller、`certs`） | `certs-kube-lego` | `certs-kube-lego` | 2018-11-20 | ラベル `heritage=Tiller`（chart kube-lego-0.4.2）。名前空間 `ingress` は無い |
| rook-ceph | `rook-ceph-global`・`rook-ceph-mgr-cluster`・`rook-ceph-object-bucket`・`rook-ceph-osd`・`rook-ceph-admission-controller-rolebinding`・`rook-ceph-system-psp`・`rook-csi-{cephfs,rbd}-{plugin,provisioner}-sa-psp`（4）・`cephfs-csi-nodeplugin`・`cephfs-csi-provisioner-role`・`rbd-csi-nodeplugin`・`rbd-csi-provisioner-role` | `rook-ceph-global`・`rook-ceph-mgr-cluster`・`rook-ceph-object-bucket`・`rook-ceph-osd`・`rook-ceph-admission-controller-role`・`psp:rook`・`cephfs-csi-nodeplugin`・`cephfs-external-provisioner-runner`・`rbd-csi-nodeplugin`・`rbd-external-provisioner-runner`、どこからも参照されない `rook-ceph-cluster-mgmt`・`rook-ceph-mgr-system` | 2018-10-17、2020-10-29 | 名前空間 `rook-ceph` は無い。`psp:rook` は PodSecurityPolicy（1.25 で削除済み）向け。2018 年の 2 つは k8s-env の `templates/templates/manifests/rook-operator/operator.yaml` |
| gpu-operator（NFD を同梱） | `gpu-operator`・`gpu-operator-node-feature-discovery`・`-gc`・`-prune`・`-topology-updater`・`gpu-operator-upgrade-crd-hook-binding` | `gpu-operator`・`gpu-operator-node-feature-discovery`・`-gc`・`-prune`・`gpu-operator-upgrade-crd-hook-role`（`-topology-updater` の ClusterRole は既に無い） | 2023-09-02、2025-03-16 | 名前空間 `gpu-operator` は無い。§3 の CRD と同じ持ち主 |
| kubevirt | `kubevirt-operator` | `kubevirt-operator`、どこからも参照されない `kubevirt.io:operator`（`aggregate-to-admin`） | 2023-04-19 | 名前空間 `kubevirt` も CRD も無い |
| tgtd-operator・zfs-operator | `tgtd-operator-{controller,node,proxy}-rolebinding`・`zfs-operator-{node,proxy}-rolebinding` | `tgtd-operator-{controller,node,proxy}-role`・`zfs-operator-{node,proxy}-role`、参照されない `tgtd-operator-metrics-reader`・`zfs-operator-metrics-reader` | 2020-07-30 | 名前空間 `tgtd-operator-system`・`zfs-operator-system` は無い。k8s-base の `iscsi-zvol/`（k8s-manifests-fraction の `2d22dd4` で消えたアプリ） |

判断: **すべて消してよい。** subjects が存在せず、誰にも権限を与えていない。`kubevirt.io:operator` は `aggregate-to-admin` で admin の ClusterRole に kubevirt の権限を足しているが、kubevirt の API が無いので効いていない。

### 5.2 kube-system などに残る名残

| 対象 | 作成 | 状態 | 判断 |
|---|---|---|---|
| `pod-checkpointer`（kube-system の SA・ConfigMap・Role・RoleBinding、ClusterRole・ClusterRoleBinding） | 2017-10-10、2020-04-10 | bootkube の pod-checkpointer。Pod・DaemonSet は無い。SA はあるので §5.1 の機械的な検出には出ない。参照は porkadot-dev の `docs/cp-replacement/method-comparison.md`（説明）だけ | 消す |
| Service `kube-system/tiller-deploy` | 2017-10-10 | selector `app=helm,name=tiller`、endpoint 0 | 消す |
| ConfigMap `kube-system/core-dns` | 2017-10-10 | 古い CoreDNS の設定（Corefile と `fraction.jp`・`iwaco.pink`・`oeilvert.org` のゾーンのファイル）。今の CoreDNS は ConfigMap `coredns` を使う | 消す（ゾーンのファイルを残したければ控えで足りる） |
| ConfigMap `kube-system/kube-keepalived` | 2017-10-10 | 古い keepalived・haproxy の設定。参照なし | 消す |
| ConfigMap `kube-system/kube-flannel-cni-sh` | 2018-01-29 | flannel の名残（CNI は 2026-10-17 から cnidaria） | 消す |
| Job `kube-system/update-storage-objects` と SA `storage-objects-updater` | 2018-10-19 | 2018 年に 1 回成功した Job（`zlabjp/update-storage-objects:1.1.0`） | 消す |
| Secret `kube-system/cilium-ca`・`cilium-cli-helm-values`・`hubble-server-certs` | 2022-12-01 | cilium を試した名残。cilium の Pod・CRD は無い | 消す（**Secret なので控えは秘密情報を含む。§11.2**） |
| Secret `kube-system/sealed-secrets-key*`（23 個） | 2023-03-26〜2024-12-15 | sealed-secrets のコントローラの鍵。コントローラも CRD も無く、どのリポジトリにも `kind: SealedSecret` は無い（fleet-infra は sops） | **ユーザー判断**。消すと、手元のどこかに SealedSecret が残っていた場合に復号できなくなる。既定は残す |
| PriorityClass `kubevirt-cluster-critical` | 2023-04-19 | 使う Pod 0 | 消す |
| ノードのラベル `kubevirt.io/schedulable`（chirico・oeilvert）・`cpumanager=false`（chirico・duchamp・oeilvert）、注釈 `kubevirt.io/heartbeat`（chirico・duchamp・oeilvert） | — | kubevirt の virt-handler が付けたもの。どの nodeSelector・affinity も使わない | 消す |

ノードのラベルのうち `metallb=speaker`・`tgtd.unstable.cloud/storage`・`zfs.unstable.cloud/storage`・`node-role.kubernetes.io/{assassin,laga,lapin,simone}`・`role=worker` もどのワークロードからも使われていないが、`metallb=speaker`・`tgtd`・`zfs` は本番の `porkadot.yaml` の node labels（kubelet の `--node-labels`）が付けるもので、ノードから外しても kubelet が付け直す。外すなら `porkadot.yaml` の PR と `install kubelet`（単位 C。害が無いので今回は対象外の案）。`node-role.kubernetes.io/*` の名前は表示用として残す。

### 5.3 消し方

```sh
# 消す前に確かめる: §5.1 の 32 個の subjects が今も無いこと（results/cleanup-survey/orphan-bindings.tsv を読み直す形で再計算する）
kubectl --context fraction get ns -o name | sort > /tmp/k8u-cleanup-ns.txt
kubectl --context fraction get sa -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' | sort > /tmp/k8u-cleanup-sa.txt
# subjects の SA が 1 つでも存在する binding は消さずに止める

CRB="mlb0-metallb:controller mlb0-metallb:speaker p0-prometheus-kube-state-metrics p0-prometheus-server g0-grafana-clusterrolebinding certs-kube-lego rook-ceph-global rook-ceph-mgr-cluster rook-ceph-object-bucket rook-ceph-osd rook-ceph-admission-controller-rolebinding rook-ceph-system-psp rook-csi-cephfs-plugin-sa-psp rook-csi-cephfs-provisioner-sa-psp rook-csi-rbd-plugin-sa-psp rook-csi-rbd-provisioner-sa-psp cephfs-csi-nodeplugin cephfs-csi-provisioner-role rbd-csi-nodeplugin rbd-csi-provisioner-role gpu-operator gpu-operator-node-feature-discovery gpu-operator-node-feature-discovery-gc gpu-operator-node-feature-discovery-prune gpu-operator-node-feature-discovery-topology-updater gpu-operator-upgrade-crd-hook-binding kubevirt-operator tgtd-operator-controller-rolebinding tgtd-operator-node-rolebinding tgtd-operator-proxy-rolebinding zfs-operator-node-rolebinding zfs-operator-proxy-rolebinding pod-checkpointer"
CR="mlb0-metallb:controller mlb0-metallb:speaker p0-prometheus-kube-state-metrics p0-prometheus-server g0-grafana-clusterrole certs-kube-lego rook-ceph-global rook-ceph-mgr-cluster rook-ceph-object-bucket rook-ceph-osd rook-ceph-admission-controller-role psp:rook cephfs-csi-nodeplugin cephfs-external-provisioner-runner rbd-csi-nodeplugin rbd-external-provisioner-runner rook-ceph-cluster-mgmt rook-ceph-mgr-system gpu-operator gpu-operator-node-feature-discovery gpu-operator-node-feature-discovery-gc gpu-operator-node-feature-discovery-prune gpu-operator-upgrade-crd-hook-role kubevirt-operator kubevirt.io:operator tgtd-operator-controller-role tgtd-operator-node-role tgtd-operator-proxy-role tgtd-operator-metrics-reader zfs-operator-node-role zfs-operator-proxy-role zfs-operator-metrics-reader pod-checkpointer"

# 控える（§11）
kubectl --context fraction get clusterrolebinding $CRB -o yaml > $NOTES/clusterrolebindings.yaml
kubectl --context fraction get clusterrole $CR -o yaml > $NOTES/clusterroles.yaml
kubectl --context fraction get -n kube-system sa/pod-checkpointer cm/pod-checkpointer role/pod-checkpointer rolebinding/pod-checkpointer \
  svc/tiller-deploy cm/core-dns cm/kube-keepalived cm/kube-flannel-cni-sh job/update-storage-objects sa/storage-objects-updater -o yaml > $NOTES/kube-system-leftovers.yaml
kubectl --context fraction get priorityclass kubevirt-cluster-critical -o yaml > $NOTES/priorityclass-kubevirt.yaml

kubectl-admin delete clusterrolebinding $CRB
kubectl-admin delete clusterrole $CR
kubectl-admin delete -n kube-system sa/pod-checkpointer cm/pod-checkpointer role/pod-checkpointer rolebinding/pod-checkpointer \
  svc/tiller-deploy cm/core-dns cm/kube-keepalived cm/kube-flannel-cni-sh job/update-storage-objects sa/storage-objects-updater
kubectl-admin delete priorityclass kubevirt-cluster-critical
for n in chirico duchamp oeilvert; do
  kubectl-admin label node $n kubevirt.io/schedulable- cpumanager-
  kubectl-admin annotate node $n kubevirt.io/heartbeat-
done
```

- `gpu-operator-node-feature-discovery-topology-updater` の ClusterRole は既に無いので `$CR` に入れていない（binding だけ消す）
- `pod-checkpointer` は ClusterRoleBinding・ClusterRole と kube-system の 4 つの両方
- cilium の Secret 3 つは §11.2 の控え方を決めてから `kubectl-admin delete -n kube-system secret cilium-ca cilium-cli-helm-values hubble-server-certs`。sealed-secrets の鍵は承認が無い限り消さない
- Job を消すと、その Pod は既に無い（2018 年の完了の Pod は GC 済み）

### 5.4 確かめ

- §5.1 の検出をもう一度流し、残るのが §5.1 の既定の RBAC の 5 つだけになること
- `kubectl --context fraction auth can-i --list --as=system:serviceaccount:kube-system:infra-admin` などで、今の SA の権限が変わっていないこと（消したのは subjects のいない binding だけなので変わらない）
- MetalLB・kube-prometheus・Longhorn・metrics-server・CoreDNS の Pod が Running のまま、restart が増えない

### 5.5 戻し方

控えた yaml から `metadata.uid`・`resourceVersion`・`creationTimestamp`・`managedFields` を除いて `kubectl-admin apply -f`。subjects が無いので、作り直しても何も動かない。

## 6. kube-prometheus の CRD の last-applied の注釈

### 6.1 状態

`podmonitors`・`probes`・`prometheusrules`・`servicemonitors`（`monitoring.coreos.com`）の 4 つに `kubectl.kubernetes.io/last-applied-configuration` がある（42,592・42,434・8,484・43,227 B）。中身は 0.94.1（`operator.prometheus.io/version: 0.94.1`）で、今の CRD と同じ。managedFields は `kubectl-last-applied`（Apply、注釈だけ）・`kubectl`（Apply）・`kube-apiserver`（Update、status）。

ほかの CRD（Longhorn、trivy、gated、NFD）にも last-applied があるが、それらは client-side apply で入っているので当然ある。kube-prometheus の 10 個のうちほかの 6 つは server-side apply だけで入っていて、注釈が無い。

### 6.2 消すと何が起きるか

- kubectl の server-side apply は、対象に last-applied の注釈があり、まだ Apply の manager が持っていなければ、`kubectl-last-applied` の manager で注釈だけを Apply し直してから本体を Apply する（kubectl の `saveLastApplyAnnotationIfNecessary`。注釈が無ければ何もしない）。apiserver は、注釈がある間は server-side apply のたびに中身を新しく書き換える。**注釈を消せば、次の server-side apply で作り直されることは無い**
- 消しても server-side apply（今の運用。`runbook-kube-prometheus-92.md` §3.4）には影響が無い
- 消すと、その 4 つを client-side apply に戻したときの 3-way merge の材料が無くなる。ただし CRD は大きくて client-side では入らないものがあり（`prometheuses` は約 497 KB）、client-side に戻す運用は無い

### 6.3 判断

**残す（案）。** 害が無く、中身は apiserver が新しく保っている。消して得るのは etcd の 4 オブジェクトで計約 137 KB だけ。ユーザーがそろえたい場合だけ、単位 A に入れて次のとおり消す。

```sh
for c in podmonitors probes prometheusrules servicemonitors; do
  kubectl --context fraction get crd $c.monitoring.coreos.com -o yaml > $NOTES/crd-$c.monitoring.coreos.com.yaml
  kubectl-admin annotate crd $c.monitoring.coreos.com kubectl.kubernetes.io/last-applied-configuration-
done
```

確かめ: 4 つの注釈が無く、managedFields から `kubectl-last-applied` が消え、`kubectl --context fraction get crd <名前> -o jsonpath='{.status.conditions[?(@.type=="Established")].status}'` が `True`。戻すなら控えの注釈の値を `kubectl-admin annotate` で書き戻す（または client-side の `kubectl apply` を 1 回）。

## 7. ノードの containerd に残る古いイメージ

### 7.1 状態

| ノード | ディスク（/） | 使用率 | イメージ | 合計 | 使われていない | うち消す案 | うち残す案 |
|---|---|---|---|---|---|---|---|
| rasp01（.111） | 117G | 10% | 49 | 1.1 GiB | 40（0.9 GiB） | 0.7 GiB | 0.2 GiB |
| rasp02（.112） | 117G | 9% | 49 | 1.1 GiB | 42（1.0 GiB） | 0.7 GiB | 0.2 GiB |
| rasp03（.113） | 117G | 9% | 48 | 1.1 GiB | 39（0.9 GiB） | 0.7 GiB | 0.2 GiB |
| braque | 109G | 18% | 41 | 1.3 GiB | 36（1.2 GiB） | 1.1 GiB | 0.1 GiB |
| chirico | 457G | 26% | 289 | 25.1 GiB | 247（21.8 GiB） | 20.2 GiB | 1.6 GiB |
| duchamp | 228G | 41% | 195 | 18.3 GiB | 168（16.1 GiB） | 14.6 GiB | 1.7 GiB |
| oeilvert | 457G | **82%** | 76 | 6.8 GiB | 43（4.1 GiB） | 2.1 GiB | 2.0 GiB |
| pablo | 229G | 32% | 149 | 10.3 GiB | 130（9.0 GiB） | 7.6 GiB | 1.4 GiB |

- 大きさは `crictl images` の `size`（目安。展開した snapshot の大きさとは違う。chirico の `/var/lib/containerd` は 91G）
- **oeilvert の 82% は Docker が原因。** `/var/lib/docker` が 236G（`docker system df`: イメージ 558 個 166.5GB のうち 101GB が回収できる、build cache 138GB のうち 44GB）。containerd のイメージは 6.8 GiB で、片付けても 2 GiB しか空かない。Docker の片付け（`docker image prune`・`docker builder prune`）は oeilvert の Docker の持ち主（ユーザーの devbox・ビルド）の判断で、この片付けの範囲の外。**ただし kubelet の既定の `evictionHard` は `imagefs.available<15%`（使用率 85% 超）で、oeilvert はあと 3% で DiskPressure になり Pod が退去させられる**（ユーザーに知らせる）
- 一覧は `results/cleanup-survey/images-plan.tsv`（258 行。リポジトリ・タグ・クラスタが今使う版・大きさ・ノード・判断）

使われていないものの内訳（タグ単位、8 台の合計）:

| 分類 | 数 | 大きさ | 例 |
|---|---|---|---|
| 今のマニフェストが参照する（Pod がそのノードに無いだけ） | 16 | 0.7 GiB | Longhorn の CSI の sidecar、`longhorn-ui:v1.13.0`、`metallb/controller:v0.16.1`、`coredns:v1.14.7`、`trivy:0.75.0` |
| 今動いているものの古い版 | 126 | 19.5 GiB | MetalLB v0.12.1・v0.13.9・v0.14.5、kube-apiserver などの v1.24.6〜v1.36.5、kube-proxy v1.24.6〜v1.36.5、etcd 3.5.12・3.5.34・3.6.15、CoreDNS v1.9.3〜v1.13.2、metrics-server v0.7.2、Prometheus v2.32.1〜v3.11.3、cnidaria v0.1.0・v0.1.1、Longhorn の instance-manager・share-manager v1.11.2、natsumi・fraction-agents の古い版 |
| 持ち主のいないもの（クラスタに同じリポジトリのイメージが無い） | 116 | 35.0 GiB | タグの無い `<none>` 117 個（12.5 GiB）、open-webui（5.9 GiB）、kubevirt v0.57.1・CDI v1.55.0、cert-manager v1.7〜v1.18、flannel、gpu-operator・NFD、crawl4ai、home-gallery、hackmd、docker-mailserver、minio、browserless/chrome、k8s.gcr.io の古いもの |

Longhorn の 1.12.x のイメージと 1.11.x の engine はもう無い（2026-10-21・10-26 の Longhorn の片付けで消えた）。v1.11.2 の instance-manager（chirico・oeilvert・pablo）と share-manager（chirico）だけ残っている。

### 7.2 判断

- **kubelet の GC には任せない。** 既定の `imageGCHighThresholdPercent` 85 を超えないと動かない（oeilvert 以外は 9〜41%）。oeilvert で動くと、使っていないイメージを戻しの材料も含めて消し、それでも Docker のぶん 80% まで下がらない。本番の KubeletConfiguration（`assets/kubelet/<ノード>/config.yaml`）は `imageMinimumGCAge` 以外の GC の設定を持たず、`imageMaximumGCAge` も 0（無効）
- **`crictl rmi --prune` も使わない。** 戻しの材料まで消える
- **`crictl rmi` で、一覧の「消す」を名前で 1 つずつ消す。** 残すのは次のもの
  - 今のマニフェストが参照するもの（16）と、今の sandbox の `registry.k8s.io/pause:3.10.1`（pinned）
  - **戻しの材料**: 今動いているもののリポジトリごとに、使っていない版のうちいちばん新しい 1 つ（例: kube-* v1.36.5、etcd 3.6.15、CoreDNS v1.13.2、cnidaria v0.1.1、MetalLB v0.14.5、metrics-server v0.7.2、kube-state-metrics v2.19.0、Prometheus v3.11.3、operator v0.90.1、Alertmanager v0.32.1、Grafana 13.0.1-security-01、node-exporter v1.11.1、natsumi v0.1.51 など 36）
  - kube-dns-autoscaler の戻しの材料 `registry.k8s.io/cluster-proportional-autoscaler-amd64:1.7.1`、作業の道具が使う `busybox:1.36`（`tools/npcheck.yaml`・`docs/longhorn/tools/pvcheck.sh`）
  - Longhorn は版を下げられないので、v1.11.2 の instance-manager・share-manager は戻しの材料にならず消す
- 同じイメージに 2 つのタグがあるものが 2 つある（duchamp の `k8s.gcr.io/` と `registry.k8s.io/` の `cluster-proportional-autoscaler-amd64:1.7.1`、`bitnami/postgresql` と `bitnamilegacy/postgresql` の `16.3.0-debian-12-r4`）。`crictl rmi <タグ>` は CRI の RemoveImage でイメージごと消すので、**残すタグと同じイメージの別のタグは消さない**（autoscaler の `k8s.gcr.io/` のタグは duchamp では残す）
- タグの無い `<none>` は `crictl images` の IMAGE ID で消す

### 7.3 消し方

1 台ずつ、消す直前に「使われていない」を取り直す（CRI の RemoveImage は使用中のイメージも消せてしまうため、一覧を古いまま使わない）。

```sh
C='sudo /opt/bin/crictl --runtime-endpoint unix:///run/containerd/containerd.sock --image-endpoint unix:///run/containerd/containerd.sock'
# 1. その時点の images と ps -a を取り、results/cleanup-survey/images-plan.tsv の「消す」と突き合わせて、
#    今も使われていない「消す」のタグ（と <none> の ID）だけを /tmp/k8u-rmi-<ノード>.txt にする
# 2. 1 つずつ消す（使用中なら crictl が失敗するのではなく消してしまうので、1 の突き合わせが要）
ssh -n yuanying@<IP> "for i in \$(cat /tmp/k8u-rmi-<ノード>.txt); do $C rmi \$i >/dev/null && echo removed \$i || echo FAIL \$i; done"
```

- control-plane（rasp01〜03）は `ubuntu@`、`unset LC_ALL` してから入る
- 順: rasp01 → rasp02 → rasp03 → braque → pablo → duchamp → oeilvert → chirico（小さいものから。chirico は 213 タグで最後）
- 消した後の空きは containerd の GC（content と snapshot）が非同期に回収する。`df` の変化は数分おいて見る

### 7.4 確かめ

- `crictl ps` の Running のコンテナの数が消す前と同じ。`kubectl --context fraction get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded` が増えない
- `crictl images` に「残す」のタグが揃っている（kube-* v1.37.1・v1.36.5、etcd 3.7.3-0・3.6.15-0、`pause:3.10.1` など）
- `df -h /` の使用率が下がる

### 7.5 戻し方

消したイメージは registry から pull し直せる（`crictl pull <タグ>`。今のマニフェストのものは Pod が要るときに kubelet が pull する）。registry から消えたもの（`<none>`、`registry.fraction.jp` の古いタグなど）は戻せないが、どのマニフェストも参照していない。

### 7.6 `/opt/bin` の古いバイナリ（追加の候補）

porkadot の `install kubelet` は版つきのファイルを置き、リンクを付け替える。古い版が残っている。

| ノード | `/opt/bin` | 1 つ前より古い版 |
|---|---|---|
| rasp01〜03 | 1.5G | 23 個、1.2G（kubelet・kubectl v1.29.8〜v1.35.9、crictl v1.28.0〜v1.35.0、etcdctl 3.5.12・3.5.34） |
| braque・duchamp・pablo | 2.8G | 43 個、2.5G（kubelet・kubectl v1.23.5〜、crictl v1.23.0〜、etcdctl v3.4.13・3.5.5 など） |
| chirico | 2.6G | 39 個、2.2G |
| oeilvert | 3.8G | 57 個、3.4G（crictl v1.22.0〜） |

判断: 消してよい。**残すのは今の版（`kubelet-v1.37.1`・`kubectl-v1.37.1`・`crictl-v1.37.0`・`etcdctl-3.7.3`・`etcdutl-3.7.3`）と 1 つ前（`v1.36.5`・`crictl-v1.36.0`・`3.6.15`）とリンク**。消し方は `sudo rm /opt/bin/kubelet-v1.29.8 …`（名前を並べる。glob は使わない）。確かめは `readlink /opt/bin/{kubelet,kubectl,crictl,etcdctl,etcdutl}` が今の版のままで、`systemctl is-active kubelet`。戻すときは porkadot の前の版の `install kubelet --node` が版つきのファイルを置き直す。

## 8. replicas 0 の ReplicaSet

- replicas 0 の ReplicaSet は 135 個。Deployment ごとに数えると、どれも `revisionHistoryLimit`（既定 10。MetalLB の controller は 3）以内（最も多いのは `longhorn-ui`・`longhorn-driver-deployer`・`kube-scheduler`・`kube-controller-manager`・`coredns` の 10 で、上限ちょうど）
- metrics-server の `75bf97fcc9`（v0.7.2、2026-10-15）は `kubectl rollout undo` の材料（`runbook-metrics-server-0.9.md` の戻し）
- 持ち主の Deployment が無い ReplicaSet は 0

**判断: 消さない。** Deployment コントローラが `revisionHistoryLimit` を超えた古いものから消す。手で消す必要は無い。

## 9. private・k8s-env・このリポジトリの古いマニフェスト

**リポジトリは変えていない。** 以下は案。

### 9.1 k8s-manifests-fraction-private（`3df954d`）

| パス | 削除済みの API | 本番に同じ名前のリソース | 案 |
|---|---|---|---|
| `proxy/`（`proxy.yaml` の Ingress が `extensions/v1beta1`） | あり | **無い**（名前空間 `proxy` が無い） | ディレクトリごと消す。k8s-manifests-fraction 側の `proxy/` は `2d22dd4` で消えている |
| `metrics-server/`（`src.yaml` の APIService が `apiregistration.k8s.io/v1beta1`、2018 年） | あり | 同じ名前のものは**ある**が、2026-10-15 に fleet-infra の `infrastructure/metrics-server/`（`c9373b6`、v0.9.0 は `7529112`）から入ったもの | ディレクトリごと消す（持ち主は fleet-infra。private を apply すると v1beta1 の APIService で失敗し、古い Deployment で上書きしかねない） |
| `shja-base/templates/chrome-deployment.yaml`・`shja-cronjob.yaml`（`extensions/v1beta1` の Deployment） | あり | 無い（`shja-base/kustomization.yaml` で既にコメントアウト）。`shja-configmap.yaml`・`chrome-service.yaml` もコメントアウトで、本番に無い | 4 ファイルを消し、kustomization のコメントの行も消す。`shja-base` の nginx（Service・ConfigMap・Deployment・Ingress）は**本番の `shja` に今ある**（2022-09-19、client-side apply）ので残す |
| `mailserver/`（Ingress は `networking.k8s.io/v1`） | 無い | 無い（名前空間 `mail` が無い） | ディレクトリごと消す（ユーザー確認。設定ファイルに秘密情報を含むので、消す前に控えが要るかを聞く） |
| `homegallery/` | 無い | 無い（名前空間 `homegallery` が 10-27 時点で無い） | ディレクトリごと消す（ユーザー確認） |
| `000-namespaces/` の `grafana`・`hackmd`・`mailserver`（`mail`）・`prometheus`・`proxy` | — | 無い | その 5 ファイルと kustomization の行を消す |

### 9.2 k8s-env（`60b5333`）

| パス | 削除済みの API | 本番 | 案 |
|---|---|---|---|
| `templates/templates/manifests/rook-operator/operator.yaml`（CRD が `apiextensions.k8s.io/v1beta1`）・`rook/cluster.yaml`、`rook/` のほかのファイル | あり | rook は無い（§5.1 の RBAC の名残だけ）。`templates/` は jinja の雛形で、`render.py` で外部の `configs` から作る 2018 年の仕組み | `templates/templates/manifests/rook*` を消す。`templates/` 全体（coredns・hackmd・owncloud・prometheus・docker-gitlab）も今の本番の持ち主ではないので、ユーザーが要らないと言えば `templates/` ごと消す |
| `charts/mailserver/templates/ingress.yaml`（`extensions/v1beta1`） | あり | 無い | `charts/mailserver/` を消す。`charts/` のほかの chart（elasticsearch・kibana・glusterfs・heketi など）も 2018 年のもので本番に無い。ユーザーが要らないと言えばまとめて消す |

k8s-env のこれ以外のファイルに、削除済みの API は無い（`apiVersion:` を grep した）。

### 9.3 このリポジトリ（k8s-manifests-fraction、`27d29a9`）

- `000-namespaces/kustomization.yaml` は `bases: ../base/000-namespaces` を指すが、`base`（k8s-base の submodule）は `2d22dd4` で外れたので、`kubectl kustomize 000-namespaces` は失敗する。並ぶ名前空間のうち `ddns`・`mail`（`mailserver.yaml`）・`proxy` は本番に無い。`aphrael`・`comics`・`sites` は本番にあるが fleet-infra の `infrastructure/namespace/ns.yaml` にもある（fleet-infra が持ち主）。案: `000-namespaces/` を消す（ユーザー確認）
- `minecraft*/` は本番にある（触らない）

### 9.4 fleet-infra（§2 の帰結）

- `ml-study` を使わないと決まった場合: `apps/ml-study/` と `secrets/prod/docker-registry-key.enc.yaml` の ml-study の分、`apps/natsumi/{aki,myao}/kustomization.yaml` のコメントの `::151・::152（ml-study）`
- `kagent` を prod から外すと決まった場合: `infrastructure/namespace/ns.yaml` から test だけの置き場へ

## 10. 作業端末とリポジトリ

**一覧だけ。消すのは coordinator が承認の後に。**

### 10.1 マージ済みのローカルのブランチ

このタスクの作業単位のブランチ（`notes/workers/*.md` の「ブランチ」114 個）のうち、元の clone にローカルのブランチとして残っているのは 110 本（`cleanup-survey` を含む）。手元の origin が古いため `--merged` に出ないもの（k8s-env の `raspi-containerd-io`、porkadot-dev の `dev-cnidaria-0-1-2`）も、リモートの既定のブランチのマージコミットの親であることを確かめた。**110 本ともマージ済み**。消すのは `cleanup-survey` を除く 109 本（`cleanup-survey` はこの PR のマージの後）。

| clone | 本数 | 例 |
|---|---|---|
| k8s-manifests-fraction | 48（と `cleanup-survey`） | `runbook-stage-*`・`stage-*-k8s-1-3*`・`longhorn-*`・`metallb-0-16-prod`・`cnidaria-0-1-2-prod` |
| porkadot-dev/porkadot | 35 | `porkadot-k8s-1-3*`・`bump-0-3*` |
| porkadot-dev | 18 | `dev-porkadot-0-3*-rc`・`dev-*` |
| fleet-infra | 6 | `fleet-longhorn-1-12-1`・`fleet-longhorn-1-13-0`・`fleet-kube-prometheus`・`fleet-metrics-server` など |
| cnidaria-cni | 1 | `cnidaria-no-plugin-copy` |
| k8s-env | 1 | `raspi-containerd-io` |

消し方: 各 clone で fetch してから `git branch -d <名前>`（`-D` は使わない。`-d` が拒否したら止める）。fleet-infra には別タスクのブランチ・worktree（`fraction-vuln-tracking`・`natsumi-dev`）もあるので、このタスクの 6 本だけ。元の clone のメインの checkout は k8s-manifests-fraction が `7716d7b`（origin/master `27d29a9` より古い）など、fast-forward も合わせて行う。

### 10.2 タスクディレクトリの `worktrees/`

| パス | 種類 | HEAD | 未コミット | 大きさ | 案 |
|---|---|---|---|---|---|
| `porkadot-v0-37-4` | 独立の clone | `d0d84c9`（タグ `v0.37.4`） | なし | 9.2M | 消してよい（今の本番の render は 0.37.5 で、cnidaria v0.1.2 の戻しの材料は 0.37.4。cnidaria の戻しの心配が無くなるまで残すなら残す） |
| `porkadot-v0-37-5` | 独立の clone | `aacfba7`（タグ `v0.37.5`） | なし | 9.4M | 今の本番の版。containerd の config v4（`setup-containerd`）で使うので、それが終わるまで残す |
| `cleanup-survey` | worktree | この作業単位 | — | — | この PR のマージの後に `~/bin/herdr-task-worktree remove` |

### 10.3 メインの checkout の `backup/`（1.7G、`.gitignore` で除外）

| ファイル | 何の前か | 案 |
|---|---|---|
| `etcd-2026-10-27T10:39:31+00:00.db` | cnidaria v0.1.2 の前（いちばん新しい） | **残す** |
| `etcd-2026-10-23T22:17:11+00:00.db` | 段 8 の前（K8s 1.36・etcd 3.6 の最後） | **残す**（etcd 3.6 へ戻す唯一の材料） |
| `etcd-2026-10-23T22:27:19`・`22:41:23` | 段 8 の途中・最後 | 消してよい |
| `etcd-2026-10-25T02:08:18`・`10-25T10:16:55`・`10-26T07:02:07` | MetalLB・autoscaler・CoreDNS の seccomp の前 | 消してよい（10-27 で足りる） |
| `etcd-2026-10-19`〜`10-21`（12 個） | 段 1〜7 の前と途中 | 消してよい（その版にはもう戻さない） |
| `etcd-2026-10-14`・`10-16`（5 個）、`node11{1,2,3}-var-lib-etcd-20261016*.tar.gz`、`cp-replacement-20261016.sha256` | 前のタスク（control-plane の Pi への入れ替え） | ユーザー判断（このタスクの外） |
| `etcd-2024-05-12*.db`・`etcd-2024-05-19.tar.gz` | このタスクの外 | ユーザー判断 |
| `backup.tmp/etcd-2022-09-24*.db`（未追跡のディレクトリ） | このタスクの外 | ユーザー判断 |

etcd のスナップショットは Secret を含むので、消すときは `rm` で（ほかの場所へ写さない）。

### 10.4 `/tmp` に残る作業のもの

| パス | 中身 | 案 |
|---|---|---|
| `/tmp/fraction-coredns-0373`・`/tmp/fraction-coredns-0374all` | k8s-manifests-fraction の clone（origin は消えた worktree `runbook-coredns-seccomp`）。0374all は未コミットの変更 13（render の差分） | 消してよい（CoreDNS の seccomp は #63・#64 で入った） |
| `/tmp/rnv-sim` | porkadot の clone（origin は消えた worktree `porkadot-renovate-coredns`）。未コミット 2 | 消してよい（porkadot#71 で入った） |
| `/tmp/lh-oldim-probe.sh`・`lh-oldim-fns.sh`・`lh-oldim-pr.md` | Longhorn の古い instance-manager の片付け（#66）の道具 | 消してよい |
| `/tmp/fleet-base`・`/tmp/fleet-d3dee13`・`/tmp/fleet-e133a38` | fleet-infra の展開（10-27） | 持ち主が分からない（別のタスクかもしれない）。coordinator が確かめてから |

`/tmp/fleet-infra-kp` など記録に出てくるほかの `/tmp` のもの（`k8u-*-admin-token` を含む）は既に無い。`/tmp` のほかのもの（`fraction-agents-*`、`release-plan-*`、`hunkgit-*` など数千）は別のタスク・テストのもので対象外。

## 11. ほかの記録からの候補

| 候補 | 出どころ | 状態 | 判断 |
|---|---|---|---|
| 各台の `/root/k8u-stage-c/`（33〜70M） | 段 C（`results/stage-c/summary.md`） | 8 台ともある。containerd 2.2.1 の version 3 の config などの控え | **containerd の config v4 が終わるまで残す**（計画 §5.7 の 2.2.1 への戻しの材料）。その後に消す |
| worker 5 台の `/etc/containerd/config.toml.porkadot-bak.2026101{7,8}` | 段 C | ある | 同上 |
| worker 4 台の `/root/cluster-dns.service.bak-2026101{7,8}`、braque の `/root/zfs.prom.bak-20261026`、control-plane の `/root/netplan.bak.20261016*` | 段 C・前のタスク | ある | 消してよい（4 KB〜8 KB。ユーザー判断で残してもよい） |
| oeilvert の `/var/lib/kubelet/cpu_manager_state.bak-k8u8` | 段 8（`results/stage-8/workers.md`） | ある | 消してよい |
| apt の `rc` の `containerd` 2.2.1（8 台）、oeilvert の `docker.io` 29.1.3 | 段 C（runbook-stage-c §8.7） | `rc`（設定だけ残る） | 段 C の方針どおり purge しない（戻しの手順が `rc` を前提にしているかを確かめてから。containerd の config v4 の後に判断） |
| worker 4 台の `/etc/apt/sources.list.d/docker.list.disabled-2026101{7,8}` と `/usr/share/keyrings/docker.gpg` | 段 C（runbook §8.5） | ある。今の Docker のリポジトリは `docker.sources`・`docker.asc` | 消してよい |
| worker の `dpkg -l` の `rc` の 251〜391 個 | OS の更新（前のタスク） | ある | このタスクの外（OS） |
| Longhorn の `replica-auto-balance` を `least-effort` に戻すか | 段 C | `disabled` のまま | 片付けではない。ユーザーに聞く項目として残す |
| fraction-auditor が default などで強い権限を持つ（`notes/backlog.md` 2026-10-25） | backlog | 出どころは fleet-infra の `infrastructure/commons/rbac-base`（Role `developer` = `*`、RoleBinding `developer` → `kube-system/infra-auditor`）。default・fs・minecraft・minecraft2・minecraft3・sites の 6 つ（`infrastructure/commons/rbac-<名前空間>`）と、マニフェストの無い ml-study の 1 つ（§2） | 意図した設定と読める（fleet-infra の管理下）。片付けの対象にしない。権限を絞るかはユーザーの判断（backlog に戻す） |
| `results/metrics-server-0.9/summary.md` §5、`results/metallb-0.16/summary.md` §7、`runbook-kube-prometheus-92.md` §10 の申し送り | 各 results | §5・§7・§8・§9 に入れた | — |

### 11.1 控えの置き場所（戻し方の共通）

- Kubernetes のリソースの yaml（Secret を除く）: タスクディレクトリの `notes/cleanup/`（`$NOTES`）。名前空間・CRD・CSIDriver・RBAC・ConfigMap・Job・PriorityClass。どれも秘密情報を含まない（ConfigMap `core-dns` はゾーンのファイル、`kube-keepalived` は設定）
- ノードで消すもの（イメージ・バイナリ）は控えない（registry と porkadot から取り直せる）。消したタグの一覧を `notes/cleanup/rmi-<ノード>.txt` に残す

### 11.2 Secret の控え

cilium の 3 つ（と、消すと決まった場合の sealed-secrets の鍵）は鍵を含む。`notes/` やリポジトリには置かない。控えが要るなら、メインの checkout の `backup/`（`.gitignore` 済み、`umask 077`）に `kubectl-admin get secret … -o yaml` を置くか、控えずに消すかをユーザーが決める。

## 12. 消す順と、まとめて承認を取る単位（案）

| 順 | 単位 | 中身 | 承認の形 | 戻し |
|---|---|---|---|---|
| 1 | **A. 本番の Kubernetes のリソース** | §2 の名前空間 `istio-system`・`metallb`（`ml-study` は答えしだい）、§3 の NFD の CRD 3 つ、§4 の rook の CSIDriver 2 つ、§5 の ClusterRoleBinding 33 個（§5.1 の 32 と `pod-checkpointer`）・ClusterRole 33 個（§5.1 の 27、参照されない 4 つ、`kubevirt.io:operator`、`pod-checkpointer`）・kube-system の名残 10 個・PriorityClass 1 個・ノードの kubevirt のラベルと注釈、cilium の Secret 3 つ（§11.2 の答えしだい）。§6 は既定では入れない | 一覧（この文書の §2〜§5）で 1 回。`infra-admin` の短命トークンで、控えを取ってから消す。消す前に各節の「消す前に確かめる」を流し、想定と違えば止める | 控えの yaml を apply |
| 2 | **B. ノード** | §7 のイメージ（8 台、約 48 GiB）、§7.6 の `/opt/bin` の古いバイナリ、§11 の小さい控え（`cluster-dns.service.bak` など）と oeilvert の `cpu_manager_state.bak-k8u8`、古い Docker の apt のファイル | 一覧で 1 回。1 台ずつ、消す直前に使用中のものを取り直す。SSH はサンドボックスの外（現在地の 2026-10-19 の承認の範囲）か中 | イメージは pull し直し、バイナリは porkadot の `install kubelet` |
| 3 | **C. リポジトリのマニフェスト** | §9.1 private（`proxy/`・`metrics-server/`・`shja-base` の 4 ファイル・`mailserver/`・`homegallery/`・`000-namespaces` の 5 つ）、§9.2 k8s-env（`templates/` の rook、`charts/mailserver`、広げるなら `templates/`・`charts/` 全体）、§9.3 このリポジトリの `000-namespaces/`、§9.4 fleet-infra（`ml-study`・`kagent` の答えしだい） | リポジトリごとの PR。PR のマージがそのまま承認 | git の revert |
| 4 | **D. 作業端末** | §10.1 のブランチ 109 本、§10.2 の `porkadot-v0-37-4`、§10.3 の etcd のスナップショット（残す 2 つ以外のこのタスクのもの 17 個）、§10.4 の `/tmp` のもの | coordinator が一覧を示して 1 回 | ブランチはリモートにマージ済み。スナップショットは戻せない（残す 2 つで足りる） |

- A を先にする（B のイメージの片付けは、A で消すものと関係が無いので、順は入れ替えてよい）
- §2 の `ml-study`・`kagent`、§5.2 の sealed-secrets の鍵、§9 の「ユーザー確認」の行、§10.3 の「ユーザー判断」の行は、承認の前にユーザーに答えてもらう
- B の後に containerd の config v4（STATE.md の 2c）。§11 の段 C の控えと `porkadot-v0-37-5` は config v4 が終わってから片付ける（そのときの単位 B'・D'）
- oeilvert の Docker（`/var/lib/docker` 236G、使用率 82%）は、この片付けとは別にユーザーに知らせる（DiskPressure まで 3%）
