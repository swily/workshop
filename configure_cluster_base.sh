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

# Update kubeconfig
eksctl utils write-kubeconfig --cluster ${CLUSTER_NAME}

# Install Prometheus Operator
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
echo "Checking if Prometheus Operator is installed..."
if ! helm get values prometheus-operator -n monitoring > /dev/null 2>&1; then
  echo "Prometheus Operator not found. Installing..."

  helm install prometheus-operator prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --values ./templates/prometheus-operator-values.yaml
else
  echo "Prometheus Operator found. Waiting for components to be ready..."
fi

echo "Waiting for essential Prometheus Operator CRDs..."

ESSENTIAL_CRDS="prometheuses.monitoring.coreos.com servicemonitors.monitoring.coreos.com"

for crd in $ESSENTIAL_CRDS; do
    while ! kubectl get crd $crd >/dev/null 2>&1; do
        sleep 2
    done
    # Wait for CRD to be fully established
    while [[ $(kubectl get crd $crd -o jsonpath='{.status.conditions[?(@.type=="Established")].status}') != "True" ]]; do
        sleep 2
    done
done

echo "Waiting for Prometheus Operator deployment..."
# Wait for operator
while [[ $(kubectl get pods -n monitoring -l "app.kubernetes.io/name=kube-prometheus-stack-prometheus-operator" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    sleep 5
done

echo "Waiting for Grafana deployment..."
while [[ $(kubectl get pods -n monitoring -l "app.kubernetes.io/name=grafana" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    sleep 5
done

echo "Waiting for kube-state-metrics deployment..."
while [[ $(kubectl get pods -n monitoring -l "app.kubernetes.io/name=kube-state-metrics" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    sleep 5
done

# Wait for Prometheus
while [[ $(kubectl get pods -n monitoring -l "app.kubernetes.io/name=prometheus" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    sleep 5
done

echo "Waiting for Alertmanager deployment..."
while [[ $(kubectl get pods -n monitoring -l "app.kubernetes.io/name=alertmanager" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    sleep 5
done

echo "Waiting 30 seconds for components to fully initialize..."
sleep 30

echo "Applying ServiceMonitors and Grafana LoadBalancer..."
kubectl apply -f ./templates/service-monitors.yaml
kubectl apply -f ./templates/kubelet-servicemonitor.yaml
kubectl apply -f ./templates/monitoring-grafana-lb.yaml

echo "
✅ Base cluster configuration completed successfully!

Next steps:
1. Set your Gremlin credentials as environment variables:
   export TEAM_ID=<your-team-id>
   export TEAM_SECRET=<your-team-secret>

2. Run the OpenTelemetry demo configuration:
   ./configure_otel_demo.sh
"
