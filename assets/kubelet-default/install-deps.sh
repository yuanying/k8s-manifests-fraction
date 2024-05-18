#!/bin/bash

set -euo pipefail

architecture="arm64"
case $(uname -m) in
    x86_64) architecture="amd64" ;;
    arm)    dpkg --print-architecture | grep -q "arm64" && architecture="arm64" || architecture="arm" ;;
esac
echo $architecture

CNI_VERSION="v1.2.0"
mkdir -p /opt/cni/bin
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${architecture}-${CNI_VERSION}.tgz" | tar -C /opt/cni/bin -xz

RELEASE="v1.26.15"

mkdir -p /opt/bin

curl -L https://storage.googleapis.com/kubernetes-release/release/${RELEASE}/bin/linux/${architecture}/kubectl \
  -o /opt/bin/kubectl-${RELEASE}
chmod +x /opt/bin/kubectl-${RELEASE}
rm -f /opt/bin/kubectl
ln -s /opt/bin/kubectl-${RELEASE} /opt/bin/kubectl

curl -L https://storage.googleapis.com/kubernetes-release/release/${RELEASE}/bin/linux/${architecture}/kubelet \
  -o /opt/bin/kubelet-${RELEASE}
chmod +x /opt/bin/kubelet-${RELEASE}
rm -f /opt/bin/kubelet
ln -s /opt/bin/kubelet-${RELEASE} /opt/bin/kubelet

ETCD_VER="3.5.5"
ETCD_URL=https://github.com/etcd-io/etcd/releases/download/v${ETCD_VER}/etcd-v${ETCD_VER}-linux-${architecture}.tar.gz
ETCD_TMP=$(mktemp -d)

curl -L ${ETCD_URL} -o ${ETCD_TMP}/etcd.tar.gz
tar zxvf ${ETCD_TMP}/etcd.tar.gz -C ${ETCD_TMP}/ --strip-components=1
chmod +x ${ETCD_TMP}/etcdctl
rm -f /opt/bin/etcdctl
mv ${ETCD_TMP}/etcdctl /opt/bin/etcdctl-${ETCD_VER}
ln -s /opt/bin/etcdctl-${ETCD_VER} /opt/bin/etcdctl

CRICTL_VER="v1.26.0"
CRICTL_URL=https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VER}/crictl-${CRICTL_VER}-linux-${architecture}.tar.gz
CRICTL_TMP=$(mktemp -d)
curl -L ${CRICTL_URL} -o ${CRICTL_TMP}/crictl.tar.gz
tar zxvf ${CRICTL_TMP}/crictl.tar.gz -C ${CRICTL_TMP}/
rm -f /opt/bin/crictl
mv ${CRICTL_TMP}/crictl /opt/bin/crictl-${CRICTL_VER}
ln -s /opt/bin/crictl-${CRICTL_VER} /opt/bin/crictl
