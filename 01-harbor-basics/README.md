# 01 - Harbor Basics

## What is Harbor?

Harbor is an **open-source container registry** that stores, signs, and scans container images. It extends the Docker Distribution by adding security, identity, and management features.

### Key Features
- **Vulnerability Scanning** — Automatically scan images for CVEs using Trivy
- **RBAC** — Role-based access control for projects and repositories
- **Image Signing** — Content trust with Notary/Cosign
- **Replication** — Replicate images between Harbor instances or from Docker Hub
- **Robot Accounts** — Service accounts for CI/CD pipelines
- **Garbage Collection** — Clean up unused image layers

## Architecture

```
┌──────────────────────────────────────────────────┐
│                     Harbor                        │
├──────────────────────────────────────────────────┤
│                                                   │
│  ┌─────────┐  ┌─────────┐  ┌──────────────────┐ │
│  │  Nginx   │  │  Core   │  │   Job Service    │ │
│  │ (Proxy)  │──│ (API)   │──│ (Scan/Replicate) │ │
│  └─────────┘  └─────────┘  └──────────────────┘ │
│       │            │               │              │
│  ┌─────────┐  ┌─────────┐  ┌──────────────────┐ │
│  │Registry  │  │  DB     │  │     Trivy        │ │
│  │(Storage) │  │(Postgres)│  │  (Scanner)       │ │
│  └─────────┘  └─────────┘  └──────────────────┘ │
│       │                                           │
│  ┌─────────┐                                      │
│  │  Redis  │                                      │
│  └─────────┘                                      │
└──────────────────────────────────────────────────┘
```

## Step 1: Install Harbor via Helm

```bash
# Add the Harbor Helm repo
helm repo add harbor https://helm.goharbor.io
helm repo update

# Create a namespace
kubectl create namespace harbor

# Install Harbor with custom values
helm install harbor harbor/harbor \
  --namespace harbor \
  -f harbor-helm-values.yaml
```

### Understanding the Helm Values

See [harbor-helm-values.yaml](./harbor-helm-values.yaml) — each section is commented to explain what it does.

## Step 2: Access the Harbor UI

```bash
# If using NodePort (as in our values file)
# Get the node IP
kubectl get nodes -o wide

# Access Harbor at https://<node-ip>:30003
# Default credentials: admin / Harbor12345

# If using port-forward for local development
kubectl port-forward svc/harbor-portal 8080:80 -n harbor
# Access at http://localhost:8080
```

## Step 3: Create a Project

Projects in Harbor are logical groupings of repositories (like organizations in Docker Hub).

```bash
# Via the API
curl -k -u "admin:Harbor12345" \
  -X POST "https://harbor.example.com/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d '{
    "project_name": "my-app",
    "public": false,
    "metadata": {
      "auto_scan": "true",
      "severity": "high"
    }
  }'
```

Or use the script: `./scripts/create-project.sh`

## Step 4: Create a Robot Account

Robot accounts are **service accounts** for automated systems (CI/CD pipelines). They have limited permissions and can be scoped to specific projects.

```bash
# Via the API — create a robot account with push/pull permissions
curl -k -u "admin:Harbor12345" \
  -X POST "https://harbor.example.com/api/v2.0/robots" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ci-pipeline",
    "description": "Robot account for CI/CD pipeline",
    "duration": 365,
    "level": "project",
    "permissions": [
      {
        "namespace": "my-app",
        "kind": "project",
        "access": [
          {"resource": "repository", "action": "push"},
          {"resource": "repository", "action": "pull"},
          {"resource": "tag",        "action": "create"},
          {"resource": "tag",        "action": "list"}
        ]
      }
    ]
  }'
```

Save the returned `secret` — you'll need it for Docker login.

## Step 5: Build and Push an Image

```bash
# Login to Harbor
docker login harbor.example.com -u 'robot$ci-pipeline' -p '<robot-secret>'

# Build the sample app
docker build -t harbor.example.com/my-app/sample-web:v1.0.0 -f Dockerfile .

# Push to Harbor
docker push harbor.example.com/my-app/sample-web:v1.0.0
```

## Step 6: Vulnerability Scanning

Harbor can automatically scan every pushed image (we enabled `auto_scan` in Step 3).

```bash
# Manually trigger a scan
curl -k -u "admin:Harbor12345" \
  -X POST "https://harbor.example.com/api/v2.0/projects/my-app/repositories/sample-web/artifacts/v1.0.0/scan"

# Check scan results
curl -k -u "admin:Harbor12345" \
  "https://harbor.example.com/api/v2.0/projects/my-app/repositories/sample-web/artifacts/v1.0.0?with_scan_overview=true"
```

## Step 7: Pull from Kubernetes

```bash
# Create an image pull secret
kubectl create secret docker-registry harbor-creds \
  --docker-server=harbor.example.com \
  --docker-username='robot$ci-pipeline' \
  --docker-password='<robot-secret>' \
  --namespace=default

# Use it in a Pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-harbor-pull
spec:
  imagePullSecrets:
    - name: harbor-creds
  containers:
    - name: app
      image: harbor.example.com/my-app/sample-web:v1.0.0
      ports:
        - containerPort: 8080
EOF
```

## Key Concepts Recap

| Concept | What It Means |
|---------|---------------|
| **Project** | A namespace for grouping related repositories (e.g., `my-app`) |
| **Repository** | A collection of image tags within a project (e.g., `my-app/backend`) |
| **Robot Account** | A service account with scoped permissions for automation |
| **Vulnerability Scan** | Automated scanning of images for known CVEs |
| **Image Pull Secret** | A Kubernetes Secret that stores registry credentials for pulling images |
| **Replication Rule** | Automatically copy images between registries |

## Files in This Directory

| File | Purpose |
|------|---------|
| `harbor-helm-values.yaml` | Helm chart values with detailed comments |
| `Dockerfile` | Sample multi-stage Dockerfile for a Go web app |
| `app/main.go` | Simple Go web server (the sample application) |
| `scripts/create-project.sh` | Script to create a Harbor project via API |
| `scripts/create-robot-account.sh` | Script to create a robot account |
| `scripts/push-image.sh` | Script to build and push a Docker image |
