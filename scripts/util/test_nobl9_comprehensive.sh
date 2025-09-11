#!/bin/bash

# Comprehensive Nobl9 SLO Endpoint Test Script
# This script tries all possible combinations to access the Nobl9 SLO endpoint

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Nobl9 credentials and settings
CLIENT_ID="0oapcehib7aBVukir417"
CLIENT_SECRET="pwLeeaQ3Sc5JE4N18nQMQFNIUVakxf0L-juN7Nj7ZUxU9TmSteLe07g6u5e2l6KR"
BASE64_CREDS=$(echo -n "${CLIENT_ID}:${CLIENT_SECRET}" | base64)
ORG_NAME="gremlin-vfdjkMGgZxkR"
SLO_NAME="hostcpu-alert"
PROJECT="default"

# Predefined access token (in case we want to skip token generation)
PREDEFINED_TOKEN="eyJraWQiOiJwYjh1T0Vsc1dWZ1ZkTV8tUm1HbWhJRUtvOEozVVZNQWtNbldQU2xYTkcwIiwiYWxnIjoiUlMyNTYifQ.eyJ2ZXIiOjEsImp0aSI6IkFULlZLRlRwR2VueDdtNGdkQWhKcV9rOTVnVW5MWmRpMWZ4cVFmT0RrcndXNVkiLCJpc3MiOiJodHRwczovL2FjY291bnRzLm5vYmw5LmNvbS9vYXV0aDIvYXVzZWc5a2llZ1dLRXRKWkM0MTYiLCJhdWQiOiJhcGk6Ly9kZWZhdWx0IiwiaWF0IjoxNzU0NTI3OTMwLCJleHAiOjE3NTQ1MzE1MzAsImNpZCI6IjBvYXBjZWhpYjdhQlZ1a2lyNDE3Iiwic2NwIjpbIm0ybSJdLCJhZ2VudFByb2ZpbGUiOiIiLCJzdWIiOiIwb2FwY2VoaWI3YUJWdWtpcjQxNyIsIm0ybVByb2ZpbGUiOnsidXNlciI6InNlYW4ud2lsZXlAZ3JlbWxpbi5jb20iLCJvcmdhbml6YXRpb24iOiJncmVtbGluLXZmZGprTUdnWnhrUiIsImVudmlyb25tZW50IjoiYXBwLm5vYmw5LmNvbSJ9fQ.NhgmSRCN97SMPbhbqUtBG_CyeJ5JTvbLPOBACJmaVsRpAhVR8UgZI_8C4zbMND4YHPj6X4pZvjoAg4QhpxgXqTvjLYGbKRe_-ZROI_u1Wc9_RPEsrMqbrHTF8-f-Tfxgf1yWm9PxqHmAA3sdVxx8WYMnzwkRQO4DemGp41YDM05JMOsHRo2CcBunFCkoW6yWLWdgbQoqj35fOWXSL1XnF5zlUsZ-Reva4q1CykmN-ToJIfT2P15376AWowX9rliMywxGOK-t4HiHdomzAjiRm6vmhLzZnQ-stMirNg5q3KFOxHgT_cdtNDWTWziSziPzWMRUDwPT5mA789QIlD-Y8w"

echo -e "${BLUE}=== Comprehensive Nobl9 SLO Endpoint Test Script ===${NC}"
echo -e "${BLUE}Organization: ${ORG_NAME}${NC}"
echo -e "${BLUE}SLO Name: ${SLO_NAME}${NC}"
echo -e "${BLUE}Project: ${PROJECT}${NC}"

# Step 1: Generate a fresh access token
echo -e "\n${YELLOW}Step 1: Generating a fresh Nobl9 access token${NC}"
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
else
  echo -e "${RED}Failed to generate access token${NC}"
  echo -e "Response: ${token_response}"
  echo -e "${YELLOW}Using predefined token instead${NC}"
  ACCESS_TOKEN="${PREDEFINED_TOKEN}"
fi

# Define arrays for our test combinations
HTTP_METHODS=("GET" "POST")
TOKENS=("${ACCESS_TOKEN}" "${PREDEFINED_TOKEN}")
ENDPOINTS=(
  "/api/v2/slos/${SLO_NAME}"
  "/api/v2/slos/${SLO_NAME}/status"
  "/api/v2/slos/${SLO_NAME}/state"
  "/api/v2/slos/${SLO_NAME}/health"
  "/api/v1/slos/${SLO_NAME}"
  "/api/v1/slos/${SLO_NAME}/status"
  "/api/v1/slos/${SLO_NAME}/state"
  "/api/v1/slos/${SLO_NAME}/health"
  "/api/v2/projects/${PROJECT}/slos/${SLO_NAME}"
  "/api/v2/projects/${PROJECT}/slos/${SLO_NAME}/status"
)
ACCEPT_HEADERS=(
  "application/json"
  "application/json; version=v1alpha"
  "application/json; version=v2"
)
PROJECT_VARIATIONS=(
  "header"      # Use Project header
  "query"       # Use project query parameter
  "none"        # Don't specify project
)

