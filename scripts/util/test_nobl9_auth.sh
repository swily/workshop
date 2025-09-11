#!/bin/bash

# Nobl9 API Authentication Test Script
# This script tests various authentication methods for Nobl9 API

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

# SLO name
SLO_NAME="hostcpu-alert"

# Test different organization names
ORG_NAMES=("gremlin" "gremlin-vfdjkMGgZxkR" "default" "nobl9" "")

# Test different projects
PROJECTS=("default" "")

echo -e "${BLUE}=== Nobl9 API Authentication Test Script ===${NC}"
echo -e "${BLUE}Testing with client ID: ${CLIENT_ID}${NC}"
echo -e "${BLUE}Base64 credentials: ${BASE64_CREDS}${NC}"

# Step 1: Test token generation with different organization names
echo -e "\n${YELLOW}Step 1: Testing token generation with different organization names${NC}"

for org in "${ORG_NAMES[@]}"; do
  if [ -z "$org" ]; then
    echo -e "\n${YELLOW}Testing without Organization header${NC}"
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
      "https://app.nobl9.com/api/accessToken" \
      -H "Authorization: Basic ${BASE64_CREDS}" \
      -H "Content-Type: application/json")
  else
    echo -e "\n${YELLOW}Testing with Organization: ${org}${NC}"
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
      "https://app.nobl9.com/api/accessToken" \
      -H "Authorization: Basic ${BASE64_CREDS}" \
      -H "Content-Type: application/json" \
      -H "Organization: ${org}")
  fi
  
  http_status=$(echo "$response" | grep "HTTP_STATUS" | cut -d':' -f2)
  body=$(echo "$response" | sed '/HTTP_STATUS/d')
  
  echo -e "Status code: ${http_status}"
  echo -e "Response body: ${body}"
  
  # Extract token if successful
  if [[ "$http_status" == "200" ]]; then
    echo -e "${GREEN}Token generation successful with org: ${org}${NC}"
    ACCESS_TOKEN=$(echo "$body" | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4)
    SUCCESSFUL_ORG="$org"
    echo -e "Access token: ${ACCESS_TOKEN}"
    break
  else
    echo -e "${RED}Token generation failed with org: ${org}${NC}"
  fi
done

# If we couldn't get a token, try with the organization name in lowercase
if [ -z "$ACCESS_TOKEN" ]; then
  echo -e "\n${YELLOW}Trying with lowercase organization names${NC}"
  for org in "${ORG_NAMES[@]}"; do
    if [ -n "$org" ]; then
      org_lower=$(echo "$org" | tr '[:upper:]' '[:lower:]')
      echo -e "\n${YELLOW}Testing with Organization: ${org_lower}${NC}"
      response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
        "https://app.nobl9.com/api/accessToken" \
        -H "Authorization: Basic ${BASE64_CREDS}" \
        -H "Content-Type: application/json" \
        -H "Organization: ${org_lower}")
      
      http_status=$(echo "$response" | grep "HTTP_STATUS" | cut -d':' -f2)
      body=$(echo "$response" | sed '/HTTP_STATUS/d')
      
      echo -e "Status code: ${http_status}"
      echo -e "Response body: ${body}"
      
      if [[ "$http_status" == "200" ]]; then
        echo -e "${GREEN}Token generation successful with org: ${org_lower}${NC}"
        ACCESS_TOKEN=$(echo "$body" | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4)
        SUCCESSFUL_ORG="$org_lower"
        echo -e "Access token: ${ACCESS_TOKEN}"
        break
      else
        echo -e "${RED}Token generation failed with org: ${org_lower}${NC}"
      fi
    fi
  done
fi

# If we still don't have a token, try with common organization names
if [ -z "$ACCESS_TOKEN" ]; then
  echo -e "\n${YELLOW}Trying with common organization names${NC}"
  COMMON_ORGS=("demo" "test" "development" "production" "staging" "workshop")
  
  for org in "${COMMON_ORGS[@]}"; do
    echo -e "\n${YELLOW}Testing with Organization: ${org}${NC}"
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
      "https://app.nobl9.com/api/accessToken" \
      -H "Authorization: Basic ${BASE64_CREDS}" \
      -H "Content-Type: application/json" \
      -H "Organization: ${org}")
    
    http_status=$(echo "$response" | grep "HTTP_STATUS" | cut -d':' -f2)
    body=$(echo "$response" | sed '/HTTP_STATUS/d')
    
    echo -e "Status code: ${http_status}"
    echo -e "Response body: ${body}"
    
    if [[ "$http_status" == "200" ]]; then
      echo -e "${GREEN}Token generation successful with org: ${org}${NC}"
      ACCESS_TOKEN=$(echo "$body" | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4)
      SUCCESSFUL_ORG="$org"
      echo -e "Access token: ${ACCESS_TOKEN}"
      break
    else
      echo -e "${RED}Token generation failed with org: ${org}${NC}"
    fi
  done
fi

