#!/bin/bash

set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

mkdir -p /etc/etcd/pki
# install also resets the owner and mode of files that already exist.
install -m 0600 -o root -g root ${ROOT}/etcd.crt /etc/etcd/pki/etcd.crt
install -m 0600 -o root -g root ${ROOT}/etcd.key /etc/etcd/pki/etcd.key
install -m 0600 -o root -g root ${ROOT}/ca.crt /etc/etcd/pki/ca.crt
cp ${ROOT}/etcd.env /etc/etcd/
mkdir -p /etc/kubernetes/manifests
cp ${ROOT}/etcd-server.yaml /etc/kubernetes/manifests/
