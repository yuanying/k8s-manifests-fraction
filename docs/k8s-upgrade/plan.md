# K8s を 1.29 から 1.37 へ上げる計画

本番クラスタ `fraction` の Kubernetes を v1.29.8 から最新の安定版 v1.37.1 へ、1 マイナーずつ上げる計画と、各段の手順の骨子。
containerd も、K8s の段に入る前に 2.2.1 から 2.3 系へ上げる（2026-10-18 のユーザー指示「containerd は早い段階で上げておきたい」）。
根拠は同じディレクトリの `survey-2026-10.md`（現状調査）にある。各段の実施記録は、段ごとに `results/` に足していく。

**この計画は 2026-10-18 にユーザーの承認を得た。** 承認のときに決まったことは §9、本筋の段のほかに範囲に入れた作業をいつどこで行うかは §10 にある。本番への書き込みは、§9.1 の節目ごとに承認を取ってから行う。

## 1. 方針

- 1 段 = 1 マイナー。1.29 → 1.30 → … → 1.37。**前の段が本番で健全になるまで次の段に進まない。**
- 各段で porkadot の対応版（0.30.x 〜 0.37.x）を用意する。porkadot の PR → dev クラスタでの検証 → リリース → 本番、の順。dev の検証は本番より先に進めてよい。
- **containerd は段 1 の前（K8s 1.29 のまま）に 2.3 系へ上げる**（段 C。§5）。以後の段の dev の検証も本番も、最終形の containerd の上で行う。
- 関連コンポーネントは TASK の方針に従う。**クリティカルなものだけ段に合わせて最小の回数で上げ、それ以外は本番が 1.37 になってから最新へ上げる**（§3）。
- K8s の版は各段の最新パッチにする。段に入る前に `https://dl.k8s.io/release/stable-1.3X.txt` で確かめ直し、最終目標は着手時点の `stable.txt` のマイナー版の最新パッチとする。
- 本番への書き込み（porkadot の install、drain、Longhorn の更新、kubectl apply）は、`porkadot-dev/CLAUDE.md` の「本番クラスタ（fraction）の kubeconfig 運用」に従い、`infra-admin` の短命なトークンで行う。普段は `fraction-auditor` で読むだけにする。

## 2. 段の一覧

| 段 | porkadot | K8s | etcd | CoreDNS | containerd | 段の前後に挟むもの |
|---|---|---|---|---|---|---|
| 0 | 0.29.2 | v1.29.8 | 3.5.12-0 | v1.10.1 | 2.2.1（Ubuntu） | （今の状態） |
| **C** | 0.29.2 | v1.29.8 | 3.5.12-0 | v1.10.1 | **2.3.x（Docker の `containerd.io`）** | containerd と runc だけを 1 台ずつ置き換える（§5） |
| 1 | 0.30.x | v1.30.14 | **3.5.34-0**（パッチ更新） | v1.11.3 | 2.3.x | |
| 2 | 0.31.x | v1.31.14 | 3.5.34-0 | v1.11.3 | 2.3.x | |
| 3 | 0.32.x | v1.32.13 | 3.5.34-0 | v1.11.4 | 2.3.x | porkadot 0.32 から、`install kubelet` が iscsid を必要なときだけ再起動する（§4.4）。CNI plugins を v1.9.1 に（§3）。段の前に古い storage の版のオブジェクトを書き直す（§6.4） |
| 4 | 0.33.x | v1.33.13 | 3.5.34-0 | **v1.12.4** | 2.3.x | drain しない（§9.3）。storage version の書き直しは無い（1.33 が作る ServiceCIDR・IPAddress は v1beta1 で保存されるのが正しい。§7） |
| 5 | **0.34.1** | v1.34.12 | **3.6.15-0**（マイナー更新） | v1.12.4（段 4 のまま） | 2.3.x | drain しない（§9.3）。段の前に 3.5 の etcdutl で `check v2store`、`install kubernetes` の後に IPAddress を v1 に書き直す（§7）。**段の後に Longhorn 1.11.2 → 1.12.x（v1.12.1 以上）→ 1.13.x**（§4） |
| 6 | **0.35.0** | v1.35.9 | 3.6.15-0 | **v1.13.2** | 2.3.x | drain しない（§9.3）。段の前に全台が cgroup v2 であることを確かめる。storage version の書き直しは無い（§7） |
| 7 | **0.36.0** | v1.36.5 | 3.6.15-0 | **v1.14.7** | 2.3.x | drain しない（§9.3）。storage version の書き直しは無い。上げる前に StrictIPCIDRValidation に当たる値が無いことを読み取りで確かめる（§7） |
| 8 | **0.37.0** | v1.37.1 | **3.7.3-0**（マイナー更新） | v1.14.7（段 7 のまま。Corefile の `cache` に `disable success/denial cluster.local`） | 2.3.x | drain しない（§9.3）。kubelet の `--container-runtime-endpoint` を KubeletConfiguration の `containerRuntimeEndpoint` へ。storage version の書き直しは無い（1.37 の override を `tools/storage-versions.sh` に足した）。全台 3.7 の後の戻しは restore（§7）。段の後に非クリティカルなコンポーネント（CoreDNS v1.15 を含む）を最新へ（§8）、containerd の config を version 4 に（§10） |

- K8s・crictl・CoreDNS の版は porkadot 側の調査（`survey-2026-10.md` §6）の値。各段の前に最新パッチを確かめ直す。
- **etcd は kubeadm の既定値を追わない。** etcd は 3.6 へは 3.5.26 以上から、3.7 へは 3.6.11 以上からしか上げられない。kubeadm の既定（1.31〜1.33 の 3.5.24、1.36 の 3.6.8）はこの条件を満たさない。そこで 1.30 で 3.5 の最新パッチに上げて 1.31〜1.33 の間寝かせ、1.34 で 3.6 の最新パッチ、1.37 で 3.7 にする。マイナー更新は 2 回で済む。
- 1.37 の etcd は **3.7.3-0**（3.7 の最新パッチ。2026-10-22）にした（porkadot#61。kubeadm v1.37.1 の既定は 3.7.0-0。3.7.1 の watch の権限の直し（GHSA-xg4h-6gfc-h4m8）、3.7.3 の leader の `MsgApp` の順の回帰の直しを含む）。
- containerd の 2.3.x は、段 C の時点で Docker のリポジトリにある 2.3 系の最新パッチ（2026-10-18 は 2.3.6、runc 1.5.1 同梱）。段 1 以降の 2.3 のパッチは §5.8。
- **CoreDNS は段 1〜7 で kubeadm の既定に合わせ、最後は kubeadm の既定（v1.14.6）ではなく CoreDNS の最新にする**（ユーザー指示）。当時の記述（「段 8 で CoreDNS の最新（2026-10-18 は v1.14.7）にする」）→ v1.14.7 は段 7 で入れた。**段 8 は v1.14.7 のままで、kubeadm の Corefile の改善（`cache` の `disable success cluster.local` / `disable denial cluster.local`。`survey-2026-10.md` §6）だけを入れる**（2026-10-23 のユーザー判断。kubeadm と同じく `dns_domain` だけで、本番の additional_domains の `fraction.cluster` には広げない。`forward` の `max_concurrent 1000` は入れない）。最新の v1.15.0（2026-10-21）は registry.k8s.io にまだ無く、`cache`・`forward` の振る舞いも変わるので、**段 8 の後の非クリティカルの更新で上げる**（§8、porkadot#61）。
- **段 6 は v1.13.2 にする**（porkadot 0.35.0。kubeadm 1.35 の既定は v1.13.1）。v1.13.2 は v1.13 系の最新パッチで、`forward` の直し（coredns#7704 の接続エラーでの busy loop、#7622）を含む。v1.13.1 は Go 1.25.2 でビルドされ、その crypto/x509 が一部の SAN の dNSName を拒む（Go 1.25.3 で直った。porkadot#56 の `6d00ac7`）。Corefile は変えない（`runbook-stage-6.md` §3.3 の 13）
- **段 7 は v1.14.7 にする**（porkadot 0.36.0。kubeadm 1.36 の既定は v1.14.2）。v1.14.7 は v1.14 系の最新パッチで、v1.14.2 の後の Go の CVE の直しと、porkadot の Corefile が使う `forward`・`cache`・`kubernetes` の直しを含む（porkadot#58）。Corefile・RBAC・引数は変えない。段 8 で使う予定だった版を段 7 で入れたので、段 8 の CoreDNS は Corefile の改善だけにした（上の項目。2026-10-23 のユーザー判断）
- **ただし段 4 と段 5 は v1.12.4 にする**（2026-10-20 の coordinator の判断。段 4 の kubeadm の既定は v1.12.0、段 5 は v1.12.1）。v1.12.0 には v1.11.4 で入った coredns#6898（hostname のある Endpoint だけに PTR を作る）の回帰が残り、v1.12.1 で revert された（coredns#7194）。v1.12.1・v1.12.3 の修正も入り、Renovate がすぐ patch を出す。段 5 の kubeadm の既定（v1.12.1）より新しいので、段 5 では据え置く。本番の v1.11.4 では、hostname の無い Endpoint の Pod の IP の逆引きが NXDOMAIN になっている（2026-10-20 の読み取り。`runbook-stage-4.md` §2.2 の 23）

## 3. コンポーネントの分類

**クリティカル** = その K8s の版でサポート外になる・動かなくなる・削除された API を使う・製品自身が段階的な更新しか許さない、のどれかに当たるもの。

