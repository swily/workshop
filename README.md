# Workshop - Unified Observability Platform

A comprehensive framework for deploying and managing observability platforms (Dynatrace, New Relic, Grafana) with automated setup, health checks, and Gremlin chaos engineering integration.

## Prerequisites

Before starting, ensure you have the following tools installed and configured:

### Required Tools
- **AWS CLI** - Installed and configured with your credentials (`aws configure`)
- **kubectl** - Kubernetes command-line tool
- **eksctl** - Amazon EKS command-line tool  
- **Helm v3** - Kubernetes package manager
- **jq** - JSON processor for parsing API responses
- **curl** - Command-line tool for HTTP requests

### AWS Configuration
Ensure your AWS CLI is configured with:
```bash
aws configure list
# Should show your access key, secret key, region, and output format
```

### Kubernetes Context
Verify kubectl can access your cluster:
```bash
kubectl config current-context
kubectl cluster-info
```

### Optional Platform Accounts
For observability platform integration, you'll need accounts and credentials for:
- **Gremlin** - Team ID and Team Secret for chaos engineering

## Quick Start (Modern Workflow)

1. **Create a new cluster and deploy everything (minimal inputs):**
   ```bash
   ./workshop.sh --action build_new --cluster-name my-demo --region us-east-2
   ```

2. **Deploy to existing cluster:**
   ```bash
   ./workshop.sh --action deploy_existing --cluster-name my-demo --region us-east-2
   ```

3. **Install Gremlin only (existing cluster):**
   ```bash
   ./workshop.sh --action gremlin_only --cluster-name my-demo --region us-east-2
   # Provide GREMLIN_TEAM_ID / GREMLIN_TEAM_SECRET / GREMLIN_API_KEY via env or prompts
   ```

## What's Included

- **OpenTelemetry Demo**: Full e-commerce application with distributed tracing
- **Enhanced Load Testing**: Chaos-engineering optimized locustfile.py with Gremlin integration
- **Production-Ready Configuration**: Security contexts, resource limits, ALB ingress
- **Monitoring Stack**: Prometheus, Grafana, Jaeger, OpenSearch for full observability
- **Chaos Engineering**: Gremlin integration for reliability testing
- **AWS ALB Integration**: Application Load Balancer with health checks and auto-scaling
- **ExternalDNS**: Automatically creates Route53 DNS records
- **TLS at ALB via ACM**: Wildcard cert `*.gremlin.poc.com` auto-discovered per region

## Architecture (ALB-first, DNS/TLS automated)

The workshop deploys:
- EKS cluster with managed node groups and ALB controller
- OpenTelemetry demo application (microservices) with enhanced configuration
- **ALB Ingress** for internet-facing access (replaces manual load balancer setup)
- Prometheus + Grafana + OpenSearch monitoring stack
- Jaeger distributed tracing with exemplar integration
- Advanced load generator with chaos testing scenarios
- Gremlin chaos engineering platform with Istio integration

## Prerequisites

- AWS CLI configured with appropriate permissions
- kubectl installed
- Helm 3.x installed
- **AWS Load Balancer Controller** (automatically installed)
- Docker (for local development)

## Domain & TLS Automation

- **Fixed Base Domain**: `gremlin.poc.com` (no user input)
- **TLS**: If a wildcard ACM certificate `*.gremlin.poc.com` exists in the target AWS region, the system automatically enables HTTPS at the ALB and redirects HTTP→HTTPS. If not found, it falls back to HTTP-only.
- **DNS**: ExternalDNS creates records like `my-demo-frontend.gremlin.poc.com`, `my-demo-grafana.gremlin.poc.com`, `my-demo-prometheus.gremlin.poc.com`.

### Prerequisites for DNS/TLS

1) Route53 hosted zone for `gremlin.poc.com` in your AWS account

2) Wildcard ACM certificate `*.gremlin.poc.com` in the same region as your cluster/ALB (e.g., `us-east-2`). ACM auto-discovery selects it if present.

3) ExternalDNS IAM Role (IRSA)

