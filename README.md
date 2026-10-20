# kro Supervisor Service

Packages upstream [kro](https://kro.run) as a vSphere Supervisor Service. kro lets you define new Kubernetes APIs from a ResourceGraphDefinition (RGD) and turns each instance of that API into a set of managed resources.

- Upstream chart: `oci://registry.k8s.io/kro/charts/kro`, currently 0.9.4 ([source](https://github.com/kubernetes-sigs/kro))
- Carvel package: `kro.field.vmware.com`
- Bundle: `ghcr.io/warroyo/kro-supervisor-service`
- Service version: in `VERSION`, and on the [releases page](https://github.com/warroyo/kro-supervisor-service/releases)

The service version is independent of the chart version. A fix to the Supervisor overrides can ship without a chart update. See [CHANGELOG.md](CHANGELOG.md) for what changed in each release.

## Install

1. In vCenter, go to Workload Management > Services.
2. Add a new service and upload `kro-service.yml` from the [GitHub release](https://github.com/warroyo/kro-supervisor-service/releases).
3. Install the service on a Supervisor. Provide a values YAML (see below).

`make install-supervisor-service` does steps 2 and 3 through the vCenter API (see [Testing on a Supervisor](#testing-on-a-supervisor)).

Example values:

```yaml
admins:
  groups:
  - sso:Administrators@vsphere.local
  users:
  - sso:alice@vsphere.local
```

The controller can already manage the kinds RGDs commonly use on a Supervisor, such as VMs, VKS clusters, DSM databases and Secret Store secrets (see [Controller](#controller)). Add `controllerRules` only for other kinds:

```yaml
controllerRules:
- apiGroups: ["monitoring.coreos.com"]
  resources: ["servicemonitors"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

Check which kinds your Supervisor has with `kubectl api-resources`. To let VCF Automation organizations author RGDs, add the `multitenancy` values (see [Multitenancy](#multitenancy)).

An upgrade through `make install-supervisor-service` keeps the values the service already runs with, unless you set `SERVICE_VALUES`.

## Configuration

You can set any [upstream chart value](https://github.com/kubernetes-sigs/kro/blob/main/helm/values.yaml). These values are specific to this service:

| Value | Default | Purpose |
|---|---|---|
| `namespace` | set by the Supervisor | The service namespace (`svc-kro-<random>`). Do not set it. |
| `admins.groups` | `[]` | vSphere SSO groups, for example `sso:Administrators@vsphere.local`. Members get ClusterRole `kro:admin`: manage ResourceGraphDefinitions and read GraphRevisions. |
| `admins.users` | `[]` | vSphere SSO users, for example `sso:alice@vsphere.local`, who get `kro:admin`. Nothing is bound when both lists are empty. |
| `defaultControllerRules` | `true` | Ships ClusterRole `kro:controller:defaults`: the namespaced kinds RGDs commonly use on a Supervisor (see [Controller](#controller)). |
| `controllerRules` | `[]` | Extra RBAC rules for the kro controller, on top of the defaults. Rendered into ClusterRole `kro:controller:supervisor`, labeled `rbac.kro.run/aggregate-to-controller`. |
| `multitenancy.enabled` | `false` | Lets platform teams in VCF Automation organizations author RGDs. See [docs/authoring-modes.md](docs/authoring-modes.md). |
| `multitenancy.oidcClientId` | `""` | Client ID of the OIDC identity provider VCF Automation registered on this Supervisor. Required when multitenancy is on. |
| `multitenancy.orgs` | `[]` | Organizations allowed to author, as `name`, `id` and `authorProjects` (a list of project `name` and `id`, the Project's `metadata.uid`; at least one). Each organization gets the API group `<name>.kro.run`. Required when multitenancy is on. |

The service changes two upstream defaults:

| Value | Upstream default | Supervisor default | Reason |
|---|---|---|---|
| `rbac.mode` | `unrestricted` (`*/*` cluster-wide) | `aggregation` | The controller gets only what it needs plus `controllerRules`. |
| `deployment.nodeSelector` | `kubernetes.io/os: linux` | `kubernetes.io/os: CRX` | The controller runs as a vSphere Pod. |

The package `valuesSchema` shows the Supervisor defaults, because `make sync` merges the overrides over the chart values.

## Access control

### Controller

In `aggregation` mode the controller can only touch what its aggregated ClusterRoles allow. The service always ships ClusterRole `kro:controller:instances`, which grants all verbs on `kro.run/*`. That lets the controller manage RGD instances.

An RGD can only read (`externalRef`) or create kinds that the controller can access. With `defaultControllerRules: true` the service grants these, all namespaced:

| Area | Kinds | Access |
|---|---|---|
| Kubernetes | ConfigMaps, Secrets, Services, PersistentVolumeClaims, ServiceAccounts; Deployments, StatefulSets; Jobs, CronJobs; HorizontalPodAutoscalers; PodDisruptionBudgets; Ingresses, NetworkPolicies; Gateways, HTTPRoutes; cert-manager Certificates, Issuers | manage |
| Kubernetes | Pods, Events | read |
| VM Service | VirtualMachines, VirtualMachineServices, VirtualMachineGroups, VirtualMachineSnapshots, VirtualMachinePublishRequests | manage |
| VM Service | VirtualMachineClasses, VirtualMachineImages | read |
| VKS | Clusters (`cluster.x-k8s.io`) | manage |
| Data Services Manager | PostgresClusters, MySQLClusters | manage |
| Secret Store | KeyValueSecrets | manage |

RBAC objects, namespaces, quotas and other cluster-scoped kinds are left out on purpose. Add anything else to `controllerRules`. If a kind is missing, the RGD fails at runtime with a forbidden error. The install example above shows the format.

All controller rules apply in every namespace and to every RGD. With multitenancy on, list only namespaced kinds in `controllerRules`: a tenant template has no namespace, so a cluster-scoped kind would be created cluster-wide. The Supervisor also refuses some grants for packages, such as wildcards on the core group or `pods/exec`, and the install fails if one is listed.

To restore the upstream behavior, set `rbac.mode: unrestricted`. This gives the controller `*/*` on the whole cluster.

### Admins and namespace users

By default only the users and groups in `admins` can create and manage RGDs. RGDs are cluster-scoped, so namespace roles never grant them. Namespace users get `kro.run` access through upstream's `kro-edit` and `kro-view` ClusterRoles, which aggregate into the standard `admin`, `edit` and `view` roles.

### Multitenancy

With `multitenancy.enabled: true`, editors and admins of each organization's author projects in VCF Automation also author RGDs, from kubectl or Argo CD. Each organization gets its own API group (`goad.kro.run`), and two admission policies keep its RGDs, kinds and instances inside the organization. [docs/authoring-modes.md](docs/authoring-modes.md) explains both modes with diagrams, the rules, and who can do what.

```yaml
multitenancy:
  enabled: true
  oidcClientId: 4f2c9a1e-7b3d-4c8a-9e61-2d5b8f0a3c7e   # VCF Automation's OIDC client on this Supervisor
  orgs:
  - name: goad                                       # API group goad.kro.run
    id: 6b1d3f8a-2c4e-4a7b-8d9f-0e5c7a1b3d2f         # organization UUID
    authorProjects:
    - name: kro-authors
      id: 9a7e5c3b-1d2f-4e6a-8b0c-4f3d2e1a0b9c       # the Project's metadata.uid
```

You don't need to look these IDs up. Run `scripts/multitenancy-values.sh <namespace-context> <org name>` with a kubectl context for a namespace of the author project, as one of its editors, and it prints this block. Only VCF Automation organizations can author: their users reach the Supervisor through the VCF Automation proxy, which sends the organization and project. vSphere users author only through `admins`.

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
make render     # render the package to _out/rendered.yaml and _out/rendered-multitenancy.yaml
make validate   # render, then kubeconform and the check scripts
```

`make sync` runs vendir, deep-merges `service/supervisor-overrides/supervisor-values.yaml` over the chart `values.yaml` (the overrides win), and copies `service/supervisor-overrides/templates/` into the chart. `service/upstream/` is not committed. Edit only `service/supervisor-overrides`.

`make render` renders the way kapp-controller does: `helm template` into the placeholder namespace `kro`, then `ytt`. It renders twice: with `test/values-supervisor.yaml`, and with `test/values-multitenancy.yaml` layered on top.

`make validate` runs kubeconform in strict mode on both renders. Then `test/check-rendered.sh` asserts that:

- nothing is left in the placeholder namespace `kro`
- the Deployment and ServiceAccount are in the service namespace
- the controller ClusterRoleBinding subject points at the service namespace
- the controller pods use the `CRX` node selector
- no ClusterRole grants `*` on `*` in aggregation mode
- the controller aggregation ClusterRoles are present (upstream `kro:controller:static`, `kro:controller:instances`, `kro:controller:defaults` and `controllerRules`)
- the default controller rules name every kind, with no wildcards, and include no RBAC, namespaces or other cluster-scoped kinds
- `kro:admin` is bound to every group and user in `admins`
- the RGD and GraphRevision CRDs are present

`test/check-rendered-multitenancy.sh` checks the multitenancy render: the author ClusterRoleBinding names one exact group per author project and not `system:authenticated`, the per-organization roles and API groups, both admission policies (fail closed, bound with Deny), and the kapp change group and change rules.

### Testing on a Supervisor

`make install-supervisor-service` registers `kro-service.yml` in vCenter and installs or upgrades it on the Supervisor through the vCenter API. A first install uses `test/values-supervisor.yaml` (minus `namespace`). An upgrade keeps the values already installed. Set `SERVICE_VALUES` to use another file.

```bash
export VC_HOST=vc01.example.lab VC_USER=administrator@vsphere.local VC_PASSWORD_FILE=/path/to/pw
make install-supervisor-service
make smoke-test NAMESPACE=<supervisor-namespace>
```

`make smoke-test` needs a kubectl context on the Supervisor as a user in `admins` or in one of its groups. It creates the `KroSmoke` RGD in `test/smoke/`, creates an instance in the namespace, checks that the instance becomes a ConfigMap, then deletes both.

To test a change before it is released, build a pre-release package. `make test-package` pushes the bundle to ghcr and writes `_out/kro-service.yml`, and leaves the committed release files as they were:

```bash
make sync
make test-package VERSION=1.2.0-rc.1
SERVICE_YAML=_out/kro-service.yml SERVICE_VALUES=my-values.yaml make install-supervisor-service
```

### Testing multitenancy on a Supervisor

`make smoke-test-multitenancy` runs `test/smoke/multitenancy.sh`. It checks who may write RGDs, every content rule, and where tenant instances may live. Each content rule has a fixture in `test/smoke/multitenancy/deny/` with the message it must be refused with, so a denial for the wrong reason fails. Add a fixture there when you add a rule. All RGD writes in `deny/` and `allow/` are server-side dry runs.

One-time setup, in an organization that will author (here `acme`):

1. As an org admin of `acme` in VCF Automation, create a project (any name, here `kro-authors`) and a Supervisor namespace in it. With the vcf CLI context of the org (`vcfa` here):

   ```bash
   kubectl --context vcfa create -f - <<EOF
   apiVersion: project.cci.vmware.com/v1alpha2
   kind: Project
   metadata:
     name: kro-authors
   EOF
   # then a SupervisorNamespace in namespace kro-authors, copied from one of your existing ones
   ```

   Use `kubectl create`, not `apply`: VCF Automation refuses the annotation that `apply` adds.
2. Get a kubectl context for the new namespace. `vcf context refresh <context>` should create it. If it does not, run `test/add-namespace-context.sh vcfa kro-authors <namespace>`.
3. Install the service with multitenancy on. Copy `test/values-live-multitenancy.yaml.example` and set your admins. Run `scripts/multitenancy-values.sh <namespace context> <org name>` with the context from step 2 to print the organization's values, and merge them into the file. List a second organization too, for the checks between organizations.

Then run it with four settings, plus two optional ones for a second organization:

```bash
export KRO_ADMIN_CONTEXT=sup-gpu                                        # Supervisor, member of admins
export KRO_AUTHOR_CONTEXT=vcfa:kro-authors-9k6vx:kro-authors            # acme, kro-authors namespace
export KRO_ORG_USER_CONTEXT=vcfa:dev-1-lbtbl:tenant-1                   # acme, a namespace in another project
export KRO_ORG=acme
export KRO_OTHER_ORG_CONTEXT=goad-pe:music-store-8q8l6:default-project  # optional: another organization
export KRO_OTHER_ORG=goad
make smoke-test-multitenancy
```

Non-authors are stopped by RBAC (`is forbidden`), before the admission policy runs. The script creates RGDs `mt-notes` and `mt-admin-notes` and an `MtNote` instance, and deletes them when it ends. Its exit status is the number of failed checks. Run `make smoke-test` too: admins-only behavior must not change.

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
├── Makefile                         # sync, render, validate, release, test-package, install and smoke tests
├── kro-service.yml                  # Package + PackageMetadata, written by release
├── renovate.json                    # Renovate config for service/vendir.yml
├── docs/
│   └── authoring-modes.md           # admins-only vs multitenancy, with diagrams
├── scripts/
│   ├── multitenancy-values.sh       # prints multitenancy values for an author project
│   └── next-version.sh              # computes the service version after a chart bump
├── test/
│   ├── values-supervisor.yaml       # values used by make render
│   ├── values-multitenancy.yaml     # layered on top for the multitenancy render
│   ├── check-rendered.sh            # assertions on the rendered package
│   ├── check-rendered-multitenancy.sh # assertions on the multitenancy render
│   ├── values-live-multitenancy.yaml.example # install values for a live multitenancy test
│   ├── install-supervisor-service.sh # register + install through the vCenter API
│   ├── add-namespace-context.sh     # kubectl context for a VCF Automation namespace
│   └── smoke/                       # KroSmoke round trip, and multitenancy.sh with its fixtures
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
    │   └── templates/supervisor/    # ns-overlay, kro:admin, controller RBAC and defaults, multitenancy
    ├── carvel-artifacts/            # generated package artifacts, committed by release
    └── upstream/                    # filled by make sync, not committed
```
