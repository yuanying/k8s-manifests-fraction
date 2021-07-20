#!/bin/bash

architecture="arm64"
case $(uname -m) in
    x86_64) architecture="amd64" ;;
    arm)    dpkg --print-architecture | grep -q "arm64" && architecture="arm64" || architecture="arm" ;;
esac
echo $architecture

CNI_VERSION="v0.8.2"
mkdir -p /opt/cni/bin
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${architecture}-${CNI_VERSION}.tgz" | tar -C /opt/cni/bin -xz

RELEASE="v1.19.6"

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

ETCD_VER="v3.4.3"
ETCD_URL=https://storage.googleapis.com/etcd/${ETCD_VER}/etcd-${ETCD_VER}-linux-${architecture}.tar.gz
ETCD_TMP=$(mktemp -d)

curl -L ${ETCD_URL} -o ${ETCD_TMP}/etcd.tar.gz
tar zxvf ${ETCD_TMP}/etcd.tar.gz -C ${ETCD_TMP}/ --strip-components=1
chmod +x ${ETCD_TMP}/etcdctl
rm -f /opt/bin/etcdctl
mv ${ETCD_TMP}/etcdctl /opt/bin/etcdctl-${ETCD_VER}
ln -s /opt/bin/etcdctl-${ETCD_VER} /opt/bin/etcdctl
