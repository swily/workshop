#!/bin/bash -e

# Grafana Ingress Deployment Script
# This script deploys an ingress for Grafana to make it accessible for Gremlin health checks

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
CLUSTER_NAME="${CLUSTER_NAME:-current-workshop}"

# Show help information
show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo "Deploy an ingress for Grafana to make it accessible for Gremlin health checks."
  echo ""
  echo "Options:"
  echo "  -n, --cluster-name NAME   Specify the cluster name (default: current-workshop)"
  echo "  -h, --help                Show this help message"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--cluster-name)
      CLUSTER_NAME="$2"
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

echo "=== Deploying Grafana Ingress for cluster: ${CLUSTER_NAME} ==="

# Update kubeconfig
echo "Updating kubeconfig..."
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION:-us-east-2}

# Check if the Grafana service exists (try multiple possible names)
GRAFANA_SERVICE=""
if kubectl get service prometheus-operator-grafana -n monitoring &>/dev/null; then
  GRAFANA_SERVICE="prometheus-operator-grafana"
elif kubectl get service prometheus-grafana -n monitoring &>/dev/null; then
  GRAFANA_SERVICE="prometheus-grafana"
elif kubectl get service grafana -n monitoring &>/dev/null; then
  GRAFANA_SERVICE="grafana"
else
  echo -e "\n${RED}❌ Error: No Grafana service found in monitoring namespace!${NC}"
  echo "Available services in monitoring namespace:"
  kubectl get services -n monitoring
  echo "Please ensure that Grafana is installed before deploying the ingress."
  exit 1
fi

echo -e "${GREEN}✅ Found Grafana service: ${GRAFANA_SERVICE}${NC}"

# Create the ingress directory if it doesn't exist
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
mkdir -p "${SCRIPT_DIR}"

# Create the ingress manifest
INGRESS_FILE="${SCRIPT_DIR}/grafana-ingress.yaml"
echo "Creating Grafana ingress manifest..."

cat > ${INGRESS_FILE} <<EOL
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=600
    alb.ingress.kubernetes.io/healthcheck-path: /api/health
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '15'
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '5'
    alb.ingress.kubernetes.io/healthy-threshold-count: '2'
    alb.ingress.kubernetes.io/unhealthy-threshold-count: '2'
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/security-groups: ${CLUSTER_NAME}-alb-access
    alb.ingress.kubernetes.io/subnets: subnet-08038efe886c31791,subnet-0135b61262e48f4d6,subnet-0fe7be30ec2528c4c
    alb.ingress.kubernetes.io/manage-backend-security-group-rules: "true"
    alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=30
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${GRAFANA_SERVICE}
            port:
              number: 80
EOL

# Apply the ingress manifest
echo "Applying Grafana ingress manifest..."
kubectl apply -f ${INGRESS_FILE}

# Wait for the ingress to be created
echo "Waiting for Grafana load balancer to be provisioned..."
echo "This typically takes 2-3 minutes for AWS ALB provisioning"
echo "Progress will be shown every 30 seconds..."
echo ""

# Check every 30 seconds with improved progress messaging
LB_HOSTNAME="pending"
for i in {1..6}; do
  LB_HOSTNAME=$(kubectl get ingress -n monitoring grafana-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  
  if [[ -n "$LB_HOSTNAME" && "$LB_HOSTNAME" != "null" && "$LB_HOSTNAME" =~ elb\.amazonaws\.com ]]; then
    echo -e "${GREEN}✅ Load balancer ready after $((i*30)) seconds!${NC}"
    break
  fi
  
  # Progress indicator with dots
  dots=""
  for j in $(seq 1 $i); do dots="$dots."; done
  echo -e "${YELLOW}⏳ ALB provisioning in progress$dots ($((i*30))s elapsed)${NC}"
  
  if [ $i -lt 6 ]; then
    sleep 30
  fi
done

if [[ "$LB_HOSTNAME" == "pending" || -z "$LB_HOSTNAME" ]]; then
  echo -e "\n${YELLOW}⚠️ Load balancer is still being provisioned. Please check status later with:${NC}"
  echo "kubectl get ingress -n monitoring grafana-ingress"
  echo -e "${BLUE}Note: ALB provisioning can take up to 5 minutes. This is normal AWS behavior.${NC}"
else
  echo -e "\n${GREEN}✅ Grafana ingress created successfully!${NC}"
  echo "Load balancer hostname: ${LB_HOSTNAME}"
  echo "You can access Grafana at: http://${LB_HOSTNAME}/"
  echo "For Gremlin health checks, use these endpoints:"
  echo "1. Alert instances endpoint: http://${LB_HOSTNAME}/api/alertmanager/grafana/api/v2/alerts"
  echo "2. Alert rules endpoint: http://${LB_HOSTNAME}/api/prometheus/grafana/api/v1/rules"
  echo ""
  echo "Note: It may take a few minutes for DNS to propagate and the load balancer to become fully available."
fi

# Update the health check script with the new URL
HEALTH_CHECK_SCRIPT="/Users/seanwiley/workshop/monitoring/grafana/health_check/setup_health_check.sh"
if [[ -f "$HEALTH_CHECK_SCRIPT" && "$LB_HOSTNAME" != "pending" ]]; then
  echo "Updating health check script with the new Grafana URL..."
  sed -i.bak "s|GRAFANA_URL=\"http://localhost:3000\"|GRAFANA_URL=\"http://${LB_HOSTNAME}\"|g" "$HEALTH_CHECK_SCRIPT"
  echo "Health check script updated with the new Grafana URL"
fi

echo -e "${GREEN}✅ Grafana Ingress Setup Complete${NC}"
