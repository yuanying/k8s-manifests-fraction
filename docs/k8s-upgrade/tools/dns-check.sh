#!/usr/bin/env bash
# Read-only. Ask the cluster DNS the same questions before and after CoreDNS changes
# (runbook-stage-6 §1.8, §2.2 item 23, §3.3 item 13):
# the kube-dns Service (10.254.0.10) from this host, and each CoreDNS Pod from a node
# (Pod IPs are not routed to the workstation).
#
#   docs/k8s-upgrade/tools/dns-check.sh [node-ssh-target] > <file>
#
# node-ssh-target defaults to yuanying@192.168.1.134 (pablo); the node needs dig.
# Prints one line per question: "<question> -> <sorted answers> status: <rcode>".
set -u
K="kubectl --context fraction"
NODE=${1:-yuanying@192.168.1.134}
pods=$($K -n kube-system get pods -l k8s-app=kube-dns -o jsonpath='{.items[*].status.podIP}')
kd=$($K -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns -o jsonpath='{range .items[?(@.addressType=="IPv4")].endpoints[*]}{.addresses[0]}{" "}{end}')
h2=$($K -n fs get endpointslices -l kubernetes.io/service-name=h2 -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{" "}{end}')
questions() {
  echo kubernetes.default.svc.cluster.local A
  echo kubernetes.default.svc.cluster.local AAAA
  echo kubernetes.default.svc.fraction.cluster A
  echo h2.fs.svc.cluster.local A
  echo h2.fs.svc.cluster.local AAAA
  echo -x 10.254.0.1
  echo -x 10.254.0.10
  echo -x fd20:afc2:7c09::521
  for ip in $kd $h2; do echo -x $ip; done
  echo www.google.com A
  echo www.google.com AAAA
  echo github.com A
  echo no-such-name.example.invalid A
  echo no-such-svc.default.svc.cluster.local A
}
ask() { # $1 = server; reads questions on stdin; prints "question -> answers status"
  while read -r a b; do
    echo "$a $b -> $(dig -4 +short +time=2 +tries=1 @$1 $a $b 2>/dev/null | sort | tr '\n' ' ')$(dig -4 +time=2 +tries=1 @$1 $a $b 2>/dev/null | grep -o 'status: [A-Z]*')"
  done
}
echo "## server 10.254.0.10 (Service, from $(hostname))"
questions | ask 10.254.0.10
for p in $pods; do
  echo "## server $p (Pod, from $NODE)"
  questions | ssh -o BatchMode=yes $NODE "$(declare -f ask); ask $p"
done
