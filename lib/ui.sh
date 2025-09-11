#!/bin/bash
#
# User Interface functions for workshop scripts
# Handles user input collection, menus, and interactive prompts
#

# Source common functions if not already loaded
if [[ -z "$RED" ]]; then
    LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$LIB_DIR/common.sh"
fi

# Shared help formatting helpers
help_header() {
    local title="$1"
    local description="$2"
    echo "Usage: $0 [OPTIONS]"
    echo ""
    if [[ -n "$title" ]]; then
        echo "$title"
    fi
    if [[ -n "$description" ]]; then
        echo ""
        echo "$description"
    fi
}

help_footer() {
    echo ""
    echo "-h, --help             Show this help message"
}

# Global variables for user choices
WORKSHOP_ACTION=""
CLUSTER_NAME=""
AWS_REGION="us-east-2"
GREMLIN_TEAM_ID=""
GREMLIN_TEAM_SECRET=""
GREMLIN_API_KEY=""
GREMLIN_BEARER_TOKEN=""
MONITORING_PLATFORM=""
DYNATRACE_API_TOKEN=""
DYNATRACE_INSTANCE_ID=""
NEWRELIC_API_KEY=""
APPLY_PATCHES=true
APPLY_GREMLIN_ENHANCEMENTS=true

# Function to collect workshop action
collect_workshop_action() {
    echo -e "${BLUE}What would you like to do?${NC}"
    echo ""
    echo -e "${GREEN}1)${NC} 🏗️  Build new cluster from scratch & deploy everything"
    echo -e "${GREEN}2)${NC} 📦 Deploy to existing cluster"  
    echo -e "${GREEN}3)${NC} 🐒 Point cluster to different Gremlin team"
    echo -e "${GREEN}4)${NC} 🧽 Cleanup/Delete cluster"
    echo ""
    
    while true; do
        read -p "Enter your choice (1-4): " choice
        case $choice in
            1) WORKSHOP_ACTION="build_new"; break ;;
            2) WORKSHOP_ACTION="deploy_existing"; break ;;
            3) WORKSHOP_ACTION="run_gremlin_only"; break ;;
            4) WORKSHOP_ACTION="cleanup"; break ;;
            *) log_error "Invalid choice. Please enter 1-4." ;;
        esac
    done
    echo ""
    echo "$WORKSHOP_ACTION"
}

# Function to collect cluster information
collect_cluster_info() {
    if [[ "$WORKSHOP_ACTION" == "build_new" || "$WORKSHOP_ACTION" == "clean_deploy" || "$WORKSHOP_ACTION" == "deploy_existing" || "$WORKSHOP_ACTION" == "run_gremlin_only" || "$WORKSHOP_ACTION" == "cleanup" ]]; then
        while [ -z "${CLUSTER_NAME}" ]; do
            if [ "$WORKSHOP_ACTION" == "build_new" ]; then
                read -p "Enter new cluster name: " CLUSTER_NAME
            elif [ "$WORKSHOP_ACTION" == "clean_deploy" ]; then
                read -p "Enter cluster name to clean and redeploy: " CLUSTER_NAME
            elif [ "$WORKSHOP_ACTION" == "deploy_existing" ]; then
                read -p "Enter existing cluster name to deploy to: " CLUSTER_NAME
            elif [ "$WORKSHOP_ACTION" == "run_gremlin_only" ]; then
                read -p "Enter existing cluster name for Gremlin setup: " CLUSTER_NAME
            elif [ "$WORKSHOP_ACTION" == "cleanup" ]; then
                read -p "Enter cluster name to delete: " CLUSTER_NAME
            fi
        done
        export CLUSTER_NAME
    fi
    
    # AWS Region - check if REGION environment variable is set
    if [ -z "${AWS_REGION}" ] && [ -n "${REGION}" ]; then
        AWS_REGION="${REGION}"
        log_success "Using REGION environment variable: ${AWS_REGION}"
    elif [ -n "${AWS_REGION}" ] && [ -z "${REGION}" ]; then
        log_success "Using existing AWS_REGION: ${AWS_REGION}"
    elif [ -n "${REGION}" ]; then
        AWS_REGION="${REGION}"
        log_success "Using REGION environment variable: ${AWS_REGION}"
    else
        read -p "Enter AWS region [${AWS_REGION}]: " input_region
        AWS_REGION=${input_region:-$AWS_REGION}
    fi
    export AWS_REGION
    export AWS_DEFAULT_REGION=${AWS_REGION}
    
    echo "$CLUSTER_NAME:$AWS_REGION"
}

