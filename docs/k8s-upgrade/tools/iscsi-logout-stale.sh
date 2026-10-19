#!/bin/sh
# Log out the Longhorn iSCSI sessions left on a drained node, before
# anything restarts iscsid. Copied from porkadot-dev
# docs/longhorn/iscsi-stale-sessions.md section 4.2 (dev, 2026-10-19).
#
#   ssh <user>@<node> 'sudo sh -s' < docs/k8s-upgrade/tools/iscsi-logout-stale.sh
#   ssh <user>@<node> 'sudo sh -s -- <instance-manager IP to keep>' < ...
#
# WRITES (iscsiadm logout / node record delete). Run it only on a node that
# is drained: no instance-manager and no attached Longhorn volume, so every
# Longhorn session there is stale. With an argument, sessions to that portal
# IP are kept.
# FAILED (error 32) means iscsid was restarted after the session was left;
# the fix is section 4.3 of the same document (drain, then let iscsid give up).
keep="${1:-}"
iscsiadm -m session 2>/dev/null | awk '$4 ~ /^iqn\.2019-10\.io\.longhorn:/ {
    sid = $2; gsub(/[][]/, "", sid); split($3, p, ","); print sid, p[1], $4 }' |
while read -r sid portal target; do
    ip=${portal%:*}
    [ -n "$keep" ] && [ "$ip" = "$keep" ] && continue
    if iscsiadm -m session -r "$sid" -u; then
        iscsiadm -m node -T "$target" -p "$portal" -o delete || true
    else
        echo "FAILED sid=$sid target=$target portal=$portal" >&2
    fi
done
iscsiadm -m session
