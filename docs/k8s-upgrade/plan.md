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
| 3 | 0.32.x | v1.32.13 | 3.5.34-0 | v1.11.3 | 2.3.x | |
| 4 | 0.33.x | v1.33.13 | 3.5.34-0 | v1.12.0 | 2.3.x | |
| 5 | 0.34.x | v1.34.12 | **3.6.15-0**（マイナー更新） | v1.12.1 | 2.3.x | **段の後に Longhorn 1.11.2 → 1.12.x → 1.13.x**（§4） |
| 6 | 0.35.x | v1.35.9 | 3.6.15-0 | v1.13.1 | 2.3.x | 段の前に全台が cgroup v2 であることを確かめる |
| 7 | 0.36.x | v1.36.5 | 3.6.15-0 | v1.14.2 | 2.3.x | |
| 8 | 0.37.x | v1.37.1 | **3.7.x**（マイナー更新） | **v1.14.7**（CoreDNS の最新） | 2.3.x | 段の後に非クリティカルなコンポーネントを最新へ（§8）、containerd の config を version 4 に（§10） |

- K8s・crictl・CoreDNS の版は porkadot 側の調査（`survey-2026-10.md` §6）の値。各段の前に最新パッチを確かめ直す。
- **etcd は kubeadm の既定値を追わない。** etcd は 3.6 へは 3.5.26 以上から、3.7 へは 3.6.11 以上からしか上げられない。kubeadm の既定（1.31〜1.33 の 3.5.24、1.36 の 3.6.8）はこの条件を満たさない。そこで 1.30 で 3.5 の最新パッチに上げて 1.31〜1.33 の間寝かせ、1.34 で 3.6 の最新パッチ、1.37 で 3.7 にする。マイナー更新は 2 回で済む。
- 1.37 の etcd を 3.7.0-0（kubeadm の既定）と 3.7.2-0（3.7 の最新パッチ）のどちらにするかは、段 8 の時点の最新を見て porkadot の 0.37 の PR で決める。
- containerd の 2.3.x は、段 C の時点で Docker のリポジトリにある 2.3 系の最新パッチ（2026-10-18 は 2.3.6、runc 1.5.1 同梱）。段 1 以降の 2.3 のパッチは §5.8。
- **CoreDNS は段 1〜7 で kubeadm の既定に合わせ、段 8 では kubeadm の既定（v1.14.6）ではなく CoreDNS の最新（2026-10-18 は v1.14.7）にする**（ユーザー指示）。kubeadm の Corefile の改善（`cache` の `disable success <domain>` / `disable denial <domain>`。`survey-2026-10.md` §6）も段 8 で一緒に入れる。段 8 の時点で CoreDNS の最新と `registry.k8s.io/coredns/coredns` のタグ（arm64 を含む）を確かめ直す。

## 3. コンポーネントの分類

**クリティカル** = その K8s の版でサポート外になる・動かなくなる・削除された API を使う・製品自身が段階的な更新しか許さない、のどれかに当たるもの。

