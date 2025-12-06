# Pre-Testing Tasks - Must Complete Before Testing

## Overview

These tasks MUST be completed before running any deployment tests. They ensure the system uses the correct DNS names, URLs, and configurations for the new Terraform-based infrastructure.

---

## 🔴 CRITICAL: DNS Name Alignment

### Problem
The health checks script uses **old naming convention**:
- Old: `{cluster-name}-frontend.gremlinpoc.com`
- New: `demo-frontend.{subdomain}.gremlinpoc.com`

### Files That Need Updates

#### 1. `/build_scripts/demo/healthchecks.sh` ⚠️

**Current (WRONG):**
```bash
FRONTEND_DNS="$CLUSTER_NAME-frontend.gremlinpoc.com"
GRAFANA_DNS="$CLUSTER_NAME-grafana.gremlinpoc.com"
PROMETHEUS_DNS="$CLUSTER_NAME-prometheus.gremlinpoc.com:9090"
```

**Should Be (CORRECT):**
```bash
FRONTEND_DNS="demo-frontend.${SUBDOMAIN}.gremlinpoc.com"
GRAFANA_DNS="monitoring.${SUBDOMAIN}.gremlinpoc.com"
PROMETHEUS_DNS="monitoring.${SUBDOMAIN}.gremlinpoc.com/prometheus"
```

**Lines to Update:** 240-242

---

## 📋 Complete Task List

### Task 1: Update Health Checks DNS Names ⚠️ CRITICAL

**File:** `/build_scripts/demo/healthchecks.sh`

**Changes Needed:**

1. **Add SUBDOMAIN variable support** (around line 27)
   ```bash
   # Add after CLUSTER_NAME
   SUBDOMAIN="${SUBDOMAIN:-}"
   ```

2. **Update DNS name construction** (lines 240-242)
   ```bash
   # OLD:
   FRONTEND_DNS=$(jq -r --arg cluster "$CLUSTER_NAME" '.dns_mappings | to_entries[] | select(.value == "frontend") | .key' "$state_file" 2>/dev/null || echo "$CLUSTER_NAME-frontend.gremlinpoc.com")
   GRAFANA_DNS=$(jq -r --arg cluster "$CLUSTER_NAME" '.dns_mappings | to_entries[] | select(.value == "grafana_monitoring") | .key' "$state_file" 2>/dev/null || echo "$CLUSTER_NAME-grafana.gremlinpoc.com")
   PROMETHEUS_DNS=$(jq -r --arg cluster "$CLUSTER_NAME" '.dns_mappings | to_entries[] | select(.value == "prometheus") | .key' "$state_file" 2>/dev/null || echo "$CLUSTER_NAME-prometheus.gremlinpoc.com:9090")
   
   # NEW:
   # Use SUBDOMAIN if available, fallback to CLUSTER_NAME for backwards compatibility
   local dns_prefix="${SUBDOMAIN:-${CLUSTER_NAME}}"
   FRONTEND_DNS=$(jq -r --arg cluster "$CLUSTER_NAME" '.dns_mappings | to_entries[] | select(.value == "frontend") | .key' "$state_file" 2>/dev/null || echo "demo-frontend.${dns_prefix}.gremlinpoc.com")
   GRAFANA_DNS=$(jq -r --arg cluster "$CLUSTER_NAME" '.dns_mappings | to_entries[] | select(.value == "grafana_monitoring") | .key' "$state_file" 2>/dev/null || echo "monitoring.${dns_prefix}.gremlinpoc.com")
   PROMETHEUS_DNS=$(jq -r --arg cluster "$CLUSTER_NAME" '.dns_mappings | to_entries[] | select(.value == "prometheus") | .key' "$state_file" 2>/dev/null || echo "monitoring.${dns_prefix}.gremlinpoc.com/prometheus")
   ```

3. **Update argument parsing** (add --subdomain flag around line 71)
   ```bash
   --subdomain)
       SUBDOMAIN="$2"
       shift 2
       ;;
   ```

**Estimated Time:** 10 minutes

---

### Task 2: Update Service Annotations Script ⚠️ CRITICAL

**File:** Check if `scripts/gremlin_annotations.sh` or similar exists

**Purpose:** Ensure Gremlin service discovery uses correct service names

**Check for:**
- Service annotation logic
- Service ID generation
- Namespace handling

**Action:**
```bash
# Search for annotation scripts
find /Users/seanwiley/workshop -name "*annotation*" -o -name "*gremlin*service*"
```

