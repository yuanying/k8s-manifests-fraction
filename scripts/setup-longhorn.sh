#!/bin/bash

set -eux
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

longhorn_disk=/dev/disk/by-label/longhorn
if [[ ! -L "${longhorn_disk}" ]]; then
    mkfs.ext4 /dev/sdb -L longhorn
fi


longhorn_dir=/var/lib/longhorn
longhorn_mount=/etc/systemd/system/var-lib-longhorn.mount
longhorn_automount=/etc/systemd/system/var-lib-longhorn.automount
if [[ ! -f "${longhorn_mount}" ]]; then
    mkdir -p "${longhorn_dir}"
    cat <<-EOF > "${longhorn_mount}"
[Unit]
Description=Mount ${longhorn_disk}
[Mount]
What=${longhorn_disk}
Where=${longhorn_dir}
Type=ext4
Options=discard,noatime
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable var-lib-longhorn.mount
    systemctl start var-lib-longhorn.mount
fi

