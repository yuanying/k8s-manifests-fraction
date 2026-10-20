# 本番の cnidaria の CNI plugins のコピーをやめる（2026-10-20）

本番 `fraction` の cnidaria の DaemonSet を、porkadot 0.33.1 のマニフェストにした記録。時刻は UTC。

porkadot 0.33.1 は、0.33.0 に porkadot#48 だけを足したリリース。porkadot が配る cnidaria の DaemonSet から次の 2 つを外す。外した後は、標準の CNI plugins（bridge・host-local・portmap・loopback）を `porkadot install kubelet` だけが置く。

- init container `install-cni-plugins`（cnidaria のイメージの bridge・host-local・portmap を `/opt/cni/bin` へコピーする）
- `/opt/cni/bin` の hostPath（volume `cni-bin`）

| | 前 | 後 |
|---|---|---|
| porkadot | 0.33.0 | **0.33.1**（`1b6a671`、タグ `v0.33.1`） |
| cnidaria の DaemonSet | init container あり、`cni-bin` あり（generation 2） | **どちらも無い**（generation 3） |
| cnidaria のイメージ | `ghcr.io/yuanying/cnidaria-cni:v0.1.1` | 変えない |
| K8s | v1.33.13 | 変えない |
| ノードの `/opt/cni/bin` | CNI plugins v1.9.1（版の印 `v1.9.1`） | 変えない（中身も mtime も同じ） |

- 決めたこと: cnidaria は標準の CNI plugins をコピーしない。持ち主はノードの構築側（porkadot の `install kubelet`）。K8s の段 5（1.34）の前に、ほかの変更と分けて入れる（2026-10-20 ユーザー判断）
- 先に dev で確かめた: porkadot-dev の `docs/cni/cnidaria-no-plugin-copy.md`（porkadot-dev#13。以下「dev の記録」）。この作業は、その「本番に入れるときの手順の案」に沿って流した
- 承認（2026-10-20 ユーザー）: 0.33.1 での render、etcd backup、`porkadot install kubernetes --node 192.168.1.111`、一時的な名前空間での netcheck・npcheck（`infra-admin` の 1h トークン）。✋ の操作の前に coordinator へ知らせた
- porkadot のコマンドとノードへの `ssh` は、すべてサンドボックスの中で流した。ノードへの `ssh` は読み取りだけ
- `install kubelet` は流していない（版の印が同じで、0.33.1 の `install-deps.sh` の差分はコメントだけ）
- 作業の前後の状態、ログ、使ったスクリプトはタスクディレクトリの `notes/cni-no-copy-prod/` にある

## 1. 結果

| 項目 | 結果 |
|---|---|
| render の差分 | `render kubernetes` だけを流した。差分は `assets/kubernetes/manifests/addons/cnidaria/cnidaria.yaml` の init container と `cni-bin` の volume の削除、コメント（4 行足し、26 行消す）だけ。dev の記録の差分と同じ |
| `install kubernetes --node 192.168.1.111` | 1 回目で rc 0（05:04:28〜05:04:53）。generation が変わったのは DaemonSet `cnidaria`（2 → 3）だけ |
| cnidaria の rollout | 8 台が 05:04:47〜05:04:58 に新しい Pod になり、8/8 Ready、restartCount 0。新しい Pod に init container は無く、volume は `cni-conf`・`proc-sys-net`・`xtables-lock` だけ |
| `/opt/cni/bin` | 8 台とも、前と後でファイルの一覧・sha256・大きさ・mtime・版の印が同じ。`/etc/cni/net.d` の conflist の sha256 も同じ |
| ほかの Pod | cnidaria の 8 つ以外の 140 個は、UID も restartCount も前と同じ |
| Running / Completed 以外の Pod | 前も後も 0 |
| Node、etcd | 8/8 Ready、v1.33.13。etcd 3/3 healthy（リーダーは .113 のまま） |
| Longhorn | attached healthy 16、detached unknown 1（`homegallery/cg-data`。前から）。ボリュームの state・robustness・アタッチ先が前と同じ |
| ✋ netcheck | 05:06:37〜05:06:53。新しく作った 8 Pod が 3 秒で Ready。PASS 168 / 168 |
| ✋ npcheck | 05:07:01〜05:09:30。`up` の後の `nft` が 8 台とも 9、`run` は OK 56 / not OK 0、`down` の後の `nft` が 8 台とも 0、名前空間は NotFound |
| LoadBalancer、VIP | gated-v4・gated-v6 が応答（404）、`fs/h2-sshd` と `natsumi/natsumi-sshd`・`-myao`・`-aki`（`::131`〜`::134`、3222）が SSH のバナーを返す、VIP の `/version` が 200。前と同じ |
| NFS、registry | oeilvert の `/home/yuanying/shared/nfs` は `192.168.1.131:/` の nfs4 で中身が読める。braque は 2049 を listen している。`registry.fraction.jp/v2/` は 401（応答あり）。前と同じ |
| 監視 | VIP の `/livez` と gated-v4 を 1 秒ごと（05:04:05〜05:10:03、336 回）。FAIL 0 |
| トークン | 05:06:32 に発行し、05:09:33 にファイルを消した（発行から 1h の 06:06:32 に失効） |

