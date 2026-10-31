# 0004. Longhorn は K8s 1.34 の後に v1.11.2 → v1.12.1 → v1.13.0 と続けて上げる（経路 A）

- Date: 2026-10-18（v1.12.1 以上と open-iscsi の扱いは 2026-10-19）
- Status: Accepted

## Context

本番のストレージは Longhorn v1.11.2 で、K8s の段（[0001](0001-one-minor-version-per-stage.md)）の間にクリティカルなコンポーネントとして上げる必要があった（[0003](0003-critical-and-non-critical-components.md)）。制約は次のとおり（`docs/k8s-upgrade/plan.md` §4.1）。

- Longhorn は 1 マイナーずつしか上げられない（1.11 → 1.13 は 1.12 を経る）。**ダウングレードはできない。**
- v1.13 と v1.11.3 は K8s 1.34 以上を要求する。どの版も K8s の上限は表明していない。
- v1.11 は 2026-09-12 で EOM。

最新の 1.13 に着くまでの更新は、どの経路でも 2 回になる。違いは「いつ上げるか」で、3 つの経路を比べた（plan §4.2）。A: 1.34 まで 1.11.2 のまま、段 5（1.34）の後に 1.12 → 1.13 を続けて。B: 段 1 の前に 1.12、段 5 の後に 1.13。C: 段 8 の後に 1.12 → 1.13。

段 2 の本番で、もう 1 つの制約が分かった。**ボリュームがアタッチされたまま iscsid が再起動すると、v1.11.2 のエンジンは古い iscsid の PID で `nsenter` して iSCSI を logout できなくなる。** その後の detach で古いセッションが残り、もう一度 iscsid が再起動すると、そのノードに同じボリュームが来たときにエンジンが落ちて faulted を繰り返す（`docs/k8s-upgrade/results/stage-2/iscsi-stale-sessions.md`、porkadot-dev の `docs/longhorn/iscsi-stale-sessions.md`、longhorn#13334・#10544）。直しは v1.11.3・**v1.12.1**・v1.13.0 に入っていて、v1.12.0 には入っていない。

## Decision

- **経路 A** を取る。各段の Longhorn が、その版が出た時期の K8s に近い組み合わせになる（1.11 は 1.34 まで、1.13 は 1.35〜1.37）。Longhorn の作業が 1 か所にまとまる。
- **1.12 は v1.12.1 以上**にする（v1.12.0 には iscsid の件の直しが無い）。v1.11.3 は、1.34 以上を要求するので段 5 まで入れられず、段 5 の後は 1.12 へ上げるので挟まない。
- 各回の手順（`docs/longhorn/runbook-upgrade-1.12-1.13.md`、fleet-infra の `infrastructure/longhorn/CLAUDE.md`）:
  - apply の前に、attached のボリュームのバックアップと SystemBackup を取る（BackupTarget は braque の NFS）。ダウングレードできないので、戻り道はこのバックアップだけである。2024 年から detached の `homegallery/cg-data` は、アタッチして何が起きるか確かめていないので取らない
  - 新しいイメージを Longhorn のノードに先に pull し、replica 1 のボリュームを使う Prometheus を apply の間止める（dev で、manager の更新とイメージの pull が重なって replica が timeout で落ちたため）
  - `kubectl apply -k infrastructure/longhorn/prod/`（本番に Flux は無い）の後、一時的な PVC で CSI と NetworkPolicy を確かめる
  - エンジンを新しいエンジンイメージへ更新する。attached のものは 1 本ずつ live upgrade、detached のものは `spec.image` の更新。全部を更新したら古い engine image を消す
- **Longhorn のエンジンが直った版になるまで、Longhorn のノード（pablo、duchamp、chirico、oeilvert）で open-iscsi を unattended-upgrades から外す**（`/etc/apt/apt.conf.d/51fraction-hold-open-iscsi`）。open-iscsi の更新の postinst が iscsid を再起動しうるためである。**v1.12.1 以上にし、全ボリュームのエンジンを新しいエンジンイメージにしたら、このファイルを消して戻す。**
- それまでの段では、iscsid を再起動しないように運用する。porkadot 0.32 からは `install kubelet` が iscsid を `initiatorname.iscsi` が変わったときだけ再起動し、各段の runbook で `install kubelet` の前と後の iscsid の PID とセッションを確かめる（plan §4.4）。

## Consequences

- 段 5 の後に 2 回（2026-10-20 に v1.12.1、2026-10-21 に v1.13.0）上げ、データは失われず、ボリュームは全部 healthy に戻った（`docs/longhorn/results/upgrade-1.12-1.13/`）。open-iscsi の hold は 2026-10-21 に 4 台とも消した。
- K8s 1.29〜1.34 の間は、EOM の v1.11.2 と、iscsid の件を抱えたまま走った。そのぶん各段の runbook に iscsid とセッションの確認が要った。
- v1.12.1 から longhorn-system に NetworkPolicy が 6 つ入る。fleet-infra の prod overlay の `commonLabels` がその selector にも入って通信を止めるので、overlay を直した（fleet-infra#194）。overlay を持つ限り、次の Longhorn の更新でも上流の NetworkPolicy の selector を読む必要がある。
- live upgrade したエンジンは、detach するまで古い instance-manager の上で動き続ける。古い instance-manager の片付けは別の手順（`docs/longhorn/runbook-old-instance-manager.md`）になった。
- 更新のために取ったスナップショットとバックアップは、2 回目の完了の後に消した（`docs/longhorn/results/upgrade-1.12-1.13/cleanup.md`）。
- 次に Longhorn を上げるときも、1 マイナーずつであること、新しい版が要求する K8s の下限、各ボリュームのエンジンの更新まで含めて 1 回と数えること、が経路の制約になる。
