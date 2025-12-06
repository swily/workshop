#!/bin/bash -e

# Ensure required environment variable is set
if [ -z "${CLUSTER_NAME}" ]; then
  echo "CLUSTER_NAME environment variable must be set"
  exit 1
fi

# Update kubeconfig
echo "Updating kubeconfig..."
eksctl utils write-kubeconfig --cluster ${CLUSTER_NAME}

echo "🧽 Cleaning Helm resources..."

# Function to forcefully clean up a namespace
clean_namespace() {
    local ns=$1
    # Silent cleanup - only show errors
    
    # Force delete all pods in the namespace (silent)
    kubectl get pods -n $ns --no-headers | awk '{print $1}' | xargs -r kubectl delete pod -n $ns --force --grace-period=0 >/dev/null 2>&1 || true
    
    # Force delete all other resources (silent)
    kubectl delete all --all -n $ns --force --grace-period=0 >/dev/null 2>&1 || true
    
    # Delete any finalizers from remaining resources (silent)
    for type in deployment statefulset daemonset service pod pvc configmap secret; do
        kubectl get $type -n $ns -o json 2>/dev/null | jq '.items[] | select(.metadata.finalizers != null) | .metadata.name' 2>/dev/null | xargs -r -I{} kubectl patch $type -n $ns {} -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
    done
    
    # Force delete the namespace
    kubectl delete namespace $ns --force --grace-period=0 >/dev/null 2>&1 || true
    
    # If namespace is still stuck, patch out finalizers (silent)
    if kubectl get namespace $ns >/dev/null 2>&1; then
        kubectl patch namespace $ns -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
    fi
    
    # Wait for namespace to be fully deleted (with timeout)
    local timeout=60
    local count=0
    while kubectl get namespace $ns >/dev/null 2>&1 && [ $count -lt $timeout ]; do
        sleep 1
        count=$((count + 1))
    done
}

# Clean up Helm releases first (silent)
for ns in otel-demo monitoring gremlin; do
    # List and remove all Helm releases in the namespace
    helm list -n $ns -q | xargs -r helm uninstall -n $ns >/dev/null 2>&1 || true

    # Clean up Helm secrets (silent)
    kubectl get secrets -n $ns | grep helm | awk '{print $1}' | xargs -r kubectl delete secret -n $ns >/dev/null 2>&1 || true

    # Clean up Helm configmaps (silent)
    kubectl get configmaps -n $ns | grep helm | awk '{print $1}' | xargs -r kubectl delete configmap -n $ns >/dev/null 2>&1 || true
done

# Clean up legacy patches that may persist across deployments
echo "🧽 Cleaning legacy patches..."
# Remove any deployments that might have legacy patch configurations
kubectl delete deployment cart -n otel-demo --ignore-not-found=true >/dev/null 2>&1 || true

# Delete namespaces and wait for completion
echo "🧽 Cleaning namespaces..."
for ns in otel-demo monitoring gremlin; do
    clean_namespace $ns
done

# Delete Prometheus CRDs (silent)
PROM_CRDS="alertmanagerconfigs.monitoring.coreos.com alertmanagers.monitoring.coreos.com podmonitors.monitoring.coreos.com probes.monitoring.coreos.com prometheusagents.monitoring.coreos.com prometheuses.monitoring.coreos.com prometheusrules.monitoring.coreos.com scrapeconfigs.monitoring.coreos.com servicemonitors.monitoring.coreos.com thanosrulers.monitoring.coreos.com"

for crd in $PROM_CRDS; do
    kubectl delete crd $crd --force --grace-period=0 >/dev/null 2>&1 || true
done

# Wait for CRDs to be fully deleted (silent)
for crd in $PROM_CRDS; do
    while kubectl get crd $crd >/dev/null 2>&1; do
        sleep 1
    done
done

# Delete any leftover PVs and PVCs
echo "Cleaning up persistent volumes..."
kubectl delete pv --all --force --grace-period=0 2>/dev/null || true
kubectl delete pvc --all --all-namespaces --force --grace-period=0 2>/dev/null || true

echo "Cluster cleanup complete. You can now run configure_cluster.sh"
