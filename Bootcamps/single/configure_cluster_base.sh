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
helm get values prometheus-operator -n monitoring > /dev/null || \
  helm install prometheus-operator prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --values ../templates/prometheus-operator-values.yaml

# Wait for essential Prometheus Operator CRDs
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

# Wait for Prometheus Operator core components to be ready
# Wait for operator
while [[ $(kubectl get pods -n monitoring -l "app.kubernetes.io/name=kube-prometheus-stack-prometheus-operator" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    sleep 5
done

# Wait for Grafana
while [[ $(kubectl get pods -n monitoring -l "app.kubernetes.io/name=grafana" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    sleep 5
done

# Wait for kube-state-metrics
while [[ $(kubectl get pods -n monitoring -l "app.kubernetes.io/name=kube-state-metrics" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    sleep 5
done

# Wait for Prometheus
while [[ $(kubectl get pods -n monitoring -l "app.kubernetes.io/name=prometheus" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    sleep 5
done

# Wait for Alertmanager
while [[ $(kubectl get pods -n monitoring -l "app.kubernetes.io/name=alertmanager" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    sleep 5
done

# Wait an additional 30 seconds for all components to fully initialize
sleep 30

# Apply ServiceMonitors
kubectl apply -f ../templates/service-monitors.yaml
kubectl apply -f ../templates/kubelet-servicemonitor.yaml
