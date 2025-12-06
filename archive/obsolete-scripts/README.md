# Obsolete Operation Scripts

These scripts were archived on 2025-10-21 because their functionality has been replaced or is no longer needed.

## Files in This Archive

### `cluster_create.sh`
**Status:** Replaced by Terraform  
**Replacement:** `lib/terraform.sh` → `provision_infrastructure()`  
**Reason:** 
- Used eksctl (deprecated approach)
- Terraform now handles all infrastructure provisioning
- Not called by workshop.sh

**Reference:** See TESTING_CHECKLIST.md for deprecation notice

### `add_monitoring_platform.sh`
**Status:** Not used in workflow  
**Replacement:** `workshop.sh` → `setup_comprehensive_monitoring()`  
**Reason:**
- Monitoring platforms installed during initial deployment
- Not called by any active scripts
- Only mentioned in archived documentation

## Why Archived

Both scripts represent old approaches that have been superseded:

1. **cluster_create.sh** - Infrastructure as Code (Terraform) replaced imperative cluster creation
2. **add_monitoring_platform.sh** - Monitoring setup integrated into main workflow

## Verification

Neither script is called by workshop.sh or active workflows:
```bash
grep -r "cluster_create.sh" workshop.sh lib/*.sh  # No results
grep -r "add_monitoring_platform.sh" workshop.sh lib/*.sh  # No results
```

## Historical Value

These scripts may be useful for:
- Understanding the old deployment approach
- Reference for manual operations
- Troubleshooting legacy deployments

**Archived:** 2025-10-21  
**Safe to delete:** Yes (after verification period)  
**Recommendation:** Keep for 30 days, then delete
