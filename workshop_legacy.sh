#!/bin/bash
#
# Enhanced Master Workshop Orchestration Script
# OpenTelemetry Demo Workshop Setup with Integrated Monitoring & Chaos Engineering
#

set -e

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

# ASCII Art Banner
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║    🚀 OpenTelemetry Demo Workshop Orchestration 🚀          ║"
    echo "║                                                              ║"
    echo "║    Complete Observability & Chaos Engineering Platform      ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# Function to validate prerequisites
validate_prerequisites() {
    echo -e "${BLUE}🔍 Validating prerequisites...${NC}"
    
    local missing_tools=()
    
    # Check required tools
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    command -v aws >/dev/null 2>&1 || missing_tools+=("aws")
    command -v eksctl >/dev/null 2>&1 || missing_tools+=("eksctl")
    command -v istioctl >/dev/null 2>&1 || missing_tools+=("istioctl")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${RED}❌ Missing required tools: ${missing_tools[*]}${NC}"
        echo -e "${YELLOW}Please install the missing tools and try again.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ All prerequisites validated${NC}"
    echo ""
}

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
            *) echo -e "${RED}❌ Invalid choice. Please enter 1-4.${NC}" ;;
        esac
    done
    echo ""
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
        echo -e "${GREEN}✓ Using REGION environment variable: ${AWS_REGION}${NC}"
    elif [ -n "${AWS_REGION}" ] && [ -z "${REGION}" ]; then
        echo -e "${GREEN}✓ Using existing AWS_REGION: ${AWS_REGION}${NC}"
    elif [ -n "${REGION}" ]; then
        AWS_REGION="${REGION}"
        echo -e "${GREEN}✓ Using REGION environment variable: ${AWS_REGION}${NC}"
    else
        read -p "Enter AWS region [${AWS_REGION}]: " input_region
        AWS_REGION=${input_region:-$AWS_REGION}
    fi
    export AWS_REGION
    export AWS_DEFAULT_REGION=${AWS_REGION}
}

# Function to validate cluster exists
validate_cluster_exists() {
    echo -e "${BLUE}🔍 Validating cluster exists...${NC}"
    
    if ! aws eks describe-cluster --region "${AWS_REGION}" --name "${CLUSTER_NAME}" >/dev/null 2>&1; then
        echo -e "${RED}❌ Cluster '${CLUSTER_NAME}' not found in region '${AWS_REGION}'${NC}"
        echo -e "${YELLOW}Please check the cluster name and region, or create the cluster first.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Cluster '${CLUSTER_NAME}' found and accessible${NC}"
}

# Function to validate monitoring namespace exists
validate_monitoring_namespace() {
    if ! kubectl get namespace monitoring >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Monitoring namespace not found, creating...${NC}"
        kubectl create namespace monitoring || {
            echo -e "${RED}❌ Failed to create monitoring namespace${NC}"
            return 1
        }
    fi
    echo -e "${GREEN}✅ Monitoring namespace ready${NC}"
}

