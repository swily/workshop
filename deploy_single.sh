#!/bin/bash -e

export AWS_DEFAULT_REGION=us-east-2
export AWS_REGION=us-east-2

# Default values
NAMESPACE="otel-demo-custom"
CLUSTER_NAME="otel-demo-single"
OWNER="$(whoami)"
EXPIRATION=$(date -v +7d +%Y-%m-%d)
GREMLIN_TEAM="Group 01"  # Use an existing team from SSM

# Parse command line arguments
while getopts "n:c:o:e:g:" opt; do
  case $opt in
    n) NAMESPACE="$OPTARG" ;;
    c) CLUSTER_NAME="$OPTARG" ;;
    o) OWNER="$OPTARG" ;;
    e) EXPIRATION="$OPTARG" ;;
    g) GREMLIN_TEAM="$OPTARG" ;;
    *) echo "Usage: $0 [-n namespace] [-c cluster_name] [-o owner] [-e expiration_date] [-g gremlin_team]" >&2
       exit 1 ;;
  esac
done

echo "Deploying OpenTelemetry demo to:"
echo "  Cluster: $CLUSTER_NAME"
echo "  Namespace: $NAMESPACE"
echo "  Owner: $OWNER"
echo "  Expiration: $EXPIRATION"
echo "  Gremlin Team: $GREMLIN_TEAM"
echo "Sleeping for 5 seconds - press Ctrl+C to cancel..."
sleep 5

# Validate AWS Account
if [ $(aws sts get-caller-identity | jq -r .Account) -ne 856940208208 ]; then
  echo "This script is intended to be run in the Gremlin Sales Demo AWS account."
  echo "The current AWS credentials are not for this account. Please check your AWS CLI configuration."
  exit 1
fi

# Convert namespace to valid k8s format (lowercase, hyphens instead of underscores)
NAMESPACE=$(echo "$NAMESPACE" | tr '[:upper:]' '[:lower:]' | tr '_' '-')

# Use the provided cluster name directly
ACTUAL_CLUSTER_NAME="$CLUSTER_NAME"

# Check if cluster already exists
if eksctl get clusters | grep -q "^$ACTUAL_CLUSTER_NAME "; then
  echo "Cluster $ACTUAL_CLUSTER_NAME already exists, using existing cluster"
else
  echo "Creating new cluster: $ACTUAL_CLUSTER_NAME"
  # Create temporary eksctl config file
  TMP_CONFIG=$(mktemp)
  cat ./templates/eksctl-custom.yaml | \
    sed -e "s/{{.CLUSTER_NAME}}/$ACTUAL_CLUSTER_NAME/g" \
    -e "s/{{.OWNER}}/$OWNER/g" \
    -e "s/{{.EXPIRATION}}/$EXPIRATION/g" > $TMP_CONFIG
  
  # Create the cluster
  eksctl create cluster -f $TMP_CONFIG
  rm $TMP_CONFIG
fi

# Update kubeconfig
eksctl utils write-kubeconfig --cluster $ACTUAL_CLUSTER_NAME

# Wait for nodes to be ready
echo "Waiting for nodes to be ready..."
while true; do
  READY_NODES=$(kubectl get nodes | grep -c "Ready")
  TOTAL_NODES=$(kubectl get nodes | grep -c "<none>")
  if [ "$READY_NODES" -eq "$TOTAL_NODES" ] && [ "$READY_NODES" -gt 0 ]; then
    echo "All $READY_NODES nodes are ready"
    break
  fi
  echo "Waiting for nodes to be ready ($READY_NODES/$TOTAL_NODES)..."
  sleep 10
done

# Wait for core components
echo "Waiting for core components..."
while true; do
  if kubectl get pods -n kube-system | grep -q "aws-node.*Running" && \
     kubectl get pods -n kube-system | grep -q "kube-proxy.*Running" && \
     kubectl get pods -n kube-system | grep -q "coredns.*Running"; then
    echo "Core components are ready"
    break
  fi
  echo "Waiting for core components..."
  sleep 10
done

# Install OpenTelemetry demo first (less privileged)
echo "Installing OpenTelemetry demo in namespace $NAMESPACE"
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>&1 | grep -v skipping
helm repo update

# Check if already installed
if helm list -n $NAMESPACE 2>/dev/null | grep -q "opentelemetry-demo"; then
  echo "OpenTelemetry demo already installed in namespace $NAMESPACE"
else
  # Install OpenTelemetry demo with custom values
  # Create namespace first to ensure it exists for the secret
  kubectl create namespace $NAMESPACE 2>/dev/null || true

  # Create the secret for OpenTelemetry collector
  echo "Creating OpenTelemetry collector secret"
  kubectl create secret generic otelcol-keys -n $NAMESPACE --from-literal=MY_POD_IP=0.0.0.0 2>/dev/null || true

  # Install OpenTelemetry demo
  helm install opentelemetry-demo open-telemetry/opentelemetry-demo \
    --version 0.34.2 \
    --create-namespace \
    -n $NAMESPACE \
    --values ./templates/otelcol-config-gremlin-enhanced.yaml
