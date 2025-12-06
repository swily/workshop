# Deep Analysis: Workshop.sh Flows & Terraform Integration

## Timeline Revision
**Original Estimate:** 8-13 days  
**Revised Target:** 2-3 days with focused implementation

---

## Part 1: Current Workshop.sh Flow Mapping

### Flow 1: `build_new` (Create New Cluster + Deploy Everything)

```
workshop.sh --action build_new
    ↓
parse_arguments()
    ↓
create_and_deploy()
    ├── scripts/operations/cluster_create.sh
    │   ├── lib/cluster.sh::create_cluster() [EKSCTL - WILL BE REPLACED]
    │   │   └── eksctl create cluster [OBSOLETE]
    │   └── lib/cluster.sh::configure_cluster_base()
    │       ├── install_aws_load_balancer_controller() [KEEP]
    │       ├── install_istio() [KEEP - OPTIONAL]
    │       └── install_prometheus_operator() [KEEP]
    │
    ├── scripts/operations/deploy_otel.sh [KEEP - MODIFY]
    │   └── Helm install opentelemetry-demo
    │
    ├── setup_gremlin_only() [KEEP - MODIFY]
    │   ├── scripts/gremlin_install.sh [MODIFY FOR SECRETS MANAGER]
    │   └── config/gremlin/gremlin_annotations.sh [KEEP]
    │
    ├── scripts/operations/deploy_failure_flags.sh [KEEP]
    │
    ├── setup_comprehensive_monitoring() [KEEP]
    │   └── lib/monitoring.sh::setup_comprehensive_monitoring()
    │
    ├── Apply cross-namespace services [KEEP]
    │   └── otel-demo-cross-namespace-services.yaml
    │
    ├── Apply consolidated ingress [MODIFY - TERRAFORM WILL CREATE]
    │   └── consolidated-demo-ingress.yaml [POTENTIALLY OBSOLETE]
    │
    ├── patch_consolidated_ingress_dns_tls() [OBSOLETE - TERRAFORM HANDLES]
    │
    └── display_workshop_endpoints() [MODIFY - USE TERRAFORM OUTPUTS]
```

**OBSOLETE CODE IN FLOW 1:**
- ❌ `lib/cluster.sh::create_cluster()` - Replaced by Terraform
- ❌ `eksctl create cluster` command - Replaced by Terraform EKS module
- ❌ `patch_consolidated_ingress_dns_tls()` - Terraform creates ALB with TLS
- ❌ Manual ACM certificate detection (lines 338-356) - Terraform handles
- ❌ Manual DNS record creation - Terraform DNS module handles
- ❌ `consolidated-demo-ingress.yaml` envsubst application - Terraform creates listener rules

**KEEP & MODIFY:**
- ✅ `install_aws_load_balancer_controller()` - Still needed for K8s ingress → ALB
- ✅ `deploy_otel.sh` - Application deployment (not infrastructure)
- ✅ `gremlin_install.sh` - Modify to fetch from Secrets Manager
- ✅ `setup_comprehensive_monitoring()` - Application layer
- ✅ Cross-namespace services - K8s resources, not infrastructure

---

### Flow 2: `deploy_existing` (Deploy to Existing Cluster)

```
workshop.sh --action deploy_existing
    ↓
deploy_to_existing()
    ├── validate_cluster_exists() [KEEP - VERIFY TERRAFORM OUTPUT]
    ├── update_kubeconfig() [KEEP]
    │
    ├── Check existing Helm releases [KEEP - GOOD IDEMPOTENCY]
    │   ├── helm list opentelemetry-demo
    │   └── helm list gremlin
    │
    ├── deploy_otel.sh [KEEP]
    ├── gremlin_install.sh [MODIFY]
    ├── gremlin_annotations.sh [KEEP]
    ├── deploy_failure_flags.sh [KEEP]
    ├── setup_comprehensive_monitoring() [KEEP]
    │
    └── setup_consolidated_ingress_and_dns() [OBSOLETE - TERRAFORM CREATED]
```

**OBSOLETE CODE IN FLOW 2:**
- ❌ `setup_consolidated_ingress_and_dns()` - Terraform already created ALB/DNS
- ❌ Manual ingress patching - Terraform handles
- ❌ DNS record creation - Terraform handles

