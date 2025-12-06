# Workshop Script Flow & Modular Component Analysis

## Overview

This document analyzes the workshop.sh orchestration flow, modular components, credential handling, and identifies areas for improvement.

---

## Main Entry Point: `./workshop.sh`

### What Happens When You Run `./workshop.sh`

```bash
./workshop.sh [OPTIONS]
```

**Execution Flow:**

1. **Parse Arguments** → `parse_arguments()`
2. **Show Banner** → `print_banner()`
3. **Interactive Mode** (if no args) → `run_interactive_mode()`
4. **Validate Prerequisites** → `validate_prerequisites()`, `check_aws_config()`
5. **Execute Action** → Based on `--action` flag
6. **Success Message** → Display completion

---

## Available Actions

### 1. `--action build_new` (Create New Infrastructure)

**Full Command:**
```bash
./workshop.sh \
    --subdomain alexs \
    --owner alex.smith \
    --enable-eks \
    --monitoring prometheus \
    --action build_new
```

**Execution Flow:**
```
create_and_deploy()
├── provision_infrastructure()              # Terraform creates EKS, ALB, DNS
│   ├── resolve_gremlin_credentials_from_owner()  # Auto-fetch from Secrets Manager
│   ├── terraform_create_workspace()
│   ├── terraform_init()
│   ├── terraform_plan()
│   ├── terraform_apply()
│   ├── export_terraform_outputs()          # Export CLUSTER_NAME, SUBDOMAIN, etc.
│   ├── fetch_gremlin_credentials()         # Fetch actual credential values
│   └── update_kubeconfig()
├── configure_cluster_base()                # Install AWS LB Controller, Istio (optional)
├── deploy_otel.sh                          # Deploy OpenTelemetry Demo
├── setup_gremlin_only()                    # Install Gremlin agent
├── deploy_failure_flags.sh (optional)      # Deploy FF sidecar
├── setup_comprehensive_monitoring()        # Setup monitoring platform
├── apply cross-namespace services          # Route monitoring through ALB
└── display_workshop_endpoints()            # Show URLs
```

**Credentials Flow:**
- ✅ Fetched from Secrets Manager via owner name
- ✅ Exported as environment variables
- ✅ Available to all downstream scripts

---

### 2. `--action deploy_existing` (Deploy to Existing Cluster)

**Full Command:**
```bash
./workshop.sh \
    --cluster-name existing-cluster \
    --owner your.name \
    --action deploy_existing
```

**Execution Flow:**
```
deploy_to_existing()
├── validate_cluster_exists()
├── update_kubeconfig()
├── ensure_gremlin_credentials()            # ✅ Auto-resolves from owner
├── deploy_otel.sh                          # ✅ Idempotent
├── setup_gremlin_complete()                # ✅ Unified function
│   ├── fix_gremlin_ec2_permissions()
│   ├── install_gremlin()                   # ✅ Idempotent check
│   └── apply_gremlin_annotations()
├── deploy_failure_flags_if_enabled()       # ✅ Unified function
├── setup_comprehensive_monitoring()
├── apply_cross_namespace_services()        # ✅ Now included
├── cleanup_legacy_ingresses()              # ✅ Idempotent cleanup
└── finalize_deployment()                   # ✅ Unified function
```

**✅ CREDENTIALS FIXED:**
- Auto-resolves credentials from owner via Secrets Manager
- Falls back to subdomain-based owner lookup
- Helpful error messages if credentials not found

---

### 3. `--action gremlin_only` (Install Gremlin Only)

**Full Command:**
```bash
./workshop.sh \
    --cluster-name my-cluster \
    --owner your.name \
    --action gremlin_only
```

**Execution Flow:**
```
setup_gremlin_only()
├── validate_cluster_exists()
├── update_kubeconfig()
├── ensure_gremlin_credentials()            # ✅ Auto-resolves from owner
├── setup_gremlin_complete()                # ✅ Unified function
│   ├── fix_gremlin_ec2_permissions()
│   ├── install_gremlin()                   # ✅ Idempotent check
│   └── apply_gremlin_annotations()
└── setup_gremlin_monitoring()
    └── healthchecks.sh                     # ✅ Uses --subdomain
```

**✅ CREDENTIALS FIXED:**
- Auto-resolves credentials from owner via Secrets Manager
- Falls back to subdomain-based owner lookup
- Helpful error messages if credentials not found

---

### 4. `--action cleanup` (Destroy Infrastructure)

**Full Command:**
```bash
./workshop.sh \
    --subdomain alexs \
    --action cleanup
```

