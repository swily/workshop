#!/bin/bash

# Default values
SERVICE_NAME="otel-demo-frontendproxy"
NAMESPACE="otel-demo"
DNS_PREFIX=""

# Validate required environment variables
for var in "AWS_DEFAULT_REGION" "CLUSTER_NAME"; do
    if [ -z "${!var}" ]; then
        echo "Error: $var environment variable is not set"
        exit 1
    fi
done

# Parse command line arguments
while getopts ":s:n:p:" opt; do
  case $opt in
    s) SERVICE_NAME="$OPTARG" ;;
    n) NAMESPACE="$OPTARG" ;;
    p) DNS_PREFIX="$OPTARG" ;;
    \?) echo "Invalid option -$OPTARG" >&2; exit 1 ;;
  esac
done

echo "Using service: $SERVICE_NAME in namespace: $NAMESPACE"

# Get the Route53 zone ID for gremlinpoc.com
r53_zone_id=$(aws route53 list-hosted-zones-by-name --dns-name gremlinpoc.com | jq -r '.HostedZones[0].Id')

# Get the LoadBalancer hostname
record_target=$(kubectl get service $SERVICE_NAME -n $NAMESPACE -o json | jq -r '.status.loadBalancer.ingress[].hostname')

if [ -z "$record_target" ]; then
    echo "Error: Could not find LoadBalancer hostname for service $SERVICE_NAME in namespace $NAMESPACE"
    exit 1
fi

# Get the ELB details
lb_name=$(aws elb describe-load-balancers | jq -r --arg dnsname "$record_target" '.LoadBalancerDescriptions[] | select(.DNSName == $dnsname).LoadBalancerName')
canonical_hosted_zone_name=dualstack.$(aws elb describe-load-balancers --load-balancer-names "$lb_name" | jq -r '.LoadBalancerDescriptions[0].CanonicalHostedZoneName')
canonical_hosted_zone_id=$(aws elb describe-load-balancers --load-balancer-names "$lb_name" | jq -r '.LoadBalancerDescriptions[0].CanonicalHostedZoneNameID')

# Create the DNS record
# Construct DNS name
if [ -n "$DNS_PREFIX" ]; then
    dns_name="${CLUSTER_NAME}-${DNS_PREFIX}.gremlinpoc.com"
else
    dns_name="${CLUSTER_NAME}.gremlinpoc.com"
fi

# Update DNS record silently
aws route53 change-resource-record-sets --hosted-zone-id "$r53_zone_id" --change-batch \
"{ \"Changes\": [ { \"Action\": \"UPSERT\", \"ResourceRecordSet\": { \"Name\": \"${dns_name}\", \"Type\": \"A\",\"AliasTarget\": { \"HostedZoneId\": \"$canonical_hosted_zone_id\", \"DNSName\": \"$canonical_hosted_zone_name\", \"EvaluateTargetHealth\":true } } } ] }" > /dev/null

# Store the URL for later output
if [[ "$SERVICE_NAME" == "otel-demo-frontendproxy" ]]; then
    echo "http://${dns_name}:8080" > /tmp/frontend_url
else
    echo "http://${dns_name}" > /tmp/monitoring_url
fi

# If this is the monitoring service (second run), show both URLs
if [[ "$SERVICE_NAME" != "otel-demo-frontendproxy" ]]; then
    echo ""
    echo "DNS Records have been updated for both services ✅"
    echo ""
    echo "Your links are:"
    echo ""
    echo "Frontend   - $(cat /tmp/frontend_url)"
    echo "Monitoring - $(cat /tmp/monitoring_url)"
    echo ""
    rm -f /tmp/frontend_url /tmp/monitoring_url
fi
