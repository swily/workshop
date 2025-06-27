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
  
  # Set Istio version
  export ISTIO_VERSION=${ISTIO_VERSION:-1.18.0}

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

# Function to install Gremlin with certificate-based authentication
install_gremlin() {
  echo -e "\n=== Installing Gremlin with certificate-based authentication ==="
  
  # Create gremlin namespace if it doesn't exist
  if ! kubectl get namespace gremlin &>/dev/null; then
    echo "Creating gremlin namespace..."
    kubectl create namespace gremlin
  fi
  
  # Add Gremlin Helm repo if not already added
  ensure_helm_repo "gremlin" "https://helm.gremlin.com"
  
  # Install Gremlin using certificate-based authentication
  echo "Installing Gremlin using certificate-based authentication..."
  helm upgrade --install gremlin gremlin/gremlin \
    --namespace gremlin \
    --set gremlin.teamID=438c58ec-03db-47ac-8c58-ec03db67ac42 \
    --set gremlin.clusterID=istio-otel-demo-cluster \
    --set gremlin.certSecret.create=true \
    --set gremlin.certSecret.teamCertificate="$(cat patches/gremlin-values.yaml | grep -A 10 'teamCertificate:' | tail -n +2 | sed 's/^ *//' | tr -d '\n' | sed 's/-----END CERTIFICATE-----/-----END CERTIFICATE-----\\n/g')" \
    --set gremlin.certSecret.teamPrivateKey="$(cat patches/gremlin-values.yaml | grep -A 10 'teamPrivateKey:' | tail -n +2 | sed 's/^ *//' | tr -d '\n' | sed 's/-----END PRIVATE KEY-----/-----END PRIVATE KEY-----\\n/g')" \
    -f patches/gremlin-values.yaml
  
  # Apply EnvoyFilter for Istio integration
  echo "Applying Gremlin EnvoyFilter for Istio integration..."
  kubectl apply -f patches/gremlin-envoy-filter.yaml
  
  echo -e "\n✅ Gremlin installation completed successfully!"
  echo -e "\nTo verify Gremlin installation, run:"
  echo "kubectl get pods -n gremlin"
  echo -e "\nTo access the Gremlin web UI, run:"
  echo "kubectl port-forward -n gremlin svc/gremlin 8080:80"
  echo -e "\nThen open http://localhost:8080 in your browser"
}

# Show help message
show_help() {
  echo "Usage: $0 [--install-istio] [--install-gremlin]"
  echo ""
  echo "Options:"
  echo "  --install-istio     Install Istio as part of the base configuration"
  echo "  --install-gremlin  Install Gremlin with certificate-based authentication"
  echo ""
  echo "Note: It's recommended to install Istio separately using ./install_istio.sh"
  echo "      for better control over the installation process."
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

  # Create IAM service account
  echo "Creating IAM service account for AWS Load Balancer Controller..."
  eksctl create iamserviceaccount \
    --cluster=${CLUSTER_NAME} \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=${policy_arn} \
    --override-existing-serviceaccounts \
    --approve

  # Add EKS chart repo
  ensure_helm_repo "eks" "https://aws.github.io/eks-charts"

  # Install AWS Load Balancer Controller
  echo "Installing AWS Load Balancer Controller..."
  helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --namespace kube-system \
    --set clusterName=${CLUSTER_NAME} \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region=${AWS_REGION} \
    --set vpcId=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.resourcesVpcConfig.vpcId" --output text)

  echo "✅ AWS Load Balancer Controller installed successfully!"
}

# Function to check if Istio is already installed
is_istio_installed() {
  kubectl get namespaces | grep -q istio-system
  return $?
}

# Function to install Istio
install_istio() {
  echo "=== Installing Istio ==="
  
  # Check if already installed
  if is_istio_installed; then
    echo "Istio is already installed. Skipping installation."
    return 0
  fi

  # Download Istio
  echo "Downloading Istio ${ISTIO_VERSION}..."
  curl -L https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} sh -
  export PATH="$PWD/istio-${ISTIO_VERSION}/bin:$PATH"

  # Install Istio operator
  echo "Installing Istio operator..."
  istioctl operator init

  # Wait for operator to be ready
  echo "Waiting for Istio operator to be ready..."
  kubectl wait --for=condition=ready pod -l name=istio-operator -n istio-operator --timeout=300s

  # Install Istio with demo profile
  echo "Installing Istio with demo profile..."
  kubectl create namespace istio-system
  kubectl apply -f - <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  namespace: istio-system
  name: istio-operator
