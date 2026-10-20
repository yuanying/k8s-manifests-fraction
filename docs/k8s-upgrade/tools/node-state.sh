#!/usr/bin/env bash
# Read-only state of one node, taken before and after `porkadot install kubelet`.
# Run it as root on the node:
#
#   ssh <user>@<node> 'sudo bash -s' < docs/k8s-upgrade/tools/node-state.sh > <file>
#
# Prints:
#   bin      where /opt/bin/{kubelet,kubectl,crictl,etcdctl,etcdutl} point
#            (<name>:none when the link is missing; porkadot 0.34 adds etcdutl)
#   cni      the porkadot version mark and `--version` of the plugins in use
#   iscsid   MainPID and ActiveEnterTimestamp (MainPID=0: not running, socket activated)
#   session  one line per iSCSI session: sid, portal, target
#   engine   one line per Longhorn engine: start time, volume, and
#            `older-than-iscsid` when it started before the running iscsid
#            (such an engine cannot log out on detach with Longhorn v1.11.2,
#            porkadot-dev docs/longhorn/iscsi-stale-sessions.md section 4.1)
#   initiatorname  md5 of /etc/iscsi/initiatorname.iscsi
set -u
export LC_ALL=C

echo "bin $(for b in kubelet kubectl crictl etcdctl etcdutl; do t=$(readlink /opt/bin/$b) && basename "$t" || echo "$b:none"; done | tr '\n' ' ')"
echo "cni mark=$(cat /opt/cni/bin/.porkadot-cni-plugins-version 2>/dev/null)" \
  "$(for p in bridge host-local portmap loopback; do printf '%s=%s ' $p "$(/opt/cni/bin/$p --version 2>&1 | head -1 | awk '{print $NF}')"; done)"
echo "iscsid $(systemctl show iscsid -p MainPID -p ActiveEnterTimestamp | tr '\n' ' ')"
iscsiadm -m session 2>/dev/null | awk '{ sid = $2; gsub(/[][]/, "", sid); split($3, p, ","); print "session", sid, p[1], $4 }'
iscsid_start=$(date -d "$(systemctl show iscsid -p ActiveEnterTimestamp --value)" +%s 2>/dev/null || echo 0)
ps -C longhorn -o lstart=,args= | awk -v t="$iscsid_start" '/ controller pvc-/ {
    for (i = 1; i <= NF; i++) if ($i == "controller") vol = $(i + 1)
    cmd = "date -d \"" $1 " " $2 " " $3 " " $4 " " $5 "\" +%s"; cmd | getline s; close(cmd)
    print "engine", strftime("%FT%TZ", s, 1), vol, (t > 0 && s < t) ? "older-than-iscsid" : ""
  }'
echo "initiatorname $(md5sum < /etc/iscsi/initiatorname.iscsi | cut -c1-12)"
