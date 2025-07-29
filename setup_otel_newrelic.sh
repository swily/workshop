#!/bin/bash -e

# Configuration
CLUSTER_NAME="seanwiley-otel"
OWNER="seanwiley"
AWS_REGION="us-east-2"
EXPIRATION=$(date -v +30d +%Y-%m-%d)

# Set SSH key path
SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"

# Create SSH key if it doesn't exist
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "SSH key not found at $SSH_KEY_PATH"
    echo "Generating a new SSH key..."
    mkdir -p ~/.ssh
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "${USER}@${HOSTNAME}"
    chmod 600 ~/.ssh/id_rsa*
    echo "SSH key generated at $SSH_KEY_PATH"
fi

# Export SSH key name for use in node group config
export SSH_KEY_NAME="${USER}-${CLUSTER_NAME}-key"

# Import or create the key pair in AWS
existing_key=$(aws ec2 describe-key-pairs --key-names "$SSH_KEY_NAME" --query 'KeyPairs[0].KeyName' --output text 2>/dev/null || true)
if [ -z "$existing_key" ]; then
    echo "Creating EC2 key pair: $SSH_KEY_NAME"
    aws ec2 import-key-pair --key-name "$SSH_KEY_NAME" --public-key-material "fileb://$SSH_KEY_PATH"
else
    echo "Using existing EC2 key pair: $SSH_KEY_NAME"
fi

# Gremlin Credentials
# Get from environment variable or prompt if not set
if [ -z "$GREMLIN_TEAM_ID" ]; then
  echo "Please enter your Gremlin Team ID:"
  read -r GREMLIN_TEAM_ID
  if [ -z "$GREMLIN_TEAM_ID" ]; then
    echo "Error: Gremlin Team ID is required"
    exit 1
  fi
  export GREMLIN_TEAM_ID
fi

if [ -z "$GREMLIN_TEAM_SECRET" ]; then
  echo "Please enter your Gremlin Team Secret:"
  read -r GREMLIN_TEAM_SECRET
  if [ -z "$GREMLIN_TEAM_SECRET" ]; then
    echo "Error: Gremlin Team Secret is required"
    exit 1
  fi
  export GREMLIN_TEAM_SECRET
fi

# New Relic Configuration
# Get from environment variable or prompt if not set
if [ -z "$NEW_RELIC_LICENSE_KEY" ]; then
  echo "Please enter your New Relic License Key:"
  read -r NEW_RELIC_LICENSE_KEY
  if [ -z "$NEW_RELIC_LICENSE_KEY" ]; then
    echo "Error: New Relic License Key is required"
    exit 1
  fi
  export NEW_RELIC_LICENSE_KEY
fi

# Set environment variables
export CLUSTER_NAME AWS_REGION OWNER EXPIRATION
export AWS_DEFAULT_REGION=$AWS_REGION

