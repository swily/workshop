#!/bin/bash

# Default values
SERVICE_NAME="otel-demo-frontendproxy"
NAMESPACE="otel-demo"
DNS_PREFIX=""

# Parse command line arguments
while getopts ":s:n:p:" opt; do
  case $opt in
    s) SERVICE_NAME="$OPTARG"
    ;;
    n) NAMESPACE="$OPTARG"
    ;;
    p) DNS_PREFIX="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    exit 1
    ;;
  esac
done

if [ -z "$CLUSTER_NAME" ]; then
    echo "Error: CLUSTER_NAME environment variable is not set"
    exit 1
fi

echo "Using service: $SERVICE_NAME in namespace: $NAMESPACE"

export AWS_REGION=us-east-2
export AWS_DEFAULT_REGION=us-east-2

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

echo "Updating DNS record for ${dns_name} to point to ${canonical_hosted_zone_name}"
aws route53 change-resource-record-sets --hosted-zone-id "$r53_zone_id" --change-batch \
"{ \"Changes\": [ { \"Action\": \"UPSERT\", \"ResourceRecordSet\": { \"Name\": \"${dns_name}\", \"Type\": \"A\",\"AliasTarget\": { \"HostedZoneId\": \"$canonical_hosted_zone_id\", \"DNSName\": \"$canonical_hosted_zone_name\", \"EvaluateTargetHealth\":true } } } ] }" | jq .
