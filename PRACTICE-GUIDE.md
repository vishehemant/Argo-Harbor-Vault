# Hands-On Practice Guide (Step by Step)

Complete lab covering **Harbor, JFrog Artifactory, Vault, Argo CD, and Prometheus + Grafana** on a local kind cluster. Every command is copy-pasteable, and every step explains **why** you're running it.

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

> **Why?** Docker is the container runtime. kind uses Docker to run Kubernetes nodes as containers on your laptop, and we need it to build images later.

```bash
# Check if Docker is already installed and the daemon is running
docker ps

# If not installed (Ubuntu/Debian):
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl start docker
sudo usermod -aG docker $USER
# Log out and back in for the group change to take effect
```

### Step 2: Install kind

> **Why?** kind (Kubernetes in Docker) creates a lightweight, disposable Kubernetes cluster on your laptop. It's the fastest way to get a real cluster running for practice without needing cloud infrastructure.

```bash
# Linux — download the kind binary
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# macOS
brew install kind

# Verify the installation worked
kind version
```

### Step 3: Install kubectl

> **Why?** kubectl is the standard CLI for interacting with Kubernetes. Every command that talks to the cluster (creating namespaces, deploying apps, checking pod status) goes through kubectl.

```bash
# Linux — download the latest stable kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# macOS
brew install kubectl

# Verify — should show the client version
kubectl version --client
```

### Step 4: Install Helm

> **Why?** Helm is the package manager for Kubernetes (like apt for Ubuntu or brew for macOS). Instead of writing dozens of YAML files to install Harbor/Vault/Argo CD, Helm packages them into "charts" that you install with a single command. Almost every tool in this lab is installed via Helm.

```bash
# Downloads and runs the official Helm installer script
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
```

### Step 5: Install Argo CD CLI

> **Why?** The Argo CD CLI lets you manage applications, trigger syncs, check status, and perform rollbacks from the terminal. While the web UI is great for visualization, the CLI is what you'd use in scripts and automation.

```bash
# Linux — download the argocd binary
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# macOS
brew install argocd

# Verify — should show the client version
argocd version --client
```

### Step 6: Install jq and yq

> **Why?** `jq` processes JSON output (we use it to extract Vault tokens and keys from JSON responses). `yq` processes YAML (our CI pipeline uses it to update image tags in Helm values files). Both are essential for scripting.

```bash
# jq — JSON processor
sudo apt-get install -y jq    # Linux
# brew install jq              # macOS

# yq — YAML processor (used by Azure Pipeline to update Helm values)
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
# brew install yq              # macOS

# Verify both are installed
jq --version
yq --version
```

### Step 7: Create the kind Cluster

> **Why?** This creates a Kubernetes cluster with specific port mappings. The `extraPortMappings` section maps container ports to your laptop's ports so you can access Harbor UI (8080), Argo CD UI (8443), Grafana (3000), etc. from your browser. Without these mappings, the services would only be reachable from inside the cluster.

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

> **Why?** This confirms the cluster is running and kubectl can connect to it. If this fails, nothing else will work.

```bash
# Shows the cluster API server address — confirms the cluster is up
kubectl cluster-info

# Lists all nodes — you should see one "control-plane" node in "Ready" status
kubectl get nodes
```

### Step 9: Clone the Repo

> **Why?** This repo contains all the Helm values files, Kubernetes manifests, scripts, and Argo CD Application definitions we'll use throughout the lab. We checkout the specific branch that has all the examples.

```bash
git clone https://github.com/vishehemant/Argo-Harbor-Vault.git
cd Argo-Harbor-Vault
git checkout cursor/harbor-argo-vault-integration-aad0
```

### Step 10: Add All Helm Repos

> **Why?** Helm charts are hosted in remote repositories (like npm packages on npmjs.org). Before you can install a chart, you must tell Helm where to find it. Each `helm repo add` command registers a chart repository. `helm repo update` downloads the latest chart index from each repo.

```bash
helm repo add harbor https://helm.goharbor.io              # Harbor chart
helm repo add hashicorp https://helm.releases.hashicorp.com # Vault chart
helm repo add argo https://argoproj.github.io/argo-helm     # Argo CD chart
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts  # Prometheus + Grafana
helm repo add external-secrets https://charts.external-secrets.io  # External Secrets Operator
helm repo add jfrog https://charts.jfrog.io                 # JFrog Artifactory chart
helm repo update                                             # Download latest chart indexes
```

**Checkpoint:** All tools installed, cluster running, repo cloned. You're ready to go.

---

## Phase 1: Install Prometheus + Grafana

> **Why install monitoring first?** Prometheus scrapes metrics from everything running in the cluster. By installing it before Harbor, Vault, and Argo CD, we ensure that when those tools come online, Prometheus is already there to capture their metrics from the very beginning. Grafana gives us dashboards to visualize those metrics.

### Step 1.1: Install kube-prometheus-stack

> **Why this chart?** `kube-prometheus-stack` is a single Helm chart that installs Prometheus (metrics collection), Grafana (dashboards), Alertmanager (alert routing), and pre-built dashboards for Kubernetes. It's the standard way to set up monitoring in Kubernetes.

```bash
helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword="admin123" \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30030 \
  --wait --timeout 5m
```

> `--namespace monitoring` — installs everything in a dedicated namespace (keeps monitoring separate from app workloads).
> `--create-namespace` — creates the "monitoring" namespace if it doesn't exist.
> `--set grafana.adminPassword` — sets the Grafana login password.
> `--wait` — Helm waits until all pods are running before returning.

### Step 1.2: Wait for All Pods

> **Why check?** Helm's `--wait` usually handles this, but it's good practice to verify. The prometheus-stack deploys ~10 pods (prometheus, grafana, alertmanager, node-exporter, kube-state-metrics, operators). All must be running before we proceed.

```bash
kubectl get pods -n monitoring
# Wait until all pods show Running. This takes 2-3 minutes.
```

### Step 1.3: Access Grafana

> **Why port-forward?** The Grafana service is running inside the Kubernetes cluster. Port-forwarding creates a tunnel from your laptop's port 3000 to the service's port 80, letting your browser reach it.

```bash
kubectl port-forward svc/kube-prometheus-grafana -n monitoring 3000:80 &
```

> The `&` at the end runs it in the background so you can continue using the terminal.

Open http://localhost:3000 in your browser.
- **Username:** `admin`
- **Password:** `admin123`

### Step 1.4: Explore Built-in Dashboards

> **Why explore now?** These dashboards show cluster-level metrics (CPU, memory, network) that will become useful when we deploy Harbor, Vault, and Argo CD. You'll see their resource usage appear in these dashboards as we install them.

