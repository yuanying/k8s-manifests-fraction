#!/bin/bash
# usage: run_node.sh <node> <user@ip> plan|delete|after
set -euo pipefail
unset LC_ALL
node=$1; host=$2; step=$3
T=$(cd "$(dirname "$0")" && pwd)   # this directory
W=${WORK:-/tmp/k8u-cleanup}; R=$W/run/$node
TSV=${TSV:-$T/../../cleanup-survey/images-plan.tsv}
C='sudo -n /opt/bin/crictl --runtime-endpoint unix:///run/containerd/containerd.sock --image-endpoint unix:///run/containerd/containerd.sock'
case $step in
plan)
  rm -rf "$R/before"; $T/collect.sh "$node" "$host" "$R/before" 2>/dev/null
  python3 $T/plan.py "$node" "$R/before" "$TSV"
  python3 $T/plan_optbin.py "$R/before"
  date -u +%FT%TZ > "$R/plan-time.txt"
  ;;
delete)
  # re-collect right before deleting and require the same rmi list
  rm -rf "$R/pre"; $T/collect.sh "$node" "$host" "$R/pre" 2>/dev/null
  python3 $T/plan.py "$node" "$R/pre" "$TSV" >/dev/null
  cmp <(sort "$R/before/rmi.txt") <(sort "$R/pre/rmi.txt") || { echo "rmi list changed; stop"; exit 1; }
  date -u +%FT%TZ > "$R/delete-start.txt"
  ssh -o BatchMode=yes "$host" "while read i; do $C rmi \$i >/dev/null 2>&1 && echo removed \$i || echo FAIL \$i; done" < "$R/pre/rmi.txt" > "$R/rmi-result.txt"
  if [ -s "$R/before/optbin-rm.txt" ]; then
    ssh -o BatchMode=yes -n "$host" "sudo -n rm -v -- $(tr '\n' ' ' < "$R/before/optbin-rm.txt")" > "$R/optbin-result.txt"
  fi
  date -u +%FT%TZ > "$R/delete-end.txt"
  echo "removed $(grep -c ^removed "$R/rmi-result.txt") FAIL $(grep -c ^FAIL "$R/rmi-result.txt" || true) optbin $(wc -l < "$R/optbin-result.txt" 2>/dev/null || echo 0)"
  ;;
after)
  rm -rf "$R/after"; $T/collect.sh "$node" "$host" "$R/after" 2>/dev/null
  echo "running before $(cat $R/pre/running.txt) after $(cat $R/after/running.txt)"
  echo "df before: $(sed -n 2p $R/before/df.txt)"; echo "df after:  $(sed -n 2p $R/after/df.txt)"
  grep LINK "$R/after/optbin.txt"
  ssh -o BatchMode=yes -n "$host" "systemctl is-active kubelet containerd; for b in kubelet kubectl crictl etcdctl; do /opt/bin/\$b --version 2>/dev/null | head -1 || /opt/bin/\$b version 2>/dev/null | head -1; done" || true
  python3 - "$R" <<'EOF'
import json,sys
R=sys.argv[1]
tags=lambda d:{t for i in json.load(open(f"{R}/{d}/images.json"))["images"] for t in (i.get("repoTags") or [])}
ids=lambda d:{i["id"] for i in json.load(open(f"{R}/{d}/images.json"))["images"]}
keep=[l.split("\t") for l in open(f"{R}/pre/rmi-detail.tsv").read().splitlines()[1:] if l.startswith("keep")]
missing=[k[1] for k in keep if k[2] not in ids("after")]
print("kept images missing after:", missing)
rm=set(open(f"{R}/pre/rmi.txt").read().split())
print("rmi ids still present:", sorted(rm & ids("after")))
print("images before", len(ids("pre")), "after", len(ids("after")))
EOF
  ;;
esac
