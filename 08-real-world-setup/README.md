# 08 - Real-World Production Setup

This scenario mirrors a **real production environment** using:

- **Azure Pipelines** — multi-stage CI/CD (dev → UAT → prod) with approval gates
- **Helm charts** — single chart with per-environment values files
- **Argo CD manual sync** — no auto-sync for UAT/prod (change management compliance)
- **AVP-Helm plugin** — `helm template` → AVP resolves Vault placeholders
- **Vault per-environment paths** — isolated secrets per environment
- **Prometheus + Grafana** — monitoring for all components

## Architecture

```
Developer ──PR merge──► Azure Pipelines ──build+push──► Harbor (scan)
                             │
                ┌────────────┼────────────────┐
                ▼            ▼                 ▼
           ┌────────┐  ┌─────────┐      ┌──────────┐
           │  DEV   │  │   UAT   │      │   PROD   │
           │ (auto) │  │(approve)│      │ (approve)│
           └───┬────┘  └────┬────┘      └────┬─────┘
               │             │                │
          yq updates    yq updates       yq updates
          values/       values/          values/
          dev.yaml      uat.yaml         prod.yaml
               │             │                │
               ▼             ▼                ▼
           ┌──────────────────────────────────────┐
           │  Git Repo                             │
           │  helm-chart/                          │
           │    Chart.yaml                         │
           │    templates/  (shared across envs)   │
           │    values/                            │
           │      dev.yaml  uat.yaml  prod.yaml    │
           └────────────────┬─────────────────────┘
                            │ watches
                            ▼
           ┌──────────────────────────────────────┐
           │  Argo CD                              │
           │                                       │
           │  myapp-dev:  helm + values/dev.yaml   │
           │    → auto-sync                        │
           │                                       │
           │  myapp-uat:  helm + values/uat.yaml   │
           │    → manual sync (post-approval)      │
           │                                       │
           │  myapp-prod: helm + values/prod.yaml  │
           │    → manual sync (change window)      │
           │              │                        │
           │         AVP-Helm plugin               │
           │         resolves <path:...#key>        │
           │              │                        │
           └──────────────┼────────────────────────┘
                          │ fetch secrets
                          ▼
                   ┌────────────┐
                   │   Vault    │
                   │ secret/dev │
                   │ secret/uat │
                   │ secret/prod│
                   └────────────┘
```

## How Helm + AVP Works Together

The AVP-Helm plugin runs a two-step process:

```
Step 1: helm template
  Renders Chart.yaml + templates/ + values/prod.yaml
  Output: standard YAML with AVP placeholders still present
    DB_PASSWORD: <path:secret/data/prod/myapp/config#db_password>

Step 2: argocd-vault-plugin generate
  Reads the rendered YAML
  Replaces <path:...#key> with real Vault values
  Output: final YAML with real secrets
    DB_PASSWORD: actual-production-password
```

The Helm `values.yaml` controls which Vault path to use per environment:

```yaml
# values/dev.yaml
vaultPathPrefix: "secret/data/dev/myapp"

# values/prod.yaml
vaultPathPrefix: "secret/data/prod/myapp"
```

The secret template uses this variable:

```yaml
# templates/secret.yaml
DB_PASSWORD: <path:{{ .Values.vaultPathPrefix }}/config#db_password>
```

## How Azure Pipeline Updates the Image Tag

The pipeline uses `yq` to update the `image.tag` field in the per-environment values file:

```bash
# For dev (automatic)
yq e '.image.tag = "42"' -i helm-chart/values/dev.yaml

# For prod (after change manager approves the pipeline stage)
yq e '.image.tag = "42"' -i helm-chart/values/prod.yaml
```

Then commits and pushes. Argo CD detects the change and:
- **Dev**: auto-syncs immediately
- **UAT/Prod**: shows "OutOfSync" — team triggers manual sync

## Files in This Directory

| Directory | Purpose |
|-----------|---------|
| `helm-chart/` | Complete Helm chart (Chart.yaml, templates/, values/) |
| `helm-chart/values/dev.yaml` | Dev overrides: 1 replica, small resources, dev Vault path |
| `helm-chart/values/uat.yaml` | UAT overrides: 2 replicas, moderate resources, UAT Vault path |
| `helm-chart/values/prod.yaml` | Prod overrides: 3 replicas, HPA, large resources, prod Vault path |
| `azure-pipelines/azure-pipelines-helm.yaml` | Azure Pipeline using yq to update Helm values |
| `argocd-multi-env/argocd-apps-helm.yaml` | Three Argo CD Applications using Helm + AVP |
| `vault-multi-env/` | Per-environment Vault policies and setup script |
| `monitoring/` | Prometheus ServiceMonitors, alert rules, Grafana dashboard |
