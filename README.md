# Tetris — End-to-End Kubernetes DevSecOps CI/CD Pipeline

A **playable Tetris game** deployed through a production-grade DevSecOps pipeline using **GitHub, Azure Pipelines, Harbor, JFrog, Trivy, Docker, Kubernetes, Argo CD, Helm, Prometheus, and Grafana**.

The Docker image is **built once** in the CI pipeline and **promoted unchanged** through dev → UAT → prod environments with approval gates.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                          DEVELOPER WORKFLOW                           │
│  Developer ──► Git push ──► Pull Request ──► Merge to main           │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ triggers
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│                      AZURE PIPELINE (CI/CD)                           │
│                                                                       │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────────────┐  │
│  │ ESLint   │──►│ Trivy FS │──►│ Docker   │──►│ Trivy Image Scan │  │
│  │ (lint)   │   │ (secrets │   │ Build    │   │ (CRITICAL,HIGH)  │  │
│  │          │   │  + vuln) │   │          │   │ blocks if found  │  │
│  └──────────┘   └──────────┘   └──────────┘   └────────┬─────────┘  │
│                                                          │            │
│                                              ┌───────────┤            │
│                                              ▼           ▼            │
│                                        ┌──────────┐ ┌──────────┐     │
│                                        │  Harbor   │ │  JFrog   │     │
│                                        │ (private  │ │ (npm,    │     │
│                                        │  images)  │ │  Docker  │     │
│                                        │ +auto-scan│ │  proxy)  │     │
│                                        └──────────┘ └──────────┘     │
│                                                                       │
│  SAME IMAGE promoted through environments:                            │
│  ┌──────────┐     ┌───────────────┐     ┌──────────────────────┐     │
│  │   DEV    │────►│     UAT       │────►│     PRODUCTION       │     │
│  │  (auto)  │     │  (approval)   │     │  (approval + change  │     │
│  │          │     │              │     │   window)             │     │
│  └────┬─────┘     └──────┬───────┘     └──────────┬────────────┘     │
│       │                  │                         │                  │
└───────┼──────────────────┼─────────────────────────┼──────────────────┘
        │                  │                         │
        ▼                  ▼                         ▼
   yq updates         yq updates                yq updates
   values/dev/        values/uat/               values/prod/
   values.yaml        values.yaml               values.yaml
        │                  │                         │
        └──────────────────┼─────────────────────────┘
                           │ Git commit
                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                        GIT REPOSITORY                                 │
│                                                                       │
│  helm-chart/                                                          │
│    ├── templates/          (shared Deployment, Service, Ingress...)   │
│    └── values/                                                        │
│        ├── dev/values.yaml   (image.tag updated by pipeline)          │
│        ├── uat/values.yaml                                            │
│        └── prod/values.yaml                                           │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ watches
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│                      ARGO CD (GitOps)                                 │
│                                                                       │
│  tetris-dev   (auto-sync — deploys when Git changes)                 │
│  tetris-uat   (manual sync — after change manager approval)          │
│  tetris-prod  (manual sync — during approved change window)          │
│                                                                       │
│  helm template + values ──► Kubernetes manifests ──► apply            │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ deploys
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│                      KUBERNETES CLUSTER                               │
│                                                                       │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────┐             │
│  │ tetris-dev  │  │ tetris-uat  │  │   tetris-prod    │             │
│  │  1 replica  │  │  2 replicas │  │  3 replicas + HPA│             │
│  └─────────────┘  └─────────────┘  └──────────────────┘             │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │  Prometheus ──► scrapes metrics ──► Grafana (dashboards)        │ │
│  │  Alertmanager ──► fires alerts ──► Slack / PagerDuty            │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

## Tools & Their Roles

| Tool | Role | Why We Need It |
|------|------|---------------|
| **GitHub** | Source code repository | Version control, pull requests, code review |
| **Azure Pipelines** | CI/CD orchestration | Builds, tests, scans, promotes through environments with approval gates |
| **Docker** | Containerization | Packages the app + nginx into a portable, reproducible image |
| **Trivy** | Security scanning | Scans source code for secrets, Docker images for CVEs — blocks critical vulnerabilities |
| **Harbor** | Private container registry | Stores Docker images with auto-scan, RBAC, vulnerability blocking |
| **JFrog** | Artifact repository | Proxy-caches public packages (npm, Docker Hub) — avoids rate limits, controls dependencies |
| **Helm** | Kubernetes package manager | Templates Kubernetes manifests with per-environment values |
| **Argo CD** | GitOps deployment | Watches Git, syncs to cluster. Dev=auto, UAT/Prod=manual (change management) |
| **Kubernetes** | Container orchestration | Runs the app with scaling, self-healing, rolling updates |
| **Prometheus** | Metrics collection | Scrapes metrics from Argo CD, Harbor, JFrog, and app pods |
| **Grafana** | Dashboards & visualization | Displays deployment status, vulnerability counts, resource usage |
| **Alertmanager** | Alert routing | Sends alerts for sync failures, critical CVEs, pod crashes |

