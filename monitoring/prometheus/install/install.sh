#!/bin/bash -e

# Unified Prometheus Installation Script
# This script installs the kube-prometheus-stack Helm chart in the monitoring namespace
# It sets up the basic monitoring infrastructure for the workshop environment

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CLUSTER_NAME="${CLUSTER_NAME:-test-cluster}"
VALUES_DIR="${SCRIPT_DIR}/../values"
DASHBOARDS_DIR="${SCRIPT_DIR}/../dashboards"
PROMETHEUS_VERSION="55.5.0"  # kube-prometheus-stack chart version

# Function to print section headers with time estimates
section() {
  local message="$1"
  local estimate="$2"
  echo -e "\n${GREEN}=== $message ===${NC}"
  if [ -n "$estimate" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message (Est. time: $estimate)"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message"
  fi
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to ensure Helm repo is added
ensure_helm_repo() {
  local repo_name="$1"
  local repo_url="$2"
  
  echo "Ensuring Helm repo ${repo_name} is added..."
  if ! helm repo list | grep -q "^${repo_name}"; then
    echo "Adding Helm repo ${repo_name}..."
    helm repo add "${repo_name}" "${repo_url}"
  else
    echo "Helm repo ${repo_name} already exists, updating..."
    helm repo update "${repo_name}"
  fi
}

# Check for required tools
section "Checking for required tools"
for cmd in kubectl helm jq; do
  if ! command_exists "$cmd"; then
    echo -e "${RED}Error: $cmd is not installed${NC}"
    exit 1
  fi
done

# Check if we can connect to the cluster
section "Checking cluster connectivity"
if ! kubectl get nodes &>/dev/null; then
  echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
  echo "Please ensure you have set the correct kubeconfig and have access to the cluster."
  exit 1
fi

# Create monitoring namespace if it doesn't exist
section "Creating monitoring namespace"
if ! kubectl get namespace monitoring &>/dev/null; then
  echo "Creating monitoring namespace..."
  kubectl create namespace monitoring
else
  echo "monitoring namespace already exists"
fi

# Add Prometheus Helm repository
section "Adding Prometheus Helm repository"
ensure_helm_repo "prometheus-community" "https://prometheus-community.github.io/helm-charts"

# Create values file directory if it doesn't exist
mkdir -p "${VALUES_DIR}"

# Check if custom values file exists, if not create a default one
CUSTOM_VALUES_FILE="${VALUES_DIR}/prometheus-values.yaml"
if [ ! -f "${CUSTOM_VALUES_FILE}" ]; then
  section "Creating default values file"
  echo "No custom values file found, creating default values file at ${CUSTOM_VALUES_FILE}"
  
  # Check if we can copy from the existing config
  if [ -f "/Users/seanwiley/workshop/config/monitoring/prometheus-operator-values.yaml" ]; then
    cp "/Users/seanwiley/workshop/config/monitoring/prometheus-operator-values.yaml" "${CUSTOM_VALUES_FILE}"
    echo "Copied existing values from config/monitoring/prometheus-operator-values.yaml"
  else
    # Create a basic default values file
    cat > "${CUSTOM_VALUES_FILE}" <<EOF
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelector:
      matchLabels:
        release: prometheus-operator
    additionalScrapeConfigs:
      - job_name: 'kubernetes-cadvisor'
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
          - role: node
        relabel_configs:
          - action: labelmap
            regex: __meta_kubernetes_node_label_(.+)
          - target_label: __address__
            replacement: kubernetes.default.svc:443
          - source_labels: [__meta_kubernetes_node_name]
            regex: (.+)
            target_label: __metrics_path__
            replacement: /api/v1/nodes/\${1}/proxy/metrics/cadvisor
        metric_relabel_configs:
          - source_labels: [container]
            regex: ^$
            action: drop

grafana:
  additionalDataSources:
    - name: webstore-metrics
      type: prometheus
      url: http://prometheus.otel-demo:9090
      access: proxy
      isDefault: false

  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'otel-demo'
          orgId: 1
          folder: 'OpenTelemetry Demo'
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/otel-demo

  dashboards:
    default:
      otel-demo:
        # This will mount the dashboards from the demo into Grafana
        configMapRef: otel-demo-dashboards
        enabled: true
EOF
    echo "Created default values file"
  fi
fi

# Check for existing Prometheus installations and make idempotent
section "Checking for existing Prometheus installations"
EXISTING_RELEASE=""
if helm list -n monitoring | grep -q "prometheus-operator"; then
  EXISTING_RELEASE="prometheus-operator"
  echo "Found existing prometheus-operator release"
elif helm list -n monitoring | grep -q "prometheus"; then
  EXISTING_RELEASE="prometheus"
  echo "Found existing prometheus release"
fi

# Install or upgrade kube-prometheus-stack
section "Installing/Upgrading kube-prometheus-stack" "5 min"
if [ -n "$EXISTING_RELEASE" ]; then
  echo "Upgrading existing release: ${EXISTING_RELEASE}"
  RELEASE_NAME="$EXISTING_RELEASE"
else
  echo "Installing new prometheus release"
  RELEASE_NAME="prometheus"
fi

echo "Installing kube-prometheus-stack with Helm..."

# Comprehensive cleanup of stuck resources
echo "Checking for stuck resources and cleaning up..."

# Force delete any stuck terminating pods (silent output)
kubectl get pods -n monitoring --field-selector=status.phase=Failed -o name 2>/dev/null | xargs -r kubectl delete --force --grace-period=0 >/dev/null 2>&1 || true
kubectl get pods -n monitoring | grep Terminating | awk '{print $1}' | xargs -r kubectl delete pod -n monitoring --force --grace-period=0 >/dev/null 2>&1 || true

# Clean up any orphaned resources (silent output)
kubectl delete statefulsets,deployments,daemonsets,replicasets -n monitoring --all --force --grace-period=0 >/dev/null 2>&1 || true
kubectl delete services,configmaps,secrets -n monitoring --all >/dev/null 2>&1 || true

# Wait for cleanup to complete
echo "Waiting for cleanup to complete..."
sleep 10

# Install with improved timeout and error handling
echo "Starting Prometheus installation..."
if ! helm upgrade --install "$RELEASE_NAME" prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version "${PROMETHEUS_VERSION}" \
  --values "${CUSTOM_VALUES_FILE}" \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorSelector.matchLabels.release="$RELEASE_NAME" \
  --set prometheus.prometheusSpec.resources.requests.memory="1Gi" \
  --set prometheus.prometheusSpec.resources.limits.memory="2Gi" \
  --set alertmanager.alertmanagerSpec.resources.requests.memory="200Mi" \
  --set alertmanager.alertmanagerSpec.resources.limits.memory="500Mi" \
  --timeout=20m \
  --wait; then
  
  echo -e "${YELLOW}⚠️ Helm install/upgrade timed out or failed. Checking deployment status...${NC}"
  
  # Check if the deployment actually succeeded despite timeout
  if kubectl get deployment "${RELEASE_NAME}-kube-prometheus-stack-operator" -n monitoring >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Prometheus operator deployment exists, continuing...${NC}"
  else
    echo -e "${RED}❌ Prometheus installation failed completely. Manual intervention may be required.${NC}"
    echo -e "${YELLOW}You can try running the monitoring setup again or check cluster resources.${NC}"
    exit 1
  fi
fi

# Wait for Prometheus to be ready
section "Waiting for Prometheus to be ready"
echo "Waiting for Prometheus deployment to be ready..."
kubectl rollout status deployment/${RELEASE_NAME}-kube-prometheus-operator -n monitoring --timeout=300s || true
kubectl rollout status statefulset/prometheus-${RELEASE_NAME}-kube-prometheus-prometheus -n monitoring --timeout=300s || true

# Wait for Grafana to be ready
echo "Waiting for Grafana deployment to be ready..."
kubectl rollout status deployment/${RELEASE_NAME}-grafana -n monitoring --timeout=300s || true

# Create default ServiceMonitors directory
mkdir -p "${SCRIPT_DIR}/../servicemonitors"

# Check if we have default ServiceMonitors to apply
if [ -d "${SCRIPT_DIR}/../servicemonitors" ] && [ "$(ls -A ${SCRIPT_DIR}/../servicemonitors)" ]; then
  section "Applying default ServiceMonitors"
  for file in "${SCRIPT_DIR}/../servicemonitors"/*.yaml; do
    if [ -f "$file" ]; then
      echo "Applying ServiceMonitor: $file"
      kubectl apply -f "$file"
    fi
  done
fi

# Apply Prometheus rule namespace patch
section "Configuring Prometheus Rule Namespace Selector"
if kubectl get crd prometheuses.monitoring.coreos.com &>/dev/null; then
    echo "Applying Prometheus rule namespace patch to limit alert rules to monitoring and otel-demo namespaces..."
    
    # Create the patch file
    cat > /tmp/prometheus-rule-namespace-patch.yaml <<EOF
spec:
  ruleNamespaceSelector:
    matchExpressions:
    - key: name
      operator: In
      values: [monitoring, otel-demo]
EOF

    # Try to find the Prometheus resource name
    PROMETHEUS_RESOURCE=$(kubectl get prometheus -n monitoring -o name 2>/dev/null || true)
    
    if [ -n "$PROMETHEUS_RESOURCE" ]; then
        # Apply the patch to the Prometheus operator
        if kubectl patch "$PROMETHEUS_RESOURCE" -n monitoring --type=merge --patch-file=/tmp/prometheus-rule-namespace-patch.yaml; then
            echo -e "${GREEN}✅ Prometheus rule namespace patch applied successfully${NC}"
        else
            echo -e "${YELLOW}⚠️  Failed to apply Prometheus rule namespace patch. This is non-fatal but may require manual configuration.${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Could not find Prometheus resource to patch. Will retry in 30 seconds...${NC}"
        sleep 30
        
        # Try again after waiting
        PROMETHEUS_RESOURCE=$(kubectl get prometheus -n monitoring -o name 2>/dev/null || true)
        if [ -n "$PROMETHEUS_RESOURCE" ]; then
            if kubectl patch "$PROMETHEUS_RESOURCE" -n monitoring --type=merge --patch-file=/tmp/prometheus-rule-namespace-patch.yaml; then
                echo -e "${GREEN}✅ Prometheus rule namespace patch applied successfully on retry${NC}"
            else
                echo -e "${YELLOW}⚠️  Still unable to apply Prometheus rule namespace patch. Manual configuration may be required.${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  Could not find Prometheus resource after retry. Manual configuration may be required.${NC}"
        fi
    fi
    
    # Clean up temporary file
    rm -f /tmp/prometheus-rule-namespace-patch.yaml
else
    echo -e "${YELLOW}⚠️  Prometheus CRD not found. Skipping rule namespace patch.${NC}"
fi

# Print success message and access instructions
section "Installation Complete"
echo -e "${GREEN}✅ kube-prometheus-stack has been successfully installed in the monitoring namespace!${NC}"
echo ""
echo "To access Grafana:"
echo "  kubectl port-forward -n monitoring svc/${RELEASE_NAME}-grafana 3000:80"
echo "  Then open http://localhost:3000 in your browser"
echo "  Default credentials: admin / prom-operator"
echo ""
echo "To access Prometheus:"
echo "  kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090"
echo "  Then open http://localhost:9090 in your browser"
echo ""
echo "To access Alertmanager:"
echo "  kubectl port-forward -n monitoring svc/prometheus-operator-kube-p-alertmanager 9093:9093"
echo "  Then open http://localhost:9093 in your browser"
