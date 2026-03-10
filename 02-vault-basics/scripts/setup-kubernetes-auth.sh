#!/usr/bin/env bash
# Configures Vault's Kubernetes authentication method.
#
# This allows Kubernetes Pods to authenticate with Vault using their
# ServiceAccount tokens — the foundation for all Vault-K8s integrations.
#
# Usage: ./setup-kubernetes-auth.sh
#
# Prerequisites:
#   - Vault is initialized, unsealed, and logged in
#   - vault-init.json exists in the parent directory

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

echo "==> Enabling Kubernetes auth method..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault auth enable kubernetes 2>/dev/null || echo "  (already enabled)"

echo "==> Configuring Kubernetes auth..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc.cluster.local:443"

echo "==> Enabling KV v2 secrets engine at 'secret/'..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault secrets enable -path=secret kv-v2 2>/dev/null || echo "  (already enabled)"

echo "==> Creating 'app-read' policy..."
kubectl cp ../policies/app-read-policy.hcl "${NAMESPACE}/${POD}:/tmp/app-read-policy.hcl"
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault policy write app-read /tmp/app-read-policy.hcl

echo "==> Creating 'argocd' policy..."
kubectl cp ../policies/argocd-policy.hcl "${NAMESPACE}/${POD}:/tmp/argocd-policy.hcl"
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault policy write argocd /tmp/argocd-policy.hcl

echo "==> Creating Kubernetes auth role 'myapp'..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault write auth/kubernetes/role/myapp \
    bound_service_account_names=myapp-sa \
    bound_service_account_namespaces=default \
    policies=app-read \
    ttl=1h

echo "==> Creating Kubernetes auth role 'argocd'..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  vault write auth/kubernetes/role/argocd \
    bound_service_account_names=argocd-repo-server \
    bound_service_account_namespaces=argocd \
    policies=argocd \
    ttl=1h

echo ""
echo "==> Kubernetes auth setup complete!"
echo ""
echo "Roles created:"
echo "  - myapp  : for app Pods using ServiceAccount 'myapp-sa' in 'default' namespace"
echo "  - argocd : for Argo CD repo-server in 'argocd' namespace"
echo ""
echo "Next steps:"
echo "  1. Store secrets:  see ./store-secrets.sh"
echo "  2. Test from a Pod: see the README.md Step 6"
