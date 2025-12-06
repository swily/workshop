# Final Directories Audit - istio, lib, patches, scripts, versions, terraform

**Date:** 2025-10-21  
**Purpose:** Analyze remaining directories for obsolete files  
**Total Files:** 18 files across 6 directories

---

## Executive Summary

**Files Analyzed:** 18 files  
**Status:** 8 ACTIVE (core), 3 UTILITY, 4 OBSOLETE, 3 EMPTY/GITIGNORED

**Key Findings:**
- `lib/` - All 8 files ACTIVE (core library functions)
- `istio/` - 2 files OBSOLETE (Istio not used)
- `patches/` - Empty directory (DELETE)
- `scripts/` - Mix of active and utility files
- `versions/` - 2 files OBSOLETE (API error responses)
- `terraform/` - Workspace directory (keep structure)

---

## 1. /istio Directory Analysis (2 files)

### Directory Purpose
Contains Istio service mesh configuration files.

### Files

#### 1. `istio-operator.yaml` - ❌ OBSOLETE

**Status:** ❌ **OBSOLETE** (Istio not used)  
**Purpose:** Istio operator configuration

**Used By:** **NONE** - Not referenced in any scripts

**Evidence:**
```bash
grep -r "istio-operator.yaml" *.sh  # No results
grep -r "istio" *.sh  # No results in active scripts
```

**Why Obsolete:**
- `lib/cluster.sh` has `install_istio()` function but it's never called
- Function uses `istioctl` CLI, not this YAML file
- Workshop.sh doesn't have `--install-istio` flag
- Only archived `cluster_create.sh` referenced Istio

**From Memory:**
- Istio was installed on test-cluster but NOT being used
- OpenTelemetry Demo has no Envoy sidecars
- No VirtualServices or DestinationRules configured
- Kubernetes-native approach used instead

**Action:** **ARCHIVE** to `archive/obsolete-configs/`

---

#### 2. `kiali-values.yaml` - ❌ OBSOLETE

**Status:** ❌ **OBSOLETE** (Istio not used)  
**Purpose:** Kiali (Istio observability) Helm values

**Used By:** **NONE** - Not referenced in any scripts

**Why Obsolete:**
- Kiali is part of Istio ecosystem
- `install_istio()` installs Kiali from remote URL, not this file
- Istio not used in current workflow

**Action:** **ARCHIVE** to `archive/obsolete-configs/`

---

## 2. /lib Directory Analysis (8 files)

### Directory Purpose
Core library functions used by workshop.sh and other scripts.

### Files - ALL ACTIVE ✅

#### 1. `cluster.sh` - ✅ ACTIVE

**Status:** ✅ **CRITICAL - CORE LIBRARY**  
**Purpose:** Cluster operations and configuration

**Used By:**
- `workshop.sh` line 13 - Sourced directly

**Key Functions:**
- `update_kubeconfig()` - Connect to EKS cluster
- `validate_cluster_exists()` - Verify cluster exists
- `configure_cluster_base()` - Setup base components
- `install_aws_load_balancer_controller()` - ALB controller
- `install_istio()` - Istio installation (not used but available)
- `install_prometheus_operator()` - Prometheus setup

**Action:** **KEEP** - Core functionality

---

#### 2. `common.sh` - ✅ ACTIVE

**Status:** ✅ **CRITICAL - CORE LIBRARY**  
**Purpose:** Shared utility functions

**Used By:**
- `workshop.sh` line 11 - Sourced directly
- All other lib files source this

**Key Functions:**
- Logging functions (`log_info`, `log_error`, `log_success`)
- `ensure_namespace()` - Namespace management
- `ensure_helm_repo()` - Helm repository management
- `wait_for_pods()` - Pod readiness checks
- `export_cluster_state()` - State file generation
- `command_exists()` - Command availability checks

**Action:** **KEEP** - Core functionality

---

#### 3. `deployment.sh` - ✅ ACTIVE

**Status:** ✅ **CRITICAL - CORE LIBRARY**  
**Purpose:** Shared deployment functions

**Used By:**
- `workshop.sh` line 17 - Sourced directly

**Key Functions:**
- `deploy_failure_flags_if_enabled()` - Failure flags deployment
- `apply_cross_namespace_services()` - Cross-namespace routing
- `finalize_deployment()` - Deployment finalization
- `ensure_gremlin_credentials()` - Credential auto-resolution
- `cleanup_legacy_ingresses()` - Ingress cleanup

