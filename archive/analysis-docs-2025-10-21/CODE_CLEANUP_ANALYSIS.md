# Workshop Script Code Cleanup & Unification Analysis

## Executive Summary

The workshop.sh script has **significant code duplication** and **repeated installation patterns** across multiple functions. This analysis identifies all duplicate code, repeated patterns, and proposes a unified architecture to simplify and streamline the codebase.

---

## Critical Issues Found

### 🔴 Issue 1: Gremlin Installation Duplicated 3 Times

**Locations:**
1. `create_and_deploy()` - Line 235 (calls `setup_gremlin_only()`)
2. `deploy_to_existing()` - Lines 303-311 (inline installation)
3. `setup_gremlin_only()` - Lines 344-352 (inline installation)

**Problem:**
```bash
# deploy_to_existing() - Lines 303-311
GREMLIN_TEAM_ID="$GREMLIN_TEAM_ID" \
GREMLIN_TEAM_SECRET="$GREMLIN_TEAM_SECRET" \
GREMLIN_API_KEY="$GREMLIN_API_KEY" \
"$SCRIPT_DIR/scripts/gremlin_install.sh" \
    --cluster-name "$CLUSTER_NAME" \
    --team-id "$GREMLIN_TEAM_ID" \
    --team-secret "$GREMLIN_TEAM_SECRET" \
    --api-key "$GREMLIN_API_KEY"

# setup_gremlin_only() - Lines 344-352
GREMLIN_TEAM_ID="$GREMLIN_TEAM_ID" \
GREMLIN_TEAM_SECRET="$GREMLIN_TEAM_SECRET" \
GREMLIN_API_KEY="$GREMLIN_API_KEY" \
"$SCRIPT_DIR/scripts/gremlin_install.sh" \
    --cluster-name "$CLUSTER_NAME" \
    --team-id "$GREMLIN_TEAM_ID" \
    --team-secret "$GREMLIN_TEAM_SECRET" \
    --api-key "$GREMLIN_API_KEY"
```

**Impact:**
- 18 lines of duplicate code
- Inconsistent credential handling
- Maintenance nightmare (change in 3 places)

---

### 🔴 Issue 2: Gremlin Annotations Duplicated 3 Times

**Locations:**
1. `deploy_to_existing()` - Lines 313-315
2. `setup_gremlin_only()` - Lines 354-356
3. `setup_gremlin_monitoring()` in `lib/monitoring.sh` - Lines 558-561

**Problem:**
```bash
# Repeated 3 times:
log_info "Applying Gremlin service annotations..."
"$SCRIPT_DIR/config/gremlin/gremlin_annotations.sh" otel-demo
```

**Impact:**
- Annotations applied multiple times
- Inconsistent namespace handling
- No idempotency check

---

### 🔴 Issue 3: EC2 Permissions Fix in Wrong Place

**Location:** `lib/monitoring.sh` - Lines 546-554

**Problem:**
```bash
setup_gremlin_monitoring() {
    # Fix Gremlin EC2 permissions for service discovery
    log_info "Fixing Gremlin EC2 permissions for service discovery..."
    local node_role_name
    node_role_name=$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" ...)
    
    if [ -n "$node_role_name" ]; then
        log_info "Attaching EC2ReadOnlyAccess policy to node role: $node_role_name"
        aws iam attach-role-policy --role-name "$node_role_name" --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess" 2>/dev/null || log_warning "Policy may already be attached"
    fi
}
```

**Why This is Wrong:**
- EC2 permissions are **infrastructure-level**, not monitoring-level
- Should be done during **cluster creation**, not monitoring setup
- Gets called multiple times unnecessarily
- Belongs in `configure_cluster_base()` or Terraform

---

### 🔴 Issue 4: Credential Handling Inconsistency

**Problem:** Three different credential patterns:

**Pattern 1: Terraform-based (build_new)**
```bash
# provision_infrastructure() - Lines 175-183
resolve_gremlin_credentials_from_owner "$OWNER"
fetch_gremlin_credentials  # Sets GREMLIN_TEAM_ID, etc.
```

**Pattern 2: Manual env vars (deploy_existing)**
```bash
# deploy_to_existing() - Lines 303-311
GREMLIN_TEAM_ID="$GREMLIN_TEAM_ID" \
GREMLIN_TEAM_SECRET="$GREMLIN_TEAM_SECRET" \
GREMLIN_API_KEY="$GREMLIN_API_KEY" \
```

