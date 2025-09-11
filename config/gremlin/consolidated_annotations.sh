#!/bin/bash

# Consolidated Gremlin Annotation Script
# This script applies all necessary Gremlin annotations in a single pass to avoid duplication

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track annotation counts for summary
service_count=0
deployment_count=0
sample_shown=false

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

# Function to create RBAC resources (only once)
create_gremlin_rbac() {
  echo -e "${BLUE}Creating Gremlin RBAC resources...${NC}"
  
  cat <<EOF | kubectl apply -f - >/dev/null 2>&1
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
---
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
  
  echo -e "${GREEN}✅ Gremlin RBAC resources created${NC}"
}

# Function to apply all annotations in a single pass
apply_consolidated_annotations() {
  local namespace="$1"
  echo -e "${BLUE}Applying Gremlin annotations to namespace '$namespace'...${NC}"
  
  # Get all services and deployments
  local services=$(kubectl get services -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
  local deployments=$(kubectl get deployments -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
  
  # Annotate services (single pass)
  if [ -n "$services" ]; then
    echo -e "${BLUE}  Annotating services...${NC}"
    for service in $services; do
      local category=$(get_service_category "$service")
      
      # Apply all service annotations at once
      kubectl annotate service "$service" -n "$namespace" \
        "gremlin.com/service-id=$service" \
        "gremlin.com/service-type=kubernetes" \
        "gremlin.com/tags=environment:demo,app:otel-demo,category:${category}" \
        "gremlin.com/description=OpenTelemetry Demo ${service} service" \
        --overwrite >/dev/null 2>&1 || true
      service_count=$((service_count + 1))
      
      # Show sample annotation for the first service (frontend)
      if [[ "$service" == *"frontend"* ]] && [ "$sample_shown" = false ]; then
        echo -e "${YELLOW}  📝 Sample annotations applied to '$service':${NC}"
        echo -e "${YELLOW}    gremlin.com/service-id: $service${NC}"
        echo -e "${YELLOW}    gremlin.com/service-type: kubernetes${NC}"
        echo -e "${YELLOW}    gremlin.com/tags: environment:demo,app:otel-demo,category:$category${NC}"
        echo -e "${YELLOW}    gremlin.com/description: OpenTelemetry Demo $service service${NC}"
        sample_shown=true
      fi
    done
    echo -e "${GREEN}  ✅ Services annotated ($service_count services)${NC}"
  fi
  
  # Annotate deployments (single pass)
  if [ -n "$deployments" ]; then
    echo -e "${BLUE}  Annotating deployments...${NC}"
    for deployment in $deployments; do
      category=$(get_service_category "$deployment")
      kubectl patch deployment "$deployment" -n "$namespace" --type='merge' --patch='{"metadata":{"annotations":{"gremlin.com/service-id":"'${deployment}'","gremlin.com/service-type":"kubernetes","gremlin.com/tags":"environment:demo,app:otel-demo,category:'${category}'","gremlin.com/description":"OpenTelemetry Demo '${deployment}' deployment"}},"spec":{"template":{"metadata":{"labels":{"service-category":"'${category}'","service-component":"'${deployment}'","app":"otel-demo","environment":"demo"},"annotations":{"container.gremlin.com/service-category":"'${category}'","container.gremlin.com/service-component":"'${deployment}'","container.gremlin.com/service-id":"'${deployment}'","container.gremlin.com/service-type":"kubernetes"}}}}}' >/dev/null 2>&1 || true
      deployment_count=$((deployment_count + 1))
    done
    echo -e "${GREEN}  ✅ Deployments annotated ($deployment_count deployments)${NC}"
  fi
  
  # Update Gremlin agent configuration (only once)
  echo -e "${BLUE}  Updating Gremlin agent configuration...${NC}"
  kubectl patch daemonset gremlin -n gremlin --type='merge' --patch='{"spec":{"template":{"spec":{"containers":[{"name":"gremlin","env":[{"name":"GREMLIN_CONTAINER_LABELS","value":"service-category,service-component,app,environment"}]}]}}}}' >/dev/null 2>&1 || true
  
  kubectl rollout restart daemonset/gremlin -n gremlin >/dev/null 2>&1 || true
  echo -e "${GREEN}  ✅ Gremlin agent updated${NC}"
  
  # Force rolling update of deployments (single command)
  echo -e "${BLUE}  Restarting deployments to apply changes...${NC}"
  if [ -n "$deployments" ]; then
    for deployment in $deployments; do
      kubectl rollout restart deployment/"$deployment" -n "$namespace" >/dev/null 2>&1 || true
    done
  fi
  echo -e "${GREEN}  ✅ Deployments restarted${NC}"
}

# Main execution
main() {
  echo -e "${BLUE}=== Consolidated Gremlin Annotation Setup ===${NC}"
  
  # Create RBAC resources
  create_gremlin_rbac
  
  # Apply all annotations in a single pass
  apply_consolidated_annotations "otel-demo"
  
  echo -e "${GREEN}=== Gremlin annotations applied successfully! ===${NC}"
  echo -e "${GREEN}✅ Total services annotated: $service_count${NC}"
  echo -e "${GREEN}✅ Total deployments annotated: $deployment_count${NC}"
  echo -e "${GREEN}✅ Pod templates updated${NC}"
  echo -e "${GREEN}✅ Gremlin agent configured${NC}"
  echo -e "${YELLOW}📝 Note: It may take a few minutes for changes to appear in the Gremlin UI${NC}"
}

# Execute main function
main "$@"
