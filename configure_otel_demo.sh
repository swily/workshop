#!/bin/bash -e

if [ -z "${CLUSTER_NAME}" ]; then
  echo "CLUSTER_NAME environment variable must be set"
  exit 1
fi

# Identify the services that we care about
SERVICES="otel-demo-accountingservice otel-demo-adservice otel-demo-cartservice otel-demo-frontend otel-demo-frauddetectionservice otel-demo-checkoutservice otel-demo-productcatalogservice otel-demo-currencyservice otel-demo-emailservice otel-demo-paymentservice otel-demo-quoteservice otel-demo-recommendationservice otel-demo-shippingservice"

# Install OpenTelemetry Demo
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# Create namespace for OpenTelemetry demo
kubectl create namespace otel-demo 2>/dev/null || true

helm install otel-demo open-telemetry/opentelemetry-demo \
  --version 0.34.2 \
  --create-namespace \
  -n otel-demo \
  --values ./templates/otelcol-config-extras.yaml

# Wait for deployments to be created and ready
for service in $SERVICES; do
    while ! kubectl get deployment -n otel-demo $service >/dev/null 2>&1; do
        sleep 2
    done
    kubectl rollout status deployment -n otel-demo $service --timeout=300s
done

# Function to convert deployment name to desired service name format
get_service_name() {
  local deployment=$1
  
  # Remove the otel-demo- prefix
  local service_name=${deployment#otel-demo-}
  
  # Convert camelCase to snake_case
  service_name=$(echo $service_name | sed 's/\([a-z0-9]\)\([A-Z]\)/\1_\L\2/g')
  
  # Add _service suffix if it doesn't already end with 'service'
  if [[ ! $service_name =~ .*service$ ]]; then
    service_name="${service_name}_service"
  fi
  
  echo $service_name
}

# Annotate and scale deployments
for deployment in $(kubectl get deployment -n otel-demo -o jsonpath='{.items[*].metadata.name}'); do
  if [ -z "$(echo $SERVICES | grep ${deployment})" ]; then
    continue
  fi
  
  # Get the desired service name
  service_name=$(get_service_name $deployment)
  
  echo "Annotating $deployment with service name: $service_name"
  kubectl annotate deployment $deployment -n otel-demo "gremlin.com/service-id=$service_name" --overwrite
  kubectl scale deployment $deployment -n otel-demo --replicas=2
done

# Apply frontend service
kubectl apply -f ./templates/frontend-service.yaml

# Install Gremlin
bash "$( dirname "${BASH_SOURCE[0]}" )/subscripts/install_gremlin.sh"
