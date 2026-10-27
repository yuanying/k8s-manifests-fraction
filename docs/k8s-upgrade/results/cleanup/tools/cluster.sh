#!/bin/bash
# pods-before.txt: the same listing taken before the cleanup
K="kubectl --context fraction"
echo "notready: $($K get nodes --no-headers | awk '$2!="Ready"' | wc -l)"
echo "bad pods: $($K get pods -A --no-headers --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | wc -l)"
$K get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.status.phase} {range .status.containerStatuses[*]}{.restartCount},{end}{"\n"}{end}' | sort > ${WORK:-/tmp/k8u-cleanup}/pods-now.txt
diff ${WORK:-/tmp/k8u-cleanup}/pods-before.txt ${WORK:-/tmp/k8u-cleanup}/pods-now.txt && echo "pods unchanged"
echo "longhorn: $($K get volumes.longhorn.io -n longhorn-system --no-headers -o custom-columns=S:.status.state,R:.status.robustness | sort | uniq -c | tr '\n' ' ')"
