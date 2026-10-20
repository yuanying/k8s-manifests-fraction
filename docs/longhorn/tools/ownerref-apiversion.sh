#!/bin/bash
# Rewrite the apiVersion of a Longhorn ownerReference that still says
# longhorn.io/v1beta1 (no longer served since Longhorn v1.10.0) to
# longhorn.io/v1beta2. Only the apiVersion changes; kind, name, uid and the
# other fields are kept. See docs/longhorn/gc-and-orphans.md section 2.
#
#   KUBECTL="kubectl --context fraction" ownerref-apiversion.sh list
#   KUBECTL="kubectl --context fraction --token=..." \
#     ownerref-apiversion.sh fix  <resource> <name> [--dry-run]
#   KUBECTL=... ownerref-apiversion.sh undo <resource> <name> [--dry-run]
#
# <resource> is engines.longhorn.io, sharemanagers.longhorn.io or services
# (namespace longhorn-system). `list` only reads. `fix` and `undo` WRITE one
# object, unless --dry-run (server-side dry run, admission webhooks included).
# `undo` sets the apiVersion back to longhorn.io/v1beta1 (rollback, and how
# dev reproduces the production state).
#
# Before writing, the script checks that the object has exactly one
# ownerReference, that its kind is Volume or ShareManager, and that the owner
# with that name exists, is not being deleted, and has the same uid. The JSON
# patch then tests the whole ownerReferences array and metadata.uid, so a
# concurrent change makes the API server reject the patch instead of writing.
set -euo pipefail

NS=longhorn-system
KUBECTL=${KUBECTL:-kubectl --context fraction}
V1=longhorn.io/v1beta1
V2=longhorn.io/v1beta2

die() { echo "ERROR: $*" >&2; exit 1; }

owner_resource() {
    case "$1" in
        Volume) echo volumes.longhorn.io ;;
        ShareManager) echo sharemanagers.longhorn.io ;;
        *) return 1 ;;
    esac
}

list() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' RESOURCE NAME OWNER_APIVERSION OWNER UID_MATCH OWNER_STATE
    for r in engines.longhorn.io sharemanagers.longhorn.io services; do
        $KUBECTL -n "$NS" get "$r" -o json |
            jq -r --arg r "$r" '.items[]
                | select(any(.metadata.ownerReferences[]?; .apiVersion | startswith("longhorn.io/")))
                | .metadata.name as $n
                | .metadata.ownerReferences[]
                | [$r, $n, .apiVersion, .kind + "/" + .name, .uid] | @tsv' |
        while IFS=$'\t' read -r res name av owner uid; do
            [ "$av" = "$V2" ] && continue
            kind=${owner%%/*}; oname=${owner#*/}
            ores=$(owner_resource "$kind") || { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$res" "$name" "$av" "$owner" "?" "unknown kind"; continue; }
            live=$($KUBECTL -n "$NS" get "$ores" "$oname" -o json 2>/dev/null || true)
            if [ -z "$live" ]; then
                printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$res" "$name" "$av" "$owner" "no" "owner not found"
                continue
            fi
            luid=$(jq -r .metadata.uid <<<"$live")
            state=$(jq -r 'if .metadata.deletionTimestamp then "deleting" else (.status.state // "-") end' <<<"$live")
            match=no; [ "$luid" = "$uid" ] && match=yes
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$res" "$name" "$av" "$owner" "$match" "$state"
        done
    done
}

rewrite() {
    local from=$1 to=$2 res=$3 name=$4 dry=${5:-}
    case "$res" in
        engines.longhorn.io|sharemanagers.longhorn.io|services) ;;
        *) die "unsupported resource: $res" ;;
    esac
    case "$dry" in
        "") dryflag=() ;;
        --dry-run) dryflag=(--dry-run=server) ;;
        *) die "unknown option: $dry" ;;
    esac

    obj=$($KUBECTL -n "$NS" get "$res" "$name" -o json)
    [ "$(jq '.metadata.ownerReferences | length' <<<"$obj")" = 1 ] || die "$res/$name does not have exactly one ownerReference"
    ref=$(jq -c '.metadata.ownerReferences[0]' <<<"$obj")
    [ "$(jq -r .apiVersion <<<"$ref")" = "$from" ] || die "$res/$name ownerReference apiVersion is not $from: $ref"
    kind=$(jq -r .kind <<<"$ref"); oname=$(jq -r .name <<<"$ref"); ouid=$(jq -r .uid <<<"$ref")
    ores=$(owner_resource "$kind") || die "$res/$name owner kind is not Volume or ShareManager: $ref"

    owner=$($KUBECTL -n "$NS" get "$ores" "$oname" -o json) || die "owner $ores/$oname not found"
    [ "$(jq -r .metadata.uid <<<"$owner")" = "$ouid" ] || die "owner $ores/$oname uid $(jq -r .metadata.uid <<<"$owner") != ownerReference uid $ouid"
    [ "$(jq -r '.metadata.deletionTimestamp // ""' <<<"$owner")" = "" ] || die "owner $ores/$oname is being deleted"

    patch=$(jq -c --argjson refs "$(jq -c '.metadata.ownerReferences' <<<"$obj")" \
        --arg uid "$(jq -r .metadata.uid <<<"$obj")" --arg to "$to" -n '[
        {op: "test", path: "/metadata/uid", value: $uid},
        {op: "test", path: "/metadata/ownerReferences", value: $refs},
        {op: "replace", path: "/metadata/ownerReferences/0/apiVersion", value: $to}]')
    echo "before: $res/$name $ref"
    echo "owner:  $ores/$oname uid=$ouid (matches)"
    $KUBECTL -n "$NS" patch "$res" "$name" --type=json -p "$patch" "${dryflag[@]}" -o json |
        jq -r --arg d "${dry:-applied}" '"after (\($d)): \(.kind)/\(.metadata.name) \(.metadata.ownerReferences[0] | tojson) resourceVersion=\(.metadata.resourceVersion)"'
}

case "${1:-}" in
    list) list ;;
    fix) [ $# -ge 3 ] || die "usage: $0 fix <resource> <name> [--dry-run]"; rewrite "$V1" "$V2" "$2" "$3" "${4:-}" ;;
    undo) [ $# -ge 3 ] || die "usage: $0 undo <resource> <name> [--dry-run]"; rewrite "$V2" "$V1" "$2" "$3" "${4:-}" ;;
    *) die "usage: $0 list | fix <resource> <name> [--dry-run] | undo <resource> <name> [--dry-run]" ;;
esac
