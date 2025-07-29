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

# Install Gremlin
helm upgrade --install gremlin gremlin/gremlin \
  --namespace gremlin \
  --create-namespace \
  --set gremlin.secret.managed=true \
  --set gremlin.secret.type=secret \
  --set gremlin.secret.teamID=$GREMLIN_TEAM_ID \
  --set gremlin.secret.teamSecret=$GREMLIN_TEAM_SECRET \
  --set gremlin.secret.clusterID=$CLUSTER_NAME \
  --set gremlin.hostPID=true \
  --set gremlin.client.tags.cluster=$CLUSTER_NAME
