#!/bin/bash

# Script to create Grafana service account and token
# This script assumes Grafana is accessible at http://localhost:3000 via port forwarding
# Uses the modern service account approach instead of legacy API keys

set -e

# Colors for output
green='\033[0;32m'
yellow='\033[1;33m'
red='\033[0;31m'
nc='\033[0m' # No Color

# Default values
GRAFANA_URL="http://localhost:3000"
SERVICE_ACCOUNT_NAME="gremlin-health-check"
SERVICE_ACCOUNT_ROLE="Admin"
TOKEN_NAME="gremlin-token"
TOKEN_TTL_SECONDS=0  # 0 means never expires

# Function to display script usage
usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  --grafana-url URL              Grafana URL (default: $GRAFANA_URL)"
  echo "  --service-account-name NAME    Service account name (default: $SERVICE_ACCOUNT_NAME)"
  echo "  --service-account-role ROLE    Service account role (Admin|Editor|Viewer, default: $SERVICE_ACCOUNT_ROLE)"
  echo "  --token-name NAME              Token name (default: $TOKEN_NAME)"
  echo "  --token-ttl SECONDS            Token TTL in seconds (0 = never expires, default: $TOKEN_TTL_SECONDS)"
  echo "  --help                         Display this help message"
  exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --grafana-url)
      GRAFANA_URL="$2"
      shift 2
      ;;
    --service-account-name)
      SERVICE_ACCOUNT_NAME="$2"
      shift 2
      ;;
    --service-account-role)
      SERVICE_ACCOUNT_ROLE="$2"
      shift 2
      ;;
    --token-name)
      TOKEN_NAME="$2"
      shift 2
      ;;
    --token-ttl)
      TOKEN_TTL_SECONDS="$2"
      shift 2
      ;;
    --help)
      usage
      ;;
    *)
      echo -e "${red}Error: Unknown option: $1${nc}"
      usage
      ;;
  esac
done

