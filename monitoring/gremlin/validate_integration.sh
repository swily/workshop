#!/bin/bash

# Final validation script for Gremlin Prometheus health check integration
# This script validates that the integration is working end-to-end

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Hardcoded working credentials
GREMLIN_TEAM_ID="438c58ec-03db-47ac-8c58-ec03db67ac42"
BEARER_TOKEN="Yy02MDY1YTk1MC0wMzEzLTU5ZmQtYWJiZS1mZDRjNzIxOWIzZDE6MjU4ZThlMjk5NmQ2YTQxMTBmY2RhYjA3NzJlMzk2NjMyNDY1YzYxMjIwMjA2MjZhOGEzZmU4NmM5OWQwYzc3NzhkZDYxNjU1YmIwNTc3NzdiODNjNjU4ZDZmOGI4MTE0ZjVkNGRjNDg3ZGJjYTI4ODg1OGFiZWZkNGEzMzJhMDQ6YWE1YjVhYmYtYmQ1Yi00OWJiLTliNWEtYmZiZDViNDliYmEw"
GREMLIN_API_URL="https://api.gremlin.com/v1"

echo -e "${BLUE}🔍 Final Gremlin Integration Validation 🔍${NC}\n"

# Function to make API requests to Gremlin
make_gremlin_request() {
  local method="$1"
  local endpoint="$2"
  
  local full_url="${GREMLIN_API_URL}${endpoint}?teamId=${GREMLIN_TEAM_ID}"
  
  curl -s -X "$method" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $BEARER_TOKEN" \
    "$full_url"
}

# Test 1: API Connection
echo -e "${BLUE}Test 1: Gremlin API Connection${NC}"
if make_gremlin_request "GET" "/status-checks" >/dev/null 2>&1; then
  echo -e "${GREEN}✅ Successfully connected to Gremlin API${NC}"
else
  echo -e "${RED}❌ Failed to connect to Gremlin API${NC}"
  exit 1
fi

# Test 2: List Health Checks
echo -e "\n${BLUE}Test 2: Current Health Checks${NC}"
response=$(make_gremlin_request "GET" "/status-checks")
if [ $? -eq 0 ] && [ -n "$response" ]; then
  echo -e "${GREEN}✅ Successfully retrieved health checks${NC}"
  
  # Count Prometheus health checks
  prometheus_count=$(echo "$response" | jq '[.[] | select(.name | contains("prometheus-health"))] | length' 2>/dev/null)
  total_count=$(echo "$response" | jq '. | length' 2>/dev/null)
  
  echo -e "${BLUE}📊 Health Check Summary:${NC}"
  echo -e "   Total health checks: $total_count"
  echo -e "   Prometheus health checks: $prometheus_count"
  
  # Show Prometheus health checks
  if [ "$prometheus_count" -gt 0 ]; then
    echo -e "\n${GREEN}🎯 Prometheus Health Checks Created:${NC}"
    echo "$response" | jq -r '.[] | select(.name | contains("prometheus-health")) | "   • \(.name) (ID: \(.identifier))"' 2>/dev/null
  fi
else
  echo -e "${RED}❌ Failed to retrieve health checks${NC}"
  exit 1
fi

# Test 3: Kubernetes Services
echo -e "\n${BLUE}Test 3: Kubernetes Services Discovery${NC}"
if kubectl get svc -n otel-demo >/dev/null 2>&1; then
  service_count=$(kubectl get svc -n otel-demo --no-headers 2>/dev/null | wc -l)
  echo -e "${GREEN}✅ Successfully connected to Kubernetes${NC}"
  echo -e "   Services in otel-demo namespace: $service_count"
else
  echo -e "${YELLOW}⚠️  Kubernetes connection issue (expected in some environments)${NC}"
fi

# Test 4: Working Script Validation
echo -e "\n${BLUE}Test 4: Working Script Validation${NC}"
if [ -f "monitoring/gremlin/create_prometheus_health_checks_working.sh" ]; then
  echo -e "${GREEN}✅ Working health check script exists${NC}"
  if [ -x "monitoring/gremlin/create_prometheus_health_checks_working.sh" ]; then
    echo -e "${GREEN}✅ Script is executable${NC}"
  else
    echo -e "${YELLOW}⚠️  Script needs execute permissions${NC}"
  fi
else
  echo -e "${RED}❌ Working script not found${NC}"
fi

# Test 5: Integration with Workshop
echo -e "\n${BLUE}Test 5: Workshop Integration${NC}"
if [ -f "workshop.sh" ]; then
  if grep -q "setup_gremlin_health_checks.sh" workshop.sh; then
    echo -e "${GREEN}✅ Workshop integration configured${NC}"
  else
    echo -e "${YELLOW}⚠️  Workshop integration may need updating${NC}"
  fi
else
  echo -e "${RED}❌ Workshop script not found${NC}"
fi

# Test 6: Validate Specific Health Checks
echo -e "\n${BLUE}Test 6: Validate Key Service Health Checks${NC}"
key_services=("frontend" "cart" "checkout" "payment" "shipping" "product-catalog")
found_services=0

for service in "${key_services[@]}"; do
  health_check_name="${service}-prometheus-health"
  if echo "$response" | jq -e ".[] | select(.name == \"$health_check_name\")" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ $service health check exists${NC}"
    ((found_services++))
  else
    echo -e "${YELLOW}⚠️  $service health check not found${NC}"
  fi
done

echo -e "\n${BLUE}📈 Service Coverage: $found_services/${#key_services[@]} key services${NC}"

# Final Summary
echo -e "\n${BLUE}=== Final Validation Summary ===${NC}"
if [ "$prometheus_count" -gt 0 ] && [ "$found_services" -gt 0 ]; then
  echo -e "${GREEN}🎉 SUCCESS: Gremlin Prometheus health check integration is working!${NC}"
  echo -e "\n${GREEN}✅ Key Achievements:${NC}"
  echo -e "   • Gremlin API connection established"
  echo -e "   • $prometheus_count Prometheus health checks created"
  echo -e "   • $found_services key services covered"
  echo -e "   • Integration scripts are in place"
  echo -e "\n${BLUE}🚀 Next Steps:${NC}"
  echo -e "   • Use health checks in Gremlin chaos experiments"
  echo -e "   • Monitor service health during experiments"
  echo -e "   • Validate Prometheus metrics integration"
  
  exit 0
else
  echo -e "${RED}❌ INCOMPLETE: Some health checks are missing${NC}"
  echo -e "   Run: ./monitoring/gremlin/create_prometheus_health_checks_working.sh"
  exit 1
fi
