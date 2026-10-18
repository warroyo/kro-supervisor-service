#!/usr/bin/env bash
# Prints the service version that follows an upstream chart bump.
# An upstream major or minor change bumps the service minor; an upstream patch
# bumps the service patch. The service major is only ever bumped by hand.
#
#   scripts/next-version.sh <service-version> <old-chart-version> <new-chart-version>
#   scripts/next-version.sh 1.1.0 0.9.4 0.10.0   # 1.2.0
set -euo pipefail

service=${1:?service version}
old=${2#v}
new=${3#v}

IFS=. read -r s_major s_minor s_patch <<<"$service"
IFS=. read -r o_major o_minor _ <<<"$old"
IFS=. read -r n_major n_minor _ <<<"$new"

if [[ $o_major != "$n_major" || $o_minor != "$n_minor" ]]; then
  echo "$s_major.$((s_minor + 1)).0"
else
  echo "$s_major.$s_minor.$((s_patch + 1))"
fi