**KEEP:**
- ✅ Helm release conflict detection (lines 200-214) - Good idempotency
- ✅ All application deployments
- ✅ Kubeconfig update

---

### Flow 3: `gremlin_only` (Install Gremlin Only)

```
workshop.sh --action gremlin_only
    ↓
setup_gremlin_only()
    ├── validate_cluster_exists() [KEEP]
    ├── gremlin_install.sh [MODIFY]
    ├── gremlin_annotations.sh [KEEP]
    └── setup_gremlin_monitoring() [KEEP]
```

**CHANGES NEEDED:**
- ✅ Fetch Gremlin credentials from Secrets Manager
- ✅ No infrastructure changes

---

### Flow 4: `cleanup` (Delete Cluster)

```
workshop.sh --action cleanup
    ↓
cleanup_cluster_wrapper()
    ├── scripts/operations/cluster_cleanup.sh
    │   └── lib/cluster.sh::cleanup_cluster()
    │       ├── Delete ingresses [KEEP]
    │       ├── Delete LoadBalancer services [KEEP]
    │       ├── eksctl delete cluster [OBSOLETE - TERRAFORM DESTROY]
    │       ├── cleanup_cloudformation_stacks() [OBSOLETE]
    │       └── cleanup_iam_resources() [OBSOLETE]
```

**OBSOLETE CODE IN FLOW 4:**
- ❌ `eksctl delete cluster` - Replaced by `terraform destroy`
- ❌ `cleanup_cloudformation_stacks()` - No CloudFormation with Terraform
- ❌ `cleanup_iam_resources()` - Terraform manages IAM

**KEEP:**
- ✅ Delete K8s ingresses (prevents hanging ALBs)
- ✅ Delete LoadBalancer services

---

## Part 2: End-State Resource Inventory

### Resources Created by Terraform (Infrastructure Layer)

**EKS Cluster:**
- Cluster: `{subdomain}-eks`
- Node groups: 3 spot instance node groups (one per AZ)
- Instance types: m6a.large, m6i.large, m5.large
- Auto-scaling groups with CloudWatch alarms
- OIDC provider for IAM roles

**Networking:**
- VPC: Shared VPC (from existing CloudFormation)
- Subnets: Private subnets for nodes
- Security groups: EKS-managed

**Load Balancer:**
- ALB: `{subdomain}-alb`
- Target groups:
  - `{subdomain}-otel-demo-tg` (port 8080)
  - `{subdomain}-monitoring-tg` (port 80)
- Listener rules:
  - Priority 100: `demo-frontend.{subdomain}.gremlinpoc.com` → otel-demo-tg
  - Priority 101: `monitoring.{subdomain}.gremlinpoc.com` → monitoring-tg
- HTTPS listener with ACM certificate

**DNS (Route53):**
- Hosted zone: `{subdomain}.gremlinpoc.com`
- A records:
  - `demo-frontend.{subdomain}.gremlinpoc.com` → ALB
  - `monitoring.{subdomain}.gremlinpoc.com` → ALB
  - `eks-fargate.{subdomain}.gremlinpoc.com` → ALB (legacy)

**IAM:**
- EKS cluster role
- EKS node role with Secrets Manager access
- Pod Identity associations for Gremlin

**Secrets Manager:**
- `{owner}/gremlin_team_id`
- `{owner}/gremlin_team_certificate`
- `{owner}/gremlin_team_private_key`

---

### Resources Created by Workshop Scripts (Application Layer)

**Kubernetes Namespaces:**
- `otel-demo`
- `monitoring`
- `gremlin`
- `kube-system` (AWS LB Controller)
- `istio-system` (if Istio enabled)

**OpenTelemetry Demo (Helm):**
- Deployment: `opentelemetry-demo` (20+ microservices)
- Services: frontend, cart, checkout, payment, etc.
- ConfigMaps, Secrets

**Monitoring Platform (Prometheus/Grafana):**
- Helm: `kube-prometheus-stack` or platform-specific
- Deployments: prometheus, grafana, alertmanager
- Services: prometheus, grafana
- PVCs: prometheus-data (if persistence enabled)

