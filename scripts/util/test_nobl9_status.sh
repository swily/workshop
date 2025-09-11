#!/bin/bash

# Nobl9 API SLO Status Test Script
# This script tests different SLO status endpoints to find the correct one

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Nobl9 credentials
CLIENT_ID="0oapcehib7aBVukir417"
CLIENT_SECRET="pwLeeaQ3Sc5JE4N18nQMQFNIUVakxf0L-juN7Nj7ZUxU9TmSteLe07g6u5e2l6KR"
BASE64_CREDS=$(echo -n "${CLIENT_ID}:${CLIENT_SECRET}" | base64)
ORG_NAME="gremlin-vfdjkMGgZxkR"
SLO_NAME="hostcpu-alert"
PROJECT="default"

echo -e "${BLUE}=== Nobl9 API SLO Status Test Script ===${NC}"
echo -e "${BLUE}Organization: ${ORG_NAME}${NC}"
echo -e "${BLUE}SLO Name: ${SLO_NAME}${NC}"
echo -e "${BLUE}Project: ${PROJECT}${NC}"

# Step 1: Generate access token
echo -e "\n${YELLOW}Step 1: Generating Nobl9 access token${NC}"
token_response=$(curl -s -X POST \
  "https://app.nobl9.com/api/accessToken" \
  -H "Authorization: Basic ${BASE64_CREDS}" \
  -H "Content-Type: application/json" \
  -H "Organization: ${ORG_NAME}" \
  -H "Accept: application/json; version=v1alpha")

echo -e "Token response: ${token_response}"

