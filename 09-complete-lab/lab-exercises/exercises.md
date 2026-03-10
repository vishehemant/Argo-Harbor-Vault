# Lab Exercises

Hands-on exercises to practice each integration point. Complete them in order.

---

## Exercise 1: JFrog — Set Up a Private npm Package

**Goal:** Publish a private npm package to JFrog and consume it in a build.

```bash
# 1. Port-forward JFrog
kubectl port-forward svc/artifactory -n jfrog 8082:8082 &

# 2. Configure npm to use JFrog
npm config set registry http://localhost:8082/artifactory/api/npm/npm-virtual/
npm login --registry http://localhost:8082/artifactory/api/npm/npm-virtual/
#   Username: admin
#   Password: password

# 3. Create a simple private package
mkdir my-private-pkg && cd my-private-pkg
npm init -y --scope=@myorg
echo "module.exports = { greet: () => 'Hello from JFrog!' };" > index.js

# 4. Publish to JFrog
npm publish --registry http://localhost:8082/artifactory/api/npm/npm-local/

# 5. Verify in JFrog UI: Artifacts > npm-local > @myorg/my-private-pkg

# 6. Consume it in another project
cd .. && mkdir test-app && cd test-app
npm init -y
npm install @myorg/my-private-pkg
# This pulls from npm-virtual (which includes npm-local + npm-remote)
```

**Verify:** Check the JFrog UI — you should see your package in `npm-local` and cached public packages in `npm-remote`.

---

## Exercise 2: JFrog Docker Proxy — Avoid Docker Hub Rate Limits

**Goal:** Pull public Docker images through JFrog's proxy cache.

```bash
# 1. Configure Docker to use JFrog as a mirror
# For kind clusters, this is done via containerd config

# 2. Pull an image through JFrog's Docker remote proxy
docker pull localhost:8082/docker-remote/nginx:1.25-alpine

# 3. Pull again — this time from JFrog's cache (much faster)
docker pull localhost:8082/docker-remote/nginx:1.25-alpine

# 4. Check JFrog UI: Artifacts > docker-remote > nginx
#    You should see the cached layers
```

**Verify:** The second pull should be significantly faster (cached in JFrog).

---

## Exercise 3: Harbor — Push and Scan an Image

**Goal:** Build an image, push to Harbor, and review the vulnerability scan.

```bash
# 1. Build the sample app
docker build -t localhost:8080/my-app/sample-web:v1.0.0 -f 01-harbor-basics/Dockerfile 01-harbor-basics/

# 2. Push to Harbor
docker login localhost:8080 -u admin -p Harbor12345
docker push localhost:8080/my-app/sample-web:v1.0.0

# 3. Check Harbor UI: Projects > my-app > sample-web > v1.0.0
#    Click the tag to see the Trivy scan results

# 4. Via API: check scan results
curl -u "admin:Harbor12345" \
  "http://localhost:8080/api/v2.0/projects/my-app/repositories/sample-web/artifacts/v1.0.0?with_scan_overview=true" | jq .
```

**Verify:** The image should show scan results with vulnerability counts.

---

## Exercise 4: Vault — Store and Retrieve JFrog Credentials

**Goal:** Store JFrog credentials in Vault and verify access control.

```bash
# 1. Store JFrog credentials
kubectl exec -n vault vault-0 -- vault kv put secret/registry/jfrog \
  url="jfrog.example.com" \
  username="ci-user" \
  password="jfrog-token-123" \
  npm_token="jfrog-npm-auth-token"

# 2. Read them back
kubectl exec -n vault vault-0 -- vault kv get secret/registry/jfrog

# 3. Create a policy that only allows reading registry creds
kubectl exec -n vault vault-0 -- vault policy write registry-read - <<'POLICY'
path "secret/data/registry/*" {
  capabilities = ["read"]
}
POLICY

# 4. Create a token with this policy
kubectl exec -n vault vault-0 -- vault token create -policy=registry-read -format=json

# 5. Try reading prod secrets with this token — should FAIL
# (demonstrates least privilege)
```

**Verify:** The registry-read token can read `secret/registry/*` but NOT `secret/prod/*`.

---

