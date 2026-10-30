# 0001. K8s は 1 マイナーずつ、porkadot の対応版と dev の検証を経て上げる

- Date: 2026-10-18
- Status: Accepted

## Context

本番クラスタ `fraction` は porkadot（自作の CLI）で構築・運用している。kubelet は porkadot が置く `/opt/bin/kubelet`、control-plane は self-hosted（apiserver は DaemonSet）、etcd は porkadot が static Pod で管理する。K8s の版を上げることは、porkadot の版を上げることと切り離せない。

- **porkadot の版は K8s のマイナーに対応する**（0.3X.x = K8s 1.3X）。K8s のマイナーを 1 つ上げるには、その版の porkadot をリリースする必要がある。
- K8s の version skew policy は、control-plane のマイナーを 1 つずつしか上げることを許さず、kubelet が kube-apiserver より新しくなることを許さない。
- 2026-10 の時点で本番は v1.29.8（EOL）、最新の安定版は v1.37.1 で、8 マイナーの差があった。
- 検証用に dev クラスタ（porkadot-dev、KVM の VM、context `test`）がある。本番と同じ porkadot で、同じ順序の操作を先に流せる。

## Decision

**1 段 = 1 マイナー**（1.29 → 1.30 → … → 1.37）で上げ、各段を次の順で進める。**前の段が本番で健全になるまで、次の段の本番に進まない。** dev の検証は本番より先に進めてよい。

1. porkadot の対応版の PR（`bundle exec rake test` が通ること）
2. dev クラスタで本番と同じ順序の更新を流し、記録を porkadot-dev の `docs/k8s-upgrade/verification-*.md` に残す。kubelet の更新でコンテナが再起動するか（[0002](0002-drain-decided-by-longhorn-volume-safety.md)）、戻し方が通るかもここで見る
3. porkadot のリリース
4. このリポジトリで新しい porkadot の render の差分と段の runbook（`docs/k8s-upgrade/runbook-stage-*.md`）を PR にする
5. 本番の更新と、段の完了の確認（`docs/k8s-upgrade/plan.md` §6.3）。記録は `docs/k8s-upgrade/results/`

段の中の順序は skew policy に合わせて固定する（plan §6.2）。

1. `porkadot install kubernetes --node <control-plane>`（apiserver・KCM・scheduler・kube-proxy・addon）
2. control-plane の `install kubelet` を 1 台ずつ（etcd の static Pod もここで 1 台ずつ変わる。リーダーは `move-leader` で移してから）
3. worker の `install kubelet` を 1 台ずつ

**最終目標は、着手時点の最新のマイナーの最新パッチ**とし、各段の前に `stable-1.3X.txt` で最新パッチを確かめ直す。作業中に出た最終マイナーの patch（v1.37.2）も、同じ流れ（porkadot の patch のリリース → dev → runbook → 本番）で入れる。

## Consequences

- 8 段とその後の patch で、porkadot を 0.30.0〜0.37.6 までリリースした。段ごとに porkadot の PR・dev の記録・runbook・本番の記録がそろうので、次の更新はそれを下敷きにできる（Wiki `wiki/synthesis/cluster-upgrade-plan-2026.md` の「K8s の更新のやり方」）。
- 段ごとの問題を、その段の変更だけに切り分けられる。dev で見つかったもの（1.34 の scheduler が 1.33 の apiserver の返さない API を待つデッドロックなど）は、本番の前に porkadot で直せた。dev で流していない組み合わせや戻し方は runbook に「確かめていない」と書き、本番で特に見る。
- 段の数だけ porkadot のリリースと本番の作業が要る。1 段の本番は 1 時間前後。etcd のマイナー更新を含む段の後は、1 日ほど様子を見てから次へ進んだ（plan §9.6）。
- 段の間でも、本番はつねに skew policy の範囲内にある。ロールバックは、前の段の porkadot と前の commit の `assets/` で戻す（[0008](0008-approval-and-credentials-for-production-changes.md)）。
- 関連コンポーネントの更新を段にどう挟むかは [0003](0003-critical-and-non-critical-components.md)。containerd は段 1 の前に単独の段として上げた（[0005](0005-containerd-io-2-3-from-docker-apt.md)）。