**Gremlin:**
- Helm: `gremlin`
- DaemonSet: `gremlin` (standard agent)
- Deployment: `opentelemetry-demo-checkoutservice-ff` (if failure flags)
- Secret: `gremlin-team-cert`
- ServiceAccount: `gremlin:chao`
- ClusterRole: `gremlin-service-discovery`

**AWS Load Balancer Controller:**
- Deployment: `aws-load-balancer-controller`
- ServiceAccount: `aws-load-balancer-controller`
- IAM role: `AmazonEKSLoadBalancerControllerRole`

**Cross-Namespace Services:**
- ExternalName services in `otel-demo` namespace:
  - `grafana` → `monitoring/grafana`
  - `prometheus` → `monitoring/prometheus`

**Ingress (Kubernetes):**
- Ingress: `{cluster-name}-consolidated-demo-ingress` (otel-demo namespace)
  - Annotations trigger ALB creation
  - Rules map paths to services

---

## Part 3: Obsolete Code Identification

### Files to DELETE:

1. **`consolidated-demo-ingress.yaml`** (root)
   - Reason: Terraform creates ALB listener rules directly
   - Alternative: Terraform ALB module

2. **Any eksctl config files** (if they exist)
   - Reason: Terraform replaces eksctl

3. **Manual DNS scripts in `helper_scripts/dns/`:**
   - `create_route53_records.sh` (if exists)
   - `update_dns.sh` (if exists)
   - Reason: Terraform DNS module handles

4. **Manual ALB scripts:**
   - Any scripts that create/configure ALBs manually
   - Reason: Terraform ALB module handles

### Functions to DELETE in `lib/cluster.sh`:

```bash
# Line 14-76: create_cluster() - REPLACE WITH TERRAFORM CALL
create_cluster() { ... }

# Line 79-109: cleanup_cloudformation_stacks() - NOT NEEDED WITH TERRAFORM
cleanup_cloudformation_stacks() { ... }

# Line 346-365: cleanup_iam_resources() - TERRAFORM MANAGES
cleanup_iam_resources() { ... }
```

### Functions to DELETE in `workshop.sh`:

```bash
# Line 103-120: patch_consolidated_ingress_dns_tls() - TERRAFORM HANDLES
patch_consolidated_ingress_dns_tls() { ... }

# Lines 334-356: ACM certificate auto-detection - TERRAFORM HANDLES
if [ -z "${HTTPS_MODE:-}" ]; then
    if command_exists aws; then
        found_arn=$(aws acm list-certificates ...)
        ...
    fi
fi

# Lines 165-173: consolidated-demo-ingress.yaml application - TERRAFORM CREATES ALB
if [[ -f "$SCRIPT_DIR/consolidated-demo-ingress.yaml" ]]; then
    envsubst < "$SCRIPT_DIR/consolidated-demo-ingress.yaml" | kubectl apply -f -
fi

# Line 176: patch_consolidated_ingress_dns_tls() call
patch_consolidated_ingress_dns_tls

# Lines 179-180: Legacy ingress cleanup - STILL USEFUL FOR MIGRATION
kubectl delete ingress -n otel-demo frontend-proxy jaeger-ingress 2>/dev/null || true
```

### Code to MODIFY:

**`workshop.sh` - parse_arguments():**
```bash
# REMOVE these arguments (Terraform handles):
--https
--externaldns-iam-role-arn
--cluster-name  # Replace with --subdomain

# ADD these arguments:
--subdomain
--owner
--enable-eks
--enable-ecs-fargate
--gremlin-team-id-arn
--gremlin-team-certificate-arn
--gremlin-team-private-key-arn
--terraform-dir
```

**`scripts/gremlin_install.sh`:**
```bash
# REPLACE credential handling:
# OLD:
GREMLIN_TEAM_ID="$1"
GREMLIN_TEAM_SECRET="$2"

# NEW:
export GREMLIN_TEAM_ID=$(aws secretsmanager get-secret-value \
    --secret-id "$GREMLIN_TEAM_ID_ARN" \
    --query 'SecretString' --output text)
```

---

## Part 4: Modular Deployment Analysis

### Current Modularity (Good)

The workshop already has modular operations:

```
scripts/operations/
├── cluster_create.sh          # Cluster only
├── deploy_otel.sh             # OpenTelemetry Demo only
├── deploy_failure_flags.sh    # Failure Flags only
├── add_monitoring_platform.sh # Add monitoring to existing
└── cluster_cleanup.sh         # Cleanup only
```

