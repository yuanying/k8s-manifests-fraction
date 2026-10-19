#!/usr/bin/env bash
# List the objects in etcd that are stored in a version other than the one the
# running kube-apiserver would write now. Read-only: it runs `etcdctl get` on a
# control-plane node and `kubectl get` with the given context.
#
#   docs/k8s-upgrade/tools/storage-versions.sh <out-dir>
#
# Environment:
#   ETCD_HOST     node to read etcd from (default ubuntu@192.168.1.111)
#   KUBE_CONTEXT  kubectl context (default fraction)
#   PAUSE         seconds to sleep between prefixes (default 1)
#
# Output (<out-dir>):
#   prefixes.txt     the prefixes that were read, one etcdctl get per prefix
#   objects.tsv      key, encoding, apiVersion, kind for every key (no values)
#   expected.tsv     group, the version expected in storage, where it came from
#   summary.tsv      prefix, encoding, apiVersion, kind, count, ok|OLD
#   old.tsv          key, stored apiVersion, expected apiVersion (OLD only)
#   crds.tsv         CRD, storage version, status.storedVersions, ok|MULTI
set -euo pipefail

out=${1:?usage: storage-versions.sh <out-dir>}
host=${ETCD_HOST:-ubuntu@192.168.1.111}
ctx=${KUBE_CONTEXT:-fraction}
pause=${PAUSE:-1}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"
unset LC_ALL

etcdctl() {
  # $1 is a key prefix under /registry; it never contains quotes.
  ssh -n "$host" "sudo bash -c '. /etc/etcd/etcd.env; /opt/bin/etcdctl get $1 --prefix $2'"
}

# 1. Prefixes: /registry/<resource> for the built-in resources and
#    /registry/<group>/<resource> where the first part is an API group
#    (has a dot). Only the keys are read here.
etcdctl /registry --keys-only | grep '^/registry/' |
  awk -F/ '{ if ($3 ~ /\./) print "/" $2 "/" $3 "/" $4 "/"; else print "/" $2 "/" $3 "/" }' |
  sort -u > "$out/prefixes.txt"

# 2. Read the prefixes one at a time (a single read of the whole range is a
#    heavy request for the etcd on the Raspberry Pi).
: > "$out/objects.tsv"
while read -r p; do
  etcdctl "$p" '-w json' | python3 -I "$here/etcd-typemeta.py" >> "$out/objects.tsv"
  sleep "$pause"
done < "$out/prefixes.txt"

# 3. What the apiserver writes now.
#    Built-in groups: the preferred version from discovery. For the groups in
#    the cluster this is also the storage version of kube-apiserver 1.31-1.37
#    (the first version of the group's SetVersionPriority; no
#    ResourceEncodingOverrides apply to them). See ../storage-versions.md.
#    The exception is the CRD objects themselves: kube-apiserver 1.31-1.37
#    always writes them as apiextensions.k8s.io/v1beta1
#    (pkg/controlplane/apiserver/apiextensions.go, EncodeVersioner).
#    Custom resources: the version marked storage: true in the CRD.
kubectl --context "$ctx" get crd -o json | jq -r '.items[] |
  [.metadata.name, .spec.group, .spec.names.plural,
   (.spec.versions[] | select(.storage) | .name),
   (.status.storedVersions | join(","))] | @tsv' > "$out/crd-raw.tsv"
awk -F'\t' '{ print $1 "\t" $4 "\t" $5 "\t" (($5 == $4) ? "ok" : "MULTI") }' "$out/crd-raw.tsv" > "$out/crds.tsv"
{
  printf '\tv1\tcore\n'
  kubectl --context "$ctx" get --raw /apis | jq -r '.groups[] |
    if .name == "apiextensions.k8s.io" then [.name, "v1beta1", "apiextensions.go"]
    else [.name, .preferredVersion.version, "discovery"] end | @tsv'
} > "$out/expected.tsv"

# 4. Compare. A custom resource key is /registry/<group>/<plural>/...;
#    everything else is compared with the preferred version of the group in
#    its stored apiVersion.
python3 -I - "$out" <<'EOF'
import collections, sys
out = sys.argv[1]
expected = {}
for line in open(f"{out}/expected.tsv"):
    g, v, _ = line.rstrip("\n").split("\t")
    expected[g] = v
crs = {}
for line in open(f"{out}/crd-raw.tsv"):
    _, group, plural, storage, _ = line.rstrip("\n").split("\t")
    crs[f"/registry/{group}/{plural}/"] = f"{group}/{storage}"
counts = collections.Counter()
old = []
for line in open(f"{out}/objects.tsv"):
    key, enc, av, kind = line.rstrip("\n").split("\t")
    parts = key.split("/")
    cr_prefix = "/".join(parts[:4]) + "/"
    if cr_prefix in crs:
        prefix, want = cr_prefix, crs[cr_prefix]
    else:
        prefix = "/".join(parts[:4 if "." in parts[2] else 3]) + "/"
        group = av.rsplit("/", 1)[0] if "/" in av else ""
        want = (f"{group}/" if group else "") + expected.get(group, "?")
    status = "ok" if av == want else "OLD"
    counts[(prefix, enc, av, kind, status)] += 1
    if status == "OLD":
        old.append((key, av, want))
with open(f"{out}/summary.tsv", "w") as f:
    for (prefix, enc, av, kind, status), n in sorted(counts.items()):
        f.write(f"{prefix}\t{enc}\t{av}\t{kind}\t{n}\t{status}\n")
with open(f"{out}/old.tsv", "w") as f:
    for row in sorted(old):
        f.write("\t".join(row) + "\n")
EOF

echo "prefixes: $(wc -l < "$out/prefixes.txt"), keys: $(wc -l < "$out/objects.tsv"), OLD: $(wc -l < "$out/old.tsv"), CRDs with more than one stored version: $(grep -c 'MULTI$' "$out/crds.tsv" || true)"