1. Click the hamburger menu (top-left) > **Dashboards**
2. Open **Kubernetes / Compute Resources / Namespace (Pods)**
3. Select namespace `monitoring` from the dropdown
4. You should see CPU and memory usage of the monitoring pods

**Checkpoint:** Grafana is running and showing Kubernetes metrics.

---

## Phase 2: Install Harbor

> **Why Harbor?** Harbor is your private container registry — like a private Docker Hub. In a real company, you don't push your application images to Docker Hub (public, rate-limited, no control). Harbor gives you vulnerability scanning, access control, and image signing — all within your own infrastructure.

### Step 2.1: Install Harbor via Helm

> **Why use a values file?** The values file (`harbor-helm-values.yaml`) customizes how Harbor is installed — what ports to use, how much storage to allocate, whether to enable Trivy scanning, etc. Without it, you'd get Harbor's defaults which may not match your needs.

```bash
# Create a dedicated namespace to keep Harbor's pods organized separately
kubectl create namespace harbor

# Install Harbor using our custom configuration
helm install harbor harbor/harbor \
  --namespace harbor \
  -f 01-harbor-basics/harbor-helm-values.yaml \
  --wait --timeout 10m
```

> `-f 01-harbor-basics/harbor-helm-values.yaml` — points to our custom values file that configures ports, storage sizes, Trivy scanning, and resource limits.
> `--timeout 10m` — Harbor has many components and takes a while to start.

### Step 2.2: Wait for All Pods

> **Why watch?** Harbor runs 9 pods (nginx, core, portal, registry, database, redis, jobservice, trivy, exporter). If any pod is stuck (CrashLoopBackOff, Pending), the UI won't work. The `-w` flag watches in real-time.

```bash
kubectl get pods -n harbor -w
# Wait until ALL pods show Running and Ready
# Press Ctrl+C when done. This takes 3-5 minutes.
```

### Step 2.3: Find the Admin Password

> **Why not just use "Harbor12345"?** While that's the default, Helm may store a different password in the Kubernetes Secret. Reading it from the Secret ensures you always get the actual password the system is using. This technique works for any Helm-installed app.

```bash
# The admin password is stored as a base64-encoded Secret in Kubernetes
# We extract it and decode it
kubectl get secret -n harbor harbor-core -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d && echo
```

> `jsonpath` extracts a specific field from the Secret. `base64 -d` decodes it because Kubernetes stores Secret values in base64.

Save this password — you'll need it for login.

### Step 2.4: Access Harbor UI

> **Why port-forward to harbor-nginx and not harbor-portal?** Harbor's nginx component is the main gateway — it routes traffic to the correct backend (portal for UI, core for API, registry for Docker pushes). Port-forwarding directly to the portal would skip authentication and API routing.

```bash
# Kill any existing port-forwards on 8080 to avoid conflicts
pkill -f "port-forward.*8080" 2>/dev/null

# Create a tunnel from localhost:8080 to Harbor's nginx service (HTTPS port 8443)
kubectl port-forward svc/harbor-nginx -n harbor 8080:8443 &
```

Open https://localhost:8080 in your browser (accept the certificate warning).
- **Username:** `admin`
- **Password:** (from Step 2.3)

### Step 2.5: Create a Project

> **Why create a project?** In Harbor, a "project" is like a namespace for Docker images. All images in our app (backend, frontend, worker) go under the `my-app` project. Setting `auto_scan: true` means every image pushed to this project will automatically be scanned for vulnerabilities — no manual trigger needed.

```bash
# Store the password in a variable so we don't have to type it repeatedly
HARBOR_PASS=$(kubectl get secret -n harbor harbor-core -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d)

# Call Harbor's REST API to create a new project
# -k = skip TLS verification (self-signed cert in our lab)
# -X POST = HTTP POST method (creating a resource)
curl -k -u "admin:${HARBOR_PASS}" \
  -X POST "https://localhost:8080/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d '{"project_name":"my-app","public":false,"metadata":{"auto_scan":"true"}}'

# Verify the project was created by listing all projects
curl -k -u "admin:${HARBOR_PASS}" \
  "https://localhost:8080/api/v2.0/projects" | jq '.[].name'
```

> `"public": false` — only authenticated users can pull images from this project. In production, this prevents unauthorized access.
> `"auto_scan": "true"` — Harbor runs Trivy on every pushed image automatically.

### Step 2.6: Check in the UI

Refresh the Harbor UI. Click **Projects** — you should see `my-app` alongside the default `library` project.

**Checkpoint:** Harbor is running, you can access the UI, and created a project via API.

### What You Learned
- [ ] Harbor runs multiple components (nginx, core, portal, registry, database, redis, trivy)
- [ ] Projects are namespaces for repositories
- [ ] auto_scan means every pushed image gets scanned by Trivy automatically

---

## Phase 3: Install JFrog Artifactory

> **Why JFrog when we already have Harbor?** Harbor handles Docker images. But your build needs more than Docker images — it needs npm packages, Maven JARs, Python packages, Go modules, etc. JFrog is a **universal artifact manager** that handles all of these. It also acts as a **proxy cache** for public registries like Docker Hub, npmjs.org, and Maven Central — avoiding rate limits and giving you control over which dependencies enter your build.

### Step 3.1: Install JFrog via Helm

> **Why these settings?** `NodePort` exposes JFrog on a fixed port so we can access the UI from the browser. The admin password is set for practice only — in production, you'd use a strong password stored in Vault.

```bash
# Create a dedicated namespace for JFrog
kubectl create namespace jfrog

# Install JFrog Artifactory OSS (open-source edition)
helm install artifactory jfrog/artifactory \
  --namespace jfrog \
  --set artifactory.admin.password="password" \
  --set nginx.service.type=NodePort \
  --set nginx.service.nodePort=30082 \
  --wait --timeout 10m
```

### Step 3.2: Wait for All Pods

> **Why does JFrog take so long?** JFrog runs a database, a web server, and the main Artifactory service. On first start, it initializes the database schema and configures default repositories. This is a one-time cost.

```bash
kubectl get pods -n jfrog -w
# Wait until all pods are Running. JFrog takes 3-5 minutes to start.
# Press Ctrl+C when done.
```

### Step 3.3: Access JFrog UI

> **Why port-forward?** Same reason as Harbor — the JFrog service is inside the cluster. Port-forwarding makes it accessible from your browser.

```bash
kubectl port-forward svc/artifactory -n jfrog 8082:8082 &
```

Open http://localhost:8082 in your browser.
- **Username:** `admin`
- **Password:** `password`

On first login, JFrog may ask you to set a new password and configure a base URL. You can skip/use defaults for practice.

### Step 3.4: Create Repositories (Private + Public Proxy)