### Required Modularity Enhancements

**1. Separate Infrastructure from Application:**

```
NEW STRUCTURE:
scripts/operations/
├── infrastructure/
│   ├── provision.sh           # Terraform apply
│   ├── destroy.sh             # Terraform destroy
│   └── outputs.sh             # Export Terraform outputs
│
├── applications/
│   ├── deploy_otel.sh         # OpenTelemetry Demo
│   ├── deploy_monitoring.sh   # Monitoring platform
│   ├── deploy_gremlin.sh      # Gremlin agent
│   └── deploy_failure_flags.sh # Failure Flags
│
└── integrations/
    ├── configure_ingress.sh   # K8s ingress → ALB mapping
    ├── setup_dns.sh           # Verify DNS (read-only)
    └── health_checks.sh       # Gremlin health checks
```

**2. Modular Deployment Commands:**

```bash
# Infrastructure only
./scripts/operations/infrastructure/provision.sh \
    --subdomain alexs \
    --owner alex.smith \
    --enable-eks

# OpenTelemetry Demo only (assumes infrastructure exists)
./scripts/operations/applications/deploy_otel.sh \
    --subdomain alexs

# Monitoring only
./scripts/operations/applications/deploy_monitoring.sh \
    --subdomain alexs \
    --platform prometheus

# Gremlin only
./scripts/operations/applications/deploy_gremlin.sh \
    --subdomain alexs

# Failure Flags only
./scripts/operations/applications/deploy_failure_flags.sh \
    --subdomain alexs

# Full stack (all in one)
./workshop.sh \
    --subdomain alexs \
    --owner alex.smith \
    --enable-eks \
    --monitoring prometheus \
    --enable-failure-flags \
    --action create_new
```

**3. Idempotent Re-deployment:**

Each module should support:
- **Fresh install:** Deploy if not exists
- **Upgrade:** Upgrade if exists
- **Force reinstall:** Delete and redeploy

```bash
# Redeploy OpenTelemetry Demo only
./scripts/operations/applications/deploy_otel.sh \
    --subdomain alexs \
    --force-reinstall

# Upgrade monitoring platform
./scripts/operations/applications/deploy_monitoring.sh \
    --subdomain alexs \
    --platform prometheus \
    --upgrade
```

---

## Part 5: Integration Points

### Terraform → Workshop Bridge

**Terraform Outputs (`terraform output -json`):**
```json
{
  "cluster_name": {"value": "alexs-eks"},
  "cluster_endpoint": {"value": "https://..."},
  "cluster_region": {"value": "us-east-2"},
  "alb_dns_name": {"value": "alexs-alb-123.us-east-2.elb.amazonaws.com"},
  "demo_frontend_url": {"value": "https://demo-frontend.alexs.gremlinpoc.com"},
  "monitoring_url": {"value": "https://monitoring.alexs.gremlinpoc.com"},
  "otel_demo_target_group_arn": {"value": "arn:aws:..."},
  "monitoring_target_group_arn": {"value": "arn:aws:..."},
  "gremlin_team_id_arn": {"value": "arn:aws:secretsmanager:..."},
  "gremlin_team_certificate_arn": {"value": "arn:aws:secretsmanager:..."},
  "gremlin_team_private_key_arn": {"value": "arn:aws:secretsmanager:..."},
  "subdomain": {"value": "alexs"},
  "owner": {"value": "alex.smith"}
}
```

**Workshop Consumption (`lib/terraform.sh`):**
```bash
export_terraform_outputs() {
    local outputs=$(terraform output -json)
    export CLUSTER_NAME=$(echo "$outputs" | jq -r '.cluster_name.value')
    export ALB_DNS_NAME=$(echo "$outputs" | jq -r '.alb_dns_name.value')
    # ... etc
}

# Then use in scripts:
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
```

### Kubernetes Ingress → ALB Target Group Mapping

**Current (Manual):**
```yaml
# consolidated-demo-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
  - host: demo-frontend.gremlinpoc.com
    http:
      paths:
      - path: /
        backend:
          service:
            name: opentelemetry-demo-frontendproxy
            port:
              number: 8080
```

**New (Terraform + K8s):**

Terraform creates ALB + target groups, K8s ingress uses TargetGroupBinding:

