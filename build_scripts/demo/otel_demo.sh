#!/bin/bash -e

# Get the directory of the script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# --- Configuration---
DEFAULT_CLUSTER_NAME="current-workshop"
VALUES_FILE="${SCRIPT_DIR}/otel-demo-values-enhanced.yaml"

# --- Helper Functions ---

# ASCII Art and Headers
print_header() {
  echo ""
  echo "================================================================================" 
  echo "$1"
  echo "================================================================================" 
}

print_otel_demo_banner() {
  echo ""
  echo " ██████╗ ████████╗███████╗██╗         ██████╗ ███████╗███╗   ███╗ ██████╗"
  echo "██╔═══██╗╚══██╔══╝██╔════╝██║         ██╔══██╗██╔════╝████╗ ████║██╔═══██╗"
  echo "██║   ██║   ██║   █████╗  ██║         ██║  ██║█████╗  ██╔████╔██║██║   ██║"
  echo "██║   ██║   ██║   ██╔══╝  ██║         ██║  ██║██╔══╝  ██║╚██╔╝██║██║   ██║"
  echo "╚██████╔╝   ██║   ███████╗███████╗    ██████╔╝███████╗██║ ╚═╝ ██║╚██████╔╝"
  echo " ╚═════╝    ╚═╝   ╚══════╝╚══════╝    ╚═════╝ ╚══════╝╚═╝     ╚═╝ ╚═════╝"
  echo ""
}


print_gremlin_progress() {
  local current=$1
  local total=$2
  local width=40
  local percentage=$((current * 100 / total))
  local filled=$((current * width / total))
  local empty=$((width - filled))
  
  # Colors for progression (grey to green)
  local GREY='\033[0;37m'
  local GREEN='\033[0;32m'
  local NC='\033[0m'
  
  # Use grey until 100%, then green
  local color=$GREY
  if [ $percentage -ge 100 ]; then
    color=$GREEN
  fi
  
  # Only show progress bar during scaling, ASCII art comes at the end
  printf "\r["
  printf "%*s" $filled | tr ' ' '#'
  printf "%*s" $empty | tr ' ' '-'
  printf "] %d%% (%d/%d)" $percentage $current $total
}

show_otel_demo_ascii_art() {
  local GREEN='\033[0;32m'
  local NC='\033[0m'
  
  echo ""
  echo ""
  echo -e "${GREEN} ██████╗ ████████╗███████╗██╗         ██████╗ ███████╗███╗   ███╗ ██████╗${NC}"
  echo -e "${GREEN}██╔═══██╗╚══██╔══╝██╔════╝██║         ██╔══██╗██╔════╝████╗ ████║██╔═══██╗${NC}"
  echo -e "${GREEN}██║   ██║   ██║   █████╗  ██║         ██║  ██║█████╗  ██╔████╔██║██║   ██║${NC}"
  echo -e "${GREEN}██║   ██║   ██║   ██╔══╝  ██║         ██║  ██║██╔══╝  ██║╚██╔╝██║██║   ██║${NC}"
  echo -e "${GREEN}╚██████╔╝   ██║   ███████╗███████╗    ██████╔╝███████╗██║ ╚═╝ ██║╚██████╔╝${NC}"
  echo -e "${GREEN} ╚═════╝    ╚═╝   ╚══════╝╚══════╝    ╚═════╝ ╚══════╝╚═╝     ╚═╝ ╚═════╝${NC}"
  echo ""
  echo -e "${GREEN}         OpenTelemetry Demo Services Ready!${NC}"
  echo ""
}

show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo "Configure OpenTelemetry Demo in the EKS cluster."
  echo ""
  echo "Options:"
  echo "  -n, --cluster-name NAME   Specify the cluster name to configure (default: ${DEFAULT_CLUSTER_NAME})"
  echo "  -h, --help                Show this help message"
}

# --- Main Logic Functions ---

setup_environment() {
  clear
  print_header "Gremlin - OpenTelemetry Deployment"

  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -n|--cluster-name)
        export CLUSTER_NAME="$2"
        shift 2
        ;;
      -h|--help)
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

  # Check if CLUSTER_NAME is set, otherwise detect or ask
  if [ -z "${CLUSTER_NAME}" ]; then
    DETECTED_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
    if [ -n "${DETECTED_CONTEXT}" ]; then
      # Get the full ARN and extract just the cluster name (last part after last slash)
      DETECTED_CLUSTER_ARN=$(kubectl config get-contexts ${DETECTED_CONTEXT} --no-headers | awk '{print $3}')
      DETECTED_CLUSTER=$(echo "${DETECTED_CLUSTER_ARN}" | awk -F'/' '{print $NF}')
      read -p "No cluster name specified. Use current context's cluster '${DETECTED_CLUSTER}'? (y/n): " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        export CLUSTER_NAME="${DETECTED_CLUSTER}"
      fi
    fi

    if [ -z "${CLUSTER_NAME}" ]; then
      read -p "Please enter the cluster name: " CLUSTER_NAME
      export CLUSTER_NAME
    fi

    if [ -z "${CLUSTER_NAME}" ]; then
      echo "Error: No cluster name provided. Exiting."
      exit 1
    fi
  fi

  echo "Using cluster: ${CLUSTER_NAME}"
  sleep 1
  clear
  print_otel_demo_banner
  echo "Deploying OpenTelemetry demo..."
  echo ""
  sleep 1
}