止める条件には一度も当たらず、手順から外れた操作もしていない。

見つけたこと:

1. **今のノードの bridge・host-local・portmap・loopback は、どれも porkadot が置いたもの。** 8 台とも mtime が CNI plugins v1.9.1 の tarball の中の時刻（2026-03-16 14:18Z）だった。cnidaria の init container は `cp` で写すので mtime が新しくなる。段 3（10-19 23:2x〜23:48Z）の `install kubelet` が tarball を展開し直した後に、init container が置き直したものは残っていない。dev の記録の見つけたことの 2 と同じで、持ち主が porkadot だけになってもノードの中身は変わらない
2. **chirico の cnidaria が 1 回だけ `Reconciler error` を出した**（05:07:13、`controller: routes`、`node IPv6 annotation: routes: list addresses: results may be incomplete or inconsistent`）。npcheck の `up` で 24 個の Pod（chirico には 3 つ）を作った瞬間で、netlink のアドレスの一覧が途中でインターフェイスの変化に割り込まれたもの。controller-runtime が再試行し、エラーはそれきり出ていない。8 台とも cnidaria の経路は v4・v6 で 7 本ずつそろっていて、その後の npcheck の `run`（chirico を含む全ノードの間）は合格した。CNI plugins の置き場とは関係ない
3. 本番に、hostNetwork でなく hostPort を使う Pod は無い（portmap は conflist に入っているが、今は使われていない）。hostPort の確認は、dev の記録で済ませたものに任せた

## 2. 流れ

| 時刻 | 操作 | 結果 |
|---|---|---|
| 05:00〜05:01 | 前の確認（読み取り）。8 台の `/opt/cni/bin` と conflist（`tools/cni-bin.sh`）、全 Pod の UID と restartCount、Longhorn、cnidaria の DaemonSet | `s0/`。下の「`/opt/cni/bin`」 |
| 05:02:20 | secrets の本番との突き合わせ（`runbook-stage-4.md` §1.6 の形。読み取り） | 28 項目すべて一致（§3） |
| 05:02:30 | `render kubernetes`（0.33.1） | rc 0。差分は §1 のとおり。`7a99bf0` |
| 05:03 | LoadBalancer・NFS・registry・etcd（読み取り） | すべて応答。etcd 3/3 healthy |
| 05:04:05 | 監視を開始 | |
| 05:04:14 | ✋ `porkadot etcd backup` | rc 0（05:04:17）。§4 |
| 05:04:28 | ✋ `porkadot install kubernetes --node 192.168.1.111` | rc 0（05:04:53）。`daemonset.apps/cnidaria configured` |
| 05:04:47〜05:04:58 | cnidaria の rollout | `rollout status` が `successfully rolled out`（05:05:06） |
| 05:05 | `/opt/cni/bin`・conflist・Pod・generation の比較、cnidaria のログ、LoadBalancer・NFS・registry・etcd | 変わらない（§1） |
| 05:06:32 | ✋ `infra-admin` のトークン（1h）を発行 | |
| 05:06:37〜05:06:53 | ✋ netcheck の `up`・`run`・`down` | PASS 168 / 168。名前空間 `cnidaria-netcheck` は NotFound |
| 05:07:01〜05:09:30 | ✋ npcheck の `nft`・`up`・`nft`・`run`・`down`・`nft` | §1 のとおり |
| 05:09:33 | トークンのファイルを消す | |
| 05:09〜05:10 | 最後の状態（§1 の後の確認をもう一度） | `s2/`。前と同じ（cnidaria の Pod と DaemonSet の generation のほか） |
| 05:10:03 | 監視を止める | FAIL 0 |

`install kubernetes` の出力の `configured` は、`daemonset.apps/cnidaria` のほかに `poddisruptionbudget.policy/kube-controller-manager`・`kube-scheduler`、`daemonset.apps/kube-apiserver`、`validatingwebhookconfiguration…/metallb-webhook-configuration` の 4 つ。dev の記録の `install kubernetes` と同じ 5 行で、段 4 の流し直し（マニフェストが変わらない 2 回目）でも出ていた。kube-apiserver の generation は 27 のままで、rollout は起きていない。毎回 `configured` になる理由は調べていない。

## 3. render と secrets

porkadot 0.33.1 の checkout（`porkadot-dev/porkadot` の `v0.33.1`、Ruby 4.0.7、`bundle install` 済み）で、このリポジトリのルートを cwd にして流した。

```sh
P=/home/yuanying/src/github.com/yuanying/porkadot-dev/porkadot
BUNDLE_GEMFILE=$P/Gemfile bundle exec $P/exe/porkadot render kubernetes --config ./porkadot.yaml
```

