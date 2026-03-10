#!/usr/bin/env bash
# Builds and pushes the sample app image to Harbor.
#
# Usage: ./push-image.sh <tag>
#
# Example:
#   ./push-image.sh v1.0.0
#   ./push-image.sh $(git rev-parse --short HEAD)

set -euo pipefail

HARBOR_URL="${HARBOR_URL:-harbor.example.com}"
PROJECT="${HARBOR_PROJECT:-my-app}"
IMAGE_NAME="${IMAGE_NAME:-sample-web}"
TAG="${1:?Usage: $0 <tag>}"

FULL_IMAGE="${HARBOR_URL}/${PROJECT}/${IMAGE_NAME}:${TAG}"

echo "==> Building image: ${FULL_IMAGE}"
docker build -t "${FULL_IMAGE}" -f ../Dockerfile ..

echo "==> Pushing image to Harbor..."
docker push "${FULL_IMAGE}"

echo "==> Done! Image available at: ${FULL_IMAGE}"
echo ""
echo "To deploy this image via Argo CD, update the image tag in your manifests."
echo "See ../04-harbor-argocd-integration/ for examples."
