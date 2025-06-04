#!/bin/bash -e

export AWS_DEFAULT_REGION=us-east-2
export AWS_REGION=us-east-2

if [ -z "${EXPIRATION}" ]; then
  EXPIRATION=$(date -v +7d  +%Y-%m-%d)
fi  

if [ -z "${OWNER}" ]; then
  OWNER="$(whoami)"
fi

if [ -z "${CLUSTER_NAME}" ]; then
  echo "CLUSTER_NAME environment variable must be set"
  exit 1
fi

eksctl get clusters | grep ${CLUSTER_NAME} && echo "Cluster ${CLUSTER_NAME} already exists" && exit 0
eksctl create cluster -f <(cat ../templates/eksctl-custom.yaml | sed -e "s/{{.CLUSTER_NAME}}/${CLUSTER_NAME}/g" -e "s/{{.OWNER}}/${OWNER}/g" -e "s/{{.EXPIRATION}}/${EXPIRATION}/g")