# Check if we got a token
if echo "$token_response" | grep -q "access_token"; then
  ACCESS_TOKEN=$(echo "$token_response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
  echo -e "${GREEN}Successfully generated access token${NC}"
  echo -e "Access token: ${ACCESS_TOKEN}"
  
  # Step 2: Test different SLO status endpoints
  echo -e "\n${YELLOW}Step 2: Testing different SLO status endpoints${NC}"
  
  # Array of endpoint patterns to try
  ENDPOINTS=(
    "/api/v2/slos/${SLO_NAME}"
    "/api/v2/slos/${SLO_NAME}/status"
    "/api/v2/slos/${SLO_NAME}/state"
    "/api/v2/slos/${SLO_NAME}/health"
    "/api/v1/slos/${SLO_NAME}/status"
    "/api/v1/slos/${SLO_NAME}"
    "/api/v2/projects/${PROJECT}/slos/${SLO_NAME}/status"
    "/api/v2/projects/${PROJECT}/slos/${SLO_NAME}"
  )
  
  # Try each endpoint
  for endpoint in "${ENDPOINTS[@]}"; do
    echo -e "\n${BLUE}Testing endpoint: ${endpoint}${NC}"
    
    # Try with Project header
    echo -e "${YELLOW}With Project header:${NC}"
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X GET \
      "https://app.nobl9.com${endpoint}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Organization: ${ORG_NAME}" \
      -H "Project: ${PROJECT}")
    
    http_status=$(echo "$response" | grep "HTTP_STATUS" | cut -d':' -f2)
    body=$(echo "$response" | sed '/HTTP_STATUS/d')
    
    echo -e "Status code: ${http_status}"
    echo -e "Response body: ${body}"
    
    # Check if response contains status field
    if [[ "$http_status" == "200" ]]; then
      if echo "$body" | grep -q '"status"'; then
        echo -e "${GREEN}Found status field in response!${NC}"
        STATUS=$(echo "$body" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        echo -e "${GREEN}SLO Status: ${STATUS}${NC}"
        
        # Save the successful endpoint and configuration
        SUCCESSFUL_ENDPOINT="https://app.nobl9.com${endpoint}"
        break
      else
        echo -e "${YELLOW}No status field in response${NC}"
      fi
    fi
    
    # Try without Project header
    echo -e "${YELLOW}Without Project header:${NC}"
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X GET \
      "https://app.nobl9.com${endpoint}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Organization: ${ORG_NAME}")
    
    http_status=$(echo "$response" | grep "HTTP_STATUS" | cut -d':' -f2)
    body=$(echo "$response" | sed '/HTTP_STATUS/d')
    
    echo -e "Status code: ${http_status}"
    echo -e "Response body: ${body}"
    
    # Check if response contains status field
    if [[ "$http_status" == "200" ]]; then
      if echo "$body" | grep -q '"status"'; then
        echo -e "${GREEN}Found status field in response!${NC}"
        STATUS=$(echo "$body" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        echo -e "${GREEN}SLO Status: ${STATUS}${NC}"
        
        # Save the successful endpoint and configuration
        SUCCESSFUL_ENDPOINT="https://app.nobl9.com${endpoint}"
        USE_PROJECT_HEADER=false
        break
      else
        echo -e "${YELLOW}No status field in response${NC}"
      fi
    fi
    
    # Try with project as query parameter
    echo -e "${YELLOW}With project as query parameter:${NC}"
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X GET \
      "https://app.nobl9.com${endpoint}?project=${PROJECT}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Organization: ${ORG_NAME}")
    
    http_status=$(echo "$response" | grep "HTTP_STATUS" | cut -d':' -f2)
    body=$(echo "$response" | sed '/HTTP_STATUS/d')
    
    echo -e "Status code: ${http_status}"
    echo -e "Response body: ${body}"
    
    # Check if response contains status field
    if [[ "$http_status" == "200" ]]; then
      if echo "$body" | grep -q '"status"'; then
        echo -e "${GREEN}Found status field in response!${NC}"
        STATUS=$(echo "$body" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        echo -e "${GREEN}SLO Status: ${STATUS}${NC}"
        
        # Save the successful endpoint and configuration
        SUCCESSFUL_ENDPOINT="https://app.nobl9.com${endpoint}?project=${PROJECT}"
        USE_PROJECT_HEADER=false
        USE_PROJECT_QUERY=true
        break
      else
        echo -e "${YELLOW}No status field in response${NC}"
      fi
    fi
  done
  
  # Step 3: Generate Gremlin health check configuration
  if [ -n "$SUCCESSFUL_ENDPOINT" ]; then
    echo -e "\n${BLUE}=== Gremlin Health Check Configuration ===${NC}"
    echo -e "1. Authentication Endpoint URL:"
    echo -e "   https://app.nobl9.com/api/accessToken"
    echo -e "\n2. Authentication Headers:"
    echo -e "   Header Name: Authorization"
    echo -e "   Header Value: Basic ${BASE64_CREDS}"
    echo -e "   Header Name: Content-Type"
    echo -e "   Header Value: application/json"
    echo -e "   Header Name: Organization"
    echo -e "   Header Value: ${ORG_NAME}"
    echo -e "   Header Name: Accept"
    echo -e "   Header Value: application/json; version=v1alpha"
    echo -e "\n3. Monitor URL (GET method):"
    echo -e "   ${SUCCESSFUL_ENDPOINT}"
    
    if [ "$USE_PROJECT_HEADER" = true ]; then
      echo -e "   Header Name: Project"
      echo -e "   Header Value: ${PROJECT}"
    fi
    
    echo -e "\n4. Success Evaluation:"
    echo -e "   Healthy status code: 200"
    echo -e "   JSON Path: $.status"
    echo -e "   Operator: equals"
    echo -e "   Value: HEALTHY"
    echo -e "\n5. Polling Interval: 30 seconds"
  else
    echo -e "\n${RED}Could not find a valid SLO status endpoint${NC}"
    echo -e "${RED}Please check the Nobl9 API documentation for the correct endpoint${NC}"
  fi
else
  echo -e "${RED}Failed to generate access token${NC}"
  echo -e "Response: ${token_response}"
fi
