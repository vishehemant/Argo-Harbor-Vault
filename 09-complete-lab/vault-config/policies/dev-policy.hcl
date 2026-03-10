path "secret/data/dev/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/dev/*" {
  capabilities = ["read", "list"]
}
path "secret/data/registry/*" {
  capabilities = ["read"]
}
path "secret/data/jfrog/*" {
  capabilities = ["read"]
}