**Pattern 3: No credential resolution (gremlin_only)**
```bash
# setup_gremlin_only() - Lines 344-352
# Assumes credentials are already set
# No fallback to Secrets Manager
```

**Impact:**
- User must manually export credentials for some actions
- Inconsistent behavior across actions
- No unified credential strategy

---

### 🔴 Issue 5: Failure Flags Deployment Duplicated

**Locations:**
1. `create_and_deploy()` - Lines 237-242
2. `deploy_to_existing()` - Lines 317-322

**Problem:**
```bash
# Repeated twice:
if [[ "$ENABLE_FAILURE_FLAGS" == "true" ]]; then
    log_info "Deploying Failure Flags sidecar..."
    "$SCRIPT_DIR/scripts/operations/deploy_failure_flags.sh" \
        --cluster-name "$CLUSTER_NAME"
fi
```

**Impact:**
- 6 lines of duplicate code
- Inconsistent flag checking

---

### 🔴 Issue 6: Monitoring Setup Duplicated

**Locations:**
1. `create_and_deploy()` - Line 245
2. `deploy_to_existing()` - Line 325

**Problem:**
```bash
# create_and_deploy()
CONSOLIDATED_INGRESS=true setup_comprehensive_monitoring "$MONITORING_PLATFORM"

# deploy_to_existing()
MONITORING_PLATFORM="$MONITORING_PLATFORM" setup_comprehensive_monitoring "$MONITORING_PLATFORM"
```

**Impact:**
- Different environment variable patterns
- Redundant `MONITORING_PLATFORM` assignment

---

### 🔴 Issue 7: Cross-Namespace Services Only in build_new

**Location:** `create_and_deploy()` - Lines 247-256

**Problem:**
```bash
# Only in create_and_deploy()
log_info "Applying cross-namespace services for consolidated ingress..."
if [[ -f "$SCRIPT_DIR/otel-demo-cross-namespace-services.yaml" ]]; then
    kubectl apply -f "$SCRIPT_DIR/otel-demo-cross-namespace-services.yaml"
fi
```

**Missing from:**
- `deploy_to_existing()` - Should also apply these services
- `setup_gremlin_only()` - May need these for health checks

**Impact:**
- Inconsistent cluster state
- Health checks may fail on existing clusters

---

### 🔴 Issue 8: Cluster State Export Duplicated

**Locations:**
1. `create_and_deploy()` - Line 266
2. `deploy_to_existing()` - Line 331

**Problem:**
```bash
# Repeated twice:
export_cluster_state "$CLUSTER_NAME" "$AWS_REGION"
```

---

### 🔴 Issue 9: Endpoint Display Duplicated

**Locations:**
1. `create_and_deploy()` - Line 269
2. `deploy_to_existing()` - Line 334

**Problem:**
```bash
# Repeated twice:
display_workshop_endpoints
```

---

### 🔴 Issue 10: Idempotency Checks Missing

**Location:** `deploy_to_existing()` - Lines 279-297

**Problem:**
```bash
# Check for existing OpenTelemetry Demo
if helm list -n otel-demo -q | grep -q "opentelemetry-demo"; then
    log_warning "Existing OpenTelemetry Demo found. Upgrading in place..."
    helm upgrade opentelemetry-demo open-telemetry/opentelemetry-demo -n otel-demo --reuse-values || {
        log_warning "Upgrade failed, uninstalling and reinstalling..."
        helm uninstall opentelemetry-demo -n otel-demo --ignore-not-found
        sleep 10
    }
fi
```

**Issues:**
- Upgrade logic is fragile
- Uninstall on failure causes downtime
- Should skip if already installed
- No version checking
- Hardcoded sleep timers

---

## Proposed Unified Architecture

### New Shared Functions (lib/gremlin.sh)

