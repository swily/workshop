#!/bin/bash

# Script to enhance container tags for better visibility in Gremlin
# This script adds pod labels that will be visible as container tags in Gremlin

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to patch deployments with additional pod labels
enhance_pod_labels() {
  local namespace="$1"
  echo -e "${BLUE}=== Enhancing pod labels for deployments in namespace '$namespace' ===${NC}"
  
  # Get all deployments in the namespace
  local deployments=$(kubectl get deployments -n "$namespace" -o jsonpath='{.items[*].metadata.name}')
  
  for deployment in $deployments; do
    echo -e "${BLUE}Enhancing pod labels for deployment '$deployment'...${NC}"
    
    # Get the component name from existing labels
    local component=$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/component}')
    if [ -z "$component" ]; then
      # Fall back to the deployment name if component label doesn't exist
      component=$(echo "$deployment" | sed 's/otel-demo-//g')
    fi
    
    # Determine service category
    local category=""
    if [[ "$component" == *"frontend"* ]]; then
      category="frontend"
    elif [[ "$component" == *"cart"* ]]; then
      category="shopping"
    elif [[ "$component" == *"product"* ]]; then
      category="catalog"
    elif [[ "$component" == *"payment"* ]]; then
      category="payment"
    elif [[ "$component" == *"shipping"* ]]; then
      category="fulfillment"
    elif [[ "$component" == *"currency"* ]]; then
      category="payment"
    elif [[ "$component" == *"checkout"* ]]; then
      category="checkout"
    elif [[ "$component" == *"email"* ]]; then
      category="notification"
    elif [[ "$component" == *"recommendation"* ]]; then
      category="recommendation"
    elif [[ "$component" == *"ad"* ]]; then
      category="marketing"
    elif [[ "$component" == *"otelcol"* || "$component" == *"jaeger"* || "$component" == *"prometheus"* || "$component" == *"grafana"* ]]; then
      category="observability"
    elif [[ "$component" == *"kafka"* ]]; then
      category="messaging"
    elif [[ "$component" == *"valkey"* || "$component" == *"redis"* ]]; then
      category="database"
    else
      category="other"
    fi
    
    # Create the patch file for this deployment
    cat > /tmp/pod-labels-patch.yaml <<EOF
spec:
  template:
    metadata:
      labels:
        gremlin.com/service-id: ${deployment}
        gremlin.com/service-type: kubernetes
        gremlin.com/service-category: ${category}
        gremlin.com/service-component: ${component}
        gremlin.com/environment: demo
        gremlin.com/app: otel-demo
EOF
    
    # Apply the patch to the deployment
    kubectl patch deployment "$deployment" -n "$namespace" --patch "$(cat /tmp/pod-labels-patch.yaml)"
    
    echo -e "${GREEN}✅ Enhanced pod labels for deployment '$deployment'${NC}"
  done
  
  # Clean up
  rm -f /tmp/pod-labels-patch.yaml
}

# Function to verify the pod labels have been applied
verify_pod_labels() {
  local namespace="$1"
  echo -e "${BLUE}=== Verifying pod labels in namespace '$namespace' ===${NC}"
  
  # Wait a bit for deployments to update
  echo "Waiting for pods to update with new labels..."
  sleep 10
  
  # Get a sample pod to verify
  local sample_pod=$(kubectl get pods -n "$namespace" -o jsonpath='{.items[0].metadata.name}')
  
  echo -e "${BLUE}Sample pod labels for '$sample_pod':${NC}"
  kubectl get pod "$sample_pod" -n "$namespace" -o jsonpath='{.metadata.labels}' | jq .
  
  echo -e "${GREEN}✅ Pod labels verification complete${NC}"
}

# Main execution
main() {
  echo -e "${BLUE}=== Gremlin Container Tag Enhancement Script ===${NC}"
  
  # Enhance pod labels in the otel-demo namespace
  enhance_pod_labels "otel-demo"
  
  # Verify the pod labels have been applied
  verify_pod_labels "otel-demo"
  
  echo -e "${GREEN}=== Container tag enhancement complete! ===${NC}"
  echo -e "${YELLOW}Note: It may take a few minutes for pods to restart and for new tags to appear in the Gremlin UI${NC}"
  echo -e "${YELLOW}You may need to force a rolling update with: kubectl rollout restart deployment/<deployment-name> -n otel-demo${NC}"
}

# Execute main function
main "$@"
