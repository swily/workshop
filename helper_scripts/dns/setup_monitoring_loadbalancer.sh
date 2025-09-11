#!/bin/bash

# Set environment variables
export CLUSTER_NAME=${CLUSTER_NAME:-current-workshop}
export AWS_DEFAULT_REGION=${AWS_REGION:-us-east-2}

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Setting up LoadBalancer services for Prometheus and Grafana...${NC}"

# Create LoadBalancer service for Prometheus (monitoring namespace)
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: prometheus-lb
  namespace: monitoring
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
spec:
  type: LoadBalancer
  ports:
  - port: 9090
    targetPort: 9090
    protocol: TCP
  externalTrafficPolicy: Cluster
  selector:
    app.kubernetes.io/instance: kube-prometheus-stack-prometheus
    app.kubernetes.io/name: prometheus
EOF

# Create LoadBalancer service for otel-demo Grafana
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: grafana-otel-lb
  namespace: otel-demo
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 3000
    protocol: TCP
  selector:
    app.kubernetes.io/instance: otel-demo
    app.kubernetes.io/name: grafana
EOF

# Create LoadBalancer service for monitoring Grafana
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: grafana-monitoring-lb
  namespace: monitoring
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 3000
    protocol: TCP
  selector:
    app.kubernetes.io/instance: prometheus
    app.kubernetes.io/name: grafana
EOF

echo -e "${YELLOW}Waiting for LoadBalancer services to get external IPs...${NC}"

# Wait for Prometheus LoadBalancer
echo "Waiting for Prometheus LoadBalancer..."
while true; do
    PROMETHEUS_LB=$(kubectl get svc prometheus-lb -n otel-demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ -n "$PROMETHEUS_LB" ]; then
        echo "Prometheus LoadBalancer ready: $PROMETHEUS_LB"
        break
    fi
    sleep 10
done

# Wait for otel-demo Grafana LoadBalancer
echo "Waiting for otel-demo Grafana LoadBalancer..."
while true; do
    GRAFANA_OTEL_LB=$(kubectl get svc grafana-otel-lb -n otel-demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ -n "$GRAFANA_OTEL_LB" ]; then
        echo "otel-demo Grafana LoadBalancer ready: $GRAFANA_OTEL_LB"
        break
    fi
    sleep 10
done

# Wait for monitoring Grafana LoadBalancer
echo "Waiting for monitoring Grafana LoadBalancer..."
while true; do
    GRAFANA_MONITORING_LB=$(kubectl get svc grafana-monitoring-lb -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ -n "$GRAFANA_MONITORING_LB" ]; then
        echo "monitoring Grafana LoadBalancer ready: $GRAFANA_MONITORING_LB"
        break
    fi
    sleep 10
done

# Get the Route53 zone ID for gremlinpoc.com
r53_zone_id=$(aws route53 list-hosted-zones-by-name --dns-name gremlinpoc.com | jq -r '.HostedZones[0].Id')
r53_zone_id=${r53_zone_id#/hostedzone/}  # Remove the /hostedzone/ prefix

# DNS records will be created silently

# Create DNS CNAME records silently
aws route53 change-resource-record-sets --hosted-zone-id "$r53_zone_id" --change-batch "{
    \"Changes\": [{
        \"Action\": \"UPSERT\",
        \"ResourceRecordSet\": {
            \"Name\": \"${CLUSTER_NAME}-prometheus.gremlinpoc.com\",
            \"Type\": \"CNAME\",
            \"TTL\": 300,
            \"ResourceRecords\": [{
                \"Value\": \"$PROMETHEUS_LB\"
            }]
        }
    }]
}" > /dev/null 2>&1

