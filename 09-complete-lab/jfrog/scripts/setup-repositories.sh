#!/usr/bin/env bash
# Sets up JFrog Artifactory repositories for the complete lab.
#
# Creates:
#   LOCAL repos  — your private artifacts
#   REMOTE repos — proxy + cache for public registries
#   VIRTUAL repos — unified endpoints combining local + remote
#
# Usage: ./setup-repositories.sh

set -euo pipefail

JFROG_URL="${JFROG_URL:-http://localhost:8082}"
JFROG_USER="${JFROG_USER:-admin}"
JFROG_PASS="${JFROG_PASS:-password}"
AUTH="-u ${JFROG_USER}:${JFROG_PASS}"

echo "==> Setting up JFrog Artifactory repositories..."
echo "    URL: ${JFROG_URL}"
echo ""

# ─────────────────────────────────────────────
# Docker repositories
# ─────────────────────────────────────────────
echo "==> Creating Docker repositories..."

# LOCAL: your private Docker images (alternative to Harbor for some teams)
curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/docker-local" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "docker-local",
    "rclass": "local",
    "packageType": "docker",
    "description": "Private Docker images built by our CI pipeline"
  }' && echo " docker-local created"

# REMOTE: proxy + cache for Docker Hub (saves bandwidth, avoids rate limits)
curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/docker-remote" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "docker-remote",
    "rclass": "remote",
    "packageType": "docker",
    "url": "https://registry-1.docker.io/",
    "description": "Proxy cache for Docker Hub (avoids rate limits)"
  }' && echo " docker-remote created"

# VIRTUAL: single endpoint combining local + remote
curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/docker-virtual" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "docker-virtual",
    "rclass": "virtual",
    "packageType": "docker",
    "repositories": ["docker-local", "docker-remote"],
    "defaultDeploymentRepo": "docker-local",
    "description": "Virtual Docker repo — use this as your registry endpoint"
  }' && echo " docker-virtual created"

echo ""

# ─────────────────────────────────────────────
# npm repositories (Node.js packages)
# ─────────────────────────────────────────────
echo "==> Creating npm repositories..."

curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/npm-local" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "npm-local",
    "rclass": "local",
    "packageType": "npm",
    "description": "Private npm packages published by our teams"
  }' && echo " npm-local created"

curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/npm-remote" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "npm-remote",
    "rclass": "remote",
    "packageType": "npm",
    "url": "https://registry.npmjs.org",
    "description": "Proxy cache for public npm registry"
  }' && echo " npm-remote created"

curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/npm-virtual" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "npm-virtual",
    "rclass": "virtual",
    "packageType": "npm",
    "repositories": ["npm-local", "npm-remote"],
    "defaultDeploymentRepo": "npm-local",
    "description": "Virtual npm repo — set as your npm registry"
  }' && echo " npm-virtual created"

echo ""

# ─────────────────────────────────────────────
# Maven repositories (Java)
# ─────────────────────────────────────────────
echo "==> Creating Maven repositories..."

curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/maven-local" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "maven-local",
    "rclass": "local",
    "packageType": "maven",
    "description": "Private Maven artifacts"
  }' && echo " maven-local created"

curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/maven-remote" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "maven-remote",
    "rclass": "remote",
    "packageType": "maven",
    "url": "https://repo1.maven.org/maven2/",
    "description": "Proxy cache for Maven Central"
  }' && echo " maven-remote created"

curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/maven-virtual" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "maven-virtual",
    "rclass": "virtual",
    "packageType": "maven",
    "repositories": ["maven-local", "maven-remote"],
    "defaultDeploymentRepo": "maven-local",
    "description": "Virtual Maven repo"
  }' && echo " maven-virtual created"

echo ""

# ─────────────────────────────────────────────
# PyPI repositories (Python)
# ─────────────────────────────────────────────
echo "==> Creating PyPI repositories..."

curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/pypi-local" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "pypi-local",
    "rclass": "local",
    "packageType": "pypi",
    "description": "Private Python packages"
  }' && echo " pypi-local created"

curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/pypi-remote" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "pypi-remote",
    "rclass": "remote",
    "packageType": "pypi",
    "url": "https://pypi.org",
    "description": "Proxy cache for PyPI"
  }' && echo " pypi-remote created"

curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/pypi-virtual" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "pypi-virtual",
    "rclass": "virtual",
    "packageType": "pypi",
    "repositories": ["pypi-local", "pypi-remote"],
    "defaultDeploymentRepo": "pypi-local",
    "description": "Virtual PyPI repo"
  }' && echo " pypi-virtual created"

echo ""

# ─────────────────────────────────────────────
# Helm chart repository
# ─────────────────────────────────────────────
echo "==> Creating Helm repositories..."

curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/helm-local" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "helm-local",
    "rclass": "local",
    "packageType": "helm",
    "description": "Private Helm charts"
  }' && echo " helm-local created"

curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/helm-bitnami-remote" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "helm-bitnami-remote",
    "rclass": "remote",
    "packageType": "helm",
    "url": "https://charts.bitnami.com/bitnami",
    "description": "Proxy cache for Bitnami Helm charts"
  }' && echo " helm-bitnami-remote created"

curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/helm-virtual" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "helm-virtual",
    "rclass": "virtual",
    "packageType": "helm",
    "repositories": ["helm-local", "helm-bitnami-remote"],
    "defaultDeploymentRepo": "helm-local",
    "description": "Virtual Helm repo"
  }' && echo " helm-virtual created"

echo ""

# ─────────────────────────────────────────────
# Go module repository
# ─────────────────────────────────────────────
echo "==> Creating Go repositories..."

curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/go-local" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "go-local",
    "rclass": "local",
    "packageType": "go",
    "description": "Private Go modules"
  }' && echo " go-local created"

curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/go-remote" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "go-remote",
    "rclass": "remote",
    "packageType": "go",
    "url": "https://proxy.golang.org/",
    "description": "Proxy cache for Go module proxy"
  }' && echo " go-remote created"

curl -s $AUTH -X PUT "${JFROG_URL}/artifactory/api/repositories/go-virtual" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "go-virtual",
    "rclass": "virtual",
    "packageType": "go",
    "repositories": ["go-local", "go-remote"],
    "defaultDeploymentRepo": "go-local",
    "description": "Virtual Go repo"
  }' && echo " go-virtual created"

echo ""
echo "==> All repositories created!"
echo ""
echo "Client configuration:"
echo ""
echo "  Docker:  docker login ${JFROG_URL}/docker-virtual"
echo "  npm:     npm config set registry ${JFROG_URL}/artifactory/api/npm/npm-virtual/"
echo "  Maven:   Configure ${JFROG_URL}/artifactory/maven-virtual in settings.xml"
echo "  PyPI:    pip install --index-url ${JFROG_URL}/artifactory/api/pypi/pypi-virtual/simple/"
echo "  Go:      export GOPROXY=${JFROG_URL}/artifactory/api/go/go-virtual"
echo "  Helm:    helm repo add myrepo ${JFROG_URL}/artifactory/helm-virtual"
