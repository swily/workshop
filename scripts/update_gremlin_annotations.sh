#!/bin/bash -e

# Update Gremlin annotations for OpenTelemetry demo services
# This script will update the gremlin.com/service-id annotations for all services

# Set the namespace
NAMESPACE="otel-demo"

echo "Updating Gremlin service annotations in namespace: $NAMESPACE"

# Get all deployments in the namespace
for DEPLOYMENT in $(kubectl get deployments -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
  # Format the service name (remove otel-demo- prefix if it exists)
  SERVICE_NAME="${DEPLOYMENT#otel-demo-}"
  
  # Format the Gremlin service ID
  GREMLIN_SERVICE_ID="otel-demo-${SERVICE_NAME}"
  
  echo "Updating $DEPLOYMENT with service ID: $GREMLIN_SERVICE_ID"
  
  # Add or update the annotation
  kubectl annotate deployment $DEPLOYMENT -n $NAMESPACE \
    "gremlin.com/service-id=$GREMLIN_SERVICE_ID" \
    --overwrite
    
  # Add additional Gremlin tags for better organization
  # For system components, add a system tag
  if [[ "$DEPLOYMENT" == *"grafana"* ]] || \
     [[ "$DEPLOYMENT" == *"jaeger"* ]] || \
     [[ "$DEPLOYMENT" == *"prometheus"* ]] || \
     [[ "$DEPLOYMENT" == *"otelcol"* ]] || \
     [[ "$DEPLOYMENT" == *"kafka"* ]] || \
     [[ "$DEPLOYMENT" == *"valkey"* ]] || \
     [[ "$DEPLOYMENT" == *"imageprovider"* ]] || \
     [[ "$DEPLOYMENT" == *"flagd"* ]]; then
    # System component tags
    kubectl annotate deployment $DEPLOYMENT -n $NAMESPACE \
      "gremlin.com/tags=environment:workshop,app:otel-demo,type:system" \
      --overwrite
  else
    # Application service tags
    kubectl annotate deployment $DEPLOYMENT -n $NAMESPACE \
      "gremlin.com/tags=environment:workshop,app:otel-demo,type:application" \
      --overwrite
  fi
done

echo "Gremlin annotations updated successfully!"
echo "Restarting Gremlin pods to pick up the changes..."

# Restart Gremlin daemonset to pick up the new annotations
kubectl rollout restart daemonset -n gremlin

echo "Done!"