## Project Structure

```
.
├── README.md                                  # This file — architecture, steps, production notes
├── app/                                       # Tetris game source code
│   ├── index.html                             # Game UI
│   ├── style.css                              # Dark theme styling
│   ├── tetris.js                              # Game logic (10×20 board, 7 pieces, scoring)
│   └── nginx/
│       └── default.conf                       # Nginx: static files + /health + /api/info + /metrics
├── docker/
│   ├── Dockerfile                             # Multi-stage build: alpine → nginx (non-root)
│   └── .dockerignore
├── helm-chart/                                # Kubernetes deployment (Helm)
│   ├── Chart.yaml
│   ├── values.yaml                            # Defaults
│   ├── values/
│   │   ├── dev/values.yaml                    # Dev: 1 replica, small resources
│   │   ├── uat/values.yaml                    # UAT: 2 replicas, moderate resources
│   │   └── prod/values.yaml                   # Prod: 3 replicas, HPA 3-10, TLS
│   └── templates/
│       ├── deployment.yaml, service.yaml, ingress.yaml, hpa.yaml, configmap.yaml
│       └── _helpers.tpl
├── azure-pipelines/
│   └── azure-pipelines.yaml                   # Full DevSecOps pipeline (5 stages)
├── argocd/
│   └── applications.yaml                      # 3 Argo CD apps (dev/uat/prod)
├── harbor/scripts/
│   └── setup-harbor.sh                        # Create Harbor project + robot account
├── jfrog/scripts/
│   └── setup-jfrog.sh                         # Create JFrog repos (npm, Docker, Helm)
├── monitoring/
│   ├── prometheus/
│   │   ├── kube-prometheus-values.yaml        # Prometheus + Grafana Helm values
│   │   ├── service-monitors.yaml              # Scrape targets for ArgoCD, Harbor, JFrog
│   │   └── alert-rules.yaml                   # Alerts for sync failures, CVEs, pod crashes
│   └── grafana/
│       └── tetris-dashboard.json              # Import-ready Grafana dashboard
├── trivy/
│   └── trivy-config.yaml                      # Trivy scan configuration
├── scripts/
│   └── install-tools.sh                       # Install all CLI tools (kind, kubectl, helm, etc.)
└── docs/                                      # Additional documentation
```

---

## End-to-End Steps: Practice Guide

### Prerequisites

| Requirement | Why |
|-------------|-----|
| Docker installed | kind runs K8s nodes as Docker containers; we build images with Docker |
| 8 GB RAM free | Harbor, JFrog, Prometheus, Argo CD all run simultaneously |
| Linux or macOS | Windows users: use WSL2 |

### Step 1: Install All CLI Tools

> **Why?** These are the CLIs you'll use throughout the lab. kind creates the cluster, kubectl talks to it, Helm installs charts, argocd manages GitOps apps, jq/yq process JSON/YAML.

```bash
# Clone the repo
git clone https://github.com/vishehemant/Argo-Harbor-Vault.git
cd Argo-Harbor-Vault
git checkout cursor/harbor-argo-vault-integration-aad0

# Install tools (or run scripts/install-tools.sh)
# kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Argo CD CLI
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 && chmod +x /usr/local/bin/argocd

# jq + yq
sudo apt-get install -y jq
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq
```

### Step 2: Create the Kubernetes Cluster

> **Why kind?** Runs a real K8s cluster inside Docker. `extraPortMappings` let your browser reach services (Harbor, Grafana, Argo CD) running inside the cluster.

```bash
cat <<EOF | kind create cluster --name tetris --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30080
        hostPort: 30080
      - containerPort: 30443
        hostPort: 30443
      - containerPort: 30030
        hostPort: 30030
EOF

kubectl cluster-info
kubectl get nodes
```

### Step 3: Add Helm Repos

> **Why?** Helm charts are hosted remotely. `helm repo add` tells Helm where to find each chart.

```bash
helm repo add harbor https://helm.goharbor.io
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add jfrog https://charts.jfrog.io
helm repo update
```

### Step 4: Install Prometheus + Grafana

