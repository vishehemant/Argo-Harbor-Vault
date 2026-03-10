# 08 - Real-World Production Setup

This scenario mirrors a **real production environment** with:

- **Azure Pipelines** — multi-stage CI/CD (dev → UAT → prod) with approval gates
- **Kustomize overlays** — base + per-environment patches
- **Argo CD manual sync** — no auto-sync for UAT/prod (change management compliance)
- **Vault per-environment paths** — isolated secrets per environment
- **Prometheus + Grafana** — monitoring for all components

```
Developer ──PR merge──► Azure Pipelines
                             │
                ┌────────────┼────────────────┐
                ▼            ▼                 ▼
           ┌────────┐  ┌─────────┐      ┌──────────┐
           │  DEV   │  │   UAT   │      │   PROD   │
           │ (auto) │  │(approve)│      │ (approve)│
           └───┬────┘  └────┬────┘      └────┬─────┘
               │             │                │
               ▼             ▼                ▼
           Git overlay   Git overlay     Git overlay
           overlays/dev  overlays/uat    overlays/prod
               │             │                │
               ▼             ▼                ▼
           Argo CD       Argo CD          Argo CD
           (auto-sync)   (manual sync)    (manual sync)
               │             │                │
               ▼             ▼                ▼
           Dev cluster   UAT cluster     Prod cluster
```

## Files in This Directory

| Directory | Purpose |
|-----------|---------|
| `azure-pipelines/` | Multi-stage Azure Pipeline with approval gates |
| `argocd-multi-env/` | Kustomize base + overlays + per-env Argo CD Applications |
| `vault-multi-env/` | Per-environment Vault policies and roles |
| `monitoring/` | Prometheus ServiceMonitors, Grafana dashboards, alert rules |
