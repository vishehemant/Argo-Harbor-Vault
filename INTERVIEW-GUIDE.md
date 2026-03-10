# Interview Guide: Harbor + Argo CD + Vault Architecture

> Tailored to a real production setup using **Azure Pipelines** with multi-stage approvals (dev → UAT → prod), **manual Argo CD sync** (no auto-sync due to change management), and **Grafana + Prometheus** for monitoring.

---

## The 2-Minute Elevator Pitch

> "We follow a **GitOps approach** for Kubernetes deployments with a strong **change management** process.
>
> Our CI runs on **Azure Pipelines** with a multi-stage setup — **dev**, **UAT**, and **prod** — where UAT and prod stages require **change manager approval** before proceeding. This ensures every production deployment is reviewed and authorized.
>
> **Harbor** is our private container registry. Every image pushed by CI is automatically scanned for vulnerabilities by Trivy. If critical CVEs are found, Harbor blocks the image from being pulled — acting as a security gate before it ever reaches a cluster.
>
> **HashiCorp Vault** is our centralized secrets manager. Database passwords, API keys, registry credentials — everything lives in Vault with AES-256 encryption, fine-grained policies, and full audit logging. Each environment (dev/UAT/prod) has its own secret paths and policies.
>
> **Argo CD** handles the deployment side using GitOps. But unlike typical setups, we **don't use auto-sync**. After the Azure Pipeline updates the image tag in Git and the change is approved, the team manually triggers the Argo CD sync. This gives us controlled, auditable deployments that align with our change management process. The **Argo Vault Plugin** resolves secret placeholders from Vault at sync time, so secrets never touch Git.
>
> For observability, we use **Prometheus** to scrape metrics from all three tools and **Grafana** dashboards for real-time visibility into deployments, registry health, secret access patterns, and pipeline status."

---

## How to Explain the Flow (Step by Step)

When the interviewer asks "walk me through a deployment," use this structure:

### Step 1: Developer Pushes Code

> "A developer creates a feature branch, writes code, and raises a **pull request** in Azure DevOps. The PR triggers the CI pipeline for validation — unit tests, linting, and a dev build."

### Step 2: Azure Pipelines Builds and Pushes to Harbor

> "Once the PR is merged to main, the **Azure Pipeline** kicks off. The first stage builds a Docker image, tags it with the build number or semantic version, and pushes it to **Harbor**. Harbor automatically runs a **Trivy vulnerability scan**. If critical CVEs are found, we can block the image — this is our first security gate."

### Step 3: Dev Stage — Automatic Deployment

> "The pipeline's **dev stage** automatically updates the Kustomize overlay for the dev environment with the new image tag and commits it to the GitOps repo. Argo CD picks it up, resolves secrets from the **dev Vault path**, and deploys to the dev cluster. Dev runs with auto-sync because it's a lower environment where rapid iteration matters."

### Step 4: UAT Stage — Change Manager Approval

> "The **UAT stage** has an **approval gate** in Azure Pipelines. The change manager reviews the change request — what's being deployed, the scan results from Harbor, the test results from dev. Once approved, the pipeline updates the UAT Kustomize overlay. Then the team **manually syncs** Argo CD to deploy to UAT. No auto-sync — we control when changes hit UAT."

### Step 5: Prod Stage — Full Change Management

> "Production follows the strictest process. After UAT validation, a **change request** goes through our change management workflow. The change manager approves the Azure Pipeline's prod stage. The pipeline updates the prod overlay. Then a senior engineer **manually triggers the Argo CD sync** during the approved change window. Argo CD's AVP resolves secrets from the **production Vault path** (which has its own isolated policy), and the deployment rolls out."

### Step 6: Secrets Are Never in Git

> "Throughout this entire flow, secrets are managed by **Vault**. Our manifests in Git contain **placeholders** like `<path:secret/data/prod/myapp#db_password>`. The **Argo Vault Plugin** on the repo-server authenticates with Vault using Kubernetes ServiceAccount auth, fetches the real values, and injects them at sync time. For Harbor image pull credentials, the **External Secrets Operator** keeps them synced from Vault automatically."

### Step 7: Monitoring & Observability

