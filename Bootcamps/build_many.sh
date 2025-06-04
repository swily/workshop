#!/bin/bash

export AWS_REGION=us-east-2
export AWS_DEFAULT_REGION=us-east-2

get_build_status () {
  for team_number in $*; do

    if [ ${team_number} -lt 10 ]; then
      padded_team_number="0${team_number}"
    else
      padded_team_number="${team_number}"
    fi

    STATUS=$(eksctl get cluster otel-bootcamp-group-${padded_team_number} -o json | jq -r '.[0].Status')
    if [ "$STATUS" != "ACTIVE" ]; then
      return 1
    fi
  done
  return 0
}

# Validate AWS Account
if [ $(aws sts get-caller-identity | jq -r .Account) -ne 856940208208 ]; then
  echo "This script is intended to be run in the Gremlin Sales Demo AWS account."
  echo "The current AWS credentials are not for this account. Please check your AWS CLI configuration."
  exit 1
fi

# Script to add a custom annotation to Kubernetes Service definitions in a YAML file
echo "Deploying multiple bootcamps..."
echo "Building bootcamps for teams: $*"

build_teams=$*

while [ $# -gt 1 ]; do
  echo "Building team number: $1"
  (bash ./subscripts/build_cluster.sh $1) &
  shift
done

# Foreground this last one so we wait for it to complete before proceeding to cluster configuration.
echo "Building team number: $1"
bash ./subscripts/build_cluster.sh $1

echo "All builds completed."
echo "Waiting 5 minutes for builds to stabilize before configuring clusters..."
sleep 300
for team_number in $build_teams; do
  bash ./subscripts/configure_cluster.sh $team_number
  sleep 30
done

echo "Get all load balancer endpoints"
bash ./subscripts/get_http_endpoints.sh