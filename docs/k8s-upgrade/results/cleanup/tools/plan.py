#!/usr/bin/env python3
"""usage: plan.py <node> <dir> <images-plan.tsv>
Writes <dir>/rmi.txt (image IDs to remove) and <dir>/rmi-detail.tsv.
An image is removed only if:
  - every tag of it is "消す" in the TSV for this node (untagged = <none> "消す")
  - no container (incl. exited) references it by id / repoDigest / tag
  - no containerd container (incl. sandboxes) uses it, and it is not the configured sandbox image
"""
import csv, json, sys

node, d, tsv = sys.argv[1:4]
imgs = json.load(open(f"{d}/images.json"))["images"]
ps = json.load(open(f"{d}/ps.json"))["containers"]
pods = json.load(open(f"{d}/pods.json"))["items"]

plan = {}
for r in csv.DictReader(open(tsv), delimiter="\t"):
    nodes = r["ノード"].split(",")
    plan[(r["リポジトリ"], r["タグ"])] = (r["判断"], nodes)

used = set()
for c in ps:
    for k in ("imageRef", "imageId"):
        if c.get(k):
            used.add(c[k])
    im = c.get("image", {}) or {}
    if im.get("image"):
        used.add(im["image"])
    if c.get("imageId"):
        used.add(c["imageId"])
for line in open(f"{d}/ctr-images.txt"):
    used.add(line.strip())  # all containerd containers incl. sandboxes
sandbox = open(f"{d}/sandbox.txt").read().split()
assert sandbox, "no sandbox image"
used.update(sandbox)

rm, keep_reason = [], []
for i in imgs:
    iid = i["id"]
    tags = i.get("repoTags") or []
    digests = i.get("repoDigests") or []
    refs = {iid, *tags, *digests}
    size = int(i.get("size", 0))
    pairs = []
    for t in tags:
        repo, _, tag = t.rpartition(":")
        pairs.append((repo, tag))
    if not pairs:
        pairs = [("<none>", "<none>")]
    label = ",".join(tags) or "<none>"
    if refs & used:
        keep_reason.append((label, iid, "使用中", size)); continue
    verdicts = []
    for p in pairs:
        v = plan.get(p)
        if v is None:
            verdicts.append("一覧に無い")
        elif node not in v[1]:
            verdicts.append("一覧のノードに無い")
        else:
            verdicts.append(v[0])
    if all(v.startswith("消す") for v in verdicts):
        rm.append((label, iid, size))
    else:
        keep_reason.append((label, iid, "/".join(sorted(set(verdicts))), size))

with open(f"{d}/rmi.txt", "w") as f:
    for _, iid, _ in rm:
        f.write(iid + "\n")
with open(f"{d}/rmi-detail.tsv", "w") as f:
    f.write("action\ttags\tid\tsize\treason\n")
    for label, iid, size in rm:
        f.write(f"rmi\t{label}\t{iid}\t{size}\t消す\n")
    for label, iid, why, size in keep_reason:
        f.write(f"keep\t{label}\t{iid}\t{size}\t{why}\n")

tot = sum(int(i.get("size", 0)) for i in imgs)
print(f"{node}: images {len(imgs)} ({tot/2**30:.1f} GiB), rmi {len(rm)} ({sum(s for *_, s in rm)/2**30:.2f} GiB), keep {len(keep_reason)}")
from collections import Counter
print("  keep reasons:", dict(Counter(k[2] for k in keep_reason)))
for label, iid, why, size in keep_reason:
    if why not in ("使用中", "pinned") and not why.startswith("残す"):
        print("  keep(not 残す):", label, why)
