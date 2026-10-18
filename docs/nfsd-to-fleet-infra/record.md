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
| `before/nfsd-pod.exportfs-v.txt`、`nfsd-pod.etc-exports.txt`、`nfsd-pod.exports-ls.txt` | 切り替え直前（01:35Z）に旧 Pod の中で取った `exportfs -v`、`/etc/exports`、`/exports` の `ls -la` と `df -h` |

- 旧 image は braque に残っていた（Node の `status.images` に `gcr.io/google_containers/volume-nfs:0.8`、Pod の imageID は `sha256:2173ee90…`）。
  控えの tar は braque の `/root/volume-nfs-0.8.tar`（`docs/worker-os-upgrade/results/braque.md`）
- namespace `nfsd` のラベルは `region=fraction` のまま。`infrastructure/namespace/` は apply しない（このラベルが外れるため）

### 1.3 本番との差

- fleet-infra の `origin/main`（`1130d5c`）の `infrastructure/nfsd/prod` を描画し、3 つのオブジェクトの last-applied と比べた。
  差は DaemonSet の image だけだった
- admin の権限で `kubectl diff -k` を取った（00:46Z）。差は DaemonSet `nfsd` だけで、image と、それに伴う
  `generation`・`deprecated.daemonset.template.generation` の 1 → 2。Service と ServiceAccount は差なし。selector は変わらない
- `kubectl apply -k --dry-run=server` はエラーなく通った

## 2. 切り替え（2026-10-18 01:35Z〜01:37Z、JST 10:35〜10:37）

pablo の OS 更新（drain で docker/registry と fs/h2 が oeilvert へ、fs/h2-restore が duchamp へ移った）が 01:27Z に終わってから行った。
fleet-infra は `origin/main` が `1130d5c` のままであることを確かめ、`git archive origin/main infrastructure/nfsd` で取り出したものを使った。

| 時刻（UTC） | したこと | 結果 |
|---|---|---|
| 01:35 | 時間帯と Pod の確認 | 次の CronJob は 03:38Z の aphrael/tumblr-like（PVC `aphrael-2` で、braque の NFS は使わない）。braque の NFS を使う次の回は 05:44Z の fs/h2-backup。Running・Completed でない Pod は無かった |
| 01:35 | braque の `crictl images` と `/root/volume-nfs-0.8.tar` | 旧 image（`2173ee9074d1b`）も控えの tar も残っていた |
| 01:35:58〜01:36:12 | braque で事前 pull: `sudo /opt/bin/crictl pull registry.k8s.io/e2e-test-images/volume/nfs:1.6.0@sha256:fd050af0…3e29c2` | 14 秒で終わった。image ID は `6b77aa34a2b0e` |
| 01:36:26 | admin で `kubectl diff -k infrastructure/nfsd/prod` を取り直す（`after/kubectl-diff-pre-apply.txt`） | §1.3 と同じ差だった |
| 01:36:55 | `kadmin.sh apply -k infrastructure/nfsd/prod` | `serviceaccount/nfsd unchanged`、`service/nfs unchanged`、`daemonset.apps/nfsd configured`。`infrastructure/namespace/` は apply しなかった |
| 01:36:56〜01:36:58 | `kadmin.sh -n nfsd rollout status ds/nfsd` | 旧 Pod `nfsd-wxsnb` の停止が 01:36:56、新しい Pod `nfsd-vt5k2` の作成が 01:36:57、コンテナの開始が 01:36:58（`after/events.txt`）。image は pull 済みのものを使った（`already present on machine`） |

### 停止時間

**サーバーが止まっていたのはおよそ 12 秒と見ている**（イベントから見積もった値）。内訳は、旧 Pod の停止（01:36:56）から新しいコンテナの開始（01:36:58）までの 2 秒と、
`rpc.nfsd -G 10` の grace の 10 秒。fleet-infra の README の見込み（30 秒前後）より短かったのは、image を事前に pull していたことと、
旧 Pod が 1 秒かからずに止まったためである。

2049 番に 0.5 秒ごとにつなぐ probe を手元で走らせたが、作業環境のサンドボックスがこのコマンドの終了とともに probe を止め、apply の前で途切れていた。
クライアント側から見た停止は測れていない。

## 3. 確認