> **Why three repos for each package type?** This is JFrog's "local + remote + virtual" pattern:
> - **Local** = your team's private packages (things you build and publish)
> - **Remote** = a proxy that caches public packages from npmjs.org/Docker Hub/Maven Central. First request goes to the internet; subsequent requests are served from cache.
> - **Virtual** = a single URL that checks local first, then remote. Your developers configure ONE registry URL and get both private and public packages.
>
> This pattern gives you: caching (faster builds), availability (works if npmjs.org is down), security (you control what enters your builds), and simplicity (one URL for developers).

```bash
JFROG_URL="http://localhost:8082"

# Create a LOCAL npm repo — stores packages your team publishes privately
curl -u "admin:password" -X PUT "${JFROG_URL}/artifactory/api/repositories/npm-local" \
  -H "Content-Type: application/json" \
  -d '{"key":"npm-local","rclass":"local","packageType":"npm"}'

# Create a REMOTE npm repo — proxies and caches packages from the public npmjs.org
# When someone runs "npm install lodash", JFrog fetches it from npmjs.org
# and caches it locally. Next time anyone needs lodash, it's served from cache.
curl -u "admin:password" -X PUT "${JFROG_URL}/artifactory/api/repositories/npm-remote" \
  -H "Content-Type: application/json" \
  -d '{"key":"npm-remote","rclass":"remote","packageType":"npm","url":"https://registry.npmjs.org"}'

# Create a VIRTUAL npm repo — combines local + remote into a single endpoint
# Developers point their npm config here and get both private + public packages
curl -u "admin:password" -X PUT "${JFROG_URL}/artifactory/api/repositories/npm-virtual" \
  -H "Content-Type: application/json" \
  -d '{"key":"npm-virtual","rclass":"virtual","packageType":"npm","repositories":["npm-local","npm-remote"],"defaultDeploymentRepo":"npm-local"}'

echo "npm repos created!"

# Create a Docker proxy repo — caches Docker Hub images to avoid rate limits
# Docker Hub limits free users to 100 pulls per 6 hours. By proxying through
# JFrog, all your CI jobs share one cache instead of each hitting Docker Hub.
curl -u "admin:password" -X PUT "${JFROG_URL}/artifactory/api/repositories/docker-remote" \
  -H "Content-Type: application/json" \
  -d '{"key":"docker-remote","rclass":"remote","packageType":"docker","url":"https://registry-1.docker.io/"}'

echo "Docker proxy repo created!"
```

### Step 3.5: Verify in JFrog UI

1. Click **Administration** (gear icon) > **Repositories**
2. You should see: `npm-local`, `npm-remote`, `npm-virtual`, `docker-remote`

### Step 3.6: Test npm Proxy

> **Why test this?** To prove that JFrog is actually proxying and caching. When you `npm install lodash`, JFrog fetches it from npmjs.org, caches it, and serves it. The second time (or for any other developer), it's served instantly from JFrog's cache.

```bash
# Tell npm to use JFrog instead of going directly to npmjs.org
npm config set registry http://localhost:8082/artifactory/api/npm/npm-virtual/

# Install a public package — JFrog fetches it from npmjs.org and caches it
npm install lodash --prefix /tmp/test-npm

# Check JFrog UI: go to Artifacts > npm-remote
# You should see lodash cached there — future installs will be served from cache
```

**Checkpoint:** JFrog is running with private and proxy repositories for npm and Docker.

### What You Learned
- [ ] **Local** repos store your private artifacts
- [ ] **Remote** repos proxy and cache public registries (npm, Docker Hub, Maven Central)
- [ ] **Virtual** repos combine local + remote into a single client endpoint
- [ ] This avoids Docker Hub rate limits and gives you full control over dependencies

---

## Phase 4: Install Vault

> **Why Vault?** In Kubernetes, secrets (database passwords, API keys) are typically stored as base64-encoded Kubernetes Secrets — **not encrypted**. Anyone with cluster access can decode them. Vault provides real encryption (AES-256), access control (policies), audit logging (who accessed what, when), and dynamic secrets (generate temporary database credentials on demand). In this lab, Vault is the **single source of truth** for all credentials.

### Step 4.1: Install Vault via Helm

> **Why use a values file?** Our values file configures Vault for practice — single-node mode, file-based storage, UI enabled. In production, you'd configure HA mode with 3-5 replicas and Raft consensus storage.

```bash
# Create a dedicated namespace for Vault
kubectl create namespace vault

# Install Vault using our configuration
helm install vault hashicorp/vault \
  --namespace vault \
  -f 02-vault-basics/vault-helm-values.yaml \
  --wait --timeout 5m
```

### Step 4.2: Check Pod Status

> **Why is vault-0 not Ready?** Vault starts in a "sealed" state by design. When sealed, Vault's encryption key is split and locked — it can't serve any requests. This is a security feature: if someone steals the Vault storage, they can't read anything without the unseal keys. We need to initialize and unseal it first.

```bash
kubectl get pods -n vault
# vault-0 will show Running but NOT Ready (0/1)
# This is expected — Vault is sealed and needs initialization
```

### Step 4.3: Initialize Vault

> **Why initialize?** Initialization happens only once per Vault cluster. It generates:
> 1. **Unseal keys** — cryptographic keys needed to unlock (unseal) Vault
> 2. **Root token** — the all-powerful admin token
>
> We use `-key-shares=1 -key-threshold=1` for practice (one key to unseal). In production, you'd use 5 shares with a threshold of 3 (Shamir's Secret Sharing) — meaning 3 of 5 key holders must cooperate to unseal Vault.

```bash
# Initialize Vault and save the output (unseal key + root token) to a JSON file
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=1 \
  -key-threshold=1 \
  -format=json > vault-keys.json

echo "Vault initialized. Keys saved to vault-keys.json"
echo "IMPORTANT: In production, distribute unseal keys to separate trusted people!"
```

### Step 4.4: Unseal Vault

> **Why unseal?** After initialization (or after a restart), Vault is sealed. The unseal key decrypts Vault's master key, which in turn decrypts all the stored secrets. Without unsealing, Vault refuses all requests. Think of it like unlocking a safe — you need the combination before you can access the contents.

```bash
# Extract the unseal key from the JSON file we saved
VAULT_UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' vault-keys.json)

# Send the unseal key to Vault
kubectl exec -n vault vault-0 -- vault operator unseal "$VAULT_UNSEAL_KEY"
```

### Step 4.5: Verify Unsealed

> **Why verify?** To confirm Vault is ready to accept requests. If "Sealed" is still true, something went wrong with the unseal key.

```bash
kubectl exec -n vault vault-0 -- vault status
# Look for: Sealed = false
# Also note: Initialized = true
```

### Step 4.6: Login and Enable KV v2

