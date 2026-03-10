#!/usr/bin/env bash
# Creates a Harbor robot account with push/pull permissions for a project.
#
# Usage: ./create-robot-account.sh <project-name> <robot-name>
#
# Example:
#   ./create-robot-account.sh my-app ci-pipeline
#
# The script outputs the robot token — save it securely (e.g., in Vault).

set -euo pipefail

HARBOR_URL="${HARBOR_URL:-https://harbor.example.com}"
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_PASS="${HARBOR_PASS:-Harbor12345}"
PROJECT_NAME="${1:?Usage: $0 <project-name> <robot-name>}"
ROBOT_NAME="${2:?Usage: $0 <project-name> <robot-name>}"

echo "Creating robot account '${ROBOT_NAME}' for project '${PROJECT_NAME}'..."

RESPONSE=$(curl -sk \
  -u "${HARBOR_USER}:${HARBOR_PASS}" \
  -X POST "${HARBOR_URL}/api/v2.0/robots" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"${ROBOT_NAME}\",
    \"description\": \"Robot account for ${PROJECT_NAME} CI/CD\",
    \"duration\": 365,
    \"level\": \"project\",
    \"permissions\": [
      {
        \"namespace\": \"${PROJECT_NAME}\",
        \"kind\": \"project\",
        \"access\": [
          {\"resource\": \"repository\", \"action\": \"push\"},
          {\"resource\": \"repository\", \"action\": \"pull\"},
          {\"resource\": \"tag\",        \"action\": \"create\"},
          {\"resource\": \"tag\",        \"action\": \"list\"},
          {\"resource\": \"artifact\",   \"action\": \"read\"}
        ]
      }
    ]
  }")

ROBOT_FULL_NAME=$(echo "$RESPONSE" | jq -r '.name // empty')
ROBOT_SECRET=$(echo "$RESPONSE" | jq -r '.secret // empty')

if [ -n "$ROBOT_SECRET" ]; then
  echo ""
  echo "Robot account created successfully!"
  echo "  Name:   ${ROBOT_FULL_NAME}"
  echo "  Secret: ${ROBOT_SECRET}"
  echo ""
  echo "Use these credentials for docker login:"
  echo "  docker login ${HARBOR_URL} -u '${ROBOT_FULL_NAME}' -p '${ROBOT_SECRET}'"
  echo ""
  echo "IMPORTANT: Save this secret securely — it cannot be retrieved later."
  echo "  Consider storing it in Vault (see ../02-vault-basics/)."
else
  echo "Error creating robot account:"
  echo "$RESPONSE" | jq .
  exit 1
fi
