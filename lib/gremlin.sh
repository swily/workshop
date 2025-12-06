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
    
    kubectl apply -f - >/dev/null 2>&1 <<EOF
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

# Unified Gremlin installation function
install_gremlin() {
    local cluster_name="$1"
    
    log_info "Installing Gremlin agent..."
    
    # Check if already installed
    if helm list -n gremlin -q 2>/dev/null | grep -q "^gremlin$"; then
        log_info "Gremlin already installed, skipping..."
        return 0
    fi
    
    # Ensure credentials are available
    if [[ -z "$GREMLIN_TEAM_ID" ]]; then
        log_error "GREMLIN_TEAM_ID not set"
        return 1
    fi
    
    if [[ -z "$GREMLIN_TEAM_SECRET" ]]; then
        log_error "GREMLIN_TEAM_SECRET not set"
        return 1
    fi
    
    # Install via script
    "$REPO_ROOT/scripts/gremlin_install.sh" \
        --cluster-name "$cluster_name" \
        --team-id "$GREMLIN_TEAM_ID" \
        --team-secret "$GREMLIN_TEAM_SECRET" \
        --api-key "$GREMLIN_API_KEY"
}

# Unified Gremlin annotations function
apply_gremlin_annotations() {
    local namespace="${1:-otel-demo}"
    
    log_info "Applying Gremlin service annotations to namespace: $namespace..."
    
    # Check if namespace exists
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        log_warning "Namespace $namespace does not exist, skipping annotations"
        return 0
    fi
    
    # Check if services exist in namespace
    local service_count
    service_count=$(kubectl get services -n "$namespace" --no-headers 2>/dev/null | wc -l)
    
    if [[ $service_count -eq 0 ]]; then
        log_warning "No services found in namespace $namespace, skipping annotations"
        return 0
    fi
    
    # Apply annotations
    if [[ -f "$REPO_ROOT/config/gremlin/gremlin_annotations.sh" ]]; then
        "$REPO_ROOT/config/gremlin/gremlin_annotations.sh" "$namespace"
    else
        log_error "Gremlin annotations script not found: $REPO_ROOT/config/gremlin/gremlin_annotations.sh"
        return 1
    fi
}

# Unified EC2 permissions fix (should be called during cluster setup)
fix_gremlin_ec2_permissions() {
    local cluster_name="$1"
    local region="${2:-$AWS_REGION}"
    
    log_info "Fixing Gremlin EC2 permissions for service discovery..."
    
    # Get node role name
    local node_role_name
    node_role_name=$(aws eks describe-nodegroup \
        --cluster-name "$cluster_name" \
        --nodegroup-name "$(aws eks list-nodegroups --cluster-name "$cluster_name" --region "$region" --query 'nodegroups[0]' --output text)" \
        --region "$region" \
        --query 'nodegroup.nodeRole' \
        --output text 2>/dev/null | awk -F'/' '{print $NF}')
    
    if [[ -z "$node_role_name" ]]; then
        log_warning "Could not determine node role name"
        return 1
    fi
    
    # Check if policy already attached
    if aws iam list-attached-role-policies --role-name "$node_role_name" 2>/dev/null | grep -q "AmazonEC2ReadOnlyAccess"; then
        log_info "EC2ReadOnlyAccess policy already attached to role: $node_role_name"
        return 0
    fi
    
    # Attach policy
    log_info "Attaching EC2ReadOnlyAccess policy to node role: $node_role_name"
    if aws iam attach-role-policy \
        --role-name "$node_role_name" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess" 2>/dev/null; then
        log_success "EC2 permissions configured successfully"
        return 0
    else
        log_warning "Failed to attach policy (may already be attached)"
        return 0
    fi
}

# Complete Gremlin setup (installation + annotations + permissions)
setup_gremlin_complete() {
    local cluster_name="$1"
    
    log_section "Setting up Gremlin"
    
    # Fix EC2 permissions first (required for service discovery)
    fix_gremlin_ec2_permissions "$cluster_name" || {
        log_warning "EC2 permissions fix failed, continuing anyway..."
    }
    
    # Install Gremlin agent
    install_gremlin "$cluster_name" || {
        log_error "Gremlin installation failed"
        return 1
    }
    
    # Apply service annotations
    apply_gremlin_annotations "otel-demo" || {
        log_warning "Failed to apply annotations, continuing anyway..."
    }
    
    log_success "Gremlin setup completed"
}

# Export functions for use in other scripts
export -f create_gremlin_rbac
export -f verify_gremlin_access
export -f install_gremlin
export -f apply_gremlin_annotations
export -f fix_gremlin_ec2_permissions
export -f setup_gremlin_complete
