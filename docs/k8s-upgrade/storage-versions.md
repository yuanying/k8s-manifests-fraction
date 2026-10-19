# etcd に保存されたオブジェクトの版（storage version）

本番 `fraction` の etcd に、今の kube-apiserver が書く版と違う版で保存されたままのオブジェクトがあるかを調べた結果と、調べ方。
書き直しの手順は各段の手順書に書く（段 3 は `runbook-stage-3.md` §2.5）。計画の扱いは `plan.md` §6.4。

## 1. なぜ見るか

kube-apiserver は、オブジェクトを書くときに、そのリソースの storage の版に直して etcd に保存する。読むときは、保存された版から変換する。保存された版は、そのオブジェクトがもう一度書かれるまで変わらない。

- 古い版で保存されたオブジェクトは、kube-apiserver がその版を scheme から外すと読めなくなる（K8s の文書「Upgrade A Cluster」の「Switch your cluster's storage API version」: 「Failure to do this will eventually result in resources that are no longer decodable or usable by the Kubernetes API server. For each affected object, fetch it using the latest supported API and then write it back also using the latest supported API.」）
- 段 3（1.32）で `flowcontrol.apiserver.k8s.io/v1beta3` が提供されなくなる。提供をやめても、kube-apiserver は v1.37.1 まで、flowcontrol の v1beta1〜v1beta3 と discovery の v1beta1 を scheme に登録したまま（`pkg/apis/flowcontrol/install/install.go`、`pkg/apis/discovery/install/install.go`）なので、今の古いオブジェクトは 1.37 でも読める。壊れはしないが、段 3 で今の storage の版に揃える

## 2. 2026-10-19 の結果（K8s v1.31.14）

2026-10-19 13:09Z に、§4 のスクリプトで 192.168.1.111 の etcd を prefix ごとに読んだ（読み取りだけ）。64 の prefix、2149 個のキー。値の形は protobuf 1747、JSON 402（CRD、APIService、カスタムリソース）で、暗号化されたもの（`k8s:enc:`）は無い。

### 2.1 古い版で保存された組み込みのオブジェクト（32 個）

| prefix | 保存された版 | 今の storage の版 | 数 |
|---|---|---|---|
| `/registry/flowschemas/` | `flowcontrol.apiserver.k8s.io/v1beta3` | `flowcontrol.apiserver.k8s.io/v1` | 13（全部） |
| `/registry/prioritylevelconfigurations/` | `flowcontrol.apiserver.k8s.io/v1beta3` | `flowcontrol.apiserver.k8s.io/v1` | 8（全部） |
| `/registry/endpointslices/` | `discovery.k8s.io/v1beta1` | `discovery.k8s.io/v1` | 11（82 のうち） |

FlowSchema（13）: `catch-all`、`endpoint-controller`、`exempt`、`global-default`、`kube-controller-manager`、`kube-scheduler`、`kube-system-service-accounts`、`probes`、`service-accounts`、`system-leader-election`、`system-node-high`、`system-nodes`、`workload-leader-election`。

PriorityLevelConfiguration（8）: `catch-all`、`exempt`、`global-default`、`leader-election`、`node-high`、`system`、`workload-high`、`workload-low`。

- どれも kube-apiserver が作って保守する既定のもの（`apf.kubernetes.io/autoupdate-spec: "true"`）。kube-apiserver は、spec が自分の考える値と違うときだけ書き直すので、1.29 より前（v1beta3 が storage の版だったころ）に書かれたまま残っている
- `metadata.generation` は `system-leader-election` が 8、PriorityLevelConfiguration の 6 つが 2、ほかは 1

EndpointSlice（11）:

