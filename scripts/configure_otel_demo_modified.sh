#!/bin/bash -e

if [ -z "${CLUSTER_NAME}" ]; then
  echo "CLUSTER_NAME environment variable must be set"
  exit 1
fi

# Identify the services that we care about
SERVICES="otel-demo-accountingservice otel-demo-adservice otel-demo-cartservice otel-demo-frontend otel-demo-frauddetectionservice otel-demo-checkoutservice otel-demo-productcatalogservice otel-demo-currencyservice otel-demo-emailservice otel-demo-paymentservice otel-demo-quoteservice otel-demo-recommendationservice otel-demo-shippingservice"

# Skip Prometheus installation as it's already set up
echo "=== Skipping Prometheus Operator installation (already installed) ==="

# Install OpenTelemetry Demo
echo -e "\n=== Installing OpenTelemetry Demo ==="
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# Create namespace for OpenTelemetry demo
kubectl create namespace otel-demo 2>/dev/null || true

# Install the OpenTelemetry demo with updated configuration
echo "Installing OpenTelemetry demo with spanmetrics and Prometheus exporter..."
helm upgrade --install otel-demo open-telemetry/opentelemetry-demo \
  --version 0.34.2 \
  --namespace otel-demo \
  --values ./templates/otelcol-config-updated.yaml \
  --set opentelemetry-collector.config.exporters.prometheus.endpoint="0.0.0.0:8889" \
  --set opentelemetry-collector.service.ports.prometheus-metrics.port=8889 \
  --set opentelemetry-collector.service.ports.prometheus-metrics.protocol=TCP \
  --set opentelemetry-collector.service.ports.prometheus-metrics.targetPort=8889 \
  --set opentelemetry-collector.service.ports.prometheus-metrics.name=prometheus-metrics

# Remove the redundant Prometheus deployment that comes with the OpenTelemetry demo
echo -e "\n=== Removing redundant Prometheus deployment from otel-demo ==="
kubectl delete deployment prometheus -n otel-demo 2>/dev/null || echo "Prometheus deployment not found or already removed"

# Apply the ServiceMonitor for the OpenTelemetry Collector
echo -e "\n=== Configuring ServiceMonitor for OpenTelemetry Collector ==="
kubectl apply -f ./templates/otel-servicemonitor.yaml

# Configure Grafana datasource
echo -e "\n=== Configuring Grafana datasource ==="
kubectl apply -f - <<EOF
apiVersion: v1
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
    - editable: true
      isDefault: true
      jsonData:
        exemplarTraceIdDestinations:
        - datasourceUid: webstore-traces
          name: trace_id
        - name: trace_id
          url: http://localhost:8080/jaeger/ui/trace/$${__value.raw}
          urlDisplayLabel: View in Jaeger UI
      name: Prometheus
      type: prometheus
      uid: webstore-metrics
      url: http://prometheus-kube-prometheus-prometheus.monitoring:9090
    - editable: true
      isDefault: false
      name: Jaeger
      type: jaeger
      uid: webstore-traces
      url: http://jaeger-query:16686/jaeger/ui
    - access: proxy
      editable: true
      isDefault: false
      jsonData:
        database: otel
        flavor: opensearch
        logLevelField: severity.text.keyword
        logMessageField: body
        pplEnabled: true
        timeField: observedTimestamp
        version: 2.18.0
      name: OpenSearch
      type: grafana-opensearch-datasource
      uid: webstore-logs
      url: http://opensearch:9200/
kind: ConfigMap
metadata:
  name: grafana
  namespace: otel-demo
  labels:
    app.kubernetes.io/instance: otel-demo
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/name: grafana
    app.kubernetes.io/version: 11.5.2
    helm.sh/chart: grafana-8.10.1
  annotations:
    meta.helm.sh/release-name: otel-demo
    meta.helm.sh/release-namespace: otel-demo
EOF

