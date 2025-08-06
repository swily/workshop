#!/bin/bash -e

# Unified Dynatrace Installation Script
# This script installs the Dynatrace Operator and OneAgent in the dynatrace namespace
# It integrates with the monitoring framework for the workshop environment

# Configuration
DYNATRACE_API_TOKEN="${DYNATRACE_API_TOKEN:-dt0c01.T7LOPNX6U5T5Y3DKJRP5WYP7.FADRHQQLSG2P62RCSDJUZC47YBTLANIEYILQ7AKGBKQKHUMVJQXOT6LEOJPNBA6J}"
CLUSTER_NAME="${CLUSTER_NAME:-seanwiley-otel}"
DYNATRACE_INSTANCE_ID="${DYNATRACE_INSTANCE_ID:-qpm46186}"
DYNATRACE_ENV_URL="https://${DYNATRACE_INSTANCE_ID}.live.dynatrace.com"

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

# Function to prompt for API token if not provided
prompt_for_api_token() {
  if [[ "$DYNATRACE_API_TOKEN" == *"dt0c01.T7LOPNX6U5T5Y3DKJRP5WYP7"* ]]; then
    echo -e "${YELLOW}Using default Dynatrace API token. For production use, please provide your own token.${NC}"
    echo -e "${YELLOW}To use your own token, set the DYNATRACE_API_TOKEN environment variable.${NC}"
    echo -e "${YELLOW}Example: export DYNATRACE_API_TOKEN=your-token-here${NC}"
    echo ""
    echo -e "${YELLOW}Would you like to continue with the default token? (y/n)${NC}"
    read -r response
    if [[ "$response" != "y" && "$response" != "Y" ]]; then
      echo -e "${YELLOW}Please enter your Dynatrace API token:${NC}"
      read -r DYNATRACE_API_TOKEN
      if [ -z "$DYNATRACE_API_TOKEN" ]; then
        echo -e "${RED}Error: Dynatrace API token is required${NC}"
        exit 1
      fi
    fi
  fi
}

# Function to prompt for Dynatrace instance ID if not provided
prompt_for_instance_id() {
  if [[ "$DYNATRACE_INSTANCE_ID" == "qpm46186" ]]; then
    echo -e "${YELLOW}Using default Dynatrace instance ID. For production use, please provide your own instance ID.${NC}"
    echo -e "${YELLOW}To use your own instance ID, set the DYNATRACE_INSTANCE_ID environment variable.${NC}"
    echo -e "${YELLOW}Example: export DYNATRACE_INSTANCE_ID=your-instance-id${NC}"
    echo ""
    echo -e "${YELLOW}Would you like to continue with the default instance ID? (y/n)${NC}"
    read -r response
    if [[ "$response" != "y" && "$response" != "Y" ]]; then
      echo -e "${YELLOW}Please enter your Dynatrace instance ID:${NC}"
      read -r DYNATRACE_INSTANCE_ID
      if [ -z "$DYNATRACE_INSTANCE_ID" ]; then
        echo -e "${RED}Error: Dynatrace instance ID is required${NC}"
        exit 1
      fi
      DYNATRACE_ENV_URL="https://${DYNATRACE_INSTANCE_ID}.live.dynatrace.com"
    fi
  fi
}

# Check for required tools
section "Checking for required tools"
for cmd in kubectl jq curl; do
  if ! command_exists "$cmd"; then
    echo -e "${RED}Error: $cmd is not installed${NC}"
    exit 1
  fi
done

# Prompt for API token and instance ID
prompt_for_api_token
prompt_for_instance_id

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
section "Creating Dynatrace namespace"
kubectl create namespace dynatrace --dry-run=client -o yaml | kubectl apply -f -

section "Installing Dynatrace Operator"
echo -e "${YELLOW}Using API token: ${DYNATRACE_API_TOKEN:0:10}...${NC}"
echo -e "${YELLOW}Using Dynatrace environment: ${DYNATRACE_ENV_URL}${NC}"

