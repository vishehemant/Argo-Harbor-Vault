# Interview Guide: Harbor + Argo CD + Vault Architecture

## The 2-Minute Elevator Pitch

> "In our setup, we follow a **GitOps approach** for Kubernetes deployments using three key tools.
>
> **Harbor** is our private container registry — it stores all our Docker images and automatically scans them for vulnerabilities before they reach production.
>
> **HashiCorp Vault** is our centralized secrets manager — instead of hardcoding passwords or API keys in YAML files or Kubernetes Secrets, everything lives in Vault with encryption, access control, and audit logging.
>
> **Argo CD** is our GitOps delivery tool — it watches our Git repository and automatically deploys changes to Kubernetes. The key integration is the **Argo Vault Plugin**, which lets us put secret placeholders in Git and resolves them from Vault at deploy time. So secrets never touch Git.
>
> For registry credentials, we use the **External Secrets Operator** to dynamically create Kubernetes image pull secrets from Vault. This means even our Harbor credentials are managed by Vault and automatically rotated.
>
> The end-to-end flow is: developer pushes code → CI builds and pushes the image to Harbor → CI updates the image tag in Git → Argo CD detects the change, fetches secrets from Vault, and deploys to the cluster."

---

## How to Explain the Flow (Step by Step)

When the interviewer asks "walk me through a deployment," use this structure:

### Step 1: Developer Pushes Code

> "A developer merges a PR into the main branch. This triggers our CI pipeline — in our case GitHub Actions."

### Step 2: CI Builds and Pushes to Harbor

> "The CI pipeline builds a Docker image, tags it with the Git SHA or semantic version, and pushes it to **Harbor** — our private registry. Harbor automatically runs a **Trivy vulnerability scan** on the image. If critical CVEs are found, we can configure Harbor to block the image from being pulled, acting as a security gate."

### Step 3: CI Updates the Git Manifests

> "After the image is pushed, CI updates the `kustomization.yaml` file with the new image tag and commits it back to Git. This is the GitOps trigger — the source of truth changes."

### Step 4: Argo CD Detects the Change

> "Argo CD continuously watches the Git repo. It detects the new commit, clones the repo, and starts rendering the manifests."

### Step 5: Argo Vault Plugin Resolves Secrets

> "Here's where it gets interesting. Our Kubernetes Secret manifests in Git contain **placeholders** like `<path:secret/data/myapp/config#db_password>` instead of real values. The **Argo Vault Plugin** runs as a sidecar on the Argo CD repo-server. It authenticates with Vault using **Kubernetes ServiceAccount auth**, reads the real secret values, and replaces the placeholders. So the actual secrets are **never stored in Git**."

### Step 6: Image Pull Credentials from Vault

> "For pulling images from our private Harbor registry, we use the **External Secrets Operator**. It syncs Harbor robot account credentials from Vault into a Kubernetes `dockerconfigjson` Secret. This means even our registry credentials are centrally managed in Vault and can be rotated without touching any manifests."

### Step 7: Deployment to Kubernetes

> "Argo CD applies the fully resolved manifests. Kubernetes pulls the image from Harbor using the ESO-managed pull secret, and the pods start with real secrets injected as environment variables. If anything goes wrong, Argo CD shows the app as 'Degraded' and we can roll back by reverting the Git commit."

---

## Common Interview Questions and Answers

### Q: Why not just use Kubernetes Secrets directly?

> "Kubernetes Secrets are **base64-encoded, not encrypted**. Anyone with cluster access can decode them. They also lack audit logging — you don't know who accessed which secret and when. Vault provides **AES-256 encryption**, fine-grained **access policies**, full **audit logging**, **automatic rotation**, and **dynamic secrets** — for example, it can generate short-lived database credentials on demand."

### Q: Why Harbor instead of Docker Hub or ECR?

> "Harbor gives us **full control** over our registry — it runs inside our infrastructure so images never leave our network. It provides **built-in vulnerability scanning** with Trivy, **RBAC** at the project level, **image signing** for supply chain security, and **replication** between registries for disaster recovery. With Docker Hub, we'd be subject to rate limits and our images would be on someone else's infrastructure."

### Q: Why Argo CD instead of Helm install or kubectl apply in CI?

> "The traditional approach is **push-based** — CI runs `kubectl apply` and pushes changes to the cluster. The problem is: if someone runs `kubectl edit` directly, your cluster drifts from Git and nobody knows.
>
> Argo CD is **pull-based and declarative** — it continuously compares the cluster state with Git. If someone makes a manual change, Argo CD's **self-heal** reverts it automatically. Git becomes the single source of truth, and every change has an audit trail through Git history."

### Q: How do you handle secret rotation?

> "We have two mechanisms:
> 1. **Application secrets** (DB passwords, API keys) — we update them in Vault and trigger an Argo CD sync. AVP reads the new values and updates the Kubernetes Secrets. Pods pick up the changes on restart.
> 2. **Harbor credentials** — the External Secrets Operator **periodically syncs** from Vault (every hour by default). When we rotate the Harbor robot account password in Vault, ESO automatically updates the Kubernetes pull secret. No manual intervention needed."

### Q: What happens if Vault goes down?

> "Existing pods continue running — they already have their secrets injected. New deployments would fail because AVP can't resolve placeholders. That's why Vault is deployed in **HA mode** with Raft consensus in production — 3 or 5 replicas across availability zones. We also have alerts on Vault health and seal status."