> **Why first?** Install monitoring before other tools so Prometheus captures metrics from the moment they start.

```bash
helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f monitoring/prometheus/kube-prometheus-values.yaml \
  --wait --timeout 5m

# Access Grafana
kubectl port-forward svc/kube-prometheus-grafana -n monitoring 3000:80 &
# Open http://localhost:3000 — Login: admin / prom-operator
```

### Step 5: Install Harbor

> **Why Harbor?** Private Docker registry with auto vulnerability scanning. Every pushed image is scanned by Trivy. Critical CVEs can block pulls.

```bash
kubectl create namespace harbor
helm install harbor harbor/harbor --namespace harbor \
  --set expose.type=nodePort --set expose.tls.enabled=false \
  --set externalURL=http://localhost:30002 \
  --set harborAdminPassword=Harbor12345 \
  --set trivy.enabled=true \
  --wait --timeout 10m

# Wait for all pods
kubectl get pods -n harbor -w

# Get admin password
HARBOR_PASS=$(kubectl get secret -n harbor harbor-core -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d)
echo "Harbor password: $HARBOR_PASS"

# Create the "tetris" project
kubectl port-forward svc/harbor-nginx -n harbor 8080:8443 &
sleep 3
curl -k -u "admin:${HARBOR_PASS}" -X POST "https://localhost:8080/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d '{"project_name":"tetris","public":false,"metadata":{"auto_scan":"true"}}'
```

### Step 6: Install JFrog Artifactory

> **Why JFrog?** Proxy-caches public registries (Docker Hub, npmjs.org). Avoids rate limits, gives you control over which dependencies enter your build. Also stores private packages.

```bash
kubectl create namespace jfrog
helm install artifactory jfrog/artifactory --namespace jfrog \
  --set artifactory.admin.password=password \
  --wait --timeout 10m

# Access JFrog UI
kubectl port-forward svc/artifactory -n jfrog 8082:8082 &
# http://localhost:8082 — admin / password

# Create repositories (run after JFrog is ready)
bash jfrog/scripts/setup-jfrog.sh
```

### Step 7: Install Argo CD

> **Why Argo CD?** GitOps tool that watches this Git repo. When the Azure Pipeline updates `values/dev/values.yaml` with a new image tag, Argo CD detects the commit and deploys the new version. Dev auto-syncs; UAT/Prod require manual sync (change management).

```bash
kubectl create namespace argocd
helm install argocd argo/argo-cd --namespace argocd \
  --set server.service.type=NodePort --set server.service.nodePortHttps=30443 \
  --set server.extraArgs="{--insecure}" \
  --wait --timeout 5m

# Get password
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "Argo CD password: $ARGOCD_PASS"

# Access UI
kubectl port-forward svc/argocd-server -n argocd 8443:443 &
# https://localhost:8443 — admin / <password above>

# Login CLI
argocd login localhost:8443 --username admin --password "$ARGOCD_PASS" --insecure
```

### Step 8: Build the Tetris Docker Image

> **Why build locally?** To test the image before deploying. In the real pipeline, Azure Pipelines does this. The image is built ONCE and promoted unchanged through all environments.

```bash
docker build -t tetris:v1.0.0 -f docker/Dockerfile .

# Test locally
docker run -d --name tetris-test -p 9090:8080 tetris:v1.0.0
# Open http://localhost:9090 — play Tetris!
curl http://localhost:9090/health
docker stop tetris-test && docker rm tetris-test
```

### Step 9: Scan the Image with Trivy

> **Why scan?** This is the security gate. In the Azure Pipeline, Trivy runs with `--exit-code 1` — if CRITICAL or HIGH vulnerabilities are found, the pipeline stops and the image never reaches Harbor.

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --severity CRITICAL,HIGH tetris:v1.0.0
```

### Step 10: Load Image into Kind and Deploy

> **Why `kind load`?** In a real setup, you'd push to Harbor and K8s would pull from there. In kind, we load the image directly into the cluster.

```bash
kind load docker-image tetris:v1.0.0 --name tetris

# Deploy with Helm directly (to verify the chart works)
helm install tetris-dev helm-chart/ --namespace tetris-dev --create-namespace \
  -f helm-chart/values/dev/values.yaml \
  --set image.repository=tetris --set image.tag=v1.0.0 --set image.pullPolicy=Never

# Wait for pods
kubectl get pods -n tetris-dev -w

# Access the game
kubectl port-forward svc/tetris -n tetris-dev 9090:80 &
# Open http://localhost:9090 — Tetris running in Kubernetes!

