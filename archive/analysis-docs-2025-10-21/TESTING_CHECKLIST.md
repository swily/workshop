# Testing Checklist - Terraform Integration

## Current Status: Ready for Testing ✅

All core implementation is complete. The system is ready for end-to-end testing.

---

## ✅ Completed Implementation

### Core Terraform Integration
- [x] Created `lib/terraform.sh` with all wrapper functions
- [x] Single module reference to fictional-computing-machine
- [x] Workspace generation per subdomain
- [x] Terraform init/plan/apply/destroy functions
- [x] Output export to environment variables
- [x] Gremlin credential fetching from Secrets Manager
- [x] Owner-based credential auto-resolution

### Workshop Script Updates
- [x] Updated argument parsing for Terraform parameters
- [x] Added `provision_infrastructure()` function
- [x] Integrated `configure_cluster_base()` call
- [x] Updated cleanup to use `terraform destroy`
- [x] Maintained backwards compatibility with legacy args
- [x] Added validation for required parameters

### Documentation
- [x] Comprehensive README with user workflows
- [x] Flag explanations and examples
- [x] Credential management guide
- [x] Troubleshooting section
- [x] Architecture overview
- [x] Implementation summary document

### Code Cleanup
- [x] Removed obsolete `create_cluster()` function
- [x] Removed obsolete `cleanup_cloudformation_stacks()`
- [x] Removed obsolete `cleanup_iam_resources()`
- [x] Removed obsolete `patch_consolidated_ingress_dns_tls()`
- [x] Removed ACM certificate auto-detection
- [x] Added comments explaining Terraform replacement

---

## ⚠️ Files That Should Be Cleaned Up (Optional)

These files are now obsolete but kept for backwards compatibility:

### 1. `scripts/operations/cluster_create.sh`
**Status:** Obsolete (replaced by Terraform)  
**Used by:** Nothing (workshop.sh now calls `provision_infrastructure()`)  
**Action:** Can be deleted or marked as deprecated  
**Risk:** Low - not called by main workflow

### 2. Legacy eksctl configuration files
**Status:** May exist in repo  
**Action:** Search for and remove `.eksctl.yaml` or similar files

---

## 🧪 Testing Plan

### Phase 1: Dry Run Testing (Safe)

```bash
# Test workspace generation
./workshop.sh \
    --subdomain test-dry \
    --owner test.user \
    --enable-eks \
    --dry-run \
    --action create_new

# Expected: Should generate workspace files without running terraform
# Check: terraform/workspace/test-dry/main.tf should exist
```

### Phase 2: Credential Resolution Testing

```bash
# Test 1: Owner-based lookup (requires secrets in AWS)
./workshop.sh \
    --subdomain test1 \
    --owner your.name \
    --enable-eks \
    --action create_new

# Expected: Should auto-resolve credentials from {owner}/gremlin_* secrets

# Test 2: Environment variables
export GREMLIN_TEAM_ID="test-id"
export GREMLIN_TEAM_CERTIFICATE="test-cert"
export GREMLIN_TEAM_PRIVATE_KEY="test-key"

./workshop.sh \
    --subdomain test2 \
    --owner test.user \
    --enable-eks \
    --action create_new

# Expected: Should use environment variables

# Test 3: Explicit ARNs
./workshop.sh \
    --subdomain test3 \
    --owner test.user \
    --enable-eks \
    --gremlin-team-id-arn "arn:aws:secretsmanager:..." \
    --gremlin-team-certificate-arn "arn:aws:secretsmanager:..." \
    --gremlin-team-private-key-arn "arn:aws:secretsmanager:..." \
    --action create_new

# Expected: Should use provided ARNs
```

### Phase 3: Full Deployment Testing

```bash
# Prerequisites:
# 1. Store credentials in Secrets Manager
OWNER="your.name"
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_id" \
    --secret-string "YOUR_TEAM_ID" \
    --region us-east-2

aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_certificate" \
    --secret-string "$(cat team-cert.pem)" \
    --region us-east-2

aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_private_key" \
    --secret-string "$(cat team-key.pem)" \
    --region us-east-2

# 2. Run full deployment
./workshop.sh \
    --subdomain test-full \
    --owner your.name \
    --enable-eks \
    --monitoring prometheus \
    --action create_new

# Expected timeline: 15-20 minutes
# Expected outputs:
# - EKS cluster created
# - ALB provisioned
# - DNS records created
# - OpenTelemetry Demo deployed
# - Gremlin agent installed
# - Monitoring stack deployed
```

### Phase 4: Validation Testing

```bash
# After deployment completes:

# 1. Check Terraform state
cd terraform/workspace/test-full
terraform show

# 2. Check cluster access
kubectl get nodes
kubectl get pods -A

# 3. Check services
kubectl get svc -n otel-demo
kubectl get svc -n monitoring
kubectl get svc -n gremlin

# 4. Check DNS
nslookup demo-frontend.test-full.gremlinpoc.com
nslookup monitoring.test-full.gremlinpoc.com

# 5. Check ALB
kubectl get ingress -A

# 6. Test frontend access
curl https://demo-frontend.test-full.gremlinpoc.com

# 7. Check Gremlin UI
# Go to https://app.gremlin.com
# Verify services are discovered
# Verify health checks are created
```

### Phase 5: Update Testing

```bash
# Test deploy_existing action
./workshop.sh \
    --subdomain test-full \
    --action deploy_existing

# Expected: Should load existing Terraform outputs and redeploy apps
```

### Phase 6: Cleanup Testing

