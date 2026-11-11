# audit の policy の見直し（status の subresource を Metadata に）を入れた記録（2026-11-11）

[手順書](../runbook-status-metadata.md) §7 の記録。形は[元の手順書](../runbook.md) §10 に合わせた。時刻はすべて UTC。ここに書くのは集計だけで、audit のログの中身は写していない。

## 結果

- 3 台とも新しい policy の ConfigMap `kube-apiserver-audit-policy-97tmd5m5gk` を mount した Pod で Ready、restart は 0。`updateStrategy` は `RollingUpdate`（`maxSurge: 0`・`maxUnavailable: 1`）に戻り、全体の `kubectl diff -k assets/kubernetes` は差分なし
- 止める条件（元の手順書 §3.4 の 1〜5・7、手順書 §3.1 の 8・9）には、どの台も当たらなかった。ただし 1 台目の後には 8・9 を確かめられず、2 台目の後に確かめた（「手順書との差」）
- status の subresource への書き込みは、新しい Pod の後は 3 台とも `Metadata` だけになった。status 以外への、部品ではない身元の書き込みは `Request` のまま
- 3 台の合計の増え方は、約 **49.9 MB/時から約 22.8 MB/時** に減った（約 54% 減）

## 承認と知らせ

- 開始（✋✋）は本人が承認した。PR #79 は `5aab123` でマージ済みで、その master で流した。§1.4 の `git status --short assets porkadot.yaml` は空
- ✋ の手順（`OnDelete` と apply、3 台それぞれの入れ替え、`RollingUpdate` に戻す）は、それぞれの前に coordinator に知らせてから行った。1 台目の 30 分の確かめの結果も知らせた
- 1 台目の後に一度止めて報告し、coordinator の判断を受けてから 2 台目に進んだ（「手順書との差」）
- etcd のバックアップは、手順書 §1 のとおり取らなかった。porkadot のコマンドは 1 つも流していない

## 前提とベースライン（§1、10:56〜11:28Z）

- DaemonSet は generation 35・3/3 Ready・`RollingUpdate`（`maxSurge: 0`、`maxUnavailable: 1`）、image は v1.37.2。3 つの Pod はどれも ConfigMap `kube-apiserver-audit-policy-2gd9b4f598` を mount し、restart 0（前回の記録の Pod のまま）
- ほかの本番の作業が control plane と kube-system を触っていないことを確かめた（kube-system の Pod で前回の後に入れ替わったものは無い）
- VIP と 3 台の `/readyz` は `ok`。8 台とも Ready、etcd は 3/3 healthy
- 3 台ともルートの fs の空きは 106 GiB。.113 は前回から 2 回、ログが回っていた（`audit-*.log` が 3 つ）
- 旧 Pod のログの `E` の行は、前回の記録の起動時のもの（空の manifest、metrics-server の解決）だけだった

### 増え方（元の手順書 §5 の測り方、10:57:48〜11:28:13Z）

| node | 増え方 |
|---|---|
| .113 | 約 38.6 MB/時 |
| .112 | 約 11.3 MB/時 |
| .111 | ほぼ 0 |
| 合計 | 約 49.9 MB/時 |

回ったファイルも足して測った（.113 は 11:19Z ごろに 1 回回った）。

### status の出来事（3 台それぞれの直近 2 万行、10:57Z）

| node | status の出来事 | level の内訳 | 大きさの合計 | 2 万行の大きさに占める割合 |
|---|---|---|---|---|
| .113 | 4868 件 | Request 4762・Metadata 106 | 約 38.4 MB | 約 63% |
| .112 | 169 件 | Request 2・Metadata 167 | 約 0.15 MB | 約 0.5% |
| .111 | 0 件（ファイル全体で 46 行） | — | — | — |

status への書き込みが最も多かった .113 を 1 台目にした。`Request` の status の出来事は 1 件あたり約 8 KB だった。

## 差分（§2、10:58Z）

`kubectl diff` は手順書の「出てよいもの」だけだった。ConfigMap `kube-apiserver-audit-policy-97tmd5m5gk` の新規作成（label は前と同じ、中身は前の policy に status の規則と説明のコメントが増えたもの）と、DaemonSet の volume `audit-policy` の ConfigMap の名前、generation の繰り上げ。Service 2 つには差分が無く、古い ConfigMap も出なかった。

## 入れ替え（§3）

