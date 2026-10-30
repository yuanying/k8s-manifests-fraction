# 0006. CoreDNS などの addon のイメージは registry.k8s.io に出たものを使う

- Date: 2026-10-26
- Status: Accepted

## Context

porkadot が配る addon のうち、CoreDNS と kube-dns-autoscaler は Kubernetes のプロジェクトの registry（`registry.k8s.io/coredns/coredns`、`registry.k8s.io/cpa/cluster-proportional-autoscaler`）のイメージを使っている。control-plane・kube-proxy・etcd のイメージも同じ registry から取る。

CoreDNS v1.15.0 は 2026-10-21 に GitHub でリリースされ、上流の `docker.io/coredns/coredns:1.15.0`（amd64・arm64 を含む）はすぐ出た。一方、registry.k8s.io には 2026-10-26 の時点で `coredns:v1.15.0` が無かった。registry.k8s.io の CoreDNS は、Kubernetes のプロジェクトが上流のリリースを取り込んでから出る。

K8s 1.37 の段（段 8）の後に CoreDNS を最新にする計画だった（[0003](0003-critical-and-non-critical-components.md)）。待つか、docker.io の上流のイメージに切り替えるかを決める必要があった。

## Decision

- **CoreDNS のイメージは registry.k8s.io に出たものを使い、docker.io の上流のイメージは使わない。** v1.15 は registry.k8s.io に出るまで待つ。
- 出るまでは v1.14.7 のまま動かし、「最新に上げる」という目標に対しては、上げなかった理由（registry.k8s.io に無い）を記録する。
- 待つ間に、版に依存しない直し（CoreDNS の seccomp を Pod の `seccompProfile: RuntimeDefault` にする。porkadot#69、0.37.4）を先に入れる。
- porkadot の Renovate は、CoreDNS を GitHub のリリースではなく registry.k8s.io のタグで追う（porkadot#71）。registry.k8s.io に出ていない版を「新しい版がある」と見ないようにする。

## Consequences

- addon のイメージの入手元が control-plane のイメージと同じ registry のままで、イメージを取る先が増えない。docker.io の匿名の pull の上限（`docs/longhorn/runbook-upgrade-1.12-1.13.md` §9.6）の影響も受けない。
- 最新の版を入れるのが、上流のリリースより遅れる。v1.15.0 は 2026-10-30 に registry.k8s.io にあることを確かめ、同じ日に porkadot 0.37.6 で本番に入れた（`docs/k8s-upgrade/results/0.37.6/`）。本番に入ったのは上流のリリースの 9 日後だった。
- registry.k8s.io に出たかどうかは、manifest の取得（`v1.15.0` が 200 か 404 か）で確かめる。
- 急ぎのセキュリティ修正が上流のイメージにだけ出ている、という場合の扱いは決めていない。そのときにあらためて判断する。