- Recommended: provide the IAM role ARN via env var `EXTERNALDNS_IAM_ROLE_ARN` so the installer can attach it to ExternalDNS.
- Minimal IAM policy example (replace `Z1234567890ABCDEFG` with your hosted zone ID):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/Z1234567890ABCDEFG"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets"
      ],
      "Resource": ["*"]
    }
  ]
}
```

Attach this policy to a role that trusts your EKS OIDC provider and the ExternalDNS service account (IRSA). Then export:

```bash
export EXTERNALDNS_IAM_ROLE_ARN=arn:aws:iam::<ACCOUNT_ID>:role/<ExternalDNSRole>
```

The workshop will install ExternalDNS automatically when `BASE_DOMAIN` is set (it is fixed to `gremlin.poc.com`).

### LOCUST_HOST automation

- After deployment, `scripts/operations/deploy_otel.sh` sets `LOCUST_HOST` on the load-generator Deployment using:
  - Preferred FQDN from `${CLUSTER_NAME}-frontend.gremlin.poc.com` if DNS is present
  - Fallback to ALB hostname from the `frontend-proxy` Ingress until DNS propagates

---

## Directory Structure

- `build_scripts/` - Core deployment scripts
  - `demo/otel-demo-values-enhanced.yaml` - **Production-ready configuration**
  - `demo/locustfile.py` - **Enhanced chaos testing scenarios**
  - `demo/update_loadgen_alb.sh` - ALB integration script
- `config/` - Configuration files and patches
- `helper_scripts/` - Utility scripts for maintenance
- `monitoring/` - Monitoring stack configurations
- `patches/` - Kubernetes patches (legacy - mostly replaced by enhanced config)

## Configuration Modes

### Enhanced Configuration (Recommended)
- **Production-ready** with security contexts and resource limits
- **ALB ingress** with automatic load balancer provisioning
- **Advanced load testing** with Gremlin chaos scenarios
- **Comprehensive monitoring** with OpenSearch logging
- **Auto-scaling** and health check integration

### Basic Configuration (Legacy)
- Standard OpenTelemetry demo setup
- Manual load balancer creation
- Basic load testing scenarios
- Minimal resource configuration
# Deploy with enhanced visual output
cd build_scripts/demo
./otel_demo.sh
```

#### 3. Setup Monitoring Platforms (Number-Based)
```bash
cd monitoring
./setup_monitoring_numbered.sh 1  # Prometheus & Grafana
./setup_monitoring_numbered.sh 2  # Dynatrace (optional)
./setup_monitoring_numbered.sh 3  # New Relic (optional)
cd monitoring

# Setup individual platforms
./setup_monitoring.sh --dynatrace     # Dynatrace + Prometheus
./setup_monitoring.sh --newrelic      # New Relic + Prometheus  
./setup_monitoring.sh --grafana       # Grafana health checks
./setup_monitoring.sh --prometheus-only  # Prometheus only

# Setup multiple platforms
./setup_monitoring.sh --dynatrace --newrelic --grafana

# Setup all platforms
./setup_monitoring.sh --all
```

## Repository Structure

### build_scripts/
**Main deployment and configuration scripts:**
- `cluster/create.sh` - Creates EKS cluster with VPC CNI and security groups
- `cluster/base_setup.sh` - Configures base cluster components and monitoring
- `demo/otel_demo.sh` - **Enhanced** OpenTelemetry Demo with progressive ASCII art deployment
- `demo/otel-demo-values.yaml` - **Updated** Helm values with fixed Prometheus and accounting configs
- `gremlin/install.sh` - Interactive Gremlin installation with team/cluster configuration
- `load-balancer/install.sh` - Load balancer setup for service exposure

### monitoring/
**Unified observability platform management:**
- `setup_monitoring.sh` - **Enhanced** master script with individual platform options
- `prometheus/install/install.sh` - Baseline Prometheus/Grafana stack installation
- `dynatrace/install/install.sh` - **Fully automated** Dynatrace setup with health checks
- `newrelic/install/install.sh` - **Enhanced** New Relic setup with API key automation
- `newrelic/auth/generate_api_key.sh` - **NEW** Automated New Relic API key generation
- `newrelic/health_check/setup_health_check.sh` - **Enhanced** with Gremlin integration
- `grafana/install/install.sh` - **NEW** Automated Grafana health check setup
- `grafana/auth/create_grafana_token.sh` - **NEW** Automated Grafana token generation
- `grafana/health_check/setup_health_check.sh` - **Existing** Grafana alert management
- `datadog/install/install.sh` - DataDog integration (placeholder)

### helper_scripts/
**Utility and support scripts:**
- `configure_otel_demo_observability.sh` - OpenTelemetry observability configuration
- `cleanup/` - Comprehensive cluster and resource cleanup scripts
- `templates/` - YAML configuration templates

**Dynatrace entity mapping and configuration:**
- `generate_entity_mapping.sh` - Creates entity mapping between service names and Dynatrace entity IDs