> "After deployment, **Prometheus** scrapes metrics from Argo CD, Harbor, and Vault. Our **Grafana dashboards** show deployment frequency, sync duration, image scan results, secret access patterns, and pod health. We have alerts for sync failures, critical vulnerabilities, Vault seal status, and pod crashes."

---

## The Real Architecture Diagram (Whiteboard)

```
    Developer
        │
        │ PR merge
        ▼
    ┌─────────────┐    build + push     ┌─────────────┐
    │   Azure      │ ──────────────────► │   Harbor     │
    │   Pipelines  │                     │  (Trivy scan)│
    └──────┬──────┘                     └──────┬──────┘
           │                                    │
    ┌──────┼────────────────────────────────────┼──────────┐
    │      │           STAGES                   │          │
    │      │                                    │          │
    │  ┌───▼────┐  ┌──────────┐  ┌──────────┐  │          │
    │  │  DEV   │  │   UAT    │  │   PROD   │  │          │
    │  │(auto)  │─►│(approval)│─►│(approval)│  │          │
    │  └───┬────┘  └───┬──────┘  └────┬─────┘  │          │
    │      │           │              │         │          │
    └──────┼───────────┼──────────────┼─────────┘          │
           │           │              │                    │
           ▼           ▼              ▼                    │
    ┌──────────┐  (update image tag per environment)       │
    │ Git Repo │                                           │
    │ (YAML)   │                                           │
    │ ├─ base/ │                                           │
    │ ├─ dev/  │                                           │
    │ ├─ uat/  │                                           │
    │ └─ prod/ │                                           │
    └────┬─────┘                                           │
         │ watches                                         │
         ▼                                                 │
    ┌──────────┐    fetch secrets     ┌─────────┐         │
    │ Argo CD  │ ───────────────────► │  Vault  │         │
    │ (+ AVP)  │                      │         │         │
    │          │                      │ dev/    │         │
    │ DEV:auto │                      │ uat/    │         │
    │ UAT:manual│                     │ prod/   │         │
    │ PROD:manual│                    └────┬────┘         │
    └─────┬─────┘                          │              │
          │ deploy                         │ ESO syncs    │
          ▼                                │ pull creds   │
    ┌───────────┐                          │              │
    │Kubernetes │ ◄────────────────────────┘              │
    │ Clusters  │ ◄── pull image ─────────────────────────┘
    │           │
    │ dev/uat/  │         ┌──────────────────────┐
    │ prod      │────────►│ Prometheus + Grafana  │
    │           │ metrics │ (dashboards & alerts) │
    └───────────┘         └──────────────────────┘
```

**Draw it in this order:**
1. Developer at the top → Azure Pipelines
2. Three stages (dev/UAT/prod) with approval gates between them
3. Each stage updates the Git repo (different Kustomize overlay)
4. Argo CD watches Git → fetches secrets from Vault → deploys
5. Highlight: dev=auto-sync, UAT+prod=manual sync
6. Prometheus + Grafana on the side collecting metrics from everything

---

## Common Interview Questions and Answers

### Q: Why not auto-sync in production?

> "We follow a **change management process**. Every production deployment requires an approved change request. Auto-sync would bypass that — imagine a developer pushes a commit at 2 AM and it auto-deploys to production without any review.
>
> Our setup is:
> - **Dev** — auto-sync enabled (fast iteration, low risk)
> - **UAT** — manual sync (change manager approves the Azure Pipeline stage, then we trigger sync)
> - **Prod** — manual sync (full change request, approved change window, senior engineer triggers sync)
>
> Argo CD still provides value without auto-sync — it shows the **diff** between Git and the cluster, tracks sync history, and provides **rollback** capability. We just control **when** the sync happens."

### Q: Walk me through your change management process.

> "Here's the end-to-end flow:
> 1. Developer merges PR → CI builds and pushes image to Harbor
> 2. Dev stage auto-deploys → team validates in dev
> 3. Developer raises a **change request** for UAT
> 4. Change manager reviews: what changed, scan results, dev test results
> 5. Change manager **approves the UAT stage** in Azure Pipelines
> 6. Pipeline updates UAT overlay in Git
> 7. Team **manually syncs** Argo CD for UAT
> 8. QA validates in UAT
> 9. Change request updated for **prod deployment** with UAT sign-off
> 10. Change manager approves the **prod stage** during the change window
> 11. Pipeline updates prod overlay
> 12. Senior engineer **manually syncs** Argo CD for prod
> 13. Post-deployment validation using Grafana dashboards
>
> Every step is auditable — Azure Pipeline logs, Git history, Argo CD sync history, and Vault audit logs."

