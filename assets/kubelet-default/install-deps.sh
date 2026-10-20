#!/bin/bash

set -euo pipefail

# Each binary is installed as ${BIN_DIR}/<name>-<version> and linked from
# ${BIN_DIR}/<name>. A version already on the node is reused and only
# relinked, so going back to an earlier version needs no download.
# --force downloads everything again.
FORCE=false
case "${1:-}" in
    "") ;;
    --force) FORCE=true ;;
    *) echo "Usage: $0 [--force]" >&2; exit 2 ;;
esac

architecture="arm64"
case $(uname -m) in
    x86_64) architecture="amd64" ;;
    arm)    dpkg --print-architecture | grep -q "arm64" && architecture="arm64" || architecture="arm" ;;
esac
echo $architecture

# PORKADOT_OPT_DIR is only meant to be overridden by tests.
OPT_DIR=${PORKADOT_OPT_DIR:-/opt}
BIN_DIR=${OPT_DIR}/bin
CNI_BIN_DIR=${OPT_DIR}/cni/bin
# The reference CNI plugins (bridge, host-local, portmap, loopback, ...) are owned by
# the node, whichever CNI addon is enabled: the CNI DaemonSet only puts its own
# binary here (flannel puts flannel, cnidaria puts none).
# The CNI plugins are extracted in place, so their version is kept in a file.
CNI_VERSION_FILE=${CNI_BIN_DIR}/.porkadot-cni-plugins-version

mkdir -p ${BIN_DIR}
mkdir -p ${CNI_BIN_DIR}

# install_bin NAME VERSION FETCH
# FETCH is called with a work directory and leaves the binary there as NAME.
install_bin() {
  local name=$1 version=$2 fetch=$3
  local target=${BIN_DIR}/${name}-${version}

  if [ "${FORCE}" = true ] || [ ! -f ${target} ]; then
    local tmp=$(mktemp -d)
    ${fetch} ${tmp}
    chmod +x ${tmp}/${name}
    mv ${tmp}/${name} ${target}.tmp
    mv ${target}.tmp ${target}
    rm -rf ${tmp}
  else
    echo "${target} already exists"
  fi

  if [ "$(readlink ${BIN_DIR}/${name} || true)" != "${target}" ]; then
    rm -f ${BIN_DIR}/${name}
    ln -s ${target} ${BIN_DIR}/${name}
  fi
}

CNI_VERSION="v1.9.1"
if [ "${FORCE}" = true ] || [ "$(cat ${CNI_VERSION_FILE} 2>/dev/null || true)" != "${CNI_VERSION}" ]; then
  CNI_TMP=$(mktemp -d)
  curl -fL "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${architecture}-${CNI_VERSION}.tgz" \
    -o ${CNI_TMP}/cni-plugins.tgz
  tar -C ${CNI_BIN_DIR} -xzf ${CNI_TMP}/cni-plugins.tgz
  echo ${CNI_VERSION} > ${CNI_VERSION_FILE}
  rm -rf ${CNI_TMP}
else
  echo "CNI plugins ${CNI_VERSION} already installed"
fi

RELEASE="v1.34.12"

fetch_kubectl() {
  curl -fL https://dl.k8s.io/${RELEASE}/bin/linux/${architecture}/kubectl -o $1/kubectl
}
install_bin kubectl ${RELEASE} fetch_kubectl

fetch_kubelet() {
  curl -fL https://dl.k8s.io/${RELEASE}/bin/linux/${architecture}/kubelet -o $1/kubelet
}
install_bin kubelet ${RELEASE} fetch_kubelet

ETCD_VER="3.6.15"
# etcdctl and etcdutl come from the same etcd release archive.
fetch_etcd() {
  curl -fL https://github.com/etcd-io/etcd/releases/download/v${ETCD_VER}/etcd-v${ETCD_VER}-linux-${architecture}.tar.gz \
    -o $1/etcd.tar.gz
  tar zxvf $1/etcd.tar.gz -C $1/ --strip-components=1
}
install_bin etcdctl ${ETCD_VER} fetch_etcd
install_bin etcdutl ${ETCD_VER} fetch_etcd

CRICTL_VER="v1.34.0"
fetch_crictl() {
  curl -fL https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VER}/crictl-${CRICTL_VER}-linux-${architecture}.tar.gz \
    -o $1/crictl.tar.gz
  tar zxvf $1/crictl.tar.gz -C $1/
}
install_bin crictl ${CRICTL_VER} fetch_crictl