# Download the latest Dynatrace Operator release
LATEST_RELEASE=$(curl -s https://api.github.com/repos/dynatrace/dynatrace-operator/releases/latest | jq -r '.tag_name')
echo -e "${YELLOW}Latest Dynatrace Operator release: ${LATEST_RELEASE}${NC}"

# Create a temporary directory for Dynatrace Operator manifests
TMP_DIR=$(mktemp -d)
trap 'rm -rf ${TMP_DIR}' EXIT

# Download the Dynatrace Operator manifest
curl -L -o ${TMP_DIR}/dynatrace-operator.yaml https://github.com/Dynatrace/dynatrace-operator/releases/latest/download/kubernetes.yaml

# Apply the Dynatrace Operator manifest
kubectl apply -f ${TMP_DIR}/dynatrace-operator.yaml

# Wait for Dynatrace Operator to be ready
section "Waiting for Dynatrace Operator to be ready"
kubectl -n dynatrace wait --for=condition=available deployment/dynatrace-operator --timeout=300s

# Wait for Dynatrace Webhook to be ready
section "Waiting for Dynatrace Webhook to be ready"
echo "Waiting 30 seconds for webhook pods to start..."
sleep 30
kubectl -n dynatrace wait --for=condition=ready pods -l app.kubernetes.io/component=webhook --timeout=120s

# Create a secret with the Dynatrace API token
section "Creating Dynatrace API token secret"
kubectl -n dynatrace create secret generic dynatrace-api-token \
  --from-literal="apiToken=${DYNATRACE_API_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Create values directory if it doesn't exist
mkdir -p "${VALUES_DIR}"

# Check if custom values file exists, if not create a default one
CUSTOM_VALUES_FILE="${VALUES_DIR}/dynatrace-values.yaml"
if [ ! -f "${CUSTOM_VALUES_FILE}" ]; then
  section "Creating default values file"
  echo "No custom values file found, creating default values file at ${CUSTOM_VALUES_FILE}"
  
  # Create a basic default values file
  cat > "${CUSTOM_VALUES_FILE}" <<EOF
apiUrl: ${DYNATRACE_ENV_URL}/api
tokens: dynatrace-api-token
oneAgent:
  classicFullStack:
    tolerations:
    - effect: NoSchedule
      key: node-role.kubernetes.io/master
      operator: Exists
    - effect: NoSchedule
      key: node-role.kubernetes.io/control-plane
      operator: Exists
activeGate:
  capabilities:
    - routing
    - kubernetes-monitoring
  group: default
kubernetesMonitoring:
  enabled: true
EOF
  echo "Created default values file"
fi

# Create a Dynatrace OneAgent custom resource
section "Creating Dynatrace OneAgent custom resource"
cat <<EOF > ${TMP_DIR}/dynatrace-oneagent.yaml
apiVersion: dynatrace.com/v1beta1
kind: DynaKube
metadata:
  name: dynatrace
  namespace: dynatrace
spec:
  $(cat "${CUSTOM_VALUES_FILE}")
EOF

kubectl apply -f ${TMP_DIR}/dynatrace-oneagent.yaml

# Verify Dynatrace installation
section "Verifying Dynatrace installation"
echo -e "${YELLOW}Waiting for Dynatrace OneAgent pods to be ready...${NC}"
sleep 30

# Check if OneAgent pods are running
ONEAGENT_PODS=$(kubectl get pods -n dynatrace -l app.kubernetes.io/name=oneagent -o name 2>/dev/null || echo "")
if [ -n "$ONEAGENT_PODS" ]; then
  echo -e "${GREEN}✅ Dynatrace OneAgent pods are being created${NC}"
  kubectl get pods -n dynatrace
else
  echo -e "${RED}❌ Dynatrace OneAgent pods were not found. Check the logs:${NC}"
  echo "kubectl logs -n dynatrace -l app.kubernetes.io/name=dynatrace-operator"
fi

# Create ServiceMonitors if Prometheus is installed
if kubectl get namespace monitoring &>/dev/null && kubectl get deployment -n monitoring prometheus-operator-kube-p-operator &>/dev/null; then
  section "Creating ServiceMonitors for Dynatrace"
  
  # Create ServiceMonitors directory if it doesn't exist
  mkdir -p "${SCRIPT_DIR}/../servicemonitors"
  
  # Create a ServiceMonitor for Dynatrace
  cat > "${SCRIPT_DIR}/../servicemonitors/dynatrace-servicemonitor.yaml" <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: dynatrace
  namespace: monitoring
  labels:
    release: prometheus-operator
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: dynatrace-operator
  namespaceSelector:
    matchNames:
      - dynatrace
  endpoints:
    - port: metrics
      interval: 30s
EOF

  # Apply the ServiceMonitor
  kubectl apply -f "${SCRIPT_DIR}/../servicemonitors/dynatrace-servicemonitor.yaml"
  echo -e "${GREEN}✅ ServiceMonitor for Dynatrace created${NC}"
fi

# Provide instructions for next steps
section "Next Steps"
echo -e "${GREEN}Dynatrace has been installed in your cluster.${NC}"
echo -e "1. Complete the setup by configuring your Dynatrace environment URL in the DynaKube custom resource."
echo -e "2. Visit your Dynatrace environment to verify the cluster is connected."
echo -e "3. Create health checks in Gremlin using the Dynatrace integration."

# Cleanup
rm -rf ${TMP_DIR}

echo -e "\n${GREEN}Dynatrace installation completed${NC}"
exit 0
