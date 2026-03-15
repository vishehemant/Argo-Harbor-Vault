# Tetris DevSecOps Lab — Step by Step

> **Prerequisites:** Complete the [PRACTICE-GUIDE.md](../../PRACTICE-GUIDE.md) first (sets up kind, Harbor, Vault, Argo CD, Prometheus).

## Step 1: Play the Game Locally

> **Why?** Before deploying to Kubernetes, run the app locally to see what you're deploying. This also proves the source code works before containerizing.

```bash
cd 10-tetris-devsecops/app/src
python3 -m http.server 8080
# Open http://localhost:8080 — play Tetris!
# Press Ctrl+C to stop
```

## Step 2: Build the Docker Image

> **Why?** Containerizing the app packages the game + nginx web server into a single, portable unit that runs identically on any machine — your laptop, CI, dev cluster, production.

```bash
cd 10-tetris-devsecops
docker build -t tetris:v1.0.0 -f docker/Dockerfile .
```

## Step 3: Run the Container Locally

> **Why?** Test the Docker image before pushing to Harbor. If it works here, it'll work in Kubernetes. The `-e` flags simulate environment variables that Kubernetes would set.

```bash
docker run -d --name tetris-test \
  -p 9090:80 \
  -e APP_VERSION=v1.0.0 \
  -e APP_ENV=local-docker \
  tetris:v1.0.0

# Open http://localhost:9090 — Tetris running in a container!
# Check the footer: shows version and environment

# Check the health endpoint
curl http://localhost:9090/health

# Check the info endpoint
curl http://localhost:9090/api/info

# Clean up
docker stop tetris-test && docker rm tetris-test
```

## Step 4: Scan the Image with Trivy

> **Why?** This is the "Sec" in DevSecOps. Before pushing to Harbor, scan for known vulnerabilities in the base image and installed packages. In the Azure Pipeline, this step would FAIL the build if critical CVEs are found.

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image \
  --severity CRITICAL,HIGH \
  tetris:v1.0.0
```

Review the output — it shows each CVE with its severity and whether a fix is available.

## Step 5: Store Tetris Secrets in Vault

> **Why?** The Tetris app has configuration that varies by environment (analytics keys, feature flags). Instead of hardcoding these in the Helm values, we store them in Vault and let AVP inject them at deploy time.

```bash
# Store dev config
kubectl exec -n vault vault-0 -- vault kv put secret/dev/tetris/config \
  analytics_key="dev_analytics_key_2026" \
  feature_flags="leaderboard=true,multiplayer=false"

# Store prod config (different values)
kubectl exec -n vault vault-0 -- vault kv put secret/prod/tetris/config \
  analytics_key="prod_analytics_key_REAL" \
  feature_flags="leaderboard=true,multiplayer=true"

# Verify
kubectl exec -n vault vault-0 -- vault kv get secret/dev/tetris/config
```

## Step 6: Load the Image into Kind

> **Why?** In a real setup, you'd push to Harbor and Kubernetes would pull from there. In our kind cluster, we use `kind load` to make the image available without a real registry. The Helm chart image reference will use this local image.

```bash
kind load docker-image tetris:v1.0.0 --name practice
```

## Step 7: Deploy with Helm (Direct — No Argo CD)

> **Why try Helm directly first?** To verify the chart works before adding Argo CD + AVP into the mix. If something breaks, you know it's the chart, not the AVP integration.

```bash
helm install tetris-dev 10-tetris-devsecops/helm-chart \
  --namespace tetris-dev \
  --create-namespace \
  -f 10-tetris-devsecops/helm-chart/values/dev.yaml \
  --set image.repository=tetris \
  --set image.tag=v1.0.0 \
  --set imagePullSecrets=null

# Watch pods start
kubectl get pods -n tetris-dev -w

# Port-forward to access the game
kubectl port-forward svc/tetris -n tetris-dev 9090:80 &
# Open http://localhost:9090 — Tetris running in Kubernetes!
# Check footer: Environment should show "dev"

# Clean up (we'll redeploy via Argo CD next)
helm uninstall tetris-dev -n tetris-dev
```

## Step 8: Deploy via Argo CD

> **Why Argo CD instead of Helm directly?** Argo CD watches Git continuously. When the Azure Pipeline updates the image tag, Argo CD detects it and deploys. With plain Helm, someone would need to manually run `helm upgrade`.

```bash
kubectl apply -f 10-tetris-devsecops/argocd/applications.yaml

# Check all three environments
argocd app list
argocd app get tetris-dev
```

## Step 9: Simulate a CI Pipeline Run

> **Why simulate?** This is exactly what the Azure Pipeline does — update the image tag in the values file and commit. Argo CD picks up the change and deploys.

```bash
# "CI" builds v2.0.0 and updates the tag
cd 10-tetris-devsecops/helm-chart
yq e '.image.tag = "v2.0.0"' -i values/dev.yaml
cd ../..
git add 10-tetris-devsecops/helm-chart/values/dev.yaml
git commit -m "ci(dev): tetris v2.0.0"

# Argo CD detects the commit and syncs dev (auto-sync)
argocd app get tetris-dev

# For UAT — after "change manager approval":
argocd app sync tetris-uat

# For Prod — during "approved change window":
argocd app sync tetris-prod
```

## Step 10: Check Monitoring

> **Why?** After deployment, verify the app is healthy in Grafana. In production, you'd watch these dashboards after every deployment to catch issues early.

```bash
# Open Grafana: http://localhost:3000
# Go to Dashboards > Kubernetes / Compute Resources / Namespace (Pods)
# Select namespace: tetris-dev
# You should see CPU and memory usage of the Tetris pods
```

## What You Built

```
Code (HTML/CSS/JS)
  │
  ├── Lint (ESLint) ✓
  ├── SAST (Semgrep) ✓
  ├── Dependency Audit (npm audit) ✓
  │
  ▼
Docker Image
  │
  ├── Trivy Scan ✓
  │
  ▼
Harbor (private registry, auto-scan)
  │
  ▼
Git (Helm values updated by Azure Pipeline)
  │
  ▼
Argo CD (watches Git)
  │
  ├── AVP resolves secrets from Vault ✓
  ├── ESO provides Harbor pull creds from Vault ✓
  │
  ▼
Kubernetes (dev → UAT → prod with approvals)
  │
  ▼
Prometheus + Grafana (monitoring + alerts)
```

Congratulations — you've built a complete DevSecOps pipeline!
