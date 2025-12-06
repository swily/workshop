#!/bin/bash

# New Relic API Key Generation Script
# This script generates a New Relic User API key for monitoring and alerting
# It uses the New Relic GraphQL API to create API keys

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NEW_RELIC_LICENSE_KEY="${NEW_RELIC_LICENSE_KEY:-}"
NEW_RELIC_ACCOUNT_ID="${NEW_RELIC_ACCOUNT_ID:-}"
API_KEY_NAME="gremlin-health-check-$(date +%s)"
API_KEY_TYPE="USER"  # USER or INGEST

# Function to display script usage
usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  --license-key KEY         New Relic License Key (required)"
  echo "  --account-id ID           New Relic Account ID (required)"
  echo "  --api-key-name NAME       Name for the API key (default: gremlin-health-check-timestamp)"
  echo "  --api-key-type TYPE       Type of API key (USER|INGEST, default: USER)"
  echo "  --help                    Display this help message"
  echo ""
  echo "Examples:"
  echo "  $0 --license-key NRAK-... --account-id 1234567"
  echo "  $0 --license-key NRAK-... --account-id 1234567 --api-key-name my-gremlin-key"
  exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --license-key)
      NEW_RELIC_LICENSE_KEY="$2"
      shift 2
      ;;
    --account-id)
      NEW_RELIC_ACCOUNT_ID="$2"
      shift 2
      ;;
    --api-key-name)
      API_KEY_NAME="$2"
      shift 2
      ;;
    --api-key-type)
      API_KEY_TYPE="$2"
      shift 2
      ;;
    --help)
      usage
      ;;
    *)
      echo -e "${RED}Error: Unknown option: $1${NC}"
      usage
      ;;
  esac
done

# Validate required parameters
if [ -z "$NEW_RELIC_LICENSE_KEY" ]; then
  echo -e "${RED}Error: New Relic License Key is required${NC}"
  echo -e "${YELLOW}You can find your license key in New Relic One: Account settings > API keys${NC}"
  usage
fi

if [ -z "$NEW_RELIC_ACCOUNT_ID" ]; then
  echo -e "${RED}Error: New Relic Account ID is required${NC}"
  echo -e "${YELLOW}You can find your account ID in the URL when logged into New Relic One${NC}"
  usage
fi

# Function to check if New Relic API is accessible
check_newrelic_access() {
  echo -e "${YELLOW}Checking New Relic API access...${NC}"
  
  local status_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Api-Key: ${NEW_RELIC_LICENSE_KEY}" \
    "https://api.newrelic.com/v2/applications.json")
  
  if [ "$status_code" -eq 200 ]; then
    echo -e "${GREEN}✅ New Relic API is accessible${NC}"
    return 0
  else
    echo -e "${RED}❌ Cannot access New Relic API. Status code: ${status_code}${NC}"
    echo -e "${YELLOW}Please verify your license key is correct${NC}"
    return 1
  fi
}

