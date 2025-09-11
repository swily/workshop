#!/bin/bash -e
#
# base_setup.sh
#
# This script configures the EKS cluster with necessary components
# like the AWS Load Balancer Controller, Istio, and monitoring.

# Note: Prometheus installation is now handled by the unified monitoring setup script
# See /monitoring/setup_monitoring.sh and /monitoring/prometheus/install/install.sh

# Note: New Relic installation is now handled by the unified monitoring setup script
# See /monitoring/setup_monitoring.sh and /monitoring/newrelic/install/install.sh

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check requirements
check_requirements() {
    echo "Checking for required tools..."
    local missing_tools=()
    
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    command -v aws >/dev/null 2>&1 || missing_tools+=("aws")
    command -v eksctl >/dev/null 2>&1 || missing_tools+=("eksctl")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${RED}❌ Missing required tools: ${missing_tools[*]}${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ All required tools found${NC}"
}

# Function to update kubeconfig
update_kubeconfig() {
    echo "Updating kubeconfig for cluster: ${CLUSTER_NAME}"
    aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
}

# Function to validate cluster access
validate_cluster_access() {
    echo "Validating cluster access..."
    if ! kubectl get nodes >/dev/null 2>&1; then
        echo -e "${RED}❌ Cannot access cluster ${CLUSTER_NAME}${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Cluster access validated${NC}"
}

# Function to tag subnets for ALB
tag_subnets() {
    echo "Tagging subnets for AWS Load Balancer Controller..."
    
    # Get VPC ID from cluster
    local vpc_id=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query 'cluster.resourcesVpcConfig.vpcId' --output text)
    
    if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]; then
        echo -e "${RED}❌ Failed to get VPC ID for cluster ${CLUSTER_NAME}${NC}"
        return 1
    fi
    
    echo "Working with VPC: $vpc_id for cluster: ${CLUSTER_NAME}"
    
    # Get all subnets in the VPC
    local all_subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${vpc_id}" \
        --query 'Subnets[*].SubnetId' --output text)
    
    if [[ -z "$all_subnets" ]]; then
        echo -e "${RED}❌ No subnets found in VPC ${vpc_id}${NC}"
        return 1
    fi
    
    # Remove old cluster tags from all subnets to prevent conflicts
    echo "Cleaning up old cluster tags..."
    for subnet in $all_subnets; do
        # Get existing cluster tags
        local existing_tags=$(aws ec2 describe-tags \
            --filters "Name=resource-id,Values=${subnet}" "Name=key,Values=kubernetes.io/cluster/*" \
            --query 'Tags[*].Key' --output text)
        
        # Delete old cluster tags
        for tag_key in $existing_tags; do
            if [[ "$tag_key" != "kubernetes.io/cluster/${CLUSTER_NAME}" ]]; then
                echo "Removing old tag: $tag_key from subnet $subnet"
                aws ec2 delete-tags --resources "$subnet" --tags Key="$tag_key" 2>/dev/null || true
            fi
        done
    done
    
    # Tag all subnets with current cluster ownership
    echo "Tagging subnets for cluster: ${CLUSTER_NAME}"
    for subnet in $all_subnets; do
        aws ec2 create-tags --resources "$subnet" --tags Key="kubernetes.io/cluster/${CLUSTER_NAME}",Value=shared
    done
    
    # Tag public subnets for external load balancers
    local public_subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${vpc_id}" "Name=map-public-ip-on-launch,Values=true" \
        --query 'Subnets[*].SubnetId' --output text)
    
    echo "Tagging $(echo $public_subnets | wc -w) public subnets for external ALB..."
    for subnet in $public_subnets; do
        aws ec2 create-tags --resources "$subnet" --tags Key=kubernetes.io/role/elb,Value=1
    done
    
    # Tag private subnets for internal load balancers
    local private_subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${vpc_id}" "Name=map-public-ip-on-launch,Values=false" \
        --query 'Subnets[*].SubnetId' --output text)
    
    echo "Tagging $(echo $private_subnets | wc -w) private subnets for internal ALB..."
    for subnet in $private_subnets; do
        aws ec2 create-tags --resources "$subnet" --tags Key=kubernetes.io/role/internal-elb,Value=1
    done
    
    echo -e "${GREEN}✅ Subnets tagged successfully for cluster: ${CLUSTER_NAME}${NC}"
}

# Function to install Istio
install_istio() {
    echo "Installing Istio..."
    
    # Check if istioctl is available
    if ! command -v istioctl >/dev/null 2>&1; then
        echo -e "${RED}❌ istioctl not found. Please install Istio CLI first.${NC}"
        return 1
    fi
    
    # Install Istio
    istioctl install --set values.defaultRevision=default -y
    
    # Label default namespace for injection
    kubectl label namespace default istio-injection=enabled --overwrite
    
    echo -e "${GREEN}✅ Istio installed successfully${NC}"
}

