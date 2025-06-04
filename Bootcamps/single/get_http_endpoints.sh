#!/bin/bash -e

export AWS_DEFAULT_REGION=us-east-2
export AWS_REGION=us-east-2

if [ -z "${CLUSTER_NAME}" ]; then
  echo "CLUSTER_NAME environment variable must be set"
  exit 1
fi

echo "Getting HTTP endpoint for ${CLUSTER_NAME}"
eksctl utils write-kubeconfig --cluster ${CLUSTER_NAME}
kubectl get svc -n otel-demo otel-demo-frontendproxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo ""