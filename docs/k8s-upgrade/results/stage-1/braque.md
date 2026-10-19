# braque の段 1 の作業記録

braque（192.168.1.131）の kubelet を、porkadot 0.30.0 の `install kubelet --node` で v1.30.14 に上げた記録。手順は `../../runbook-stage-1.md`（以下 runbook）。
時刻は UTC。worker の 3 台目。前は `duchamp.md`。

## 1. 事前の読み取り（2026-10-19 01:17:12Z〜）

### 1.1 クラスタ

| 項目 | 結果 |
|---|---|
| Node | 8 台 Ready。v1.30.14 のノード: control-plane 3 台、pablo、duchamp、v1.29.8 のノード: braque、chirico、oeilvert |
| etcd、VIP | 3/3 healthy、リーダー .113、3 台とも 3.5.34。`/readyz`: `ok` |
| Running / Completed 以外の Pod | 0 個 |
| Longhorn | attached healthy 23、detached（ベースラインのもの）: 2 |
| Longhorn の設定 | `replica-auto-balance`: `disabled` |
| MetalLB の告知ノード | duchamp の後と同じ（VIP: pablo、gated: chirico ほか）。braque には speaker が無い |
| 時間帯 | 01:17Z（JST 10:17）。NFS を使う CronJob の時間帯（runbook §5.1）の外 |

### 1.2 対象のノード

| 項目 | 値 |
|---|---|
| Node | Ready、v1.29.8、`containerd://2.3.6` |
| `/opt/bin` の向き先 | kubelet: `kubelet-v1.29.8`、kubectl: `kubectl-v1.29.8`、etcdctl: `etcdctl-3.5.12`、crictl: `crictl-v1.29.0`。CNI の印: 無い |
| Pod の名前・UID・再起動回数（控え） | 5 個（`nfsd/nfsd-vt5k2` 1、cnidaria 3、kube-proxy 0、node-exporter 3、smart-exporter 3） |
| Longhorn の replica | なし（Longhorn のノードではない） |
| そのノードが告知している LoadBalancer | なし |

## 2. etcd のリーダー

なし（worker）。

## 3. `install kubelet`（runbook §5.2 の 2）

- 開始 01:17:38Z、終わり 01:18:19Z、rc 0。サンドボックスの外で流した（runbook §8.10）
- `install-deps.sh` 10.8 秒、`install-pkgs.sh` 19.4 秒、`install.sh` 6.8 秒。どれも `successful`
- `install.sh` の `dns` の addon が 01:18:12Z に `systemd-networkd` を再起動し（enp1s0 は DHCPv4 で 192.168.1.131 を取り直した）、kubelet の再起動は 01:18:19Z

## 4. 確認（runbook §5.3。01:18Z〜01:20Z）

| # | 確認 | 結果 |
|---|---|---|
| 1 | Node | Ready、v1.30.14、`containerd://2.3.6` |
| 2 | バイナリ | `kubelet-v1.30.14`、`kubectl-v1.30.14`、`crictl-v1.30.1`（etcdctl も `etcdctl-3.5.34`）。CNI の印 `v1.4.1`。`kubelet-v1.29.8`・`kubectl-v1.29.8` も残っている |
| 3 | Pod の再起動 | 5 個とも名前・UID・再起動回数が控えと同じ（nfsd も再起動していない） |
| 4 | Longhorn | attached healthy 23、detached 2。replica の置き場所と instance-manager が控えと同じ |
| 5 | cnidaria | 8 台の Pod が 1/1。`verify-nodes.sh` 64 PASS、FAIL 0。braque の cnidaria が `Reconciler error` を 8 件、ほかの 7 台が info の `no route for a family` を 2 件ずつ（runbook §8.1） |
| 6 | MetalLB の speaker | braque には無い |
| 7 | kubelet のログ | 古い kubelet（pid 1694）が 01:18:13Z に 1 回 `Failed to update lease ... read tcp 192.168.1.131:37180->192.168.1.101:6443: read: connection reset by peer`（下の 7 の 1 つ目）。新しい kubelet は起動の直後（01:18:19Z）の `invalid capacity 0 on image filesystem`、crio の factory、checkpoint が無い、だけ |
| 8 | 監視の FAIL | 0 |
| 9 | 告知していた LoadBalancer | なし。`check-apps.sh` はベースラインと同じ、LoadBalancer はすべて応答する |

ノードごとの追加の確認（braque）: nfsd の Pod `nfsd-vt5k2` が Running（再起動 0 のまま）で、ホストが 2049 を listen している。NFS の PV は Bound 14、Released 3（ベースラインのとおり）。NFS の PV を使う Pod も含めて Running / Completed 以外の Pod は 0 個。oeilvert のホストの `/home/yuanying/shared/nfs` が読める。`registry.fraction.jp/v2/` は 401（応答あり）。

leader election で再起動した controller は無い（01:17:38Z より後に終わったコンテナは 0）。warning のイベントは braque の `InvalidDiskCapacity` だけ。

## 5. 監視の FAIL と、その原因

なし。

## 6. 次の 1 台へ進む条件（runbook §5.3）

| 条件 | 結果 |
|---|---|
| §5.3 の 1〜9 とノードごとの確認 | すべて合格 |
| 全 8 台の Node が Ready。終えたノードが v1.30.14、まだのノードが v1.29.8 | 合格 |
| etcd 3/3 healthy、VIP が応答する | 合格 |
| Running / Completed 以外の Pod がベースラインから増えていない | 合格（0 個） |
| Longhorn のボリュームが healthy | 合格 |

## 7. 手順書との差、気づいたこと

- braque では `systemd-networkd` の再起動で、古い kubelet の VIP への接続が 1 回 reset され、lease の更新が 1 回失敗した（lease の更新は 10 秒ごとにやり直される。Node の `NodeNotReady` のイベントは 01:18:19Z の kubelet の再起動のときの 1 回だけで、これはどの台でも kubelet の再起動のたびに出ている）。braque の enp1s0 は DHCP で、再起動のたびにアドレスを取り直す。pablo と duchamp の kubelet のログには同じものは無かった。害は無い
