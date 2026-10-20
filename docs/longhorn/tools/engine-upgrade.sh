#!/bin/bash
# Upgrade the engine of one Longhorn volume to a new engine image and wait
# until it is done. See docs/longhorn/runbook-upgrade-1.12-1.13.md.
#
#   KUBECTL="kubectl --context fraction --token=..." \
#     engine-upgrade.sh <volume> <engine image> [--dry-run]
#
# <engine image> is the full name, the same as the engine image's spec.image
# and the setting default-engine-image (docker.io/longhornio/longhorn-engine:vX.Y.Z).
#
# An attached volume is upgraded live, a detached one stays detached and only
# its spec.image changes. The script WRITES the volume's spec.image, unless
# --dry-run (server-side dry run, admission webhooks included). Before writing
# it checks that the volume is attached and healthy, or detached; that the
# engine image is deployed; and that the number of Replica CRs equals
# spec.numberOfReplicas. Then it prints every change of the volume's state
# until status.currentImage is the new image, the Replica CRs are back to
# spec.numberOfReplicas and an attached volume is healthy again.
#
# Exit status: 0 done, 1 refused or failed (nothing written, or the volume
# became faulted), 2 timeout (TIMEOUT seconds, default 600).
set -euo pipefail

NS=longhorn-system
KUBECTL=${KUBECTL:-kubectl --context fraction}
TIMEOUT=${TIMEOUT:-600}
INTERVAL=${INTERVAL:-2}

die() { echo "ERROR: $*" >&2; exit 1; }
now() { date -u +%T; }

[ $# -ge 2 ] && [ $# -le 3 ] || die "usage: engine-upgrade.sh <volume> <engine image> [--dry-run]"
vol=$1; img=$2; dry=${3:-}
case "$dry" in ""|--dry-run) ;; *) die "unknown option: $dry" ;; esac

# state robustness currentImage spec.image numberOfReplicas currentNodeID
volume_state() {
    $KUBECTL -n "$NS" get volumes.longhorn.io "$vol" -o json |
        jq -r '[.status.state, .status.robustness, (.status.currentImage // "-"),
                .spec.image, (.spec.numberOfReplicas | tostring),
                (.status.currentNodeID // "" | if . == "" then "-" else . end)] | @tsv'
}

replica_crs() {
    $KUBECTL -n "$NS" get replicas.longhorn.io -l "longhornvolume=$vol" -o name | wc -l | tr -d ' '
}

IFS=$'\t' read -r st rob cur spec reps node < <(volume_state)
[ "$cur" != "$img" ] || die "$vol already runs $img"
[ "$spec" != "$img" ] || die "$vol spec.image is already $img (an upgrade is in progress?)"
case "$st/$rob" in
    attached/healthy) mode=live ;;
    detached/*) mode=offline ;;
    *) die "$vol is $st/$rob; a live upgrade needs attached/healthy, an offline one detached" ;;
esac
ei=$($KUBECTL -n "$NS" get engineimages.longhorn.io -o json |
    jq -r --arg i "$img" '[.items[] | select(.spec.image == $i) | .status.state] | first // "missing"')
[ "$ei" = deployed ] || die "engine image $img is not deployed ($ei)"
n=$(replica_crs)
[ "$n" = "$reps" ] || die "$vol has $n Replica CRs, numberOfReplicas is $reps"

patch="{\"spec\":{\"image\":\"$img\"}}"
echo "$(now) $vol $st/$rob node=$node $cur -> $img ($mode)"
if [ -n "$dry" ]; then
    $KUBECTL -n "$NS" patch volumes.longhorn.io "$vol" --type=merge -p "$patch" \
        --dry-run=server -o jsonpath='{.spec.image}{"\n"}'
    exit 0
fi

start=$(date +%s)
$KUBECTL -n "$NS" patch volumes.longhorn.io "$vol" --type=merge -p "$patch"
last=""
while :; do
    # A failed read (API not answering for a moment) is printed and retried.
    out=""
    if out=$(volume_state) && n=$(replica_crs); then
        IFS=$'\t' read -r st rob cur spec reps node <<<"$out"
    else
        echo "$(now) could not read $vol, retrying"
        out=""
        last=""
    fi
    if [ -n "$out" ]; then
        line="$st/$rob node=$node current=${cur##*:} replicaCRs=$n/$reps"
        [ "$line" != "$last" ] && echo "$(now) $line" && last=$line
        [ "$rob" = faulted ] && die "$vol is faulted"
        if [ "$cur" = "$img" ] && [ "$n" = "$reps" ]; then
            if [ "$mode" = offline ] || [ "$st/$rob" = attached/healthy ]; then
                break
            fi
        fi
    fi
    if [ $(( $(date +%s) - start )) -ge "$TIMEOUT" ]; then
        echo "$(now) TIMEOUT after ${TIMEOUT}s" >&2
        exit 2
    fi
    sleep "$INTERVAL"
done
echo "$(now) done in $(( $(date +%s) - start ))s"
