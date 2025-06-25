#!/bin/bash
set -e

echo "=== Verifying Monitoring Setup ===\n"

# Check Prometheus
function check_prometheus() {
    echo "Checking Prometheus..."
    if ! kubectl -n monitoring get pods -l app=prometheus &>/dev/null; then
        echo "❌ Prometheus pods not found"
        return 1
    fi
    
    local prom_pod=$(kubectl -n monitoring get pods -l app=prometheus -o jsonpath='{.items[0].metadata.name}')
    local status=$(kubectl -n monitoring get pod $prom_pod -o jsonpath='{.status.phase}')
    
    if [ "$status" != "Running" ]; then
        echo "❌ Prometheus pod is not running (status: $status)"
        return 1
    fi
    
    echo "✅ Prometheus is running"
    
    # Check Prometheus targets
    echo "\nChecking Prometheus targets..."
    local targets=$(kubectl -n monitoring exec $prom_pod -- wget -qO- 'http://localhost:9090/api/v1/targets' | jq -r '.data.activeTargets[].health' | sort | uniq -c)
    echo "Prometheus targets health status:"
    echo "$targets"
    
    if ! echo "$targets" | grep -q "up"; then
        echo "❌ No healthy Prometheus targets found"
        return 1
    fi
    
    echo "✅ Prometheus has healthy targets"
    return 0
}

# Check Istio
function check_istio() {
    echo "\nChecking Istio..."
    if ! kubectl -n istio-system get deployment istiod &>/dev/null; then
        echo "❌ Istio control plane not found"
        return 1
    fi
    
    local ready=$(kubectl -n istio-system get deployment istiod -o jsonpath='{.status.readyReplicas}')
    local desired=$(kubectl -n istio-system get deployment istiod -o jsonpath='{.status.replicas}')
    
    if [ "$ready" != "$desired" ]; then
        echo "❌ Istio control plane not ready ($ready/$desired pods ready)"
        return 1
    fi
    
    echo "✅ Istio control plane is running ($ready/$desired pods ready)"
    
    # Check Istio proxy metrics
    echo "\nChecking Istio proxy metrics..."
    local proxy_pod=$(kubectl -n istio-system get pods -l app=istio-ingressgateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$proxy_pod" ]; then
        echo "⚠️  No Istio ingress gateway pod found"
    else
        local metrics=$(kubectl -n istio-system exec $proxy_pod -c istio-proxy -- curl -s http://localhost:15090/stats/prometheus | grep -i istio_requests_total | wc -l)
        if [ "$metrics" -gt 0 ]; then
            echo "✅ Found $metrics Istio metrics in the proxy"
        else
            echo "❌ No Istio metrics found in the proxy"
            return 1
        fi
    fi
    
    return 0
}

# Check OpenTelemetry Collector
function check_otel() {
    echo "\nChecking OpenTelemetry Collector..."
    if ! kubectl -n otel-demo get deployment otel-collector &>/dev/null; then
        echo "⚠️  OpenTelemetry Collector not found in otel-demo namespace"
        return 0
    fi
    
    local ready=$(kubectl -n otel-demo get deployment otel-collector -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired=$(kubectl -n otel-demo get deployment otel-collector -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
    
    if [ "$ready" != "$desired" ]; then
        echo "⚠️  OpenTelemetry Collector not ready ($ready/$desired pods ready)"
        return 0
    fi
    
    echo "✅ OpenTelemetry Collector is running ($ready/$desired pods ready)"
    return 0
}

# Run all checks
check_prometheus
check_istio
check_otel

echo "\n=== Verification Complete ==="
