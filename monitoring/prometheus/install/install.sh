#!/bin/bash -e

# Unified Prometheus Installation Script
# This script installs the kube-prometheus-stack Helm chart in the monitoring namespace
# It sets up the basic monitoring infrastructure for the workshop environment

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CLUSTER_NAME="${CLUSTER_NAME:-test-cluster}"
VALUES_DIR="${SCRIPT_DIR}/../values"
DASHBOARDS_DIR="${SCRIPT_DIR}/../dashboards"
PROMETHEUS_VERSION="55.5.0"  # kube-prometheus-stack chart version

# Function to print section headers
section() {
  echo -e "\n${GREEN}=== $1 ===${NC}"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
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

# Check for required tools
section "Checking for required tools"
for cmd in kubectl helm jq; do
  if ! command_exists "$cmd"; then
    echo -e "${RED}Error: $cmd is not installed${NC}"
    exit 1
  fi
done

# Check if we can connect to the cluster
section "Checking cluster connectivity"
if ! kubectl get nodes &>/dev/null; then
  echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
  echo "Please ensure you have set the correct kubeconfig and have access to the cluster."
  exit 1
fi

# Create monitoring namespace if it doesn't exist
section "Creating monitoring namespace"
if ! kubectl get namespace monitoring &>/dev/null; then
  echo "Creating monitoring namespace..."
  kubectl create namespace monitoring
else
  echo "Monitoring namespace already exists"
fi

# Add Prometheus Helm repository
section "Adding Prometheus Helm repository"
ensure_helm_repo "prometheus-community" "https://prometheus-community.github.io/helm-charts"

# Create values file directory if it doesn't exist
mkdir -p "${VALUES_DIR}"

# Check if custom values file exists, if not create a default one
CUSTOM_VALUES_FILE="${VALUES_DIR}/prometheus-values.yaml"
if [ ! -f "${CUSTOM_VALUES_FILE}" ]; then
  section "Creating default values file"
  echo "No custom values file found, creating default values file at ${CUSTOM_VALUES_FILE}"
  
  # Check if we can copy from the existing config
  if [ -f "/Users/seanwiley/workshop/config/monitoring/prometheus-operator-values.yaml" ]; then
    cp "/Users/seanwiley/workshop/config/monitoring/prometheus-operator-values.yaml" "${CUSTOM_VALUES_FILE}"
    echo "Copied existing values from config/monitoring/prometheus-operator-values.yaml"
  else
    # Create a basic default values file
    cat > "${CUSTOM_VALUES_FILE}" <<EOF
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelector:
      matchLabels:
        release: prometheus-operator
    additionalScrapeConfigs:
      - job_name: 'kubernetes-cadvisor'
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
          - role: node
        relabel_configs:
          - action: labelmap
            regex: __meta_kubernetes_node_label_(.+)
          - target_label: __address__
            replacement: kubernetes.default.svc:443
          - source_labels: [__meta_kubernetes_node_name]
            regex: (.+)
            target_label: __metrics_path__
            replacement: /api/v1/nodes/\${1}/proxy/metrics/cadvisor
        metric_relabel_configs:
          - source_labels: [container]
            regex: ^$
            action: drop

grafana:
  additionalDataSources:
    - name: webstore-metrics
      type: prometheus
      url: http://otel-demo-prometheus-server.otel-demo:9090
      access: proxy
      isDefault: false

  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'otel-demo'
          orgId: 1
          folder: 'OpenTelemetry Demo'
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/otel-demo

  dashboards:
    default:
      otel-demo:
        # This will mount the dashboards from the demo into Grafana
        configMapRef: otel-demo-dashboards
        enabled: true
EOF
    echo "Created default values file"
  fi
fi

# Install kube-prometheus-stack
section "Installing kube-prometheus-stack"
echo "Installing kube-prometheus-stack with Helm..."
helm upgrade --install prometheus-operator prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version "${PROMETHEUS_VERSION}" \
  --values "${CUSTOM_VALUES_FILE}" \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorSelector.matchLabels.release=prometheus-operator

# Wait for Prometheus to be ready
section "Waiting for Prometheus to be ready"
echo "Waiting for Prometheus deployment to be ready..."
kubectl rollout status deployment/prometheus-operator-kube-p-operator -n monitoring --timeout=300s || true
kubectl rollout status statefulset/prometheus-prometheus-operator-kube-p-prometheus -n monitoring --timeout=300s || true

# Wait for Grafana to be ready
echo "Waiting for Grafana deployment to be ready..."
kubectl rollout status deployment/prometheus-operator-grafana -n monitoring --timeout=300s || true

# Create default ServiceMonitors directory
mkdir -p "${SCRIPT_DIR}/../servicemonitors"

# Check if we have default ServiceMonitors to apply
if [ -d "${SCRIPT_DIR}/../servicemonitors" ] && [ "$(ls -A ${SCRIPT_DIR}/../servicemonitors)" ]; then
  section "Applying default ServiceMonitors"
  for file in "${SCRIPT_DIR}/../servicemonitors"/*.yaml; do
    if [ -f "$file" ]; then
      echo "Applying ServiceMonitor: $file"
      kubectl apply -f "$file"
    fi
  done
fi

# Print success message and access instructions
section "Installation Complete"
echo -e "${GREEN}✅ kube-prometheus-stack has been successfully installed in the monitoring namespace!${NC}"
echo ""
echo "To access Grafana:"
echo "  kubectl port-forward -n monitoring svc/prometheus-operator-grafana 3000:80"
echo "  Then open http://localhost:3000 in your browser"
echo "  Default credentials: admin / prom-operator"
echo ""
echo "To access Prometheus:"
echo "  kubectl port-forward -n monitoring svc/prometheus-operator-kube-p-prometheus 9090:9090"
echo "  Then open http://localhost:9090 in your browser"
echo ""
echo "To access Alertmanager:"
echo "  kubectl port-forward -n monitoring svc/prometheus-operator-kube-p-alertmanager 9093:9093"
echo "  Then open http://localhost:9093 in your browser"
