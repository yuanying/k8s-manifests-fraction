#!/bin/bash
set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

# PORKADOT_ETC_DIR is only meant to be overridden by tests.
ETC_DIR=${PORKADOT_ETC_DIR:-/etc}

if type apt-get > /dev/null 2>&1 ;then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  # Installed packages are not upgraded: upgrading open-iscsi restarts iscsid
  # in its postinst. Upgrades are left to the OS updates.
  apt-get install -y --no-upgrade \
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
      util-linux \
      open-iscsi
fi

cat > ${ETC_DIR}/modules-load.d/porkadot.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF >  ${ETC_DIR}/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-iptables  = 1
EOF

# iscsid is restarted only when the initiator name changes. Restarting it
# while Longhorn volumes are attached leaves the running engines unable to
# log out of their iSCSI sessions (Longhorn before v1.11.3 and v1.12.1).
if cmp -s ${ROOT}/initiatorname.iscsi ${ETC_DIR}/iscsi/initiatorname.iscsi; then
  # Does nothing if iscsid is already running.
  systemctl start iscsid.service
else
  cp ${ROOT}/initiatorname.iscsi ${ETC_DIR}/iscsi/
  systemctl restart iscsid.service
fi

sysctl --system
