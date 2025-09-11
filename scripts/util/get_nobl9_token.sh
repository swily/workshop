#!/bin/bash

# Nobl9 API Token Generation and SLO Status Check
# This script generates a Nobl9 access token and checks SLO status

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
ORG_NAME="gremlin"
SLO_NAME="hostcpu-alert"
PROJECT="default"

echo -e "${BLUE}=== Nobl9 API Token Generation and SLO Status Check ===${NC}"
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
  
  # Step 2: Check SLO status
  echo -e "\n${YELLOW}Step 2: Checking SLO status${NC}"
  slo_response=$(curl -s -X GET \
    "https://app.nobl9.com/api/v2/slos/${SLO_NAME}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Organization: ${ORG_NAME}" \
    -H "Project: ${PROJECT}")
  
  echo -e "SLO response: ${slo_response}"
  
  # Check if we got a valid SLO response
  if echo "$slo_response" | grep -q "status"; then
    SLO_STATUS=$(echo "$slo_response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    echo -e "${GREEN}Successfully retrieved SLO status: ${SLO_STATUS}${NC}"
  else
    echo -e "${RED}Failed to retrieve SLO status${NC}"
    echo -e "Response: ${slo_response}"
  fi
  
  # Step 3: Generate Gremlin health check configuration
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
  echo -e "   https://app.nobl9.com/api/v2/slos/${SLO_NAME}"
  echo -e "   Header Name: Project"
  echo -e "   Header Value: ${PROJECT}"
  echo -e "\n4. Success Evaluation:"
  echo -e "   Healthy status code: 200"
  echo -e "   JSON Path: $.status"
  echo -e "   Operator: equals"
  echo -e "   Value: HEALTHY"
  echo -e "\n5. Polling Interval: 30 seconds"
else
  echo -e "${RED}Failed to generate access token${NC}"
  echo -e "Response: ${token_response}"
  
  # Try with organization ID instead
  echo -e "\n${YELLOW}Trying with organization ID instead${NC}"
  token_response=$(curl -s -X POST \
    "https://app.nobl9.com/api/accessToken" \
    -H "Authorization: Basic ${BASE64_CREDS}" \
    -H "Content-Type: application/json" \
    -H "Organization: gremlin-vfdjkMGgZxkR" \
    -H "Accept: application/json; version=v1alpha")
  
  echo -e "Token response: ${token_response}"
  
  if echo "$token_response" | grep -q "access_token"; then
    ACCESS_TOKEN=$(echo "$token_response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
    echo -e "${GREEN}Successfully generated access token with organization ID${NC}"
    echo -e "Access token: ${ACCESS_TOKEN}"
    
    # Update the organization name for future requests
    ORG_NAME="gremlin-vfdjkMGgZxkR"
    
    # Step 2: Check SLO status
    echo -e "\n${YELLOW}Step 2: Checking SLO status${NC}"
    slo_response=$(curl -s -X GET \
      "https://app.nobl9.com/api/v2/slos/${SLO_NAME}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Organization: ${ORG_NAME}" \
      -H "Project: ${PROJECT}")
    
    echo -e "SLO response: ${slo_response}"
    
    # Check if we got a valid SLO response
    if echo "$slo_response" | grep -q "status"; then
      SLO_STATUS=$(echo "$slo_response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
      echo -e "${GREEN}Successfully retrieved SLO status: ${SLO_STATUS}${NC}"
    else
      echo -e "${RED}Failed to retrieve SLO status${NC}"
      echo -e "Response: ${slo_response}"
    fi
    
    # Step 3: Generate Gremlin health check configuration
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
    echo -e "   https://app.nobl9.com/api/v2/slos/${SLO_NAME}"
    echo -e "   Header Name: Project"
    echo -e "   Header Value: ${PROJECT}"
    echo -e "\n4. Success Evaluation:"
    echo -e "   Healthy status code: 200"
    echo -e "   JSON Path: $.status"
    echo -e "   Operator: equals"
    echo -e "   Value: HEALTHY"
    echo -e "\n5. Polling Interval: 30 seconds"
  else
    echo -e "${RED}Failed to generate access token with organization ID${NC}"
    echo -e "Response: ${token_response}"
  fi
fi
