#!/bin/bash -e

# Set AWS region
export AWS_DEFAULT_REGION=us-east-2
export AWS_REGION=us-east-2

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

# Function to configure subnet routing for load balancers
configure_subnet_routing() {
  echo "Configuring subnet routing for load balancers..."
  
  # Get VPC ID from the cluster
  local vpc_id=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.resourcesVpcConfig.vpcId" --output text)
  if [[ -z "$vpc_id" ]]; then
    echo "❌ Failed to get VPC ID for cluster ${CLUSTER_NAME}"
    return 1
  fi
  
  # Get internet gateway ID
  local igw_id=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${vpc_id}" --query "InternetGateways[0].InternetGatewayId" --output text)
  if [[ -z "$igw_id" || "$igw_id" == "None" ]]; then
    echo "❌ No internet gateway found for VPC ${vpc_id}"
    return 1
  fi
  
  # Get subnets with the kubernetes.io/role/elb tag
  local elb_subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${vpc_id}" "Name=tag:kubernetes.io/role/elb,Values=1" --query "Subnets[*].SubnetId" --output text)
  if [[ -z "$elb_subnets" ]]; then
    echo "❌ No subnets with kubernetes.io/role/elb tag found in VPC ${vpc_id}"
    return 1
  fi
  
  # Create a new route table for load balancer subnets
  echo "Creating route table for load balancer subnets..."
  local route_table_id=$(aws ec2 create-route-table --vpc-id ${vpc_id} --query "RouteTable.RouteTableId" --output text)
  if [[ -z "$route_table_id" ]]; then
    echo "❌ Failed to create route table"
    return 1
  fi
  
  # Add a tag to the route table
  aws ec2 create-tags --resources ${route_table_id} --tags Key=Name,Value=${CLUSTER_NAME}-lb-route-table Key=ManagedBy,Value=install_load_balancer.sh
  
  # Add a route to the internet gateway
  echo "Adding route to internet gateway..."
  aws ec2 create-route --route-table-id ${route_table_id} --destination-cidr-block 0.0.0.0/0 --gateway-id ${igw_id}
  
  # Associate the route table with the load balancer subnets
  echo "Associating route table with load balancer subnets..."
  for subnet_id in ${elb_subnets}; do
    echo "Associating subnet ${subnet_id} with route table ${route_table_id}"
    aws ec2 associate-route-table --route-table-id ${route_table_id} --subnet-id ${subnet_id}
  done
  
  echo "✅ Subnet routing for load balancers configured successfully!"
}

# Function to create an ALB/CLB for the OpenTelemetry demo frontend-proxy
create_load_balancer() {
  local lb_type="$1"
  echo "=== Creating ${lb_type} for OpenTelemetry demo ==="
  
  # Update kubeconfig
  echo "Updating kubeconfig..."
  aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}
  
  # Check if the frontend-proxy service exists
  if ! kubectl get service otel-demo-frontendproxy -n otel-demo &>/dev/null; then
    echo -e "\n⚠️  Warning: otel-demo-frontendproxy service not found in otel-demo namespace!"
    echo "The OpenTelemetry demo doesn't appear to be installed yet."
    echo "You should install the OpenTelemetry demo first with:"
    echo "  ./fix_configure_otel_demo.sh -n ${CLUSTER_NAME}"
    exit 1
  fi
  
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
            name: otel-demo-frontendproxy
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
            name: otel-demo-frontendproxy
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
  
  # Clean up the temporary file
  rm -f ${ingress_file}
}

# Main execution
echo "=== Installing load balancer for OpenTelemetry demo on cluster: ${CLUSTER_NAME} ==="

# Configure subnet routing for load balancers
echo "=== Configuring subnet routing for load balancers ==="
configure_subnet_routing

# Create the load balancer
create_load_balancer "${lb_type}"
