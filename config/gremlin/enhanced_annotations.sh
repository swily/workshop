#!/bin/bash

# Enhanced script to update Gremlin service discovery annotations with comprehensive tagging
# This script adds rich metadata to services for better organization in Gremlin UI

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to create the necessary RBAC resources for Gremlin service discovery
create_gremlin_service_discovery_rbac() {
  echo -e "${BLUE}=== Creating Gremlin service discovery RBAC resources ===${NC}"
  
  # Create ClusterRole for service discovery
  cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: gremlin-service-discovery
  labels:
    app: gremlin
rules:
- apiGroups: [""]
  resources: ["services", "pods", "endpoints", "nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list", "watch"]
EOF
  
  echo -e "${GREEN}✅ Created gremlin-service-discovery ClusterRole${NC}"
  
  # Create ClusterRoleBinding for service discovery
  cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gremlin-service-discovery
  labels:
    app: gremlin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: gremlin-service-discovery
subjects:
- kind: ServiceAccount
  name: chao
  namespace: gremlin
EOF
  
  echo -e "${GREEN}✅ Created gremlin-service-discovery ClusterRoleBinding${NC}"
}

# Function to determine service category based on name
get_service_category() {
  local service_name="$1"
  
  if [[ "$service_name" == *"frontend"* ]]; then
    echo "frontend"
  elif [[ "$service_name" == *"cart"* ]]; then
    echo "shopping"
  elif [[ "$service_name" == *"product"* ]]; then
    echo "catalog"
  elif [[ "$service_name" == *"payment"* ]]; then
    echo "payment"
  elif [[ "$service_name" == *"shipping"* ]]; then
    echo "fulfillment"
  elif [[ "$service_name" == *"currency"* ]]; then
    echo "payment"
  elif [[ "$service_name" == *"checkout"* ]]; then
    echo "checkout"
  elif [[ "$service_name" == *"email"* ]]; then
    echo "notification"
  elif [[ "$service_name" == *"recommendation"* ]]; then
    echo "recommendation"
  elif [[ "$service_name" == *"ad"* ]]; then
    echo "marketing"
  elif [[ "$service_name" == *"otelcol"* || "$service_name" == *"jaeger"* || "$service_name" == *"prometheus"* || "$service_name" == *"grafana"* ]]; then
    echo "observability"
  elif [[ "$service_name" == *"kafka"* ]]; then
    echo "messaging"
  elif [[ "$service_name" == *"valkey"* || "$service_name" == *"redis"* ]]; then
    echo "database"
  else
    echo "other"
  fi
}

# Function to annotate services with enhanced metadata for Gremlin service discovery
annotate_services_with_enhanced_metadata() {
  local namespace="$1"
  echo -e "${BLUE}=== Adding enhanced annotations to services in namespace '$namespace' ===${NC}"
  
  # Get all services in the namespace
  local services=$(kubectl get services -n "$namespace" -o jsonpath='{.items[*].metadata.name}')
  
  for service in $services; do
    echo "Enhancing annotations for service '$service' in namespace '$namespace'..."
    
    # Determine service category
    local category=$(get_service_category "$service")
    
    # Add the required annotations
    echo -e "${BLUE}  - Adding service-id annotation...${NC}"
    kubectl annotate service "$service" -n "$namespace" "gremlin.com/service-id=$service" --overwrite
    
    echo -e "${BLUE}  - Adding service-type annotation...${NC}"
    kubectl annotate service "$service" -n "$namespace" "gremlin.com/service-type=kubernetes" --overwrite
    
    # Add custom tags for better organization in Gremlin UI
    echo -e "${BLUE}  - Adding tags annotation (environment, app, category)...${NC}"
    kubectl annotate service "$service" -n "$namespace" "gremlin.com/tags=environment:demo,app:otel-demo,category:${category}" --overwrite
    
    # Add description annotation
    echo -e "${BLUE}  - Adding description annotation...${NC}"
    kubectl annotate service "$service" -n "$namespace" "gremlin.com/description=OpenTelemetry Demo ${service} service" --overwrite
    
    echo -e "${GREEN}✅ Added enhanced Gremlin annotations to service '$service'${NC}"
  done
}

# Function to annotate deployments for better Gremlin integration
annotate_deployments() {
  local namespace="$1"
  echo -e "${BLUE}=== Adding annotations to deployments in namespace '$namespace' ===${NC}"
  
  # Get all deployments in the namespace
  local deployments=$(kubectl get deployments -n "$namespace" -o jsonpath='{.items[*].metadata.name}')
  
  for deployment in $deployments; do
    echo "Annotating deployment '$deployment' in namespace '$namespace'..."
    
    # Determine service category
    local category=$(get_service_category "$deployment")
    
    # Add the required annotations
    echo -e "${BLUE}  - Adding service-id annotation to deployment...${NC}"
    kubectl annotate deployment "$deployment" -n "$namespace" "gremlin.com/service-id=$deployment" --overwrite
    
    # Add custom tags for better organization in Gremlin UI
    echo -e "${BLUE}  - Adding tags annotation to deployment (environment, app, category)...${NC}"
    kubectl annotate deployment "$deployment" -n "$namespace" "gremlin.com/tags=environment:demo,app:otel-demo,category:${category}" --overwrite
    
    echo -e "${GREEN}✅ Added Gremlin annotations to deployment '$deployment'${NC}"
  done
}

# Function to verify Gremlin has proper access
verify_gremlin_access() {
  echo -e "${BLUE}=== Verifying Gremlin service account permissions ===${NC}"
  
  # Check if Gremlin service account exists
  if ! kubectl get serviceaccount -n gremlin chao &>/dev/null; then
    echo -e "${YELLOW}⚠️ Gremlin service account 'chao' not found in namespace 'gremlin'${NC}"
    return 1
  fi
  
  # Check if Gremlin has the necessary permissions
  if ! kubectl auth can-i --as=system:serviceaccount:gremlin:chao get services --all-namespaces &>/dev/null; then
    echo -e "${YELLOW}⚠️ Gremlin service account doesn't have permission to list services${NC}"
    return 1
  fi
  
  echo -e "${GREEN}✅ Gremlin service account has proper permissions${NC}"
  return 0
}

# Main execution
main() {
  echo -e "${BLUE}=== Gremlin Enhanced Service Discovery Script ===${NC}"
  
  # Create RBAC resources
  create_gremlin_service_discovery_rbac
  
  # Annotate services in the otel-demo namespace with enhanced metadata
  annotate_services_with_enhanced_metadata "otel-demo"
  
  # Annotate deployments in the otel-demo namespace
  annotate_deployments "otel-demo"
  
  # Verify Gremlin access
  if verify_gremlin_access; then
    echo -e "${GREEN}=== Gremlin enhanced service discovery setup complete! ===${NC}"
    echo -e "${YELLOW}Note: It may take up to 5 minutes for services to appear in the Gremlin UI${NC}"
  else
    echo -e "${YELLOW}=== Gremlin service discovery setup completed with warnings ===${NC}"
    echo -e "${YELLOW}Please check the Gremlin installation and try again${NC}"
  fi
}

# Execute main function
main "$@"
