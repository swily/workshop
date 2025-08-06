#!/bin/bash -e

# Unified New Relic Installation Script
# This script installs the New Relic bundle in the newrelic namespace
# It integrates with the monitoring framework for the workshop environment

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-seanwiley-otel}"
NEW_RELIC_LICENSE_KEY="${NEW_RELIC_LICENSE_KEY:-}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VALUES_DIR="${SCRIPT_DIR}/../values"

# Function to print section headers
section() {
  echo -e "\n${GREEN}=== $1 ===${NC}"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to prompt for license key if not provided
prompt_for_license_key() {
  if [ -z "$NEW_RELIC_LICENSE_KEY" ]; then
    echo -e "${YELLOW}New Relic License Key not provided.${NC}"
    echo -e "${YELLOW}Please enter your New Relic License Key:${NC}"
    read -r NEW_RELIC_LICENSE_KEY
    if [ -z "$NEW_RELIC_LICENSE_KEY" ]; then
      echo -e "${RED}Error: New Relic License Key is required${NC}"
      exit 1
    fi
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

# Prompt for license key
prompt_for_license_key

# Check if Prometheus is installed
section "Checking if Prometheus is installed"
if ! kubectl get namespace monitoring &>/dev/null || ! kubectl get deployment -n monitoring prometheus-operator-kube-p-operator &>/dev/null; then
  echo -e "${YELLOW}Prometheus is not installed or not found in the monitoring namespace.${NC}"
  echo -e "${YELLOW}It is recommended to install Prometheus first for complete monitoring.${NC}"
  echo -e "${YELLOW}Would you like to install Prometheus now? (y/n)${NC}"
  read -r response
  if [[ "$response" == "y" || "$response" == "Y" ]]; then
    echo "Installing Prometheus..."
    "${SCRIPT_DIR}/../../prometheus/install/install.sh"
  else
    echo -e "${YELLOW}Continuing without Prometheus...${NC}"
  fi
fi

# Create namespace if it doesn't exist
section "Creating New Relic namespace"
kubectl create namespace newrelic --dry-run=client -o yaml | kubectl apply -f -

# Add New Relic Helm repository
section "Adding New Relic Helm repository"
helm repo add newrelic https://helm-charts.newrelic.com
helm repo update newrelic

# Create values directory if it doesn't exist
mkdir -p "${VALUES_DIR}"

# Check if custom values file exists, if not create a default one
CUSTOM_VALUES_FILE="${VALUES_DIR}/newrelic-values.yaml"
if [ ! -f "${CUSTOM_VALUES_FILE}" ]; then
  section "Creating default values file"
  echo "No custom values file found, creating default values file at ${CUSTOM_VALUES_FILE}"
  
  # Create a basic default values file
  cat > "${CUSTOM_VALUES_FILE}" <<EOF
global:
  licenseKey: "${NEW_RELIC_LICENSE_KEY}"
  cluster: "${CLUSTER_NAME}"
  lowDataMode: false

nri-metadata-injection:
  enabled: true

newrelic-infrastructure:
  enabled: true
  privileged: true
  kubelet:
    enabled: true
  kubeStateMetrics:
    enabled: true
  prometheus:
    enabled: true
    configMap:
      create: true
  integrations:
    nri-kube-events:
      enabled: true
    nri-prometheus:
      enabled: true
      config:
        kubernetes:
          integrations_filter:
            enabled: true

nri-prometheus:
  enabled: true
  config:
    kubernetes:
      integrations_filter:
        enabled: true

newrelic-logging:
  enabled: true
  fluentBit:
    config:
      outputs: |
        [OUTPUT]
            Name  newrelic
            Match *
    containers:
      enable: true

kube-state-metrics:
  enabled: true

prometheus-node-exporter:
  enabled: true

newrelic-pixie:
  enabled: false

pixie-chart:
  enabled: false

newrelic-k8s-metrics-adapter:
  enabled: false
EOF
  echo "Created default values file"
fi

# Install New Relic bundle
section "Installing New Relic bundle"
helm upgrade --install newrelic-bundle newrelic/nri-bundle \
  --namespace newrelic \
  --values "${CUSTOM_VALUES_FILE}" \
  --set global.licenseKey="${NEW_RELIC_LICENSE_KEY}" \
  --set global.cluster="${CLUSTER_NAME}" \
  --wait

# Create ServiceMonitors if Prometheus is installed
if kubectl get namespace monitoring &>/dev/null && kubectl get deployment -n monitoring prometheus-operator-kube-p-operator &>/dev/null; then
  section "Creating ServiceMonitors for New Relic"
  
  # Create ServiceMonitors directory if it doesn't exist
  mkdir -p "${SCRIPT_DIR}/../servicemonitors"
  
  # Create a ServiceMonitor for New Relic
  cat > "${SCRIPT_DIR}/../servicemonitors/newrelic-servicemonitor.yaml" <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: newrelic
  namespace: monitoring
  labels:
    release: prometheus-operator
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: newrelic-bundle
  namespaceSelector:
    matchNames:
      - newrelic
  endpoints:
    - port: metrics
      interval: 30s
EOF

  # Apply the ServiceMonitor
  kubectl apply -f "${SCRIPT_DIR}/../servicemonitors/newrelic-servicemonitor.yaml"
  echo -e "${GREEN}✅ ServiceMonitor for New Relic created${NC}"
fi

# Verify New Relic installation
section "Verifying New Relic installation"
echo -e "${YELLOW}Waiting for New Relic pods to be ready...${NC}"
sleep 30

# Check if New Relic pods are running
if kubectl get pods -n newrelic | grep -q 'Running'; then
  echo -e "${GREEN}✅ New Relic is running${NC}"
  kubectl get pods -n newrelic
  echo -e "${GREEN}📊 View your cluster in New Relic: https://one.newrelic.com/launcher/infra.launcher${NC}"
  echo -e "${GREEN}   Cluster Name: ${CLUSTER_NAME}${NC}"
else
  echo -e "${RED}❌ New Relic installation may have issues. Check logs with:${NC}"
  echo "kubectl logs -n newrelic -l app.kubernetes.io/name=newrelic-bundle"
fi

# Provide instructions for next steps
section "Next Steps"
echo -e "${GREEN}New Relic has been installed in your cluster.${NC}"
echo -e "1. Visit New Relic One to verify the cluster is connected: https://one.newrelic.com"
echo -e "2. Set up dashboards and alerts in New Relic"
echo -e "3. Configure OpenTelemetry to send data to New Relic"

echo -e "\n${GREEN}New Relic installation completed${NC}"
exit 0
