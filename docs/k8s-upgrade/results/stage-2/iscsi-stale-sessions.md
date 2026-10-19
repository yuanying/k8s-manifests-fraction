# 段 2 の drain の後に残った iSCSI のセッション

段 2 の oeilvert の drain の後に、Longhorn のボリューム 4 つが chirico へのアタッチのたびに faulted になり、それを使う Pod が 20 分ほど止まった件の記録。原因、影響、対処（ユーザーの承認を得て runbook から外れて行ったもの）を書く。時刻は UTC。手順は `../../runbook-stage-2.md`（以下 runbook）。

## 1. 何が起きたか

- 08:34:22Z〜08:41:26Z に oeilvert を drain した（`oeilvert.md` §3）。oeilvert から退いた Pod は、cordon されていない pablo・duchamp・chirico に移った
- そのうち 4 つのボリューム（`hedgedoc/data-db-postgresql-0`、`fraction-agents/data-web-researcher-0`、`open-webui/open-webui`、`homegallery/tumblr-data`（RWX、share-manager 経由））は、chirico にアタッチしようとするたびに `Engine of volume ... dead unexpectedly, setting v.Status.Robustness to faulted` になり、`FailedAttachVolume`（DeadlineExceeded）を繰り返した。Longhorn が Pod を消し、Pod が chirico で作り直されて、また失敗した
- エンジンのログ（chirico の instance-manager）:

  ```
  failed to init frontend: device pvc-8eb75c08-...: failed to stop iSCSI device: failed to logout target:
  ... iscsiadm -m node -T iqn.2019-10.io.longhorn:pvc-8eb75c08-... --logout ...
  iscsiadm: Could not logout of [sid: 6, target: ..., portal: 10.244.8.88,3260].
  iscsiadm: initiator reported error (32 - target likely not connected)
  ```

## 2. 原因

- chirico のホストに、**chirico の drain（08:09:50Z）の前の instance-manager の Pod の IP（10.244.8.88）への iSCSI のセッションが 15 本**残っていた（`iSCSI Session State: FREE`、`Internal iscsid Session State: REOPEN`）。drain の後の instance-manager は 10.244.8.165 で、10.244.8.88 にはもう誰も居ない
- エンジンは起動のときに、同じ iqn の既存のセッションを logout しようとする。相手が居ないので logout が失敗し、エンジンが落ちる。chirico に古いセッションを持つボリュームは、chirico にアタッチできない
- 同じ形の古いセッションは duchamp に 2 本（10.244.5.26。`data-gmail-agent-0`、`export-minio-3`）、oeilvert に 2 本（`natsumi`、`natsumi-aki`）残っていた。pablo には無かった
- Wiki の `wiki/topics/自宅クラスター.md` にある既知の問題（drain の後、消えた instance-manager への iSCSI セッションが `TRANSPORT WAIT` で残る。ノードの再起動で消える。2026-10-03 の pablo でも、アタッチできなくなった）と同じもの
- **段 C は drain の後にノードを再起動していたので表に出なかった。段 2 は drain の後に再起動しない手順にしたので、古いセッションが残ったまま、そのノードに同じボリュームがアタッチされると失敗する**。pablo・duchamp・chirico の作業の直後は、退いたボリュームが元のノードに戻らなかったので当たらず、oeilvert の drain でボリュームが chirico に寄ったときに当たった

## 3. 影響

| ボリューム | 使う Pod | 止まっていた時間 | データ |
|---|---|---|---|
| `hedgedoc/data-db-postgresql-0` | `hedgedoc/db-postgresql-0` | 08:34:28Z（drain で止まった）〜08:54:04Z | PostgreSQL は 08:34:28Z にきれいに止まり、08:54:04Z の起動で `database system was shut down at 08:34:28` から起きた。hedgedoc の server は前から 0 replica なので、text.fraction.jp は前から 503 |
| `fraction-agents/data-web-researcher-0` | `web-researcher-0` | 08:34Z ごろ〜08:56Z ごろ | 損失なし（Longhorn の replica は chirico と oeilvert に残っていた） |
| `open-webui/open-webui` | `open-webui-0`（chatllm.fraction.jp） | 08:34Z ごろ〜08:56Z ごろ | 同上 |
| `homegallery/tumblr-data`（RWX） | `tumblr-web` の 1 つ | 08:34Z ごろ〜08:57Z | 同上。もう 1 つの `tumblr-web` は動いていた |

