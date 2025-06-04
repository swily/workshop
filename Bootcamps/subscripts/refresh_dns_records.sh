#!/bin/bash

export AWS_REGION=us-east-2
export AWS_DEFAULT_REGION=us-east-2

clusters=$(eksctl get clusters | awk '/^otel-bootcamp-group/ {print $1}')

r53_zone_id=$(aws route53 list-hosted-zones-by-name --dns-name gremlinpoc.com | jq -r '.HostedZones[0].Id')

for cluster in ${clusters}; do
  cluster_number=$(echo $cluster | awk -F'-' '{print $4}')
  eksctl utils write-kubeconfig --cluster $cluster 2> /dev/null > /dev/null
  record_target=$(kubectl get service otel-demo-frontendproxy -n otel-demo -o json | jq -r '.status.loadBalancer.ingress[].hostname')
  lb_name=$(aws elb describe-load-balancers | jq -r --arg dnsname $record_target '.LoadBalancerDescriptions[] | select(.DNSName == $dnsname).LoadBalancerName')
  canonical_hosted_zone_name=dualstack.$(aws elb describe-load-balancers --load-balancer-names $lb_name | jq -r '.LoadBalancerDescriptions[0].CanonicalHostedZoneName')
  canonical_hosted_zone_id=$(aws elb describe-load-balancers --load-balancer-names $lb_name | jq -r '.LoadBalancerDescriptions[0].CanonicalHostedZoneNameID')


  echo "Update DNS record for bc${cluster_number} to $canonical_hosted_zone_name in Route53 hosted zone $r53_zone_id"
  aws route53 change-resource-record-sets --hosted-zone-id $r53_zone_id --change-batch \
  "{ \"Changes\": [ { \"Action\": \"UPSERT\", \"ResourceRecordSet\": { \"Name\": \"bc${cluster_number}.gremlinpoc.com\", \"Type\": \"A\",\"AliasTarget\": { \"HostedZoneId\": \"$canonical_hosted_zone_id\", \"DNSName\": \"$canonical_hosted_zone_name\", \"EvaluateTargetHealth\":true } } } ] }" | jq .
  echo "Update DNS record for bootcamp${cluster_number} to $canonical_hosted_zone_name in Route53 hosted zone $r53_zone_id"
  aws route53 change-resource-record-sets --hosted-zone-id $r53_zone_id --change-batch \
  "{ \"Changes\": [ { \"Action\": \"UPSERT\", \"ResourceRecordSet\": { \"Name\": \"bootcamp${cluster_number}.gremlinpoc.com\", \"Type\": \"A\",\"AliasTarget\": { \"HostedZoneId\": \"$canonical_hosted_zone_id\", \"DNSName\": \"$canonical_hosted_zone_name\", \"EvaluateTargetHealth\":true } } } ] }" | jq .
  if [ $cluster_number -lt 10 ]; then
    trimmed_cluster_number=$(echo $cluster_number | sed 's/^0*//')
    echo "Update DNS record for bc${trimmed_cluster_number} to $canonical_hosted_zone_name in Route53 hosted zone $r53_zone_id"
    aws route53 change-resource-record-sets --hosted-zone-id $r53_zone_id --change-batch \
    "{ \"Changes\": [ { \"Action\": \"UPSERT\", \"ResourceRecordSet\": { \"Name\": \"bc${trimmed_cluster_number}.gremlinpoc.com\", \"Type\": \"A\",\"AliasTarget\": { \"HostedZoneId\": \"$canonical_hosted_zone_id\", \"DNSName\": \"$canonical_hosted_zone_name\", \"EvaluateTargetHealth\":true } } } ] }" | jq .
    echo "Update DNS record for bootcamp${trimmed_cluster_number} to $canonical_hosted_zone_name in Route53 hosted zone $r53_zone_id"
    aws route53 change-resource-record-sets --hosted-zone-id $r53_zone_id --change-batch \
    "{ \"Changes\": [ { \"Action\": \"UPSERT\", \"ResourceRecordSet\": { \"Name\": \"bootcamp${trimmed_cluster_number}.gremlinpoc.com\", \"Type\": \"A\",\"AliasTarget\": { \"HostedZoneId\": \"$canonical_hosted_zone_id\", \"DNSName\": \"$canonical_hosted_zone_name\", \"EvaluateTargetHealth\":true } } } ] }" | jq .
  fi

done