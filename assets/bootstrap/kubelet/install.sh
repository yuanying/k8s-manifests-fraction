#!/bin/bash

set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

export KUBERNETES_PATH="/etc/kubernetes"
export KUBERNETES_PKI_PATH="${KUBERNETES_PATH}/pki"
export KUBERNETES_MANIFESTS_PATH="${KUBERNETES_PATH}/manifests"
export KUBELET_PATH="/var/lib/kubelet"

mkdir -p ${KUBERNETES_PATH}
mkdir -p ${KUBERNETES_PKI_PATH}
mkdir -p ${KUBERNETES_MANIFESTS_PATH}
mkdir -p ${KUBELET_PATH}

cp ${ROOT}/bootstrap-kubelet.conf ${KUBERNETES_PATH}/
cp ${ROOT}/bootstrap.* ${KUBERNETES_PKI_PATH}/
cp ${ROOT}/ca.crt ${KUBERNETES_PKI_PATH}/
cp ${ROOT}/config.yaml ${KUBELET_PATH}/
cp ${ROOT}/kubelet.service /etc/systemd/system/

# Install addons
for addon in $(ls ${ROOT}/addons/); do
  install_sh="${ROOT}/addons/${addon}/install.sh"
  if [[ -f ${install_sh} ]]; then
    echo "Install: ${install_sh}"
    bash ${install_sh}
  fi
done

rm -f ${KUBERNETES_PATH}/kubelet.conf
systemctl daemon-reload
systemctl enable kubelet
systemctl restart kubelet