# Function to collect Gremlin credentials
collect_gremlin_credentials() {
    log_section "Gremlin Configuration"
    
    # Gremlin Team ID
    if [ -z "${GREMLIN_TEAM_ID}" ]; then
        echo -e "${BLUE}Enter your Gremlin Team ID:${NC}"
        echo -e "${YELLOW}(Find this at: https://app.gremlin.com/settings/teams)${NC}"
        read -p "Team ID [438c58ec-03db-47ac-8c58-ec03db67ac42]: " input_team_id
        GREMLIN_TEAM_ID=${input_team_id:-"438c58ec-03db-47ac-8c58-ec03db67ac42"}
    fi
    
    # Gremlin Team Secret
    if [ -z "${GREMLIN_TEAM_SECRET}" ]; then
        echo -e "${BLUE}Enter your Gremlin Team Secret:${NC}"
        echo -e "${YELLOW}(Find this at: https://app.gremlin.com/settings/teams)${NC}"
        read -p "Team Secret [680010a2-b4b7-4540-8010-a2b4b7b54031]: " input_team_secret
        GREMLIN_TEAM_SECRET=${input_team_secret:-"680010a2-b4b7-4540-8010-a2b4b7b54031"}
    fi
    
    # Gremlin API Key (for health checks)
    if [ -z "${GREMLIN_API_KEY}" ]; then
        echo -e "${BLUE}Enter your Gremlin API Key (for health checks):${NC}"
        echo -e "${YELLOW}(Create at: https://app.gremlin.com/settings/api-keys)${NC}"
        read -p "API Key [14bdb4c5b41e93955d4b0a32f79ddf93bac61cccd4ce59ed29b937fba2b970f7]: " input_api_key
        GREMLIN_API_KEY=${input_api_key:-"14bdb4c5b41e93955d4b0a32f79ddf93bac61cccd4ce59ed29b937fba2b970f7"}
    fi
    
    export GREMLIN_TEAM_ID
    export GREMLIN_TEAM_SECRET
    export GREMLIN_API_KEY
    
    log_success "Gremlin credentials configured"
}

# Function to collect monitoring platform choice
collect_monitoring_platform() {
    log_section "Monitoring Platform Selection"
    
    echo -e "${BLUE}Select your primary monitoring platform:${NC}"
    echo ""
    echo -e "${GREEN}1)${NC} 📊 Grafana + Prometheus (Open Source)"
    echo -e "${GREEN}2)${NC} 🔍 Dynatrace"
    echo -e "${GREEN}3)${NC} 📈 New Relic"
    echo -e "${GREEN}4)${NC} 📉 DataDog"
    echo -e "${GREEN}5)${NC} 🎯 AppDynamics"
    echo -e "${GREEN}6)${NC} 🚫 Skip monitoring setup"
    echo ""
    
    while true; do
        read -p "Enter your choice (1-6): " choice
        case $choice in
            1) MONITORING_PLATFORM="grafana"; break ;;
            2) MONITORING_PLATFORM="dynatrace"; break ;;
            3) MONITORING_PLATFORM="newrelic"; break ;;
            4) MONITORING_PLATFORM="datadog"; break ;;
            5) MONITORING_PLATFORM="appdynamics"; break ;;
            6) MONITORING_PLATFORM="none"; break ;;
            *) log_error "Invalid choice. Please enter 1-6." ;;
        esac
    done
    
    export MONITORING_PLATFORM
    log_success "Selected monitoring platform: $MONITORING_PLATFORM"
    
    # Collect platform-specific credentials
    case "$MONITORING_PLATFORM" in
        "dynatrace")
            collect_dynatrace_credentials
            ;;
        "newrelic")
            collect_newrelic_credentials
            ;;
        "datadog")
            collect_datadog_credentials
            ;;
        "appdynamics")
            collect_appdynamics_credentials
            ;;
    esac
    
    echo "$MONITORING_PLATFORM"
}

