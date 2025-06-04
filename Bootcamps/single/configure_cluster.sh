#!/bin/bash -e

export AWS_DEFAULT_REGION=us-east-2
export AWS_REGION=us-east-2

if [ -z "${EXPIRATION}" ]; then
  EXPIRATION=$(date -v +7d  +%Y-%m-%d)
fi  

if [ -z "${OWNER}" ]; then
  OWNER="$(whoami)"
fi

if [ -z "${CLUSTER_NAME}" ]; then
  echo "CLUSTER_NAME environment variable must be set"
  exit 1
fi

# Identify the services that we care about.
SERVICES="otel-demo-accountingservice otel-demo-adservice otel-demo-cartservice otel-demo-frontend otel-demo-frauddetectionservice otel-demo-checkoutservice otel-demo-productcatalogservice otel-demo-currencyservice otel-demo-emailservice otel-demo-paymentservice otel-demo-quoteservice otel-demo-recommendationservice otel-demo-shippingservice"

# Update kubeconfig
eksctl utils write-kubeconfig --cluster ${CLUSTER_NAME}

# Install Prometheus Operator
echo "Installing Prometheus Operator..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm get values prometheus-operator -n monitoring > /dev/null || \
  helm install prometheus-operator prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --values ./templates/prometheus-operator-values.yaml

# Apply ServiceMonitors
kubectl apply -f ./templates/service-monitors.yaml

# OTEL
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>&1 | grep -v skipping
helm repo update

# Create namespace for OpenTelemetry demo
kubectl create namespace otel-demo 2>/dev/null || true

# Note: Secret creation for external exporters has been removed as they are not used
# Uncomment the following if you enable Datadog, New Relic, or Dynatrace exporters:
# kubectl create secret generic otelcol-keys -n otel-demo \
#   --from-literal=DD_API_KEY=dummy \
#   --from-literal=DD_SITE_PARAMETER=datadoghq.com \
#   --from-literal=NR_API_KEY=dummy \
#   --from-literal=NR_API_ENDPOINT=https://otlp.nr-data.net \
#   --from-literal=DT_API_TOKEN=dummy \
#   --from-literal=DT_OTLP_ENDPOINT=https://dummy.live.dynatrace.com/api/v2/otlp

helm get values otel-demo -n otel-demo > /dev/null || helm install otel-demo open-telemetry/opentelemetry-demo --version 0.34.2 --create-namespace -n otel-demo --values ./templates/otelcol-config-extras.yaml

for deployment in $(kubectl get deployment -n otel-demo -o jsonpath='{.items[*].metadata.name}'); do
  if [ -z "$(echo $SERVICES | grep ${deployment})" ]; then
    continue
  fi
  echo "Annotating: $deployment"
  # ADD SERVICE ANNOTATIONS
  kubectl annotate deployment $deployment -n otel-demo "gremlin.com/service-id=${CLUSTER_NAME}-${deployment}" --overwrite
  # SCALE DEPLOYMENTS
  kubectl scale deployment $deployment -n otel-demo --replicas=2
done

# INSTALL GREMLIN
echo "Installing Gremlin for ${CLUSTER_NAME}"
bash "$( dirname "${BASH_SOURCE[0]}" )/install_gremlin.sh"

# INSTALL DYNATRACE
# echo "Installing Dynatrace for ${CLUSTER_NAME}"
#bash ./install_dynatrace_oneagent.sh