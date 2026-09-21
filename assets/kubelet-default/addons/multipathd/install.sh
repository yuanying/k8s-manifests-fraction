#!/bin/bash

set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

cat <<EOF > /etc/multipath.conf
defaults {
    user_friendly_names yes
    find_multipaths no
}
blacklist {
    devnode "^sd[a-z0-9]+"
}
EOF

systemctl restart multipath-tools

