#!/bin/bash

# healthchecks.sh - Gremlin Health Check & Authentication Setup
# Separated from workshop.sh for better DNS readiness and service management

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Source HTTPS detection library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../../lib/https_detection.sh" ]; then
    source "$SCRIPT_DIR/../../lib/https_detection.sh"
fi

# Default values
CLUSTER_NAME="${CLUSTER_NAME:-current-workshop}"
SUBDOMAIN="${SUBDOMAIN:-}"
AWS_REGION="${AWS_REGION:-us-east-2}"
DNS_WAIT_TIME=300
DRY_RUN=false
VALIDATE_ONLY=false
PLATFORMS=()

# Print banner
print_banner() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║               HEALTH CHECKS SETUP                            ║${NC}"
    echo -e "${CYAN}║          Gremlin Health Check & Authentication Manager       ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --platform PLATFORM    Create health checks for platform (prometheus|grafana|dynatrace|newrelic|all)"
    echo "  --cluster-name NAME     Specify cluster name (default: from state file or current-workshop)"
    echo "  --subdomain NAME        Specify subdomain for DNS (default: from SUBDOMAIN env var)"
    echo "  --dns-wait SECONDS      Wait for DNS propagation (default: 300)"
    echo "  --dry-run              Show what would be created without making changes"
    echo "  --validate-only        Only validate existing health checks"
    echo "  --cleanup-services     Delete existing Gremlin services before creating new ones"
    echo "  --help                 Show this usage information"
    echo ""
    echo "Examples:"
    echo "  $0 --platform prometheus --platform grafana"
    echo "  $0 --platform all --dns-wait 600"
    echo "  $0 --cleanup-services --platform prometheus"
    echo "  $0 --validate-only"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --platform)
                PLATFORMS+=("$2")
                shift 2
                ;;
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --subdomain)
                SUBDOMAIN="$2"
                shift 2
                ;;
            --dns-wait)
                DNS_WAIT_TIME="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --validate-only)
                VALIDATE_ONLY=true
                shift
                ;;
            --cleanup-services)
                CLEANUP_SERVICES=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}[ERROR] Unknown option: $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Default to prometheus and grafana if no platforms specified
    if [ ${#PLATFORMS[@]} -eq 0 ]; then
        PLATFORMS=("prometheus" "grafana")
    fi
    
    # Expand "all" platform
    if [[ " ${PLATFORMS[*]} " =~ " all " ]]; then
        PLATFORMS=("prometheus" "grafana" "dynatrace" "newrelic")
    fi
}

# Validate prerequisites
validate_prerequisites() {
    echo -e "${BLUE}[INFO] Validating prerequisites...${NC}"
    
    # Check required tools
    local required_tools=("kubectl" "jq" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            echo -e "${RED}[ERROR] Required tool not found: $tool${NC}"
            exit 1
        fi
    done
    
    # Check kubectl cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}[ERROR] Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}[OK] Prerequisites validated${NC}"
}

# Load cluster state
load_cluster_state() {
    local state_file="$SCRIPT_DIR/cluster-state.json"
    
    if [ ! -f "$state_file" ]; then
        echo -e "${YELLOW}[WARN]  Cluster state file not found: $state_file${NC}"
        echo -e "${BLUE}[TIP] Run './workshop.sh' first to generate cluster state${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}[FILE] Loading cluster state from: $state_file${NC}"
    
    # Export cluster info from state file
    export CLUSTER_NAME=$(jq -r '.cluster_name' "$state_file")
    export AWS_REGION=$(jq -r '.region' "$state_file")
    
    echo -e "${GREEN}[OK] Cluster state loaded: $CLUSTER_NAME in $AWS_REGION${NC}"
}

# Collect Gremlin credentials
collect_gremlin_credentials() {
    if [[ "$VALIDATE_ONLY" == true ]]; then
        echo -e "${BLUE}[INFO] Validation mode - skipping credential collection${NC}"
        return 0
    fi
    
    echo -e "${BLUE}[AUTH] Collecting Gremlin credentials...${NC}"
    
    # Collect or validate Gremlin Team ID
    if [ -z "${GREMLIN_TEAM_ID:-}" ]; then
        while [ -z "${GREMLIN_TEAM_ID}" ]; do
            read -p "Enter Gremlin Team ID: " GREMLIN_TEAM_ID
        done
    fi
    export GREMLIN_TEAM_ID
    echo -e "${GREEN}✓ GREMLIN_TEAM_ID: ${GREMLIN_TEAM_ID:0:8}...${NC}"
    
    # Collect or validate Gremlin Team Secret
    if [ -z "${GREMLIN_TEAM_SECRET:-}" ]; then
        while [ -z "${GREMLIN_TEAM_SECRET}" ]; do
            read -s -p "Enter Gremlin Team Secret: " GREMLIN_TEAM_SECRET
            echo ""
        done
    fi
    export GREMLIN_TEAM_SECRET
    echo -e "${GREEN}✓ GREMLIN_TEAM_SECRET: ${GREMLIN_TEAM_SECRET:0:8}...${NC}"
    
    # Collect or validate Gremlin API Key
    if [ -z "${GREMLIN_API_KEY:-}" ]; then
        while [ -z "${GREMLIN_API_KEY}" ]; do
            read -s -p "Enter Gremlin API Key: " GREMLIN_API_KEY
            echo ""
        done
    fi
    export GREMLIN_API_KEY
    echo -e "${GREEN}✓ GREMLIN_API_KEY: ${GREMLIN_API_KEY:0:8}...${NC}"
    
    # Use API key authentication (bearer token not needed for this API)
    echo -e "${GREEN}✓ Using API key authentication${NC}"
    
    echo ""
}

# Setup DNS records for monitoring services
setup_dns_records() {
    # DNS setup is handled separately via consolidated ingress
    # Skip this step to avoid creating unnecessary Route53 records
    echo -e "${BLUE}ℹ️  Using consolidated ALB ingress (DNS setup not needed)${NC}"
    echo ""
}

# Discover cluster endpoints dynamically
discover_cluster_endpoints() {
    echo -e "${BLUE}[INFO] Discovering cluster endpoints...${NC}"
    
    local state_file="$SCRIPT_DIR/cluster-state.json"
    
    # Get scheme from state file, fallback to http
    local scheme=$(jq -r '.scheme // "http"' "$state_file" 2>/dev/null)
    if [[ -z "$scheme" ]] || [[ "$scheme" == "null" ]]; then
        scheme="http"
    fi
    
    # Get endpoints from state file
    FRONTEND_ALB=$(jq -r '.endpoints.frontend // empty' "$state_file" 2>/dev/null)
    GRAFANA_MONITORING_ALB=$(jq -r '.endpoints.grafana_monitoring // empty' "$state_file" 2>/dev/null)
    GRAFANA_OTEL_ALB=$(jq -r '.endpoints.grafana_otel // empty' "$state_file" 2>/dev/null)
    PROMETHEUS_ALB=$(jq -r '.endpoints.prometheus // empty' "$state_file" 2>/dev/null)
    
    # Add scheme to ALB endpoints if they exist and don't already have a scheme
    if [ -n "$FRONTEND_ALB" ] && [[ ! "$FRONTEND_ALB" =~ ^https?:// ]]; then
        FRONTEND_ALB="${scheme}://${FRONTEND_ALB}"
    fi
    if [ -n "$GRAFANA_MONITORING_ALB" ] && [[ ! "$GRAFANA_MONITORING_ALB" =~ ^https?:// ]]; then
        GRAFANA_MONITORING_ALB="${scheme}://${GRAFANA_MONITORING_ALB}"
    fi
    if [ -n "$GRAFANA_OTEL_ALB" ] && [[ ! "$GRAFANA_OTEL_ALB" =~ ^https?:// ]]; then
        GRAFANA_OTEL_ALB="${scheme}://${GRAFANA_OTEL_ALB}"
    fi
    if [ -n "$PROMETHEUS_ALB" ] && [[ ! "$PROMETHEUS_ALB" =~ ^https?:// ]]; then
        PROMETHEUS_ALB="${scheme}://${PROMETHEUS_ALB}"
    fi
    
    # Get DNS mappings
    # Use SUBDOMAIN if available, fallback to CLUSTER_NAME for backwards compatibility
    local dns_prefix="${SUBDOMAIN:-${CLUSTER_NAME}}"
    FRONTEND_DNS=$(jq -r --arg cluster "$CLUSTER_NAME" '.dns_mappings | to_entries[] | select(.value == "frontend") | .key' "$state_file" 2>/dev/null || echo "demo-frontend.${dns_prefix}.gremlinpoc.com")
    GRAFANA_DNS=$(jq -r --arg cluster "$CLUSTER_NAME" '.dns_mappings | to_entries[] | select(.value == "grafana_monitoring") | .key' "$state_file" 2>/dev/null || echo "monitoring.${dns_prefix}.gremlinpoc.com")
    PROMETHEUS_DNS=$(jq -r --arg cluster "$CLUSTER_NAME" '.dns_mappings | to_entries[] | select(.value == "prometheus") | .key' "$state_file" 2>/dev/null || echo "monitoring.${dns_prefix}.gremlinpoc.com/prometheus")
    
    # Add scheme to DNS endpoints if they don't already have one
    if [[ ! "$FRONTEND_DNS" =~ ^https?:// ]]; then
        FRONTEND_DNS="${scheme}://${FRONTEND_DNS}"
    fi
    if [[ ! "$GRAFANA_DNS" =~ ^https?:// ]]; then
        GRAFANA_DNS="${scheme}://${GRAFANA_DNS}"
    fi
    if [[ ! "$PROMETHEUS_DNS" =~ ^https?:// ]]; then
        PROMETHEUS_DNS="${scheme}://${PROMETHEUS_DNS}"
    fi
    
    echo -e "${GREEN}[OK] Endpoints discovered (using ${scheme}):${NC}"
    echo -e "   Frontend: ${FRONTEND_ALB:-$FRONTEND_DNS}"
    echo -e "   Grafana: ${GRAFANA_MONITORING_ALB:-$GRAFANA_DNS}"
    echo -e "   Prometheus: ${PROMETHEUS_ALB:-$PROMETHEUS_DNS}"
    echo ""
}

# Wait for endpoint readiness
wait_for_endpoint_readiness() {
    if [[ "$VALIDATE_ONLY" == true ]] || [[ "$DRY_RUN" == true ]]; then
        echo -e "${BLUE}[INFO] Skipping endpoint readiness check in validation/dry-run mode${NC}"
        return 0
    fi
    
    echo -e "${BLUE}[WAIT] Waiting for endpoint readiness...${NC}"
    
    local endpoints_to_check=()
    
    # Build endpoint list based on platforms
    for platform in "${PLATFORMS[@]}"; do
        case "$platform" in
            "prometheus")
                if [ -n "${PROMETHEUS_ALB:-}" ]; then
                    endpoints_to_check+=("$PROMETHEUS_ALB/api/v1/query?query=up")
                else
                    # PROMETHEUS_DNS already has scheme from discover_cluster_endpoints
                    endpoints_to_check+=("$PROMETHEUS_DNS/api/v1/query?query=up")
                fi
                ;;
            "grafana")
                if [ -n "${GRAFANA_MONITORING_ALB:-}" ]; then
                    endpoints_to_check+=("$GRAFANA_MONITORING_ALB/api/health")
                else
                    # GRAFANA_DNS already has scheme from discover_cluster_endpoints
                    endpoints_to_check+=("$GRAFANA_DNS/api/health")
                fi
                ;;
        esac
    done
    
    local max_attempts=10
    local attempt=1
    
    for endpoint in "${endpoints_to_check[@]}"; do
        echo -e "${YELLOW}Checking endpoint: $endpoint${NC}"
        
        while [ $attempt -le $max_attempts ]; do
            if curl -s --max-time 10 "$endpoint" > /dev/null 2>&1; then
                echo -e "${GREEN}[OK] Endpoint ready: $endpoint${NC}"
                break
            else
                echo -e "${YELLOW}[WAIT] Attempt $attempt/$max_attempts failed, waiting 30s...${NC}"
                sleep 30
                ((attempt++))
            fi
        done
        
        if [ $attempt -gt $max_attempts ]; then
            echo -e "${YELLOW}[WARN]  Endpoint not ready after $max_attempts attempts: $endpoint${NC}"
            echo -e "${BLUE}[TIP] Continuing anyway - DNS may still be propagating${NC}"
        fi
        
        attempt=1
    done
    
    echo ""
}

# Cleanup existing Gremlin services
cleanup_gremlin_services() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${BLUE}🧪 DRY RUN: Would cleanup existing Gremlin services${NC}"
        return 0
    fi
    
    if [[ "${CLEANUP_SERVICES:-false}" != true ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}🧹 Cleaning up existing Gremlin services...${NC}"
    
    # Get list of existing services
    local services_response=$(curl -s -H "Authorization: Key $GREMLIN_API_KEY" \
        "https://api.gremlin.com/v1/services?teamId=$GREMLIN_TEAM_ID" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$services_response" ]; then
        local service_ids=$(echo "$services_response" | jq -r '.[].identifier // empty' 2>/dev/null)
        
        if [ -n "$service_ids" ]; then
            echo "$service_ids" | while read -r service_id; do
                if [ -n "$service_id" ]; then
                    echo -e "${BLUE}🗑️  Deleting service: $service_id${NC}"
                    
                    local delete_response=$(curl -s -X DELETE \
                        -H "Authorization: Key $GREMLIN_API_KEY" \
                        "https://api.gremlin.com/v1/services/$service_id?teamId=$GREMLIN_TEAM_ID" 2>/dev/null)
                    
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}[OK] Service deleted: $service_id${NC}"
                    else
                        echo -e "${YELLOW}[WARN]  Failed to delete service: $service_id${NC}"
                    fi
                fi
            done
        else
            echo -e "${BLUE}[TIP] No existing services found to cleanup${NC}"
        fi
    else
        echo -e "${YELLOW}[WARN]  Failed to retrieve existing services${NC}"
    fi
    
    echo ""
}

# Create Prometheus health checks
create_prometheus_health_checks() {
    local platform="prometheus"
    echo -e "${PURPLE}[INFO] Creating Prometheus health checks...${NC}"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${BLUE}🧪 DRY RUN: Would create Prometheus health checks${NC}"
        return 0
    fi
    
    # Determine endpoint URL (already has scheme from discover_cluster_endpoints)
    local prometheus_url
    if [ -n "${PROMETHEUS_ALB:-}" ]; then
        prometheus_url="$PROMETHEUS_ALB"
    else
        prometheus_url="$PROMETHEUS_DNS"
    fi
    
    # Create Prometheus authorization for alert monitoring
    echo -e "${BLUE}📡 Creating Prometheus authorization for alert monitoring...${NC}"
    local integration_payload=$(cat << EOF
{
  "name": "prometheus-auth-working",
  "description": "Prometheus authorization for monitoring alerts",
  "type": "CUSTOM",
  "privateNetwork": false,
  "lastAuthenticationStatus": "AUTHENTICATED",
  "url": "$prometheus_url",
  "headers": {}
}
EOF
)
    
    local integration_response=$(curl -s -X POST "https://api.gremlin.com/v1/external-integrations/status-check?teamId=$GREMLIN_TEAM_ID&type=CUSTOM" \
        -H "Authorization: Key $GREMLIN_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$integration_payload" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$integration_response" ]; then
        echo -e "${GREEN}[OK] Prometheus authorization created/verified${NC}"
    else
        echo -e "${YELLOW}[WARN] Authorization may already exist, continuing...${NC}"
    fi
    
    # Create health check to monitor firing alerts count
    local check_name="prometheus-$(date +%s)"
    local health_check_payload=$(cat << EOF
{
  "name": "$check_name",
  "endpointType": "http",
  "isContinuous": true,
  "endpointConfiguration": {
    "url": "$prometheus_url/api/v1/alerts",
    "method": "GET",
    "headers": {}
  },
  "evaluationConfiguration": {
    "okStatusCodes": [200],
    "responseBodyEvaluation": {
      "op": "AND",
      "predicates": [
        {
          "comparator": "CONTAINS",
          "type": "String",
          "jpQuery": "data.alerts[*].labels.severity",
          "rValue": "critical"
        }
      ]
    }
  },
  "teamExternalIntegration": {
    "observabilityToolType": "CUSTOM",
    "name": "prometheus-auth-working"
  },
  "pollingIntervalSeconds": 30
}
EOF
)
            
            echo -e "${BLUE}[HEALTH] Creating Prometheus firing alerts health check...${NC}"
            local health_check_response=$(curl -s -X POST "https://api.gremlin.com/v1/status-checks?teamId=$GREMLIN_TEAM_ID" \
                -H "Authorization: Key $GREMLIN_API_KEY" \
                -H "Content-Type: application/json" \
                -d "$health_check_payload" 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$health_check_response" ]; then
                # Check if response contains an error
                local error_msg=$(echo "$health_check_response" | jq -r '.error // empty' 2>/dev/null)
                if [ -n "$error_msg" ]; then
                    echo -e "${RED}[ERROR] Failed to create Prometheus health check: $error_msg${NC}"
                    echo -e "${YELLOW}Response: $health_check_response${NC}"
                else
                    echo -e "${GREEN}[OK] Prometheus firing alerts health check created successfully${NC}"
                    echo -e "${BLUE}[LINK] URL: $prometheus_url/api/v1/alerts${NC}"
                fi
            else
                echo -e "${RED}[ERROR] Failed to create Prometheus health check${NC}"
                echo -e "${YELLOW}Response: $health_check_response${NC}"
            fi
    
    echo ""
}

# Create Grafana health checks
create_grafana_health_checks() {
    local platform="grafana"
    echo -e "${PURPLE}[METRICS] Creating Grafana health checks...${NC}"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${BLUE}🧪 DRY RUN: Would create Grafana health checks${NC}"
        return 0
    fi
    
    # Determine endpoint URL (already has scheme from discover_cluster_endpoints)
    local grafana_url
    if [ -n "${GRAFANA_MONITORING_ALB:-}" ]; then
        grafana_url="$GRAFANA_MONITORING_ALB"
    else
        grafana_url="$GRAFANA_DNS"
    fi
    
    # Create Grafana authorization for alert monitoring via datasource proxy
    echo -e "${BLUE}📡 Creating Grafana authorization for alert monitoring...${NC}"
    
    # Get Grafana password from environment or Kubernetes secret
    local grafana_password="${GRAFANA_ADMIN_PASSWORD:-}"
    if [ -z "$grafana_password" ]; then
        grafana_password=$(kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 --decode 2>/dev/null || echo "admin123")
    fi
    local basic_auth=$(echo -n "admin:$grafana_password" | base64)
    
    local integration_payload=$(cat << EOF
{
  "name": "grafana-auth-working",
  "description": "Grafana authorization for monitoring alerts via datasource proxy",
  "type": "CUSTOM",
  "privateNetwork": false,
  "lastAuthenticationStatus": "AUTHENTICATED",
  "url": "$grafana_url/login",
  "headers": {
    "Authorization": "Basic $basic_auth"
  }
}
EOF
)
    
    local integration_response=$(curl -s -X POST "https://api.gremlin.com/v1/external-integrations/status-check?teamId=$GREMLIN_TEAM_ID&type=CUSTOM" \
        -H "Authorization: Key $GREMLIN_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$integration_payload" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$integration_response" ]; then
        echo -e "${GREEN}[OK] Grafana authorization created/verified${NC}"
    else
        echo -e "${YELLOW}[WARN] Authorization may already exist, continuing...${NC}"
    fi
    
    # Create health check to monitor firing alerts count via Grafana datasource proxy
    local check_name="grafana-$(date +%s)"
    local health_check_payload=$(cat << EOF
{
  "name": "$check_name",
  "endpointType": "http",
  "isContinuous": true,
  "endpointConfiguration": {
    "url": "$grafana_url/api/datasources/proxy/1/api/v1/alerts",
    "method": "GET",
    "headers": {}
  },
  "evaluationConfiguration": {
    "okStatusCodes": [200],
    "responseBodyEvaluation": {
      "op": "AND",
      "predicates": [
        {
          "comparator": "CONTAINS",
          "type": "String",
          "jpQuery": "data.alerts[*].labels.severity",
          "rValue": "critical"
        }
      ]
    }
  },
  "teamExternalIntegration": {
    "observabilityToolType": "CUSTOM",
    "name": "grafana-auth-working"
  },
  "pollingIntervalSeconds": 30
}
EOF
)
            
            echo -e "${BLUE}[HEALTH] Creating Grafana firing alerts health check...${NC}"
            local health_check_response=$(curl -s -X POST "https://api.gremlin.com/v1/status-checks?teamId=$GREMLIN_TEAM_ID" \
                -H "Authorization: Key $GREMLIN_API_KEY" \
                -H "Content-Type: application/json" \
                -d "$health_check_payload" 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$health_check_response" ]; then
                # Check if response contains an error
                local error_msg=$(echo "$health_check_response" | jq -r '.error // empty' 2>/dev/null)
                if [ -n "$error_msg" ]; then
                    echo -e "${RED}[ERROR] Failed to create Grafana health check: $error_msg${NC}"
                    echo -e "${YELLOW}Response: $health_check_response${NC}"
                else
                    # API returns plain UUID string on success, not JSON
                    if [[ "$health_check_response" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
                        echo -e "${GREEN}[OK] Grafana firing alerts health check created: $health_check_response${NC}"
                        echo -e "${BLUE}[LINK] URL: $grafana_url/api/datasources/proxy/1/api/v1/alerts${NC}"
                    else
                        echo -e "${RED}[ERROR] Failed to create Grafana health check (unexpected response)${NC}"
                        echo -e "${YELLOW}Response: $health_check_response${NC}"
                    fi
                fi
            else
                echo -e "${RED}[ERROR] Failed to create Grafana health check - API call failed${NC}"
            fi
    
    echo ""
}

# Create platform-specific health checks
create_platform_health_checks() {
    echo -e "${CYAN}[HEALTH] Creating health checks for platforms: ${PLATFORMS[*]}${NC}"
    
    for platform in "${PLATFORMS[@]}"; do
        case "$platform" in
            "prometheus")
                create_prometheus_health_checks
                ;;
            "grafana")
                create_grafana_health_checks
                ;;
            "dynatrace")
                echo -e "${YELLOW}[WARN]  Dynatrace health checks not yet implemented${NC}"
                ;;
            "newrelic")
                echo -e "${YELLOW}[WARN]  New Relic health checks not yet implemented${NC}"
                ;;
            *)
                echo -e "${RED}[ERROR] Unknown platform: $platform${NC}"
                ;;
        esac
    done
}

# Validate existing health checks
validate_health_checks() {
    echo -e "${BLUE}[INFO] Validating existing health checks...${NC}"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${BLUE}🧪 DRY RUN: Would validate existing health checks${NC}"
        return 0
    fi
    
    # Get list of existing health checks
    local health_checks_response=$(curl -s -H "Authorization: Key $GREMLIN_API_KEY" \
        "https://api.gremlin.com/v1/status-checks?teamId=$GREMLIN_TEAM_ID" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$health_checks_response" ]; then
        local health_check_count=$(echo "$health_checks_response" | jq '. | length' 2>/dev/null)
        
        if [ -n "$health_check_count" ] && [ "$health_check_count" != "null" ]; then
            echo -e "${GREEN}[OK] Found $health_check_count existing health checks${NC}"
            
            # Show health check details
            echo "$health_checks_response" | jq -r '.[] | "  • \(.name) (\(.identifier)) - \(.description)"' 2>/dev/null || true
        else
            echo -e "${YELLOW}[WARN]  No health checks found${NC}"
        fi
    else
        echo -e "${RED}[ERROR] Failed to retrieve health checks${NC}"
    fi
    
    echo ""
}

# Display summary
display_summary() {
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    [HEALTH] HEALTH CHECKS SUMMARY [HEALTH]               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${GREEN}[TARGET] COMPLETED ACTIONS:${NC}"
    if [[ "$VALIDATE_ONLY" == true ]]; then
        echo -e "   • Validated existing health checks"
    elif [[ "$DRY_RUN" == true ]]; then
        echo -e "   • Dry run completed - no changes made"
    else
        echo -e "   • Collected Gremlin credentials"
        echo -e "   • Discovered cluster endpoints"
        echo -e "   • Created health checks for: ${PLATFORMS[*]}"
        if [[ "${CLEANUP_SERVICES:-false}" == true ]]; then
            echo -e "   • Cleaned up existing Gremlin services"
        fi
    fi
    echo ""
    
    echo -e "${BLUE}[LINK] USEFUL LINKS:${NC}"
    echo -e "   • Gremlin Health Checks: https://app.gremlin.com/reliability/status-checks"
    echo -e "   • Gremlin Services: https://app.gremlin.com/services"
    echo -e "   • Team Dashboard: https://app.gremlin.com/team/$GREMLIN_TEAM_ID"
    echo ""
    
    echo -e "${YELLOW}[TIP] NEXT STEPS:${NC}"
    echo -e "   1. Visit Gremlin dashboard to verify health checks"
    echo -e "   2. Run chaos experiments targeting your services"
    echo -e "   3. Monitor health check status during experiments"
    echo -e "   4. Use health checks to validate system resilience"
    echo ""
    
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
}

# Main function
main() {
    print_banner
    parse_arguments "$@"
    validate_prerequisites
    load_cluster_state
    
    if [[ "$VALIDATE_ONLY" == true ]]; then
        echo -e "${BLUE}[INFO] Running in validation mode...${NC}"
        collect_gremlin_credentials
        validate_health_checks
    else
        collect_gremlin_credentials
        setup_dns_records
        discover_cluster_endpoints
        wait_for_endpoint_readiness
        cleanup_gremlin_services
        create_platform_health_checks
        validate_health_checks
    fi
    
    display_summary
    
    echo -e "${GREEN}[OK] Health checks setup completed successfully!${NC}"
}

# Run main function with all arguments
main "$@"
