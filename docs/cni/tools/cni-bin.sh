#!/usr/bin/env bash
# Read-only state of the CNI plugins on every fraction node, for a before / after comparison
# (docs/cni/cnidaria-no-plugin-copy.md):
#   - every file in /opt/cni/bin: sha256, size, mtime (the node's local time zone), name
#   - the porkadot version mark (.porkadot-cni-plugins-version)
#   - what bridge, host-local, portmap and loopback report with --version
#   - sha256 of the conflists in /etc/cni/net.d (sudo: the directory is root 0700)
#
#   docs/cni/tools/cni-bin.sh <out dir>     writes <out dir>/cni-<node>.txt
#
# Compare two runs with `diff -r <before> <after>`: nothing should differ.
set -u
unset LC_ALL   # the control-plane Pis have no en_US.UTF-8 locale
NODES=(
  "192.168.1.111 ubuntu@192.168.1.111"
  "192.168.1.112 ubuntu@192.168.1.112"
  "192.168.1.113 ubuntu@192.168.1.113"
  "braque yuanying@192.168.1.131"
  "chirico yuanying@192.168.1.83"
  "duchamp yuanying@192.168.1.135"
  "oeilvert yuanying@192.168.1.82"
  "pablo yuanying@192.168.1.134"
)
out=${1:?usage: $0 <out dir>}
mkdir -p "$out"
for e in "${NODES[@]}"; do
  read -r name target <<<"$e"
  ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$target" 'export LC_ALL=C; cd /opt/cni/bin && echo "mark: $(cat .porkadot-cni-plugins-version 2>/dev/null || echo none)"
    for f in * .??*; do [ -f "$f" ] && printf "%s %10s %s %s\n" "$(sha256sum "$f" | cut -c1-64)" "$(stat -c %s "$f")" "$(stat -c %y "$f")" "$f"; done
    for p in bridge host-local portmap loopback; do printf "%-10s %s\n" $p "$(./$p --version 2>&1 | head -1)"; done
    echo "== /etc/cni/net.d"
    sudo -n sh -c "sha256sum /etc/cni/net.d/*"' > "$out/cni-$name.txt" 2>&1
  echo "$name rc=$? $(head -1 "$out/cni-$name.txt") files=$(grep -cE '^[0-9a-f]{64} ' "$out/cni-$name.txt")"
done