### Q: Why not just use Kubernetes Secrets directly?

> "Kubernetes Secrets are **base64-encoded, not encrypted**. Anyone with cluster access can decode them. They also lack audit logging — you don't know who accessed which secret and when. Vault provides **AES-256 encryption**, fine-grained **access policies**, full **audit logging**, **automatic rotation**, and **dynamic secrets** — for example, it can generate short-lived database credentials on demand."

### Q: Why Harbor instead of Azure Container Registry (ACR)?

> "We evaluated ACR but chose Harbor for several reasons:
> - **Multi-cloud portability** — Harbor runs anywhere (on-prem, any cloud), so we're not locked into Azure
> - **Built-in vulnerability scanning** with Trivy — more configurable than ACR's scanning
> - **Image pull prevention** — Harbor can block pulling vulnerable images, ACR can only flag them
> - **Replication** — we replicate images between regions using Harbor's built-in replication rules
> - **RBAC with robot accounts** — fine-grained CI/CD service accounts scoped per project
>
> That said, ACR is a valid choice if you're fully committed to Azure. Harbor just gave us more control and flexibility."

### Q: Why Argo CD instead of deploying directly from Azure Pipelines?

> "Azure Pipelines could run `kubectl apply` or `helm upgrade` directly — that's the **push-based** model. The problems:
> 1. **Drift detection** — if someone runs `kubectl edit` directly, nobody knows the cluster drifted from Git
> 2. **Pipeline needs cluster credentials** — your CI system has direct access to production clusters, which is a security risk
> 3. **No continuous reconciliation** — the pipeline runs once and is done; if a pod crashes and Kubernetes recreates it with stale config, you don't notice
>
> With Argo CD (**pull-based**):
> - The pipeline only touches **Git**, never the cluster directly
> - Argo CD continuously compares Git vs. cluster and shows **drift**
> - Even without auto-sync, we see exactly what's **OutOfSync** before triggering a deployment
> - Argo CD runs **inside** the cluster, so no external system has cluster credentials"

### Q: How do you handle secret rotation?

> "Two mechanisms:
> 1. **Application secrets** (DB passwords, API keys) — we update in Vault, then trigger an Argo CD sync. AVP reads the new values and updates the Kubernetes Secrets. We do a rolling restart of affected pods.
> 2. **Harbor credentials** — the External Secrets Operator syncs from Vault every hour. When we rotate the robot account password, ESO auto-updates the pull secret. Zero downtime, no manual steps.
>
> We also monitor secret access patterns in **Grafana** using Vault audit log metrics. If we see unusual access, we rotate immediately."

### Q: What happens if Vault goes down?

> "Existing pods continue running — they already have their secrets. New deployments would fail because AVP can't resolve placeholders. That's why Vault runs in **HA mode** with 3 replicas using Raft consensus across availability zones. We have **Prometheus alerts** on Vault health and seal status in Grafana. If a node is sealed, the ops team is paged immediately."

### Q: How does Vault authenticate Argo CD?

> "Vault uses **Kubernetes auth** — no passwords to manage:
> 1. Argo CD repo-server has a Kubernetes ServiceAccount
> 2. Kubernetes signs a JWT for that ServiceAccount
> 3. Vault calls the Kubernetes API to validate the JWT
> 4. If valid, Vault issues a time-limited token scoped to the `argocd` policy
>
> No shared secrets. The trust is bootstrapped through Kubernetes itself. This solves the **secret-zero problem**."

### Q: How do you prevent secrets from leaking into Git?

> "Three layers:
> 1. **AVP placeholders** — manifests only contain references like `<path:secret/...#key>`, never real values
> 2. **Azure Repos branch policies** — PR reviews required; pre-commit hooks scan for secret patterns
> 3. **Vault policies** — even if someone gets a token, each environment (dev/UAT/prod) has isolated paths and policies
>
> The principle: Git stores **what to deploy** and **where secrets come from**, never the secrets themselves."

