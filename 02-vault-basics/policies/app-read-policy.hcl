# Policy: app-read
# Grants read-only access to application secrets under secret/data/myapp/*
#
# Attach this policy to roles used by application Pods.
# They can read their own secrets but cannot modify or delete them.

# Read application config
path "secret/data/myapp/*" {
  capabilities = ["read", "list"]
}

# List available secrets (useful for discovery)
path "secret/metadata/myapp/*" {
  capabilities = ["read", "list"]
}
