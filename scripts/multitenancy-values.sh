#!/usr/bin/env bash
# Print the multitenancy values for one author project, read from what VCF
# Automation sends to the Supervisor for its editors.
#
#   scripts/multitenancy-values.sh <namespace-context> <org-name> [project-name]
#   scripts/multitenancy-values.sh vcfa:kro-authors-9k6vx:kro-authors acme
#
# <namespace-context> is a kubectl context for any Supervisor namespace of the
# author project, as a user with the edit or admin role there. <org-name> is
# the name to give the organization: its API group becomes <org-name>.kro.run.
# The project name defaults to the last part of a vcf CLI context name
# (<context>:<namespace>:<project>).
#
# Merge the output of several projects by hand: one oidcClientId, one entry per
# organization, one authorProjects entry per project.
set -euo pipefail
ctx=${1:?usage: multitenancy-values.sh <namespace-context> <org-name> [project-name]}
org=${2:?org-name}
project=${3:-${ctx##*:}}

user=$(kubectl --context "$ctx" auth whoami -o json)
org_id=$(jq -r '.status.userInfo.extra["vcf.vmware.com/org_id"][0] // empty' <<<"$user")
[[ -n $org_id ]] || { echo "$ctx is not a VCF Automation user: no vcf.vmware.com/org_id" >&2; exit 1; }
group=$(jq -r '[.status.userInfo.groups[] | select(test("^edit-[0-9a-f]{32}-[a-z0-9]+@[0-9a-f]{32}[.]net$"))][0] // empty' <<<"$user")
[[ -n $group ]] || { echo "$ctx sends no edit-<project>@<client>.net group: use a namespace of the author project, with the edit or admin role" >&2; exit 1; }

[[ $group =~ ^edit-([0-9a-f]{32})-([a-z0-9]+)@([0-9a-f]{32})[.]net$ ]]
uuid() { local h=$1; echo "${h:0:8}-${h:8:4}-${h:12:4}-${h:16:4}-${h:20:12}"; }
project_id=$(uuid "${BASH_REMATCH[1]}")
name_part=${BASH_REMATCH[2]}
client_id=$(uuid "${BASH_REMATCH[3]}")

reduced=$(tr 'A-Z' 'a-z' <<<"$project" | tr -cd 'a-z0-9' | cut -c1-10)
if [[ $reduced != "$name_part" ]]; then
  echo "project name '$project' becomes '$reduced', but the group says '$name_part'. Pass the project name as the third argument." >&2
  exit 1
fi

cat <<EOF
multitenancy:
  enabled: true
  oidcClientId: $client_id
  orgs:
  - name: $org
    id: $org_id
    authorProjects:
    - name: $project
      id: $project_id
EOF