### Q: What's the difference between AVP and External Secrets Operator?

> "Different tools for different use cases:
> - **AVP** works at **Argo CD sync time** — it processes YAML templates in the repo-server. Best for app secrets that are part of deployment manifests.
> - **ESO** runs **continuously** as a controller — syncs Vault secrets into K8s Secrets on a schedule. Best for infrastructure creds like image pull secrets that must exist before Argo CD syncs.
>
> We use both: ESO for Harbor credentials, AVP for application configuration."

### Q: How do you handle multiple environments?

> "Three layers of separation:
> 1. **Vault paths** — `secret/dev/myapp/`, `secret/uat/myapp/`, `secret/prod/myapp/` with **separate policies per environment**. The dev Vault role cannot read prod secrets.
> 2. **Kustomize overlays** — a `base/` directory with common manifests, plus `overlays/dev/`, `overlays/uat/`, `overlays/prod/` with environment-specific patches (replicas, resource limits, image tags, ingress hostnames)
> 3. **Argo CD Applications** — three separate Application CRDs, each pointing to the correct overlay. Dev has `automated` sync, UAT and prod have **manual sync** only.
> 4. **Azure Pipeline stages** — each stage targets a different overlay and has its own approval gate."

### Q: How do you roll back a failed deployment?

> "Two options:
> 1. **Git revert** — `git revert HEAD && git push`, then trigger Argo CD sync. This is the GitOps way — full audit trail.
> 2. **Argo CD rollback** — `argocd app rollback <app> <history-id>` for immediate rollback from the UI or CLI.
>
> For production rollbacks, we still go through change management — but it's an emergency change with expedited approval. The rollback itself takes seconds once approved."

### Q: What monitoring do you have?

> "We use **Prometheus + Grafana** across the entire stack:
>
> **Argo CD metrics** (via Prometheus):
> - Sync duration, sync status (success/failure count)
> - Application health status across environments
> - Git fetch latency, repo-server performance
>
> **Harbor metrics**:
> - Image push/pull rates, storage usage
> - Vulnerability scan results per project (critical/high/medium counts)
> - Registry availability and latency
>
> **Vault metrics**:
> - Seal status, token creation rate
> - Secret access patterns per path
> - Auth failures (potential security events)
>
> **Application metrics** (pods themselves):
> - CPU/memory usage, request latency, error rates
> - Pod restart counts, OOMKill events
>
> **Grafana alerts** configured for:
> - Argo CD sync failure → Slack notification
> - Critical vulnerability found in Harbor → PagerDuty
> - Vault sealed → PagerDuty (P1)
> - Pod CrashLoopBackOff → Slack
> - Resource utilization > 80% → Slack"

### Q: Why not use Azure DevOps's built-in release management instead of Argo CD?

> "Azure DevOps has release pipelines, but they're **push-based**. Argo CD adds value that Azure Pipelines alone can't provide:
> - **Continuous drift detection** — we see in real-time if the cluster state differs from Git
> - **Visual resource tree** — the UI shows Deployments → ReplicaSets → Pods with health status
> - **Self-heal** — in dev, if someone manually deletes a resource, Argo CD recreates it
> - **Multi-cluster management** — one Argo CD instance can manage dev, UAT, and prod clusters
> - **History and rollback** — every sync is recorded with what changed and when
>
> We use Azure Pipelines for **CI** (build, test, scan, push) and Argo CD for **CD** (deploy, monitor, reconcile). Each tool does what it's best at."

---

## Key Terms to Use in Interviews

