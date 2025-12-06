#!/bin/bash -e

# Unified DataDog Installation Script
# This script installs the DataDog agent in the datadog namespace
# It integrates with the monitoring framework for the workshop environment

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-current-workshop}"
DATADOG_API_KEY="${DATADOG_API_KEY:-}"
DATADOG_APP_KEY="${DATADOG_APP_KEY:-}"

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

# Function to prompt for API key if not provided
prompt_for_api_key() {
  if [ -z "$DATADOG_API_KEY" ]; then
    echo -e "${YELLOW}DataDog API Key not provided.${NC}"
    echo -e "${YELLOW}Please enter your DataDog API Key:${NC}"
    read -r DATADOG_API_KEY
    if [ -z "$DATADOG_API_KEY" ]; then
      echo -e "${RED}Error: DataDog API Key is required${NC}"
      exit 1
    fi
  fi
}

# Function to prompt for APP key if not provided
prompt_for_app_key() {
  if [ -z "$DATADOG_APP_KEY" ]; then
    echo -e "${YELLOW}DataDog APP Key not provided.${NC}"
    echo -e "${YELLOW}Please enter your DataDog APP Key (optional, press Enter to skip):${NC}"
    read -r DATADOG_APP_KEY
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

# Prompt for API key and APP key
prompt_for_api_key
prompt_for_app_key

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
section "Creating DataDog namespace"
kubectl create namespace datadog --dry-run=client -o yaml | kubectl apply -f -

# Add DataDog Helm repository
section "Adding DataDog Helm repository"
helm repo add datadog https://helm.datadoghq.com
helm repo update datadog

# Create values directory if it doesn't exist
mkdir -p "${VALUES_DIR}"

# Check if custom values file exists, if not create a default one
CUSTOM_VALUES_FILE="${VALUES_DIR}/datadog-values.yaml"
if [ ! -f "${CUSTOM_VALUES_FILE}" ]; then
  section "Creating default values file"
  echo "No custom values file found, creating default values file at ${CUSTOM_VALUES_FILE}"
  
  # Create a basic default values file
  cat > "${CUSTOM_VALUES_FILE}" <<EOF
datadog:
  apiKey: "${DATADOG_API_KEY}"
  appKey: "${DATADOG_APP_KEY}"
  clusterName: "${CLUSTER_NAME}"
  logs:
    enabled: true
    containerCollectAll: true
  apm:
    enabled: true
  processAgent:
    enabled: true
  systemProbe:
    enabled: true
  networkMonitoring:
    enabled: true
  securityAgent:
    compliance:
      enabled: true
    runtime:
      enabled: true
  kubernetesPodLabelsAsTags:
    app: kube_app
    release: kube_release
  kubernetesNamespaceLabelAsTags:
    env: kube_namespace_env
  orchestratorExplorer:
    enabled: true
  clusterChecks:
    enabled: true
  kubeStateMetricsCore:
    enabled: true
  prometheusScrape:
    enabled: true
    serviceEndpoints: true
    additionalConfigs:
      - autodiscovery:
          kubernetes:
            container_name: prometheus-server
        configurations:
          - timeout: 5
            send_distribution_buckets: true
EOF
  echo "Created default values file"
fi

# Install DataDog agent
section "Installing DataDog agent"
helm upgrade --install datadog datadog/datadog \
  --namespace datadog \
  --values "${CUSTOM_VALUES_FILE}" \
  --set datadog.apiKey="${DATADOG_API_KEY}" \
  --set datadog.appKey="${DATADOG_APP_KEY}" \
  --set datadog.clusterName="${CLUSTER_NAME}" \
  --wait

# Create ServiceMonitors if Prometheus is installed
if kubectl get namespace monitoring &>/dev/null && kubectl get deployment -n monitoring prometheus-operator-kube-p-operator &>/dev/null; then
  section "Creating ServiceMonitors for DataDog"
  
  # Create ServiceMonitors directory if it doesn't exist
  mkdir -p "${SCRIPT_DIR}/../servicemonitors"
  
  # Create a ServiceMonitor for DataDog
  cat > "${SCRIPT_DIR}/../servicemonitors/datadog-servicemonitor.yaml" <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: datadog
  namespace: monitoring
  labels:
    release: prometheus-operator
spec:
  selector:
    matchLabels:
      app: datadog
  namespaceSelector:
    matchNames:
      - datadog
  endpoints:
    - port: metrics
      interval: 30s
EOF

  # Apply the ServiceMonitor
  kubectl apply -f "${SCRIPT_DIR}/../servicemonitors/datadog-servicemonitor.yaml"
  echo -e "${GREEN}✅ ServiceMonitor for DataDog created${NC}"
fi

# Verify DataDog installation
section "Verifying DataDog installation"
echo -e "${YELLOW}Waiting for DataDog pods to be ready...${NC}"
sleep 30

if kubectl get pods -n datadog | grep -q 'Running'; then
  echo -e "${GREEN}✅ DataDog is running${NC}"
  kubectl get pods -n datadog
  echo -e "${GREEN}📊 View your cluster in DataDog: https://app.datadoghq.com/infrastructure${NC}"
  echo -e "${GREEN}   Cluster Name: ${CLUSTER_NAME}${NC}"
else
  echo -e "${RED}❌ DataDog installation may have issues. Check logs with:${NC}"
  echo "kubectl logs -n datadog -l app=datadog"
fi

# Provide instructions for next steps
section "Next Steps"
echo -e "${GREEN}DataDog has been installed in your cluster.${NC}"
echo -e "1. Visit DataDog to verify the cluster is connected: https://app.datadoghq.com"
echo -e "2. Set up dashboards and alerts in DataDog"
echo -e "3. Create health checks with: ./monitoring/datadog/create_health_checks.sh"

echo -e "\n${GREEN}DataDog installation completed${NC}"
exit 0