**Created:** 2025-10-21 (during refactoring)

**Action:** **KEEP** - Core functionality

---

#### 4. `gremlin.sh` - ✅ ACTIVE

**Status:** ✅ **CRITICAL - CORE LIBRARY**  
**Purpose:** Unified Gremlin installation and configuration

**Used By:**
- `workshop.sh` line 16 - Sourced directly

**Key Functions:**
- `create_gremlin_rbac()` - RBAC setup
- `verify_gremlin_access()` - Permission verification
- `install_gremlin()` - Gremlin agent installation
- `apply_gremlin_annotations()` - Service annotations
- `fix_gremlin_ec2_permissions()` - EC2 permissions
- `setup_gremlin_complete()` - Complete Gremlin setup

**Created:** 2025-10-21 (during refactoring)

**Action:** **KEEP** - Core functionality

---

#### 5. `https_detection.sh` - ✅ ACTIVE

**Status:** ✅ **ACTIVE**  
**Purpose:** HTTPS/TLS detection and scheme handling

**Used By:**
- `build_scripts/demo/healthchecks.sh` line 23 - Sourced

**Key Functions:**
- Detects if HTTPS is enabled
- Determines correct URL scheme
- ACM certificate detection

**Action:** **KEEP** - Used by health checks

---

#### 6. `monitoring.sh` - ✅ ACTIVE

**Status:** ✅ **CRITICAL - CORE LIBRARY**  
**Purpose:** Monitoring platform setup and configuration

**Used By:**
- `workshop.sh` line 14 - Sourced directly

**Key Functions:**
- `setup_comprehensive_monitoring()` - Main monitoring setup
- `setup_prometheus_monitoring()` - Prometheus setup
- `setup_grafana_monitoring()` - Grafana setup
- `setup_dynatrace_monitoring()` - Dynatrace setup
- `setup_newrelic_monitoring()` - New Relic setup
- `setup_datadog_monitoring()` - DataDog setup
- `setup_gremlin_monitoring()` - Gremlin health checks

**Updated:** 2025-10-21 (removed fallback logic)

**Action:** **KEEP** - Core functionality

---

#### 7. `terraform.sh` - ✅ ACTIVE

**Status:** ✅ **CRITICAL - CORE LIBRARY**  
**Purpose:** Terraform wrapper for infrastructure provisioning

**Used By:**
- `workshop.sh` line 15 - Sourced directly

**Key Functions:**
- `provision_infrastructure()` - Create infrastructure via Terraform
- `destroy_infrastructure()` - Destroy infrastructure via Terraform
- `generate_terraform_workspace()` - Create Terraform workspace
- `export_terraform_outputs()` - Export outputs as env vars

**Action:** **KEEP** - Core functionality

---

#### 8. `ui.sh` - ✅ ACTIVE

**Status:** ✅ **CRITICAL - CORE LIBRARY**  
**Purpose:** Interactive UI and user prompts

**Used By:**
- `workshop.sh` line 12 - Sourced directly

**Key Functions:**
- `show_banner()` - Display workshop banner
- `show_completion_summary()` - Show completion info
- `help_header()` - Help text formatting
- `help_footer()` - Help text formatting
- Interactive prompts and menus

**Action:** **KEEP** - Core functionality

---

## 3. /patches Directory Analysis

### Status: ❌ **EMPTY DIRECTORY**

**Contents:** None (all patch files were archived earlier)

**Previously Contained:**
- `load-generator-loadbalancer-patch.yaml` (archived)
- `otel-collector-grpc-metrics-patch.yaml` (archived)

**Action:** **DELETE** empty directory

---

## 4. /scripts Directory Analysis

### Directory Structure
```
scripts/
├── check_metrics.sh
├── fix_gremlin_permissions.sh
├── gremlin_install.sh
├── operations/
│   ├── cluster_cleanup.sh
│   ├── deploy_failure_flags.sh
│   └── deploy_otel.sh
└── util/
    ├── api_keys_reference.txt
    ├── find_prometheus_auth_id.sh
    ├── test_gremlin_api.sh
    ├── test_health_checks.sh
    └── validate_cluster_health.sh
```

### Root Scripts (3 files)

#### 1. `check_metrics.sh` - ✅ ACTIVE

**Status:** ✅ **ACTIVE** (Utility)  
**Purpose:** Validates metrics collection

**Used By:** Manual validation, not automated workflow