| Term | How to Use It |
|------|---------------|
| **GitOps** | "We follow a GitOps model — Git is the single source of truth for cluster state" |
| **Change Management** | "UAT and prod deployments go through our change management process with approvals" |
| **Approval Gates** | "Azure Pipeline stages have approval gates — the change manager must approve before proceeding" |
| **Manual Sync** | "We use manual sync in Argo CD for UAT and prod to align with our change windows" |
| **Shift Left** | "We shift security left — Harbor scans images before they reach any cluster" |
| **Least Privilege** | "Each environment has its own Vault policy scoped to only its secret paths" |
| **Secret Zero** | "We solve the secret-zero problem using Kubernetes ServiceAccount auth with Vault" |
| **Separation of Concerns** | "Azure Pipelines handles CI, Argo CD handles CD, Vault handles secrets, Harbor handles images" |
| **Immutable Infrastructure** | "We never patch running containers — we build new images and deploy through the pipeline" |
| **Observability** | "Prometheus scrapes metrics from all components; Grafana provides dashboards and alerting" |
| **Drift Detection** | "Argo CD continuously compares Git vs. cluster state — we see drift even without auto-sync" |
| **Defense in Depth** | "Multiple security layers: Harbor scans, Vault encryption, RBAC policies, approval gates" |

---

## Architecture Diagram to Draw on a Whiteboard

Draw in this order — explain each component as you draw it:

**Step 1:** Draw the developer and Azure Pipelines
```
Developer → PR merge → Azure Pipelines
```

**Step 2:** Draw the three stages with gates
```
Azure Pipelines:  [DEV auto] ──approval──► [UAT] ──approval──► [PROD]
                      │                       │                    │
                   (each stage updates Git overlay for that env)
```

**Step 3:** Draw Harbor and the connection
```
Azure Pipelines ──build+push──► Harbor (Trivy scan)
```

**Step 4:** Draw the Git repo with Kustomize structure
```
Git Repo:  base/ + overlays/dev/ + overlays/uat/ + overlays/prod/
```

**Step 5:** Draw Argo CD with manual vs auto
```
Argo CD ──watches──► Git
  │
  ├── dev app    (auto-sync)
  ├── uat app    (manual sync, post-approval)
  └── prod app   (manual sync, change window)
```

**Step 6:** Draw Vault with per-env paths
```
Argo CD (AVP) ──fetch secrets──► Vault
                                   ├── secret/dev/
                                   ├── secret/uat/
                                   └── secret/prod/
```

**Step 7:** Draw Kubernetes and monitoring
```
Argo CD ──deploy──► Kubernetes (dev/uat/prod clusters)
                         │
                    metrics via Prometheus
                         │
                    Grafana dashboards + alerts
```

---

## Sample Conversation Script

**Interviewer:** "Tell me about your CI/CD architecture."

**You:** "Sure. We have a GitOps-based pipeline. On the CI side, we use **Azure Pipelines** with a multi-stage setup — dev, UAT, and production. Each stage has its own responsibilities and approval gates.

When a developer merges a PR, the pipeline builds a Docker image, runs tests, and pushes the image to **Harbor** — our private container registry. Harbor auto-scans every image with Trivy for vulnerabilities.

For deployment, we use **Argo CD** in a GitOps model. The pipeline doesn't deploy directly — instead, it updates the image tag in our Kustomize overlays in Git. Each environment has its own overlay. For dev, Argo CD auto-syncs immediately. For UAT and prod, we follow **change management** — the change manager approves the pipeline stage, and then the team manually triggers the Argo CD sync during the approved window.

Secrets are managed by **HashiCorp Vault**. Our manifests in Git contain placeholders, and the **Argo Vault Plugin** resolves them from Vault at sync time. Each environment has isolated Vault paths and policies, so the dev role can't access production secrets.

For observability, we have **Prometheus** scraping metrics from Argo CD, Harbor, Vault, and the applications themselves, with **Grafana** dashboards and alerts for sync failures, critical CVEs, Vault seal status, and pod health."

**Interviewer:** "Why not auto-sync in production?"

**You:** "Change management. Every prod deployment needs an approved change request. Auto-sync would bypass that — a commit at 2 AM shouldn't auto-deploy to production. We still get value from Argo CD without auto-sync: drift detection, visual diff of what will change, sync history, and one-click rollback. We just control *when* the sync happens."

**Interviewer:** "How do secrets work without being in Git?"

**You:** "Our Secret manifests contain placeholders like `<path:secret/data/prod/myapp#db_password>`. The Argo Vault Plugin, running as a sidecar on the Argo CD repo-server, authenticates with Vault using Kubernetes ServiceAccount auth — no passwords to manage. It replaces placeholders with real values at sync time. So Git has the *shape* of the secret, but never the *values*. Even Harbor registry credentials are managed by Vault via the External Secrets Operator."
