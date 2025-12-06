# Workshop - OpenTelemetry Demo with Gremlin Chaos Engineering

Automated deployment of OpenTelemetry Demo application with integrated monitoring (Prometheus/Grafana) and Gremlin chaos engineering on AWS EKS.


---

## What This Does

Deploys a complete chaos engineering demo environment:

- **20 OpenTelemetry microservices** (2 replicas each for dependency detection)
- **Prometheus + Grafana** monitoring with pre-configured dashboards
- **Gremlin agents** for chaos engineering experiments
- **HTTPS endpoints** with automatic DNS configuration
- **Health checks** monitoring service availability

**Access URLs:**
- Frontend: `https://demo-frontend.{your-subdomain}.gremlinpoc.com`
- Grafana: `https://monitoring.{your-subdomain}.gremlinpoc.com` (admin/prom-operator)
- Gremlin: `https://app.gremlin.com/services`

---

## Prerequisites

**Required Tools:**
```bash
# Install via Homebrew (macOS)
brew install awscli terraform kubectl helm jq

# Configure AWS credentials
aws configure
```

**Required Accounts:**
- AWS account with admin permissions
- Gremlin account (sign up at https://app.gremlin.com/signup)

**Gremlin Credentials Needed:**
1. Team ID and Team Secret (Settings → Teams)
2. Team Certificate and Private Key (Settings → Teams → Download)
3. API Key (Settings → API Keys → Create new key with health check permissions)

---

## Quick Start

### Step 1: Store Gremlin Credentials (One-Time Setup)

```bash
# Set your information
export OWNER="john.doe"        # Your name
export AWS_REGION="us-east-2"  # AWS region

# Store Gremlin Team ID (required)
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_id" \
    --secret-string "YOUR_GREMLIN_TEAM_ID" \
    --region $AWS_REGION

# Store Gremlin Team Secret (required)
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_secret" \
    --secret-string "YOUR_GREMLIN_TEAM_SECRET" \
    --region $AWS_REGION

# Store Gremlin API Key (required for health checks)
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_api_key" \
    --secret-string "YOUR_GREMLIN_API_KEY" \
    --region $AWS_REGION

# Store Gremlin Team Certificate (required)
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_certificate" \
    --secret-string "$(cat /path/to/gremlin-cert.pem)" \
    --region $AWS_REGION

# Store Gremlin Team Private Key (required)
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_private_key" \
    --secret-string "$(cat /path/to/gremlin-key.pem)" \
    --region $AWS_REGION
```

**How to get your Gremlin credentials:**
1. Go to https://app.gremlin.com
2. Settings → Teams → Download certificate/key
3. Settings → API Keys → Create new API key (needs health check permissions)

### Step 2: Deploy Everything

```bash
./workshop.sh \
    --action build_new \
    --subdomain johndoe \
    --owner john.doe
```

The script will:
- Create infrastructure with Terraform (~20 minutes)
- Deploy 20 OpenTelemetry microservices (2 replicas each)
- Install Gremlin agents and create health checks
- Deploy Prometheus + Grafana monitoring
- Configure HTTPS with ACM certificates
- Set up DNS records

**Access your deployment:**
- Frontend: `https://demo-frontend.johndoe.gremlinpoc.com`
- Grafana: `https://monitoring.johndoe.gremlinpoc.com` (admin/admin#)
- Gremlin: `https://app.gremlin.com/services`

### Alternative: Deploy to Existing Cluster

If infrastructure already exists:

```bash
./workshop.sh \
    --action deploy_existing \
    --cluster-name johndoe-eks \
    --owner john.doe
```

This will:
- Update/deploy applications (idempotent)
- Scale services to 2 replicas (for dependency detection)
- Update Gremlin annotations
- Refresh health checks
- Update DNS records
- **Does NOT delete** existing resources

---

## Understanding the Flags

### Required Flags

| Flag | Description | Example | Notes |
|------|-------------|---------|-------|
| `--action` | What to do | `build_new`, `deploy_existing`, `cleanup` | See [Actions](#actions) below |
| `--subdomain` | Unique identifier for your deployment | `johndoe`, `demo1`, `test` | Used for DNS: `demo-frontend.{subdomain}.gremlinpoc.com` |
| `--owner` | Your name/identifier | `john.doe`, `jane.smith` | Used for resource tagging and AWS Secrets Manager lookup |

### Optional Flags

| Flag | Description | Default | Example |
|------|-------------|---------|----------|
| `--cluster-name` | EKS cluster name (for deploy_existing) | `{subdomain}-eks` | `--cluster-name my-cluster` |
| `--region` | AWS region | `us-east-2` | `--region us-west-2` |
| `--monitoring` | Monitoring platform | `grafana` | `--monitoring prometheus` |
| `--enable-failure-flags` | Deploy Failure Flags sidecar | `false` | `--enable-failure-flags` |
| `--dry-run` | Show what would happen | (none) | `--dry-run` |

### Credential Flags (Optional)

If you don't want to use Secrets Manager auto-detection:

| Flag | Description | Example |
|------|-------------|---------|
| `--gremlin-team-id-arn` | ARN of Team ID secret | `arn:aws:secretsmanager:us-east-2:123:secret:...` |
| `--gremlin-team-certificate-arn` | ARN of certificate secret | `arn:aws:secretsmanager:us-east-2:123:secret:...` |
| `--gremlin-team-private-key-arn` | ARN of private key secret | `arn:aws:secretsmanager:us-east-2:123:secret:...` |

### Actions

| Action | What It Does | When to Use | Time |
|--------|--------------|-------------|------|
| `build_new` | Create infrastructure + deploy apps | First time deployment | ~20-30 min |
| `deploy_existing` | Update apps on existing cluster | Update/redeploy applications | ~10-15 min |
| `cleanup` | Destroy all resources | Remove deployment | ~10 min |

---

## Credential Management

### How Credentials Are Resolved

The script tries multiple methods in this order:

1. **Explicit ARNs** (if provided via `--gremlin-team-id-arn`, etc.)
2. **Owner-based lookup** (checks `{owner}/gremlin_*` secrets in Secrets Manager)
3. **Environment variables** (`GREMLIN_TEAM_ID`, `GREMLIN_TEAM_CERTIFICATE`, etc.)
4. **Fail with helpful error**

### Secrets Manager (Required)
**Required Secrets:**

```bash
export OWNER="your.name"
export AWS_REGION="us-east-2"

# 1. Team ID (required)
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_id" \
    --secret-string "YOUR_TEAM_ID" \
    --region $AWS_REGION

# 2. Team Secret (required)
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_secret" \
    --secret-string "YOUR_TEAM_SECRET" \
    --region $AWS_REGION

# 3. API Key (required for health checks)
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_api_key" \
    --secret-string "YOUR_API_KEY" \
    --region $AWS_REGION

# 4. Certificate (required)
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_certificate" \
    --secret-string "$(cat /path/to/gremlin-cert.pem)" \
    --region $AWS_REGION

# 5. Private Key (required)
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_private_key" \
    --secret-string "$(cat /path/to/gremlin-key.pem)" \
    --region $AWS_REGION
```

**Usage:**
```bash
./workshop.sh --action build_new --subdomain demo --owner your.name
# Credentials automatically loaded from Secrets Manager!
```

### Method 2: Environment Variables

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

