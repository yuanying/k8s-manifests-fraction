#!/bin/bash
# usage: netswitch-fraction.sh <ip/prefix>   e.g. 192.168.1.113/16
# Switch eth0 of a new control-plane Pi 5 from its temporary address to <ip/prefix>,
# and revert unless /run/netswitch-ok appears within 120 seconds.
# Run it detached from SSH: sudo systemd-run --unit netswitch /root/netswitch-fraction.sh 192.168.1.11N/16
#
# Production variant of porkadot-dev docs/cp-replacement/rehearsal/netswitch.sh.
# Instead of writing a new netplan, it rewrites only the address of the netplan that
# k8s-env raspi/ cloud-init generated (/etc/netplan/50-cloud-init.yaml), so the rest
# of it -- accept-ra: true (fraction is dual-stack, flannel needs the IPv6 default
# route), gateway and DNS 192.168.0.1 -- stays as provisioned.
set -u
NEW=${1:?usage: $0 <ip/prefix>}
[[ ${NEW} =~ ^192\.168\.1\.[0-9]+/16$ ]] || { echo "unexpected address: ${NEW}" >&2; exit 1; }
NP=/etc/netplan/50-cloud-init.yaml
[[ -f ${NP} ]] || { echo "${NP} not found" >&2; exit 1; }
grep -q 'accept-ra: true' ${NP} || { echo "${NP} does not accept RA" >&2; exit 1; }
# cloud-init writes the address quoted (- "192.168.1.121/16").
[[ $(grep -cE '^ *- "?192\.168\.[0-9]+\.[0-9]+/16"?$' ${NP}) == 1 ]] || { echo "${NP} must have exactly one IPv4 address" >&2; exit 1; }

BAK=/root/netplan.bak.$(date +%Y%m%d%H%M%S)
cp -a /etc/netplan ${BAK}
rm -f /run/netswitch-ok
sed -i -E "s#^( *- )\"?192\.168\.[0-9]+\.[0-9]+/16\"?\$#\1\"${NEW}\"#" ${NP}
echo "switching to ${NEW} (backup: ${BAK})"
netplan apply
for i in $(seq 1 120); do
  [[ -f /run/netswitch-ok ]] && { echo "confirmed ${NEW}"; exit 0; }
  sleep 1
done
echo "not confirmed, reverting to ${BAK}"
rm -f /etc/netplan/*.yaml
cp -a ${BAK}/. /etc/netplan/
netplan apply
exit 1
