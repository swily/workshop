#!/bin/bash -e

if [ -z "${GREMLIN_TEAM_ID}" ] || [ -z "${GREMLIN_TEAM_SECRET}" ]; then
  echo "GREMLIN_TEAM_ID and GREMLIN_TEAM_SECRET environment variables must be set"
  exit 1
fi

if [ -z "${CLUSTER_NAME}" ]; then
  echo "CLUSTER_NAME environment variable must be set"
  exit 1
fi

# Add Gremlin helm repo
helm repo add gremlin https://helm.gremlin.com
helm repo update

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKSHOP_DIR="$(dirname "$SCRIPT_DIR")"

# Install Gremlin using the custom values file
helm upgrade --install gremlin gremlin/gremlin \
  --namespace gremlin \
  --create-namespace \
  -f "$WORKSHOP_DIR/gremlin-values-custom.yaml" \
  --set gremlin.client.tags.cluster=$CLUSTER_NAME
