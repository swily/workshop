#!/bin/bash

# Test Script for Prometheus/Grafana Health Check Creation
# This script tests the unified health check creator

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       Testing Prometheus/Grafana Health Check Creation      ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"

# Check Gremlin credentials
if [ -z "${GREMLIN_TEAM_ID:-}" ]; then
    echo -e "${RED}❌ GREMLIN_TEAM_ID not set${NC}"
    echo "Please set: export GREMLIN_TEAM_ID=your-team-id"
    exit 1
fi

if [ -z "${GREMLIN_API_KEY:-}" ]; then
    echo -e "${RED}❌ GREMLIN_API_KEY not set${NC}"
    echo "Please set: export GREMLIN_API_KEY=your-api-key"
    exit 1
fi

echo -e "${GREEN}✅ Gremlin credentials found${NC}"
echo "   Team ID: ${GREMLIN_TEAM_ID:0:8}..."
echo "   API Key: ${GREMLIN_API_KEY:0:8}..."
echo ""

# Check kubectl connection
echo -e "${BLUE}Checking Kubernetes connection...${NC}"
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Connected to Kubernetes${NC}"
echo ""

# Check if monitoring namespace exists
echo -e "${BLUE}Checking monitoring stack...${NC}"
if ! kubectl get namespace monitoring &>/dev/null; then
    echo -e "${RED}❌ Monitoring namespace not found${NC}"
    echo "Please install Prometheus/Grafana first"
    exit 1
fi
echo -e "${GREEN}✅ Monitoring namespace exists${NC}"

# Check Grafana password
echo -e "${BLUE}Checking Grafana credentials...${NC}"
GRAFANA_PASSWORD=$(kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 --decode 2>/dev/null || echo "")
if [ -z "$GRAFANA_PASSWORD" ]; then
    echo -e "${YELLOW}⚠️  Could not retrieve Grafana password from secret${NC}"
    echo "Using default: admin123"
    GRAFANA_PASSWORD="admin123"
else
    echo -e "${GREEN}✅ Grafana password retrieved from secret${NC}"
fi
export GRAFANA_ADMIN_PASSWORD="$GRAFANA_PASSWORD"
echo ""

# Check for consolidated ingress
echo -e "${BLUE}Checking ingress configuration...${NC}"
CONSOLIDATED_ALB=$(kubectl get ingress -n otel-demo consolidated-demo-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
if [ -n "$CONSOLIDATED_ALB" ]; then
    echo -e "${GREEN}✅ Consolidated ALB found: $CONSOLIDATED_ALB${NC}"
    
    # Detect HTTPS
    CERT_ARN=$(kubectl get ingress -n otel-demo consolidated-demo-ingress -o jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/certificate-arn}' 2>/dev/null || echo "")
    if [ -n "$CERT_ARN" ]; then
        SCHEME="https"
        echo -e "${GREEN}✅ HTTPS enabled (ACM certificate detected)${NC}"
    else
        SCHEME="http"
        echo -e "${YELLOW}⚠️  Using HTTP (no ACM certificate)${NC}"
    fi
    
    export PROMETHEUS_URL="${SCHEME}://${CONSOLIDATED_ALB}/prometheus/api/v1/alerts"
    export GRAFANA_URL="${SCHEME}://${CONSOLIDATED_ALB}/grafana/api/health"
else
    echo -e "${YELLOW}⚠️  No consolidated ingress found${NC}"
    echo "Will use default endpoint discovery"
fi
echo ""

# Run the unified health check creator
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              Creating Health Checks via Unified Script       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/create_health_checks.sh" ]; then
    bash "$SCRIPT_DIR/create_health_checks.sh" --platform prometheus --platform grafana
    EXIT_CODE=$?
else
    echo -e "${RED}❌ Unified health check script not found${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                      TEST SUMMARY                            ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ Health check creation completed successfully${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Visit Gremlin UI: https://app.gremlin.com/reliability/status-checks"
    echo "2. Verify health checks appear with recent timestamps"
    echo "3. Check that they are monitoring the correct endpoints:"
    if [ -n "${PROMETHEUS_URL:-}" ]; then
        echo "   - Prometheus: $PROMETHEUS_URL"
    fi
    if [ -n "${GRAFANA_URL:-}" ]; then
        echo "   - Grafana: $GRAFANA_URL"
    fi
    echo ""
    echo -e "${GREEN}If health checks appear correctly, run:${NC}"
    echo "  ./monitoring/cleanup_deprecated.sh"
    echo ""
else
    echo -e "${RED}❌ Health check creation failed${NC}"
    echo "Please check the errors above and try again"
    exit 1
fi
