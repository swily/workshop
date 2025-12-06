#!/bin/bash -e

# Ensure required environment variable is set
if [ -z "${CLUSTER_NAME}" ]; then
  echo "CLUSTER_NAME environment variable must be set"
  exit 1
fi

# Set timeout in seconds (30 minutes max)
TIMEOUT=1800
START_TIME=$(date +%s)

timeout_check() {
  local current_time=$(date +%s)
  local elapsed=$((current_time - START_TIME))
  if [ $elapsed -ge $TIMEOUT ]; then
    echo "Timeout reached ($TIMEOUT seconds). Moving to next step..."
    return 1
  fi
  return 0
}

# Update kubeconfig with timeout
echo "Updating kubeconfig..."
eksctl utils write-kubeconfig --cluster ${CLUSTER_NAME} --timeout 5m

# Function to force delete resources in a namespace
force_delete_resources() {
    local ns=$1
    echo "Force deleting resources in namespace: $ns"
    
    # Skip if namespace doesn't exist
    if ! kubectl get ns $ns >/dev/null 2>&1; then
        echo "Namespace $ns does not exist, skipping..."
        return 0
    fi
    
    # Delete all resources in the namespace
    for resource in $(kubectl api-resources --verbs=delete -o name); do
        echo "Deleting $resource in $ns..."
        kubectl delete --all $resource -n $ns --timeout=30s --ignore-not-found=true >/dev/null 2>&1 || true
    done
    
    # Remove finalizers from remaining resources
    for resource in $(kubectl api-resources -o name); do
        kubectl get $resource -n $ns -o name | xargs -r -n 1 kubectl patch -n $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    done
    
    # Delete the namespace
    echo "Deleting namespace: $ns"
    kubectl delete namespace $ns --force --grace-period=0 --timeout=30s 2>/dev/null || true
    
    # Wait for namespace deletion with timeout
    local wait_time=0
    while kubectl get namespace $ns >/dev/null 2>&1; do
        echo "Waiting for $ns namespace to be deleted..."
        sleep 5
        wait_time=$((wait_time + 5))
        if [ $wait_time -ge 300 ]; then  # 5 minutes max per namespace
            echo "Timeout waiting for namespace $ns to be deleted. Moving on..."
            break
        fi
    done
}

# Clean up Helm releases with timeout
echo "Cleaning up Helm releases..."
for ns in otel-demo monitoring gremlin; do
    if ! timeout_check; then break; fi
    
    # Skip if namespace doesn't exist
    if ! kubectl get ns $ns >/dev/null 2>&1; then
        echo "Skipping Helm cleanup for non-existent namespace: $ns"
        continue
    fi
    
    echo "Cleaning up Helm releases in $ns namespace..."
    helm uninstall -n $ns $(helm ls -n $ns -q) --no-hooks 2>/dev/null || true
    
    # Clean up orphaned Helm resources
    kubectl delete secrets,configmaps -n $ns -l "owner=helm" --timeout=30s 2>/dev/null || true
    kubectl delete secrets,configmaps -n $ns -l "NAME IN (helm.sh/release)" --timeout=30s 2>/dev/null || true
done

# Clean up namespaces in parallel
echo "Cleaning up namespaces..."
for ns in otel-demo monitoring gremlin; do
    if ! timeout_check; then break; fi
    force_delete_resources $ns &
done
wait

# Clean up cluster-scoped resources
echo "Cleaning up cluster-scoped resources..."

# Delete CRDs
kubectl delete --all crds --timeout=30s 2>/dev/null || true

# Delete PVs and PVCs
echo "Cleaning up persistent volumes..."
kubectl delete --all pv --force --grace-period=0 --timeout=30s 2>/dev/null || true
kubectl delete --all pvc --all-namespaces --force --grace-period=0 --timeout=30s 2>/dev/null || true

# Clean up any remaining namespaces (except kube-system)
for ns in $(kubectl get ns -o jsonpath='{.items[?(@.status.phase=="Terminating")].metadata.name}'); do
    if [[ "$ns" != "kube-system" ]]; then
        echo "Force deleting remaining namespace: $ns"
        kubectl get ns $ns -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
    fi
done

echo "Cluster cleanup complete."
