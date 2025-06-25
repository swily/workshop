#!/bin/bash
set -e

# Store the script directory for reliable path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/../templates/cartservice-deployment.yaml"

# Check if the template file exists
if [ ! -f "${TEMPLATE_FILE}" ]; then
    echo "Error: Template file not found at ${TEMPLATE_FILE}"
    exit 1
fi

echo "Updating cartservice deployment with improved configuration..."

# Check if the deployment exists
if kubectl get deployment -n otel-demo otel-demo-cartservice &> /dev/null; then
    echo "Existing deployment found. Deleting it first..."
    kubectl delete deployment -n otel-demo otel-demo-cartservice --wait=true
    
    # Wait for the deployment to be fully terminated
    echo "Waiting for old deployment to be fully terminated..."
    while kubectl get deployment -n otel-demo otel-demo-cartservice &> /dev/null; do
        echo -n "."
        sleep 1
    done
    echo ""
fi

# Apply the new deployment
echo "Applying new cartservice deployment..."
kubectl apply -f "${TEMPLATE_FILE}"

# Wait for rollout to complete
echo "Waiting for cartservice rollout to complete..."
kubectl rollout status deployment/otel-demo-cartservice -n otel-demo --timeout=180s

# Verify the pods are running
echo -e "\nVerifying cartservice pods..."
kubectl get pods -n otel-demo -l app.kubernetes.io/component=cartservice

echo -e "\nCartservice deployment updated successfully!"
