#!/bin/bash

set -eu
export LC_ALL=C

cat << EOF > /etc/systemd/network/10-porka-dummy.netdev
[NetDev]
Name=porka-dummy01
Kind=dummy
EOF

cat << EOF > /etc/systemd/network/20-porka-dummy.network
[Match]
Name=porka-dummy01

[Network]
Address=10.254.0.1/24
EOF

systemctl restart systemd-networkd

# Quoted heredoc: keep the systemd escape "\x2d" in the device unit name as is.
cat <<'EOF' > /etc/systemd/system/cluster-dns.service
[Unit]
Description=Setup cluster.local DNS
BindsTo=sys-subsystem-net-devices-porka\x2ddummy01.device
Wants=systemd-networkd.service
After=sys-subsystem-net-devices-porka\x2ddummy01.device systemd-networkd.service systemd-resolved.service
Requires=systemd-resolved.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=resolvectl dns porka-dummy01 10.254.0.10
ExecStart=resolvectl domain porka-dummy01 default.svc.cluster.local svc.cluster.local cluster.local

[Install]
WantedBy=multi-user.target sys-subsystem-net-devices-porka\x2ddummy01.device
EOF

systemctl daemon-reload
systemctl enable cluster-dns.service
systemctl restart cluster-dns.service
