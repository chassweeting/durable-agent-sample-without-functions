#!/usr/bin/env bash
set -euo pipefail

# Assign "Cognitive Services OpenAI User" role to the currently signed-in user
# for the Azure OpenAI resource specified in src/.env

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../src/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: .env file not found at $ENV_FILE"
  exit 1
fi

# Extract endpoint from .env
ENDPOINT=$(grep -E '^AZURE_OPENAI_ENDPOINT=' "$ENV_FILE" | cut -d= -f2-)
if [[ -z "$ENDPOINT" ]]; then
  echo "Error: AZURE_OPENAI_ENDPOINT not set in .env"
  exit 1
fi

# Derive resource name from endpoint (e.g. https://clsopenai.openai.azure.com/ -> clsopenai)
RESOURCE_NAME=$(echo "$ENDPOINT" | sed -E 's|https://([^.]+)\.openai\.azure\.com/?|\1|')

echo "Looking up Azure OpenAI resource: $RESOURCE_NAME"

# Find the resource ID
RESOURCE_ID=$(az resource list \
  --resource-type "Microsoft.CognitiveServices/accounts" \
  --query "[?name=='$RESOURCE_NAME'].id" -o tsv)

if [[ -z "$RESOURCE_ID" ]]; then
  echo "Error: Could not find Cognitive Services resource '$RESOURCE_NAME'"
  exit 1
fi

# Get the current user's object ID
USER_ID=$(az ad signed-in-user show --query id -o tsv)
echo "Assigning role to principal: $USER_ID"
echo "Resource: $RESOURCE_ID"

az role assignment create \
  --assignee "$USER_ID" \
  --role "Cognitive Services OpenAI User" \
  --scope "$RESOURCE_ID"

echo "Done. Role assignment may take a few minutes to propagate."
