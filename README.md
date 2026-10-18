# kro Supervisor Service

Packages upstream [kro](https://kro.run) as a vSphere Supervisor Service. kro lets you define new Kubernetes APIs from a ResourceGraphDefinition (RGD) and turns each instance of that API into a set of managed resources.

- Upstream chart: `oci://registry.k8s.io/kro/charts/kro`, currently 0.9.4 ([source](https://github.com/kubernetes-sigs/kro))
- Carvel package: `kro.field.vmware.com`
- Bundle: `ghcr.io/warroyo/kro-supervisor-service`
- Service version: 1.1.0 (see `VERSION`)

The service version is independent of the chart version. A fix to the Supervisor overrides can ship without a chart update. See [CHANGELOG.md](CHANGELOG.md) for what changed in each release.

## Install

1. In vCenter, go to Workload Management > Services.
2. Add a new service and upload `kro-service.yml` from the [GitHub release](https://github.com/warroyo/kro-supervisor-service/releases).
3. Install the service on a Supervisor. Provide a values YAML (see below).

Example values:

```yaml
adminGroup: sso:Administrators@vsphere.local
controllerRules:
- apiGroups: ["secretstore.vmware.com"]
  resources: ["keyvaluesecrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["databases.dataservices.vmware.com"]
  resources: ["postgresclusters"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["vmoperator.vmware.com"]
  resources: ["virtualmachineservices"]
  verbs: ["get", "list", "watch"]
```

These groups match a VCF 9 Supervisor with Data Services Manager and Secret Store. Check yours with `kubectl api-resources`.

## Configuration

You can set any [upstream chart value](https://github.com/kubernetes-sigs/kro/blob/main/helm/values.yaml). These values are specific to this service:

| Value | Default | Purpose |
|---|---|---|
| `namespace` | set by the Supervisor | The service namespace (`svc-kro-domain-cN`). Do not set it. |
| `adminGroup` | `""` | vSphere SSO group, for example `sso:Administrators@vsphere.local`. Members get ClusterRole `kro:admin`: manage ResourceGraphDefinitions and read GraphRevisions. Nothing is bound when empty. |
| `controllerRules` | `[]` | Extra RBAC rules for the kro controller. Rendered into ClusterRole `kro:controller:supervisor`, labeled `rbac.kro.run/aggregate-to-controller`. |

The service changes two upstream defaults:

| Value | Upstream default | Supervisor default | Reason |
|---|---|---|---|
| `rbac.mode` | `unrestricted` (`*/*` cluster-wide) | `aggregation` | The controller gets only what it needs plus `controllerRules`. |
| `deployment.nodeSelector` | `kubernetes.io/os: linux` | `kubernetes.io/os: CRX` | The controller runs as a vSphere Pod. |

The package `valuesSchema` shows the Supervisor defaults, because `make sync` merges the overrides over the chart values.

## Access control

### Controller

In `aggregation` mode the controller can only touch what its aggregated ClusterRoles allow. The service always ships ClusterRole `kro:controller:instances`, which grants all verbs on `kro.run/*`. That lets the controller manage RGD instances.

An RGD can only read (`externalRef`) or create kinds that the controller can access. Add a rule to `controllerRules` for every API group and resource your RGDs use. If a kind is missing, the RGD fails at runtime with a forbidden error. The install example above shows the format.

To restore the upstream behavior, set `rbac.mode: unrestricted`. This gives the controller `*/*` on the whole cluster.

### Admins and namespace users

Members of `adminGroup` can create and manage RGDs. Namespace users get `kro.run` access through upstream's `kro-edit` and `kro-view` ClusterRoles, which aggregate into the standard `admin`, `edit` and `view` roles.

## Updating

Updates are automated. A chart bump is a PR you review and merge. A merge to `main` that changes `VERSION` publishes a release.

### Chart updates

1. The hosted [Mend Renovate](https://github.com/apps/renovate) GitHub app watches `service/vendir.yml`. Install the app on the repo once. It uses a regex custom manager in `renovate.json`: OCI charts go through the `docker` datasource, HTTP Helm repos through the `helm` datasource. Keep the `name`, `repository` and `version` keys in that order in `vendir.yml`, or the regex will not match.
2. When upstream publishes a new chart, Renovate opens a PR that changes the `version` line.
3. The `renovate-sync` workflow runs on that PR. It runs `make sync` and `make validate`, then bumps `VERSION` with `scripts/next-version.sh`:
   - Upstream major or minor change: service minor bump.
   - Upstream patch change: service patch bump.
   - Service major bumps are manual only.
   - If the PR already changed `VERSION`, the bump is skipped.

   The workflow pushes one commit with `VERSION` and `service/vendir.lock.yml` to the PR branch. `gitIgnoredAuthors` in `renovate.json` lets Renovate keep rebasing the branch despite that commit.
4. A reviewer reads the upstream release notes and merges.
5. The `release` workflow runs on the push to `main` because `VERSION` changed. It:
   - runs `make sync` and `make validate`
   - runs `kctrl package release` and pushes the bundle to ghcr
   - commits `service/carvel-artifacts/` and `kro-service.yml` with `[skip ci]`
   - tags `vX.Y.Z`
   - creates a GitHub release with `kro-service.yml` attached

   It skips the release if the tag already exists.

The `validate` workflow runs on every PR and on every push to `main`.

### Override-only changes

To change something in `service/supervisor-overrides` without a chart update, edit the files there and bump `VERSION` by hand in the same PR. The release runs when the PR merges.

## Development

Required tools: `vendir`, `ytt`, `kctrl`, `helm`, `yq` (mikefarah v4) and `kubeconform`.

```bash
make sync       # fetch the chart, merge the overrides, copy the templates
make render     # render the package to _out/rendered.yaml
make validate   # render, then kubeconform and test/check-rendered.sh
```

`make sync` runs vendir, deep-merges `service/supervisor-overrides/supervisor-values.yaml` over the chart `values.yaml` (the overrides win), and copies `service/supervisor-overrides/templates/` into the chart. `service/upstream/` is not committed. Edit only `service/supervisor-overrides`.

`make render` renders the way kapp-controller does: `helm template` into the placeholder namespace `kro`, then `ytt`. It uses `test/values-supervisor.yaml`.

`make validate` runs kubeconform in strict mode, then `test/check-rendered.sh`, which asserts that:

- nothing is left in the placeholder namespace `kro`
- the Deployment and ServiceAccount are in the service namespace
- the controller ClusterRoleBinding subject points at the service namespace
- the controller pods use the `CRX` node selector
- no ClusterRole grants `*` on `*` in aggregation mode
- the controller aggregation ClusterRoles are present (upstream `kro:controller:static`, `kro:controller:instances`, and `controllerRules`)
- `kro:admin` is bound to `adminGroup`
- the RGD and GraphRevision CRDs are present

### Manual release

CI normally does this. To release by hand, log in to ghcr and run `make release`:

```bash
docker login ghcr.io
make sync
make release
```

This runs `kctrl package release` with the version in `VERSION` and writes `kro-service.yml`.

### Why the namespace overlay is a Helm template

The Supervisor injects the target namespace as the package value `namespace`. kapp-controller passes package values only to the first template step, `helmTemplate`. The chart hardcodes `.Release.Namespace`, so it cannot use that value directly.

The fix has two parts. Helm renders the chart into a placeholder namespace, `kro`. Then a ytt overlay moves every object into the real namespace. The overlay file is itself a Helm template that carries ytt annotations. Helm fills in `.Values.namespace`, and the ytt step applies the result. The overlay also rewrites the ServiceAccount subject in the controller ClusterRoleBinding. See `service/supervisor-overrides/templates/supervisor/ns-overlay.yml`.

## Layout

```
.
├── VERSION                          # service version, independent of the chart
├── CHANGELOG.md
├── Makefile                         # sync, render, validate, release
├── kro-service.yml                  # Package + PackageMetadata, written by release
├── renovate.json                    # Renovate config for service/vendir.yml
├── scripts/
│   └── next-version.sh              # computes the service version after a chart bump
├── test/
│   ├── values-supervisor.yaml       # values used by make render
│   └── check-rendered.sh            # assertions on the rendered package
├── .github/
│   ├── actions/setup-tools/         # installs helm, Carvel tools, kubeconform
│   └── workflows/                   # validate, renovate-sync, release
└── service/
    ├── vendir.yml                   # upstream chart source and version
    ├── vendir.lock.yml              # locked chart version
    ├── package-build.yml            # kctrl build config
    ├── package-resources.yml        # Package and PackageMetadata stubs
    ├── supervisor-overrides/
    │   ├── supervisor-values.yaml   # value overrides (edit this)
    │   └── templates/supervisor/    # ns-overlay, kro:admin, controller RBAC
    ├── carvel-artifacts/            # generated package artifacts, committed by release
    └── upstream/                    # filled by make sync, not committed
```
