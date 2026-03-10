#!/usr/bin/env bash
# Stores all secrets needed for the full integration scenario.
#
# Usage: ./store-all-secrets.sh
#
# Run this ONCE after Vault is initialized and unsealed.

set -euo pipefail

NAMESPACE="${VAULT_NAMESPACE:-vault}"
POD="vault-0"
INIT_FILE="${INIT_FILE:-../../02-vault-basics/vault-init.json}"

if [ ! -f "$INIT_FILE" ]; then
  echo "Error: ${INIT_FILE} not found."
  echo "Run 02-vault-basics/scripts/init-and-unseal.sh first."
  exit 1
fi

ROOT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")

echo "==> Logging into Vault..."
kubectl exec -n "$NAMESPACE" "$POD" -- vault login "$ROOT_TOKEN" > /dev/null

echo "==> Enabling KV v2 (if not already enabled)..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault secrets enable -path=secret kv-v2 2>/dev/null || true

echo ""
echo "==> Storing Harbor registry credentials..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault kv put secret/harbor/creds \
    url="harbor.example.com" \
    username="robot\$ci-pipeline" \
    password="harbor-robot-secret-token" \
    email="ci@example.com"

echo ""
echo "==> Storing production database config..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault kv put secret/production/myapp/config \
    db_host="postgres.production.svc.cluster.local" \
    db_port="5432" \
    db_name="myapp_production" \
    db_user="myapp_prod" \
    db_password="production-db-password-2024"

echo ""
echo "==> Storing production API keys..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault kv put secret/production/myapp/api-keys \
    stripe_key="sk_live_production_stripe_key" \
    sendgrid_key="SG.production_sendgrid_key" \
    jwt_secret="production-jwt-signing-key-2024"

echo ""
echo "==> Applying Vault policy..."
kubectl cp policies/full-app-policy.hcl "${NAMESPACE}/${POD}:/tmp/full-app-policy.hcl"
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault policy write full-app /tmp/full-app-policy.hcl

echo ""
echo "==> Creating Vault Kubernetes auth roles..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault write auth/kubernetes/role/eso-harbor \
    bound_service_account_names=vault-auth-sa \
    bound_service_account_namespaces=production \
    policies=full-app \
    ttl=1h

kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault write auth/kubernetes/role/argocd \
    bound_service_account_names=argocd-repo-server \
    bound_service_account_namespaces=argocd \
    policies=full-app \
    ttl=1h

echo ""
echo "==> All secrets stored and roles configured!"
echo ""
echo "Verify:"
echo "  kubectl exec -n vault vault-0 -- vault kv get secret/harbor/creds"
echo "  kubectl exec -n vault vault-0 -- vault kv get secret/production/myapp/config"
echo "  kubectl exec -n vault vault-0 -- vault kv get secret/production/myapp/api-keys"