# Step 2: If we have a token, test SLO endpoint with different projects
if [ -n "$ACCESS_TOKEN" ]; then
  echo -e "\n${YELLOW}Step 2: Testing SLO endpoint with access token${NC}"
  
  for project in "${PROJECTS[@]}"; do
    if [ -z "$project" ]; then
      echo -e "\n${YELLOW}Testing without project parameter${NC}"
      response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X GET \
        "https://app.nobl9.com/api/v2/slos/${SLO_NAME}" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Organization: ${SUCCESSFUL_ORG}")
    else
      echo -e "\n${YELLOW}Testing with project: ${project}${NC}"
      response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X GET \
        "https://app.nobl9.com/api/v2/slos/${SLO_NAME}?project=${project}" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Organization: ${SUCCESSFUL_ORG}")
    fi
    
    http_status=$(echo "$response" | grep "HTTP_STATUS" | cut -d':' -f2)
    body=$(echo "$response" | sed '/HTTP_STATUS/d')
    
    echo -e "Status code: ${http_status}"
    echo -e "Response body: ${body}"
    
    if [[ "$http_status" == "200" ]]; then
      echo -e "${GREEN}SLO endpoint successful with project: ${project}${NC}"
      SUCCESSFUL_PROJECT="$project"
      SUCCESSFUL_RESPONSE="$body"
      break
    else
      echo -e "${RED}SLO endpoint failed with project: ${project}${NC}"
    fi
  done
  
  # If we couldn't access the SLO with the provided name, try listing all SLOs
  if [[ "$http_status" != "200" ]]; then
    echo -e "\n${YELLOW}Trying to list all SLOs${NC}"
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X GET \
      "https://app.nobl9.com/api/v2/slos" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Organization: ${SUCCESSFUL_ORG}")
    
    http_status=$(echo "$response" | grep "HTTP_STATUS" | cut -d':' -f2)
    body=$(echo "$response" | sed '/HTTP_STATUS/d')
    
    echo -e "Status code: ${http_status}"
    echo -e "Response body: ${body}"
    
    if [[ "$http_status" == "200" ]]; then
      echo -e "${GREEN}Successfully listed all SLOs${NC}"
      # Extract SLO names from the response
      SLO_NAMES=$(echo "$body" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
      echo -e "Available SLOs: ${SLO_NAMES}"
      
      # Try each SLO name
      for slo in $SLO_NAMES; do
        echo -e "\n${YELLOW}Testing with SLO name: ${slo}${NC}"
        response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X GET \
          "https://app.nobl9.com/api/v2/slos/${slo}?project=${SUCCESSFUL_PROJECT}" \
          -H "Authorization: Bearer ${ACCESS_TOKEN}" \
          -H "Organization: ${SUCCESSFUL_ORG}")
        
        http_status=$(echo "$response" | grep "HTTP_STATUS" | cut -d':' -f2)
        body=$(echo "$response" | sed '/HTTP_STATUS/d')
        
        echo -e "Status code: ${http_status}"
        echo -e "Response body: ${body}"
        
        if [[ "$http_status" == "200" ]]; then
          echo -e "${GREEN}SLO endpoint successful with SLO name: ${slo}${NC}"
          SUCCESSFUL_SLO="$slo"
          SUCCESSFUL_RESPONSE="$body"
          break
        else
          echo -e "${RED}SLO endpoint failed with SLO name: ${slo}${NC}"
        fi
      done
    else
      echo -e "${RED}Failed to list SLOs${NC}"
    fi
  fi
else
  echo -e "\n${RED}Could not generate access token with any organization name${NC}"
  echo -e "${RED}Cannot proceed to testing SLO endpoint${NC}"
fi

# Summary
echo -e "\n${BLUE}=== Test Summary ===${NC}"
if [ -n "$ACCESS_TOKEN" ]; then
  echo -e "${GREEN}Successfully generated access token with organization: ${SUCCESSFUL_ORG}${NC}"
  echo -e "Access token: ${ACCESS_TOKEN}"
  
  if [ -n "$SUCCESSFUL_RESPONSE" ]; then
    if [ -n "$SUCCESSFUL_SLO" ]; then
      echo -e "${GREEN}Successfully accessed SLO: ${SUCCESSFUL_SLO}${NC}"
    else
      echo -e "${GREEN}Successfully accessed SLO: ${SLO_NAME}${NC}"
    fi
    
    if [ -n "$SUCCESSFUL_PROJECT" ]; then
      echo -e "${GREEN}With project: ${SUCCESSFUL_PROJECT}${NC}"
    else
      echo -e "${GREEN}Without project parameter${NC}"
    fi
    
    echo -e "\n${BLUE}For Gremlin health check, use:${NC}"
    echo -e "1. Authentication Endpoint URL: https://app.nobl9.com/api/accessToken"
    echo -e "2. Authentication Headers:"
    echo -e "   - Authorization: Basic ${BASE64_CREDS}"
    echo -e "   - Content-Type: application/json"
    echo -e "   - Organization: ${SUCCESSFUL_ORG}"
    
    if [ -n "$SUCCESSFUL_SLO" ]; then
      if [ -n "$SUCCESSFUL_PROJECT" ]; then
        echo -e "3. Monitor URL: https://app.nobl9.com/api/v2/slos/${SUCCESSFUL_SLO}?project=${SUCCESSFUL_PROJECT}"
      else
        echo -e "3. Monitor URL: https://app.nobl9.com/api/v2/slos/${SUCCESSFUL_SLO}"
      fi
    else
      if [ -n "$SUCCESSFUL_PROJECT" ]; then
        echo -e "3. Monitor URL: https://app.nobl9.com/api/v2/slos/${SLO_NAME}?project=${SUCCESSFUL_PROJECT}"
      else
        echo -e "3. Monitor URL: https://app.nobl9.com/api/v2/slos/${SLO_NAME}"
      fi
    fi
  else
    echo -e "${RED}Could not access any SLO endpoint${NC}"
  fi
else
  echo -e "${RED}Could not generate access token with any organization name${NC}"
  echo -e "${RED}Possible issues:${NC}"
  echo -e "1. Invalid client credentials"
  echo -e "2. Unknown organization name"
  echo -e "3. API rate limiting"
  echo -e "4. Network connectivity issues"
fi
