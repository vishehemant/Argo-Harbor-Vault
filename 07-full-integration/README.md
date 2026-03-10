# 07 - Full Integration: Harbor + Vault + Argo CD

## The Complete Picture

This scenario ties everything together into a **production-grade CI/CD pipeline**:

1. **Developer** pushes code to GitHub
2. **GitHub Actions** CI builds a Docker image and pushes it to **Harbor**
3. CI updates the image tag in the Git manifests
4. **Argo CD** detects the Git change
5. Argo CD (with AVP) resolves secret placeholders from **Vault**
6. Argo CD deploys to the Kubernetes cluster, pulling the image from **Harbor** using credentials stored in **Vault**

```
┌──────────┐   push    ┌──────────┐   build &    ┌──────────┐
│Developer │──────────►│  GitHub   │──push image─►│  Harbor   │
└──────────┘           │  Actions  │              │ Registry  │
                       └─────┬─────┘              └──────────┘
                             │ update                    │
                             │ image tag                 │
                             ▼                           │
                       ┌──────────┐                      │
                       │Git Repo  │                      │
                       │(manifests)│                     │
                       └─────┬─────┘                     │
                             │ watches                   │
                             ▼                           │
                       ┌──────────┐   fetch     ┌──────┐│
                       │ Argo CD  │──secrets──►│Vault ││
                       │  + AVP   │             └──────┘│
                       └─────┬─────┘                     │
                             │ deploy                    │
                             ▼                           │
                       ┌──────────┐   pull image         │
                       │Kubernetes│◄─────────────────────┘
                       │ Cluster  │  (creds from Vault
                       └──────────┘   via ESO)
```

## Prerequisites

Before running this scenario, complete:
- [01 - Harbor Basics](../01-harbor-basics/) — Harbor installed with a project and robot account
- [02 - Vault Basics](../02-vault-basics/) — Vault installed, unsealed, with K8s auth configured
- [03 - Argo CD Basics](../03-argocd-basics/) — Argo CD installed
- Secrets stored in Vault (run `../02-vault-basics/scripts/store-secrets.sh`)

## Step-by-Step Setup

### Step 1: Store All Secrets in Vault

```bash
# Harbor credentials
kubectl exec -n vault vault-0 -- vault kv put secret/harbor/creds \
  url="harbor.example.com" \
  username="robot\$ci-pipeline" \
  password="<harbor-robot-secret>" \
  email="ci@example.com"

# Application database config
kubectl exec -n vault vault-0 -- vault kv put secret/production/myapp/config \
  db_host="postgres.production.svc.cluster.local" \
  db_port="5432" \
  db_name="myapp_production" \
  db_user="myapp_prod" \
  db_password="production-db-password-rotated-2024"

# Application API keys
kubectl exec -n vault vault-0 -- vault kv put secret/production/myapp/api-keys \
  stripe_key="sk_live_production_key" \
  sendgrid_key="SG.production_key" \
  jwt_secret="super-secret-jwt-signing-key"
```

Or use the script: `./vault-config/store-all-secrets.sh`

### Step 2: Create the Vault Policy

```bash
kubectl cp vault-config/policies/full-app-policy.hcl vault/vault-0:/tmp/full-app-policy.hcl
kubectl exec -n vault vault-0 -- vault policy write full-app /tmp/full-app-policy.hcl
```

### Step 3: Configure Vault Roles

```bash
# Role for the ESO controller (creates image pull secrets)
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/eso-harbor \
  bound_service_account_names=vault-auth-sa \
  bound_service_account_namespaces=production \
  policies=full-app \
  ttl=1h

# Role for Argo CD AVP (resolves secret placeholders)
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/argocd \
  bound_service_account_names=argocd-repo-server \
  bound_service_account_namespaces=argocd \
  policies=full-app \
  ttl=1h
```

### Step 4: Deploy the Application

```bash
# Apply the Argo CD Application
kubectl apply -f argocd-application.yaml

# Watch it sync
argocd app get full-integration-app
kubectl get pods -n production -w
```

### Step 5: Set Up CI Pipeline

Add the GitHub Actions workflow to your repository:
- See [ci-pipeline/github-actions-workflow.yaml](./ci-pipeline/github-actions-workflow.yaml)

The workflow:
1. Builds the Docker image
2. Pushes to Harbor
3. Updates the image tag in the Kustomize overlay
4. Commits and pushes the change
5. Argo CD detects the change and deploys

## What Happens at Each Stage

### CI Pipeline (GitHub Actions)

```
git push ──► GitHub Actions ──► docker build ──► docker push (Harbor)
                                                      │
                                              update kustomization.yaml
                                              with new image tag
                                                      │
                                                  git commit & push
```

### Argo CD Sync

```
Argo CD detects new commit
    │
    ├──► Repo Server clones the repo
    │
    ├──► AVP Plugin resolves <path:secret/...#key> placeholders
    │    by reading from Vault (using K8s auth)
    │
    ├──► ESO has already created harbor-pull-secret
    │    from Vault's secret/harbor/creds
    │
    └──► kubectl apply (Deployment, Service, Ingress, etc.)
              │
              ├──► kubelet pulls image from Harbor
              │    using harbor-pull-secret
              │
              └──► Pod starts with real secrets
                   injected as env vars
```

## Key Concepts Reinforced

| Concept | Where It Appears |
|---------|-----------------|
| **Harbor robot account** | CI pipeline uses it to push images |
| **Harbor image pull secret** | ESO creates it from Vault → used by K8s to pull images |
| **Vault KV v2** | Stores all credentials: Harbor creds, DB passwords, API keys |
| **Vault Kubernetes auth** | ESO and AVP both authenticate using K8s ServiceAccount tokens |
| **Vault policies** | Control which roles can access which secret paths |
| **Argo CD Application** | Watches Git, orchestrates the deployment |
| **AVP placeholders** | `<path:...#key>` in manifests, resolved to real values at sync |
| **ESO ExternalSecret** | Syncs Vault secrets → K8s Secrets (for image pull creds) |
| **Kustomize** | Organizes manifests; CI updates image tag via kustomization.yaml |
| **GitHub Actions** | Automates build → push → update manifests |

## Files in This Directory

| File | Purpose |
|------|---------|
| `argocd-application.yaml` | Argo CD Application for the full stack |
| `app-manifests/namespace.yaml` | Namespace definition |
| `app-manifests/deployment.yaml` | Deployment with Harbor image and Vault-injected secrets |
| `app-manifests/service.yaml` | Service exposing the app |
| `app-manifests/ingress.yaml` | Ingress for external access |
| `app-manifests/secret.yaml` | Secret with AVP placeholders |
| `app-manifests/external-secret.yaml` | ESO ExternalSecret for Harbor credentials |
| `app-manifests/kustomization.yaml` | Kustomize configuration |
| `vault-config/policies/full-app-policy.hcl` | Vault policy for this scenario |
| `vault-config/store-all-secrets.sh` | Script to populate Vault with all required secrets |
| `ci-pipeline/github-actions-workflow.yaml` | Complete GitHub Actions CI/CD workflow |