# Export cluster state for build_scripts/demo/healthchecks.sh
export_cluster_state() {
    echo -e "${BLUE}📤 Exporting cluster state for health check creation...${NC}"
    
    local state_file="$SCRIPT_DIR/cluster-state.json"
    local cluster_name="${CLUSTER_NAME:-current-workshop}"
    local region="${AWS_REGION:-us-east-2}"
    
    # Discover ALB endpoints dynamically
    echo -e "${YELLOW}Discovering ALB endpoints...${NC}"
    
    local frontend_alb=$(kubectl get ingress -n otel-demo frontend-proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    local grafana_monitoring_alb=$(kubectl get ingress -n monitoring grafana-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    local grafana_otel_alb=$(kubectl get ingress -n otel-demo grafana-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    local prometheus_alb=$(kubectl get ingress -n otel-demo prometheus-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    # Fallback to LoadBalancer services if ingress not available
    if [ -z "$frontend_alb" ]; then
        frontend_alb=$(kubectl get svc -n otel-demo frontend-proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    fi
    
    # Create state file
    cat > "$state_file" << EOF
{
  "cluster_name": "$cluster_name",
  "region": "$region",
  "endpoints": {
    "frontend": "${frontend_alb:+http://$frontend_alb}",
    "grafana_monitoring": "${grafana_monitoring_alb:+http://$grafana_monitoring_alb}",
    "grafana_otel": "${grafana_otel_alb:+http://$grafana_otel_alb}",
    "prometheus": "${prometheus_alb:+http://$prometheus_alb}"
  },
  "dns_mappings": {
    "$cluster_name-frontend.gremlinpoc.com": "frontend",
    "$cluster_name-grafana.gremlinpoc.com": "grafana_monitoring",
    "$cluster_name-prometheus.gremlinpoc.com": "prometheus"
  },
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    echo -e "${GREEN}✅ Cluster state exported to: $state_file${NC}"
    echo -e "${BLUE}💡 Run './build_scripts/demo/healthchecks.sh' after DNS propagation to create health checks${NC}"
    echo ""
}

# Core implementation functions
run_full_build_new_cluster() {
    echo -e "${GREEN}🚀 Starting full build with new cluster...${NC}"
    
    # Create new EKS cluster
    "$SCRIPT_DIR/build_scripts/cluster/create.sh" "$CLUSTER_NAME" "$AWS_REGION"
    
    # Configure cluster base components
    "$SCRIPT_DIR/build_scripts/cluster/base_setup.sh" --install-istio --monitoring-type="$MONITORING_PLATFORM"
    
    # Deploy OpenTelemetry demo
    "$SCRIPT_DIR/build_scripts/demo/otel_demo.sh" --cluster-name "$CLUSTER_NAME"
    
    # Install Gremlin
    "$SCRIPT_DIR/build_scripts/gremlin/install.sh"
    
    # Setup comprehensive monitoring with master orchestration
    setup_comprehensive_monitoring
    
    # Install load balancer
    "$SCRIPT_DIR/build_scripts/load-balancer/install.sh"
    
    # Export cluster state for health checks
    export_cluster_state
    
    # Optional DNS propagation wait
    wait_for_dns_propagation
    
    # Display final endpoint summary
    display_workshop_endpoints
    
    echo -e "${GREEN}✅ Full build with new cluster completed successfully!${NC}"
}

run_clean_and_deploy() {
    echo -e "${YELLOW}🧹 Starting clean deployment on existing cluster...${NC}"
    
    # Clean existing deployments
    kubectl delete namespace otel-demo --ignore-not-found=true
    kubectl delete namespace gremlin --ignore-not-found=true
    
    # Wait for cleanup
    echo "Waiting for namespace cleanup..."
    sleep 30
    
    # Deploy fresh components
    run_deploy_only
    
    # Display final endpoint summary
    display_workshop_endpoints
    
    echo -e "${GREEN}✅ Clean deployment completed successfully!${NC}"
}

run_deploy_only() {
    echo -e "${BLUE}📦 Deploying to existing cluster...${NC}"
    
    # Deploy OpenTelemetry demo
    "$SCRIPT_DIR/build_scripts/demo/otel_demo.sh" --cluster-name "$CLUSTER_NAME"
    
    # Install Gremlin
    "$SCRIPT_DIR/build_scripts/gremlin/install.sh"
    
    # Setup comprehensive monitoring
    setup_comprehensive_monitoring
    
    # Update load balancer configuration
    "$SCRIPT_DIR/build_scripts/load-balancer/install.sh"
    
    # Export cluster state for health checks
    export_cluster_state
    
    # Optional DNS propagation wait
    wait_for_dns_propagation
    
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
}

run_gremlin_only() {
{{ ... }}
    echo -e "${PURPLE}🐵 Installing Gremlin components only...${NC}"
    
    # Install Gremlin agent
    "$SCRIPT_DIR/build_scripts/gremlin/install.sh"
    
    # Setup Gremlin-specific monitoring and health checks
    setup_gremlin_monitoring
    
    echo -e "${GREEN}✅ Gremlin installation completed successfully!${NC}"
}

run_cleanup() {
    echo -e "${RED}🗑️  Starting cleanup...${NC}"
    
    # Remove monitoring components
    if [ -f "$SCRIPT_DIR/monitoring/setup_monitoring.sh" ]; then
        "$SCRIPT_DIR/monitoring/setup_monitoring.sh" --remove-all
    fi
    
    # Remove OpenTelemetry demo
    kubectl delete namespace otel-demo --ignore-not-found=true
    
    # Remove Gremlin
    kubectl delete namespace gremlin --ignore-not-found=true
    
    # Remove load balancer resources
    kubectl delete ingress --all --all-namespaces --ignore-not-found=true
    
    # Optionally delete cluster (with confirmation)
    if [ -n "$CLUSTER_NAME" ]; then
        echo -e "${YELLOW}Do you want to delete the EKS cluster '$CLUSTER_NAME'? (y/N)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            eksctl delete cluster --name="$CLUSTER_NAME" --region="$AWS_REGION"
        fi
    fi
    
    echo -e "${GREEN}✅ Cleanup completed successfully!${NC}"
}

# Comprehensive monitoring setup with master orchestration
setup_comprehensive_monitoring() {
    echo -e "${CYAN}Setting up comprehensive monitoring platform...${NC}"
    
    # Use master monitoring orchestration script
    if [ -f "$SCRIPT_DIR/monitoring/setup_monitoring.sh" ]; then
        case "$MONITORING_PLATFORM" in
            "prometheus")
                "$SCRIPT_DIR/monitoring/setup_monitoring.sh" --prometheus-only --create-gremlin-checks
                ;;
            "dynatrace")
                "$SCRIPT_DIR/monitoring/setup_monitoring.sh" --dynatrace-only --create-gremlin-checks
                ;;
            "newrelic")
                "$SCRIPT_DIR/monitoring/setup_monitoring.sh" --newrelic-only --create-gremlin-checks
                ;;
            "aws")
                "$SCRIPT_DIR/monitoring/setup_monitoring.sh" --aws-only --create-gremlin-checks
                ;;
            *)
                echo -e "${YELLOW}Unknown monitoring platform: $MONITORING_PLATFORM, defaulting to Prometheus${NC}"
                "$SCRIPT_DIR/monitoring/setup_monitoring.sh" --prometheus-only --create-gremlin-checks
                ;;
        esac
    else
        echo -e "${YELLOW}⚠️  Master monitoring script not found, using legacy approach${NC}"
        setup_legacy_monitoring
    fi
    
    # Apply comprehensive Prometheus alert rules
    setup_prometheus_alert_rules
    
    # Setup external access for health checks
    setup_external_monitoring_access
    
    # Create enhanced Gremlin health checks with proper evaluation
    create_enhanced_gremlin_health_checks
}

# Setup comprehensive Prometheus alert rules (Fix #1 from fixes.md)
setup_prometheus_alert_rules() {
    echo -e "${BLUE}🚨 Setting up comprehensive Prometheus alert rules...${NC}"
    
    if [ -f "$SCRIPT_DIR/monitoring/grafana/health_check/improved_alert_rules_v2.sh" ]; then
        # Check if alert rules already exist to avoid duplicates
        if ! kubectl get prometheusrules -n monitoring &>/dev/null || [ "$(kubectl get prometheusrules -n monitoring --no-headers | wc -l)" -lt 10 ]; then
            echo "Creating comprehensive Prometheus alert rules..."
            if "$SCRIPT_DIR/monitoring/grafana/health_check/improved_alert_rules_v2.sh"; then
                echo "✅ Prometheus alert rules created successfully"
                
                # Apply namespace patch for custom rules
                if [ -f "$SCRIPT_DIR/monitoring/grafana/health_check/apply_prometheus_rule_patch.sh" ]; then
                    "$SCRIPT_DIR/monitoring/grafana/health_check/apply_prometheus_rule_patch.sh"
                fi
                
                # Apply the generated rules
                if [ -d "$SCRIPT_DIR/monitoring/grafana/health_check/prometheus-rules/" ]; then
                    kubectl apply -f "$SCRIPT_DIR/monitoring/grafana/health_check/prometheus-rules/"
                    echo "✅ Alert rules applied to cluster"
                fi
            else
                echo "⚠️  Failed to create Prometheus alert rules - continuing with basic monitoring"
            fi
        else
            echo "✅ Prometheus alert rules already exist, skipping creation"
        fi
    else
        echo "⚠️  Alert rules script not found, skipping comprehensive alert setup"
    fi
}

# Setup external access for monitoring (Fix #10 from fixes.md)
setup_external_monitoring_access() {
    echo -e "${CYAN}🌐 Setting up external monitoring access...${NC}"
    
    # Deploy Grafana ingress for external health checks
    if [ -f "$SCRIPT_DIR/monitoring/grafana/ingress/deploy_grafana_ingress.sh" ]; then
        "$SCRIPT_DIR/monitoring/grafana/ingress/deploy_grafana_ingress.sh"
        echo "Grafana ingress deployed for external access"
    fi
    
    # Deploy NodePort service as fallback
    if [ -f "$SCRIPT_DIR/monitoring/grafana/nodeport/grafana-nodeport.yaml" ]; then
        kubectl apply -f "$SCRIPT_DIR/monitoring/grafana/nodeport/grafana-nodeport.yaml"
        echo "Grafana NodePort service deployed (port 30860)"
    fi
}

# Wait for DNS propagation (optional)
wait_for_dns_propagation() {
    local wait_time=${1:-300}
    echo -e "${BLUE}⏳ Optionally waiting ${wait_time}s for DNS propagation...${NC}"
    echo -e "${YELLOW}💡 You can skip this and run './build_scripts/demo/healthchecks.sh' manually when DNS is ready${NC}"
    
    read -t 10 -p "Wait for DNS propagation? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Waiting ${wait_time} seconds for DNS propagation...${NC}"
        sleep "$wait_time"
        echo -e "${GREEN}✅ DNS propagation wait complete${NC}"
    else
        echo -e "${YELLOW}⏭️  Skipping DNS wait - run './build_scripts/demo/healthchecks.sh' when ready${NC}"
    fi
}

# Gremlin-only monitoring setup
setup_gremlin_monitoring() {
    echo -e "${PURPLE}Setting up Gremlin-specific monitoring...${NC}"
    
    # Apply Gremlin service annotations
    if [ -f "$SCRIPT_DIR/config/gremlin/consolidated_annotations.sh" ]; then
        "$SCRIPT_DIR/config/gremlin/consolidated_annotations.sh"
    fi
    
    # Create basic health checks
    create_enhanced_gremlin_health_checks
}

# Legacy monitoring setup fallback
setup_legacy_monitoring() {
    echo -e "${YELLOW}⚠️  Using legacy monitoring setup${NC}"
    
    case "$MONITORING_PLATFORM" in
        "prometheus")
            if [ -f "$SCRIPT_DIR/monitoring/prometheus/install/install.sh" ]; then
                "$SCRIPT_DIR/monitoring/prometheus/install/install.sh"
            fi
            ;;
        "dynatrace")
            if [ -f "$SCRIPT_DIR/monitoring/dynatrace/install/install.sh" ]; then
                "$SCRIPT_DIR/monitoring/dynatrace/install/install.sh"
            fi
            ;;
        "newrelic")
            if [ -f "$SCRIPT_DIR/monitoring/newrelic/install/install.sh" ]; then
                "$SCRIPT_DIR/monitoring/newrelic/install/install.sh"
            fi
            ;;
    esac
}

