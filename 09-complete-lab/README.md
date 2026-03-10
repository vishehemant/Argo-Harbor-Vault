# 09 - Complete Lab: Azure Pipelines + Harbor + JFrog + Vault + Argo CD + Grafana/Prometheus

A production-grade lab covering the **full DevSecOps toolchain**. This lab adds **JFrog Artifactory** for managing both private and public package repositories alongside Harbor, Vault, Argo CD, and full observability with Prometheus + Grafana.

## Architecture

```
                            Developer
                                │
                                │ git push (PR merge)
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        Azure Pipelines                               │
│                                                                      │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐      │
│  │  Build   │───►│  Test    │───►│  Scan    │───►│  Push    │      │
│  │          │    │(unit/int)│    │ (Trivy)  │    │          │      │
│  └──────────┘    └──────────┘    └──────────┘    └────┬─────┘      │
│                                                       │             │
│                       ┌───────────────────────────────┤             │
│                       ▼                               ▼             │
│              ┌──────────────┐                ┌──────────────┐       │
│              │   JFrog      │                │   Harbor      │       │
│              │ Artifactory  │                │  (Docker      │       │
│              │              │                │   Registry)   │       │
│              │ ▪ npm        │                │              │       │
│              │ ▪ Maven      │                │ ▪ Vuln scan  │       │
│              │ ▪ PyPI       │                │ ▪ RBAC       │       │
│              │ ▪ Go modules │                │ ▪ Signing    │       │
│              │ ▪ Helm charts│                │              │       │
│              │ ▪ Docker     │                │              │       │
│              │   (proxy)    │                │              │       │
│              └──────────────┘                └──────────────┘       │
│                                                                      │
│  ┌───────┐  ┌─────────┐  ┌──────────┐                              │
│  │  DEV  │─►│   UAT   │─►│   PROD   │   (approval gates)           │
│  │ auto  │  │ approve │  │ approve  │                              │
│  └───┬───┘  └────┬────┘  └────┬─────┘                              │
└──────┼───────────┼─────────────┼────────────────────────────────────┘
       │           │             │   update Helm values/
       │           │             │   {dev,uat,prod}.yaml
       ▼           ▼             ▼
┌─────────────────────────────────────┐
│          Git Repository              │
│   helm-chart/                        │
│     templates/                       │
│     values/dev.yaml                  │
│     values/uat.yaml                  │
│     values/prod.yaml                 │
└──────────────┬──────────────────────┘
               │ watches
               ▼
┌─────────────────────────────────────┐
│          Argo CD + AVP               │
│                                      │
│  myapp-dev   (auto-sync)            │
│  myapp-uat   (manual sync)          │     ┌──────────────┐
│  myapp-prod  (manual sync)          │────►│    Vault      │
│                                      │     │              │
│  helm template → AVP resolves        │     │ secret/dev/  │
│  <path:...#key> from Vault          │     │ secret/uat/  │
└──────────────┬──────────────────────┘     │ secret/prod/ │
               │ deploy                      │              │
               ▼                             │ harbor creds │
┌─────────────────────────────────────┐     │ jfrog creds  │
│        Kubernetes Cluster            │     │ db passwords │
│                                      │     │ api keys     │
│  dev / uat / prod namespaces         │     └──────────────┘
│                                      │
│  Pods pull images from Harbor        │
│  (pull creds from Vault via ESO)     │
└──────────────┬──────────────────────┘
               │ metrics
               ▼
┌─────────────────────────────────────┐
│     Prometheus + Grafana             │
│                                      │
│  Scrapes: Argo CD, Harbor, Vault,   │
│           JFrog, Kubernetes pods     │
│                                      │
│  Dashboards: deployments, scans,    │
│              secrets, artifacts      │
│                                      │
│  Alerts: sync failures, sealed      │
│          vault, critical CVEs,      │
│          pod crashes                 │
└─────────────────────────────────────┘
```

## What is JFrog Artifactory?

JFrog Artifactory is a **universal artifact repository manager**. While Harbor handles Docker images, JFrog manages **everything else** your build needs:

| Repository Type | What It Stores | Example |
|----------------|---------------|---------|
| **Docker** (proxy) | Cached images from Docker Hub, GCR, etc. | `docker pull jfrog.example.com/docker-remote/nginx:latest` |
| **npm** | Node.js packages (private + proxied public) | `npm install --registry https://jfrog.example.com/api/npm/npm-repo/` |
| **Maven** | Java JARs, WARs | `mvn deploy` to JFrog |
| **PyPI** | Python packages | `pip install --index-url https://jfrog.example.com/api/pypi/pypi-repo/simple/` |
| **Go** | Go modules | `GOPROXY=https://jfrog.example.com/api/go/go-repo` |
| **Helm** | Helm charts (alternative to Harbor OCI) | `helm repo add myrepo https://jfrog.example.com/artifactory/helm-repo` |
| **Generic** | Any binary, config file, tarball | Upload via API |

