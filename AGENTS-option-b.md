# AGENTS.md

Kubernetes GitOps deployment configuration for eLife's journal platform. All changes are applied via Flux CD reconciliation — commit to `main` and Flux applies the state to the cluster.

## Quick Reference

```bash
make reconcile                                      # Force Flux to sync now
make generate-reference TARGET=manifests/test/journal  # Render kustomize output
make compare-reference TARGET=manifests/test/journal   # Diff against saved reference
```

## Project Layout

```
kustomizations/<service>/     # Base Kubernetes manifests (shared across environments)
  kustomization.yaml          # Resources list, labels, configMapGenerators
  deployment.yaml             # Pod spec with ${variable} placeholders
  service.yaml                # ClusterIP service definition
  ingress.yaml                # Traefik ingress with ${hostname}
  config/                     # App config files (mounted as ConfigMaps)

manifests/test/<service>/     # Test environment — Flux Kustomization overlays
manifests/prod/<service>/     # Production environment — Flux Kustomization overlays
manifests/previews/           # PR preview environment (Kluctl-driven)
manifests/dashboards/         # Grafana dashboard ConfigMaps
```

Bases use `${env}`, `${hostname}`, `${replicas}` and other placeholders. Overlays provide the concrete values via `postBuild.substitute`.

## How Deployments Work

1. Developer pushes code to an application repo (e.g. `elifesciences/journal`)
2. CI builds a container image tagged like `master-<sha>-<timestamp>`
3. Flux `ImagePolicy` detects the new tag and `ImageUpdateAutomation` commits the updated `newTag` to this repo
4. Flux reconciles the `Kustomization`, applies the change to the cluster

Manual config changes follow the same flow: commit here, Flux applies.

## Task Guide

### Change a configuration value

Determine scope:
- **All environments**: edit files in `kustomizations/<service>/`
- **One environment**: edit the Flux Kustomization in `manifests/<env>/<service>/`, either via `postBuild.substitute` or a patch

Example — change replica count for journal in prod:
```yaml
# manifests/prod/journal/journal-app.yaml
spec:
  postBuild:
    substitute:
      replicas: "5"  # was "3"
```

### Tune resource requests

Edit `kustomizations/<service>/deployment.yaml`. Convention: set both `requests` and `limits` for memory, only `requests` for CPU.

```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
```

### Upgrade a version (OpenSearch, database engine, etc.)

Find the `postBuild.substitute` variable in the environment overlay and update it:

```yaml
# manifests/test/search/opensearch.yaml
spec:
  postBuild:
    substitute:
      opensearch_version: "3.3.1"  # was "3.3.0"
```

Always upgrade `test` first, verify, then upgrade `prod`.

### Add a new service from scratch

Use `kustomizations/jats-to-pdf/` as a minimal template:

1. **Create base** at `kustomizations/<new-service>/`:

   `kustomization.yaml`:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   namespace: journal
   resources:
     - deployment.yaml
     - service.yaml
     - ingress.yaml
   labels:
     - includeSelectors: true
       pairs:
         app.kubernetes.io/part-of: <new-service>
         app.kubernetes.io/instance: <new-service>-${env}
   ```

   `deployment.yaml` — standard pod spec with image placeholder and health probes.

   `service.yaml` — ClusterIP targeting the pod's port.

   `ingress.yaml`:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: <new-service>
     annotations:
       cert-manager.io/cluster-issuer: "${cert_manager_issuer}"
   spec:
     ingressClassName: traefik
     rules:
       - host: ${hostname}
         http:
           paths:
             - path: /
               pathType: ImplementationSpecific
               backend:
                 service:
                   name: <new-service>
                   port:
                     number: 80
     tls:
       - hosts:
           - ${hostname}
         secretName: ${hostname}-tls
   ```

2. **Create test overlay** at `manifests/test/<new-service>/`:

   A Flux Kustomization YAML:
   ```yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: <new-service>
     namespace: journal--test
   spec:
     interval: 1h
     retryInterval: 1m
     path: ./kustomizations/<new-service>
     prune: true
     sourceRef:
       kind: GitRepository
       name: journal-team-deployment
       namespace: flux-system
     targetNamespace: journal--test
     postBuild:
       substitute:
         env: test
         hostname: <new-service>.test.elifesciences.org
         replicas: "1"
     images:
       - name: ghcr.io/elifesciences/<new-service>
         newTag: <initial-tag>
   ```

3. **Add image automation** (in the same file or a separate YAML document):
   - `ImageRepository` pointing at `ghcr.io/elifesciences/<new-service>`
   - `ImagePolicy` with tag filter pattern (typically `^main-[a-fA-F0-9]+-(?P<ts>.*)` with numerical ascending order)
   - `ImageUpdateAutomation` with `update.path` set to `./manifests/test/<new-service>`

