#!/bin/bash -e

# Set AWS region
export AWS_DEFAULT_REGION=us-east-2
export AWS_REGION=us-east-2

# Show help information
show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo "Install Gremlin chaos engineering platform on the EKS cluster."
  echo ""
  echo "Options:"
  echo "  -n, --cluster-name NAME   Specify the cluster name to configure"
  echo "  -i, --istio               Enable Istio integration for Gremlin"
  echo "  -t, --team-id ID          Specify the Gremlin team ID"
  echo "  -s, --team-secret SECRET  Specify the Gremlin team secret"
  echo "  -c, --cluster-id ID       Specify a custom Gremlin cluster ID (defaults to cluster name)"
  echo "  -a, --auto-tag            Automatically tag all services in specified namespaces"
  echo "  -h, --help                Show this help message"
}

# Parse command line arguments
istio_integration=false
auto_tag=false
team_id=""
team_secret=""
cluster_id=""
namespaces_to_tag=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--cluster-name)
      export CLUSTER_NAME="$2"
      shift 2
      ;;
    -i|--istio)
      istio_integration=true
      shift
      ;;
    -t|--team-id)
      team_id="$2"
      shift 2
      ;;
    -s|--team-secret)
      team_secret="$2"
      shift 2
      ;;
    -c|--cluster-id)
      cluster_id="$2"
      shift 2
      ;;
    -a|--auto-tag)
      auto_tag=true
      if [[ "$2" != -* && ! -z "$2" ]]; then
        namespaces_to_tag="$2"
        shift 2
      else
        shift
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

# Function to apply Istio integration for Gremlin
apply_istio_integration() {
  echo -e "\n=== Applying Gremlin Istio integration ==="
  
  # Check if Istio is installed
  if kubectl get namespaces | grep -q istio-system; then
    echo "Applying Gremlin EnvoyFilter for Istio integration..."
    kubectl apply -f ../config/patches/gremlin-envoy-filter.yaml
    echo "✅ Gremlin Istio integration applied successfully!"
  else
    echo "⚠️  Warning: Istio namespace (istio-system) not found."
    echo "Istio integration was requested but Istio is not installed."
    echo "You can install Istio by running:"
    echo "  ./configure_cluster_base.sh -i -n ${CLUSTER_NAME}"
  fi
}

# Function to annotate services for Gremlin service discovery
annotate_services_for_gremlin() {
  local namespace="$1"
  echo -e "\n=== Annotating services in namespace '$namespace' for Gremlin service discovery ==="
  
  # Get all services in the namespace
  local services=$(kubectl get services -n "$namespace" -o jsonpath='{.items[*].metadata.name}')
  
  for service in $services; do
    echo "Annotating service '$service' in namespace '$namespace'..."
    
    # Check if annotation already exists
    local existing_annotation=$(kubectl get service "$service" -n "$namespace" -o jsonpath='{.metadata.annotations.gremlin\.com/service-id}' 2>/dev/null)
    
    if [ -z "$existing_annotation" ]; then
      # Add the annotation using the service name as the service-id
      kubectl annotate service "$service" -n "$namespace" "gremlin.com/service-id=$service" --overwrite
      echo "✅ Added Gremlin service-id annotation to service '$service'"
    else
      echo "ℹ️  Service '$service' already has Gremlin service-id annotation: '$existing_annotation'"
    fi
  done
}

# Function to prompt for Gremlin credentials if not provided
prompt_for_gremlin_credentials() {
  # Prompt for team ID if not provided
  if [ -z "$team_id" ]; then
    echo -e "\n=== Gremlin Team Configuration ==="
    echo -e "\nℹ️  No Gremlin team ID provided."
    echo "You can find your team ID in the Gremlin web interface under Team Settings."
    echo -e "\nDefault team ID: 438c58ec-03db-47ac-8c58-ec03db67ac42 (demo account)"
    read -p "Use default team ID? (y/n, default: y): " use_default_team_id
    
    if [[ -z "$use_default_team_id" || "$use_default_team_id" =~ ^[Yy]$ ]]; then
      team_id="438c58ec-03db-47ac-8c58-ec03db67ac42"
      echo "Using default team ID."
    else
      read -p "Enter your Gremlin team ID: " team_id
      if [ -z "$team_id" ]; then
        echo "❌ Error: Team ID cannot be empty. Using default."
        team_id="438c58ec-03db-47ac-8c58-ec03db67ac42"
      fi
    fi
  fi
  
  # Prompt for team secret if not provided
  if [ -z "$team_secret" ]; then
    echo -e "\nℹ️  No Gremlin team secret provided."
    echo "You can find your team secret in the Gremlin web interface under Team Settings."
    echo -e "\nDefault team secret: 27494963-e91a-43d3-8949-63e91a93d3c5 (demo account)"
    read -p "Use default team secret? (y/n, default: y): " use_default_team_secret
    
    if [[ -z "$use_default_team_secret" || "$use_default_team_secret" =~ ^[Yy]$ ]]; then
      team_secret="27494963-e91a-43d3-8949-63e91a93d3c5"
      echo "Using default team secret."
    else
      read -p "Enter your Gremlin team secret: " team_secret
      if [ -z "$team_secret" ]; then
        echo "❌ Error: Team secret cannot be empty. Using default."
        team_secret="27494963-e91a-43d3-8949-63e91a93d3c5"
      fi
    fi
  fi
  
  # Prompt for cluster ID if not provided
  if [ -z "$cluster_id" ]; then
    echo -e "\nℹ️  No custom Gremlin cluster ID provided."
    echo "The cluster ID is used to identify this cluster in the Gremlin web interface."
    echo -e "Default cluster ID: ${CLUSTER_NAME}"
    read -p "Use default cluster ID (${CLUSTER_NAME})? (y/n, default: y): " use_default_cluster_id
    
    if [[ -z "$use_default_cluster_id" || "$use_default_cluster_id" =~ ^[Yy]$ ]]; then
      cluster_id="${CLUSTER_NAME}"
      echo "Using default cluster ID: ${CLUSTER_NAME}"
    else
      read -p "Enter your custom Gremlin cluster ID: " cluster_id
      if [ -z "$cluster_id" ]; then
        echo "❌ Error: Cluster ID cannot be empty. Using default."
        cluster_id="${CLUSTER_NAME}"
      fi
    fi
  else
    # If cluster_id was provided via command line but is empty, use CLUSTER_NAME
    if [ -z "$cluster_id" ]; then
      cluster_id="${CLUSTER_NAME}"
    fi
  fi
}

