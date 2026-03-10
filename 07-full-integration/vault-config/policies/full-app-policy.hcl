# Policy: full-app
# Combined policy for the full integration scenario.
# Grants read access to all paths needed by:
#   - External Secrets Operator (Harbor credentials)
#   - Argo Vault Plugin (application secrets)

# Harbor registry credentials (for ESO to create image pull secrets)
path "secret/data/harbor/*" {
  capabilities = ["read", "list"]
}

# Production application secrets (for AVP to inject into manifests)
path "secret/data/production/*" {
  capabilities = ["read", "list"]
}

# Metadata paths (for listing/discovery)
path "secret/metadata/harbor/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/production/*" {
  capabilities = ["read", "list"]
}
