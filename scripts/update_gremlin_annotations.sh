#!/bin/bash -e

# Update Gremlin annotations for OpenTelemetry demo services
# This script will update the gremlin.com/service-id annotations for all services and deployments

# Set the namespace
NAMESPACE="otel-demo"

echo "Updating Gremlin service annotations in namespace: $NAMESPACE"

# Function to annotate a resource
annotate_resource() {
  local resource_type=$1
  local resource_name=$2
  local service_name=$3
  
  # Format the Gremlin service ID
  local GREMLIN_SERVICE_ID="${service_name}"
  
  echo "Updating $resource_type $resource_name with service ID: $GREMLIN_SERVICE_ID"
  
  # Add or update the annotation
  kubectl annotate $resource_type $resource_name -n $NAMESPACE \
    "gremlin.com/service-id=$GREMLIN_SERVICE_ID" \
    --overwrite
    
  # Add additional Gremlin tags for better organization
  # For system components, add a system tag
  if [[ "$resource_name" == *"grafana"* ]] || \
     [[ "$resource_name" == *"jaeger"* ]] || \
     [[ "$resource_name" == *"prometheus"* ]] || \
     [[ "$resource_name" == *"otelcol"* ]] || \
     [[ "$resource_name" == *"kafka"* ]] || \
     [[ "$resource_name" == *"valkey"* ]] || \
     [[ "$resource_name" == *"image"* ]] || \
     [[ "$resource_name" == *"flagd"* ]]; then
    # System component tags
    kubectl annotate $resource_type $resource_name -n $NAMESPACE \
      "gremlin.com/tags=environment:workshop,app:otel-demo,type:system" \
      --overwrite
  else
    # Application service tags
    kubectl annotate $resource_type $resource_name -n $NAMESPACE \
      "gremlin.com/tags=environment:workshop,app:otel-demo,type:application" \
      --overwrite
  fi
}

# Annotate all deployments
for DEPLOYMENT in $(kubectl get deployments -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
  # Format the service name (remove otel-demo- prefix if it exists)
  SERVICE_NAME="${DEPLOYMENT#otel-demo-}"
  annotate_resource "deployment" "$DEPLOYMENT" "$SERVICE_NAME"
done

# Annotate all services
for SERVICE in $(kubectl get svc -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
  # Skip services that don't have a corresponding deployment
  if [[ "$SERVICE" == *"headless"* ]] || \
     [[ "$SERVICE" == *"metrics"* ]] || \
     [[ "$SERVICE" == *"jaeger-agent"* ]] || \
     [[ "$SERVICE" == *"collector"* ]] || \
     [[ "$SERVICE" == *"opensearch-headless"* ]]; then
    continue
  fi
  
  # Format the service name (remove otel-demo- prefix if it exists)
  SERVICE_NAME="${SERVICE#otel-demo-}"
  
  # Special case for frontend-proxy service
  if [[ "$SERVICE" == "frontend-proxy" ]]; then
    annotate_resource "service" "$SERVICE" "frontend-proxy-service"
  else
    annotate_resource "service" "$SERVICE" "$SERVICE_NAME-service"
  fi
done

echo "Gremlin annotations updated successfully!"
echo "Restarting Gremlin pods to pick up the changes..."

# Restart Gremlin daemonset to pick up the new annotations
kubectl rollout restart daemonset -n gremlin

echo "Done!"
