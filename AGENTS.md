# AGENTS.md

Kubernetes GitOps deployment repository for eLife's Continuum journal platform, managed by Flux CD with Kustomize overlays.

## Stack

- **Flux CD v2** for GitOps reconciliation
- **Kustomize** for template composition (bases + environment overlays)
- **Traefik** ingress controller
- **Kong** API Gateway (via Gateway API)
- **OpenSearch Operator** for search clusters
- **KEDA** for event-driven autoscaling
- **AWS Controllers for Kubernetes (ACK)** for S3, SQS, SNS, IAM
- **External Secrets Operator** for secrets from AWS Secrets Manager
- **Cert-Manager** for TLS certificates
- **Kluctl** for dynamic PR preview environments

## Architecture

Two-tier Kustomize model:

- `kustomizations/<service>/` — reusable base definitions (Deployments, Services, Ingresses, ConfigMaps). Use `${variable}` placeholders for environment-specific values.
- `manifests/<env>/<service>/` — Flux `Kustomization` resources that reference a base path and provide `postBuild.substitute` values. Environments: `test`, `prod`, `previews`.

Each environment has its own namespace: `journal--test`, `journal--prod`, `journal--previews`.

## Services

| Service | Description | Base path |
|---|---|---|
| journal | Main journal web app (PHP + nginx) | `kustomizations/journal/` |
| journal-cms | Content management system | `kustomizations/journal-cms/` |
| search | OpenSearch cluster + queue watcher | `kustomizations/search/` |
| jats-to-pdf | PDF conversion (HTTP-triggered, scales to zero) | `kustomizations/jats-to-pdf/` |
| iiif | IIIF image server (Cantaloupe + Caddy) | `kustomizations/iiif/` |
| digests | Digest service (Django + PostgreSQL) | `kustomizations/digests/` |
| api-gateway | Kong API Gateway with routes | `kustomizations/api-gateway/` |
| basex-validator | XML validation service | `kustomizations/basex-validator/` |
| recommendations | Article recommendations (PHP) | `kustomizations/recommendations/` |
| pattern-library | UI pattern library | `kustomizations/pattern-library/` |

## Commands

```bash
# Trigger Flux to reconcile immediately
make reconcile

# Generate rendered Kustomize output for a kustomization base
make generate-reference TARGET=kustomizations/journal

# Compare current vs reference output
make compare-reference TARGET=kustomizations/journal
```

Note: these commands operate on `kustomizations/<service>/` bases (which are valid Kustomize directories), not on `manifests/<env>/<service>/` (which contain Flux Kustomization CRDs, not Kustomize overlays).

```bash
# Purge a single image from the Cantaloupe (IIIF) cache in prod.
# Credentials are fetched automatically from the iiif-api-admin-secret k8s secret.
# The id is the IIIF image identifier, e.g. the source path used to request the image.
make purge-iiif-cache-item id="lax:100555/elife-100555-fig3-v1.tif"
```

The target port-forwards to the Cantaloupe pod, waits for the tunnel to be ready, then POSTs a `PurgeItemFromCache` task to the `/tasks` API endpoint with HTTP Basic Auth. The port-forward is cleaned up automatically on exit.

## Common Tasks

### Changing configuration for a service

1. Identify whether the change is environment-specific or universal.
2. **Universal**: edit files in `kustomizations/<service>/` (e.g. deployment.yaml, config files).
3. **Environment-specific**: edit the Flux Kustomization in `manifests/<env>/<service>/` — typically adjusting `postBuild.substitute` values, `images` blocks, or adding patches.
4. Always apply to `test` first, then `prod` after validation.

### Adjusting resource requests/limits

Edit the deployment in `kustomizations/<service>/deployment.yaml` or apply a patch in the environment overlay. Convention: set `requests` and `limits` for memory; set only `requests` for CPU.

### Upgrading a dependency version

For image tags managed by Flux automation, changes happen automatically via `ImagePolicy` and `ImageUpdateAutomation`. For manually-pinned versions (e.g. OpenSearch), edit the `postBuild.substitute` value in the environment's Flux Kustomization.

### Adding a new service

Follow the pattern of an existing simple service (e.g. `pattern-library` for always-running services, `jats-to-pdf` for scale-to-zero):

1. **Verify the container image** before writing any configuration:
   - Confirm the exact image name in the registry (it may differ from the service name)
   - Check the tag naming convention (e.g. `master-<hash>-<timestamp>`, `HEAD-<hash>-<timestamp>`, `main-<hash>-<timestamp>`) — this varies between images
   - Confirm the image is publicly accessible; if access is denied (403), verify the image name is correct first — registries return 403 for both private and nonexistent images to avoid leaking what exists. Only configure `imagePullSecrets`/`secretRef` after confirming the name is correct

