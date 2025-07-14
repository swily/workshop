# Workshop

## Grafana Instances

This setup includes two Grafana instances with different purposes:

1. **OpenTelemetry Demo Grafana** (port 3001)
   - Access: http://localhost:3001/grafana
   - Default credentials: admin/otel
   - Purpose: Contains OpenTelemetry-specific dashboards including:
     - Demo Dashboard
     - Service Graph
     - Service Performance
     - Span Metrics
   - Best for: Viewing application-level metrics and traces from the OpenTelemetry demo

2. **Monitoring Grafana** (port 3000)
   - Access: http://localhost:3000
   - Default credentials: admin/prom-operator
   - Purpose: Contains comprehensive Kubernetes and system monitoring dashboards including:
     - Kubernetes / Compute Resources / Cluster
     - Kubernetes / Compute Resources / Namespace (Pods)
     - Kubernetes / Compute Resources / Node (Pods)
     - Node Exporter / USE Method / Node
   - Best for: Monitoring infrastructure metrics, node resources, and cluster health

### For Gremlin Experiments
For tracking Gremlin latency or network experiments, the **Monitoring Grafana (port 3000)** is the better choice as it provides:
- Detailed node and pod resource metrics
- Network traffic monitoring
- System-level performance metrics
- Kubernetes-specific metrics that are essential for infrastructure chaos engineering

## Repository Structure and Scripts

### Main Deployment Scripts

1. **`build_one.sh`** - Main orchestration script that automates the entire deployment:
   - Creates the EKS cluster using `build_cluster.sh`
   - Waits for cluster stabilization
   - Configures base components using `configure_cluster_base.sh`
   - Deploys the OpenTelemetry demo using `configure_otel_demo.sh`
   - Outputs access URLs and DNS setup instructions
   ```bash
   ./build_one.sh
   ```

2. **`build_cluster.sh`** - Creates the EKS cluster using eksctl
   ```bash
   ./build_cluster.sh
   ```

3. **`configure_cluster_base.sh`** - Sets up base cluster components:
   - AWS Load Balancer Controller
   - IAM roles and policies
   - Subnet tagging
   - Istio service mesh
   ```bash
   ./configure_cluster_base.sh
   ```

4. **`configure_otel_demo.sh`** - Deploys the OpenTelemetry demo and monitoring stack:
   - Prometheus Operator
   - OpenTelemetry Collector
   - Grafana dashboards
   - Service Monitors
   - Gremlin integration
   ```bash
   ./configure_otel_demo.sh
   ```

### Utility Scripts

- **`clean_cluster.sh`** - Cleans up cluster resources while preserving the cluster
  ```bash
  ./clean_cluster.sh
  ```

- **`delete_cluster.sh`** - Completely deletes the EKS cluster and all resources
  ```bash
  ./delete_cluster.sh
  ```

- **`refresh_dns_record.sh`** - Updates Route53 DNS records for services
  ```bash
  # For frontend
  ./refresh_dns_record.sh
  
  # For Grafana
  ./refresh_dns_record.sh -s prometheus-operator-grafana -n monitoring -p grafana
  ```

### Directory Structure

```
/
├── build_one.sh                # Main orchestration script
├── build_cluster.sh            # Creates EKS cluster
├── configure_cluster_base.sh    # Sets up base infrastructure
├── configure_otel_demo.sh       # Deploys OpenTelemetry demo
├── clean_cluster.sh            # Cleans cluster resources
├── delete_cluster.sh           # Deletes the entire cluster
├── refresh_dns_record.sh       # Updates Route53 DNS records
├── dashboards/                 # Grafana dashboards
├── scripts/                    # Helper scripts
│   └── setup_port_forwards.sh
├── subscripts/                 # Installation scripts
│   └── install_gremlin.sh
└── config/                     # Configuration files
    ├── gremlin-values-custom.yaml
    └── otel-demo-values.yaml
```

## Prerequisites

Before starting, ensure you have the following installed and configured:

1. AWS CLI installed and configured with your credentials (`aws configure`)
2. `eksctl` installed
3. `kubectl` installed
4. A Gremlin account with Team ID and Team Secret
5. `istioctl` (will be installed automatically if not present)

## Istio Configuration

This workshop uses Istio 1.18.0 for service mesh capabilities. The installation is handled automatically by the setup scripts.

Key Istio components:
- Istio Control Plane (istiod)
- Ingress Gateway (LoadBalancer type with AWS NLB)
- Egress Gateway
- Kiali for service mesh observability
- Jaeger for distributed tracing

To modify the Istio version, set the `ISTIO_VERSION` environment variable before running the setup:

```bash
export ISTIO_VERSION=1.18.0  # Default version
./build_one.sh
```

## Setup

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd workshop
   ```

2. Set required environment variables:
   ```bash
   # Set your desired EKS cluster name
   export CLUSTER_NAME=your-cluster-name

This script:
1. Creates an EKS cluster
2. Waits for cluster stabilization
3. Installs Prometheus and Grafana
4. Deploys the OpenTelemetry demo application
5. Configures Gremlin for chaos engineering



## Monitoring

### Grafana Dashboards

The following optimized dashboards are available:

1. **CPU Dashboard**
   - Container CPU usage with recording rules
   - 30-second refresh interval
   - Optimized query performance

2. **Memory Dashboard**
   - Container memory metrics
   - Working set and cache monitoring
   - Pre-computed recording rules

3. **Network HTTP Dashboard**
   - HTTP request rates
   - DNS request latency
   - Error rates monitoring

4. **Latency Dashboard**
   - API server request durations
   - CoreDNS performance
   - Kubelet and REST client latency

### Access

Grafana is accessible via LoadBalancer service. The URL will be displayed after deployment completion.

Default credentials:
- Username: admin
- Password: (retrieved from Kubernetes secret)

## Chaos Engineering

Gremlin is automatically configured with:
- Service-level targeting using Kubernetes annotations
- Cluster identification for experiments
- Full integration with monitoring stack

Refer to Gremlin documentation for running chaos experiments.
