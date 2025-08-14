#!/bin/bash -e

# Get the directory of the script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# --- Configuration---
DEFAULT_CLUSTER_NAME="current-workshop"
VALUES_FILE="${SCRIPT_DIR}/otel-demo-values.yaml"

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

# Progressive GREMLIN ASCII art
print_gremlin_banner() {
  echo ""
  echo "  ██████╗ ██████╗ ███████╗███╗   ███╗██╗     ██╗███╗   ██╗"
  echo " ██╔════╝ ██╔══██╗██╔════╝████╗ ████║██║     ██║████╗  ██║"
  echo " ██║  ███╗██████╔╝█████╗  ██╔████╔██║██║     ██║██╔██╗ ██║"
  echo " ██║   ██║██╔══██╗██╔══╝  ██║╚██╔╝██║██║     ██║██║╚██╗██║"
  echo " ╚██████╔╝██║  ██║███████╗██║ ╚═╝ ██║███████╗██║██║ ╚████║"
  echo "  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚══════╝╚═╝╚═╝  ╚═══╝"
  echo ""
}

print_gremlin_progress() {
  local current=$1
  local total=$2
  local width=40
  local percentage=$((current * 100 / total))
  local filled=$((current * width / total))
  local empty=$((width - filled))
  
  # Clear the area and move cursor up
  printf "\033[8A\033[J"
  
  # GREMLIN ASCII art lines - each letter appears at different percentages
  local line1="  "
  local line2="  "
  local line3="  "
  local line4="  "
  local line5="  "
  local line6="  "
  
  # G appears at 15%
  if [ $percentage -ge 15 ]; then
    line1+="██████╗ "
    line2+="██╔════╝ "
    line3+="██║  ███╗"
    line4+="██║   ██║"
    line5+="╚██████╔╝"
    line6+=" ╚═════╝ "
  fi
  
  # R appears at 30%
  if [ $percentage -ge 30 ]; then
    line1+="██████╗ "
    line2+="██╔══██╗"
    line3+="██████╔╝"
    line4+="██╔══██╗"
    line5+="██║  ██║"
    line6+="╚═╝  ╚═╝"
  fi
  
  # E appears at 45%
  if [ $percentage -ge 45 ]; then
    line1+="███████╗"
    line2+="██╔════╝"
    line3+="█████╗  "
    line4+="██╔══╝  "
    line5+="███████╗"
    line6+="╚══════╝"
  fi
  
  # M appears at 60%
  if [ $percentage -ge 60 ]; then
    line1+="███╗   ███╗"
    line2+="████╗ ████║"
    line3+="██╔████╔██║"
    line4+="██║╚██╔╝██║"
    line5+="██║ ╚═╝ ██║"
    line6+="╚═╝     ╚═╝"
  fi
  
  # L appears at 75%
  if [ $percentage -ge 75 ]; then
    line1+="██╗     "
    line2+="██║     "
    line3+="██║     "
    line4+="██║     "
    line5+="███████╗"
    line6+="╚══════╝"
  fi
  
  # I appears at 90%
  if [ $percentage -ge 90 ]; then
    line1+="██╗"
    line2+="██║"
    line3+="██║"
    line4+="██║"
    line5+="██║"
    line6+="╚═╝"
  fi
  
  # N appears at 100%
  if [ $percentage -ge 100 ]; then
    line1+="███╗   ██╗"
    line2+="████╗  ██║"
    line3+="██╔██╗ ██║"
    line4+="██║╚██╗██║"
    line5+="██║ ╚████║"
    line6+="╚═╝  ╚═══╝"
  fi
  
  # Print the GREMLIN ASCII art
  echo "$line1"
  echo "$line2"
  echo "$line3"
  echo "$line4"
  echo "$line5"
  echo "$line6"
  echo ""
  
  # Print the progress bar
  printf "["
  printf "%*s" $filled | tr ' ' '█'
  printf "%*s" $empty | tr ' ' '░'
  printf "] %d%%" $percentage
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
  # Create namespace for OpenTelemetry demo
  kubectl create namespace otel-demo 2>/dev/null || true

  # Install silently
  helm upgrade --install otel-demo open-telemetry/opentelemetry-demo \
    --namespace otel-demo \
    --values "${VALUES_FILE}" \
    --timeout 15m0s >/dev/null 2>&1
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

  # Get list of deployments to scale
  for deployment in $(kubectl get deployments -n otel-demo -o jsonpath='{.items[*].metadata.name}'); do
    local exclude=false
    for exclude_svc in $EXCLUDE_SERVICES; do
      if [[ "$deployment" == *"$exclude_svc"* ]]; then
        exclude=true
        break
      fi
    done
    if [[ "$exclude" == "false" ]]; then
      deployments_to_scale+=("$deployment")
    fi
  done

  # Initialize empty GREMLIN area
  echo ""
  echo ""
  echo ""
  echo ""
  echo ""
  echo ""
  echo ""
  echo ""

  # Scale deployments with GREMLIN progress
  local count=0
  local total=${#deployments_to_scale[@]}
  
  for deployment in "${deployments_to_scale[@]}"; do
    kubectl scale deployment "$deployment" -n otel-demo --replicas=1 > /dev/null 2>&1
    count=$((count + 1))
    print_gremlin_progress $count $total
    sleep 0.2
  done
  echo ""
}

show_summary() {
  echo ""
  print_header "🎉 OpenTelemetry Demo Ready"
  echo ""
  echo "To access all services, run the port forward script:"
  echo "  ./helper_scripts/dns/port_forward_services.sh"
  echo ""
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
