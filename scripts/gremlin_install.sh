#!/bin/bash
set -Eeuo pipefail

# Unified Gremlin Installation Script
# Combines functionality from build_scripts/gremlin/install.sh and monitoring/gremlin/install_pni.sh
# Supports both standard Gremlin agent and PNI (Private Network Integration) installation

# Source shared library for logging, dry-run, and helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Default configuration
CLUSTER_NAME=""
AWS_REGION="${AWS_REGION:-us-east-2}"
NAMESPACE="gremlin"
INSTALL_TYPE="standard" # standard, pni, or both
DRY_RUN=false
ISTIO_INTEGRATION=false
AUTO_TAG=true
NAMESPACES_TO_TAG="otel-demo"

# Gremlin credentials - must be provided via environment or CLI
GREMLIN_TEAM_ID="${GREMLIN_TEAM_ID:-}"
GREMLIN_TEAM_SECRET="${GREMLIN_TEAM_SECRET:-}"
GREMLIN_API_KEY="${GREMLIN_API_KEY:-}"
GREMLIN_CLUSTER_ID=""

# Function to print section headers (use common logging style)
section() {
  log_section "$1"
}

# Show help information
show_help() {
  echo ""
  echo "Unified script to install Gremlin chaos engineering platform on EKS clusters."
  echo "Supports both standard Gremlin agent and Private Network Integration (PNI)."
  echo ""
  cat << EOF

OPTIONS:
  -n, --cluster-name NAME     Specify the cluster name to configure
  -t, --type TYPE             Installation type: standard, pni, or both (default: standard)
  --use-pni                   Convenience flag: always install standard agent and add PNI (same as --type both)
  --namespace NS              Target namespace (default: gremlin)
  --team-id ID                Specify the Gremlin team ID
  --team-secret SECRET        Specify the Gremlin team secret
  --api-key KEY               Specify the Gremlin API key (for PNI)
  --cluster-id ID             Specify a custom Gremlin cluster ID (defaults to cluster name)
  -i, --istio                 Enable Istio integration for Gremlin
  --disable-auto-tag          Disable automatic service tagging (enabled by default)
  --auto-tag-namespace NS     Override default namespace for auto-tagging (default: otel-demo)
  --dry-run                   Show what would be installed without actually installing
EOF
  echo ""
  cat << 'EOF'
EXAMPLES:
  ./scripts/gremlin_install.sh -n my-cluster                           # Install with auto-tag enabled (default)
  ./scripts/gremlin_install.sh -n my-cluster --disable-auto-tag        # Install without auto-tagging
  ./scripts/gremlin_install.sh -n my-cluster -t pni                    # Install PNI agent only
  ./scripts/gremlin_install.sh -n my-cluster -t both                   # Install both standard and PNI
  ./scripts/gremlin_install.sh -n my-cluster --auto-tag-namespace "my-ns" # Auto-tag custom namespace
  ./scripts/gremlin_install.sh --dry-run                               # Preview installation commands

WHAT THIS INSTALLS:
  Standard: Gremlin chaos engineering agent for running experiments
  PNI:      Private Network Integration for internal cluster health checks
  Both:     Complete Gremlin setup with all capabilities

PREREQUISITES:
  - AWS CLI configured with cluster access
  - kubectl configured for target cluster
  - Helm 3.x installed
  - Cluster admin permissions
EOF
  echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--cluster-name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    -t|--type)
      INSTALL_TYPE="$2"
      if [[ ! "$INSTALL_TYPE" =~ ^(standard|pni|both)$ ]]; then
        echo -e "${RED}❌ Invalid install type: $INSTALL_TYPE. Must be: standard, pni, or both${NC}"
        exit 1
      fi
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --team-id)
      GREMLIN_TEAM_ID="$2"
      shift 2
      ;;
    --team-secret)
      GREMLIN_TEAM_SECRET="$2"
      shift 2
      ;;
    --api-key)
      GREMLIN_API_KEY="$2"
      shift 2
      ;;
    --use-pni)
      # Always install standard + PNI
      INSTALL_TYPE="both"
      shift
      ;;
    --cluster-id)
      GREMLIN_CLUSTER_ID="$2"
      shift 2
      ;;
    -i|--istio)
      ISTIO_INTEGRATION=true
      shift
      ;;
    --disable-auto-tag)
      AUTO_TAG=false
      shift
      ;;
    --auto-tag-namespace)
      NAMESPACES_TO_TAG="$2"
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
      echo -e "${RED}❌ Unknown parameter: $1${NC}"
      show_help
      exit 1
      ;;
  esac
