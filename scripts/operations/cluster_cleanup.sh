#!/bin/bash
#
# Cluster Cleanup Operation Script
# Safely deletes EKS cluster and associated resources
#

set -e

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
source "$SCRIPT_DIR/../../lib/ui.sh"
source "$SCRIPT_DIR/../../lib/cluster.sh"
source "$SCRIPT_DIR/../../lib/monitoring.sh"

# Default configuration
CLUSTER_NAME=""
AWS_REGION="us-east-2"
FORCE_DELETE=false
CLEANUP_MONITORING=true

# Function to show help
show_help() {
    help_header \
        "" \
        "Safely deletes an EKS cluster and all associated resources including:\n- Load balancers and ingresses\n- Monitoring components\n- IAM roles and policies\n- The EKS cluster itself"
    cat << EOF

OPTIONS:
  --cluster-name NAME     Cluster name to delete (required)
  --region REGION         AWS region (default: us-east-2)
  --force                 Skip confirmation prompts
  --skip-monitoring       Skip monitoring cleanup
  --dry-run               Show what would be done without executing
EOF
    echo ""
    cat << 'EOF'
EXAMPLES:
  ./scripts/operations/cluster_cleanup.sh --cluster-name my-workshop
  ./scripts/operations/cluster_cleanup.sh --cluster-name test-cluster --force --region us-west-2
  ./scripts/operations/cluster_cleanup.sh --cluster-name old-cluster --skip-monitoring

WARNING:
  This operation is irreversible and will permanently delete all cluster resources!
EOF
    help_footer
}

# Parse command line arguments
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
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --skip-monitoring)
            CLEANUP_MONITORING=false
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

# Validate required parameters
if [ -z "$CLUSTER_NAME" ]; then
    log_error "Cluster name is required"
    show_help
    exit 1
fi

# Main execution
main() {
    print_banner
    
    log_warning "CLUSTER DELETION REQUESTED"
    echo "  Cluster: $CLUSTER_NAME"
    echo "  Region: $AWS_REGION"
    echo "  Cleanup Monitoring: $CLEANUP_MONITORING"
    echo ""
    
    # Validate prerequisites
    validate_prerequisites
    check_aws_config
    set_aws_region "$AWS_REGION"
    
    # Validate cluster exists
    if ! validate_cluster_exists "$CLUSTER_NAME" "$AWS_REGION"; then
        log_warning "Cluster does not exist, nothing to cleanup"
        exit 0
    fi
    
    # Update kubeconfig
    update_kubeconfig "$CLUSTER_NAME" "$AWS_REGION"
    
    # Cleanup monitoring if requested
    if [ "$CLEANUP_MONITORING" = "true" ]; then
        cleanup_monitoring "all"
    fi
    
    # Cleanup cluster
    cleanup_cluster "$CLUSTER_NAME" "$AWS_REGION" "$FORCE_DELETE"
    
    log_success "Cluster cleanup completed successfully!"
}

# Run main function
main "$@"