| EndpointSlice | Service | 管理 | endpoint の数 | 作られた日 |
|---|---|---|---|---|
| `default/nginx-1-xhkzq` | `nginx-1` | endpointslice-controller | 0 | 2022-09-26 |
| `homegallery/cg-w8dmk` | `cg` | endpointslice-controller | 0 | 2022-08-28 |
| `kube-system/kube-prometheus-kubelet-96ktq` | `kube-prometheus-kubelet` | endpointslicemirroring-controller | 8 | 2023-04-08 |
| `kube-system/tiller-deploy-jgh7c` | `tiller-deploy` | endpointslice-controller | 0 | 2020-10-30 |
| `longhorn-system/longhorn-conversion-webhook-5nz8j` | `longhorn-conversion-webhook` | endpointslice-controller | 0 | 2022-09-19 |
| `longhorn-system/pvc-c9f006ad-fe37-48c0-9a4a-c3f7831fbd46-5smvq` | `pvc-c9f006ad-…`（`homegallery/cg-data` のボリューム） | endpointslice-controller | 0 | 2025-01-31 |
| `minecraft/bds-mc4cm` | `bds` | endpointslice-controller | 0 | 2023-07-28 |
| `minecraft/bds-v4-gz7rk` | `bds-v4` | endpointslice-controller | 0 | 2023-01-07 |
| `minecraft2/bds-m99wf` | `bds` | endpointslice-controller | 0 | 2022-04-17 |
| `minecraft3/bds-5ttnf` | `bds` | endpointslice-controller | 0 | 2022-04-17 |
| `nfsd/nfs-ntht8` | `nfs` | endpointslice-controller | 1 | 2022-09-19 |

- どれも controller が Service（または Endpoints）から作るもので、中身が変わらないので書き直されずに残っている。多くは endpoint が 0 の Service のもの

### 2.2 今の storage の版で保存されているもの

上の 3 つの prefix のほかは、すべて今の storage の版だった。

| 種類 | prefix | 保存された版 |
|---|---|---|
| core | `configmaps`、`events`、`limitranges`、`masterleases`（Endpoints）、`minions`（Node）、`namespaces`、`persistentvolumeclaims`、`persistentvolumes`、`pods`、`podtemplates`、`ranges`（RangeAllocation）、`secrets`、`serviceaccounts`、`services`（Service と Endpoints） | `v1` |
| apps | `controllerrevisions`、`daemonsets`、`deployments`、`replicasets`、`statefulsets` | `apps/v1` |
| batch | `cronjobs`、`jobs` | `batch/v1` |
| ほかの組み込み | `clusterrolebindings`、`clusterroles`、`rolebindings`、`roles`（rbac）、`csidrivers`、`csinodes`、`storageclasses`、`volumeattachments`（storage）、`ingress`、`ingressclasses`（networking）、`leases`（coordination）、`mutatingwebhookconfigurations`、`validatingwebhookconfigurations`（admissionregistration）、`poddisruptionbudgets`（policy）、`priorityclasses`（scheduling）、`endpointslices` の 71 個（discovery） | 各グループの `v1` |
| apiregistration | `apiregistration.k8s.io/apiservices`（31） | `apiregistration.k8s.io/v1` |
| CRD | `apiextensions.k8s.io/customresourcedefinitions`（47） | `apiextensions.k8s.io/v1beta1`（下の注） |
| カスタムリソース | `longhorn.io` の 13 種（238）、`monitoring.coreos.com` の 5 種（53）、`gate.unstable.cloud` の 3 種（31）、`metallb.io` の 2 種（2） | どれも CRD の storage の版（`longhorn.io/v1beta2`、`monitoring.coreos.com/v1`、`gate.unstable.cloud/v1alpha1`、`metallb.io/v1beta1`） |

- **CRD のオブジェクト自体は `apiextensions.k8s.io/v1beta1` で保存されるのが正しい。** kube-apiserver は CRD を、v1 の 1 オブジェクトの大きさの制限を避けるため、わざと v1beta1 で書く（`pkg/controlplane/apiserver/apiextensions.go` の `EncodeVersioner`。v1.31.14 と v1.37.1 で同じ。「prefer the more compact serialization (v1beta1) for storage until https://issue.k8s.io/82292 is resolved」）。apiregistration は同じ仕組みで v1 で書く（`aggregator.go`）
- 中身の無い CRD（MetalLB の `addresspools` など）は、カスタムリソースの prefix が無い

### 2.3 CRD の `status.storedVersions`

47 個の CRD すべてで、`status.storedVersions` は 1 つだけで、spec の `storage: true` の版と同じだった（`kubectl get crd` で読んだ）。

## 3. 今の storage の版の決まり方

kube-apiserver 1.31 は、組み込みのリソースを、そのグループの `SetVersionPriority` の先頭の版で保存する（`staging/src/k8s.io/apiserver/pkg/server/storage/resource_encoding_config.go` の `StorageEncodingFor`。1.31 からは emulation version の範囲で、互換の版より後に出た版を避ける `emulatedStorageVersion` を通る）。例外は `pkg/kubeapiserver/default_storage_factory_builder.go` の `ResourceEncodingOverrides` に書かれたもの（1.31 は `leasecandidates`、`ipaddresses`、`servicecidrs`、`clustertrustbundles`、`volumeattributesclasses`、`storagemigrations`。1.32 は `mutatingadmissionpolicies` などが増える）で、本番にはどれのオブジェクトも無い。

