# Hands-On Practice Guide (Step by Step)

Complete lab covering **Harbor, JFrog Artifactory, Vault, Argo CD, and Prometheus + Grafana** on a local kind cluster. Every command is copy-pasteable.

## Time Estimates

| Phase | What You'll Do | Time |
|-------|---------------|------|
| Setup | Install tools, create kind cluster | 15 min |
| Phase 1 | Install Prometheus + Grafana (monitoring) | 10 min |
| Phase 2 | Install Harbor (container registry) | 15 min |
| Phase 3 | Install JFrog Artifactory (package repos) | 15 min |
| Phase 4 | Install Vault (secrets manager) | 15 min |
| Phase 5 | Install Argo CD (GitOps) | 15 min |
| Phase 6 | Integration: Harbor + Argo CD | 15 min |
| Phase 7 | Integration: Vault + Argo CD (AVP) | 20 min |
| Phase 8 | Integration: Vault + Harbor (ESO) | 15 min |
| Phase 9 | Full pipeline simulation | 15 min |
| **Total** | | **~2.5 hours** |

---

## Setup: Prerequisites

### Step 1: Install Docker

```bash
# Check if Docker is installed and running
docker ps

# If not installed (Ubuntu/Debian):
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl start docker
sudo usermod -aG docker $USER
# Log out and back in for group changes to take effect
```

### Step 2: Install kind

```bash
# Linux
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# macOS
brew install kind

# Verify
kind version
```

### Step 3: Install kubectl

```bash
# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# macOS
brew install kubectl

# Verify
kubectl version --client
```

### Step 4: Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
```

### Step 5: Install Argo CD CLI

```bash
# Linux
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# macOS
brew install argocd

# Verify
argocd version --client
```

### Step 6: Install jq and yq

```bash
# jq (JSON processor)
sudo apt-get install -y jq    # Linux
# brew install jq              # macOS

# yq (YAML processor)
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
# brew install yq              # macOS

# Verify
jq --version
yq --version
```

### Step 7: Create the kind Cluster

```bash
cat <<EOF | kind create cluster --name practice --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30002
        hostPort: 30002
      - containerPort: 30003
        hostPort: 30003
      - containerPort: 30080
        hostPort: 30080
      - containerPort: 30443
        hostPort: 30443
      - containerPort: 30030
        hostPort: 30030
      - containerPort: 30082
        hostPort: 30082
    extraMounts:
      - hostPath: /tmp/harbor-data
        containerPath: /harbor-data
EOF
```

### Step 8: Verify the Cluster

```bash
kubectl cluster-info
kubectl get nodes
# Should show one node in Ready status
```

### Step 9: Clone the Repo

```bash
git clone https://github.com/vishehemant/Argo-Harbor-Vault.git
cd Argo-Harbor-Vault
git checkout cursor/harbor-argo-vault-integration-aad0
```

### Step 10: Add All Helm Repos

```bash
helm repo add harbor https://helm.goharbor.io
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add external-secrets https://charts.external-secrets.io
helm repo add jfrog https://charts.jfrog.io
helm repo update
```

**Checkpoint:** All tools installed, cluster running, repo cloned. You're ready to go.

---

## Phase 1: Install Prometheus + Grafana

**Why first?** So we can monitor everything we install after this.

### Step 1.1: Install kube-prometheus-stack

```bash
helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword="admin123" \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30030 \
  --wait --timeout 5m
```

### Step 1.2: Wait for All Pods

```bash
kubectl get pods -n monitoring
# Wait until all pods show Running. This takes 2-3 minutes.
```

### Step 1.3: Access Grafana

```bash
kubectl port-forward svc/kube-prometheus-grafana -n monitoring 3000:80 &
```

Open http://localhost:3000 in your browser.
- **Username:** `admin`
- **Password:** `admin123`

### Step 1.4: Explore Built-in Dashboards

1. Click the hamburger menu (top-left) > **Dashboards**
2. Open **Kubernetes / Compute Resources / Namespace (Pods)**
3. Select namespace `monitoring` from the dropdown
4. You should see CPU and memory usage of the monitoring pods

**Checkpoint:** Grafana is running and showing Kubernetes metrics.

---

## Phase 2: Install Harbor

### Step 2.1: Install Harbor via Helm

```bash
kubectl create namespace harbor

