# Fictional Computing Machine + Workshop Merge Analysis

## Executive Summary

**Goal:** Merge infrastructure (fictional-computing-machine Terraform) with application layer (workshop scripts) for unified deployment.

**Key Decision:** Use Terraform for infrastructure, keep workshop scripts for application deployment.

---

## 1. Current State

### Fictional Computing Machine
- **Tool:** Terraform modules
- **Manages:** EKS cluster, ALB, Route53, IAM
- **Naming:** `{subdomain}-eks`, `eks-fargate.{subdomain}.gremlinpoc.com`
- **Credentials:** AWS Secrets Manager ARNs
- **State:** GCS backend

### Workshop
- **Tool:** Bash scripts + eksctl
- **Manages:** OpenTelemetry Demo, monitoring, Gremlin
- **Naming:** `demo-frontend.gremlinpoc.com`, `monitoring.gremlinpoc.com`
- **Credentials:** CLI arguments
- **State:** None

---

## 2. Major Conflicts

| Issue | Fictional-Computing-Machine | Workshop | Resolution |
|-------|----------------------------|----------|------------|
| **Infrastructure Tool** | Terraform | eksctl | Use Terraform only |
| **DNS Names** | `eks-fargate.{subdomain}` | `demo-frontend` | Add workshop DNS to Terraform |
| **Credentials** | Secrets Manager ARNs | CLI args | Fetch from Secrets Manager |
| **State** | GCS | None | Switch to S3 backend |
| **Cluster Name** | `{subdomain}-eks` | User-provided | Use Terraform naming |

---

## 3. Integration Architecture

```
User runs: ./deploy.sh --subdomain alexs --owner alex.smith --enable-eks

    ↓

[Terraform Layer]
- Creates EKS cluster: alexs-eks
- Creates ALB + DNS: demo-frontend.alexs.gremlinpoc.com
- Outputs: cluster_name, alb_dns, secret ARNs

    ↓

[Workshop Layer]
- Reads Terraform outputs
- Creates namespaces (otel-demo, monitoring, gremlin)
- Deploys OpenTelemetry Demo
- Installs monitoring + Gremlin
```

---

## 4. Required Changes

### Terraform Modules

**DNS Module (`terraform/modules/dns/main.tf`):**
```hcl
# Add workshop-compatible DNS records
resource "aws_route53_record" "demo_frontend" {
  zone_id = data.aws_route53_zone.subdomain.id
  name    = "demo-frontend.${var.subdomain}.gremlinpoc.com"
  type    = "CNAME"
  ttl     = 60
  records = [data.aws_lb.alb.dns_name]
}

resource "aws_route53_record" "monitoring" {
  zone_id = data.aws_route53_zone.subdomain.id
  name    = "monitoring.${var.subdomain}.gremlinpoc.com"
  type    = "CNAME"
  ttl     = 60
  records = [data.aws_lb.alb.dns_name]
}
```

**Outputs (`terraform/environments/us-east-2/outputs.tf`):**
```hcl
output "cluster_name" {
  value = module.demo.cluster_name
}

output "alb_dns_name" {
  value = module.demo.alb_dns_name
}

output "demo_frontend_url" {
  value = "https://demo-frontend.${var.subdomain}.gremlinpoc.com"
}

output "gremlin_team_id_arn" {
  value     = var.gremlin_team_id_arn
  sensitive = true
}

# ... other outputs
```

**Backend (`terraform/environments/us-east-2/terraform.tf`):**
```hcl
terraform {
  backend "s3" {
    bucket = "gremlin-terraform-state"
    key    = "demo-platform/${var.subdomain}/terraform.tfstate"
    region = "us-east-2"
  }
}
```

### Workshop Scripts

**New Library (`lib/terraform.sh`):**
```bash
export_terraform_outputs() {
    local tf_dir="$1"
    local outputs_json=$(cd "$tf_dir" && terraform output -json)
    
    export CLUSTER_NAME=$(echo "$outputs_json" | jq -r '.cluster_name.value')
    export ALB_DNS_NAME=$(echo "$outputs_json" | jq -r '.alb_dns_name.value')
    export DEMO_FRONTEND_URL=$(echo "$outputs_json" | jq -r '.demo_frontend_url.value')
    export GREMLIN_TEAM_ID_ARN=$(echo "$outputs_json" | jq -r '.gremlin_team_id_arn.value')
    # ... other exports
}

fetch_gremlin_credentials() {
    export GREMLIN_TEAM_ID=$(aws secretsmanager get-secret-value \
        --secret-id "$GREMLIN_TEAM_ID_ARN" \
        --query 'SecretString' --output text)
    # ... fetch certificate and private key
}
```

