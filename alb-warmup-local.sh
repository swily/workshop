#!/bin/bash

# Local ALB Warm-up Script
# Keeps ALB targets warm by making HTTP requests every 15 minutes
# Run this continuously in a terminal to avoid cold start delays

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-current-workshop}"
GRAFANA_URL="http://${CLUSTER_NAME}-grafana.gremlinpoc.com"
FRONTEND_URL="http://${CLUSTER_NAME}-frontend.gremlinpoc.com"
INTERVAL_MINUTES=15
TIMEOUT_SECONDS=30

# Additional endpoints to warm up (add more as needed)
ADDITIONAL_ENDPOINTS=(
    "${GRAFANA_URL}/api/health"
    "${FRONTEND_URL}/productpage"
    # Add more endpoints here if needed
)

# Function to make HTTP request with error handling
make_request() {
    local url="$1"
    local endpoint_name="$2"
    
    echo -n "  ${endpoint_name}: "
    
    # Use curl with timeout and follow redirects
    if response=$(curl -s -w "%{http_code}|%{time_total}" -m "${TIMEOUT_SECONDS}" -L "${url}" 2>/dev/null); then
        http_code=$(echo "$response" | tail -1 | cut -d'|' -f1)
        time_total=$(echo "$response" | tail -1 | cut -d'|' -f2)
        
        if [[ "$http_code" =~ ^[23][0-9][0-9]$ ]]; then
            echo -e "${GREEN}OK ${http_code} (${time_total}s)${NC}"
            return 0
        else
            echo -e "${YELLOW}WARN ${http_code} (${time_total}s)${NC}"
            return 1
        fi
    else
        echo -e "${RED}FAILED (timeout/error)${NC}"
        return 1
    fi
}

# Function to perform warm-up cycle
warmup_cycle() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}ALB Warm-up Cycle - ${timestamp}${NC}"
    echo "=================================================="
    
    local success_count=0
    local total_count=0
    
    # Main endpoints
    make_request "${GRAFANA_URL}" "Grafana" && ((success_count++))
    ((total_count++))
    
    make_request "${FRONTEND_URL}" "Frontend" && ((success_count++))
    ((total_count++))
    
    # Additional endpoints
    for endpoint in "${ADDITIONAL_ENDPOINTS[@]}"; do
        endpoint_name=$(echo "$endpoint" | sed 's|.*/||' | sed 's|^$|root|')
        make_request "$endpoint" "$endpoint_name" && ((success_count++))
        ((total_count++))
    done
    
    # Summary
    echo "=================================================="
    if [ "$success_count" -eq "$total_count" ]; then
        echo -e "${GREEN}All endpoints warmed successfully (${success_count}/${total_count})${NC}"
    else
        echo -e "${YELLOW}Partial success (${success_count}/${total_count})${NC}"
    fi
    
    echo -e "${BLUE}Next warm-up in ${INTERVAL_MINUTES} minutes...${NC}"
    echo ""
}

# Function to handle script termination
cleanup() {
    echo -e "\n${YELLOW}ALB warm-up script stopped${NC}"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Main execution
echo -e "${BLUE}Starting ALB Warm-up Script${NC}"
echo "=================================================="
echo -e "${GREEN}Target URLs:${NC}"
echo "  - Grafana: ${GRAFANA_URL}"
echo "  - Frontend: ${FRONTEND_URL}"
echo -e "${GREEN}Interval: ${INTERVAL_MINUTES} minutes${NC}"
echo -e "${GREEN}Timeout: ${TIMEOUT_SECONDS} seconds per request${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""

# Initial warm-up
warmup_cycle

# Continuous loop
while true; do
    sleep $((INTERVAL_MINUTES * 60))
    warmup_cycle
done