## Exercise 5: Argo CD — Deploy with Helm + AVP

**Goal:** Deploy the app using Helm templates with Vault secret injection.

```bash
# 1. Store app secrets in Vault
kubectl exec -n vault vault-0 -- vault kv put secret/dev/myapp/config \
  db_host="postgres.myapp-dev.svc" \
  db_port="5432" \
  db_user="devuser" \
  db_password="dev-secret-password"

# 2. Apply the dev Argo CD Application
kubectl apply -f argocd-apps/argocd-apps.yaml

# 3. Check the app
argocd app get myapp-dev

# 4. Verify secrets were resolved from Vault
kubectl get secret sample-web-config -n myapp-dev -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
# Should output: dev-secret-password
```

**Verify:** The Kubernetes Secret contains real values from Vault, not the AVP placeholders.

---

## Exercise 6: Secret Rotation

**Goal:** Rotate a database password in Vault and verify the app picks it up.

```bash
# 1. Update the password in Vault
kubectl exec -n vault vault-0 -- vault kv put secret/dev/myapp/config \
  db_host="postgres.myapp-dev.svc" \
  db_port="5432" \
  db_user="devuser" \
  db_password="NEW-rotated-password-2026"

# 2. Trigger an Argo CD sync
argocd app sync myapp-dev

# 3. Verify the new password
kubectl get secret sample-web-config -n myapp-dev -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
# Should output: NEW-rotated-password-2026

# 4. Restart pods to pick up the new secret
kubectl rollout restart deployment/sample-web -n myapp-dev
```

**Verify:** After sync + restart, the pods use the rotated password.

---

## Exercise 7: Monitoring — Check Grafana Dashboards

**Goal:** Explore the monitoring stack and understand the metrics.

```bash
# 1. Access Grafana
kubectl port-forward svc/kube-prometheus-grafana -n monitoring 3000:80 &
# http://localhost:3000 — admin / prom-operator

# 2. Explore built-in dashboards:
#    - Kubernetes / Compute Resources / Namespace (Pods)
#    - Kubernetes / Compute Resources / Node (Pods)

# 3. Import the custom dashboard:
#    Dashboard > Import > Upload JSON
#    Select: monitoring/grafana-dashboards/dashboard-overview.json

# 4. Explore Prometheus targets:
kubectl port-forward svc/kube-prometheus-kube-prome-prometheus -n monitoring 9090:9090 &
# http://localhost:9090/targets
# Check that Harbor, Vault, Argo CD, JFrog targets are UP

# 5. Run sample PromQL queries:
#    argocd_app_info                          — all Argo CD apps with status
#    vault_core_unsealed                      — 1=unsealed, 0=sealed
#    harbor_project_artifact_dangerous_count  — images with critical CVEs
#    rate(kube_pod_container_status_restarts_total[5m]) — pod restart rate
```

**Verify:** All targets show "UP" in Prometheus, and Grafana dashboards display data.

---

## Exercise 8: Full Pipeline Simulation

**Goal:** Simulate the complete Azure Pipeline → Harbor → Vault → Argo CD flow.

```bash
# 1. "CI builds and pushes" — manually push a new image tag
docker build -t localhost:8080/my-app/sample-web:v2.0.0 -f 01-harbor-basics/Dockerfile 01-harbor-basics/
docker push localhost:8080/my-app/sample-web:v2.0.0

# 2. "CI updates Helm values" — simulate what Azure Pipeline does
cd 09-complete-lab/helm-chart
yq e '.image.tag = "v2.0.0"' -i values/dev.yaml
git add values/dev.yaml
git commit -m "ci(dev): update image to v2.0.0"
git push

# 3. Argo CD detects the change
argocd app get myapp-dev
# Should show OutOfSync (or auto-sync if enabled)

# 4. If manual sync:
argocd app sync myapp-dev

# 5. Verify the new version is running
kubectl get pods -n myapp-dev -o jsonpath='{.items[0].spec.containers[0].image}'
# Should show: harbor.example.com/my-app/sample-web:v2.0.0

# 6. Check Grafana — the deployment should appear in the Argo CD sync metrics
```

**Verify:** The full chain works: new image → Git update → Argo CD sync → new pods running.
