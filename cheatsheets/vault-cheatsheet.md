# Vault Cheatsheet

## Basic Operations

```bash
# Set Vault address
export VAULT_ADDR='http://vault.vault.svc.cluster.local:8200'

# Login with token
vault login <token>

# Check status
vault status

# Seal Vault (emergency)
vault operator seal
```

## KV v2 Secrets Engine

```bash
# Enable KV v2
vault secrets enable -path=secret kv-v2

# Write a secret
vault kv put secret/myapp/config \
  db_host="localhost" \
  db_password="s3cret"

# Read a secret
vault kv get secret/myapp/config

# Read a specific field
vault kv get -field=db_password secret/myapp/config

# Read as JSON
vault kv get -format=json secret/myapp/config

# List secrets at a path
vault kv list secret/myapp/

# Delete (soft delete — can be undeleted)
vault kv delete secret/myapp/config

# Permanently destroy a version
vault kv destroy -versions=1 secret/myapp/config

# Undelete
vault kv undelete -versions=1 secret/myapp/config

# Read a specific version
vault kv get -version=2 secret/myapp/config

# Get metadata
vault kv metadata get secret/myapp/config
```

## Policies

```bash
# Write a policy from file
vault policy write my-policy policy.hcl

# Write inline
vault policy write my-policy - <<EOF
path "secret/data/myapp/*" {
  capabilities = ["read", "list"]
}
EOF

# List policies
vault policy list

# Read a policy
vault policy read my-policy

# Delete a policy
vault policy delete my-policy
```

### Policy Capabilities

| Capability | HTTP Verb | Description |
|------------|-----------|-------------|
| `create` | POST | Create new data |
| `read` | GET | Read data |
| `update` | PUT/POST | Update existing data |
| `delete` | DELETE | Delete data |
| `list` | LIST | List keys at a path |
| `deny` | — | Explicitly deny access |

## Kubernetes Auth

```bash
# Enable
vault auth enable kubernetes

# Configure
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local:443"

# Create a role
vault write auth/kubernetes/role/myapp \
  bound_service_account_names=myapp-sa \
  bound_service_account_namespaces=default \
  policies=my-policy \
  ttl=1h

# Login (from inside a Pod)
JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
vault write auth/kubernetes/login role=myapp jwt=$JWT

# List roles
vault list auth/kubernetes/role

# Read a role
vault read auth/kubernetes/role/myapp
```

## Token Management

```bash
# Create a token with a policy
vault token create -policy=my-policy -ttl=24h

# Lookup current token
vault token lookup

# Renew a token
vault token renew <token>

# Revoke a token
vault token revoke <token>
```

## Using from Kubernetes (kubectl exec)

```bash
NAMESPACE=vault
POD=vault-0

# Run vault commands inside the pod
kubectl exec -n $NAMESPACE $POD -- vault status
kubectl exec -n $NAMESPACE $POD -- vault kv get secret/myapp/config

# Copy files into the pod
kubectl cp policy.hcl $NAMESPACE/$POD:/tmp/policy.hcl
```

## Vault Agent Injector Annotations

```yaml
# Enable injection
vault.hashicorp.com/agent-inject: "true"

# Auth role
vault.hashicorp.com/role: "myapp"

# Inject a secret as a file
vault.hashicorp.com/agent-inject-secret-config: "secret/data/myapp/config"

# Custom template
vault.hashicorp.com/agent-inject-template-config: |
  {{- with secret "secret/data/myapp/config" -}}
  export DB_PASSWORD="{{ .Data.data.db_password }}"
  {{- end }}

# Run init container only (no sidecar)
vault.hashicorp.com/agent-pre-populate-only: "true"
```

## Key Concepts

| Term | Meaning |
|------|---------|
| Seal/Unseal | Vault must be unsealed to serve requests |
| Root Token | All-powerful token generated at init |
| KV v2 | Versioned key-value secrets engine |
| Policy | Rules defining path access and capabilities |
| Auth Method | How clients prove identity (k8s, token, approle) |
| Lease | Time-limited access grant; auto-revoked on expiry |
| Secret Engine | Backend that stores/generates secrets |
| Kubernetes Auth | Auth using K8s ServiceAccount tokens |
