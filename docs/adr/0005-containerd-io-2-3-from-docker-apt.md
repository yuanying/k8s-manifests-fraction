# 0005. containerd は Docker の apt リポジトリの containerd.io を 2.3 系に pin し、K8s の段の前に上げる

- Date: 2026-10-18（config を version 3 のまま残すことは 2026-10-30 にあらためて決めた）
- Status: Accepted

## Context

本番の 8 台は Ubuntu 24.04 の `containerd` 2.2.1 と runc 1.3.4 で動いていた。最終目標の K8s 1.37 の containerd の推奨表は 2.4.0+ / 2.3.0+ で、2.2 は入らない。containerd 2.2 の upstream の EoL は 2026-11-06、runc 1.3 は 2026-10 末だった（`docs/k8s-upgrade/plan.md` §3、§5）。

- 2.3 は LTS（2028-04-30 まで）で、1.36 と 1.37 の推奨表に入り、2.2 から直接上げられる。2.4 は 2.2 から直接は上げられず（2.3 を経る）、保守期間も短い。
- Ubuntu の archive には 2.3 が無い（24.04 は 2.2.1、26.04 でも 2.2.2）。
- containerd 2.3 の `config default` は config の version 4 を出す。2.3 は version 3 も読み、起動時に移す。2.2.1 は version 4 を読めない。
- porkadot は containerd を入れない。`setup-containerd` は config を書くだけで、版の行のある config は作り直さない。

## Decision

- **containerd は 2.3 系（LTS）の最新パッチにする。入手元は Docker の apt リポジトリの `containerd.io` で、apt の pin で 2.3 系に固定する**（`/etc/apt/preferences.d/containerd-io` に `Pin: version 2.3.*`）。pin が無いと `apt full-upgrade` で 2.4 系に上がる。deb なので apt で入れ替えも戻しもでき、runc も同梱される。upstream の tarball は、apt の管理の外になるので予備にとどめる。
- **K8s の段 1 の前に、K8s 1.29 のまま単独の段（段 C）として上げる。** 以後の段の dev の検証と本番を、最終形の containerd の上で行う。段 C の間は K8s・porkadot・etcd を変えず、問題が出たら containerd だけを疑えるようにする。
- **`/etc/containerd/config.toml` は version 3 のまま残す。** 2.2.1 へ戻すときに config に触らずに済む。`containerd.io` を入れるときは `--force-confold` で手元の config を残す（`containerd.io` の conffile は CRI を無効にしている）。
- **version 4 への作り直しは、このアップグレードでは行わない**（2026-10-30）。残課題として Wiki の `wiki/synthesis/cluster-upgrade-plan-2026.md` の TODO に載せる。
- 2.3 のパッチは自動では上がらない（unattended-upgrades は Docker の origin を対象にしない）。**セキュリティ修正があるときだけ、K8s の段の合間に** 段 C と同じ手順で 1 台ずつ上げる（plan §5.8）。
- oeilvert の Ubuntu の `docker.io` は `containerd.io` と両立しないので、Docker の `docker-ce` に移す。
- control-plane を作り直したときに 2.2 系に戻らないよう、k8s-env の `raspi/` の cloud-init も `containerd.io` 2.3 系を pin して入れる形にする。

## Consequences

- 2026-10-18 に 8 台を 2.3.6（runc 1.5.1）にした。apt が `containerd` と `runc` を外して `containerd.io` を入れるだけで、config とイメージはそのまま、kubelet の再起動で Pod は再起動しなかった（`docs/k8s-upgrade/results/stage-c/`、porkadot-dev の `docs/k8s-upgrade/verification-stage-c.md`）。
- 段 1〜8 は、最終形の containerd の上で検証と本番を通せた。
- `containerd.io` のパッチは人が追う必要がある。Docker の `containerd.io` は upstream より遅れて出る。
- 今の 8 台は、version 3 の config を containerd 2.3 が読み込むときに移している。**version 4 に作り直すときの注意**: 1 台ずつ config を退避してから porkadot の `setup-containerd --node` で作らせる。作り直した後は、2.2.1 へ戻すときに退避した version 3 の config が要る（2.2.1 は version 4 を読めない。plan §5.7、§10）。作り直しが済んだら、段 C で取った戻し用の控えと、apt に `rc` で残る 2.2.1 を片付けてよい。
- k8s-env の `raspi/` の cloud-init は k8s-env#7 で直した。新しく作る control-plane には既存の config が無いので、porkadot の `setup-containerd` が version 4 の config を作る。既存の 8 台とは config の版が分かれる（k8s-env の `raspi/README.md`）。
- Docker のリポジトリが有効だと、将来の `do-release-upgrade` で拒否されることがある。OS を上げるときに、その手順でリポジトリの扱いを決める。
