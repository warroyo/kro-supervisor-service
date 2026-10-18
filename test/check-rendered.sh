#!/usr/bin/env bash
# Checks the Supervisor-specific parts of a rendered package (see `make render`).
# Fails when an upstream chart change silently breaks an override.
set -euo pipefail

rendered=${1:?usage: check-rendered.sh <rendered.yaml>}
ns=$(yq '.namespace' test/values-supervisor.yaml)
fail=0

check() {
  local desc=$1 expr=$2 want=$3 got
  got=$(yq ea -N "[$expr] | length" "$rendered")
  if [[ $got == "$want" ]]; then
    echo "ok   $desc"
  else
    echo "FAIL $desc: got $got, want $want"
    fail=1
  fi
}

check "nothing left in the placeholder namespace kro" \
  'select(.metadata.namespace == "kro")' 0
check "controller Deployment in the service namespace" \
  "select(.kind == \"Deployment\" and .metadata.namespace == \"$ns\")" 1
check "controller ServiceAccount in the service namespace" \
  "select(.kind == \"ServiceAccount\" and .metadata.namespace == \"$ns\")" 1
check "controller ClusterRoleBinding subject in the service namespace" \
  "select(.kind == \"ClusterRoleBinding\") | .subjects[] | select(.kind == \"ServiceAccount\" and .namespace == \"$ns\")" 1
check "no ServiceAccount subject left in kro" \
  'select(.kind == "ClusterRoleBinding") | .subjects[] | select(.kind == "ServiceAccount" and .namespace == "kro")' 0
check "controller pods run as vSphere Pods (CRX)" \
  'select(.kind == "Deployment") | select(.spec.template.spec.nodeSelector."kubernetes.io/os" == "CRX")' 1
check "aggregation mode: no wildcard ClusterRole" \
  'select(.kind == "ClusterRole") | .rules[]? | select((.apiGroups[] | test("^\*$")) and (.resources[] | test("^\*$")))' 0
check "controller aggregates kro instances and controllerRules" \
  'select(.kind == "ClusterRole" and .metadata.labels."rbac.kro.run/aggregate-to-controller" == "true")' 3
check "kro:admin bound to adminGroup" \
  'select(.kind == "ClusterRoleBinding" and .metadata.name == "wcp:administrators:kro:admin") | .subjects[] | select(.name == "sso:Administrators@vsphere.local")' 1
check "CRDs for RGDs and GraphRevisions" \
  'select(.kind == "CustomResourceDefinition")' 2

exit $fail