4. **Deploy and validate in test**, then create `manifests/prod/<new-service>/` with production values.

### Add an AWS resource

**SQS Queue** — follow `kustomizations/search/queue.yaml`:
```yaml
apiVersion: sqs.services.k8s.aws/v1alpha1
kind: Queue
metadata:
  name: <service>-queue
spec:
  queueName: elife-<service>-${env}
  tags:
    Project: journal
```

**S3 Bucket** — follow `kustomizations/iiif/bucket.yaml`:
```yaml
apiVersion: s3.services.k8s.aws/v1alpha1
kind: Bucket
metadata:
  name: <service>-cache-${env}
spec:
  name: elife-<service>-cache-${env}
```

**IAM Role (IRSA)** — follow `kustomizations/search/iam.yaml`. Create an `iam.services.k8s.aws/v1alpha1 Role` with an assume-role policy referencing `${aws_oidc_arn}` and the service account.

### Add secrets

Use External Secrets Operator:
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <service>-secret
spec:
  secretStoreRef:
    name: secret-store
    kind: ClusterSecretStore
  target:
    name: <service>-secret
  dataFrom:
    - extract:
        key: journal-team/<service>/${env}
```

Store the actual secret values at `journal-team/<service>/<env>` in AWS Secrets Manager (outside this repo).

### Set up autoscaling

**HTTP-based** (scale to zero) — follow `kustomizations/jats-to-pdf/`:
```yaml
kind: HTTPScaledObject
apiVersion: http.keda.sh/v1alpha1
metadata:
  name: <service>
spec:
  hosts:
    - "${hostname}"
  scaleTargetRef:
    name: <service>
    kind: Deployment
    service: <service>-web
    port: 8080
  replicas:
    min: 0
    max: 10
  scaledownPeriod: 300
  scalingMetric:
    concurrency:
      targetValue: 5
```

**Queue-based** — follow `kustomizations/search/`:
```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: <service>-queue-scaler
spec:
  scaleTargetRef:
    name: <service>-queue-watcher
  minReplicaCount: 1
  maxReplicaCount: 10
  triggers:
    - type: aws-sqs-queue
      metadata:
        queueURL: "${queue_url}"
        queueLength: "50"
        awsRegion: "${aws_region}"
```

### Add a Grafana dashboard

1. Create JSON dashboard file at `manifests/dashboards/<service>/dashboard.json`
2. Create `kustomization.yaml` in the same directory:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   namespace: monitoring
   configMapGenerator:
     - name: <service>-dashboard
       files:
         - dashboard.json
       options:
         labels:
           grafana_dashboard: "1"
   ```

### Migrate an ingress to Traefik

The established multi-step pattern:
1. Create a temporary Traefik ingress alongside the existing one (different hostname)
2. Verify the temporary ingress works
3. Switch DNS to point at the Traefik ingress
4. Update the original ingress to use `ingressClassName: traefik`
5. Point DNS back to the original ingress
6. Remove the temporary ingress

### Add a database (RDS)

Follow `manifests/test/digests/` — create a Flux Kustomization referencing `./kustomizations/utils/rds-dbinstance` with substitute variables for `instance_name`, `instance_storage`, `instance_class`, `engine`, and `engine_version`. Add a second Kustomization for the database secret that `dependsOn` the database resource.

### Add API Gateway routes

Add `HTTPRoute` resources in `kustomizations/api-gateway/`:
```yaml
kind: HTTPRoute
apiVersion: gateway.networking.k8s.io/v1
metadata:
  name: <service>
spec:
  parentRefs:
    - kind: Gateway
      name: api-gateway
  rules:
    - backendRefs:
        - name: ${service_name}
          kind: Service
          port: ${service_port}
      matches:
        - path:
            type: PathPrefix
            value: /<path>
```

## Conventions

- **Test before prod**: always deploy changes to `test` first
- **Namespaces**: `journal--test`, `journal--prod`, `journal--previews`
- **Hostnames**: `<service>.test.elifesciences.org` (test), `<service>.elifesciences.org` (prod)
- **Labels**: always include `app.kubernetes.io/part-of`, `app.kubernetes.io/name`, `app.kubernetes.io/instance`
- **Logging**: Fluent Bit sidecar reading from app log files, outputting to stdout
- **TLS**: cert-manager with `${cert_manager_issuer}` annotation
- **Variable substitution**: never hardcode environment values in bases — use `${var}` and substitute in overlays

## Do Not

- Edit lines containing `# {"$imagepolicy":` — Flux image automation manages these
- Hardcode hostnames, replica counts, or environment names in base kustomizations
- Skip the test environment when making changes
- Create Kubernetes resources outside the Kustomize/Flux structure
- Store secrets in this repository — use External Secrets Operator
