# 02 - Vault Basics

## What is HashiCorp Vault?

Vault is a tool for **securely storing and accessing secrets**. A "secret" is anything you want to tightly control access to — API keys, passwords, certificates, database credentials, etc.

### Why Not Just Use Kubernetes Secrets?

| Feature | K8s Secrets | Vault |
|---------|------------|-------|
| Encryption at rest | Base64 only (not encrypted by default) | AES-256-GCM encrypted |
| Access control | RBAC on the Secret object | Fine-grained policies per path |
| Audit logging | Kubernetes audit logs | Detailed audit log per secret access |
| Dynamic secrets | No | Yes — generate on-the-fly DB creds, AWS keys |
| Secret rotation | Manual | Automatic with leases and TTLs |
| Secret versioning | No | Yes — KV v2 supports versions |

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                    HashiCorp Vault                     │
├──────────────────────────────────────────────────────┤
│                                                       │
│  ┌──────────────────────────────────────────────┐    │
│  │              API / CLI Interface               │    │
│  └──────────────┬───────────────────────────────┘    │
│                  │                                     │
│  ┌───────────┐  │  ┌──────────────┐ ┌────────────┐  │
│  │   Auth     │──│──│   Secrets    │ │   Audit    │  │
│  │  Methods   │  │  │   Engines   │ │   Devices  │  │
│  │            │  │  │             │ │            │  │
│  │ - Token    │  │  │ - KV v2     │ │ - File     │  │
│  │ - K8s     │  │  │ - Database  │ │ - Syslog   │  │
│  │ - AppRole  │  │  │ - AWS      │ │ - Socket   │  │
│  │ - LDAP    │  │  │ - PKI      │ │            │  │
│  └───────────┘  │  └──────────────┘ └────────────┘  │
│                  │                                     │
│  ┌──────────────┴───────────────────────────────┐    │
│  │           Barrier (Encryption Layer)           │    │
│  └──────────────────────────────────────────────┘    │
│                                                       │
│  ┌──────────────────────────────────────────────┐    │
│  │        Storage Backend (Raft / Consul)         │    │
│  └──────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

### Key Concepts

- **Seal/Unseal** — Vault starts in a "sealed" state. It must be unsealed with key shares before it can serve requests.
- **Auth Method** — How clients prove their identity (tokens, Kubernetes ServiceAccount, AppRole, etc.)
- **Secrets Engine** — A backend that stores or generates secrets (KV store, database, PKI, etc.)
- **Policy** — Defines what paths a token can access and what operations it can perform
- **Lease** — A time-limited grant. When the lease expires, the secret is revoked.

## Step 1: Install Vault via Helm

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

kubectl create namespace vault

helm install vault hashicorp/vault \
  --namespace vault \
  -f vault-helm-values.yaml
```

## Step 2: Initialize and Unseal Vault

```bash
# Initialize Vault (only done ONCE per cluster)
# This generates the unseal keys and root token
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > vault-init.json

# CRITICAL: Save vault-init.json securely!
# It contains the unseal keys and root token.

# Unseal Vault (need 3 of 5 keys)
UNSEAL_KEY_1=$(jq -r '.unseal_keys_b64[0]' vault-init.json)
UNSEAL_KEY_2=$(jq -r '.unseal_keys_b64[1]' vault-init.json)
UNSEAL_KEY_3=$(jq -r '.unseal_keys_b64[2]' vault-init.json)

kubectl exec -n vault vault-0 -- vault operator unseal "$UNSEAL_KEY_1"
kubectl exec -n vault vault-0 -- vault operator unseal "$UNSEAL_KEY_2"
kubectl exec -n vault vault-0 -- vault operator unseal "$UNSEAL_KEY_3"

# Verify it's unsealed
kubectl exec -n vault vault-0 -- vault status
```

Or use the script: `./scripts/init-and-unseal.sh`

## Step 3: Enable the KV Secrets Engine

The KV (Key-Value) secrets engine stores arbitrary key-value pairs. Version 2 supports versioning.

```bash
ROOT_TOKEN=$(jq -r '.root_token' vault-init.json)

# Login with root token
kubectl exec -n vault vault-0 -- vault login "$ROOT_TOKEN"

# Enable KV v2 at the path "secret/"
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2