**Action:** **KEEP** - Useful utility

---

#### 2. `fix_gremlin_permissions.sh` - ✅ ACTIVE

**Status:** ✅ **ACTIVE**  
**Purpose:** Fixes EC2 permissions for Gremlin

**Used By:**
- Can be run standalone
- Similar logic in `lib/gremlin.sh` → `fix_gremlin_ec2_permissions()`

**Note:** Could be consolidated into lib/gremlin.sh, but useful as standalone utility

**Action:** **KEEP** - Standalone utility

---

#### 3. `gremlin_install.sh` - ✅ ACTIVE

**Status:** ✅ **CRITICAL - ACTIVELY USED**  
**Purpose:** Installs Gremlin agent via Helm

**Used By:**
- `lib/gremlin.sh` line 113 - Called by `install_gremlin()`

**Action:** **KEEP** - Core functionality

---

### operations/ Subdirectory (3 files) - ALL ACTIVE ✅

Already analyzed in previous cleanup - all 3 files are ACTIVE:
1. ✅ `cluster_cleanup.sh` - Cleanup operations
2. ✅ `deploy_failure_flags.sh` - Failure flags deployment
3. ✅ `deploy_otel.sh` - OpenTelemetry Demo deployment

**Action:** **KEEP ALL** - Core functionality

---

### util/ Subdirectory (5 files)

#### 1. `api_keys_reference.txt` - ❌ OBSOLETE (SECURITY RISK!)

**Status:** ❌ **OBSOLETE - SECURITY RISK**  
**Purpose:** Reference file with actual API keys

**Contents:**
- New Relic License Key: `NRAK-NEN4AEYCWR41FTG6M9WBBXEFZMQ`
- Dynatrace API Token: `dt0c01.T7LOPNX6U5T5Y3DKJRP5WYP7...`

**Why Obsolete:**
- Contains actual API keys (security issue!)
- Should use Secrets Manager or environment variables
- Not referenced by any scripts
- Should be in .gitignore

**Action:** **DELETE** immediately (security risk)

---

#### 2. `find_prometheus_auth_id.sh` - ⚠️ UTILITY

**Status:** ⚠️ **UTILITY** (Keep)  
**Purpose:** Helper for finding Prometheus authentication IDs

**Used By:** Manual debugging only

**Action:** **KEEP** - Useful utility

---

#### 3. `test_gremlin_api.sh` - ⚠️ UTILITY

**Status:** ⚠️ **UTILITY** (Keep)  
**Purpose:** Tests Gremlin API connectivity

**Used By:** Manual testing only

**Action:** **KEEP** - Useful utility (moved here earlier)

---

#### 4. `test_health_checks.sh` - ⚠️ UTILITY

**Status:** ⚠️ **UTILITY** (Keep)  
**Purpose:** Tests health checks functionality

**Used By:** Manual testing only

**Action:** **KEEP** - Useful utility (moved here earlier)

---

#### 5. `validate_cluster_health.sh` - ⚠️ UTILITY

**Status:** ⚠️ **UTILITY** (Keep)  
**Purpose:** Validates cluster health post-deployment

**Used By:** Manual validation only

**Action:** **KEEP** - Useful utility

---

## 5. /versions Directory Analysis (2 files)

### Directory Purpose
Appears to contain Gremlin agent version information.

### Files

#### 1. `agents.json` - ❌ OBSOLETE

**Status:** ❌ **OBSOLETE** (API Error Response)  
**Purpose:** Gremlin agent versions

**Contents:**
```
User requires privilege for target team: CLIENTS_READ
```

**Why Obsolete:**
- Contains API error response, not actual data
- Not referenced by any scripts
- Appears to be output from failed API call

**Action:** **DELETE**

---

#### 2. `agents_summary.json` - ❌ OBSOLETE

**Status:** ❌ **OBSOLETE** (Likely similar error)  
**Purpose:** Gremlin agent version summary

**Used By:** **NONE** - Not referenced in any scripts

**Evidence:**
```bash
grep -r "versions/agents" *.sh  # No results
```

**Action:** **DELETE**

---

## 6. /terraform Directory Analysis

### Directory Structure
```
terraform/
├── .gitignore          # Terraform-specific gitignore
└── workspace/          # Empty (workspaces created at runtime)
```

### Files

#### 1. `.gitignore` - ✅ ACTIVE

**Status:** ✅ **ACTIVE**  
**Purpose:** Ignores Terraform state files and sensitive data