aws route53 change-resource-record-sets --hosted-zone-id "$r53_zone_id" --change-batch "{
    \"Changes\": [{
        \"Action\": \"UPSERT\",
        \"ResourceRecordSet\": {
            \"Name\": \"${CLUSTER_NAME}-grafana-otel.gremlinpoc.com\",
            \"Type\": \"CNAME\",
            \"TTL\": 300,
            \"ResourceRecords\": [{
                \"Value\": \"$GRAFANA_OTEL_LB\"
            }]
        }
    }]
}" > /dev/null 2>&1

aws route53 change-resource-record-sets --hosted-zone-id "$r53_zone_id" --change-batch "{
    \"Changes\": [{
        \"Action\": \"UPSERT\",
        \"ResourceRecordSet\": {
            \"Name\": \"${CLUSTER_NAME}-grafana-monitoring.gremlinpoc.com\",
            \"Type\": \"CNAME\",
            \"TTL\": 300,
            \"ResourceRecords\": [{
                \"Value\": \"$GRAFANA_MONITORING_LB\"
            }]
        }
    }]
}" > /dev/null 2>&1

echo ""
echo -e "${GREEN}LoadBalancer services and DNS records created successfully${NC}"
echo ""
## Define DNS hostnames for display and exports
prometheus_dns="${CLUSTER_NAME}-prometheus.gremlinpoc.com"
grafana_otel_dns="${CLUSTER_NAME}-grafana-otel.gremlinpoc.com"
grafana_monitoring_dns="${CLUSTER_NAME}-grafana-monitoring.gremlinpoc.com"

echo "Your public monitoring endpoints are:"
echo ""
echo -e "${GREEN}Prometheus - http://${prometheus_dns}:9090${NC}"
echo -e "${GREEN}otel-demo Grafana - http://${grafana_otel_dns}${NC}"
echo -e "${GREEN}monitoring Grafana - http://${grafana_monitoring_dns}${NC}"
echo ""
echo "Health check endpoints:"
echo -e "${YELLOW}Prometheus Alerts: http://${prometheus_dns}:9090/api/v1/alerts${NC}"
echo -e "${YELLOW}otel-demo Grafana Health: http://${grafana_otel_dns}/api/health${NC}"
echo -e "${YELLOW}monitoring Grafana Health: http://${grafana_monitoring_dns}/api/health${NC}"
echo ""
echo "LoadBalancer endpoints (direct):"
echo -e "${YELLOW}Prometheus: http://${PROMETHEUS_LB}:9090${NC}"
echo -e "${YELLOW}otel-demo Grafana: http://${GRAFANA_OTEL_LB}${NC}"
echo -e "${YELLOW}monitoring Grafana: http://${GRAFANA_MONITORING_LB}${NC}"
echo ""
echo "Note: It may take a few minutes for DNS changes to propagate"

# Export variables for use in other scripts
export PROMETHEUS_PUBLIC_URL="http://${prometheus_dns}:9090"
export GRAFANA_OTEL_PUBLIC_URL="http://${grafana_otel_dns}"
export GRAFANA_MONITORING_PUBLIC_URL="http://${grafana_monitoring_dns}"
export PROMETHEUS_LB_URL="http://${PROMETHEUS_LB}:9090"
export GRAFANA_OTEL_LB_URL="http://${GRAFANA_OTEL_LB}"
export GRAFANA_MONITORING_LB_URL="http://${GRAFANA_MONITORING_LB}"

echo ""
echo "Environment variables set:"
echo "PROMETHEUS_PUBLIC_URL=$PROMETHEUS_PUBLIC_URL"
echo "GRAFANA_OTEL_PUBLIC_URL=$GRAFANA_OTEL_PUBLIC_URL"
echo "GRAFANA_MONITORING_PUBLIC_URL=$GRAFANA_MONITORING_PUBLIC_URL"
echo "PROMETHEUS_LB_URL=$PROMETHEUS_LB_URL"
echo "GRAFANA_OTEL_LB_URL=$GRAFANA_OTEL_LB_URL"
echo "GRAFANA_MONITORING_LB_URL=$GRAFANA_MONITORING_LB_URL"
