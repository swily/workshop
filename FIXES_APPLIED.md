# Workshop Script Fixes Applied

## Summary

Fixed critical issues in workshop.sh and lib/terraform.sh that were causing "stale plan" errors and deployment failures.

## Issues Fixed

### 1. Stale Terraform Plan Error (CRITICAL)

**Problem:**
- `terraform_apply()` in `lib/terraform.sh` had broken two-phase apply logic
- First applied VPC module (which doesn't exist in sa_demo)
- Then tried to apply a plan created before VPC apply
- Result: "Saved plan is stale" error

**Root Cause:**
```bash
# OLD CODE (lines 312-330 in lib/terraform.sh)
# First, apply VPC module if it exists (to resolve for_each dependencies)
if terraform state list 2>/dev/null | grep -q "module.demo.module.vpc"; then
    log_info "VPC already exists, proceeding with full apply"
else
    log_info "First deployment detected - applying VPC module first"
    terraform apply -target=module.demo.module.vpc -auto-approve  # <-- Changes state
    log_success "VPC module applied successfully"
fi

# Now apply everything
if [[ -f "tfplan" ]]; then
    terraform apply tfplan  # <-- Plan is now stale!
```

**Fix:**
```bash
# NEW CODE
terraform_apply() {
    local workspace_dir="$1"
    log_info "Applying Terraform configuration"
    cd "$workspace_dir" || return 1
    
    # Simple single-phase apply
    # No need for VPC targeting - sa_demo uses existing shared VPC
    terraform apply -auto-approve
}
```

**Files Changed:**
- `/Users/seanwiley/workshop/lib/terraform.sh` (lines 305-315)

### 2. Unnecessary Plan Step

**Problem:**
- `provision_infrastructure()` called both `terraform_plan()` and `terraform_apply()`
- Plan was created but then ignored by the apply logic
- Wasted time and created confusion

**Fix:**
Removed separate plan step - `terraform apply` does its own planning automatically.

**Files Changed:**
- `/Users/seanwiley/workshop/workshop.sh` (line 202)

### 3. Kubeconfig Update Timing

**Problem:**
- Tried to update kubeconfig before `CLUSTER_NAME` was set
- `CLUSTER_NAME` comes from Terraform outputs, not available until after apply

**Fix:**
Added check that `CLUSTER_NAME` is set before calling `update_kubeconfig()`:

```bash
# Update kubeconfig (CLUSTER_NAME now set by export_terraform_outputs)
if [[ -n "$CLUSTER_NAME" ]]; then
    update_kubeconfig "$CLUSTER_NAME" "$AWS_REGION"
else
    log_error "CLUSTER_NAME not set after Terraform apply"
    return 1
fi
```

**Files Changed:**
- `/Users/seanwiley/workshop/workshop.sh` (lines 215-221)

## Previous Fixes (From Earlier in Session)

### 4. S3 Backend Conflicts

**Problem:**
- Shared S3 bucket `gremlin-terraform-state-us-east-2` caused access denied errors
- Multiple users couldn't use same bucket

**Fix:**
- Created owner-specific bucket names: `gremlin-tf-state-{owner}-us-east-2`
- Created owner-specific DynamoDB tables: `gremlin-terraform-locks-{owner}`

**Files Changed:**
- `/Users/seanwiley/workshop/lib/terraform.sh` (lines 28-31, 265-267)

### 5. SSH Git URL Issues

**Problem:**
- `sa_demo/main.tf` used SSH Git URLs for module sources
- Required GitHub SSH keys to be configured
- Failed with "Permission denied (publickey)" errors

**Fix:**
Changed all module sources to relative local paths:
- `git@github.com:.../dns` → `../dns`
- `git@github.com:.../iam` → `../iam`
- `git@github.com:.../alb` → `../alb`
- `git@github.com:.../demo_ecs_fargate` → `../demo_ecs_fargate`

**Files Changed:**
- `/Users/seanwiley/gremform/fictional-computing-machine/terraform/modules/sa_demo/main.tf`

### 6. Missing Terraform Outputs

**Problem:**
- `sa_demo` module had no `outputs.tf` file
- `demo_eks` module had no outputs for `cluster_name` and `cluster_endpoint`
- Workshop script expected these outputs

**Fix:**
Created output files:
- `/Users/seanwiley/gremform/fictional-computing-machine/terraform/modules/sa_demo/outputs.tf`
- `/Users/seanwiley/gremform/fictional-computing-machine/terraform/modules/demo_eks/outputs.tf`

### 7. Wildcard Certificate Variable

**Problem:**
- Workshop passed `wildcard_certificate_arn` to `sa_demo` module
- Module doesn't accept this variable (creates its own cert)

**Fix:**
Removed `wildcard_certificate_arn` from:
- Module invocation in generated `main.tf`
- Variable definition in generated `variables.tf`

**Files Changed:**
- `/Users/seanwiley/workshop/lib/terraform.sh` (lines 129-140, 250-254)

## Testing Status

✅ Terraform init: Success  
✅ Terraform validate: Success  
⏳ Terraform apply: Running (expected 15-20 minutes)

## How to Run

```bash
cd /Users/seanwiley/workshop

FCM_LOCAL_PATH=/Users/seanwiley/gremform/fictional-computing-machine \
./workshop.sh \
  --subdomain seanw \
  --owner sean.wiley \
  --enable-eks \
  --action build_new
```

## Monitoring Progress

```bash
# Watch the log
tail -f /tmp/workshop-fixed.log

# Check Terraform state
cd /Users/seanwiley/terraform/workspace/seanw
terraform state list
```

## Expected Outcome

After 15-20 minutes:
- EKS cluster `seanw-eks` created
- ALB with wildcard cert for `*.seanw.gremlinpoc.com`
- Route53 DNS records
- OpenTelemetry Demo deployed
- Prometheus + Grafana installed
- Gremlin agent running

URLs:
- Frontend: `https://demo-frontend.seanw.gremlinpoc.com`
- Grafana: `https://monitoring.seanw.gremlinpoc.com`
