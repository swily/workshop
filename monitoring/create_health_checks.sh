#!/bin/bash

# Unified Health Check Creator for Gremlin
# Creates health checks for Prometheus, Grafana, Dynatrace, New Relic, and DataDog

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
PLATFORMS=()
DRY_RUN=false

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Unified health check creator for multiple monitoring platforms.

OPTIONS:
  --platform PLATFORM    Platform to create health checks for
                        (prometheus|grafana|dynatrace|newrelic|datadog|all)
                        Can be specified multiple times
  --dry-run             Show what would be created without making changes
  --help                Show this help message

EXAMPLES:
  $0 --platform prometheus --platform grafana
  $0 --platform all
  $0 --platform dynatrace
  $0 --dry-run --platform all

ENVIRONMENT VARIABLES:
  Gremlin:
    GREMLIN_TEAM_ID       Gremlin team ID
    GREMLIN_API_KEY       Gremlin API key
  
  Grafana/Prometheus:
    GRAFANA_ADMIN_PASSWORD  Grafana admin password (default: from k8s secret)
  
  Dynatrace:
    DYNATRACE_INSTANCE_ID   Dynatrace instance ID
    DYNATRACE_API_TOKEN     Dynatrace API token
  
  New Relic:
    NEW_RELIC_API_KEY       New Relic API key
    NEW_RELIC_ACCOUNT_ID    New Relic account ID
  
  DataDog:
    DATADOG_API_KEY         DataDog API key
    DATADOG_APP_KEY         DataDog application key
    DATADOG_SITE            DataDog site (default: datadoghq.com)

EOF
}

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --platform)
                PLATFORMS+=("$2")
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                export DRY_RUN
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Default to prometheus and grafana if no platforms specified
    if [ ${#PLATFORMS[@]} -eq 0 ]; then
        PLATFORMS=("prometheus" "grafana")
    fi
    
    # Expand "all" to all platforms
    if [[ " ${PLATFORMS[*]} " =~ " all " ]]; then
        PLATFORMS=("prometheus" "grafana" "dynatrace" "newrelic" "datadog")
    fi
}

# Create health checks for a platform
create_platform_health_checks() {
    local platform="$1"
    
    case "$platform" in
        prometheus|grafana)
            echo -e "${CYAN}Creating health checks for Prometheus/Grafana...${NC}"
            if [ -f "$SCRIPT_DIR/../build_scripts/demo/healthchecks.sh" ]; then
                bash "$SCRIPT_DIR/../build_scripts/demo/healthchecks.sh" --platform prometheus --platform grafana
            else
                echo -e "${RED}Error: Prometheus/Grafana health check script not found${NC}"
                return 1
            fi
            ;;
        dynatrace)
            echo -e "${CYAN}Creating health checks for Dynatrace...${NC}"
            if [ -f "$SCRIPT_DIR/dynatrace/create_health_checks.sh" ]; then
                bash "$SCRIPT_DIR/dynatrace/create_health_checks.sh"
            else
                echo -e "${RED}Error: Dynatrace health check script not found${NC}"
                return 1
            fi
            ;;
        newrelic)
            echo -e "${CYAN}Creating health checks for New Relic...${NC}"
            if [ -f "$SCRIPT_DIR/newrelic/create_health_checks.sh" ]; then
                bash "$SCRIPT_DIR/newrelic/create_health_checks.sh"
            else
                echo -e "${RED}Error: New Relic health check script not found${NC}"
                return 1
            fi
            ;;
        datadog)
            echo -e "${CYAN}Creating health checks for DataDog...${NC}"
            if [ -f "$SCRIPT_DIR/datadog/create_health_checks.sh" ]; then
                bash "$SCRIPT_DIR/datadog/create_health_checks.sh"
            else
                echo -e "${RED}Error: DataDog health check script not found${NC}"
                return 1
            fi
            ;;
        *)
            echo -e "${RED}Unknown platform: $platform${NC}"
            return 1
            ;;
    esac
}

# Main
main() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          Unified Health Check Creator for Gremlin           ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    parse_arguments "$@"
    
    echo -e "${BLUE}Platforms selected: ${PLATFORMS[*]}${NC}"
    echo ""
    
    # Remove duplicates and handle prometheus/grafana together
    local unique_platforms=()
    local has_prometheus=false
    local has_grafana=false
    
    for platform in "${PLATFORMS[@]}"; do
        if [[ "$platform" == "prometheus" ]]; then
            has_prometheus=true
        elif [[ "$platform" == "grafana" ]]; then
            has_grafana=true
        elif [[ ! " ${unique_platforms[*]} " =~ " ${platform} " ]]; then
            unique_platforms+=("$platform")
        fi
    done
    
    # Add prometheus/grafana as single entry if either was requested
    if [[ "$has_prometheus" == true ]] || [[ "$has_grafana" == true ]]; then
        if [ ${#unique_platforms[@]} -eq 0 ]; then
            unique_platforms=("prometheus")
        else
            unique_platforms=("prometheus" "${unique_platforms[@]}")
        fi
    fi
    
    # Create health checks for each platform
    local success_count=0
    local fail_count=0
    
    for platform in "${unique_platforms[@]}"; do
        echo ""
        if create_platform_health_checks "$platform"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    # Summary
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                         SUMMARY                              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}✅ Successful: $success_count${NC}"
    if [ $fail_count -gt 0 ]; then
        echo -e "${RED}❌ Failed: $fail_count${NC}"
    fi
    echo ""
    echo -e "${BLUE}View health checks: https://app.gremlin.com/reliability/status-checks${NC}"
    echo ""
    
    if [ $fail_count -gt 0 ]; then
        exit 1
    fi
}

main "$@"
