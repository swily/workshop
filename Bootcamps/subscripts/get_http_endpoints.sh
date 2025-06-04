#!/bin/bash

export AWS_REGION=us-east-2
export AWS_DEFAULT_REGION=us-east-2

clusters=$(eksctl get clusters | awk '/^otel-bootcamp-group/ {print $1}')

for cluster in ${clusters}; do
  eksctl utils write-kubeconfig --cluster $cluster 2> /dev/null > /dev/null
  echo ${cluster} $(kubectl get service otel-demo-frontendproxy -n otel-demo -o json | jq -r '.status.loadBalancer.ingress[].hostname')
done