helm install harbor harbor/harbor \
  --namespace harbor \
  -f 01-harbor-basics/harbor-helm-values.yaml \
  --wait --timeout 10m
```

### Step 2.2: Wait for All Pods

```bash
kubectl get pods -n harbor -w
# Wait until ALL pods show Running and Ready
# Press Ctrl+C when done. This takes 3-5 minutes.
```

### Step 2.3: Find the Admin Password

```bash
kubectl get secret -n harbor harbor-core -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d && echo
```

Save this password — you'll need it for login.

### Step 2.4: Access Harbor UI

```bash
# Kill any existing port-forwards on 8080
pkill -f "port-forward.*8080" 2>/dev/null

# Port-forward the nginx gateway service
kubectl port-forward svc/harbor-nginx -n harbor 8080:8443 &
```

Open https://localhost:8080 in your browser (accept the certificate warning).
- **Username:** `admin`
- **Password:** (from Step 2.3)

### Step 2.5: Create a Project

```bash
# Get the password into a variable
HARBOR_PASS=$(kubectl get secret -n harbor harbor-core -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d)

# Create project "my-app" via API
curl -k -u "admin:${HARBOR_PASS}" \
  -X POST "https://localhost:8080/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d '{"project_name":"my-app","public":false,"metadata":{"auto_scan":"true"}}'

# Verify — should see "my-app" in the list
curl -k -u "admin:${HARBOR_PASS}" \
  "https://localhost:8080/api/v2.0/projects" | jq '.[].name'
```

### Step 2.6: Check in the UI

Refresh the Harbor UI. Click **Projects** — you should see `my-app` alongside the default `library` project.

**Checkpoint:** Harbor is running, you can access the UI, and created a project via API.

### What You Learned
- [ ] Harbor runs multiple components (nginx, core, portal, registry, database, redis, trivy)
- [ ] Projects are namespaces for repositories
- [ ] auto_scan means every pushed image gets scanned by Trivy automatically

---

## Phase 3: Install JFrog Artifactory

### Step 3.1: Install JFrog via Helm

```bash
kubectl create namespace jfrog

helm install artifactory jfrog/artifactory \
  --namespace jfrog \
  --set artifactory.admin.password="password" \
  --set nginx.service.type=NodePort \
  --set nginx.service.nodePort=30082 \
  --wait --timeout 10m
```

### Step 3.2: Wait for All Pods

```bash
kubectl get pods -n jfrog -w
# Wait until all pods are Running. JFrog takes 3-5 minutes to start.
# Press Ctrl+C when done.
```

### Step 3.3: Access JFrog UI

```bash
kubectl port-forward svc/artifactory -n jfrog 8082:8082 &
```

Open http://localhost:8082 in your browser.
- **Username:** `admin`
- **Password:** `password`

On first login, JFrog may ask you to set a new password and configure a base URL. You can skip/use defaults for practice.

### Step 3.4: Create Repositories (Private + Public Proxy)

```bash
JFROG_URL="http://localhost:8082"

# Create a LOCAL npm repo (your private packages)
curl -u "admin:password" -X PUT "${JFROG_URL}/artifactory/api/repositories/npm-local" \
  -H "Content-Type: application/json" \
  -d '{"key":"npm-local","rclass":"local","packageType":"npm"}'

# Create a REMOTE npm repo (proxy cache for public npmjs.org)
curl -u "admin:password" -X PUT "${JFROG_URL}/artifactory/api/repositories/npm-remote" \
  -H "Content-Type: application/json" \
  -d '{"key":"npm-remote","rclass":"remote","packageType":"npm","url":"https://registry.npmjs.org"}'

# Create a VIRTUAL npm repo (combines local + remote into one endpoint)
curl -u "admin:password" -X PUT "${JFROG_URL}/artifactory/api/repositories/npm-virtual" \
  -H "Content-Type: application/json" \
  -d '{"key":"npm-virtual","rclass":"virtual","packageType":"npm","repositories":["npm-local","npm-remote"],"defaultDeploymentRepo":"npm-local"}'

echo "npm repos created!"

# Create Docker proxy repo (caches Docker Hub images — avoids rate limits)
curl -u "admin:password" -X PUT "${JFROG_URL}/artifactory/api/repositories/docker-remote" \
  -H "Content-Type: application/json" \
  -d '{"key":"docker-remote","rclass":"remote","packageType":"docker","url":"https://registry-1.docker.io/"}'

echo "Docker proxy repo created!"
```

### Step 3.5: Verify in JFrog UI

1. Click **Administration** > **Repositories**
2. You should see: `npm-local`, `npm-remote`, `npm-virtual`, `docker-remote`

### Step 3.6: Test npm Proxy

```bash
# Configure npm to use JFrog as its registry
npm config set registry http://localhost:8082/artifactory/api/npm/npm-virtual/

# Install a public package through JFrog (first time: fetched from npmjs.org and cached)
npm install lodash --prefix /tmp/test-npm

# Check JFrog UI: Artifacts > npm-remote
# You should see lodash cached there
```

**Checkpoint:** JFrog is running with private and proxy repositories for npm and Docker.

### What You Learned
- [ ] **Local** repos store your private artifacts
- [ ] **Remote** repos proxy and cache public registries (npm, Docker Hub, Maven Central)
- [ ] **Virtual** repos combine local + remote into a single client endpoint
- [ ] This avoids Docker Hub rate limits and gives you full control over dependencies

---

## Phase 4: Install Vault

### Step 4.1: Install Vault via Helm

```bash
kubectl create namespace vault

helm install vault hashicorp/vault \
  --namespace vault \
  -f 02-vault-basics/vault-helm-values.yaml \
  --wait --timeout 5m
```

### Step 4.2: Check Pod Status

```bash
kubectl get pods -n vault
# vault-0 will show Running but NOT Ready (0/1)
# This is expected — Vault is sealed and needs initialization
```

### Step 4.3: Initialize Vault

```bash
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=1 \
  -key-threshold=1 \
  -format=json > vault-keys.json

echo "Vault initialized. Keys saved to vault-keys.json"
```

### Step 4.4: Unseal Vault

```bash
VAULT_UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' vault-keys.json)
kubectl exec -n vault vault-0 -- vault operator unseal "$VAULT_UNSEAL_KEY"
```

### Step 4.5: Verify Unsealed

```bash
kubectl exec -n vault vault-0 -- vault status
# Look for: Sealed = false
```

### Step 4.6: Login and Enable KV v2

```bash
ROOT_TOKEN=$(jq -r '.root_token' vault-keys.json)
echo "Root token: $ROOT_TOKEN"

kubectl exec -n vault vault-0 -- vault login "$ROOT_TOKEN"
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2
```

### Step 4.7: Store Secrets

```bash
# Application database credentials
kubectl exec -n vault vault-0 -- vault kv put secret/myapp/config \
  db_host="postgres.default.svc" \
  db_port="5432" \
  db_name="myapp_db" \
  db_user="myapp" \
  db_password="super-secret-password"

# API keys
kubectl exec -n vault vault-0 -- vault kv put secret/myapp/api-keys \
  stripe_key="sk_test_practice123" \
  sendgrid_key="SG.practice456" \
  redis_url="redis://localhost:6379/0"

# Harbor registry credentials
kubectl exec -n vault vault-0 -- vault kv put secret/harbor/creds \
  url="harbor.example.com" \
  username="robot-ci-pipeline" \
  password="harbor-robot-secret" \
  email="ci@example.com"

# JFrog registry credentials
kubectl exec -n vault vault-0 -- vault kv put secret/jfrog/creds \
  url="jfrog.example.com" \
  username="ci-user" \
  password="jfrog-api-token"
```

### Step 4.8: Read Secrets Back

```bash
# Read all keys
kubectl exec -n vault vault-0 -- vault kv get secret/myapp/config

