#!/bin/bash

# New Relic Health Check Creator for Gremlin
# Creates Gremlin health checks for New Relic Alert Conditions API

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NEW_RELIC_API_KEY="${NEW_RELIC_API_KEY:-}"
NEW_RELIC_ACCOUNT_ID="${NEW_RELIC_ACCOUNT_ID:-}"
GREMLIN_TEAM_ID="${GREMLIN_TEAM_ID:-}"
GREMLIN_API_KEY="${GREMLIN_API_KEY:-}"
GREMLIN_API_URL="https://api.gremlin.com/v1"

# Collect credentials
collect_credentials() {
    echo -e "${BLUE}Collecting New Relic credentials...${NC}"
    
    if [ -z "$NEW_RELIC_API_KEY" ]; then
        read -sp "Enter New Relic API Key: " NEW_RELIC_API_KEY
        echo ""
    fi
    
    if [ -z "$NEW_RELIC_ACCOUNT_ID" ]; then
        read -p "Enter New Relic Account ID: " NEW_RELIC_ACCOUNT_ID
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

# Create New Relic integration
create_newrelic_integration() {
    local integration_name="newrelic-alerts-$(date +%s)"
    
    echo -e "${BLUE}Creating New Relic integration: $integration_name${NC}"
    
    local integration_payload=$(cat << EOF
{
  "name": "$integration_name",
  "description": "New Relic Alert Conditions API integration",
  "type": "CUSTOM",
  "privateNetwork": false,
  "lastAuthenticationStatus": "AUTHENTICATED",
  "url": "https://api.newrelic.com/v2/alerts_nrql_conditions.json",
  "headers": {
    "Api-Key": "$NEW_RELIC_API_KEY"
  }
}
EOF
)
    
    local response=$(curl -s -X POST "https://api.gremlin.com/v1/external-integrations/status-check?teamId=$GREMLIN_TEAM_ID&type=CUSTOM" \
        -H "Authorization: Key $GREMLIN_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$integration_payload" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ New Relic integration created${NC}"
        echo "$integration_name"
    else
        echo -e "${RED}❌ Failed to create integration${NC}"
        return 1
    fi
}

# Create health check
create_health_check() {
    local integration_name="$1"
    local check_name="newrelic-alerts-$(date +%s)"
    
    echo -e "${BLUE}Creating health check: $check_name${NC}"
    
    local health_check_payload=$(cat << EOF
{
  "name": "$check_name",
  "endpointType": "http",
  "isContinuous": true,
  "endpointConfiguration": {
    "url": "https://api.newrelic.com/v2/alerts_violations.json?only_open=true",
    "method": "GET",
    "headers": {
      "Api-Key": "$NEW_RELIC_API_KEY"
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
          "jpQuery": "violations.length",
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
        echo -e "${BLUE}URL: https://api.newrelic.com/v2/alerts_violations.json${NC}"
    else
        echo -e "${RED}❌ Failed to create health check${NC}"
        return 1
    fi
}

# Main
main() {
    echo -e "${GREEN}New Relic Health Check Creator${NC}"
    echo ""
    
    collect_credentials
    
    local integration_name=$(create_newrelic_integration)
    if [ $? -eq 0 ]; then
        create_health_check "$integration_name"
    fi
    
    echo ""
    echo -e "${GREEN}✅ New Relic health check setup complete${NC}"
    echo -e "${BLUE}View: https://app.gremlin.com/reliability/status-checks${NC}"
}

main "$@"