```bash
#!/bin/bash
# lib/gremlin.sh - Unified Gremlin installation and configuration

# Unified Gremlin installation function
install_gremlin() {
    local cluster_name="$1"
    
    log_info "Installing Gremlin agent..."
    
    # Check if already installed
    if helm list -n gremlin -q | grep -q "^gremlin$"; then
        log_info "Gremlin already installed, skipping..."
        return 0
    fi
    
    # Ensure credentials are available
    if [[ -z "$GREMLIN_TEAM_ID" ]]; then
        log_error "GREMLIN_TEAM_ID not set"
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
    
    log_info "Applying Gremlin service annotations..."
    
    # Check if namespace exists
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        log_warning "Namespace $namespace does not exist, skipping annotations"
        return 0
    fi
    
    # Apply annotations
    "$REPO_ROOT/config/gremlin/gremlin_annotations.sh" "$namespace"
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
        --output text | awk -F'/' '{print $NF}')
    
    if [[ -z "$node_role_name" ]]; then
        log_warning "Could not determine node role name"
        return 1
    fi
    
    # Check if policy already attached
    if aws iam list-attached-role-policies --role-name "$node_role_name" | grep -q "AmazonEC2ReadOnlyAccess"; then
        log_info "EC2ReadOnlyAccess policy already attached"
        return 0
    fi
    
    # Attach policy
    log_info "Attaching EC2ReadOnlyAccess policy to node role: $node_role_name"
    aws iam attach-role-policy \
        --role-name "$node_role_name" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess" 2>/dev/null || {
        log_warning "Failed to attach policy (may already be attached)"
        return 0
    }
    
    log_success "EC2 permissions configured successfully"
}

# Complete Gremlin setup (installation + annotations + permissions)
setup_gremlin_complete() {
    local cluster_name="$1"
    
    log_section "Setting up Gremlin"
    
    # Fix EC2 permissions first (required for service discovery)
    fix_gremlin_ec2_permissions "$cluster_name"
    
    # Install Gremlin agent
    install_gremlin "$cluster_name"
    
    # Apply service annotations
    apply_gremlin_annotations "otel-demo"
    
    log_success "Gremlin setup completed"
}
```

---

### New Shared Functions (lib/deployment.sh)

```bash
#!/bin/bash
# lib/deployment.sh - Unified deployment functions

# Deploy failure flags if enabled
deploy_failure_flags_if_enabled() {
    if [[ "$ENABLE_FAILURE_FLAGS" != "true" ]]; then
        return 0
    fi
    
    log_info "Deploying Failure Flags sidecar..."
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
    
    # Export cluster state
    export_cluster_state "$cluster_name" "$region"
    
    # Display endpoints
    display_workshop_endpoints
}

# Unified credential resolution
ensure_gremlin_credentials() {
    # If credentials already set, return
    if [[ -n "$GREMLIN_TEAM_ID" ]]; then
        log_info "Gremlin credentials already available"
        return 0
    fi
    
    # Try to resolve from owner
    if [[ -n "$OWNER" ]]; then
        log_info "Resolving Gremlin credentials from owner: $OWNER"
        resolve_gremlin_credentials_from_owner "$OWNER" || {
            log_error "Failed to resolve credentials from owner"
            return 1
        }
        fetch_gremlin_credentials || {
            log_error "Failed to fetch credentials from Secrets Manager"
            return 1
        }
        return 0
    fi
    
    # Try to derive owner from subdomain
    if [[ -n "$SUBDOMAIN" ]]; then
        log_info "Attempting to derive owner from subdomain: $SUBDOMAIN"
        # Convention: subdomain format is "firstname" or "firstnamelastname"
        # Try to resolve as owner
        OWNER="$SUBDOMAIN"
        resolve_gremlin_credentials_from_owner "$OWNER" && {
            fetch_gremlin_credentials
            return 0
        }
    fi
    
    log_error "Could not resolve Gremlin credentials"
    log_info "Please provide credentials via:"
    log_info "  1. --owner flag (for Secrets Manager lookup)"
    log_info "  2. Environment variables: GREMLIN_TEAM_ID, GREMLIN_TEAM_SECRET, GREMLIN_API_KEY"
    return 1
}
```

---

### Refactored workshop.sh

