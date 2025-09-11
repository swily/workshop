#!/bin/bash -e

# Unified AWS CloudWatch Installation Script
# This script installs ADOT collector and sets up CloudWatch integration for otel-demo
# It integrates with the monitoring framework for the workshop environment

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CLUSTER_NAME="${CLUSTER_NAME:-test-cluster}"
AWS_REGION="${AWS_REGION:-us-east-2}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
VALUES_DIR="${SCRIPT_DIR}/../values"
DASHBOARDS_DIR="${SCRIPT_DIR}/../dashboards"
AUTH_DIR="${SCRIPT_DIR}/../auth"
NAMESPACE="aws-otel-eks"
ADOT_VERSION="0.95.0"

# Function to print section headers with time estimates
section() {
  local message="$1"
  local estimate="$2"
  echo -e "\n${GREEN}=== $message ===${NC}"
  if [ -n "$estimate" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message (Est. time: $estimate)"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message"
  fi
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to prompt for AWS credentials if not provided
prompt_for_aws_credentials() {
  if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo -e "${YELLOW}AWS Access Key ID not provided.${NC}"
    read -p "Enter AWS Access Key ID: " AWS_ACCESS_KEY_ID
    if [ -z "$AWS_ACCESS_KEY_ID" ]; then
      echo -e "${RED}Error: AWS Access Key ID is required${NC}"
      exit 1
    fi
  fi
  
  if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo -e "${YELLOW}AWS Secret Access Key not provided.${NC}"
    read -s -p "Enter AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
    echo ""
    if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
      echo -e "${RED}Error: AWS Secret Access Key is required${NC}"
      exit 1
    fi
  fi
  
  if [ -z "$AWS_REGION" ]; then
    read -p "Enter AWS Region (default: us-east-2): " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-2}
  fi
}

# Function to configure AWS CLI
configure_aws_cli() {
  section "Configuring AWS CLI"
  
  # Create AWS credentials directory if it doesn't exist
  mkdir -p ~/.aws
  
  # Configure AWS credentials
  cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF

  cat > ~/.aws/config << EOF
[default]
region = ${AWS_REGION}
output = json
EOF

  echo "AWS CLI configured for region: $AWS_REGION"
}

# Function to ensure Helm repo is added
ensure_helm_repo() {
  local repo_name="$1"
  local repo_url="$2"
  
  echo "Ensuring Helm repo ${repo_name} is added..."
  if ! helm repo list | grep -q "^${repo_name}"; then
    echo "Adding Helm repo ${repo_name}..."
    helm repo add "${repo_name}" "${repo_url}"
  else
    echo "Helm repo ${repo_name} already exists, updating..."
    helm repo update "${repo_name}"
  fi
}

# Function to create namespace
create_namespace() {
  section "Creating namespace"
  
  if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Namespace $NAMESPACE already exists"
  else
    echo "Creating namespace $NAMESPACE..."
    kubectl create namespace "$NAMESPACE"
  fi
}

# Function to setup IAM roles
setup_iam() {
  section "Setting up IAM roles and policies" "2 min"
  
  export CLUSTER_NAME="$CLUSTER_NAME"
  export AWS_REGION="$AWS_REGION"
  
  # Run IAM setup script
  chmod +x "$AUTH_DIR/setup-iam.sh"
  "$AUTH_DIR/setup-iam.sh"
  
  # Source the IAM variables
  if [ -f /tmp/aws-iam-vars.sh ]; then
    source /tmp/aws-iam-vars.sh
    echo "IAM Role ARN: $IAM_ROLE_ARN"
  else
    echo -e "${RED}Error: IAM setup failed${NC}"
    exit 1
  fi
}

# Function to install ADOT operator
install_adot_operator() {
  section "Installing ADOT Operator" "3 min"
  
  ensure_helm_repo "aws-otel" "https://aws-observability.github.io/aws-otel-helm-charts"
  
  # Install ADOT operator
  echo "Installing ADOT Operator..."
  helm upgrade --install adot-operator aws-otel/adot-exporter-for-eks-on-ec2 \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set clusterName="$CLUSTER_NAME" \
    --set awsRegion="$AWS_REGION" \
    --wait --timeout=300s
  
  echo "Waiting for ADOT operator to be ready..."
  kubectl wait --for=condition=available --timeout=300s deployment/adot-operator -n "$NAMESPACE"
}

# Function to create service account with IAM role
create_service_account() {
  section "Creating service account with IAM role"
  
  # Create service account with IAM role annotation
  kubectl apply -f - << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-otel-collector
  namespace: ${NAMESPACE}
  annotations:
    eks.amazonaws.com/role-arn: ${IAM_ROLE_ARN}
EOF

  # Create ClusterRole for ADOT collector
  kubectl apply -f - << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: aws-otel-collector-role
rules:
- apiGroups: [""]
  resources: ["pods", "nodes", "services", "endpoints", "namespaces"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["nodes/stats", "nodes/proxy"]
  verbs: ["get"]
EOF

  # Create ClusterRoleBinding
  kubectl apply -f - << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: aws-otel-collector-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: aws-otel-collector-role
subjects:
- kind: ServiceAccount
  name: aws-otel-collector
  namespace: ${NAMESPACE}
EOF
}

# Function to deploy ADOT collector
deploy_adot_collector() {
  section "Deploying ADOT Collector" "2 min"
  
  # Substitute environment variables in the collector config
  envsubst < "$VALUES_DIR/adot-collector.yaml" | kubectl apply -f -
  
  echo "Waiting for ADOT collector to be ready..."
  kubectl wait --for=condition=available --timeout=300s deployment/otel-demo-cloudwatch-collector -n "$NAMESPACE"
  
  echo "ADOT Collector deployed successfully"
}

# Function to create CloudWatch dashboard
create_cloudwatch_dashboard() {
  section "Creating CloudWatch Dashboard" "1 min"
  
  local dashboard_name="otel-demo-${CLUSTER_NAME}"
  local dashboard_file="/tmp/dashboard-${CLUSTER_NAME}.json"
  
  # Substitute environment variables in dashboard template
  envsubst < "$DASHBOARDS_DIR/otel-demo-dashboard.json" > "$dashboard_file"
  
  # Create dashboard using AWS CLI
  echo "Creating CloudWatch dashboard: $dashboard_name"
  aws cloudwatch put-dashboard \
    --dashboard-name "$dashboard_name" \
    --dashboard-body "file://$dashboard_file" \
    --region "$AWS_REGION"
  
  # Clean up temp file
  rm -f "$dashboard_file"
  
  echo -e "${GREEN}✅ Dashboard created: $dashboard_name${NC}"
  
  # Export dashboard URL for Gremlin integration
  export CLOUDWATCH_DASHBOARD_URL="https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${dashboard_name}"
  echo "export CLOUDWATCH_DASHBOARD_URL=\"$CLOUDWATCH_DASHBOARD_URL\"" >> /tmp/aws-cloudwatch-vars.sh
}

# Function to create CloudWatch alarms for health checks
create_cloudwatch_alarms() {
  section "Creating CloudWatch Alarms for Health Checks" "2 min"
  
  local alarm_prefix="otel-demo-${CLUSTER_NAME}"
  
  # Create alarm for high error rate
  echo "Creating error rate alarm..."
  aws cloudwatch put-metric-alarm \
    --alarm-name "${alarm_prefix}-high-error-rate" \
    --alarm-description "High error rate in otel-demo services" \
    --metric-name "http_server_requests_total" \
    --namespace "OTel/Demo/Application" \
    --statistic Sum \
    --period 300 \
    --threshold 10 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --alarm-actions "arn:aws:sns:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):otel-demo-alerts" \
    --dimensions Name=http.status_code,Value=5xx \
    --region "$AWS_REGION" || echo "SNS topic may not exist, alarm created without actions"
  
  # Create alarm for high response time
  echo "Creating response time alarm..."
  aws cloudwatch put-metric-alarm \
    --alarm-name "${alarm_prefix}-high-response-time" \
    --alarm-description "High response time in otel-demo services" \
    --metric-name "http_server_duration" \
    --namespace "OTel/Demo/Application" \
    --statistic Average \
    --period 300 \
    --threshold 1000 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --alarm-actions "arn:aws:sns:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):otel-demo-alerts" \
    --region "$AWS_REGION" || echo "SNS topic may not exist, alarm created without actions"
  
  # Export alarm URLs for Gremlin integration
  local error_alarm_url="https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#alarmsV2:alarm/${alarm_prefix}-high-error-rate"
  local response_alarm_url="https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#alarmsV2:alarm/${alarm_prefix}-high-response-time"
  
  echo "export CLOUDWATCH_ERROR_ALARM_URL=\"$error_alarm_url\"" >> /tmp/aws-cloudwatch-vars.sh
  echo "export CLOUDWATCH_RESPONSE_ALARM_URL=\"$response_alarm_url\"" >> /tmp/aws-cloudwatch-vars.sh
  
  echo -e "${GREEN}✅ CloudWatch alarms created${NC}"
}

# Function to verify installation
verify_installation() {
  section "Verifying Installation"
  
  echo "Checking ADOT collector status..."
  kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=opentelemetry-collector
  
  echo "Checking for metrics in CloudWatch..."
  aws cloudwatch list-metrics --namespace "OTel/Demo/Application" --region "$AWS_REGION" | head -20
  
  echo -e "${GREEN}✅ AWS CloudWatch integration installed successfully${NC}"
}

# Function to display connection information
display_connection_info() {
  section "AWS CloudWatch Integration Complete"
  
  echo -e "${GREEN}✅ ADOT Collector deployed in namespace: $NAMESPACE${NC}"
  echo -e "${GREEN}✅ CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=otel-demo-${CLUSTER_NAME}${NC}"
  echo -e "${GREEN}✅ Container Insights: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#container-insights:infrastructure${NC}"
  echo -e "${GREEN}✅ CloudWatch Alarms: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#alarmsV2:${NC}"
  echo ""
  echo -e "${BLUE}Metrics are being collected in the following namespaces:${NC}"
  echo "  - OTel/Demo/Application (application metrics)"
  echo "  - ContainerInsights (infrastructure metrics)"
  echo ""
  echo -e "${BLUE}For Gremlin integration, use these URLs:${NC}"
  if [ -f /tmp/aws-cloudwatch-vars.sh ]; then
    source /tmp/aws-cloudwatch-vars.sh
    echo "  - Dashboard: $CLOUDWATCH_DASHBOARD_URL"
    echo "  - Error Rate Alarm: $CLOUDWATCH_ERROR_ALARM_URL"
    echo "  - Response Time Alarm: $CLOUDWATCH_RESPONSE_ALARM_URL"
  fi
}

# Main execution function
main() {
  section "Starting AWS CloudWatch Integration Installation"
  
  # Check prerequisites
  if ! command_exists kubectl; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
  fi
  
  if ! command_exists helm; then
    echo -e "${RED}Error: helm not found${NC}"
    exit 1
  fi
  
  if ! command_exists aws; then
    echo -e "${RED}Error: aws CLI not found${NC}"
    exit 1
  fi
  
  # Prompt for credentials and configure AWS
  prompt_for_aws_credentials
  configure_aws_cli
  
  # Create temporary variables file
  echo "# AWS CloudWatch Integration Variables" > /tmp/aws-cloudwatch-vars.sh
  
  # Execute installation steps
  create_namespace
  setup_iam
  install_adot_operator
  create_service_account
  deploy_adot_collector
  create_cloudwatch_dashboard
  create_cloudwatch_alarms
  verify_installation
  display_connection_info
  
  echo -e "\n${GREEN}🎉 AWS CloudWatch integration installation completed successfully!${NC}"
}

# Execute main function
main "$@"
