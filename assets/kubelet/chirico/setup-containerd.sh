#!/bin/bash
set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml

grep SystemdCgroup /etc/containerd/config.toml && :

if [[ $? == 0 ]]; then
  sed -i -e "s/SystemdCgroup.*$/SystemdCgroup = true/" /etc/containerd/config.toml
else
  sed -i -e "/containerd.runtimes.runc.options/a SystemdCgroup = true" /etc/containerd/config.toml
fi

systemctl restart containerd
