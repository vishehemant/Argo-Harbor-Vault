#!/usr/bin/env bash
# Sets up per-environment Vault paths, policies, and Kubernetes auth roles.
#
# Usage: ./setup-multi-env.sh
#
# Creates:
#   - Secrets at secret/{dev,uat,prod}/myapp/config
#   - Policies: dev-app, uat-app, prod-app
#   - Kubernetes auth roles: argocd-dev, argocd-uat, argocd-prod

set -euo pipefail

NAMESPACE="${VAULT_NAMESPACE:-vault}"
POD="vault-0"

echo "==> Storing per-environment secrets..."

for ENV in dev uat prod; do
  echo "  Storing secrets for: ${ENV}"
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    vault kv put "secret/${ENV}/myapp/config" \
      db_host="postgres.myapp-${ENV}.svc.cluster.local" \
      db_port="5432" \
      db_name="myapp_${ENV}" \
      db_user="myapp_${ENV}_user" \
      db_password="${ENV}-db-password-$(date +%Y)"
done

echo ""
echo "==> Applying per-environment policies..."

for ENV in dev uat prod; do
  echo "  Applying policy: ${ENV}-app"
  kubectl cp "policies/${ENV}-policy.hcl" "${NAMESPACE}/${POD}:/tmp/${ENV}-policy.hcl"
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    vault policy write "${ENV}-app" "/tmp/${ENV}-policy.hcl"
done

echo ""
echo "==> Creating per-environment Kubernetes auth roles..."

for ENV in dev uat prod; do
  echo "  Creating role: argocd-${ENV}"
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    vault write "auth/kubernetes/role/argocd-${ENV}" \
      bound_service_account_names=argocd-repo-server \
      bound_service_account_namespaces=argocd \
      policies="${ENV}-app" \
      ttl=1h
done

echo ""
echo "==> Multi-environment setup complete!"
echo ""
echo "Verify:"
for ENV in dev uat prod; do
  echo "  kubectl exec -n vault vault-0 -- vault kv get secret/${ENV}/myapp/config"
done
echo ""
echo "Roles created:"
echo "  argocd-dev  → can only read secret/data/dev/*"
echo "  argocd-uat  → can only read secret/data/uat/*"
echo "  argocd-prod → can only read secret/data/prod/*"