| コンポーネント | 今 | 分類 | 根拠 | 扱い |
|---|---|---|---|---|
| etcd | 3.5.12 | **クリティカル** | 1 マイナーずつ、かつ前の系列の新しいパッチからしか上げられない（[3.6 の zombie members](https://etcd.io/blog/2025/zombie_members_upgrade/)、[3.7 の upgrade](https://etcd.io/docs/v3.7/upgrades/upgrade_3_7/)）。3.7 は `--experimental-*` が残ると起動しない | porkadot の各版で上げる（§2） |
| control-plane・kube-proxy・kubelet | v1.29.8 | **クリティカル**（本体） | — | porkadot の各版 |
| CoreDNS | v1.10.1 | **クリティカル**（porkadot が配る） | porkadot の版が K8s のマイナーに対応する決まり。kubeadm の各版の既定に合わせる（段 4・5 は v1.12.4。§2） | porkadot の各版。段 7 で v1.14.7、段 8 で Corefile の改善だけ、v1.15 は段 8 の後（§2、§8） |
| cnidaria | v0.1.1 | **クリティカル**（自作 CNI） | 動かなくなれば Pod の通信が止まる。API の面では問題は見当たらない（GA の API だけ、client-go v0.37.0） | 各段で dev と本番で確かめる。直しが要れば cnidaria-cni の PR |
| Longhorn | v1.11.2 | **クリティカル** | 製品自身が 1 マイナーずつしか許さない。1.11.3・1.13.0 は K8s 1.34 以上を要求する。上限の K8s の表明はどの版にも無い（[release notes](https://github.com/longhorn/longhorn/releases)、[upgrade](https://longhorn.io/docs/1.13.0/deploy/upgrade/)） | 段 5 の後に 2 回（§4） |
| containerd・runc | 2.2.1・1.3.4 | **クリティカル** | 2.2 は 1.37 の推奨表に無い（1.37 は 2.4.0+ / 2.3.0+）。2.2 の upstream の EoL は 2026-11-06、runc 1.3 は 2026-10 末（[containerd RELEASES.md](https://github.com/containerd/containerd/blob/main/RELEASES.md)、runc 1.5.0 の release notes） | 段 C で 2.3 系へ（§5） |
| MetalLB | v0.14.5 | 非クリティカル | 使う API（`policy/v1`、CRD v1、admission v1）は 1.37 まで残る。0.16.0 の「1.36 で ASN の CRD 検証が通らない」修正（metallb#3034）は BGPPeer のオブジェクトの検証の問題で、本番は L2 だけ（BGPPeer 0 件） | 段 8 の後（porkadot の addon） |
| kube-prometheus-stack | 85.2.1 | 非クリティカル | chart の `kubeVersion` は `>=1.25.0-0`（最新の 92.10.1 も同じ）。同梱の kube-state-metrics v2.19.0 は client-go 1.35 でビルド（[互換表](https://github.com/kubernetes/kube-state-metrics#compatibility-matrix)）で、新しい資源の metrics が出ないだけ | 段 8 の後（fleet-infra） |
| metrics-server | v0.7.2 | 非クリティカル | 0.7.x は 1.27 以上、上限無し（[互換表](https://github.com/kubernetes-sigs/metrics-server#compatibility-matrix)）。0.8.x は 1.31+、0.9.x は 1.34+ | 段 8 の後（fleet-infra） |
| kube-dns-autoscaler | cpa-amd64 1.7.1 | 非クリティカル | core の API だけ。amd64 専用だが worker に載る | 段 8 の後（porkadot の addon。マルチアーキの `registry.k8s.io/cpa/cluster-proportional-autoscaler` へ） |
| kubelet-serving-cert-approver | `:main` | 非クリティカル | `certificates.k8s.io/v1` だけ | 据え置き（タグの固定は任意） |
| CNI plugins | v1.4.1 | 非クリティカル | K8s の版と連動しない | 段 3 で v1.9.1 にした（porkadot 0.32.0。cnidaria の init container が置く v1.9.1 と版をそろえるため。`runbook-stage-3.md` §8.11） |
| gated | v0.4.1 | 非クリティカル | 自作。Ingress v1 と自前の CRD だけ。`k8s.io/*` v0.36.4 | 必要なら 0.37 のライブラリで作り直す（任意） |
| nfsd、アプリ | — | 対象外 | K8s の API を自分で使わない | — |

API の削除は 1.32 の `flowcontrol.apiserver.k8s.io/v1beta3` だけで、本番は使っていない（`survey-2026-10.md` §4）。API の削除を理由にクリティカルになるものは無い。

## 4. Longhorn の経路

### 4.1 制約

| | v1.11.2（今） | v1.12.x | v1.13.x |
|---|---|---|---|
| 要求する K8s | ≥ 1.25 | ≥ 1.25（1.12.1 で一度 1.34 にした記述を 1.25 に戻した） | **≥ 1.34** |
| 上限 | 表明なし | 表明なし | 表明なし |
| どこから上げられるか | — | 1.11.x から | **1.12.x から**（飛ばし不可） |
| 保守 | 2026-09-12 で EOM | 2027-02-13 で EOM | 最新（2026-09-29） |
| iscsid の再起動の後に iSCSI を logout できない問題（§4.4） | **直っていない** | **v1.12.0 は直っていない。v1.12.1 から直っている** | v1.13.0 から直っている |

- **最新（1.13）に着くまでの更新は、どの経路でも 2 回**（1.11 → 1.12 → 1.13）。経路の違いは「いつ上げるか」だけである。
- 1.13 は K8s 1.34 以上でしか入らないので、1.13 へ上げるのは早くても段 5 の後になる。
- 1.11.3 も 1.34 以上を要求する。1.11 のパッチを上げる意味は無い（上げるなら 1.12 へ）。1.11.3 には §4.4 の直しが入っているが、段 5 までは入れられず、段 5 の後は 1.12 へ上げるので、挟まない（2026-10-19 のユーザーの判断）。
- **1.12 は v1.12.1 以上にする。** v1.12.0 には §4.4 の直しが入っていない。
- ダウングレードはできない。上げる前に Longhorn の system backup とボリュームのバックアップ（BackupTarget は braque の NFS）を取る。

### 4.2 選択肢

| 経路 | 1.29〜1.34 の Longhorn | 1.35〜1.37 の Longhorn | 更新の時期 | 良い点 | 悪い点 |
|---|---|---|---|---|---|
| **A（推奨）** | 1.11.2 | 1.13.x | 段 5（1.34）の後に 1.12 → 1.13 を続けて | 各段の Longhorn が「その版が出た時期の K8s」に近い。1.11（2026-01）は 1.34 まで、1.13（2026-09）は 1.35〜1.37 を受け持つ。Longhorn の作業が 1 か所にまとまる | 段 5 の後に Longhorn の更新が 2 回続く。1.34 に着くまで EOM の 1.11 で走る |
| B | 1.12.x | 1.13.x | 段 1 の前に 1.12、段 5 の後に 1.13 | EOM の 1.11 をすぐ離れる。2 回の更新が時期で分かれる | 1.12（2026-06）を 1.29〜1.32 という古い K8s で動かすことになる。段 C と時期が近く、containerd と Longhorn の変化が重なる |
| C | 1.11.2 | 1.11.2 | 段 8（1.37）の後に 1.12 → 1.13 | K8s の段の途中で Longhorn に触らない | EOM の 1.11 を、それより後に出た 1.35〜1.37 で動かす |

推奨は **A**。どれも公式の要件（下限）は満たすが、A がもっとも「その Longhorn が出た時期に upstream がテストしていたはずの K8s」と組み合わさる。

### 4.3 経路 A の表

| 時点 | K8s | Longhorn |
|---|---|---|
| 今 〜 段 5 の完了 | 1.29 → 1.34 | 1.11.2 |
| 段 5 の後（1 回目） | 1.34 | **1.11.2 → 1.12.x**（その時点の 1.12 の最新パッチ。**v1.12.1 以上**。今は 1.12.1） |
| 段 5 の後（2 回目） | 1.34 | **1.12.x → 1.13.x**（その時点の 1.13 の最新パッチ。v1.13.0 以上。今は 1.13.0） |
| 段 6 〜 段 8 | 1.35 → 1.37 | 1.13.x |

- 1 回目と 2 回目のそれぞれで、manager → エンジン（V1 は live upgrade）→ instance-manager の入れ替わり → ボリュームが全部 healthy、まで確かめてから次へ進む。
- **§4.4 の直しが効くのは、新しいエンジンイメージで起動したエンジンだけである。** manager を上げただけでは、古いエンジンイメージのまま動いているボリュームは直らない。各ボリュームのエンジンを新しいエンジンイメージへ更新する（アタッチされたものは live upgrade、detached のものはアタッチの前の更新）まで、§4.4 の守ることを続ける。live upgrade したエンジンが iscsid の PID を引き直すかは dev で確かめていないので、dev の Longhorn の経路の検証（§6.6）で、エンジンの更新の後に iscsid を再起動して detach し、セッションが残らないことを見る。
- **戻すもの**: 1 回目（v1.12.1 以上）の後、全ボリュームのエンジンが新しいエンジンイメージになったことを確かめたら、Longhorn のノード 4 台の `/etc/apt/apt.conf.d/51fraction-hold-open-iscsi` を消して、open-iscsi を unattended-upgrades の対象に戻す（§4.4）。手順は fleet-infra の `infrastructure/longhorn/CLAUDE.md` と Wiki（`wiki/topics/自宅クラスター.md` の「Longhorn の運用メモ」）に従う。
- 1.13 は `longhorn-global-manager` の Deployment（3 replica）を足し、CSI のサイドカーを専用の ServiceAccount に変える。fleet-infra の `update-longhorn.sh` で生成した manifest の diff でこれを確かめる。
- fleet-infra の変更（`MANIFEST_VER` と `longhorn.yaml`、README の互換表）は fleet-infra の PR で出す。
- **CRD の storage の版**: 各回の更新の後、Longhorn の CRD の `status.storedVersions` を見る（`tools/storage-versions.sh` の `crds.tsv`）。古い版が残っていたら、その CRD のカスタムリソースを全部、今の storage の版で書き直し（`kubectl get <種類> -A -o json | kubectl replace -f -`。中身は変えない）、`tools/storage-versions.sh` でその prefix の `OLD` が 0 になったことを確かめてから、`kubectl patch crd <名前> --subresource=status --type=merge -p '{"status":{"storedVersions":["<今の版>"]}}'` で古い版を外す（K8s の文書「Versions in CustomResourceDefinitions」の「Upgrade existing objects to a new stored version」と同じ形）。`storedVersions` に残った版は CRD の `spec.versions` から消せないので、次の更新がその版を消す前に片付ける。Longhorn が自分で移すものは、更新の後に残っていないことを確かめるだけでよい

### 4.4 iscsid の再起動と古い iSCSI のセッション（v1.11.2 の問題）

段 2 の本番で、drain の後のノードに消えた instance-manager の IP への iSCSI のセッションが残り、そのノードに同じボリュームをアタッチするたびにエンジンが落ちて faulted を繰り返した（`results/stage-2/iscsi-stale-sessions.md`）。dev で原因を突き止めた（porkadot-dev の `docs/longhorn/iscsi-stale-sessions.md`）。

- **原因は drain ではなく、iscsid の再起動である。** ボリュームがアタッチされたまま iscsid が再起動すると、v1.11.2 のエンジンは起動のときに覚えた iscsid の PID で `nsenter` して `iscsiadm` を流すので、以後 logout できない（`nsenter: cannot open /host/proc/<古い PID>/ns/mnt`）。その後の detach（drain を含む）のたびにセッションが残る。残ったまま iscsid がもう一度再起動すると、iscsid がそのセッションを引き取ってつなぎ直し続け、logout も断る（`32 - target likely not connected`）。この状態でそのノードに同じボリュームがアタッチされると、エンジンが落ちる。
- 本番で iscsid を再起動したのは porkadot の `install kubelet`（`install-pkgs.sh.erb` が毎回 `systemctl restart iscsid.service` を流す）。段 1 の `install kubelet` が 1 回目、段 2 の drain で残り、段 2 の `install kubelet` が 2 回目だった。drain だけでは残らない（dev の 2 本・11 本の drain で 0 本）。
- **Longhorn の直し**: go-common-libs の `b3e1f44`（`nsenter` が古い PID の名前空間で失敗したら iscsid の PID を引き直してやり直す）。longhorn-engine の go.mod で、v1.11.2 と **v1.12.0 には入っておらず**、v1.11.3・v1.12.1・v1.13.0 には入っている（[longhorn#13334](https://github.com/longhorn/longhorn/issues/13334)、[longhorn#10544](https://github.com/longhorn/longhorn/issues/10544)）。
- **守ること（Longhorn のエンジンが直った版になるまで）: Longhorn の iSCSI のセッションが残ったノードで、iscsid を再起動しない。** drain する台は、drain の後・`install kubelet` の前にノードで `sudo iscsiadm -m session` を見て、Longhorn の iqn（`iqn.2019-10.io.longhorn:`）のセッションが残っていれば logout する（drain した台のセッションは全部古いもの。dev で 11 本が 1 秒）。`install kubelet` の後にも `No active sessions.` を確かめ、ノードを再起動せずに uncordon する。drain しない台は、`install kubelet` が iscsid を再起動しない（porkadot 0.32 以降で、`initiatorname.iscsi` が render の結果と同じ）ことを前提に、`install kubelet` の前に古いセッション（今の instance-manager の IP でない portal へのもの）が無いことを、前と後で iscsid の PID とセッションが変わらないことを確かめる（`runbook-stage-3.md` §5.3、§8.10）。iscsid を再起動する porkadot（0.31 以前）で流すときは、drain しない台でも `install kubelet` の前に Longhorn のセッションが無いことを確かめる（あれば drain する）。コマンドと、logout できなくなっていたときの消し方（drain してから iscsid に諦めさせる。再起動は要らない）は porkadot-dev の記録の §4。段ごとの手順は各段の runbook に書く（段 3 から）。
- **porkadot の直し**: `install kubelet` が iscsid を、`initiatorname.iscsi` の中身が変わったときだけ再起動するようにする（porkadot の PR、0.32 に入れる）。0.32 からは、`install kubelet` では iscsid がふつうは再起動しない。ただし上の確認は、Longhorn のエンジンが直るまで続ける（iscsid はほかの理由でも再起動しうる。下）。
- **unattended-upgrades による open-iscsi の更新。** 本番の 8 台とも unattended-upgrades が有効で、open-iscsi は Package-Blacklist に無かった（2026-10-19 の読み取り。全台 open-iscsi 2.1.9-3ubuntu5.5、control-plane の apt の履歴に 5.4 → 5.5 の更新がある）。open-iscsi の更新が自動で入ると、postinst で iscsid が再起動しうる。longhorn#10544 の報告でも apt-daily-upgrade で iscsid が再起動していた。Longhorn のエンジンが直るまでは、これも 1 回目のきっかけになり、次の drain で古いセッションが残る。**対策（2026-10-19 ユーザー承認）**: Longhorn のノード（pablo、duchamp、chirico、oeilvert）に `/etc/apt/apt.conf.d/51fraction-hold-open-iscsi`（`Unattended-Upgrade::Package-Blacklist` に `open-iscsi`・`libopeniscsiusr`）を置いた。open-iscsi は段の作業の中で手で上げる。**Longhorn を v1.12.1 以上にし、全ボリュームのエンジンを新しいイメージにしたら、このファイルを消して戻す**（ユーザー指示。§4.3）。

## 5. containerd の更新（段 C）

### 5.1 目標の版: 2.3 系（LTS）の最新パッチ

| | 2.3（推奨） | 2.4 |
|---|---|---|
| 状態 | **LTS**（2026-04-30 〜 2028-04-30） | Active（2026-09-16 〜 2027-05-16） |
| 推奨表 | 1.36 と 1.37 の両方に入る | 1.37 に入る（1.36 には無い） |
| 2.2 から | **直接上げられる**（連続するマイナー） | 直接は不可（2.2 → 2.4 は飛ばし。2.3 を経る） |
| 次の更新 | 次の LTS へ LTS どうしで直接上げられる | 2027-05 までに 2.5 へ |
| 2026-10-18 の最新 | upstream 2.3.7（runc 1.5.2）、Docker の `containerd.io` 2.3.6（runc 1.5.1） | upstream・`containerd.io` とも 2.4.2 |
| config | `config default` は version 4。version 3 も読み、起動時に移行する | 同じ |

推奨は **2.3**。1 回の更新で最終目標の 1.37 の推奨表に入り、保守期間も 1.37 の寿命より長い。2.4 は 2.3 を経る 2 回の更新になり、保守期間は短い。

K8s 1.29〜1.35 と 2.3 の組み合わせについて:

- 推奨表の 1.32〜1.35 の行に 2.3 は載っておらず、1.29〜1.31 は行そのものが無い（containerd は K8s のサポート中の版だけを載せる）。今の 2.2.1 も 1.29 では表の外で、2026-10-16（control-plane）・2026-10-18（worker）からこの状態で動いている。
- kubelet 1.29〜1.37 も containerd 2.2・2.3 も CRI は **v1** だけを使う（v1alpha2 は containerd 2.0 で消え、kubelet は 1.26 から v1 だけ）。2.3.0 の CRI の変更は機能の追加で、Breaking は NRI の plugin 名の規則だけ。
- **dev で、K8s 1.29 の上に 2.3 を入れて段 C を通し、その上で段 1 以降の検証を続ける。** 表の外の組み合わせは、dev の各段の検証で確かめる。

### 5.2 入手元: Docker の apt リポジトリの `containerd.io` を 2.3 系に固定する

| 入手元 | 判断 | 理由 |
|---|---|---|
| Ubuntu の archive | 使えない | 24.04 は 2.2.1、26.04 でも 2.2.2。2.3 は無い |
| **Docker の apt リポジトリ（`containerd.io`）** | **推奨** | noble の amd64・arm64 とも 2.3.3〜2.3.6 がある。deb なので apt で入れ替え・戻しができ、runc も同梱される。apt の pin で 2.3 系に固定できる |
| upstream の tarball | 予備 | 最新パッチ（2.3.7）が先に出る。ただし apt の管理の外になり、unit と runc を自分で置き、Ubuntu の `containerd` パッケージとの衝突も自分で避けることになる |

`containerd.io` を使うときに守ること（前タスクの OS 更新で分かったことを含む）:

- **apt の pin で 2.3 系に固定する**（例: `/etc/apt/preferences.d/containerd-io` に `Package: containerd.io`、`Pin: version 2.3.*`、`Pin-Priority: 1001`）。固定しないと `apt full-upgrade` で 2.4 系に上がる（前タスクでは Docker のリポジトリが残っていて 2.4.2 が入りかけた）。
- Docker のリポジトリは noble 用を新しく足す（worker の `docker.list.disabled-*` は jammy の頃のもの。oeilvert の `third-party.sources` は jammy で無効）。
- **`/etc/containerd/config.toml` は手元の版を残す。** `containerd.io` は `disabled_plugins = ["cri"]` の config を conffile として持つ。入れるときに `-o Dpkg::Options::=--force-confold` を付け、入れた後に先頭が `version = 3` で `SystemdCgroup = true` が残っていることを確かめる。
- Ubuntu の `containerd` と `runc` は `containerd.io` に置き換わる（`Conflicts/Replaces`）。runc は 1.3.4 から同梱の 1.5.x に上がる。
- unattended-upgrades は Docker の origin を対象にしないので、`containerd.io` のセキュリティ更新は手で入れる。2.3 のパッチの追い方は §5.8。
- OS の更新（`do-release-upgrade`）は、Docker のリポジトリが有効だと「Please install all available updates」で拒否されることがある（前タスク）。OS の更新はこの計画の範囲外だが、将来 26.04 へ上げるときは、その手順でリポジトリの扱いを決める。

### 5.3 時期: 段 1 の前（K8s 1.29 のまま）

- 「早い段で上げる」というユーザーの指示に沿い、K8s の段と同じ時に containerd を変えないために、段 1 の前に単独の段として行う。
- 段 1 以降の dev の検証と本番が、最終形の containerd の上で行われる。containerd を後で変えると、それまでの段の検証をやり直すことになる。
- 段 C の間、K8s・porkadot・etcd は変えない。問題が出たときに containerd だけを疑えばよい。

### 5.4 porkadot との関係

- **porkadot に変更は要らない。** porkadot は containerd を入れず（`setup-containerd` は config を書くだけ）、0.29.2 の `setup-containerd` は containerd 2.3 と config version 4 に対応済み。
- **config は今の version 3 のまま使う。** 2.3 は version 3 を読んで起動時に移行する。2.2.1 は version 4 を読めないので、version 3 を残しておけば、戻すときに config に触らずに済む。
- `setup-containerd` は版の行のある config を作り直さないので、流しても version 3 のまま `SystemdCgroup` を確かめて containerd を再起動するだけ。段 C では流す必要は無い（流す場合は、このリポジトリの `assets/` を 0.29.2 で render し直してから。今の `assets/kubelet-default/setup-containerd.sh` は version 4 に対応する前の render）。
- version 4 の config に作り直す（`containerd config default` の 2.3 の既定値にする）のは、段 8 の後に行う（§10）。
- **porkadot の外で変更が要るもの**: k8s-env の `raspi/` の cloud-init は Ubuntu の `containerd` を入れる。control-plane を作り直すと 2.2 系に戻るので、Docker の `containerd.io` 2.3 系を pin して入れる形に直す（k8s-env の PR。段 C の前後。§10）。dev の VM の cloud-config（`porkadot-dev/tools/`）も同じく見直す。

### 5.5 手順の骨子（1 台ずつ）

前タスクの `docs/worker-os-upgrade/runbook.md` の §3.3（事前確認と drain）、§3.4（containerd の置き換え）、§3.7〜3.9（確認と uncordon）、§4.2（containerd の戻し方）を流用する。違いは、置き換える先が Ubuntu の `containerd` ではなく Docker の `containerd.io` 2.3 系であること、config を作り直さないこと、OS を上げないこと。

順番: chirico → duchamp → pablo → braque → oeilvert → 192.168.1.113 → .112 → .111。

- worker を先にし、control-plane（etcd）を後にする。oeilvert は MinIO の 4 つの replica があり、Docker の入れ替え（下）も伴うので worker の最後にする。braque は再起動で NFS と LAN の Service の経路が止まるので、時間帯を決めて行う。

1 台の流れ（本番の手順は `runbook-stage-c.md`。dev の段 C の結果で 2・3・8〜10 を直した）:

1. 事前確認（読み取り）: Node が Ready、`containerd --version`・`runc --version`、`/etc/containerd/config.toml` の控え、`apt-cache policy containerd containerd.io runc`、他のノードがすべて Ready で degraded のボリュームが無い。
2. 戻すための deb を控える: `apt-get download containerd=2.2.1-0ubuntu1~24.04.3 runc=1.3.4-0ubuntu1~24.04.1`（oeilvert は `docker.io` も）。**1 台目で Docker のリポジトリを足す前に、全台で控える。**
3. control-plane は drain しない（DaemonSet と static Pod だけ）。cordon し、controller-manager と scheduler の Pod が載っていれば、**1 つずつ消し、代わりが別の master で Running になってから次を消す**（dev では、同じ master に載っていた 2 つの scheduler をまとめて消し、scheduler が居なくなって代わりの Pod が Pending のままになった）。etcd のリーダーなら `move-leader` で移す（`etcd.env` の `ETCDCTL_ENDPOINTS` を外して流す）。worker はここでは drain しない（8 の前に行う）。
4. ✋ Docker の noble のリポジトリと鍵、`containerd.io` の pin を置き、`apt update`。`apt-cache policy containerd.io` の候補が 2.3 系の最新であること（2.4 ではないこと）を確かめる。
5. ✋ `apt-get install -o Dpkg::Options::=--force-confold containerd.io`。実行の前に、apt が削除するのが `containerd` と `runc` だけであることを読む（oeilvert は下の注意）。
6. ノードで確かめる: `containerd --version` が 2.3.x、`runc --version` が 1.5.x、`/etc/containerd/config.toml` が version 3 のまま（`containerd config dump` は読み込むときに移した version 4 を示す）、`containerd config dump` に `SystemdCgroup = true`、`journalctl -u containerd` に config の移行のエラーが無い（2.2.1 が作った sandbox への `failed to unmarshal sandbox spec` の error は想定内）、`sudo /opt/bin/crictl info` と `crictl images`（既存のイメージが残る）。
7. ✋ `sudo systemctl restart kubelet`。Node が Ready、CONTAINER-RUNTIME が `containerd://2.3.x`、DaemonSet の Pod が Running。control-plane では etcd 3/3 healthy と apiserver 3/3。dev では、5 と 7 で Pod は 1 つも再起動しなかった（drain していないノードでも）。
8. ✋ worker は、ここで cordon と drain（前タスクの §3.3。Longhorn の `concurrent-replica-rebuild-per-node-limit` を 0、`replica-auto-balance` を disabled、最後の replica を持つノードでは `node-drain-policy` を一時的に変え、MinIO・Prometheus を止める）。drain が要るのは次の再起動のためである（§9.3）。
9. ✋ ノードを再起動する（推奨）。古い shim を入れ替え、2.3 で起動から上がることを確かめる。braque の再起動は前タスクの §2.1.1 の注意（NFS、LAN の 10.254.0.0/16 の経路、ZFS の取り込み）に従う。control-plane の再起動の間は、VIP がところどころ失敗する（dev では 10〜35 秒の間に 2〜8 回）。
10. 再起動の後に 6・7 をもう一度確かめ、§6.3 のノードの項目（cnidaria の経路、Longhorn のボリューム、MetalLB の speaker）を見る。再起動の直後に cnidaria と speaker が数回 CrashLoopBackOff になることがある（kube-proxy の規則が入る前に API へ繋ごうとして落ちる。1 分ほどで戻る）。**そのノードの cnidaria の Pod が Ready になり、`verify-nodes.sh` が通ってから** uncordon する。
11. ✋ uncordon、Longhorn の設定を戻し、replica の再同期を待ってから次の 1 台へ。

**oeilvert**: Ubuntu の `docker.io`（devbox が使う）は `containerd (>= 1.2.6-0ubuntu1~)` に版つきで依存し、`containerd.io` では満たせない。`containerd.io` を入れると `docker.io` が外れるので、Docker の `docker-ce` と `docker-ce-cli`（`containerd.io (>= 2.1.5)` に依存）に移す。前タスクの §3.4.1（docker-ce から `docker.io` へ移した手順）の逆向きになる。devbox は Docker の再起動の間止まる。devbox の起動スクリプトが docker-ce で動くことを dev かその場で確かめる（§9.4）。

### 5.6 確認（段 C の完了条件）

- 8 台すべてで `containerd --version` が 2.3.x、`runc --version` が 1.5.x、`kubectl get nodes -o wide` の CONTAINER-RUNTIME が `containerd://2.3.x`
- `/etc/containerd/config.toml` が全台 version 3、`SystemdCgroup = true`
- `apt-cache policy containerd.io` の候補が 2.3 系（pin が効いている）
- §6.3 の健全性確認がすべて成り立つ（K8s の版は v1.29.8 のまま）
- oeilvert の devbox（`mosh.fraction.jp`）が動く

### 5.7 ロールバック

- その台で、控えた deb（または noble-updates）から Ubuntu の `containerd` 2.2.1 と `runc` 1.3.4 を入れ直す（`containerd.io` が外れる）。pin とリポジトリを外す。config は version 3 のままなので触らない。containerd と kubelet を再起動する。oeilvert は `docker.io` も入れ直す。
- **config を version 4 に作り直していた場合は、2.2.1 が読めないので、控えた version 3 の config を戻す。** 段 C で作り直さないのはこのためである。
- 前タスクでは、24.04 の上で containerd を戻す手順を dev で通してある（Pod が 1 回ずつ再起動し、MetalLB の speaker が 1 回 CrashLoopBackOff になってから戻った）。段 C の dev の検証でも、戻す手順を 1 台で通した（2026-10-18、porkadot-dev の `docs/k8s-upgrade/verification-stage-c.md`）。drain せずに戻し、Pod の再起動は 0 だった。

### 5.8 段 C の後の 2.3 のパッチ

- `containerd.io` は自動では上がらない。**K8s の段の合間に、2.3 系のパッチにセキュリティ修正があれば上げる**（それ以外のパッチは追わなくてよい）。手順は段 C と同じ 1 台ずつ（config・pin はそのまま、worker は drain する）。K8s の段と同じ時には上げない。
- Docker の `containerd.io` は upstream より遅れて出る（2026-10-18 は upstream の 2.3.7 に対して 2.3.6）。上げるかどうかは、upstream の release notes のセキュリティ修正と、Docker のリポジトリに出たかを見て決める。

## 6. K8s の各段の手順（骨子）

段ごとの runbook は、この骨子に段固有の注意（§7）を足して、段に入る前に `docs/k8s-upgrade/` に書く。

### 6.1 段に入る前

1. **porkadot の対応版がリリース済み**であること（PR で `bundle exec rake test` が通り、dev で検証済み、マージ・リリース済み）。dev の検証で見るものは §6.6。
2. 最新パッチを確かめ直す（`stable-1.3X.txt`、etcd、CoreDNS）。
3. ベースラインを取る（§6.5 の全項目）。前の段の結果と比べ、更新前からの問題を区別して記録する。
4. 作業端末の kubectl を、新しい版の ±1 に入るものにする。
5. **etcd のバックアップ**: `porkadot etcd backup --config ./porkadot.yaml`。保存先とサイズを記録する。
6. render: このリポジトリで新しい porkadot を使い、`porkadot render kubelet / etcd / bootstrap / kubernetes --config ./porkadot.yaml`（`render all` と `render certs` は使わない）。**render に使う secrets が本番と一致していることを確かめる**（前のタスクで devbox の `assets/secrets` が古かった）。
7. `assets/` の差分を確かめ、意図した変更（版の数字と、その段で porkadot が変えたもの）だけであることを見る。この差分を PR にし、段の記録とともに残す。前の段の `assets/` は git に残るので、それがロールバックの材料になる。

### 6.2 更新の順序

K8s の version skew policy では、kubelet が kube-apiserver より新しくてはいけない。porkadot の手順書（`skills/porkadot/references/operations.md`）は「`install kubelet` → `install kubernetes`」の順になっているが、それでは kubelet が先に新しくなる。**この計画では次の順にする**（porkadot の手順書も 0.30 の PR でこの順に直す）。

1. **control-plane のマニフェスト**: `porkadot install kubernetes --config ./porkadot.yaml --node 192.168.1.111`
   - bootstrap ノード（pablo）は worker なので `--node <control-plane>` が要る。
   - apiserver（DaemonSet）・controller-manager・scheduler・kube-proxy・addon（CoreDNS、MetalLB、cnidaria など）が新しくなる。
   - `kubectl rollout status` で apiserver の DaemonSet、KCM・scheduler の Deployment、kube-proxy の DaemonSet の完了を待つ。VIP が応答し続けることを見る。
   - kube-proxy は kubelet より 3 マイナーまで新しくてよいので、ここで先に上がってよい。
2. **control-plane の kubelet と etcd を 1 台ずつ**: `porkadot install kubelet --config ./porkadot.yaml --node <IP>`（.113 → .112 → .111。リーダーは最後にするか、`move-leader` で移してから）
   - `install kubelet` は etcd の static Pod のマニフェストも置くので、**etcd もここで 1 台ずつ変わる。**
   - 1 台ごとに、Node が Ready で新しい版になったこと、etcd が 3/3 healthy で raft index が追いついていること、apiserver 3/3 を確かめてから次へ進む。
3. **worker の kubelet を 1 台ずつ**: `porkadot install kubelet --config ./porkadot.yaml --node <ノード>`
   - 順は Longhorn の replica 1 のボリュームが少ない順を基本にし、oeilvert（MinIO の 4 つの replica）は最後にする。braque は NFS と Docker レジストリの保存先なので、他の worker が健全な状態で行う。
   - drain するかどうかは §9.3。drain する場合は、drain の後・`install kubelet` の前に古い iSCSI のセッションを見る（§4.4）。drain しない場合も、1 台ごとに Node が Ready、そのノードの Pod の再起動回数が増えていないこと、Longhorn のボリュームが healthy を確かめてから次へ進む。
   - **bootstrap が終わる前に全台へ `install kubelet` を流してはいけない**（porkadot の SKILL.md の注意）。更新では bootstrap を使わないので当たらないが、`install all` は使わない。

### 6.3 段の後の健全性確認（完了条件）

次がすべて成り立てば、その段は完了とする。更新前から問題のあったもの（`myao/myao`・`homegallery/cg-data` の detached など）は区別して記録する。

- `kubectl --context fraction get nodes -o wide` で 8 台が Ready、全台がその段の版、CONTAINER-RUNTIME が段 C で入れた版
- etcd 3/3 healthy（`etcdctl endpoint health / status`）、リーダーが居る、raft index が揃っている
- VIP `https://192.168.1.101:6443/livez` が `ok`、`/version` がその段の版
- apiserver 3/3、controller-manager と scheduler が Ready（別々の master に 1 つずつ）
- Running / Completed 以外の Pod が無い
- Longhorn: attached のボリュームが全部 healthy（detached 2 は以前から）、instance-manager が全部 running、その段の K8s が Longhorn の要件に入る
- cnidaria: 全ノードの cnidaria の Pod が Ready。ノードをまたいだ Pod 間通信（例: CoreDNS への問い合わせ、`text.fraction.jp` → hedgedoc → postgres）。NetworkPolicy（`hedgedoc/db-postgresql`）の規則がノードの nftables に入っていること
- MetalLB: LoadBalancer の Service がアドレスを持ち、応答する（gated の 192.168.1.200 / `::200` で数ホスト、`h2-sshd`、`natsumi-sshd`）
- braque の NFS が応答する（NFS の PV を使う Pod が Running、oeilvert のホストのマウント）
- metrics-server が応答する（`kubectl top nodes`）、Prometheus のスクレイプが落ちていない
- 新しい warning のイベント・ログ（kubelet、apiserver、kube-proxy、cnidaria、containerd）が増えていない
- storage の版: 古い版で保存された組み込みのオブジェクトが無い（`tools/storage-versions.sh` の `OLD: 0`）、CRD の `status.storedVersions` がどれも 1 つ（同じく `CRDs with more than one stored version: 0`）。§6.4
- NetworkPolicy: 2026-10-19 に hedgedoc が消え、本番の NetworkPolicy は 0 個になった。段 3 からは、一時的な名前空間に NetworkPolicy と Pod を作り、ノードをまたいで（v4・v6）許した通信が通り許していない通信が止まること、規則が `table inet cnidaria` に入り、消すと消えることを確かめる（✋。`tools/npcheck.sh`、`runbook-stage-3.md` §1.9）

### 6.4 ロールバック

| どこまで進んだか | 戻し方 |
|---|---|
| `install kubernetes` の後、kubelet はまだ前の版 | 前の段の porkadot と、前の段の commit の `assets/` で `install kubernetes` をやり直す。etcd はまだ変わっていない |
| control-plane の kubelet の一部まで（etcd が混在） | 戻す台を前の版の `assets/` で `install kubelet --node` し直す。etcd は混在中なら前のイメージに戻せる |
| etcd の**全メンバーが新しいマイナー版**になった後（段 5 と段 8） | イメージを戻すだけでは戻せない。段の前の `porkadot etcd backup` から restore するか、etcd の公式の downgrade 手順に従う。restore するとバックアップ後の変更は失われる。段 5 は porkadot 0.34.1 の `etcd restore`（etcdutl で戻し、revision を上げて compacted にし、control-plane を入れ替える）で、3.6.15 のまま 3.5 の backup を戻せることを dev で確かめた（`runbook-stage-5.md` §7.4）。段 8 も同じく、porkadot 0.37 の `etcd restore` で 3.7.3 のまま 3.6 の backup を戻せることを dev で確かめた（`runbook-stage-8.md` §7.4） |
| worker の kubelet の途中 | その台を前の版の `assets/` で `install kubelet --node` し直す |
| Longhorn の更新の後 | **戻せない**（ダウングレード不可）。manager の更新が失敗した場合だけ、前の版の manifest を apply して戻れる。データは更新前のバックアップから戻す |
| containerd（段 C） | §5.7 |

- apiserver を前のマイナーへ戻すのは、新しい版で書かれた storage の版があると危うい。逆に、古い版で保存されたままのオブジェクトは、kube-apiserver がその版を scheme から外すと読めなくなる。どちらも etcd に保存された版を読んで確かめる（`storage-versions.md`）。
  - **各段の `install kubernetes` の前に**、`tools/storage-versions.sh` で etcd を prefix ごとに読み（読み取りだけ）、今の kube-apiserver の storage の版と違う版で保存された組み込みのオブジェクト（`OLD`）を洗い出し、中身を変えずに書き直す（`kubectl get -o json | kubectl replace -f -`。段の開始の承認の範囲の ✋）。段 3 の前（2026-10-19）は FlowSchema 13・PriorityLevelConfiguration 8（`flowcontrol.apiserver.k8s.io/v1beta3`）と EndpointSlice 11（`discovery.k8s.io/v1beta1`）だった。手順は `runbook-stage-3.md` §2.5
  - 各段の完了の確認（§6.3）で、`OLD` が 0 で、CRD の `status.storedVersions` がどれも 1 つであることを見る
  - 組み込みのリソースの storage の版は、そのグループの `SetVersionPriority` の先頭の版（`ResourceEncodingOverrides` に書かれたものを除く）。本番にオブジェクトのあるグループは 1.31〜1.37 でどれも GA の `v1` で、discovery の `preferredVersion` と同じ。CRD のオブジェクト自体は、kube-apiserver がわざと `apiextensions.k8s.io/v1beta1` で書く（`storage-versions.md` §3）。段が進んで本番に新しい種類のオブジェクトができたら、その節を読み直す
  - kube-apiserver 1.37.1 まで、flowcontrol の v1beta1〜v1beta3 と discovery の v1beta1 は scheme に残っているので、書き直さなくても読めはする。それでも、段ごとに今の storage の版にそろえておく（2026-10-19 のユーザー指示）
  - StorageVersionMigration（`storagemigration.k8s.io`）は 1.36 まで既定で無効で、kube-storage-version-migrator は本番に部品を足すので使わない（`storage-versions.md` §5）
- 戻すと決める基準は runbook に書く（例: Node が Ready にならない、etcd が 2/3 を下回る、VIP が応答しない時間が一定を超える）。

### 6.5 ベースラインの取り方

段の前と後で同じものを取り、`results/` に残す。

- `kubectl get nodes -o wide`、`kubectl version`
- `etcdctl endpoint status -w table`、`endpoint health`（control-plane の 1 台で、sudo）
- `kubectl get pods -A`（Running / Completed 以外）、再起動回数の多い Pod
- Longhorn の `volumes.longhorn.io`（state・robustness・engine image）、`instancemanagers`、`engineimages`、`nodes.longhorn.io`、`replicas`（running 以外）
- LoadBalancer の Service、Ingress の到達、NFS の PV
- Prometheus の `apiserver_requested_deprecated_apis`（次の段で消える API が増えていないか）

### 6.6 dev クラスタでの検証

- dev（`porkadot-dev`、KVM の VM + Pi 5、context `test`）で、本番と同じ順序（段 C → 段 1 → …、各段は §6.2）で上げる。**段 C も dev で先に通す**（amd64 の VM と arm64 の Pi 5 の両方。戻す手順も 1 台で通す）。2026-10-18 の段 C の dev の検証は amd64 の VM 7 台だけで通した。arm64 の `containerd.io` を入れるのは本番の 192.168.1.113 が初めてになる（`runbook-stage-c.md` §8.4）。
- **dev の `addons.enabled` を本番に合わせる**（`cnidaria`、`coredns`、`metallb`、`kubelet-serving-cert-approver`）。dev は既定の flannel のままなので、そのままでは cnidaria を確かめられない。dev を cnidaria に移すのは dev の検証の単位で決める。
- Longhorn の経路（§4）も dev で先に通す。dev に Longhorn が無ければ、fleet-infra の test overlay で入れるかを dev の単位で決める。
- 見るもの: §6.3 の項目に加えて、kubelet の更新で Pod のコンテナが再起動しないか（drain の要否の判断材料。§9.3）、`kubectl get csr`（1.31 で kubelet の CSR の検査が厳しくなる）、etcd の 1 台ずつの更新の時間。
- porkadot の `assets/` の差分は `porkadot-dev/CLAUDE.md` の「refactoring01 の assets 回帰確認」に従って確かめる。

## 7. 段ごとの注意

| 段 | 注意 |
|---|---|
| C | containerd 2.2.1 → 2.3.x、runc 1.3.4 → 1.5.x（§5）。K8s は v1.29.8 のまま |
| 1（1.30） | etcd を 3.5.34 へ（パッチ更新）。porkadot の手順書を §6.2 の順に直す（0.30 の PR）。crictl を v1.30.1 へ（1.29 で上げ忘れていた）。本番の `porkadot.yaml` から `ETCD_UNSUPPORTED_ARCH` を消す（§10） |
| 2（1.31） | kubelet の serving 証明書の CSR が CN とノード名の一致を検査される。kubelet-serving-cert-approver で承認されることを `kubectl get csr` で見る。**本番で分かったこと**: 1.31 の kubelet はそのノードの全コンテナを 1 回再起動させる（kubernetes#124220。`runbook-stage-2.md` §8.4）ので、Longhorn のノードの worker 4 台は drain した（§9.3）。drain の後に古い iSCSI のセッションが残り、ボリュームが faulted を繰り返したので、drain した台は uncordon の前に再起動した（§4.4、`results/stage-2/iscsi-stale-sessions.md`） |
| 3（1.32） | `flowcontrol.apiserver.k8s.io/v1beta3` の削除。本番は使っていないことを確かめてある。段の前に Prometheus の `apiserver_requested_deprecated_apis` を見直す。**etcd に v1beta3 で保存されたままの FlowSchema・PriorityLevelConfiguration（と v1beta1 の EndpointSlice）を、`install kubernetes` の前に v1 で書き直す**（§6.4）。porkadot 0.32 から `install kubelet` が iscsid を必要なときだけ再起動する。**dev で 1.32 の kubelet ではコンテナが再起動しなかったので、drain しない**（§9.3。drain する台が出たら、drain の後・`install kubelet` の前に `iscsiadm -m session` を見て古いセッションを logout し、再起動はしない。§4.4）。CoreDNS v1.11.4、CNI plugins v1.9.1 |
| 4（1.33） | CoreDNS v1.12.4（§2。Corefile は変わらない）、crictl v1.33.0。etcd・CNI plugins は据え置き。**dev で 1.33 の kubelet でもコンテナが再起動せず、iscsid も再起動しなかったので、drain しない**（§9.3。porkadot-dev の `verification-0.33-rc.md`）。**1.33 の apiserver は ServiceCIDR と Service の ClusterIP ごとの IPAddress を作り、`networking.k8s.io/v1beta1` で保存する**（`ResourceEncodingOverrides`。1.32 に戻せるように）。これが 1.33 の正しい保存の形なので書き直さず、`tools/storage-versions.sh` の期待値にこの override を足した（`storage-versions.md` §3.1）。移行のときの Service ごとの `ClusterIPNotAllocated` の event は想定どおり。**v1 Endpoints API が非推奨になる**（削除はされない）。control-plane 自身が使うので `apiserver_requested_deprecated_apis` に `endpoints` が必ず出る。合格基準から外し、warning を出すクライアントを記録するだけにする（dev では longhorn-manager v1.11.2 だけ。`runbook-stage-4.md` §6、§8.15） |
| 5（1.34） | **etcd 3.6.15 へ（マイナー更新）**。porkadot 0.34.1。porkadot がフラグ名（`--experimental-initial-corrupt-check`、`--experimental-watch-progress-notify-interval`）を新しい名前に変える。static Pod から API オブジェクトを参照できなくなる（bootstrap の kube-proxy を porkadot で直した。稼働中の更新には効かない）。**段の後に Longhorn を 2 回上げる**（§4。1.12 は v1.12.1 以上。各ボリュームのエンジンの更新まで。その後に open-iscsi の unattended-upgrades の止めを戻す）。CoreDNS は段 4 の v1.12.4 のまま（§2）。**dev の結果**（porkadot-dev の `verification-0.34-rc.md`）: 1.34 の kubelet でもコンテナも iscsid も再起動せず、アタッチしたままのボリュームは healthy なので **drain しない**。`install kubernetes` で apiserver と KCM・scheduler を同時に上げると、1.34 の scheduler が 1.33 の apiserver の返さない `resource.k8s.io/v1` を待ってデッドロックしたので、**porkadot 0.34 は kube-apiserver を先に入れて rollout を待つ**（0.33 以前で 1.34 に上げない）。etcd は control-plane の `install kubelet` で 1 台ずつ 3.6 になり、混在中も 3/3 healthy。上げる前に **3.5 の etcdutl で `check v2store`**（3.6.15 の etcdutl には `check` が無い）。全台 3.6 の後は、**0.34.1 の `etcd restore`** で上げる前（3.5）の backup を戻せる（etcdutl で戻し、revision を max(10 億、今 − snapshot + 10 億) 上げて compacted にし、apiserver・KCM・scheduler を入れ替える。0.34.0 の固定の幅では 2 回目の restore で informer が止まった）。1.34 は `ipaddresses`・`servicecidrs` の v1beta1 の override を外す（v1.34.12 で確かめた）ので、**IPAddress を `install kubernetes` の後に v1 に書き直す**（段 3 の形。ServiceCIDR は 1.34 の apiserver が自分で v1 に書き直す）。手順は `runbook-stage-5.md` |
| 6（1.35） | **kubelet が cgroup v1 で起動しない**（KubeletConfiguration の `failCgroupV1` の既定が true。porkadot 0.35.0 は書かず既定のまま）。段の前に全台の `stat -fc %T /sys/fs/cgroup` が `cgroup2fs` であることを確かめる（2026-10-18 の調査と 2026-10-21 の読み取りで 8 台とも `cgroup2fs`）。kubelet の `--pod-infra-container-image` の削除（使っていない）。porkadot 0.35.0（K8s v1.35.9、crictl v1.35.0、**CoreDNS v1.13.2**、etcd 3.6.15-0 は据え置き）。**dev の結果**（porkadot-dev の `verification-0.35-rc.md`）: 1.35 の kubelet でもコンテナも iscsid も再起動せず、アタッチしたままの Longhorn v1.13.0 のボリュームは healthy なので **drain しない**。`install kubernetes` は 0.34 と同じく apiserver を先に入れて rollout を待ち、1.35 の scheduler・KCM が 1.34 の apiserver の返さない API を待つ形は無かった。CoreDNS は v1.13.2 に rollout し、名前の答えは上げる前と同じ。1.35 の apiserver は storage の版を変えない（`ResourceEncodingOverrides` は 1.34 のものに既定では出ない `scheduling/workloads` を足しただけ）ので、**storage version の書き直しは要らない**。etcd は変わらないが、control-plane の `install kubelet` で static Pod が作り直される。Longhorn v1.13.0 の要件（1.34 以上、上限の表明なし）に入る。手順は `runbook-stage-6.md` |
| 7（1.36） | `gitRepo` volume が無効になる（使っていない。2026-10-21 の読み取りで Pod とワークロードに 0）。kube-controller-manager のメトリクス `volume_operation_total_errors` が `volume_operation_errors_total` に改名（本番の PrometheusRule と ConfigMap は、どちらの名前も使っていない）。MetalLB の CRD を apply し直すことになるので、dev で `install kubernetes` が通ることを見る（通った）。porkadot 0.36.0（K8s v1.36.5、crictl v1.36.0、**CoreDNS v1.14.7**、etcd 3.6.15-0 は据え置き）。**dev の結果**（porkadot-dev の `verification-0.36-rc.md`）: 1.36 の kubelet でもコンテナも iscsid も再起動せず、アタッチしたままの Longhorn v1.13.0 のボリュームは healthy なので **drain しない**。`install kubernetes` は 0.34・0.35 と同じく apiserver を先に入れて rollout を待ち、1.36 の scheduler・KCM が 1.35 の apiserver の返さない API を待つ形は無かった。CoreDNS は v1.14.7 に rollout し（イメージの User は `65532:65532` で UID は同じ）、名前の答えは上げる前と同じ。1.36 の apiserver は本番にあるオブジェクトの storage の版を変えないので、**storage version の書き直しは要らない**。1.36 は MutatingAdmissionPolicy・…Binding を `v1beta1` で保存する（GA。`TODO: remove in 1.37`）ので、`tools/storage-versions.sh` の期待値に足した（本番にオブジェクトは無い。`storage-versions.md` §3.2）。**StrictIPCIDRValidation**（1.36 で既定 on）は、既存のオブジェクトの値を変えない update は通し、新しい正規形でない IP・CIDR を拒否する。本番を読み取りで `tools/ipcidr-scan.py` にかけ、**該当は 0**（2026-10-21、1,487 個の値）。1.36 では `UnknownVersionInteroperabilityProxy` が既定 on になる（段 7 では版がそろうので働かない。段 8 の apiserver の混在で見る）。Longhorn v1.13.0 の要件（1.34 以上、上限の表明なし）に入る。手順は `runbook-stage-7.md` |
| 8（1.37） | **etcd 3.7.3 へ（マイナー更新）**。`--experimental-*` が残っていると etcd が起動しないが、段 5 でフラグを直してあり、render の差分でも本番の動いている etcd でも無いことを確かめた。kube-proxy は `mode` の明示が無いと warning を出す（本番は `mode: iptables` を継ぐ）。containerd 2.3 は 1.37 の推奨表に入る。porkadot 0.37.0（K8s v1.37.1、crictl v1.37.0、etcd 3.7.3-0、**CoreDNS は v1.14.7 のまま Corefile の `cache` に `disable success/denial cluster.local`**、**kubelet の `--container-runtime-endpoint` を KubeletConfiguration の `containerRuntimeEndpoint` へ**）。**dev の結果**（porkadot-dev の `verification-0.37-rc.md`）: 1.37 の kubelet でもコンテナも iscsid も再起動せず、アタッチしたままの Longhorn v1.13.0 のボリュームは healthy なので **drain しない**。`install kubernetes` は apiserver を先に入れて rollout を待ち、1.37 の scheduler・KCM が 1.36 の apiserver の返さない API（DeviceTaintRules などの `v1`）を待つ形は無かった。1.36 と 1.37 の apiserver が並ぶ間も 503 は出ない（porkadot は `--peer-ca-file` を渡さないので peer proxy は働かない）。etcd は control-plane の `install kubelet` で 1 台ずつ 3.7.3 になり、混在中も 3/3 healthy、3 台目の後に cluster version 3.7.0。全台 3.7 の後は、**0.37 の `etcd restore`** で上げる前（3.6）の backup を戻せる（etcd は 3.7.3 のまま、API は約 2 分止まる）。CoreDNS は Pod を作り直さず `reload` で新しい Corefile を読み、クラスタ内の名前は cache されなくなった。ノードの resolv.conf に kube-dns が入っているので、reload のとき `loop` plugin が FATAL で 1 回再起動しうる。1.37 の KCM が ClusterTrustBundle を 1 つ作り、`certificates.k8s.io/v1beta1` で保存されるので、`tools/storage-versions.sh` に 1.37 の override（ClusterTrustBundle・PodCertificateRequest・StorageVersionMigration・DeviceTaintRule）を足した（書き直しは要らない。1.36 の MutatingAdmissionPolicy の override は外れる。`storage-versions.md` §3.2）。1.37 の etcdctl の `-w table` は罫線が Unicode。Longhorn v1.13.0 の要件（1.34 以上、上限の表明なし）に入る。**0.36 の `install kubernetes` だけで戻す形と、混在中に 3.6 に戻す形は dev で流していない**。手順は `runbook-stage-8.md` |

- **段 3 以降の drain の後**: Longhorn のエンジンが直った版になる（段 5 の後の Longhorn の更新と、各ボリュームのエンジンの更新）までは、drain した台で `install kubelet` の前に古い iSCSI のセッションを logout し、`install kubelet` の後に空であることを確かめる。drain しない台は、`install kubelet` の前に古いセッションが無いことと、前と後で iscsid の PID とセッションが変わらないことを確かめる（§4.4）。
- kubelet の `--container-runtime-endpoint` は 1.37 で DEPRECATED、削除は 1.38 に延期された。KubeletConfiguration の `containerRuntimeEndpoint` へ移すのは段 8 で行う（porkadot 0.37.0 に入った。§10）。
- 本番の `porkadot.yaml` の `etcd.extra_env: ETCD_UNSUPPORTED_ARCH=arm64` は警告が出るだけだが、段 1 で消す（§10）。

## 8. 最後に上げる非クリティカルなコンポーネント

本番が 1.37 で健全になってから、1 つずつ上げる。目標の版は 2026-10-18 時点の最新で、上げる時点で確かめ直す。

CRD を持つもの（kube-prometheus-stack の `monitoring.coreos.com`、MetalLB の `metallb.io`）は、更新の後に CRD の `status.storedVersions` を見て、古い版が残っていたら §4.3 の末尾と同じ形でカスタムリソースを書き直してから外す（§6.4）。

| コンポーネント | 今 | 目標 | 管理 | 注意 |
|---|---|---|---|---|
| kube-prometheus-stack | chart 85.2.1（operator v0.90.1） | **chart 92.13.1**（operator v0.94.1、Prometheus v3.15.0、Alertmanager v0.34.1、Grafana 13.2.4。fleet-infra#206、`675f543`） | fleet-infra `scripts/update-kube-prometheus.sh`（`infrastructure/kube-prometheus/prod/` を手で apply） | major が 7 つ上がる。各 major の upgrade notes は #206 の本文。CRD は served・storage の版が変わらない（`storedVersions` の書き直しは要らない）。#206 で control-plane の scrape を scrape class にし（期限の無い SA token の Secret を作らない）、`grafana-test` を作らない。CRD を server-side で先に、CRD 以外を client-side で流す。operator は admission の Secret が `kubernetes.io/tls` に作り直されるまで 2 回落ち、StatefulSet は 2 回 rollout する。dev で先に通した（2026-10-25、porkadot-dev の `verification-kube-prometheus-92.md`。85.2.1 への戻しも）。本番の Prometheus のデータは失ってもよい（2026-10-25 ユーザー方針）。porkadot を使わないので `assets/` は変わらない。手順は `runbook-kube-prometheus-92.md` |
| metrics-server | v0.7.2 | **v0.9.0**（fleet-infra#203、`baecff7`） | fleet-infra `scripts/update-metrics-server.sh`（`infrastructure/metrics-server/prod/` を手で apply） | 0.9.x は 1.34 以上。#203 で README の互換表も直した。Renovate の `allowedVersions: "<0.8.0"` の規則は fleet-infra#204 で外した。差は Deployment の image と Service の `appProtocol: https` だけ。dev で先に通した（2026-10-25、porkadot-dev の `verification-metrics-server-0.9.md`。`kubectl top` の途切れ 0）。porkadot を使わないので `assets/` は変わらない。手順は `runbook-metrics-server-0.9.md` |
| MetalLB | v0.14.5 | **v0.16.1**（porkadot 0.37.2、porkadot#65） | porkadot の addon | 0.16.0 で BGP の既定の backend が frr-k8s に、metrics が HTTPS に。本番は L2 だけ。残っている `addresspools` の CRD を片付ける。API の VIP を持つので dev で先に通す（2026-10-24、porkadot-dev の `verification-metallb-0.16.md`。途切れ 0）。v0.16.0 ではなく v0.16.1 にしたのは、v0.16.0 の controller の health probe の不具合（metallb#3062）のため。手順は `runbook-metallb-0.16.md` |
| CoreDNS | v1.14.7（seccomp は注釈だけで効いていない） | **seccomp を `RuntimeDefault` に（v1.14.7 のまま。porkadot 0.37.4、porkadot#69）**。v1.15.x は registry.k8s.io に出てから | porkadot の addon | **seccomp の直しを先に入れる**。porkadot の `coredns.yaml.erb` は alpha の注釈だけで、本番の CoreDNS は seccomp なしで動いている（`Seccomp: 0`）。#69 で Pod の `seccompProfile: RuntimeDefault` にし、`capabilities.drop` を `ALL` にした。イメージと Corefile は変わらないが、`install kubernetes` で Pod 2 つが入れ替わる。dev で先に通した（2026-10-26、porkadot-dev の `verification-coredns-seccomp.md`。DNS の途切れ 0、`Seccomp: 2`、0.37.3 への戻しも）。手順は `runbook-coredns-seccomp.md`。**v1.15 は registry.k8s.io に出るまで待つ**（2026-10-26 のユーザー判断。同日の時点で v1.15.0 は registry.k8s.io に無く、docker.io の上流のイメージは使わない）。出るまでは v1.14.7 で、その理由を記録する。v1.15.0 は `cache`（応答の無い SERVFAIL を cache する、cache の答えに AA を付けない）と `forward`（上流のホスト名を FQDN として扱う）の振る舞いが変わる（porkadot#61）。段 8 では上げなかった（2026-10-23 のユーザー判断）。ノードの resolv.conf に kube-dns が入る件（`runbook-stage-8.md` §2.10）もここで一緒に考える |
| kube-dns-autoscaler | cpa-amd64 1.7.1 | **cpa v1.11.0**（マルチアーキ。porkadot 0.37.3、porkadot#67） | porkadot の addon | CoreDNS と同じ addon のディレクトリにあるが、段 8 の CoreDNS の PR とは分け、段 8 の後に別の porkadot の PR で上げる（段 8 の変更を小さく保ち、壊れたときに CoreDNS 本体と切り分けられるように）。v1.10.3 ではなく v1.11.0 にしたのは registry.k8s.io に出ている最新のため（porkadot#67）。seccomp を `RuntimeDefault` にする。dev で先に通した（2026-10-25、porkadot-dev の `verification-dns-autoscaler-1.11.md`。DNS の途切れ 0）。手順は `runbook-dns-autoscaler-1.11.md` |
| CNI plugins | v1.4.1 | v1.9.1 | porkadot（`cni_version`） | **段 3 で済む**（porkadot 0.32.0）。cnidaria の init container が置く版とそろえておく |
| kubelet-serving-cert-approver | `:main` | 据え置き | porkadot の addon | タグを固定するかは別途 |
| gated | v0.4.1 | 任意 | fleet-infra `apps/gated` | `k8s.io/*` を 0.37 に上げて作り直すのは任意 |

## 9. 決まったこと（2026-10-18 のユーザーの回答）

計画の承認のときに、次のとおり決まった。

### 9.1 承認の粒度

**計画を一度承認し、その後は次の節目でだけ承認を取る。** 節目の間の runbook どおりの手順は、知らせるだけで進める。

- 段 C の開始（Docker のリポジトリを足す前）と、oeilvert の Docker の入れ替えの前
- 各段の porkadot の PR のマージとリリース
- 本番の各段の開始（render の差分を見せてから `install kubernetes` を流す前）
- etcd のマイナー更新を含む段（5 と 8）の control-plane の kubelet の更新の前
- Longhorn の各更新の前（`kubectl diff` と `--dry-run=server` を見せてから）
- §10 の本番の片付け（その時点で対象を示して承認を取る）
- runbook から外れる操作（ロールバック、想定外の対処）は、その都度

### 9.2 containerd の目標の版と入手元

**2.3 系（LTS）を、Docker の apt リポジトリの `containerd.io` から、apt の pin で 2.3 系に固定して入れる**（§5）。前タスクの OS 更新で「Ubuntu の containerd に揃える」とした判断を、containerd については戻す（Ubuntu に 2.3 が無いため）。

### 9.3 drain の要否

- **段 C**: worker は drain する（前タスクの手順をそのまま使う）。control-plane は drain しない。
- **K8s の各段（計画の承認のとき）**: worker も drain しない。dev の検証（§6.6）で kubelet の更新でコンテナが再起動しないことを各段で確かめ、再起動する段だけ drain する。
- **段 2 で分かったこと（2026-10-19）**: 1.31 の kubelet はそのノードの全コンテナを 1 回再起動させ、drain しないと Longhorn のボリュームが faulted になる（porkadot-dev の `docs/k8s-upgrade/verification-0.31-rc.md`）。そこで段 2 では、**Longhorn のノードの worker 4 台（pablo、duchamp、chirico、oeilvert）を drain してから `install kubelet` し、braque と control-plane 3 台は drain しなかった**（ユーザーの承認）。drain の基準は「短時間の途切れ」より「Longhorn のボリュームの安全」（ユーザーの方針。短時間の障害は許容する）。drain の後に古い iSCSI のセッションが残ったので、drain した台は uncordon の前に再起動した。
- **段 3 以降**: drain の要否は、その段の dev の検証で同じことが起きるかを見て決める。段 3（1.32）は、dev でコンテナが再起動せず、porkadot 0.32.0 の `install kubelet` が iscsid も再起動しなかったので、drain しない（`runbook-stage-3.md` §2.7。本番でコンテナの再起動が出たら止める）。本番の段 3 でも 8 台でコンテナの再起動は無かった。段 4（1.33）も、dev でコンテナも iscsid も再起動せず、アタッチしたままのボリュームが healthy のままだったので、drain しない（`runbook-stage-4.md` §2.7）。本番の段 4 でも 8 台でコンテナの再起動は無かった。段 5（1.34）も、dev で同じ結果だったので drain しない（`runbook-stage-5.md` §2.7）。本番の段 5 でも 8 台でコンテナの再起動は無かった。段 6（1.35）も、dev で同じ結果（Longhorn v1.13.0 のボリュームをアタッチしたまま）だったので drain しない（`runbook-stage-6.md` §2.7）。本番の段 6 でも 8 台でコンテナの再起動は無かった。段 7（1.36）も、dev で同じ結果だったので drain しない（`runbook-stage-7.md` §2.7）。本番の段 7 でも 8 台でコンテナの再起動は無かった。段 8（1.37）も、dev で同じ結果（Longhorn v1.13.0 のボリュームをアタッチしたまま）だったので drain しない（`runbook-stage-8.md` §2.7）。drain する台は、**再起動の代わりに**、drain の後・`install kubelet` の前に `iscsiadm -m session` を見て古いセッションを logout し、`install kubelet` の後に空を確かめて uncordon する（§4.4）。porkadot 0.32 からは `install kubelet` が iscsid を必要なときだけ再起動する。

### 9.4 oeilvert の Docker（devbox）

**Docker の `docker-ce` に移す**（§5.5）。devbox は入れ替えの間止まる。

### 9.5 Longhorn の経路

**経路 A**（§4.2）。段 5（1.34）の後に 1.11.2 → 1.12.x → 1.13.x。

2026-10-19 に、§4.4 の件で 1.12 を **v1.12.1 以上**にした（v1.12.0 には直しが入っていない）。v1.11.3 は挟まない（ユーザーの判断）。

### 9.6 停止時間と時期

- **いつでもよい。** サービスの停止の時間帯の制約は無い。
- ただし braque を止める（再起動する）ときは、前タスクの `docs/worker-os-upgrade/runbook.md` §2.1.1 のとおり、braque の NFS を使うバックアップの CronJob の時間帯を避ける（UTC で 05:44 ごろ、07:53 ごろ、09:03 ごろ、20:30 ごろ、21:00 ごろ）。
- 段の間隔は必須ではない。目安として、段 C の後と、etcd のマイナー更新を含む段 5・段 8 の後は 1 日ほど様子を見てから次へ進む。

### 9.7 範囲

承認の前の計画で「範囲に入れるか」として挙げたものは、すべて範囲に入れる。いつどこで行うかは §10。

## 10. 本筋の段の外で行う作業

| 作業 | 時期 | リポジトリ（PR） | 備考 |
|---|---|---|---|
| k8s-env の `raspi/` の cloud-init を、Docker の `containerd.io` 2.3 系を pin して入れる形に直す | 段 C の前後（段 C の dev の検証で手順が固まったら） | k8s-env | control-plane を作り直したときに 2.2 系に戻らないように。dev の VM の cloud-config（porkadot-dev `tools/`）も同じ時に見直す（porkadot-dev） |
| 本番の `porkadot.yaml` から `etcd.extra_env: ETCD_UNSUPPORTED_ARCH=arm64` を消す | 段 1 | k8s-manifests-fraction（段 1 の render の差分と同じ PR） | 3.5〜3.7 では警告が出るだけ。etcd の static Pod のマニフェストの差分で消えたことを確かめる |
| Corefile の `cache` に `disable success cluster.local` / `disable denial cluster.local` を足す（CoreDNS は v1.14.7 のまま） | 段 8 | porkadot（porkadot#61、0.37.0） | §2。当時の記述「CoreDNS を最新（v1.14.7）にし」→ v1.14.7 は段 7 で入れ、段 8 は Corefile だけ（2026-10-23 のユーザー判断）。v1.15 は段 8 の後（§8） |
| kubelet の `--container-runtime-endpoint` を KubeletConfiguration の `containerRuntimeEndpoint` へ移す | 段 8 | porkadot（porkadot#61、0.37.0） | 1.38 で削除される見込みのフラグ。`kubelet.service` と `config.yaml` の差分で確かめた（`runbook-stage-8.md` §2.6） |
| containerd の config を version 4 に作り直す | 段 8 の後 | ノードの作業（porkadot の `setup-containerd`。porkadot の変更は不要） | 1 台ずつ、config を退避して `setup-containerd --node` で 2.3 の既定値の version 4 を作らせる。以後は 2.2.1 へ戻すときに退避した version 3 の config が要る（§5.7） |
| containerd 2.3 のパッチ | K8s の段の合間に、セキュリティ修正があれば | ノードの作業 | §5.8 |
| 非クリティカルなコンポーネント（kube-prometheus-stack、metrics-server、MetalLB、dns-autoscaler、CoreDNS v1.15） | 段 8 の後 | fleet-infra・porkadot | §8。CNI plugins は段 3 で上げた。順は `runbook-stage-8.md` §10 |
| 片付け: 中身の無い名前空間（`istio-system`、`kagent`、`crawl4ai`、`ml-study`、`metallb`、`minio-system`）、残っている CRD（`nfd.k8s-sigs.io`、MetalLB の `addresspools` は MetalLB の更新と一緒に）、CSIDriver `rook-ceph.*` | 最後 | 本番の作業（必要ならマニフェストの持ち主のリポジトリの PR） | 消す前に中身が空であることと、どのマニフェストからも参照されていないことを確かめ、対象を示して承認を取る。2026-10-23 にユーザーが使っていないアプリ（minio など。k8s-manifests-fraction `2d22dd4`、`7716d7b`）を消したので、対象を読み直してから示す。2026-10-27 の読み直しの結果と一覧・手順は `cleanup.md` |
| 片付け: private（`proxy/proxy.yaml`、`shja-base/templates/`、`metrics-server/`）と k8s-env（`templates/` の rook、`charts/mailserver`）の、1.22 で削除済みの API を使う古いマニフェスト | 最後 | k8s-manifests-fraction-private、k8s-env | 使われていないことを確かめてから、消すか今の API に直す。案は `cleanup.md` §9 |
