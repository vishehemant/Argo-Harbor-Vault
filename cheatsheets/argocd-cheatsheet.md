# Argo CD Cheatsheet

## CLI Login & Setup

```bash
# Login
argocd login <server> --username admin --password <pass> --insecure

# Get password from K8s secret
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port-forward the UI
kubectl port-forward svc/argocd-server -n argocd 8443:443

# Update admin password
argocd account update-password
```

## Application Management

```bash
# Create an app (CLI)
argocd app create my-app \
  --repo https://github.com/org/repo.git \
  --path k8s/ \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# Create from YAML
kubectl apply -f application.yaml

# List apps
argocd app list

# Get app details
argocd app get my-app

# Sync (manual deploy)
argocd app sync my-app

# Sync specific resources
argocd app sync my-app --resource apps:Deployment:my-deploy

# Force sync (ignore hooks)
argocd app sync my-app --force

# Hard refresh (clear cache)
argocd app get my-app --hard-refresh

# Rollback to previous sync
argocd app rollback my-app <history-id>

# View sync history
argocd app history my-app

# Delete app (keep resources)
argocd app delete my-app --cascade=false

# Delete app (remove resources too)
argocd app delete my-app
```

## Application YAML Template

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/org/repo.git
    targetRevision: main
    path: manifests/
    # For Helm:
    # helm:
    #   valueFiles:
    #     - values-prod.yaml
    # For Kustomize:
    # kustomize:
    #   images:
    #     - name=tag
    # For plugin (AVP):
    # plugin:
    #   name: argocd-vault-plugin
  destination:
    server: https://kubernetes.default.svc
    namespace: my-namespace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

## Repository Management

```bash
# Add a Git repo
argocd repo add https://github.com/org/repo.git \
  --username user --password token

# Add an SSH repo
argocd repo add git@github.com:org/repo.git \
  --ssh-private-key-path ~/.ssh/id_rsa

# Add a Helm repo
argocd repo add https://charts.example.com \
  --type helm --name my-charts

# Add Harbor OCI registry
argocd repo add harbor.example.com \
  --type helm --enable-oci \
  --username 'robot$ci' --password secret

# List repos
argocd repo list

# Remove
argocd repo rm https://github.com/org/repo.git
```

## Cluster Management

```bash
# Add a cluster
argocd cluster add <context-name>

# List clusters
argocd cluster list

# Remove
argocd cluster rm https://cluster-api-url
```

## Project Management

```bash
# Create a project
argocd proj create my-project \
  --src https://github.com/org/* \
  --dest https://kubernetes.default.svc,my-namespace

# Add allowed source repo
argocd proj add-source my-project https://github.com/org/repo2.git

# Add allowed destination
argocd proj add-destination my-project https://kubernetes.default.svc staging

# List projects
argocd proj list
```

## kubectl Equivalents

```bash
# List apps
kubectl get applications -n argocd

# Describe an app
kubectl describe application my-app -n argocd

# Get app sync status
kubectl get app my-app -n argocd -o jsonpath='{.status.sync.status}'

# Get app health
kubectl get app my-app -n argocd -o jsonpath='{.status.health.status}'

# Watch all apps
kubectl get app -n argocd -w
```

## Helm Installation

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd -n argocd --create-namespace -f values.yaml

# Upgrade
helm upgrade argocd argo/argo-cd -n argocd -f values.yaml

# Uninstall
helm uninstall argocd -n argocd
```

## Sync Statuses

| Status | Meaning |
|--------|---------|
| `Synced` | Cluster matches Git |
| `OutOfSync` | Cluster differs from Git |
| `Unknown` | Cannot determine status |

## Health Statuses

| Status | Meaning |
|--------|---------|
| `Healthy` | All resources are healthy |
| `Progressing` | Rollout in progress |
| `Degraded` | Errors detected |
| `Suspended` | Paused (e.g., HPA scaled to 0) |
| `Missing` | Resource doesn't exist yet |
| `Unknown` | Health cannot be determined |

## Key Concepts

| Term | Meaning |
|------|---------|
| Application | CRD defining what/where to deploy |
| Sync | Apply desired state from Git to cluster |
| Prune | Delete resources removed from Git |
| Self-Heal | Revert manual cluster changes |
| Project | RBAC grouping for Applications |
| Hook | Pre/post sync operations (Jobs, etc.) |
| Wave | Ordering mechanism for sync operations |
| Refresh | Re-read manifests from Git |
| Hard Refresh | Clear cache and re-read |
