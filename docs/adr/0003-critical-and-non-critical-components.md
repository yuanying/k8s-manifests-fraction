# 0003. 関連コンポーネントは、クリティカルなものだけ段に合わせて最小の経路で上げ、残りは K8s を最新にしてから上げる

- Date: 2026-10-18
- Status: Accepted

## Context

K8s の段を 1 マイナーずつ進める間（[0001](0001-one-minor-version-per-stage.md)）、本番には K8s と一緒に動く部品が多い。etcd・CoreDNS・kube-proxy など porkadot が配るもの、自作の CNI（cnidaria）、ストレージの Longhorn、containerd、fleet-infra で入れる kube-prometheus-stack・metrics-server、porkadot の addon の MetalLB などである。

すべてを段ごとに追うと、段ごとの変更が増えて問題の切り分けが難しくなり、更新の回数も増える。一方で、古いままにすると K8s の段そのものが止まるものもある。

## Decision

**クリティカルでないものは、K8s を最新に上げ切ってから最新版へ上げる。クリティカルなものだけ、K8s の段に合わせて最小の更新経路で上げる。**

**クリティカル** = 次のどれかに当たるもの。

- その K8s のマイナーでサポート外になる、または動かなくなる
- その K8s で削除された API を使っている
- その製品自身が段階的な更新しか許していない

当てはめた結果（根拠は `docs/k8s-upgrade/plan.md` §3、`survey-2026-10.md`）:

| 分類 | コンポーネント | 扱い |
|---|---|---|
| クリティカル | control-plane・kubelet・kube-proxy | porkadot の各版（0001） |
| クリティカル | etcd | 1 マイナーずつ、前の系列の新しいパッチからしか上げられない（3.6 へは 3.5.26 以上、3.7 へは 3.6.11 以上）。**kubeadm の既定の版を追わず**、1.30 で 3.5 の最新パッチ、1.34 で 3.6、1.37 で 3.7 にしてマイナー更新を 2 回に抑えた（plan §2） |
| クリティカル | CoreDNS | porkadot が配る。段ごとに kubeadm の既定に合わせ、最後は CoreDNS の最新（[0006](0006-addon-images-from-registry-k8s-io.md)、[0007](0007-corefile-shaped-like-kubeadm.md)） |
| クリティカル | cnidaria | 動かなければ Pod の通信が止まる。各段で dev と本番で確かめ、直しが要れば cnidaria-cni の PR。標準の CNI plugins はノードの構築側（porkadot の `install kubelet`）が置き、cnidaria はコピーしない（cnidaria-cni の ADR 0001、`docs/cni/cnidaria-no-plugin-copy.md`） |
| クリティカル | Longhorn | 製品が 1 マイナーずつしか許さず、v1.13 は K8s 1.34 以上を要求する（[0004](0004-longhorn-upgrade-path.md)） |
| クリティカル | containerd・runc | 2.2 は 1.37 の推奨表に無く、upstream の EoL が近い（[0005](0005-containerd-io-2-3-from-docker-apt.md)） |
| 非クリティカル | MetalLB、kube-prometheus-stack、metrics-server、kube-dns-autoscaler、kubelet-serving-cert-approver、CNI plugins、gated | 段 8 の後に 1 つずつ最新へ（plan §8） |

- サポート表で「その K8s では未検証」程度なら非クリティカルとし、実際に動かなくなる・API が消えると分かったらクリティカルに格上げする。
- 分類は根拠とともに計画に書き、計画の承認を経てから本番に入る。
- 非クリティカルなものも、上げるときは dev → runbook → 本番の順にする。CRD を持つものは、更新の後に CRD の `status.storedVersions` を確かめる。
- **kube-prometheus-stack の更新では、本番の Prometheus のデータを残すことを条件にしない**（2026-10-25）。PVC の作り直しが要る場合は許す。Prometheus のデータは家庭用のクラスタの監視の履歴で、失っても困らない。

## Consequences

- K8s の段で動かしたのは、K8s 本体・etcd・CoreDNS・cnidaria の確認・Longhorn・containerd だけで済んだ。1.29〜1.37 で削除された API を使うものは無く（1.32 の `flowcontrol.apiserver.k8s.io/v1beta3` の削除は、etcd に残った古い保存の版の書き直しで済んだ）、API の削除を理由に格上げしたものは無かった。
- 非クリティカルなものは、古い版のまま新しい K8s の上で数日動いた（例: metrics-server v0.7.2 を 1.37 で）。サポート表で上限が表明されていないことを根拠にした。
- etcd の版を kubeadm と変えたので、etcd の版を決めるのは porkadot の各版の責任になった。次の etcd のマイナー（3.8）でも、上げられる前の版の条件を先に読む必要がある。
- Prometheus のデータを条件にしないので、kube-prometheus-stack の runbook は PVC の作り直しを、Pod が PVC の中身のために起動しないときの手順として持てた（`docs/k8s-upgrade/runbook-kube-prometheus-92.md` §5.2）。実際の更新でデータは残った。
