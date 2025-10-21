#!/bin/bash
#
# Modular Workshop Orchestration Script
# OpenTelemetry Demo Workshop Setup with Integrated Monitoring & Chaos Engineering
#

set -Eeu

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/cluster.sh"
source "$SCRIPT_DIR/lib/monitoring.sh"

# Enforce consolidated ingress mode (single ALB with path-based routing)
export CONSOLIDATED_INGRESS=true

# Parse command line arguments
parse_arguments() {
    # Internal defaults for HTTPS/DNS (no user input required)
    HTTPS_MODE="${HTTPS_MODE:-off}"
    BASE_DOMAIN="${BASE_DOMAIN:-}"
    HOST_PREFIX="${HOST_PREFIX:-}"
    ACM_CERT_ARN="${ACM_CERT_ARN:-}"

    # Feature flags
    INSTALL_ISTIO=false
    ENABLE_FAILURE_FLAGS=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --monitoring)
                MONITORING_PLATFORM="$2"
                shift 2
                ;;
            --https)
                # Values: off | alb-acm
                HTTPS_MODE="$2"
                shift 2
                ;;
            --externaldns-iam-role-arn)
                EXTERNALDNS_IAM_ROLE_ARN="$2"
                shift 2
                ;;
            --action)
                WORKSHOP_ACTION="$2"
                shift 2
                ;;
            --install-istio)
                INSTALL_ISTIO=true
                shift
                ;;
            --enable-failure-flags)
                ENABLE_FAILURE_FLAGS=true
                shift
                ;;
            --gremlin-team-id)
                GREMLIN_TEAM_ID="$2"
                shift 2
                ;;
            --gremlin-team-secret)
                GREMLIN_TEAM_SECRET="$2"
                shift 2
                ;;
            --gremlin-api-key)
                GREMLIN_API_KEY="$2"
                shift 2
                ;;
            --skip-patches)
                APPLY_PATCHES=false
                shift
                ;;
            --skip-gremlin-enhancements)
                APPLY_GREMLIN_ENHANCEMENTS=false
                shift
                ;;
            --dry-run)
                export DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown parameter: $1"
                show_help
                exit 1
                ;;
        esac
    done
}
# NOTE: patch_consolidated_ingress_dns_tls() removed - Terraform creates ALB with TLS
# Terraform ALB module handles certificate attachment and HTTPS configuration
# Core workflow functions
create_and_deploy() {
    log_section "Creating New Cluster and Deploying Everything"
    
    # Create cluster
    CREATE_ARGS=(
        --cluster-name "$CLUSTER_NAME"
        --region "$AWS_REGION"
        --monitoring "$MONITORING_PLATFORM"
    )
    if [ "$INSTALL_ISTIO" = true ]; then
        CREATE_ARGS+=(--install-istio)
    fi
    "$SCRIPT_DIR/scripts/operations/cluster_create.sh" "${CREATE_ARGS[@]}"
    
    # Deploy OpenTelemetry demo (skip per-app ingress when CONSOLIDATED_INGRESS=true)
    CONSOLIDATED_INGRESS=true "$SCRIPT_DIR/scripts/operations/deploy_otel.sh" \
        --cluster-name "$CLUSTER_NAME"
    
    # Setup Gremlin
    setup_gremlin_only
    
    # Deploy failure flags if requested
    if [[ "$ENABLE_FAILURE_FLAGS" == "true" ]]; then
        log_info "Deploying Failure Flags sidecar..."
        "$SCRIPT_DIR/scripts/operations/deploy_failure_flags.sh" \
            --cluster-name "$CLUSTER_NAME"
    fi
    
    # Setup monitoring (skip per-app ingresses when CONSOLIDATED_INGRESS=true)
    CONSOLIDATED_INGRESS=true setup_comprehensive_monitoring "$MONITORING_PLATFORM"

    # Apply cross-namespace services to route monitoring through consolidated ALB
    log_info "Applying cross-namespace services for consolidated ingress..."
    if [[ -f "$SCRIPT_DIR/otel-demo-cross-namespace-services.yaml" ]]; then
        kubectl apply -f "$SCRIPT_DIR/otel-demo-cross-namespace-services.yaml" || {
            log_error "Failed to apply cross-namespace services"
            return 1
        }
    else
        log_warning "Cross-namespace services file not found: $SCRIPT_DIR/otel-demo-cross-namespace-services.yaml"
    fi

    # NOTE: Consolidated ingress creation removed - Terraform creates ALB listener rules
    # Terraform ALB module handles target groups and routing configuration

    # Remove any legacy per-app ingresses if they exist (idempotent cleanup)
    kubectl delete ingress -n otel-demo frontend-proxy jaeger-ingress 2>/dev/null || true
    kubectl delete ingress -n monitoring grafana-ingress prometheus-ingress 2>/dev/null || true
    
    # Export cluster state
    export_cluster_state "$CLUSTER_NAME" "$AWS_REGION"
    
    # Display endpoints
    display_workshop_endpoints
}

