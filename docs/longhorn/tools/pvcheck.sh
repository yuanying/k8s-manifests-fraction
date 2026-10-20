#!/usr/bin/env bash
# Longhorn CSI check with a temporary namespace (pvcheck.yaml). See
# docs/longhorn/runbook-upgrade-1.12-1.13.md.
#
#   pvcheck.sh dry-run       kubectl apply --dry-run=client (read-only; works with fraction-auditor)
#   pvcheck.sh up <node>     WRITES: create the namespace and the two PVCs (provision), then a pod on
#                            <node> that mounts both (attach), writes 16 MiB of random data and its md5
#                            to each, and checks them
#   pvcheck.sh move <node>   WRITES: delete the pod and make it again on <node> (detach, attach on
#                            another node), check the md5 of the data written by up
#   pvcheck.sh status        read-only: the PVCs, their Longhorn volumes and the pod's log
#   pvcheck.sh down          WRITES: delete the namespace and wait until the PVs and the Longhorn
#                            volumes are gone
#
# up and move exit 0 when the pod prints "/rwo/blob: OK" and "/rwx/blob: OK".
# Environment: ADMIN_TOKEN (infra-admin token; needed for up, move, down), KUBE_CONTEXT (default fraction).
set -u
cd "$(dirname "$0")"
NS=lh-pvcheck
ctx=${KUBE_CONTEXT:-fraction}
K=(kubectl --context "$ctx")
[ -n "${ADMIN_TOKEN:-}" ] && K+=(--token="$ADMIN_TOKEN")

pod() {
  cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pvcheck
  namespace: $NS
spec:
  nodeName: $1
  terminationGracePeriodSeconds: 1
  containers:
    - name: check
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          for d in /rwo /rwx; do
            if [ ! -f \$d/blob.md5 ]; then
              head -c 16777216 /dev/urandom > \$d/blob && (cd \$d && md5sum blob > blob.md5) && sync
            fi
            (cd \$d && md5sum -c blob.md5 | sed "s|^|\$d/|")
          done
          echo done
          exec sleep 86400
      volumeMounts:
        - {name: rwo, mountPath: /rwo}
        - {name: rwx, mountPath: /rwx}
  volumes:
    - name: rwo
      persistentVolumeClaim: {claimName: rwo}
    - name: rwx
      persistentVolumeClaim: {claimName: rwx}
EOF
}

wait_check() {
  local start=$SECONDS log
  while :; do
    log=$("${K[@]}" -n $NS logs pvcheck 2>/dev/null)
    if grep -q '^done$' <<<"$log"; then
      echo "$log"
      grep -q '^/rwo/blob: OK$' <<<"$log" && grep -q '^/rwx/blob: OK$' <<<"$log" && return 0
      echo "pvcheck: md5 mismatch" >&2; return 1
    fi
    if [ $((SECONDS - start)) -ge 300 ]; then
      "${K[@]}" -n $NS get pvc,pods -o wide
      "${K[@]}" -n $NS get events --sort-by=.lastTimestamp | tail -20
      echo "pvcheck: not done in 300s" >&2; return 1
    fi
    echo "$(date -u +%T) $("${K[@]}" -n $NS get pvc --no-headers -o custom-columns=N:.metadata.name,S:.status.phase | xargs) pod=$("${K[@]}" -n $NS get pod pvcheck -o jsonpath='{.status.phase}' 2>/dev/null)"
    sleep 5
  done
}

volumes() {
  "${K[@]}" -n longhorn-system get volumes.longhorn.io -o json |
    jq -r --arg ns $NS '.items[] | select(.status.kubernetesStatus.namespace == $ns)
      | [.metadata.name, .status.kubernetesStatus.pvcName, .status.state, .status.robustness,
         (.status.currentNodeID // "-"), (.status.currentImage | sub(".*:"; ""))] | @tsv'
}

case "${1:-}" in
  dry-run)
    "${K[@]}" apply --dry-run=client -f pvcheck.yaml
    pod "${2:-chirico}" | "${K[@]}" apply --dry-run=client -f - ;;
  up)
    node=${2:?usage: pvcheck.sh up <node>}
    "${K[@]}" apply -f pvcheck.yaml || exit 1
    pod "$node" | "${K[@]}" apply -f - || exit 1
    wait_check || exit 1
    volumes ;;
  move)
    node=${2:?usage: pvcheck.sh move <node>}
    "${K[@]}" -n $NS delete pod pvcheck --wait=true || exit 1
    pod "$node" | "${K[@]}" apply -f - || exit 1
    wait_check || exit 1
    volumes ;;
  status)
    "${K[@]}" -n $NS get pvc,pods -o wide
    volumes
    "${K[@]}" -n $NS logs pvcheck 2>/dev/null ;;
  down)
    pvs=$("${K[@]}" -n $NS get pvc -o jsonpath='{.items[*].spec.volumeName}' 2>/dev/null)
    "${K[@]}" delete namespace $NS --wait=true --timeout=300s || exit 1
    start=$SECONDS
    for pv in $pvs; do
      while "${K[@]}" get pv "$pv" >/dev/null 2>&1 ||
            "${K[@]}" -n longhorn-system get volumes.longhorn.io "$pv" >/dev/null 2>&1; do
        [ $((SECONDS - start)) -ge 300 ] && { echo "pvcheck: $pv still there" >&2; exit 1; }
        sleep 3
      done
      echo "$pv gone (PV and Longhorn volume)"
    done
    "${K[@]}" get namespace $NS 2>&1 | tail -1 ;;
  *)
    sed -n '2,17p' "$0"; exit 2 ;;
esac
