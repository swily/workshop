#!/bin/bash
#
# Number-Based Monitoring Setup Script
# Consistent with workshop orchestration numbering system
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default cluster name
CLUSTER_NAME=${CLUSTER_NAME:-current-workshop}

# Function to display help
show_help() {
  echo "Usage: $0 [option_number]"
  echo ""
  echo "Number-based monitoring platform options:"
  echo "  1    Install Prometheus & Grafana (baseline required)"
  echo "  2    Install Dynatrace"
  echo "  3    Install New Relic"
  echo "  4    Install DataDog (placeholder)"
  echo "  5    Show status of monitoring installations"
  echo "  6    Remove all monitoring installations"
  echo ""
  echo "Examples:"
  echo "  $0 1       # Install Prometheus & Grafana"
  echo "  $0 2       # Install Dynatrace (requires Prometheus & Grafana first)"
  echo "  $0 3       # Install New Relic (requires Prometheus & Grafana first)"
  echo "  $0 5       # Show status"
  echo "  $0 6       # Remove all"
  echo ""
  echo "Environment variables:"
  echo "  CLUSTER_NAME           - Cluster name (default: current-workshop)"
  echo "  DYNATRACE_API_TOKEN    - Required for Dynatrace installation"
  echo "  DYNATRACE_INSTANCE_ID  - Required for Dynatrace installation"
  echo "  NEWRELIC_API_KEY       - Required for New Relic installation"
}

# Function to check if Prometheus & Grafana are installed
check_baseline_monitoring() {
  if ! kubectl get namespace monitoring &>/dev/null; then
    echo -e "${RED}❌ Baseline monitoring (Prometheus & Grafana) not found${NC}"
    echo -e "${YELLOW}Please run: $0 1 first${NC}"
    return 1
  fi
  
  if ! kubectl get deployment -n monitoring prometheus-grafana &>/dev/null; then
    echo -e "${RED}❌ Grafana not found in monitoring namespace${NC}"
    echo -e "${YELLOW}Please run: $0 1 first${NC}"
    return 1
  fi
  
  return 0
}

# Function to install Prometheus & Grafana (Option 1)
install_prometheus_grafana() {
  echo -e "${BLUE}🔧 Installing Prometheus & Grafana (baseline monitoring)...${NC}"
  
  # Install Prometheus
  if [ -f "prometheus/install/install.sh" ]; then
    echo -e "${BLUE}  Installing Prometheus...${NC}"
    cd prometheus/install
    ./install.sh
    cd ../..
  else
    echo -e "${RED}❌ Prometheus install script not found${NC}"
    return 1
  fi
  
  # Install Grafana
  if [ -f "grafana/install/install.sh" ]; then
    echo -e "${BLUE}  Installing Grafana...${NC}"
    cd grafana/install
    ./install.sh
    cd ../..
  else
    echo -e "${RED}❌ Grafana install script not found${NC}"
    return 1
  fi
  
  echo -e "${GREEN}✅ Prometheus & Grafana installation complete${NC}"
  echo -e "${YELLOW}📝 Access URLs:${NC}"
  echo -e "${CYAN}   Prometheus: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090${NC}"
  echo -e "${CYAN}   Grafana: kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80${NC}"
}

# Function to install Dynatrace (Option 2)
install_dynatrace() {
  echo -e "${BLUE}🔧 Installing Dynatrace monitoring...${NC}"
  
  # Check baseline monitoring
  if ! check_baseline_monitoring; then
    return 1
  fi
  
  # Check required environment variables
  if [ -z "${DYNATRACE_API_TOKEN}" ] || [ -z "${DYNATRACE_INSTANCE_ID}" ]; then
    echo -e "${RED}❌ Missing required Dynatrace configuration${NC}"
    echo -e "${YELLOW}Please set: DYNATRACE_API_TOKEN and DYNATRACE_INSTANCE_ID${NC}"
    return 1
  fi
  
  # Install Dynatrace
  if [ -f "dynatrace/install/install.sh" ]; then
    echo -e "${BLUE}  Installing Dynatrace...${NC}"
    cd dynatrace/install
    ./install.sh
    cd ../..
  else
    echo -e "${RED}❌ Dynatrace install script not found${NC}"
    return 1
  fi
  
  echo -e "${GREEN}✅ Dynatrace installation complete${NC}"
}

