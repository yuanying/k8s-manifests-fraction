#!/bin/bash

set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

export KUBERNETES_PATH="/etc/kubernetes"
export KUBERNETES_BOOTSTRAP_ASSETS_PATH="${KUBERNETES_PATH}/bootstrap"
export KUBERNETES_MANIFESTS_PATH="${KUBERNETES_PATH}/manifests"

mkdir -p ${KUBERNETES_BOOTSTRAP_ASSETS_PATH}

cp ${ROOT}/manifests/*.bootstrap.yaml ${KUBERNETES_MANIFESTS_PATH}/
cp -r ${ROOT}/bootstrap/* ${KUBERNETES_BOOTSTRAP_ASSETS_PATH}/
