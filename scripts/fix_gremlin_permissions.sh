#!/bin/bash

# Fix Gremlin EC2 DescribeTags Permission for EKS Node Role
# This script adds the necessary EC2 permissions to the EKS node role for Gremlin service discovery

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
CLUSTER_NAME="${CLUSTER_NAME:-}"
AWS_REGION="${AWS_REGION:-us-east-2}"
DRY_RUN=false

# Function to print colored output
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --cluster-name CLUSTER    EKS cluster name (required)"
    echo "  -r, --region REGION          AWS region (default: us-east-2)"
    echo "  --dry-run                    Show what would be done without making changes"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  CLUSTER_NAME                 EKS cluster name"
    echo "  AWS_REGION                   AWS region"
    echo ""
    echo "Example:"
    echo "  $0 --cluster-name my-cluster --region us-east-2"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$CLUSTER_NAME" ]; then
    log_error "Cluster name is required. Use --cluster-name or set CLUSTER_NAME environment variable."
    usage
    exit 1
fi

# Function to check if AWS CLI is available and configured
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
}

# Function to get EKS node role ARN
get_node_role_arn() {
    local cluster_name="$1"
    
    # Get the first nodegroup name
    local nodegroup_name
    nodegroup_name=$(aws eks list-nodegroups --cluster-name "$cluster_name" --region "$AWS_REGION" --query 'nodegroups[0]' --output text 2>/dev/null)
    
    if [ -z "$nodegroup_name" ] || [ "$nodegroup_name" = "None" ]; then
        log_error "No node groups found for cluster: $cluster_name"
        return 1
    fi
    
    # Get the node role ARN
    local node_role_arn
    node_role_arn=$(aws eks describe-nodegroup --cluster-name "$cluster_name" --nodegroup-name "$nodegroup_name" --region "$AWS_REGION" --query 'nodegroup.nodeRole' --output text 2>/dev/null)
    
    if [ -z "$node_role_arn" ] || [ "$node_role_arn" = "None" ]; then
        log_error "Could not retrieve node role ARN for nodegroup: $nodegroup_name"
        return 1
    fi
    
    echo "$node_role_arn"
}

# Function to extract role name from ARN
get_role_name_from_arn() {
    local role_arn="$1"
    echo "$role_arn" | awk -F'/' '{print $NF}'
}

# Function to create Gremlin EC2 policy
create_gremlin_ec2_policy() {
    local policy_name="GremlinEC2DescribeTags"
    
    # Check if policy already exists
    if aws iam get-policy --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/$policy_name" &>/dev/null; then
        log_info "Policy $policy_name already exists"
        echo "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/$policy_name"
        return 0
    fi
    
    log_info "Creating IAM policy: $policy_name"
    
    # Policy document for Gremlin EC2 permissions
    local policy_document='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "ec2:DescribeTags",
                    "ec2:DescribeInstances"
                ],
                "Resource": "*"
            }
        ]
    }'
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] Would create policy: $policy_name"
        log_warning "[DRY RUN] Policy document: $policy_document"
        echo "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/$policy_name"
        return 0
    fi
    
    # Create the policy
    local policy_arn
    policy_arn=$(aws iam create-policy \
        --policy-name "$policy_name" \
        --policy-document "$policy_document" \
        --description "Allows Gremlin agents to describe EC2 tags and instances for service discovery" \
        --query 'Policy.Arn' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$policy_arn" ]; then
        log_success "Created policy: $policy_arn"
        echo "$policy_arn"
    else
        log_error "Failed to create policy: $policy_name"
        return 1
    fi
}

# Function to attach policy to role
attach_policy_to_role() {
    local role_name="$1"
    local policy_arn="$2"
    
    log_info "Checking if policy is already attached to role: $role_name"
    
    # Check if policy is already attached (escape special characters in role name)
    local attached_policies
    attached_policies=$(aws iam list-attached-role-policies --role-name "$role_name" --query "AttachedPolicies[?PolicyArn=='$policy_arn'].PolicyArn" --output text 2>/dev/null)
    
    if [ -n "$attached_policies" ] && [ "$attached_policies" != "None" ]; then
        log_info "Policy already attached to role: $role_name"
        return 0
    fi
    
    log_info "Attaching policy to role: $role_name"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] Would attach policy $policy_arn to role $role_name"
        return 0
    fi
    
    if aws iam attach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null; then
        log_success "Successfully attached policy to role: $role_name"
    else
        log_error "Failed to attach policy to role: $role_name"
        return 1
    fi
}

# Function to restart Gremlin daemonset to pick up new permissions
restart_gremlin_daemonset() {
    log_info "Restarting Gremlin daemonset to pick up new permissions..."
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] Would restart Gremlin daemonset"
        return 0
    fi
    
    if kubectl get daemonset gremlin -n gremlin &>/dev/null; then
        kubectl rollout restart daemonset/gremlin -n gremlin
        log_success "Gremlin daemonset restart initiated"
        
        # Wait for rollout to complete
        log_info "Waiting for Gremlin daemonset rollout to complete..."
        kubectl rollout status daemonset/gremlin -n gremlin --timeout=300s
        log_success "Gremlin daemonset rollout completed"
    else
        log_warning "Gremlin daemonset not found - skipping restart"
    fi
}

# Main function
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║           🔧 Gremlin EC2 Permissions Fix Script             ║"
    echo "║                                                              ║"
    echo "║         Adds EC2:DescribeTags permission to EKS nodes       ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "Running in DRY RUN mode - no changes will be made"
    fi
    
    # Check prerequisites
    check_aws_cli
    
    # Get node role ARN
    log_info "Getting EKS node role for cluster: $CLUSTER_NAME"
    local node_role_arn
    node_role_arn=$(get_node_role_arn "$CLUSTER_NAME")
    
    if [ $? -ne 0 ] || [ -z "$node_role_arn" ]; then
        log_error "Failed to get node role ARN"
        exit 1
    fi
    
    local role_name
    role_name=$(get_role_name_from_arn "$node_role_arn")
    log_success "Found node role: $role_name ($node_role_arn)"
    
    # Create Gremlin EC2 policy
    local policy_arn
    policy_arn=$(create_gremlin_ec2_policy)
    
    if [ $? -ne 0 ] || [ -z "$policy_arn" ]; then
        log_error "Failed to create Gremlin EC2 policy"
        exit 1
    fi
    
    # Attach policy to role
    attach_policy_to_role "$role_name" "$policy_arn"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to attach policy to role"
        exit 1
    fi
    
    # Restart Gremlin daemonset if kubectl is available
    if command -v kubectl &> /dev/null; then
        restart_gremlin_daemonset
    else
        log_warning "kubectl not available - Gremlin daemonset restart skipped"
        log_info "Manually restart Gremlin daemonset: kubectl rollout restart daemonset/gremlin -n gremlin"
    fi
    
    echo ""
    log_success "Gremlin EC2 permissions fix completed successfully!"
    echo ""
    log_info "Next steps:"
    echo "  1. Wait 2-3 minutes for Gremlin agents to restart"
    echo "  2. Check Gremlin logs: kubectl logs -n gremlin -l app=gremlin --tail=10"
    echo "  3. Verify service discovery in Gremlin UI: https://app.gremlin.com"
    echo ""
}

# Run main function
main "$@"
