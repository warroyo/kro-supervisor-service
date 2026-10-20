{{/*
The group VCF Automation sends for an editor or admin of a project:

  edit-<project uid>-<project name>@<OIDC client ID>.net

The project uid and the client ID lose their hyphens. The project name is
lowercased, loses every character that is not a letter or digit, and is cut to
10 characters: kro-authors becomes kroauthors. The client ID is the one VCF
Automation registered on this Supervisor as an identity provider, the same for
every organization on the Supervisor.

Call with (dict "project" <authorProjects entry> "root" $).
*/}}
{{- define "kro.authorGroup" -}}
{{- $name := regexReplaceAll "[^a-z0-9]" (.project.name | toString | lower) "" | trunc 10 -}}
{{- $id := .project.id | toString | lower | replace "-" "" -}}
{{- $client := .root.Values.multitenancy.oidcClientId | toString | lower | replace "-" "" -}}
{{- printf "edit-%s-%s@%s.net" $id $name $client -}}
{{- end }}

{{/*
kapp change group of the two admission policies. Objects that grant what the
policies restrict are applied after them and deleted before them, so the grants
never exist without the policies.
*/}}
{{- define "kro.multitenancyPolicyChangeGroup" -}}
kro.field.vmware.com/multitenancy-policy
{{- end }}

{{- define "kro.afterMultitenancyPolicy" -}}
kapp.k14s.io/change-rule.0: "upsert after upserting {{ include "kro.multitenancyPolicyChangeGroup" . }}"
kapp.k14s.io/change-rule.1: "delete before deleting {{ include "kro.multitenancyPolicyChangeGroup" . }}"
{{- end }}