# Read a single field
kubectl exec -n vault vault-0 -- vault kv get -field=db_password secret/myapp/config
# Should output: super-secret-password
```

### Step 4.9: Create Policies

```bash
# Copy the policy file into the Vault pod
kubectl cp 02-vault-basics/policies/app-read-policy.hcl vault/vault-0:/tmp/app-read-policy.hcl
kubectl cp 02-vault-basics/policies/argocd-policy.hcl vault/vault-0:/tmp/argocd-policy.hcl

# Apply policies
kubectl exec -n vault vault-0 -- vault policy write app-read /tmp/app-read-policy.hcl
kubectl exec -n vault vault-0 -- vault policy write argocd /tmp/argocd-policy.hcl

# Verify
kubectl exec -n vault vault-0 -- vault policy list
```

### Step 4.10: Enable Kubernetes Auth

```bash
kubectl exec -n vault vault-0 -- vault auth enable kubernetes

kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local:443"

# Role for app pods
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/myapp \
  bound_service_account_names=myapp-sa \
  bound_service_account_namespaces=default \
  policies=app-read \
  ttl=1h

# Role for Argo CD (used by AVP in Phase 7)
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/argocd \
  bound_service_account_names=argocd-repo-server \
  bound_service_account_namespaces=argocd \
  policies=argocd \
  ttl=1h
```

### Step 4.11: Access the Vault UI

```bash
kubectl port-forward svc/vault -n vault 8200:8200 &
echo "Root token: $(jq -r '.root_token' vault-keys.json)"
```

Open http://localhost:8200 in your browser. Login with the root token.

Navigate to **Secrets Engines** > **secret/** > **myapp** > **config** to see your stored secrets.

### Step 4.12: Test Access Control

```bash
# Create a token that can ONLY read (not write) secrets
kubectl exec -n vault vault-0 -- vault token create -policy=app-read -format=json > /tmp/app-token.json
APP_TOKEN=$(jq -r '.auth.client_token' /tmp/app-token.json)
echo "Limited token: $APP_TOKEN"

# This works — reading is allowed
kubectl exec -n vault vault-0 -- sh -c "VAULT_TOKEN=$APP_TOKEN vault kv get -field=db_password secret/myapp/config"

# This FAILS — writing is not allowed by the app-read policy
kubectl exec -n vault vault-0 -- sh -c "VAULT_TOKEN=$APP_TOKEN vault kv put secret/myapp/config hacked=true" 2>&1 || echo "EXPECTED: Permission denied!"
```

**Checkpoint:** Vault is running, unsealed, storing secrets, and has Kubernetes auth configured.

### What You Learned
- [ ] Vault must be unsealed before it can serve requests
- [ ] KV v2 engine stores versioned key-value pairs
- [ ] Policies control what a token can access (least privilege)
- [ ] Kubernetes auth lets Pods authenticate with Vault using their ServiceAccount

---

## Phase 5: Install Argo CD

### Step 5.1: Install Argo CD via Helm

```bash
kubectl create namespace argocd

helm install argocd argo/argo-cd \
  --namespace argocd \
  -f 03-argocd-basics/argocd-helm-values.yaml \
  --wait --timeout 5m
```

### Step 5.2: Get the Admin Password

```bash
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "Argo CD password: $ARGOCD_PASS"
```

**Save this password** — you'll use it repeatedly.

### Step 5.3: Access the UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8443:443 &
```

Open https://localhost:8443 (accept the certificate warning).
- **Username:** `admin`
- **Password:** (from Step 5.2)

### Step 5.4: Login via CLI

```bash
argocd login localhost:8443 --username admin --password "$ARGOCD_PASS" --insecure
```

### Step 5.5: Deploy a Sample Application

```bash
kubectl apply -f 03-argocd-basics/argocd-application.yaml
```

### Step 5.6: Watch the Deployment

```bash
# Check status in CLI
argocd app get sample-app

# Watch pods come up
kubectl get pods -n sample-app -w
# Press Ctrl+C when you see 2 pods Running
```

### Step 5.7: Check the Argo CD UI

1. Go to https://localhost:8443
2. You should see the **sample-app** card
3. Click it — see the resource tree: **Application → Deployment → ReplicaSet → 2 Pods**
4. Green = healthy

### Step 5.8: Experiment — Self-Heal