**Execution Flow:**
```
cleanup_cluster_wrapper()
├── get_workspace_dir()                     # Find Terraform workspace
├── workspace_exists()                      # Check if Terraform state exists
├── kubectl delete ingress/svc              # Clean up K8s resources first
└── terraform_destroy()                     # Destroy infrastructure
```

**✅ WORKS WELL:**
- Uses Terraform for clean teardown
- Prevents hanging ALBs
- Falls back to manual cleanup if no workspace

---

## Modular Component Scripts

### Location: `/scripts/operations/`

#### 1. `deploy_otel.sh` - OpenTelemetry Demo Deployment

**Standalone Usage:**
```bash
./scripts/operations/deploy_otel.sh \
    --cluster-name my-cluster \
    --namespace otel-demo \
    --chart-version 0.30.0
```

**What It Does:**
- Deploys OpenTelemetry Demo via Helm
- Configures LOCUST_HOST for load generator
- Creates otel-demo namespace
- Installs all microservices

**Credential Needs:** ❌ None (no Gremlin interaction)

**✅ WORKS INDEPENDENTLY:** Yes

---

#### 2. `deploy_failure_flags.sh` - Failure Flags Sidecar

**Standalone Usage:**
```bash
./scripts/operations/deploy_failure_flags.sh \
    --cluster-name my-cluster \
    --namespace otel-demo
```

**What It Does:**
- Patches checkout service deployment
- Adds Gremlin FF sidecar container
- Configures ingress/egress proxies
- Mounts Gremlin secrets

**Credential Needs:** ✅ Expects Gremlin secrets in `gremlin` namespace

**✅ WORKS INDEPENDENTLY:** Yes (if secrets exist)

---

#### 3. `add_monitoring_platform.sh` - Add Monitoring

**Standalone Usage:**
```bash
./scripts/operations/add_monitoring_platform.sh \
    --cluster-name my-cluster \
    --platform prometheus
```

**What It Does:**
- Installs monitoring platform (Prometheus, Grafana, etc.)
- Creates monitoring namespace
- Configures platform-specific settings

**Credential Needs:** ❌ None (unless Dynatrace/New Relic)

**✅ WORKS INDEPENDENTLY:** Yes

---

#### 4. `cluster_cleanup.sh` - Manual Cleanup

**Standalone Usage:**
```bash
./scripts/operations/cluster_cleanup.sh \
    --cluster-name my-cluster \
    --region us-east-2 \
    --force
```

**What It Does:**
- Deletes Helm releases
- Removes Kubernetes resources
- Cleans up AWS resources (ALBs, security groups)
- Deletes EKS cluster (if --force)

**Credential Needs:** ❌ None

**✅ WORKS INDEPENDENTLY:** Yes

---

#### 5. `cluster_create.sh` - Legacy Cluster Creation

**Status:** ⚠️ **OBSOLETE** (replaced by Terraform)

**Standalone Usage:**
```bash
./scripts/operations/cluster_create.sh \
    --cluster-name my-cluster \
    --node-type m5.large
```

**What It Does:**
- Creates EKS cluster via eksctl
- Installs AWS LB Controller
- Configures base components

**⚠️ SHOULD NOT BE USED:** Terraform handles this now

---

### Location: `/scripts/gremlin_install.sh`

**Standalone Usage:**
```bash
export GREMLIN_TEAM_ID="abc123"
export GREMLIN_TEAM_SECRET="secret"

./scripts/gremlin_install.sh \
    --cluster-name my-cluster \
    --type standard
```

**What It Does:**
- Installs Gremlin agent via Helm
- Creates gremlin namespace
- Configures Gremlin secrets
- Supports standard agent and PNI

**Credential Needs:** ✅ Requires env vars OR CLI args

**✅ WORKS INDEPENDENTLY:** Yes (with credentials)

---

### Location: `/config/gremlin/gremlin_annotations.sh`

**Standalone Usage:**
```bash
./config/gremlin/gremlin_annotations.sh otel-demo
```

**What It Does:**
- Annotates services with `gremlin.com/service-id`
- Adds Gremlin discovery metadata
- Patches deployments with pod annotations

**Credential Needs:** ❌ None

**✅ WORKS INDEPENDENTLY:** Yes

---

### Location: `/build_scripts/demo/healthchecks.sh`

**Standalone Usage:**
```bash
./build_scripts/demo/healthchecks.sh \
    --subdomain alexs \
    --cluster-name alexs-eks \
    --platform all
```

**What It Does:**
- Creates Gremlin health checks
- Configures Prometheus/Grafana monitoring
- Sets up custom authorizations
- Uses dynamic DNS names

**Credential Needs:** ✅ Requires `GREMLIN_TEAM_ID` env var

