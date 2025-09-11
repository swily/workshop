#!/bin/bash -e

# Comprehensive Metric Validation Script for otel-demo Resources
# This script validates that otel-demo services have meaningful metrics before creating alerts and health checks

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OTEL_DEMO_NAMESPACE="otel-demo"
PROMETHEUS_NAMESPACE="monitoring"
PROMETHEUS_PORT="9090"
GRAFANA_PORT="3100"
VERBOSE=${VERBOSE:-0}

# Expected otel-demo services (aligned with deployed names)
OTEL_DEMO_SERVICES=(
  "frontend"
  "cart"
  "product-catalog"
  "currency"
  "payment"
  "shipping"
  "email"
  "checkout"
  "recommendation"
  "ad"
  "accounting"
)

# Function to print section headers
section() {
  echo -e "\n${GREEN}=== $1 ===${NC}"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# URL-encode a string for safe HTTP use
urlencode() {
  # Uses Python for robust encoding if available, else fallback to sed (limited)
  local raw="$1"
  if command_exists python3; then
    python3 - <<PY
import urllib.parse
print(urllib.parse.quote('''$raw''', safe=''))
PY
  else
    # Fallback minimal encoding for common PromQL special chars
    echo "$raw" \
      | sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/\{/%7B/g' -e 's/\}/%7D/g' -e 's/\"/%22/g' -e 's/,/%2C/g' -e 's/\[/ %5B/g' -e 's/\]/%5D/g' -e 's/\|/%7C/g' -e 's/\+/%2B/g' -e 's/:/%3A/g' -e 's/=/%3D/g'
  fi
}

# Function to wait for port-forward to be ready
wait_for_port_forward() {
  local port="$1"
  local service_name="$2"
  local max_attempts=30
  local attempt=1
  
  echo "Waiting for ${service_name} port-forward on port ${port}..."
  
  while [ $attempt -le $max_attempts ]; do
    if curl -s "http://localhost:${port}" >/dev/null 2>&1; then
      echo -e "${GREEN}✅ ${service_name} port-forward ready on port ${port}${NC}"
      return 0
    fi
    echo -n "."
    sleep 2
    attempt=$((attempt + 1))
  done
  
  echo -e "${RED}❌ ${service_name} port-forward failed to become ready on port ${port}${NC}"
  return 1
}

# Function to query Prometheus for a metric
query_prometheus_metric() {
  local query="$1"
  local description="$2"
  local quiet_on_empty="${3:-0}"
  
  echo "Checking: ${description}"
  
  local enc_query=$(urlencode "${query}")
  local response=$(curl -s "http://localhost:${PROMETHEUS_PORT}/api/v1/query?query=${enc_query}" 2>/dev/null)
  
  if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to query Prometheus${NC}"
    return 1
  fi
  
  # Check if response is valid JSON
  if ! echo "$response" | jq . >/dev/null 2>&1; then
    echo -e "${RED}❌ Invalid JSON response from Prometheus${NC}"
    return 1
  fi
  
  # Check if query was successful
  local status=$(echo "$response" | jq -r '.status')
  if [ "$status" != "success" ]; then
    echo -e "${RED}❌ Prometheus query failed: ${status}${NC}"
    return 1
  fi
  
  # Check if there are results
  local result_count=$(echo "$response" | jq '.data.result | length')
  if [ "$result_count" -eq 0 ]; then
    if [ "$quiet_on_empty" = "1" ] && [ "$VERBOSE" -eq 0 ]; then
      # Suppress noisy per-service empties unless VERBOSE enabled
      echo -e "${YELLOW}No metrics found for: ${description}${NC}" >/dev/null
    else
      echo -e "${RED}❌ No metrics found for: ${description}${NC}"
    fi
    return 1
  fi
  
  # Check if values are meaningful - focus on load-generated traffic
  local values=$(echo "$response" | jq -r '.data.result[].value[1]')
  local meaningful_values=0
  local total_values=0
  
  while IFS= read -r value; do
    total_values=$((total_values + 1))
    # For 'up' metrics: 1 = healthy, 0 = down
    # For request/traffic metrics: > 0 indicates load generation is working
    if [ "$value" != "null" ] && [ "$value" != "" ]; then
      if [[ "$query" == *"up{"* ]]; then
        # For 'up' metrics, we want value = 1 (service is up)
        if [ "$value" = "1" ]; then
          meaningful_values=$((meaningful_values + 1))
        fi
      else
        # For traffic metrics, we want value > 0 (traffic is flowing)
        if (( $(echo "$value > 0" | bc -l 2>/dev/null || echo "0") )); then
          meaningful_values=$((meaningful_values + 1))
        fi
      fi
    fi
  done <<< "$values"
  
  if [ $meaningful_values -gt 0 ]; then
    echo -e "${GREEN}✅ Found ${meaningful_values}/${total_values} healthy/active metric values${NC}"
    return 0
  else
    if [ "$quiet_on_empty" = "1" ] && [ "$VERBOSE" -eq 0 ]; then
      echo -e "${YELLOW}No healthy/active metric values found for: ${description}${NC}" >/dev/null
    else
      echo -e "${RED}❌ No healthy/active metric values found (${total_values} total)${NC}"
    fi
    return 1
  fi
}

# Quiet wrapper to reduce noise for fallback checks
query_prometheus_metric_quiet() {
  local query="$1"
  local description="$2"
  query_prometheus_metric "$query" "$description" 1
}

# Function to validate otel-demo namespace and pods
validate_otel_demo_deployment() {
  section "Validating otel-demo Deployment"
  
  # Check if namespace exists
  if ! kubectl get namespace "$OTEL_DEMO_NAMESPACE" >/dev/null 2>&1; then
    echo -e "${RED}❌ otel-demo namespace not found${NC}"
    echo -e "${YELLOW}Please deploy otel-demo first using: ./build_scripts/demo/otel_demo.sh${NC}"
    return 1
  fi
  
  echo "otel-demo namespace exists"
  
  # Check if pods are running
  local running_pods=$(kubectl get pods -n "$OTEL_DEMO_NAMESPACE" --field-selector=status.phase=Running --no-headers | wc -l)
  local total_pods=$(kubectl get pods -n "$OTEL_DEMO_NAMESPACE" --no-headers | wc -l)
  
  printf "Pod status: %s/%s running" "$running_pods" "$total_pods"
  
  if [ "$running_pods" -lt 8 ]; then
    echo " - insufficient pods running"
    return 1
  fi
  
  echo " - ready"
  return 0
}

# Function to validate Prometheus is ready and has otel-demo metrics
validate_prometheus_metrics() {
  section "Validating Prometheus Metrics for otel-demo"
  
  # Prefer the otel-demo namespace Prometheus (receives OTLP from collector)
  local pf_pid=""
  local prom_ns=""
  local prom_svc=""
  if kubectl get svc -n "${OTEL_DEMO_NAMESPACE}" otel-demo-prometheus-server >/dev/null 2>&1; then
    prom_ns="${OTEL_DEMO_NAMESPACE}"; prom_svc="otel-demo-prometheus-server"
  elif kubectl get svc -n "${OTEL_DEMO_NAMESPACE}" prometheus >/dev/null 2>&1; then
    prom_ns="${OTEL_DEMO_NAMESPACE}"; prom_svc="prometheus"
  elif kubectl get svc -n "$PROMETHEUS_NAMESPACE" prometheus-operated >/dev/null 2>&1; then
    prom_ns="$PROMETHEUS_NAMESPACE"; prom_svc="prometheus-operated"
  else
    echo -e "${RED}❌ No Prometheus service found in otel-demo or monitoring namespaces${NC}"
    return 1
  fi
  echo "Using Prometheus service $prom_svc in namespace $prom_ns"
  
  # Start port-forward for Prometheus (background process) if not already responding
  if ! curl -s "http://localhost:${PROMETHEUS_PORT}/-/healthy" >/dev/null 2>&1; then
    kubectl port-forward -n "$prom_ns" "svc/${prom_svc}" "$PROMETHEUS_PORT:9090" >/dev/null 2>&1 &
    pf_pid=$!
    disown
  else
    pf_pid=""
  fi
  
  echo "Waiting for Prometheus port-forward on port $PROMETHEUS_PORT..."
  wait_for_port_forward $PROMETHEUS_PORT
  echo "Prometheus port-forward ready on port $PROMETHEUS_PORT" >/dev/null 2>&1 || true
  
  # Check otel-collector is working first (this is what actually collects metrics)
  echo -e "\n${BLUE}Checking otel-collector activity:${NC}"
  query_prometheus_metric "otelcol_receiver_accepted_spans_total" "OpenTelemetry Collector availability"
  
  echo ""
  echo "Checking aggregated metrics:"
  query_prometheus_metric "otelcol_receiver_accepted_spans_total > 0" "OpenTelemetry spans received"
  query_prometheus_metric "otelcol_processor_batch_batch_send_size_sum > 0" "OpenTelemetry batch processing"
  query_prometheus_metric "calls_total" "Span metrics from traces"
  
  # Check service availability (simplified)
  local services=(frontend cart product-catalog currency payment shipping email checkout recommendation ad accounting)
  local healthy_services=0
  for service in "${services[@]}"; do
    if query_prometheus_metric_quiet "kube_deployment_status_replicas_available{deployment=\"$service\", namespace=\"$OTEL_DEMO_NAMESPACE\"}"; then
      ((healthy_services++))
    fi
  done
  
  echo "Service deployments: $healthy_services/${#services[@]} ready"
  
  if [ "$healthy_services" -ge 8 ]; then
    echo "Sufficient otel-demo services have valid metrics"
    return 0
  else
    echo "Insufficient services with valid metrics (need at least 8)"
    return 1
  fi
}

# Function to validate Grafana is ready
validate_grafana_readiness() {
  section "Validating Grafana Readiness"
  
  # Check if Grafana is running (handle both prometheus and prometheus-operator releases)
  if ! kubectl get pod -n "$PROMETHEUS_NAMESPACE" -l app.kubernetes.io/name=grafana >/dev/null 2>&1; then
    echo -e "${RED}❌ Grafana not found in monitoring namespace${NC}"
    return 1
  fi
  
  echo "Grafana deployment found"
  
  echo "Starting Grafana port-forward..."
  local grafana_svc=""
  if kubectl get svc -n "$PROMETHEUS_NAMESPACE" prometheus-grafana >/dev/null 2>&1; then
    grafana_svc="prometheus-grafana"
  elif kubectl get svc -n "$PROMETHEUS_NAMESPACE" prometheus-operator-grafana >/dev/null 2>&1; then
    grafana_svc="prometheus-operator-grafana"
  else
    echo -e "${RED}❌ No Grafana service found${NC}"
    return 1
  fi
  
  echo "Using Grafana service: $grafana_svc"
  
  # Start port-forward for Grafana
  kubectl port-forward -n "$PROMETHEUS_NAMESPACE" "svc/$grafana_svc" "$GRAFANA_PORT:80" >/dev/null 2>&1 &
  local pf_pid=$!
  
  echo "Waiting for Grafana port-forward on port $GRAFANA_PORT..."
  wait_for_port_forward $GRAFANA_PORT
  echo "Grafana port-forward ready on port $GRAFANA_PORT"
  
  # Test Grafana API
  if curl -s "http://localhost:$GRAFANA_PORT/api/health" >/dev/null 2>&1; then
    echo "Grafana API is responding and healthy"
    kill $pf_pid 2>/dev/null || true
    return 0
  else
    echo "Grafana API is not responding"
    kill $pf_pid 2>/dev/null || true
    return 1
  fi
}

# Function to validate alert rules exist and are active (silent unless errors)
validate_alert_rules() {
  local platform="$1"
  local service_name="$2"
  local namespace="$3"
  
  # Silent validation - only report errors
  case "$platform" in
    "prometheus")
      if ! curl -s "http://localhost:${PROMETHEUS_PORT}/api/v1/rules" | jq -r '.data.groups[].rules[] | select(.type=="alerting") | .name' | grep -q "."; then
        echo -e "${RED}Error: No Prometheus alert rules found${NC}"
        return 1
      fi
      return 0
      ;;
    *)
      return 0  # Silent success for other platforms
      ;;
  esac
}

# Main validation function (silent unless errors)
main() {
  # Set up validation steps
  local validation_steps=("validate_otel_demo_deployment" "validate_prometheus_metrics" "validate_grafana_readiness")
  local total_validations=${#validation_steps[@]}
  local successful_validations=0
  local errors_found=false
  
  # Run each validation step silently
  for validation_step in "${validation_steps[@]}"; do
    if $validation_step >/dev/null 2>&1; then
      successful_validations=$((successful_validations + 1))
    else
      echo -e "${RED}Validation failed: ${validation_step}${NC}"
      errors_found=true
    fi
  done
  
  # Only show summary if errors found
  if [ "$errors_found" = true ]; then
    echo "Some validations failed. Please check the issues above."
    return 1
  fi
  
  # Silent success
  return 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