# Function to prompt for namespaces to tag
prompt_for_namespaces_to_tag() {
  if [ "$auto_tag" = true ] && [ -z "$namespaces_to_tag" ]; then
    echo -e "\n=== Service Tagging Configuration ==="
    echo "Auto-tagging was enabled but no namespaces were specified."
    echo "Please specify which namespaces to tag for Gremlin service discovery."
    echo "Available namespaces:"
    kubectl get namespaces -o name | sed 's|namespace/||' | grep -v "kube-"
    echo -e "\nEnter namespaces separated by spaces (default: otel-demo):"
    read -p "> " input_namespaces
    
    if [ -z "$input_namespaces" ]; then
      namespaces_to_tag="otel-demo"
      echo "Using default namespace: otel-demo"
    else
      namespaces_to_tag="$input_namespaces"
    fi
  fi
}

# Function to install Gremlin with secret-based authentication
install_gremlin() {
  echo -e "\n=== Installing Gremlin with secret-based authentication ==="
  
  # Prompt for credentials if not provided
  prompt_for_gremlin_credentials
  
  # Create gremlin namespace if it doesn't exist
  if ! kubectl get namespace gremlin &>/dev/null; then
    echo "Creating gremlin namespace..."
    kubectl create namespace gremlin
  fi
  
  # Add Gremlin Helm repo if not already added
  ensure_helm_repo "gremlin" "https://helm.gremlin.com"
  
  # Install Gremlin using secret-based authentication
  echo "Installing Gremlin using secret-based authentication..."
  
  # Create the secret first
  echo "Creating Gremlin team secret..."
  kubectl create secret generic gremlin-team-cert \
    --namespace gremlin \
    --from-literal=GREMLIN_TEAM_ID="$team_id" \
    --from-literal=GREMLIN_TEAM_SECRET="$team_secret" \
    --dry-run=client -o yaml | kubectl apply -f -
  
  # Install Gremlin using Helm
  helm upgrade --install gremlin gremlin/gremlin \
    --namespace gremlin \
    --set gremlin.teamID="$team_id" \
    --set gremlin.clusterID="$cluster_id" \
    --set gremlin.secret.managed=false \
    --set gremlin.secret.type=secret
  
  # Success message
  echo -e "\n✅ Gremlin installation with secret-based authentication completed successfully!"
  echo "Team ID: $team_id"
  echo "Cluster ID: $cluster_id"
}

# Main execution
echo "=== Installing Gremlin on cluster: ${CLUSTER_NAME} ==="

# Update kubeconfig
echo "Updating kubeconfig..."
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}

# Prompt for namespaces to tag if auto-tag is enabled
prompt_for_namespaces_to_tag

# Install Gremlin
install_gremlin

# Apply Istio integration if requested
if [ "$istio_integration" = true ]; then
  apply_istio_integration
fi

# Annotate services in the specified namespaces or otel-demo by default
if [ "$auto_tag" = true ]; then
  for namespace in $namespaces_to_tag; do
    if kubectl get namespace "$namespace" &>/dev/null; then
      annotate_services_for_gremlin "$namespace"
      echo -e "\n✅ Service annotation for Gremlin completed successfully in namespace: $namespace"
    else
      echo -e "\n⚠️  Warning: Namespace '$namespace' not found. No services were annotated."
    fi
  done
else
  # Default behavior: annotate services in the otel-demo namespace
  if kubectl get namespace otel-demo &>/dev/null; then
    annotate_services_for_gremlin "otel-demo"
    echo -e "\n✅ Service annotation for Gremlin completed successfully in namespace: otel-demo"
  else
    echo -e "\n⚠️  Warning: otel-demo namespace not found. No services were annotated."
    echo "Run the OpenTelemetry demo installation first, then re-run this script to annotate services."
    echo "Or use the --auto-tag option to specify namespaces to tag."
  fi
fi