```yaml
# Created by workshop scripts
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: otel-demo-tgb
  namespace: otel-demo
spec:
  serviceRef:
    name: opentelemetry-demo-frontendproxy
    port: 8080
  targetGroupARN: ${OTEL_DEMO_TARGET_GROUP_ARN}  # From Terraform output
```

---

## Part 6: Migration Strategy

### Phase 1: Add Terraform Integration (No Breaking Changes)

**Goal:** Run Terraform alongside existing workshop, validate outputs

**Steps:**
1. Add `lib/terraform.sh`
2. Add `--terraform-dir` argument to workshop.sh
3. Add `provision_infrastructure()` function
4. Test Terraform provisioning separately
5. Validate outputs match expectations

**Validation:**
```bash
# Run Terraform only
cd terraform/sa-demos/us-east-2
terraform apply

# Verify outputs
terraform output -json

# Run workshop with existing cluster
./workshop.sh --action deploy_existing --cluster-name alexs-eks
```

### Phase 2: Remove Obsolete Code

**Goal:** Delete eksctl, manual ALB/DNS code

**Steps:**
1. Comment out `create_cluster()` in `lib/cluster.sh`
2. Comment out `patch_consolidated_ingress_dns_tls()` in `workshop.sh`
3. Comment out ACM detection logic
4. Test `deploy_existing` flow
5. If successful, delete commented code

### Phase 3: Integrate Terraform into Workflows

**Goal:** Make `build_new` use Terraform

**Steps:**
1. Update `create_and_deploy()` to call `provision_infrastructure()`
2. Remove eksctl calls
3. Update `cleanup` to call `terraform destroy`
4. Test end-to-end

### Phase 4: Add Modular Deployment Scripts

**Goal:** Enable individual component deployment

**Steps:**
1. Create `scripts/operations/infrastructure/` directory
2. Create `scripts/operations/applications/` directory
3. Extract deployment logic into modular scripts
4. Test each module independently

---

## Part 7: Immediate Action Items

### Pre-Implementation Checklist

- [x] Commit current changes
- [ ] Create feature branch: `git checkout -b terraform-integration`
- [ ] Backup current workshop.sh: `cp workshop.sh workshop.sh.backup`
- [ ] Document current cluster state

### Implementation Order

**Day 1: Terraform Setup**
1. Update Terraform modules (DNS, ALB, outputs)
2. Test Terraform apply/destroy cycle
3. Validate outputs

**Day 2: Workshop Integration**
1. Create `lib/terraform.sh`
2. Update `workshop.sh` argument parsing
3. Add `provision_infrastructure()` function
4. Test `create_new` flow

**Day 3: Cleanup & Modularization**
1. Remove obsolete code
2. Create modular deployment scripts
3. Update documentation
4. End-to-end testing

---

## Part 8: Risk Mitigation

### Rollback Strategy

**If Terraform integration fails:**
```bash
# Revert to backup
git checkout workshop.sh.backup
mv workshop.sh.backup workshop.sh

# Use existing eksctl workflow
./workshop.sh --action build_new --cluster-name fallback-cluster
```

### Parallel Testing

**Run both approaches simultaneously:**
```bash
# Terraform approach
./workshop.sh --subdomain test-tf --action create_new

# Legacy eksctl approach (on backup)
./workshop.sh.backup --cluster-name test-eksctl --action build_new

# Compare results
```

### Incremental Validation

After each change:
1. Run syntax check: `bash -n workshop.sh`
2. Run dry-run: `./workshop.sh --dry-run --action create_new`
3. Test on disposable cluster
4. Validate with real deployment

---

## Summary

**Obsolete Code:** ~500 lines across multiple files  
**New Code:** ~300 lines (lib/terraform.sh + updates)  
**Net Change:** -200 lines (simpler codebase)

**Key Deletions:**
- eksctl cluster creation
- Manual ALB/DNS management
- CloudFormation cleanup
- ACM certificate detection

**Key Additions:**
- Terraform wrapper library
- Secrets Manager integration
- Modular deployment scripts
- Enhanced idempotency

**End Result:**
- Infrastructure as code (Terraform)
- Application deployment (Workshop scripts)
- Clean separation of concerns
- Faster deployments (parallel Terraform)
- Better state management
