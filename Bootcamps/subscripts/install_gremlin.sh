#!/bin/bash


TEAM_NUMBER=$1
TEAM_NAME="Group ${TEAM_NUMBER}"

# Add Helm Repo for Gremlin

# Retrieve secret for the selected team.
team_id=$(aws ssm get-parameter --name '/Bootcamp/TeamSecrets' --with-decryption | jq -r --arg team "${TEAM_NAME}" '.Parameter.Value | fromjson | .[$team].team_id')
team_secret=$(aws ssm get-parameter --name '/Bootcamp/TeamSecrets' --with-decryption | jq -r --arg team "${TEAM_NAME}" '.Parameter.Value | fromjson | .[$team].team_secret')

# Install Gremlin via helm.
echo "Installing Gremlin for ${TEAM_NAME}"
echo "Team ID: ${team_id}"
echo "Team Secret: ${team_secret}"

helm repo add gremlin https://helm.gremlin.com 2>&1 | grep -v skipping
helm get values gremlin -n gremlin > /dev/null || \
helm install \
  --create-namespace \
  --set gremlin.secret.managed=true \
  --set gremlin.secret.type=secret \
  --set gremlin.clusterID=group-${TEAM_NUMBER}-bootcamp-otel-demo \
  --set gremlin.secret.teamID="${team_id}" \
  --set gremlin.secret.teamSecret="${team_secret}" \
  --set gremlin.container.driver=containerd-linux \
  --namespace gremlin \
  --set gremlin.hostPID=true \
  --set gremlin.hostNetwork=true \
  gremlin gremlin/gremlin
