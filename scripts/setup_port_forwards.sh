#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Kill existing port-forwards
echo -e "${YELLOW}Killing existing port forwards...${NC}"
pkill -f "kubectl port-forward" || true
sleep 2  # Give it a moment to clean up

# Define services to forward (format: namespace:service:port:local_port:description)
SERVICES="
  otel-demo:grafana:80:3000:Grafana Dashboard (otel-demo)
  monitoring:prometheus-grafana:80:3001:Grafana Dashboard (monitoring)
  otel-demo:load-generator:8089:8089:Load Generator
  otel-demo:frontend:8080:8080:Frontend Store
  otel-demo:frontend-proxy:8080:8081:Frontend Proxy
  otel-demo:prometheus:9090:9090:Prometheus Server
  otel-demo:jaeger-query:16686:16686:Jaeger UI
  otel-demo:opensearch:9200:9200:OpenSearch
"

echo -e "\n${YELLOW}Setting up port forwards...${NC}"
echo "Service,Local Port,Description" > port_forwards.csv

# Function to start port forwarding
start_port_forward() {
    local NAMESPACE=$1
    local SVC_NAME=$2
    local PORT=$3
    local LOCAL_PORT=$4
    local DESCRIPTION=$5

    echo -e "${GREEN}Forwarding ${NAMESPACE}/${SVC_NAME}:${PORT} to localhost:${LOCAL_PORT} (${DESCRIPTION})${NC}"
    
    # Start the port forward in the background
    kubectl port-forward -n ${NAMESPACE} svc/${SVC_NAME} ${LOCAL_PORT}:${PORT} > /dev/null 2>&1 &
    local PID=$!
    
    # Wait a moment to see if it fails immediately
    sleep 2
    
    if ps -p $PID > /dev/null; then
        echo "${SVC_NAME},${LOCAL_PORT},${DESCRIPTION}" >> port_forwards.csv
        echo -e "${GREEN}✓ Successfully started port forward for ${SVC_NAME} on port ${LOCAL_PORT}${NC}"
    else
        echo -e "${RED}✗ Failed to start port forward for ${SVC_NAME}${NC}"
    fi
}

# Process each service
while IFS= read -r line; do
    if [ -z "$line" ]; then continue; fi  # Skip empty lines
    
    # Parse the service definition
    IFS=':' read -r -a parts <<< "$line"
    NAMESPACE="${parts[0]}"
    SVC_NAME="${parts[1]}"
    PORT="${parts[2]}"
    LOCAL_PORT="${parts[3]}"
    DESCRIPTION="${parts[4]}"
    
    # Start the port forward
    start_port_forward "$NAMESPACE" "$SVC_NAME" "$PORT" "$LOCAL_PORT" "$DESCRIPTION"
done <<< "$SERVICES"

# Print summary
echo -e "\n${GREEN}Port forwarding setup complete. Active forwards:${NC}"
cat port_forwards.csv | column -t -s, | sed 's/^/  /'
echo -e "\n${YELLOW}To stop all port forwards, run: pkill -f \"kubectl port-forward\"${NC}"

# Keep the script running to maintain the port forwards
wait