spec:
  profile: demo
  components:
    egressGateways:
    - name: istio-egressgateway
      enabled: true
    ingressGateways:
    - name: istio-ingressgateway
      enabled: true
  values:
    global:
      proxy:
        autoInject: enabled
      useMCP: false
    gateways:
      istio-ingressgateway:
        type: LoadBalancer
        serviceAnnotations:
          service.beta.kubernetes.io/aws-load-balancer-type: nlb
          service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
          service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
    pilot:
      autoscaleEnabled: true
      autoscaleMin: 1
      autoscaleMax: 3
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
    telemetry:
      enabled: true
      v2:
        enabled: true
        metadataExchange:
          wasmEnabled: false
        prometheus:
          enabled: true
          wasmEnabled: false
        stackdriver:
          configOverride: {}
          enabled: false
          logging: false
          monitoring: false
          topology: false
    meshConfig:
      enableTracing: true
      defaultConfig:
        holdApplicationUntilProxyStarts: true
        proxyMetadata:
          ISTIO_META_DNS_CAPTURE: "true"
          ISTIO_META_DNS_AUTO_ALLOCATE: "true"
EOF

  # Wait for Istio to be ready
  echo "Waiting for Istio to be ready..."
  kubectl wait --for=condition=available deployment/istiod -n istio-system --timeout=300s
  kubectl wait --for=condition=available deployment/istio-ingressgateway -n istio-system --timeout=300s
  kubectl wait --for=condition=available deployment/istio-egressgateway -n istio-system --timeout=300s

  echo "✅ Istio installed successfully!"
}

# Function to tag subnets for AWS Load Balancer Controller
tag_subnets() {
  echo "=== Tagging subnets for AWS Load Balancer Controller ==="
  
  # Get VPC ID
  local vpc_id=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.resourcesVpcConfig.vpcId" --output text)
  
  # Get all subnets
  local subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${vpc_id}" --query 'Subnets[].SubnetId' --output text)
  
  # Tag subnets for internal load balancers
  echo "Tagging subnets for internal load balancers..."
  for subnet in $subnets; do
    aws ec2 create-tags \
      --resources ${subnet} \
      --tags "Key=kubernetes.io/role/internal-elb,Value=1"
  done
  
  # Tag subnets for external load balancers
  echo "Tagging subnets for external load balancers..."
  for subnet in $subnets; do
    aws ec2 create-tags \
      --resources ${subnet} \
      --tags "Key=kubernetes.io/role/elb,Value=1"
  done
  
  echo "✅ Subnets tagged successfully!"
}

# Main execution
main() {
  # Parse command line arguments
  local install_istio_flag=false
  local install_gremlin_flag=false
  
  while [[ $# -gt 0 ]]; do
    case $1 in
      --install-istio)
        install_istio_flag=true
        shift
        ;;
      --install-gremlin)
        install_gremlin_flag=true
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

  # Tag subnets for AWS Load Balancer Controller
  tag_subnets

  # Install Istio if requested
  if [ "$install_istio_flag" = true ]; then
    echo -e "\n=== Installing Istio (as requested) ==="
    install_istio
  else
    echo -e "\nℹ️  Skipping Istio installation. To install Istio, run:"
    echo "   ./install_istio.sh"
    echo "   or rerun this script with: $0 --install-istio"
  fi
  
  # Install Gremlin if requested
  if [ "$install_gremlin_flag" = true ]; then
    if [ "$install_istio_flag" = false ]; then
      echo -e "\n⚠️  Warning: Gremlin installation requires Istio. Please install Istio first."
      echo "You can install Istio by running:"
      echo "  $0 --install-istio --install-gremlin"
      echo -e "\nOr install Istio separately and then run with --install-gremlin"
    else
      install_gremlin
    fi
  fi
  
  echo -e "\n✅ Base cluster configuration completed successfully!"
  
  if [ "$install_gremlin_flag" = false ]; then
    echo -e "\nℹ️  To install Gremlin with certificate-based authentication, run:"
    echo "   $0 --install-istio --install-gremlin"
  fi
  
  if [ "$install_istio_flag" = false ]; then
    echo -e "\nNext steps:"
    echo "1. Install Istio (recommended):"
    echo "   ./install_istio.sh"
    echo ""
    echo "2. Install Gremlin with certificate-based authentication:"
    echo "   $0 --install-gremlin"
    echo ""
    echo "3. Run the OpenTelemetry demo configuration:"
    echo "   ./configure_otel_demo.sh"
  fi
}

# Execute the main function if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
