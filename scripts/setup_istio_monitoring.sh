#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Setting up Istio Monitoring ===${NC}"

# Enable Istio addons if not already enabled
if ! kubectl get cm -n istio-system istio-sidecar-injector &> /dev/null; then
    echo -e "${YELLOW}Installing Istio with monitoring addons...${NC}"
    istioctl install --set profile=demo \
        --set addonComponents.prometheus.enabled=true \
        --set addonComponents.kiali.enabled=true \
        --set addonComponents.tracing.enabled=true \
        --set values.prometheus.enabled=true \
        --set values.kiali.enabled=true \
        --set values.tracing.enabled=true \
        --set values.global.tracer.zipkin.address=jaeger-collector.istio-system:9411
else
    echo -e "${GREEN}✓ Istio is already installed${NC}"
fi

# Wait for Istio components to be ready
echo -e "\n${YELLOW}Waiting for Istio components to be ready...${NC}
kubectl wait --for=condition=ready pod -l app=prometheus -n istio-system --timeout=300s
kubectl wait --for=condition=ready pod -l app=kiali -n istio-system --timeout=300s

# Enable automatic sidecar injection for the otel-demo namespace
kubectl label namespace otel-demo istio-injection=enabled --overwrite

# Restart deployments to inject sidecars
echo -e "\n${YELLOW}Restarting deployments to inject Istio sidecars...${NC}
for deployment in $(kubectl get deployments -n otel-demo -o name); do
    kubectl rollout restart $deployment -n otel-demo
    kubectl rollout status $deployment -n otel-demo --timeout=300s
done

echo -e "\n${GREEN}✓ Istio monitoring setup complete!${NC}"
echo -e "\nAccess the following services:"
echo -e "- Kiali:        http://localhost:20001/kiali"
echo -e "- Prometheus:   http://localhost:9090"
echo -e "- Jaeger:      http://localhost:16686"
echo -e "\nTo access them, run:"
echo -e "kubectl port-forward -n istio-system svc/kiali 20001:20001 &"
echo -e "kubectl port-forward -n istio-system svc/prometheus 9090:9090 &"
echo -e "kubectl port-forward -n istio-system svc/tracing 16686:80 &"
