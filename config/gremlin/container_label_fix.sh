#!/bin/bash

# Script to enhance container visibility in Gremlin by adding container-level tags
# This script uses a different approach to ensure Gremlin can see our custom tags

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to update Gremlin agent to recognize our custom labels
update_gremlin_agent() {
  echo -e "${BLUE}=== Updating Gremlin agent to recognize custom labels ===${NC}"
  
  # Create a patch for the Gremlin DaemonSet to add client tags
  cat > /tmp/gremlin-agent-patch.yaml <<EOF
spec:
  template:
    spec:
      containers:
      - name: gremlin
        env:
        - name: GREMLIN_CLIENT_TAGS
          value: "service-category,service-component,app,environment"
EOF
  
  # Apply the patch to the Gremlin DaemonSet
  kubectl patch daemonset gremlin -n gremlin --patch "$(cat /tmp/gremlin-agent-patch.yaml)"
  
  echo -e "${GREEN}✅ Updated Gremlin agent configuration${NC}"
  
  # Restart the Gremlin DaemonSet to apply changes
  kubectl rollout restart daemonset/gremlin -n gremlin
  
  echo -e "${GREEN}✅ Restarted Gremlin agent pods${NC}"
}

# Function to add container-level annotations to deployments
enhance_container_annotations() {
  local namespace="$1"
  echo -e "${BLUE}=== Enhancing container annotations for deployments in namespace '$namespace' ===${NC}"
  
  # Get all deployments in the namespace
  local deployments=$(kubectl get deployments -n "$namespace" -o jsonpath='{.items[*].metadata.name}')
  
  for deployment in $deployments; do
    echo -e "${BLUE}Enhancing container annotations for deployment '$deployment'...${NC}"
    
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
    
    # Create the patch file for this deployment to add container-level annotations
    cat > /tmp/container-annotations-patch.yaml <<EOF
spec:
  template:
    metadata:
      annotations:
        container.gremlin.com/service-id: "${deployment}"
        container.gremlin.com/service-type: "kubernetes"
        container.gremlin.com/service-category: "${category}"
        container.gremlin.com/service-component: "${component}"
        container.gremlin.com/environment: "demo"
        container.gremlin.com/app: "otel-demo"
EOF
    
    # Apply the patch to the deployment
    kubectl patch deployment "$deployment" -n "$namespace" --patch "$(cat /tmp/container-annotations-patch.yaml)"
    
    echo -e "${GREEN}✅ Enhanced container annotations for deployment '$deployment'${NC}"
  done
  
  # Clean up
  rm -f /tmp/container-annotations-patch.yaml
}

# Function to verify the container annotations have been applied
verify_container_annotations() {
  local namespace="$1"
  echo -e "${BLUE}=== Verifying container annotations in namespace '$namespace' ===${NC}"
  
  # Wait a bit for deployments to update
  echo "Waiting for pods to update with new annotations..."
  sleep 10
  
  # Get a sample pod to verify
  local sample_pod=$(kubectl get pods -n "$namespace" -o jsonpath='{.items[0].metadata.name}')
  
  echo -e "${BLUE}Sample pod annotations for '$sample_pod':${NC}"
  kubectl get pod "$sample_pod" -n "$namespace" -o jsonpath='{.metadata.annotations}' | jq .
  
  echo -e "${GREEN}✅ Container annotations verification complete${NC}"
}

# Main execution
main() {
  echo -e "${BLUE}=== Gremlin Container Label Fix Script ===${NC}"
  
  # Update Gremlin agent to recognize our custom labels
  update_gremlin_agent
  
  # Enhance container annotations in the otel-demo namespace
  enhance_container_annotations "otel-demo"
  
  # Verify the container annotations have been applied
  verify_container_annotations "otel-demo"
  
  # Force a rolling update of all deployments to apply the new annotations
  echo -e "${BLUE}=== Forcing rolling update of all deployments in otel-demo namespace ===${NC}"
  kubectl rollout restart deployment -n otel-demo
  
  echo -e "${GREEN}=== Container label fix complete! ===${NC}"
  echo -e "${YELLOW}Note: It may take a few minutes for the changes to be reflected in the Gremlin UI${NC}"
  echo -e "${YELLOW}The Gremlin agent has been configured to recognize the following custom tags:${NC}"
  echo -e "${YELLOW}- service-category${NC}"
  echo -e "${YELLOW}- service-component${NC}"
  echo -e "${YELLOW}- app${NC}"
  echo -e "${YELLOW}- environment${NC}"
}

# Execute main function
main "$@"
