#!/bin/bash -e

# Configuration
DYNATRACE_API_TOKEN="${1:-dt0c01.T7LOPNX6U5T5Y3DKJRP5WYP7.FADRHQQLSG2P62RCSDJUZC47YBTLANIEYILQ7AKGBKQKHUMVJQXOT6LEOJPNBA6J}"
CLUSTER_NAME="${CLUSTER_NAME:-seanwiley-otel}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print section headers
section() {
  echo -e "\n${GREEN}=== $1 ===${NC}"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check for required tools
section "Checking for required tools"
for cmd in kubectl jq curl; do
  if ! command_exists "$cmd"; then
    echo -e "${RED}Error: $cmd is not installed${NC}"
    exit 1
  fi
done

# Create namespace if it doesn't exist
section "Creating Dynatrace namespace"
kubectl create namespace dynatrace --dry-run=client -o yaml | kubectl apply -f -

# Set Dynatrace environment URL with the actual environment ID
# Note: For the DynaKube CR, we need to use the live.dynatrace.com format
DYNATRACE_INSTANCE_ID="qpm46186"
DYNATRACE_ENV_URL="https://${DYNATRACE_INSTANCE_ID}.live.dynatrace.com"

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

# Create a Dynatrace OneAgent custom resource
section "Creating Dynatrace OneAgent custom resource"
cat <<EOF > ${TMP_DIR}/dynatrace-oneagent.yaml
apiVersion: dynatrace.com/v1beta1
kind: DynaKube
metadata:
  name: dynatrace
  namespace: dynatrace
spec:
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
