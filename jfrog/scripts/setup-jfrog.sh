#!/usr/bin/env bash
# Setup JFrog Artifactory for Tetris DevSecOps project
# Creates LOCAL, REMOTE, and VIRTUAL repositories for npm, Docker, and Helm

set -e

# Configuration from env with defaults
JFROG_URL="${JFROG_URL:-https://artifactory.example.com/artifactory}"
JFROG_USER="${JFROG_USER:-admin}"
JFROG_PASS="${JFROG_PASS:-password}"

# Normalize URL (remove trailing slash)
JFROG_URL="${JFROG_URL%/}"
# API base: Artifactory REST API is at /artifactory/api/repositories
JFROG_API="${JFROG_URL}/api/repositories"

echo "=== JFrog Artifactory Setup for Tetris ==="
echo "JFrog URL: ${JFROG_URL}"
echo ""

create_repo() {
  local key="$1"
  local config="$2"
  echo "Creating repository: ${key}..."
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    "${JFROG_API}/${key}" \
    -u "${JFROG_USER}:${JFROG_PASS}" \
    -H "Content-Type: application/json" \
    -d "${config}")
  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
    echo "  Created: ${key}"
  elif [[ "$HTTP_CODE" == "400" ]]; then
    echo "  Already exists or error: ${key} (HTTP ${HTTP_CODE})"
  else
    echo "  WARNING: ${key} - HTTP ${HTTP_CODE}"
  fi
}

# --- npm repositories ---
create_repo "npm-local" '{"rclass":"local","packageType":"npm"}'
create_repo "npm-remote" '{"rclass":"remote","packageType":"npm","url":"https://registry.npmjs.org"}'
create_repo "npm-virtual" '{"rclass":"virtual","packageType":"npm","repositories":["npm-local","npm-remote"]}'

# --- Docker repositories ---
create_repo "docker-local" '{"rclass":"local","packageType":"docker"}'
create_repo "docker-remote" '{"rclass":"remote","packageType":"docker","url":"https://registry-1.docker.io/"}'
create_repo "docker-virtual" '{"rclass":"virtual","packageType":"docker","repositories":["docker-local","docker-remote"]}'

# --- Helm repositories ---
create_repo "helm-local" '{"rclass":"local","packageType":"helm"}'
create_repo "helm-remote" '{"rclass":"remote","packageType":"helm","url":"https://charts.helm.sh/stable"}'
create_repo "helm-virtual" '{"rclass":"virtual","packageType":"helm","repositories":["helm-local","helm-remote"]}'

echo ""
echo "=== Client Configuration Commands ==="
echo ""
echo "--- npm ---"
echo "npm config set registry ${JFROG_URL}/api/npm/npm-virtual/"
echo "npm login --registry=${JFROG_URL}/api/npm/npm-virtual/"
echo ""
echo "--- Docker ---"
JFROG_HOST="${JFROG_URL#https://}"
JFROG_HOST="${JFROG_HOST#http://}"
JFROG_HOST="${JFROG_HOST%%/*}"
echo "docker login ${JFROG_HOST} -u ${JFROG_USER} -p <password>"
echo "# Or configure /etc/docker/daemon.json:"
echo '# {"insecure-registries": ["artifactory.example.com:8082"]}'
echo ""
echo "--- Helm ---"
echo "helm repo add artifactory ${JFROG_URL}/helm-virtual/ --username ${JFROG_USER} --password <password>"
echo ""
