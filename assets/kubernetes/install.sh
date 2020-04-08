#!/bin/bash

set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

/opt/bin/kubectl apply -f ${ROOT}/manifests/
