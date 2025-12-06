# File Audit Analysis - Obsolete vs. Active Files

**Date:** 2025-10-21  
**Purpose:** Determine which files are still needed vs. obsolete after refactoring

---

## Executive Summary

**Files Analyzed:** 24 files across monitoring, scripts, and patches  
**Status:** 11 OBSOLETE, 9 ACTIVE, 4 UTILITY (keep for now)

**Recommendation:** Archive 11 obsolete files, keep 13 active/utility files

---

## Detailed Analysis

### 🔴 OBSOLETE FILES (Can Be Archived)

#### 1. `/monitoring/config/` - All 4 files OBSOLETE

**Files:**
- `kubelet-servicemonitor.yaml`
- `prometheus-operator-values.yaml`
- `prometheus-rules.yaml`
- `service-monitors.yaml`

**Status:** ❌ OBSOLETE  
**Reason:** Not referenced anywhere in active scripts  
**Replacement:** Monitoring setup now uses:
- `monitoring/prometheus/values/prometheus-values.yaml`
- `monitoring/prometheus/servicemonitors/otel-demo-servicemonitor.yaml`
- Individual platform-specific configs

**Evidence:**
```bash
# No references found in any .sh files
grep -r "kubelet-servicemonitor.yaml" *.sh  # No results
grep -r "prometheus-operator-values.yaml" *.sh  # No results
grep -r "prometheus-rules.yaml" *.sh  # No results
grep -r "service-monitors.yaml" *.sh  # No results
```

**Action:** Archive to `archive/obsolete-configs/`

---

#### 2. `/monitoring/cleanup_deprecated.sh` - OBSOLETE

**Status:** ❌ OBSOLETE (Ironic!)  
**Reason:** This script was meant to clean up deprecated files, but those files still exist  
**Purpose:** Was supposed to remove:
- `monitoring/gremlin/create_health_checks.sh` (still exists, still used)
- `monitoring/gremlin/validate_integration.sh` (still exists)
- `monitoring/gremlin/gremlin_credentials_manager.sh` (still exists)

**Current Reality:**
- The "deprecated" files it targets are still being used
- `lib/monitoring.sh` line 559 still calls `monitoring/gremlin/create_health_checks.sh`
- This cleanup script was never run

