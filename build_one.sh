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
bash ./build_cluster.sh

echo "Build completed."
echo "Waiting 5 minutes for build to stabilize before configuring cluster..."
sleep 300

echo "Configuring cluster base components..."
bash ./configure_cluster_base.sh

echo "Installing OpenTelemetry demo..."
bash ./configure_otel_demo.sh

echo "Getting load balancer endpoints..."
echo -n "Frontend URL: http://"
kubectl get svc -n otel-demo otel-demo-frontendproxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo ":8080"