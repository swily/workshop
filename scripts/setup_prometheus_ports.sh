#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Create output directory
OUTPUT_DIR="./prometheus_ports_$(date +%s)"
mkdir -p "$OUTPUT_DIR"

# Kill existing port-forwards
echo -e "${YELLOW}Checking for existing port forwards...${NC}"
pkill -f "kubectl port-forward" || true
sleep 2  # Give it a moment to clean up

# Define additional services to forward (format: namespace:service:port:local_port:description)
ADDITIONAL_SERVICES="
  otel-demo:grafana:80:3000:Grafana Dashboard
  otel-demo:frontend:8080:8080:Frontend Store
  otel-demo:frontend-proxy:8080:8081:Frontend Proxy
"

# Get all Prometheus services
echo -e "\n${YELLOW}Finding Prometheus services...${NC}"
# Get services with their ports in a more reliable way
PROMETHEUS_SERVICES=$(kubectl get svc -A -o json | \
  jq -r '.items[] | select(.metadata.name | test("prometheus"; "i")) | 
  "\(.metadata.namespace):\(.metadata.name):\(.spec.ports[0].port):prometheus-\(.metadata.name)"' 2>/dev/null)

if [ -z "$PROMETHEUS_SERVICES" ]; then
    echo -e "${YELLOW}No Prometheus services found in the cluster, continuing with additional services only${NC}"
fi

echo -e "\n${YELLOW}Setting up port forwards...${NC}"
echo "namespace,service,local_port,target_port,status,metrics,istio_metrics" > "${OUTPUT_DIR}/prometheus_ports.csv"

BASE_PORT=9090
PORT_COUNTER=0

# Arrays to track PIDs and services
PIDS=()
SERVICES=()

# Function to verify service is accessible
verify_service() {
    local NAMESPACE=$1
    local SVC_NAME=$2
    local PORT=$3
    
    echo -n "Verifying ${NAMESPACE}/${SVC_NAME}:${PORT}... "
    
    # Check if the service exists and is accessible
    if ! kubectl -n $NAMESPACE get svc $SVC_NAME &> /dev/null; then
        echo -e "${RED}Service not found${NC}"
        return 1
    fi
    
    # Check if any pods are running for the service
    local selector=$(kubectl -n $NAMESPACE get svc $SVC_NAME -o jsonpath='{.spec.selector}' | jq -r 'to_entries|map("\(.key)=\(.value|tostring)")|.[]' | paste -sd "," -)
    if [ -z "$selector" ]; then
        echo -e "${YELLOW}No selector found${NC}"
    else
        local pod_count=$(kubectl -n $NAMESPACE get pods -l $selector --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$pod_count" -eq 0 ]; then
            echo -e "${YELLOW}No pods found${NC}"
        else
            echo -e "${GREEN}✓ Found ${pod_count} pod(s)${NC}"
        fi
    fi
    
    return 0
}

# Function to start port forwarding
start_port_forward() {
    local NAMESPACE=$1
    local SVC_NAME=$2
    local TARGET_PORT=$3
    local LOCAL_PORT=$4
    local DESCRIPTION=${5:-""}
    
    # Verify service first
    if ! verify_service "$NAMESPACE" "$SVC_NAME" "$TARGET_PORT"; then
        echo -e "${RED}✗ Skipping ${NAMESPACE}/${SVC_NAME} due to verification failure${NC}"
        return 1
    fi
    
    # Create a service-specific log file name
    LOG_FILE="${OUTPUT_DIR}/${NAMESPACE}_${SVC_NAME}.log"
    
    echo -e "\n${YELLOW}Forwarding ${NAMESPACE}/${SVC_NAME} (port ${TARGET_PORT}) to localhost:${LOCAL_PORT} ${DESCRIPTION:+($DESCRIPTION)}...${NC}"
    
    # Start port forward in background
    kubectl port-forward -n $NAMESPACE svc/$SVC_NAME ${LOCAL_PORT}:${TARGET_PORT} > "$LOG_FILE" 2>&1 &
    local PORT_FORWARD_PID=$!
    
    # Store the PID and service info
    PIDS+=($PORT_FORWARD_PID)
    SERVICES+=("$NAMESPACE/$SVC_NAME")
    
    # Wait briefly to check if port forward started successfully
    sleep 2
    if ! ps -p $PORT_FORWARD_PID > /dev/null; then
        echo -e "${RED}✗ Failed to start port forward for ${NAMESPACE}/${SVC_NAME}${NC}"
        echo -e "Check ${LOG_FILE} for details"
        return 1
    fi
    
    # Add to CSV
    echo "$NAMESPACE,$SVC_NAME,$LOCAL_PORT,$TARGET_PORT,running,http://localhost:$LOCAL_PORT/metrics,http://localhost:$LOCAL_PORT/stats/prometheus" >> "${OUTPUT_DIR}/prometheus_ports.csv"
    
    echo -e "${GREEN}✓ Successfully started port forward for ${NAMESPACE}/${SVC_NAME} (PID: $PORT_FORWARD_PID)${NC}"
    return 0
}

# Start the main port forwarding
echo -e "\n${GREEN}Starting port forwarding...${NC}"

# Arrays to store PIDs and service names
PIDS=()
SERVICES=()

# Forward Prometheus services
for svc_info in $PROMETHEUS_SERVICES; do
    IFS=':' read -r NAMESPACE SVC_NAME TARGET_PORT DESCRIPTION <<< "$svc_info"
    
    if [ -z "$TARGET_PORT" ] || ! [[ "$TARGET_PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}✗ Invalid port for ${NAMESPACE}/${SVC_NAME}: ${TARGET_PORT}${NC}"
        continue
    fi
    
    LOCAL_PORT=$((BASE_PORT + PORT_COUNTER))
    ((PORT_COUNTER++))
    
    start_port_forward "$NAMESPACE" "$SVC_NAME" "$TARGET_PORT" "$LOCAL_PORT" "$DESCRIPTION"
done

# Forward additional services
echo -e "\n${YELLOW}Setting up additional service forwards...${NC}"
echo "$ADDITIONAL_SERVICES" | while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" == \#* ]] && continue
    
    # Clean up the line
    line=$(echo "$line" | xargs)
    
    # Parse the line (format: namespace:service:port:local_port:description)
    IFS=':' read -r NAMESPACE SVC_NAME TARGET_PORT LOCAL_PORT DESCRIPTION <<< "$line"
    
    # Clean up each variable
    NAMESPACE=$(echo "$NAMESPACE" | xargs)
    SVC_NAME=$(echo "$SVC_NAME" | xargs)
    TARGET_PORT=$(echo "$TARGET_PORT" | xargs)
    LOCAL_PORT=$(echo "$LOCAL_PORT" | xargs)
    DESCRIPTION=$(echo "$DESCRIPTION" | xargs)
    
    if [ -z "$NAMESPACE" ] || [ -z "$SVC_NAME" ] || [ -z "$TARGET_PORT" ] || [ -z "$LOCAL_PORT" ]; then
        echo -e "${RED}✗ Invalid service definition: $line${NC}"
        continue
    fi
    
    start_port_forward "$NAMESPACE" "$SVC_NAME" "$TARGET_PORT" "$LOCAL_PORT" "$DESCRIPTION"
done

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    # Kill all background processes
    for i in "${!PIDS[@]}"; do
        local pid=${PIDS[$i]}
        local svc=${SERVICES[$i]}
        if ps -p $pid > /dev/null; then
            echo -e "Stopping ${YELLOW}${svc}${NC} (PID: $pid)..."
            kill $pid 2>/dev/null || true
        fi
    done
    echo -e "${GREEN}All port forwards have been stopped.${NC}"
    exit 0
}

# Set up trap to catch script termination
trap cleanup INT TERM EXIT

# Print summary
echo -e "\n${GREEN}Port forwarding summary:${NC}"
column -t -s, "${OUTPUT_DIR}/prometheus_ports.csv"

echo -e "\n${GREEN}Port forwarding is running. Press Ctrl+C to stop all forwards.${NC}"
echo -e "Access the following services:"
echo -e "- Grafana Dashboard: ${GREEN}http://localhost:3000${NC}"
echo -e "- Frontend Store: ${GREEN}http://localhost:8080${NC}"
echo -e "- Frontend Proxy: ${GREEN}http://localhost:8081${NC}"

# Keep the script running
while true; do
    sleep 10
done
