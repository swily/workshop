#!/bin/bash -e

# Set AWS region
export AWS_DEFAULT_REGION=us-east-2
export AWS_REGION=us-east-2

# Cleanup function to remove temporary files and resources
cleanup() {
  echo "Cleaning up temporary files and resources..."
  
  # Kill any running Kiali port-forward
  if [ -f /tmp/kiali-port-forward.pid ]; then
    echo "Stopping Kiali port-forward..."
    kill $(cat /tmp/kiali-port-forward.pid) 2>/dev/null || true
    rm -f /tmp/kiali-port-forward.pid
  fi
  
  # Remove temporary files
  rm -f /tmp/alb-values.yaml
  rm -f iam-policy.json
  
  # Only remove generated config files if they're not symlinks
  [ ! -L istio-values.yaml ] && rm -f istio-values.yaml 2>/dev/null || true
  [ ! -L kiali-values.yaml ] && rm -f kiali-values.yaml 2>/dev/null || true
  
  # Clean up downloaded Istio files if they exist
  if [ -d "istio-${ISTIO_VERSION:-1.18.0}" ]; then
    echo "Cleaning up Istio download..."
    rm -rf "istio-${ISTIO_VERSION:-1.18.0}"
  fi
}

trap cleanup EXIT

# Check for required tools
check_requirements() {
  echo "Checking for required tools..."
  for tool in aws kubectl eksctl helm istioctl; do
    if ! command -v $tool &> /dev/null; then
      echo "Error: $tool is required but not installed"
      exit 1
    fi
  done
}

# Set default values
set_defaults() {
  if [ -z "${EXPIRATION}" ]; then
    EXPIRATION=$(date -v +7d +%Y-%m-%d)
  fi  

  if [ -z "${OWNER}" ]; then
    OWNER="$(whoami)"
  fi

  if [ -z "${CLUSTER_NAME}" ]; then
    echo "CLUSTER_NAME environment variable must be set"
    exit 1
  fi
}

# Validate cluster access
validate_cluster_access() {
  echo "Validating cluster access..."
  if ! kubectl cluster-info > /dev/null 2>&1; then
    echo "Error: Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
  fi
}

# Update kubeconfig
update_kubeconfig() {
  echo "Updating kubeconfig..."
  if ! eksctl utils write-kubeconfig --cluster ${CLUSTER_NAME}; then
    echo "Error: Failed to update kubeconfig for cluster ${CLUSTER_NAME}"
    exit 1
  fi
}

# Show help message
show_help() {
  echo "Usage: $0 [--install-istio]"
  echo ""
  echo "Options:"
  echo "  --install-istio  Install Istio as part of the base configuration"
  echo ""
  echo "Note: It's recommended to install Istio separately using ./install_istio.sh"
  echo "      for better control over the installation process."
}

