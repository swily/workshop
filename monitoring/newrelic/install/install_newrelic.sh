#!/bin/bash

# New Relic Kubernetes Integration Installation Script
# This script installs the New Relic Kubernetes integration using Helm
# following official best practices for license key configuration

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
CLUSTER_NAME=$(kubectl config current-context)
NAMESPACE="newrelic"
TIMEOUT="10m"
LOW_DATA_MODE="false"
HELM_CHART_VERSION="" # Empty for latest version

# Function to display script usage
usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  --license-key KEY         New Relic License Key (required if no secret exists)"
  echo "  --cluster-name NAME       Cluster name (default: current kubectl context)"
  echo "  --namespace NAMESPACE     Namespace for New Relic (default: newrelic)"
  echo "  --timeout DURATION        Helm install timeout (default: 10m)"
  echo "  --secret-name NAME        Name of existing secret containing license key"
  echo "  --secret-key KEY          Key in the secret containing license key (default: licenseKey)"
  echo "  --low-data-mode           Enable low data mode to reduce data volume (default: false)"
  echo "  --chart-version VERSION   Specify Helm chart version (default: latest)"
  echo "  --help                    Display this help message"
  exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --license-key)
      LICENSE_KEY="$2"
      shift 2
      ;;
    --cluster-name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --secret-name)
      SECRET_NAME="$2"
      shift 2
      ;;
    --secret-key)
      SECRET_KEY="$2"
      shift 2
      ;;
    --low-data-mode)
      LOW_DATA_MODE="true"
      shift
      ;;
    --chart-version)
      HELM_CHART_VERSION="$2"
      shift 2
      ;;
    --help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Function to print section headers
section() {
  echo -e "\n${YELLOW}=== $1 ===${NC}"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Validate license key or secret configuration
if [ -z "$LICENSE_KEY" ] && [ -z "$SECRET_NAME" ]; then
  # Check if NEW_RELIC_LICENSE_KEY is set in environment
  if [ -n "$NEW_RELIC_LICENSE_KEY" ]; then
    LICENSE_KEY="$NEW_RELIC_LICENSE_KEY"
    echo "Using license key from NEW_RELIC_LICENSE_KEY environment variable"
  else
    echo -e "${RED}Error: Either --license-key or --secret-name must be provided${NC}"
    usage
  fi
fi

# If SECRET_KEY is not provided but SECRET_NAME is, set default
if [ -n "$SECRET_NAME" ] && [ -z "$SECRET_KEY" ]; then
  SECRET_KEY="licenseKey"
fi

# Create namespace if it doesn't exist
section "Creating namespace $NAMESPACE"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Create license key secret if license key is provided
if [ -n "$LICENSE_KEY" ]; then
  section "Creating New Relic license key secret"
  kubectl create secret generic newrelic-license-key \
    --from-literal=licenseKey="$LICENSE_KEY" \
    -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
  
  # Use the created secret
  SECRET_NAME="newrelic-license-key"
  SECRET_KEY="licenseKey"
  
  echo -e "${GREEN}✅ Created New Relic license key secret${NC}"
else
  section "Using existing secret $SECRET_NAME"
  # Verify the secret exists
  if ! kubectl get secret $SECRET_NAME -n $NAMESPACE &>/dev/null; then
    echo -e "${RED}❌ Secret $SECRET_NAME does not exist in namespace $NAMESPACE${NC}"
    exit 1
  fi
  echo -e "${GREEN}✅ Found existing secret $SECRET_NAME${NC}"
fi

# Add New Relic Helm repo
section "Adding New Relic Helm repository"
helm repo add newrelic https://helm-charts.newrelic.com
helm repo update

# Prepare Helm install command
HELM_CMD="helm upgrade --install newrelic-bundle newrelic/nri-bundle \
  --namespace $NAMESPACE \
  --set global.cluster=$CLUSTER_NAME \
  --set global.lowDataMode=$LOW_DATA_MODE \
  --set global.customSecretName=$SECRET_NAME \
  --set global.customSecretLicenseKey=$SECRET_KEY \
  --set newrelic-infrastructure.enabled=true \
  --set kube-state-metrics.enabled=true \
  --set kubeEvents.enabled=true \
  --set newrelic-logging.enabled=true \
  --set newrelic-logging.fluentBit.enabled=true \
  --set newrelic-logging.fluentBit.containers.enable=true \
  --set prometheus.enabled=true \
  --set prometheus.nginx.enabled=true \
  --timeout $TIMEOUT"

# Add version if specified
if [ -n "$HELM_CHART_VERSION" ]; then
  HELM_CMD="$HELM_CMD --version $HELM_CHART_VERSION"
fi

# Execute Helm install
section "Installing New Relic bundle"
echo "Executing: $HELM_CMD"
eval $HELM_CMD

# Wait for pods to be ready
section "Waiting for New Relic pods to be ready"
echo "This may take a few minutes..."
kubectl wait --for=condition=ready pod --all -n $NAMESPACE --timeout=5m || true

# Display pod status
section "New Relic pod status"
kubectl get pods -n $NAMESPACE

# Check for any pods in CrashLoopBackOff
CRASH_PODS=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[?(@.status.phase=="Running")].status.containerStatuses[?(@.state.waiting.reason=="CrashLoopBackOff")].name}' 2>/dev/null || echo "")
if [ -n "$CRASH_PODS" ]; then
  echo -e "${RED}⚠️ Warning: Some pods are in CrashLoopBackOff state${NC}"
  echo "Check logs with: kubectl logs -n $NAMESPACE <pod-name>"
fi

# Display success message
section "Installation Complete"
echo -e "${GREEN}✅ New Relic Kubernetes integration has been installed${NC}"
echo "Cluster Name: $CLUSTER_NAME"
echo "Namespace: $NAMESPACE"
echo -e "${YELLOW}View your cluster in New Relic: https://one.newrelic.com/launcher/infra.launcher${NC}"

exit 0
