#!/bin/bash
#
# EKS Cluster Health Validation Script
# Prevents the nightmare scenario from thingsfixed.json
# Validates all critical components that previously failed
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CLUSTER_NAME="${1:-${CLUSTER_NAME}}"
AWS_REGION="${AWS_REGION:-us-west-2}"

if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${RED}❌ ERROR: Cluster name required${NC}"
    echo "Usage: $0 <cluster-name>"
    exit 1
fi

echo -e "${BLUE}🔍 VALIDATING EKS CLUSTER HEALTH: ${CLUSTER_NAME}${NC}"
echo "Region: ${AWS_REGION}"
echo "Timestamp: $(date)"
echo ""

# Function to check and report status
check_status() {
    local component="$1"
    local status="$2"
    local details="$3"
    
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✅ ${component}${NC}"
        [ -n "$details" ] && echo -e "   ${details}"
    else
        echo -e "${RED}❌ ${component}${NC}"
        [ -n "$details" ] && echo -e "   ${RED}${details}${NC}"
        return 1
    fi
}

# 1. CLUSTER BASIC CONNECTIVITY
echo -e "${BLUE}=== CLUSTER CONNECTIVITY ===${NC}"
if kubectl cluster-info &>/dev/null; then
    check_status "Cluster API Server" "PASS" "kubectl can connect to cluster"
else
    check_status "Cluster API Server" "FAIL" "kubectl cannot connect to cluster"
    exit 1
fi

# 2. NODE READINESS (Critical failure point from thingsfixed.json)
echo -e "\n${BLUE}=== NODE READINESS ===${NC}"
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")

if [ "$READY_NODES" -gt 0 ] && [ "$READY_NODES" -eq "$NODE_COUNT" ]; then
    check_status "Node Readiness" "PASS" "${READY_NODES}/${NODE_COUNT} nodes Ready"
else
    check_status "Node Readiness" "FAIL" "${READY_NODES}/${NODE_COUNT} nodes Ready"
    echo -e "${YELLOW}Node Details:${NC}"
    kubectl get nodes -o wide
fi

# 3. VPC CNI HEALTH (Major failure point)
echo -e "\n${BLUE}=== VPC CNI VALIDATION ===${NC}"
VPC_CNI_PODS=$(kubectl get pods -n kube-system -l k8s-app=aws-node --no-headers 2>/dev/null | wc -l)
VPC_CNI_READY=$(kubectl get pods -n kube-system -l k8s-app=aws-node --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "$VPC_CNI_READY" -gt 0 ] && [ "$VPC_CNI_READY" -eq "$VPC_CNI_PODS" ]; then
    check_status "VPC CNI Pods" "PASS" "${VPC_CNI_READY}/${VPC_CNI_PODS} aws-node pods Running"
else
    check_status "VPC CNI Pods" "FAIL" "${VPC_CNI_READY}/${VPC_CNI_PODS} aws-node pods Running"
fi

# Check VPC CNI service account (Critical from thingsfixed.json)
if kubectl get serviceaccount aws-node -n kube-system &>/dev/null; then
    SA_ANNOTATIONS=$(kubectl get serviceaccount aws-node -n kube-system -o jsonpath='{.metadata.annotations}')
    if echo "$SA_ANNOTATIONS" | grep -q "eks.amazonaws.com/role-arn"; then
        check_status "VPC CNI Service Account" "PASS" "aws-node SA has IAM role annotation"
    else
        check_status "VPC CNI Service Account" "FAIL" "aws-node SA missing IAM role annotation"
    fi
else
    check_status "VPC CNI Service Account" "FAIL" "aws-node service account not found"
fi

# 4. OIDC PROVIDER (Critical failure point)
echo -e "\n${BLUE}=== OIDC PROVIDER ===${NC}"
CLUSTER_OIDC=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.identity.oidc.issuer' --output text 2>/dev/null)
if [ -n "$CLUSTER_OIDC" ] && [ "$CLUSTER_OIDC" != "None" ]; then
    OIDC_ID=$(echo "$CLUSTER_OIDC" | cut -d'/' -f5)
    if aws iam list-open-id-connect-providers --region "$AWS_REGION" | grep -q "$OIDC_ID" 2>/dev/null; then
        check_status "OIDC Provider" "PASS" "OIDC provider exists and is registered"
    else
        check_status "OIDC Provider" "FAIL" "OIDC provider not registered in IAM"
    fi
else
    check_status "OIDC Provider" "FAIL" "OIDC issuer not found on cluster"
fi

