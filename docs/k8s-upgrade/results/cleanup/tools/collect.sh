#!/bin/bash
# usage: collect.sh <node> <user@ip> <outdir>
set -euo pipefail
unset LC_ALL
node=$1; host=$2; out=$3
mkdir -p "$out"
C='sudo -n /opt/bin/crictl --runtime-endpoint unix:///run/containerd/containerd.sock --image-endpoint unix:///run/containerd/containerd.sock'
ssh -o BatchMode=yes -n "$host" "$C images -o json" > "$out/images.json"
ssh -o BatchMode=yes -n "$host" "$C ps -a -o json" > "$out/ps.json"
ssh -o BatchMode=yes -n "$host" "$C pods -o json" > "$out/pods.json"
ssh -o BatchMode=yes -n "$host" "$C ps -q --state Running | wc -l" > "$out/running.txt"
ssh -o BatchMode=yes -n "$host" "df -B1 / | tail -1; df -h / | tail -1; sudo -n du -sh /var/lib/containerd /opt/bin 2>/dev/null" > "$out/df.txt"
ssh -o BatchMode=yes -n "$host" "ls -la /opt/bin; for l in kubelet kubectl crictl etcdctl etcdutl; do echo LINK \$l \$(readlink /opt/bin/\$l); done" > "$out/optbin.txt"
ssh -o BatchMode=yes -n "$host" "sudo -n ls -la /root/ /var/lib/kubelet/ /etc/apt/sources.list.d/ /usr/share/keyrings/ 2>&1; sudo -n grep -rn 'docker' /etc/apt/sources.list.d/ /etc/apt/sources.list 2>/dev/null" > "$out/misc.txt"
ssh -o BatchMode=yes -n "$host" "sudo -n ctr -n k8s.io containers ls" | awk 'NR>1{print $2}' | sort -u > "$out/ctr-images.txt"
ssh -o BatchMode=yes -n "$host" "sudo -n grep -h \"sandbox = \" /etc/containerd/config.toml" | sed "s/.*= *'//; s/'.*//" > "$out/sandbox.txt"
test -s "$out/ctr-images.txt"; test -s "$out/sandbox.txt"
echo "collected $node"
