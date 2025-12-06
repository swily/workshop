#!/bin/bash
#
# Cluster Creation Operation Script
# Creates new EKS cluster with base configuration
#

set -Eeuo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
source "$SCRIPT_DIR/../../lib/ui.sh"
source "$SCRIPT_DIR/../../lib/cluster.sh"

# Default configuration
CLUSTER_NAME=""
AWS_REGION="us-east-2"
NODE_TYPE="m5.large"
NODE_COUNT=3
INSTALL_ISTIO=false
MONITORING_TYPE="grafana"

# Function to show help
show_help() {
    help_header \
        "" \
        "Creates a new EKS cluster with base configuration including:\n- AWS Load Balancer Controller\n- Optional Istio service mesh\n- Monitoring namespace and base components"
    cat << EOF

OPTIONS:
  --cluster-name NAME     Cluster name (required)
  --region REGION         AWS region (default: us-east-2)
  --node-type TYPE        EC2 instance type (default: m5.large)
  --node-count COUNT      Number of nodes (default: 3)
  --install-istio         Install Istio service mesh
  --monitoring TYPE       Monitoring type: grafana|dynatrace|newrelic|none (default: grafana)
  --dry-run               Show what would be done without executing
EOF
    echo ""
    cat << 'EOF'
EXAMPLES:
  ./scripts/operations/cluster_create.sh --cluster-name my-workshop --region us-west-2
  ./scripts/operations/cluster_create.sh --cluster-name test-cluster --install-istio --monitoring dynatrace
  ./scripts/operations/cluster_create.sh --cluster-name demo --node-type m5.xlarge --node-count 5

PREREQUISITES:
  - AWS CLI configured with appropriate permissions
  - eksctl installed
  - kubectl installed
  - helm installed
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
        --node-type)
            NODE_TYPE="$2"
            shift 2
            ;;
        --node-count)
            NODE_COUNT="$2"
            shift 2
            ;;
        --install-istio)
            INSTALL_ISTIO=true
            shift
            ;;
        --monitoring)
            MONITORING_TYPE="$2"
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

# Validate required parameters
if [ -z "$CLUSTER_NAME" ]; then
    log_error "Cluster name is required"
    show_help
    exit 1
fi

# Main execution
main() {
    print_banner
    
    log_info "Creating EKS cluster with configuration:"
    echo "  Name: $CLUSTER_NAME"
    echo "  Region: $AWS_REGION"
    echo "  Node Type: $NODE_TYPE"
    echo "  Node Count: $NODE_COUNT"
    echo "  Install Istio: $INSTALL_ISTIO"
    echo "  Monitoring Type: $MONITORING_TYPE"
    echo ""
    
    # Validate prerequisites
    validate_prerequisites
    check_aws_config
    set_aws_region "$AWS_REGION"
    
    # Create the cluster
    create_cluster "$CLUSTER_NAME" "$AWS_REGION" "$NODE_TYPE" "$NODE_COUNT"
    
    # Configure base components
    configure_cluster_base "$CLUSTER_NAME" "$INSTALL_ISTIO" "$MONITORING_TYPE"
    
    # Display cluster information
    log_section "Cluster Information"
    get_cluster_nodes "$CLUSTER_NAME"
    
    log_success "Cluster creation completed successfully!"
    log_info "Next steps:"
    echo "1. Deploy applications: ./scripts/operations/deploy_otel.sh --cluster-name $CLUSTER_NAME"
    echo "2. Install Gremlin: ./scripts/gremlin_install.sh --cluster-name $CLUSTER_NAME"
    echo "3. Setup monitoring: Use the main workshop.sh script"
}

# Run main function
main "$@"
