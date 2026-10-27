# worker duchamp の停止と復旧（本番 `fraction`、2026-10-27）

本番 `fraction` の worker duchamp（192.168.1.135、Intel NUC8i5BEH）が 2026-10-27 16:51Z ごろに止まり、
23:32Z にユーザーが電源を入れて戻るまで、およそ 6 時間 40 分止まっていた記録。

- 原因の見立て: **duchamp 単体の電源断**。起動時の RTC が 2009-01-01 にリセットされていて、ログに前兆が無く、他のノードは止まっていない（§4）。
  電源断の元（AC アダプタ、コンセント・タップ・プラグ、ボードの電源回路）は分かっていない
- 復旧: ユーザーが物理で電源を入れただけ。ノードが戻ると、Terminating のまま残っていた Pod、Longhorn のボリューム、natsumi-myao は自動で回復した。
  Pod の強制削除は要らなかった（§5）
- 起動後にターボ有効のまま 98℃ まで上がったので、23:43Z に `no_turbo=1` にした（ユーザー承認。再起動で戻る）（§6）
- 再発防止の提案は §7。このリポジトリでは manifest などを何も変えていない。提案の実施はユーザーの承認の後

時刻はすべて UTC。

## 1. 構成

- 本番 `fraction` は 8 台。control-plane は rasp01〜03、worker は braque・chirico・duchamp・oeilvert・pablo。Longhorn のノードは chirico・duchamp・oeilvert・pablo
- duchamp は Intel NUC8i5BEH（NUC8BEB）。SSD 232.9GB（`/`）と HDD 1.8TB（`/var/lib/longhorn`）
- duchamp は 2026-10 上旬に冷却ファン（ブロワー）が壊れ、85〜100℃ で throttle を繰り返していた。交換までターボを止めていた
  （`/sys/devices/system/cpu/intel_pstate/no_turbo` = 1、再起動で 0 に戻る）。新しいファンは届いて交換済みとみられる（停止前 7 日の最高は 78〜80℃）
- 本番にログ収集（Loki・promtail・alloy など）は無い。ノードのログはそのノードの journal と `/var/log` にしか残らない

## 2. 時系列

| 時刻（UTC） | できごと |
|---|---|
| 10-19 09:42:28 | 止まる前の boot の起動（`node_boot_time`） |
| 10-27 16:45:01 | 止まる前の boot の syslog の最後の行（cron の debian-sa1） |
| 16:51:29 | node-exporter の最後の scrape。16:45〜16:51 は普段から syslog に記録の無い時間帯 |
| 16:55:13 | duchamp が NotReady（`Kubelet stopped posting node status`）。taint `node.kubernetes.io/unreachable` |
| 23:2x | ユーザーから「アラートが鳴ってる。ノードの状態がおかしい」と連絡。読み取りだけで調べ始める。作業端末から ping・22/tcp・10250/tcp はどれも `No route to host`（ARP も返らない） |
| 23:26 | まだ `No route to host` で NotReady |
| 23:32:31 | ユーザーが duchamp の電源を入れ、起動 |
| 23:3x | 8 台 Ready。Running・Completed 以外の Pod なし、Longhorn は全ボリューム attached healthy、natsumi-myao-0 が duchamp で 4/4 Running |
| 23:3x | 起動後に coretemp が 51→63→77→89→98℃（`no_turbo=0`） |
| 23:43 | ユーザー承認で `no_turbo=1` |
| 23:45 | coretemp 59〜60℃ |

## 3. 影響

止まっていた間（23:2x 時点の読み取り）:

- Deployment は他のノードに作り直され、全部そろっていた。duchamp 上の Pod（aphrael、fs の `*-restore`、sites、yuanying、Longhorn の CSI・UI・manager など）は
  Terminating の表示のまま残っていた
- Longhorn は 14 ボリュームが healthy。**natsumi/natsumi-myao（`pvc-3a665d04-…`）が attaching / unknown のまま**だった
- `natsumi/natsumi-myao-0`（StatefulSet）が duchamp で Terminating のまま残り、作り直されなかった。**myao はおよそ 16:51Z から 23:3xZ まで止まっていた**
- Longhorn の node duchamp は Ready False

