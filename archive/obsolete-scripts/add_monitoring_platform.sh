#!/bin/bash

# Add Monitoring Platform Post-Install
# Allows adding monitoring platforms after initial cluster deployment

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source common functions
source "$REPO_ROOT/lib/common.sh"

# Configuration
PLATFORM=""
CREATE_HEALTH_CHECKS=true
CLUSTER_NAME="${CLUSTER_NAME:-}"

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Add a monitoring platform to an existing cluster deployment.

OPTIONS:
  --platform PLATFORM    Platform to install (dynatrace|newrelic|datadog)
  --cluster-name NAME    Cluster name (default: from cluster-state.json)
  --no-health-checks     Skip creating health checks
  --help                 Show this help message

EXAMPLES:
  $0 --platform dynatrace
  $0 --platform newrelic --cluster-name my-cluster
  $0 --platform datadog --no-health-checks

ENVIRONMENT VARIABLES:
  Dynatrace:
    DYNATRACE_INSTANCE_ID   Dynatrace instance ID
    DYNATRACE_API_TOKEN     Dynatrace API token
  
  New Relic:
    NEW_RELIC_LICENSE_KEY   New Relic license key
  
  DataDog:
    DATADOG_API_KEY         DataDog API key
    DATADOG_APP_KEY         DataDog application key
  
  Gremlin (for health checks):
    GREMLIN_TEAM_ID         Gremlin team ID
    GREMLIN_API_KEY         Gremlin API key

EOF
}

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --platform)
                PLATFORM="$2"
                shift 2
                ;;
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --no-health-checks)
                CREATE_HEALTH_CHECKS=false
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    if [ -z "$PLATFORM" ]; then
        log_error "Platform is required. Use --platform <dynatrace|newrelic|datadog>"
        show_usage
        exit 1
    fi
}

# Load cluster state
load_cluster_state() {
    local state_file="$REPO_ROOT/build_scripts/demo/cluster-state.json"
    
    if [ -f "$state_file" ] && [ -z "$CLUSTER_NAME" ]; then
        CLUSTER_NAME=$(jq -r '.cluster_name' "$state_file" 2>/dev/null || echo "")
        if [ -n "$CLUSTER_NAME" ]; then
            log_info "Loaded cluster name from state: $CLUSTER_NAME"
        fi
    fi
    
    if [ -z "$CLUSTER_NAME" ]; then
        CLUSTER_NAME="current-workshop"
        log_warning "No cluster name found, using default: $CLUSTER_NAME"
    fi
    
    export CLUSTER_NAME
}

# Verify prerequisites
verify_prerequisites() {
    log_section "Verifying Prerequisites"
    
    # Check kubectl connection
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if Prometheus is installed (recommended)
    if ! kubectl get namespace monitoring &>/dev/null; then
        log_warning "Prometheus not found in monitoring namespace"
        log_warning "It's recommended to have Prometheus installed first"
        echo -n "Continue anyway? (y/n): "
        read -r response
        if [[ "$response" != "y" && "$response" != "Y" ]]; then
            exit 0
        fi
    fi
    
    log_success "Prerequisites verified"
}

# Install platform
install_platform() {
    local platform="$1"
    
    log_section "Installing $platform"
    
    case "$platform" in
        dynatrace)
            if [ -f "$REPO_ROOT/monitoring/dynatrace/install/install.sh" ]; then
                bash "$REPO_ROOT/monitoring/dynatrace/install/install.sh"
            else
                log_error "Dynatrace install script not found"
                exit 1
            fi
            ;;
        newrelic)
            if [ -f "$REPO_ROOT/monitoring/newrelic/install/install.sh" ]; then
                bash "$REPO_ROOT/monitoring/newrelic/install/install.sh"
            else
                log_error "New Relic install script not found"
                exit 1
            fi
            ;;
        datadog)
            if [ -f "$REPO_ROOT/monitoring/datadog/install/install.sh" ]; then
                bash "$REPO_ROOT/monitoring/datadog/install/install.sh"
            else
                log_error "DataDog install script not found"
                exit 1
            fi
            ;;
        *)
            log_error "Unknown platform: $platform"
            exit 1
            ;;
    esac
    
    log_success "$platform installation completed"
}

# Create health checks
create_health_checks() {
    local platform="$1"
    
    if [ "$CREATE_HEALTH_CHECKS" != true ]; then
        log_info "Skipping health check creation (--no-health-checks specified)"
        return 0
    fi
    
    log_section "Creating Health Checks for $platform"
    
    # Check if Gremlin credentials are available
    if [ -z "${GREMLIN_TEAM_ID:-}" ] || [ -z "${GREMLIN_API_KEY:-}" ]; then
        log_warning "Gremlin credentials not found"
        log_info "To create health checks later, run:"
        log_info "  ./monitoring/create_health_checks.sh --platform $platform"
        return 0
    fi
    
    # Use unified health check creator
    if [ -f "$REPO_ROOT/monitoring/create_health_checks.sh" ]; then
        bash "$REPO_ROOT/monitoring/create_health_checks.sh" --platform "$platform"
    else
        log_warning "Unified health check creator not found"
        log_info "To create health checks manually, run:"
        log_info "  ./monitoring/$platform/create_health_checks.sh"
    fi
}

# Main
main() {
    log_section "Add Monitoring Platform"
    
    parse_arguments "$@"
    load_cluster_state
    verify_prerequisites
    
    log_info "Platform: $platform"
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Create health checks: $CREATE_HEALTH_CHECKS"
    echo ""
    
    install_platform "$PLATFORM"
    create_health_checks "$PLATFORM"
    
    log_section "Summary"
    log_success "$PLATFORM has been added to cluster: $CLUSTER_NAME"
    
    echo ""
    log_info "Next steps:"
    case "$PLATFORM" in
        dynatrace)
            log_info "  1. Visit https://${DYNATRACE_INSTANCE_ID:-YOUR_INSTANCE}.live.dynatrace.com"
            log_info "  2. Verify cluster appears in Dynatrace"
            ;;
        newrelic)
            log_info "  1. Visit https://one.newrelic.com"
            log_info "  2. Navigate to Infrastructure > Kubernetes"
            ;;
        datadog)
            log_info "  1. Visit https://app.datadoghq.com/infrastructure"
            log_info "  2. Verify cluster appears in DataDog"
            ;;
    esac
    
    if [ "$CREATE_HEALTH_CHECKS" == true ]; then
        log_info "  3. View health checks: https://app.gremlin.com/reliability/status-checks"
    fi
    echo ""
}

main "$@"