- `render kubernetes` だけで足りる。0.33.0 から 0.33.1 で変わったテンプレートは `cnidaria.yaml.erb` と `kubelet-default/install-deps.sh.erb`（コメント 3 行）の 2 つで、後者は `install kubelet` を流すときにしか使わない。`render kubelet` は、毎回作り直される `bootstrap.crt` と etcd の証明書も変えるので流さなかった。`assets/kubelet-default/install-deps.sh` のコメントは、次に `render kubelet` を流すとき（段 5）に入る
- `render all`・`render certs` は使っていない。`porkadot.yaml` は変えていない
- 本番の DaemonSet の `last-applied-configuration` の Pod の spec は、render の前の `cnidaria.yaml` と同じだった。apply で変わるのは render の差分だけ

secrets は `runbook-stage-4.md` §1.6 と同じものを、同じ形（復号をパイプで流してハッシュだけを比べる）で突き合わせた。

| 比べたもの | 本番の側 | 結果 |
|---|---|---|
| `assets/certs/kubernetes/ca.crt` | ConfigMap `default/kube-root-ca.crt` | 一致（`AB:5A:49:9E:…`） |
| `assets/certs/kubernetes/apiserver.crt` | VIP と 192.168.1.111〜113 の 6443 | 4 つとも一致（`4A:E8:7B:B3:…`） |
| `assets/certs/kubernetes/` の 10 ファイル | .111 の kube-apiserver の Pod（`kube-apiserver-6kv5q`）の Secret `kube-apiserver` | 10 ファイルとも一致 |
| `assets/certs/etcd/{ca.crt,etcd-client.crt,etcd-client.key}` | 同じく Secret `etcd-tls` | 3 ファイルとも一致 |
| `assets/kubelet/192.168.1.11{1,2,3}/addons/etcd/{ca.crt,etcd.crt,etcd.key}` | 3 台の `/etc/etcd/pki/` | 9 ファイルとも一致 |
| CA の鍵と証明書（kubernetes、front-proxy、etcd） | — | 3 組とも公開鍵が一致 |

## 4. etcd のバックアップ

- `porkadot etcd backup`（0.33.1）、05:04:14〜05:04:17、rc 0
- `./backup/etcd-2026-10-20T05:04:14+00:00.db`、55,107,616 バイト、モード 0600、sha256 `66b98866b714791bfcb4384689701e3d09a10f2a25e93c7780f0452585a1c086`。段 3・段 4 のバックアップと同じ大きさ
- worktree の `./backup/` にできた（`.gitignore` で除外）。メインの checkout の `backup/` へ移すのは coordinator

## 5. `/opt/cni/bin`

`tools/cni-bin.sh` の出力（8 台。前・後とも同じ）。sha256 は先頭 16 桁、mtime は UTC に直した。

| ファイル | amd64（braque、chirico、duchamp、oeilvert、pablo） | arm64（192.168.1.111〜113） | mtime | `--version` |
|---|---|---|---|---|
| bridge | `3553f5e8f47ed62a` | `35132ed8c8487372` | 2026-03-16 14:18 | `CNI bridge plugin v1.9.1` |
| host-local | `ac5ff19b1120bd1d` | `b1d68ea8f0bbd89b` | 同上 | v1.9.1 |
| portmap | `10cc11a28d9c1646` | `9d41b9e34eed0dbe` | 同上 | v1.9.1 |
| loopback | `02956bdd03b9b716` | `4234e86e220b3e01` | 同上 | `CNI loopback plugin v1.9.1` |
| `.porkadot-cni-plugins-version` | `v1.9.1` | `v1.9.1` | 2026-10-19 23:25〜23:48（段 3 の `install kubelet`。ノードごと） | — |

- ほかに tarball の残り 16 個（bandwidth、dhcp、…、LICENSE、README.md）。全部で 22 ファイル。同じアーキテクチャのノードは sha256 がすべて同じ
- `/etc/cni/net.d` は 8 台とも `10-cnidaria.conflist` の 1 つだけ（sha256 はノードごとに違い、前と後で同じ）

## 6. 戻し方

使っていない。0.33.0（`v0.33.0`）で `render kubernetes` を流し直して `install kubernetes --node 192.168.1.111` を流せば、init container が戻る。init container はノードの bridge・host-local・portmap をイメージのもの（v1.9.1）で置き換えるだけなので、戻しても版は変わらない（dev の記録の「戻し方」）。

## 7. 申し送り

- **cnidaria のイメージから CNI plugins を外したもの（cnidaria-cni#19、v0.1.2 の予定）は、この作業の後なら入れられる。** 本番の DaemonSet にもう init container が無いので、plugins の無いイメージでも Pod は Init で止まらない。本番のイメージを上げるのは別の作業
- §1 の見つけたことの 2（netlink の割り込みのエラー）は、Pod をまとめて作るときに出うる（再試行で直る）。数が増えるようなら cnidaria-cni で、`results may be incomplete` のときに一覧を取り直すかを考える
