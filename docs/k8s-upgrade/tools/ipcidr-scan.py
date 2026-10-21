#!/usr/bin/env python3
# Copied unchanged from porkadot-dev docs/k8s-upgrade/tools/ipcidr-scan.py (main 5341bc4, porkadot-dev#17;
# its use is in porkadot-dev docs/k8s-upgrade/verification-0.36-rc.md, "StrictIPCIDRValidation").
# Read-only. List the IP and CIDR values in the objects that K8s 1.36's StrictIPCIDRValidation
# (beta, on by default) would not accept in a new value, and the non-canonical IPv6 ones it only warns about.
# Reads `kubectl get <kinds> -A -o json` on stdin; walks every string under spec and status (and the
# name of IPAddress objects), skipping metadata.
#   kubectl --context <ctx> get services,endpoints,endpointslices,networkpolicies,nodes,pods,ingresses,\
#     servicecidrs,ipaddresses -A -o json | python3 -I ipcidr-scan.py
# Prints one line per finding: kind ns/name path value REASON, then a count per kind of the values checked.
# REASON: leading-0 / ipv4-mapped / host-bits (rejected by the strict validation when a create or an update
# brings a new such value; an update that keeps the old value is allowed) or non-canonical (warning only).
import collections, ipaddress, json, re, sys

V4 = re.compile(r'^\d{1,3}(\.\d{1,3}){3}$')
V6 = re.compile(r'^[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]*$')

def check(value):
    """Return (is_ip_or_cidr, [reasons])."""
    ip, _, plen = value.partition('/')
    if plen and not plen.isdigit():
        return False, []
    reasons = []
    if V4.match(ip):
        octets = ip.split('.')
        if any(int(o) > 255 for o in octets):
            return False, []
        if any(len(o) > 1 and o[0] == '0' for o in octets):
            reasons.append('leading-0')
        addr = ipaddress.IPv4Address('.'.join(str(int(o)) for o in octets))
    elif V6.match(ip):
        try:
            addr = ipaddress.IPv6Address(ip)
        except ValueError:
            return False, []
        if addr.ipv4_mapped is not None:
            reasons.append('ipv4-mapped')
        elif str(addr) != ip:
            reasons.append('non-canonical')
    else:
        return False, []
    if plen:
        if len(plen) > 1 and plen[0] == '0':
            reasons.append('leading-0')
        if int(plen) > addr.max_prefixlen:
            return False, []
        net = ipaddress.ip_network(f'{addr}/{int(plen)}', strict=False)
        if net.network_address != addr:
            reasons.append('host-bits')
    return True, reasons

checked = collections.Counter()
findings = []

def walk(kind, name, path, node):
    if isinstance(node, dict):
        for k, v in node.items():
            walk(kind, name, f'{path}.{k}', v)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(kind, name, f'{path}[{i}]', v)
    elif isinstance(node, str):
        ok, reasons = check(node)
        if ok:
            checked[kind] += 1
            for r in reasons:
                findings.append((kind, name, path, node, r))

data = json.load(sys.stdin)
for item in data.get('items', []):
    kind = item.get('kind', '?')
    md = item.get('metadata', {})
    name = (md.get('namespace', '') + '/' if md.get('namespace') else '') + md.get('name', '')
    if kind == 'IPAddress':
        walk(kind, name, 'metadata.name', md.get('name', ''))
    for top in ('spec', 'status', 'subsets', 'endpoints', 'addressType'):
        if top in item:
            walk(kind, name, top, item[top])

for f in findings:
    print(*f, sep='\t')
print('# findings:', len(findings), dict(collections.Counter(f[4] for f in findings)))
print('# IP / CIDR values checked per kind:', dict(sorted(checked.items())))