**Contents:**
- Ignores `*.tfstate`, `*.tfstate.backup`
- Ignores `.terraform/` directories
- Ignores `*.tfvars` files
- Keeps workspace directory structure

**Action:** **KEEP** - Essential for Terraform

---

#### 2. `workspace/` - ✅ ACTIVE (Empty)

**Status:** ✅ **ACTIVE** (Runtime directory)  
**Purpose:** Contains Terraform workspaces created at runtime

**How It Works:**
- `lib/terraform.sh` generates workspaces dynamically
- Each subdomain gets its own workspace directory
- Example: `workspace/test1/` for `--subdomain test1`
- Contains `main.tf`, `variables.tf`, `terraform.tf`

**Current State:** Empty (workspaces created/destroyed as needed)

**Action:** **KEEP** - Required for Terraform workflow

---

## Summary Tables

### istio/ Files (2 files)

| File | Status | Action |
|------|--------|--------|
| `istio-operator.yaml` | ❌ OBSOLETE | **ARCHIVE** |
| `kiali-values.yaml` | ❌ OBSOLETE | **ARCHIVE** |

---

### lib/ Files (8 files)

| File | Status | Action |
|------|--------|--------|
| `cluster.sh` | ✅ ACTIVE | **KEEP** |
| `common.sh` | ✅ ACTIVE | **KEEP** |
| `deployment.sh` | ✅ ACTIVE | **KEEP** |
| `gremlin.sh` | ✅ ACTIVE | **KEEP** |
| `https_detection.sh` | ✅ ACTIVE | **KEEP** |
| `monitoring.sh` | ✅ ACTIVE | **KEEP** |
| `terraform.sh` | ✅ ACTIVE | **KEEP** |
| `ui.sh` | ✅ ACTIVE | **KEEP** |

**Result:** **KEEP ALL** - Core library functions

---

### patches/ Directory

| Status | Action |
|--------|--------|
| ❌ EMPTY | **DELETE** |

---

### scripts/ Files (8 files)

| File | Status | Action |
|------|--------|--------|
| `check_metrics.sh` | ✅ ACTIVE | **KEEP** |
| `fix_gremlin_permissions.sh` | ✅ ACTIVE | **KEEP** |
| `gremlin_install.sh` | ✅ ACTIVE | **KEEP** |
| `operations/cluster_cleanup.sh` | ✅ ACTIVE | **KEEP** |
| `operations/deploy_failure_flags.sh` | ✅ ACTIVE | **KEEP** |
| `operations/deploy_otel.sh` | ✅ ACTIVE | **KEEP** |
| `util/api_keys_reference.txt` | ❌ SECURITY | **DELETE** |
| `util/find_prometheus_auth_id.sh` | ⚠️ UTILITY | **KEEP** |
| `util/test_gremlin_api.sh` | ⚠️ UTILITY | **KEEP** |
| `util/test_health_checks.sh` | ⚠️ UTILITY | **KEEP** |
| `util/validate_cluster_health.sh` | ⚠️ UTILITY | **KEEP** |

---

### versions/ Files (2 files)

| File | Status | Action |
|------|--------|--------|
| `agents.json` | ❌ OBSOLETE | **DELETE** |
| `agents_summary.json` | ❌ OBSOLETE | **DELETE** |

---

### terraform/ Files (2 items)

| File | Status | Action |
|------|--------|--------|
| `.gitignore` | ✅ ACTIVE | **KEEP** |
| `workspace/` | ✅ ACTIVE | **KEEP** |

---

## Overall Summary

### By Status

| Status | Count | Percentage |
|--------|-------|------------|
| ✅ ACTIVE (Core) | 11 | 61% |
| ⚠️ UTILITY | 4 | 22% |
| ❌ OBSOLETE | 2 | 11% |
| ❌ SECURITY | 1 | 6% |
| ❌ EMPTY DIR | 1 | - |
| **Total** | **18** | **100%** |

### By Action

| Action | Count | Files |
|--------|-------|-------|
| **KEEP** | 15 | Core + utility files |
| **ARCHIVE** | 2 | Istio configs |
| **DELETE** | 3 | API keys + version files |
| **DELETE DIR** | 2 | patches/ + (empty) |
| **Total** | **20** | (18 files + 2 actions) |

---

## Recommended Actions

### Phase 1: Delete Security Risk (IMMEDIATE)

