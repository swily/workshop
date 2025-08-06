#!/bin/bash -e

# Master Monitoring Setup Script
# This script orchestrates the installation of monitoring tools in the workshop environment
# It provides a unified interface for installing and configuring Prometheus, Dynatrace, New Relic, and DataDog

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-current-workshop}"
SETUP_HEALTH_CHECKS=true  # Set to false to skip health check setup

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Function to print section headers
section() {
  echo -e "\n${GREEN}=== $1 ===${NC}"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to display help
show_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -h, --help                 Show this help message"
  echo "  -c, --cluster-name NAME    Set the cluster name (default: $CLUSTER_NAME)"
  echo "  -p, --prometheus-only      Install only Prometheus stack"
  echo "  -d, --dynatrace            Install Dynatrace"
  echo "  -n, --newrelic             Install New Relic"
  echo "  -g, --datadog              Install DataDog (placeholder)"
  echo "  -a, --all                  Install all monitoring tools"
  echo "  -s, --status               Show status of monitoring installations"
  echo "  -r, --remove               Remove all monitoring installations"
  echo "  --no-health-checks         Skip setting up health checks"
  echo ""
  echo "Examples:"
  echo "  $0 --prometheus-only       # Install only Prometheus"
  echo "  $0 --dynatrace             # Install Prometheus and Dynatrace"
  echo "  $0 --all                   # Install all monitoring tools"
  echo "  $0 --status                # Show status of monitoring installations"
  echo "  $0 --remove                # Remove all monitoring installations"
  echo "  $0 --no-health-checks      # Skip setting up health checks"
}

# Function to check monitoring status
check_status() {
  section "Checking Monitoring Status"
  
  # Check Prometheus
  echo -e "${BLUE}Prometheus:${NC}"
  if kubectl get namespace monitoring &>/dev/null; then
    if kubectl get deployment -n monitoring prometheus-operator-kube-p-operator &>/dev/null; then
      echo -e "  ${GREEN}✅ Prometheus is installed${NC}"
      echo -e "  Pods in monitoring namespace:"
      kubectl get pods -n monitoring | grep -E 'prometheus|grafana' | head -5
      if [ $(kubectl get pods -n monitoring | grep -E 'prometheus|grafana' | wc -l) -gt 5 ]; then
        echo -e "  ${YELLOW}...and more pods not shown${NC}"
      fi
      
      # Check Grafana health check
      echo -e "\n  ${BLUE}Grafana Health Check:${NC}"
      if kubectl get configmap -n monitoring grafana-health-check-status &>/dev/null; then
        echo -e "  ${GREEN}✅ Grafana health check is configured${NC}"
      else
        echo -e "  ${YELLOW}⚠️ Grafana health check is not configured${NC}"
      fi
    else
      echo -e "  ${YELLOW}⚠️ Monitoring namespace exists but Prometheus is not installed${NC}"
    fi
  else
    echo -e "  ${RED}❌ Prometheus is not installed (monitoring namespace not found)${NC}"
  fi
  
  # Check Dynatrace
  echo -e "\n${BLUE}Dynatrace:${NC}"
  if kubectl get namespace dynatrace &>/dev/null; then
    if kubectl get deployment -n dynatrace dynatrace-operator &>/dev/null; then
      echo -e "  ${GREEN}✅ Dynatrace is installed${NC}"
      echo -e "  Pods in dynatrace namespace:"
      kubectl get pods -n dynatrace | head -5
      if [ $(kubectl get pods -n dynatrace | wc -l) -gt 5 ]; then
        echo -e "  ${YELLOW}...and more pods not shown${NC}"
      fi
    else
      echo -e "  ${YELLOW}⚠️ Dynatrace namespace exists but Dynatrace Operator is not installed${NC}"
    fi
  else
    echo -e "  ${RED}❌ Dynatrace is not installed (dynatrace namespace not found)${NC}"
  fi
  
  # Check New Relic
  echo -e "\n${BLUE}New Relic:${NC}"
  if kubectl get namespace newrelic &>/dev/null; then
    if kubectl get pods -n newrelic -l app.kubernetes.io/name=newrelic-bundle &>/dev/null; then
      echo -e "  ${GREEN}✅ New Relic is installed${NC}"
      echo -e "  Pods in newrelic namespace:"
      kubectl get pods -n newrelic | head -5
      if [ $(kubectl get pods -n newrelic | wc -l) -gt 5 ]; then
        echo -e "  ${YELLOW}...and more pods not shown${NC}"
      fi
      
      # Check New Relic health check
      echo -e "\n  ${BLUE}New Relic Health Check:${NC}"
      if kubectl get configmap -n newrelic newrelic-health-check-status &>/dev/null; then
        echo -e "  ${GREEN}✅ New Relic health check is configured${NC}"
      else
        echo -e "  ${YELLOW}⚠️ New Relic health check is not configured${NC}"
      fi
    else
      echo -e "  ${YELLOW}⚠️ New Relic namespace exists but New Relic bundle is not installed${NC}"
    fi
  else
    echo -e "  ${RED}❌ New Relic is not installed (newrelic namespace not found)${NC}"
  fi
  
  # Check DataDog
  echo -e "\n${BLUE}DataDog:${NC}"
  if kubectl get namespace datadog &>/dev/null; then
    if kubectl get pods -n datadog -l app=datadog &>/dev/null; then
      echo -e "  ${GREEN}✅ DataDog is installed${NC}"
      echo -e "  Pods in datadog namespace:"
      kubectl get pods -n datadog | head -5
      if [ $(kubectl get pods -n datadog | wc -l) -gt 5 ]; then
        echo -e "  ${YELLOW}...and more pods not shown${NC}"
      fi
    else
      echo -e "  ${YELLOW}⚠️ DataDog namespace exists but DataDog agent is not installed${NC}"
    fi
  else
    echo -e "  ${RED}❌ DataDog is not installed (datadog namespace not found)${NC}"
  fi
}