| 手順 | 時刻 | 結果 |
|---|---|---|
| token の発行 | 10:58:04Z | 3 時間の期限、モード 600 のファイル。`auth can-i` は 3 つとも yes |
| `OnDelete` | 11:28:47Z | generation 36。Pod の UID は変わらず |
| apply | 11:29:00Z | ConfigMap は created、DaemonSet は configured、Service 2 つは unchanged。generation 37、`OnDelete` のまま、Pod の UID は変わらず |
| 1 台目 .113 | 11:29:14Z に削除 | 新 Pod `kube-apiserver-svttc`、11:30:10Z ごろ Ready（削除から約 1 分） |
| 1 台目の観察 | 11:31〜12:06Z（37 分） | 止める条件なし。ただし 8・9 は確かめられず、止めて報告した（下） |
| 2 台目 .112 | 12:08:25Z に削除 | 新 Pod `kube-apiserver-n4p85`、12:09:27Z ごろ Ready |
| 8・9 の確かめ | 12:09〜12:12Z | .113 に両方の種類の出来事が来て、通った（下） |
| 3 台目 .111 | 12:13:05Z に削除 | 新 Pod `kube-apiserver-ktc2k`、12:13:56Z ごろ Ready |
| `RollingUpdate` | 12:14:47Z | generation 38、`updatedNumberScheduled` 3、Pod は入れ替わらず。全体の `kubectl diff` は差分なし |
| token の破棄 | 12:14:59Z | ファイルを消した |

入れ替えのたびに、VIP の `/readyz` が `ok` であることと、etcd が 3/3 であることを確かめた。.111 を消した直後に、作業端末の読み取りが 1 回 `apiserver is shutting down` を受けた（VIP から止まりかけの .111 に振られたもの）。

### 1 台目の観察（11:31〜12:06Z、2 分おき）

| # | 条件 | 結果 |
|---|---|---|
| 1 | Ready にならない・restart | 約 1 分で Ready、37 分間 restart 0 |
| 2 | `audit` を含む `E` の行 | なし |
| 3 | `audit.log` が無い・大きくならない | 新しい Pod の出来事が書かれ、伸びた |
| 4 | 機微のリソースに本文が付く | 0 件 |
| 5 | VIP の `/readyz`・etcd | 17 回とも `ok`。etcd は 3/3 |
| 7 | 新しい種類の `E` の行が続けて出る | 起動時の行だけで、続けては出なかった（前回の記録と同じ種類） |
| 8 | status への書き込みで `Request` のもの | 0 件。ただし status への書き込みそのものが 0 件 |
| 9 | status 以外への部品ではない身元の書き込みで `Metadata` のもの | 0 件。ただし部品ではない身元の書き込みそのものが 0 件 |

新しい Pod の起動から 37 分で .113 に来た出来事は 45 件だけで、どれも部品の書き込みか読みだった。入れ替えで、長く続く接続がほかの台に移ったためである。古い Pod の .112 で `Request` になっている種類（Argo CD の Application への `patch`、Longhorn の CR の status の `update` など）は、.113 には 1 件も来なかった。手順書 §3.1 の「判断がつかなければ止めて報告する」で止めた。

### 8・9 の確かめ（2 台目の後）

2 台目を入れ替えると、.112 の接続が移り、新しい policy の .113 に両方の種類の出来事が来た。11:29:50Z〜12:11:45Z の .113 の出来事で数えた。

- 8: status への書き込みは 9 件で、どれも `Metadata`。そのうち 4 件は部品ではない身元の、CRD の CR の status への `patch`（前の policy なら `Request`）。`Request` は 0 件
- 9: status 以外への、部品ではない身元の書き込みは 35 件で、どれも `Request`（Argo CD の Application への `patch`）。`Metadata` は 0 件
- 部品の `Request`、部品の読み、機微のリソースの本文は 0 件

通ったので 3 台目に進んだ。

## ログが書かれていることの確かめ（3 台がそろった後、12:45〜12:47Z）

元の手順書 §4 の 1〜5 と、手順書 §3.1 の確かめを、3 台について新しい Pod の起動の後の出来事で行い、どれも通った。

