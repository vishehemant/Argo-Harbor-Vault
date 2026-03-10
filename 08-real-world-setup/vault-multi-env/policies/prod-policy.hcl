# Production environment policy — scoped to prod secret paths only.
# Cannot read dev or UAT secrets.
# Most restrictive policy — only read, no list on metadata.

path "secret/data/prod/*" {
  capabilities = ["read"]
}

path "secret/data/harbor/creds" {
  capabilities = ["read"]
}
