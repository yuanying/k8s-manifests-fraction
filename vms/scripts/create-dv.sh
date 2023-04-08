#!/bin/bash

set -eu

servers="chirico oeilvert duchamp pablo"

for s in ${servers}; do
    cat <<EOF
---
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: jammy-server-${s}
  namespace: vms
spec:
  source:
    http:
      url: "https://www.fraction.jp/images/jammy-server-cloudimg-amd64.img"
  pvc:
    accessModes:
    - ReadWriteOnce
    storageClassName: manual
    resources:
      requests:
        storage: 10Gi
    selector:
      matchLabels:
        use: "jammy-server-${s}"
---
apiVersion: v1
kind: PersistentVolume
metadata:
  labels:
    use: "jammy-server-${s}"
  name: jammy-server-${s}
spec:
  storageClassName: manual
  capacity:
    storage: "10Gi"
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  local:
    path: /var/lib/longhorn/vms/data-0
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values: [${s}]
EOF
done