update_helm_repos() {
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1
  helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1
  helm repo update >/dev/null 2>&1
}

check_monitoring() {
  if ! kubectl get namespace monitoring &>/dev/null; then
    echo "⚠️  Warning: Monitoring namespace not found!"
    echo "You can install it by running:"
    echo "  ./configure_cluster_base.sh -n ${CLUSTER_NAME} -m prometheus"
    echo ""
    read -p "Continue without monitoring? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Installation aborted. Please install monitoring first."
      exit 1
    fi
  fi
}

install_otel_demo() {
  echo "Installing OpenTelemetry Demo..."
  
  # Create locust ConfigMap with enhanced locustfile.py and people.json data
  echo "Creating locust configuration..."
  kubectl create configmap locust-config \
    --from-file=locustfile.py="${SCRIPT_DIR}/locustfile.py" \
    --from-file=people.json="/Users/seanwiley/opentelemetry-demo/src/load-generator/people.json" \
    --namespace otel-demo \
    --dry-run=client -o yaml | kubectl apply -f -
  
  # Helm repositories already updated in update_helm_repos()

  # Install the OpenTelemetry demo
  if [ -f "${SCRIPT_DIR}/otel-demo-values-enhanced.yaml" ]; then
    VALUES_FILE="${SCRIPT_DIR}/otel-demo-values-enhanced.yaml"
  else
    echo "Enhanced values file not found. Please ensure otel-demo-values-enhanced.yaml exists."
    exit 1
  fi
  
  if ! helm upgrade --install otel-demo open-telemetry/opentelemetry-demo \
    --namespace otel-demo \
    --values "${VALUES_FILE}" \
    --timeout 15m0s; then
    echo "Failed to install OpenTelemetry demo"
    exit 1
  fi

  echo "OpenTelemetry Demo installed successfully"
  
  # Wait for frontend deployment to be ready
  echo "Waiting for frontend deployment to be ready..."
  kubectl wait --for=condition=available --timeout=300s deployment/frontend -n otel-demo || {
    echo "Frontend deployment failed to become ready"
    kubectl get pods -n otel-demo
    exit 1
  }
  
  # Verify frontend-proxy service exists
  if ! kubectl get service frontend-proxy -n otel-demo >/dev/null 2>&1; then
    echo "Frontend proxy service not found"
    kubectl get services -n otel-demo
    exit 1
  fi
  
  echo "Frontend deployment and services are ready"
  
  # Update load generator for ALB if using enhanced configuration
  if [ "$VALUES_FILE" = "${SCRIPT_DIR}/otel-demo-values-enhanced.yaml" ]; then
    echo "Enhanced configuration detected - updating load generator for ALB integration..."
    if [ -f "${SCRIPT_DIR}/update_loadgen_alb.sh" ]; then
      "${SCRIPT_DIR}/update_loadgen_alb.sh"
    else
      echo "ALB update script not found - load generator will use internal service endpoint"
    fi
  fi
}

configure_servicemonitor() {
  if ! kubectl get crd servicemonitors.monitoring.coreos.com > /dev/null 2>&1; then
    # Prometheus CRDs not found. Skipping ServiceMonitor.
    true
  else
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: otel-collector
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: opentelemetry-collector
  namespaceSelector:
    matchNames:
      - otel-demo
  endpoints:
    - port: prom-metrics
      path: /metrics
      interval: 30s
EOF
  fi
}

scale_deployments() {
  local EXCLUDE_SERVICES="grafana jaeger prometheus opensearch kafka loadgenerator valkey flagd imageprovider otelcol"
  local deployments_to_scale=()

  # Get all deployments in otel-demo namespace
  local all_deployments
  all_deployments=$(kubectl get deployments -n otel-demo -o jsonpath='{.items[*].metadata.name}')

  # Filter out excluded services
  for deployment in $all_deployments; do
    local should_exclude=false
    for exclude in $EXCLUDE_SERVICES; do
      if [[ "$deployment" == *"$exclude"* ]]; then
        should_exclude=true
        break
      fi
    done
    if [ "$should_exclude" = false ]; then
      deployments_to_scale+=("$deployment")
    fi
  done

  echo ""
  echo "Scaling OpenTelemetry Demo services..."
  
  # Scale deployments with simple progress
  local count=0
  local total=${#deployments_to_scale[@]}
  
  for deployment in "${deployments_to_scale[@]}"; do
    kubectl scale deployment "$deployment" -n otel-demo --replicas=1 > /dev/null 2>&1
    count=$((count + 1))
    print_gremlin_progress $count $total
    sleep 0.2
  done
  echo ""
  
  # Show the ASCII art after scaling is complete
  show_otel_demo_ascii_art
}

show_summary() {
  # Summary removed - deployment complete without verbose output
  return 0
}


# --- Main Execution ---

main() {
  setup_environment "$@"
  update_helm_repos
  check_monitoring
  install_otel_demo
  configure_servicemonitor
  scale_deployments
  show_summary
}

main "$@"
