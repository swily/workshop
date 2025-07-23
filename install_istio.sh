#!/bin/bash
set -e

# Exit if not in the workshop directory
if [ "$(basename $(pwd))" != "workshop" ]; then
  echo "Please run this script from the workshop directory"
  exit 1
fi

# Set variables
ISTIO_VERSION=1.18.0
ISTIO_ARCH=osx-arm64  # Change to 'linux-amd64' if needed

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check for required tools
for cmd in kubectl curl tar; do
  if ! command_exists $cmd; then
    echo "Error: $cmd is required but not installed"
    exit 1
  fi
done

# Check if Istio is already installed
if kubectl get namespace istio-system >/dev/null 2>&1; then
  echo "⚠️  Istio is already installed. Uninstalling first..."
  istioctl uninstall --purge -y
  kubectl delete namespace istio-system --grace-period=0 --force 2>/dev/null || true
  kubectl delete namespace istio-demo --grace-period=0 --force 2>/dev/null || true
  sleep 5
fi

# Download and install Istio
if [ ! -d "istio-${ISTIO_VERSION}" ]; then
  echo "📥 Downloading Istio ${ISTIO_VERSION}..."
  curl -L https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-${ISTIO_ARCH}.tar.gz | tar xz
else
  echo "ℹ️  Using existing Istio ${ISTIO_VERSION} directory"
fi

# Add istioctl to PATH
export PATH="$(pwd)/istio-${ISTIO_VERSION}/bin:${PATH}"

# Verify istioctl version
istioctl version --remote=false

# Create istio-system namespace if it doesn't exist
kubectl create namespace istio-system 2>/dev/null || true

# Install Istio with the custom configuration
echo -e "\n🚀 Installing Istio ${ISTIO_VERSION}..."

# First, install the base Istio components
istioctl install -f templates/istio/istio-operator.yaml -y

# Wait for Istiod to be ready
echo -e "\n⏳ Waiting for Istiod to be ready..."
kubectl wait --for=condition=ready pod -n istio-system -l app=istiod --timeout=300s

# Install addons
echo -e "\n📦 Installing Istio addons..."

# 1. Install Prometheus
kubectl apply -f istio-${ISTIO_VERSION}/samples/addons/prometheus.yaml

# 2. Install Jaeger
kubectl apply -f istio-${ISTIO_VERSION}/samples/addons/jaeger.yaml

# 3. Install Kiali
kubectl apply -f istio-${ISTIO_VERSION}/samples/addons/kiali.yaml

# Wait for addons to be ready
echo -e "\n⏳ Waiting for addons to be ready..."

# Wait for Prometheus
if ! kubectl wait --for=condition=ready pod -n istio-system -l app=prometheus --timeout=180s 2>/dev/null; then
  echo "⚠️  Prometheus is taking longer than expected to start..."
fi

# Wait for Jaeger
if ! kubectl wait --for=condition=ready pod -n istio-system -l app=jaeger --timeout=180s 2>/dev/null; then
  echo "⚠️  Jaeger is taking longer than expected to start..."
fi

# Wait for Kiali
if ! kubectl wait --for=condition=ready pod -n istio-system -l app.kubernetes.io/name=kiali --timeout=180s 2>/dev/null; then
  echo "⚠️  Kiali is taking longer than expected to start..."
fi

# Create demo namespace and enable sidecar injection
echo -e "\n🔄 Creating demo namespace with sidecar injection..."
kubectl create namespace istio-demo 2>/dev/null || true
kubectl label namespace istio-demo istio-injection=enabled --overwrite

# Print status
echo -e "\n✅ Istio installation completed!"
echo -e "\n📊 Components status:"
kubectl get pods -n istio-system

echo -e "\n🔌 To access Kiali, run:"
echo "istioctl dashboard kiali --address 0.0.0.0"

echo -e "\n🔌 To access Jaeger, run:"
echo "istioctl dashboard jaeger --address 0.0.0.0"

echo -e "\n🔌 To access Prometheus, run:"
echo "kubectl -n istio-system port-forward svc/prometheus 9090:9090"

echo -e "\n🌐 To access the Istio Ingress Gateway, run:"
echo "kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80"

echo -e "\n🔄 To apply the OpenTelemetry demo configuration, run:"
echo "./configure_otel_demo.sh"

echo -e "\n💡 Note: Some components might take a few minutes to fully initialize."