# AWS Account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Function to print section headers
section() {
  echo -e "\n=== $1 ==="
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check for required tools
section "Checking for required tools"
for cmd in aws eksctl kubectl helm jq; do
  if ! command_exists "$cmd"; then
    echo "Error: $cmd is not installed"
    exit 1
  fi
done

# Clean existing cluster if it exists
section "Cleaning existing cluster"
if [ -f "./clean_cluster_fast.sh" ]; then
  ./clean_cluster_fast.sh
else
  echo "clean_cluster_fast.sh not found, falling back to clean_cluster.sh"
  if [ -f "./clean_cluster.sh" ]; then
    ./clean_cluster.sh
  else
    echo "No cleanup script found, skipping cleanup"
  fi
fi

# Create new cluster
section "Creating new EKS cluster"
if [ -f "./build_cluster.sh" ]; then
  ./build_cluster.sh
else
  echo "build_cluster.sh not found, please ensure it exists"
  exit 1
fi

# Function to delete existing node groups
cleanup_nodegroups() {
  section "Cleaning up existing node groups"
  local nodegroups=$(aws eks list-nodegroups --cluster-name ${CLUSTER_NAME} --query 'nodegroups' --output text)
  
  if [ -n "$nodegroups" ]; then
    echo "Found existing node groups: $nodegroups"
    for ng in $nodegroups; do
      echo "Deleting node group: $ng"
      aws eks delete-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name $ng --region ${AWS_REGION}
    done
    
    # Wait for node groups to be deleted
    for ng in $nodegroups; do
      echo "Waiting for node group $ng to be deleted..."
      aws eks wait nodegroup-deleted --cluster-name ${CLUSTER_NAME} --nodegroup-name $ng --region ${AWS_REGION}
    done
  else
    echo "No existing node groups found"
  fi
}

# Function to create a new node group
create_nodegroup() {
  section "Creating new node group"
  local ng_config="/tmp/ng-config-$(date +%s).yaml"
  
  cat > $ng_config <<EOL
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  version: "1.30"

vpc:
  id: vpc-0ae237bb717910ccc
  subnets:
    private:
      us-east-2a: { id: subnet-0403fbdc0a75620d6 }  # Private in us-east-2a
      us-east-2b: { id: subnet-0dcb40d6b8fad2c03 }  # Private in us-east-2b
      us-east-2c: { id: subnet-0d36418b808d97976 }  # Private in us-east-2c
    public:
      us-east-2a: { id: subnet-08038efe886c31791 }  # Public in us-east-2a
      us-east-2b: { id: subnet-0135b61262e48f4d6 }  # Public in us-east-2b
      us-east-2c: { id: subnet-0fe7be30ec2528c4c }  # Public in us-east-2c

managedNodeGroups:
  - name: ${CLUSTER_NAME}-ng
    minSize: 2
    maxSize: 4
    desiredCapacity: 2
    instanceType: t3.medium
    volumeSize: 20
    amiFamily: AmazonLinux2023
    tags:
      Environment: Demo
      Owner: ${OWNER}
      k8s.io/cluster-autoscaler/enabled: "true"
      k8s.io/cluster-autoscaler/${CLUSTER_NAME}: owned
    iam:
      instanceRoleARN: arn:aws:iam::856940208208:role/DemosVPC-EksNodeInstanceRole
    securityGroups:
      attachIDs:
        - sg-0a499ed85cbdf45c5
    ssh:
      allow: true
      publicKeyName: ${SSH_KEY_NAME}
EOL

  echo "Creating node group with config:"
  cat $ng_config
  
  eksctl create nodegroup -f $ng_config
  
  # Wait for node group to be active
  echo "Waiting for node group to be active..."
  aws eks wait nodegroup-active \
    --cluster-name ${CLUSTER_NAME} \
    --nodegroup-name ${CLUSTER_NAME}-ng \
    --region ${AWS_REGION}
    
  rm -f $ng_config
}

# Check if cluster exists, if not create it with proper VPC config
section "Ensuring EKS cluster exists with proper configuration"

if ! aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION &>/dev/null; then
  echo "Creating EKS cluster $CLUSTER_NAME..."
  
  # Create the cluster with proper VPC config
  eksctl create cluster \
    --name $CLUSTER_NAME \
    --version 1.30 \
    --region $AWS_REGION \
    --vpc-private-subnets=subnet-0fe7be30ec2528c4c,subnet-08038efe886c31791,subnet-0135b61262e48f4d6 \
    --vpc-public-subnets=subnet-0403fbdc0a75620d6,subnet-0dcb40d6b8fad2c03,subnet-0d36418b808d97976 \
    --vpc-cidr 172.16.0.0/16 \
    --without-nodegroup \
    --asg-access \
    --full-ecr-access \
    --appmesh-access \
    --alb-ingress-access \
    --verbose 4
  
  # Update cluster VPC config to enable private endpoint access
  echo "Updating cluster VPC configuration..."
  aws eks update-cluster-config \
    --region $AWS_REGION \
    --name $CLUSTER_NAME \
    --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=false,publicAccessCidrs="0.0.0.0/0" \
    --no-cli-pager
  
  echo "Waiting for cluster update to complete..."
  aws eks wait cluster-active --name $CLUSTER_NAME --region $AWS_REGION
else
  echo "Cluster $CLUSTER_NAME already exists, ensuring VPC configuration is correct..."
  
  # Ensure VPC config is correct even if cluster exists
  aws eks update-cluster-config \
    --region $AWS_REGION \
    --name $CLUSTER_NAME \
    --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=false,publicAccessCidrs=\"0.0.0.0/0\" \
    --no-cli-pager || true
  
  aws eks wait cluster-active --name $CLUSTER_NAME --region $AWS_REGION
fi

# Clean up any existing node groups
cleanup_nodegroups

# Create new node group
create_nodegroup

# Verify nodes are ready
section "Waiting for nodes to be ready"
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || true)
  if [ "$READY_NODES" -ge 1 ]; then
    echo "Found $READY_NODES node(s) in Ready state"
    kubectl get nodes
    break
  fi
  
  RETRY_COUNT=$((RETRY_COUNT+1))
  echo "Waiting for nodes to be ready... (Attempt $RETRY_COUNT/$MAX_RETRIES)"
  sleep 20
  
  if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    # Check if cluster exists, if not create it
    if ! aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION &>/dev/null; then
      echo "Creating EKS cluster $CLUSTER_NAME..."
      
      # First create the cluster with proper VPC config
      eksctl create cluster \
        --name $CLUSTER_NAME \
        --version 1.30 \
        --region $AWS_REGION \
        --vpc-private-subnets=subnet-0fe7be30ec2528c4c,subnet-08038efe886c31791,subnet-0135b61262e48f4d6 \
        --vpc-public-subnets=subnet-0403fbdc0a75620d6,subnet-0dcb40d6b8fad2c03,subnet-0d36418b808d97976 \
        --vpc-cidr 172.16.0.0/16 \
        --without-nodegroup \
        --asg-access \
        --full-ecr-access \
        --appmesh-access \
        --alb-ingress-access \
        --verbose 4
      
      # Update cluster VPC config to enable private endpoint access
      echo "Updating cluster VPC configuration..."
      aws eks update-cluster-config \
        --region $AWS_REGION \
        --name $CLUSTER_NAME \
        --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=false,publicAccessCidrs="0.0.0.0/0" \
        --no-cli-pager
      
      echo "Waiting for cluster update to complete..."
      aws eks wait cluster-active --name $CLUSTER_NAME --region $AWS_REGION
    else
      echo "Cluster $CLUSTER_NAME already exists, skipping creation"
      
      # Ensure VPC config is correct even if cluster exists
      echo "Ensuring VPC configuration is correct..."
      aws eks update-cluster-config \
        --region $AWS_REGION \
        --name $CLUSTER_NAME \
        --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=false,publicAccessCidrs="0.0.0.0/0" \
        --no-cli-pager || true
    fi
    
    # Install base components (ALB Controller only)
    section "Installing base components"
    if [ -f "./configure_cluster_base.sh" ]; then
      ./configure_cluster_base.sh
    else
      echo "configure_cluster_base.sh not found, please ensure it exists"
      exit 1
    fi
  fi
