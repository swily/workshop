#!/bin/bash

# Set environment variables
export CLUSTER_NAME=${CLUSTER_NAME:-current-workshop}
export AWS_DEFAULT_REGION=${AWS_REGION:-us-east-2}

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Setting up public DNS endpoints for Prometheus and Grafana...${NC}"

# Get the first node's external IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')

if [ -z "$NODE_IP" ]; then
    echo -e "${RED}Error: Could not find external IP for any node${NC}"
    exit 1
fi

echo "Using node IP: $NODE_IP"

# Get the Route53 zone ID for gremlinpoc.com
r53_zone_id=$(aws route53 list-hosted-zones-by-name --dns-name gremlinpoc.com | jq -r '.HostedZones[0].Id')
r53_zone_id=${r53_zone_id#/hostedzone/}  # Remove the /hostedzone/ prefix

echo "Using Route53 zone ID: $r53_zone_id"

# Create NodePort services for Prometheus and Grafana
echo -e "${YELLOW}Creating NodePort services...${NC}"

# Create Prometheus NodePort service
kubectl patch svc prometheus -n otel-demo -p '{"spec":{"type":"NodePort","ports":[{"port":9090,"targetPort":9090,"nodePort":30090}]}}'

# Create Grafana NodePort service  
kubectl patch svc grafana -n otel-demo -p '{"spec":{"type":"NodePort","ports":[{"port":80,"targetPort":3000,"nodePort":30100}]}}'

# Wait for services to be ready
sleep 5

# Create DNS record for Prometheus
prometheus_dns="${CLUSTER_NAME}-prometheus.gremlinpoc.com"
echo "Creating DNS record for Prometheus: $prometheus_dns -> $NODE_IP:30090"

aws route53 change-resource-record-sets --hosted-zone-id "$r53_zone_id" --change-batch "{
  \"Changes\": [
    {
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"${prometheus_dns}\",
        \"Type\": \"A\",
        \"TTL\": 300,
        \"ResourceRecords\": [
          {
            \"Value\": \"$NODE_IP\"
          }
        ]
      }
    }
  ]
}"

# Create DNS record for Grafana
grafana_dns="${CLUSTER_NAME}-grafana-monitoring.gremlinpoc.com"
echo "Creating DNS record for Grafana: $grafana_dns -> $NODE_IP:30100"

aws route53 change-resource-record-sets --hosted-zone-id "$r53_zone_id" --change-batch "{
  \"Changes\": [
    {
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"${grafana_dns}\",
        \"Type\": \"A\",
        \"TTL\": 300,
        \"ResourceRecords\": [
          {
            \"Value\": \"$NODE_IP\"
          }
        ]
      }
    }
  ]
}"

echo ""
echo -e "${GREEN}DNS Records have been updated for monitoring services ✅${NC}"
echo ""
echo "Your public monitoring endpoints are:"
echo ""
echo -e "${GREEN}Prometheus - http://${prometheus_dns}:30090${NC}"
echo -e "${GREEN}Grafana    - http://${grafana_dns}:30100${NC}"
echo ""
echo "Health check endpoints:"
echo -e "${YELLOW}Prometheus Alerts: http://${prometheus_dns}:30090/api/v1/alerts${NC}"
echo -e "${YELLOW}Grafana Health:    http://${grafana_dns}:30100/api/health${NC}"
echo ""
echo "Note: It may take a few minutes for DNS changes to propagate"

# Export variables for use in other scripts
export PROMETHEUS_PUBLIC_URL="http://${prometheus_dns}:30090"
export GRAFANA_PUBLIC_URL="http://${grafana_dns}:30100"

echo ""
echo "Environment variables set:"
echo "PROMETHEUS_PUBLIC_URL=$PROMETHEUS_PUBLIC_URL"
echo "GRAFANA_PUBLIC_URL=$GRAFANA_PUBLIC_URL"
