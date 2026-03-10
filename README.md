# Harbor + Argo CD + Vault Integration Examples

A comprehensive collection of examples demonstrating how **Harbor** (container registry), **Argo CD** (GitOps delivery), and **HashiCorp Vault** (secrets management) work together in a Kubernetes environment.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Developer Workflow                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Developer ──> Git Push ──> CI Pipeline (GitHub Actions)        │
│                                  │                               │
│                      ┌───────────┼───────────────┐               │
│                      ▼           ▼               ▼               │
│               ┌──────────┐ ┌──────────┐  ┌────────────┐         │
│               │  Harbor   │ │  Vault   │  │  Argo CD   │         │
│               │ (Images)  │ │(Secrets) │  │  (GitOps)  │         │
│               └─────┬────┘ └────┬─────┘  └─────┬──────┘         │
│                     │           │               │                │
│                     └───────────┼───────────────┘                │
│                                 ▼                                │
│                        ┌──────────────┐                          │
│                        │  Kubernetes   │                          │
│                        │   Cluster     │                          │
│                        └──────────────┘                          │
└─────────────────────────────────────────────────────────────────┘
```

## What You'll Learn

| Scenario | Description | Key Concepts |
|----------|-------------|--------------|
| [01 - Harbor Basics](./01-harbor-basics/) | Install & configure Harbor registry | Helm install, projects, robot accounts, image push/pull, vulnerability scanning |
| [02 - Vault Basics](./02-vault-basics/) | Install & configure HashiCorp Vault | Helm install, init/unseal, KV secrets engine, policies, Kubernetes auth |
| [03 - Argo CD Basics](./03-argocd-basics/) | Install & configure Argo CD | Helm install, Application CRD, sync policies, health checks |
| [04 - Harbor + Argo CD](./04-harbor-argocd-integration/) | Deploy Harbor-hosted images via Argo CD | Image pull secrets, private registry config, Argo CD repository credentials |
| [05 - Vault + Argo CD](./05-vault-argocd-integration/) | Inject Vault secrets into Argo CD deployments | Argo Vault Plugin (AVP), secret templating, ConfigManagementPlugin |
| [06 - Harbor + Vault](./06-harbor-vault-integration/) | Manage Harbor credentials via Vault | External Secrets Operator, Vault Agent injector, dynamic registry credentials |
| [07 - Full Integration](./07-full-integration/) | End-to-end CI/CD pipeline | GitHub Actions CI, Harbor image storage, Vault secret injection, Argo CD deployment |

## Prerequisites

- **Kubernetes cluster** (v1.24+) — Minikube, kind, k3s, or any managed cluster
- **kubectl** configured to talk to your cluster
- **Helm** v3.x installed
- **Docker** installed (for building images)
- Basic understanding of Kubernetes concepts (Pods, Deployments, Services, Secrets)

## Quick Start

```bash
# Clone this repo
git clone https://github.com/vishehemant/Argo-Harbor-Vault.git
cd Argo-Harbor-Vault

# Start with the basics (follow each README in order)
cd 01-harbor-basics/
# Follow the README.md in each directory
```

> **Want to practice hands-on?** See the [PRACTICE-GUIDE.md](./PRACTICE-GUIDE.md) for a complete local setup walkthrough using kind, with step-by-step exercises and verification checkpoints (~2.5 hours total).

> **Preparing for interviews?** See the [INTERVIEW-GUIDE.md](./INTERVIEW-GUIDE.md) for a 2-minute elevator pitch, step-by-step flow explanation, 12 common interview Q&As, key terms, and a whiteboard diagram.

## How the Three Tools Fit Together

### Harbor — "Where your container images live"
Harbor is an open-source container registry that stores, signs, and scans your Docker images. Think of it as your private Docker Hub with enterprise features like vulnerability scanning, RBAC, and replication.

### Vault — "Where your secrets live"
HashiCorp Vault manages secrets (passwords, API keys, certificates). Instead of hardcoding secrets in YAML files or storing them as plain Kubernetes Secrets, Vault provides encryption, access control, audit logging, and dynamic secret generation.

### Argo CD — "How your apps get deployed"
Argo CD is a GitOps continuous delivery tool. It watches a Git repository for Kubernetes manifests and automatically syncs them to your cluster. When you push a change to Git, Argo CD detects it and updates your running applications.

### The Integration Story
1. **CI pipeline** builds a Docker image and pushes it to **Harbor**
2. **Vault** stores all sensitive config — database passwords, API keys, and even Harbor registry credentials
3. **Argo CD** watches the Git repo, pulls the image from Harbor, injects secrets from Vault, and deploys to Kubernetes

## Directory Structure

```
.
├── README.md                          # This file
├── 01-harbor-basics/                  # Harbor installation & fundamentals
│   ├── harbor-helm-values.yaml
│   ├── Dockerfile
│   ├── app/
│   └── scripts/
├── 02-vault-basics/                   # Vault installation & fundamentals
│   ├── vault-helm-values.yaml
│   ├── policies/
│   └── scripts/
├── 03-argocd-basics/                  # Argo CD installation & fundamentals
│   ├── argocd-helm-values.yaml
│   ├── sample-app/
│   └── argocd-application.yaml
├── 04-harbor-argocd-integration/      # Harbor + Argo CD working together
│   ├── registry-credentials/
│   └── sample-app/
├── 05-vault-argocd-integration/       # Vault + Argo CD (AVP plugin)
│   ├── argocd-vault-plugin/
│   └── sample-app/
├── 06-harbor-vault-integration/       # Harbor + Vault (dynamic creds)
│   ├── external-secrets/
│   └── vault-injector/
├── 07-full-integration/               # Complete end-to-end pipeline
│   ├── app-manifests/
│   ├── vault-config/
│   ├── ci-pipeline/
│   └── argocd-application.yaml
└── cheatsheets/                       # Quick reference guides
    ├── harbor-cheatsheet.md
    ├── vault-cheatsheet.md
    └── argocd-cheatsheet.md
```

## License

MIT
