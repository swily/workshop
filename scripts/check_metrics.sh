#!/bin/bash
# Diagnostic script for Prometheus metrics
set -e

PROM="${1:-http://localhost:9091}"  # Allow overriding Prometheus URL
NS="${2:-otel-demo}"
OUTPUT_FILE="/tmp/prom_metrics_check_$(date +%s).log"

echo "Starting metrics check at $(date)" | tee -a "$OUTPUT_FILE"
echo "Prometheus: $PROM" | tee -a "$OUTPUT_FILE"
echo "Namespace: $NS" | tee -a "$OUTPUT_FILE"

# Function to run a query and log results
run_query() {
  local name="$1"
  local query="$2"
  echo -e "\n=== $name ===" | tee -a "$OUTPUT_FILE"
  echo "Query: $query" | tee -a "$OUTPUT_FILE"
  
  # Run the query and capture both stdout and stderr
  local result
  result=$(curl -sS --connect-timeout 10 -G --data-urlencode "query=$query" "${PROM}/api/v1/query" 2>&1)
  
  # Check if curl failed
  local curl_exit=$?
  if [ $curl_exit -ne 0 ]; then
    echo "ERROR: curl failed with exit code $curl_exit" | tee -a "$OUTPUT_FILE"
    echo "Output: $result" | tee -a "$OUTPUT_FILE"
    return 1
  fi
  
  # Check if the response is valid JSON
  if ! echo "$result" | jq -e . >/dev/null 2>&1; then
    echo "ERROR: Invalid JSON response" | tee -a "$OUTPUT_FILE"
    echo "Response: $result" | tee -a "$OUTPUT_FILE"
    return 1
  fi
  
  # Check for Prometheus API errors
  local error=$(echo "$result" | jq -r '.error // empty')
  if [ -n "$error" ]; then
    echo "ERROR: $error" | tee -a "$OUTPUT_FILE"
    return 1
  fi
  
  # Extract and display the result
  local result_count=$(echo "$result" | jq -r '.data.result | length')
  echo "Found $result_count results" | tee -a "$OUTPUT_FILE"
  
  if [ "$result_count" -gt 0 ]; then
    echo "First result:" | tee -a "$OUTPUT_FILE"
    echo "$result" | jq -c '.data.result[0]' | tee -a "$OUTPUT_FILE"
    
    # For metrics with multiple time series, show a count by metric/label
    if [ "$result_count" -gt 1 ]; then
      echo -e "\nBreakdown by metric/label:" | tee -a "$OUTPUT_FILE"
      echo "$result" | jq -r '.data.result[] | to_entries | map(select(.key != "value")) | from_entries | to_entries | map("\(.key)=\(.value)") | join(", ")' | sort | uniq -c | sort -nr | head -n 10 | tee -a "$OUTPUT_FILE"
    fi
  else
    echo "No results found" | tee -a "$OUTPUT_FILE"
  fi
}

# List all available metrics
echo -e "\n=== Available Metrics ===" | tee -a "$OUTPUT_FILE"
curl -sS --connect-timeout 10 -G "${PROM}/api/v1/label/__name__/values" | jq -r '.data[]' | sort > "/tmp/available_metrics.txt"
AVAILABLE_METRICS=$(wc -l < "/tmp/available_metrics.txt")
echo "Found $AVAILABLE_METRICS metrics" | tee -a "$OUTPUT_FILE"

# Check for key metrics
echo -e "\n=== Key Metrics Check ===" | tee -a "$OUTPUT_FILE"
for metric in \
  kube_deployment_status_replicas_available \
  container_cpu_usage_seconds_total \
  container_memory_working_set_bytes \
  kube_pod_container_status_restarts_total \
  istio_requests_total \
  spanmetrics_calls_total; do
  
  if grep -q "^$metric$" "/tmp/available_metrics.txt"; then
    echo "FOUND: $metric" | tee -a "$OUTPUT_FILE"
  else
    echo "MISSING: $metric" | tee -a "$OUTPUT_FILE"
  fi
done

# Run diagnostic queries
run_query "Deployment Availability" "kube_deployment_status_replicas_available{namespace=\"$NS\"}"
run_query "CPU Usage" "sum(rate(container_cpu_usage_seconds_total{namespace=\"$NS\",container!~\"POD|istio-proxy\"}[5m])) by (container)"
run_query "Memory Usage" "sum(container_memory_working_set_bytes{namespace=\"$NS\",container!~\"POD|istio-proxy\"}) by (container)"
run_query "Pod Restarts (5m increase)" "sum(increase(kube_pod_container_status_restarts_total{namespace=\"$NS\"}[5m])) by (pod, container)"
run_query "Istio Request Rate" "sum(rate(istio_requests_total{destination_workload_namespace=\"$NS\"}[5m])) by (destination_service, response_code)"
run_query "Spanmetrics Calls" "sum(rate(spanmetrics_calls_total[5m])) by (service)"

# Check for Istio metrics
if grep -q "^istio_" "/tmp/available_metrics.txt"; then
  echo -e "\n=== Istio Metrics Detected ===" | tee -a "$OUTPUT_FILE"
  run_query "Istio Request Duration (p95)" "histogram_quantile(0.95, sum(rate(istio_request_duration_milliseconds_bucket{destination_workload_namespace=\"$NS\"}[5m])) by (le, destination_service))"
  run_query "Istio Request Errors" "sum(rate(istio_requests_total{destination_workload_namespace=\"$NS\", response_code=~\"5..\"}[5m])) by (destination_service)"
else
  echo -e "\n=== No Istio Metrics Found ===" | tee -a "$OUTPUT_FILE"
fi

# Check for spanmetrics
if grep -q "^spanmetrics_" "/tmp/available_metrics.txt"; then
  echo -e "\n=== Spanmetrics Detected ===" | tee -a "$OUTPUT_FILE"
  run_query "Spanmetrics Latency (p95)" "histogram_quantile(0.95, sum(rate(spanmetrics_latency_bucket[5m])) by (le, service))"
  run_query "Spanmetrics Errors" "sum(rate(spanmetrics_calls_total{status_code=\"STATUS_CODE_ERROR\"}[5m])) by (service)"
else
  echo -e "\n=== No Spanmetrics Found ===" | tee -a "$OUTPUT_FILE"
fi

echo -e "\n=== Summary ===" | tee -a "$OUTPUT_FILE"
echo "Diagnostic output written to: $OUTPUT_FILE" | tee -a "$OUTPUT_FILE"
echo -e "\nTo view the full output:"
echo "  cat $OUTPUT_FILE | less"

# Clean up
exit 0