> **Why login?** Vault requires authentication before any operation. The root token (from initialization) has unlimited permissions — like being root on Linux. We use it here for setup; in production, you'd create scoped tokens and avoid using root.
>
> **Why enable KV v2?** By default, Vault has no secrets engines enabled. KV v2 (Key-Value version 2) is the most common engine — it stores arbitrary key-value pairs with versioning (you can roll back to a previous version of a secret).

```bash
# Extract the root token from the saved file
ROOT_TOKEN=$(jq -r '.root_token' vault-keys.json)
echo "Root token: $ROOT_TOKEN"

# Authenticate with Vault using the root token
kubectl exec -n vault vault-0 -- vault login "$ROOT_TOKEN"

# Enable the KV v2 secrets engine at the path "secret/"
# This creates a "database" for storing key-value secrets
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2
```

### Step 4.7: Store Secrets

> **Why store these specific secrets?** These represent the real secrets an application needs:
> - **Database credentials** — the app needs to connect to PostgreSQL
> - **API keys** — the app calls Stripe for payments and SendGrid for emails
> - **Harbor credentials** — Kubernetes needs these to pull Docker images from Harbor
> - **JFrog credentials** — CI needs these to download build dependencies
>
> In a real system, these would NEVER be in Git or plain Kubernetes Secrets — only in Vault.

```bash
# Application database credentials — used by the app to connect to PostgreSQL
kubectl exec -n vault vault-0 -- vault kv put secret/myapp/config \
  db_host="postgres.default.svc" \
  db_port="5432" \
  db_name="myapp_db" \
  db_user="myapp" \
  db_password="super-secret-password"

# External API keys — used by the app for payment processing and email
kubectl exec -n vault vault-0 -- vault kv put secret/myapp/api-keys \
  stripe_key="sk_test_practice123" \
  sendgrid_key="SG.practice456" \
  redis_url="redis://localhost:6379/0"

# Harbor registry credentials — used by Kubernetes to pull private Docker images
kubectl exec -n vault vault-0 -- vault kv put secret/harbor/creds \
  url="harbor.example.com" \
  username="robot-ci-pipeline" \
  password="harbor-robot-secret" \
  email="ci@example.com"

# JFrog credentials — used by CI pipelines to download build dependencies
kubectl exec -n vault vault-0 -- vault kv put secret/jfrog/creds \
  url="jfrog.example.com" \
  username="ci-user" \
  password="jfrog-api-token"
```

### Step 4.8: Read Secrets Back

> **Why read them back?** To confirm the write was successful and to practice the read syntax. In production, you'd read secrets programmatically (via API) from your applications.

```bash
# Read all fields at a path — shows a table of all key-value pairs
kubectl exec -n vault vault-0 -- vault kv get secret/myapp/config

# Read a single field — useful in scripts when you need just one value
kubectl exec -n vault vault-0 -- vault kv get -field=db_password secret/myapp/config
# Should output: super-secret-password
```

### Step 4.9: Create Policies

> **Why policies?** Policies implement the **principle of least privilege**. Without policies, anyone with a Vault token could read ALL secrets. Policies restrict what paths a token can access:
> - `app-read` — allows reading only `secret/data/myapp/*` (for application pods)
> - `argocd` — allows reading all secrets under `secret/data/*` (for the AVP plugin to resolve any placeholder)
>
> We copy the policy files into the Vault pod because `vault policy write` reads from the local filesystem inside the pod.

```bash
# Copy policy files from our repo into the Vault pod's /tmp directory
kubectl cp 02-vault-basics/policies/app-read-policy.hcl vault/vault-0:/tmp/app-read-policy.hcl
kubectl cp 02-vault-basics/policies/argocd-policy.hcl vault/vault-0:/tmp/argocd-policy.hcl

# Register the policies with Vault
kubectl exec -n vault vault-0 -- vault policy write app-read /tmp/app-read-policy.hcl
kubectl exec -n vault vault-0 -- vault policy write argocd /tmp/argocd-policy.hcl

# List all policies to confirm they were created
kubectl exec -n vault vault-0 -- vault policy list
# Should show: app-read, argocd, default, root
```

### Step 4.10: Enable Kubernetes Auth

> **Why Kubernetes auth?** This is the crucial integration between Vault and Kubernetes. It allows Pods to authenticate with Vault using their ServiceAccount token — no passwords or API keys needed.
>
> **How it works:**
> 1. A Pod has a Kubernetes ServiceAccount (e.g., `argocd-repo-server`)
> 2. Kubernetes automatically mounts a JWT token for that ServiceAccount into the Pod
> 3. The Pod sends that JWT to Vault
> 4. Vault calls the Kubernetes API to verify the JWT is valid
> 5. If valid, Vault issues a time-limited Vault token with the policy attached to that role
>
> **Why two roles?**
> - `myapp` role — for application pods that need to read their own secrets
> - `argocd` role — for the Argo Vault Plugin sidecar that needs to resolve secret placeholders

```bash
# Enable the Kubernetes auth method in Vault
kubectl exec -n vault vault-0 -- vault auth enable kubernetes

# Tell Vault how to reach the Kubernetes API server (for token validation)
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local:443"

# Create a role for application pods:
# "Any Pod using ServiceAccount 'myapp-sa' in the 'default' namespace
#  gets a Vault token with the 'app-read' policy, valid for 1 hour"
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/myapp \
  bound_service_account_names=myapp-sa \
  bound_service_account_namespaces=default \
  policies=app-read \
  ttl=1h

# Create a role for Argo CD's repo-server (used by AVP in Phase 7):
# "Any Pod using ServiceAccount 'argocd-repo-server' in 'argocd' namespace
#  gets a Vault token with the 'argocd' policy"
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/argocd \
  bound_service_account_names=argocd-repo-server \
  bound_service_account_namespaces=argocd \
  policies=argocd \
  ttl=1h
```

### Step 4.11: Access the Vault UI

> **Why use the UI?** The UI provides a visual way to browse secrets, see policy details, and check auth methods. It's especially useful when learning — you can click through the secret paths instead of memorizing CLI commands.

```bash
kubectl port-forward svc/vault -n vault 8200:8200 &
echo "Root token: $(jq -r '.root_token' vault-keys.json)"
```

Open http://localhost:8200 in your browser. Login with the root token.

