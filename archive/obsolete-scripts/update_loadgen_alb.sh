#!/bin/bash
# Script to update load generator to use ALB endpoint from ingress
# This is specifically for enhanced configuration with ALB ingress

set -euo pipefail

# Function to get ALB hostname from ingress
get_alb_hostname() {
    local ingress_name="$1"
    local namespace="$2"
    
    echo "Getting ALB hostname from ingress ${ingress_name} in namespace ${namespace}..." >&2
    
    # Wait for ingress to have a hostname (up to 5 minutes)
    local timeout=300
    local elapsed=0
    local interval=10
    
    while [ $elapsed -lt $timeout ]; do
        local hostname=$(kubectl get ingress "$ingress_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        
        if [ -n "$hostname" ]; then
            echo "Found ALB hostname: $hostname" >&2
            echo "$hostname"
            return 0
        fi
        
        echo "Waiting for ALB to be provisioned... (${elapsed}s/${timeout}s)" >&2
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo "Timeout waiting for ALB hostname" >&2
    return 1
}

# Function to update load generator LOCUST_HOST
update_load_generator() {
    local alb_hostname="$1"
    local alb_url="http://${alb_hostname}"
    
    # Read current LOCUST_HOST
    local current_host
    current_host=$(kubectl get deployment opentelemetry-demo-loadgenerator -n otel-demo -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="LOCUST_HOST")].value}' 2>/dev/null || echo "")

    if [ "${current_host:-}" = "$alb_url" ]; then
        echo "LOCUST_HOST already set correctly: $current_host"
    else
        echo "Updating load generator LOCUST_HOST -> $alb_url (was: ${current_host:-<unset>})"
        # Safely update only the LOCUST_HOST env var without clobbering others
        kubectl -n otel-demo set env deploy/opentelemetry-demo-loadgenerator "LOCUST_HOST=$alb_url"

        # Wait for rollout
        echo "Waiting for load generator rollout..."
        kubectl -n otel-demo rollout status deploy/opentelemetry-demo-loadgenerator --timeout=180s

        # Verify the update
        current_host=$(kubectl get deployment opentelemetry-demo-loadgenerator -n otel-demo -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="LOCUST_HOST")].value}')
        if [ "$current_host" != "$alb_url" ]; then
            echo "Failed to update LOCUST_HOST (expected: $alb_url, got: $current_host)" >&2
            return 1
        fi
        echo "Load generator updated successfully! Current LOCUST_HOST: $current_host"
    fi
}

# Main execution
echo "=== Updating Load Generator for ALB Integration ==="

# Wait for a known frontend Ingress to exist (enhanced ALB path)
INGRESS_NAME=""
echo "Looking for frontend Ingress in namespace otel-demo..."
for i in {1..60}; do # up to ~5 minutes
    if kubectl get ingress frontend-proxy -n otel-demo &>/dev/null; then
        INGRESS_NAME="frontend-proxy"
        break
    fi
    if kubectl get ingress otel-demo-ingress -n otel-demo &>/dev/null; then
        INGRESS_NAME="otel-demo-ingress"
        break
    fi
    echo "Waiting for frontend Ingress to be created... (${i}/60)"
    sleep 5
done

if [ -z "$INGRESS_NAME" ]; then
    echo "No frontend Ingress found after waiting. Ensure enhanced ALB ingress is enabled."
    echo "For basic configuration, use: ./helper_scripts/update_loadgen_target.sh"
    exit 1
fi

echo "Found ingress: $INGRESS_NAME"

# Get ALB hostname
ALB_HOSTNAME=$(get_alb_hostname "$INGRESS_NAME" "otel-demo")
if [ $? -ne 0 ]; then
    exit 1
fi

# Update load generator
update_load_generator "$ALB_HOSTNAME"

echo ""
echo "Load generator ALB integration complete!"
echo "Demo accessible at: http://$ALB_HOSTNAME"
echo "Load generator web UI: http://$ALB_HOSTNAME/loadgen"
echo "Grafana: http://$ALB_HOSTNAME/grafana"
echo "Jaeger: http://$ALB_HOSTNAME/jaeger"
