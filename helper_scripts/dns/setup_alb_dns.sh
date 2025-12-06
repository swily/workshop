#!/bin/bash

# Unified DNS setup for ALB/LoadBalancer-based services across clusters
# This script creates consistent DNS records using only ALB and LoadBalancer endpoints
# Removes all NodePort-based DNS records and services

set -e

# Set environment variables
export CLUSTER_NAME=${CLUSTER_NAME:-current-workshop}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-2}

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Setting up ALB-based DNS for cluster: ${CLUSTER_NAME} ===${NC}"

# Get Route53 zone ID for gremlinpoc.com
get_zone_id() {
    local zone_id=$(aws route53 list-hosted-zones-by-name --dns-name gremlinpoc.com --query 'HostedZones[0].Id' --output text 2>/dev/null)
    if [[ "$zone_id" == "None" || -z "$zone_id" ]]; then
        echo -e "${RED}Error: Could not find Route53 hosted zone for gremlinpoc.com${NC}"
        exit 1
    fi
    echo ${zone_id#/hostedzone/}  # Remove prefix
}

# Remove redundant services
cleanup_redundant_services() {
    echo -e "${YELLOW}Cleaning up redundant NodePort and LoadBalancer services...${NC}"
    
    # Remove redundant Grafana services
    kubectl delete svc prometheus-grafana-nodeport -n monitoring --ignore-not-found=true
    kubectl delete svc grafana-monitoring-lb -n monitoring --ignore-not-found=true
    kubectl delete svc grafana-otel-lb -n otel-demo --ignore-not-found=true
    
    echo -e "${GREEN}  ✅ Redundant services removed${NC}"
}

# Clean up old DNS records
cleanup_old_dns_records() {
    local zone_id="$1"
    echo -e "${YELLOW}Cleaning up old NodePort-based DNS records...${NC}"
    
    # Get all DNS records for this cluster
    local records=$(aws route53 list-resource-record-sets --hosted-zone-id "$zone_id" \
        --query "ResourceRecordSets[?contains(Name, '${CLUSTER_NAME}')]" --output json)
    
    # Delete A records (NodePort-based)
    echo "$records" | jq -r '.[] | select(.Type == "A") | "\(.Name) \(.ResourceRecords[0].Value)"' | while read name value; do
        if [[ "$name" == *"${CLUSTER_NAME}"* ]]; then
            name=${name%.}  # Remove trailing dot
            echo -e "${YELLOW}  Removing A record: $name${NC}"
            aws route53 change-resource-record-sets --hosted-zone-id "$zone_id" --change-batch "{
                \"Changes\": [{
                    \"Action\": \"DELETE\",
                    \"ResourceRecordSet\": {
                        \"Name\": \"$name\",
                        \"Type\": \"A\",
                        \"TTL\": 300,
                        \"ResourceRecords\": [{\"Value\": \"$value\"}]
                    }
                }]
            }" >/dev/null 2>&1 || true
        fi
    done
    
    echo -e "${GREEN}  ✅ Old DNS records cleaned${NC}"
}

# Create or update DNS record
create_dns_record() {
    local dns_name="$1"
    local target_hostname="$2"
    local zone_id="$3"
    
    echo -e "${YELLOW}Creating DNS: ${dns_name} → ${target_hostname}${NC}"
    
    # Create CNAME record (upsert will replace any existing)
    aws route53 change-resource-record-sets --hosted-zone-id "$zone_id" --change-batch "{
        \"Changes\": [{
            \"Action\": \"UPSERT\",
            \"ResourceRecordSet\": {
                \"Name\": \"${dns_name}\",
                \"Type\": \"CNAME\",
                \"TTL\": 300,
                \"ResourceRecords\": [{\"Value\": \"$target_hostname\"}]
            }
        }]
    }" >/dev/null
    
    echo -e "${GREEN}  ✅ DNS record created${NC}"
}

# Main execution
main() {
    local zone_id=$(get_zone_id)
    echo -e "${BLUE}Using Route53 zone: ${zone_id}${NC}"
    
    # Clean up redundant services and old DNS records
    cleanup_redundant_services
    cleanup_old_dns_records "$zone_id"
    
    # Frontend (ALB Ingress)
    echo -e "\n${YELLOW}Setting up Frontend DNS...${NC}"
    local frontend_alb=$(kubectl get ingress frontend-proxy -n otel-demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [[ -n "$frontend_alb" ]]; then
        create_dns_record "${CLUSTER_NAME}-frontend.gremlinpoc.com" "$frontend_alb" "$zone_id"
    else
        echo -e "${RED}  ❌ Frontend ALB not found${NC}"
    fi
    
    # Grafana (ALB Ingress)
    echo -e "\n${YELLOW}Setting up Grafana DNS...${NC}"
    local grafana_alb=$(kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [[ -n "$grafana_alb" ]]; then
        create_dns_record "${CLUSTER_NAME}-grafana.gremlinpoc.com" "$grafana_alb" "$zone_id"
    else
        echo -e "${RED}  ❌ Grafana ALB not found${NC}"
    fi
    
    # Prometheus (LoadBalancer)
    echo -e "\n${YELLOW}Setting up Prometheus DNS...${NC}"
    local prometheus_lb=$(kubectl get svc prometheus-lb -n otel-demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [[ -n "$prometheus_lb" ]]; then
        create_dns_record "${CLUSTER_NAME}-prometheus.gremlinpoc.com" "$prometheus_lb" "$zone_id"
    else
        echo -e "${RED}  ❌ Prometheus LoadBalancer not found${NC}"
    fi
    
    echo -e "\n${GREEN}🎉 Unified DNS setup complete!${NC}"
    echo -e "\n${BLUE}Your clean endpoints:${NC}"
    echo -e "  🛒 Frontend:   http://${CLUSTER_NAME}-frontend.gremlinpoc.com"
    echo -e "  📊 Grafana:    http://${CLUSTER_NAME}-grafana.gremlinpoc.com"
    echo -e "  🔍 Prometheus: http://${CLUSTER_NAME}-prometheus.gremlinpoc.com:9090"
    echo -e "\n${YELLOW}Note: DNS propagation may take 1-2 minutes${NC}"
    echo -e "${GREEN}All services now use ClusterIP + ALB/LoadBalancer (no NodePort)${NC}"
}

# Run main function
main "$@"
