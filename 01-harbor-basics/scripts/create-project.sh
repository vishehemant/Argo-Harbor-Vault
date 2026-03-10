#!/usr/bin/env bash
# Creates a Harbor project with auto-scan enabled.
#
# Usage: ./create-project.sh <project-name> [public|private]
#
# Example:
#   ./create-project.sh my-app private

set -euo pipefail

HARBOR_URL="${HARBOR_URL:-https://harbor.example.com}"
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_PASS="${HARBOR_PASS:-Harbor12345}"
PROJECT_NAME="${1:?Usage: $0 <project-name> [public|private]}"
VISIBILITY="${2:-private}"

if [ "$VISIBILITY" = "public" ]; then
  PUBLIC="true"
else
  PUBLIC="false"
fi

echo "Creating project '$PROJECT_NAME' (${VISIBILITY}) on ${HARBOR_URL}..."

HTTP_CODE=$(curl -sk -o /tmp/harbor-response.json -w "%{http_code}" \
  -u "${HARBOR_USER}:${HARBOR_PASS}" \
  -X POST "${HARBOR_URL}/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d "{
    \"project_name\": \"${PROJECT_NAME}\",
    \"public\": ${PUBLIC},
    \"metadata\": {
      \"auto_scan\": \"true\",
      \"severity\": \"high\",
      \"prevent_vul\": \"true\"
    }
  }")

case "$HTTP_CODE" in
  201)
    echo "Project '${PROJECT_NAME}' created successfully."
    ;;
  409)
    echo "Project '${PROJECT_NAME}' already exists."
    ;;
  *)
    echo "Error creating project. HTTP ${HTTP_CODE}:"
    cat /tmp/harbor-response.json
    exit 1
    ;;
esac
