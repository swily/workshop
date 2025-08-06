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

# Function to create an ALB/CLB for the OpenTelemetry demo frontend-proxy
create_load_balancer() {
  local lb_type="$1"
  echo "=== Creating ${lb_type} for OpenTelemetry demo ==="
  
  # Create a namespace for the ingress if it doesn't exist
  if ! kubectl get namespace ingress-${CLUSTER_NAME} &>/dev/null; then
    echo "Creating namespace for ingress..."
    kubectl create namespace ingress-${CLUSTER_NAME}
  fi
  
  # Create a temporary ingress manifest file
  local ingress_file="/tmp/otel-demo-ingress.yaml"
  
  # Configure annotations based on load balancer type
  if [ "${lb_type}" = "clb" ]; then
    echo "Configuring Classic Load Balancer (CLB)..."
    cat > ${ingress_file} <<EOL
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: otel-demo-ingress
  namespace: ingress-${CLUSTER_NAME}
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=600
    alb.ingress.kubernetes.io/healthcheck-path: /
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '15'
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '5'
    alb.ingress.kubernetes.io/healthy-threshold-count: '2'
    alb.ingress.kubernetes.io/unhealthy-threshold-count: '2'
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    # Force use of CLB instead of ALB
    service.beta.kubernetes.io/aws-load-balancer-type: "classic"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-proxy
            port:
              number: 8080
EOL
  else
    # Default to ALB
    echo "Configuring Application Load Balancer (ALB)..."
    cat > ${ingress_file} <<EOL
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: otel-demo-ingress
  namespace: ingress-${CLUSTER_NAME}
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=600
    alb.ingress.kubernetes.io/healthcheck-path: /
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '15'
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '5'
    alb.ingress.kubernetes.io/healthy-threshold-count: '2'
    alb.ingress.kubernetes.io/unhealthy-threshold-count: '2'
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/backend-protocol: HTTP
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-proxy
            port:
              number: 8080
EOL
  fi
  
  # Apply the ingress manifest
  echo "Applying ingress manifest..."
  kubectl apply -f ${ingress_file}
  
  # Wait for the ingress to be created
  echo "Waiting for load balancer to be provisioned (this may take a few minutes)..."
  kubectl wait --namespace=ingress-${CLUSTER_NAME} \
    --for=jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
    --timeout=300s \
    ingress/otel-demo-ingress
  
  # Get the load balancer hostname
  local lb_hostname=$(kubectl get ingress -n ingress-${CLUSTER_NAME} otel-demo-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  
  echo "✅ ${lb_type} created successfully!"
  echo "Load balancer hostname: ${lb_hostname}"
  echo "You can access the OpenTelemetry demo at: http://${lb_hostname}/"
  echo "Note: It may take a few minutes for DNS to propagate and the load balancer to become fully available."
  
  # Clean up the temporary file
  rm -f ${ingress_file}
}

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
  echo "Note: This script installs the AWS Load Balancer Controller but does not create any load balancers."
  echo "      Use ../load-balancer/install.sh to create a load balancer for the OpenTelemetry demo."
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

  echo -e "\n=== Installing AWS Load Balancer Controller ==="
  install_aws_load_balancer_controller

  # Tag subnets for AWS Load Balancer Controller
  tag_subnets

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
