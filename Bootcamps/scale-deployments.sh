#!/bin/bash

# Namespace and desired number of replicas
NAMESPACE="otel-demo"
REPLICAS=2

# Get the list of deployments in the specified namespace that end with "service"
DEPLOYMENTS=$(kubectl get deployments -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep 'service$')

# Loop through each deployment and update the replicas
for DEPLOYMENT in $DEPLOYMENTS; 
do 
  kubectl scale deployment $DEPLOYMENT --replicas=$REPLICAS -n $NAMESPACE; 
done

echo "Updated replicas for deployments ending with 'service' in namespace $NAMESPACE to $REPLICAS"