done

# Set default cluster name if not provided
if [ -z "${CLUSTER_NAME}" ]; then
  CLUSTER_NAME="current-workshop"
  echo -e "${YELLOW}⚠️  CLUSTER_NAME not set, using default: ${CLUSTER_NAME}${NC}"
fi

# Set default cluster ID if not provided
if [ -z "${GREMLIN_CLUSTER_ID}" ]; then
  GREMLIN_CLUSTER_ID="${CLUSTER_NAME}"
fi

# Function to check prerequisites
check_prerequisites() {
  section "Checking Prerequisites"
  
  local missing_tools=()
  
  # Check required tools
  command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
  command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
  command -v aws >/dev/null 2>&1 || missing_tools+=("aws")
  
  if [ ${#missing_tools[@]} -ne 0 ]; then
    echo -e "${RED}❌ Missing required tools: ${missing_tools[*]}${NC}"
    echo -e "${YELLOW}Please install the missing tools and try again.${NC}"
    exit 1
  fi
  
  # Check if kubectl can connect to cluster
  if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ kubectl cannot connect to cluster${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}✅ All prerequisites met${NC}"
  echo "Current cluster: $(kubectl config current-context)"
  echo "Target namespace: $NAMESPACE"
  echo "Install type: $INSTALL_TYPE"
}

# Note: Do not redefine helpers from lib/common.sh to avoid recursion.

# Function to install standard Gremlin agent
install_standard_gremlin() {
  section "Installing Standard Gremlin Agent"
  
  if is_dry_run; then
    log_warning "[DRY RUN] Would install standard Gremlin agent"
    log_warning "[DRY RUN] Team ID: $GREMLIN_TEAM_ID"
    log_warning "[DRY RUN] Cluster ID: $GREMLIN_CLUSTER_ID"
    return 0
  fi
  
  # Ensure namespace exists
  ensure_namespace "$NAMESPACE"
  
  # Add Gremlin Helm repo
  ensure_helm_repo "gremlin" "https://helm.gremlin.com"
  
  # Install/upgrade Gremlin using Helm with managed secret (Option A)
  log_info "Installing Gremlin agent with Helm-managed secret (Option A)..."
  execute_command "helm upgrade --install gremlin gremlin/gremlin \
    --namespace '$NAMESPACE' \
    --set gremlin.teamID='$GREMLIN_TEAM_ID' \
    --set gremlin.clusterID='$GREMLIN_CLUSTER_ID' \
    --set gremlin.secret.managed=true \
    --set gremlin.secret.type=secret \
    --set gremlin.secret.teamID='$GREMLIN_TEAM_ID' \
    --set gremlin.secret.teamSecret='$GREMLIN_TEAM_SECRET' \
    --set chao.create=true \
    --set gremlin.features.discoverDestinationService.enabled=true"
  
  log_success "Standard Gremlin agent installed successfully"
}

# Function to install PNI agent
install_pni_agent() {
  section "Installing Gremlin PNI Agent"
  
  local helm_command="helm upgrade --install gremlin-integrations gremlin/gremlin-integrations \\
  --namespace '$NAMESPACE' \\
  --create-namespace \\
  --set gremlin.secret.teamID='$GREMLIN_TEAM_ID' \\
  --set gremlin.secret.teamSecret='$GREMLIN_TEAM_SECRET' \\
  --set gremlin.secret.clusterID='$GREMLIN_CLUSTER_ID'"
  
  if is_dry_run; then
    log_warning "[DRY RUN] Would run: $helm_command"
    return 0
  fi
  
  # Ensure namespace exists
  ensure_namespace
  
  # Add Gremlin Helm repo
  ensure_helm_repo "gremlin" "https://helm.gremlin.com"
  
  log_info "Installing Gremlin PNI agent..."
  if execute_command "$helm_command"; then
    log_success "PNI agent installed successfully"
  else
    log_error "Failed to install PNI agent"
    exit 1
  fi
}

# Function to apply Istio integration
apply_istio_integration() {
  section "Applying Istio Integration"
  
  if is_dry_run; then
    log_warning "[DRY RUN] Would apply Istio integration"
    return 0
  fi
  
  # Check if Istio is installed
  if kubectl get namespaces | grep -q istio-system; then
    echo -e "${YELLOW}⚠️  Istio detected but EnvoyFilter integration not yet implemented${NC}"
    echo "   Gremlin will work without Istio integration"
  else
    echo -e "${YELLOW}⚠️  Warning: Istio namespace (istio-system) not found.${NC}"
    echo "Istio integration was requested but Istio is not installed."
  fi
}


# Function to verify installation
verify_installation() {
  if is_dry_run; then
    log_warning "[DRY RUN] Would verify installation"
    return 0
  fi
  
  section "Verifying Installation"
  
  # Check standard Gremlin agent
  if [[ "$INSTALL_TYPE" == "standard" || "$INSTALL_TYPE" == "both" ]]; then
    echo "Checking Gremlin agent pods..."
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=gremlin
  fi
  
  # Check PNI agent
  if [[ "$INSTALL_TYPE" == "pni" || "$INSTALL_TYPE" == "both" ]]; then
    echo "Checking PNI agent pods..."
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=gremlin-integrations
  fi
  
  echo ""
  echo "All services in namespace $NAMESPACE:"
  kubectl get svc -n "$NAMESPACE"
}

# Function to show next steps
show_next_steps() {
  section "Next Steps"
  
  echo -e "${GREEN}🎉 Gremlin installation complete!${NC}"
  echo ""
  
  if [[ "$INSTALL_TYPE" == "standard" || "$INSTALL_TYPE" == "both" ]]; then
    echo "Standard Gremlin Agent:"
    echo "- Visit https://app.gremlin.com to create and run chaos experiments"
    echo "- Use the Gremlin CLI or web UI to target your cluster: $GREMLIN_CLUSTER_ID"
    echo ""
  fi
  
  if [[ "$INSTALL_TYPE" == "pni" || "$INSTALL_TYPE" == "both" ]]; then
    echo "Private Network Integration (PNI):"
    echo "1. Create Prometheus authentication in Gremlin UI:"
    echo "   - Go to: https://app.gremlin.com/health-checks/list"
    echo "   - Click '+ Health Check' → Select 'Prometheus'"
    echo "   - Under Authentication:"
    echo "     * Name: 'Prometheus Cluster Auth'"
    echo "     * ✅ Enable 'Private Network Integration'"
    echo "     * Base URL: http://prometheus.monitoring.svc.cluster.local:9090"
    echo "   - Click 'Save Authentication' and note the Authentication ID"
    echo ""
    echo "2. Create health checks with the authentication ID"
    echo "3. Verify PNI connectivity in Gremlin UI under Integrations → Private Network"
    echo ""
  fi
  
  if [ "$AUTO_TAG" = true ]; then
    echo "Service Discovery:"
    echo "- Services in namespaces [$NAMESPACES_TO_TAG] have been tagged for Gremlin"
    echo "- These services will appear in the Gremlin UI for targeted experiments"
    echo ""
  fi
}

# Main execution function
main() {
  echo -e "${BLUE}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                                                              ║"
  echo "║           🚀 Unified Gremlin Installation Script            ║"
  echo "║                                                              ║"
  echo "║         Chaos Engineering & Health Check Platform           ║"
  echo "║                                                              ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  
  # Update kubeconfig if not dry run
  if ! is_dry_run; then
    log_info "Updating kubeconfig for cluster: $CLUSTER_NAME"
    execute_command "aws eks update-kubeconfig --name '$CLUSTER_NAME' --region '$AWS_REGION'"
  fi
  
  # Run installation steps
  check_prerequisites
  
  # Install based on type
  case "$INSTALL_TYPE" in
    "standard")
      install_standard_gremlin
      ;;
    "pni")
      install_pni_agent
      ;;
    "both")
      install_standard_gremlin
      install_pni_agent
      ;;
  esac
  
  # Apply optional features
  if [ "$ISTIO_INTEGRATION" = true ]; then
    apply_istio_integration
  fi
  
  verify_installation
  show_next_steps
  
  echo -e "\n${GREEN}🚀 Installation complete!${NC}"
}

# Run main function
main "$@"