```bash
#!/bin/bash
# workshop.sh - Refactored with unified functions

set -Eeu

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/cluster.sh"
source "$SCRIPT_DIR/lib/monitoring.sh"
source "$SCRIPT_DIR/lib/terraform.sh"
source "$SCRIPT_DIR/lib/gremlin.sh"        # NEW
source "$SCRIPT_DIR/lib/deployment.sh"     # NEW

# ... parse_arguments() unchanged ...

# ... provision_infrastructure() unchanged ...

# REFACTORED: create_and_deploy()
create_and_deploy() {
    log_section "Creating New Cluster and Deploying Everything"
    
    # Provision infrastructure with Terraform
    provision_infrastructure
    
    # Configure cluster base components (includes EC2 permissions now)
    configure_cluster_base "$CLUSTER_NAME" "$INSTALL_ISTIO" "$MONITORING_PLATFORM"
    
    # Deploy OpenTelemetry demo
    CONSOLIDATED_INGRESS=true "$SCRIPT_DIR/scripts/operations/deploy_otel.sh" \
        --cluster-name "$CLUSTER_NAME"
    
    # Setup Gremlin (unified function)
    setup_gremlin_complete "$CLUSTER_NAME"
    
    # Deploy failure flags if enabled (unified function)
    deploy_failure_flags_if_enabled
    
    # Setup monitoring
    CONSOLIDATED_INGRESS=true setup_comprehensive_monitoring "$MONITORING_PLATFORM"
    
    # Apply cross-namespace services (unified function)
    apply_cross_namespace_services
    
    # Remove legacy ingresses (idempotent cleanup)
    kubectl delete ingress -n otel-demo frontend-proxy jaeger-ingress 2>/dev/null || true
    kubectl delete ingress -n monitoring grafana-ingress prometheus-ingress 2>/dev/null || true
    
    # Finalize deployment (unified function)
    finalize_deployment "$CLUSTER_NAME" "$AWS_REGION"
}

# REFACTORED: deploy_to_existing()
deploy_to_existing() {
    log_section "Deploying to Existing Cluster"
    
    # Validate cluster exists
    validate_cluster_exists "$CLUSTER_NAME" "$AWS_REGION"
    update_kubeconfig "$CLUSTER_NAME" "$AWS_REGION"
    
    # Ensure credentials are available (unified function)
    ensure_gremlin_credentials || {
        log_error "Cannot proceed without Gremlin credentials"
        exit 1
    }
    
    # Deploy OpenTelemetry demo (idempotent)
    "$SCRIPT_DIR/scripts/operations/deploy_otel.sh" \
        --cluster-name "$CLUSTER_NAME"
    
    # Setup Gremlin (unified function)
    setup_gremlin_complete "$CLUSTER_NAME"
    
    # Deploy failure flags if enabled (unified function)
    deploy_failure_flags_if_enabled
    
    # Setup monitoring
    setup_comprehensive_monitoring "$MONITORING_PLATFORM"
    
    # Apply cross-namespace services (unified function)
    apply_cross_namespace_services
    
    # Finalize deployment (unified function)
    finalize_deployment "$CLUSTER_NAME" "$AWS_REGION"
}

# REFACTORED: setup_gremlin_only()
setup_gremlin_only() {
    log_section "Setting up Gremlin Only"
    
    # Validate cluster exists
    validate_cluster_exists "$CLUSTER_NAME" "$AWS_REGION"
    update_kubeconfig "$CLUSTER_NAME" "$AWS_REGION"
    
    # Ensure credentials are available (unified function)
    ensure_gremlin_credentials || {
        log_error "Cannot proceed without Gremlin credentials"
        exit 1
    }
    
    # Setup Gremlin (unified function)
    setup_gremlin_complete "$CLUSTER_NAME"
    
    # Setup Gremlin monitoring (health checks)
    setup_gremlin_monitoring
    
    log_success "Gremlin setup completed!"
}

# ... cleanup_cluster_wrapper() unchanged ...
# ... main() unchanged ...
```

---

### Refactored lib/monitoring.sh

```bash
# REFACTORED: setup_gremlin_monitoring()
setup_gremlin_monitoring() {
    log_info "Setting up Gremlin-specific monitoring..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would setup Gremlin monitoring"
        return 0
    fi
    
    # NOTE: EC2 permissions are now handled in configure_cluster_base()
    # NOTE: Gremlin installation is now handled by setup_gremlin_complete()
    # NOTE: Annotations are now handled by setup_gremlin_complete()
    
    # Create health checks using healthchecks.sh script
    if [ -f "$REPO_ROOT/build_scripts/demo/healthchecks.sh" ]; then
        log_info "Creating Gremlin health checks..."
        export SUBDOMAIN="${SUBDOMAIN}"
        export CLUSTER_NAME="${CLUSTER_NAME}"
        "$REPO_ROOT/build_scripts/demo/healthchecks.sh" \
            --platform all \
            --subdomain "$SUBDOMAIN" \
            --cluster-name "$CLUSTER_NAME"
    else
        log_warning "Health checks script not found: $REPO_ROOT/build_scripts/demo/healthchecks.sh"
    fi
    
    log_success "Gremlin monitoring setup completed"
}
```

