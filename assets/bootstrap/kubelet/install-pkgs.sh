#!/bin/bash
set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

if type apt-get > /dev/null 2>&1 ;then
  apt-get update
  apt-get install -y \
      ca-certificates \
      conntrack \
      e2fsprogs \
      xfsprogs \
      ebtables \
      ethtool \
      git \
      iptables \
      ipset \
      jq \
      kmod \
      openssh-client \
      netbase \
      nfs-common \
      socat \
      udev \
      util-linux
fi

cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sysctl --system