done

# Install New Relic
section "Installing New Relic"

# Create namespaces
kubectl create namespace newrelic --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace gremlin --dry-run=client -o yaml | kubectl apply -f -

# Create New Relic secret
kubectl create secret generic newrelic-license \
  --from-literal=licenseKey="$NEW_RELIC_LICENSE_KEY" \
  -n newrelic --dry-run=client -o yaml | kubectl apply -f -

# Add New Relic Helm repo
helm repo add newrelic https://helm-charts.newrelic.com
helm repo update

# Install New Relic Kubernetes integration
helm upgrade --install newrelic-bundle newrelic/nri-bundle \
  --namespace newrelic \
  --set global.licenseKey="$NEW_RELIC_LICENSE_KEY" \
  --set global.cluster="$CLUSTER_NAME" \
  --set kube-state-metrics.enabled=true \
  --set kube-state-metrics.image.tag=v2.10.0 \
  --set kube-events.enabled=true \
  --set kubeEvents.enabled=true \
  --set prometheus.enabled=true \
  --set prometheus.nginx.enabled=true \
  --set infrastructure.enabled=true \
  --set logging.enabled=true \
  --set logging.fluentBit.enabled=true \
  --set logging.fluentBit.containers.enable=true \
  --wait

# Configure AWS Load Balancer Controller for Gremlin health checks
section "Configuring AWS Load Balancer Controller"

# Install AWS Load Balancer Controller if not already installed
if ! kubectl get deployment -n kube-system aws-load-balancer-controller &>/dev/null; then
  echo "=== Installing AWS Load Balancer Controller ==="
  
  # Install the TargetGroupBinding CRDs first
  echo "Installing AWS Load Balancer Controller CRDs..."
  kubectl apply -f https://github.com/aws/eks-charts/raw/master/stable/aws-load-balancer-controller/crds/crds.yaml
  
  # Download IAM policy
  echo "Downloading IAM policy..."
  curl -s -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.7/docs/install/iam_policy.json
  
  # Create IAM policy if it doesn't exist
  if ! aws iam get-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy &>/dev/null; then
    aws iam create-policy \
      --policy-name AWSLoadBalancerControllerIAMPolicy \
      --policy-document file://iam-policy.json
  else
    echo "IAM policy already exists, skipping creation"
  fi
  
  # Create IAM service account
  eksctl create iamserviceaccount \
    --cluster=${CLUSTER_NAME} \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
    --override-existing-serviceaccounts \
    --region ${AWS_REGION} \
    --approve
  
  # Install AWS Load Balancer Controller using Helm
  helm repo add eks https://aws.github.io/eks-charts
  helm repo update
  
  # Wait for the CRDs to be established
  kubectl wait --for=condition=established --timeout=300s crd/targetgroupbindings.elbv2.k8s.aws
  
  helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=${CLUSTER_NAME} \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region=${AWS_REGION} \
    --set vpcId=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.resourcesVpcConfig.vpcId' --output text) \
    --set image.repository=602401143452.dkr.ecr.${AWS_REGION}.amazonaws.com/amazon/aws-load-balancer-controller \
    --set image.tag=v2.4.7