Navigate to **Secrets Engines** > **secret/** > **myapp** > **config** to see your stored secrets.

### Step 4.12: Test Access Control

> **Why test this?** To prove that policies actually work. We create a token scoped to the `app-read` policy and show that it can read secrets but CANNOT write them. This is the core of Vault's security model — even if an attacker compromises an app pod, they can only read their own secrets, not modify them or access other paths.

```bash
# Create a token that is restricted to ONLY the app-read policy
kubectl exec -n vault vault-0 -- vault token create -policy=app-read -format=json > /tmp/app-token.json
APP_TOKEN=$(jq -r '.auth.client_token' /tmp/app-token.json)
echo "Limited token: $APP_TOKEN"

# TEST 1: Reading is allowed by app-read policy ✅
kubectl exec -n vault vault-0 -- sh -c "VAULT_TOKEN=$APP_TOKEN vault kv get -field=db_password secret/myapp/config"

# TEST 2: Writing is NOT allowed — the policy only grants "read" and "list" ❌
kubectl exec -n vault vault-0 -- sh -c "VAULT_TOKEN=$APP_TOKEN vault kv put secret/myapp/config hacked=true" 2>&1 || echo "EXPECTED: Permission denied! (This proves the policy works)"
```

**Checkpoint:** Vault is running, unsealed, storing secrets, and has Kubernetes auth configured with proper access control.

### What You Learned
- [ ] Vault must be unsealed before it can serve requests (security feature)
- [ ] KV v2 engine stores versioned key-value pairs
- [ ] Policies control what a token can access (principle of least privilege)
- [ ] Kubernetes auth lets Pods authenticate with Vault using their ServiceAccount — no passwords needed

---

## Phase 5: Install Argo CD

> **Why Argo CD?** Traditional deployments use "push-based" CI/CD — the CI pipeline runs `kubectl apply` and pushes changes to the cluster. The problem: if someone runs `kubectl edit` directly on the cluster, the cluster drifts from what's in Git and nobody knows. Argo CD flips this to "pull-based" — it continuously watches Git and ensures the cluster matches Git. If someone makes a manual change, Argo CD detects the drift and can automatically revert it. **Git becomes the single source of truth.**

### Step 5.1: Install Argo CD via Helm

> **Why use a values file?** Our values file configures the server to run with `--insecure` (no TLS internally, since we're in a lab), sets up NodePort access, and configures RBAC. In production, you'd enable TLS and integrate with your company's SSO.

```bash
# Create a dedicated namespace for Argo CD
kubectl create namespace argocd

# Install Argo CD
helm install argocd argo/argo-cd \
  --namespace argocd \
  -f 03-argocd-basics/argocd-helm-values.yaml \
  --wait --timeout 5m
```

### Step 5.2: Get the Admin Password

> **Why does Argo CD generate a random password?** For security — using a default password (like "admin") would be a vulnerability. Argo CD generates a random password and stores it as a Kubernetes Secret. We extract and decode it the same way we did for Harbor.

```bash
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "Argo CD password: $ARGOCD_PASS"
```

**Save this password** — you'll use it repeatedly.

### Step 5.3: Access the UI

> **Why port 8443?** Argo CD serves its UI over HTTPS (port 443 inside the cluster). We forward our local port 8443 to the service's port 443. Using 8443 (instead of 443) avoids needing root privileges on your laptop.

```bash
kubectl port-forward svc/argocd-server -n argocd 8443:443 &
```

Open https://localhost:8443 (accept the certificate warning).
- **Username:** `admin`
- **Password:** (from Step 5.2)

### Step 5.4: Login via CLI

> **Why login via CLI too?** The CLI is how you'd interact with Argo CD in scripts and automation. `--insecure` skips TLS verification (our lab uses a self-signed certificate).

```bash
argocd login localhost:8443 --username admin --password "$ARGOCD_PASS" --insecure
```

### Step 5.5: Deploy a Sample Application

> **Why `kubectl apply`?** The Application CRD is Argo CD's core resource — it tells Argo CD: "Watch this Git repo at this path and deploy its manifests to this namespace." We create it with `kubectl apply` because Argo CD itself IS the deployment tool — we just need to tell it what to manage.

```bash
# This creates an Argo CD Application that watches our Git repo
# and deploys the sample-app manifests to the "sample-app" namespace
kubectl apply -f 03-argocd-basics/argocd-application.yaml
```

### Step 5.6: Watch the Deployment

> **Why check both CLI and pods?** The Argo CD CLI shows the sync status (Synced/OutOfSync) and health (Healthy/Degraded). Watching pods shows the actual containers starting. Together, they give you the full picture.

```bash
# Check Argo CD's view of the application
argocd app get sample-app

# Watch the actual pods being created by Argo CD in the target namespace
kubectl get pods -n sample-app -w
# Press Ctrl+C when you see 2 pods Running
```

### Step 5.7: Check the Argo CD UI

1. Go to https://localhost:8443
2. You should see the **sample-app** card
3. Click it — see the resource tree: **Application → Deployment → ReplicaSet → 2 Pods**
4. Green = healthy

### Step 5.8: Experiment — Self-Heal

> **Why test self-heal?** This is one of Argo CD's most powerful features. Imagine a developer runs `kubectl scale` directly on the cluster at 3 AM to "fix" a performance issue. Without self-heal, the cluster would drift from Git and nobody would know. With self-heal, Argo CD notices the change and reverts it — Git always wins.

```bash
# Manually scale to 5 replicas — this bypasses Git entirely
kubectl scale deployment sample-web -n sample-app --replicas=5

# Watch Argo CD revert it back to 2 replicas (defined in Git)
# Self-heal kicks in within ~30 seconds
kubectl get pods -n sample-app -w
# You'll see 3 extra pods appear briefly, then Terminate as Argo CD reverts
```

### Step 5.9: Experiment — Drift Detection

> **Why delete a service?** To prove that Argo CD monitors ALL resources defined in Git, not just Deployments. If any resource is manually deleted, Argo CD recreates it. This is the "desired state" model — Git says "a Service should exist," so Argo CD ensures it does.

```bash
# Delete the service manually
kubectl delete svc sample-web -n sample-app

# Argo CD detects the missing resource and recreates it automatically
kubectl get svc -n sample-app -w
# The service reappears within seconds
```

**Checkpoint:** Argo CD is deployed, managing a sample app, with auto-sync and self-heal working.

### What You Learned
- [ ] Argo CD watches Git and syncs manifests to the cluster (pull-based GitOps)
- [ ] Self-heal reverts manual changes — Git is always the source of truth
- [ ] Auto-sync deploys automatically when Git changes
- [ ] The UI shows the full resource tree with health status

---

## Phase 6: Harbor + Argo CD Integration

> **Why integrate them?** In the real world, your Docker images live in a private Harbor registry (not Docker Hub). Kubernetes needs credentials to pull those images, and Argo CD needs to deploy Deployments that reference Harbor URLs. This phase connects them.

### Step 6.1: Create the Namespace and Pull Secret

> **Why an image pull secret?** When Kubernetes tries to pull `harbor.example.com/my-app/sample-web:v1.0.0`, Harbor says "who are you?" The pull secret provides the answer — it's a Kubernetes Secret containing Docker registry credentials that the kubelet uses automatically.

```bash
# Create the namespace (idempotent — won't fail if it already exists)
kubectl create namespace my-app 2>/dev/null || true

# Create a docker-registry type secret with Harbor robot account credentials
# In production, these credentials come from Vault via ESO (Phase 8)
kubectl create secret docker-registry harbor-pull-secret \
  --docker-server=harbor.example.com \
  --docker-username='robot-ci-pipeline' \
  --docker-password='placeholder-for-practice' \
  --namespace=my-app
```

### Step 6.2: Deploy via Argo CD

> **Why deploy via Argo CD instead of `kubectl apply`?** This is GitOps in action — we create an Argo CD Application that points to the manifests in Git. Argo CD reads the Deployment (which references a Harbor image and the pull secret) and applies it to the cluster. If someone modifies the Deployment manually, Argo CD reverts it.

```bash
kubectl apply -f 04-harbor-argocd-integration/argocd-application.yaml
argocd app get harbor-sample-app
```

The Deployment will show `ImagePullBackOff` because `harbor.example.com` isn't reachable locally — **this is expected**. The point is to understand the configuration.

### Step 6.3: Study the Key Files

> **Why study the files?** Understanding the YAML is more important than running the commands. These files show how Harbor and Argo CD connect — the Deployment references the Harbor image URL, the pull secret provides credentials, and the Image Updater annotations automate tag updates.

```bash
# 1. See how the Deployment references a Harbor image and links to the pull secret
cat 04-harbor-argocd-integration/sample-app/deployment.yaml
# Key lines: imagePullSecrets, image: harbor.example.com/my-app/sample-web:v1.0.0

# 2. See the docker-registry secret structure (the credential format Kubernetes expects)
cat 04-harbor-argocd-integration/sample-app/image-pull-secret.yaml
# Key: type is kubernetes.io/dockerconfigjson with auths block

# 3. See how Argo CD Image Updater can auto-detect new tags in Harbor
cat 04-harbor-argocd-integration/argocd-application-with-image-updater.yaml
# Key: annotations starting with argocd-image-updater.argoproj.io/
```

**Checkpoint:** You understand how Argo CD deploys from a private Harbor registry.

### What You Learned
- [ ] `imagePullSecrets` in a Pod spec tells kubelet which credentials to use when pulling
- [ ] The secret type `kubernetes.io/dockerconfigjson` stores registry credentials
- [ ] Argo CD Image Updater watches Harbor for new tags and auto-updates the Application

---

## Phase 7: Vault + Argo CD Integration (AVP)

> **Why this integration?** This solves the biggest challenge in GitOps: **secrets should not be stored in Git**, but Argo CD reads everything from Git. The Argo Vault Plugin (AVP) bridges this gap — you put placeholders like `<path:secret/data/myapp/config#db_password>` in your YAML files in Git (safe to commit), and AVP replaces them with real values from Vault at sync time. Secrets never touch Git.

### Step 7.1: Create the AVP Vault Policy

> **Why a separate policy?** The `argocd` policy grants read access to all secret paths under `secret/data/*`. This is broader than the `app-read` policy because AVP needs to resolve placeholders for ANY secret path referenced in the manifests. We use the file copy approach because heredocs don't work through `kubectl exec`.

```bash
# Copy the policy file into the Vault pod
kubectl cp 02-vault-basics/policies/argocd-policy.hcl vault/vault-0:/tmp/argocd-policy.hcl

# Register the policy with Vault
kubectl exec -n vault vault-0 -- vault policy write argocd /tmp/argocd-policy.hcl
```

### Step 7.2: Install the AVP Plugin

> **Why three steps?**
> 1. **ConfigMap** — defines how AVP processes manifests (what commands to run, how to discover files)
> 2. **Patch** — adds AVP as a sidecar container to the Argo CD repo-server. The repo-server normally just renders Helm/Kustomize; the patch adds AVP processing as a second step.
> 3. **Wait** — the repo-server pod restarts with the new sidecar; we wait for it to be ready.

```bash
# Step 1: Create the ConfigMap that defines the AVP plugin behavior
kubectl apply -f 05-vault-argocd-integration/argocd-vault-plugin/cmp-plugin-configmap.yaml

# Step 2: Add the AVP sidecar container to the repo-server Deployment
# This modifies the existing Deployment to include an init container
# (downloads AVP binary) and a sidecar container (runs AVP)
kubectl patch deployment argocd-repo-server -n argocd \
  --patch-file 05-vault-argocd-integration/argocd-vault-plugin/argocd-repo-server-patch.yaml

# Step 3: Wait for the repo-server to restart with the new AVP sidecar
kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=120s
```

### Step 7.3: Verify AVP Is Running

> **Why check the logs?** If AVP failed to start (wrong Vault address, binary not found), it will show in the logs. The pod might show Running but AVP could be crashing internally.

```bash
# Check the pod is running
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server

# Check AVP sidecar logs for errors
kubectl logs -n argocd deploy/argocd-repo-server -c avp --tail=10
```

### Step 7.4: Ensure Secrets Are in Vault

> **Why verify now?** AVP will try to read these paths when we deploy the app. If the secrets don't exist, AVP will fail with "secret not found" and the sync will error out. Better to verify now than debug later.

```bash
kubectl exec -n vault vault-0 -- vault kv get secret/myapp/config
kubectl exec -n vault vault-0 -- vault kv get secret/myapp/api-keys
# You should see the values stored in Phase 4
```

### Step 7.5: Study the Secret Template

> **Why is this the key file?** This is where the magic happens. The file looks like a normal Kubernetes Secret, but the VALUES are AVP placeholders, not real secrets. This file is **100% safe to commit to Git** — it contains zero sensitive data.

```bash
cat 05-vault-argocd-integration/sample-app/secret.yaml
```

Notice the placeholders — this is what's stored in Git:
```
DB_PASSWORD: <path:secret/data/myapp/config#db_password>
```

What AVP produces at sync time (applied to the cluster):
```
DB_PASSWORD: super-secret-password
```

### Step 7.6: Deploy via Argo CD

> **Why use `plugin: argocd-vault-plugin`?** Normally, Argo CD applies manifests as-is. The `plugin` field tells Argo CD: "Don't apply these directly — run them through the AVP plugin first." AVP then authenticates with Vault, resolves all placeholders, and returns the final manifests with real secret values.

```bash
kubectl apply -f 05-vault-argocd-integration/argocd-application.yaml
argocd app get vault-argocd-demo
```

### Step 7.7: Verify Secrets Were Resolved

> **Why decode the Secret?** The Kubernetes Secret in the cluster should now contain REAL values from Vault, not the `<path:...>` placeholders. If you see real values, it proves the entire chain worked: Argo CD → AVP → Vault (K8s auth) → secret read → placeholder replaced → Secret created in cluster.

```bash
# Decode the DB_PASSWORD field from the K8s Secret
kubectl get secret myapp-secrets -n vault-argocd-demo -o jsonpath='{.data.DB_PASSWORD}' | base64 -d && echo
# Expected output: super-secret-password

kubectl get secret myapp-secrets -n vault-argocd-demo -o jsonpath='{.data.DB_HOST}' | base64 -d && echo
# Expected output: postgres.default.svc
```

**Checkpoint:** AVP is resolving Vault secrets into Argo CD-managed Kubernetes Secrets.

### What You Learned
- [ ] Manifests in Git contain `<path:...#key>` placeholders — safe to commit, no real secrets
- [ ] AVP runs as a sidecar on the repo-server (intercepts manifests before they're applied)
- [ ] AVP authenticates with Vault using the repo-server's Kubernetes ServiceAccount (no passwords)
- [ ] Placeholders are resolved at **sync time**, not at commit time

---

## Phase 8: Harbor + Vault Integration (ESO)

> **Why ESO?** In Phase 6, we manually created the Harbor pull secret with `kubectl create secret`. That means credentials are either hardcoded in a YAML file (insecure) or created manually (not reproducible). The External Secrets Operator (ESO) solves this — it watches Vault for changes and automatically creates/updates Kubernetes Secrets. When you rotate the Harbor robot account password in Vault, ESO automatically updates the pull secret. Zero manual steps.

### Step 8.1: Install External Secrets Operator

> **Why a separate operator?** ESO runs as a Kubernetes controller (like Argo CD). It watches `ExternalSecret` CRDs and syncs the referenced secrets from Vault (or AWS Secrets Manager, Azure Key Vault, etc.) into native Kubernetes Secrets. It's the bridge between Vault and Kubernetes.

```bash
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --wait --timeout 5m
```

### Step 8.2: Verify ESO Is Running

```bash
kubectl get pods -n external-secrets
# 3 pods should be Running: controller, webhook, cert-controller
```

### Step 8.3: Create the SecretStore

> **Why a SecretStore?** The SecretStore tells ESO HOW to connect to Vault — the server URL, which auth method to use, and which ServiceAccount to authenticate with. It's created once per namespace (or once per cluster as a ClusterSecretStore).

```bash
kubectl create namespace my-app 2>/dev/null || true
kubectl apply -f 06-harbor-vault-integration/external-secrets/secret-store.yaml
```

### Step 8.4: Check SecretStore Status

> **Why check status?** If the SecretStore can't connect to Vault (wrong URL, auth failure), it will show an error here. Catching it now saves debugging later.

```bash
kubectl get secretstore -n my-app
# STATUS should show: Valid
# If it shows anything else, run: kubectl describe secretstore vault-backend -n my-app
```

### Step 8.5: Create the ExternalSecret for Harbor Creds

> **Why an ExternalSecret?** This CRD tells ESO WHAT to sync — which Vault path to read from, what Kubernetes Secret to create, and in what format. Our ExternalSecret reads `secret/harbor/creds` from Vault and creates a `kubernetes.io/dockerconfigjson` Secret (the format Kubernetes needs for image pull credentials).

```bash
kubectl apply -f 06-harbor-vault-integration/external-secrets/external-secret-harbor-creds.yaml
```

### Step 8.6: Verify the K8s Secret Was Created

> **Why three checks?** Each shows a different layer:
> 1. ExternalSecret status → confirms ESO synced successfully
> 2. Secret existence → confirms the K8s Secret was created
> 3. Decoded content → confirms it has the correct credentials from Vault

```bash
# Check 1: Did ESO sync successfully?
kubectl get externalsecret harbor-pull-secret -n my-app
# STATUS should show: SecretSynced

# Check 2: Does the K8s Secret exist?
kubectl get secret harbor-pull-secret -n my-app
# TYPE should be: kubernetes.io/dockerconfigjson

# Check 3: Does it contain the right credentials from Vault?
kubectl get secret harbor-pull-secret -n my-app \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .
# You should see harbor.example.com with the credentials stored in Vault
```

### Step 8.7: Test Secret Rotation

> **Why test rotation?** This is the key benefit of ESO over static secrets. In production, when you rotate a Harbor robot account password, you update it in Vault once, and ESO propagates it to every namespace that needs it. No manual `kubectl delete/create secret` needed. This simulates that flow.

```bash
# Step 1: "Rotate" the password in Vault (simulates a credential rotation)
kubectl exec -n vault vault-0 -- vault kv put secret/harbor/creds \
  url="harbor.example.com" \
  username="robot-ci-pipeline" \
  password="ROTATED-new-password-2026" \
  email="ci@example.com"

# Step 2: Force ESO to re-sync immediately (default interval is 1 hour)
# The annotation change triggers an immediate reconciliation
kubectl annotate externalsecret harbor-pull-secret -n my-app \
  force-sync=$(date +%s) --overwrite

# Step 3: Wait a few seconds for ESO to process, then check
sleep 5
kubectl get secret harbor-pull-secret -n my-app \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .
# The password should now show: ROTATED-new-password-2026
```

**Checkpoint:** ESO creates and rotates Kubernetes Secrets from Vault automatically.

### What You Learned
- [ ] ESO runs as a controller that continuously syncs external secrets into K8s Secrets
- [ ] SecretStore defines HOW to connect to Vault (URL, auth method, ServiceAccount)
- [ ] ExternalSecret defines WHAT to sync (which path, which keys, what format)
- [ ] Secret rotation: update in Vault → ESO syncs → K8s Secret is updated automatically

---

## Phase 9: Full Pipeline Simulation

> **Why simulate the full pipeline?** Phases 1-8 installed and configured each tool individually. Now we connect them end-to-end to understand how a real deployment flows: developer pushes code → Azure Pipeline builds and pushes to Harbor → pipeline updates Helm values in Git → Argo CD syncs with secrets from Vault → Kubernetes pulls image from Harbor → Prometheus monitors everything.

### Step 9.1: Store Per-Environment Secrets in Vault

> **Why per-environment?** In production, dev/UAT/prod use different database servers, different API keys, and different credentials. Storing them at separate Vault paths (`secret/dev/`, `secret/uat/`, `secret/prod/`) with separate policies ensures that the dev environment can NEVER accidentally read production secrets.

```bash
# Create secrets for each environment at isolated Vault paths
for ENV in dev uat prod; do
  kubectl exec -n vault vault-0 -- vault kv put "secret/${ENV}/myapp/config" \
    db_host="postgres.myapp-${ENV}.svc" \
    db_port="5432" \
    db_name="myapp_${ENV}" \
    db_user="${ENV}_user" \
    db_password="${ENV}-password-2026"
done

# Verify — notice each environment has different credentials
kubectl exec -n vault vault-0 -- vault kv get secret/dev/myapp/config
kubectl exec -n vault vault-0 -- vault kv get secret/prod/myapp/config
```

### Step 9.2: Review the Helm Chart

> **Why Helm?** Instead of maintaining separate YAML files for each environment, we have ONE Helm chart with templates, and per-environment values files that override settings. The `secret.yaml` template is the key — it uses `{{ .Values.vaultPathPrefix }}` so each environment reads from its own Vault path.

```bash
# See the chart structure — same templates, different values per environment
ls 08-real-world-setup/helm-chart/
ls 08-real-world-setup/helm-chart/templates/
ls 08-real-world-setup/helm-chart/values/

# THE KEY FILE: see how secret.yaml uses vaultPathPrefix from values
# When deployed for prod, it becomes: <path:secret/data/prod/myapp/config#db_password>
# When deployed for dev, it becomes:  <path:secret/data/dev/myapp/config#db_password>
cat 08-real-world-setup/helm-chart/templates/secret.yaml

# Compare dev vs prod — notice different replicas, resources, and Vault paths
diff 08-real-world-setup/helm-chart/values/dev.yaml 08-real-world-setup/helm-chart/values/prod.yaml
```

### Step 9.3: Review the Argo CD Applications

> **Why three Applications?** Each Application points to the same Helm chart but uses a DIFFERENT values file. The sync policy is the critical difference — dev auto-syncs (fast iteration), but UAT and prod require manual sync (change management compliance).

```bash
cat 08-real-world-setup/argocd-multi-env/argocd-apps-helm.yaml
```

Notice:
- `myapp-dev` has `automated` sync policy → deploys immediately when Git changes
- `myapp-uat` has NO `automated` → shows "OutOfSync" but waits for manual `argocd app sync myapp-uat`
- `myapp-prod` has NO `automated` → shows "OutOfSync" until approved change window

### Step 9.4: Simulate "CI Updates the Image Tag"

> **Why is this important?** This is what the Azure Pipeline does in the real world. After building and pushing a new Docker image to Harbor, the pipeline uses `yq` to update `image.tag` in the values file and commits to Git. Argo CD then detects the commit and deploys the new version. We're doing this manually to understand the flow.

```bash
# This is exactly what the Azure Pipeline "DeployDev" stage does:
# Update the image tag in the dev values file
cd 08-real-world-setup/helm-chart
yq e '.image.tag = "v2.0.0"' -i values/dev.yaml

# See the change — image.tag should now be "v2.0.0"
cat values/dev.yaml | head -10

# Commit — just like the pipeline would
cd ../..
git add 08-real-world-setup/helm-chart/values/dev.yaml
git commit -m "ci(dev): update image to v2.0.0"
```

### Step 9.5: Review the Azure Pipeline

> **Why review instead of run?** You can't run Azure Pipelines locally. But reading the YAML and understanding each stage is critical for interviews and real-world setup. Trace the flow — see how each stage has its own approval gate and updates a different values file.

```bash
cat 08-real-world-setup/azure-pipelines/azure-pipelines-helm.yaml
```

Trace the flow:
1. **Build stage** → `docker build`, Trivy vulnerability scan, `docker push` to Harbor
2. **Dev stage** → `yq` updates `values/dev.yaml` with new tag → commit → auto-deploy by Argo CD
3. **UAT stage** → ⏸️ waits for change manager approval → `yq` updates `values/uat.yaml` → manual Argo CD sync
4. **Prod stage** → ⏸️ waits for change manager approval → `yq` updates `values/prod.yaml` → manual Argo CD sync during change window

### Step 9.6: Review the Monitoring Stack

> **Why review monitoring?** In production, you need to know immediately when: a deployment fails, Vault becomes sealed, a critical CVE is found in Harbor, or pods are crash-looping. These alert rules and service monitors make that possible.

```bash
# ServiceMonitors: tell Prometheus WHERE to scrape metrics
# Each tool (Argo CD, Harbor, Vault, JFrog) exposes a /metrics endpoint
cat 09-complete-lab/monitoring/prometheus/service-monitors-all.yaml

# Alert Rules: tell Prometheus WHEN to fire alerts
cat 08-real-world-setup/monitoring/prometheus/alert-rules.yaml
```

Key alerts:
- **ArgoCDSyncFailed** → Argo CD failed to sync for 5 minutes → Slack notification
- **VaultSealed** → Vault is sealed → PagerDuty P1 (ops team paged immediately)
- **HarborCriticalVulnerabilities** → images with critical CVEs → block deployment
- **PodCrashLooping** → app pods restarting repeatedly → Slack notification

**Checkpoint:** You understand the full end-to-end pipeline: Azure Pipelines → Harbor (images) + JFrog (dependencies) → Vault (secrets) → Argo CD (deploy) → Prometheus + Grafana (monitor).

---

## Cleanup

```bash
# Delete the entire kind cluster — removes everything in one command
kind delete cluster --name practice

# Reset npm registry (if you changed it in Phase 3)
npm config delete registry
```

---

## Troubleshooting Quick Reference

| Problem | Why It Happens | Fix |
|---------|---------------|-----|
| `connection refused` on kubectl | kind cluster stopped or kubeconfig not set | `kind export kubeconfig --name practice` |
| Vault is sealed after restart | kind clusters lose state on restart; Vault seals itself | `kubectl exec -n vault vault-0 -- vault operator unseal $(jq -r '.unseal_keys_b64[0]' vault-keys.json)` |
| Harbor password not working | You may be using the wrong password | `kubectl get secret -n harbor harbor-core -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' \| base64 -d` |
| Argo CD app stuck `Unknown` | App points to `main` branch but examples are on feature branch | Check `targetRevision` matches: `cursor/harbor-argo-vault-integration-aad0` |
| AVP not resolving placeholders | AVP can't reach Vault or authenticate | `kubectl logs -n argocd deploy/argocd-repo-server -c avp --tail=20` |
| ESO ExternalSecret not syncing | SecretStore can't connect to Vault | `kubectl describe externalsecret <name> -n <namespace>` |
| Port-forward died | Background process was killed or terminal closed | Re-run the `kubectl port-forward` command for that service |
| `helm install` name already in use | Helm release already exists from a previous attempt | `helm upgrade <name>` instead, or `helm uninstall <name> -n <namespace>` first |
| Pods stuck `Pending` | Not enough CPU/memory on the kind node | `kubectl describe pod <name> -n <namespace>` — check the Events section |
| `heredoc` fails with kubectl exec | Bash heredoc doesn't pass through kubectl correctly | Copy the file into the pod first: `kubectl cp file.hcl vault/vault-0:/tmp/file.hcl` |
