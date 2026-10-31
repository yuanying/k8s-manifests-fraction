# 0007. CoreDNS の Corefile は kubeadm と同じ形にそろえる

- Date: 2026-10-23
- Status: Accepted

## Context

CoreDNS の Corefile は porkadot の `coredns.yaml.erb` が作る。本番の `porkadot.yaml` には、`cluster.local`（`dns_domain`）のほかに追加のドメイン `fraction.cluster`（additional_domains）がある。

kubeadm は新しい版で Corefile を改善していて、K8s 1.37 の段（段 8、porkadot 0.37.0。porkadot#61）でそれを取り込むことにした（`docs/k8s-upgrade/plan.md` §2、`survey-2026-10.md` §6）。

- `cache` に `disable success cluster.local` と `disable denial cluster.local` を足す（クラスタ内の名前の答えを cache しない。Service や Pod の変化がすぐ見える）
- `forward` に `max_concurrent 1000` を足す

取り込むときに、2 つの点を決める必要があった。`disable` を additional_domains の `fraction.cluster` にも広げるか。`max_concurrent 1000` も入れるか。

## Decision

**Corefile は kubeadm と同じ形にそろえ、段 8 の変更を小さく保つ。**

- `cache` の `disable success` / `disable denial` は **`dns_domain`（`cluster.local`）だけ**に付ける。additional_domains の `fraction.cluster` には広げない。
- `forward` の `max_concurrent 1000` は入れない。
- CoreDNS の版は段 8 では v1.14.7 のままにした（v1.15 は [0006](0006-addon-images-from-registry-k8s-io.md)）。

## Consequences

- `fraction.cluster` の名前の答えは、これまでどおり 30 秒 cache される。`cluster.local` の名前は cache されなくなった。
- Corefile が kubeadm と同じ形なので、次に kubeadm の Corefile が変わったときも、差分をそのまま読める（corefile-migration の plugin の表と比べられる）。
- Corefile を変えると、CoreDNS は Pod を作り直さず `reload` で読み直す。ノードの resolv.conf に kube-dns 自身が入っているので、reload の直後に `loop` plugin の FATAL で 1 回再起動しうる（`docs/k8s-upgrade/runbook-stage-8.md` §2.10）。1 回の再起動は許容し、CrashLoop なら止める。resolv.conf の件は残課題として Wiki の TODO にある。
- `fraction.cluster` も cache しないようにしたい、`max_concurrent` を入れたい、となったら、kubeadm の形から外れる理由とともに新しい ADR で決める。