```bash
# Test cleanup
./workshop.sh \
    --subdomain test-full \
    --action cleanup

# Expected:
# - Kubernetes resources deleted
# - Terraform destroy runs
# - All AWS resources removed
# - Workspace directory remains (for state history)

# Verify cleanup
aws eks list-clusters --region us-east-2 | grep test-full
# Should return nothing

aws elbv2 describe-load-balancers --region us-east-2 | grep test-full
# Should return nothing
```

---

## 🔍 Known Issues to Watch For

### 1. Terraform State Backend
**Issue:** S3 bucket and DynamoDB table must exist  
**Check:** `gremlin-terraform-state-us-east-2` bucket exists  
**Fix:** Create bucket if missing

### 2. AWS Account ID Resolution
**Issue:** `get_aws_account_id()` might fail if AWS CLI not configured  
**Check:** `aws sts get-caller-identity` works  
**Fix:** Run `aws configure`

### 3. SSH Key for Git
**Issue:** Terraform needs SSH access to GitHub  
**Check:** `ssh -T git@github.com` works  
**Fix:** Add SSH key to GitHub

### 4. Secrets Manager ARN Format
**Issue:** ARNs might have version suffixes (e.g., `-AbCdEf`)  
**Check:** Secrets exist without version suffix in ARN  
**Fix:** Use exact ARN from AWS Console

### 5. fictional-computing-machine Module Path
**Issue:** Module path might change in FCM repo  
**Check:** `terraform/modules/sa_demo` exists in FCM repo  
**Fix:** Update `FCM_MODULE_PATH` in `lib/terraform.sh`

---

## 🚨 Critical Pre-Testing Checks

Before running any tests:

```bash
# 1. Check AWS credentials
aws sts get-caller-identity

# 2. Check Terraform version
terraform version
# Should be >= 1.13

# 3. Check GitHub SSH access
ssh -T git@github.com
# Should say: "Hi username! You've successfully authenticated"

# 4. Check S3 backend exists
aws s3 ls s3://gremlin-terraform-state-us-east-2

# 5. Check DynamoDB table exists
aws dynamodb describe-table --table-name gremlin-terraform-locks

# 6. Check Route53 hosted zone
aws route53 list-hosted-zones --query "HostedZones[?Name=='gremlinpoc.com.']"

# 7. Verify fictional-computing-machine access
git ls-remote git@github.com:gremlin/fictional-computing-machine.git
```

---

## 📋 Post-Testing Validation

After successful deployment:

### Infrastructure Validation
- [ ] EKS cluster exists and is ACTIVE
- [ ] Node group has correct number of nodes
- [ ] ALB is provisioned and healthy
- [ ] Target groups have healthy targets
- [ ] Route53 DNS records exist
- [ ] Security groups allow traffic
- [ ] IAM roles have correct permissions

### Application Validation
- [ ] All OTel Demo pods are Running
- [ ] All monitoring pods are Running
- [ ] Gremlin agent pod is Running
- [ ] Services have endpoints
- [ ] Ingresses have ALB addresses

### Gremlin Integration Validation
- [ ] Services appear in Gremlin UI
- [ ] Services have correct annotations
- [ ] Health checks are created
- [ ] Health checks are passing
- [ ] Failure Flags (if enabled) are visible

### DNS/TLS Validation
- [ ] Frontend URL resolves
- [ ] Monitoring URL resolves
- [ ] HTTPS works (if TLS enabled)
- [ ] Certificate is valid

---

## 🎯 Success Criteria

The integration is successful if:

1. ✅ Workspace generation works without errors
2. ✅ Terraform init/plan/apply complete successfully
3. ✅ All infrastructure is created (EKS, ALB, DNS, IAM)
4. ✅ Applications deploy successfully
5. ✅ Gremlin integration works (services discovered, health checks created)
6. ✅ URLs are accessible
7. ✅ Cleanup removes all resources
8. ✅ No manual intervention required

---

## 🔧 Debugging Commands

If something goes wrong:

```bash
# Check Terraform logs
cd terraform/workspace/{subdomain}
terraform show
terraform state list

# Check Kubernetes events
kubectl get events -A --sort-by='.lastTimestamp'

# Check pod logs
kubectl logs -n otel-demo -l app.kubernetes.io/name=opentelemetry-demo --tail=100

# Check Gremlin agent logs
kubectl logs -n gremlin -l app=gremlin --tail=100

# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=100

# Check Terraform state
cd terraform/workspace/{subdomain}
terraform state show module.demo

# Force refresh outputs
terraform refresh
terraform output
```

---

## 📝 Testing Notes Template

Use this template to document your testing:

```
## Test Run: [Date/Time]

**Subdomain:** test-xyz
**Owner:** your.name
**Region:** us-east-2

### Pre-Test Checks
- [ ] AWS credentials valid
- [ ] Terraform version correct
- [ ] GitHub SSH access working
- [ ] Secrets Manager credentials exist

### Test Execution
- Start time: [TIME]
- Command: [FULL COMMAND]
- End time: [TIME]
- Duration: [MINUTES]

### Results
- [ ] Workspace created
- [ ] Terraform init successful
- [ ] Terraform plan successful
- [ ] Terraform apply successful
- [ ] Cluster accessible
- [ ] Applications deployed
- [ ] Gremlin integrated
- [ ] URLs accessible

### Issues Encountered
[List any issues]

### Resolution
[How issues were resolved]

### Cleanup
- [ ] Cleanup command ran
- [ ] All resources removed
- [ ] Verified in AWS Console
```

---

## Next Steps After Testing

Once testing is complete and successful:

1. **Tag Release:** Create a git tag for this version
2. **Update Documentation:** Add any lessons learned
3. **Create Examples:** Add example commands to README
4. **Train Users:** Share documentation with team
5. **Monitor Usage:** Track any issues in production use