# Function to install New Relic (Option 3)
install_newrelic() {
  echo -e "${BLUE}🔧 Installing New Relic monitoring...${NC}"
  
  # Check baseline monitoring
  if ! check_baseline_monitoring; then
    return 1
  fi
  
  # Check required environment variables
  if [ -z "${NEWRELIC_API_KEY}" ]; then
    echo -e "${RED}❌ Missing required New Relic configuration${NC}"
    echo -e "${YELLOW}Please set: NEWRELIC_API_KEY${NC}"
    return 1
  fi
  
  # Install New Relic
  if [ -f "newrelic/install/install.sh" ]; then
    echo -e "${BLUE}  Installing New Relic...${NC}"
    cd newrelic/install
    ./install.sh
    cd ../..
  else
    echo -e "${RED}❌ New Relic install script not found${NC}"
    return 1
  fi
  
  echo -e "${GREEN}✅ New Relic installation complete${NC}"
}

# Function to install DataDog (Option 4 - placeholder)
install_datadog() {
  echo -e "${YELLOW}⚠️  DataDog installation not yet implemented${NC}"
  echo -e "${BLUE}This is a placeholder for future DataDog integration${NC}"
}

# Function to show monitoring status (Option 5)
show_monitoring_status() {
  echo -e "${BLUE}🔍 Monitoring Platform Status${NC}"
  echo ""
  
  # Check Prometheus & Grafana
  echo -e "${BLUE}Prometheus & Grafana (Baseline):${NC}"
  if kubectl get namespace monitoring &>/dev/null; then
    if kubectl get deployment -n monitoring prometheus-grafana &>/dev/null; then
      echo -e "  ✅ Installed and running"
    else
      echo -e "  ❌ Namespace exists but Grafana not found"
    fi
  else
    echo -e "  ❌ Not installed"
  fi
  
  # Check Dynatrace
  echo -e "${BLUE}Dynatrace:${NC}"
  if kubectl get namespace dynatrace &>/dev/null; then
    echo -e "  ✅ Installed"
  else
    echo -e "  ❌ Not installed"
  fi
  
  # Check New Relic
  echo -e "${BLUE}New Relic:${NC}"
  if kubectl get namespace newrelic &>/dev/null; then
    echo -e "  ✅ Installed"
  else
    echo -e "  ❌ Not installed"
  fi
  
  # Check DataDog
  echo -e "${BLUE}DataDog:${NC}"
  if kubectl get namespace datadog &>/dev/null; then
    echo -e "  ✅ Installed"
  else
    echo -e "  ❌ Not installed"
  fi
}

# Function to remove all monitoring (Option 6)
remove_all_monitoring() {
  echo -e "${RED}⚠️  WARNING: This will remove ALL monitoring installations${NC}"
  echo -e "${YELLOW}Are you sure? (type 'REMOVE' to confirm)${NC}"
  read -p "> " confirmation
  
  if [ "$confirmation" != "REMOVE" ]; then
    echo -e "${YELLOW}Removal cancelled${NC}"
    return 0
  fi
  
  echo -e "${BLUE}🧹 Removing all monitoring installations...${NC}"
  
  # Remove namespaces
  kubectl delete namespace monitoring --ignore-not-found=true
  kubectl delete namespace dynatrace --ignore-not-found=true
  kubectl delete namespace newrelic --ignore-not-found=true
  kubectl delete namespace datadog --ignore-not-found=true
  
  # Remove CRDs and other resources
  kubectl delete crd --selector=app.kubernetes.io/name=prometheus-operator --ignore-not-found=true
  
  echo -e "${GREEN}✅ All monitoring installations removed${NC}"
}

# Main function
main() {
  # Check if running from monitoring directory
  if [ ! -f "setup_monitoring_numbered.sh" ]; then
    echo -e "${RED}❌ Please run this script from the monitoring directory${NC}"
    exit 1
  fi
  
  # Handle command line arguments
  if [ $# -eq 0 ]; then
    show_help
    exit 0
  fi
  
  case $1 in
    1)
      install_prometheus_grafana
      ;;
    2)
      install_dynatrace
      ;;
    3)
      install_newrelic
      ;;
    4)
      install_datadog
      ;;
    5)
      show_monitoring_status
      ;;
    6)
      remove_all_monitoring
      ;;
    -h|--help)
      show_help
      ;;
    *)
      echo -e "${RED}❌ Invalid option: $1${NC}"
      echo ""
      show_help
      exit 1
      ;;
  esac
}

# Run main function
main "$@"
