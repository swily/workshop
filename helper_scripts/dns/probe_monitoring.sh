#!/bin/bash
# Probe Prometheus and Grafana endpoints via DNS and ELB with clean output
set -euo pipefail

CLUSTER_NAME=${CLUSTER_NAME:-current-workshop}

PROM_LB=$(kubectl -n monitoring get svc prometheus-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
GRAF_LB=$(kubectl -n monitoring get svc grafana-monitoring-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

PROM_DNS="${CLUSTER_NAME}-prometheus.gremlinpoc.com"
GRAF_DNS="${CLUSTER_NAME}-grafana-monitoring.gremlinpoc.com"

echo "Probing endpoints (DNS first, then ELB)..."

# Prometheus DNS
if [ -n "$PROM_DNS" ]; then
  echo "Prometheus DNS:"; curl -s -o /dev/null -w "%{http_code} %{remote_ip}\n" --max-time 10 "http://${PROM_DNS}:9090/api/v1/alerts" || true
fi

# Grafana DNS
if [ -n "$GRAF_DNS" ]; then
  echo "Grafana DNS:"; curl -s -o /dev/null -w "%{http_code} %{remote_ip}\n" --max-time 10 "http://${GRAF_DNS}/api/health" || true
fi

# Prometheus ELB
if [ -n "$PROM_LB" ]; then
  echo "Prometheus ELB:"; curl -s -o /dev/null -w "%{http_code} %{remote_ip}\n" --max-time 10 "http://${PROM_LB}:9090/api/v1/alerts" || true
else
  echo "Prometheus ELB: not available"
fi

# Grafana ELB
if [ -n "$GRAF_LB" ]; then
  echo "Grafana ELB:"; curl -s -o /dev/null -w "%{http_code} %{remote_ip}\n" --max-time 10 "http://${GRAF_LB}/api/health" || true
else
  echo "Grafana ELB: not available"
fi
