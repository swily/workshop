#!/bin/bash -e

# Ensure required environment variable is set
if [ -z "${CLUSTER_NAME}" ]; then
  echo "CLUSTER_NAME environment variable must be set"
  exit 1
fi

# Update kubeconfig
echo "Updating kubeconfig..."
eksctl utils write-kubeconfig --cluster ${CLUSTER_NAME}

# Function to delete namespace and wait for completion
delete_namespace() {
    local ns=$1
    echo "Cleaning up namespace: $ns"
    
    # Delete any finalizers from resources in the namespace
    echo "Removing finalizers from resources in $ns namespace..."
    for type in deployment statefulset daemonset service pod pvc configmap secret; do
        kubectl get $type -n $ns -o json | jq '.items[] | select(.metadata.finalizers != null) | .metadata.name' 2>/dev/null | xargs -r -I{} kubectl patch $type -n $ns {} -p '{"metadata":{"finalizers":[]}}' --type=merge || true
    done
    
    # Force delete the namespace
    kubectl delete namespace $ns --force --grace-period=0 || true
    
    # Wait for namespace to be fully deleted
    while kubectl get namespace $ns >/dev/null 2>&1; do
        echo "Waiting for $ns namespace to be deleted..."
        sleep 2
    done
}

# Clean up Helm releases first
echo "Cleaning up Helm releases..."
for ns in otel-demo monitoring gremlin; do
    # List and remove all Helm releases in the namespace
    echo "Cleaning up Helm releases in $ns namespace..."
    helm ls -n $ns -q | xargs -r helm uninstall -n $ns 2>/dev/null || true

    # Clean up Helm secrets
    echo "Cleaning up Helm secrets in $ns namespace..."
    kubectl get secrets -n $ns -o json | jq -r '.items[] | select(.metadata.annotations["meta.helm.sh/release-name"]) | .metadata.name' | xargs -r kubectl delete secrets -n $ns 2>/dev/null || true

    # Clean up Helm configmaps
    echo "Cleaning up Helm configmaps in $ns namespace..."
    kubectl get configmaps -n $ns -o json | jq -r '.items[] | select(.metadata.annotations["meta.helm.sh/release-name"]) | .metadata.name' | xargs -r kubectl delete configmaps -n $ns 2>/dev/null || true
done

# Delete namespaces and wait for completion
for ns in otel-demo monitoring gremlin; do
    delete_namespace $ns
done

# Delete Prometheus CRDs
echo "Removing Prometheus CRDs..."
PROM_CRDS="alertmanagerconfigs.monitoring.coreos.com alertmanagers.monitoring.coreos.com podmonitors.monitoring.coreos.com probes.monitoring.coreos.com prometheusagents.monitoring.coreos.com prometheuses.monitoring.coreos.com prometheusrules.monitoring.coreos.com scrapeconfigs.monitoring.coreos.com servicemonitors.monitoring.coreos.com thanosrulers.monitoring.coreos.com"

for crd in $PROM_CRDS; do
    kubectl delete crd $crd --force --grace-period=0 2>/dev/null || true
done

# Wait for CRDs to be fully deleted
echo "Waiting for Prometheus CRDs to be fully deleted..."
for crd in $PROM_CRDS; do
    while kubectl get crd $crd >/dev/null 2>&1; do
        echo "Waiting for $crd to be deleted..."
        sleep 2
    done
done

# Delete any leftover PVs and PVCs
echo "Cleaning up persistent volumes..."
kubectl delete pv --all --force --grace-period=0 2>/dev/null || true
kubectl delete pvc --all --all-namespaces --force --grace-period=0 2>/dev/null || true

echo "Cluster cleanup complete. You can now run configure_cluster.sh"