# Function to collect Dynatrace credentials
collect_dynatrace_credentials() {
    log_info "Configuring Dynatrace integration..."
    
    if [ -z "${DYNATRACE_API_TOKEN}" ]; then
        echo -e "${BLUE}Enter your Dynatrace API Token:${NC}"
        echo -e "${YELLOW}(Create at: https://[your-environment].dynatrace.com/ui/settings/integration/apikeys)${NC}"
        read -p "API Token: " DYNATRACE_API_TOKEN
    fi
    
    if [ -z "${DYNATRACE_INSTANCE_ID}" ]; then
        echo -e "${BLUE}Enter your Dynatrace Instance ID:${NC}"
        echo -e "${YELLOW}(Format: abc12345 from https://abc12345.dynatrace.com)${NC}"
        read -p "Instance ID: " DYNATRACE_INSTANCE_ID
    fi
    
    export DYNATRACE_API_TOKEN
    export DYNATRACE_INSTANCE_ID
}

# Function to collect New Relic credentials
collect_newrelic_credentials() {
    log_info "Configuring New Relic integration..."
    
    if [ -z "${NEWRELIC_API_KEY}" ]; then
        echo -e "${BLUE}Enter your New Relic License Key:${NC}"
        echo -e "${YELLOW}(Find at: https://one.newrelic.com/launcher/api-keys-ui.api-keys-launcher)${NC}"
        read -p "License Key: " NEWRELIC_API_KEY
    fi
    
    export NEWRELIC_API_KEY
}

# Function to collect DataDog credentials
collect_datadog_credentials() {
    log_info "Configuring DataDog integration..."
    
    if [ -z "${DATADOG_API_KEY}" ]; then
        echo -e "${BLUE}Enter your DataDog API Key:${NC}"
        echo -e "${YELLOW}(Find at: https://app.datadoghq.com/organization-settings/api-keys)${NC}"
        read -p "API Key: " DATADOG_API_KEY
    fi
    
    if [ -z "${DATADOG_APP_KEY}" ]; then
        echo -e "${BLUE}Enter your DataDog Application Key:${NC}"
        echo -e "${YELLOW}(Find at: https://app.datadoghq.com/organization-settings/application-keys)${NC}"
        read -p "Application Key: " DATADOG_APP_KEY
    fi
    
    export DATADOG_API_KEY
    export DATADOG_APP_KEY
}

# Function to collect AppDynamics credentials
collect_appdynamics_credentials() {
    log_info "Configuring AppDynamics integration..."
    
    if [ -z "${APPDYNAMICS_CONTROLLER_HOST}" ]; then
        echo -e "${BLUE}Enter your AppDynamics Controller Host:${NC}"
        echo -e "${YELLOW}(Format: mycompany.saas.appdynamics.com)${NC}"
        read -p "Controller Host: " APPDYNAMICS_CONTROLLER_HOST
    fi
    
    if [ -z "${APPDYNAMICS_ACCOUNT_NAME}" ]; then
        echo -e "${BLUE}Enter your AppDynamics Account Name:${NC}"
        read -p "Account Name: " APPDYNAMICS_ACCOUNT_NAME
    fi
    
    if [ -z "${APPDYNAMICS_API_KEY}" ]; then
        echo -e "${BLUE}Enter your AppDynamics API Key:${NC}"
        read -p "API Key: " APPDYNAMICS_API_KEY
    fi
    
    export APPDYNAMICS_CONTROLLER_HOST
    export APPDYNAMICS_ACCOUNT_NAME
    export APPDYNAMICS_API_KEY
}

# Function to collect advanced options
collect_advanced_options() {
    log_section "Advanced Options"
    
    echo -e "${BLUE}Configure advanced options:${NC}"
    echo ""
    
    # Apply patches
    if confirm_action "Apply performance and reliability patches?" "y"; then
        APPLY_PATCHES=true
    else
        APPLY_PATCHES=false
    fi
    
    # Apply Gremlin enhancements
    if confirm_action "Apply Gremlin service discovery enhancements?" "y"; then
        APPLY_GREMLIN_ENHANCEMENTS=true
    else
        APPLY_GREMLIN_ENHANCEMENTS=false
    fi
    
    export APPLY_PATCHES
    export APPLY_GREMLIN_ENHANCEMENTS
    
    log_success "Advanced options configured"
}

# Function to display configuration summary
display_configuration_summary() {
    log_section "Configuration Summary"
    
    echo -e "${CYAN}Workshop Configuration:${NC}"
    echo "  Action: $WORKSHOP_ACTION"
    echo "  Cluster: $CLUSTER_NAME"
    echo "  Region: $AWS_REGION"
    echo "  Monitoring: $MONITORING_PLATFORM"
    echo "  Apply Patches: $APPLY_PATCHES"
    echo "  Gremlin Enhancements: $APPLY_GREMLIN_ENHANCEMENTS"
    echo ""
    
    if ! confirm_action "Proceed with this configuration?" "y"; then
        log_info "Configuration cancelled by user"
        exit 0
    fi
}

