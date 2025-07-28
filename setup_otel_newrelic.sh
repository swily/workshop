#!/bin/bash -e

# Configuration
CLUSTER_NAME="seanwiley-otel"
OWNER="seanwiley"
AWS_REGION="us-east-2"
EXPIRATION=$(date -v +30d +%Y-%m-%d)

# Gremlin Credentials
GREMLIN_TEAM_ID="879f455b-4655-4712-9f45-5b4655971232"
GREMLIN_TEAM_SECRET="90db3562-3de0-4246-9b35-623de0624615"

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
if [ -f "./clean_cluster.sh" ]; then
  ./clean_cluster.sh
else
  echo "clean_cluster.sh not found, skipping cleanup"
fi

# Create new cluster
section "Creating new EKS cluster"
if [ -f "./build_cluster.sh" ]; then
  ./build_cluster.sh
else
  echo "build_cluster.sh not found, please ensure it exists"
  exit 1
fi

# Wait for cluster to be ready
section "Waiting for cluster to stabilize"
sleep 300

# Install base components (ALB Controller only)
section "Installing base components"
if [ -f "./configure_cluster_base.sh" ]; then
  ./configure_cluster_base.sh
else
  echo "configure_cluster_base.sh not found, please ensure it exists"
  exit 1
fi

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
  echo "Installing AWS Load Balancer Controller..."
  
  # Create IAM policy for ALB controller
  curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.7/docs/install/iam_policy.json
  aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam-policy.json
  
  # Create IAM role and service account
  eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
    --override-existing-serviceaccounts \
    --approve
  
  # Install ALB controller
  helm repo add eks https://aws.github.io/eks-charts
  helm repo update
  
  helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=$CLUSTER_NAME \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --wait
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
