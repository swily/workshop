#!/bin/bash -e

# Unified Grafana Health Check Installation Script
# This script sets up Grafana health checks for the workshop environment
# It integrates with the monitoring framework and generates Gremlin-compatible endpoints

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-current-workshop}"
GRAFANA_NAMESPACE="${GRAFANA_NAMESPACE:-monitoring}"
SERVICE_NAME="${SERVICE_NAME:-frontend}"
NAMESPACE="${NAMESPACE:-otel-demo}"
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-/health}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

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
for cmd in kubectl jq; do
  if ! command_exists "$cmd"; then
    echo -e "${RED}Error: $cmd is not installed${NC}"
    exit 1
  fi
done

# Check if Prometheus/Grafana is installed
section "Checking if Prometheus/Grafana is installed"
if ! kubectl get namespace "$GRAFANA_NAMESPACE" &>/dev/null; then
  echo -e "${RED}Error: Namespace '$GRAFANA_NAMESPACE' not found${NC}"
  echo -e "${YELLOW}Grafana is typically installed as part of the Prometheus stack.${NC}"
  echo -e "${YELLOW}Would you like to install Prometheus first? (y/n)${NC}"
  read -r response
  if [[ "$response" == "y" || "$response" == "Y" ]]; then
    echo "Installing Prometheus..."
    "${SCRIPT_DIR}/../../prometheus/install/install.sh"
  else
    echo -e "${RED}Cannot proceed without Grafana. Exiting.${NC}"
    exit 1
  fi
fi

if ! kubectl get deployment -n "$GRAFANA_NAMESPACE" prometheus-grafana &>/dev/null; then
  echo -e "${RED}Error: Grafana deployment not found in namespace '$GRAFANA_NAMESPACE'${NC}"
  echo -e "${YELLOW}Please ensure Grafana is properly installed${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Grafana is installed in namespace '$GRAFANA_NAMESPACE'${NC}"

# Get Grafana admin password
section "Retrieving Grafana credentials"
GRAFANA_ADMIN_PASSWORD=$(kubectl get secret -n "$GRAFANA_NAMESPACE" prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode 2>/dev/null)

