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

RELEASE="v1.16.9"

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
