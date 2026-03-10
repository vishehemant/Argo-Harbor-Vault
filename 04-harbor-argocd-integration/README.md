# 04 - Harbor + Argo CD Integration

## The Scenario

You have a **private Harbor registry** and want **Argo CD** to deploy applications using images stored in Harbor. This requires:

1. Argo CD needs credentials to **pull manifests** (if your Git repo is private)
2. Kubernetes needs credentials to **pull images** from Harbor
3. Your Deployment manifests reference images by their Harbor URL

```
┌──────────┐     watches      ┌──────────┐     pulls image    ┌──────────┐
│  Git     │◄────────────────│  Argo CD  │─────────────────►│  Harbor   │
│  Repo    │     manifests    │          │     (via K8s)      │ Registry │
└──────────┘                  └──────────┘                    └──────────┘
                                   │
                              deploys to
                                   │
                                   ▼
                             ┌──────────┐
                             │Kubernetes│
                             │ Cluster  │
                             └──────────┘
```

## Approach 1: Image Pull Secret (Simplest)

Create a Kubernetes Secret with Harbor credentials, and reference it in your Deployment.

### Step 1: Create the Image Pull Secret

```bash
# Option A: kubectl create (imperative)
kubectl create secret docker-registry harbor-pull-secret \
  --docker-server=harbor.example.com \
  --docker-username='robot$ci-pipeline' \
  --docker-password='<robot-secret>' \
  --docker-email='ci@example.com' \
  --namespace=my-app

# Option B: Apply the YAML (declarative — better for GitOps)
kubectl apply -f registry-credentials/image-pull-secret.yaml
```

See [registry-credentials/image-pull-secret.yaml](./registry-credentials/image-pull-secret.yaml).

### Step 2: Reference It in Your Deployment

```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: harbor-pull-secret
      containers:
        - name: app
          image: harbor.example.com/my-app/sample-web:v1.0.0
```

See [sample-app/deployment.yaml](./sample-app/deployment.yaml) for the complete manifest.

## Approach 2: Patch the Default ServiceAccount (Cluster-Wide)

Instead of adding `imagePullSecrets` to every Deployment, patch the `default` ServiceAccount so all Pods in the namespace automatically use it.

```bash
kubectl patch serviceaccount default \
  -n my-app \
  -p '{"imagePullSecrets": [{"name": "harbor-pull-secret"}]}'
```

## Approach 3: Register Harbor as an Argo CD Repository (for Helm Charts in OCI)

Harbor supports OCI artifacts, including Helm charts. You can store Helm charts in Harbor and have Argo CD install them.

```bash
# Register Harbor as a Helm OCI repository in Argo CD
argocd repo add harbor.example.com \
  --type helm \
  --name harbor-charts \
  --enable-oci \
  --username 'robot$ci-pipeline' \
  --password '<robot-secret>'
```

Or declaratively via [registry-credentials/argocd-repo-secret.yaml](./registry-credentials/argocd-repo-secret.yaml).

## Approach 4: Argo CD Image Updater (Automatic Image Updates)

[Argo CD Image Updater](https://argocd-image-updater.readthedocs.io/) watches Harbor for new image tags and automatically updates the Application to use the latest image.

```bash
# Install the image updater
helm install argocd-image-updater argo/argocd-image-updater \
  --namespace argocd

# Configure the Application with image updater annotations
kubectl apply -f argocd-application-with-image-updater.yaml
```

See [argocd-application-with-image-updater.yaml](./argocd-application-with-image-updater.yaml) for the annotated Application.

## Complete Walkthrough

```bash
# 1. Ensure Harbor is running and you have a robot account (see 01-harbor-basics/)

# 2. Build and push an image to Harbor
cd ../01-harbor-basics
docker build -t harbor.example.com/my-app/sample-web:v1.0.0 -f Dockerfile .
docker push harbor.example.com/my-app/sample-web:v1.0.0

# 3. Create the namespace and image pull secret
kubectl create namespace my-app
kubectl apply -f registry-credentials/image-pull-secret.yaml

# 4. Deploy via Argo CD
kubectl apply -f argocd-application.yaml

# 5. Watch the deployment
argocd app get harbor-sample-app
kubectl get pods -n my-app -w
```

## Key Concepts

| Concept | Why It Matters |
|---------|---------------|
| **imagePullSecrets** | Kubernetes needs registry credentials to pull private images |
| **Robot Account** | Use Harbor robot accounts (not admin) for CI/CD and K8s image pulls |
| **OCI Registry** | Harbor supports OCI artifacts — you can store both images AND Helm charts |
| **Image Updater** | Automates the "update image tag in Git" step of the CI/CD pipeline |

## Files in This Directory

| File | Purpose |
|------|---------|
| `registry-credentials/image-pull-secret.yaml` | Kubernetes Secret for pulling images from Harbor |
| `registry-credentials/argocd-repo-secret.yaml` | Argo CD repository credential for Harbor (Helm OCI) |
| `sample-app/deployment.yaml` | Deployment using a Harbor-hosted image |
| `sample-app/service.yaml` | Service for the sample app |
| `sample-app/kustomization.yaml` | Kustomize file |
| `argocd-application.yaml` | Argo CD Application pointing to sample-app/ |
| `argocd-application-with-image-updater.yaml` | Argo CD Application with Image Updater annotations |
