#!/bin/bash
#
# Find Prometheus Authentication ID from Gremlin Health Checks
# Use this script to discover existing authentication IDs
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Finding Prometheus Authentication ID${NC}"
echo ""

echo -e "${YELLOW}To find your authentication ID, you have two options:${NC}"
echo ""

echo -e "${BLUE}Option 1: Use your working Bearer token${NC}"
echo "Run this curl command with your current Bearer token:"
echo ""
echo "curl -X 'GET' \\"
echo "  'https://api.gremlin.com/v1/status-checks?teamId=438c58ec-03db-47ac-8c58-ec03db67ac42' \\"
echo "  -H 'Authorization: Bearer YOUR_CURRENT_BEARER_TOKEN' \\"
echo "  -H 'accept: application/json' | jq -r '.[] | select(.authenticationId != null) | \"Name: \\(.name) | Auth ID: \\(.authenticationId)\"'"
echo ""

echo -e "${BLUE}Option 2: Manual UI Method (Recommended)${NC}"
echo "1. Go to https://app.gremlin.com/health-checks/list"
echo "2. Look for any existing Prometheus or Grafana health checks"
echo "3. Click 'Edit' on one that has authentication configured"
echo "4. Open browser Developer Tools (F12) → Network tab"
echo "5. Look for API requests containing authentication IDs"
echo ""

echo -e "${BLUE}Option 3: Create New Authentication${NC}"
echo "1. Go to https://app.gremlin.com/health-checks/list"
echo "2. Click '+ Health Check' → Select 'Prometheus'"
echo "3. Enter URL: http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query?query=up"
echo "4. Under Authentication, create new or select existing"
echo "5. For Prometheus, typically use 'No Authentication' or 'Bearer Token'"
echo "6. Save and note the authentication ID from the response"
echo ""

echo -e "${YELLOW}Common Prometheus Authentication Types:${NC}"
echo "• No Authentication (most common for internal Prometheus)"
echo "• Bearer Token (if Prometheus has auth enabled)"
echo "• Basic Auth (username/password)"
echo ""

echo -e "${GREEN}Once you have the authentication ID, update your scripts:${NC}"
echo "export PROMETHEUS_AUTH_ID=\"your-auth-id-here\""
echo "./monitoring/gremlin/create_prometheus_health_checks_working.sh --auth-id \$PROMETHEUS_AUTH_ID"