```bash
# Manually scale to 5 replicas (bypassing Git)
kubectl scale deployment sample-web -n sample-app --replicas=5

# Watch Argo CD revert it back to 2 (self-heal kicks in within ~30 seconds)
kubectl get pods -n sample-app -w
# You'll see extra pods Terminating as Argo CD reverts the change
```

### Step 5.9: Experiment — Drift Detection

```bash
# Delete the service
kubectl delete svc sample-web -n sample-app

# Argo CD recreates it automatically
kubectl get svc -n sample-app -w
# The service reappears within seconds
```

**Checkpoint:** Argo CD is deployed, managing a sample app, with auto-sync and self-heal working.

### What You Learned
- [ ] Argo CD watches Git and syncs manifests to the cluster
- [ ] Self-heal reverts manual changes (someone runs kubectl directly)
- [ ] Auto-sync deploys when Git changes
- [ ] The UI shows the full resource tree and health status

---

## Phase 6: Harbor + Argo CD Integration

**Goal:** Deploy an app that pulls its image from a private Harbor registry.

### Step 6.1: Create the Namespace and Pull Secret

```bash
kubectl create namespace my-app 2>/dev/null || true

kubectl create secret docker-registry harbor-pull-secret \
  --docker-server=harbor.example.com \
  --docker-username='robot-ci-pipeline' \
  --docker-password='placeholder-for-practice' \
  --namespace=my-app
```

### Step 6.2: Deploy via Argo CD

```bash
kubectl apply -f 04-harbor-argocd-integration/argocd-application.yaml
argocd app get harbor-sample-app
```

The Deployment will show `ImagePullBackOff` because `harbor.example.com` isn't reachable locally — **this is expected**. The point is to understand the configuration.

### Step 6.3: Study the Key Files

```bash
# See how imagePullSecrets connects to the Harbor credential
cat 04-harbor-argocd-integration/sample-app/deployment.yaml

# See the docker-registry secret structure
cat 04-harbor-argocd-integration/sample-app/image-pull-secret.yaml

# See Argo CD Image Updater annotations
cat 04-harbor-argocd-integration/argocd-application-with-image-updater.yaml
```

**Checkpoint:** You understand how Argo CD deploys from a private Harbor registry.

### What You Learned
- [ ] `imagePullSecrets` tells kubelet which credentials to use when pulling
- [ ] The secret type is `kubernetes.io/dockerconfigjson`
- [ ] Argo CD Image Updater can auto-detect new tags in Harbor

---

## Phase 7: Vault + Argo CD Integration (AVP)

**Goal:** Inject secrets from Vault into Argo CD-managed manifests.

### Step 7.1: Create the AVP Vault Policy

```bash
kubectl cp 02-vault-basics/policies/argocd-policy.hcl vault/vault-0:/tmp/argocd-policy.hcl
kubectl exec -n vault vault-0 -- vault policy write argocd /tmp/argocd-policy.hcl
```

### Step 7.2: Install the AVP Plugin

```bash
# Create the plugin ConfigMap
kubectl apply -f 05-vault-argocd-integration/argocd-vault-plugin/cmp-plugin-configmap.yaml

# Patch the repo-server to add the AVP sidecar
kubectl patch deployment argocd-repo-server -n argocd \
  --patch-file 05-vault-argocd-integration/argocd-vault-plugin/argocd-repo-server-patch.yaml

# Wait for the repo-server to restart
kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=120s
```

### Step 7.3: Verify AVP Is Running

```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server
# Should show 1/1 Running (or 2/2 if sidecar is counted)

# Check AVP sidecar logs
kubectl logs -n argocd deploy/argocd-repo-server -c avp --tail=10
```

### Step 7.4: Ensure Secrets Are in Vault

```bash
kubectl exec -n vault vault-0 -- vault kv get secret/myapp/config
kubectl exec -n vault vault-0 -- vault kv get secret/myapp/api-keys
# You should see the values stored in Phase 4
```

### Step 7.5: Study the Secret Template

```bash
cat 05-vault-argocd-integration/sample-app/secret.yaml
```

Notice the placeholders:
```
DB_PASSWORD: <path:secret/data/myapp/config#db_password>
```

