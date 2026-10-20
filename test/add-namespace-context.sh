#!/usr/bin/env bash
# Add a kubectl context for a VCF Automation Supervisor namespace, named the
# way the vcf CLI names it: <cci-context>:<namespace>:<project>.
#
# `vcf context refresh` is meant to create a context for every namespace, but
# it can skip new ones (seen with VCF CLI 9 when plugin discovery fails). This
# builds the context from the CCI context's own login and certificate.
#
#   test/add-namespace-context.sh <cci-context> <project> <namespace>
#   test/add-namespace-context.sh vcfa kro-authors kro-authors-9k6vx
set -euo pipefail
ctx=${1:?usage: add-namespace-context.sh <cci-context> <project> <namespace>}
project=${2:?project}
ns=${3:?namespace}

cluster=$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"$ctx\")].context.cluster}")
user=$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"$ctx\")].context.user}")
[[ -n $cluster && -n $user ]] || { echo "no context $ctx" >&2; exit 1; }
server=$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"$cluster\")].cluster.server}")
host=${server#https://}
host=${host%%/*}

urn=$(kubectl --context "$ctx" get supervisornamespaces.infrastructure.cci.vmware.com -n "$project" "$ns" \
  -o jsonpath='{.metadata.annotations.infrastructure\.cci\.vmware\.com/id}')
[[ -n $urn ]] || { echo "namespace $ns in project $project has no infrastructure.cci.vmware.com/id yet" >&2; exit 1; }

ca=$(mktemp)
trap 'rm -f "$ca"' EXIT
kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$cluster\")].cluster.certificate-authority-data}" | base64 -d > "$ca"

name="$ctx:$ns@$host"
if [[ -s $ca ]]; then
  kubectl config set-cluster "$name" --server="https://$host/proxy/k8s/namespaces/$urn" \
    --certificate-authority="$ca" --embed-certs >/dev/null
else
  kubectl config set-cluster "$name" --server="https://$host/proxy/k8s/namespaces/$urn" >/dev/null
fi
kubectl config set-context "$ctx:$ns:$project" --cluster="$name" --user="$user" --namespace="$ns" >/dev/null
echo "context $ctx:$ns:$project"
