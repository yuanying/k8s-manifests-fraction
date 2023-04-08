#!/bin/bash

set -euxo pipefail

# chirico
ssh yuanying@192.168.1.83 sudo cp -rp /var/lib/longhorn/vms/data-0/disk.img /var/lib/longhorn/vms/data-1/disk.img
ssh yuanying@192.168.1.83 sudo cp -rp /var/lib/longhorn/vms/data-0/disk.img /var/lib/longhorn/vms/data-2/disk.img
ssh yuanying@192.168.1.83 sudo cp -rp /var/lib/longhorn/vms/data-0/disk.img /var/lib/longhorn/vms/data-3/disk.img

# oeilvert
ssh yuanying@192.168.1.82 sudo cp -rp /var/lib/longhorn/vms/data-0/disk.img /var/lib/longhorn/vms/data-1/disk.img
ssh yuanying@192.168.1.82 sudo cp -rp /var/lib/longhorn/vms/data-0/disk.img /var/lib/longhorn/vms/data-2/disk.img

# duchamp
ssh yuanying@192.168.1.135 sudo cp -rp /var/lib/longhorn/vms/data-0/disk.img /var/lib/longhorn/vms/data-1/disk.img

# pablo
ssh yuanying@192.168.1.134 sudo cp -rp /var/lib/longhorn/vms/data-0/disk.img /var/lib/longhorn/vms/data-1/disk.img