# Function to wait for DNS propagation
wait_for_dns_propagation() {
    if confirm_action "Wait for DNS propagation before creating health checks?" "n"; then
        log_info "Waiting for DNS propagation..."
        echo "This typically takes 5-10 minutes for Route53 changes to propagate globally."
        echo "You can monitor propagation at: https://www.whatsmydns.net/"
        
        for i in {1..10}; do
            echo "Waiting... ($i/10 minutes)"
            sleep 60
        done
        
        log_success "DNS propagation wait completed"
    else
        log_info "Skipping DNS propagation wait"
        log_warning "Remember to wait for DNS propagation before running health checks"
    fi
}

# Function to display workshop endpoints
display_workshop_endpoints() {
    log_section "Workshop Endpoints"
    
    echo -e "${CYAN}Your workshop is ready! Access it via:${NC}"
    echo ""
    
    # Get current endpoints
    local frontend_alb=$(kubectl get ingress -n otel-demo frontend-proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Not available")
    local grafana_alb=$(kubectl get ingress -n monitoring grafana-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Not available")
    local prometheus_alb=$(kubectl get ingress -n otel-demo prometheus-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Not available")
    
    echo -e "${GREEN}🌐 Direct ALB Endpoints:${NC}"
    echo "  Frontend:    http://$frontend_alb"
    echo "  Grafana:     http://$grafana_alb"
    echo "  Prometheus:  http://$prometheus_alb"
    echo ""
    
    echo -e "${GREEN}🔗 DNS Endpoints (after propagation):${NC}"
    echo "  Frontend:    https://$CLUSTER_NAME-frontend.gremlinpoc.com"
    echo "  Grafana:     https://$CLUSTER_NAME-grafana.gremlinpoc.com"
    echo "  Prometheus:  https://$CLUSTER_NAME-prometheus.gremlinpoc.com"
    echo ""
    
    echo -e "${GREEN}🐒 Gremlin Integration:${NC}"
    echo "  Team ID:     $GREMLIN_TEAM_ID"
    echo "  Cluster ID:  $CLUSTER_NAME"
    echo "  Web UI:      https://app.gremlin.com"
    echo ""
    
    echo -e "${YELLOW}📋 Next Steps:${NC}"
    echo "1. Wait for DNS propagation (5-10 minutes)"
    echo "2. Run health checks: ./build_scripts/demo/healthchecks.sh"
    echo "3. Create Gremlin experiments at: https://app.gremlin.com"
    echo "4. Monitor results in your chosen observability platform"
    echo ""
}

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

DESCRIPTION:
  Interactive workshop orchestration script for OpenTelemetry Demo with
  integrated monitoring and chaos engineering capabilities.

OPTIONS:
  --cluster-name NAME     Specify cluster name (skips interactive prompt)
  --region REGION         Specify AWS region (skips interactive prompt)
  --monitoring PLATFORM   Specify monitoring platform: grafana|dynatrace|newrelic|datadog|appdynamics|none
  --action ACTION         Specify action: build_new|deploy_existing|gremlin_only|cleanup
  --gremlin-team-id ID    Specify Gremlin team ID
  --gremlin-team-secret SECRET  Specify Gremlin team secret
  --gremlin-api-key KEY   Specify Gremlin API key
  --skip-patches          Skip applying performance patches
  --skip-gremlin-enhancements  Skip Gremlin service discovery enhancements
  --dry-run              Show what would be done without executing
  -h, --help             Show this help message

EXAMPLES:
  $0                                    # Interactive mode
  $0 --action build_new --cluster-name my-cluster --region us-west-2
  $0 --action deploy_existing --cluster-name existing-cluster --monitoring grafana
  $0 --action gremlin_only --cluster-name test-cluster

MONITORING PLATFORMS:
  grafana      - Grafana + Prometheus (open source)
  dynatrace    - Dynatrace APM
  newrelic     - New Relic One
  datadog      - DataDog APM
  appdynamics  - AppDynamics APM
  none         - Skip monitoring setup

For more information, visit: https://github.com/your-org/workshop
EOF
}
