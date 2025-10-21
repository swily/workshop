#!/bin/bash
#
# Common functions and utilities for workshop scripts
# Provides shared functionality across all workshop components
#

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# Script directory detection
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
}

# Function to get the preferred frontend FQDN (DNS first, fallback to ALB hostname)
get_frontend_fqdn() {
    local fqdn=""
    if [[ -n "${BASE_DOMAIN:-}" ]]; then
        fqdn="${HOST_PREFIX:-}${HOST_PREFIX:+}frontend.${BASE_DOMAIN}"
        echo "$fqdn"
        return 0
    fi
    # Fallback: discover ALB hostname from ingress
    local alb_host=$(kubectl get ingress -n otel-demo consolidated-demo-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    echo "$alb_host"
}

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_section() {
    echo -e "\n${GREEN}=== $1 ===${NC}"
}

# Function to print banner
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║    🚀 OpenTelemetry Demo Workshop Orchestration 🚀          ║"
    echo "║                                                              ║"
    echo "║    Complete Observability & Chaos Engineering Platform      ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    command -v aws >/dev/null 2>&1 || missing_tools+=("aws")
    command -v eksctl >/dev/null 2>&1 || missing_tools+=("eksctl")
    command -v istioctl >/dev/null 2>&1 || missing_tools+=("istioctl")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_warning "Please install the missing tools and try again."
        exit 1
    fi
    
    log_success "All prerequisites validated"
    echo ""
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if kubectl can connect to cluster
check_kubectl_connection() {
    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl cannot connect to cluster"
        return 1
    fi
    return 0
}

# Function to ensure namespace exists
ensure_namespace() {
    local namespace="$1"
    
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        log_info "Creating namespace: $namespace"
        kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - || {
            log_error "Failed to create namespace: $namespace"
            return 1
        }
    else
        log_info "Namespace $namespace already exists"
    fi
    return 0
}

# Function to wait for pods to be ready
wait_for_pods() {
    local namespace="$1"
    local label_selector="$2"
    local timeout="${3:-300}" # 5 minutes default
    local interval="${4:-10}" # 10 seconds default
    
    log_info "Waiting for pods to be ready in namespace: $namespace"
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local ready_pods=$(kubectl get pods -n "$namespace" -l "$label_selector" --no-headers 2>/dev/null | grep "Running" | wc -l)
        local total_pods=$(kubectl get pods -n "$namespace" -l "$label_selector" --no-headers 2>/dev/null | wc -l)
        
        if [ "$ready_pods" -gt 0 ] && [ "$ready_pods" -eq "$total_pods" ]; then
            log_success "All pods are ready ($ready_pods/$total_pods)"
            return 0
        fi
        
        log_info "Waiting for pods... ($ready_pods/$total_pods ready)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_warning "Timeout waiting for pods to be ready"
    kubectl get pods -n "$namespace" -l "$label_selector"
    return 1
}

# Function to ensure Helm repo is added
ensure_helm_repo() {
    local repo_name="$1"
    local repo_url="$2"
    
    log_info "Ensuring Helm repo $repo_name is available..."
    
    if ! helm repo list | grep -q "^${repo_name}"; then
        log_info "Adding Helm repo: $repo_name"
        helm repo add "$repo_name" "$repo_url"
    else
        log_info "Helm repo $repo_name already exists, updating..."
    fi
    
    helm repo update "$repo_name"
    log_success "Helm repo $repo_name is ready"
}

# Function to check if AWS CLI is configured
check_aws_config() {
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        log_info "Please run: aws configure"
        return 1
    fi
    
    local identity=$(aws sts get-caller-identity --output text --query 'Arn' 2>/dev/null)
    log_success "AWS CLI configured as: $identity"
    return 0
}

# Function to set AWS region
set_aws_region() {
    local region="$1"
    
    export AWS_REGION="$region"
    export AWS_DEFAULT_REGION="$region"
    
    log_success "AWS region set to: $region"
}

# Function to update kubeconfig for EKS cluster
update_kubeconfig() {
    local cluster_name="$1"
    local region="$2"
    
    log_info "Updating kubeconfig for cluster: $cluster_name"
    
    if aws eks update-kubeconfig --name "$cluster_name" --region "$region" &>/dev/null; then
        log_success "Kubeconfig updated successfully"
        return 0
    else
        log_error "Failed to update kubeconfig for cluster: $cluster_name"
        return 1
    fi
}

# Function to validate cluster exists
validate_cluster_exists() {
    local cluster_name="$1"
    local region="$2"
    
    log_info "Validating cluster exists: $cluster_name"
    
    if ! aws eks describe-cluster --region "$region" --name "$cluster_name" >/dev/null 2>&1; then
        log_error "Cluster '$cluster_name' not found in region '$region'"
        log_warning "Please check the cluster name and region, or create the cluster first."
        return 1
    fi
    
    log_success "Cluster '$cluster_name' found and accessible"
    return 0
}

# Function to get cluster status
get_cluster_status() {
    local cluster_name="$1"
    local region="$2"
    
    aws eks describe-cluster --region "$region" --name "$cluster_name" --query 'cluster.status' --output text 2>/dev/null
}

# Function to export cluster state for health checks
export_cluster_state() {
    local cluster_name="$1"
    local region="$2"
    local output_file="${3:-cluster-state.json}"
    
    log_info "Exporting cluster state for health check creation..."
    
    # Discover ALB endpoints dynamically
    log_info "Discovering ALB endpoints..."
    
    local frontend_alb=$(kubectl get ingress -n otel-demo frontend-proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    local grafana_monitoring_alb=$(kubectl get ingress -n monitoring grafana-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    local grafana_otel_alb=$(kubectl get ingress -n otel-demo grafana-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    local prometheus_alb=$(kubectl get ingress -n monitoring prometheus-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    # Ingress-only: no fallback to LoadBalancer Services
    
    # Preferred FQDN (DNS first, fallback to ALB hostname)
    local frontend_fqdn
    frontend_fqdn=$(get_frontend_fqdn)

    # Create state file
    cat > "$output_file" << EOF
{
  "cluster_name": "$cluster_name",
  "region": "$region",
  "endpoints": {
    "frontend": "${frontend_alb:+http://$frontend_alb}",
    "frontend_fqdn": "${frontend_fqdn:+http://$frontend_fqdn}",
    "grafana_monitoring": "${grafana_monitoring_alb:+http://$grafana_monitoring_alb}",
    "grafana_otel": "${grafana_otel_alb:+http://$grafana_otel_alb}",
    "prometheus": "${prometheus_alb:+http://$prometheus_alb}"
  },
  "dns_mappings": {
    "demo-frontend.$cluster_name.gremlinpoc.com": "frontend",
    "monitoring.$cluster_name.gremlinpoc.com": "grafana_monitoring",
    "monitoring.$cluster_name.gremlinpoc.com/prometheus": "prometheus"
  },
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log_success "Cluster state exported to: $output_file"
    log_info "Run './build_scripts/demo/healthchecks.sh' after DNS propagation to create health checks"
}

# Function to cleanup resources by label
cleanup_resources_by_label() {
    local namespace="$1"
    local label_selector="$2"
    
    log_info "Cleaning up resources in namespace: $namespace with labels: $label_selector"
    
    # Delete deployments
    kubectl delete deployments -n "$namespace" -l "$label_selector" --ignore-not-found=true
    
    # Delete services
    kubectl delete services -n "$namespace" -l "$label_selector" --ignore-not-found=true
    
    # Delete configmaps
    kubectl delete configmaps -n "$namespace" -l "$label_selector" --ignore-not-found=true
    
    # Delete secrets
    kubectl delete secrets -n "$namespace" -l "$label_selector" --ignore-not-found=true
    
    log_success "Cleanup completed for namespace: $namespace"
}

# Function to check if running in dry-run mode
is_dry_run() {
    [[ "${DRY_RUN:-false}" == "true" ]]
}

# Function to execute command with dry-run support
execute_command() {
    local cmd="$1"
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would execute: $cmd"
        return 0
    else
        log_info "Executing: $cmd"
        eval "$cmd"
    fi
}

# Function to prompt for confirmation
confirm_action() {
    local message="$1"
    local default="${2:-n}" # Default to 'n' if not specified
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$message [Y/n]: " response
            response=${response:-y}
        else
            read -p "$message [y/N]: " response
            response=${response:-n}
        fi
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}
