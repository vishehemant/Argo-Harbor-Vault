path "secret/data/uat/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/uat/*" {
  capabilities = ["read", "list"]
}
path "secret/data/registry/*" {
  capabilities = ["read"]
}
path "secret/data/jfrog/*" {
  capabilities = ["read"]
}
