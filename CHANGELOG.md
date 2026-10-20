# Changelog

All notable changes to this service are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The service version is independent of the kro chart version.

## [1.2.0] - Unreleased

### Added

- Multitenancy mode for VCF Automation (`multitenancy.enabled`, off by default). Editors and admins of each organization's author projects author ResourceGraphDefinitions from kubectl or Argo CD, without being Supervisor admins. Author projects are listed per organization by name and uid (`multitenancy.orgs[].authorProjects`), and `multitenancy.oidcClientId` is the OIDC client of VCF Automation on the Supervisor. The ClusterRoleBinding `kro:tenant-author` is bound to the exact author group of each listed project, so only admins and author project editors can read or write RGDs. kapp applies it after the policies and removes it before them. Each organization gets the API group `<name>.kro.run`. The admission policy `kro-multitenancy` checks the author, ownership and content of tenant RGDs, and `kro-multitenancy-instances` keeps an organization's instances in its namespaces. See [docs/authoring-modes.md](docs/authoring-modes.md).
- `scripts/multitenancy-values.sh` prints the multitenancy values for an author project from `kubectl auth whoami`.
- A default set of controller permissions (`defaultControllerRules`, on by default): ClusterRole `kro:controller:defaults` lets kro manage the namespaced kinds RGDs commonly use on a Supervisor, including VMs, VKS clusters, DSM databases and Secret Store secrets. `controllerRules` is now for extras only.
- `make smoke-test-multitenancy` (`test/smoke/multitenancy.sh`): live checks of the multitenancy rules, with one fixture per content rule in `test/smoke/multitenancy/`.
- `make test-package` builds and pushes a pre-release package to `_out/kro-service.yml` without changing the committed release files.
- `test/add-namespace-context.sh` adds a kubectl context for a VCF Automation namespace when `vcf context refresh` does not.

## [1.1.0] - Unreleased

### Changed

- Upstream kro moves from 0.4.1 to 0.9.4.
- The chart now comes from `oci://registry.k8s.io/kro/charts` (was `oci://ghcr.io/kro-run/kro`). The controller image is now `registry.k8s.io/kro/kro`.
- Leader election is on by default (upstream change).
- **Breaking:** the RBAC mode now defaults to `aggregation` (was upstream `unrestricted`, `*/*` cluster-wide). RGDs that read or create kinds other than `kro.run` need rules in the new `controllerRules` value. To keep the old behavior, set `rbac.mode: unrestricted`.
- The old `aggregate-kro-edit` and `aggregate-kro-view` ClusterRoles are replaced by upstream's `kro-edit` and `kro-view`.
- `adminGroup` is replaced by `admins.groups` and `admins.users`, so several groups and individual users can get `kro:admin`. The binding is rendered only when one of them is set. `kro:admin` now also grants read access to GraphRevisions.
- The upstream chart is no longer committed. `make sync` fetches it and applies `service/supervisor-overrides`.

### Added

- GraphRevision CRD (upstream).
- `controllerRules` value for extra controller RBAC, rendered into ClusterRole `kro:controller:supervisor`.
- ClusterRole `kro:controller:instances`, which lets the controller manage RGD instances (`kro.run/*`, all verbs).
- Renovate configuration for chart updates, a CI validation workflow, and automated releases.

## [1.0.5]

- kro 0.4.1 (last release before this changelog).