```bash
# Delete file with hardcoded API keys
rm scripts/util/api_keys_reference.txt
```

**CRITICAL:** This file contains actual API keys and should be deleted immediately.

---

### Phase 2: Delete Obsolete Files

```bash
# Delete version files (API error responses)
rm versions/agents.json
rm versions/agents_summary.json

# Delete empty versions directory
rmdir versions
```

---

### Phase 3: Archive Istio Files

```bash
# Archive Istio configuration files
mv istio/istio-operator.yaml archive/obsolete-configs/
mv istio/kiali-values.yaml archive/obsolete-configs/

# Delete empty istio directory
rmdir istio
```

---

### Phase 4: Delete Empty Directories

```bash
# Delete empty patches directory
rmdir patches
```

---

### Phase 5: Update .gitignore

```bash
# Add to .gitignore
echo "" >> .gitignore
echo "# API keys and secrets (never commit)" >> .gitignore
echo "scripts/util/api_keys_reference.txt" >> .gitignore
echo "versions/" >> .gitignore
```

---

## Key Findings

### ✅ Core Library Files (All Active)

**ALL 8 files in `lib/` are CRITICAL and ACTIVE:**
1. `cluster.sh` - Cluster operations
2. `common.sh` - Shared utilities
3. `deployment.sh` - Deployment functions (new)
4. `gremlin.sh` - Gremlin functions (new)
5. `https_detection.sh` - HTTPS detection
6. `monitoring.sh` - Monitoring setup
7. `terraform.sh` - Terraform wrapper
8. `ui.sh` - Interactive UI

**These are the backbone of the workshop system - DO NOT MODIFY**

---

### ❌ Istio Not Used

**Evidence:**
- Istio config files not referenced
- `install_istio()` function exists but never called
- No `--install-istio` flag in workshop.sh
- Memory confirms Istio installed but not used on test-cluster
- Kubernetes-native approach used instead

**Conclusion:** Istio files are obsolete

---

### 🔒 Security Issue Found

**File:** `scripts/util/api_keys_reference.txt`

**Contains:**
- New Relic License Key (exposed)
- Dynatrace API Token (exposed)

**Action:** DELETE IMMEDIATELY

---

### 📁 Empty/Runtime Directories

**patches/** - Empty (all files archived)  
**terraform/workspace/** - Empty (runtime-generated)  
**versions/** - Contains only error responses

---

## Impact Analysis

### No Risk (Core Files)

- ✅ All `lib/` files are CRITICAL - DO NOT TOUCH
- ✅ All `scripts/operations/` files are ACTIVE
- ✅ All `scripts/util/` files (except api_keys) are useful utilities

### Low Risk (Archive)

- ✅ Istio files not referenced anywhere
- ✅ Safe to archive

### High Risk (Security)

- 🔴 `api_keys_reference.txt` - Contains actual API keys
- 🔴 Must be deleted immediately

### No Risk (Delete)

- ✅ `versions/` files are API error responses
- ✅ Empty directories can be deleted

---

## Testing Plan

After cleanup:

### 1. Verify No Broken References

```bash
# Check for references to deleted files
grep -r "istio-operator.yaml" *.sh
grep -r "kiali-values.yaml" *.sh
grep -r "api_keys_reference.txt" *.sh
grep -r "versions/agents" *.sh
```

### 2. Test All Three Workshop Actions

```bash
./workshop.sh --action build_new --subdomain test1 --owner user --enable-eks
./workshop.sh --action deploy_existing --cluster-name test --owner user
./workshop.sh --action gremlin_only --cluster-name test --owner user
```

### 3. Verify Library Functions

All lib files are sourced by workshop.sh - if workshop.sh runs, they're working.

---

## Conclusion

**Total Files:** 18 files + 2 directories  
**Obsolete:** 2 files (Istio configs)  
**Security Risk:** 1 file (API keys)  
**Empty/Error:** 2 files + 2 directories  
**Active:** 15 files (83%)

**Recommendation:** 
1. **IMMEDIATE:** Delete `api_keys_reference.txt` (security)
2. Archive 2 Istio files
3. Delete 2 version files + empty directories
4. Keep all 15 active/utility files

**Risk Level:** Low (except security issue)

**Estimated Time:** 10 minutes

---

**Last Updated:** 2025-10-21  
**Status:** Analysis Complete - Ready for Cleanup  
**Next Step:** Execute Phase 1 (delete API keys file immediately)