# Function to remove all monitoring installations
remove_all() {
  section "Removing All Monitoring Installations"
  
  # Confirm removal
  echo -e "${RED}WARNING: This will remove all monitoring installations.${NC}"
  echo -e "${RED}This includes Prometheus, Dynatrace, New Relic, and DataDog.${NC}"
  echo -e "${RED}All monitoring data will be lost.${NC}"
  echo -e "${YELLOW}Are you sure you want to continue? (y/n)${NC}"
  read -r response
  if [[ "$response" != "y" && "$response" != "Y" ]]; then
    echo "Aborted."
    exit 0
  fi
  
  # Remove DataDog
  if kubectl get namespace datadog &>/dev/null; then
    echo "Removing DataDog..."
    helm uninstall datadog -n datadog 2>/dev/null || true
    kubectl delete namespace datadog --wait=false 2>/dev/null || true
  fi
  
  # Remove New Relic
  if kubectl get namespace newrelic &>/dev/null; then
    echo "Removing New Relic..."
    helm uninstall newrelic-bundle -n newrelic 2>/dev/null || true
    kubectl delete namespace newrelic --wait=false 2>/dev/null || true
  fi
  
  # Remove Dynatrace
  if kubectl get namespace dynatrace &>/dev/null; then
    echo "Removing Dynatrace..."
    kubectl delete dynakube --all -n dynatrace 2>/dev/null || true
    kubectl delete deployment dynatrace-operator -n dynatrace 2>/dev/null || true
    kubectl delete namespace dynatrace --wait=false 2>/dev/null || true
  fi
  
  # Remove Prometheus
  if kubectl get namespace monitoring &>/dev/null; then
    echo "Removing Prometheus..."
    helm uninstall prometheus-operator -n monitoring 2>/dev/null || true
    kubectl delete namespace monitoring --wait=false 2>/dev/null || true
  fi
  
  echo -e "${GREEN}All monitoring installations have been removed.${NC}"
}

# Check for required tools
section "Checking for required tools"
for cmd in kubectl helm jq; do
  if ! command_exists "$cmd"; then
    echo -e "${RED}Error: $cmd is not installed${NC}"
    exit 1
  fi
