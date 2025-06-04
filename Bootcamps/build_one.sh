#!/bin/bash

export AWS_REGION=us-east-2
export AWS_DEFAULT_REGION=us-east-2
export CLUSTER_NAME="otel-workshop-v2"

# Validate AWS Account
if [ $(aws sts get-caller-identity | jq -r .Account) -ne 856940208208 ]; then
  echo "This script is intended to be run in the Gremlin Sales Demo AWS account."
  echo "The current AWS credentials are not for this account. Please check your AWS CLI configuration."
  exit 1
fi

echo "Deploying single cluster: ${CLUSTER_NAME}"

# Create the cluster
echo "Building cluster: ${CLUSTER_NAME}"
bash ./single/build_cluster.sh

echo "Build completed."
echo "Waiting 5 minutes for build to stabilize before configuring cluster..."
sleep 300

echo "Configuring cluster base components..."
bash ./single/configure_cluster_base.sh

echo "Installing OpenTelemetry demo..."
bash ./single/configure_otel_demo.sh

echo "Getting load balancer endpoints..."
bash ./single/get_http_endpoints.sh