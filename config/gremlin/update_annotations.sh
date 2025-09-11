#!/bin/bash

# Script to update Gremlin service discovery annotations and ensure proper RBAC permissions
# This script enhances service discovery for Gremlin by adding required annotations and RBAC permissions

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

# Function to annotate services for Gremlin service discovery
annotate_services() {
  local namespace="$1"
  echo -e "${BLUE}=== Annotating services in namespace '$namespace' for Gremlin service discovery ===${NC}"
  
  # Get all services in the namespace
  local services=$(kubectl get services -n "$namespace" -o jsonpath='{.items[*].metadata.name}')
  
  for service in $services; do
    echo "Annotating service '$service' in namespace '$namespace'..."
    
    # Add the required annotations
    kubectl annotate service "$service" -n "$namespace" "gremlin.com/service-id=$service" --overwrite
    
    # Add additional helpful annotations for better service discovery
    kubectl annotate service "$service" -n "$namespace" "gremlin.com/service-type=kubernetes" --overwrite
    
    echo -e "${GREEN}✅ Added Gremlin annotations to service '$service'${NC}"
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
  echo -e "${BLUE}=== Gremlin Service Discovery Enhancement Script ===${NC}"
  
  # Create RBAC resources
  create_gremlin_service_discovery_rbac
  
  # Annotate services in the otel-demo namespace
  annotate_services "otel-demo"
  
  # Verify Gremlin access
  if verify_gremlin_access; then
    echo -e "${GREEN}=== Gremlin service discovery setup complete! ===${NC}"
    echo -e "${YELLOW}Note: It may take a few minutes for services to appear in the Gremlin UI${NC}"
  else
    echo -e "${YELLOW}=== Gremlin service discovery setup completed with warnings ===${NC}"
    echo -e "${YELLOW}Please check the Gremlin installation and try again${NC}"
  fi
}

# Execute main function
main "$@"
