# 03 - Argo CD Basics

## What is Argo CD?

Argo CD is a **declarative, GitOps continuous delivery tool** for Kubernetes. It monitors a Git repository containing Kubernetes manifests and ensures the live cluster state matches the desired state defined in Git.

### The GitOps Principle
> "Git is the single source of truth for what should be running in the cluster."

Instead of running `kubectl apply` manually, you push changes to Git and Argo CD automatically syncs them to the cluster.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                        Argo CD                            │
├──────────────────────────────────────────────────────────┤
│                                                           │
│  ┌──────────────┐    ┌──────────────┐    ┌────────────┐ │
│  │  API Server   │    │  Repo Server  │    │Application │ │
│  │              │    │              │    │ Controller  │ │
│  │ - UI / CLI   │    │ - Git clone  │    │            │ │
│  │ - Auth       │    │ - Render     │    │ - Watch    │ │
│  │ - RBAC       │    │   manifests  │    │ - Compare  │ │
│  │              │    │ - Helm/Kust  │    │ - Sync     │ │
│  └──────┬───────┘    └──────┬───────┘    └─────┬──────┘ │
│         │                   │                   │        │
│         └───────────────────┼───────────────────┘        │
│                             │                             │
│                    ┌────────▼────────┐                    │
│                    │   Redis Cache    │                    │
│                    └─────────────────┘                    │
└──────────────────────────────────────────────────────────┘
         │                   │                    │
         ▼                   ▼                    ▼
   ┌──────────┐      ┌──────────────┐    ┌──────────────┐
   │   Users   │      │ Git Repos    │    │  Kubernetes   │
   │ (UI/CLI)  │      │ (GitHub etc) │    │  Cluster(s)   │
   └──────────┘      └──────────────┘    └──────────────┘
```

### Key Components

| Component | Role |
|-----------|------|
| **API Server** | Serves the UI and CLI, handles authentication |
| **Repo Server** | Clones Git repos, renders manifests (Helm, Kustomize, plain YAML) |
| **Application Controller** | Monitors apps, compares desired vs. live state, performs syncs |

## Step 1: Install Argo CD via Helm

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl create namespace argocd

helm install argocd argo/argo-cd \
  --namespace argocd \
  -f argocd-helm-values.yaml
```

## Step 2: Access the Argo CD UI

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo  # newline

# Port-forward to access the UI
kubectl port-forward svc/argocd-server -n argocd 8443:443

# Open https://localhost:8443
# Login: admin / <password from above>
```

## Step 3: Install the Argo CD CLI

```bash
# macOS
brew install argocd

# Linux
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/

# Login
argocd login localhost:8443 --username admin --password <password> --insecure
```

## Step 4: Understanding the Application CRD

The `Application` custom resource is the core of Argo CD. It defines:
- **Where to get manifests** (Git repo, path, branch)
- **Where to deploy them** (which cluster, which namespace)
- **How to sync** (automatic vs. manual, prune, self-heal)

See [argocd-application.yaml](./argocd-application.yaml) for a fully commented example.

### Application Lifecycle

```
┌─────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│  Create  │────►│  OutOf   │────►│ Syncing  │────►│ Synced   │
│  App     │     │  Sync    │     │          │     │ Healthy  │
└─────────┘     └──────────┘     └──────────┘     └──────────┘
                     ▲                                   │
                     │         Git push / drift          │
                     └───────────────────────────────────┘
```

**Sync Statuses:**
- `Synced` — Live state matches desired state in Git
- `OutOfSync` — Live state differs from Git (someone changed something, or Git was updated)

**Health Statuses:**
- `Healthy` — All resources are healthy (Deployments rolled out, Pods running)
- `Progressing` — Rollout in progress
- `Degraded` — Something is wrong (CrashLoopBackOff, insufficient resources)

## Step 5: Deploy a Sample Application

```bash
# Apply the sample app manifests to Git (they're already in this repo)
# Argo CD will read them from the sample-app/ directory

# Create the Argo CD Application
kubectl apply -f argocd-application.yaml

# Watch the sync status
argocd app get sample-app

# Or via kubectl
kubectl get application sample-app -n argocd -o yaml
```

### Sync Policies Explained

```yaml
syncPolicy:
  automated:           # Enable auto-sync (sync when Git changes)
    prune: true        # Delete resources removed from Git
    selfHeal: true     # Revert manual changes made to the cluster
  syncOptions:
    - CreateNamespace=true   # Create namespace if it doesn't exist
    - PruneLast=true         # Delete old resources after new ones are healthy
```

| Policy | Behavior |
|--------|----------|
| `automated` | Sync automatically when Git changes (no manual trigger needed) |
| `prune: true` | If you delete a YAML file from Git, delete the resource from the cluster |
| `selfHeal: true` | If someone runs `kubectl edit` directly, revert the change |
| Manual (no `automated`) | Only sync when you click "Sync" in UI or run `argocd app sync` |

## Step 6: Multi-Source Applications

Argo CD can combine manifests from multiple sources (e.g., a Helm chart + value overrides from a different repo).

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: multi-source-app
  namespace: argocd
spec:
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  project: default
  sources:
    - repoURL: https://charts.bitnami.com/bitnami
      chart: nginx
      targetRevision: 15.4.4
      helm:
        valueFiles:
          - $values/envs/production/nginx-values.yaml
    - repoURL: https://github.com/your-org/config-repo.git
      targetRevision: main
      ref: values
```

## Key Concepts Recap

| Concept | What It Means |
|---------|---------------|
| **Application** | CRD that defines what to deploy, where from, and where to |
| **Sync** | The act of applying the desired state (from Git) to the cluster |
| **Prune** | Delete resources from the cluster that no longer exist in Git |
| **Self-Heal** | Automatically revert manual changes to match Git |
| **Project** | Grouping mechanism with RBAC — restricts which repos, clusters, and namespaces an App can use |
| **Repo Server** | Fetches and renders manifests from Git (understands Helm, Kustomize, plain YAML) |
| **Health Check** | Built-in health assessment for K8s resources (Deployment, StatefulSet, etc.) |

## Files in This Directory

| File | Purpose |
|------|---------|
| `argocd-helm-values.yaml` | Helm chart values for Argo CD installation |
| `argocd-application.yaml` | Sample Application CRD (fully commented) |
| `sample-app/deployment.yaml` | Sample app Kubernetes Deployment |
| `sample-app/service.yaml` | Sample app Kubernetes Service |
| `sample-app/kustomization.yaml` | Kustomize file for the sample app |
