#!/bin/bash -e

export AWS_DEFAULT_REGION=us-east-2
export AWS_REGION=us-east-2

if [ -z "${CLUSTER_NAME}" ]; then
  echo "CLUSTER_NAME environment variable must be set"
  exit 1
fi

# Validate AWS Account
if [ $(aws sts get-caller-identity | jq -r .Account) -ne 856940208208 ]; then
  echo "This script is intended to be run in the Gremlin Sales Demo AWS account."
  echo "The current AWS credentials are not for this account. Please check your AWS CLI configuration."
  exit 1
fi

echo "Cleaning cluster resources for ${CLUSTER_NAME}..."
./clean_cluster.sh

echo "Deleting cluster ${CLUSTER_NAME}..."
eksctl delete cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --disable-nodegroup-eviction --force