**Estimated Time:** 5 minutes to check, 10 minutes to update if needed

---

### Task 3: Verify Workshop.sh Calls Health Checks Correctly ⚠️ IMPORTANT

**File:** `/workshop.sh`

**Check:**
1. Does `setup_gremlin_monitoring()` pass `SUBDOMAIN` to health checks?
2. Does it export `SUBDOMAIN` before calling health checks?

**Search for:**
```bash
grep -n "healthchecks.sh" /Users/seanwiley/workshop/workshop.sh
grep -n "setup_gremlin_monitoring" /Users/seanwiley/workshop/workshop.sh
```

**Expected:**
```bash
# In setup_gremlin_monitoring function
export SUBDOMAIN
export CLUSTER_NAME
"$SCRIPT_DIR/build_scripts/demo/healthchecks.sh" --platform all --subdomain "$SUBDOMAIN"
```

**Estimated Time:** 5 minutes to check, 5 minutes to fix if needed

---

### Task 4: Update Gremlin Install Script ✅ VERIFY

**File:** `/scripts/gremlin_install.sh`

**Check:**
- Does it use credentials from Secrets Manager?
- Does it handle `GREMLIN_TEAM_ID`, `GREMLIN_TEAM_CERTIFICATE`, `GREMLIN_TEAM_PRIVATE_KEY` env vars?

**Expected:** Should already be using environment variables from `fetch_gremlin_credentials()`

**Action:** Quick verification only

**Estimated Time:** 3 minutes

---

### Task 5: Verify Terraform Outputs Match Expected Names ⚠️ CRITICAL

**File:** `/lib/terraform.sh` (lines 276-288)

**Check:** Do the output names match what fictional-computing-machine provides?

**Expected Outputs from FCM:**
- `cluster_name`
- `cluster_endpoint`
- `cluster_region`
- `alb_dns_name`
- `demo_frontend_url`
- `monitoring_url`
- `otel_demo_target_group_arn`
- `monitoring_target_group_arn`
- `gremlin_team_id_arn`
- `gremlin_team_certificate_arn`
- `gremlin_team_private_key_arn`
- `subdomain`
- `owner`

**Action:**
1. Check fictional-computing-machine repo for actual output names
2. Update `export_terraform_outputs()` if names don't match

**Estimated Time:** 10 minutes to verify, 5 minutes to fix if needed

---

### Task 6: Add SUBDOMAIN Export in provision_infrastructure() ⚠️ IMPORTANT

**File:** `/workshop.sh`

**Location:** In `provision_infrastructure()` function (around line 204)

**Add after `export_terraform_outputs()`:**
```bash
# Ensure SUBDOMAIN is exported for downstream scripts
export SUBDOMAIN="$subdomain"
export OWNER="$owner"
```

**Why:** Health checks and other scripts need these variables

**Estimated Time:** 2 minutes

---

### Task 7: Update configure_cluster_base() Call ⚠️ CHECK

**File:** `/workshop.sh` (line 223)

**Current:**
```bash
configure_cluster_base "$CLUSTER_NAME" "$INSTALL_ISTIO" "$MONITORING_PLATFORM"
```

**Check:** Does `configure_cluster_base()` need SUBDOMAIN or OWNER?

**Action:** Review function signature and update if needed

**Estimated Time:** 5 minutes

---

### Task 8: Verify Gremlin Service Annotation Logic ⚠️ IMPORTANT

**Purpose:** Ensure all OTel Demo services get annotated with `gremlin.com/service-id`

**Files to Check:**
- `/build_scripts/demo/healthchecks.sh` (annotation logic)
- Any script that annotates services

**Expected Behavior:**
```bash
# Should annotate all services in otel-demo namespace
kubectl annotate svc -n otel-demo \
    opentelemetry-demo-checkoutservice \
    gremlin.com/service-id=checkout-service
```

**Action:** Verify annotation logic exists and works with new naming

**Estimated Time:** 10 minutes

---

### Task 9: Check for Hardcoded Cluster Names ⚠️ CLEANUP

**Action:**
```bash
# Search for hardcoded cluster names
grep -r "current-workshop\|test-cluster\|demo-cluster" /Users/seanwiley/workshop/scripts/ /Users/seanwiley/workshop/build_scripts/
```

**Fix:** Replace with `$CLUSTER_NAME` or `$SUBDOMAIN` variables

**Estimated Time:** 10 minutes

---

