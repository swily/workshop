#!/bin/bash
set -e

# Create namespaces if they don't exist
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -

# Apply Prometheus RBAC
echo "Applying Prometheus RBAC..."
kubectl apply -f k8s/monitoring/prometheus-rbac.yaml

# Patch Prometheus service account
echo "Patching Prometheus deployment to use service account..."
kubectl patch deployment -n monitoring prometheus --patch '{"spec": {"template": {"spec": {"serviceAccountName": "prometheus"}}}}'

# Apply Prometheus config
echo "Updating Prometheus configuration..."
kubectl apply -f k8s/monitoring/prometheus-config.yaml

# Restart Prometheus to apply config
echo "Restarting Prometheus..."
kubectl rollout restart deployment -n monitoring prometheus

# Apply Istio telemetry config
echo "Applying Istio telemetry configuration..."
kubectl apply -f k8s/istio/istio-telemetry-config.yaml

# Patch Istio deployment
echo "Patching Istio deployment with resource limits..."
kubectl patch deployment -n istio-system istiod --patch-file k8s/istio/istiod-patch.yaml

# Restart Istio
echo "Restarting Istio..."
kubectl rollout restart deployment -n istio-system istiod

echo "Monitoring setup completed successfully!"