---

### Updated lib/cluster.sh

```bash
# UPDATED: configure_cluster_base()
configure_cluster_base() {
    local cluster_name="$1"
    local install_istio="${2:-false}"
    local monitoring_type="${3:-prometheus}"
    
    log_section "Configuring Cluster Base Components"
    
    # Install AWS Load Balancer Controller
    install_aws_lb_controller "$cluster_name"
    
    # Fix Gremlin EC2 permissions (MOVED HERE from monitoring.sh)
    if command -v fix_gremlin_ec2_permissions &>/dev/null; then
        fix_gremlin_ec2_permissions "$cluster_name"
    fi
    
    # Install Istio if requested
    if [[ "$install_istio" == "true" ]]; then
        install_istio "$cluster_name"
    fi
    
    log_success "Cluster base configuration completed"
}
```

---

## Code Reduction Summary

### Before Refactoring

| Component | Lines | Occurrences | Total Lines |
|-----------|-------|-------------|-------------|
| Gremlin installation | 9 | 3 | 27 |
| Gremlin annotations | 3 | 3 | 9 |
| EC2 permissions fix | 9 | 1 (wrong place) | 9 |
| Failure flags deployment | 6 | 2 | 12 |
| Cross-namespace services | 10 | 1 (missing from 2) | 10 |
| Cluster state export | 1 | 2 | 2 |
| Endpoint display | 1 | 2 | 2 |
| Credential resolution | Varies | 3 (inconsistent) | ~30 |
| **Total Duplicate Code** | | | **~101 lines** |

### After Refactoring

| Component | Lines | Occurrences | Total Lines |
|-----------|-------|-------------|-------------|
| `setup_gremlin_complete()` | 15 | 1 (shared) | 15 |
| `deploy_failure_flags_if_enabled()` | 8 | 1 (shared) | 8 |
| `apply_cross_namespace_services()` | 15 | 1 (shared) | 15 |
| `finalize_deployment()` | 8 | 1 (shared) | 8 |
| `ensure_gremlin_credentials()` | 35 | 1 (shared) | 35 |
| **Total Shared Code** | | | **81 lines** |

**Net Reduction:** ~20 lines + improved maintainability

---

## Benefits of Refactoring

### ✅ 1. Single Source of Truth
- Gremlin installation logic in one place
- Credential resolution unified
- EC2 permissions in correct location

### ✅ 2. Consistency
- All actions use same credential strategy
- All actions apply same configurations
- Predictable behavior across workflows

### ✅ 3. Maintainability
- Change once, affects all workflows
- Easier to add new features
- Clearer code organization

### ✅ 4. Idempotency
- Check before install
- Skip if already exists
- No unnecessary reinstalls

### ✅ 5. Error Handling
- Unified error messages
- Consistent validation
- Better user feedback

---

## Implementation Plan

### Phase 1: Create New Library Files (1 hour)

1. Create `lib/gremlin.sh`
   - Move Gremlin functions
   - Add idempotency checks
   - Unify credential handling

2. Create `lib/deployment.sh`
   - Move shared deployment functions
   - Add validation logic

### Phase 2: Refactor workshop.sh (2 hours)

1. Source new libraries
2. Replace duplicate code with function calls
3. Update all three actions:
   - `create_and_deploy()`
   - `deploy_to_existing()`
   - `setup_gremlin_only()`

### Phase 3: Update lib/monitoring.sh (1 hour)

1. Remove EC2 permissions fix
2. Remove Gremlin installation logic
3. Simplify `setup_gremlin_monitoring()`

### Phase 4: Update lib/cluster.sh (30 minutes)

1. Add EC2 permissions fix to `configure_cluster_base()`
2. Ensure it runs during cluster setup

### Phase 5: Testing (2 hours)

