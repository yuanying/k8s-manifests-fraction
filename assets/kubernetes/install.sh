#!/bin/bash

set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")
KUBECTL_OPTS=${KUBECTL_OPTS:-""}

KUBECTL_OPTS="${KUBECTL_OPTS} --prune"
KUBECTL_OPTS="${KUBECTL_OPTS} -l kubernetes.unstable.cloud/installed-by=porkadot"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=apiextensions.k8s.io/v1/customresourcedefinition"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=apps/v1/daemonset"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=apps/v1/deployment"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=core/v1/configmap"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=core/v1/namespace"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=core/v1/service"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=core/v1/secret"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=core/v1/serviceaccount"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=policy/v1/poddisruptionbudget"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=rbac.authorization.k8s.io/v1/clusterrole"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=rbac.authorization.k8s.io/v1/clusterrolebinding"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=rbac.authorization.k8s.io/v1/role"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=rbac.authorization.k8s.io/v1/rolebinding"
KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=admissionregistration.k8s.io/v1/validatingwebhookconfiguration"

/opt/bin/kubectl apply --force-conflicts --server-side -R -f ${ROOT}/manifests/crds
/opt/bin/kubectl wait --for condition=established --timeout=60s crd --all
/opt/bin/kubectl apply ${KUBECTL_OPTS} -k ${ROOT}
