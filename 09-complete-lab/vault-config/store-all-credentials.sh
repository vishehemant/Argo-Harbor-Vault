#!/usr/bin/env bash
# Stores ALL credentials for the complete lab in Vault:
#   - Harbor registry credentials
#   - JFrog Artifactory credentials
#   - Per-environment application secrets (dev/uat/prod)
#
# Usage: ./store-all-credentials.sh

set -euo pipefail

NAMESPACE="${VAULT_NAMESPACE:-vault}"
POD="vault-0"

echo "==> Enabling KV v2..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault secrets enable -path=secret kv-v2 2>/dev/null || true

echo ""
echo "==> Storing Harbor registry credentials..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault kv put secret/registry/harbor \
    url="harbor.example.com" \
    username="robot\$ci-pipeline" \
    password="harbor-robot-secret-token" \
    email="ci@example.com"

echo ""
echo "==> Storing JFrog Artifactory credentials..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault kv put secret/registry/jfrog \
    url="jfrog.example.com" \
    username="ci-user" \
    password="jfrog-api-token" \
    email="ci@example.com"

echo ""
echo "==> Storing JFrog npm auth token..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault kv put secret/jfrog/npm \
    registry="https://jfrog.example.com/artifactory/api/npm/npm-virtual/" \
    auth_token="jfrog-npm-auth-token" \
    scope="@myorg"

echo ""
echo "==> Storing per-environment application secrets..."

for ENV in dev uat prod; do
  echo "  Storing ${ENV} secrets..."
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    vault kv put "secret/${ENV}/myapp/config" \
      db_host="postgres.myapp-${ENV}.svc.cluster.local" \
      db_port="5432" \
      db_name="myapp_${ENV}" \
      db_user="myapp_${ENV}_user" \
      db_password="${ENV}-db-password-$(date +%Y)"

  kubectl exec -n "$NAMESPACE" "$POD" -- \
    vault kv put "secret/${ENV}/myapp/api-keys" \
      stripe_key="sk_${ENV}_stripe_key" \
      sendgrid_key="SG.${ENV}_sendgrid_key" \
      jwt_secret="${ENV}-jwt-signing-key"
done

echo ""
echo "==> Applying Vault policies..."

for ENV in dev uat prod; do
  kubectl cp "policies/${ENV}-policy.hcl" "${NAMESPACE}/${POD}:/tmp/${ENV}-policy.hcl"
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    vault policy write "${ENV}-app" "/tmp/${ENV}-policy.hcl"
done

echo ""
echo "==> Creating Kubernetes auth roles..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault auth enable kubernetes 2>/dev/null || true

kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc.cluster.local:443"

for ENV in dev uat prod; do
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    vault write "auth/kubernetes/role/argocd-${ENV}" \
      bound_service_account_names=argocd-repo-server \
      bound_service_account_namespaces=argocd \
      policies="${ENV}-app" \
      ttl=1h

  kubectl exec -n "$NAMESPACE" "$POD" -- \
    vault write "auth/kubernetes/role/eso-${ENV}" \
      bound_service_account_names=vault-auth-sa \
      bound_service_account_namespaces="myapp-${ENV}" \
      policies="${ENV}-app" \
      ttl=1h
done

echo ""
echo "==> All credentials stored!"
echo ""
echo "Verify:"
echo "  kubectl exec -n vault vault-0 -- vault kv get secret/registry/harbor"
echo "  kubectl exec -n vault vault-0 -- vault kv get secret/registry/jfrog"
echo "  kubectl exec -n vault vault-0 -- vault kv get secret/dev/myapp/config"