1. Test `--action build_new`
2. Test `--action deploy_existing`
3. Test `--action gremlin_only`
4. Verify idempotency
5. Verify credential resolution

### Phase 6: Documentation (1 hour)

1. Update WORKFLOW_ANALYSIS.md
2. Update README.md
3. Add comments to new functions

**Total Time:** ~7.5 hours

---

## Migration Strategy

### Option A: Big Bang (Recommended)

- Implement all changes at once
- Test thoroughly before merging
- Single PR with all refactoring

**Pros:**
- Clean break from old code
- No intermediate states
- Easier to review holistically

**Cons:**
- Larger PR
- More testing required

### Option B: Incremental

- Phase 1: Create new libraries
- Phase 2: Migrate one action at a time
- Phase 3: Remove old code

**Pros:**
- Smaller PRs
- Gradual migration
- Can test each phase

**Cons:**
- Temporary code duplication
- Multiple PRs to track
- Longer timeline

---

## Testing Checklist

### Test Case 1: New Cluster Deployment

```bash
./workshop.sh \
    --subdomain test1 \
    --owner test.user \
    --enable-eks \
    --monitoring prometheus \
    --action build_new
```

**Verify:**
- ✅ Gremlin installed once
- ✅ EC2 permissions set during cluster setup
- ✅ Annotations applied once
- ✅ Health checks created
- ✅ No duplicate installations

### Test Case 2: Existing Cluster Deployment

```bash
./workshop.sh \
    --cluster-name existing-cluster \
    --owner test.user \
    --action deploy_existing
```

**Verify:**
- ✅ Credentials auto-resolved from owner
- ✅ Gremlin installed if not present
- ✅ Gremlin skipped if already installed
- ✅ Cross-namespace services applied
- ✅ Health checks created

### Test Case 3: Gremlin Only

```bash
./workshop.sh \
    --cluster-name existing-cluster \
    --owner test.user \
    --action gremlin_only
```

**Verify:**
- ✅ Credentials auto-resolved
- ✅ Gremlin installed if not present
- ✅ EC2 permissions checked/fixed
- ✅ Annotations applied
- ✅ Health checks created

### Test Case 4: Idempotency

```bash
# Run twice
./workshop.sh --cluster-name test --owner user --action deploy_existing
./workshop.sh --cluster-name test --owner user --action deploy_existing
```

**Verify:**
- ✅ Second run skips existing installations
- ✅ No errors or conflicts
- ✅ Same end state

---

## Risk Assessment

### Low Risk ✅
- Creating new library files
- Adding new functions
- Improving error handling

### Medium Risk ⚠️
- Changing credential resolution logic
- Moving EC2 permissions fix
- Refactoring existing functions

### High Risk 🔴
- Removing duplicate code without testing
- Changing function signatures
- Breaking backwards compatibility

**Mitigation:**
- Comprehensive testing before merge
- Keep old code commented out temporarily
- Test all three actions thoroughly
- Document breaking changes

---

## Backwards Compatibility

### Breaking Changes: None

All refactoring maintains existing behavior:
- Same command-line arguments
- Same environment variables
- Same output format
- Same end state

### Deprecated Patterns

None - all existing patterns continue to work

---

## Success Criteria

✅ **Code Quality:**
- No duplicate Gremlin installation code
- Single credential resolution strategy
- EC2 permissions in correct location

✅ **Functionality:**
- All three actions work correctly
- Idempotency verified
- Credentials auto-resolve

✅ **Testing:**
- All test cases pass
- No regressions
- Improved error messages

✅ **Documentation:**
- Updated workflow analysis
- Clear function documentation
- Migration guide complete

---

## Recommendation

**Proceed with refactoring using Option A (Big Bang approach).**

**Rationale:**
1. Code duplication is significant (~101 lines)
2. Current state is confusing and error-prone
3. Unified architecture is clearer and more maintainable
4. Testing effort is similar for both approaches
5. Single PR is easier to review

**Next Steps:**
1. Create feature branch: `refactor/unify-gremlin-installation`
2. Implement Phase 1-4 (new libraries + refactoring)
3. Test all three actions thoroughly
4. Update documentation
5. Submit PR for review

**Estimated Effort:** 7.5 hours (1 day)

---

**Last Updated:** 2025-10-21  
**Author:** Workshop Automation Team  
**Status:** Analysis Complete - Ready for Implementation