This is **safe in Git** — no real secrets. AVP replaces these at sync time.

### Step 7.6: Deploy via Argo CD

```bash
kubectl apply -f 05-vault-argocd-integration/argocd-application.yaml
argocd app get vault-argocd-demo
```

### Step 7.7: Verify Secrets Were Resolved

```bash
# If AVP is working, the K8s Secret has REAL values from Vault
kubectl get secret myapp-secrets -n vault-argocd-demo -o jsonpath='{.data.DB_PASSWORD}' | base64 -d && echo
# Expected output: super-secret-password

kubectl get secret myapp-secrets -n vault-argocd-demo -o jsonpath='{.data.DB_HOST}' | base64 -d && echo
# Expected output: postgres.default.svc
```

**Checkpoint:** AVP is resolving Vault secrets into Argo CD-managed Kubernetes Secrets.

### What You Learned
- [ ] Manifests in Git contain `<path:...#key>` placeholders, never real secrets
- [ ] AVP runs as a sidecar on the repo-server
- [ ] AVP authenticates with Vault using Kubernetes ServiceAccount auth
- [ ] Placeholders are resolved at sync time, not at commit time

---

## Phase 8: Harbor + Vault Integration (ESO)

**Goal:** Use External Secrets Operator to dynamically create Harbor pull secrets from Vault.

### Step 8.1: Install External Secrets Operator

```bash
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --wait --timeout 5m
```

### Step 8.2: Verify ESO Is Running

```bash
kubectl get pods -n external-secrets
# All pods should be Running
```

### Step 8.3: Create the SecretStore

```bash
# Ensure namespace and ServiceAccount exist
kubectl create namespace my-app 2>/dev/null || true

kubectl apply -f 06-harbor-vault-integration/external-secrets/secret-store.yaml
```

### Step 8.4: Check SecretStore Status

```bash
kubectl get secretstore -n my-app
# STATUS should show: Valid
```

### Step 8.5: Create the ExternalSecret for Harbor Creds

```bash
kubectl apply -f 06-harbor-vault-integration/external-secrets/external-secret-harbor-creds.yaml
```

### Step 8.6: Verify the K8s Secret Was Created

```bash
# Check ExternalSecret status
kubectl get externalsecret harbor-pull-secret -n my-app
# STATUS should show: SecretSynced

# Check the created K8s Secret
kubectl get secret harbor-pull-secret -n my-app
# TYPE should be: kubernetes.io/dockerconfigjson

# Decode and view the contents
kubectl get secret harbor-pull-secret -n my-app \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .
# You should see the Harbor credentials from Vault
```

### Step 8.7: Test Secret Rotation

```bash
# Change the password in Vault
kubectl exec -n vault vault-0 -- vault kv put secret/harbor/creds \
  url="harbor.example.com" \
  username="robot-ci-pipeline" \
  password="ROTATED-new-password-2026" \
  email="ci@example.com"

# Force ESO to re-sync (instead of waiting 1 hour)
kubectl annotate externalsecret harbor-pull-secret -n my-app \
  force-sync=$(date +%s) --overwrite

# Wait a few seconds, then check the secret
sleep 5
kubectl get secret harbor-pull-secret -n my-app \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .password
# Should show: ROTATED-new-password-2026
```

**Checkpoint:** ESO creates and rotates Kubernetes Secrets from Vault automatically.

### What You Learned
- [ ] ESO runs as a controller that syncs external secrets into K8s Secrets
- [ ] SecretStore defines HOW to connect to Vault
- [ ] ExternalSecret defines WHAT to sync and in what format
- [ ] Secret rotation: update Vault → ESO syncs → K8s Secret is updated

---

## Phase 9: Full Pipeline Simulation

**Goal:** Simulate the entire flow: build image → update Helm values → Argo CD syncs.

### Step 9.1: Store Per-Environment Secrets in Vault

```bash
for ENV in dev uat prod; do
  kubectl exec -n vault vault-0 -- vault kv put "secret/${ENV}/myapp/config" \
    db_host="postgres.myapp-${ENV}.svc" \
    db_port="5432" \
    db_name="myapp_${ENV}" \
    db_user="${ENV}_user" \
    db_password="${ENV}-password-2026"
done

# Verify
kubectl exec -n vault vault-0 -- vault kv get secret/dev/myapp/config
kubectl exec -n vault vault-0 -- vault kv get secret/prod/myapp/config
```

