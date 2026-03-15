# 10 - Tetris: End-to-End Kubernetes DevSecOps Project

A **complete, real-world DevSecOps project** — a playable Tetris game deployed to Kubernetes through a fully automated, secure pipeline. This project ties together every tool covered in this repo into one working system.

## Live Demo

After deployment, open the Tetris game in your browser:
- **Dev:** http://tetris-dev.example.com
- **UAT:** http://tetris-uat.example.com
- **Prod:** http://tetris.example.com

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         DEVELOPER WORKFLOW                            │
│                                                                       │
│  Developer writes code ──► Git push ──► PR Review ──► Merge to main  │
└──────────────────────────────┬────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    AZURE PIPELINE (CI/CD)                              │
│                                                                       │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  │
│  │  Lint   │─►│  Test   │─►│  SAST   │─►│  Build  │─►│  Scan   │  │
│  │(ESLint) │  │ (Jest)  │  │(SonarQ) │  │(Docker) │  │(Trivy)  │  │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └────┬────┘  │
│                                                             │        │
│                                              ┌──────────────┤        │
│                                              ▼              ▼        │
│                                        ┌──────────┐  ┌──────────┐   │
│                                        │  Harbor   │  │  JFrog   │   │
│                                        │  (image)  │  │  (deps)  │   │
│                                        └──────────┘  └──────────┘   │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │  DEPLOYMENT STAGES                                              │ │
│  │                                                                  │ │
│  │  ┌────────┐    ┌──────────────┐    ┌───────────────────┐       │ │
│  │  │  DEV   │───►│     UAT      │───►│    PRODUCTION     │       │ │
│  │  │ (auto) │    │  (approval)  │    │   (approval +     │       │ │
│  │  │        │    │              │    │   change window)   │       │ │
│  │  └────────┘    └──────────────┘    └───────────────────┘       │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
                               │
                               │ updates Helm values in Git
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│                      GITOPS (Argo CD + AVP)                           │
│                                                                       │
│  Watches Git ──► Helm template ──► AVP resolves secrets ──► Deploy   │
│                                          │                            │
│                                    ┌─────▼─────┐                     │
│                                    │   Vault    │                     │
│                                    │ (secrets)  │                     │
│                                    └───────────┘                     │
└──────────────────────────────────────┬───────────────────────────────┘
                                       │
                                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     KUBERNETES CLUSTER                                 │
│                                                                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │
│  │ tetris-dev  │  │ tetris-uat  │  │ tetris-prod │                  │
│  │  1 replica  │  │  2 replicas │  │  3 replicas │                  │
│  │  no HPA     │  │  no HPA     │  │  HPA 3-10  │                  │
│  └─────────────┘  └─────────────┘  └─────────────┘                  │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │  Prometheus ──► Grafana (dashboards + alerts)                   │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

## DevSecOps Pipeline Stages

| # | Stage | Tool | What Happens |
|---|-------|------|-------------|
| 1 | **Code Lint** | ESLint | Checks code quality and style |
| 2 | **Unit Tests** | Jest | Runs automated tests |
| 3 | **SAST** | SonarQube/Semgrep | Static Application Security Testing — finds security bugs in code |
| 4 | **Dependency Check** | npm audit / Snyk | Checks for vulnerable npm packages |
| 5 | **Build Image** | Docker | Creates the container image |
| 6 | **Image Scan** | Trivy | Scans the image for OS and library vulnerabilities |
| 7 | **Push Image** | Harbor | Stores the image in private registry (Harbor auto-scans too) |
| 8 | **Push Deps** | JFrog | Caches npm dependencies for faster future builds |
| 9 | **Update Manifests** | yq + Git | Updates image tag in Helm values file |
| 10 | **Deploy Dev** | Argo CD (auto) | Deploys to dev automatically |
| 11 | **Deploy UAT** | Argo CD (manual) | After change manager approval |
| 12 | **Deploy Prod** | Argo CD (manual) | After change request + approved window |
| 13 | **Monitor** | Prometheus + Grafana | Tracks deployment health, latency, errors |

## Project Structure

```
10-tetris-devsecops/
├── app/                        # Tetris game source code
│   ├── src/
│   │   ├── index.html          # Game UI
│   │   ├── style.css           # Styling
│   │   └── tetris.js           # Game logic
│   └── nginx/
│       └── default.conf        # Nginx config for serving the game
├── docker/
│   ├── Dockerfile              # Multi-stage build
│   └── .dockerignore
├── helm-chart/                 # Kubernetes deployment
│   ├── Chart.yaml
│   ├── values.yaml             # Defaults
│   ├── values/
│   │   ├── dev.yaml
│   │   ├── uat.yaml
│   │   └── prod.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       ├── hpa.yaml
│       ├── secret.yaml         # AVP placeholders
│       └── configmap.yaml
├── azure-pipelines/
│   └── azure-pipelines.yaml    # Full DevSecOps pipeline
├── argocd/
│   └── applications.yaml       # Dev/UAT/Prod Argo CD apps
├── vault-config/
│   ├── policies/
│   └── setup.sh
├── security-scanning/
│   ├── trivy-config.yaml
│   └── semgrep-rules.yaml
├── monitoring/
│   └── grafana-dashboard.json
└── docs/
    └── STEP-BY-STEP-LAB.md     # Complete hands-on walkthrough
```

## Quick Start

```bash
# 1. Build and run locally
cd app && python3 -m http.server 8080
# Open http://localhost:8080 — play Tetris!

# 2. Build Docker image
docker build -t tetris:latest -f docker/Dockerfile .

# 3. Deploy to Kubernetes (see docs/STEP-BY-STEP-LAB.md for full walkthrough)
```
