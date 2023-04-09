#!/bin/bash

set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

export PORKADOT_METADATA=${ROOT}/metadata.json

# Install addons
for addon in $(ls ${ROOT}/addons/); do
  install_sh="${ROOT}/addons/${addon}/install.sh"
  if [[ -f ${install_sh} ]]; then
    echo "Install: ${install_sh}"
    bash ${install_sh}
  fi
done