### Step 9.2: Review the Helm Chart

```bash
# See the chart structure
ls 08-real-world-setup/helm-chart/
ls 08-real-world-setup/helm-chart/templates/
ls 08-real-world-setup/helm-chart/values/

# See how secret.yaml uses vaultPathPrefix from values
cat 08-real-world-setup/helm-chart/templates/secret.yaml

# See per-environment differences
diff 08-real-world-setup/helm-chart/values/dev.yaml 08-real-world-setup/helm-chart/values/prod.yaml
```

### Step 9.3: Review the Argo CD Applications

```bash
cat 08-real-world-setup/argocd-multi-env/argocd-apps-helm.yaml
```

Notice:
- `myapp-dev` has `automated` sync policy (auto-deploy)
- `myapp-uat` has NO automated sync (manual trigger after approval)
- `myapp-prod` has NO automated sync (manual trigger during change window)

### Step 9.4: Simulate "CI Updates the Image Tag"

```bash
# This is what Azure Pipeline does:
cd 08-real-world-setup/helm-chart
yq e '.image.tag = "v2.0.0"' -i values/dev.yaml

# See the change
cat values/dev.yaml | head -10

# Commit (simulating what CI does)
cd ../..
git add 08-real-world-setup/helm-chart/values/dev.yaml
git commit -m "ci(dev): update image to v2.0.0"
```

### Step 9.5: Review the Azure Pipeline

```bash
cat 08-real-world-setup/azure-pipelines/azure-pipelines-helm.yaml
```

Trace the flow:
1. **Build stage** → builds image, Trivy scan, pushes to Harbor
2. **Dev stage** → `yq` updates `values/dev.yaml` → auto-deploy
3. **UAT stage** → approval gate → `yq` updates `values/uat.yaml` → manual sync
4. **Prod stage** → approval gate → `yq` updates `values/prod.yaml` → manual sync

### Step 9.6: Review the Monitoring Stack

```bash
# See what gets monitored
cat 09-complete-lab/monitoring/prometheus/service-monitors-all.yaml

# See the alert rules
cat 08-real-world-setup/monitoring/prometheus/alert-rules.yaml
```

Key alerts:
- **ArgoCDSyncFailed** → sync broken for 5 min
- **VaultSealed** → critical, pager alert
- **HarborCriticalVulnerabilities** → images with critical CVEs
- **PodCrashLooping** → app pods restarting

**Checkpoint:** You understand the full end-to-end pipeline: Azure Pipelines → Harbor (images) + JFrog (dependencies) → Vault (secrets) → Argo CD (deploy) → Prometheus + Grafana (monitor).

---

## Cleanup

```bash
# Delete the entire kind cluster (removes everything)
kind delete cluster --name practice

# Reset npm registry (if you changed it in Phase 3)
npm config delete registry
```

---

## Troubleshooting Quick Reference

| Problem | Fix |
|---------|-----|
| `connection refused` on kubectl | `kind export kubeconfig --name practice` |
| Vault is sealed after restart | `kubectl exec -n vault vault-0 -- vault operator unseal $(jq -r '.unseal_keys_b64[0]' vault-keys.json)` |
| Harbor password not working | `kubectl get secret -n harbor harbor-core -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' \| base64 -d` |
| Argo CD app stuck `Unknown` | Check `targetRevision` matches your branch: `cursor/harbor-argo-vault-integration-aad0` |
| AVP not resolving placeholders | `kubectl logs -n argocd deploy/argocd-repo-server -c avp --tail=20` |
| ESO ExternalSecret not syncing | `kubectl describe externalsecret <name> -n <namespace>` |
| Port-forward died | Re-run the `kubectl port-forward` command for that service |
| `helm install` name already in use | Use `helm upgrade` instead, or `helm uninstall <name> -n <namespace>` first |
| Pods stuck `Pending` | `kubectl describe pod <name> -n <namespace>` — likely insufficient resources |