### Task 10: Remove or Mark Obsolete Files ⚠️ OPTIONAL

**Files to Consider:**

1. **`/scripts/operations/cluster_create.sh`**
   - Status: Obsolete (replaced by Terraform)
   - Action: Add deprecation notice or delete

2. **Search for `.eksctl.yaml` files**
   ```bash
   find /Users/seanwiley/workshop -name "*.eksctl.yaml" -o -name "*eksctl*"
   ```
   - Action: Delete if found

3. **Old cluster state files**
   ```bash
   find /Users/seanwiley/workshop -name "cluster-state.json"
   ```
   - Action: Document or remove

**Estimated Time:** 15 minutes

---

## 📊 Task Priority Matrix

| Priority | Task | Time | Blocking? |
|----------|------|------|-----------|
| 🔴 **P0** | Update health checks DNS names | 10 min | YES |
| 🔴 **P0** | Verify Terraform outputs | 15 min | YES |
| 🟡 **P1** | Add SUBDOMAIN export | 2 min | YES |
| 🟡 **P1** | Update workshop.sh health check call | 10 min | YES |
| 🟡 **P1** | Verify service annotations | 10 min | MAYBE |
| 🟢 **P2** | Check configure_cluster_base | 5 min | NO |
| 🟢 **P2** | Verify gremlin_install.sh | 3 min | NO |
| 🟢 **P2** | Check hardcoded names | 10 min | NO |
| ⚪ **P3** | Remove obsolete files | 15 min | NO |

**Total Critical Path Time:** ~37 minutes  
**Total All Tasks:** ~80 minutes

---

## ✅ Completion Checklist

Before you can test, verify:

- [ ] Health checks script uses `demo-frontend.${SUBDOMAIN}.gremlinpoc.com`
- [ ] Health checks script uses `monitoring.${SUBDOMAIN}.gremlinpoc.com`
- [ ] Health checks script accepts `--subdomain` flag
- [ ] `workshop.sh` exports `SUBDOMAIN` before calling health checks
- [ ] `provision_infrastructure()` exports `SUBDOMAIN` and `OWNER`
- [ ] Terraform output names match fictional-computing-machine module
- [ ] Service annotation logic exists and works
- [ ] No hardcoded cluster names in critical paths
- [ ] Gremlin install script uses environment variables
- [ ] All scripts use consistent naming convention

---

## 🧪 Quick Validation Test

After completing tasks, run this to validate:

```bash
# Set test variables
export SUBDOMAIN="test"
export OWNER="test.user"
export CLUSTER_NAME="test-eks"

# Test health checks DNS generation (dry run)
cd /Users/seanwiley/workshop
./build_scripts/demo/healthchecks.sh \
    --subdomain test \
    --cluster-name test-eks \
    --dry-run \
    --platform prometheus

# Expected output should show:
# - demo-frontend.test.gremlinpoc.com
# - monitoring.test.gremlinpoc.com
```

---

## 🎯 Success Criteria

You're ready to test when:

1. ✅ All P0 tasks completed
2. ✅ All P1 tasks completed
3. ✅ Quick validation test passes
4. ✅ No hardcoded DNS names in critical path
5. ✅ All scripts use `$SUBDOMAIN` consistently

---

## 📝 Implementation Notes

### DNS Naming Convention

**New Standard:**
```
Frontend:    demo-frontend.{subdomain}.gremlinpoc.com
Monitoring:  monitoring.{subdomain}.gremlinpoc.com
Prometheus:  monitoring.{subdomain}.gremlinpoc.com/prometheus
Grafana:     monitoring.{subdomain}.gremlinpoc.com/grafana
```

**Backwards Compatibility:**
```bash
# Use SUBDOMAIN if available, fallback to CLUSTER_NAME
local dns_prefix="${SUBDOMAIN:-${CLUSTER_NAME}}"
```

### Environment Variables

**Must be exported before calling scripts:**
```bash
export SUBDOMAIN="alexs"
export OWNER="alex.smith"
export CLUSTER_NAME="alexs-eks"
export AWS_REGION="us-east-2"
export GREMLIN_TEAM_ID="..."
export GREMLIN_TEAM_CERTIFICATE="..."
export GREMLIN_TEAM_PRIVATE_KEY="..."
```

---

## 🚀 Next Steps After Completion

Once all tasks are done:

1. Commit changes
2. Run dry-run test
3. Proceed to full deployment test
4. Update TESTING_CHECKLIST.md with results