- 本番にオブジェクトのあるグループでは、`SetVersionPriority` の先頭は GA の `v1`（`flowcontrol` は v1、v1beta3、v1beta2、v1beta1 の順。`discovery` は v1、v1beta1 の順）。GA の版には「introduced」の印が無いので、emulation の扱いでも v1 になる
- これは discovery（`kubectl get --raw /apis`）の `preferredVersion` と同じなので、§4 のスクリプトは `preferredVersion` を期待値にしている。CRD のオブジェクト（§2.2 の注）だけは v1beta1 を期待値にする
- 段が進んで、新しい版が storage の版になるリソース（`ResourceEncodingOverrides` から外れるもの）にオブジェクトができたら、`preferredVersion` と storage の版がずれることがある。そのときはこの節を読み直す

## 4. 調べ方（`tools/`）

| ファイル | 中身 |
|---|---|
| `tools/storage-versions.sh` | control-plane の 1 台で `etcdctl get --keys-only` で prefix の一覧を取り、prefix ごとに `etcdctl get --prefix -w json` を読み、`etcd-typemeta.py` で版を取り出して、期待値と比べる。`kubectl get crd` と `kubectl get --raw /apis` も読む |
| `tools/etcd-typemeta.py` | `etcdctl get -w json` の出力から、キーごとに値の形（protobuf / json / encrypted）と apiVersion・kind だけを出す。値は出さない |

```sh
cd <このリポジトリの checkout>
docs/k8s-upgrade/tools/storage-versions.sh /tmp/storage-versions-$(date -u +%Y%m%dT%H%MZ)
# prefixes: 64, keys: 2149, OLD: 32, CRDs with more than one stored version: 0
```

- 読み取りだけ（`etcdctl get` と `kubectl get`）。SSH は `ubuntu@192.168.1.111`（`ETCD_HOST` で変えられる）、kubectl は `--context fraction`（`fraction-auditor` で足りる）。サンドボックスの中で流せる
- etcd の全範囲を 1 回で読むと Raspberry Pi の etcd に重いので、prefix ごとに 1 秒おいて読む（2026-10-19 は 1 分 36 秒）
- 出力: `summary.tsv`（prefix、値の形、版、kind、数、`ok` / `OLD`）、`old.tsv`（古い版のキーと期待値）、`crds.tsv`（CRD、storage の版、`storedVersions`、`ok` / `MULTI`）、`objects.tsv`（全キーの版）。**値は書かない**が、キーには Secret の名前も入るので、記録に写すのは prefix・キー・版だけにする
- `OLD: 0` と `CRDs with more than one stored version: 0` が、書き直しの後と各段の完了の確認の合格基準（各段の手順書 §6）

## 5. 書き直し方と、kube-storage-version-migrator を使わない理由

古い版のオブジェクトは、中身を変えずに読んで書き戻す（`kubectl get -o json | kubectl replace -f -`）。手順は `runbook-stage-3.md` §2.5。

- 中身が同じでも、kube-apiserver は新しい storage の版でエンコードし直したバイト列を、etcd の今の値と比べ、違えば書く（`staging/src/k8s.io/apiserver/pkg/storage/etcd3/store.go` の `GuaranteedUpdate` の `bytes.Equal(data, origState.data)`）。保存された版が違えばバイト列が違うので、書き直される
- kube-storage-version-migrator（out-of-tree）も K8s の StorageVersionMigration（`storagemigration.k8s.io`）も、オブジェクトごとに同じ「何も変えない更新」を流すもので、やることは同じである。使わない理由:
  - 対象が 32 個で、手で書き直して §4 で確かめれば済む
  - StorageVersionMigration は既定では無効（feature gate `StorageVersionMigrator` は 1.30〜1.34 が alpha、1.35・1.36 が beta で、どちらも `Default: false`。`pkg/features/kube_features.go`。1.37 で GA になり既定で有効。`CHANGELOG-1.37`）。使うには kube-apiserver と kube-controller-manager の feature gate と `--runtime-config` を porkadot で変えることになる
  - kube-storage-version-migrator は、新しい Deployment と CRD、cluster-admin に近い権限の ServiceAccount を本番に足すことになる
- 段 8（1.37）の後に、StorageVersionMigration を使うかは改めて考えてよい（そのときも対象を §4 で洗い出す）
