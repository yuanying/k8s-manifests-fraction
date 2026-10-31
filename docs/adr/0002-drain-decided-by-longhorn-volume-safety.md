# 0002. drain の要否は Longhorn のボリュームの安全で決め、短時間の障害は許容する

- Date: 2026-10-19
- Status: Accepted

## Context

K8s の各段で worker を drain するかどうかを決める必要があった。drain すれば kubelet の更新で Pod が止まらないが、ワークロードの移動と Longhorn の replica の再同期で 1 台ごとの時間が長くなり、最後の replica を持つノードでは Longhorn の設定を一時的に変える手間も要る。

計画の承認のとき（2026-10-18）は、K8s の段では drain しないことにしていた。kubelet の更新でコンテナが再起動しないことを、各段の dev の検証で確かめる前提だった。

段 2（1.31）の dev の検証で、**1.31 の kubelet はそのノードの全コンテナを 1 回再起動させる**ことが分かった（kubernetes#124220。porkadot-dev の `docs/k8s-upgrade/verification-0.31-rc.md`）。drain しないと Longhorn のボリュームが faulted になり、Pod に 1〜2 分 EIO が出た。

本番 `fraction` は家庭用のクラスタで、サービスが短時間止まることは問題にならない。失って困るのは Longhorn のボリュームのデータと、degraded のまま戻らないボリュームである。

## Decision

- **drain の基準は「短時間の途切れ」ではなく「Longhorn のボリュームの安全」（データ、degraded のまま戻らないこと）とする。短時間の障害は許容する。**
- 段ごとに、dev の検証で kubelet の更新によりコンテナが再起動するか（と iscsid が再起動するか）を見て、drain の要否を決める。その段の runbook に理由を書く。
- 段 2（1.31）は、**Longhorn のノードの worker 4 台（pablo、duchamp、chirico、oeilvert）を drain してから `install kubelet` し、braque と control-plane 3 台は drain しなかった**。
- 段 3〜8（1.32〜1.37）は、dev でコンテナも iscsid も再起動せず、アタッチしたままのボリュームが healthy のままだったので、drain しなかった（plan §9.3、各段の runbook の §2.7）。
- drain しない段の止める条件として、`install kubelet` をした台の Pod の再起動を見る。

## Consequences

- 段 3 以降は、本番でもコンテナの再起動は 0 だった。1 台の更新は数十秒で済み、Longhorn の設定にも触らずに済んだ。
- drain が要るときの手順（Longhorn の `concurrent-replica-rebuild-per-node-limit` を 0、最後の replica を持つノードで `node-drain-policy` を一時的に変える、replica 1 の Prometheus を止める）は、段 C と段 2 の runbook（`docs/k8s-upgrade/runbook-stage-c.md`、`runbook-stage-2.md`）にある。
- 段 2 で drain した台には、drain の後に古い iSCSI のセッションが残った。原因は drain ではなく、アタッチ中の iscsid の再起動と Longhorn v1.11.2 のエンジンの不具合だった（`docs/k8s-upgrade/results/stage-2/iscsi-stale-sessions.md`、porkadot-dev の `docs/longhorn/iscsi-stale-sessions.md`）。これが Longhorn の更新経路の判断に影響した（[0004](0004-longhorn-upgrade-path.md)）。
- 「短時間の障害は許容する」は、本番の作業中に止める条件を決めるときの基準にもなる。たとえば、metrics-server の入れ替わりで APIService が約 70 ms だけ False になったものは、止めずに記録した。
- 次の K8s の更新でも、dev でコンテナの再起動を見ることを省けない。kubelet の振る舞いはマイナーごとに変わりうる。
