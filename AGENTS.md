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

# Generate rendered Kustomize output for a target
make generate-reference TARGET=manifests/test/journal

# Compare current vs reference output
make compare-reference TARGET=manifests/test/journal
```

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

Follow the pattern of an existing simple service like `jats-to-pdf`:

1. Create `kustomizations/<service>/` with at minimum:
   - `kustomization.yaml` — list resources, add labels, define configMapGenerators
   - `deployment.yaml` — pod spec with `${variable}` placeholders
   - `service.yaml` — ClusterIP service
   - `ingress.yaml` — Traefik ingress with `${hostname}` and TLS

2. Create environment overlays in `manifests/test/<service>/` and `manifests/prod/<service>/`:
   - A Flux `Kustomization` resource referencing `./kustomizations/<service>`
   - `postBuild.substitute` with `env`, `hostname`, `replicas`, and any service-specific vars
   - An `images` block with the initial image tag
   - `ImagePolicy`, `ImageRepository`, and `ImageUpdateAutomation` for automated deploys

3. Deploy to `test` first, validate, then create `prod` overlay.

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
- **Logging**: use Fluent Bit sidecar containers for structured log forwarding
- **Hostnames**: test uses `<service>.test.elifesciences.org`, prod uses `<service>.elifesciences.org`
- **TLS**: always configure via cert-manager annotation `cert-manager.io/cluster-issuer: "${cert_manager_issuer}"`
- **Dependencies**: use `dependsOn` in Flux Kustomizations to ensure proper ordering, and `substituteFrom` to pass ConfigMap/Secret values between components

## Boundaries

- Never modify files under `manifests/` that contain `# {"$imagepolicy":` comments — these are managed by Flux image automation
- Never hardcode environment-specific values in `kustomizations/` — use `${variable}` substitution
- Always deploy to `test` before `prod`
- Do not create standalone Kubernetes resources outside the Kustomize structure