deploy_to_existing() {
    log_section "Deploying to Existing Cluster"
    
    # Validate cluster exists
    validate_cluster_exists "$CLUSTER_NAME" "$AWS_REGION"
    update_kubeconfig "$CLUSTER_NAME" "$AWS_REGION"
    
    # Check for existing installations and handle conflicts
    log_info "Checking for existing installations..."
    
    # Check for existing OpenTelemetry Demo
    if helm list -n otel-demo -q | grep -q "opentelemetry-demo"; then
        log_warning "Existing OpenTelemetry Demo found. Upgrading in place..."
        helm upgrade opentelemetry-demo open-telemetry/opentelemetry-demo -n otel-demo --reuse-values || {
            log_warning "Upgrade failed, uninstalling and reinstalling..."
            helm uninstall opentelemetry-demo -n otel-demo --ignore-not-found
            sleep 10
        }
    fi
    
    # Check for existing Gremlin installation
    if helm list -n gremlin -q | grep -q "gremlin"; then
        log_warning "Existing Gremlin installation found. Uninstalling first..."
        helm uninstall gremlin -n gremlin --ignore-not-found
        sleep 10
    fi
    
    # Deploy OpenTelemetry demo
    "$SCRIPT_DIR/scripts/operations/deploy_otel.sh" \
        --cluster-name "$CLUSTER_NAME"
    
    # Install Gremlin
    GREMLIN_TEAM_ID="$GREMLIN_TEAM_ID" \
    GREMLIN_TEAM_SECRET="$GREMLIN_TEAM_SECRET" \
    GREMLIN_API_KEY="$GREMLIN_API_KEY" \
    "$SCRIPT_DIR/scripts/gremlin_install.sh" \
        --cluster-name "$CLUSTER_NAME" \
        --team-id "$GREMLIN_TEAM_ID" \
        --team-secret "$GREMLIN_TEAM_SECRET" \
        --api-key "$GREMLIN_API_KEY"
    
    # Apply Gremlin service annotations
    log_info "Applying Gremlin service annotations..."
    "$SCRIPT_DIR/config/gremlin/gremlin_annotations.sh" otel-demo
    
    # Deploy failure flags if requested
    if [[ "$ENABLE_FAILURE_FLAGS" == "true" ]]; then
        log_info "Deploying Failure Flags sidecar..."
        "$SCRIPT_DIR/scripts/operations/deploy_failure_flags.sh" \
            --cluster-name "$CLUSTER_NAME"
    fi
    
    # Setup monitoring
    MONITORING_PLATFORM="$MONITORING_PLATFORM" setup_comprehensive_monitoring "$MONITORING_PLATFORM"
    
    # Setup consolidated ingress and DNS
    setup_consolidated_ingress_and_dns
    
    # Export cluster state
    export_cluster_state "$CLUSTER_NAME" "$AWS_REGION"
    
    # Display endpoints
    display_workshop_endpoints
}

setup_gremlin_only() {
    log_section "Setting up Gremlin Only"
    
    # Validate cluster exists
    validate_cluster_exists "$CLUSTER_NAME" "$AWS_REGION"
    update_kubeconfig "$CLUSTER_NAME" "$AWS_REGION"
    
    # Install Gremlin
    GREMLIN_TEAM_ID="$GREMLIN_TEAM_ID" \
    GREMLIN_TEAM_SECRET="$GREMLIN_TEAM_SECRET" \
    GREMLIN_API_KEY="$GREMLIN_API_KEY" \
    "$SCRIPT_DIR/scripts/gremlin_install.sh" \
        --cluster-name "$CLUSTER_NAME" \
        --team-id "$GREMLIN_TEAM_ID" \
        --team-secret "$GREMLIN_TEAM_SECRET" \
        --api-key "$GREMLIN_API_KEY"
    
    # Apply Gremlin service annotations
    log_info "Applying Gremlin service annotations..."
    "$SCRIPT_DIR/config/gremlin/gremlin_annotations.sh" otel-demo
    
    # Setup Gremlin monitoring
    MONITORING_PLATFORM="$MONITORING_PLATFORM" setup_gremlin_monitoring
    
    log_success "Gremlin setup completed!"
}

cleanup_cluster_wrapper() {
    log_section "Cleaning up Cluster"
    
    "$SCRIPT_DIR/scripts/operations/cluster_cleanup.sh" \
        --cluster-name "$CLUSTER_NAME" \
        --region "$AWS_REGION"
}

# Interactive mode functions
run_interactive_mode() {
    # Ensure we are interacting with the terminal device directly
    if [ -e /dev/tty ]; then
        exec </dev/tty >/dev/tty 2>&1
    fi
    # Collect user choices
    collect_workshop_action
    collect_cluster_info
    
    # Collect credentials if needed
    if [[ "$WORKSHOP_ACTION" != "cleanup" ]]; then
        collect_gremlin_credentials
        collect_monitoring_platform
        collect_advanced_options
    fi
    
    # Display configuration summary
    display_configuration_summary
}

# Main execution function
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Show banner
    print_banner
    
    # If no arguments provided, run interactive mode
    if [ -z "$WORKSHOP_ACTION" ]; then
        run_interactive_mode
    fi
    
    # Validate prerequisites
    validate_prerequisites
    check_aws_config
    set_aws_region "$AWS_REGION"

    # Resolve HOST_PREFIX default if not set
    if [ -z "${HOST_PREFIX}" ]; then
        HOST_PREFIX="${CLUSTER_NAME}-"
    fi

    # NOTE: ACM certificate auto-detection removed - Terraform handles TLS configuration
    # Terraform ALB module manages certificates and HTTPS setup
    BASE_DOMAIN="gremlinpoc.com"
    export BASE_DOMAIN HOST_PREFIX
    
    # Execute the requested action
    case "$WORKSHOP_ACTION" in
        "build_new")
            create_and_deploy
            ;;
        "deploy_existing")
            deploy_to_existing
            ;;
        "gremlin_only")
            setup_gremlin_only
            ;;
        "cleanup")
            cleanup_cluster_wrapper
            ;;
        *)
            log_error "Unknown action: $WORKSHOP_ACTION"
            show_help
            exit 1
            ;;
    esac
    
    log_success "Workshop operation completed successfully!"
}

# Run main function
main "$@"
