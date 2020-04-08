#!/bin/bash

set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

export KUBERNETES_PATH="/etc/kubernetes"
export KUBERNETES_BOOTSTRAP_ASSETS_PATH="${KUBERNETES_PATH}/bootstrap"
export KUBERNETES_MANIFESTS_PATH="${KUBERNETES_PATH}/manifests"

rm -rf ${KUBERNETES_BOOTSTRAP_ASSETS_PATH}
rm -rf ${KUBERNETES_MANIFESTS_PATH}/*.bootstrap.yaml
