# Implementation Checklist: Fictional Computing Machine + Workshop Merge

## Phase 1: Terraform Updates ✓

### DNS Module
- [ ] Add `demo-frontend.{subdomain}.gremlinpoc.com` Route53 record
- [ ] Add `monitoring.{subdomain}.gremlinpoc.com` Route53 record
- [ ] Add outputs for workshop-compatible hostnames
- [ ] Test DNS module changes

### ALB Module
- [ ] Create target group for OpenTelemetry Demo (port 8080)
- [ ] Create target group for monitoring (port 80)
- [ ] Add listener rule for demo frontend hostname
- [ ] Add listener rule for monitoring hostname
- [ ] Add target group ARN outputs
- [ ] Test ALB module changes

### SA Demo Module
- [ ] Create `outputs.tf` with all workshop-compatible outputs
- [ ] Add `data.aws_region.current` data source
- [ ] Test output values

### Backend Configuration
- [ ] Create S3 bucket: `gremlin-terraform-state-us-east-2`
- [ ] Enable S3 versioning
- [ ] Create DynamoDB table: `gremlin-terraform-locks`
- [ ] Update `terraform.tf` to use S3 backend
- [ ] Test backend migration

---

## Phase 2: Workshop Integration ✓

### New Files
- [ ] Create `lib/terraform.sh` with wrapper functions
- [ ] Create `tests/test_terraform_integration.sh`
- [ ] Create `tests/test_full_deployment.sh`

### workshop.sh Updates
- [ ] Source `lib/terraform.sh`
- [ ] Update `parse_arguments()` for Terraform args
- [ ] Add `provision_infrastructure()` function
- [ ] Update `main()` to handle Terraform workflow
- [ ] Add `--terraform-dir` argument
- [ ] Test workshop.sh changes

### Gremlin Installation
- [ ] Update `scripts/gremlin_install.sh` to use Secrets Manager
- [ ] Remove hardcoded credential handling
- [ ] Add fallback to fetch from Secrets Manager
- [ ] Test Gremlin installation

### Health Checks
- [ ] Update `config/gremlin/healthchecks.sh` for dynamic hostnames
- [ ] Use `$SUBDOMAIN` variable for DNS names
- [ ] Add subdomain/owner tags to health checks
- [ ] Test health check creation

---

## Phase 3: Testing ✓

### Unit Tests
- [ ] Test Terraform output parsing
- [ ] Test Secrets Manager access
- [ ] Test environment variable exports
- [ ] Run `tests/test_terraform_integration.sh`

### Integration Tests
- [ ] Test full `create_new` workflow
- [ ] Test `deploy_existing` workflow
- [ ] Test `destroy` workflow
- [ ] Validate DNS records created
- [ ] Validate ALB listener rules
- [ ] Validate OpenTelemetry Demo deployment
- [ ] Validate Gremlin agent installation
- [ ] Run `tests/test_full_deployment.sh`

### Manual Validation
- [ ] Deploy to test subdomain
- [ ] Access demo frontend URL
- [ ] Access monitoring URL
- [ ] Check Gremlin UI for agent
- [ ] Run Gremlin experiment
- [ ] Verify health checks working
- [ ] Destroy test environment

---

## Phase 4: Documentation ✓

### README Updates
- [ ] Add Terraform prerequisites
- [ ] Add Secrets Manager setup instructions
- [ ] Update deployment examples
- [ ] Add troubleshooting section
- [ ] Update architecture diagram

### Migration Guide
- [ ] Document breaking changes
- [ ] Provide before/after examples
- [ ] Add migration steps for existing users
- [ ] Document DNS name changes

### API Documentation
- [ ] Document all new CLI arguments
- [ ] Document Terraform outputs
- [ ] Document environment variables
- [ ] Add examples for each workflow

---

## Phase 5: Cleanup ✓

### Remove Deprecated Files
- [ ] Remove eksctl configs (if any)
- [ ] Remove manual ALB creation scripts
- [ ] Remove manual DNS scripts
- [ ] Update `.gitignore` for Terraform files

### Code Cleanup
- [ ] Remove unused functions
- [ ] Remove hardcoded values
- [ ] Add error handling
- [ ] Add input validation

---

## Validation Checklist

### Infrastructure
- [ ] EKS cluster created with correct name: `{subdomain}-eks`
- [ ] ALB created and healthy
- [ ] DNS records resolve correctly
- [ ] Target groups attached to ALB
- [ ] IAM roles have Secrets Manager permissions

### Application
- [ ] OpenTelemetry Demo deployed
- [ ] All services running
- [ ] Monitoring platform deployed
- [ ] Gremlin agent installed
- [ ] Health checks created

### Integration
- [ ] Frontend accessible via `demo-frontend.{subdomain}.gremlinpoc.com`
- [ ] Monitoring accessible via `monitoring.{subdomain}.gremlinpoc.com`
- [ ] Gremlin experiments work
- [ ] Health checks reporting correctly
- [ ] Logs visible in CloudWatch

---

## Rollback Plan

If issues occur:

1. **Terraform state backup:**
   ```bash
   aws s3 cp s3://gremlin-terraform-state-us-east-2/demo-platform/terraform.tfstate ./backup.tfstate
   ```

2. **Restore previous workshop.sh:**
   ```bash
   git checkout main -- workshop.sh
   ```

3. **Manual cleanup:**
   ```bash
   terraform destroy -auto-approve
   ```

---

## Success Criteria

✅ Single command deploys complete environment
✅ Infrastructure managed by Terraform
✅ Applications deployed by workshop scripts
✅ DNS names work with health checks
✅ Gremlin credentials from Secrets Manager
✅ Idempotent deployments
✅ Clean teardown with `terraform destroy`
✅ All tests passing
✅ Documentation complete
