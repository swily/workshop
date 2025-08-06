#!/bin/bash -e

# Show help information
show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo "Configure OpenTelemetry Demo in the EKS cluster."
  echo ""
  echo "Options:"
  echo "  -n, --cluster-name NAME   Specify the cluster name to configure"
  echo "  -h, --help                Show this help message"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--cluster-name)
      export CLUSTER_NAME="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Error: Unknown parameter: $1"
      show_help
      exit 1
      ;;
  esac
done

# Set default cluster name if not provided
if [ -z "${CLUSTER_NAME}" ]; then
  CLUSTER_NAME="current-workshop"
  echo "CLUSTER_NAME not set, using default: ${CLUSTER_NAME}"
fi

# Identify the services that we care about
SERVICES="otel-demo-accountingservice otel-demo-adservice otel-demo-cartservice otel-demo-frontend otel-demo-frauddetectionservice otel-demo-checkoutservice otel-demo-productcatalogservice otel-demo-currencyservice otel-demo-emailservice otel-demo-paymentservice otel-demo-quoteservice otel-demo-recommendationservice otel-demo-shippingservice"

# Install Prometheus Operator for monitoring
echo "=== Installing Prometheus Operator ==="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Check if monitoring namespace exists (should be created by configure_cluster_base.sh)
if ! kubectl get namespace monitoring &>/dev/null; then
  echo -e "\n⚠️  Warning: Monitoring namespace not found!"
  echo "It seems the monitoring stack was not installed."
  echo "You can install it by running:"
  echo "  ./configure_cluster_base.sh -n ${CLUSTER_NAME} -m prometheus"
  echo ""
  read -p "Do you want to continue without monitoring? (y/n): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation aborted. Please install monitoring first."
    exit 1
  fi
  echo "Continuing without monitoring..."
fi

# Install OpenTelemetry Demo
echo -e "\n=== Installing OpenTelemetry Demo ==="
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# Create namespace for OpenTelemetry demo
kubectl create namespace otel-demo 2>/dev/null || true

# Create a values file for the OpenTelemetry demo
cat <<EOF > /tmp/otel-demo-values.yaml
opentelemetry-collector:
  config:
    exporters:
      prometheus:
        endpoint: "0.0.0.0:8889"
    connectors:
      spanmetrics:
        namespace: ""
        dimensions:
          - name: "http.method"
            default: "GET"
          - name: "http.status_code"
            default: "200"
    service:
      pipelines:
        metrics:
          receivers: [spanmetrics]
        traces:
          exporters: [spanmetrics]
  ports:
    prom-metrics:
      enabled: true
      containerPort: 8889
      servicePort: 8889
      protocol: TCP
EOF

# Install the OpenTelemetry demo with updated configuration
echo "Installing OpenTelemetry demo with spanmetrics and Prometheus exporter..."
helm upgrade --install otel-demo open-telemetry/opentelemetry-demo \
  --version 0.34.2 \
  --namespace otel-demo \
  --values /tmp/otel-demo-values.yaml

# Remove the redundant Prometheus deployment that comes with the OpenTelemetry demo
echo -e "\n=== Removing redundant Prometheus deployment from otel-demo ==="
kubectl delete deployment otel-demo-prometheus-server -n otel-demo 2>/dev/null || echo "Prometheus deployment not found or already removed"

# Check if Prometheus CRDs are installed
if ! kubectl get crd servicemonitors.monitoring.coreos.com > /dev/null 2>&1; then
  echo "Warning: Prometheus CRDs not found. ServiceMonitor creation will be skipped."
  echo "If you want to monitor the OpenTelemetry Collector with Prometheus, please install the Prometheus Operator."
else
  # Create ServiceMonitor for the OpenTelemetry Collector
  echo -e "\n=== Configuring ServiceMonitor for OpenTelemetry Collector ==="
  cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: otel-collector
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: otelcol
  namespaceSelector:
    matchNames:
      - otel-demo
  endpoints:
    - port: prom-metrics
      path: /metrics
      interval: 30s
EOF
fi

# Scale deployments to 2 replicas for better reliability
echo -e "\n=== Scaling deployments to 2 replicas ==="
for deployment in $(kubectl get deployments -n otel-demo -o jsonpath='{.items[*].metadata.name}'); do
  if [[ "$deployment" != *"grafana"* && "$deployment" != *"jaeger"* && "$deployment" != *"prometheus"* && "$deployment" != *"opensearch"* && "$deployment" != *"kafka"* && "$deployment" != *"loadgenerator"* && "$deployment" != *"valkey"* && "$deployment" != *"flagd"* && "$deployment" != *"imageprovider"* && "$deployment" != *"otelcol"* ]]; then
    echo "Scaling $deployment to 2 replicas"
    kubectl scale deployment $deployment -n otel-demo --replicas=2
  fi
done

echo -e "\n=== OpenTelemetry Demo configuration complete ==="
echo "You can access the demo frontendproxy at: http://localhost:8080 (after port-forwarding)"
echo "To set up port forwarding, run:"
echo "kubectl port-forward svc/otel-demo-frontendproxy -n otel-demo 8080:8080"
echo "You can access Jaeger UI at: http://localhost:16686 (after port-forwarding)"
echo "To set up port forwarding, run:"
echo "kubectl port-forward svc/otel-demo-jaeger-query -n otel-demo 16686:16686"
echo "You can access Grafana at: http://localhost:3000 (after port-forwarding)"
echo "To set up port forwarding, run:"
echo "kubectl port-forward svc/otel-demo-grafana -n otel-demo 3000:80"
