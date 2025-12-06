#!/bin/bash -e

# Set AWS region
export AWS_DEFAULT_REGION=${AWS_REGION:-us-east-2}
export AWS_REGION=${AWS_REGION:-us-east-2}

# Show help information
show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo "Install a load balancer for the OpenTelemetry demo frontend-proxy."
  echo ""
  echo "Options:"
  echo "  -n, --cluster-name NAME   Specify the cluster name to configure"
  echo "  -t, --type TYPE           Load balancer type (alb or clb), defaults to alb"
  echo "  -h, --help                Show this help message"
}

# Parse command line arguments
lb_type="alb" # Default to ALB
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--cluster-name)
      export CLUSTER_NAME="$2"
      shift 2
      ;;
    -t|--type)
      if [[ "$2" == "alb" || "$2" == "clb" ]]; then
        lb_type="$2"
        shift 2
      else
        echo "Error: Load balancer type must be either 'alb' or 'clb'"
        show_help
        exit 1
      fi
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Error: Unknown parameter: $1"
      show_help
      exit 1
      ;;
  esac
done

# Set default cluster name if not provided
if [ -z "${CLUSTER_NAME}" ]; then
  CLUSTER_NAME="current-workshop"
  echo "CLUSTER_NAME not set, using default: ${CLUSTER_NAME}"
fi

# Function to verify subnet configuration for load balancers
verify_subnet_configuration() {
  echo "Verifying load balancer subnet configuration..."
  
  # Get VPC ID from the cluster
  local vpc_id=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.resourcesVpcConfig.vpcId" --output text)
  if [[ -z "$vpc_id" ]]; then
    echo "❌ Failed to get VPC ID for cluster ${CLUSTER_NAME}"
    return 1
  fi
  
  # Get subnets with the kubernetes.io/role/elb tag (public subnets for ALB)
  local elb_subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${vpc_id}" "Name=tag:kubernetes.io/role/elb,Values=1" --query "Subnets[*].SubnetId" --output text)
  if [[ -z "$elb_subnets" ]]; then
    echo "❌ No public subnets with kubernetes.io/role/elb tag found in VPC ${vpc_id}"
    echo "This is required for ALB creation. Please ensure your EKS cluster has public subnets."
    return 1
  fi
  
  local subnet_count=$(echo $elb_subnets | wc -w)
  echo "✅ Found ${subnet_count} public subnet(s) ready for load balancer deployment"
  echo "✅ EKS subnets are pre-configured with internet routing - no additional setup needed"
}

# Function to create an ALB/CLB for the OpenTelemetry demo frontend-proxy
create_load_balancer() {
  local lb_type="$1"
  echo "=== Creating ${lb_type} for OpenTelemetry demo ==="
  
  # Update kubeconfig
  echo "Updating kubeconfig..."
  aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}
  
  # Check if the frontend-proxy service exists (try both naming conventions)
  if kubectl get service frontend-proxy -n otel-demo &>/dev/null; then
    FRONTEND_SERVICE="frontend-proxy"
  elif kubectl get service otel-demo-frontendproxy -n otel-demo &>/dev/null; then
    FRONTEND_SERVICE="otel-demo-frontendproxy"
  else
    echo -e "\n⚠️  Warning: frontend-proxy service not found in otel-demo namespace!"
    echo "The OpenTelemetry demo doesn't appear to be installed yet."
    echo "You should install the OpenTelemetry demo first."
    exit 1
  fi
  
  echo "✅ Found frontend service: ${FRONTEND_SERVICE}"
  
  # Create a temporary ingress manifest file
  local ingress_file="/tmp/otel-demo-ingress.yaml"
  
  # Configure annotations based on load balancer type
  if [ "${lb_type}" = "clb" ]; then
    echo "Configuring Classic Load Balancer (CLB)..."
    cat > ${ingress_file} <<EOL
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: otel-demo-ingress
  namespace: otel-demo
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=600
    alb.ingress.kubernetes.io/healthcheck-path: /
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '15'
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '5'
    alb.ingress.kubernetes.io/healthy-threshold-count: '2'
    alb.ingress.kubernetes.io/unhealthy-threshold-count: '2'
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/security-groups: ${CLUSTER_NAME}-alb-access
    alb.ingress.kubernetes.io/manage-backend-security-group-rules: "true"
    alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=30
    # Force use of CLB instead of ALB
    service.beta.kubernetes.io/aws-load-balancer-type: "classic"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${FRONTEND_SERVICE}
            port:
              number: 8080