同じ日の 13:11Z に、別の作業で孤児の ClusterRoleBinding 2 つを消している。その時点では 8 台 Ready だった。今回との関係は確かめていないが、
電源断の見立て（§4）からは無関係と考えている。

## 4. 原因

### 4.1 根拠

| 見たもの | 分かったこと |
|---|---|
| 起動時のカーネルのログ | `PM: RTC time: 00:00:17, date: 2009-01-01`。RTC（CMOS）がリセットされていた。ボード上の待機電源とボタン電池の両方が無かったことになる |
| 止まる前の boot の syslog | 最後の行は 16:45:01 の cron。その前にも MCE・watchdog・soft lockup・hung_task・panic・Oops・I/O error・e1000e・thermal の記録は無い |
| 停止直前のメトリクス（16:30〜16:52） | coretemp 48〜52℃、thermal_zone1 48〜49℃。load1 0.25〜1.13。MemAvailable 31.4GB 前後で一定（メモリ使用率 6%）。eno1 は受信 約 20KB/s、受信・送信エラー 0、carrier_changes 2 のまま（リンクのフラップなし）。sda/sdb/sdd の io_time は小さく、`/` は空き 81%、`/var/lib/longhorn` は空き 91%。EDAC のメトリクスは無い |
| 他のノード | `node_boot_time` は 10-18〜10-24 で、16:40〜17:10 の `up` に欠けは無い。同じ時刻に止まったノードは無い |
| 止まっていた間の到達性 | ping・22/tcp・10250/tcp が `No route to host`、ARP も返らない。kubelet だけの停止ではない |

### 4.2 結論

**duchamp 単体の電源断**と見ている。

- ログを残す間もなく止まっていて、RTC がリセットされている。電源が落ちたとすれば両方とも説明できる
- カーネルのハングやパニックなら、syslog に何か残るか、少なくとも RTC はリセットされない。今回はログに何も無く、RTC はリセットされていた
- 熱・メモリ・ディスク・負荷・ネットワークの前兆が無い。停止直前の温度は 48〜52℃ で、ファン故障のときのような熱による停止とは考えにくい
- 他のノードは止まっていないので、家全体の停電ではない
- RTC のリセットは、待機電源が無くなったことに加えて、ボタン電池が切れていたことを示す（推測。電池の電圧は測っていない）

### 4.3 分からなかったこと

- 電源断の元が AC アダプタか、コンセント・タップ・プラグの接触か、ボードの電源回路か
- 止まっていた間の画面と電源 LED。ユーザーへの物理の確認（ファン、AC アダプタ・プラグ、停止時の画面と LED）は、記録の時点で回答が無い
- 電源が戻ったときに自動で起動しなかった理由。CMOS のリセットで BIOS の「After Power Failure」が既定値に戻った可能性があるが、確かめていない（推測）。
  そもそも電源がいつ戻ったのか（ユーザーが入れるまで電源が無かったのか）も分かっていない

## 5. 復旧

### 5.1 実際にやったこと

1. 読み取りだけで状況を調べた（§2、§3）。natsumi-myao-0 の強制削除は、duchamp がボリュームに書き込んでいないと確かめられるまでしない方針にし、
   ノードの復旧を先にした
2. ユーザーが物理で duchamp の電源を入れた（23:32:31Z 起動）
3. ノードが戻ると、Terminating の Pod は片付き、Longhorn のボリュームは attached healthy に戻り、natsumi-myao-0 は duchamp で 4/4 Running になった。
   **Pod の強制削除、cordon・drain、Longhorn の操作は何もしていない**
4. 起動後の温度を見て、`no_turbo=1` にした（§6）

### 5.2 確認

`fraction-auditor`（context `fraction`、読み取りのみ）で:

