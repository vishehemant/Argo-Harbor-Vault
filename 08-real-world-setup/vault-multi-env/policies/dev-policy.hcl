# Dev environment policy — scoped to dev secret paths only.
# Cannot read UAT or prod secrets.

path "secret/data/dev/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/dev/*" {
  capabilities = ["read", "list"]
}

path "secret/data/harbor/creds" {
  capabilities = ["read"]
}