fi

# Install Gremlin
section "Installing Gremlin"

# Install Gremlin using Helm with our credentials
helm repo add gremlin https://helm.gremlin.com
helm repo update

# Create values file for Gremlin with health check configuration
cat > gremlin-values.yaml <<-EOF
gremlin:
  api:
    enabled: true
    service:
      type: ClusterIP
      port: 80
      targetPort: 8080
      annotations:
        service.beta.kubernetes.io/aws-load-balancer-type: external
        service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
        service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
        service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: HTTP
        service.beta.kubernetes.io/aws-load-balancer-healthcheck-port: "80"
        service.beta.kubernetes.io/aws-load-balancer-healthcheck-path: "/healthz"
        service.beta.kubernetes.io/aws-load-balancer-healthcheck-healthy-threshold: "2"
        service.beta.kubernetes.io/aws-load-balancer-healthcheck-unhealthy-threshold: "2"
        service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval: "10"
        service.beta.kubernetes.io/aws-load-balancer-healthcheck-timeout: "6"
        service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
  livenessProbe:
    httpGet:
      path: /healthz
      port: 8080
    initialDelaySeconds: 30
    periodSeconds: 10
  container:
  hostPID: true
  hostNetwork: true
  container:
    driver: containerd-linux
  secret:
    create: true
    managed: true
    type: secret
    name: gremlin-secret
    teamID: "$GREMLIN_TEAM_ID"
    clusterID: "$CLUSTER_NAME"
    teamSecret: "$GREMLIN_TEAM_SECRET"
    existingSecret: ""
  teamID: "$GREMLIN_TEAM_ID"
  clusterID: "$CLUSTER_NAME"
  serviceAccount:
    create: true
    name: gremlin
    annotations: {}
  podSecurityContext:
    runAsUser: 0
    runAsGroup: 0
  securityContext:
    privileged: true
    capabilities:
      add: ["SYS_ADMIN", "NET_ADMIN", "SYS_PTRACE", "KILL", "MKNOD", "SYS_CHROOT", "AUDIT_CONTROL", "SETFCAP"]
  nodeSelector:
    kubernetes.io/os: linux
  tolerations:
    - key: "gremlin"
      operator: "Exists"
      effect: "NoSchedule"
  resources:
    limits:
      cpu: "1"
      memory: "512Mi"
    requests:
      cpu: "100m"
      memory: "128Mi"
  collectProcesses: true
  enableSystemMetrics: true
  enableContainerMetrics: true
  enableNetworkCapture: true
  enableFileSystem: true
  enableUserDefinedMetrics: true
  enableKubernetesDiscovery: true
  enableKubernetesEvents: true
  enableKubernetesState: true
  enableKubernetesLogs: true
  enableKubernetesPods: true
  enableKubernetesNodes: true
  enableKubernetesServices: true
  enableKubernetesDeployments: true
  enableKubernetesReplicaSets: true
  enableKubernetesDaemonSets: true
  enableKubernetesStatefulSets: true
  enableKubernetesJobs: true
  enableKubernetesCronJobs: true
  enableKubernetesConfigMaps: true
  enableKubernetesSecrets: true
  enableKubernetesIngresses: true
  enableKubernetesPersistentVolumes: true
  enableKubernetesStorageClasses: true
  enableKubernetesPersistentVolumeClaims: true
  enableKubernetesResourceQuotas: true
  enableKubernetesLimitRanges: true
  enableKubernetesHorizontalPodAutoscalers: true
  enableKubernetesPodDisruptionBudgets: true
  enableKubernetesNetworkPolicies: true
  enableKubernetesRoles: true
  enableKubernetesRoleBindings: true
  enableKubernetesServiceAccounts: true
  enableKubernetesClusterRoles: true
  enableKubernetesClusterRoleBindings: true
  enableKubernetesCustomResourceDefinitions: true
  enableKubernetesPriorityClasses: true
  enableKubernetesRuntimeClasses: true
  enableKubernetesPodSecurityPolicies: true
  enableKubernetesPodTemplates: true
  enableKubernetesReplicationControllers: true
  enableKubernetesControllerRevisions: true
  enableKubernetesVolumeAttachments: true
  enableKubernetesVolumeSnapshots: true
  enableKubernetesVolumeSnapshotClasses: true
  enableKubernetesVolumeSnapshotContents: true
  enableKubernetesCSIDrivers: true
  enableKubernetesCSINodes: true

  # New Relic integration
  newrelic:
    enabled: true
    licenseKey: "$NEW_RELIC_LICENSE_KEY"
    cluster: "$CLUSTER_NAME"
    lowDataMode: false
    kubeEvents:
      enabled: true
    prometheus:
      enabled: true
      serviceMonitor:
        enabled: true
    kubeStateMetrics:
      enabled: true
    kubelet:
      tlsSecret:
        name: newrelic-kubelet-tls
        create: true
