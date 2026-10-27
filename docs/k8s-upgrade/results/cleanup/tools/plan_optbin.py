#!/usr/bin/env python3
"""usage: plan_optbin.py <dir>  -> <dir>/optbin-rm.txt (one path per line)
Keeps the current and the previous version (cleanup.md 7.6) and the links.
Refuses if a link does not point at the current version."""
import re, sys
d = sys.argv[1]
KEEP = {"kubelet-v1.37.1", "kubelet-v1.36.5", "kubectl-v1.37.1", "kubectl-v1.36.5",
        "crictl-v1.37.0", "crictl-v1.36.0", "etcdctl-3.7.3", "etcdctl-3.6.15",
        "etcdutl-3.7.3", "etcdutl-3.6.15"}
CUR = {"kubelet": "/opt/bin/kubelet-v1.37.1", "kubectl": "/opt/bin/kubectl-v1.37.1",
       "crictl": "/opt/bin/crictl-v1.37.0", "etcdctl": "/opt/bin/etcdctl-3.7.3",
       "etcdutl": "/opt/bin/etcdutl-3.7.3"}
pat = re.compile(r"^(kubelet|kubectl|crictl|etcdctl|etcdutl)-v?\d+\.\d+\.\d+$")
rm, other, total = [], [], 0
for line in open(f"{d}/optbin.txt"):
    f = line.split()
    if line.startswith("LINK"):
        assert CUR[f[1]] == (f[2] if len(f) > 2 else ""), f"link {f[1]} -> {f[2:]}"
        continue
    if len(f) < 9 or f[0].startswith("total"):
        continue
    name = f[8]
    if name in (".", "..") or f[0].startswith("l"):
        continue
    if pat.match(name) and name not in KEEP:
        rm.append(name); total += int(f[4])
    elif name not in KEEP:
        other.append(name)
open(f"{d}/optbin-rm.txt", "w").write("".join(f"/opt/bin/{n}\n" for n in rm))
print(f"optbin rm {len(rm)} ({total/2**30:.2f} GiB); other files kept: {other}")
