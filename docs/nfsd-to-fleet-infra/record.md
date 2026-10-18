# nfsd の fleet-infra への移行と image の切り替え（本番 `fraction`、2026-10-18）

本番 `fraction` の NFS サーバー（namespace `nfsd` の DaemonSet `nfsd`、braque だけで動く）の定義を
k8s-manifests-fraction から fleet-infra の `infrastructure/nfsd` に移し、image を
containerd 2.x で pull できるものに替えた記録。

- 定義と手順の正: fleet-infra の `infrastructure/nfsd/README.md`（PR #192、main `1130d5c`）。image の選定理由、
  test クラスタでの検証、クライアントの使い方はそちらにある
- この記録: 本番で実際に行ったことと、その結果
- 本番への反映は Flux ではなく手作業の `kubectl apply -k`（fleet-infra の Flux は test クラスタだけ）

| | 切り替え前 | 切り替え後 |
|---|---|---|
| 定義の場所 | k8s-manifests-fraction の `nfsd/`（`base/nfsd` に `commonLabels: region: fraction`） | fleet-infra の `infrastructure/nfsd/prod` |
| image | `gcr.io/google_containers/volume-nfs:0.8`（Docker schema 1。containerd 2.x で pull できない） | `registry.k8s.io/e2e-test-images/volume/nfs:1.6.0`（digest `sha256:fd050af0…3e29c2` で固定） |

k8s-manifests-fraction の overlay `nfsd/` は消した。`base` submodule（k8s-base）の `nfsd/` には触っていない。

## 1. 切り替え前の読み取り（2026-10-18 00:35Z〜00:47Z）

### 1.1 時間帯

`kubectl get cronjobs -A` の schedule と timeZone は `docs/worker-os-upgrade/runbook.md` §2.1.1 の表から変わっていなかった。
止めてはいけない時間帯（JST）は 05:15〜06:45、14:30〜15:00、16:45〜17:05、17:55〜18:15 のまま。

### 1.2 旧定義の控え

`before/` に置いた。戻すときはこれを使う（§4）。

| ファイル | 中身 |
|---|---|
| `before/daemonset-nfsd.yaml`、`service-nfs.yaml`、`serviceaccount-nfsd.yaml` | `kubectl get -o yaml` の出力 |
| `before/*.last-applied.json` | 各オブジェクトの `kubectl.kubernetes.io/last-applied-configuration`（2022-12-13 の client-side apply の内容） |
| `before/nfsd-pod.log` | 切り替え前の nfsd の Pod（`nfsd-wxsnb`）のログ |
| `before/kubectl-diff.txt` | §1.3 の `kubectl diff` の出力 |

- 旧 image は braque に残っていた（Node の `status.images` に `gcr.io/google_containers/volume-nfs:0.8`、Pod の imageID は `sha256:2173ee90…`）。
  控えの tar は braque の `/root/volume-nfs-0.8.tar`（`docs/worker-os-upgrade/results/braque.md`）
- namespace `nfsd` のラベルは `region=fraction` のまま。`infrastructure/namespace/` は apply しない（このラベルが外れるため）

### 1.3 本番との差

- fleet-infra の `origin/main`（`1130d5c`）の `infrastructure/nfsd/prod` を描画し、3 つのオブジェクトの last-applied と比べた。
  差は DaemonSet の image だけだった
- admin の権限で `kubectl diff -k` を取った（00:46Z）。差は DaemonSet `nfsd` だけで、image と、それに伴う
  `generation`・`deprecated.daemonset.template.generation` の 1 → 2。Service と ServiceAccount は差なし。selector は変わらない
- `kubectl apply -k --dry-run=server` はエラーなく通った

## 2. 切り替え

（未実施。pablo の OS 更新が終わってから行う）

## 3. 確認

（未実施）

## 4. 戻し方

selector は同じなので、どちらの向きでも DaemonSet の置き換えは要らない。

1. 旧 image が braque の containerd（namespace `k8s.io`）に残っていることを確かめる。消えていたら braque で
   `/root/volume-nfs-0.8.tar` を `ctr -n k8s.io images import` で戻す。旧 image は registry から pull できないので、braque 以外では動かせない
2. `before/daemonset-nfsd.last-applied.json` を `kubectl apply -f` する。k8s-manifests-fraction の `nfsd/` はこの移行で消したので、
   fleet-infra の README にある「`nfsd/` を `kubectl apply -k`」は使えない（`base` の commit を戻して描画しても同じものになる）
3. §3 の確認をもう一度行う

## 5. fleet-infra の README の下書きとの違い

- `kubectl diff` の出力では、`last-applied-configuration` の注釈は変更行として出なかった（README は image と注釈の差が出ると書いている）

## 6. 残っていること

（切り替えの後に書く）
