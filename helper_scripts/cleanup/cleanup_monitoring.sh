#!/bin/bash

# Comprehensive Monitoring Cleanup Script
# This script ensures clean removal of all monitoring resources to prevent stuck resources

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧽 Cleaning previous monitoring resources...${NC}"

# Function to force delete stuck resources
force_delete_stuck_resources() {
    local namespace=$1
    echo -e "${YELLOW}Force deleting stuck resources in namespace: $namespace${NC}"
    
    # Force delete stuck terminating pods
    kubectl get pods -n "$namespace" | grep Terminating | awk '{print $1}' | xargs -r kubectl delete pod -n "$namespace" --force --grace-period=0 >/dev/null 2>&1 || true
    
    # Force delete failed pods
    kubectl get pods -n "$namespace" --field-selector=status.phase=Failed -o name 2>/dev/null | xargs -r kubectl delete --force --grace-period=0 >/dev/null 2>&1 || true
    
    # Force delete stuck statefulsets
    kubectl get statefulsets -n "$namespace" -o name 2>/dev/null | xargs -r kubectl delete --force --grace-period=0 >/dev/null 2>&1 || true
    
    # Force delete stuck deployments
    kubectl get deployments -n "$namespace" -o name 2>/dev/null | xargs -r kubectl delete --force --grace-period=0 2>/dev/null || true
    
    # Force delete stuck daemonsets
    kubectl get daemonsets -n "$namespace" -o name 2>/dev/null | xargs -r kubectl delete --force --grace-period=0 2>/dev/null || true
}

# Cleanup Prometheus/monitoring namespace
if kubectl get namespace monitoring &>/dev/null; then
    echo -e "${BLUE}Cleaning up monitoring namespace...${NC}"
    
    # Uninstall Helm releases
    helm list -n monitoring -q | xargs -r helm uninstall -n monitoring 2>/dev/null || true
    
    # Force delete stuck resources
    force_delete_stuck_resources "monitoring"
    
    # Clean up remaining resources
    kubectl delete all --all -n monitoring --force --grace-period=0 2>/dev/null || true
    kubectl delete configmaps,secrets,pvc --all -n monitoring 2>/dev/null || true
    
    # Wait for cleanup
    sleep 10
    
    echo -e "${GREEN}✅ Monitoring namespace cleaned${NC}"
fi

# Cleanup other monitoring namespaces
for ns in dynatrace newrelic datadog; do
    if kubectl get namespace "$ns" &>/dev/null; then
        echo -e "${BLUE}Cleaning up $ns namespace...${NC}"
        
        # Uninstall Helm releases
        helm list -n "$ns" -q | xargs -r helm uninstall -n "$ns" 2>/dev/null || true
        
        # Force delete stuck resources
        force_delete_stuck_resources "$ns"
        
        # Clean up remaining resources
        kubectl delete all --all -n "$ns" --force --grace-period=0 2>/dev/null || true
        kubectl delete configmaps,secrets,pvc --all -n "$ns" 2>/dev/null || true
        
        echo -e "${GREEN}✅ $ns namespace cleaned${NC}"
    fi
done

# Clean up any orphaned CRDs related to monitoring
echo -e "${BLUE}Cleaning up monitoring-related CRDs...${NC}"
kubectl get crd | grep -E "(prometheus|alertmanager|servicemonitor|podmonitor|prometheusrule)" | awk '{print $1}' | xargs -r kubectl delete crd 2>/dev/null || true

echo -e "${GREEN}🎉 Comprehensive monitoring cleanup complete!${NC}"
