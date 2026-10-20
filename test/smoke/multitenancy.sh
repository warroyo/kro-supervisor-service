#!/usr/bin/env bash
# Multitenancy test against a Supervisor with the service installed and
# multitenancy.enabled: true. It checks who may write ResourceGraphDefinitions,
# what a tenant RGD may contain, and where tenant instances may live.
#
# It needs kubectl contexts, all set as environment variables:
#
#   KRO_ADMIN_CONTEXT       on the Supervisor, as a member of admins (sup-gpu)
#   KRO_AUTHOR_CONTEXT      VCF Automation, a namespace in KRO_ORG's kro author
#                           project, with the edit or admin role
#   KRO_ORG_USER_CONTEXT    VCF Automation, a namespace of KRO_ORG in another
#                           project. Instances are created there.
#   KRO_ORG                 name of KRO_ORG in multitenancy.orgs, e.g. acme
#
# Optional, for the checks between organizations:
#
#   KRO_OTHER_ORG_CONTEXT   VCF Automation, a namespace of another organization
#                           (listed or not), outside its kro author project
#   KRO_OTHER_ORG           its name in multitenancy.orgs; defaults to "other"
#
# Each context must set a namespace. Every RGD write in deny/ and allow/ is a
# server-side dry run; the script creates and deletes only mt-notes,
# mt-admin-notes and one instance. Exit status is the number of failed checks.
set -uo pipefail

: "${KRO_ADMIN_CONTEXT:?set KRO_ADMIN_CONTEXT}"
: "${KRO_AUTHOR_CONTEXT:?set KRO_AUTHOR_CONTEXT}"
: "${KRO_ORG_USER_CONTEXT:?set KRO_ORG_USER_CONTEXT}"
: "${KRO_ORG:?set KRO_ORG}"
KRO_OTHER_ORG_CONTEXT=${KRO_OTHER_ORG_CONTEXT:-}
KRO_OTHER_ORG=${KRO_OTHER_ORG:-other}

dir=$(cd "$(dirname "$0")/multitenancy" && pwd)
work=$(mktemp -d)
passed=0
failed=0

ns_of() {
  kubectl config view -o jsonpath="{.contexts[?(@.name==\"$1\")].context.namespace}"
}
ORG_NS=$(ns_of "$KRO_ORG_USER_CONTEXT")
[[ -n $ORG_NS ]] || { echo "context $KRO_ORG_USER_CONTEXT sets no namespace" >&2; exit 1; }

# render <fixture> -> path of a copy with the organization names filled in
render() {
  local out
  out="$work/$(basename "$(dirname "$1")")-$(basename "$1")"
  sed -e "s/__ORG__/$KRO_ORG/g" -e "s/__OTHER_ORG__/$KRO_OTHER_ORG/g" "$1" > "$out"
  echo "$out"
}

ok()   { passed=$((passed + 1)); echo "ok   $*"; }
fail() { failed=$((failed + 1)); echo "FAIL $*"; }

# check <allow|deny> <description> <message substring or -> <context> <kubectl args...>
# A deny passes only when the error contains the message, so a denial for the
# wrong reason (RBAC, a typo in the fixture) fails.
check() {
  local want=$1 desc=$2 msg=$3 ctx=$4
  shift 4
  local out rc
  out=$(kubectl --context "$ctx" "$@" 2>&1)
  rc=$?
  out=$(tr '\n' ' ' <<<"$out")
  if [[ $want == allow ]]; then
    if [[ $rc -eq 0 ]]; then ok "[allow] $desc"; else fail "[want allow] $desc: $out"; fi
  elif [[ $rc -eq 0 ]]; then
    fail "[want deny] $desc: allowed"
  elif [[ $msg != - && $out != *"$msg"* ]]; then
    fail "[want deny: $msg] $desc: $out"
  else
    ok "[deny]  $desc"
  fi
}

expected_message() {
  sed -n 's/^# expect: //p' "$1" | sed -e "s/__ORG__/$KRO_ORG/g" -e "s/__OTHER_ORG__/$KRO_OTHER_ORG/g"
}