| コンポーネント | 今 | 分類 | 根拠 | 扱い |
|---|---|---|---|---|
| etcd | 3.5.12 | **クリティカル** | 1 マイナーずつ、かつ前の系列の新しいパッチからしか上げられない（[3.6 の zombie members](https://etcd.io/blog/2025/zombie_members_upgrade/)、[3.7 の upgrade](https://etcd.io/docs/v3.7/upgrades/upgrade_3_7/)）。3.7 は `--experimental-*` が残ると起動しない | porkadot の各版で上げる（§2） |
| control-plane・kube-proxy・kubelet | v1.29.8 | **クリティカル**（本体） | — | porkadot の各版 |
| CoreDNS | v1.10.1 | **クリティカル**（porkadot が配る） | porkadot の版が K8s のマイナーに対応する決まり。kubeadm の各版の既定に合わせる | porkadot の各版。段 8 で最新（v1.14.7）と Corefile の改善（§2） |
| cnidaria | v0.1.1 | **クリティカル**（自作 CNI） | 動かなくなれば Pod の通信が止まる。API の面では問題は見当たらない（GA の API だけ、client-go v0.37.0） | 各段で dev と本番で確かめる。直しが要れば cnidaria-cni の PR |
| Longhorn | v1.11.2 | **クリティカル** | 製品自身が 1 マイナーずつしか許さない。1.11.3・1.13.0 は K8s 1.34 以上を要求する。上限の K8s の表明はどの版にも無い（[release notes](https://github.com/longhorn/longhorn/releases)、[upgrade](https://longhorn.io/docs/1.13.0/deploy/upgrade/)） | 段 5 の後に 2 回（§4） |
| containerd・runc | 2.2.1・1.3.4 | **クリティカル** | 2.2 は 1.37 の推奨表に無い（1.37 は 2.4.0+ / 2.3.0+）。2.2 の upstream の EoL は 2026-11-06、runc 1.3 は 2026-10 末（[containerd RELEASES.md](https://github.com/containerd/containerd/blob/main/RELEASES.md)、runc 1.5.0 の release notes） | 段 C で 2.3 系へ（§5） |
| MetalLB | v0.14.5 | 非クリティカル | 使う API（`policy/v1`、CRD v1、admission v1）は 1.37 まで残る。0.16.0 の「1.36 で ASN の CRD 検証が通らない」修正（metallb#3034）は BGPPeer のオブジェクトの検証の問題で、本番は L2 だけ（BGPPeer 0 件） | 段 8 の後（porkadot の addon） |
| kube-prometheus-stack | 85.2.1 | 非クリティカル | chart の `kubeVersion` は `>=1.25.0-0`（最新の 92.10.1 も同じ）。同梱の kube-state-metrics v2.19.0 は client-go 1.35 でビルド（[互換表](https://github.com/kubernetes/kube-state-metrics#compatibility-matrix)）で、新しい資源の metrics が出ないだけ | 段 8 の後（fleet-infra） |
| metrics-server | v0.7.2 | 非クリティカル | 0.7.x は 1.27 以上、上限無し（[互換表](https://github.com/kubernetes-sigs/metrics-server#compatibility-matrix)）。0.8.x は 1.31+、0.9.x は 1.34+ | 段 8 の後（fleet-infra） |
| kube-dns-autoscaler | cpa-amd64 1.7.1 | 非クリティカル | core の API だけ。amd64 専用だが worker に載る | 段 8 の後（porkadot の addon。マルチアーキの `registry.k8s.io/cpa/cluster-proportional-autoscaler` へ） |
| kubelet-serving-cert-approver | `:main` | 非クリティカル | `certificates.k8s.io/v1` だけ | 据え置き（タグの固定は任意） |
| CNI plugins | v1.4.1 | 非クリティカル | K8s の版と連動しない | 段 8 の後（porkadot） |
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

- **最新（1.13）に着くまでの更新は、どの経路でも 2 回**（1.11 → 1.12 → 1.13）。経路の違いは「いつ上げるか」だけである。
- 1.13 は K8s 1.34 以上でしか入らないので、1.13 へ上げるのは早くても段 5 の後になる。
- 1.11.3 も 1.34 以上を要求する。1.11 のパッチを上げる意味は無い（上げるなら 1.12 へ）。
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
| 段 5 の後（1 回目） | 1.34 | **1.11.2 → 1.12.x**（その時点の 1.12 の最新パッチ。今は 1.12.1） |
| 段 5 の後（2 回目） | 1.34 | **1.12.x → 1.13.x**（今は 1.13.0） |
| 段 6 〜 段 8 | 1.35 → 1.37 | 1.13.x |

- 1 回目と 2 回目のそれぞれで、manager → エンジン（V1 は live upgrade）→ instance-manager の入れ替わり → ボリュームが全部 healthy、まで確かめてから次へ進む。手順は fleet-infra の `infrastructure/longhorn/CLAUDE.md` と Wiki（`wiki/topics/自宅クラスター.md` の「Longhorn の運用メモ」）に従う。
- 1.13 は `longhorn-global-manager` の Deployment（3 replica）を足し、CSI のサイドカーを専用の ServiceAccount に変える。fleet-infra の `update-longhorn.sh` で生成した manifest の diff でこれを確かめる。
- fleet-infra の変更（`MANIFEST_VER` と `longhorn.yaml`、README の互換表）は fleet-infra の PR で出す。

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

1 台の流れ:

1. 事前確認（読み取り）: Node が Ready、`containerd --version`・`runc --version`、`/etc/containerd/config.toml` の控え、`apt-cache policy containerd containerd.io runc`、他のノードがすべて Ready で degraded のボリュームが無い。
2. 戻すための deb を控える: `apt-get download containerd=2.2.1-0ubuntu1~24.04.3 runc=1.3.4-0ubuntu1~24.04.1`（oeilvert は `docker.io` も）。
3. ✋ worker は cordon と drain（前タスクの §3.3。Longhorn の `concurrent-replica-rebuild-per-node-limit` を 0、`replica-auto-balance` を disabled、最後の replica を持つノードでは `node-drain-policy` を一時的に変え、MinIO・Prometheus を止める）。control-plane は drain しない（DaemonSet と static Pod だけ。controller-manager と scheduler の Pod が載っていれば消して別の master へ移す。etcd のリーダーなら `move-leader` で移す）。drain の要否は §9.3。
4. ✋ Docker の noble のリポジトリと鍵、`containerd.io` の pin を置き、`apt update`。`apt-cache policy containerd.io` の候補が 2.3 系の最新であること（2.4 ではないこと）を確かめる。
5. ✋ `apt-get install -o Dpkg::Options::=--force-confold containerd.io`。実行の前に、apt が削除するのが `containerd` と `runc` だけであることを読む（oeilvert は下の注意）。
6. ノードで確かめる: `containerd --version` が 2.3.x、`runc --version` が 1.5.x、`/etc/containerd/config.toml` が version 3 のまま、`containerd config dump` に `SystemdCgroup = true`、`journalctl -u containerd` に config の移行のエラーが無い、`sudo /opt/bin/crictl info` と `crictl images`（既存のイメージが残る）。
7. ✋ `sudo systemctl restart kubelet`。Node が Ready、CONTAINER-RUNTIME が `containerd://2.3.x`、DaemonSet の Pod が Running。control-plane では etcd 3/3 healthy と apiserver 3/3。
8. ✋ ノードを再起動する（推奨）。古い shim を入れ替え、2.3 で起動から上がることを確かめる。braque の再起動は前タスクの §2.1.1 の注意（NFS、LAN の 10.254.0.0/16 の経路、ZFS の取り込み）に従う。
9. 再起動の後に 6・7 をもう一度確かめ、§6.3 のノードの項目（cnidaria の経路、Longhorn のボリューム、MetalLB の speaker）を見る。
10. ✋ uncordon、Longhorn の設定を戻し、replica の再同期を待ってから次の 1 台へ。

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
- 前タスクでは、24.04 の上で containerd を戻す手順を dev で通してある（Pod が 1 回ずつ再起動し、MetalLB の speaker が 1 回 CrashLoopBackOff になってから戻った）。段 C の dev の検証でも、戻す手順を 1 台で通す。

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
   - drain するかどうかは §9.3。drain しない場合も、1 台ごとに Node が Ready、そのノードの Pod の再起動回数が増えていないこと、Longhorn のボリュームが healthy を確かめてから次へ進む。
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

### 6.4 ロールバック

| どこまで進んだか | 戻し方 |
|---|---|
| `install kubernetes` の後、kubelet はまだ前の版 | 前の段の porkadot と、前の段の commit の `assets/` で `install kubernetes` をやり直す。etcd はまだ変わっていない |
| control-plane の kubelet の一部まで（etcd が混在） | 戻す台を前の版の `assets/` で `install kubelet --node` し直す。etcd は混在中なら前のイメージに戻せる |
| etcd の**全メンバーが新しいマイナー版**になった後（段 5 と段 8） | イメージを戻すだけでは戻せない。段の前の `porkadot etcd backup` から restore するか、etcd の公式の downgrade 手順に従う。restore するとバックアップ後の変更は失われる |
| worker の kubelet の途中 | その台を前の版の `assets/` で `install kubelet --node` し直す |
| Longhorn の更新の後 | **戻せない**（ダウングレード不可）。manager の更新が失敗した場合だけ、前の版の manifest を apply して戻れる。データは更新前のバックアップから戻す |
| containerd（段 C） | §5.7 |

- apiserver を前のマイナーへ戻すのは、新しい版で書かれた storage の版があると危うい。1.30〜1.37 で組み込みの資源の storage の版が変わるかは、各段の porkadot の調査で確かめ、runbook に書く。
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

- dev（`porkadot-dev`、KVM の VM + Pi 5、context `test`）で、本番と同じ順序（段 C → 段 1 → …、各段は §6.2）で上げる。**段 C も dev で先に通す**（amd64 の VM と arm64 の Pi 5 の両方。戻す手順も 1 台で通す）。
- **dev の `addons.enabled` を本番に合わせる**（`cnidaria`、`coredns`、`metallb`、`kubelet-serving-cert-approver`）。dev は既定の flannel のままなので、そのままでは cnidaria を確かめられない。dev を cnidaria に移すのは dev の検証の単位で決める。
- Longhorn の経路（§4）も dev で先に通す。dev に Longhorn が無ければ、fleet-infra の test overlay で入れるかを dev の単位で決める。
- 見るもの: §6.3 の項目に加えて、kubelet の更新で Pod のコンテナが再起動しないか（drain の要否の判断材料。§9.3）、`kubectl get csr`（1.31 で kubelet の CSR の検査が厳しくなる）、etcd の 1 台ずつの更新の時間。
- porkadot の `assets/` の差分は `porkadot-dev/CLAUDE.md` の「refactoring01 の assets 回帰確認」に従って確かめる。

## 7. 段ごとの注意

| 段 | 注意 |
|---|---|
| C | containerd 2.2.1 → 2.3.x、runc 1.3.4 → 1.5.x（§5）。K8s は v1.29.8 のまま |
| 1（1.30） | etcd を 3.5.34 へ（パッチ更新）。porkadot の手順書を §6.2 の順に直す（0.30 の PR）。crictl を v1.30.1 へ（1.29 で上げ忘れていた）。本番の `porkadot.yaml` から `ETCD_UNSUPPORTED_ARCH` を消す（§10） |
| 2（1.31） | kubelet の serving 証明書の CSR が CN とノード名の一致を検査される。kubelet-serving-cert-approver で承認されることを `kubectl get csr` で見る |
| 3（1.32） | `flowcontrol.apiserver.k8s.io/v1beta3` の削除。本番は使っていないことを確かめてある。段の前に Prometheus の `apiserver_requested_deprecated_apis` を見直す |
| 4（1.33） | v1 Endpoints API が非推奨になる（削除はされない）。kube-prometheus の ServiceMonitor などが warning を出すだけ |
| 5（1.34） | **etcd 3.6.15 へ（マイナー更新）**。porkadot がフラグ名（`--experimental-initial-corrupt-check`、`--experimental-watch-progress-notify-interval`）を新しい名前に変える。static Pod から API オブジェクトを参照できなくなる（bootstrap の kube-proxy を porkadot で直す。稼働中の更新には効かない）。**段の後に Longhorn を 2 回上げる**（§4） |
| 6（1.35） | **kubelet が cgroup v1 で起動しない**。段の前に全台の `stat -fc %T /sys/fs/cgroup` が `cgroup2fs` であることを確かめる（2026-10-18 の調査では 8 台とも `cgroup2fs`）。kubelet の `--pod-infra-container-image` の削除（使っていない） |
| 7（1.36） | `gitRepo` volume が無効になる（使っていない）。kube-controller-manager のメトリクス `volume_operation_total_errors` が `volume_operation_errors_total` に改名（本番の PrometheusRule は使っていない）。MetalLB の CRD を apply し直すことになるので、dev で `install kubernetes` が通ることを見る |
| 8（1.37） | **etcd 3.7 へ（マイナー更新）**。`--experimental-*` が残っていると etcd が起動しないので、段 5 でフラグを直したことを render の差分で確かめる。kube-proxy は `mode` の明示が無いと warning を出す（本番は `mode: iptables` を継ぐ）。containerd 2.3 は 1.37 の推奨表に入る。**CoreDNS を最新（v1.14.7）にし、Corefile の `cache` に `disable success` / `disable denial` を足す**（§2）。kubelet の `--container-runtime-endpoint` を KubeletConfiguration へ移す（§10） |

- kubelet の `--container-runtime-endpoint` は 1.37 で DEPRECATED、削除は 1.38 に延期された。KubeletConfiguration の `containerRuntimeEndpoint` へ移すのは段 8 で行う（§10）。
- 本番の `porkadot.yaml` の `etcd.extra_env: ETCD_UNSUPPORTED_ARCH=arm64` は警告が出るだけだが、段 1 で消す（§10）。

## 8. 最後に上げる非クリティカルなコンポーネント

本番が 1.37 で健全になってから、1 つずつ上げる。目標の版は 2026-10-18 時点の最新で、上げる時点で確かめ直す。

| コンポーネント | 今 | 目標 | 管理 | 注意 |
|---|---|---|---|---|
| kube-prometheus-stack | chart 85.2.1（operator v0.90.1） | chart 92.10.1（operator v0.94.1） | fleet-infra `scripts/update-kube-prometheus.sh` | major が 7 つ上がる。CRD を先に更新する。各 major の upgrade notes を読む |
| metrics-server | v0.7.2 | v0.9.0 | fleet-infra `scripts/update-metrics-server.sh` | 0.9.x は 1.34 以上。fleet-infra の README の「上げない」の注記を外す |
| MetalLB | v0.14.5 | v0.16.0 | porkadot の addon | 0.16.0 で BGP の既定の backend が frr-k8s に、metrics が HTTPS に。本番は L2 だけ。残っている `addresspools` の CRD を片付ける。API の VIP を持つので dev で先に通す |
| kube-dns-autoscaler | cpa-amd64 1.7.1 | cpa v1.10.3（マルチアーキ） | porkadot の addon | CoreDNS と同じ addon のディレクトリにあるが、段 8 の CoreDNS の PR とは分け、段 8 の後に別の porkadot の PR で上げる（段 8 の変更を小さく保ち、壊れたときに CoreDNS 本体と切り分けられるように） |
| CNI plugins | v1.4.1 | v1.9.1 | porkadot（`cni_version`） | cnidaria が使う reference plugins。dev で cnidaria と一緒に確かめる |
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
- **K8s の各段**: worker も drain しない。dev の検証（§6.6）で kubelet の更新でコンテナが再起動しないことを各段で確かめ、再起動する段だけ drain する。

### 9.4 oeilvert の Docker（devbox）

**Docker の `docker-ce` に移す**（§5.5）。devbox は入れ替えの間止まる。

### 9.5 Longhorn の経路

**経路 A**（§4.2）。段 5（1.34）の後に 1.11.2 → 1.12.x → 1.13.x。

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
| CoreDNS を最新（v1.14.7）にし、Corefile の `cache` に `disable success` / `disable denial` を足す | 段 8 | porkadot（0.37 の PR） | §2。CoreDNS の最新は段 8 の時点で確かめ直す |
| kubelet の `--container-runtime-endpoint` を KubeletConfiguration の `containerRuntimeEndpoint` へ移す | 段 8 | porkadot（0.37 の PR。大きくなるなら 0.37 の別 PR） | 1.38 で削除される見込みのフラグ。`kubelet.service` と `config.yaml` の差分で確かめる |
| containerd の config を version 4 に作り直す | 段 8 の後 | ノードの作業（porkadot の `setup-containerd`。porkadot の変更は不要） | 1 台ずつ、config を退避して `setup-containerd --node` で 2.3 の既定値の version 4 を作らせる。以後は 2.2.1 へ戻すときに退避した version 3 の config が要る（§5.7） |
| containerd 2.3 のパッチ | K8s の段の合間に、セキュリティ修正があれば | ノードの作業 | §5.8 |
| 非クリティカルなコンポーネント（kube-prometheus-stack、metrics-server、MetalLB、dns-autoscaler、CNI plugins） | 段 8 の後 | fleet-infra・porkadot | §8 |
| 片付け: 中身の無い名前空間（`istio-system`、`kagent`、`crawl4ai`、`ml-study`、`metallb`、`minio-system`）、残っている CRD（`nfd.k8s-sigs.io`、MetalLB の `addresspools` は MetalLB の更新と一緒に）、CSIDriver `rook-ceph.*` | 最後 | 本番の作業（必要ならマニフェストの持ち主のリポジトリの PR） | 消す前に中身が空であることと、どのマニフェストからも参照されていないことを確かめ、対象を示して承認を取る |
| 片付け: private（`proxy/proxy.yaml`、`shja-base/templates/`、`metrics-server/`）と k8s-env（`templates/` の rook、`charts/mailserver`）の、1.22 で削除済みの API を使う古いマニフェスト | 最後 | k8s-manifests-fraction-private、k8s-env | 使われていないことを確かめてから、消すか今の API に直す |