| 確かめたこと | 方法 | 結果 |
|---|---|---|
| Pod と image | `kubectl -n nfsd get pod`、`logs` | `nfsd-vt5k2` が braque で Running。imageID は `registry.k8s.io/e2e-test-images/volume/nfs@sha256:fd050af0…3e29c2`。ログは `Serving /exports`、`Serving /`、`exportfs: / does not support NFS export`（前と同じ）、`NFS started` |
| `/exports` が tank1 の中身 | Pod の中で `ls -la /exports`、`df -h /exports`（`after/nfsd-pod.exports-ls.txt`） | `tank1/export`（15T、使用 5.1T）。エントリは前と同じ。違いは `index.html` の時刻（起動のたびに書かれる）と、gid 33 の表示名（新しい image の `/etc/group` では `tape`）だけ |
| エクスポートの設定 | `/etc/exports`、`exportfs -v`、`/proc/fs/nfs/exports`（`after/`） | `/etc/exports` は前と同じ。`exportfs -v` は表記が変わった（新しい nfs-utils は既定値の `sync`・`hide` も出す）。カーネルに入った `/exports` の設定は `rw,insecure,no_root_squash,sync,wdelay,no_subtree_check,fsid=0`。前の `exportfs -v` と同じオプションで、有効な違いは無い。NFS の版は `+3 +4 +4.1 +4.2` |
| クライアントの読み書き | fs/data-restore（chirico、`192.168.1.131:/data` を `vers=4.2,hard` で `/backup` にマウント）で 16 MiB を書いて読み、消す。もう一度書き、nfsd の Pod の中から `/exports/data/` のその file の md5 を見て、消す | 書いた md5 と読んだ md5、サーバー側の md5 がすべて一致した。file は root の持ち主で作られた（`no_root_squash` が効いている）。消した file はサーバーからも消えていた |
| stale file handle による CrashLoop | 01:38Z と 01:41Z に `kubectl get pods -A` | 起きなかった。carib2・pondo2・shja2 の movies の再起動回数は 5 のまま（braque の OS 更新のときのもの）。movies のログに error・stale は無かった |
| movies のほかのクライアント | carib の nginx の中で `ls` | 読めた（122 エントリ） |
| `registry.fraction.jp` | `curl https://registry.fraction.jp/v2/`。docker/registry の Pod（oeilvert、`192.168.1.131:/docker-registry` を `/var/lib/registry` にマウント）の中で保存先を読む | `/v2/` は 401（認証の要求で、registry は応答している）。保存先の repositories（3 つ）が見え、`llm-wiki:latest` の manifest の blob を読んで sha256 が名前と一致した。実際の pull は試していない |
| fs の各サービス | fs/h2-restore・sites-restore・data-restore の中で、`*.fs.svc.cluster.local:/`（`/original`）と braque の NFS（`/backup`）を `ls` | すべて読めた（h2 16、sites 27、data 14 エントリ） |
| oeilvert のホストのマウント | `ssh yuanying@192.168.1.82` で `findmnt` と `ls /home/yuanying/shared/nfs` | `192.168.1.131:/` が `vers=4.2,soft,timeo=60,retrans=5` でマウントされたまま、`ls` で中身が見えた |
| 次のバックアップ CronJob | 05:44Z（JST 14:44）の fs/h2-backup を待つ | （待っている） |

## 4. 戻し方

selector は同じなので、どちらの向きでも DaemonSet の置き換えは要らない。

1. 旧 image が braque の containerd（namespace `k8s.io`）に残っていることを確かめる。消えていたら braque で
   `/root/volume-nfs-0.8.tar` を `ctr -n k8s.io images import` で戻す。旧 image は registry から pull できないので、braque 以外では動かせない
2. `before/daemonset-nfsd.last-applied.json` を `kubectl apply -f` する。k8s-manifests-fraction の `nfsd/` はこの移行で消したので、
   fleet-infra の README にある「`nfsd/` を `kubectl apply -k`」は使えない（`base` の commit を戻して描画しても同じものになる）
3. §3 の確認をもう一度行う

## 5. fleet-infra の README の下書きとの違い

- `kubectl diff` の出力では、`last-applied-configuration` の注釈は変更行として出なかった（README は image と注釈の差が出ると書いている）
- 「test での検証」の表は、新しい image の `exportfs -v` が本番の旧 image と同じだと書いている。本番では表記が違った（新しい image は既定値の `sync`・`hide` も出し、
  旧 image は `rw`・`insecure`・`no_root_squash` を 2 回出していた）。有効なオプションは同じ（§3）
- 「戻し方」の 2 は k8s-manifests-fraction の `nfsd/` の `kubectl apply -k` を挙げているが、この移行で `nfsd/` を消したので使えない。
  §4 のとおり `before/daemonset-nfsd.last-applied.json` を使う
- 停止時間の見込み（30 秒前後）より短かった（§2 の「停止時間」）。事前に pull すれば image の pull の分は足されない
- README の「確かめること」の 2 に挙がっている `fs/data-restore` の読み書きは、そのとおりにできた

## 6. 残っていること

- braque の containerd の旧 image（`gcr.io/google_containers/volume-nfs:0.8`）と `/root/volume-nfs-0.8.tar` は戻すときのために残した。
  消すかどうかは、新しい image でしばらく問題が出ないことを見てから決める
- `base` submodule（k8s-base）の `nfsd/` はそのまま残っている（ユーザーの決定で触らない）
