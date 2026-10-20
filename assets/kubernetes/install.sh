#!/bin/bash

set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")
KUBECTL_OPTS=${KUBECTL_OPTS:-""}

KUBE_TARGET=${KUBE_TARGET:-""}
# The bootstrap install turns this off: there the apiservers become ready
# only once everything else is in place.
KUBE_WAIT_APISERVER=${KUBE_WAIT_APISERVER:-"true"}
KUBE_APISERVER_TIMEOUT=${KUBE_APISERVER_TIMEOUT:-"600"}

# Waits until every kube-apiserver Pod runs the applied version. The
# apiservers restart one by one meanwhile, so the status is polled and a
# failed request does not end the wait.
wait_apiserver_rollout() {
  local deadline=$(( $(date +%s) + KUBE_APISERVER_TIMEOUT ))
  local status=""
  while true; do
    status=$(/opt/bin/kubectl -n kube-system rollout status daemonset/kube-apiserver --watch=false 2>&1 || true)
    if [[ "${status}" == *"successfully rolled out"* ]]; then
      echo "${status}"
      return 0
    fi
    if [ "$(date +%s)" -ge "${deadline}" ]; then
      echo "The kube-apiserver rollout did not finish in ${KUBE_APISERVER_TIMEOUT}s: ${status}" >&2
      echo "Nothing else was applied. Check the Pods with" >&2
      echo "  kubectl -n kube-system get pods -l app.kubernetes.io/component=kube-apiserver -o wide" >&2
      echo "and run install kubernetes again once they are ready." >&2
      return 1
    fi
    sleep 5
  done
}

if [ -n "${KUBE_TARGET}" ]; then
  KUBECTL_OPTS="${KUBECTL_OPTS} -l=app.kubernetes.io/component=${KUBE_TARGET}"
else
  KUBECTL_OPTS="${KUBECTL_OPTS} --prune"
  KUBECTL_OPTS="${KUBECTL_OPTS} -l kubernetes.unstable.cloud/installed-by=porkadot"
  KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=apiextensions.k8s.io/v1/customresourcedefinition"
  KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=apps/v1/daemonset"
  KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=apps/v1/deployment"
  KUBECTL_OPTS="${KUBECTL_OPTS} --prune-allowlist=core/v1/configmap"
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

  # The apiservers have to be on the new version before the other
  # components are: a newer kube-scheduler can wait forever for APIs an
  # older apiserver does not serve, and then nothing schedules the new
  # apiserver Pods (Kubernetes' version skew policy).
  if [ "${KUBE_WAIT_APISERVER}" = "true" ]; then
    /opt/bin/kubectl apply -l=app.kubernetes.io/component=kube-apiserver -k ${ROOT}
    wait_apiserver_rollout
  fi
fi

/opt/bin/kubectl apply ${KUBECTL_OPTS} -k ${ROOT}
