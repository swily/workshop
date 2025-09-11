#!/bin/bash

# Gremlin Credentials Manager
# Securely manages Gremlin API credentials for health check creation

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CREDENTIALS_FILE="${SCRIPT_DIR}/../../demo_credentials.txt"
SECURE_CREDENTIALS_FILE="${SCRIPT_DIR}/.gremlin_credentials"

# Function to display usage
usage() {
  cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Manage Gremlin API credentials securely.

COMMANDS:
  set                       Set new Gremlin credentials
  get                       Display current credentials (masked)
  test                      Test credentials against Gremlin API
  clear                     Clear stored credentials
  export                    Export credentials as environment variables

OPTIONS:
  --team-id ID              Gremlin team ID
  --bearer-token TOKEN      Gremlin Bearer token
  --api-key KEY             Gremlin API key (optional)
  --help                    Show this help message

EXAMPLES:
  # Set credentials interactively
  $0 set
  
  # Set credentials via command line
  $0 set --team-id "your-team-id" --bearer-token "your-token"
  
  # Test current credentials
  $0 test
  
  # Export for use in other scripts
  eval \$($0 export)

EOF
}

# Function to prompt for credentials securely
prompt_for_credentials() {
  local team_id="$1"
  local bearer_token="$2"
  
  if [ -z "$team_id" ]; then
    read -p "Enter Gremlin Team ID: " team_id
  fi
  
  if [ -z "$bearer_token" ]; then
    echo "Enter Gremlin Bearer Token:"
    read -s bearer_token
    echo ""
  fi
  
  if [ -z "$team_id" ] || [ -z "$bearer_token" ]; then
    echo -e "${RED}❌ Both Team ID and Bearer Token are required${NC}"
    return 1
  fi
  
  echo "$team_id" > "$SECURE_CREDENTIALS_FILE"
  echo "$bearer_token" >> "$SECURE_CREDENTIALS_FILE"
  chmod 600 "$SECURE_CREDENTIALS_FILE"
  
  echo -e "${GREEN}✅ Credentials saved securely${NC}"
}

# Function to load credentials
load_credentials() {
  if [ ! -f "$SECURE_CREDENTIALS_FILE" ]; then
    return 1
  fi
  
  local line_count=$(wc -l < "$SECURE_CREDENTIALS_FILE")
  if [ "$line_count" -lt 2 ]; then
    return 1
  fi
  
  GREMLIN_TEAM_ID=$(sed -n '1p' "$SECURE_CREDENTIALS_FILE")
  BEARER_TOKEN=$(sed -n '2p' "$SECURE_CREDENTIALS_FILE")
  
  if [ -z "$GREMLIN_TEAM_ID" ] || [ -z "$BEARER_TOKEN" ]; then
    return 1
  fi
  
  return 0
}

# Function to display credentials (masked)
display_credentials() {
  if ! load_credentials; then
    echo -e "${YELLOW}⚠️  No credentials found${NC}"
    return 1
  fi
  
  local masked_token="${BEARER_TOKEN:0:10}...${BEARER_TOKEN: -10}"
  echo -e "${BLUE}Gremlin Team ID:${NC} $GREMLIN_TEAM_ID"
  echo -e "${BLUE}Bearer Token:${NC} $masked_token"
}

# Function to test credentials
test_credentials() {
  if ! load_credentials; then
    echo -e "${RED}❌ No credentials found. Run '$0 set' first.${NC}"
    return 1
  fi
  
  echo -e "${BLUE}Testing Gremlin API credentials...${NC}"
  
  local response
  response=$(curl -s -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $BEARER_TOKEN" \
    "https://api.gremlin.com/v1/status-checks?teamId=$GREMLIN_TEAM_ID" 2>&1)
  
  local exit_code=$?
  
  if [ $exit_code -eq 0 ]; then
    if echo "$response" | jq -e . >/dev/null 2>&1; then
      echo -e "${GREEN}✅ Credentials are valid${NC}"
      local check_count=$(echo "$response" | jq '. | length' 2>/dev/null || echo "0")
      echo -e "${BLUE}Found $check_count existing health checks${NC}"
      return 0
    else
      echo -e "${RED}❌ Invalid response from API: $response${NC}"
      return 1
    fi
  else
    echo -e "${RED}❌ Failed to connect to Gremlin API: $response${NC}"
    return 1
  fi
}

# Function to clear credentials
clear_credentials() {
  if [ -f "$SECURE_CREDENTIALS_FILE" ]; then
    rm -f "$SECURE_CREDENTIALS_FILE"
    echo -e "${GREEN}✅ Credentials cleared${NC}"
  else
    echo -e "${YELLOW}⚠️  No credentials to clear${NC}"
  fi
}

# Function to export credentials as environment variables
export_credentials() {
  if ! load_credentials; then
    echo "echo 'No credentials found'" >&2
    return 1
  fi
  
  echo "export GREMLIN_TEAM_ID='$GREMLIN_TEAM_ID'"
  echo "export BEARER_TOKEN='$BEARER_TOKEN'"
}

# Main function
main() {
  local command="$1"
  shift
  
  case "$command" in
    set)
      local team_id=""
      local bearer_token=""
      
      while [[ $# -gt 0 ]]; do
        case $1 in
          --team-id)
            team_id="$2"
            shift 2
            ;;
          --bearer-token)
            bearer_token="$2"
            shift 2
            ;;
          --help)
            usage
            exit 0
            ;;
          *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
        esac
      done
      
      prompt_for_credentials "$team_id" "$bearer_token"
      ;;
    get)
      display_credentials
      ;;
    test)
      test_credentials
      ;;
    clear)
      clear_credentials
      ;;
    export)
      export_credentials
      ;;
    --help|help)
      usage
      ;;
    *)
      echo -e "${RED}Unknown command: $command${NC}"
      usage
      exit 1
      ;;
  esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