### Q: How does Vault authenticate Argo CD? Isn't that circular?

> "No circular dependency. Vault uses **Kubernetes auth** — it validates the ServiceAccount token that's automatically mounted into the Argo CD repo-server pod. The flow is:
> 1. Argo CD repo-server has a Kubernetes ServiceAccount
> 2. Kubernetes signs a JWT for that ServiceAccount
> 3. Vault calls the Kubernetes API to verify the JWT
> 4. If valid, Vault issues a Vault token scoped to the `argocd` policy
>
> No passwords or tokens need to be pre-shared. The trust is bootstrapped through Kubernetes itself."

### Q: How do you prevent secrets from leaking into Git?

> "Three layers of protection:
> 1. **AVP placeholders** — manifests only contain references like `<path:secret/...#key>`, not real values
> 2. **Pre-commit hooks** — we scan for patterns that look like real secrets before allowing commits
> 3. **Vault policies** — even if someone gets a Vault token, they can only access paths allowed by their policy
>
> The principle is: Git stores **what** to deploy and **where** secrets come from, but never the secrets themselves."

### Q: What's the difference between AVP and External Secrets Operator?

> "They solve different problems:
> - **AVP** works at **Argo CD sync time** — it's a plugin inside the repo-server that processes YAML templates. Best for application secrets that are part of your deployment manifests.
> - **ESO** is a **standalone operator** that runs continuously — it syncs Vault secrets into Kubernetes Secrets on a schedule. Best for infrastructure credentials like image pull secrets that need to exist before Argo CD even syncs.
>
> We use both: ESO for Harbor pull credentials, AVP for application secrets."

### Q: How do you handle multiple environments (dev/staging/prod)?

> "Three layers of separation:
> 1. **Vault paths** — `secret/dev/myapp/`, `secret/staging/myapp/`, `secret/production/myapp/` with different policies per environment
> 2. **Kustomize overlays** — base manifests + environment-specific patches (different replicas, resource limits, image tags)
> 3. **Argo CD Applications** — separate Application CRDs per environment, each pointing to the correct Kustomize overlay and using a Vault role scoped to that environment's secrets"

### Q: How do you roll back a failed deployment?

> "Since we follow GitOps, rollback is just a **Git revert**:
> ```
> git revert HEAD
> git push
> ```
> Argo CD detects the reverted commit and syncs the previous working state. We can also use `argocd app rollback <app> <history-id>` from the CLI, or click 'History and Rollback' in the UI.
>
> The beauty of GitOps is that every deployment is a Git commit, so we have full traceability of what was deployed, when, and by whom."

### Q: What monitoring do you have on this pipeline?

> "Several layers:
> - **Argo CD notifications** — Slack alerts on sync success, failure, or health degradation
> - **Harbor webhooks** — alerts when critical vulnerabilities are found in scanned images
> - **Vault audit logs** — every secret access is logged with who, what, when
> - **Prometheus metrics** — Argo CD, Harbor, and Vault all expose Prometheus metrics for dashboards and alerting"

---

## Key Terms to Use in Interviews

| Term | When to Use |
|------|-------------|
| **GitOps** | "We follow a GitOps model where Git is the source of truth" |
| **Declarative** | "Our infrastructure is declaratively defined in Git" |
| **Self-heal** | "Argo CD self-heals any manual drift from the desired state" |
| **Shift left** | "We shift security left by scanning images in Harbor before deployment" |
| **Least privilege** | "Each service has a Vault policy with the minimum permissions it needs" |
| **Secret zero problem** | "We solve the secret-zero problem using Kubernetes ServiceAccount auth" |
| **Supply chain security** | "Harbor provides image signing and scanning for supply chain security" |
| **Separation of concerns** | "CI handles building, Harbor handles storage/scanning, Vault handles secrets, Argo CD handles deployment" |
| **Immutable infrastructure** | "We don't patch running containers — we build new images and deploy them through the pipeline" |
| **Infrastructure as Code** | "All our manifests, policies, and configurations are versioned in Git" |

---

## Architecture Diagram to Draw on a Whiteboard

If asked to draw the architecture, use this simplified version:

```
    Developer
        │
        │ git push
        ▼
    ┌────────┐     build + push      ┌────────┐
    │ GitHub  │ ───────────────────── │ Harbor  │
    │ Actions │                       │ (scan)  │
    └───┬────┘                       └────┬───┘
        │                                  │
        │ update image tag                 │ pull image
        ▼                                  ▼
    ┌────────┐     read secrets       ┌─────────┐
    │  Git   │ ◄──── Argo CD ───────► │  Vault  │
    │ (YAML) │       (+ AVP)          │(secrets)│
    └────────┘                        └────┬────┘
                      │                     │
                      │ deploy              │ ESO syncs
                      ▼                     │ pull creds
                 ┌──────────┐               │
                 │Kubernetes│ ◄─────────────┘
                 │ Cluster  │
                 └──────────┘
```

Draw it in this order:
1. Start with the Developer at the top
2. Draw the CI pipeline (GitHub Actions) connecting to Harbor
3. Draw Git repo in the middle
4. Draw Argo CD connecting Git to Kubernetes
5. Draw Vault on the side connecting to both Argo CD and Kubernetes
6. Explain each arrow as you draw it
