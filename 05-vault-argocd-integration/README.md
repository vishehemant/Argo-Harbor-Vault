# 05 - Vault + Argo CD Integration

## The Problem

Argo CD reads manifests from Git and applies them to the cluster. But **secrets should NOT be stored in Git** (even encrypted, it's risky). So how do we handle secrets in a GitOps workflow?

## The Solution: Argo Vault Plugin (AVP)

The **Argo Vault Plugin** (AVP) is a custom plugin for Argo CD that replaces placeholder tokens in your manifests with real values from Vault at sync time.

```
┌──────────┐                ┌──────────────────┐              ┌──────────┐
│  Git     │   manifests    │   Argo CD         │   deploy     │Kubernetes│
│  Repo    │───────────────►│   Repo Server     │─────────────►│ Cluster  │
│          │   with         │     +             │   with real  │          │
│ (has     │   placeholders │   AVP Plugin      │   secrets    │          │
│  <tokens>│                │     │             │              │          │
│  not     │                │     │ fetches     │              │          │
│  secrets)│                │     ▼             │              │          │
│          │                │   ┌──────────┐    │              │          │
│          │                │   │  Vault   │    │              │          │
│          │                │   │  Server  │    │              │          │
│          │                │   └──────────┘    │              │          │
└──────────┘                └──────────────────┘              └──────────┘
```

### How It Works

1. You write manifests with **placeholders** like `<path:secret/data/myapp/config#db_password>`
2. Argo CD's repo server passes manifests through AVP
3. AVP authenticates with Vault (using Kubernetes auth)
4. AVP replaces placeholders with real values from Vault
5. The resolved manifests (with real secrets) are applied to the cluster
6. **Secrets never touch Git**

## Step 1: Install AVP as a ConfigManagement Plugin (CMP)

Starting with Argo CD 2.6+, custom plugins are installed as **sidecar containers** on the repo-server Pod.

### 1a. Create the Plugin ConfigMap

```bash
kubectl apply -f argocd-vault-plugin/cmp-plugin-configmap.yaml
```

This ConfigMap defines how AVP processes manifests. See [argocd-vault-plugin/cmp-plugin-configmap.yaml](./argocd-vault-plugin/cmp-plugin-configmap.yaml).

### 1b. Patch the Argo CD Repo Server

```bash
kubectl apply -f argocd-vault-plugin/argocd-repo-server-patch.yaml
```

This adds the AVP sidecar container to the repo-server. See [argocd-vault-plugin/argocd-repo-server-patch.yaml](./argocd-vault-plugin/argocd-repo-server-patch.yaml).

## Step 2: Configure AVP to Authenticate with Vault

AVP supports multiple auth methods. We use **Kubernetes auth** (recommended).

```bash
# Ensure the Vault Kubernetes auth role for Argo CD exists
# (This was done in 02-vault-basics/scripts/setup-kubernetes-auth.sh)
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/argocd \
  bound_service_account_names=argocd-repo-server \
  bound_service_account_namespaces=argocd \
  policies=argocd \
  ttl=1h
```

## Step 3: Store Secrets in Vault

```bash
# Store application secrets
kubectl exec -n vault vault-0 -- vault kv put secret/myapp/config \
  db_host="postgres.default.svc.cluster.local" \
  db_port="5432" \
  db_user="myapp" \
  db_password="super-secret-password" \
  api_key="sk-1234567890abcdef"
```

## Step 4: Create Manifests with AVP Placeholders

Instead of hardcoding secrets, use AVP's placeholder syntax:

```yaml
# The placeholder format:
#   <path:SECRET_PATH#KEY>
#
# Examples:
#   <path:secret/data/myapp/config#db_password>
#   <path:secret/data/myapp/config#db_host>
```

See the sample app manifests in [sample-app/](./sample-app/) — especially `secret.yaml` and `deployment.yaml`.

## Step 5: Create an Argo CD Application Using the AVP Plugin

```bash
kubectl apply -f argocd-application.yaml
```

The Application spec includes:
```yaml
source:
  plugin:
    name: argocd-vault-plugin
```

This tells Argo CD to process the manifests through AVP before applying them.

## Placeholder Syntax Reference

| Syntax | Description | Example |
|--------|-------------|---------|
| `<path:PATH#KEY>` | Basic secret reference | `<path:secret/data/myapp/config#db_password>` |
| `<path:PATH#KEY\|base64>` | Base64-encode the value | `<path:secret/data/myapp/config#db_password\|base64>` |
| `<path:PATH#KEY\|jsonPath {.field}>` | Extract a JSON field | `<path:secret/data/certs#tls\|jsonPath {.key}>` |
| `<path:PATH#KEY>` with version | Specific version | `<path:secret/data/myapp/config#db_password version=2>` |

## Complete Example Flow

```bash
# 1. Vault has the secret
vault kv get secret/myapp/config
# => db_password = "super-secret-password"

# 2. Git has the manifest with a placeholder
cat sample-app/secret.yaml
# => password: <path:secret/data/myapp/config#db_password>

# 3. AVP resolves it at sync time
# The actual Secret applied to the cluster contains:
# => password: super-secret-password

# 4. The Pod mounts this Secret and uses the real value
```

## Troubleshooting

```bash
# Check the AVP sidecar logs
kubectl logs -n argocd deploy/argocd-repo-server -c avp

# Verify the ServiceAccount can authenticate with Vault
kubectl exec -n argocd deploy/argocd-repo-server -c avp -- \
  cat /var/run/secrets/kubernetes.io/serviceaccount/token

# Test AVP directly
kubectl exec -n argocd deploy/argocd-repo-server -c avp -- \
  argocd-vault-plugin generate ./sample-app/
```

## Key Concepts

| Concept | What It Means |
|---------|---------------|
| **AVP (Argo Vault Plugin)** | Sidecar plugin that replaces secret placeholders in manifests |
| **CMP (ConfigManagementPlugin)** | Argo CD mechanism for adding custom manifest processing |
| **Placeholder** | `<path:...#key>` token in YAML that AVP replaces with the real secret |
| **Kubernetes Auth** | How AVP authenticates with Vault using the repo-server's ServiceAccount |

## Files in This Directory

| File | Purpose |
|------|---------|
| `argocd-vault-plugin/cmp-plugin-configmap.yaml` | ConfigMap defining the AVP plugin |
| `argocd-vault-plugin/argocd-repo-server-patch.yaml` | Patch to add AVP sidecar to repo-server |
| `sample-app/deployment.yaml` | Deployment referencing secrets from a K8s Secret |
| `sample-app/service.yaml` | Service for the sample app |
| `sample-app/secret.yaml` | Secret with AVP placeholders (resolved at sync time) |
| `argocd-application.yaml` | Application CRD configured to use the AVP plugin |