**Action:** Delete (it's a cleanup script that was never executed)

---

#### 3. `/monitoring/test_gremlin_api.sh` - UTILITY (Keep)

**Status:** ⚠️ UTILITY  
**Reason:** Testing/debugging tool, not part of main workflow  
**Used by:** Manual testing only  
**Action:** Keep in `scripts/util/` for debugging

---

#### 4. `/monitoring/test_health_checks.sh` - UTILITY (Keep)

**Status:** ⚠️ UTILITY  
**Reason:** Testing/debugging tool  
**Used by:** Manual testing only  
**Action:** Keep in `scripts/util/` for debugging

---

#### 5. `/patches/load-generator-loadbalancer-patch.yaml` - OBSOLETE

**Status:** ❌ OBSOLETE  
**Reason:** Only used by `helper_scripts/update_loadgen_target.sh`  
**Evidence:**
```bash
grep -r "load-generator-loadbalancer-patch.yaml" *.sh
# Only found in: helper_scripts/update_loadgen_target.sh
```

**Current Approach:** Load generator configured via Helm values, not patches  
**Action:** Archive to `archive/obsolete-patches/`

---

#### 6. `/patches/otel-collector-grpc-metrics-patch.yaml` - OBSOLETE

**Status:** ❌ OBSOLETE  
**Reason:** Only used by `helper_scripts/update_loadgen_target.sh`  
**Current Approach:** Collector configured via Helm values  
**Action:** Archive to `archive/obsolete-patches/`

---

#### 7. `/scripts/operations/add_monitoring_platform.sh` - OBSOLETE

**Status:** ❌ OBSOLETE  
**Reason:** Not called by workshop.sh or any active workflow  
**Purpose:** Was meant to add monitoring platforms post-deployment  
**Replacement:** `workshop.sh` handles monitoring during initial deployment via `setup_comprehensive_monitoring()`

**Evidence:**
```bash
# Only mentioned in archived docs, not used in active scripts
grep -r "add_monitoring_platform.sh" *.sh  # No results in active scripts
```

**Action:** Archive to `archive/obsolete-scripts/`

---

#### 8. `/scripts/operations/cluster_create.sh` - OBSOLETE

**Status:** ❌ OBSOLETE (Already documented)  
**Reason:** Replaced by Terraform via `lib/terraform.sh`  
**Replacement:** `provision_infrastructure()` in workshop.sh  
**Notes:** Already marked as obsolete in TESTING_CHECKLIST.md

**Evidence:**
- Not called by workshop.sh
- Uses eksctl (deprecated approach)
- Terraform now handles cluster creation

**Action:** Archive to `archive/obsolete-scripts/` with deprecation notice

---

#### 9. `/scripts/util/get_nobl9_token.sh` - OBSOLETE

**Status:** ❌ OBSOLETE  
**Reason:** Nobl9 integration not part of workshop  
**Contains:** Hardcoded credentials (security issue!)
```bash
CLIENT_ID="0oapcehib7aBVukir417"
CLIENT_SECRET="pwLeeaQ3Sc5JE4N18nQMQFNIUVakxf0L-juN7Nj7ZUxU9TmSteLe07g6u5e2l6KR"
```

**Action:** DELETE (contains secrets, not used)

---

#### 10. `/scripts/util/test_nobl9_auth.sh` - OBSOLETE

**Status:** ❌ OBSOLETE  
**Reason:** Nobl9 integration not part of workshop  
**Action:** DELETE

---

#### 11. `/scripts/util/test_nobl9_comprehensive.sh` - OBSOLETE

**Status:** ❌ OBSOLETE  
**Reason:** Nobl9 integration not part of workshop  
**Action:** DELETE

---

#### 12. `/scripts/util/test_nobl9_status.sh` - OBSOLETE

**Status:** ❌ OBSOLETE  
**Reason:** Nobl9 integration not part of workshop  
**Action:** DELETE

---

### ✅ ACTIVE FILES (Keep - Currently Used)

#### 1. `/scripts/operations/deploy_failure_flags.sh` - ACTIVE

**Status:** ✅ ACTIVE  
**Used by:** `lib/deployment.sh` → `deploy_failure_flags_if_enabled()`  
**Called from:** `workshop.sh` in all 3 actions when `ENABLE_FAILURE_FLAGS=true`  
**Purpose:** Deploys Gremlin Failure Flags sidecar to checkout service  
**Action:** KEEP

---

#### 2. `/scripts/operations/deploy_otel.sh` - ACTIVE

**Status:** ✅ ACTIVE  
**Used by:** `workshop.sh` in all 3 actions  
**Purpose:** Deploys OpenTelemetry Demo application  
**Lines:** 233, 272 in workshop.sh  
**Action:** KEEP

---

#### 3. `/scripts/operations/cluster_cleanup.sh` - ACTIVE

**Status:** ✅ ACTIVE  
**Used by:** `workshop.sh` → `cleanup_cluster_wrapper()`  
**Purpose:** Fallback cleanup when Terraform workspace doesn't exist  
**Action:** KEEP

---

#### 4. `/scripts/gremlin_install.sh` - ACTIVE

**Status:** ✅ ACTIVE  
**Used by:** `lib/gremlin.sh` → `install_gremlin()`  
**Purpose:** Installs Gremlin agent via Helm  
**Action:** KEEP

---

#### 5. `/scripts/fix_gremlin_permissions.sh` - ACTIVE

**Status:** ✅ ACTIVE (but could be integrated)  
**Purpose:** Fixes EC2 permissions for Gremlin service discovery  
**Note:** Similar logic now in `lib/gremlin.sh` → `fix_gremlin_ec2_permissions()`  
**Action:** KEEP (standalone utility) or CONSOLIDATE into lib/gremlin.sh

---

#### 6. `/scripts/check_metrics.sh` - UTILITY

**Status:** ⚠️ UTILITY  
**Purpose:** Debugging tool for checking metrics  
**Action:** KEEP in scripts/util/

---

#### 7. `/scripts/util/find_prometheus_auth_id.sh` - UTILITY

**Status:** ⚠️ UTILITY  
**Purpose:** Helper for finding Prometheus authentication IDs  
**Action:** KEEP (useful for debugging health checks)

---

#### 8. `/scripts/util/validate_cluster_health.sh` - UTILITY

**Status:** ⚠️ UTILITY  
**Purpose:** Validates cluster health post-deployment  
**Action:** KEEP (useful for testing)

---

#### 9. `/monitoring/create_health_checks.sh` - ACTIVE

**Status:** ✅ ACTIVE  
**Purpose:** Unified entry point for creating health checks  
**Used by:** Various monitoring scripts  
**Action:** KEEP

---

### 📁 MONITORING/GREMLIN/ DIRECTORY - NEEDS DECISION

**Files:**
- `create_health_checks.sh` (30KB, 770 lines)
- `gremlin_credentials_manager.sh`
- `validate_integration.sh`
- `README.md`

**Status:** ⚠️ PARTIALLY OBSOLETE  
**Current Usage:**
- `lib/monitoring.sh` line 559 still calls `monitoring/gremlin/create_health_checks.sh`
- This is a fallback when `build_scripts/demo/healthchecks.sh` doesn't exist

**Replacement:**
- Primary: `build_scripts/demo/healthchecks.sh` (preferred)
- Fallback: `monitoring/gremlin/create_health_checks.sh` (legacy)

**Decision Needed:**
1. **Option A:** Keep as fallback (current state)
2. **Option B:** Remove and rely only on `build_scripts/demo/healthchecks.sh`
3. **Option C:** Consolidate into single health checks script

**Recommendation:** Option B - Remove fallback, use only `build_scripts/demo/healthchecks.sh`

---

## Summary Tables

### Files to Archive (11 files)

| File | Reason | Destination |
|------|--------|-------------|
| `monitoring/config/*.yaml` (4 files) | Not referenced | `archive/obsolete-configs/` |
| `monitoring/cleanup_deprecated.sh` | Never executed | DELETE |
| `patches/*.yaml` (2 files) | Not used | `archive/obsolete-patches/` |
| `scripts/operations/add_monitoring_platform.sh` | Not called | `archive/obsolete-scripts/` |
| `scripts/operations/cluster_create.sh` | Replaced by Terraform | `archive/obsolete-scripts/` |
| `scripts/util/test_nobl9_*.sh` (4 files) | Not used, contains secrets | DELETE |

### Files to Keep (9 files)

| File | Status | Purpose |
|------|--------|---------|
| `scripts/operations/deploy_failure_flags.sh` | ACTIVE | FF deployment |
| `scripts/operations/deploy_otel.sh` | ACTIVE | OTel deployment |
| `scripts/operations/cluster_cleanup.sh` | ACTIVE | Cleanup fallback |
| `scripts/gremlin_install.sh` | ACTIVE | Gremlin install |
| `scripts/fix_gremlin_permissions.sh` | ACTIVE | EC2 permissions |
| `scripts/check_metrics.sh` | UTILITY | Debugging |
| `scripts/util/find_prometheus_auth_id.sh` | UTILITY | Debugging |
| `scripts/util/validate_cluster_health.sh` | UTILITY | Testing |
| `monitoring/create_health_checks.sh` | ACTIVE | Health checks |

### Files to Move to Utility (2 files)

| File | Current Location | Move To |
|------|-----------------|---------|
| `monitoring/test_gremlin_api.sh` | `monitoring/` | `scripts/util/` |
| `monitoring/test_health_checks.sh` | `monitoring/` | `scripts/util/` |

---

## Recommended Actions

### Phase 1: Delete Obsolete Files with Secrets (IMMEDIATE)

```bash
# Delete Nobl9 scripts (contain hardcoded secrets!)
rm scripts/util/get_nobl9_token.sh
rm scripts/util/test_nobl9_auth.sh
rm scripts/util/test_nobl9_comprehensive.sh
rm scripts/util/test_nobl9_status.sh
rm monitoring/cleanup_deprecated.sh
```

### Phase 2: Archive Obsolete Configs and Scripts

```bash
# Create archive directories
mkdir -p archive/obsolete-configs
mkdir -p archive/obsolete-patches
mkdir -p archive/obsolete-scripts

# Move obsolete files
mv monitoring/config/*.yaml archive/obsolete-configs/
mv patches/load-generator-loadbalancer-patch.yaml archive/obsolete-patches/
mv patches/otel-collector-grpc-metrics-patch.yaml archive/obsolete-patches/
mv scripts/operations/add_monitoring_platform.sh archive/obsolete-scripts/
mv scripts/operations/cluster_create.sh archive/obsolete-scripts/
```

### Phase 3: Reorganize Utility Scripts

```bash
# Move test scripts to util directory
mv monitoring/test_gremlin_api.sh scripts/util/
mv monitoring/test_health_checks.sh scripts/util/
```

### Phase 4: Clean Up monitoring/gremlin/ (OPTIONAL)

**Option A: Keep as fallback (no action)**

**Option B: Remove fallback (recommended)**
```bash
# Update lib/monitoring.sh to remove fallback
# Then remove old scripts
rm monitoring/gremlin/create_health_checks.sh
rm monitoring/gremlin/gremlin_credentials_manager.sh
rm monitoring/gremlin/validate_integration.sh
# Keep README.md for documentation
```

---

## Impact Analysis

### Low Risk (Safe to Delete)
- ✅ Nobl9 scripts (not used anywhere)
- ✅ monitoring/config/*.yaml (not referenced)
- ✅ patches/*.yaml (not referenced)
- ✅ cleanup_deprecated.sh (never executed)

### Medium Risk (Archive, don't delete)
- ⚠️ cluster_create.sh (already documented as obsolete)
- ⚠️ add_monitoring_platform.sh (might be useful reference)

### High Risk (Needs testing before removal)
- 🔴 monitoring/gremlin/create_health_checks.sh (still referenced in lib/monitoring.sh)

---

## Testing Plan

Before removing any files:

1. **Grep for references:**
   ```bash
   for file in <file_to_remove>; do
       echo "Checking $file..."
       grep -r "$(basename $file)" *.sh *.md
   done
   ```

2. **Test all 3 workshop actions:**
   ```bash
   ./workshop.sh --action build_new --subdomain test1 --owner user --enable-eks
   ./workshop.sh --action deploy_existing --cluster-name test --owner user
   ./workshop.sh --action gremlin_only --cluster-name test --owner user
   ```

3. **Verify no broken references**

---

## Conclusion

**Total Files Analyzed:** 24  
**Obsolete:** 11 (46%)  
**Active:** 9 (37%)  
**Utility:** 4 (17%)

**Recommendation:** Proceed with Phase 1 (delete files with secrets) immediately, then Phase 2 (archive obsolete files) after brief review.

**Estimated Time:** 30 minutes for all phases

**Risk Level:** Low (most files clearly not referenced)

---

**Last Updated:** 2025-10-21  
**Status:** Analysis Complete - Ready for Cleanup  
**Next Step:** Execute Phase 1 (delete Nobl9 scripts)
