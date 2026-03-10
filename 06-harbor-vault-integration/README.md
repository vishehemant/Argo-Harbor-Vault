# 06 - Harbor + Vault Integration

## The Problem

In scenario 04, we created Harbor image pull secrets as Kubernetes Secrets stored in Git. But **credentials in Git is bad practice** — even if the repo is private. What if someone forks it? What if Git history is exposed?

## The Solution

Store Harbor credentials in **Vault** and use one of these methods to create Kubernetes Secrets dynamically:

1. **External Secrets Operator (ESO)** — A Kubernetes operator that syncs secrets from Vault into Kubernetes Secrets
2. **Vault Agent Injector** — A sidecar that injects secrets directly into Pod containers

```
┌────────────────────────────────────────────────────────┐
│                                                         │
│    Approach 1: External Secrets Operator                │
│                                                         │
│    ┌──────────┐  sync  ┌──────────────┐  read  ┌─────┐│
│    │ExternalSe│◄──────│  ESO         │──────►│Vault ││
│    │cret (CRD)│        │  Controller  │        │     ││
│    └────┬─────┘        └──────────────┘        └─────┘│
│         │ creates                                      │
│         ▼                                              │
│    ┌──────────┐                                        │
│    │K8s Secret│  ← used by Pods as imagePullSecrets    │
│    └──────────┘                                        │
│                                                         │
├────────────────────────────────────────────────────────┤
│                                                         │
│    Approach 2: Vault Agent Injector                     │
│                                                         │
│    ┌──────────┐  inject  ┌─────────────┐  read  ┌─────┐│
│    │  Pod     │◄────────│ Vault Agent │──────►│Vault ││
│    │ (sidecar)│          │ (sidecar)  │        │     ││
│    └──────────┘          └─────────────┘        └─────┘│
│                                                         │
└────────────────────────────────────────────────────────┘
```

## Approach 1: External Secrets Operator (Recommended)

The **External Secrets Operator** is a Kubernetes operator that reads secrets from external sources (Vault, AWS Secrets Manager, etc.) and creates Kubernetes Secrets.

### Step 1: Install ESO

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace
```

### Step 2: Create a SecretStore (Vault Connection)

The `SecretStore` tells ESO how to connect to Vault.

```bash
kubectl apply -f external-secrets/secret-store.yaml
```

See [external-secrets/secret-store.yaml](./external-secrets/secret-store.yaml).

### Step 3: Create an ExternalSecret (What to Sync)

The `ExternalSecret` tells ESO which Vault path to sync and what Kubernetes Secret to create.

```bash
kubectl apply -f external-secrets/external-secret-harbor-creds.yaml
```

See [external-secrets/external-secret-harbor-creds.yaml](./external-secrets/external-secret-harbor-creds.yaml).

### Step 4: Verify

```bash
# Check that the ExternalSecret synced successfully
kubectl get externalsecret harbor-pull-secret -n my-app
# STATUS should be "SecretSynced"

# Check the created Kubernetes Secret
kubectl get secret harbor-pull-secret -n my-app -o yaml
# This should be a dockerconfigjson secret with real Harbor credentials

# Use it in a Pod
kubectl run test --image=harbor.example.com/my-app/sample-web:v1.0.0 \
  --overrides='{"spec":{"imagePullSecrets":[{"name":"harbor-pull-secret"}]}}'
```

### How ESO Refresh Works

ESO **periodically re-syncs** secrets from Vault (default: every 1 hour). If you rotate the Harbor robot account password in Vault, ESO will automatically update the Kubernetes Secret.

```
Timeline:
  t=0   Store new password in Vault
  t=1h  ESO syncs → Kubernetes Secret is updated
  t=1h  New Pods pick up the new password automatically
```

## Approach 2: Vault Agent Injector

The Vault Agent Injector adds a **sidecar container** to your Pods that fetches secrets from Vault and writes them to a shared volume.

### Step 1: Annotate Your Deployment

```bash
kubectl apply -f vault-injector/deployment-with-annotations.yaml
```

See [vault-injector/deployment-with-annotations.yaml](./vault-injector/deployment-with-annotations.yaml).

### Step 2: Create ServiceAccount and Vault Role

```bash
kubectl apply -f vault-injector/service-account.yaml

# Vault role was created in 02-vault-basics/scripts/setup-kubernetes-auth.sh
```

### How Injector Annotations Work

| Annotation | Purpose |
|------------|---------|
| `vault.hashicorp.com/agent-inject: "true"` | Enable injection for this Pod |
| `vault.hashicorp.com/role: "myapp"` | Vault K8s auth role to use |
| `vault.hashicorp.com/agent-inject-secret-KEY: "PATH"` | Which secret to inject |
| `vault.hashicorp.com/agent-inject-template-KEY: "..."` | Template for formatting the secret |

## Comparison: ESO vs. Vault Injector

| Feature | External Secrets Operator | Vault Agent Injector |
|---------|--------------------------|---------------------|
| Architecture | Controller creates K8s Secrets | Sidecar injects into Pods |
| Secret type | Creates standard K8s Secrets | Writes files into the Pod |
| Image pull secrets | Native support (dockerconfigjson) | Not directly supported |
| Resource overhead | One controller per cluster | One sidecar per Pod |
| Secret refresh | Configurable interval | Automatic with Vault Agent |
| GitOps friendly | Yes (ExternalSecret CRD in Git) | Yes (annotations in manifests) |
| Best for | Registry credentials, shared secrets | Per-Pod application secrets |

## Key Concepts

| Concept | What It Means |
|---------|---------------|
| **ExternalSecret** | CRD that defines which Vault path maps to which K8s Secret |
| **SecretStore** | CRD that defines how to connect to Vault |
| **ClusterSecretStore** | Cluster-wide SecretStore (shared across namespaces) |
| **Vault Agent Injector** | Mutating webhook that adds a Vault sidecar to annotated Pods |
| **Secret Rotation** | ESO periodically re-syncs; Vault Agent uses leases and auto-renew |

## Files in This Directory

| File | Purpose |
|------|---------|
| `external-secrets/secret-store.yaml` | ESO SecretStore connecting to Vault |
| `external-secrets/external-secret-harbor-creds.yaml` | ExternalSecret for Harbor pull credentials |
| `external-secrets/external-secret-app-config.yaml` | ExternalSecret for app configuration secrets |
| `vault-injector/deployment-with-annotations.yaml` | Deployment with Vault Agent annotations |
| `vault-injector/service-account.yaml` | ServiceAccount for Vault auth |
