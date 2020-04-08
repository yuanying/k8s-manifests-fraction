#!/bin/bash

set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

mkdir -p /etc/etcd/pki
cp ${ROOT}/etcd.crt /etc/etcd/pki/
cp ${ROOT}/etcd.key /etc/etcd/pki/
cp ${ROOT}/ca.crt /etc/etcd/pki/
mkdir -p /etc/kubernetes/manifests
cp ${ROOT}/etcd-server.yaml /etc/kubernetes/manifests/
