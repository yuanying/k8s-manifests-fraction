# 0008. 本番の変更は節目でだけ承認を取り、短命の admin トークンで行い、etcd のバックアップと前の版の render で戻せるようにする

- Date: 2026-10-18
- Status: Accepted

## Context

K8s を 1 マイナーずつ上げると（[0001](0001-one-minor-version-per-stage.md)）、本番 `fraction` への書き込みが数十回になる。porkadot の `install kubernetes`・`install kubelet` をノードごとに、加えて Longhorn・containerd・addon の更新がある。1 つずつ承認を取ると進まず、承認を取らずに進めると、取り返しのつかない操作（etcd のマイナー更新、ダウングレードできない Longhorn の更新）を止める機会が無い。

本番の kubeconfig には 2 つの資格がある（porkadot-dev の `CLAUDE.md`「本番クラスタ（fraction）の kubeconfig 運用」）。

- `fraction-auditor`: SA `kube-system/infra-auditor` の期限の無いトークン。読み取り用
- `infra-admin`: `kubectl create token` でその都度発行する SA `kube-system/infra-admin` の短命のトークン。`cluster-admin`

## Decision

**承認**（`docs/k8s-upgrade/plan.md` §9.1）

- 計画を一度承認し、その後は**節目でだけ**承認を取る。runbook では節目に ✋✋ を付ける。
  - 各段の本番の開始（render の差分・ロールバックの形などを見せ、runbook と render の PR をマージしてから、`install kubernetes` の前）
  - etcd のマイナー更新を含む段では、control-plane の `install kubelet` の前（ここを過ぎると etcd は restore でしか戻せない）
  - Longhorn の各回の開始（`kubectl diff` と `--dry-run=server` を見せてから）、段 C の開始、porkadot のリリース、本番の片付け
- 節目の間の runbook どおりの操作には ✋ を付け、**知らせてから進める**（1 つずつ承認は取らない）。読み取りは知らせずに行ってよい。
- runbook に**止める条件**を書く（rollout が終わらない、VIP が 1 分を超えて応答しない、Node が 5 分たっても Ready にならない、etcd が 2/3 を下回る、`install kubelet` をした台の Pod の再起動、Longhorn のボリュームが degraded のまま戻らない、など）。当たったら止めて報告する。
- **runbook から外れる操作**（ロールバック、`etcd restore`、drain への切り替え、想定外の対処）は、その都度承認を取る。

**資格**

- 普段の確認は `fraction-auditor` で読むだけにする。
- 書き込み（porkadot の install、drain・cordon、`kubectl apply`、Longhorn の更新）と `kubectl diff`・`--dry-run=server` は、`infra-admin` の短命のトークン（数時間の期限）を作業の単位ごとに発行して行い、終わったら破棄する。

**戻せるようにしておくこと**

- **各段の前に `porkadot etcd backup` を取る。** etcd のマイナー更新を含む段は、段の前・control-plane の kubelet の前・control-plane の後にも取る。
- 段ごとの render の差分を PR にし、前の段の `assets/` を git に残す。**ロールバックは、前の段の porkadot と前の commit の `assets/` で `install kubelet` / `install kubernetes` をやり直す。** kubelet を kube-apiserver より新しくしないために、**kubelet を先に、control-plane を最後に**戻す（plan §6.4、各段の runbook の §7）。
- etcd の全メンバーが新しいマイナーになった後は、イメージを戻すだけでは戻せない。段の前のバックアップから porkadot の `etcd restore` で戻す。この形は dev で先に確かめる（段 5・段 8）。

## Consequences

- 1 段の本番を、2 つほどの承認で通せた。etcd のマイナー更新の前で一度止まるので、`install kubernetes` の結果を見てから、戻しにくい操作に進むかを決められた。
- ✋ の操作も、知らせることで記録に時刻が残る。各段の `results/` は、知らせた内容と確かめた結果の記録になっている。
- 止める条件に当たったが原因が分かり、作業と無関係だったもの（同じ時間帯の別の作業による Pod の作り直しなど）は、記録して進めた。判断の根拠はその段の記録にある。
- `infra-admin` のトークンを作業の単位ごとに発行するので、期限切れのときは発行し直す（Longhorn の初回のバックアップは 3 時間を超えた。`docs/longhorn/runbook-upgrade-1.12-1.13.md` §1.2）。
- `fraction-auditor` は read-only の想定だが、fleet-infra の Role `developer` により、default などいくつかの名前空間で強い権限を持つ。絞るかは決めていない（Wiki の TODO）。
- ロールバックの手順のうち、dev で流していないもの（例: 段 8 の `install kubernetes` だけを 1.36 に戻す形）は、runbook に「確かめていない」と書いた。今回、本番でロールバックした段は無い。
