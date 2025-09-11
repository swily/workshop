#!/bin/bash -e
# ---------------------------------------------------------------------------
# DEPRECATION NOTICE
# This script is part of the legacy monitoring setup. The modern workflow
# uses the modular orchestrator and libraries:
#   - workshop.sh (main entry)
#   - lib/monitoring.sh (Grafana/Prometheus + vendor setups)
#   - scripts/operations/* (operations)
# Please prefer running:
#   ./workshop.sh --action build_new --cluster-name <name>
# or
#   ./workshop.sh --action deploy_existing --cluster-name <name>
# ---------------------------------------------------------------------------
echo "[DEPRECATED] monitoring/setup_monitoring.sh: Use workshop.sh + lib/monitoring.sh instead." >&2

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
  echo "  -f, --grafana              Setup Grafana health checks"
  echo "  -g, --datadog              Install DataDog (placeholder)"
  echo "  -a, --all                  Install all monitoring tools"
  echo "  -s, --status               Show status of monitoring installations"
  echo "  -r, --remove               Remove all monitoring installations"
  echo "  --no-health-checks         Skip setting up health checks"
  echo "  --create-gremlin-checks    Create Gremlin health checks after platform setup"
  echo ""
  echo "Examples:"
  echo "  $0 --prometheus-only       # Install only Prometheus"
  echo "  $0 --dynatrace             # Install Prometheus and Dynatrace"
  echo "  $0 --all                   # Install all monitoring tools"
  echo "  $0 --status                # Show status of monitoring installations"
  echo "  $0 --remove                # Remove all monitoring installations"
  echo "  $0 --no-health-checks      # Skip setting up health checks"
}

# Function to check monitoring status (silent unless errors)
check_status() {
  # Only report errors, suppress normal status output
  local errors_found=false
  
  # Silent checks - only report if critical errors found
  if ! kubectl get namespace monitoring &>/dev/null; then
    if [ "$INSTALL_PROMETHEUS" = true ]; then
      echo -e "${RED}Error: Prometheus installation failed - monitoring namespace not found${NC}"
      errors_found=true
    fi
  fi
  
  # Only show error summary if errors were found
  if [ "$errors_found" = false ]; then
    return 0  # Silent success
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
INSTALL_GRAFANA=false
INSTALL_DATADOG=false
CHECK_STATUS=false
REMOVE_ALL=false
SETUP_HEALTH_CHECKS=true
CREATE_GREMLIN_CHECKS=false

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
    -f|--grafana)
      INSTALL_PROMETHEUS=true
      INSTALL_GRAFANA=true
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
      INSTALL_GRAFANA=true
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
    --create-gremlin-checks)
      CREATE_GREMLIN_CHECKS=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
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
fi

# Setup Grafana health checks if requested
if [ "$INSTALL_GRAFANA" = true ]; then
  section "Setting up Grafana Health Checks"
  "${SCRIPT_DIR}/grafana/install/install.sh"
fi

# Install DataDog if requested
if [ "$INSTALL_DATADOG" = true ]; then
  section "Installing DataDog"
  "${SCRIPT_DIR}/datadog/install/install.sh"
fi

# Note: Gremlin health checks will be created after LoadBalancer provisioning
# This prevents premature health check creation before endpoints are ready

# Final status check and summary
if [ "$INSTALL_PROMETHEUS" = true ] || [ "$INSTALL_DYNATRACE" = true ] || [ "$INSTALL_NEWRELIC" = true ] || [ "$INSTALL_GRAFANA" = true ] || [ "$INSTALL_DATADOG" = true ]; then
  section "Installation Complete"
  echo -e "${GREEN}Monitoring tools have been installed.${NC}"
  echo -e "${YELLOW}Checking final status...${NC}"
  check_status
  
  # Platform verification URLs will be shown at the end of the workshop
  echo -e "${GREEN}✅ Monitoring platforms setup complete${NC}"
  
  if [ "$INSTALL_DYNATRACE" = true ]; then
    echo -e "${YELLOW}Dynatrace:${NC}"
    echo -e "  https://\${DYNATRACE_INSTANCE_ID}.live.dynatrace.com"
    echo -e "  Problems API: https://\${DYNATRACE_INSTANCE_ID}.live.dynatrace.com/api/v2/problems"
  fi
  
  if [ "$INSTALL_NEWRELIC" = true ]; then
    echo -e "${YELLOW}New Relic:${NC}"
    echo -e "  https://one.newrelic.com"
    echo -e "  Alert Conditions API: https://api.newrelic.com/v2/alerts_nrql_conditions.json"
  fi
  
  if [ "$INSTALL_GRAFANA" = true ]; then
    echo -e "${YELLOW}Grafana Health Checks:${NC}"
    echo -e "  Alert API: http://localhost:3000/api/alertmanager/grafana/api/v2/alerts"
    echo -e "  Alert Rules: http://localhost:3000/alerting/list"
  fi
  
  # Setup complete - health checks will be handled separately after LoadBalancer provisioning
fi

exit 0