**✅ WORKS INDEPENDENTLY:** Yes (with credentials)

---

## Credential Flow Analysis

### Current State

#### ✅ **Works Well: `build_new` Action**

```bash
./workshop.sh --subdomain alexs --owner alex.smith --enable-eks --action build_new
```

**Credential Flow:**
1. `provision_infrastructure()` calls `resolve_gremlin_credentials_from_owner()`
2. Constructs ARNs: `alex.smith/gremlin_team_id`, etc.
3. Fetches ARNs from Secrets Manager
4. Calls `fetch_gremlin_credentials()` to get actual values
5. Exports `GREMLIN_TEAM_ID`, `GREMLIN_TEAM_CERTIFICATE`, `GREMLIN_TEAM_PRIVATE_KEY`
6. All downstream scripts use these env vars

**✅ Result:** Fully automated, no manual credential management

---

#### ⚠️ **Broken: `deploy_existing` Action**

```bash
./workshop.sh --cluster-name existing-cluster --action deploy_existing
```

**Credential Flow:**
1. ❌ Does NOT call `resolve_gremlin_credentials_from_owner()`
2. ❌ Does NOT call `fetch_gremlin_credentials()`
3. ❌ Expects user to manually export credentials:
   ```bash
   export GREMLIN_TEAM_ID="..."
   export GREMLIN_TEAM_SECRET="..."
   ```
4. Passes env vars to `gremlin_install.sh`

**⚠️ Result:** Manual credential management required

---

#### ⚠️ **Broken: `gremlin_only` Action**

```bash
./workshop.sh --cluster-name my-cluster --action gremlin_only
```

**Credential Flow:**
1. ❌ Does NOT call `resolve_gremlin_credentials_from_owner()`
2. ❌ Does NOT call `fetch_gremlin_credentials()`
3. ❌ Expects user to manually export credentials
4. Passes env vars to `gremlin_install.sh`

**⚠️ Result:** Manual credential management required

---

#### ⚠️ **Inconsistent: Standalone Scripts**

**Scripts that need credentials:**
- `gremlin_install.sh` ✅ Uses env vars (works)
- `healthchecks.sh` ✅ Uses env vars (works)
- `deploy_failure_flags.sh` ✅ Uses K8s secrets (works)

**Problem:** Users must manually export credentials before running

---

## Issues & Improvements

### Issue 1: Inconsistent Credential Handling

**Problem:**
- `build_new` auto-fetches credentials ✅
- `deploy_existing` requires manual export ❌
- `gremlin_only` requires manual export ❌
- Standalone scripts require manual export ❌

**Impact:** Confusing user experience, error-prone

**Solution:**
```bash
# Add credential resolution to ALL actions
case "$WORKSHOP_ACTION" in
    "build_new")
        # Already has it ✅
        ;;
    "deploy_existing"|"gremlin_only")
        # ADD THIS:
        if [[ -z "$GREMLIN_TEAM_ID" && -n "$OWNER" ]]; then
            resolve_gremlin_credentials_from_owner "$OWNER"
            fetch_gremlin_credentials
        fi
        ;;
esac
```

---

### Issue 2: `deploy_existing` Not Truly Idempotent

**Problem:**
- Checks for existing Helm releases ✅
- Attempts `helm upgrade` ✅
- Falls back to `helm uninstall` if upgrade fails ⚠️
- But uninstall + reinstall is NOT idempotent

**Impact:** Can cause downtime, data loss

**Solution:**
```bash
# Better idempotency handling
if helm list -n otel-demo -q | grep -q "opentelemetry-demo"; then
    log_info "OpenTelemetry Demo already installed, skipping..."
    return 0  # Skip installation
else
    # Install fresh
    helm install ...
fi
```

---

### Issue 3: Missing `SUBDOMAIN` in Non-Terraform Actions

**Problem:**
- `deploy_existing` doesn't have `SUBDOMAIN` variable
- `gremlin_only` doesn't have `SUBDOMAIN` variable
- `healthchecks.sh` needs `SUBDOMAIN` for DNS names

**Impact:** Health checks fail with wrong DNS names

**Solution:**
```bash
# Add SUBDOMAIN derivation for existing clusters
if [[ -z "$SUBDOMAIN" && -n "$CLUSTER_NAME" ]]; then
    # Extract subdomain from cluster name (e.g., "alexs-eks" → "alexs")
    SUBDOMAIN="${CLUSTER_NAME%-eks}"
    export SUBDOMAIN
fi
```

---

### Issue 4: No Validation of Secrets Manager Credentials

**Problem:**
- `resolve_gremlin_credentials_from_owner()` checks if secrets exist ✅
- But `fetch_gremlin_credentials()` doesn't validate values
- Empty/invalid credentials silently fail