# Function to generate User API key using GraphQL
generate_user_api_key() {
  echo -e "${YELLOW}Generating New Relic User API key...${NC}"
  
  # GraphQL mutation to create a User API key
  local graphql_query=$(cat <<EOF
{
  "query": "mutation {
    apiAccessCreateKeys(keys: {
      name: \"${API_KEY_NAME}\",
      keyType: ${API_KEY_TYPE},
      accountId: ${NEW_RELIC_ACCOUNT_ID}
    }) {
      createdKeys {
        id
        key
        name
        type
      }
      errors {
        message
        type
      }
    }
  }"
}
EOF
)
  
  local response=$(curl -s \
    -X POST \
    -H "Api-Key: ${NEW_RELIC_LICENSE_KEY}" \
    -H "Content-Type: application/json" \
    -d "$graphql_query" \
    "https://api.newrelic.com/graphql")
  
  # Check if the response contains an API key
  if echo "$response" | grep -q '"key"'; then
    local api_key=$(echo "$response" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
    local key_id=$(echo "$response" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    
    echo -e "${GREEN}✅ User API key created successfully${NC}"
    echo -e "${YELLOW}API Key ID:${NC} $key_id"
    echo -e "${YELLOW}API Key:${NC} $api_key"
    echo -e "${YELLOW}API Key Name:${NC} $API_KEY_NAME"
    echo -e "${YELLOW}API Key Type:${NC} $API_KEY_TYPE"
    
    # Save the API key to a file for later use
    local api_key_file="/tmp/newrelic_api_key.txt"
    echo "$api_key" > "$api_key_file"
    echo -e "${YELLOW}API key saved to:${NC} $api_key_file"
    
    return 0
  else
    echo -e "${RED}❌ Failed to create User API key${NC}"
    echo -e "${RED}Response: ${response}${NC}"
    
    # Check for specific errors
    if echo "$response" | grep -q "errors"; then
      local error_message=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
      echo -e "${RED}Error: ${error_message}${NC}"
    fi
    
    return 1
  fi
}

# Function to generate alternative REST API key (fallback)
generate_rest_api_key() {
  echo -e "${YELLOW}Attempting alternative REST API key generation...${NC}"
  
  # Try to use the license key as a User API key (some license keys work for both)
  echo -e "${YELLOW}Testing license key as User API key...${NC}"
  
  local test_response=$(curl -s \
    -H "Api-Key: ${NEW_RELIC_LICENSE_KEY}" \
    "https://api.newrelic.com/v2/alerts_policies.json")
  
  if echo "$test_response" | grep -q "policies"; then
    echo -e "${GREEN}✅ License key can be used as User API key${NC}"
    echo -e "${YELLOW}API Key:${NC} ${NEW_RELIC_LICENSE_KEY}"
    echo -e "${YELLOW}Note: Using license key as User API key (this works for some accounts)${NC}"
    
    # Save the license key as the API key
    local api_key_file="/tmp/newrelic_api_key.txt"
    echo "$NEW_RELIC_LICENSE_KEY" > "$api_key_file"
    echo -e "${YELLOW}API key saved to:${NC} $api_key_file"
    
    return 0
  else
    echo -e "${RED}❌ License key cannot be used as User API key${NC}"
    echo -e "${YELLOW}You may need to create a User API key manually in New Relic One${NC}"
    echo -e "${YELLOW}Go to: Account settings > API keys > Create a key${NC}"
    return 1
  fi
}

# Function to display usage instructions
display_usage_instructions() {
  echo -e "\n${BLUE}=== New Relic API Key Usage Instructions ===${NC}"
  echo -e "${YELLOW}1. For Gremlin Health Check Integration:${NC}"
  echo -e "   Use this API key with the New Relic health check setup script:"
  echo -e "   ./monitoring/newrelic/health_check/setup_health_check.sh --api-key YOUR_API_KEY"
  echo -e ""
  echo -e "${YELLOW}2. For New Relic REST API Endpoints:${NC}"
  echo -e "   Base URL: https://api.newrelic.com/v2/"
  echo -e "   Authentication: Api-Key: YOUR_API_KEY"
  echo -e ""
  echo -e "${YELLOW}3. Common Monitoring Endpoints:${NC}"
  echo -e "   - Alert Policies: https://api.newrelic.com/v2/alerts_policies.json"
  echo -e "   - Alert Conditions: https://api.newrelic.com/v2/alerts_nrql_conditions.json"
  echo -e "   - Applications: https://api.newrelic.com/v2/applications.json"
  echo -e ""
  echo -e "${YELLOW}4. For Gremlin Integration:${NC}"
  echo -e "   Monitor URL: https://api.newrelic.com/v2/alerts_nrql_conditions.json?policy_id=POLICY_ID"
  echo -e "   Success Criteria: HTTP 200 and JSON response with alert conditions"
}

# Main execution
main() {
  echo -e "${GREEN}=== New Relic API Key Generator ===${NC}"
  echo -e "${YELLOW}License Key: ${NEW_RELIC_LICENSE_KEY:0:10}...${NC}"
  echo -e "${YELLOW}Account ID: ${NEW_RELIC_ACCOUNT_ID}${NC}"
  echo -e "${YELLOW}API Key Name: ${API_KEY_NAME}${NC}"
  echo -e "${YELLOW}API Key Type: ${API_KEY_TYPE}${NC}"
  
  # Check New Relic API access
  if ! check_newrelic_access; then
    echo -e "${RED}❌ Cannot proceed without New Relic API access${NC}"
    exit 1
  fi
  
  # Try to generate User API key via GraphQL
  if generate_user_api_key; then
    echo -e "${GREEN}✅ API key generation completed successfully${NC}"
  else
    echo -e "${YELLOW}⚠️ GraphQL API key generation failed, trying alternative method...${NC}"
    
    # Fallback to using license key as User API key
    if generate_rest_api_key; then
      echo -e "${GREEN}✅ API key generation completed using alternative method${NC}"
    else
      echo -e "${RED}❌ All API key generation methods failed${NC}"
      echo -e "${YELLOW}Please create a User API key manually in New Relic One${NC}"
      exit 1
    fi
  fi
  
  # Display usage instructions
  display_usage_instructions
}

# Run main function
main