# Restart Grafana to apply the new configuration
echo -e "\n=== Restarting Grafana to apply configuration ==="
kubectl rollout restart deployment/grafana -n otel-demo

# Wait for deployments to be created and ready
echo -e "\n=== Waiting for OpenTelemetry demo deployments to be ready ==="
for service in $SERVICES; do
    echo -n "Waiting for $service to be ready..."
    while ! kubectl get deployment -n otel-demo $service >/dev/null 2>&1; do
        sleep 2
        echo -n "."
    done
    echo -n " ready."
    kubectl rollout status deployment -n otel-demo $service --timeout=300s
    echo
done

echo -e "\n=== OpenTelemetry Demo Installation Complete! ==="
echo "Access the demo application at: http://localhost:8080"
echo "Access Grafana at: http://localhost:3000/grafana"
echo "  - Username: admin"
echo "  - Password: prom-operator"
echo "Access Prometheus at: http://localhost:9090"
echo "Access Jaeger at: http://localhost:16686"

# Set up port-forwarding for easy access
echo -e "\n=== Setting up port forwarding (run in background) ==="
kubectl port-forward -n otel-demo svc/otel-demo-frontend 8080:8080 &
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
kubectl port-forward -n otel-demo svc/otel-demo-jaeger 16686:16686 &

echo -e "\nPort forwarding is running in the background. To stop all port forwards, run:"
echo "pkill -f 'kubectl port-forward'"

# Annotate and scale deployments
echo "Annotating and scaling deployments..."
for deployment in $(kubectl get deployment -n otel-demo -o jsonpath='{.items[*].metadata.name}'); do
  if [ -z "$(echo $SERVICES | grep ${deployment})" ]; then
    continue
  fi
  echo "Annotating and scaling $deployment..."
  
  # Annotate the deployment
  kubectl annotate deployment $deployment -n otel-demo "gremlin.com/service-id=${CLUSTER_NAME}-${deployment}" --overwrite
  
  # Scale the deployment
  kubectl scale deployment $deployment -n otel-demo --replicas=2
  
  # Add Prometheus annotations to services
  # Try with the full deployment name first (with otel-demo- prefix)
  if kubectl get service $deployment -n otel-demo &> /dev/null; then
    kubectl patch service $deployment -n otel-demo --type=merge -p '{"metadata":{"annotations":{"prometheus.io/scrape":"true","prometheus.io/port":"8080"}}}' || true
  else
    # If not found, try without the otel-demo- prefix
    service_name=${deployment#otel-demo-}
    if kubectl get service $service_name -n otel-demo &> /dev/null; then
      kubectl patch service $service_name -n otel-demo --type=merge -p '{"metadata":{"annotations":{"prometheus.io/scrape":"true","prometheus.io/port":"8080"}}}' || true
    fi
  fi
done

# Apply ServiceMonitors
echo "Applying ServiceMonitors..."
kubectl apply -f ./templates/service-monitors.yaml

# Apply frontend service
echo "Applying frontend service..."
kubectl apply -f ./templates/frontend-service.yaml

# Update Gremlin annotations for all services if the script exists
if [ -f "$(dirname "${BASH_SOURCE[0]}")/../update_gremlin_annotations.sh" ]; then
  echo "Updating Gremlin service annotations..."
  "$(dirname "${BASH_SOURCE[0]}")/../update_gremlin_annotations.sh"
else
  echo "Gremlin annotation script not found, skipping..."
fi

# Install Gremlin
echo "Installing Gremlin..."
bash "$( dirname "${BASH_SOURCE[0]}" )/subscripts/install_gremlin.sh"

echo -e "\n=== OpenTelemetry Demo Deployment Complete ==="
echo "Grafana is available at: http://localhost:3000 (after running port-forward)"
echo "To set up port forwarding, run:"
echo "  kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
echo "  kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "  kubectl port-forward -n otel-demo svc/otel-demo-frontend 8080:8080"
