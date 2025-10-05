#!/bin/bash

# Gremlin Library Functions
# Reusable functions for Gremlin integration

# Get the directory of this script
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions if not already loaded
if [[ -z "$COMMON_FUNCTIONS_LOADED" ]]; then
    source "$LIB_DIR/common.sh"
fi

# Create Gremlin RBAC resources (reusable across scripts)
create_gremlin_rbac() {
    log_info "Creating Gremlin RBAC resources..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would create Gremlin RBAC resources"
        return 0
    fi
    
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: gremlin-service-discovery
  labels:
    app: gremlin
rules:
- apiGroups: [""]
  resources: ["services", "pods", "endpoints", "nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["discovery.k8s.io"]
  resources: ["endpointslices"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gremlin-service-discovery
  labels:
    app: gremlin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: gremlin-service-discovery
subjects:
- kind: ServiceAccount
  name: chao
  namespace: gremlin
EOF
    
    if [[ $? -eq 0 ]]; then
        log_success "Gremlin RBAC resources created"
        return 0
    else
        log_error "Failed to create Gremlin RBAC resources"
        return 1
    fi
}

# Verify Gremlin service account has proper access
verify_gremlin_access() {
    log_info "Verifying Gremlin service account permissions..."
    
    # Check if Gremlin service account exists
    if ! kubectl get serviceaccount -n gremlin chao &>/dev/null; then
        log_warning "Gremlin service account 'chao' not found in namespace 'gremlin'"
        return 1
    fi
    
    # Check if Gremlin has the necessary permissions
    if ! kubectl auth can-i --as=system:serviceaccount:gremlin:chao get services --all-namespaces &>/dev/null; then
        log_warning "Gremlin service account doesn't have permission to list services"
        return 1
    fi
    
    log_success "Gremlin service account has proper permissions"
    return 0
}

# Export functions for use in other scripts
export -f create_gremlin_rbac
export -f verify_gremlin_access