| 確かめたこと | 方法 | 結果 |
|---|---|---|
| ノード | `kubectl --context fraction get nodes -o wide` | 8 台 Ready |
| Pod | `kubectl --context fraction get pods -A \| grep -Ev 'Running\|Completed'` | 空 |
| Longhorn のボリューム | Longhorn の volume | 全ボリューム attached healthy（natsumi-myao を含む） |
| myao | `natsumi/natsumi-myao-0` | duchamp で 4/4 Running |

Longhorn の node の `Multipathd=False`・`KernelModulesLoaded=False`（dm_crypt）は 4 台とも以前から出ているもので、今回とは関係ない。

### 5.3 調査に使ったもの

- **Prometheus**: `kubectl --context fraction get --raw` で service proxy
  （`/api/v1/namespaces/monitoring/services/http:prometheus-operated:9090/proxy/api/v1/query?...`）を通して読んだ。auditor で読める。
  duchamp の node-exporter は `instance="192.168.1.135:9100"`。16:30〜16:52 の温度（coretemp、thermal_zone）、load1、MemAvailable、eno1 の送受信量とエラーと carrier_changes、
  ディスクの io_time と空き、他のノードの `node_boot_time` と 16:40〜17:10 の `up` を見た（§4.1）
- **syslog の境目**: 前回の boot の最後の行（16:45:01）は `/var/log/syslog` で探した。今回の boot の起動直後の行は 16:54 ごろの時刻を持つので、
  時刻だけで境目を決めると、前回の boot の行と取り違えやすい。今回の boot の始まりは、起動時のカーネルの `PM: RTC time` の行で見分けられる。
  これは、RTC が 2009-01-01 だったため、systemd-timesyncd が `/var/lib/systemd/timesync/clock` の時刻（16:53:56）に時計を戻し、その後 NTP で 23:3x に合わせたからである。
  同じ理由で、`last` と journal の boot の一覧の時刻も乱れている
- **journal**: `journalctl -b -1` は索引が乱れていて、末尾が 10-17 の再起動を指していた。前回の boot は syslog を正とした
- **ノードへの SSH**: IP（`192.168.1.135`）で入り、読み取りだけ行った（`no_turbo` の変更を除く）

## 6. 起動後の温度とターボ

- 起動後、`no_turbo=0`（再起動で戻った状態）のまま coretemp が 51→63→77→89→98℃ まで上がった（load1 2〜3）。停止前 7 日の最高は 78℃。
  ファンの回転数のメトリクスは無く、ファンが回っているかは見ていない
- 23:43Z にユーザーの承認を得て、duchamp で `echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo` を実行した
- 23:45Z に coretemp 59〜60℃（load1 0.15）。停止前の平常は 48〜52℃ で、それよりはまだ高い
- **`no_turbo` は再起動で 0 に戻る。** 次に duchamp を再起動したときは、温度を見て止め直すかを決める必要がある。
  高温のまま再起動するとキー入力待ちで止まり、起動しないことがある

## 7. 再発防止の提案

どれも未実施。実施はユーザーの承認の後。このリポジトリでは何も変えない。

| 提案 | 理由 |
|---|---|
| ボタン電池（CR2032）の交換 | RTC が 2009-01-01 にリセットされていて、電池が切れているとみられる（推測）。電池が切れたままだと、電源が落ちるたびに BIOS 設定と時計が既定値に戻る |
| AC アダプタ・プラグ・タップの点検 | 電源断の元が分かっていない。接触不良やアダプタの劣化なら、また起きる |
| BIOS 設定の確認 | CMOS のリセットで既定値に戻った可能性がある。「After Power Failure」を Power On にして、電源が戻れば自動で起動するようにする。ファン制御と時刻も確かめる |
| `no_turbo` の永続化（systemd unit など）か、ファンの確認 | 起動後にターボ有効で 98℃ まで上がった。交換したはずのファンが働いているかを確かめるか、起動のたびに `no_turbo=1` にする仕組みを置く |
| ログ収集 | 本番にログ収集が無く、停止前のログはそのノードにしか残らない。今回は journal の索引も乱れていて syslog に頼った。ノードが起動しなければログは読めない |
