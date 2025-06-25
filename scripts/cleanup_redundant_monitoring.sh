#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${RED}=== Cleaning up redundant monitoring components ===${NC}"

# Check if monitoring namespace exists
if kubectl get namespace monitoring &> /dev/null; then
    echo -e "Found 'monitoring' namespace. Checking contents..."
    
    # List resources in monitoring namespace
    echo -e "\nResources in 'monitoring' namespace:"
    kubectl get all -n monitoring
    
    # Ask for confirmation
    read -p "Do you want to delete the 'monitoring' namespace and all its resources? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "\n${RED}Deleting 'monitoring' namespace...${NC}"
        kubectl delete namespace monitoring
        echo -e "${GREEN}✓ Successfully removed 'monitoring' namespace${NC}"
    else
        echo -e "\nSkipping deletion of 'monitoring' namespace"
    fi
else
    echo -e "${GREEN}✓ 'monitoring' namespace not found${NC}
"
fi

echo -e "\n${GREEN}Cleanup complete!${NC}"
echo -e "\nCurrent monitoring components:"
echo "- Istio Monitoring:  kubectl get all -n istio-system"
echo "- OTel Demo Metrics: kubectl get all -n otel-demo | grep -E 'prometheus|grafana'"
