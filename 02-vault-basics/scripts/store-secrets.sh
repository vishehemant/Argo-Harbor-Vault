#!/usr/bin/env bash
# Stores sample secrets in Vault for use across all scenarios.
#
# Usage: ./store-secrets.sh
#
# This creates secrets at the following paths:
#   secret/myapp/config    — Application database credentials
#   secret/myapp/api-keys  — External API keys
#   secret/harbor/creds    — Harbor registry credentials

set -euo pipefail

NAMESPACE="${VAULT_NAMESPACE:-vault}"
POD="vault-0"
INIT_FILE="${INIT_FILE:-vault-init.json}"

if [ ! -f "$INIT_FILE" ]; then
  echo "Error: ${INIT_FILE} not found. Run init-and-unseal.sh first."
  exit 1
fi

ROOT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")

echo "==> Logging into Vault..."
kubectl exec -n "$NAMESPACE" "$POD" -- vault login "$ROOT_TOKEN" > /dev/null

echo "==> Storing application config secrets..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault kv put secret/myapp/config \
    db_host="postgres.default.svc.cluster.local" \
    db_port="5432" \
    db_name="myapp_production" \
    db_user="myapp" \
    db_password="super-secret-db-password"

echo "==> Storing API key secrets..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault kv put secret/myapp/api-keys \
    stripe_key="sk_live_abc123" \
    sendgrid_key="SG.xyz789" \
    redis_url="redis://:redis-password@redis.default.svc:6379/0"

echo "==> Storing Harbor registry credentials..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault kv put secret/harbor/creds \
    url="harbor.example.com" \
    username="robot\$ci-pipeline" \
    password="harbor-robot-secret-token" \
    email="ci@example.com"

echo ""
echo "==> Secrets stored successfully!"
echo ""
echo "Verify with:"
echo "  kubectl exec -n vault vault-0 -- vault kv get secret/myapp/config"
echo "  kubectl exec -n vault vault-0 -- vault kv get secret/myapp/api-keys"
echo "  kubectl exec -n vault vault-0 -- vault kv get secret/harbor/creds"
