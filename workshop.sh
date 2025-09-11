#!/bin/bash
#
# Modular Workshop Orchestration Script
# OpenTelemetry Demo Workshop Setup with Integrated Monitoring & Chaos Engineering
#

set -Eeuo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/cluster.sh"
source "$SCRIPT_DIR/lib/monitoring.sh"

# Parse command line arguments
parse_arguments() {
    # Internal defaults for HTTPS/DNS (no user input required)
    HTTPS_MODE="${HTTPS_MODE:-off}"
    BASE_DOMAIN="${BASE_DOMAIN:-}"
    HOST_PREFIX="${HOST_PREFIX:-}"
    ACM_CERT_ARN="${ACM_CERT_ARN:-}"

    # Feature flags
    INSTALL_ISTIO=false

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
    
    # Deploy OpenTelemetry demo
    "$SCRIPT_DIR/scripts/operations/deploy_otel.sh" \
        --cluster-name "$CLUSTER_NAME"
    
    # Install Gremlin
    "$SCRIPT_DIR/scripts/gremlin_install.sh" \
        --cluster-name "$CLUSTER_NAME" \
        --team-id "$GREMLIN_TEAM_ID" \
        --team-secret "$GREMLIN_TEAM_SECRET" \
        --api-key "$GREMLIN_API_KEY"
    
    # Setup monitoring
    setup_comprehensive_monitoring "$MONITORING_PLATFORM"
    
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
    
    # Setup monitoring
    MONITORING_PLATFORM="$MONITORING_PLATFORM" setup_comprehensive_monitoring "$MONITORING_PLATFORM"
    
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
        --api-key "$GREMLIN_API_KEY" \
        --auto-tag "otel-demo"
    
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
    # Collect user choices
    WORKSHOP_ACTION=$(collect_workshop_action)
    cluster_info=$(collect_cluster_info)
    CLUSTER_NAME=$(echo "$cluster_info" | cut -d':' -f1)
    AWS_REGION=$(echo "$cluster_info" | cut -d':' -f2)
    
    # Collect credentials if needed
    if [[ "$WORKSHOP_ACTION" != "cleanup" ]]; then
        collect_gremlin_credentials
        MONITORING_PLATFORM=$(collect_monitoring_platform)
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

    # Auto-configure domain and ACM certificate for ALB TLS
    BASE_DOMAIN="gremlinpoc.com"
    ACM_CERT_ARN=${ACM_CERT_ARN:-}
    # Only auto-detect ACM if user hasn't overridden --https
    if [ -z "${HTTPS_MODE:-}" ]; then
        if command_exists aws; then
            found_arn=$(aws acm list-certificates \
                --region "$AWS_REGION" \
                --certificate-statuses ISSUED \
                --query "CertificateSummaryList[?DomainName=='*.${BASE_DOMAIN}' || DomainName=='${BASE_DOMAIN}'].CertificateArn" \
                --output text 2>/dev/null | head -n1 || true)
            if [ -n "$found_arn" ]; then
                ACM_CERT_ARN="$found_arn"
                HTTPS_MODE="alb-acm"
                log_success "Using ACM certificate for ${BASE_DOMAIN}: ${ACM_CERT_ARN}"
            else
                HTTPS_MODE="off"
                log_warning "No ACM certificate found for ${BASE_DOMAIN} in ${AWS_REGION}. Proceeding with HTTP only."
            fi
        fi
    else
        log_info "HTTPS mode overridden by flag: ${HTTPS_MODE}"
    fi
    export HTTPS_MODE BASE_DOMAIN HOST_PREFIX ACM_CERT_ARN EXTERNALDNS_IAM_ROLE_ARN
    
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