# Display dynamic endpoint summary
display_workshop_endpoints() {
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    🌐 WORKSHOP ENDPOINTS 🌐                  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local state_file="$SCRIPT_DIR/cluster-state.json"
    local cluster_name="${CLUSTER_NAME:-current-workshop}"
    
    # Read from state file if available
    if [ -f "$state_file" ]; then
        echo -e "${BLUE}📄 Reading endpoints from cluster state...${NC}"
        
        local frontend_url=$(jq -r '.endpoints.frontend // empty' "$state_file" 2>/dev/null)
        local grafana_url=$(jq -r '.endpoints.grafana_monitoring // empty' "$state_file" 2>/dev/null)
        local prometheus_url=$(jq -r '.endpoints.prometheus // empty' "$state_file" 2>/dev/null)
        
        # Fallback to DNS names if ALB not ready
        local frontend_dns="$cluster_name-frontend.gremlinpoc.com"
        local grafana_dns="$cluster_name-grafana.gremlinpoc.com"
        local prometheus_dns="$cluster_name-prometheus.gremlinpoc.com:9090"
        
        echo -e "${GREEN}🛒 FRONTEND STORE (OpenTelemetry Demo):${NC}"
        if [ -n "$frontend_url" ]; then
            echo -e "   ${BLUE}ALB URL:${NC} $frontend_url"
        fi
        echo -e "   ${BLUE}DNS URL:${NC} http://$frontend_dns"
        echo -e "   ${YELLOW}Use this to generate traffic and test chaos experiments${NC}"
        echo ""
        
        echo -e "${GREEN}📊 GRAFANA MONITORING UI:${NC}"
        if [ -n "$grafana_url" ]; then
            echo -e "   ${BLUE}ALB URL:${NC} $grafana_url"
        fi
        echo -e "   ${BLUE}DNS URL:${NC} http://$grafana_dns"
        echo -e "   ${BLUE}Username:${NC} admin"
        echo -e "   ${BLUE}Password:${NC} prom-operator"
        echo -e "   ${YELLOW}View dashboards, alerts, and system metrics${NC}"
        echo ""
        
        echo -e "${GREEN}🔍 PROMETHEUS METRICS:${NC}"
        if [ -n "$prometheus_url" ]; then
            echo -e "   ${BLUE}ALB URL:${NC} $prometheus_url"
        fi
        echo -e "   ${BLUE}DNS URL:${NC} http://$prometheus_dns"
        echo -e "   ${YELLOW}Query metrics and view alert rules${NC}"
        echo ""
    else
        echo -e "${YELLOW}⚠️  Cluster state file not found - using default DNS names${NC}"
        echo -e "${GREEN}🛒 FRONTEND:${NC} http://$cluster_name-frontend.gremlinpoc.com"
        echo -e "${GREEN}📊 GRAFANA:${NC} http://$cluster_name-grafana.gremlinpoc.com"
        echo -e "${GREEN}🔍 PROMETHEUS:${NC} http://$cluster_name-prometheus.gremlinpoc.com:9090"
        echo ""
    fi
    
    echo -e "${GREEN}🐒 GREMLIN HEALTH CHECKS:${NC}"
    echo -e "   ${BLUE}Dashboard:${NC} https://app.gremlin.com/reliability/status-checks"
    echo -e "   ${BLUE}Run:${NC} ./build_scripts/demo/healthchecks.sh --platform all"
    echo -e "   ${YELLOW}Health checks will be created after DNS propagation${NC}"
    echo ""
    
    echo -e "${BLUE}💡 NEXT STEPS:${NC}"
    echo -e "   ${YELLOW}1. Wait for DNS propagation (5-10 minutes)${NC}"
    echo -e "   ${YELLOW}2. Run: ./build_scripts/demo/healthchecks.sh --platform prometheus --platform grafana${NC}"
    echo -e "   ${YELLOW}3. Visit Gremlin dashboard to run chaos experiments${NC}"
    echo -e "   ${YELLOW}4. Monitor impact via Grafana dashboards${NC}"
    echo ""
    
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
}

# Main function to orchestrate the workshop
main() {
    print_banner
    validate_prerequisites
    collect_workshop_action
    collect_cluster_info
    # Credentials now handled by build_scripts/demo/healthchecks.sh
    # collect_all_credentials
    
    case "$WORKSHOP_ACTION" in
        "build_new")
            run_full_build_new_cluster
            ;;
        "clean_deploy")
            validate_cluster_exists
            run_clean_and_deploy
            ;;
        "deploy_existing")
            validate_cluster_exists
            run_deploy_only
            ;;
        "run_gremlin_only")
            validate_cluster_exists
            run_gremlin_only
            ;;
        "cleanup")
            validate_cluster_exists
            run_cleanup
            ;;
        *)
            echo -e "${RED}❌ Invalid action: $WORKSHOP_ACTION${NC}"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
