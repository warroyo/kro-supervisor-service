#!/usr/bin/env bash
# Checks the multitenancy objects in a package rendered with
# test/values-multitenancy.yaml (see `make render`).
set -euo pipefail

rendered=${1:?usage: check-rendered-multitenancy.sh <rendered.yaml>}
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

policy='select(.kind == "ValidatingAdmissionPolicy" and .metadata.name == "kro-multitenancy")'
instances='select(.kind == "ValidatingAdmissionPolicy" and .metadata.name == "kro-multitenancy-instances")'

author='select(.kind == "ClusterRoleBinding" and .metadata.name == "kro:tenant-author")'
acme_group=edit-9a7e5c3b1d2f4e6a8b0c4f3d2e1a0b9c-kroauthors@4f2c9a1e7b3d4c8a9e612d5b8f0a3c7e.net

check "RGD writes are not open to every authenticated user" \
  "$author | .subjects[] | select(.name == \"system:authenticated\")" 0
check "RGD writes bound to one exact group per author project" \
  "$author | .subjects[] | select(.kind == \"Group\" and (.name | test(\"^edit-[0-9a-f]{32}-[a-z0-9]{1,10}@4f2c9a1e7b3d4c8a9e612d5b8f0a3c7e[.]net$\")))" 3
check "author group built from project uid, reduced name and client ID" \
  "$author | .subjects[] | select(.name == \"$acme_group\")" 1
check "project name reduced to 10 letters and digits" \
  "$author | .subjects[] | select(.name == \"edit-11111111222243338444555555555555-platformte@4f2c9a1e7b3d4c8a9e612d5b8f0a3c7e.net\")" 1
check "policies in the kapp change group" \
  'select(.kind == "ValidatingAdmissionPolicy" or .kind == "ValidatingAdmissionPolicyBinding") | select(.metadata.annotations."kapp.k14s.io/change-group" == "kro.field.vmware.com/multitenancy-policy")' 4
check "author binding and org edit roles applied after and deleted before the policies" \
  'select(.metadata.annotations."kapp.k14s.io/change-rule.0" == "upsert after upserting kro.field.vmware.com/multitenancy-policy" and .metadata.annotations."kapp.k14s.io/change-rule.1" == "delete before deleting kro.field.vmware.com/multitenancy-policy")' 3
check "one edit, view and controller ClusterRole per org" \
  'select(.kind == "ClusterRole" and (.metadata.name | test("^kro:tenant:(goad|acme):(edit|view|controller)$")))' 6
check "org roles name only the org API group" \
  'select(.kind == "ClusterRole" and .metadata.name == "kro:tenant:goad:edit") | .rules[].apiGroups[] | select(. == "goad.kro.run")' 1
check "controller aggregates every org API group" \
  'select(.kind == "ClusterRole" and .metadata.labels."rbac.kro.run/aggregate-to-controller" == "true" and (.metadata.name | test("^kro:tenant:")))' 2
check "aggregation mode: still no wildcard ClusterRole" \
  'select(.kind == "ClusterRole") | .rules[]? | select((.apiGroups[] | test("^\*$")) and (.resources[] | test("^\*$")))' 0
check "both policies fail closed" \
  'select(.kind == "ValidatingAdmissionPolicy" and .spec.failurePolicy == "Fail")' 2
check "both policies bound with Deny" \
  'select(.kind == "ValidatingAdmissionPolicyBinding") | .spec.validationActions[] | select(. == "Deny")' 2
check "kro controller exempt by its service namespace" \
  "$policy | .spec.matchConditions[] | select(.expression | contains(\"system:serviceaccount:$ns:\"))" 1
check "admins from values bypass the tenant rules" \
  "$policy | .spec.variables[] | select(.name == \"isAdmin\" and (.expression | contains(\"sso:kro-admins@vsphere.local\")))" 1
check "policy maps each author group to its org" \
  "$policy | .spec.variables[] | select(.name == \"authorGroups\" and (.expression | contains(\"\\\"$acme_group\\\":\\\"acme\\\"\")))" 1
check "org IDs map to org names" \
  "$policy | .spec.variables[] | select(.name == \"orgs\" and (.expression | contains(\"\\\"6b1d3f8a-2c4e-4a7b-8d9f-0e5c7a1b3d2f\\\":\\\"goad\\\"\")))" 1
check "instance policy covers exactly the org API groups" \
  "$instances | .spec.matchConstraints.resourceRules[0].apiGroups[] | select(. == \"goad.kro.run\" or . == \"acme.kro.run\")" 2

exit $fail
