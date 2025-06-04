#!/bin/bash -e

export AWS_DEFAULT_REGION=us-east-2
export AWS_REGION=us-east-2

if [ -z "${EXPIRATION}" ]; then
  EXPIRATION=$(date -v +7d  +%Y-%m-%d)
fi  

if [ -z "${OWNER}" ]; then
  OWNER="$(whoami)"
fi

# CLI team number takes precedence over env var.
if [ -n "${1}" ]; then
    TEAM_NUMBER="${1}"
elif [ -z "${TEAM_NUMBER}" ]; then
  echo "Please provide a group number as CLI arg or set TEAM_NUMBER env var."
  exit 1
fi

if [ ${TEAM_NUMBER} -gt 20 ] || [ ${TEAM_NUMBER} -lt 1 ]; then
  echo "Team number must be between 1 and 20."
  exit 1
fi

if [ ${TEAM_NUMBER} -lt 10 ]; then
  TEAM_NUMBER="0${TEAM_NUMBER}"
fi

# Idenfity the services that we care about.
SERVICES="otel-demo-accountingservice otel-demo-adservice otel-demo-cartservice otel-demo-frontend otel-demo-frauddetectionservice otel-demo-checkoutservice otel-demo-productcatalogservice otel-demo-currencyservice otel-demo-emailservice otel-demo-paymentservice otel-demo-quoteservice otel-demo-recommendationservice otel-demo-shippingservice"

# Update kubeconfig
eksctl utils write-kubeconfig --cluster otel-bootcamp-group-${TEAM_NUMBER}

# OTEL
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>&1 | grep -v skipping
helm repo update
helm get values otel-demo -n otel-demo > /dev/null || helm install otel-demo open-telemetry/opentelemetry-demo --version 0.34.2 --create-namespace -n otel-demo --values ./templates/otelcol-config-extras.yaml

for deployment in $(kubectl get deployment -n otel-demo -o jsonpath='{.items[*].metadata.name}'); do
  if [ -z "$(echo $SERVICES | grep ${deployment})" ]; then
    continue
  fi
  echo "Annotating: $deployment"
  # ADD SERVICE ANNOTATIONS
  kubectl annotate deployment $deployment -n otel-demo "gremlin.com/service-id=group-${TEAM_NUMBER}-${deployment}" --overwrite
# SCALE DEPLOYMENTS
  kubectl scale deployment $deployment -n otel-demo --replicas=2
done

# INSTALL GREMLIN
echo "Installing Gremlin for group-${TEAM_NUMBER}"
bash ./subscripts/install_gremlin.sh ${TEAM_NUMBER}

# INSTALL DYNATRACE
echo "Installing Dynatrace for group-${TEAM_NUMBER}"
bash ./subscripts/install_dynatrace_oneagent.sh ${TEAM_NUMBER}