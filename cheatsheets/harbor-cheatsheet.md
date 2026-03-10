# Harbor Cheatsheet

## Docker Commands

```bash
# Login to Harbor
docker login harbor.example.com -u 'robot$ci-pipeline' -p '<secret>'

# Build and tag
docker build -t harbor.example.com/PROJECT/IMAGE:TAG .

# Push
docker push harbor.example.com/PROJECT/IMAGE:TAG

# Pull
docker pull harbor.example.com/PROJECT/IMAGE:TAG
```

## Harbor API (v2.0)

```bash
BASE="https://harbor.example.com/api/v2.0"
AUTH="-u admin:Harbor12345"

# List projects
curl -sk $AUTH "$BASE/projects"

# Create project
curl -sk $AUTH -X POST "$BASE/projects" \
  -H "Content-Type: application/json" \
  -d '{"project_name":"my-app","public":false}'

# List repositories in a project
curl -sk $AUTH "$BASE/projects/my-app/repositories"

# List tags for a repository
curl -sk $AUTH "$BASE/projects/my-app/repositories/sample-web/artifacts"

# Trigger vulnerability scan
curl -sk $AUTH -X POST \
  "$BASE/projects/my-app/repositories/sample-web/artifacts/v1.0.0/scan"

# Get scan results
curl -sk $AUTH \
  "$BASE/projects/my-app/repositories/sample-web/artifacts/v1.0.0?with_scan_overview=true"

# Create robot account
curl -sk $AUTH -X POST "$BASE/robots" \
  -H "Content-Type: application/json" \
  -d '{
    "name":"ci-bot",
    "duration":365,
    "level":"project",
    "permissions":[{
      "namespace":"my-app",
      "kind":"project",
      "access":[
        {"resource":"repository","action":"push"},
        {"resource":"repository","action":"pull"}
      ]
    }]
  }'

# Delete an image tag
curl -sk $AUTH -X DELETE \
  "$BASE/projects/my-app/repositories/sample-web/artifacts/v1.0.0"

# Get system health
curl -sk $AUTH "$BASE/health"
```

## Kubernetes Image Pull Secret

```bash
# Create
kubectl create secret docker-registry harbor-creds \
  --docker-server=harbor.example.com \
  --docker-username='robot$ci-pipeline' \
  --docker-password='<secret>' \
  -n my-app

# Verify
kubectl get secret harbor-creds -n my-app -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d

# Patch default ServiceAccount (auto-use for all Pods)
kubectl patch sa default -n my-app \
  -p '{"imagePullSecrets":[{"name":"harbor-creds"}]}'
```

## Helm Chart Installation

```bash
helm repo add harbor https://helm.goharbor.io
helm repo update
helm install harbor harbor/harbor -n harbor --create-namespace -f values.yaml

# Upgrade
helm upgrade harbor harbor/harbor -n harbor -f values.yaml

# Uninstall
helm uninstall harbor -n harbor
```

## Key Concepts

| Term | Meaning |
|------|---------|
| Project | Namespace for repositories (like a Docker Hub organization) |
| Repository | Collection of image tags (e.g., `my-app/backend`) |
| Artifact | A specific image digest (can have multiple tags) |
| Robot Account | Service account with scoped permissions |
| Replication | Copy images between registries |
| Vulnerability Scan | CVE detection using Trivy |
| Tag Immutability | Prevent overwriting existing tags |
| Quota | Limit storage per project |