done

# Parse command line arguments
INSTALL_PROMETHEUS=false
INSTALL_DYNATRACE=false
INSTALL_NEWRELIC=false
INSTALL_DATADOG=false
CHECK_STATUS=false
REMOVE_ALL=false
SETUP_HEALTH_CHECKS=true

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -h|--help)
      show_help
      exit 0
      ;;
    -c|--cluster-name)
      CLUSTER_NAME="$2"
      shift
      shift
      ;;
    -p|--prometheus-only)
      INSTALL_PROMETHEUS=true
      shift
      ;;
    -d|--dynatrace)
      INSTALL_PROMETHEUS=true
      INSTALL_DYNATRACE=true
      shift
      ;;
    -n|--newrelic)
      INSTALL_PROMETHEUS=true
      INSTALL_NEWRELIC=true
      shift
      ;;
    -g|--datadog)
      INSTALL_PROMETHEUS=true
      INSTALL_DATADOG=true
      shift
      ;;
    -a|--all)
      INSTALL_PROMETHEUS=true
      INSTALL_DYNATRACE=true
      INSTALL_NEWRELIC=true
      INSTALL_DATADOG=true
      shift
      ;;
    -s|--status)
      CHECK_STATUS=true
      shift
      ;;
    -r|--remove)
      REMOVE_ALL=true
      shift
      ;;
    --no-health-checks)
      SETUP_HEALTH_CHECKS=false
      shift
      ;;
    *)
      echo -e "${RED}Unknown option: $key${NC}"
      show_help
      exit 1
      ;;
  esac
done

# Export cluster name for child scripts
export CLUSTER_NAME

# Check status if requested
if [ "$CHECK_STATUS" = true ]; then
  check_status
  exit 0
fi

# Remove all if requested
if [ "$REMOVE_ALL" = true ]; then
  remove_all
  exit 0
fi

# If no installation option was selected, show interactive menu
if [ "$INSTALL_PROMETHEUS" = false ] && [ "$INSTALL_DYNATRACE" = false ] && [ "$INSTALL_NEWRELIC" = false ] && [ "$INSTALL_DATADOG" = false ]; then
  section "Monitoring Installation Menu"
  echo "Please select an option:"
  echo "1) Install Prometheus only"
  echo "2) Install Prometheus and Dynatrace"
  echo "3) Install Prometheus and New Relic"
  echo "4) Install Prometheus and DataDog (placeholder)"
  echo "5) Install all monitoring tools"
  echo "6) Check status of monitoring installations"
  echo "7) Remove all monitoring installations"
  echo "8) Exit"
  echo ""
  echo -n "Enter your choice [1-8]: "
  read -r choice
  
  case $choice in
    1)
      INSTALL_PROMETHEUS=true
      ;;
    2)
      INSTALL_PROMETHEUS=true
      INSTALL_DYNATRACE=true
      ;;
    3)
      INSTALL_PROMETHEUS=true
      INSTALL_NEWRELIC=true
      ;;
    4)
      INSTALL_PROMETHEUS=true
      INSTALL_DATADOG=true
      ;;
    5)
      INSTALL_PROMETHEUS=true
      INSTALL_DYNATRACE=true
      INSTALL_NEWRELIC=true
      INSTALL_DATADOG=true
      ;;
    6)
      check_status
      exit 0
      ;;
    7)
      remove_all
      exit 0
      ;;
    8)
      echo "Exiting."
      exit 0
      ;;
    *)
      echo -e "${RED}Invalid choice. Exiting.${NC}"
      exit 1
      ;;
  esac
fi

