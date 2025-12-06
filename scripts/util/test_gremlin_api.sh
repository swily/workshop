#!/bin/bash

# Test Gremlin API - Create a simple test health check

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Testing Gremlin API with simple health check${NC}"
echo ""

# Check credentials
if [ -z "${GREMLIN_TEAM_ID:-}" ]; then
    echo -e "${RED}❌ GREMLIN_TEAM_ID not set${NC}"
    exit 1
fi

if [ -z "${GREMLIN_API_KEY:-}" ]; then
    echo -e "${RED}❌ GREMLIN_API_KEY not set${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Credentials found${NC}"
echo "Team ID: ${GREMLIN_TEAM_ID:0:8}..."
echo "API Key: ${GREMLIN_API_KEY:0:8}..."
echo ""

# Create test integration
echo -e "${BLUE}1. Creating test integration...${NC}"
TEST_INTEGRATION=$(cat << 'EOF'
{
  "name": "test-integration-1002",
  "description": "Test integration for API verification",
  "type": "CUSTOM",
  "privateNetwork": false,
  "lastAuthenticationStatus": "AUTHENTICATED",
  "url": "https://httpbin.org/status/200",
  "headers": {}
}
EOF
)

echo "Request:"
echo "$TEST_INTEGRATION" | jq .
echo ""

INTEGRATION_RESPONSE=$(curl -s -X POST "https://api.gremlin.com/v1/external-integrations/status-check?teamId=$GREMLIN_TEAM_ID&type=CUSTOM" \
    -H "Authorization: Key $GREMLIN_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$TEST_INTEGRATION")

echo "Response:"
echo "$INTEGRATION_RESPONSE" | jq .
echo ""

INTEGRATION_NAME=$(echo "$INTEGRATION_RESPONSE" | jq -r '.name // empty')
if [ -n "$INTEGRATION_NAME" ] && [ "$INTEGRATION_NAME" != "null" ]; then
    echo -e "${GREEN}✅ Integration created: $INTEGRATION_NAME${NC}"
else
    echo -e "${RED}❌ Failed to create integration${NC}"
    exit 1
fi

echo ""

# Create test health check
echo -e "${BLUE}2. Creating test health check...${NC}"
TEST_HEALTH_CHECK=$(cat << EOF
{
  "name": "test-health-1002",
  "endpointType": "http",
  "endpointConfiguration": {
    "url": "https://httpbin.org/status/200",
    "method": "GET",
    "headers": {}
  },
  "evaluationConfiguration": {
    "okStatusCodes": [200]
  },
  "teamExternalIntegration": {
    "observabilityToolType": "CUSTOM",
    "name": "$INTEGRATION_NAME"
  },
  "pollingInterval": 60
}
EOF
)

echo "Request:"
echo "$TEST_HEALTH_CHECK" | jq .
echo ""

HEALTH_CHECK_RESPONSE=$(curl -s -X POST "https://api.gremlin.com/v1/status-checks?teamId=$GREMLIN_TEAM_ID" \
    -H "Authorization: Key $GREMLIN_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$TEST_HEALTH_CHECK")

echo "Response:"
echo "$HEALTH_CHECK_RESPONSE"
echo ""

# API returns plain UUID string on success, not JSON
if [[ "$HEALTH_CHECK_RESPONSE" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo -e "${GREEN}✅ Health check created: $HEALTH_CHECK_RESPONSE${NC}"
    echo ""
    echo -e "${BLUE}Check Gremlin UI:${NC}"
    echo "  Integration: test-integration-1002"
    echo "  Health Check: test-health-1002"
    echo "  ID: $HEALTH_CHECK_RESPONSE"
    echo "  URL: https://app.gremlin.com/reliability/status-checks"
else
    echo -e "${RED}❌ Failed to create health check${NC}"
    echo -e "${RED}Response: $HEALTH_CHECK_RESPONSE${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Test complete - check Gremlin UI for 'test-health-1002'${NC}"