# Function to create Grafana service account and token
generate_service_account_token() {
  echo -e "${yellow}Creating Grafana service account and token...${nc}"
  
  # Make sure Grafana is accessible
  echo -e "${yellow}Checking Grafana accessibility...${nc}"
  local status_code=$(curl -s -o /dev/null -w "%{http_code}" "$GRAFANA_URL/api/health")
  
  if [[ "$status_code" -ne 200 ]]; then
    echo -e "${red}Error: Cannot access Grafana at $GRAFANA_URL (status code: $status_code)${nc}"
    echo -e "${yellow}Make sure port forwarding is set up correctly:${nc}"
    echo "kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    exit 1
  fi
  
  echo -e "${green}✅ Grafana is accessible${nc}"
  
  # Get username and password from user
  echo -e "${yellow}Please enter Grafana credentials:${nc}"
  read -p "Username (default: admin): " USERNAME
  USERNAME=${USERNAME:-admin}
  
  read -s -p "Password (default: prom-operator): " PASSWORD
  PASSWORD=${PASSWORD:-prom-operator}
  echo # New line after password input
  
  # Create basic auth token
  local auth_token=$(echo -n "$USERNAME:$PASSWORD" | base64)
  
  # Create service account payload
  local sa_payload=$(cat <<EOF
{
  "name": "$SERVICE_ACCOUNT_NAME",
  "role": "$SERVICE_ACCOUNT_ROLE",
  "isDisabled": false
}
EOF
  )
  
  # Check if service account already exists
  echo -e "${yellow}Checking if service account '$SERVICE_ACCOUNT_NAME' already exists...${nc}"
  local temp_file=$(mktemp)
  local list_sa_status_code=$(curl -s -w "%{http_code}" \
    -H "Authorization: Basic $auth_token" \
    "$GRAFANA_URL/api/serviceaccounts/search?query=$SERVICE_ACCOUNT_NAME" -o "$temp_file")
  
  local sa_id=""
  local sa_name=""
  
  if [[ "$list_sa_status_code" -eq 200 ]]; then
    # Check if service account exists in the response
    local sa_exists=$(cat "$temp_file" | jq -r ".serviceAccounts[] | select(.name == \"$SERVICE_ACCOUNT_NAME\") | .id")
    if [[ -n "$sa_exists" ]]; then
      sa_id=$sa_exists
      sa_name="$SERVICE_ACCOUNT_NAME"
      echo -e "${green}✅ Service account '$sa_name' already exists (ID: $sa_id)${nc}"
    fi
  fi
  
  rm "$temp_file"
  
  # Create service account if it doesn't exist
  if [[ -z "$sa_id" ]]; then
    echo -e "${yellow}Creating service account...${nc}"
    # Use a temporary file to store the response
    local temp_file=$(mktemp)
    local sa_status_code=$(curl -s -w "%{http_code}" \
      -X POST \
      -H "Authorization: Basic $auth_token" \
      -H "Content-Type: application/json" \
      -d "$sa_payload" \
      "$GRAFANA_URL/api/serviceaccounts" -o "$temp_file")
    
    local sa_body=$(cat "$temp_file")
    rm "$temp_file"
    
    if [[ "$sa_status_code" -ne 201 ]]; then
      echo -e "${red}Error: Failed to create service account (status code: $sa_status_code)${nc}"
      echo "Response: $sa_body"
      exit 1
    fi
    
    # Extract service account ID
    sa_id=$(echo "$sa_body" | jq -r '.id')
    sa_name=$(echo "$sa_body" | jq -r '.name')
    
    echo -e "${green}✅ Service account '$sa_name' created successfully (ID: $sa_id)${nc}"
  fi
  
  # Create token payload
  local token_payload=$(cat <<EOF
{
  "name": "$TOKEN_NAME",
  "secondsToLive": $TOKEN_TTL_SECONDS
}
EOF
  )
  
  # Create service account token
  echo -e "${yellow}Creating service account token...${nc}"
  local temp_file2=$(mktemp)
  local token_status_code=$(curl -s -w "%{http_code}" \
    -X POST \
    -H "Authorization: Basic $auth_token" \
    -H "Content-Type: application/json" \
    -d "$token_payload" \
    "$GRAFANA_URL/api/serviceaccounts/$sa_id/tokens" -o "$temp_file2")
  
  local token_body=$(cat "$temp_file2")
  rm "$temp_file2"
  
  if [[ "$token_status_code" -ne 200 ]]; then
    echo -e "${red}Error: Failed to create service account token (status code: $token_status_code)${nc}"
    echo "Response: $token_body"
    exit 1
  fi
  
  # Extract token key
  local token_key=$(echo "$token_body" | jq -r '.key')
  local token_name=$(echo "$token_body" | jq -r '.name')
  
  echo -e "${green}✅ Service account token '$token_name' created successfully${nc}"
  echo -e "${yellow}Token:${nc} $token_key"
  echo -e "${yellow}Save this token securely - you won't be able to retrieve it again!${nc}"
  
  # Display service account details
  echo -e "${yellow}Service Account Details:${nc}"
  echo -e "${yellow}  Name:${nc} $sa_name"
  echo -e "${yellow}  ID:${nc} $sa_id"
  echo -e "${yellow}  Role:${nc} $SERVICE_ACCOUNT_ROLE"
  echo -e "${yellow}  Token:${nc} $token_name"
  
  if [[ $TOKEN_TTL_SECONDS -gt 0 ]]; then
    local expiry_date=$(date -r $(($(date +%s) + TOKEN_TTL_SECONDS)) "+%Y-%m-%d %H:%M:%S")
    echo -e "${yellow}  Token expires:${nc} $expiry_date"
  else
    echo -e "${yellow}  Token expires:${nc} Never"
  fi
}

# Main execution
main() {
  echo -e "${green}=== Grafana Service Account & Token Generator ===${nc}"
  echo -e "${yellow}Grafana URL: $GRAFANA_URL${nc}"
  echo -e "${yellow}Service Account Name: $SERVICE_ACCOUNT_NAME${nc}"
  echo -e "${yellow}Service Account Role: $SERVICE_ACCOUNT_ROLE${nc}"
  echo -e "${yellow}Token Name: $TOKEN_NAME${nc}"
  echo -e "${yellow}Token TTL: $TOKEN_TTL_SECONDS seconds${nc}"
  
  generate_service_account_token
}

# Run main function
main