**Impact:** Gremlin installation fails with cryptic errors

**Solution:**
```bash
# Add validation after fetch
fetch_gremlin_credentials() {
    # ... existing code ...
    
    # Validate credentials
    if [[ ${#GREMLIN_TEAM_ID} -lt 10 ]]; then
        log_error "Invalid GREMLIN_TEAM_ID (too short)"
        return 1
    fi
    
    if [[ ! "$GREMLIN_TEAM_CERTIFICATE" =~ "BEGIN CERTIFICATE" ]]; then
        log_error "Invalid GREMLIN_TEAM_CERTIFICATE (not a valid cert)"
        return 1
    fi
}
```

---

### Issue 5: Standalone Scripts Don't Auto-Fetch Credentials

**Problem:**
- Users must manually export credentials before running standalone scripts
- No helper script to fetch credentials

**Impact:** Poor user experience, error-prone

**Solution:**
Create a helper script:
```bash
# scripts/util/fetch_credentials.sh
#!/bin/bash
source "$(dirname "$0")/../../lib/terraform.sh"

OWNER="${1:-}"
if [[ -z "$OWNER" ]]; then
    echo "Usage: $0 <owner-name>"
    exit 1
fi

resolve_gremlin_credentials_from_owner "$OWNER"
fetch_gremlin_credentials

# Print export commands
echo "export GREMLIN_TEAM_ID='$GREMLIN_TEAM_ID'"
echo "export GREMLIN_TEAM_CERTIFICATE='$GREMLIN_TEAM_CERTIFICATE'"
echo "export GREMLIN_TEAM_PRIVATE_KEY='$GREMLIN_TEAM_PRIVATE_KEY'"
```

**Usage:**
```bash
# Fetch and export credentials
eval $(./scripts/util/fetch_credentials.sh alex.smith)

# Now run standalone script
./scripts/gremlin_install.sh --cluster-name my-cluster
```

---

### Issue 6: No Dry-Run for Terraform Actions

**Problem:**
- `--dry-run` flag exists but doesn't work with Terraform
- Users can't preview infrastructure changes

**Impact:** Risky deployments

**Solution:**
```bash
provision_infrastructure() {
    # ... existing code ...
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would run: terraform plan"
        terraform_plan "$workspace_dir"
        return 0  # Don't apply
    fi
    
    terraform_apply "$workspace_dir"
}
```

---

## Recent Improvements (2025-10-21)

### ✅ **Refactoring Complete**

All P0 and P1 issues have been resolved:

1. ✅ **Credential auto-fetch added to all actions**
   - `ensure_gremlin_credentials()` in lib/deployment.sh
   - Auto-resolves from owner or subdomain
   - Used by `deploy_existing` and `gremlin_only`

2. ✅ **SUBDOMAIN support added everywhere**
   - Health checks use correct DNS names
   - Backwards compatible with CLUSTER_NAME fallback

3. ✅ **Improved idempotency**
   - `install_gremlin()` checks if already installed
   - `fix_gremlin_ec2_permissions()` checks if policy attached
   - No more fragile upgrade/uninstall logic

4. ✅ **Unified Gremlin setup**
   - Created `lib/gremlin.sh` with shared functions
   - Created `lib/deployment.sh` with shared functions
   - All actions use same code paths

5. ✅ **EC2 permissions in correct location**
   - Moved from monitoring.sh to cluster.sh
   - Runs during cluster setup, not monitoring setup

---

### 🟢 **Remaining Optional Tasks**

6. **Add dry-run support for Terraform**
   - Time: 10 minutes
   - Impact: Low - safety feature
   - Status: Not blocking

7. **Mark `cluster_create.sh` as deprecated**
   - Time: 5 minutes
   - Impact: Low - documentation cleanup
   - Status: Not blocking

---

## Summary

### What Works Well ✅
- All three actions (`build_new`, `deploy_existing`, `gremlin_only`)
- Unified credential resolution across all actions
- Idempotent installations (safe to run multiple times)
- Modular script architecture with shared functions
- Consistent DNS naming convention
- EC2 permissions in correct location

### Ready for Testing ✅
- ✅ All critical issues resolved
- ✅ Code refactoring complete
- ✅ Credential auto-resolution working
- ✅ Idempotency implemented
- ✅ DNS names aligned with Terraform outputs
- Standalone scripts require manual credential export

### Recommended Next Steps
1. Fix P0 issues (credential consistency + SUBDOMAIN)
2. Test full workflow end-to-end
3. Fix P1 issues (idempotency + validation)
4. Document standalone script usage patterns