EOL
  else
    # Default to ALB
    echo "Configuring Application Load Balancer (ALB)..."
    cat > ${ingress_file} <<EOL
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: otel-demo-ingress
  namespace: otel-demo
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=600
    alb.ingress.kubernetes.io/healthcheck-path: /
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '15'
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '5'
    alb.ingress.kubernetes.io/healthy-threshold-count: '2'
    alb.ingress.kubernetes.io/unhealthy-threshold-count: '2'
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/security-groups: ${CLUSTER_NAME}-alb-access
    alb.ingress.kubernetes.io/manage-backend-security-group-rules: "true"
    alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=30
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${FRONTEND_SERVICE}
            port:
              number: 8080
EOL
  fi
  
  # Apply the ingress manifest
  echo "Applying ingress manifest..."
  kubectl apply -f ${ingress_file}
  
  # Wait for the ingress to be created
  echo "Waiting for load balancer to be provisioned (this may take a few minutes)..."
  kubectl wait --namespace=otel-demo \
    --for=jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
    --timeout=300s \
    ingress/otel-demo-ingress
  
  # Get the load balancer hostname
  local lb_hostname=$(kubectl get ingress -n otel-demo otel-demo-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  
  echo -e "\n✅ ${lb_type} created successfully!"
  echo "Load balancer hostname: ${lb_hostname}"
  echo "You can access the OpenTelemetry demo at: http://${lb_hostname}/"
  echo "Note: It may take a few minutes for DNS to propagate and the load balancer to become fully available."
  
  # Update load generator to point to the new load balancer (only if using basic config)
  echo -e "\n🎯 Checking load generator configuration..."
  if kubectl get deployment load-generator -n otel-demo -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="LOCUST_HOST")].value}' | grep -q "frontend-proxy"; then
    echo "Enhanced configuration detected - load generator already configured via Helm values"
  else
    echo "Basic configuration detected - updating load generator to target load balancer..."
    if [ -f "../../helper_scripts/update_loadgen_target.sh" ]; then
      cd ../..
      ./helper_scripts/update_loadgen_target.sh "http://${lb_hostname}"
      cd build_scripts/load-balancer
    else
      echo "⚠️  Load generator update script not found - skipping"
    fi
  fi
  
  # Clean up the temporary file
  rm -f ${ingress_file}
}

# Main execution
echo "=== Installing load balancer for OpenTelemetry demo on cluster: ${CLUSTER_NAME} ==="

# Check if enhanced configuration ALB ingress already exists
if kubectl get ingress frontend-proxy -n otel-demo >/dev/null 2>&1; then
    ALB_HOSTNAME=$(kubectl get ingress frontend-proxy -n otel-demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ -n "$ALB_HOSTNAME" ]; then
        # Update load generator silently
        if [ -f "/Users/seanwiley/workshop/helper_scripts/update_loadgen_target.sh" ]; then
            /Users/seanwiley/workshop/helper_scripts/update_loadgen_target.sh "http://${ALB_HOSTNAME}" >/dev/null 2>&1
        fi
    fi
    exit 0
fi

echo "ℹ️  No enhanced ingress found - creating separate load balancer"
echo "ℹ️  This is for basic configurations or manual override"

# Verify subnet configuration for load balancers
echo "=== Verifying subnet configuration for load balancers ==="
verify_subnet_configuration

# Create the load balancer
create_load_balancer "${lb_type}"
