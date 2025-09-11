#!/bin/bash

# Set environment variables
export CLUSTER_NAME=${CLUSTER_NAME:-current-workshop}
export AWS_DEFAULT_REGION=${AWS_REGION:-us-east-2}

# Get the first node's external IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')

if [ -z "$NODE_IP" ]; then
    echo "Error: Could not find external IP for any node"
    exit 1
fi

echo "Using node IP: $NODE_IP"

# Get the Route53 zone ID for gremlinpoc.com
r53_zone_id=$(aws route53 list-hosted-zones-by-name --dns-name gremlinpoc.com | jq -r '.HostedZones[0].Id')
r53_zone_id=${r53_zone_id#/hostedzone/}  # Remove the /hostedzone/ prefix

echo "Using Route53 zone ID: $r53_zone_id"

# Create DNS record for frontend proxy
frontend_dns="${CLUSTER_NAME}-frontend.gremlinpoc.com"
echo "Creating DNS record for frontend: $frontend_dns -> $NODE_IP:32481"

aws route53 change-resource-record-sets --hosted-zone-id "$r53_zone_id" --change-batch "{
  \"Changes\": [
    {
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"${frontend_dns}\",
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
grafana_dns="${CLUSTER_NAME}-grafana.gremlinpoc.com"
echo "Creating DNS record for Grafana: $grafana_dns -> $NODE_IP:30860"

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
echo "DNS Records have been updated for both services ✅"
echo ""
echo "Your links are:"
echo ""
echo "Frontend   - http://${frontend_dns}:32481"
echo "Monitoring - http://${grafana_dns}:30860"
echo ""
echo "Note: It may take a few minutes for DNS changes to propagate"
