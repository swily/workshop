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
source "$SCRIPT_DIR/lib/terraform.sh"

# Enforce consolidated ingress mode (single ALB with path-based routing)
export CONSOLIDATED_INGRESS=true

# Parse command line arguments
parse_arguments() {
    # Terraform-compatible arguments
    SUBDOMAIN=""
    OWNER=""
    ENABLE_EKS=false
    ENABLE_ECS_FARGATE=false
    
    # Gremlin Secrets Manager ARNs (optional - can auto-resolve from owner)
    GREMLIN_TEAM_ID_ARN=""
    GREMLIN_TEAM_CERTIFICATE_ARN=""
    GREMLIN_TEAM_PRIVATE_KEY_ARN=""
    
    # Legacy credential support (backwards compatible)
    GREMLIN_TEAM_ID="${GREMLIN_TEAM_ID:-}"
    GREMLIN_TEAM_SECRET="${GREMLIN_TEAM_SECRET:-}"
    GREMLIN_API_KEY="${GREMLIN_API_KEY:-}"
    
    # Workshop-specific arguments
    MONITORING_PLATFORM="prometheus"
    INSTALL_ISTIO=false
    ENABLE_FAILURE_FLAGS=false
    WORKSHOP_ACTION=""
    
    # Terraform configuration
    FCM_VERSION="${FCM_VERSION:-main}"
    
    # Legacy arguments (for backwards compatibility)
    CLUSTER_NAME=""
    AWS_REGION="${AWS_REGION:-us-east-2}"
    BASE_DOMAIN="gremlinpoc.com"
    HOST_PREFIX=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --subdomain)
                SUBDOMAIN="$2"
                shift 2
                ;;
            --owner)
                OWNER="$2"
                shift 2
                ;;
            --enable-eks)
                ENABLE_EKS=true
                shift
                ;;
            --enable-ecs-fargate)
                ENABLE_ECS_FARGATE=true
                shift
                ;;
            --gremlin-team-id-arn)
                GREMLIN_TEAM_ID_ARN="$2"
                shift 2
                ;;
            --gremlin-team-certificate-arn)
                GREMLIN_TEAM_CERTIFICATE_ARN="$2"
                shift 2
                ;;
            --gremlin-team-private-key-arn)
                GREMLIN_TEAM_PRIVATE_KEY_ARN="$2"
                shift 2
                ;;
            --fcm-version)
                FCM_VERSION="$2"
                shift 2
                ;;
            --cluster-name)
                CLUSTER_NAME="$2"
                SUBDOMAIN="$2"  # Map to subdomain for backwards compatibility
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
    
    # Validation for Terraform-based deployments
    if [[ "$WORKSHOP_ACTION" == "create_new" || "$WORKSHOP_ACTION" == "build_new" ]]; then
        if [[ -z "$SUBDOMAIN" ]]; then
            log_error "Missing required argument: --subdomain"
            exit 1
        fi
        
        if [[ -z "$OWNER" ]]; then
            log_error "Missing required argument: --owner"
            exit 1
        fi
        
        if [[ "$ENABLE_EKS" == false && "$ENABLE_ECS_FARGATE" == false ]]; then
            log_error "Must enable at least one platform: --enable-eks or --enable-ecs-fargate"
            exit 1
        fi
    fi
    
    # Set CLUSTER_NAME from SUBDOMAIN if not set (for backwards compatibility)
    if [[ -z "$CLUSTER_NAME" && -n "$SUBDOMAIN" ]]; then
        CLUSTER_NAME="${SUBDOMAIN}-eks"
    fi
    
    # Export for use in other scripts
    export SUBDOMAIN OWNER ENABLE_EKS ENABLE_ECS_FARGATE
    export GREMLIN_TEAM_ID_ARN GREMLIN_TEAM_CERTIFICATE_ARN GREMLIN_TEAM_PRIVATE_KEY_ARN
    export FCM_VERSION MONITORING_PLATFORM INSTALL_ISTIO ENABLE_FAILURE_FLAGS
    export CLUSTER_NAME AWS_REGION BASE_DOMAIN HOST_PREFIX
}
# Provision infrastructure with Terraform
provision_infrastructure() {
    log_section "Provisioning Infrastructure with Terraform"
    
    local workspace_dir=$(get_workspace_dir "$SUBDOMAIN")
    
    # Resolve Gremlin credentials if not explicitly provided
    if [[ -z "$GREMLIN_TEAM_ID_ARN" && -n "$OWNER" ]]; then
        log_info "No explicit Gremlin credentials provided, attempting owner-based lookup"
        resolve_gremlin_credentials_from_owner "$OWNER" || {
            log_warning "Owner-based credential lookup failed"
            log_info "You can provide explicit ARNs with --gremlin-team-id-arn, etc."
            return 1
        }
    fi
    
    # Create Terraform workspace
    terraform_create_workspace \
        "$SUBDOMAIN" \
        "$OWNER" \
        "$ENABLE_EKS" \
        "$ENABLE_ECS_FARGATE" \
        "$GREMLIN_TEAM_ID_ARN" \
        "$GREMLIN_TEAM_CERTIFICATE_ARN" \
        "$GREMLIN_TEAM_PRIVATE_KEY_ARN"
    
    # Initialize and validate Terraform
    terraform_init "$workspace_dir"
    terraform_validate "$workspace_dir"
    
    # Plan and apply
    terraform_plan "$workspace_dir"
    terraform_apply "$workspace_dir"
    
    # Export outputs to environment
    export_terraform_outputs "$workspace_dir"
    
    # Fetch Gremlin credentials from Secrets Manager
    fetch_gremlin_credentials
    
    # Update kubeconfig
    update_kubeconfig "$CLUSTER_NAME" "$AWS_REGION"
    
    log_success "Infrastructure provisioned successfully"
}

# Core workflow functions
create_and_deploy() {
    log_section "Creating New Cluster and Deploying Everything"
    
    # Provision infrastructure with Terraform
    provision_infrastructure
    
    # Configure cluster base components (AWS LB Controller, Istio, etc.)
    configure_cluster_base "$CLUSTER_NAME" "$INSTALL_ISTIO" "$MONITORING_PLATFORM"
    
    # Deploy OpenTelemetry demo
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
    
    # Determine workspace directory
    local workspace_dir
    if [[ -n "$SUBDOMAIN" ]]; then
        workspace_dir=$(get_workspace_dir "$SUBDOMAIN")
    else
        log_error "Cannot determine workspace. Please provide --subdomain"
        return 1
    fi
    
    # Check if workspace exists
    if ! workspace_exists "$SUBDOMAIN"; then
        log_warning "No Terraform workspace found for: $SUBDOMAIN"
        log_info "Falling back to manual cleanup"
        "$SCRIPT_DIR/scripts/operations/cluster_cleanup.sh" \
            --cluster-name "$CLUSTER_NAME" \
            --region "$AWS_REGION"
        return
    fi
    
    # Clean up Kubernetes resources first (prevents hanging ALBs)
    log_info "Cleaning up Kubernetes resources..."
    kubectl delete ingress -A --all --ignore-not-found=true 2>/dev/null || true
    kubectl delete svc -A --field-selector spec.type=LoadBalancer --ignore-not-found=true 2>/dev/null || true
    sleep 10
    
    # Destroy infrastructure with Terraform
    terraform_destroy "$workspace_dir"
    
    log_success "Cluster cleanup completed"
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

    # Set base domain
    BASE_DOMAIN="gremlinpoc.com"
    export BASE_DOMAIN
    
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