### Additional Tools
**Standalone utility scripts in root directory:**
- `create_grafana_api_key.sh` - Legacy Grafana API key creation (use monitoring/grafana/auth/ instead)
- `generate_grafana_token.sh` - Legacy Grafana token generation (use monitoring/grafana/auth/ instead)
- `get_nobl9_token.sh` - Nobl9 SLO platform token generation and status checking
- `run_gremlin_experiments.sh` - Comprehensive Gremlin chaos engineering experiment runner

## Advanced Usage

### Monitoring Platform Management

The unified monitoring framework provides comprehensive platform management:

```bash
cd monitoring

# Check status of all platforms
./setup_monitoring.sh --status

# Remove all monitoring installations
./setup_monitoring.sh --remove

# Install with custom cluster name
./setup_monitoring.sh --cluster-name my-cluster --dynatrace

# Skip health check setup
./setup_monitoring.sh --dynatrace --no-health-checks
```

### Automated API Key Generation

Each platform includes automated credential management:

```bash
# Generate New Relic API key
./monitoring/newrelic/auth/generate_api_key.sh

# Create Grafana service account and token
./monitoring/grafana/auth/create_grafana_token.sh \
  --grafana-url http://localhost:3000 \
  --service-account-name gremlin-health-check
```

### Health Check Integration

All platforms support automated health check setup with Gremlin integration:

```bash
# Setup New Relic health checks
./monitoring/newrelic/health_check/setup_health_check.sh \
  --api-key YOUR_API_KEY \
  --namespace otel-demo \
  --service frontend

# Setup Grafana health checks  
./monitoring/grafana/health_check/setup_health_check.sh \
  --grafana-url http://localhost:3000 \
  --api-key YOUR_TOKEN \
  --alert-name otel-demo-health-check
```

### Gremlin Chaos Engineering

Enhanced Gremlin installation with interactive configuration:

```bash
cd build_scripts/gremlin
./install.sh

# Or with parameters
./install.sh --team-id YOUR_TEAM_ID \
              --team-secret YOUR_SECRET \
              --cluster-id custom-cluster-name \
              --tag-namespaces otel-demo,monitoring
```

## Platform Status & Features

| Platform | Installation | Token Generation | Health Checks | Gremlin Integration | Status |
|----------|-------------|------------------|---------------|-------------------|---------|
| **Dynatrace** | ✅ Fully Automated | ✅ Automated | ✅ Automated | ✅ Complete | **Production Ready** |
| **New Relic** | ✅ Fully Automated | ✅ **NEW** Automated | ✅ **Enhanced** | ✅ Complete | **Production Ready** |
| **Grafana** | ✅ **NEW** Integrated | ✅ **NEW** Automated | ✅ **NEW** Automated | ✅ Complete | **Production Ready** |
| **DataDog** | ⚠️ Placeholder | ❌ Manual | ❌ Manual | ❌ None | **Planned** |
| **Nobl9** | ⚠️ Experimental | ✅ Available | ⚠️ Basic | ⚠️ Partial | **Experimental** |

## Service Access

### Grafana Dashboard
```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Access: http://localhost:3000
# Username: admin
# Password: Retrieved from Kubernetes secret (auto-detected by scripts)
```

### Prometheus Metrics
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Access: http://localhost:9090
```

### OpenTelemetry Demo Services
```bash
# Use the provided port-forward script after deployment
./build_scripts/demo/port-forward-services.sh
# Access various services on different ports
```

### Jaeger Tracing
```bash
kubectl port-forward -n otel-demo svc/jaeger-query 16686:16686
# Access: http://localhost:16686
```

## Troubleshooting

### Common Issues

**1. Prometheus Pod CrashLoopBackOff**
- **Cause**: Duplicate YAML configuration sections
- **Fix**: Use updated `otel-demo-values.yaml` with fixed Prometheus config

**2. Accounting Service Segmentation Fault**
- **Cause**: Insufficient memory allocation
- **Fix**: Increased memory limits in Helm values (already applied)

**3. Jaeger Not Showing Traces**
- **Cause**: Incorrect OTel Collector exporter configuration
- **Fix**: Use OTLP exporter instead of deprecated Jaeger exporter (already fixed)

**4. API Key Generation Failures**
- **Cause**: Missing authentication or network issues
- **Fix**: Verify platform credentials and network connectivity

### Getting Help

For platform-specific issues:
- Check the `monitoring/docs/` directory for detailed troubleshooting guides
- Review configuration files in `monitoring/config/`
- Examine logs: `kubectl logs -n <namespace> <pod-name>`

## Security Considerations

- API keys and tokens are stored securely outside the repository
- Reference file: `api_keys_reference.txt` (not committed to git)
- Scripts prompt for credentials or read from environment variables
- Kubernetes secrets are used for sensitive data storage