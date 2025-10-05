#!/bin/bash

# Enhanced Prometheus Health Check Creator for Gremlin
# This script creates external integrations and health checks with proper error handling and fallbacks
# Handles localhost endpoints by ensuring port forwarding is active

# Removed set -e to prevent premature exits on API failures
# set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Source HTTPS detection library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../../lib/https_detection.sh" ]; then
    source "$SCRIPT_DIR/../../lib/https_detection.sh"
fi

# Gremlin API configuration
GREMLIN_TEAM_ID="${GREMLIN_TEAM_ID:-438c58ec-03db-47ac-8c58-ec03db67ac42}"
GREMLIN_API_KEY="${GREMLIN_API_KEY}"
GREMLIN_BEARER_TOKEN="${GREMLIN_BEARER_TOKEN}"
GREMLIN_API_URL="https://api.gremlin.com/v1"

# Configuration
NAMESPACE="otel-demo"
DRY_RUN=false
INTEGRATION_CREATED=""
HEALTH_CHECK_CREATED=""

# Function to generate bearer token from credentials
generate_bearer_token() {
    local email="$1"
    local password="$2"
    local mfa_token="$3"
    
    if [ -n "$mfa_token" ]; then
        # Use MFA endpoint
        local response=$(curl -s -X POST \
            --header 'Content-Type: application/x-www-form-urlencoded' \
            --data-urlencode "email=$email" \
            --data-urlencode "password=$password" \
            --data-urlencode "token=$mfa_token" \
            'https://api.gremlin.com/v1/users/auth/mfa/auth?getCompanySession=true')
    else
        # Use regular auth endpoint
        local response=$(curl -s -X POST \
            --header 'Content-Type: application/x-www-form-urlencoded' \
            --data-urlencode "email=$email" \
            --data-urlencode "password=$password" \
            'https://api.gremlin.com/v1/users/auth?getCompanySession=true')
    fi
    
    # Debug the response to understand the structure
    echo "API Response: $response" >&2
    
    # Extract bearer token from response - try multiple possible fields
    local bearer_token=$(echo "$response" | jq -r '.header // .token // .access_token // .bearer_token // empty' 2>/dev/null)
    
    # If jq fails, try to extract manually
    if [ -z "$bearer_token" ] || [ "$bearer_token" = "null" ]; then
        # Try to extract from JSON manually
        bearer_token=$(echo "$response" | grep -o '"header":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
    fi
    
    if [ -n "$bearer_token" ] && [ "$bearer_token" != "null" ] && [ "$bearer_token" != "empty" ]; then
        echo "$bearer_token"
        return 0
    else
        echo "Failed to generate bearer token. Response: $response" >&2
        return 1
    fi
}

# Ensure Route53 DNS is created (CNAMEs) and wait for readiness
setup_dns_and_wait() {
    if [ -n "${BASE_DOMAIN}" ] && [ -n "${CLUSTER_NAME}" ]; then
        echo -e "${BLUE}🔧 Ensuring Route53 DNS is configured before creating health checks...${NC}"
        if [ -x "helper_scripts/dns/setup_alb_dns.sh" ]; then
            helper_scripts/dns/setup_alb_dns.sh || echo -e "${YELLOW}⚠️  DNS setup script returned non-zero, continuing...${NC}"
        else
            echo -e "${YELLOW}⚠️  DNS setup script not found or not executable: helper_scripts/dns/setup_alb_dns.sh${NC}"
        fi

        # After attempting setup, recompute endpoints to prefer DNS
        resolve_monitoring_endpoints

        # Wait for DNS endpoints to respond
        local to_check=()
        if [ -n "${PROMETHEUS_DNS_ENDPOINT}" ]; then to_check+=("${PROMETHEUS_DNS_ENDPOINT}"); fi
        if [ -n "${GRAFANA_DNS_ENDPOINT}" ]; then to_check+=("${GRAFANA_DNS_ENDPOINT}"); fi

        echo -e "${BLUE}⏳ Waiting for DNS endpoints to become reachable...${NC}"
        for url in "${to_check[@]}"; do
            echo -e "${YELLOW}  Checking ${url}${NC}"
            local attempts=12
            local i=1
            while [ $i -le $attempts ]; do
                if curl -s --max-time 5 "$url" > /dev/null 2>&1; then
                    echo -e "${GREEN}  ✅ Reachable: $url${NC}"
                    break
                fi
                echo -e "${YELLOW}  ⏳ Attempt $i/$attempts failed, retrying in 10s...${NC}"
                sleep 10
                i=$((i+1))
            done
            if [ $i -gt $attempts ]; then
                echo -e "${YELLOW}  ⚠️  DNS endpoint not reachable yet: $url (continuing)${NC}"
            fi
        done
    fi
}

# Resolve monitoring ingress hostnames (ALB) and optional DNS FQDNs
resolve_monitoring_endpoints() {
    # Detect HTTPS scheme
    local scheme="http"
    if command -v get_consolidated_alb_scheme &>/dev/null; then
        scheme=$(get_consolidated_alb_scheme)
    fi
    
    # Allow direct overrides via env vars
    if [ -n "$PROMETHEUS_URL" ]; then
        PROMETHEUS_ENDPOINT="$PROMETHEUS_URL"
    fi
    if [ -n "$GRAFANA_URL" ]; then
        GRAFANA_ENDPOINT="$GRAFANA_URL"
    fi

    if [ -z "$PROMETHEUS_ENDPOINT" ] || echo "$PROMETHEUS_ENDPOINT" | grep -q "localhost"; then
        # Prefer monitoring namespace ingress hostnames if available
        local prom_ing
        prom_ing=$(kubectl get ingress -n monitoring prometheus-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        if [ -n "$prom_ing" ]; then
            PROMETHEUS_ENDPOINT="${scheme}://${prom_ing}/api/v1/alerts"
        fi
    fi

    if [ -z "$GRAFANA_ENDPOINT" ] || echo "$GRAFANA_ENDPOINT" | grep -q "localhost"; then
        local graf_ing
        graf_ing=$(kubectl get ingress -n monitoring grafana-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        if [ -n "$graf_ing" ]; then
            GRAFANA_ENDPOINT="${scheme}://${graf_ing}/api/health"
        fi
    fi

    # Prefer Route53 DNS FQDNs based on CLUSTER_NAME and BASE_DOMAIN if provided
    if [ -n "$BASE_DOMAIN" ] && [ -n "${CLUSTER_NAME}" ]; then
        local prom_dns="${scheme}://${CLUSTER_NAME}-prometheus.${BASE_DOMAIN}:9090/api/v1/alerts"
        local graf_dns="${scheme}://${CLUSTER_NAME}-grafana-monitoring.${BASE_DOMAIN}/api/health"
        PROMETHEUS_DNS_ENDPOINT="$prom_dns"
        GRAFANA_DNS_ENDPOINT="$graf_dns"

        # If current endpoints are empty or still pointing to localhost, switch to DNS endpoints
        if [ -z "$PROMETHEUS_ENDPOINT" ] || echo "$PROMETHEUS_ENDPOINT" | grep -q "localhost"; then
            PROMETHEUS_ENDPOINT="$PROMETHEUS_DNS_ENDPOINT"
        fi
        if [ -z "$GRAFANA_ENDPOINT" ] || echo "$GRAFANA_ENDPOINT" | grep -q "localhost"; then
            GRAFANA_ENDPOINT="$GRAFANA_DNS_ENDPOINT"
        fi
    fi
}

# Function to ensure port forwarding is active for localhost endpoints
ensure_port_forwarding() {
    echo -e "${BLUE}Ensuring port forwarding is active for localhost endpoints...${NC}"
    
    # Kill existing port forwards and restart them
    if [ -f "helper_scripts/dns/port_forward_services.sh" ]; then
        echo -e "${YELLOW}  Restarting port forwarding services...${NC}"
        ./helper_scripts/dns/port_forward_services.sh >/dev/null 2>&1 &
        sleep 5
        echo -e "${GREEN}  Port forwarding services restarted${NC}"
    else
        echo -e "${YELLOW}  Port forwarding script not found${NC}"
    fi
}

# Function to make Gremlin API requests with both Bearer and API Key fallback
make_gremlin_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local auth_type="${4:-bearer}"  # bearer or apikey
    
    local url="${GREMLIN_API_URL}${endpoint}"
    local response
    local http_code
    
    # Choose authentication method
    local auth_header
    if [ "$auth_type" = "bearer" ] && [ -n "$GREMLIN_BEARER_TOKEN" ]; then
        # Remove 'Bearer ' prefix if it exists to avoid duplication
        local clean_token="${GREMLIN_BEARER_TOKEN#Bearer }"
        auth_header="Authorization: Bearer $clean_token"
    elif [ "$auth_type" = "apikey" ] && [ -n "$GREMLIN_API_KEY" ]; then
        auth_header="Authorization: Key $GREMLIN_API_KEY"
    else
        echo "No valid authentication method available" >&2
        echo "Available auth methods: Bearer Token: ${GREMLIN_BEARER_TOKEN:+SET} API Key: ${GREMLIN_API_KEY:+SET}" >&2
        return 1
    fi
    
    if [ -n "$data" ]; then
        response=$(curl -s -w "HTTPSTATUS:%{http_code}" -X "$method" \
            -H "$auth_header" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$url")
    else
        response=$(curl -s -w "HTTPSTATUS:%{http_code}" -X "$method" \
            -H "$auth_header" \
            -H "Content-Type: application/json" \
            "$url")
    fi
    
    http_code=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    body=$(echo "$response" | sed 's/HTTPSTATUS:[0-9]*$//')
    
    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
        echo "$body"
        return 0
    else
        echo "HTTP $http_code: $body" >&2
        return 1
    fi
}

# Function to list existing integrations
list_existing_integrations() {
    echo -e "${BLUE}Checking existing integrations...${NC}"
    
    local response
    local auth_success=false
    
    # Try bearer token first if available
    if [ -n "$GREMLIN_BEARER_TOKEN" ]; then
        echo "Trying bearer token authentication..."
        response=$(make_gremlin_request "GET" "/external-integrations/status-check?teamId=$GREMLIN_TEAM_ID" "" "bearer")
        if [ $? -eq 0 ]; then
            auth_success=true
        fi
    fi
    
    # Fallback to API key if bearer token failed or not available
    if [ "$auth_success" = false ] && [ -n "$GREMLIN_API_KEY" ]; then
        echo -e "${YELLOW}  Bearer token failed or not available, trying API key...${NC}"
        response=$(make_gremlin_request "GET" "/external-integrations/status-check?teamId=$GREMLIN_TEAM_ID" "" "apikey")
        if [ $? -eq 0 ]; then
            auth_success=true
        fi
    fi
    
    if [ "$auth_success" = true ]; then
        echo "$response" | jq -r '.integrations[]? | "  - \(.name) (\(.observabilityToolType))"' 2>/dev/null || echo "  No integrations found"
        return 0
    else
        echo -e "${YELLOW}  ⚠️  Could not list integrations - authentication failed${NC}"
        echo "Available credentials: Bearer Token: ${GREMLIN_BEARER_TOKEN:+SET} API Key: ${GREMLIN_API_KEY:+SET}"
        return 1
    fi
}

# Function to create Prometheus integration with alert-based health checks
create_prometheus_integration() {
    local integration_name="prometheus-grafana-$(date +%s)"
    
    echo -e "${BLUE}🔧 Creating Prometheus integration: $integration_name${NC}"
    
    # Create integration payload with Prometheus rules endpoint for alert-based health checks
    local integration_payload
    # Determine private network flag for integration
    local int_private_flag
    if [ "$USE_PNI" = "true" ]; then
        int_private_flag=true
    else
        int_private_flag=false
    fi

    # Use the selected/promoted PROMETHEUS_ENDPOINT (alerts or rules path) - remove port for DNS endpoints
    local clean_url="$PROMETHEUS_ENDPOINT"
    if echo "$PROMETHEUS_ENDPOINT" | grep -q "gremlinpoc.com:9090"; then
        clean_url=$(echo "$PROMETHEUS_ENDPOINT" | sed 's/:9090//')
    fi
    
    integration_payload=$(jq -n \
        --arg name "$integration_name" \
        --arg url "$clean_url" \
        --argjson private "$int_private_flag" \
        '{
            name: $name,
            description: "Prometheus alert rules health check integration",
            type: "CUSTOM",
            observabilityToolType: "CUSTOM",
            domain: null,
            privateNetwork: $private,
            canBeUsedAsStatusCheck: true,
            lastAuthenticationStatus: "AUTHENTICATED",
            url: $url,
            headers: {},
            timeout: 30,
            validateSSL: false
        }')
    
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[DRY RUN] Would create integration with payload:${NC}"
        echo "$integration_payload" | jq .
        INTEGRATION_CREATED="$integration_name"
        return 0
    fi
    
    local response
    response=$(make_gremlin_request "POST" "/external-integrations/status-check?teamId=$GREMLIN_TEAM_ID&type=CUSTOM" "$integration_payload" "bearer")
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Successfully created integration: $integration_name${NC}"
        INTEGRATION_CREATED="$integration_name"
        return 0
    else
        # Fallback to API key
        echo -e "${YELLOW}  Bearer token failed, trying API key...${NC}"
        response=$(make_gremlin_request "POST" "/external-integrations/status-check?teamId=$GREMLIN_TEAM_ID&type=CUSTOM" "$integration_payload" "apikey")
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Successfully created integration: $integration_name${NC}"
            INTEGRATION_CREATED="$integration_name"
            return 0
        else
            echo -e "${RED}❌ Failed to create integration${NC}"
            echo "Response: $response"
            return 1
        fi
    fi
}

# Function to verify integration was created successfully
verify_integration() {
    local integration_name="$1"
    
    echo -e "${BLUE}🔍 Verifying integration '$integration_name' exists...${NC}"
    
    local response
    response=$(make_gremlin_request "GET" "/external-integrations/status-check?teamId=$GREMLIN_TEAM_ID" "" "bearer")
    
    if [ $? -ne 0 ]; then
        response=$(make_gremlin_request "GET" "/external-integrations/status-check?teamId=$GREMLIN_TEAM_ID" "" "apikey")
    fi
    
    if [ $? -eq 0 ]; then
        local found
        found=$(echo "$response" | jq -r ".integrations[]? | select(.name == \"$integration_name\") | .name" 2>/dev/null)
        
        if [ -n "$found" ]; then
            echo -e "${GREEN}✅ Integration verified: $integration_name${NC}"
            
            # Show integration details
            local integration_url
            integration_url=$(echo "$response" | jq -r ".integrations[]? | select(.name == \"$integration_name\") | .configuration.baseUrl // \"N/A\"" 2>/dev/null)
            echo -e "${BLUE}  URL: $integration_url${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️  Integration not found in list${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠️  Could not verify integration${NC}"
        return 1
    fi
}

# Function to create a health check
create_health_check() {
    local integration_name="$1"
    local check_name_suffix="$2"   # e.g., "-alb" or "-dns"
    local check_name="prometheus-alerts${check_name_suffix}-$(date +%s)"
    # Use resolved PROMETHEUS_ENDPOINT from outer scope
    INTEGRATION_NAME="prometheus-integration-$(date +%s)"
    
    echo -e "${BLUE}Creating health check: $check_name${NC}"
    
    # Create health check payload matching working examples structure
    local payload
    # Determine private network boolean for jq
    local private_flag
    if [ "$USE_PNI" = "true" ]; then
        private_flag=true
    else
        private_flag=false
    fi

    # Clean URL for DNS endpoints (remove :9090 port)
    local clean_check_url="$PROMETHEUS_ENDPOINT"
    if echo "$PROMETHEUS_ENDPOINT" | grep -q "gremlinpoc.com:9090"; then
        clean_check_url=$(echo "$PROMETHEUS_ENDPOINT" | sed 's/:9090//')
    fi
    
    # Build payload that aligns with the verified API schema in HealthChecksExplained.md
    payload=$(jq -n \
        --arg name "$check_name" \
        --arg desc "Prometheus alerts health check" \
        --arg url "$clean_check_url" \
        --arg integrationName "$integration_name" \
        --argjson private "$private_flag" \
        '{
            name: $name,
            description: $desc,
            isContinuous: true,
            isPrivateNetwork: $private,
            endpointConfiguration: {
                url: $url,
                method: "GET",
                headers: {}
            },
            evaluationConfiguration: {
                okLatencyMaxMs: 5000,
                okStatusCodes: [200]
            },
            pollingIntervalSeconds: 30,
            category: "ERRORS",
            teamExternalIntegration: {
                observabilityToolType: "CUSTOM",
                name: $integrationName
            }
        }')
    
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[DRY RUN] Would create health check with payload:${NC}"
        echo "$payload" | jq .
        HEALTH_CHECK_CREATED="$check_name"
        return 0
    fi
    
    # Try to create health check
    local response
    response=$(make_gremlin_request "POST" "/status-checks?teamId=$GREMLIN_TEAM_ID" "$payload" "bearer")
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Successfully created health check: $check_name${NC}"
        local health_check_id
        health_check_id=$(echo "$response" | tr -d '\n' | sed 's/.*"id":"\([^"]*\)".*/\1/' 2>/dev/null || echo "$response")
        echo -e "${BLUE}  Health Check ID: $health_check_id${NC}"
        HEALTH_CHECK_CREATED="$check_name"
        return 0
    else
        # Fallback to API key
        echo -e "${YELLOW}  Bearer token failed, trying API key...${NC}"
        response=$(make_gremlin_request "POST" "/status-checks?teamId=$GREMLIN_TEAM_ID" "$payload" "apikey")
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Successfully created health check: $check_name${NC}"
            local health_check_id
            health_check_id=$(echo "$response" | tr -d '\n' | sed 's/.*"id":"\([^"]*\)".*/\1/' 2>/dev/null || echo "$response")
            echo -e "${BLUE}  Health Check ID: $health_check_id${NC}"
            HEALTH_CHECK_CREATED="$check_name"
            return 0
        else
            echo -e "${RED}Failed to create health check${NC}"
            echo "Response: $response"
            return 1
        fi
    fi
}

# Function to show animated GREMLIN art
show_animated_gremlin_art() {
    local step="$1"
    local total_steps="$2"
    
    # Suppress all other output during animation
    exec 3>&1 4>&2
    exec 1>/dev/null 2>/dev/null
    
    # Clear previous output if not first step (disabled to prevent terminal corruption)
    if [ "$step" -gt 1 ]; then
        echo "Processing step $step..." >&3
    fi
    
    # Complete GREMLIN ASCII art
    local gremlin_lines=(
        " ██████╗ ██████╗ ███████╗███╗   ███╗██╗     ██╗███╗   ██╗"
        "██╔════╝ ██╔══██╗██╔════╝████╗ ████║██║     ██║████╗  ██║"
        "██║  ███╗██████╔╝█████╗  ██╔████╔██║██║     ██║██╔██╗ ██║"
        "██║   ██║██╔══██╗██╔══╝  ██║╚██╔╝██║██║     ██║██║╚██╗██║"
        "╚██████╔╝██║  ██║███████╗██║ ╚═╝ ██║███████╗██║██║ ╚████║"
    )
    
    echo ""
    
    # Show rows progressively based on step
    local rows_to_show=$step
    if [ "$rows_to_show" -gt 5 ]; then
        rows_to_show=5
    fi
    
    # Determine color
    local color=$GREY
    if [ "$step" -eq "$total_steps" ]; then
        color=$GREEN
    fi
    
    # Display rows one by one
    for i in $(seq 0 $((rows_to_show - 1))); do
        if [ $i -lt ${#gremlin_lines[@]} ]; then
            echo -e "${color}${gremlin_lines[$i]}${NC}"
        fi
    done
    
    # Fill remaining lines with empty space to maintain consistent height
    for i in $(seq $rows_to_show 4); do
        echo ""
    done
    
    echo ""
    
    # Restore stdout and stderr
    exec 1>&3 2>&4
    exec 3>&- 4>&-
    
    # If completed, pause for 2-3 seconds
    if [ "$step" -eq "$total_steps" ]; then
        sleep 3
    fi
}

# Function to provide fallback instructions with animated art
provide_fallback_instructions() {
    local integration_name="$1"
    
    # Show final animated GREMLIN art (step 7 of 7 to include the N)
    show_animated_gremlin_art 7 7
    
    echo ""
    echo -e "${BLUE}Health check creation failed, but integration was created successfully.${NC}"
    echo -e "${BLUE}Please create the health check manually in the Gremlin UI.${NC}"
    echo -e "   ${BLUE}Name:${NC} prometheus-health-check"
    echo -e "   ${BLUE}Integration:${NC} $integration_name"
    echo -e "   ${BLUE}URL:${NC} http://localhost:9090/api/v1/rules"
    echo -e "   ${BLUE}Method:${NC} GET"
    echo -e "   ${BLUE}Expected Status:${NC} 200"
    echo -e "   ${BLUE}Expected Response:${NC} JSON with 'groups' array containing alert rules"
    echo ""
    echo -e "${YELLOW}Alert-based endpoints for health checks:${NC}"
    echo -e "   ${BLUE}Prometheus Alert Rules:${NC} http://localhost:9090/api/v1/rules"
    echo -e "   ${BLUE}Grafana Alerting API:${NC} http://localhost:3000/api/alerting/list"
    echo -e "   ${BLUE}Prometheus Alerts:${NC} http://localhost:9090/api/v1/alerts"
    echo -e "   ${BLUE}Grafana Alert Rules:${NC} http://localhost:3000/api/ruler/grafana/api/v1/rules"
    echo ""
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run              Show what would be created without making changes"
    echo "  --help                 Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  GREMLIN_BEARER_TOKEN   Required: Gremlin Bearer token (preferred)"
    echo "  GREMLIN_API_KEY        Fallback: Gremlin API key"
    echo "  GREMLIN_TEAM_ID        Optional: Gremlin team ID"
}

# Main execution
main() {
    echo -e "${GREEN}Starting Gremlin Health Check Creation${NC}"
    echo -e "${YELLOW}This script will create health checks for Prometheus and Grafana${NC}"
    echo ""
    
    # Check authentication variables
    if [ -z "$GREMLIN_BEARER_TOKEN" ] && [ -z "$GREMLIN_API_KEY" ]; then
        echo -e "${YELLOW}⚠️  No Gremlin authentication found${NC}"
        echo "Please set either GREMLIN_BEARER_TOKEN or GREMLIN_API_KEY environment variable"
        echo "Or we can generate a bearer token interactively..."
    else
        echo -e "${GREEN}✅ Gremlin authentication configured${NC}"
    fi
    echo ""
    
    # Ensure Route53 DNS is set up prior to selecting endpoints
    setup_dns_and_wait

    # Skip interactive prompt if --auto-mode is used
    if [ -z "$endpoint_choice" ]; then
        echo "Choose health check endpoint type:"
        echo "1) Localhost with port-forward (requires active port-forward)"
        echo "2) Public LoadBalancer endpoints (internet accessible)"
        echo "3) Private Network Integration (PNI) with cluster-internal URLs"
        echo ""
        read -p "Choose option (1-3): " endpoint_choice
        echo ""
    fi
    
    # Set endpoint URLs based on user choice
    case $endpoint_choice in
        1)
            echo -e "${YELLOW}Using localhost endpoints (requires port-forward)${NC}"
            PROMETHEUS_ENDPOINT="http://localhost:9090/api/v1/alerts"
            GRAFANA_ENDPOINT="http://localhost:3100/api/health"
            USE_PNI=false
            ;;
        2)
            echo -e "${YELLOW}Using public Ingress (ALB) endpoints from monitoring namespace...${NC}"
            resolve_monitoring_endpoints
            USE_PNI=false
            ;;
        3)
            echo -e "${YELLOW}Using Private Network Integration (PNI) endpoints${NC}"
            PROMETHEUS_ENDPOINT="http://prometheus.otel-demo.svc.cluster.local:9090/api/v1/alerts"
            GRAFANA_ENDPOINT="http://grafana.otel-demo.svc.cluster.local:80/api/health"
            USE_PNI=true
            ;;
        *)
            echo -e "${RED}Invalid choice, defaulting to localhost${NC}"
            PROMETHEUS_ENDPOINT="http://localhost:9090/api/v1/alerts"
            GRAFANA_ENDPOINT="http://localhost:3100/api/health"
            USE_PNI=false
            ;;
    esac
    
    echo -e "${PURPLE}Enhanced Prometheus Health Check Creator${NC}"
    echo ""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --auto-mode)
                # Skip interactive prompts when called from monitoring.sh
                endpoint_choice=2  # Use public LoadBalancer endpoints
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate authentication
    if [ -n "$GREMLIN_BEARER_TOKEN" ]; then
        echo -e "${GREEN}✅ Using Bearer Token authentication${NC}"
    elif [ -n "$GREMLIN_API_KEY" ]; then
        echo -e "${GREEN}✅ Using API Key authentication${NC}"
    else
        echo -e "${YELLOW}⚠️  No authentication method available${NC}"
    fi
    
    # Auto-generate bearer token if not provided
    if [ -z "$GREMLIN_BEARER_TOKEN" ] && [ -z "$GREMLIN_API_KEY" ]; then
        echo -e "${YELLOW}No bearer token or API key found. Let's generate one...${NC}"
        echo -n "Enter your Gremlin email: "
        read -r gremlin_email
        echo -n "Enter your Gremlin password: "
        read -rs gremlin_password
        echo
        echo -n "Enter MFA token (leave empty if no MFA): "
        read -r mfa_token
        
        echo "Generating bearer token..."
        GREMLIN_BEARER_TOKEN=$(generate_bearer_token "$gremlin_email" "$gremlin_password" "$mfa_token")
        
        if [ $? -ne 0 ] || [ -z "$GREMLIN_BEARER_TOKEN" ]; then
            echo -e "${RED}Failed to generate bearer token${NC}"
            echo -e "${YELLOW}Continuing with API key authentication if available...${NC}"
            # Don't exit - continue with API key if available
            if [ -z "$GREMLIN_API_KEY" ]; then
                echo -e "${RED}No API key available either. Cannot proceed.${NC}"
                exit 1
            fi
        else
            echo -e "${GREEN}Bearer token generated successfully${NC}"
            export GREMLIN_BEARER_TOKEN
        fi
    fi
    
    # Initialize animated progress (7 total steps)
    local total_steps=7
    local current_step=1
    
    # Step 1: Port forwarding
    show_animated_gremlin_art $current_step $total_steps
    sleep 1
    ensure_port_forwarding
    current_step=$((current_step + 1))
    
    # Step 2: List integrations
    show_animated_gremlin_art $current_step $total_steps
    sleep 1
    list_existing_integrations
    current_step=$((current_step + 1))
    
    echo ""
    echo -e "${BLUE}🚀 Starting health check creation process...${NC}"
    
    # Step 3: Create integration (auth already verified above)
    show_animated_gremlin_art $current_step $total_steps
    sleep 1
    if create_prometheus_integration; then
        echo -e "${GREEN}✅ Integration creation successful${NC}"
        current_step=$((current_step + 1))
        
        # Step 4: Verify integration
        show_animated_gremlin_art $current_step $total_steps
        sleep 1
        if verify_integration "$INTEGRATION_CREATED"; then
            echo -e "${GREEN}✅ Integration verification successful${NC}"
            current_step=$((current_step + 1))
            
            # Step 5: Create health checks (ALB first, then DNS if available)
            show_animated_gremlin_art $current_step $total_steps
            sleep 1
            # Primary check using ALB/Ingress URL
            if create_health_check "$INTEGRATION_CREATED" "-alb"; then
                echo -e "${GREEN}✅ Health check creation successful${NC}"
                current_step=$((current_step + 1))
                # Optional: create a second health check using DNS if BASE_DOMAIN is set
                if [ -n "$BASE_DOMAIN" ]; then
                    # Temporarily override endpoints to DNS for the second check
                    SAVED_PROM="$PROMETHEUS_ENDPOINT"; SAVED_GRAF="$GRAFANA_ENDPOINT"
                    PROMETHEUS_ENDPOINT="$PROMETHEUS_DNS_ENDPOINT"; GRAFANA_ENDPOINT="$GRAFANA_DNS_ENDPOINT"
                    echo -e "${BLUE}Creating DNS-based health check (prometheus.${BASE_DOMAIN})...${NC}"
                    create_health_check "$INTEGRATION_CREATED" "-dns" || echo -e "${YELLOW}Skipping DNS health check (may not be resolvable yet)${NC}"
                    PROMETHEUS_ENDPOINT="$SAVED_PROM"; GRAFANA_ENDPOINT="$SAVED_GRAF"
                fi
                
                # Step 6: Validation complete
                show_animated_gremlin_art $current_step $total_steps
                sleep 1
                current_step=$((current_step + 1))
                
                # Step 7: Final completion with full GREMLIN + N in green
                show_animated_gremlin_art $current_step $total_steps
                
                # Final summary
                echo ""
                echo -e "${GREEN}✅ Integration Created:${NC} $INTEGRATION_CREATED"
                echo -e "${GREEN}✅ Health Check Created:${NC} $HEALTH_CHECK_CREATED"
                echo ""
                echo -e "${BLUE}View your health checks in the Gremlin UI${NC}"
                echo ""
                echo -e "${YELLOW}Load Balancer Information for Manual Configuration:${NC}"
                if [ "$endpoint_choice" = "2" ]; then
                    echo "  Prometheus LB: ${PROMETHEUS_LB:-N/A}"
                    echo "  Grafana OTel LB: ${GRAFANA_OTEL_LB:-N/A}"
                    echo "  Grafana Monitoring LB: ${GRAFANA_MONITORING_LB:-N/A}"
                elif kubectl get ingress -n monitoring grafana-ingress >/dev/null 2>&1; then
                    local grafana_ingress_lb=$(kubectl get ingress -n monitoring grafana-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
                    echo "  Grafana Ingress LB: ${grafana_ingress_lb}"
                fi
                echo "  Use these identifiers when configuring manual health checks in Gremlin UI"
            else
                echo -e "${YELLOW}⚠️  Health check creation failed${NC}"
                provide_fallback_instructions "$INTEGRATION_CREATED"
            fi
        else
            echo -e "${YELLOW}⚠️  Integration verification failed${NC}"
            provide_fallback_instructions "$INTEGRATION_CREATED"
        fi
    else
        echo -e "${RED}❌ Integration creation failed${NC}"
        echo -e "${YELLOW}Please check your credentials and try again${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
