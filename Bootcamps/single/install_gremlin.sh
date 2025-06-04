#!/bin/bash -e

if [ -z "${GREMLIN_TEAM_ID}" ]; then
  echo "GREMLIN_TEAM_ID environment variable must be set"
  exit 1
fi

if [ -z "${GREMLIN_TEAM_SECRET}" ]; then
  echo "GREMLIN_TEAM_SECRET environment variable must be set"
  exit 1
fi

if [ -z "${CLUSTER_NAME}" ]; then
  echo "CLUSTER_NAME environment variable must be set"
  exit 1
fi

# Install Gremlin via helm.
echo "Installing Gremlin for cluster ${CLUSTER_NAME}"
echo "Team ID: ${GREMLIN_TEAM_ID}"

helm repo add gremlin https://helm.gremlin.com 2>&1 | grep -v skipping
helm get values gremlin -n gremlin > /dev/null || \
helm install \
  --create-namespace \
  --set gremlin.secret.managed=true \
  --set gremlin.secret.type=secret \
  --set gremlin.clusterID=${CLUSTER_NAME} \
  --set gremlin.secret.teamID="${GREMLIN_TEAM_ID}" \
  --set gremlin.secret.teamSecret="${GREMLIN_TEAM_SECRET}" \
  --set gremlin.container.driver=containerd-linux \
  --namespace gremlin \
  --set gremlin.hostPID=true \
  --set gremlin.hostNetwork=true \
  gremlin gremlin/gremlin
