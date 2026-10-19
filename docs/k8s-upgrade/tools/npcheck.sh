#!/usr/bin/env bash
# NetworkPolicy check with a temporary namespace (npcheck.yaml).
#
#   npcheck.sh dry-run   kubectl apply --dry-run=client (read-only; works with fraction-auditor)
#   npcheck.sh up        WRITES: create the namespace, the DaemonSets and the NetworkPolicy, wait for them
#   npcheck.sh run       from the clients on every node to the server on the next node, v4 and v6:
#                          allowed -> 8080  PASS  (the policy allows it)
#                          allowed -> 9090  BLOCK (port not allowed)
#                          denied  -> 8080  BLOCK (peer not allowed)
#                        and each server reaches its own 9090 (so a BLOCK is the policy, not a dead port).
#                        Exit 0 when every result is as expected. Uses kubectl exec.
#   npcheck.sh nft       on every node (ssh, sudo nft): the rules commented k8u-npcheck/allow-8080
#                        in table inet cnidaria. Expected > 0 after up, 0 after down.
#   npcheck.sh down      WRITES: delete the namespace and wait
#
# Environment: ADMIN_TOKEN (infra-admin token; needed for up, run, down), KUBE_CONTEXT (default fraction).
set -u
cd "$(dirname "$0")"
NS=k8u-npcheck
ctx=${KUBE_CONTEXT:-fraction}
K=(kubectl --context "$ctx")
[ -n "${ADMIN_TOKEN:-}" ] && K+=(--token="$ADMIN_TOKEN")
unset LC_ALL

wait_ready() {
  local start=$SECONDS ds want ready ok
  while :; do
    ok=1
    for ds in npcheck-server npcheck-allowed npcheck-denied; do
      want=$("${K[@]}" -n $NS get ds $ds -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
      ready=$("${K[@]}" -n $NS get ds $ds -o jsonpath='{.status.numberReady}' 2>/dev/null)
      echo "$(date +%T) $ds ready=${ready:-?}/${want:-?}"
      { [ -n "$want" ] && [ "$want" != 0 ] && [ "$want" = "$ready" ]; } || ok=0
    done
    [ $ok = 1 ] && return 0
    [ $((SECONDS - start)) -ge 180 ] && { "${K[@]}" -n $NS get pods -o wide; return 1; }
    sleep 3
  done
}

# name node ip... for the Running pods matching a selector, sorted by node
pods() {
  "${K[@]}" -n $NS get pods -l "$1" --field-selector status.phase=Running \
    -o jsonpath='{range .items[*]}{.spec.nodeName} {.metadata.name} {.status.podIPs[*].ip}{"\n"}{end}' | sort
}

# Runs inside a client: each argument is "<expect>|<label>|<host:port>"; prints OK / NG per probe.
# shellcheck disable=SC2016  # expanded by the pod's shell
PROBE='for t; do e=${t%%|*}; r=${t#*|}; n=${r%%|*}; a=${r#*|}; if wget -q -T 3 -O /dev/null "http://$a/" >/dev/null 2>&1; then g=PASS; else g=BLOCK; fi; [ "$g" = "$e" ] && echo "OK $g $n" || echo "NG $g (want $e) $n"; done'

run() {
  local servers=() n i node name ip next tnode tname tips target role cname targets out
  mapfile -t servers < <(pods app=npcheck-server)
  n=${#servers[@]}
  [ "$n" -ge 2 ] || { echo "need servers on at least 2 nodes, have $n"; return 1; }
  out=/tmp/npcheck-$(date -u +%Y%m%dT%H%M%SZ).txt
  {
    for ((i = 0; i < n; i++)); do
      read -r node name _ <<<"${servers[$i]}"
      echo "### server $node: own 9090"
      "${K[@]}" -n $NS exec "$name" -- sh -c "$PROBE" sh "PASS|$node self 9090|127.0.0.1:9090" 2>&1
    done
    for ((i = 0; i < n; i++)); do
      read -r node _ <<<"${servers[$i]}"
      read -r tnode tname tips <<<"${servers[$(((i + 1) % n))]}"
      for role in allowed denied; do
        cname=$(pods "app=npcheck-client,role=$role" | awk -v n="$node" '$1 == n {print $2}')
        [ -n "$cname" ] || { echo "NG no $role client on $node"; continue; }
        targets=()
        for ip in $tips; do
          case $ip in *:*) target="[$ip]" fam=v6 ;; *) target=$ip fam=v4 ;; esac
          if [ $role = allowed ]; then
            targets+=("PASS|$role $node -> $tnode $fam 8080|$target:8080" "BLOCK|$role $node -> $tnode $fam 9090|$target:9090")
          else
            targets+=("BLOCK|$role $node -> $tnode $fam 8080|$target:8080")
          fi
        done
        echo "### $role client on $node -> server on $tnode"
        "${K[@]}" -n $NS exec "$cname" -- sh -c "$PROBE" sh "${targets[@]}" 2>&1
      done
    done
  } > "$out"
  grep -v '^OK' "$out" | grep -v '^###'
  echo "OK $(grep -c '^OK' "$out"), not OK $(grep -vc -e '^OK' -e '^###' "$out")  (full output: $out)"
  ! grep -qv -e '^OK' -e '^###' "$out"
}

nft() {
  local node ip user
  "${K[@]}" get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' |
  while read -r node ip; do
    case $ip in 192.168.1.11[1-3]) user=ubuntu ;; *) user=yuanying ;; esac
    echo "$node $(ssh -n "$user@$ip" "sudo nft list table inet cnidaria | grep -c '$NS/allow-8080'" 2>/dev/null)"
  done
}

case ${1:-} in
  dry-run) "${K[@]}" apply --dry-run=client -f npcheck.yaml ;;
  up) "${K[@]}" apply -f npcheck.yaml && wait_ready ;;
  run) run ;;
  nft) nft ;;
  down) "${K[@]}" delete namespace $NS --ignore-not-found --wait ;;
  *) echo "usage: $0 dry-run|up|run|nft|down" >&2; exit 2 ;;
esac
