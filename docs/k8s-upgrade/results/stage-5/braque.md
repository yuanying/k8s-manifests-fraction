# braque の段 5 の作業記録

braque（192.168.1.131）の kubelet を、porkadot 0.34.1 の `install kubelet --node` で v1.34.12 に上げた記録。手順は `../../runbook-stage-5.md`（以下 runbook）。drain していない。
時刻は UTC。worker の 3 台目。前は `pablo.md`、次は `oeilvert.md`。読み取りの出力はタスクディレクトリの `notes/stage-5/braque/`。項目の形は `duchamp.md` と同じ。

## 1. 事前の読み取り（2026-10-20 10:22:06Z）

| 項目 | 結果 |
|---|---|
| クラスタ | 8 台 Ready（v1.34.12 は control-plane 3 台、duchamp、pablo）。etcd 3/3 healthy、3.6.15。Running / Completed 以外の Pod は 0。Longhorn は 16 + 1 |
| 対象のノード | v1.33.13。iscsid 85966、10-19 08:06:03Z。Longhorn のノードではない（セッション・エンジン・ボリュームなし） |
| 時間帯、nfsd | 10:22Z（JST 19:22）。runbook §5.4 のバックアップの CronJob の時間帯の外。CronJob は 8 個でベースラインと同じ、動いている Job は無い。`nfsd/nfsd-vt5k2` は Running、`nfsd=2` |
| Pod の控え | `pods-pre.tsv`（5 個: cnidaria、kube-proxy、node-exporter、smart-exporter、nfsd） |
| 告知している LoadBalancer | なし |

## 2. `install kubelet`

- 開始 10:22:25Z、終わり 10:23:04Z（39 秒）、rc 0。サンドボックスの中で流した
- `install-deps.sh` 10.2 秒、`install-pkgs.sh` 18.4 秒、`install.sh` 6.7 秒。kubelet の再起動 10:23:04Z

## 3. 確認（10:23:59Z）

| # | 確認 | 結果 |
|---|---|---|
| 1、2 | Node、バイナリ | v1.34.12。`kubelet-v1.34.12`、`kubectl-v1.34.12`、`crictl-v1.34.0`、`etcdctl-3.6.15`、`etcdutl-3.6.15`。CNI は `v1.9.1` のまま |
| 3 | iscsid | 85966 のまま |
| 7 | Pod の再起動 | **差分なし**（5 個。nfsd も `nfsd=2` のまま） |
| 10 | cnidaria | `verify-nodes.sh` 64 PASS、FAIL 0。braque の cnidaria の error 8（runbook §8.1） |
| 11 | kubelet のログ | 起動のときのものだけ |
| 12 | 監視の FAIL | 0 |
| NFS、registry | oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で中身が読める。braque は 2049 を listen している。`registry.fraction.jp/v2/` は 401（応答あり） |
| 4〜6、13〜15 | ほか | Longhorn は 16 + 1 のまま、再起動なし、CSR なし |

## 4. 次の 1 台へ進む条件

すべて合格。

## 5. 手順書との差、気づいたこと

- なし