if [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
  echo -e "${RED}Error: Could not retrieve Grafana admin password${NC}"
  echo -e "${YELLOW}Please ensure the Grafana secret exists: prometheus-grafana${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Retrieved Grafana admin password${NC}"

# Start port-forward for Grafana (in background)
section "Setting up Grafana port forwarding"
echo -e "${YELLOW}Starting port-forward for Grafana...${NC}"

# Kill any existing port-forward processes for Grafana
pkill -f "kubectl.*port-forward.*grafana" 2>/dev/null || true
sleep 2

# Start new port-forward
kubectl port-forward -n "$GRAFANA_NAMESPACE" svc/prometheus-grafana 3000:80 &
GRAFANA_PF_PID=$!

# Wait for port-forward to be ready
echo -e "${YELLOW}Waiting for port-forward to be ready...${NC}"
sleep 5

# Test Grafana accessibility
local_test_count=0
while [ $local_test_count -lt 10 ]; do
  if curl -s http://localhost:3000/api/health >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Grafana is accessible at http://localhost:3000${NC}"
    break
  fi
  echo -e "${YELLOW}Waiting for Grafana to be ready... (attempt $((local_test_count + 1))/10)${NC}"
  sleep 3
  local_test_count=$((local_test_count + 1))
done

if [ $local_test_count -eq 10 ]; then
  echo -e "${RED}❌ Grafana is not accessible after 30 seconds${NC}"
  kill $GRAFANA_PF_PID 2>/dev/null || true
  exit 1
fi

# Generate Grafana service account and token
section "Generating Grafana API token"
echo -e "${YELLOW}Creating Grafana service account and token for Gremlin integration...${NC}"

# Use the existing token generation script
GRAFANA_TOKEN_OUTPUT=$("${SCRIPT_DIR}/../auth/create_grafana_token.sh" \
  --grafana-url "http://localhost:3000" \
  --service-account-name "gremlin-health-check" \
  --token-name "gremlin-token-$(date +%s)" 2>&1)

# Extract the token from the output
GRAFANA_API_TOKEN=$(echo "$GRAFANA_TOKEN_OUTPUT" | grep -o "Token: [^[:space:]]*" | cut -d' ' -f2)

if [ -z "$GRAFANA_API_TOKEN" ]; then
  echo -e "${RED}❌ Failed to generate Grafana API token${NC}"
  echo -e "${RED}Output: $GRAFANA_TOKEN_OUTPUT${NC}"
  kill $GRAFANA_PF_PID 2>/dev/null || true
  exit 1
fi

echo -e "${GREEN}✅ Generated Grafana API token${NC}"

# Set up Grafana health check
section "Setting up Grafana health check"
echo -e "${YELLOW}Creating health check alert in Grafana...${NC}"

# Run the health check setup script
"${SCRIPT_DIR}/../health_check/setup_health_check.sh" \
  --grafana-url "http://localhost:3000" \
  --api-key "$GRAFANA_API_TOKEN" \
  --alert-name "otel-demo-health-check" \
  --namespace "$NAMESPACE" \
  --service "$SERVICE_NAME" \
  --endpoint "$HEALTH_ENDPOINT"

# Generate Gremlin integration configuration
section "Generating Gremlin integration configuration"

# Create configuration file for Gremlin
local config_file="/tmp/grafana_gremlin_config.json"
cat > "$config_file" <<EOF
{
  "platform": "grafana",
  "service_name": "${SERVICE_NAME}",
  "namespace": "${NAMESPACE}",
  "health_endpoint": "${HEALTH_ENDPOINT}",
  "monitor_url": "http://localhost:3000/api/alertmanager/grafana/api/v2/alerts",
  "auth_header": "Authorization: Bearer ${GRAFANA_API_TOKEN}",
  "success_criteria": {
    "http_status": 200,
    "json_contains": "alerts",
    "alert_state": "not_firing"
  },
  "polling_interval": 30,
  "grafana_url": "http://localhost:3000",
  "alert_name": "otel-demo-health-check"
}
EOF

echo -e "${GREEN}✅ Gremlin configuration saved to: ${config_file}${NC}"

# Create a ConfigMap to track Grafana health check status
section "Creating health check status tracking"
kubectl create configmap -n "$GRAFANA_NAMESPACE" grafana-health-check-status \
  --from-literal=configured=true \
  --from-literal=timestamp="$(date '+%Y-%m-%d %H:%M:%S')" \
  --from-literal=service="$SERVICE_NAME" \
  --from-literal=namespace="$NAMESPACE" \
  --from-literal=endpoint="$HEALTH_ENDPOINT" \
  --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✅ Health check status tracking created${NC}"

# Clean up port-forward
section "Cleaning up"
echo -e "${YELLOW}Stopping port-forward...${NC}"
kill $GRAFANA_PF_PID 2>/dev/null || true

# Final summary
section "Grafana Health Check Setup Complete"
echo -e "${GREEN}✅ Grafana health check has been configured successfully${NC}"
echo -e "\n${BLUE}=== Gremlin Integration Summary ===${NC}"
echo -e "${YELLOW}1. Monitor URL:${NC} http://localhost:3000/api/alertmanager/grafana/api/v2/alerts"
echo -e "${YELLOW}2. Authentication:${NC} Bearer ${GRAFANA_API_TOKEN:0:20}..."
echo -e "${YELLOW}3. Service:${NC} $SERVICE_NAME in $NAMESPACE namespace"
echo -e "${YELLOW}4. Health Endpoint:${NC} $HEALTH_ENDPOINT"
echo -e "${YELLOW}5. Configuration File:${NC} $config_file"

echo -e "\n${YELLOW}Note: To access Grafana UI, run:${NC}"
echo -e "kubectl port-forward -n $GRAFANA_NAMESPACE svc/prometheus-grafana 3000:80"
echo -e "${YELLOW}Then visit: http://localhost:3000${NC}"
echo -e "${YELLOW}Username: admin, Password: $GRAFANA_ADMIN_PASSWORD${NC}"

exit 0