2. Create `kustomizations/<service>/` with at minimum:
   - `kustomization.yaml` — list resources, add labels, define configMapGenerators
   - `deployment.yaml` — pod spec with `${variable}` placeholders
   - `service.yaml` — ClusterIP service
   - `ingress.yaml` — Traefik ingress with `${hostname}` and TLS
   - `automations/repository.yaml` — `ImageRepository` to scan the container registry
   - `automations/stable-policy.yaml` — `ImagePolicy` with a `filterTags.pattern` matching the image's tag convention. Use a strict regex anchored with `$` (e.g. `'^master-[a-fA-F0-9]+-(?P<ts>\d{8}\.\d{4})$'`) to avoid matching unexpected tag suffixes

3. Create `manifests/test/<service>/` with:
   - `app.yaml` — Flux `Kustomization` referencing `./kustomizations/<service>` with `postBuild.substitute` values (`env`, `hostname`, `cert_manager_issuer`, etc.), an `images` block with `$imagepolicy` markers, and initial tag set to `latest` (Flux automation will update it on first reconciliation)
   - `automation.yaml` — `ImageUpdateAutomation` with `update.path` pointing to `./manifests/test/<service>`

   Note: the image name must be consistent across the deployment, ImageRepository, and the `images` block in the Flux Kustomization.

4. Deploy to `test` first, validate, then create `prod` overlay.

### Adding an AWS resource (SQS, SNS, S3, IAM Role)

Use ACK custom resources in the kustomization base. Follow the patterns in `kustomizations/search/` for SQS queues and IAM roles, or `kustomizations/iiif/` for S3 buckets. Use `${env}` in resource names for environment isolation.

### Setting up autoscaling

- **Queue-based (SQS)**: use KEDA `ScaledObject` — see `kustomizations/search/`
- **HTTP-based**: use KEDA `HTTPScaledObject` — see `kustomizations/jats-to-pdf/`

### Adding secrets

Use `ExternalSecret` resources referencing the `ClusterSecretStore` named `secret-store`. Secrets are stored at paths like `journal-team/<service>/<env>` in the external store.

## Conventions

- **Labels**: always apply `app.kubernetes.io/part-of`, `app.kubernetes.io/name`, `app.kubernetes.io/instance` (with `${env}` suffix)
- **Naming**: services use `<service>-web` for HTTP endpoints; queues use `<service>-queue-watcher`
- **Logging**: if a container stores logs on the filesystem, use Fluent Bit sidecar containers to export to stdout
- **Hostnames**: test uses `<service>.test.elifesciences.org`, prod uses `<service>.elifesciences.org`
- **TLS**: always configure via cert-manager annotation `cert-manager.io/cluster-issuer: "${cert_manager_issuer}"`
- **Image tag patterns**: tag conventions vary by image — always check the actual registry. Use strict anchored regexes in `ImagePolicy.filterTags.pattern` (e.g. end with `$`) to avoid matching variant tags (like `-approved` suffixes)
- **Dependencies**: use `dependsOn` in Flux Kustomizations to ensure proper ordering if one kustomize output (Secret/ConfigMap) is needed for anothers input. Use `substituteFrom` to pass ConfigMap/Secret values as input.

### Verifying a deployment

After pushing changes, verify the deployment is healthy:

1. Run `make reconcile` to trigger immediate Flux reconciliation (otherwise wait for the 1-minute interval).
2. Check the Flux Kustomization is ready: `kubectl get kustomization <service> -n journal--<env>`
3. Check pods are running: `kubectl get pods -n journal--<env> -l app.kubernetes.io/part-of=<service>`
4. For services with image automation, also verify:
   - `kubectl get imagerepository <service> -n journal--<env>` — should show successful scan
   - `kubectl get imagepolicy <service>-stable -n journal--<env>` — should resolve to a tag
   - `kubectl get imageupdateautomation <service> -n journal--<env>` — should show `repository up-to-date`
5. Check pod events if a pod is not starting: `kubectl get events -n journal--<env> --field-selector involvedObject.name=<pod-name>`

## Boundaries

- Never modify files under `manifests/` that contain `# {"$imagepolicy":` comments — these are managed by Flux image automation
- Never hardcode environment-specific values in `kustomizations/` — use `${variable}` substitution
- Always deploy to `test` before `prod`
- Prefer not to create standalone Kubernetes resources outside the Kustomize structure
