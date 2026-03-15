#!/usr/bin/env bash
# Setup Harbor for Tetris DevSecOps project
# Creates project, robot account, and outputs credentials

set -e

# Configuration from env with defaults
HARBOR_URL="${HARBOR_URL:-https://core.harbor.domain}"
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_PASS="${HARBOR_PASS:-Harbor12345}"
PROJECT_NAME="${PROJECT_NAME:-tetris}"
ROBOT_NAME="${ROBOT_NAME:-ci-pipeline}"

# Normalize URL (remove trailing slash)
HARBOR_URL="${HARBOR_URL%/}"
AUTH=$(echo -n "${HARBOR_USER}:${HARBOR_PASS}" | base64 -w 0)

echo "=== Harbor Setup for Tetris ==="
echo "Harbor URL: ${HARBOR_URL}"
echo "Project: ${PROJECT_NAME}"
echo ""

# 1. Create Harbor project with auto_scan and prevent_vul
echo "Creating project '${PROJECT_NAME}'..."
HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "${HARBOR_URL}/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic ${AUTH}" \
  -d '{
    "project_name": "'"${PROJECT_NAME}"'",
    "metadata": {
      "auto_scan": "true",
      "prevent_vul": "true"
    }
  }')

HTTP_BODY=$(echo "$HTTP_RESPONSE" | head -n -1)
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n 1)

if [[ "$HTTP_CODE" == "201" ]]; then
  echo "  Project created successfully."
elif [[ "$HTTP_CODE" == "409" ]]; then
  echo "  Project already exists, continuing."
else
  echo "  ERROR: Failed to create project (HTTP ${HTTP_CODE})"
  echo "  Response: ${HTTP_BODY}"
  exit 1
fi

# 2. Create robot account with push/pull permissions for the project
echo ""
echo "Creating robot account '${ROBOT_NAME}'..."
ROBOT_RESPONSE=$(curl -s -X POST \
  "${HARBOR_URL}/api/v2.0/projects/${PROJECT_NAME}/robots" \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic ${AUTH}" \
  -d '{
    "name": "'"${ROBOT_NAME}"'",
    "description": "CI pipeline robot for tetris project",
    "expires_at": -1,
    "access": [
      {"resource": "repository", "action": "push"},
      {"resource": "repository", "action": "pull"}
    ]
  }')

ROBOT_SECRET=$(echo "$ROBOT_RESPONSE" | jq -r '.secret // empty')
ROBOT_FULL_NAME=$(echo "$ROBOT_RESPONSE" | jq -r '.name // empty')

if [[ -z "$ROBOT_SECRET" || -z "$ROBOT_FULL_NAME" ]]; then
  # Check if robot already exists
  if echo "$ROBOT_RESPONSE" | jq -e '.code == 409' > /dev/null 2>&1; then
    echo "  Robot account already exists. Use existing credentials or delete and recreate."
    exit 1
  fi
  echo "  ERROR: Failed to create robot account"
  echo "  Response: ${ROBOT_RESPONSE}"
  exit 1
fi

# 3. Print robot account credentials
echo ""
echo "=== Robot Account Created ==="
echo ""
echo "Robot Account Name: ${ROBOT_FULL_NAME}"
echo "Robot Account Secret: ${ROBOT_SECRET}"
echo ""
echo "SAVE THESE CREDENTIALS - The secret cannot be retrieved again!"
echo ""
echo "Docker login:"
echo "  docker login ${HARBOR_URL#https://} -u ${ROBOT_FULL_NAME} -p <secret>"
echo ""
echo "Environment variables for CI:"
echo "  export HARBOR_REGISTRY=${HARBOR_URL#https://}"
echo "  export HARBOR_ROBOT_USER=${ROBOT_FULL_NAME}"
echo "  export HARBOR_ROBOT_SECRET=${ROBOT_SECRET}"