fi

# Wait for OpenTelemetry pods to be ready
echo "Waiting for OpenTelemetry pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=opentelemetry-demo -n $NAMESPACE --timeout=300s

# Now install Gremlin (needs more system access)
echo "Installing Gremlin"
# Use the specified Gremlin team
TEAM_NAME="$GREMLIN_TEAM"

# Retrieve secret for the selected team
# Check if the team name starts with 'Group ' - if not, try both with and without the prefix
if [[ "$TEAM_NAME" != Group* ]]; then
  # Try first without the Group prefix
  team_id=$(aws ssm get-parameter --name '/Bootcamp/TeamSecrets' --with-decryption | jq -r --arg team "${TEAM_NAME}" '.Parameter.Value | fromjson | .[$team].team_id')
  team_secret=$(aws ssm get-parameter --name '/Bootcamp/TeamSecrets' --with-decryption | jq -r --arg team "${TEAM_NAME}" '.Parameter.Value | fromjson | .[$team].team_secret')
  
  # If that fails, try with the Group prefix
  if [ -z "$team_id" ] || [ "$team_id" == "null" ]; then
    GROUP_TEAM_NAME="Group ${TEAM_NAME}"
    team_id=$(aws ssm get-parameter --name '/Bootcamp/TeamSecrets' --with-decryption | jq -r --arg team "${GROUP_TEAM_NAME}" '.Parameter.Value | fromjson | .[$team].team_id')
    team_secret=$(aws ssm get-parameter --name '/Bootcamp/TeamSecrets' --with-decryption | jq -r --arg team "${GROUP_TEAM_NAME}" '.Parameter.Value | fromjson | .[$team].team_secret')
    if [ -n "$team_id" ] && [ "$team_id" != "null" ]; then
      TEAM_NAME="$GROUP_TEAM_NAME"
    fi
  fi
else
  # Original behavior for team names that already start with 'Group '
  team_id=$(aws ssm get-parameter --name '/Bootcamp/TeamSecrets' --with-decryption | jq -r --arg team "${TEAM_NAME}" '.Parameter.Value | fromjson | .[$team].team_id')
  team_secret=$(aws ssm get-parameter --name '/Bootcamp/TeamSecrets' --with-decryption | jq -r --arg team "${TEAM_NAME}" '.Parameter.Value | fromjson | .[$team].team_secret')
fi

# Install Gremlin via helm in its own namespace
echo "Installing Gremlin for ${TEAM_NAME}"
echo "Team ID: ${team_id}"
helm repo add gremlin https://helm.gremlin.com 2>&1 | grep -v skipping

if helm get values gremlin -n gremlin > /dev/null 2>&1; then
  echo "Gremlin already installed in namespace gremlin"
else
  helm install gremlin gremlin/gremlin \
    --namespace gremlin \
    --create-namespace \
    --set gremlin.secret.managed=true \
    --set gremlin.secret.type=secret \
    --set gremlin.clusterID=$CLUSTER_NAME \
    --set gremlin.secret.teamID="${team_id}" \
    --set gremlin.secret.teamSecret="${team_secret}" \
    --set gremlin.container.driver=containerd-linux \
    --set gremlin.hostPID=true \
    --set gremlin.hostNetwork=true
fi

# Wait for Gremlin to be ready
echo "Waiting for Gremlin to be ready..."
kubectl wait --for=condition=ready pod -l app=gremlin -n gremlin --timeout=300s || true

# Define services to annotate and scale (core services only, excluding infrastructure)
SERVICES="otel-demo-accountingservice otel-demo-adservice otel-demo-cartservice otel-demo-checkoutservice otel-demo-currencyservice otel-demo-emailservice otel-demo-frontend otel-demo-frauddetectionservice otel-demo-paymentservice otel-demo-productcatalogservice otel-demo-quoteservice otel-demo-recommendationservice otel-demo-shippingservice"

# Annotate and scale services
echo "Scaling and annotating services..."
for deployment in $(kubectl get deployment -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
  if [ -z "$(echo $SERVICES | grep ${deployment})" ]; then
    continue
  fi
  echo "Annotating: $deployment"
  # Add service annotations with unique identifier to prevent conflicts
  kubectl annotate deployment $deployment -n $NAMESPACE "gremlin.com/service-id=$CLUSTER_NAME-$NAMESPACE-${deployment}" --overwrite
  # Scale deployments
  kubectl scale deployment $deployment -n $NAMESPACE --replicas=2
done

# Get HTTP endpoints
echo "Getting HTTP endpoints"
kubectl get svc -n $NAMESPACE otel-demo-frontendproxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo ""

echo "Deployment complete!"
echo "To access the frontend, use the URL above."
echo "To clean up this deployment, run: ./clean_single.sh -c $CLUSTER_NAME -n $NAMESPACE"