# Clean up (we'll use Argo CD next)
helm uninstall tetris-dev -n tetris-dev
```

### Step 11: Deploy via Argo CD

> **Why Argo CD instead of Helm directly?** Argo CD continuously watches Git. When the pipeline updates the image tag, Argo CD auto-deploys (dev) or shows "OutOfSync" (UAT/prod) until you manually trigger sync.

```bash
kubectl apply -f argocd/applications.yaml

argocd app list
argocd app get tetris-dev

kubectl get pods -n tetris-dev -w
```

### Step 12: Simulate a CI Pipeline Run

> **Why simulate?** This is exactly what Azure Pipelines does in production. The image is already built (Step 8). Now we update the tag in Git, and Argo CD picks it up.

```bash
# "Pipeline" updates the image tag for dev
yq -i '.image.tag = "v1.0.0"' helm-chart/values/dev/values.yaml
git add helm-chart/values/dev/values.yaml
git commit -m "ci(dev): tetris v1.0.0"
git push

# Argo CD detects the change and auto-syncs dev
argocd app get tetris-dev

# For UAT (after change manager approves the pipeline stage):
argocd app sync tetris-uat

# For Prod (during the approved change window):
argocd app sync tetris-prod
```

### Step 13: Set Up Monitoring

> **Why?** After deployment, Prometheus scrapes metrics from Argo CD, Harbor, and the app pods. Grafana visualizes them. Alertmanager fires alerts when things go wrong.

```bash
kubectl apply -f monitoring/prometheus/service-monitors.yaml
kubectl apply -f monitoring/prometheus/alert-rules.yaml

# Import the Grafana dashboard:
# http://localhost:3000 → Dashboards → Import → Upload monitoring/grafana/tetris-dashboard.json
```

### Step 14: Experiment — Self-Heal & Drift Detection

```bash
# Scale directly — Argo CD reverts it (self-heal)
kubectl scale deployment tetris -n tetris-dev --replicas=5
kubectl get pods -n tetris-dev -w
# → Argo CD scales it back to 1

# Delete the service — Argo CD recreates it
kubectl delete svc tetris -n tetris-dev
kubectl get svc -n tetris-dev -w
# → Service reappears within seconds
```

### Step 15: Cleanup

```bash
kind delete cluster --name tetris
```

---

## Production Notes

### Image Promotion Strategy
The Docker image is **built once** in the Build stage and tagged with the Azure Pipelines build ID (e.g., `tetris/game:42`). This exact image is promoted to dev → UAT → prod by updating the `image.tag` in each environment's Helm values file. The image is **never rebuilt** for UAT or prod — this guarantees that what was tested in dev is exactly what runs in production.

### Change Management
- **Dev:** Auto-sync enabled. Every Git commit to the dev values file triggers immediate deployment.
- **UAT:** The Azure Pipeline "DeployUAT" stage uses the `UAT` environment with an approval check. After the change manager approves, the pipeline updates UAT values. A team member then manually runs `argocd app sync tetris-uat`.
- **Prod:** Same pattern but with the `Production` environment. The manual Argo CD sync must happen during the approved change window.

### Security Scanning Layers
1. **ESLint** — code quality checks
2. **Trivy filesystem scan** — finds hardcoded secrets, misconfigurations in source code
3. **npm audit** — checks for known vulnerable npm packages
4. **Trivy image scan** — scans the built Docker image for OS-level and library CVEs. Pipeline **fails** on CRITICAL/HIGH.
5. **Harbor auto-scan** — re-scans the image after push. Can block pulls if critical CVEs are found.

### Harbor vs JFrog Responsibilities
| | Harbor | JFrog |
|--|--------|-------|
| Docker images (your apps) | Primary registry | Docker Hub proxy cache |
| npm packages | Not supported | Private + public proxy |
| Helm charts | OCI support | Native Helm repository |
| Vulnerability scanning | Built-in Trivy | Xray (paid) |
| Use case | Store YOUR images | Cache ALL dependencies |

### Monitoring & Alerting
- **Prometheus** scrapes metrics from Argo CD, Harbor, JFrog, and application pods
- **Grafana** dashboards show: sync status, vulnerability counts, pod CPU/memory, restart counts
- **Alerts** fire for: sync failures (5 min), critical CVEs, pod crash loops, high memory usage (>90%)

### Rollback
```bash
# Option 1: Git revert (recommended — maintains audit trail)
git revert HEAD && git push
# Argo CD detects the revert and syncs the previous version

# Option 2: Argo CD rollback (immediate)
argocd app rollback tetris-prod <history-id>
```