# Store a secret
kubectl exec -n vault vault-0 -- vault kv put secret/myapp/config \
  db_host="postgres.default.svc.cluster.local" \
  db_port="5432" \
  db_user="myapp" \
  db_password="super-secret-password" \
  api_key="sk-1234567890abcdef"

# Read it back
kubectl exec -n vault vault-0 -- vault kv get secret/myapp/config

# Get a specific field
kubectl exec -n vault vault-0 -- vault kv get -field=db_password secret/myapp/config
```

## Step 4: Create Policies

Policies define **who can access what**. They use HCL (HashiCorp Configuration Language) or JSON.

```bash
# Copy policy file into the Vault pod
kubectl cp policies/app-read-policy.hcl vault/vault-0:/tmp/app-read-policy.hcl

# Apply the policy
kubectl exec -n vault vault-0 -- vault policy write app-read /tmp/app-read-policy.hcl

# List all policies
kubectl exec -n vault vault-0 -- vault policy list

# Read a policy
kubectl exec -n vault vault-0 -- vault policy read app-read
```

See [policies/](./policies/) for example policy files.

## Step 5: Enable Kubernetes Auth

This is the key integration point — it allows Kubernetes Pods to authenticate with Vault using their ServiceAccount tokens.

```bash
# Enable the Kubernetes auth method
kubectl exec -n vault vault-0 -- vault auth enable kubernetes

# Configure it to talk to the Kubernetes API
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local:443"

# Create a role that maps a Kubernetes ServiceAccount to a Vault policy
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/myapp \
  bound_service_account_names=myapp-sa \
  bound_service_account_namespaces=default \
  policies=app-read \
  ttl=1h
```

### How Kubernetes Auth Works

```
┌──────────────┐     1. Pod starts with     ┌──────────────┐
│  Kubernetes   │     ServiceAccount token   │    Vault      │
│  Pod          │ ─────────────────────────► │    Server     │
│               │     2. Vault validates     │               │
│  (myapp-sa)   │     token with K8s API     │               │
│               │ ◄───────────────────────── │               │
│               │     3. Returns Vault       │               │
│               │     token with policy      │               │
│               │                            │               │
│               │     4. Pod reads secrets   │               │
│               │     using Vault token      │               │
└──────────────┘                            └──────────────┘
```

Or use the script: `./scripts/setup-kubernetes-auth.sh`

## Step 6: Test It — Read Secrets from a Pod

```bash
# Create the ServiceAccount
kubectl create serviceaccount myapp-sa

# Run a test pod that uses the ServiceAccount
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: vault-test
spec:
  serviceAccountName: myapp-sa
  containers:
    - name: test
      image: vault:1.15.4
      command: ["sh", "-c", "sleep 3600"]
      env:
        - name: VAULT_ADDR
          value: "http://vault.vault.svc.cluster.local:8200"
EOF

# Exec into the pod and authenticate
kubectl exec -it vault-test -- sh

# Inside the pod:
# 1. Read the ServiceAccount JWT
JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# 2. Authenticate with Vault
vault write auth/kubernetes/login role=myapp jwt=$JWT

# 3. Use the returned token
vault login <token-from-step-2>

# 4. Read secrets
vault kv get secret/myapp/config
```

## Key Concepts Recap

| Concept | What It Means |
|---------|---------------|
| **Seal/Unseal** | Vault must be unsealed (decrypted) before it can serve requests |
| **Root Token** | All-powerful initial token — use sparingly, create scoped tokens instead |
| **KV v2 Engine** | Stores key-value pairs with versioning at a specified path |
| **Policy** | HCL rules defining what paths and operations a token can access |
| **Kubernetes Auth** | Lets K8s Pods authenticate with Vault via their ServiceAccount token |
| **Role** | Maps a Kubernetes ServiceAccount to a set of Vault policies |

## Files in This Directory

| File | Purpose |
|------|---------|
| `vault-helm-values.yaml` | Helm chart values for Vault installation |
| `policies/app-read-policy.hcl` | Policy granting read access to app secrets |
| `policies/argocd-policy.hcl` | Policy for Argo CD to read secrets (used in scenario 05) |
| `scripts/init-and-unseal.sh` | Initialize and unseal Vault |
| `scripts/setup-kubernetes-auth.sh` | Configure Kubernetes authentication |
| `scripts/store-secrets.sh` | Store sample secrets in Vault |
