#!/bin/bash -e

export AWS_DEFAULT_REGION=us-east-2
export AWS_REGION=us-east-2

if [ -z "${EXPIRATION}" ]; then
  EXPIRATION=$(date -v +7d  +%Y-%m-%d)
fi  

if [ -z "${OWNER}" ]; then
  OWNER="$(whoami)"
fi

# CLI team number takes precedence over env var.
if [ -n "${1}" ]; then
    TEAM_NUMBER="${1}"
elif [ -z "${TEAM_NUMBER}" ]; then
  echo "Please provide a group number as CLI arg or set TEAM_NUMBER env var."
  exit 1
fi

if [ ${TEAM_NUMBER} -gt 20 ] || [ ${TEAM_NUMBER} -lt 1 ]; then
  echo "Team number must be between 1 and 20."
  exit 1
fi

if [ ${TEAM_NUMBER} -lt 10 ]; then
  TEAM_NUMBER="0${TEAM_NUMBER}"
fi

eksctl get clusters | grep otel-bootcamp-group-${TEAM_NUMBER} && echo "Cluster otel-bootcamp-group-${TEAM_NUMBER} already exists" && exit 0
eksctl create cluster -f <(cat ./templates/eksctl.yaml | sed -e "s/{{.TEAM_NUMBER}}/${TEAM_NUMBER}/g" -e "s/{{.OWNER}}/${OWNER}/g" -e "s/{{.EXPIRATION}}/${EXPIRATION}/g")