cleanup() {
  kubectl --context "$KRO_ORG_USER_CONTEXT" delete -n "$ORG_NS" -f "$(render "$dir/instance.yaml")" \
    --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
  kubectl --context "$KRO_ADMIN_CONTEXT" delete rgd mt-notes mt-admin-notes \
    --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

# Only admins and author project groups have RBAC for RGDs, so everyone else is
# stopped before the admission policy.
FORBIDDEN="is forbidden: User"
ANOTHER_ORG="belongs to another organization or to the kro admins"
IMMUTABLE="group is immutable"

echo "== preflight"
check allow "admission policy kro-multitenancy is installed" - "$KRO_ADMIN_CONTEXT" \
  get validatingadmissionpolicybinding kro-multitenancy kro-multitenancy-instances
groups=$(kubectl --context "$KRO_AUTHOR_CONTEXT" auth whoami -o jsonpath='{.status.userInfo.groups}' 2>&1)
if [[ $groups =~ edit-[0-9a-f]{32}-[a-z0-9]+@ ]]; then
  ok "author context sends a VCF Automation project group: ${BASH_REMATCH[0]}"
else
  fail "author context sends no edit-<project>@ group: $groups"
fi

echo "== author in $KRO_ORG's kro author project"
check allow "create RGD mt-notes in $KRO_ORG.kro.run" - "$KRO_AUTHOR_CONTEXT" \
  create -f "$(render "$dir/rgd.yaml")"
if kubectl --context "$KRO_ADMIN_CONTEXT" wait rgd/mt-notes --for=condition=Ready --timeout=120s >/dev/null 2>&1; then
  ok "RGD mt-notes is Ready"
else
  fail "RGD mt-notes is not Ready: $(kubectl --context "$KRO_ADMIN_CONTEXT" get rgd mt-notes -o jsonpath='{.status.conditions}' 2>&1)"
fi
check allow "update own RGD" - "$KRO_AUTHOR_CONTEXT" \
  patch rgd mt-notes --type=merge -p '{"spec":{"schema":{"spec":{"message":"string | default=\"updated\""}}}}'
# kro's CRD refuses this before the policy runs. The policy also refuses it.
check deny "move own RGD to $KRO_OTHER_ORG.kro.run" "$IMMUTABLE" "$KRO_AUTHOR_CONTEXT" \
  patch rgd mt-notes --type=merge -p "{\"spec\":{\"schema\":{\"group\":\"$KRO_OTHER_ORG.kro.run\"}}}" --dry-run=server
for f in "$dir"/deny/*.yaml; do
  check deny "$(sed -n '1s/^# //p' "$f")" "$(expected_message "$f")" "$KRO_AUTHOR_CONTEXT" \
    create --dry-run=server -f "$(render "$f")"
done
for f in "$dir"/allow/*.yaml; do
  check allow "$(sed -n '1s/^# //p' "$f")" - "$KRO_AUTHOR_CONTEXT" \
    create --dry-run=server -f "$(render "$f")"
done

echo "== $KRO_ORG user outside the kro author project"
check deny "create RGD (RBAC)" "$FORBIDDEN" "$KRO_ORG_USER_CONTEXT" \
  create --dry-run=server -f "$(render "$dir/rgd.yaml")"
check deny "delete $KRO_ORG's RGD (RBAC)" "$FORBIDDEN" "$KRO_ORG_USER_CONTEXT" \
  delete rgd mt-notes --dry-run=server
check deny "read RGDs (RBAC)" "$FORBIDDEN" "$KRO_ORG_USER_CONTEXT" \
  get rgd mt-notes
check allow "create MtNote instance in $ORG_NS" - "$KRO_ORG_USER_CONTEXT" \
  create -n "$ORG_NS" -f "$(render "$dir/instance.yaml")"
got=""
for _ in $(seq 1 24); do
  got=$(kubectl --context "$KRO_ORG_USER_CONTEXT" get -n "$ORG_NS" configmap mt-live-note -o jsonpath='{.data.message}' 2>/dev/null)
  [[ -n $got ]] && break
  sleep 5
done
if [[ $got == "kro multitenancy works" ]]; then
  ok "instance reconciled into ConfigMap mt-live-note"
else
  fail "ConfigMap mt-live-note has message '$got': $(kubectl --context "$KRO_ORG_USER_CONTEXT" get -n "$ORG_NS" "mtnotes.$KRO_ORG.kro.run" mt-live -o jsonpath='{.status}' 2>&1)"
fi

if [[ -n $KRO_OTHER_ORG_CONTEXT ]]; then
  OTHER_NS=$(ns_of "$KRO_OTHER_ORG_CONTEXT")
  echo "== $KRO_OTHER_ORG, another organization"
  check deny "create RGD in $KRO_OTHER_ORG.kro.run (RBAC)" "$FORBIDDEN" "$KRO_OTHER_ORG_CONTEXT" \
    create --dry-run=server -f "$(render "$dir/deny/other-org-group.yaml")"
  check deny "patch $KRO_ORG's RGD (RBAC)" "$FORBIDDEN" "$KRO_OTHER_ORG_CONTEXT" \
    patch rgd mt-notes --type=merge -p '{"metadata":{"labels":{"mt":"x"}}}' --dry-run=server
  check deny "delete $KRO_ORG's RGD (RBAC)" "$FORBIDDEN" "$KRO_OTHER_ORG_CONTEXT" \
    delete rgd mt-notes --dry-run=server
  check deny "read $KRO_ORG's RGD (RBAC)" "$FORBIDDEN" "$KRO_OTHER_ORG_CONTEXT" \
    get rgd mt-notes
  check deny "create $KRO_ORG's MtNote instance in $OTHER_NS" \
    "can only be created in namespaces of the $KRO_ORG organization" "$KRO_OTHER_ORG_CONTEXT" \
    create -n "$OTHER_NS" --dry-run=server -f "$(render "$dir/instance.yaml")"
else
  echo "== skipping the checks between organizations: KRO_OTHER_ORG_CONTEXT is not set"
fi

echo "== admin RGDs"
check allow "admin creates mt-admin-notes in kro.run" - "$KRO_ADMIN_CONTEXT" \
  create -f "$dir/admin-rgd.yaml"
check allow "author reads the admin RGD" - "$KRO_AUTHOR_CONTEXT" \
  get rgd mt-admin-notes
check deny "author patches the admin RGD" "$ANOTHER_ORG" "$KRO_AUTHOR_CONTEXT" \
  patch rgd mt-admin-notes --type=merge -p '{"metadata":{"labels":{"mt":"x"}}}' --dry-run=server
check deny "author deletes the admin RGD" "$ANOTHER_ORG" "$KRO_AUTHOR_CONTEXT" \
  delete rgd mt-admin-notes --dry-run=server
check deny "author moves the admin RGD into $KRO_ORG.kro.run" "$IMMUTABLE" "$KRO_AUTHOR_CONTEXT" \
  patch rgd mt-admin-notes --type=merge -p "{\"spec\":{\"schema\":{\"group\":\"$KRO_ORG.kro.run\"}}}" --dry-run=server
check allow "admin is not bound by the content rules" - "$KRO_ADMIN_CONTEXT" \
  create --dry-run=server -f "$(render "$dir/deny/cluster-scope.yaml")"
check allow "admin deletes mt-admin-notes" - "$KRO_ADMIN_CONTEXT" \
  delete rgd mt-admin-notes --wait=true --timeout=120s

echo "== author cleans up"
check allow "delete the instance" - "$KRO_ORG_USER_CONTEXT" \
  delete -n "$ORG_NS" "mtnotes.$KRO_ORG.kro.run" mt-live --wait=true --timeout=120s
check allow "author deletes own RGD" - "$KRO_AUTHOR_CONTEXT" \
  delete rgd mt-notes --wait=true --timeout=120s
if kubectl --context "$KRO_ADMIN_CONTEXT" get rgd mt-notes >/dev/null 2>&1; then
  fail "mt-notes still exists: the controller did not remove its finalizer"
else
  ok "mt-notes is gone"
fi

echo
echo "passed $passed, failed $failed"
exit "$failed"
