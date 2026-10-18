#!/usr/bin/env bash
# Smoke test against a Supervisor with the service installed.
#   test/smoke/run.sh <supervisor-namespace>
# Needs a kubectl context on the Supervisor as a member of admins (a listed user or group).
set -euo pipefail
ns=${1:?usage: run.sh <supervisor-namespace>}
dir=$(cd "$(dirname "$0")" && pwd)

cleanup() {
  kubectl delete -n "$ns" -f "$dir/instance.yaml" --ignore-not-found --wait=true >/dev/null || true
  kubectl delete -f "$dir/rgd.yaml" --ignore-not-found >/dev/null || true
}
trap cleanup EXIT

kubectl apply -f "$dir/rgd.yaml"
kubectl wait rgd/krosmokes.kro.run --for=condition=Ready --timeout=120s
kubectl apply -n "$ns" -f "$dir/instance.yaml"
kubectl wait -n "$ns" krosmoke/smoke --for=jsonpath='{.status.state}'=ACTIVE --timeout=120s
got=$(kubectl get -n "$ns" configmap smoke-smoke -o jsonpath='{.data.message}')
[[ $got == "kro supervisor service works" ]] || { echo "FAIL: ConfigMap message is '$got'"; exit 1; }
echo "ok   instance reconciled into ConfigMap smoke-smoke: $got"
