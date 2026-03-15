#!/usr/bin/env bash
# Stores Tetris app secrets in Vault for all environments.
set -euo pipefail

NAMESPACE="${VAULT_NAMESPACE:-vault}"
POD="vault-0"

echo "==> Storing Tetris secrets per environment..."
for ENV in dev uat prod; do
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    vault kv put "secret/${ENV}/tetris/config" \
      analytics_key="${ENV}_analytics_key_$(date +%Y)" \
      feature_flags="${ENV}_leaderboard=true,${ENV}_multiplayer=false"
done

echo "==> Creating Vault policies..."
for ENV in dev uat prod; do
  kubectl exec -n "$NAMESPACE" "$POD" -- sh -c "
    vault policy write tetris-${ENV} - <<POLICY
path \"secret/data/${ENV}/tetris/*\" {
  capabilities = [\"read\", \"list\"]
}
path \"secret/data/registry/*\" {
  capabilities = [\"read\"]
}
POLICY"
done

echo "==> Creating Kubernetes auth roles..."
for ENV in dev uat prod; do
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    vault write "auth/kubernetes/role/tetris-${ENV}" \
      bound_service_account_names=argocd-repo-server \
      bound_service_account_namespaces=argocd \
      policies="tetris-${ENV}" \
      ttl=1h
done

echo "==> Done! Verify:"
echo "  kubectl exec -n vault vault-0 -- vault kv get secret/dev/tetris/config"
echo "  kubectl exec -n vault vault-0 -- vault kv get secret/prod/tetris/config"