- 1: `audit.log` は root の 0600。.113 と .112 は 20 秒で伸びた。.111 は要求がほとんど来ず、20 秒では伸びなかったが、新しい Pod の出来事（88 件）が書かれていた
- 2: 末尾の行は `audit.k8s.io/v1` の JSON で、stage は `ResponseComplete` か `ResponseStarted` だけ
- 3〜5: 内訳は下の表。部品の `Request`、部品の読み、機微のリソースの本文、probe・events・leases の `update` は 3 台とも 0 件

| node | 数えた出来事 | Metadata | Request | status への書き込み | そのうち部品ではない身元 | status 以外への部品ではない身元の書き込み |
|---|---|---|---|---|---|---|
| .113（11:29:45Z〜） | 6737 | 6320 | 417 | 915（すべて Metadata） | 845 | 417（すべて Request） |
| .112（12:08:58Z〜） | 5383 | 5366 | 17 | 786（すべて Metadata） | 753 | 17（すべて Request） |
| .111（12:13:37Z〜） | 88 | 83 | 5 | 0 | 0 | 5（すべて Request） |

3 台とも `E` の行は起動時のもの（空の manifest。.113 は metrics-server の解決も）だけで、その後は出ていない。

## 増え方（§3.2、3 台がそろった後の 12:15:06〜12:45:29Z）

| node | 前（10:57〜11:28Z） | 後（12:15〜12:45Z） | 上限 1.1 GB で残る日数のめやす（後） |
|---|---|---|---|
| .113 | 約 38.6 MB/時 | 約 15.8 MB/時 | 約 2.9 日 |
| .112 | 約 11.3 MB/時 | 約 12.9 MB/時 | 約 3.5 日 |
| .111 | ほぼ 0 | ほぼ 0 | — |
| 合計 | 約 49.9 MB/時 | 約 22.8 MB/時 | — |

- 5 分おきに測り、どの区間もほぼ一定の傾きだった
- 3 台の合計は約 54% 減った。前に status の書き込みが量の大半を占めていた .113 は約 59% 減で、手順書の見込み（半分ほど）どおりだった。台ごとの偏りは入れ替えで変わったので、比べるのは合計と、下の status の出来事の大きさにする

### status の出来事の大きさ

| | 前（直近 2 万行、10:57Z） | 後（新しい Pod の起動から 12:47Z まで） |
|---|---|---|
| .113 | 4868 件・約 38.4 MB（全体の約 63%） | 933 件・約 1.49 MB（全体の約 14%） |
| .112 | 169 件・約 0.15 MB | 797 件・約 1.27 MB（全体の約 15%） |
| .111 | 0 件 | 0 件 |
| 1 件あたり | `Request` 約 8 KB | `Metadata` 約 1.6 KB |

前と後で数えた時間の長さが違うので、件数と大きさの合計はそのままは比べられない。1 件あたりの大きさが約 5 分の 1 になり、量に占める割合が約 63% から約 15% に下がった。

### 1 日目の測定

**未測定。** 手順書 §3.2 の「1 日目にもう一度測る」は、この記録の後に行う。

## 手順書との差

- **1 台目の後に、8・9 を確かめられなかった。** 手順書 §3.1 は、1 台目に部品ではない身元の書き込みが来なかったときは、ほかの台と見比べるとしている。しかし .113 には status への書き込みも部品ではない身元の書き込みも 1 件も来ず、見比べられなかった。「判断がつかなければ止めて報告する」で止め、coordinator の判断で 2 台目に進んだ。2 台目の後、新しい policy の .113 に両方の種類の出来事が来たことを数で確かめ、8・9 が通ってから 3 台目に進んだ。規則が外れていたとしても影響はログの level だけで、API server の可用性には関わらない
- ほかは手順書どおり

## 申し送り

- **1 日目の測定は未測定**（上）
- 古い ConfigMap `kube-apiserver-audit-policy-2gd9b4f598` は残っている（手順書 §4。消していない）
- 増え方は約半分になったが、.113 と .112 に残るのは 3 日前後の見込みで、7 日分を残す目安（1 台で約 6.5 MB/時）にはまだ届かない。いまの量の大半は `Metadata` の出来事で（.113 の新しい Pod の後の分で約 93%）、`Request` は約 7%（その大半が Argo CD の Application への `patch`）しかない。さらに減らすなら、`Request` の規則ではなく、`Metadata` で残している読みの側を見直すことになる（.113 の `Metadata` の大きさの約 83% が `watch`・`get`・`list` で、`watch` だけで約 65%）