# Step 2: Test all combinations
echo -e "\n${YELLOW}Step 2: Testing all combinations to access the SLO endpoint${NC}"

# Function to test a specific combination
test_combination() {
  local method=$1
  local token=$2
  local endpoint=$3
  local accept=$4
  local project_var=$5
  
  echo -e "\n${BLUE}Testing: ${method} ${endpoint} (Project: ${project_var}, Accept: ${accept})${NC}"
  
  # Build the curl command based on the combination
  curl_cmd="curl -s -w \"\\nHTTP_STATUS:%{http_code}\" -X ${method}"
  
  # Add URL with or without query parameter
  if [ "$project_var" == "query" ]; then
    curl_cmd+=" \"https://app.nobl9.com${endpoint}?project=${PROJECT}\""
  else
    curl_cmd+=" \"https://app.nobl9.com${endpoint}\""
  fi
  
  # Add headers
  curl_cmd+=" -H \"Authorization: Bearer ${token}\""
  curl_cmd+=" -H \"Organization: ${ORG_NAME}\""
  curl_cmd+=" -H \"Accept: ${accept}\""
  
  # Add Project header if specified
  if [ "$project_var" == "header" ]; then
    curl_cmd+=" -H \"Project: ${PROJECT}\""
  fi
  
  # Execute the curl command
  response=$(eval $curl_cmd)
  
  # Parse response
  http_status=$(echo "$response" | grep "HTTP_STATUS" | cut -d':' -f2)
  body=$(echo "$response" | sed '/HTTP_STATUS/d')
  
  echo -e "Status code: ${http_status}"
  echo -e "Response body: ${body}"
  
  # Check if we got a successful response
  if [[ "$http_status" == "200" ]]; then
    echo -e "${GREEN}SUCCESS! Got 200 response${NC}"
    
    # Save the successful configuration
    echo -e "\n${GREEN}=== SUCCESSFUL CONFIGURATION ===${NC}" >> successful_configs.txt
    echo -e "Method: ${method}" >> successful_configs.txt
    echo -e "Endpoint: https://app.nobl9.com${endpoint}" >> successful_configs.txt
    if [ "$project_var" == "query" ]; then
      echo -e "URL: https://app.nobl9.com${endpoint}?project=${PROJECT}" >> successful_configs.txt
    else
      echo -e "URL: https://app.nobl9.com${endpoint}" >> successful_configs.txt
    fi
    echo -e "Authorization: Bearer ${token}" >> successful_configs.txt
    echo -e "Organization: ${ORG_NAME}" >> successful_configs.txt
    echo -e "Accept: ${accept}" >> successful_configs.txt
    if [ "$project_var" == "header" ]; then
      echo -e "Project: ${PROJECT}" >> successful_configs.txt
    fi
    echo -e "Response: ${body}" >> successful_configs.txt
    echo -e "=========================================" >> successful_configs.txt
    
    # Print success message
    echo -e "${GREEN}Configuration saved to successful_configs.txt${NC}"
    
    # Check if response contains status field
    if echo "$body" | grep -q '"status"'; then
      STATUS=$(echo "$body" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
      echo -e "${GREEN}Found status field: ${STATUS}${NC}"
    fi
  fi
}

# Clear previous results
rm -f successful_configs.txt

# Test all combinations
for method in "${HTTP_METHODS[@]}"; do
  for token in "${TOKENS[@]}"; do
    for endpoint in "${ENDPOINTS[@]}"; do
      for accept in "${ACCEPT_HEADERS[@]}"; do
        for project_var in "${PROJECT_VARIATIONS[@]}"; do
          test_combination "$method" "$token" "$endpoint" "$accept" "$project_var"
        done
      done
    done
  done
done

# Step 3: Summarize results
echo -e "\n${YELLOW}Step 3: Summarizing results${NC}"

if [ -f successful_configs.txt ]; then
  echo -e "${GREEN}Found successful configurations!${NC}"
  echo -e "See successful_configs.txt for details"
  
  # Count successful configurations
  config_count=$(grep -c "=== SUCCESSFUL CONFIGURATION ===" successful_configs.txt)
  echo -e "${GREEN}Total successful configurations: ${config_count}${NC}"
  
  # Display the first successful configuration
  echo -e "\n${BLUE}First successful configuration:${NC}"
  sed -n '1,/=========================================/ p' successful_configs.txt
else
  echo -e "${RED}No successful configurations found${NC}"
  echo -e "${RED}Please check the Nobl9 API documentation for the correct endpoint${NC}"
fi
