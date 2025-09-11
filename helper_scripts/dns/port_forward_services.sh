#!/bin/bash

# Port forwarding script for OpenTelemetry demo and monitoring services

# Check if a port is in use
check_port() {
  lsof -i :$1 >/dev/null 2>&1
}

# Function to start port forwarding with error handling
start_port_forward() {
  local namespace=$1
  local service=$2
  local local_port=$3
  local service_port=$4
  local name=$5
  
  # Check if port is already in use
  if check_port $local_port; then
    # Check if it's our own process
    if pgrep -f "kubectl port-forward.*:$local_port" >/dev/null 2>&1; then
      echo "$name: http://localhost:$local_port"
    else
      echo "Port $local_port is already in use by another process. Skipping $name."
    fi
  else
    kubectl port-forward -n $namespace svc/$service $local_port:$service_port >/dev/null 2>&1 &
    sleep 2
    if check_port $local_port; then
      echo "$name: http://localhost:$local_port"
    else
      echo "Failed to start port forwarding for $name"
    fi
  fi
}

# Kill any existing port-forward processes
pkill -f "kubectl port-forward" >/dev/null 2>&1
sleep 3

# OpenTelemetry Demo Services
start_port_forward "otel-demo" "frontend-proxy" 8080 8080 "Frontend Proxy"
start_port_forward "otel-demo" "jaeger-query" 16686 16686 "Jaeger UI"
start_port_forward "otel-demo" "grafana" 3000 80 "OpenTelemetry Grafana"
start_port_forward "otel-demo" "prometheus" 9090 9090 "OpenTelemetry Prometheus"

# Monitoring Namespace Services
start_port_forward "monitoring" "prometheus-grafana" 3100 80 "Monitoring Grafana"
start_port_forward "monitoring" "prometheus-kube-prometheus-prometheus" 9090 9090 "Prometheus"
start_port_forward "monitoring" "prometheus-kube-prometheus-alertmanager" 9093 9093 "Alertmanager"

# Additional useful services for chaos engineering
start_port_forward "otel-demo" "load-generator" 8089 8089 "Load Generator UI"
start_port_forward "otel-demo" "otel-collector" 8889 8889 "OTel Collector Metrics"

echo "\nServices are now available:"
echo "Frontend Proxy: http://localhost:8080"
echo "Jaeger UI: http://localhost:16686"
echo "OpenTelemetry Grafana: http://localhost:3000"
echo "Prometheus: http://localhost:9090"
echo "Monitoring Grafana: http://localhost:3100"
echo "Prometheus: http://localhost:9090"
echo "Alertmanager: http://localhost:9093"
echo "Load Generator UI: http://localhost:8089"
echo "OTel Collector Metrics: http://localhost:8889/metrics"
