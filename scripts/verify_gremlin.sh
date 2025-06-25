#!/bin/bash -e

# Set colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print section header
print_section() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

# Function to print success message
success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Function to print warning message
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Function to print error message
error() {
    echo -e "${RED}❌ $1${NC}"
}

# Main verification function
verify_gremlin() {
    local all_ready=true
    
    print_section "Verifying Gremlin Installation"
    
    # Check if Gremlin namespace exists
    if ! kubectl get ns gremlin &> /dev/null; then
        warning "Gremlin namespace not found. Gremlin may not be installed."
        echo "To install Gremlin, run: ./configure_cluster_base.sh --install-istio --install-gremlin"
        return 1
    fi
    
    success "Gremlin namespace exists"
    
    # Check Gremlin pods
    echo -e "\n${BLUE}Checking Gremlin pods...${NC}"
    if ! GREMLIN_PODS=$(kubectl get pods -n gremlin -o jsonpath='{range .items[*]}{.metadata.name}: {.status.phase}{if .status.containerStatuses[].ready=="true"} (Ready){else} (Not Ready){fi}{end}\n' 2>/dev/null); then
        error "Failed to get Gremlin pods"
        all_ready=false
    else
        if [ -z "$GREMLIN_PODS" ]; then
            warning "No Gremlin pods found. Gremlin may not be fully installed."
            all_ready=false
        else
            # Check each pod status
            while IFS= read -r pod; do
                if [[ $pod == *"Running (Ready)"* ]]; then
                    success "Pod: $pod"
                else
                    error "Pod not ready: $pod"
                    all_ready=false
                fi
            done <<< "$GREMLIN_PODS"
        fi
    fi
    
    # Check Gremlin daemonset
    echo -e "\n${BLUE}Checking Gremlin daemonset...${NC}"
    if ! GREMLIN_DS=$(kubectl get daemonset -n gremlin -l app=gremlin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); then
        error "Failed to get Gremlin daemonset"
        all_ready=false
    else
        success "Gremlin daemonset found: $GREMLIN_DS"
        
        # Check daemonset status
        DESIRED=$(kubectl get daemonset -n gremlin $GREMLIN_DS -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
        READY=$(kubectl get daemonset -n gremlin $GREMLIN_DS -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
        
        if [ "$DESIRED" -eq "$READY" ] && [ "$DESIRED" -gt 0 ]; then
            success "All $READY/$DESIRED Gremlin daemonset pods are ready"
        else
            error "Gremlin daemonset not fully ready: $READY/$DESIRED pods ready"
            all_ready=false
        fi
    fi
    
    # Check Gremlin service
    echo -e "\n${BLUE}Checking Gremlin service...${NC}"
    if ! GREMLIN_SVC=$(kubectl get svc -n gremlin -l app=gremlin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); then
        error "Failed to get Gremlin service"
        all_ready=false
    else
        success "Gremlin service found: $GREMLIN_SVC"
        
        # Check service endpoints
        ENDPOINTS=$(kubectl get endpoints -n gremlin $GREMLIN_SVC -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null || echo "")
        if [ -z "$ENDPOINTS" ]; then
            error "No endpoints found for Gremlin service"
            all_ready=false
        else
            success "Gremlin service endpoints: $ENDPOINTS"
        fi
    fi
    
    # Check Istio EnvoyFilter
    echo -e "\n${BLUE}Checking Istio EnvoyFilter...${NC}"
    if ! kubectl get envoyfilter -n istio-system gremlin-envoy-filter &> /dev/null; then
        error "Gremlin EnvoyFilter not found in istio-system namespace"
        echo "To fix, run: kubectl apply -f patches/gremlin-envoy-filter.yaml"
        all_ready=false
    else
        success "Gremlin EnvoyFilter is installed"
    fi
    
    if $all_ready; then
        success "✅ Gremlin installation verified successfully!"
        echo -e "\nTo access the Gremlin web UI, run:"
        echo "kubectl port-forward -n gremlin svc/gremlin 8080:80"
        echo -e "\nThen open http://localhost:8080 in your browser"
        return 0
    else
        error "❌ Gremlin installation has issues. Please check the above errors."
        return 1
    fi
}

# Execute verification
verify_gremlin

# Exit with appropriate status
if [ $? -eq 0 ]; then
    exit 0
else
    exit 1
fi
