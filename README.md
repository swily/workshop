# Workshop

## Repository Structure

All scripts in this repository are designed to be run from the root directory. The main entry point is `build_one.sh`, which orchestrates the cluster creation and configuration process.

```
/
├── build_one.sh                # Main orchestration script
├── build_cluster.sh            # Creates EKS cluster
├── configure_cluster_base.sh    # Sets up monitoring infrastructure
├── configure_otel_demo.sh       # Deploys OpenTelemetry demo
├── clean_cluster.sh            # Cleans cluster resources
├── delete_cluster.sh           # Deletes the entire cluster
├── refresh_dns_record.sh       # Updates Route53 DNS records
├── dashboards/                 # Grafana dashboards
├── subscripts/                 # Helper scripts
│   └── install_gremlin.sh
└── templates/                  # Kubernetes and configuration
    ├── frontend-service.yaml
    ├── gremlin-*-recording-rules.yaml
    ├── kubelet-servicemonitor.yaml
    ├── monitoring-grafana-lb.yaml
    ├── otelcol-config-extras.yaml
    ├── prometheus-operator-values.yaml
    └── service-monitors.yaml
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
