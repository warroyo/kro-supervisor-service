# Changelog

All notable changes to this service are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The service version is independent of the kro chart version.

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