EOF

# Install Gremlin
helm upgrade --install gremlin gremlin/gremlin \
  --namespace gremlin \
  -f gremlin-values.yaml \
  --wait \
  --timeout 5m0s

# Verify Gremlin installation
section "Verifying Gremlin Installation"
if kubectl get pods -n gremlin | grep -q 'Running'; then
  echo "✅ Gremlin is running"
  echo "Team ID: $GREMLIN_TEAM_ID"
  echo "Cluster ID: $CLUSTER_NAME"
  
  # Get ALB DNS for health checks
  ALB_DNS=$(kubectl get svc -n gremlin gremlin -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
  if [ -n "$ALB_DNS" ]; then
    echo "🔗 Gremlin Health Check Endpoint: http://$ALB_DNS/healthz"
    echo "   Test with: curl -I http://$ALB_DNS/healthz"
  fi
else
  echo "❌ Gremlin installation failed. Check logs with:"
  echo "   kubectl logs -n gremlin -l app=gremlin"
  exit 1
fi

# Verify New Relic installation
section "Verifying New Relic Installation"
if kubectl get pods -n newrelic | grep -q 'Running'; then
  echo "✅ New Relic is running"
  echo "📊 View your cluster in New Relic: https://one.newrelic.com/launcher/infra.launcher"
  echo "   Cluster Name: $CLUSTER_NAME"
else
  echo "⚠️  New Relic installation may have issues. Check logs with:"
  echo "   kubectl logs -n newrelic -l app.kubernetes.io/name=newrelic-bundle"
fi

# Install New Relic
section "Installing New Relic"
# TODO: Add New Relic installation commands here
# Example:
# helm repo add newrelic https://helm-charts.newrelic.com
# helm install newrelic-bundle newrelic/nri-bundle \
#   --set global.licenseKey=YOUR_NEW_RELIC_LICENSE_KEY \
#   --set global.cluster=$CLUSTER_NAME \
#   --namespace newrelic \
#   --create-namespace

echo "New Relic installation placeholder - Please add your New Relic installation commands"

# Install OTEL Demo (modified version without Prometheus/Grafana)
section "Installing OpenTelemetry Demo"
# Create a modified version of configure_otel_demo.sh that skips Prometheus/Grafana
if [ -f "./scripts/configure_otel_demo_modified.sh" ]; then
  # Use the modified version that skips Prometheus/Grafana
  ./scripts/configure_otel_demo_modified.sh
else
  echo "Warning: configure_otel_demo_modified.sh not found, using default"
  if [ -f "./configure_otel_demo.sh" ]; then
    ./configure_otel_demo.sh
  else
    echo "Error: configure_otel_demo.sh not found"
    exit 1
  fi
fi

# Final status
section "Installation Complete"
echo "Cluster Name: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo "Owner: $OWNER"
echo "Expiration: $EXPIRATION"
echo "Gremlin Team ID: $GREMLIN_TEAM_ID"
echo "Gremlin Cluster ID: $CLUSTER_NAME"

echo -e "\n=== Next Steps ==="
echo "1. Verify New Relic is receiving data"
echo "2. Access the OTEL demo application when ready"
echo "3. Log in to Gremlin UI to verify the cluster is connected"

exit 0
