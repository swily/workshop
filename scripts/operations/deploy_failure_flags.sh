#!/bin/bash
#
# Gremlin Failure Flags Deployment Script
# Deploys failure flags sidecar to OpenTelemetry Demo checkout service
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
source "$SCRIPT_DIR/../../lib/ui.sh"

# Default configuration
CLUSTER_NAME=""
NAMESPACE="otel-demo"
GREMLIN_NAMESPACE="gremlin"

# Function to show help
show_help() {
    help_header \
        "" \
        "Deploys Gremlin Failure Flags sidecar to OpenTelemetry Demo checkout service.\nEnables failure injection for checkout → downstream service calls."
    cat << EOF

OPTIONS:
  --cluster-name NAME     Target cluster name (required)
  --namespace NS          Target namespace (default: otel-demo)
  --dry-run               Show what would be done without executing

EXAMPLES:
  ./scripts/operations/deploy_failure_flags.sh --cluster-name my-workshop
  ./scripts/operations/deploy_failure_flags.sh --cluster-name test-cluster --dry-run

DESCRIPTION:
  This script deploys a Gremlin Failure Flags sidecar container alongside the
  OpenTelemetry Demo checkout service. The sidecar intercepts:
  
  - Ingress traffic: Frontend → Checkout (port 5035)
  - Egress traffic: Checkout → [Payment, Cart, Shipping, etc.] (port 5034)
  
  Only the checkout service is modified - all downstream services remain unchanged.
  
PREREQUISITES:
  - OpenTelemetry Demo must be deployed
  - Gremlin secrets must be configured
  - kubectl access to target cluster

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$CLUSTER_NAME" ]]; then
    log_error "Cluster name is required. Use --cluster-name option."
    exit 1
fi

# Function to check prerequisites
check_prerequisites() {
    log_section "Checking Prerequisites"
    
    # Check kubectl access
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "kubectl not configured or cluster not accessible"
        return 1
    fi
    
    # Check if OpenTelemetry Demo is deployed
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_error "Namespace '$NAMESPACE' not found. Deploy OpenTelemetry Demo first."
        return 1
    fi
    
    if ! kubectl get deployment -n "$NAMESPACE" opentelemetry-demo-checkoutservice >/dev/null 2>&1; then
        log_error "OpenTelemetry Demo checkout service not found in namespace '$NAMESPACE'"
        log_info "Run: ./scripts/operations/deploy_otel.sh --cluster-name $CLUSTER_NAME"
        return 1
    fi
    
    # Check if Gremlin secrets exist
    if ! kubectl get secret -n "$GREMLIN_NAMESPACE" gremlin-secret >/dev/null 2>&1; then
        log_warning "Gremlin secret not found in namespace '$GREMLIN_NAMESPACE'"
        log_info "Run: ./scripts/gremlin_install.sh --cluster-name $CLUSTER_NAME"
        log_info "Continuing without secret validation..."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to backup original checkout deployment
backup_original_deployment() {
    log_info "Backing up original checkout deployment..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would backup original deployment"
        return 0
    fi
    
    kubectl get deployment -n "$NAMESPACE" opentelemetry-demo-checkoutservice -o yaml > "/tmp/checkout-original-backup-$(date +%Y%m%d-%H%M%S).yaml"
    log_success "Original deployment backed up to /tmp/"
}

# Function to deploy failure flags
deploy_failure_flags() {
    log_section "Deploying Failure Flags Sidecar"
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would deploy failure flags sidecar"
        return 0
    fi
    
    # Apply the failure flags deployment
    local config_file="$SCRIPT_DIR/../../config/gremlin/checkout-failure-flags.yaml"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Failure flags configuration not found: $config_file"
        return 1
    fi
    
    log_info "Applying failure flags configuration..."
    kubectl apply -f "$config_file"
    
    # Scale down original deployment
    log_info "Scaling down original checkout deployment..."
    kubectl scale deployment -n "$NAMESPACE" opentelemetry-demo-checkoutservice --replicas=0
    
    # Wait for failure flags deployment to be ready
    log_info "Waiting for failure flags deployment to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/opentelemetry-demo-checkoutservice-ff -n "$NAMESPACE"
    
    log_success "Failure flags sidecar deployed successfully"
}

# Function to update frontend service routing
update_service_routing() {
    log_info "Updating service routing to failure flags deployment..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would update service routing"
        return 0
    fi
    
    # Patch the checkout service to point to failure flags deployment
    kubectl patch service -n "$NAMESPACE" opentelemetry-demo-checkoutservice -p '{
        "spec": {
            "selector": {
                "gremlin.com/failure-flags": "enabled"
            }
        }
    }'
    
    log_success "Service routing updated to failure flags deployment"
}

# Function to verify deployment
verify_deployment() {
    log_section "Verifying Failure Flags Deployment"
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would verify deployment"
        return 0
    fi
    
    # Check deployment status
    local deployment_status=$(kubectl get deployment -n "$NAMESPACE" opentelemetry-demo-checkoutservice-ff -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    if [[ "$deployment_status" == "1" ]]; then
        log_success "✅ Failure flags deployment is ready"
    else
        log_error "❌ Failure flags deployment not ready"
        return 1
    fi
    
    # Check sidecar containers
    local pod_name=$(kubectl get pods -n "$NAMESPACE" -l gremlin.com/failure-flags=enabled -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$pod_name" ]]; then
        log_info "Checking sidecar containers in pod: $pod_name"
        
        local containers=$(kubectl get pod -n "$NAMESPACE" "$pod_name" -o jsonpath='{.spec.containers[*].name}')
        if [[ "$containers" == *"gremlin-sidecar"* ]]; then
            log_success "✅ Gremlin sidecar container found"
        else
            log_error "❌ Gremlin sidecar container not found"
            return 1
        fi
    else
        log_error "❌ No failure flags pods found"
        return 1
    fi
    
    log_success "Failure flags deployment verification completed"
}

# Function to display usage information
display_usage_info() {
    log_section "Failure Flags Usage Information"
    
    echo -e "${YELLOW}🎯 Failure Injection Capabilities:${NC}"
    echo "  • Ingress failures: Frontend → Checkout (latency, errors)"
    echo "  • Egress failures: Checkout → Payment/Cart/Shipping (service unavailable)"
    echo "  • Response manipulation: Modify checkout responses"
    echo ""
    
    echo -e "${YELLOW}🔧 Gremlin Configuration:${NC}"
    echo "  • Ingress Proxy: localhost:5035 (intercepts incoming traffic)"
    echo "  • Dependency Proxy: localhost:5034 (intercepts outgoing traffic)"
    echo "  • Target Services: Payment, Cart, Currency, Email, Shipping, Product-Catalog"
    echo ""
    
    echo -e "${YELLOW}📊 Monitoring:${NC}"
    echo "  • View failures in Jaeger traces"
    echo "  • Monitor error rates in Grafana"
    echo "  • Check service health in Prometheus"
    echo ""
    
    echo -e "${YELLOW}🔄 Rollback Command:${NC}"
    echo "  kubectl scale deployment -n $NAMESPACE opentelemetry-demo-checkoutservice --replicas=1"
    echo "  kubectl scale deployment -n $NAMESPACE opentelemetry-demo-checkoutservice-ff --replicas=0"
    echo ""
}

# Main execution
main() {
    print_banner
    
    log_info "Deploying Failure Flags with configuration:"
    echo "  Cluster: $CLUSTER_NAME"
    echo "  Namespace: $NAMESPACE"
    echo "  Target Service: checkout"
    echo ""
    
    # Execute deployment steps
    check_prerequisites
    backup_original_deployment
    deploy_failure_flags
    update_service_routing
    verify_deployment
    display_usage_info
    
    log_success "Failure Flags deployment completed successfully!"
    log_info "You can now configure failure scenarios in the Gremlin web console"
}

# Execute main function
main "$@"
