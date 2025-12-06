#!/bin/bash
# Script to update the load generator to point to the external load balancer
# This should be run after the load balancer is created

set -e

# Check if hostname is provided as argument
if [ -n "$1" ]; then
    LB_HOSTNAME=$(echo "$1" | sed 's|http://||' | sed 's|/.*||')
    echo "✅ Using provided hostname: $LB_HOSTNAME"
else
    # Get the load balancer hostname from ingress
    echo "Getting load balancer hostname from ingress..."
    LB_HOSTNAME=$(kubectl get ingress -n otel-demo otel-demo-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

    if [ -z "$LB_HOSTNAME" ]; then
        echo "❌ Error: Load balancer hostname not found!"
        echo "Make sure the load balancer is created first with:"
        echo "  ./build_scripts/load-balancer/install.sh"
        exit 1
    fi

    echo "✅ Found load balancer hostname: $LB_HOSTNAME"
fi

# Update the load generator patch with the actual hostname
echo "Updating load generator to target load balancer..."
sed -i.bak "s/LOAD_BALANCER_HOSTNAME/$LB_HOSTNAME/g" /Users/seanwiley/workshop/patches/load-generator-loadbalancer-patch.yaml

# Apply the updated patch
echo "Applying load generator patch..."
kubectl patch deployment opentelemetry-demo-loadgenerator -n otel-demo --patch-file /Users/seanwiley/workshop/patches/load-generator-loadbalancer-patch.yaml

# Wait for rollout
echo "Waiting for load generator rollout..."
kubectl rollout status deployment/opentelemetry-demo-loadgenerator -n otel-demo --timeout=60s

# Verify the configuration
echo "✅ Load generator updated successfully!"
echo "Load generator is now targeting: http://$LB_HOSTNAME"

# Check pod status
echo "Checking load generator pod status..."
kubectl get pods -n otel-demo | grep loadgenerator

echo ""
echo "🎯 Load generator is now configured to:"
echo "   • Target the external load balancer (enables Gremlin health checks)"
echo "   • Use optimized resource limits (500m CPU, 1Gi memory)"
echo "   • Run with reduced load (5 users, 0.5 spawn rate)"
echo "   • Disable browser traffic for efficiency"