# Main execution
main() {
  # Parse command line arguments
  local install_istio_flag=false
  
  while [[ $# -gt 0 ]]; do
    case $1 in
      --install-istio)
        install_istio_flag=true
        shift
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

  echo -e "\n=== Installing AWS Load Balancer Controller ==="
  install_aws_load_balancer_controller

  # Install Istio if requested
  if [ "$install_istio_flag" = true ]; then
    echo -e "\n=== Installing Istio (as requested) ==="
    install_istio
  else
    echo -e "\nℹ️  Skipping Istio installation. To install Istio, run:"
    echo "   ./install_istio.sh"
    echo "   or rerun this script with: $0 --install-istio"
  fi
  
  echo -e "\n✅ Base cluster configuration completed successfully!"
  
  if [ "$install_istio_flag" = false ]; then
    echo -e "\nNext steps:"
    echo "1. Install Istio (recommended):"
    echo "   ./install_istio.sh"
    echo ""
    echo "2. Set your Gremlin credentials as environment variables:"
    echo "   export TEAM_ID=<your-team-id>"
    echo "   export TEAM_SECRET=<your-team-secret>"
    echo ""
    echo "3. Run the OpenTelemetry demo configuration:"
    echo "   ./configure_otel_demo.sh"
  fi
}

# Function to ensure Helm repo is added
ensure_helm_repo() {
  local repo_name=$1
  local repo_url=$2
  
  if ! helm repo list | grep -q "^${repo_name}"; then
    echo "Adding Helm repository ${repo_name}..."
    if ! helm repo add ${repo_name} ${repo_url}; then
      echo "Error: Failed to add Helm repository ${repo_name}"
      return 1
    fi
    helm repo update
  fi
}

# Function to install AWS Load Balancer Controller
install_aws_load_balancer_controller() {
  echo "=== Installing AWS Load Balancer Controller ==="
  
  # Download IAM policy
  echo "Downloading IAM policy..."
  curl -s -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.7/docs/install/iam_policy.json

  # Create IAM policy if it doesn't exist
  echo "Creating IAM policy for AWS Load Balancer Controller..."
  local account_id=$(aws sts get-caller-identity --query Account --output text)
  local policy_arn="arn:aws:iam::${account_id}:policy/AWSLoadBalancerControllerIAMPolicy"
  
  if ! aws iam get-policy --policy-arn $policy_arn >/dev/null 2>&1; then
    aws iam create-policy \
      --policy-name AWSLoadBalancerControllerIAMPolicy \
      --policy-document file://iam-policy.json
  else
    echo "IAM policy already exists, skipping creation"
  fi

  # Get the OIDC provider URL for the cluster
  echo -e "\n=== Configuring IAM OIDC provider ==="
  local oidc_provider=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.identity.oidc.issuer" --output text | sed -e 's/^https:\/\///')
  echo "OIDC Provider: $oidc_provider"

  # Create IAM role with trust relationship
  echo -e "\n=== Creating IAM role for AWS Load Balancer Controller ==="
  local role_name="aws-load-balancer-controller-${CLUSTER_NAME}"
  local role_arn="arn:aws:iam::${account_id}:role/${role_name}"

  # Create or update IAM role
  if ! aws iam get-role --role-name $role_name >/dev/null 2>&1; then
    echo "Creating IAM role: $role_name"
    aws iam create-role \
      --role-name $role_name \
      --assume-role-policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Federated\":\"arn:aws:iam::${account_id}:oidc-provider/${oidc_provider}\"},\"Action\":\"sts:AssumeRoleWithWebIdentity\",\"Condition\":{\"StringEquals\":{\"${oidc_provider}:sub\":\"system:serviceaccount:kube-system:aws-load-balancer-controller\",\"${oidc_provider}:aud\":\"sts.amazonaws.com\"}}}]}"
    
    # Attach the policy to the role
    echo "Attaching policy to IAM role..."
    aws iam attach-role-policy \
      --role-name $role_name \
      --policy-arn $policy_arn
  else
    echo "IAM role $role_name already exists, updating trust policy..."
    aws iam update-assume-role-policy \
      --role-name $role_name \
      --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Federated\":\"arn:aws:iam::${account_id}:oidc-provider/${oidc_provider}\"},\"Action\":\"sts:AssumeRoleWithWebIdentity\",\"Condition\":{\"StringEquals\":{\"${oidc_provider}:sub\":\"system:serviceaccount:kube-system:aws-load-balancer-controller\",\"${oidc_provider}:aud\":\"sts.amazonaws.com\"}}}]}"
  fi

  # Create Kubernetes service account
  echo -e "\n=== Creating Kubernetes service account for AWS Load Balancer Controller ==="
  kubectl create serviceaccount -n kube-system aws-load-balancer-controller --dry-run=client -o yaml | kubectl apply -f -
  kubectl annotate serviceaccount -n kube-system aws-load-balancer-controller \
    "eks.amazonaws.com/role-arn=${role_arn}" --overwrite

  # Ensure EKS Helm repository is added
  ensure_helm_repo "eks" "https://aws.github.io/eks-charts"

  # Create values file
  echo -e "\n=== Creating values file for AWS Load Balancer Controller ==="
  cat > /tmp/alb-values.yaml <<- EOM
clusterName: ${CLUSTER_NAME}
region: ${AWS_REGION}

# Disable webhook to avoid cert-manager dependency
enableServiceMutatorWebhook: false
enableServiceMutatorWebhookFailOpen: false

# Service account configuration
serviceAccount:
  create: false  # We create it explicitly above
  name: aws-load-balancer-controller
  annotations:
    eks.amazonaws.com/role-arn: ${role_arn}

# Basic security context settings
securityContext:
  runAsNonRoot: true
  runAsUser: 65534

# Resource limits
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi

# Disable leader election to simplify setup
leaderElection:
  enabled: false

# Disable metrics to reduce resource usage
metrics:
  enabled: false

# Default target type for services
targetType: ip

# Default scheme for LoadBalancers
scheme: internet-facing
EOM

  # Install or upgrade the controller
  echo -e "\n=== Installing/Upgrading AWS Load Balancer Controller ==="
  if ! helm status -n kube-system aws-load-balancer-controller >/dev/null 2>&1; then
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
      -n kube-system \
      -f /tmp/alb-values.yaml \
      --wait \
      --timeout 15m0s \
      --debug
  else
    helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
      -n kube-system \
      -f /tmp/alb-values.yaml \
      --wait \
      --timeout 15m0s \
      --debug
  fi

  # Wait for the controller to be ready
  echo -e "\nWaiting for AWS Load Balancer Controller to be ready..."
  if ! kubectl wait --for=condition=available deployment/aws-load-balancer-controller -n kube-system --timeout=300s; then
    echo -e "\n❌ AWS Load Balancer Controller failed to become available"
    kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=100
    return 1
  fi

  echo -e "\n✅ AWS Load Balancer Controller is running:"
  kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
}

# Function to check if Istio is already installed
is_istio_installed() {
  kubectl get namespace istio-system >/dev/null 2>&1
  return $?
}

# Function to install Istio
install_istio() {
  # Check if Istio is already installed
  if is_istio_installed; then
    echo "✅ Istio is already installed. Skipping installation."
    return 0
  fi
  
  echo -e "\n=== Installing and configuring Istio with monitoring ==="
  echo -e "\n=== Installing and configuring Istio with monitoring ==="
  
  # Download and install specific Istio version (1.18.0) that's compatible with Kubernetes 1.28
  echo "Downloading Istio 1.18.0..."
  ISTIO_VERSION=1.18.0
  ISTIO_ARCH=osx-arm64
  
  # Clean up any existing installation
  rm -rf istio-${ISTIO_VERSION}
  
  # Download and extract Istio
  curl -L https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-${ISTIO_ARCH}.tar.gz | tar xz
  export PATH="$(pwd)/istio-${ISTIO_VERSION}/bin:$PATH"
  
  # Use the template file for Istio configuration
  ISTIO_CONFIG_FILE="$(pwd)/templates/istio/istio-operator.yaml"
  if [ ! -f "$ISTIO_CONFIG_FILE" ]; then
    echo "❌ Error: Istio configuration template not found at $ISTIO_CONFIG_FILE"
    return 1
  fi
  
  # Make a copy we can modify if needed
  cp "$ISTIO_CONFIG_FILE" ./istio-values.yaml

  # Use the template file for Kiali configuration
  KIALI_CONFIG_FILE="$(pwd)/templates/istio/kiali-values.yaml"
  if [ ! -f "$KIALI_CONFIG_FILE" ]; then
    echo "❌ Error: Kiali configuration template not found at $KIALI_CONFIG_FILE"
    return 1
  fi
  
  # Make a copy we can modify if needed
  cp "$KIALI_CONFIG_FILE" ./kiali-values.yaml

  # Install Istio with the custom configuration
  echo "Installing Istio ${ISTIO_VERSION} with monitoring components..."
  
  # First, install the base Istio components
  if ! istioctl install -f istio-values.yaml -y; then
    echo "❌ Failed to install Istio"
    return 1
  fi
  
  # Wait for Istiod to be ready before proceeding with addons
  echo -e "\nWaiting for Istiod to be ready..."
  if ! kubectl wait --for=condition=ready pod -n istio-system -l app=istiod --timeout=300s; then
    echo "❌ Istiod failed to become ready"
    kubectl logs -n istio-system -l app=istiod --tail=100
    return 1
  fi

  # Wait for Istio Ingress Gateway to be ready
  echo -e "\nWaiting for Istio Ingress Gateway to be ready..."
  if ! kubectl wait --for=condition=ready pod -n istio-system -l app=istio-ingressgateway --timeout=300s; then
    echo "⚠️  Istio Ingress Gateway is not ready, but continuing..."
  fi

  # Enable automatic sidecar injection for the default namespace
  echo -e "\nEnabling automatic sidecar injection for default namespace..."
  kubectl create namespace istio-demo || true
  kubectl label namespace istio-demo istio-injection=enabled --overwrite
  
  # Install and configure addons in the correct order
  echo -e "\n=== Installing and configuring addons ==="
  
  # Install addons in the correct order
  echo -e "\n=== Installing Istio Addons ==="
  
  # 1. First install Prometheus (required by Kiali and Jaeger)
  echo -e "\nInstalling Prometheus..."
  kubectl apply -f istio-${ISTIO_VERSION}/samples/addons/prometheus.yaml
  
  # 2. Install Jaeger (tracing)
  echo -e "\nInstalling Jaeger..."
  kubectl apply -f istio-${ISTIO_VERSION}/samples/addons/jaeger.yaml
  
  # 3. Install Kiali (depends on Prometheus and Jaeger)
  echo -e "\nInstalling Kiali..."
  kubectl apply -f istio-${ISTIO_VERSION}/samples/addons/kiali.yaml
  
  # Wait for addons to be ready with timeouts
  echo -e "\nWaiting for addons to be ready..."
  
  # Prometheus
  if ! kubectl wait --for=condition=ready pod -n istio-system -l app=prometheus --timeout=180s; then
    echo "⚠️  Prometheus is taking longer than expected to start..."
  fi
  
  # Jaeger
  if ! kubectl wait --for=condition=ready pod -n istio-system -l app=jaeger --timeout=180s; then
    echo "⚠️  Jaeger is taking longer than expected to start..."
  fi
  
  # Kiali
  if ! kubectl wait --for=condition=ready pod -n istio-system -l app.kubernetes.io/name=kiali --timeout=180s; then
    echo "⚠️  Kiali is taking longer than expected to start..."
  fi
  
  # Don't fail the installation if addons take too long
  echo -e "\n✅ Addons installation completed. Some components may still be initializing."
  
  # 4. Create port-forward for Kiali
  echo -e "\nCreating port-forward for Kiali..."
  kubectl port-forward svc/kiali -n istio-system 20001:20001 > /dev/null 2>&1 &
  KIALI_PID=$!
  
  # Store the PID in a file for later cleanup
  echo $KIALI_PID > /tmp/kiali-port-forward.pid
  
  # 5. Verify all components are running
  echo -e "\nVerifying all Istio components are running..."
  kubectl get pods -n istio-system
  
  # 6. Wait for all Istio components to be ready
  echo -e "\nWaiting for all Istio components to be ready..."
  if ! kubectl wait --for=condition=ready pod --all -n istio-system --timeout=300s; then
    echo "❌ Some Istio components failed to become ready"
    kubectl get pods -n istio-system -o wide
    return 1
  fi
  
  echo -e "\n✅ Istio installation completed successfully"
  echo "To access the Kiali dashboard, run: istioctl dashboard kiali"
  echo "To access Prometheus, run: istioctl dashboard prometheus"
  echo "To access Jaeger, run: istioctl dashboard jaeger"
  echo "\nTo access the Kiali UI, run: kubectl port-forward svc/kiali -n istio-system 20001:20001"
  echo "Then open: http://localhost:20001"
}

# Function to tag subnets for AWS Load Balancer Controller
tag_subnets() {
  echo -e "\n=== Tagging subnets for AWS Load Balancer Controller ==="
  echo "This ensures the AWS Load Balancer Controller can properly provision load balancers."

  # Get all subnets in the VPC
  local vpc_id=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.resourcesVpcConfig.vpcId" --output text)
  local subnets=($(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${vpc_id}" --query "Subnets[].SubnetId" --output text))

  # Split subnets into public and private based on MapPublicIpOnLaunch
  local public_subnets=()
  local private_subnets=()

  for subnet in "${subnets[@]}"; do
    if [ "$(aws ec2 describe-subnets --subnet-ids $subnet --query 'Subnets[0].MapPublicIpOnLaunch' --output text)" = "True" ]; then
      public_subnets+=($subnet)
    else
      private_subnets+=($subnet)
    fi
  done

  echo "Found ${#public_subnets[@]} public subnets and ${#private_subnets[@]} private subnets"

  # Tag all subnets with the cluster tag
  echo -e "\nTagging all subnets with cluster tag..."
  for subnet in "${subnets[@]}"; do
    echo "Tagging subnet $subnet with cluster tag"
    aws ec2 create-tags \
      --resources $subnet \
      --tags "Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared"
  done

  # Tag public subnets
  echo -e "\nTagging public subnets for internet-facing load balancers..."
  for subnet in "${public_subnets[@]}"; do
    echo "Tagging public subnet $subnet with elb role"
    aws ec2 create-tags \
      --resources $subnet \
      --tags "Key=kubernetes.io/role/elb,Value=1"
  done

  # Tag private subnets
  echo -e "\nTagging private subnets for internal load balancers..."
  for subnet in "${private_subnets[@]}"; do
    echo "Tagging private subnet $subnet with internal-elb role"
    aws ec2 create-tags \
      --resources $subnet \
      --tags "Key=kubernetes.io/role/internal-elb,Value=1"
  done

  echo -e "\n✅ Subnet tagging completed."
  echo "Public subnets (${#public_subnets[@]}):"
  printf '  %s\n' "${public_subnets[@]}"
  echo -e "\nPrivate subnets (${#private_subnets[@]}):"
  printf '  %s\n' "${private_subnets[@]}"
}

# Execute the main function if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
