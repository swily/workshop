#!/bin/bash

# Dynatrace Health Check Creator for Gremlin
# Creates Gremlin health checks for Dynatrace Problems API

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DYNATRACE_INSTANCE_ID="${DYNATRACE_INSTANCE_ID:-}"
DYNATRACE_API_TOKEN="${DYNATRACE_API_TOKEN:-}"
GREMLIN_TEAM_ID="${GREMLIN_TEAM_ID:-}"
GREMLIN_API_KEY="${GREMLIN_API_KEY:-}"
GREMLIN_API_URL="https://api.gremlin.com/v1"

# Collect credentials
collect_credentials() {
    echo -e "${BLUE}Collecting Dynatrace credentials...${NC}"
    
    if [ -z "$DYNATRACE_INSTANCE_ID" ]; then
        read -p "Enter Dynatrace Instance ID: " DYNATRACE_INSTANCE_ID
    fi
    
    if [ -z "$DYNATRACE_API_TOKEN" ]; then
        read -sp "Enter Dynatrace API Token: " DYNATRACE_API_TOKEN
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

# Create Dynatrace integration
create_dynatrace_integration() {
    local dynatrace_url="https://${DYNATRACE_INSTANCE_ID}.live.dynatrace.com"
    local integration_name="dynatrace-problems-$(date +%s)"
    
    echo -e "${BLUE}Creating Dynatrace integration: $integration_name${NC}"
    
    local integration_payload=$(cat << EOF
{
  "name": "$integration_name",
  "description": "Dynatrace Problems API integration",
  "type": "CUSTOM",
  "privateNetwork": false,
  "lastAuthenticationStatus": "AUTHENTICATED",
  "url": "$dynatrace_url/api/v2/problems",
  "headers": {
    "Authorization": "Api-Token $DYNATRACE_API_TOKEN"
  }
}
EOF
)
    
    local response=$(curl -s -X POST "https://api.gremlin.com/v1/external-integrations/status-check?teamId=$GREMLIN_TEAM_ID&type=CUSTOM" \
        -H "Authorization: Key $GREMLIN_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$integration_payload" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Dynatrace integration created${NC}"
        echo "$integration_name"
    else
        echo -e "${RED}❌ Failed to create integration${NC}"
        return 1
    fi
}

# Create health check
create_health_check() {
    local integration_name="$1"
    local dynatrace_url="https://${DYNATRACE_INSTANCE_ID}.live.dynatrace.com"
    local check_name="dynatrace-problems-$(date +%s)"
    
    echo -e "${BLUE}Creating health check: $check_name${NC}"
    
    local health_check_payload=$(cat << EOF
{
  "name": "$check_name",
  "endpointType": "http",
  "isContinuous": true,
  "endpointConfiguration": {
    "url": "$dynatrace_url/api/v2/problems?problemSelector=status(OPEN)",
    "method": "GET",
    "headers": {
      "Authorization": "Api-Token $DYNATRACE_API_TOKEN"
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
          "jpQuery": "totalCount",
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
        echo -e "${BLUE}URL: $dynatrace_url/api/v2/problems${NC}"
    else
        echo -e "${RED}❌ Failed to create health check${NC}"
        return 1
    fi
}

# Main
main() {
    echo -e "${GREEN}Dynatrace Health Check Creator${NC}"
    echo ""
    
    collect_credentials
    
    local integration_name=$(create_dynatrace_integration)
    if [ $? -eq 0 ]; then
        create_health_check "$integration_name"
    fi
    
    echo ""
    echo -e "${GREEN}✅ Dynatrace health check setup complete${NC}"
    echo -e "${BLUE}View: https://app.gremlin.com/reliability/status-checks${NC}"
}

main "$@"