# Install Prometheus if requested
if [ "$INSTALL_PROMETHEUS" = true ]; then
  section "Installing Prometheus"
  "${SCRIPT_DIR}/prometheus/install/install.sh"
  
  # Setup Grafana health check if enabled
  if [ "$SETUP_HEALTH_CHECKS" = true ]; then
    section "Setting up Grafana health check"
    if [ -f "${SCRIPT_DIR}/grafana/health_check/setup_health_check.sh" ]; then
      # Get Grafana admin password
      GRAFANA_ADMIN_PASSWORD=$(kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
      if [ -n "$GRAFANA_ADMIN_PASSWORD" ]; then
        # Port-forward Grafana (in background)
        echo "Starting port-forward for Grafana..."
        kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &
        GRAFANA_PF_PID=$!
        
        # Wait for port-forward to be ready
        echo "Waiting for port-forward to be ready..."
        sleep 5
        
        # Run health check setup
        echo "Running Grafana health check setup..."
        "${SCRIPT_DIR}/grafana/health_check/setup_health_check.sh" \
          --grafana-url "http://localhost:3000" \
          --api-key "admin:${GRAFANA_ADMIN_PASSWORD}" \
          --namespace "otel-demo" \
          --service "frontend" \
          --endpoint "/health"
          
        # Create a ConfigMap to track health check status
        kubectl create configmap -n monitoring grafana-health-check-status \
          --from-literal=configured=true \
          --from-literal=timestamp="$(date '+%Y-%m-%d %H:%M:%S')" \
          --dry-run=client -o yaml | kubectl apply -f -
        
        # Kill port-forward
        kill $GRAFANA_PF_PID 2>/dev/null || true
      else
        echo -e "${YELLOW}⚠️ Could not retrieve Grafana admin password. Skipping health check setup.${NC}"
      fi
    else
      echo -e "${YELLOW}⚠️ Grafana health check setup script not found. Skipping.${NC}"
    fi
  fi
fi

# Install Dynatrace if requested
if [ "$INSTALL_DYNATRACE" = true ]; then
  section "Installing Dynatrace"
  "${SCRIPT_DIR}/dynatrace/install/install.sh"
fi

# Install New Relic if requested
if [ "$INSTALL_NEWRELIC" = true ]; then
  section "Installing New Relic"
  "${SCRIPT_DIR}/newrelic/install/install.sh"
  
  # Setup New Relic health check if enabled
  if [ "$SETUP_HEALTH_CHECKS" = true ]; then
    section "Setting up New Relic health check"
    if [ -f "${SCRIPT_DIR}/newrelic/health_check/setup_health_check.sh" ]; then
      # Get New Relic API key from secret
      NEW_RELIC_API_KEY=$(kubectl get secret -n newrelic newrelic-license-key -o jsonpath="{.data.license-key}" | base64 --decode 2>/dev/null)
      
      if [ -n "$NEW_RELIC_API_KEY" ]; then
        # Run health check setup
        echo "Running New Relic health check setup..."
        "${SCRIPT_DIR}/newrelic/health_check/setup_health_check.sh" \
          --api-key "$NEW_RELIC_API_KEY" \
          --namespace "otel-demo" \
          --service "frontend" \
          --endpoint "/health"
          
        # Create a ConfigMap to track health check status
        kubectl create configmap -n newrelic newrelic-health-check-status \
          --from-literal=configured=true \
          --from-literal=timestamp="$(date '+%Y-%m-%d %H:%M:%S')" \
          --dry-run=client -o yaml | kubectl apply -f -
      else
        echo -e "${YELLOW}⚠️ Could not retrieve New Relic API key. Skipping health check setup.${NC}"
      fi
    else
      echo -e "${YELLOW}⚠️ New Relic health check setup script not found. Skipping.${NC}"
    fi
  fi
fi

# Install DataDog if requested
if [ "$INSTALL_DATADOG" = true ]; then
  section "Installing DataDog"
  "${SCRIPT_DIR}/datadog/install/install.sh"
fi

# Final status check
if [ "$INSTALL_PROMETHEUS" = true ] || [ "$INSTALL_DYNATRACE" = true ] || [ "$INSTALL_NEWRELIC" = true ] || [ "$INSTALL_DATADOG" = true ]; then
  section "Installation Complete"
  echo -e "${GREEN}Monitoring tools have been installed.${NC}"
  echo -e "${YELLOW}Checking final status...${NC}"
  check_status
fi

exit 0
