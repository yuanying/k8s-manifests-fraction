#!/bin/bash

set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

cat <<EOF > /etc/multipath.conf
defaults {
    user_friendly_names yes
    find_multipaths no
}
EOF

systemctl restart multipath-tools

