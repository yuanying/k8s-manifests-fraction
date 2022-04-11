#!/bin/bash

set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")
KUBECTL_OPTS=${KUBECTL_OPTS:-""}

KUBECTL_OPTS="${KUBECTL_OPTS} --server-side --force-conflicts --prune"
KUBECTL_OPTS="${KUBECTL_OPTS} -l kubernetes.unstable.cloud/installed-by=porkadot"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-whitelist=apiextensions.k8s.io/v1/customresourcedefinition"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-whitelist=apps/v1/daemonset"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-whitelist=apps/v1/deployment"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-whitelist=core/v1/configmap"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-whitelist=core/v1/namespace"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-whitelist=core/v1/service"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-whitelist=core/v1/serviceaccount"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-whitelist=policy/v1/poddisruptionbudget"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-whitelist=policy/v1beta1/podsecuritypolicy"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-whitelist=rbac.authorization.k8s.io/v1/clusterrole"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-whitelist=rbac.authorization.k8s.io/v1/clusterrolebinding"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-whitelist=rbac.authorization.k8s.io/v1/role"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-whitelist=rbac.authorization.k8s.io/v1/rolebinding"

/opt/bin/kubectl apply ${KUBECTL_OPTS} -k ${ROOT}
