# Kubernetes Monitoring with Prometheus, Istio, and OpenTelemetry

This directory contains the configuration files for setting up monitoring in the Kubernetes cluster, including Prometheus, Istio telemetry, and OpenTelemetry Collector.

## Directory Structure

```
k8s/
├── monitoring/
│   ├── prometheus-rbac.yaml      # RBAC for Prometheus
│   └── prometheus-config.yaml    # Prometheus configuration
└── istio/
    ├── istio-telemetry-config.yaml  # Istio telemetry configuration
    └── istiod-patch.yaml         # Resource limits for Istiod
```

## Setup Instructions

1. **Apply the monitoring configuration**:
   ```bash
   ./scripts/setup-monitoring.sh
   ```

2. **Verify the setup**:
   ```bash
   ./scripts/verify-monitoring.sh
   ```

## Components

### Prometheus

- **RBAC**: Configured with least privilege access to monitor the cluster
- **Scraping**: Set up to scrape metrics from all Istio proxies and other Kubernetes resources
- **Configuration**: Stored in `prometheus-config.yaml`

### Istio

- **Telemetry**: Enabled with Prometheus metrics provider
- **Tracing**: Configured with OpenTelemetry and Jaeger
- **Resource Limits**: Set for the Istio control plane

### OpenTelemetry Collector

- **Metrics**: Configured to receive metrics from Istio and applications
- **Exporters**: Set up to forward metrics to Prometheus

## Verification

After setup, you can verify the monitoring stack by:

1. Accessing Prometheus UI:
   ```bash
   kubectl -n monitoring port-forward svc/prometheus 9090:9090
   ```
   Then open http://localhost:9090 in your browser

2. Checking Istio metrics in Prometheus:
   - Query for `istio_requests_total`
   - Check the "Targets" page for scrape status

## Troubleshooting

- If Prometheus targets are down, check the Prometheus pod logs:
  ```bash
  kubectl -n monitoring logs -l app=prometheus
  ```

- If Istio metrics are missing, check the proxy stats endpoint:
  ```bash
  # Get a pod with Istio proxy
  POD=$(kubectl get pods -n otel-demo -l app=frontend -o jsonpath='{.items[0].metadata.name}')
  
  # Check metrics
  kubectl -n otel-demo exec -it $POD -c istio-proxy -- curl http://localhost:15090/stats/prometheus | grep istio_requests_total
  ```

## Cleanup

To remove the monitoring components:

```bash
# Delete Prometheus resources
kubectl delete -f k8s/monitoring/prometheus-rbac.yaml
kubectl delete configmap -n monitoring prometheus-config

# Revert Istio configuration to defaults
kubectl delete configmap -n istio-system istio
kubectl -n istio-system rollout restart deployment istiod
```
