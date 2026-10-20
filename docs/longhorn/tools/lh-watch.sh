#!/bin/bash
# Watch Longhorn during an upgrade and print only what changes, every INTERVAL
# seconds (default 2). Read-only. See docs/longhorn/runbook-upgrade-1.12-1.13.md.
#
#   KUBECTL="kubectl --context fraction" lh-watch.sh | tee -a ./longhorn-watch.log
#
# Lines (UTC):
#   <time> vol <name> <state>/<robustness> node=<node> engine=<tag>   a volume changed
#   <time> vol <name> gone                                            a volume disappeared
#   <time> replicas <state>=<count> ...                               Replica CRs by state
#   <time> im <tag>=<count> ...                                       instance managers by image
#   <time> notready <pod> ...                                         longhorn-system pods not Ready
#   <time> ERROR <what>                                               a read failed (retried)
#   <time> ok <n>                                                     every 30 rounds
set -uo pipefail

NS=longhorn-system
KUBECTL=${KUBECTL:-kubectl --context fraction}
INTERVAL=${INTERVAL:-2}

declare -A prev
prev_rep="" prev_im="" prev_nr="-"
n=0
while :; do
    t=$(date -u +%FT%TZ)
    if vols=$($KUBECTL -n "$NS" get volumes.longhorn.io -o json 2>/dev/null |
        jq -r '.items[] | [.metadata.name, .status.state + "/" + .status.robustness,
               "node=" + (.status.currentNodeID // "" | if . == "" then "-" else . end),
               "engine=" + ((.status.currentImage // "-") | sub(".*:"; ""))] | join(" ")'); then
        declare -A seen=()
        while read -r name rest; do
            [ -n "$name" ] || continue
            seen[$name]=1
            [ "${prev[$name]:-}" != "$rest" ] && echo "$t vol $name $rest"
            prev[$name]=$rest
        done <<<"$vols"
        for name in "${!prev[@]}"; do
            [ -n "${seen[$name]:-}" ] || { echo "$t vol $name gone"; unset "prev[$name]"; }
        done
        unset seen
    else
        echo "$t ERROR volumes"
    fi

    if rep=$($KUBECTL -n "$NS" get replicas.longhorn.io -o json 2>/dev/null |
        jq -r '[.items[] | (.status.currentState // "-") + (if (.spec.failedAt // "") != "" then "(failed)" else "" end)]
               | group_by(.) | map(.[0] + "=" + (length | tostring)) | join(" ")'); then
        [ "$rep" != "$prev_rep" ] && echo "$t replicas $rep"
        prev_rep=$rep
    else
        echo "$t ERROR replicas"
    fi

    if im=$($KUBECTL -n "$NS" get instancemanagers.longhorn.io -o json 2>/dev/null |
        jq -r '[.items[] | (.spec.image | sub(".*:"; "")) + ":" + (.status.currentState // "-")]
               | group_by(.) | map(.[0] + "=" + (length | tostring)) | join(" ")'); then
        [ "$im" != "$prev_im" ] && echo "$t im $im"
        prev_im=$im
    else
        echo "$t ERROR instancemanagers"
    fi

    if nr=$($KUBECTL -n "$NS" get pods -o json 2>/dev/null |
        jq -r '[.items[] | select(.status.phase != "Succeeded")
                | select(any(.status.conditions[]?; .type == "Ready" and .status == "True") | not)
                | .metadata.name] | sort | join(" ")'); then
        [ "$nr" != "$prev_nr" ] && echo "$t notready ${nr:-(none)}"
        prev_nr=$nr
    else
        echo "$t ERROR pods"
    fi

    n=$((n + 1))
    (( n % 30 == 0 )) && echo "$t ok $n"
    sleep "$INTERVAL"
done