# Note: ALB creation is now handled by the enhanced Helm configuration
# See otel-demo-values-enhanced.yaml for ingress configuration

# Show help information
show_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -n, --cluster-name NAME  Specify the cluster name (default: current-workshop)"
  echo "  -i, --install-istio      Install Istio service mesh"
  echo "  -m, --monitoring TYPE    Specify monitoring type: prometheus, newrelic, or none"
  echo "  -h, --help                Show this help message"
  echo ""
  echo "Note: This script tags subnets for ALB support. ALB creation is handled by:"
  echo "      1. Enhanced Helm config (otel-demo-values-enhanced.yaml) - Recommended"
  echo "      2. Manual override (../load-balancer/install.sh) - Fallback only"
  echo "      Default monitoring is 'prometheus' if not specified."
}

# Function to ensure Helm repo is added
ensure_helm_repo() {
  local repo_name="$1"
  local repo_url="$2"
  
  echo "Ensuring Helm repo ${repo_name} is added..."
  if ! helm repo list | grep -q "^${repo_name}"; then
    echo "Adding Helm repo ${repo_name}..."
    helm repo add "${repo_name}" "${repo_url}"
  else
    echo "Helm repo ${repo_name} already exists, updating..."
    helm repo update "${repo_name}"
  fi
}

# Main execution
main() {
  # Parse command line arguments
  local install_istio_flag=false
  local monitoring_type="prometheus" # Default to Prometheus
  
  while [[ $# -gt 0 ]]; do
    case $1 in
      -n|--cluster-name)
        export CLUSTER_NAME="$2"
        shift 2
        ;;
      -i|--install-istio)
        install_istio_flag=true
        shift
        ;;
      -m|--monitoring)
        if [[ "$2" == "prometheus" || "$2" == "newrelic" || "$2" == "none" ]]; then
          monitoring_type="$2"
          shift 2
        else
          echo "Error: Monitoring type must be 'prometheus', 'newrelic', or 'none'"
          show_help
          exit 1
        fi
        ;;
      --help | -h)
        show_help
        exit 0
        ;;
      *)
        echo "Error: Unknown parameter: $1"
        show_help
        exit 1
        ;;
    esac
  done

  # Check if running on macOS
  if [[ "$(uname)" != "Darwin" ]]; then
    echo "This script is intended to run on macOS. Exiting..."
    exit 1
  fi

  echo "=== Starting cluster configuration ==="
  
  # Check for required tools
  check_requirements

  # Set AWS region
  export AWS_REGION="${AWS_REGION:=us-east-2}"
  export AWS_DEFAULT_REGION=$AWS_REGION
  echo "Using AWS Region: $AWS_REGION"

  # Update kubeconfig
  update_kubeconfig

  # Validate cluster access
  validate_cluster_access

  # Tag subnets for AWS Load Balancer Controller
  tag_subnets
  
  # Note: AWS Load Balancer Controller installation is handled by monitoring setup

  # Note: Load balancer creation has been moved to a separate script

  # Install Istio if requested
  if [ "$install_istio_flag" = true ]; then
    echo -e "\n=== Installing Istio (as requested) ==="
    install_istio
  fi
  
  # Install monitoring stack if requested
  if [ "$monitoring_type" != "none" ]; then
    echo -e "\n=== Installing monitoring stack: $monitoring_type ==="
    
    # Check if the unified monitoring script exists
    MONITORING_SCRIPT="${SCRIPT_DIR}/../../monitoring/setup_monitoring.sh"
    if [ ! -f "$MONITORING_SCRIPT" ]; then
      echo -e "\n❌ Error: Unified monitoring script not found at $MONITORING_SCRIPT"
      echo "Please ensure the monitoring framework is properly installed."
      exit 1
    fi
    
    # Export cluster name for the monitoring script
    export CLUSTER_NAME
    
    # Run the appropriate monitoring installation based on the selected type
    case "$monitoring_type" in
      prometheus)
        echo "Installing Prometheus using unified monitoring framework..."
        bash "$MONITORING_SCRIPT" --prometheus-only
        ;;
      newrelic)
        echo "Installing Prometheus and New Relic using unified monitoring framework..."
        bash "$MONITORING_SCRIPT" --newrelic
        ;;
      *)
        echo "Skipping monitoring installation"
        ;;
    esac
  else
    echo -e "\nℹ️  Skipping monitoring installation as requested."
  fi
  
  # Show next steps based on what was installed
  echo -e "\n✅ Base cluster configuration completed successfully!"
  
  if [ "$install_istio_flag" = false ]; then
    echo -e "\nTo install Istio service mesh (optional):"
    echo "   $0 -i -n ${CLUSTER_NAME}"
  fi
}

# Execute the main function if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
