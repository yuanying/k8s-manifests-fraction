#!/bin/bash
set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i -e "/containerd.runtimes.runc.options/a SystemdCgroup = true" /etc/containerd/config.toml

systemctl restart containerd
