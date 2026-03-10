# Hands-On Practice Guide

This guide walks you through practicing each scenario on your local machine using **kind** (Kubernetes in Docker). By the end, you'll have all three tools running locally and fully integrated.

## Time Estimates

| Phase | Duration |
|-------|----------|
| Environment setup | ~15 min |
| Phase 1: Harbor | ~20 min |
| Phase 2: Vault | ~20 min |
| Phase 3: Argo CD | ~15 min |
| Phase 4: Harbor + Argo CD | ~15 min |
| Phase 5: Vault + Argo CD | ~20 min |
| Phase 6: Harbor + Vault | ~15 min |
| Phase 7: Full integration | ~20 min |
| **Total** | **~2.5 hours** |

---

## Environment Setup

### Option A: kind (Recommended for Local Practice)

[kind](https://kind.sigs.k8s.io/) runs a Kubernetes cluster inside Docker containers. It's fast, lightweight, and perfect for learning.

```bash
# ── Install kind ──
# macOS
brew install kind

# Linux
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind

# ── Create a cluster with extra port mappings ──
# Harbor, Vault UI, and Argo CD all need exposed ports
cat <<EOF | kind create cluster --name practice --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30002
        hostPort: 30002    # Harbor HTTP
      - containerPort: 30003
        hostPort: 30003    # Harbor HTTPS
      - containerPort: 30080
        hostPort: 30080    # Argo CD HTTP
      - containerPort: 30443
        hostPort: 30443    # Argo CD HTTPS
    extraMounts:
      - hostPath: /tmp/harbor-data
        containerPath: /harbor-data
EOF

# Verify the cluster is running
kubectl cluster-info
kubectl get nodes
```

### Option B: Minikube

```bash
minikube start --cpus=4 --memory=8192 --driver=docker
```

### Option C: Cloud Cluster (easiest but costs money)

Use a managed Kubernetes service (GKE, EKS, AKS) if you want to skip local setup. A small 2-node cluster is sufficient.

### Install Required CLI Tools

```bash
# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Argo CD CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && sudo mv argocd /usr/local/bin/

# jq (used in scripts)
sudo apt-get install -y jq   # Linux
# brew install jq             # macOS
```

### Clone the Repo

```bash
git clone https://github.com/vishehemant/Argo-Harbor-Vault.git
cd Argo-Harbor-Vault
```

---

## Phase 1: Practice Harbor (Scenario 01)

**Goal:** Install Harbor, create a project, build an image, push it, and scan it.

### Step 1.1 — Install Harbor

```bash
helm repo add harbor https://helm.goharbor.io
helm repo update

kubectl create namespace harbor

helm install harbor harbor/harbor \
  --namespace harbor \
  -f 01-harbor-basics/harbor-helm-values.yaml \
  --wait --timeout 10m
```

Wait for all pods to become ready:

```bash
kubectl get pods -n harbor -w
# Wait until all pods show STATUS: Running and READY: 1/1 (or 2/2)
# Press Ctrl+C when done
```

### Step 1.2 — Access the Harbor UI

```bash
# Port-forward for local access
kubectl port-forward svc/harbor-portal -n harbor 8080:80 &

# Open http://localhost:8080 in your browser
# Login: admin / Harbor12345
```

**Things to explore in the UI:**
- Click "Projects" -- see the default `library` project
- Click "Administration" > "Users" -- see user management
- Click "Administration" > "Registries" -- where you'd add replication endpoints

### Step 1.3 — Create a Project via API

```bash
export HARBOR_URL="http://localhost:8080"

# Create a project called "my-app"
curl -u "admin:Harbor12345" \
  -X POST "${HARBOR_URL}/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d '{"project_name":"my-app","public":false,"metadata":{"auto_scan":"true"}}'

# Verify — should see "my-app" in the list
curl -u "admin:Harbor12345" "${HARBOR_URL}/api/v2.0/projects" | jq '.[].name'
```

**Check in the UI:** Refresh the Projects page -- you should see "my-app".

### Step 1.4 — Build and Push an Image

```bash
# For kind clusters, we need to load the image differently
# First, build it locally
docker build -t localhost:8080/my-app/sample-web:v1.0.0 -f 01-harbor-basics/Dockerfile 01-harbor-basics/

# If using port-forward, configure Docker to trust the registry
# (kind approach -- load image directly into the cluster)
kind load docker-image localhost:8080/my-app/sample-web:v1.0.0 --name practice
```

> **Note:** In a real environment with proper DNS, you'd `docker login harbor.example.com` and `docker push` directly. For local kind clusters, we use `kind load` to bypass registry authentication during practice.

### Step 1.5 — Verify Understanding

Before moving on, make sure you can answer:
- [ ] What is a Harbor "project" and why would you create one?
- [ ] What's the difference between a robot account and a regular user?
- [ ] Why would you enable auto-scan on a project?
- [ ] What does an image pull secret do?

---

## Phase 2: Practice Vault (Scenario 02)

**Goal:** Install Vault, initialize it, store secrets, set up Kubernetes auth.

### Step 2.1 — Install Vault

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

kubectl create namespace vault

helm install vault hashicorp/vault \
  --namespace vault \
  -f 02-vault-basics/vault-helm-values.yaml \
  --wait --timeout 5m
```

```bash
# The vault-0 pod will be Running but NOT Ready (0/1)
# That's expected — Vault is sealed and needs initialization
kubectl get pods -n vault
```

### Step 2.2 — Initialize and Unseal

```bash
# Initialize Vault
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=1 \
  -key-threshold=1 \
  -format=json > vault-keys.json

# Using 1 key share for simplicity in practice (use 5 shares in production!)

# Unseal
VAULT_UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' vault-keys.json)
kubectl exec -n vault vault-0 -- vault operator unseal "$VAULT_UNSEAL_KEY"

# Verify — "Sealed: false"
kubectl exec -n vault vault-0 -- vault status
```

### Step 2.3 — Access the Vault UI

```bash
kubectl port-forward svc/vault -n vault 8200:8200 &

# Open http://localhost:8200 in your browser
# Login with the root token:
ROOT_TOKEN=$(jq -r '.root_token' vault-keys.json)
echo "Root token: $ROOT_TOKEN"
```

### Step 2.4 — Store Secrets

```bash
# Login
kubectl exec -n vault vault-0 -- vault login $(jq -r '.root_token' vault-keys.json)

# Enable KV v2
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2

# Store application secrets
kubectl exec -n vault vault-0 -- vault kv put secret/myapp/config \
  db_host="postgres.default.svc" \
  db_port="5432" \
  db_user="myapp" \
  db_password="super-secret-password"

# Read them back
kubectl exec -n vault vault-0 -- vault kv get secret/myapp/config

# Try reading just one field
kubectl exec -n vault vault-0 -- vault kv get -field=db_password secret/myapp/config
```

**Check in the UI:** Navigate to Secrets Engines > secret > myapp > config.

### Step 2.5 — Create a Policy and Test Access Control

```bash
# Copy policy into the pod
kubectl cp 02-vault-basics/policies/app-read-policy.hcl vault/vault-0:/tmp/policy.hcl

# Apply it
kubectl exec -n vault vault-0 -- vault policy write app-read /tmp/policy.hcl

# Create a token with ONLY this policy
kubectl exec -n vault vault-0 -- vault token create -policy=app-read -format=json > app-token.json
APP_TOKEN=$(jq -r '.auth.client_token' app-token.json)

# Test: this token can READ secrets
kubectl exec -n vault vault-0 -- vault kv get -field=db_password secret/myapp/config

# Test: this token CANNOT WRITE secrets (should fail with "permission denied")
kubectl exec -n vault vault-0 -- sh -c "VAULT_TOKEN=$APP_TOKEN vault kv put secret/myapp/config hacked=true" || echo "Permission denied (expected!)"
```

### Step 2.6 — Set Up Kubernetes Auth

```bash
# Enable Kubernetes auth
kubectl exec -n vault vault-0 -- vault auth enable kubernetes

# Configure it
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local:443"

# Create a role
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/myapp \
  bound_service_account_names=myapp-sa \
  bound_service_account_namespaces=default \
  policies=app-read \
  ttl=1h

# Create the ServiceAccount in the default namespace
kubectl create serviceaccount myapp-sa
```

### Step 2.7 — Test Kubernetes Auth from a Pod

```bash
# Launch a test pod
kubectl run vault-test --image=vault:1.15.4 \
  --overrides='{"spec":{"serviceAccountName":"myapp-sa"}}' \
  --command -- sleep 3600

kubectl wait --for=condition=Ready pod/vault-test --timeout=60s

# From inside the pod, authenticate with Vault
kubectl exec vault-test -- sh -c '
  JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  VAULT_ADDR=http://vault.vault.svc.cluster.local:8200

  # Login with Kubernetes auth
  RESPONSE=$(wget -qO- --post-data "{\"jwt\":\"$JWT\",\"role\":\"myapp\"}" \
    $VAULT_ADDR/v1/auth/kubernetes/login)

  TOKEN=$(echo $RESPONSE | sed "s/.*client_token\":\"\([^\"]*\).*/\1/")
  echo "Got Vault token: ${TOKEN:0:10}..."

  # Read a secret
  wget -qO- --header "X-Vault-Token: $TOKEN" \
    $VAULT_ADDR/v1/secret/data/myapp/config
'

# Clean up
kubectl delete pod vault-test
```

### Step 2.8 — Verify Understanding

- [ ] What does "unsealing" Vault mean? Why is it needed?
- [ ] What's the difference between the root token and a policy-scoped token?
- [ ] How does Kubernetes auth work? (Pod ServiceAccount -> Vault role -> Vault policy)
- [ ] What is KV v2 and how does versioning work?

---

## Phase 3: Practice Argo CD (Scenario 03)

**Goal:** Install Argo CD, deploy a sample app, understand sync behavior.

### Step 3.1 — Install Argo CD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl create namespace argocd

helm install argocd argo/argo-cd \
  --namespace argocd \
  -f 03-argocd-basics/argocd-helm-values.yaml \
  --wait --timeout 5m
```

### Step 3.2 — Access the UI

```bash
# Get the admin password
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "Argo CD password: $ARGOCD_PASS"

# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8443:443 &

# Open https://localhost:8443 (accept the self-signed cert warning)
# Login: admin / <password from above>
```

### Step 3.3 — Deploy a Sample Application

```bash
# Apply the Application CRD
kubectl apply -f 03-argocd-basics/argocd-application.yaml

# Watch it in the CLI
argocd login localhost:8443 --username admin --password "$ARGOCD_PASS" --insecure
argocd app get sample-app

# Watch the pods come up
kubectl get pods -n sample-app -w
```

**Check the UI:** You should see the "sample-app" Application card. Click it to see the resource tree (Deployment -> ReplicaSet -> Pods).

### Step 3.4 — Experiment with Sync Behavior

```bash
# Experiment 1: Manual change → self-heal
# Scale the deployment directly (bypass Git)
kubectl scale deployment sample-web -n sample-app --replicas=5

# Watch Argo CD revert it back to 2 replicas (self-heal)
kubectl get pods -n sample-app -w
# Within ~30 seconds, it should scale back to 2

# Experiment 2: Delete a resource → Argo CD recreates it
kubectl delete svc sample-web -n sample-app

# Argo CD will recreate it
kubectl get svc -n sample-app -w
```

### Step 3.5 — Verify Understanding

- [ ] What is an Argo CD "Application" CRD?
- [ ] What does "OutOfSync" mean? When does it happen?
- [ ] What's the difference between auto-sync, prune, and self-heal?
- [ ] What happens if you delete a YAML file from Git with `prune: true`?

---

## Phase 4: Practice Harbor + Argo CD (Scenario 04)

**Goal:** Deploy an application that pulls its image from a private Harbor registry via Argo CD.

### Step 4.1 — Create the Image Pull Secret

```bash
kubectl create namespace my-app

# Create the secret (use your actual Harbor credentials if available,
# otherwise this demonstrates the concept)
kubectl create secret docker-registry harbor-pull-secret \
  --docker-server=harbor.example.com \
  --docker-username='robot$ci-pipeline' \
  --docker-password='placeholder-for-practice' \
  --namespace=my-app
```

### Step 4.2 — Deploy via Argo CD

```bash
# Apply the Application
kubectl apply -f 04-harbor-argocd-integration/argocd-application.yaml

# Check status (it may be "Degraded" because the Harbor image isn't reachable
# in a local setup — that's OK, the point is to understand the configuration)
argocd app get harbor-sample-app
```

### Step 4.3 — Study the Manifests

Open these files and understand each line:
1. `04-harbor-argocd-integration/sample-app/deployment.yaml` -- note `imagePullSecrets` and the Harbor image URL
2. `04-harbor-argocd-integration/registry-credentials/image-pull-secret.yaml` -- note the `dockerconfigjson` structure
3. `04-harbor-argocd-integration/argocd-application-with-image-updater.yaml` -- note the Image Updater annotations

### Step 4.4 — Verify Understanding

- [ ] Why does the Deployment need `imagePullSecrets`?
- [ ] What format is the docker-registry secret in? (`dockerconfigjson`)
- [ ] How does the Argo CD Image Updater know which registry to watch?
- [ ] What's the difference between the "argocd" and "git" write-back methods?

---

## Phase 5: Practice Vault + Argo CD (Scenario 05)

**Goal:** Set up AVP to inject Vault secrets into Argo CD-managed manifests.

### Step 5.1 — Store Secrets in Vault

```bash
# Store the secrets that our manifests reference
kubectl exec -n vault vault-0 -- vault kv put secret/myapp/config \
  db_host="postgres.default.svc" \
  db_port="5432" \
  db_name="myapp_db" \
  db_user="myapp" \
  db_password="vault-managed-password"

kubectl exec -n vault vault-0 -- vault kv put secret/myapp/api-keys \
  stripe_key="sk_test_practice123" \
  sendgrid_key="SG.practice456" \
  redis_url="redis://localhost:6379/0"
```

### Step 5.2 — Set Up AVP

```bash
# Create the AVP role in Vault for Argo CD
kubectl exec -n vault vault-0 -- vault policy write argocd - <<'EOF'
path "secret/data/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
EOF

kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/argocd \
  bound_service_account_names=argocd-repo-server \
  bound_service_account_namespaces=argocd \
  policies=argocd \
  ttl=1h

# Install the CMP plugin ConfigMap
kubectl apply -f 05-vault-argocd-integration/argocd-vault-plugin/cmp-plugin-configmap.yaml

# Patch the repo-server to add AVP sidecar
kubectl patch deployment argocd-repo-server -n argocd \
  --patch-file 05-vault-argocd-integration/argocd-vault-plugin/argocd-repo-server-patch.yaml
```

### Step 5.3 — Study the Secret Manifests

Look at `05-vault-argocd-integration/sample-app/secret.yaml`:

```yaml
# This is safe to commit to Git — no real secrets!
DB_PASSWORD: <path:secret/data/myapp/config#db_password>
```

At sync time, AVP replaces this with the real value from Vault.

### Step 5.4 — Deploy and Verify

```bash
kubectl apply -f 05-vault-argocd-integration/argocd-application.yaml
argocd app get vault-argocd-demo

# If AVP is working, the Secret in the cluster will have real values:
kubectl get secret myapp-secrets -n vault-argocd-demo -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
# Should output: vault-managed-password
```

### Step 5.5 — Verify Understanding

- [ ] Why is it safe to store `<path:secret/data/...#key>` placeholders in Git?
- [ ] How does AVP authenticate with Vault? (Kubernetes auth via repo-server's ServiceAccount)
- [ ] What's the difference between AVP-plain, AVP-Kustomize, and AVP-Helm plugins?
- [ ] When are the placeholders resolved — at commit time or at sync time?

---

## Phase 6: Practice Harbor + Vault (Scenario 06)

**Goal:** Use External Secrets Operator to dynamically create Harbor pull secrets from Vault.

### Step 6.1 — Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --wait
```

### Step 6.2 — Store Harbor Credentials in Vault

```bash
kubectl exec -n vault vault-0 -- vault kv put secret/harbor/creds \
  url="harbor.example.com" \
  username='robot$ci-pipeline' \
  password="harbor-robot-secret" \
  email="ci@example.com"
```

### Step 6.3 — Create the SecretStore and ExternalSecret

```bash
# Create the namespace and ServiceAccount
kubectl create namespace my-app 2>/dev/null || true
kubectl apply -f 06-harbor-vault-integration/external-secrets/secret-store.yaml
kubectl apply -f 06-harbor-vault-integration/external-secrets/external-secret-harbor-creds.yaml
```

### Step 6.4 — Verify

```bash
# Check ExternalSecret status
kubectl get externalsecret -n my-app
# Look for STATUS: SecretSynced

# Check that the K8s Secret was created
kubectl get secret harbor-pull-secret -n my-app
# TYPE should be: kubernetes.io/dockerconfigjson

# Decode it to see the contents
kubectl get secret harbor-pull-secret -n my-app \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .
```

### Step 6.5 — Practice Secret Rotation

```bash
# Simulate a credential rotation — update the password in Vault
kubectl exec -n vault vault-0 -- vault kv put secret/harbor/creds \
  url="harbor.example.com" \
  username='robot$ci-pipeline' \
  password="NEW-rotated-password-2024" \
  email="ci@example.com"

# Wait for ESO to refresh (or trigger manually)
# Default refresh interval is 1h, but you can annotate the ExternalSecret:
kubectl annotate externalsecret harbor-pull-secret -n my-app \
  force-sync=$(date +%s) --overwrite

# Check the updated secret
kubectl get secret harbor-pull-secret -n my-app \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .
# password should now be "NEW-rotated-password-2024"
```

### Step 6.6 — Verify Understanding

- [ ] What's the difference between a `SecretStore` and a `ClusterSecretStore`?
- [ ] How does ESO handle secret rotation? (refresh interval)
- [ ] When would you use ESO vs. Vault Agent Injector?
- [ ] Why is ESO better for image pull secrets specifically?

---

## Phase 7: Full Integration (Scenario 07)

**Goal:** Tie everything together — CI builds an image, pushes to Harbor, Vault manages secrets, Argo CD deploys.

### Step 7.1 — Review the Architecture

Open `07-full-integration/README.md` and trace the flow:

```
Developer → Git push → GitHub Actions → Harbor (image)
                                            ↓
                         Vault (secrets) ← Argo CD → Kubernetes
```

### Step 7.2 — Deploy the Full Stack

```bash
# Ensure secrets are in Vault
kubectl exec -n vault vault-0 -- vault kv put secret/production/myapp/config \
  db_host="postgres.production.svc" \
  db_port="5432" \
  db_name="myapp_production" \
  db_user="prod_user" \
  db_password="production-password"

kubectl exec -n vault vault-0 -- vault kv put secret/production/myapp/api-keys \
  stripe_key="sk_live_prod" \
  sendgrid_key="SG.prod_key" \
  jwt_secret="jwt-signing-key"

# Create the Vault role for this namespace
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/eso-harbor \
  bound_service_account_names=vault-auth-sa \
  bound_service_account_namespaces=production \
  policies=argocd \
  ttl=1h

# Deploy via Argo CD
kubectl apply -f 07-full-integration/argocd-application.yaml

argocd app get full-integration-app
kubectl get all -n production
```

### Step 7.3 — Study the CI Pipeline

Open `07-full-integration/ci-pipeline/github-actions-workflow.yaml` and trace each step:

1. **Build** -- `docker build` using the Dockerfile from `01-harbor-basics/`
2. **Scan** -- Trivy checks for vulnerabilities before pushing
3. **Push** -- `docker push` to Harbor
4. **Update Manifests** -- `kustomize edit set image` changes the tag
5. **Commit** -- Push the updated `kustomization.yaml` to Git
6. **Argo CD Syncs** -- Detects the commit and deploys the new version

### Step 7.4 — Simulate a Deployment

```bash
# Simulate what CI would do — update the image tag
cd 07-full-integration/app-manifests

# "CI" updates the tag to v1.1.0
# (In real life, kustomize CLI does this)
# kustomize edit set image harbor.example.com/my-app/sample-web=harbor.example.com/my-app/sample-web:v1.1.0

# Argo CD would detect this change and sync automatically
```

---

## Cleanup

When you're done practicing:

```bash
# Delete the kind cluster (removes everything)
kind delete cluster --name practice

# Or remove individual components
helm uninstall argocd -n argocd
helm uninstall vault -n vault
helm uninstall harbor -n harbor
helm uninstall external-secrets -n external-secrets
kubectl delete namespace argocd vault harbor my-app production sample-app
```

---

## Practice Exercises

After completing the guided walkthrough, try these on your own:

### Exercise 1: Add a New Secret
1. Store a new secret in Vault at `secret/myapp/redis`
2. Create an ExternalSecret that syncs it to a K8s Secret
3. Reference it in a Deployment as an environment variable

### Exercise 2: Create a New Harbor Project
1. Create a new Harbor project called "frontend"
2. Create a robot account scoped to that project
3. Store the robot credentials in Vault
4. Create an ExternalSecret for the pull credentials

### Exercise 3: Deploy a Helm Chart via Argo CD
1. Find a Helm chart (e.g., bitnami/nginx)
2. Create an Argo CD Application that installs it
3. Override values using a values file from Git

### Exercise 4: Implement Secret Rotation
1. Store a database password in Vault
2. Deploy an app that uses it (via AVP)
3. Rotate the password in Vault
4. Trigger an Argo CD sync and verify the pod picks up the new password

### Exercise 5: Multi-Environment Setup
1. Create Vault paths for `secret/staging/...` and `secret/production/...`
2. Create separate Argo CD Applications for each environment
3. Use Kustomize overlays to differentiate staging vs. production

---

## Troubleshooting

### Harbor pods not starting
```bash
kubectl describe pod -n harbor -l app=harbor
kubectl logs -n harbor -l component=core
```

### Vault is sealed after restart
```bash
# Re-unseal (kind clusters lose state on restart)
VAULT_UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' vault-keys.json)
kubectl exec -n vault vault-0 -- vault operator unseal "$VAULT_UNSEAL_KEY"
```

### Argo CD Application stuck "Progressing"
```bash
argocd app get <app-name> --show-operation
kubectl describe application <app-name> -n argocd
```

### AVP not resolving placeholders
```bash
# Check the AVP sidecar logs
kubectl logs -n argocd deploy/argocd-repo-server -c avp

# Verify the Vault role exists
kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/argocd
```

### ESO ExternalSecret not syncing
```bash
kubectl describe externalsecret <name> -n <namespace>
kubectl logs -n external-secrets deploy/external-secrets
```