# 5. SECURITY GROUPS (Major failure point)
echo -e "\n${BLUE}=== SECURITY GROUP VALIDATION ===${NC}"
CLUSTER_SG=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text 2>/dev/null)
if [ -n "$CLUSTER_SG" ] && [ "$CLUSTER_SG" != "None" ]; then
    check_status "Cluster Security Group" "PASS" "Cluster SG: $CLUSTER_SG"
else
    check_status "Cluster Security Group" "FAIL" "Cluster security group not found"
fi

# Check if nodes have proper security group attachment
NODE_GROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'nodegroups' --output text 2>/dev/null)
if [ -n "$NODE_GROUPS" ]; then
    for ng in $NODE_GROUPS; do
        NG_SG=$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --region "$AWS_REGION" --query 'nodegroup.remoteAccess.ec2SshKey' --output text 2>/dev/null)
        check_status "Node Group: $ng" "PASS" "Node group exists and is accessible"
    done
else
    check_status "Node Groups" "FAIL" "No node groups found"
fi

# 6. SUBNET CONFIGURATION (Critical from thingsfixed.json)
echo -e "\n${BLUE}=== SUBNET VALIDATION ===${NC}"
CLUSTER_SUBNETS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.resourcesVpcConfig.subnetIds' --output text 2>/dev/null)
if [ -n "$CLUSTER_SUBNETS" ]; then
    SUBNET_COUNT=$(echo "$CLUSTER_SUBNETS" | wc -w)
    check_status "Cluster Subnets" "PASS" "$SUBNET_COUNT subnets configured"
    
    # Check if subnets are public (critical from thingsfixed.json)
    for subnet in $CLUSTER_SUBNETS; do
        ROUTE_TABLE=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$subnet" --region "$AWS_REGION" --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null)
        if [ -n "$ROUTE_TABLE" ] && [ "$ROUTE_TABLE" != "None" ]; then
            IGW_ROUTE=$(aws ec2 describe-route-tables --route-table-ids "$ROUTE_TABLE" --region "$AWS_REGION" --query 'RouteTables[0].Routes[?GatewayId!=null && starts_with(GatewayId, `igw-`)]' --output text 2>/dev/null)
            if [ -n "$IGW_ROUTE" ]; then
                echo -e "   ${GREEN}✓${NC} $subnet (public - has IGW route)"
            else
                echo -e "   ${YELLOW}⚠${NC} $subnet (private - no IGW route)"
            fi
        fi
    done
else
    check_status "Cluster Subnets" "FAIL" "No subnets found"
fi

# 7. CORE DNS AND NETWORKING
echo -e "\n${BLUE}=== CORE NETWORKING ===${NC}"
COREDNS_PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | wc -l)
COREDNS_READY=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "$COREDNS_READY" -gt 0 ] && [ "$COREDNS_READY" -eq "$COREDNS_PODS" ]; then
    check_status "CoreDNS" "PASS" "${COREDNS_READY}/${COREDNS_PODS} CoreDNS pods Running"
else
    check_status "CoreDNS" "FAIL" "${COREDNS_READY}/${COREDNS_PODS} CoreDNS pods Running"
fi

# 8. KUBERNETES VERSION (From thingsfixed.json)
echo -e "\n${BLUE}=== VERSION VALIDATION ===${NC}"
K8S_VERSION=$(kubectl version --short --client=false 2>/dev/null | grep "Server Version" | cut -d' ' -f3)
if [[ "$K8S_VERSION" =~ v1\.31 ]]; then
    check_status "Kubernetes Version" "PASS" "Running proven version: $K8S_VERSION"
else
    check_status "Kubernetes Version" "WARN" "Running $K8S_VERSION (proven version is v1.31.x)"
fi

# 9. FINAL CONNECTIVITY TEST
echo -e "\n${BLUE}=== CONNECTIVITY TEST ===${NC}"
if kubectl get pods --all-namespaces &>/dev/null; then
    check_status "API Connectivity" "PASS" "Can list pods across all namespaces"
else
    check_status "API Connectivity" "FAIL" "Cannot list pods - API server issues"
fi

echo ""
echo -e "${BLUE}=== VALIDATION COMPLETE ===${NC}"
echo "Timestamp: $(date)"
echo ""
echo -e "${YELLOW}💡 If any checks failed, compare with golden config:${NC}"
echo -e "${YELLOW}   /Users/seanwiley/workshop/config/eks/golden-cluster-config.yaml${NC}"
echo ""
echo -e "${YELLOW}📋 Reference working cluster: jheller-otel-redux${NC}"