**Updated workshop.sh:**
```bash
source "$SCRIPT_DIR/lib/terraform.sh"

provision_infrastructure() {
    terraform_init "$TERRAFORM_DIR"
    terraform_apply "$TERRAFORM_DIR"
    export_terraform_outputs "$TERRAFORM_DIR"
    fetch_gremlin_credentials
}

deploy_applications() {
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
    kubectl create namespace otel-demo --dry-run=client -o yaml | kubectl apply -f -
    deploy_otel_demo
    deploy_monitoring
    install_gremlin
}
```

---

## 5. File Changes Summary

### New Files
- `lib/terraform.sh` - Terraform wrapper functions
- `deploy.sh` - Unified entry point
- `terraform/environments/us-east-2/outputs.tf` - Terraform outputs

### Modified Files
- `terraform/modules/dns/main.tf` - Add workshop DNS records
- `terraform/modules/alb/main.tf` - Add monitoring listener rules
- `terraform/environments/us-east-2/terraform.tf` - Switch to S3 backend
- `workshop.sh` - Add Terraform integration
- `scripts/gremlin_install.sh` - Use Secrets Manager
- `config/gremlin/healthchecks.sh` - Dynamic hostnames

### Removed Files
- Any eksctl configs (replaced by Terraform)
- Manual ALB/DNS scripts (replaced by Terraform)

---

## 6. Migration Steps

### Step 1: Repository Setup
```bash
# Create unified repo
mkdir gremlin-demo-platform
cd gremlin-demo-platform

# Copy Terraform modules
cp -r /path/to/fictional-computing-machine/terraform .

# Copy workshop scripts
cp -r /path/to/workshop/scripts .
cp -r /path/to/workshop/lib .
cp -r /path/to/workshop/config .
cp -r /path/to/workshop/monitoring .
```

### Step 2: Terraform Updates
```bash
# Update DNS module
vim terraform/modules/dns/main.tf
# Add demo-frontend and monitoring DNS records

# Create outputs file
vim terraform/environments/us-east-2/outputs.tf
# Add all workshop-compatible outputs

# Update backend
vim terraform/environments/us-east-2/terraform.tf
# Change from GCS to S3
```

### Step 3: Workshop Updates
```bash
# Create Terraform wrapper
vim lib/terraform.sh
# Add export_terraform_outputs and fetch_gremlin_credentials

# Update workshop.sh
vim workshop.sh
# Source terraform.sh
# Add provision_infrastructure function
# Update deploy_applications to use Terraform outputs
```

### Step 4: Testing
```bash
# Test Terraform
cd terraform/environments/us-east-2
terraform init
terraform plan

# Test workshop integration
cd ../../..
./deploy.sh --subdomain test --owner test.user --enable-eks --action create_new
```

---

## 7. Breaking Changes

### For Users

**Before (workshop only):**
```bash
./workshop.sh --cluster-name my-cluster --action deploy_existing
```

**After (unified):**
```bash
./deploy.sh --subdomain alexs --owner alex.smith --enable-eks --action create_new
```

### DNS Changes

**Before:**
- `demo-frontend.gremlinpoc.com`
- `monitoring.gremlinpoc.com`

**After:**
- `demo-frontend.{subdomain}.gremlinpoc.com`
- `monitoring.{subdomain}.gremlinpoc.com`

**Impact:** Health checks, monitoring URLs, documentation need updates

### Credential Management

**Before:** Pass credentials as CLI args
```bash
--gremlin-team-id xxx --gremlin-team-secret yyy
```

**After:** Pass Secrets Manager ARNs
```bash
--gremlin-team-id-arn arn:aws:secretsmanager:...
```

---

## 8. Timeline Estimate

| Phase | Tasks | Effort | Dependencies |
|-------|-------|--------|--------------|
| **1. Terraform Updates** | DNS, ALB, outputs, backend | 2-3 days | None |
| **2. Workshop Integration** | terraform.sh, workshop.sh updates | 2-3 days | Phase 1 |
| **3. Testing** | End-to-end deployment tests | 2-3 days | Phase 2 |
| **4. Documentation** | README, migration guide | 1-2 days | Phase 3 |
| **5. Validation** | User acceptance testing | 1-2 days | Phase 4 |

**Total:** 8-13 days

---

## 9. Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| **DNS conflicts** | Existing deployments break | Use subdomain-based naming |
| **State management** | Lost infrastructure state | Backup existing state, use S3 locking |
| **Credential access** | Secrets Manager permissions | Document IAM requirements |
| **Terraform version** | Module incompatibility | Pin Terraform version (1.13.3) |
| **Breaking changes** | User workflows disrupted | Provide migration guide |

---

## 10. Success Criteria

✅ Single command deploys complete environment
✅ Infrastructure managed by Terraform
✅ Applications deployed by workshop scripts
✅ DNS names work with health checks
✅ Gremlin credentials from Secrets Manager
✅ Idempotent deployments
✅ Clean teardown with `terraform destroy`

---

## Next Steps

1. **Review this analysis** with team
2. **Create feature branch** for merge work
3. **Start with Phase 1** (Terraform updates)
4. **Test incrementally** after each phase
5. **Document changes** as you go
