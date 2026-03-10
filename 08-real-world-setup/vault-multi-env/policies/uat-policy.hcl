# UAT environment policy — scoped to UAT secret paths only.
# Cannot read dev or prod secrets.

path "secret/data/uat/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/uat/*" {
  capabilities = ["read", "list"]
}

path "secret/data/harbor/creds" {
  capabilities = ["read"]
}
