#!/bin/bash -e

# AWS IAM Setup Script for CloudWatch Integration
# Creates IAM role and policies required for ADOT collector and CloudWatch access

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-test-cluster}"
AWS_REGION="${AWS_REGION:-us-east-2}"
ROLE_NAME="EKS-ADOT-CloudWatch-ServiceAccount-Role"
SERVICE_ACCOUNT_NAME="aws-otel-collector"
NAMESPACE="aws-otel-eks"

# Function to print section headers
section() {
  echo -e "\n${GREEN}=== $1 ===${NC}"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if AWS CLI is configured
check_aws_cli() {
  if ! command -v aws >/dev/null 2>&1; then
    echo -e "${RED}Error: AWS CLI not found. Please install AWS CLI first.${NC}"
    exit 1
  fi
  
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${RED}Error: AWS CLI not configured. Please run 'aws configure' first.${NC}"
    exit 1
  fi
}

# Function to get OIDC issuer URL
get_oidc_issuer() {
  local cluster_name="$1"
  aws eks describe-cluster --name "$cluster_name" --query "cluster.identity.oidc.issuer" --output text
}

# Function to create trust policy
create_trust_policy() {
  local oidc_issuer="$1"
  local oidc_issuer_stripped=$(echo "$oidc_issuer" | sed 's|https://||')
  
  cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):oidc-provider/${oidc_issuer_stripped}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${oidc_issuer_stripped}:sub": "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT_NAME}",
          "${oidc_issuer_stripped}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF
}

# Function to create CloudWatch permissions policy
create_cloudwatch_policy() {
  cat > cloudwatch-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "cloudwatch:CreateDashboard",
        "cloudwatch:PutDashboard",
        "cloudwatch:GetDashboard",
        "cloudwatch:ListDashboards",
        "cloudwatch:PutAlarm",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:DeleteAlarms",
        "logs:PutLogEvents",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DescribeLogStreams",
        "logs:DescribeLogGroups",
        "ec2:DescribeVolumes",
        "ec2:DescribeTags",
        "eks:DescribeCluster"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

# Main execution
main() {
  section "Setting up AWS IAM for CloudWatch Integration"
  
  check_aws_cli
  
  section "Getting EKS cluster OIDC issuer"
  OIDC_ISSUER=$(get_oidc_issuer "$CLUSTER_NAME")
  if [ -z "$OIDC_ISSUER" ]; then
    echo -e "${RED}Error: Could not get OIDC issuer for cluster $CLUSTER_NAME${NC}"
    exit 1
  fi
  echo "OIDC Issuer: $OIDC_ISSUER"
  
  section "Creating IAM trust policy"
  create_trust_policy "$OIDC_ISSUER"
  
  section "Creating CloudWatch permissions policy"
  create_cloudwatch_policy
  
  section "Creating IAM role"
  if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    echo "IAM role $ROLE_NAME already exists, updating trust policy..."
    aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document file://trust-policy.json
  else
    echo "Creating IAM role $ROLE_NAME..."
    aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document file://trust-policy.json
  fi
  
  section "Attaching AWS managed policies"
  aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
  aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess
  aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess
  
  section "Creating and attaching custom CloudWatch policy"
  POLICY_NAME="EKS-ADOT-CloudWatch-Policy"
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
  
  if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
    echo "Policy $POLICY_NAME already exists, creating new version..."
    aws iam create-policy-version --policy-arn "$POLICY_ARN" --policy-document file://cloudwatch-policy.json --set-as-default
  else
    echo "Creating policy $POLICY_NAME..."
    aws iam create-policy --policy-name "$POLICY_NAME" --policy-document file://cloudwatch-policy.json
  fi
  
  aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN"
  
  section "Cleanup temporary files"
  rm -f trust-policy.json cloudwatch-policy.json
  
  section "IAM Setup Complete"
  echo -e "${GREEN}✅ IAM role created: $ROLE_NAME${NC}"
  echo -e "${GREEN}✅ Role ARN: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}${NC}"
  echo -e "${GREEN}✅ Service Account: ${NAMESPACE}:${SERVICE_ACCOUNT_NAME}${NC}"
  
  # Export for use in installation script
  export IAM_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
  echo "export IAM_ROLE_ARN=\"$IAM_ROLE_ARN\"" > /tmp/aws-iam-vars.sh
}

main "$@"
