#!/bin/bash

# DataDog Health Check Creator for Gremlin
# Creates Gremlin health checks for DataDog Monitors API

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DATADOG_API_KEY="${DATADOG_API_KEY:-}"
DATADOG_APP_KEY="${DATADOG_APP_KEY:-}"
DATADOG_SITE="${DATADOG_SITE:-datadoghq.com}"
GREMLIN_TEAM_ID="${GREMLIN_TEAM_ID:-}"
GREMLIN_API_KEY="${GREMLIN_API_KEY:-}"
GREMLIN_API_URL="https://api.gremlin.com/v1"

# Collect credentials
collect_credentials() {
    echo -e "${BLUE}Collecting DataDog credentials...${NC}"
    
    if [ -z "$DATADOG_API_KEY" ]; then
        read -sp "Enter DataDog API Key: " DATADOG_API_KEY
        echo ""
    fi
    
    if [ -z "$DATADOG_APP_KEY" ]; then
        read -sp "Enter DataDog APP Key: " DATADOG_APP_KEY
        echo ""
    fi
    
    echo -e "${BLUE}Collecting Gremlin credentials...${NC}"
    
    if [ -z "$GREMLIN_TEAM_ID" ]; then
        read -p "Enter Gremlin Team ID: " GREMLIN_TEAM_ID
    fi
    
    if [ -z "$GREMLIN_API_KEY" ]; then
        read -sp "Enter Gremlin API Key: " GREMLIN_API_KEY
        echo ""
    fi
}

# Create DataDog integration
create_datadog_integration() {
    local datadog_url="https://api.${DATADOG_SITE}"
    local integration_name="datadog-monitors-$(date +%s)"
    
    echo -e "${BLUE}Creating DataDog integration: $integration_name${NC}"
    
    local integration_payload=$(cat << EOF
{
  "name": "$integration_name",
  "description": "DataDog Monitors API integration",
  "type": "CUSTOM",
  "privateNetwork": false,
  "lastAuthenticationStatus": "AUTHENTICATED",
  "url": "$datadog_url/api/v1/monitor",
  "headers": {
    "DD-API-KEY": "$DATADOG_API_KEY",
    "DD-APPLICATION-KEY": "$DATADOG_APP_KEY"
  }
}
EOF
)
    
    local response=$(curl -s -X POST "https://api.gremlin.com/v1/external-integrations/status-check?teamId=$GREMLIN_TEAM_ID&type=CUSTOM" \
        -H "Authorization: Key $GREMLIN_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$integration_payload" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ DataDog integration created${NC}"
        echo "$integration_name"
    else
        echo -e "${RED}❌ Failed to create integration${NC}"
        return 1
    fi
}

# Create health check
create_health_check() {
    local integration_name="$1"
    local datadog_url="https://api.${DATADOG_SITE}"
    local check_name="datadog-monitors-$(date +%s)"
    
    echo -e "${BLUE}Creating health check: $check_name${NC}"
    
    local health_check_payload=$(cat << EOF
{
  "name": "$check_name",
  "endpointType": "http",
  "isContinuous": true,
  "endpointConfiguration": {
    "url": "$datadog_url/api/v1/monitor?group_states=alert",
    "method": "GET",
    "headers": {
      "DD-API-KEY": "$DATADOG_API_KEY",
      "DD-APPLICATION-KEY": "$DATADOG_APP_KEY"
    }
  },
  "evaluationConfiguration": {
    "okStatusCodes": [200],
    "responseBodyEvaluation": {
      "op": "AND",
      "predicates": [
        {
          "comparator": "GREATER_THAN",
          "type": "Number",
          "jpQuery": "length",
          "rValue": "0"
        }
      ]
    }
  },
  "teamExternalIntegration": {
    "observabilityToolType": "CUSTOM",
    "name": "$integration_name"
  },
  "pollingIntervalSeconds": 60
}
EOF
)
    
    local response=$(curl -s -X POST "https://api.gremlin.com/v1/status-checks?teamId=$GREMLIN_TEAM_ID" \
        -H "Authorization: Key $GREMLIN_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$health_check_payload" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Health check created: $check_name${NC}"
        echo -e "${BLUE}URL: $datadog_url/api/v1/monitor${NC}"
    else
        echo -e "${RED}❌ Failed to create health check${NC}"
        return 1
    fi
}

# Main
main() {
    echo -e "${GREEN}DataDog Health Check Creator${NC}"
    echo ""
    
    collect_credentials
    
    local integration_name=$(create_datadog_integration)
    if [ $? -eq 0 ]; then
        create_health_check "$integration_name"
    fi
    
    echo ""
    echo -e "${GREEN}✅ DataDog health check setup complete${NC}"
    echo -e "${BLUE}View: https://app.gremlin.com/reliability/status-checks${NC}"
}

main "$@"
