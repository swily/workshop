#!/bin/bash
#
# Deployment Library - Unified deployment functions
# Provides shared functions for deployment operations across all workshop actions
#

# Get the directory of this script
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions if not already loaded
if [[ -z "$COMMON_FUNCTIONS_LOADED" ]]; then
    source "$LIB_DIR/common.sh"
fi

# Deploy failure flags if enabled
deploy_failure_flags_if_enabled() {
    if [[ "$ENABLE_FAILURE_FLAGS" != "true" ]]; then
        log_info "Failure flags not enabled, skipping..."
        return 0
    fi
    
    log_info "Deploying Failure Flags sidecar..."
    
    if [[ ! -f "$REPO_ROOT/scripts/operations/deploy_failure_flags.sh" ]]; then
        log_error "Failure flags script not found: $REPO_ROOT/scripts/operations/deploy_failure_flags.sh"
        return 1
    fi
    
    "$REPO_ROOT/scripts/operations/deploy_failure_flags.sh" \
        --cluster-name "$CLUSTER_NAME"
}

# Apply cross-namespace services
apply_cross_namespace_services() {
    log_info "Applying cross-namespace services for consolidated ingress..."
    
    local services_file="$REPO_ROOT/otel-demo-cross-namespace-services.yaml"
    
    if [[ ! -f "$services_file" ]]; then
        log_warning "Cross-namespace services file not found: $services_file"
        return 1
    fi
    
    kubectl apply -f "$services_file" || {
        log_error "Failed to apply cross-namespace services"
        return 1
    }
    
    log_success "Cross-namespace services applied"
}

# Finalize deployment (state export + endpoint display)
finalize_deployment() {
    local cluster_name="$1"
    local region="$2"
    
    log_info "Finalizing deployment..."
    
    # Export cluster state to correct location
    if command -v export_cluster_state &>/dev/null; then
        # Find workshop root directory
        local workshop_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        local state_file="$workshop_root/build_scripts/demo/cluster-state.json"
        export_cluster_state "$cluster_name" "$region" "$state_file"
    else
        log_warning "export_cluster_state function not found, skipping..."
    fi
    
    # Display endpoints
    if command -v display_workshop_endpoints &>/dev/null; then
        display_workshop_endpoints
    else
        log_warning "display_workshop_endpoints function not found, skipping..."
    fi
}

# Unified credential resolution
ensure_gremlin_credentials() {
    # If credentials already set, return
    if [[ -n "$GREMLIN_TEAM_ID" && -n "$GREMLIN_TEAM_SECRET" ]]; then
        log_info "Gremlin credentials already available"
        return 0
    fi
    
    # Try to resolve from owner
    if [[ -n "$OWNER" ]]; then
        log_info "Resolving Gremlin credentials from owner: $OWNER"
        
        if command -v resolve_gremlin_credentials_from_owner &>/dev/null; then
            resolve_gremlin_credentials_from_owner "$OWNER" || {
                log_error "Failed to resolve credentials from owner"
                return 1
            }
        else
            log_warning "resolve_gremlin_credentials_from_owner function not found"
        fi
        
        if command -v fetch_gremlin_credentials &>/dev/null; then
            fetch_gremlin_credentials || {
                log_error "Failed to fetch credentials from Secrets Manager"
                return 1
            }
        else
            log_warning "fetch_gremlin_credentials function not found"
        fi
        
        return 0
    fi
    
    # Try to derive owner from subdomain
    if [[ -n "$SUBDOMAIN" ]]; then
        log_info "Attempting to derive owner from subdomain: $SUBDOMAIN"
        # Convention: subdomain format is "firstname" or "firstnamelastname"
        # Try to resolve as owner
        OWNER="$SUBDOMAIN"
        export OWNER
        
        if command -v resolve_gremlin_credentials_from_owner &>/dev/null; then
            if resolve_gremlin_credentials_from_owner "$OWNER"; then
                if command -v fetch_gremlin_credentials &>/dev/null; then
                    fetch_gremlin_credentials && return 0
                fi
            fi
        fi
    fi
    
    log_error "Could not resolve Gremlin credentials"
    log_info "Please provide credentials via:"
    log_info "  1. --owner flag (for Secrets Manager lookup)"
    log_info "  2. Environment variables: GREMLIN_TEAM_ID, GREMLIN_TEAM_SECRET, GREMLIN_API_KEY"
    return 1
}

# Clean up legacy ingresses (idempotent)
cleanup_legacy_ingresses() {
    log_info "Cleaning up legacy per-app ingresses..."
    
    # Remove legacy otel-demo ingresses
    kubectl delete ingress -n otel-demo frontend-proxy jaeger-ingress 2>/dev/null || true
    
    # Remove legacy monitoring ingresses
    kubectl delete ingress -n monitoring grafana-ingress prometheus-ingress 2>/dev/null || true
    
    log_success "Legacy ingresses cleaned up"
}

# Export functions for use in other scripts
export -f deploy_failure_flags_if_enabled
export -f apply_cross_namespace_services
export -f finalize_deployment
export -f ensure_gremlin_credentials
export -f cleanup_legacy_ingresses
