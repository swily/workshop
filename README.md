# Workshop - OpenTelemetry Demo with Gremlin Chaos Engineering

Automated deployment of OpenTelemetry Demo application with integrated monitoring (Prometheus/Grafana) and Gremlin chaos engineering on AWS EKS. Infrastructure managed by Terraform, applications deployed via Kubernetes.

**Status:** ✅ Ready for Testing (Refactoring Complete - 2025-10-21)

---

## Table of Contents

- [Repository Architecture](#repository-architecture)
- [What This Does](#what-this-does)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Understanding the Flags](#understanding-the-flags)
- [Credential Management](#credential-management)
- [Common Workflows](#common-workflows)
- [What Gets Created](#what-gets-created)
- [Recent Improvements](#recent-improvements)
- [Troubleshooting](#troubleshooting)

---

## Repository Architecture

This workshop uses **two separate repositories** that work together:

### 1. fictional-computing-machine (Infrastructure)
- **Repository:** https://github.com/gremlin/fictional-computing-machine
- **Purpose:** Terraform modules for AWS infrastructure
- **Contains:** EKS, ALB, Route53, IAM, Secrets Manager configurations
- **Versioning:** Git tags/branches (referenced via `?ref=main`)

### 2. workshop (Orchestration)
- **Repository:** This repository
- **Purpose:** Deployment orchestration and application management
- **Contains:** Deployment scripts, monitoring setup, Gremlin integration
- **Uses:** fictional-computing-machine modules via Terraform

### How They Work Together

```
workshop.sh → lib/terraform.sh → Generates workspace
                                 ↓
                    module "workshop" {
                      source = "git::https://github.com/gremlin/
                                fictional-computing-machine.git//
                                modules/workshop?ref=main"
                    }
                                 ↓
                    Terraform creates infrastructure
                                 ↓
                    workshop.sh deploys applications
```

**Key Benefits:**
- **Separation:** Infrastructure code separate from application code
- **Reusability:** fictional-computing-machine modules used by multiple projects
- **Versioning:** Pin to specific infrastructure versions
- **Updates:** Update infrastructure independently from applications

---

## What This Does

This workshop script automates the deployment of:

1. **Infrastructure** (via Terraform)
   - EKS cluster with managed node groups
   - Application Load Balancer (ALB) with HTTPS
   - Route53 DNS records (demo-frontend.{subdomain}.gremlinpoc.com)
   - IAM roles and policies
   - Secrets Manager integration for credentials

2. **Applications** (via Kubernetes/Helm)
   - OpenTelemetry Demo (20+ microservices)
   - Prometheus + Grafana monitoring stack
   - Gremlin agent for chaos engineering
   - Optional: Failure Flags for controlled failures

3. **Integration**
   - ALB routes traffic to frontend and monitoring
   - Gremlin health checks monitor services
   - Automatic service discovery and tagging

**Result:** A fully functional demo environment accessible at `https://demo-frontend.{subdomain}.gremlinpoc.com`

---

## Prerequisites

### Required Repository

This workshop requires the `fictional-computing-machine` repository to be cloned alongside this repository:

```bash
# Clone both repositories in the same parent directory
cd ~/your-workspace
git clone https://github.com/gremlin/fictional-computing-machine.git
git clone https://github.com/your-org/workshop.git

# Directory structure should be:
# ~/your-workspace/
# ├── fictional-computing-machine/
# └── workshop/
```

The workshop automatically references Terraform modules from the local `fictional-computing-machine` repository.

**Custom path:** Set `FCM_LOCAL_PATH` environment variable if your repos are in different locations:
```bash
export FCM_LOCAL_PATH="/path/to/fictional-computing-machine"
```

### Required Tools

Install these tools before running the workshop:

```bash
# AWS CLI
brew install awscli
aws configure  # Set your credentials

# Terraform (>= 1.13)
brew install terraform

# kubectl
brew install kubectl

# Helm v3
brew install helm

# jq (JSON processor)
brew install jq
```

### AWS Account Setup

1. **AWS Credentials** - Configure with appropriate permissions:
   ```bash
   aws configure
   # AWS Access Key ID: YOUR_KEY
   # AWS Secret Access Key: YOUR_SECRET
   # Default region: us-east-2
   ```

2. **Required AWS Permissions:**
   - EKS cluster creation
   - EC2 (VPC, subnets, security groups)
   - IAM role/policy creation
   - Route53 DNS management
   - Secrets Manager access
   - S3 (for Terraform state)
   - DynamoDB (for Terraform state locking)

3. **Terraform State Backend** (automatically created):
   - The workshop automatically creates these shared resources if they don't exist:
     - S3 bucket: `gremlin-terraform-state-us-east-2` (with versioning and encryption)
     - DynamoDB table: `gremlin-terraform-locks` (for state locking)
   - All users share the same backend for collaboration
   - Each deployment gets its own state file: `workshop/{subdomain}/terraform.tfstate`

### Gremlin Account

You need a Gremlin account to use chaos engineering features:

1. **Sign up:** https://app.gremlin.com/signup
2. **Get credentials:**
   - Go to Settings → Teams
   - Download your team certificate and private key
   - Note your Team ID (format: `438c58ec-03db-47ac-8c58-ec03db67ac42`)

---

## Quick Start

### Option 1: With Secrets Manager (Recommended)

**Step 1: Store your Gremlin credentials in AWS Secrets Manager**

```bash
# Set your name (used as owner)
OWNER="alex.smith"
REGION="us-east-2"

# Create secrets (one-time setup)
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_id" \
    --description "Gremlin Team ID for ${OWNER}" \
    --secret-string "438c58ec-03db-47ac-8c58-ec03db67ac42" \
    --region "$REGION"

aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_certificate" \
    --description "Gremlin Team Certificate for ${OWNER}" \
    --secret-string "$(cat ~/Downloads/team-certificate.pem)" \
    --region "$REGION"

aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_secret" \
    --description "Gremlin Team Secret for ${OWNER}" \
    --secret-string "YOUR_TEAM_SECRET_HERE" \
    --region "$REGION"

aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_private_key" \
    --description "Gremlin Team Private Key for ${OWNER}" \
    --secret-string "$(cat ~/Downloads/team-private-key.pem)" \
    --region "$REGION"
```

**Step 2: Deploy the workshop**

```bash
./workshop.sh \
    --action build_new \
    --subdomain alexs \
    --owner alex.smith \
    --enable-eks \
    --monitoring grafana
```

That's it! The script will:
- Auto-detect your Gremlin credentials from Secrets Manager
- Create infrastructure with Terraform (~15-20 minutes)
- Deploy all applications
- Configure monitoring and chaos engineering

### Option 2: With Environment Variables (Quick Test)

```bash
# Export credentials
export GREMLIN_TEAM_ID="438c58ec-03db-47ac-8c58-ec03db67ac42"
export GREMLIN_TEAM_CERTIFICATE="$(cat ~/Downloads/team-certificate.pem)"
export GREMLIN_TEAM_PRIVATE_KEY="$(cat ~/Downloads/team-private-key.pem)"

# Deploy
./workshop.sh \
    --subdomain test \
    --owner test.user \
    --enable-eks \
    --action create_new
```

---

## Understanding the Flags

### Required Flags

| Flag | Description | Example | Notes |
|------|-------------|---------|-------|
| `--subdomain` | Unique identifier for your deployment | `alexs`, `demo1`, `test` | Used for DNS: `demo-frontend.{subdomain}.gremlinpoc.com` |
| `--owner` | Your name/identifier | `alex.smith`, `jane.doe` | Used for resource tagging and credential lookup |
| `--enable-eks` | Enable EKS cluster creation | (flag, no value) | Required for Kubernetes deployment |
| `--action` | What to do | `create_new`, `deploy_existing`, `cleanup` | See [Actions](#actions) below |

### Optional Flags

| Flag | Description | Default | Example |
|------|-------------|---------|----------|
| `--enable-ecs-fargate` | Also create ECS Fargate cluster | `false` | `--enable-ecs-fargate` |
| `--monitoring` | Monitoring platform | `prometheus` | `--monitoring grafana` |
| `--enable-failure-flags` | Deploy Failure Flags sidecar | `false` | `--enable-failure-flags` |
| `--install-istio` | Install Istio service mesh | `false` | `--install-istio` |
| `--region` | AWS region | `us-east-2` | `--region us-west-2` |
| `--fcm-version` | fictional-computing-machine version | `main` | `--fcm-version v1.2.0` |
| `--dry-run` | Show what would happen | (none) | `--dry-run` |

### Credential Flags (Optional)

If you don't want to use Secrets Manager auto-detection:

| Flag | Description | Example |
|------|-------------|---------|
| `--gremlin-team-id-arn` | ARN of Team ID secret | `arn:aws:secretsmanager:us-east-2:123:secret:...` |
| `--gremlin-team-certificate-arn` | ARN of certificate secret | `arn:aws:secretsmanager:us-east-2:123:secret:...` |
| `--gremlin-team-private-key-arn` | ARN of private key secret | `arn:aws:secretsmanager:us-east-2:123:secret:...` |

### Actions

| Action | What It Does | When to Use |
|--------|--------------|-------------|
| `create_new` | Create infrastructure + deploy apps | First time deployment |
| `deploy_existing` | Deploy apps to existing infrastructure | Update applications |
| `gremlin_only` | Install Gremlin on existing cluster | Add chaos engineering |
| `cleanup` | Destroy everything | Remove deployment |

---

## Credential Management

### How Credentials Are Resolved

The script tries multiple methods in this order:

1. **Explicit ARNs** (if provided via `--gremlin-team-id-arn`, etc.)
2. **Owner-based lookup** (checks `{owner}/gremlin_*` secrets in Secrets Manager)
3. **Environment variables** (`GREMLIN_TEAM_ID`, `GREMLIN_TEAM_CERTIFICATE`, etc.)
4. **Fail with helpful error**

### Method 1: Secrets Manager (Recommended)

**Why?**
- ✅ Secure (no credentials in shell history)
- ✅ Automatic (just provide `--owner`)
- ✅ Centralized (one place to update)
- ✅ Auditable (AWS CloudTrail logs access)

**Setup:**

```bash
OWNER="your.name"

# Create Team ID secret
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_id" \
    --secret-string "YOUR_TEAM_ID_HERE" \
    --region us-east-2

# Create certificate secret
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_certificate" \
    --secret-string "$(cat /path/to/team-certificate.pem)" \
    --region us-east-2

# Create private key secret
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_private_key" \
    --secret-string "$(cat /path/to/team-private-key.pem)" \
    --region us-east-2
```

**Usage:**
```bash
./workshop.sh --subdomain demo --owner your.name --enable-eks --action create_new
# Credentials automatically loaded!
```

### Method 2: Environment Variables

**Why?**
- ✅ Quick for testing
- ✅ No AWS setup needed
- ⚠️ Less secure (visible in process list)

**Setup:**
```bash
export GREMLIN_TEAM_ID="438c58ec-03db-47ac-8c58-ec03db67ac42"
export GREMLIN_TEAM_CERTIFICATE="$(cat team-certificate.pem)"
export GREMLIN_TEAM_PRIVATE_KEY="$(cat team-private-key.pem)"
```

**Usage:**
```bash
./workshop.sh --subdomain demo --owner your.name --enable-eks --action create_new
```

### Method 3: Explicit ARNs

**Why?**
- ✅ Full control over which secrets to use
- ✅ Can use team-shared secrets

**Usage:**
```bash
./workshop.sh \
    --subdomain demo \
    --owner your.name \
    --enable-eks \
    --gremlin-team-id-arn "arn:aws:secretsmanager:us-east-2:123:secret:team/gremlin_id" \
    --gremlin-team-certificate-arn "arn:aws:secretsmanager:us-east-2:123:secret:team/gremlin_cert" \
    --gremlin-team-private-key-arn "arn:aws:secretsmanager:us-east-2:123:secret:team/gremlin_key" \
    --action create_new
```

---

## Common Workflows

### Scenario 1: First Time User with Gremlin Team ID

**You have:**
- Gremlin Team ID: `438c58ec-03db-47ac-8c58-ec03db67ac42`
- Team certificate and private key files downloaded

**Steps:**

1. **Store credentials in Secrets Manager (one-time):**
   ```bash
   OWNER="your.name"
   
   aws secretsmanager create-secret \
       --name "${OWNER}/gremlin_team_id" \
       --secret-string "438c58ec-03db-47ac-8c58-ec03db67ac42" \
       --region us-east-2
   
   aws secretsmanager create-secret \
       --name "${OWNER}/gremlin_team_certificate" \
       --secret-string "$(cat ~/Downloads/team-certificate.pem)" \
       --region us-east-2
   
   aws secretsmanager create-secret \
       --name "${OWNER}/gremlin_team_private_key" \
       --secret-string "$(cat ~/Downloads/team-private-key.pem)" \
       --region us-east-2
   ```

2. **Deploy:**
   ```bash
   ./workshop.sh \
       --subdomain demo1 \
       --owner your.name \
       --enable-eks \
       --action create_new
   ```

3. **Access your deployment:**
   - Frontend: `https://demo-frontend.demo1.gremlinpoc.com`
   - Grafana: `https://monitoring.demo1.gremlinpoc.com`
   - Gremlin UI: `https://app.gremlin.com`

### Scenario 2: Quick Test Without Secrets Manager

**You have:**
- Gremlin credentials files
- Want to test quickly

**Steps:**

```bash
# Export credentials
export GREMLIN_TEAM_ID="438c58ec-03db-47ac-8c58-ec03db67ac42"
export GREMLIN_TEAM_CERTIFICATE="$(cat ~/Downloads/team-certificate.pem)"
export GREMLIN_TEAM_PRIVATE_KEY="$(cat ~/Downloads/team-private-key.pem)"

# Deploy
./workshop.sh \
    --subdomain quicktest \
    --owner test.user \
    --enable-eks \
    --action create_new
```

### Scenario 3: Deploy with Failure Flags

**You want:**
- Full deployment with controlled failure injection

**Steps:**

```bash
./workshop.sh \
    --subdomain demo-ff \
    --owner your.name \
    --enable-eks \
    --enable-failure-flags \
    --action create_new
```

**What you get:**
- Failure Flags sidecar on checkout service
- Ability to inject failures via Gremlin UI
- Health checks monitoring service availability

### Scenario 4: Update Applications Only

**You have:**
- Existing infrastructure
- Want to update/redeploy applications

**Steps:**

```bash
./workshop.sh \
    --subdomain demo1 \
    --action deploy_existing
```

This will:
- Load existing Terraform outputs
- Redeploy OpenTelemetry Demo
- Update monitoring stack
- Refresh Gremlin configuration

### Scenario 5: Add Gremlin to Existing Cluster

**You have:**
- Running EKS cluster with applications
- Want to add chaos engineering

**Steps:**

```bash
./workshop.sh \
    --subdomain demo1 \
    --owner your.name \
    --action gremlin_only
```

### Scenario 6: Clean Up Everything

**You want:**
- Remove all infrastructure
- Delete cluster and resources

**Steps:**

```bash
./workshop.sh \
    --subdomain demo1 \
    --action cleanup
```

This will:
1. Delete Kubernetes ingresses (prevents hanging ALBs)
2. Delete LoadBalancer services
3. Run `terraform destroy`
4. Remove all AWS resources

---

## What Gets Created

### Infrastructure (Terraform)

| Resource | Name/Pattern | Purpose |
|----------|--------------|---------|
| **EKS Cluster** | `{subdomain}-eks` | Kubernetes cluster |
| **Node Group** | `{subdomain}-eks-node-group` | EC2 instances for workloads |
| **VPC** | `{subdomain}-vpc` | Network isolation |
| **ALB** | `k8s-{subdomain}-alb-*` | Load balancer for HTTP(S) traffic |
| **Target Groups** | `k8s-{subdomain}-otel-*`<br>`k8s-{subdomain}-monitoring-*` | Route traffic to services |
| **Route53 Records** | `demo-frontend.{subdomain}.gremlinpoc.com`<br>`monitoring.{subdomain}.gremlinpoc.com` | DNS names |
| **IAM Roles** | `{subdomain}-eks-cluster-role`<br>`{subdomain}-eks-node-role`<br>`{subdomain}-alb-controller-role` | Permissions |
| **Security Groups** | Multiple for cluster, nodes, ALB | Network security |

### Applications (Kubernetes)

| Component | Namespace | Services | Purpose |
|-----------|-----------|----------|---------|
| **OpenTelemetry Demo** | `otel-demo` | 20+ microservices | Demo application |
| **Frontend** | `otel-demo` | `opentelemetry-demo-frontendproxy` | User interface |
| **Checkout** | `otel-demo` | `opentelemetry-demo-checkoutservice` | Payment processing |
| **Cart** | `otel-demo` | `opentelemetry-demo-cartservice` | Shopping cart |
| **Product Catalog** | `otel-demo` | `opentelemetry-demo-productcatalogservice` | Product data |
| **Prometheus** | `monitoring` | `prometheus-server` | Metrics collection |
| **Grafana** | `monitoring` | `grafana` | Dashboards |
| **Gremlin Agent** | `gremlin` | `gremlin` | Chaos engineering |
| **Failure Flags** | `otel-demo` | Sidecar on checkout | Controlled failures |

### Gremlin Integration

| Feature | What Gets Created | Where to See It |
|---------|-------------------|-----------------|
| **Service Discovery** | All OTel Demo services tagged with `gremlin.com/service-id` | Gremlin UI → Services |
| **Health Checks** | Prometheus alerts monitoring<br>Grafana datasource monitoring | Gremlin UI → Reliability → Status Checks |
| **Failure Flags** | Sidecar on checkout service<br>Ingress proxy (port 5035)<br>Dependency proxy (port 5034) | Gremlin UI → Failure Flags |
| **Experiments** | Available for all discovered services | Gremlin UI → Attacks |

### DNS and URLs

After deployment completes, you'll have:

| Service | URL | What It Does |
|---------|-----|--------------|
| **Frontend** | `https://demo-frontend.{subdomain}.gremlinpoc.com` | OpenTelemetry Demo UI |
| **Grafana** | `https://monitoring.{subdomain}.gremlinpoc.com` | Monitoring dashboards |
| **Prometheus** | `https://monitoring.{subdomain}.gremlinpoc.com/prometheus` | Metrics query interface |
| **Gremlin** | `https://app.gremlin.com` | Chaos engineering control plane |

### Naming Conventions

**How resources are named:**

1. **Subdomain** → Used for DNS and resource prefixes
   - Example: `--subdomain alexs` creates `alexs-eks` cluster

2. **Owner** → Used for tagging and credential lookup
   - Example: `--owner alex.smith` tags resources with `Owner=alex.smith`

3. **Gremlin Services** → Auto-discovered with descriptive names
   - `checkout-service` (from `opentelemetry-demo-checkoutservice`)
   - `payment-service` (from `opentelemetry-demo-paymentservice`)
   - `cart-service` (from `opentelemetry-demo-cartservice`)

4. **Health Checks** → Named after monitored service
   - `prometheus-firing-alerts` (monitors Prometheus)
   - `grafana-datasource-health` (monitors Grafana)

**Example for `--subdomain demo1 --owner alex.smith`:**

```
EKS Cluster: demo1-eks
ALB: k8s-demo1-alb-1234567890
Frontend URL: https://demo-frontend.demo1.gremlinpoc.com
Monitoring URL: https://monitoring.demo1.gremlinpoc.com
Gremlin Services: checkout-service, payment-service, cart-service, etc.
Health Checks: prometheus-firing-alerts, grafana-datasource-health
Tags: Owner=alex.smith, Subdomain=demo1, ManagedBy=terraform
```

---

## Troubleshooting

### Common Issues

#### 1. "Missing required argument: --subdomain"

**Problem:** You're using the new Terraform-based workflow but forgot required flags.

**Solution:**
```bash
# Old way (still works for backwards compatibility)
./workshop.sh --cluster-name test --action build_new

# New way (required for Terraform)
./workshop.sh --subdomain test --owner your.name --enable-eks --action create_new
```

#### 2. "No Gremlin credentials found"

**Problem:** Script can't find your Gremlin credentials.

**Solution - Check in order:**

1. **Secrets Manager:** Do you have secrets created?
   ```bash
   aws secretsmanager list-secrets --query "SecretList[?contains(Name, 'your.name/gremlin')]"
   ```

2. **Environment Variables:** Are they set?
   ```bash
   echo $GREMLIN_TEAM_ID
   echo $GREMLIN_TEAM_CERTIFICATE
   ```

3. **Explicit ARNs:** Did you provide them?
   ```bash
   ./workshop.sh --gremlin-team-id-arn "arn:aws:..." ...
   ```

#### 3. "Terraform workspace not found"

**Problem:** Trying to use `deploy_existing` or `cleanup` but no workspace exists.

**Solution:**
```bash
# Check if workspace exists
ls -la terraform/workspace/

# If missing, run create_new first
./workshop.sh --subdomain demo1 --owner your.name --enable-eks --action create_new
```

#### 4. "ALB not becoming healthy"

**Problem:** ALB target groups show unhealthy targets.

**Solution:**
```bash
# Check pod status
kubectl get pods -n otel-demo
kubectl get pods -n monitoring

# Check service endpoints
kubectl get svc -n otel-demo
kubectl get svc -n monitoring

# Check ALB target groups in AWS Console
# Ensure security groups allow traffic from ALB to pods
```

#### 5. "DNS records not created"

**Problem:** Can't access `demo-frontend.{subdomain}.gremlinpoc.com`

**Solution:**
1. **Check Route53 hosted zone exists:**
   ```bash
   aws route53 list-hosted-zones --query "HostedZones[?Name=='gremlinpoc.com.']"
   ```

2. **Check Terraform outputs:**
   ```bash
   cd terraform/workspace/{subdomain}
   terraform output
   ```

3. **Verify ALB DNS:**
   ```bash
   kubectl get ingress -A
   # Look for ALB DNS name
   ```

#### 6. "Gremlin services not showing up"

**Problem:** Services not appearing in Gremlin UI.

**Solution:**
```bash
# Check Gremlin agent is running
kubectl get pods -n gremlin

# Check service annotations
kubectl get svc -n otel-demo -o yaml | grep gremlin.com/service-id

# Manually annotate if missing
kubectl annotate svc -n otel-demo opentelemetry-demo-checkoutservice gremlin.com/service-id=checkout-service
```

#### 7. "Health checks not working"

**Problem:** Gremlin health checks show as failing.

**Solution:**
```bash
# Check if health check endpoints are accessible
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
curl http://localhost:9090/api/v1/query?query=ALERTS

# Check Grafana datasource
kubectl port-forward -n monitoring svc/grafana 3000:80
curl http://localhost:3000/api/health
```

### Getting Help

**Check logs:**
```bash
# Terraform logs
cd terraform/workspace/{subdomain}
terraform show

# Kubernetes logs
kubectl logs -n otel-demo deployment/opentelemetry-demo-frontendproxy
kubectl logs -n gremlin daemonset/gremlin

# Script logs
./workshop.sh --dry-run --action create_new  # See what would happen
```

**Validate configuration:**
```bash
# Check AWS credentials
aws sts get-caller-identity

# Check kubectl context
kubectl config current-context

# Check Terraform version
terraform version  # Should be >= 1.13
```

**Clean slate:**
```bash
# If all else fails, clean up and start over
./workshop.sh --subdomain demo1 --action cleanup
./workshop.sh --subdomain demo1 --owner your.name --enable-eks --action create_new
```

---

## Advanced Configuration

### Using Different Terraform Versions

```bash
# Pin to specific fictional-computing-machine version
FCM_VERSION=v1.2.0 ./workshop.sh --subdomain demo --owner your.name --enable-eks --action create_new

# Or set in environment
export FCM_VERSION=v1.2.0
./workshop.sh --subdomain demo --owner your.name --enable-eks --action create_new
```

### Deploy to Different Region

```bash
./workshop.sh \
    --subdomain demo \
    --owner your.name \
    --enable-eks \
    --region us-west-2 \
    --action create_new
```

### Enable Both EKS and ECS Fargate

```bash
./workshop.sh \
    --subdomain demo \
    --owner your.name \
    --enable-eks \
    --enable-ecs-fargate \
    --action create_new
```

### Dry Run (See What Would Happen)

```bash
./workshop.sh \
    --subdomain demo \
    --owner your.name \
    --enable-eks \
    --dry-run \
    --action create_new
```

---

## Architecture Overview

### Infrastructure Layer (Terraform)

```
fictional-computing-machine (GitHub)
    ↓ (referenced via Git URL)
terraform/workspace/{subdomain}/
    ├── main.tf          (single module reference)
    ├── variables.tf     (deployment config)
    └── terraform.tf     (backend config)
    ↓ (terraform apply)
AWS Resources:
    ├── EKS Cluster
    ├── ALB + Target Groups
    ├── Route53 DNS
    ├── IAM Roles
    └── Secrets Manager
```

### Application Layer (Kubernetes)

```
workshop.sh
    ↓
scripts/operations/
    ├── deploy_otel.sh        → OpenTelemetry Demo
    ├── deploy_failure_flags.sh → Failure Flags
    └── gremlin_install.sh    → Gremlin Agent
    ↓
Kubernetes Resources:
    ├── otel-demo namespace (20+ microservices)
    ├── monitoring namespace (Prometheus, Grafana)
    └── gremlin namespace (Chaos agent)
```

### Integration Points

```
Terraform Outputs → Environment Variables → Application Scripts
    ↓                    ↓                        ↓
CLUSTER_NAME        AWS_REGION              kubectl commands
ALB_DNS_NAME        GREMLIN_*_ARN           helm installs
TARGET_GROUP_ARN    SUBDOMAIN               service annotations
```

---

## Recent Improvements

### Code Refactoring (2025-10-21)

**Eliminated ~101 lines of duplicate code** and unified installation patterns:

1. **✅ Unified Gremlin Setup**
   - Created `lib/gremlin.sh` with shared functions
   - Created `lib/deployment.sh` with deployment helpers
   - All 3 actions now use same code paths

2. **✅ Automatic Credential Resolution**
   - Function: `ensure_gremlin_credentials()`
   - Auto-resolves from owner → Secrets Manager
   - Falls back to subdomain → owner lookup
   - **No more manual credential export required**

3. **✅ Idempotency Implemented**
   - `install_gremlin()` checks if already installed
   - `fix_gremlin_ec2_permissions()` checks if policy attached
   - Safe to run multiple times without conflicts

4. **✅ EC2 Permissions in Correct Location**
   - Moved from monitoring setup to cluster setup
   - Runs during infrastructure provisioning (correct)

5. **✅ Cross-Namespace Services Added**
   - Now included in all actions (was missing from `deploy_existing`)
   - Enables monitoring stack routing through ALB

**Result:** Consistent, maintainable, idempotent deployments across all actions.

---

## File Structure

```
workshop/
├── workshop.sh                    # Main orchestration script
├── lib/
│   ├── terraform.sh              # Terraform wrapper
│   ├── gremlin.sh                # Unified Gremlin functions (NEW)
│   ├── deployment.sh             # Shared deployment functions (NEW)
│   ├── common.sh                 # Shared utilities
│   ├── cluster.sh                # Cluster operations
│   ├── monitoring.sh             # Monitoring setup
│   └── ui.sh                     # Interactive UI
├── terraform/
│   └── workspace/                # Generated per deployment
│       └── {subdomain}/
│           ├── main.tf           # FCM module reference
│           ├── variables.tf
│           └── terraform.tf
├── scripts/
│   ├── operations/
│   │   ├── deploy_otel.sh
│   │   ├── deploy_failure_flags.sh
│   │   └── cluster_cleanup.sh
│   └── gremlin_install.sh
├── config/
│   └── gremlin/
│       ├── gremlin_annotations.sh
│       └── healthchecks.sh
└── README.md                     # This file
```

---

## Contributing

### Updating Infrastructure Modules

When Gremlin updates the `fictional-computing-machine` repository:

1. **Test new version:**
   ```bash
   FCM_VERSION=v1.3.0 ./workshop.sh --subdomain test --owner your.name --enable-eks --action create_new
   ```

2. **Update default version:**
   ```bash
   vim lib/terraform.sh
   # Change: FCM_VERSION="${FCM_VERSION:-v1.3.0}"
   ```

3. **Commit and push:**
   ```bash
   git add lib/terraform.sh
   git commit -m "Update fictional-computing-machine to v1.3.0"
   git push
   ```

### Adding New Features

1. Infrastructure changes → Update `fictional-computing-machine` repo
2. Application changes → Update `workshop` scripts
3. Keep separation clean!

---

## License

This workshop is maintained by Gremlin for demonstration purposes.