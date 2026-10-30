# ADR（Architecture Decision Records）

本番クラスタ `fraction` の運用で下した判断と、その理由を残す。手順と実施の記録は `docs/` の各ディレクトリ（`k8s-upgrade/`、`longhorn/` など）にあり、ここにはそれらを通して守る判断だけを書く。

- 1 つの ADR に 1 つの判断。ファイルは `NNNN-<kebab-case>.md`、項目は Date・Status・Context・Decision・Consequences
- Date は判断を下した日
- 受け入れた ADR の中身は書き換えない。判断を変えるときは新しい ADR を足し、古い ADR の Status を `Superseded by NNNN` にする

## 一覧

0001〜0008 は、K8s を 1.29 から 1.37 へ上げたとき（2026-10。計画は `docs/k8s-upgrade/plan.md`）の判断。次の K8s の更新でも読み直す。

| # | 題 | 決めたこと |
|---|---|---|
| [0001](0001-one-minor-version-per-stage.md) | K8s は 1 マイナーずつ、porkadot の対応版と dev の検証を経て上げる | 1 段 = 1 マイナー。porkadot の PR → dev → リリース → runbook → 本番、前の段が本番で健全になるまで次へ進まない。最終目標は着手時の最新のマイナーの最新パッチ |
| [0002](0002-drain-decided-by-longhorn-volume-safety.md) | drain の要否は Longhorn のボリュームの安全で決め、短時間の障害は許容する | 段ごとに dev でコンテナの再起動を見て決める。1.31 だけ Longhorn のノードの worker を drain した |
| [0003](0003-critical-and-non-critical-components.md) | 関連コンポーネントは、クリティカルなものだけ段に合わせて最小の経路で上げ、残りは K8s を最新にしてから上げる | クリティカルの定義と分類。etcd は kubeadm の既定を追わない。Prometheus のデータは残すことを条件にしない |
| [0004](0004-longhorn-upgrade-path.md) | Longhorn は K8s 1.34 の後に v1.11.2 → v1.12.1 → v1.13.0 と続けて上げる（経路 A） | 1.12 は v1.12.1 以上。各回の前にバックアップ、エンジンの live upgrade。直るまで open-iscsi を unattended-upgrades から外す |
| [0005](0005-containerd-io-2-3-from-docker-apt.md) | containerd は Docker の apt リポジトリの containerd.io を 2.3 系に pin し、K8s の段の前に上げる | config は version 3 のまま。version 4 への作り直しは残課題 |
| [0006](0006-addon-images-from-registry-k8s-io.md) | CoreDNS などの addon のイメージは registry.k8s.io に出たものを使う | docker.io の上流のイメージは使わない。出るまで待つ |
| [0007](0007-corefile-shaped-like-kubeadm.md) | CoreDNS の Corefile は kubeadm と同じ形にそろえる | `cache` の `disable` は `cluster.local` だけ、`max_concurrent` は入れない |
| [0008](0008-approval-and-credentials-for-production-changes.md) | 本番の変更は節目でだけ承認を取り、短命の admin トークンで行い、etcd のバックアップと前の版の render で戻せるようにする | ✋✋ と ✋、止める条件、`fraction-auditor` と `infra-admin`、ロールバックは kubelet を先に control-plane を最後に |

## ほかのリポジトリの ADR

- cnidaria-cni の ADR 0001: cnidaria は標準の CNI plugins（bridge・host-local・portmap）を `/opt/cni/bin` にコピーしない。置くのはノードの構築側（porkadot の `install kubelet`）