### JFrog Repository Types

| Type | Purpose |
|------|---------|
| **Local** | Your private artifacts — code your team builds |
| **Remote** | Proxy + cache for public registries (npmjs.org, Docker Hub, PyPI) |
| **Virtual** | Combines local + remote into a single URL (clients use one endpoint) |

### Why JFrog + Harbor Together?

| | Harbor | JFrog |
|--|--------|-------|
| **Docker images** | Primary registry (scan + sign + RBAC) | Proxy cache for public images |
| **Helm charts** | OCI support | Native Helm repository |
| **npm/Maven/PyPI** | Not supported | Full support |
| **Vulnerability scanning** | Trivy (built-in, free) | Xray (paid, deeper analysis) |
| **Use case** | Store YOUR images | Cache + manage ALL build dependencies |

## Lab Setup Order

| Step | Component | Time |
|------|-----------|------|
| 1 | [Install Prometheus + Grafana](#step-1-install-prometheus--grafana) | 10 min |
| 2 | [Install Harbor](#step-2-install-harbor) | 10 min |
| 3 | [Install JFrog Artifactory](#step-3-install-jfrog-artifactory) | 10 min |
| 4 | [Install Vault](#step-4-install-vault) | 10 min |
| 5 | [Install Argo CD + AVP](#step-5-install-argo-cd--avp) | 15 min |
| 6 | [Configure JFrog repositories](#step-6-configure-jfrog-repositories) | 10 min |
| 7 | [Store all credentials in Vault](#step-7-store-credentials-in-vault) | 10 min |
| 8 | [Deploy the application](#step-8-deploy-the-application) | 10 min |
| 9 | [Set up monitoring dashboards](#step-9-set-up-monitoring) | 10 min |
| **Total** | | **~1.5 hours** |

---

## Step 1: Install Prometheus + Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f monitoring/prometheus/kube-prometheus-values.yaml \
  --wait --timeout 5m
```

Access Grafana:
```bash
kubectl port-forward svc/kube-prometheus-grafana -n monitoring 3000:80 &
# http://localhost:3000 — admin / prom-operator
```

## Step 2: Install Harbor

```bash
helm repo add harbor https://helm.goharbor.io
helm install harbor harbor/harbor \
  --namespace harbor --create-namespace \
  -f ../01-harbor-basics/harbor-helm-values.yaml \
  --wait --timeout 10m
```

## Step 3: Install JFrog Artifactory

```bash
helm repo add jfrog https://charts.jfrog.io
helm repo update

kubectl create namespace jfrog

helm install artifactory jfrog/artifactory \
  --namespace jfrog \
  -f jfrog/helm/artifactory-values.yaml \
  --wait --timeout 10m
```

Access JFrog UI:
```bash
kubectl port-forward svc/artifactory -n jfrog 8082:8082 &
# http://localhost:8082 — admin / password
```

## Step 4: Install Vault

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --namespace vault --create-namespace \
  -f ../02-vault-basics/vault-helm-values.yaml \
  --wait --timeout 5m

# Initialize and unseal
bash ../02-vault-basics/scripts/init-and-unseal.sh
```

## Step 5: Install Argo CD + AVP

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  -f ../03-argocd-basics/argocd-helm-values.yaml \
  --wait --timeout 5m

# Install AVP plugin
kubectl apply -f ../05-vault-argocd-integration/argocd-vault-plugin/cmp-plugin-configmap.yaml
kubectl patch deployment argocd-repo-server -n argocd \
  --patch-file ../05-vault-argocd-integration/argocd-vault-plugin/argocd-repo-server-patch.yaml
```

## Step 6: Configure JFrog Repositories

```bash
bash jfrog/scripts/setup-repositories.sh
```

## Step 7: Store Credentials in Vault

```bash
bash vault-config/store-all-credentials.sh
```

## Step 8: Deploy the Application

```bash
kubectl apply -f argocd-apps/argocd-apps.yaml
```

## Step 9: Set Up Monitoring

```bash
kubectl apply -f monitoring/prometheus/service-monitors.yaml
kubectl apply -f monitoring/prometheus/alert-rules.yaml
# Import Grafana dashboard from monitoring/grafana-dashboards/
```

---

## Files in This Directory

| Directory | Purpose |
|-----------|---------|
| `jfrog/` | JFrog Artifactory Helm values + setup scripts |
| `harbor-jfrog-integration/` | Docker proxy cache, Harbor-JFrog replication |
| `azure-pipelines/` | Azure Pipeline using both JFrog and Harbor |
| `argocd-apps/` | Per-environment Argo CD Applications (Helm + AVP) |
| `vault-config/` | Vault policies, roles, and credential storage script |
| `monitoring/` | Prometheus + Grafana: values, ServiceMonitors, alerts, dashboards |
| `helm-chart/` | Application Helm chart with JFrog + Harbor integration |
| `lab-exercises/` | Hands-on exercises to practice each integration |
