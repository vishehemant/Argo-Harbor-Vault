#!/usr/bin/env bash
# Initializes and unseals Vault running in Kubernetes.
#
# Usage: ./init-and-unseal.sh
#
# Prerequisites:
#   - Vault must be installed in the 'vault' namespace
#   - kubectl must be configured

set -euo pipefail

NAMESPACE="${VAULT_NAMESPACE:-vault}"
POD="vault-0"
INIT_FILE="vault-init.json"

echo "==> Checking Vault status..."
STATUS=$(kubectl exec -n "$NAMESPACE" "$POD" -- vault status -format=json 2>/dev/null || true)

if echo "$STATUS" | jq -e '.initialized == true' &>/dev/null; then
  echo "Vault is already initialized."

  if echo "$STATUS" | jq -e '.sealed == false' &>/dev/null; then
    echo "Vault is already unsealed. Nothing to do."
    exit 0
  fi
else
  echo "==> Initializing Vault..."
  kubectl exec -n "$NAMESPACE" "$POD" -- vault operator init \
    -key-shares=5 \
    -key-threshold=3 \
    -format=json > "$INIT_FILE"

  echo "Initialization complete. Keys saved to ${INIT_FILE}"
  echo "IMPORTANT: Back up ${INIT_FILE} securely!"
fi

echo "==> Unsealing Vault (using 3 of 5 keys)..."
for i in 0 1 2; do
  KEY=$(jq -r ".unseal_keys_b64[${i}]" "$INIT_FILE")
  echo "  Applying unseal key $((i+1))..."
  kubectl exec -n "$NAMESPACE" "$POD" -- vault operator unseal "$KEY"
done

echo "==> Vault status after unseal:"
kubectl exec -n "$NAMESPACE" "$POD" -- vault status

ROOT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")
echo ""
echo "==> Root token: ${ROOT_TOKEN}"
echo "    (Use this to log into the Vault UI or CLI)"
echo ""
echo "Next steps:"
echo "  1. Enable the KV secrets engine:  see ./store-secrets.sh"
echo "  2. Set up Kubernetes auth:        see ./setup-kubernetes-auth.sh"