どのボリュームも、faulted を繰り返す間、running の replica（chirico か duchamp）と、oeilvert の stopped の replica（08:34〜08:35Z の時点）が残っていた。Longhorn が replica を消したり作り直したりしたものは無い（`concurrent-replica-rebuild-per-node-limit` は `0`）。

## 4. 対処（2026-10-19 のユーザーの承認。runbook から外れる操作）

1. 08:53:26Z、chirico を cordon（一時的）。08:53:27Z、止まっていた 4 つの Pod（`db-postgresql-0`、`web-researcher-0`、`open-webui-0`、`tumblr-web-...-6xnfl`）を消した
   - 作り直された Pod は pablo と duchamp に載り、4 つのボリュームは 08:54:15Z までにアタッチされた（tumblr-data の share-manager は duchamp）。08:57:10Z までに 4 つとも Running。chatllm.fraction.jp は 200
2. oeilvert は `install kubelet` の後、uncordon の前に再起動した（09:00:36Z → Ready 09:03:08Z）。再起動の後の `iscsiadm -m session` は `No active sessions.`（`oeilvert.md` §5）
3. chirico と duchamp を、1 台ずつ段 C の手順（Longhorn の設定の切り替え、最後の replica の workload を止める、drain、再起動、確認、uncordon、設定を戻す、再同期）で再起動した（§5）。再起動の後の `iscsiadm -m session` は、どちらも `No active sessions.`

## 5. chirico と duchamp の再起動

| | chirico | duchamp |
|---|---|---|
| 最後の replica と止めたもの | `prometheus-...-0`（pvc-625c8825）。Prometheus を 0（09:11:47Z、09:12:00Z に detached） | なし |
| Longhorn の設定の切り替え | 09:11:44Z（`0`、`allow-if-replica-is-stopped`） | 09:35:23Z（`0` だけ） |
| cordon | 08:53:26Z（§4 の 1 のまま） | 09:35:27Z |
| drain | 09:12:00Z〜09:12:34Z（31 個を evict、`Cannot evict` 5 回） | 09:35:27Z〜09:36:04Z（40 個、`Cannot evict` 7 回）。tumblr-data の share-manager が chirico に移る間、`tumblr-web` の 1 つが 09:37:27Z まで Init |
| drain の後 | アタッチ 0、退いた Pod は全部 Running（`gmail-agent-0` は oeilvert に載り、duchamp の古いセッションには当たらなかった） | アタッチ 0、退いた Pod は全部 Running |
| 再起動 | 09:13:36Z → SSH 09:15:47Z → Ready 09:15:57Z | 09:37:34Z → SSH 09:42:56Z（すぐに `no_turbo` を `1` に戻した。温度は 74℃ → 62℃） |
| 再起動の後 | v1.31.14、`containerd://2.3.6`。cnidaria Ready、`verify-nodes.sh` 全 PASS、iSCSI のセッション 0、FORWARD の先頭が `CNIDARIA-FWD`、`iscsid.socket`・`multipathd` active、failed の unit 無し、`porka-dummy01` に 10.254.0.10 | 同じ |
| uncordon、戻したもの | 09:17:26Z。Prometheus を 2（09:17:55Z に 2/2）、設定を `5`・`block-if-contains-last-replica` に戻した | 09:44:30Z。設定を `5` に戻した |
| 再同期 | 09:35:01Z（17 分半） | 10:15:45Z（31 分） |
| netcheck | （duchamp の後にまとめて流した） | 168/168 PASS（10:15:52Z） |

- `infra-admin` のトークンは 08:33:25Z に発行したもの（3h）を oeilvert から duchamp まで使い、10:16:09Z にファイルを消した
- 監視の FAIL は §4・§5 の間 0
- 10:16Z の時点で、4 台のホストの iSCSI のセッションは、今の instance-manager（pablo 10.244.4.131、chirico 10.244.8.216、duchamp 10.244.5.112、oeilvert 10.244.7.116）へのものだけ

## 6. 段 3 以降へ

- runbook-stage-2 §5.2・§8.12 に「drain した台は、uncordon の前に再起動して古い iSCSI のセッションを消す」を足した。段 3 以降で同じ drain をするなら、drain → `install kubelet` → 再起動 → uncordon の形にする
- 再起動しない方法（古いセッションだけを消す。`iscsiadm` の node の記録の削除や、sysfs からの session の削除）は、dev で確かめてから検討する（タスクのバックログ）
- 再起動の代わりに、drain の後に `iscsiadm -m session` で古いセッションが無いことを確かめ、残っていれば止める、という確認も手順に入れた
