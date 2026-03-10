# Policy: argocd
# Grants Argo CD (specifically the Argo Vault Plugin) read access
# to all secrets it needs to template into Kubernetes manifests.
#
# This policy is used in scenario 05 (Vault + Argo CD integration).

# Read all application secrets (Argo CD needs to inject these into manifests)
path "secret/data/*" {
  capabilities = ["read", "list"]
}

# Read metadata for secret listing
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}

# Read Harbor credentials (used in scenario 06)
path "secret/data/harbor/*" {
  capabilities = ["read"]
}
