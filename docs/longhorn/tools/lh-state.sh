#!/bin/bash
# Save the state of Longhorn to a directory, to compare before and after an
# upgrade (diff two directories). Read-only. See
# docs/longhorn/runbook-upgrade-1.12-1.13.md.
#
#   KUBECTL="kubectl --context fraction" lh-state.sh <out-dir>
#
# Files (TSV, sorted):
#   volumes.tsv        name, namespace/pvc, state, robustness, node, replicas,
#                      spec.image, status.currentImage, frontend, access mode
#   replicas.tsv       name, volume, node, state, failedAt, instance manager, image
#   engines.tsv        name, volume, node, state, instance manager, image
#   instancemanagers.tsv  name, node, image, state, pod IP
#   engineimages.tsv   name, image, state, refCount
#   pods.tsv           longhorn-system pods: name, uid, node, phase, restarts, images
#   settings.tsv       name, value
#   crds.tsv           Longhorn CRDs: name, status.storedVersions
#   networkpolicies.tsv  name, podSelector, ingress from selectors (JSON)
#   others.txt         orphans, backing images, system backups, backups, snapshots
# The last lines on stdout are a summary.
set -euo pipefail

NS=longhorn-system
KUBECTL=${KUBECTL:-kubectl --context fraction}
out=${1:?usage: lh-state.sh <out-dir>}
mkdir -p "$out"

get() { $KUBECTL -n "$NS" get "$1" -o json; }

get volumes.longhorn.io | jq -r '.items[] | [.metadata.name,
    ((.status.kubernetesStatus.namespace // "-") + "/" + (.status.kubernetesStatus.pvcName // "-")),
    .status.state, .status.robustness, (.status.currentNodeID // "" | if . == "" then "-" else . end),
    (.spec.numberOfReplicas | tostring), .spec.image, (.status.currentImage // "-"),
    .spec.frontend, .spec.accessMode] | @tsv' | sort > "$out/volumes.tsv"
get replicas.longhorn.io | jq -r '.items[] | [.metadata.name, .spec.volumeName, .spec.nodeID,
    (.status.currentState // "-"), (.spec.failedAt // "" | if . == "" then "-" else . end),
    (.status.instanceManagerName // "" | if . == "" then "-" else . end),
    (.status.currentImage // "" | if . == "" then "-" else . end)] | @tsv' | sort > "$out/replicas.tsv"
get engines.longhorn.io | jq -r '.items[] | [.metadata.name, .spec.volumeName,
    (.spec.nodeID // "" | if . == "" then "-" else . end), (.status.currentState // "-"),
    (.status.instanceManagerName // "" | if . == "" then "-" else . end),
    (.status.currentImage // "" | if . == "" then "-" else . end)] | @tsv' | sort > "$out/engines.tsv"
get instancemanagers.longhorn.io | jq -r '.items[] | [.metadata.name, .spec.nodeID, .spec.image,
    (.status.currentState // "-"), (.status.ip // "-")] | @tsv' | sort > "$out/instancemanagers.tsv"
get engineimages.longhorn.io | jq -r '.items[] | [.metadata.name, .spec.image, (.status.state // "-"),
    (.status.refCount // 0 | tostring)] | @tsv' | sort > "$out/engineimages.tsv"
$KUBECTL -n "$NS" get pods -o json | jq -r '.items[] | [.metadata.name, .metadata.uid,
    (.spec.nodeName // "-"), .status.phase,
    ([.status.containerStatuses[]?.restartCount] | add // 0 | tostring),
    ([.spec.containers[].image | sub(".*/"; "")] | join(","))] | @tsv' | sort > "$out/pods.tsv"
get settings.longhorn.io | jq -r '.items[] | [.metadata.name, .value] | @tsv' | sort > "$out/settings.tsv"
$KUBECTL get crd -o json | jq -r '.items[] | select(.spec.group == "longhorn.io")
    | [.metadata.name, (.status.storedVersions | join(","))] | @tsv' | sort > "$out/crds.tsv"
$KUBECTL -n "$NS" get networkpolicies -o json | jq -r '.items[] | [.metadata.name,
    (.spec.podSelector | tojson), ([.spec.ingress[]?.from[]?.podSelector] | tojson)] | @tsv' |
    sort > "$out/networkpolicies.tsv"
{
    for r in orphans backingimages systembackups backups snapshots; do
        echo "$r $($KUBECTL -n "$NS" get "$r.longhorn.io" -o name | wc -l | tr -d ' ')"
    done
} > "$out/others.txt"

echo "volumes: $(awk -F'\t' '{print $3 "/" $4}' "$out/volumes.tsv" | sort | uniq -c | xargs)"
echo "volume engines: $(awk -F'\t' '{sub(/.*:/, "", $8); print $8}' "$out/volumes.tsv" | sort | uniq -c | xargs)"
echo "replicas: $(awk -F'\t' '{print $4 ($5 == "-" ? "" : "(failed)")}' "$out/replicas.tsv" | sort | uniq -c | xargs)"
echo "instance managers: $(awk -F'\t' '{sub(/.*:/, "", $3); print $3 ":" $4}' "$out/instancemanagers.tsv" | sort | uniq -c | xargs)"
echo "engine images: $(awk -F'\t' '{sub(/.*:/, "", $2); print $2 ":" $3 ":" $4}' "$out/engineimages.tsv" | xargs)"
echo "pods not Running: $(awk -F'\t' '$4 != "Running"' "$out/pods.tsv" | wc -l | tr -d ' ')"
echo "CRDs: $(wc -l < "$out/crds.tsv" | tr -d ' '), storedVersions: $(cut -f2 "$out/crds.tsv" | sort | uniq -c | xargs)"
echo "network policies: $(wc -l < "$out/networkpolicies.tsv" | tr -d ' '), with region in a selector: $(grep -c '"region"' "$out/networkpolicies.tsv" || true)"
echo "$(xargs < "$out/others.txt")"
