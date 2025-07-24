#!/bin/bash
set -e

# Configuration
CLUSTER_NAME="gremlin-workshop"
AWS_REGION="us-east-2"
TEAM_ID="7a5d7d09-c3de-4d6b-9d7d-09c3de7d6b5d"
TEAM_SECRET="f627ca78-c489-4d72-a7ca-78c4894d72b5"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print section headers
section() {
  echo -e "\n${YELLOW}==> $1${NC}"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check for required tools
check_requirements() {
  section "Checking for required tools"
  local missing=0
  
  for tool in aws eksctl kubectl helm; do
    if ! command_exists "$tool"; then
      echo "❌ Error: $tool is required but not installed"
      missing=$((missing + 1))
    else
      echo "✅ $tool is installed"
    fi
  done
  
  if [ $missing -gt 0 ]; then
    echo -e "\nPlease install the missing tools and try again."
    exit 1
  fi
}

# Create EKS cluster
create_cluster() {
  section "Creating EKS cluster: ${CLUSTER_NAME}"
  
  if eksctl get cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --output json | jq -e '.[].Status == "ACTIVE"' >/dev/null 2>&1; then
    echo "Cluster ${CLUSTER_NAME} already exists. Skipping creation."
    return 0
  fi
  
  # Create cluster with VPC and subnet configuration
  cat <<EOF | eksctl create cluster -f -
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  version: "1.28"
  tags:
    owner: $(whoami)
    Environment: Workshop
    Purpose: GremlinWorkshop

vpc:
  id: vpc-0ae237bb717910ccc
  subnets:
    private:
      us-east-2a:
        id: subnet-0403fbdc0a75620d6
      us-east-2b:
        id: subnet-0dcb40d6b8fad2c03
      us-east-2c:
        id: subnet-0d36418b808d97976
    public:
      us-east-2a:
        id: subnet-08038efe886c31791
      us-east-2b:
        id: subnet-0135b61262e48f4d6
      us-east-2c:
        id: subnet-0fe7be30ec2528c4c

iam:
  serviceRoleARN: arn:aws:iam::856940208208:role/DemosVPC-EksServiceRole
  withOIDC: true

managedNodeGroups:
  - name: ${CLUSTER_NAME}-ng
    instanceTypes: ["t3.medium", "t3a.medium", "t2.medium"]
    minSize: 3
    maxSize: 6
    desiredCapacity: 3
    volumeSize: 50
    iam:
      instanceRoleARN: arn:aws:iam::856940208208:role/DemosVPC-EksNodeInstanceRole
    securityGroups:
      attachIDs:
        - sg-0a499ed85cbdf45c5
    labels:
      role: worker
    tags:
      NodeGroupType: GremlinWorkshop
      owner: $(whoami)

# Add IAM user mappings for access
iamIdentityMappings:
  - arn: arn:aws:iam::856940208208:user/sean.wiley
    username: sean.wiley
    groups:
      - system:masters
EOF

  # Update kubeconfig
  aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
}

# Install Gremlin
install_gremlin() {
  section "Installing Gremlin"
  
  # Create namespace if it doesn't exist
  if ! kubectl get namespace gremlin &>/dev/null; then
    echo "Creating gremlin namespace..."
    kubectl create namespace gremlin
  fi
  
  # Create Gremlin RBAC resources
  echo "Creating Gremlin RBAC resources..."
  cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: gremlin-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "endpoints", "nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "daemonsets", "statefulsets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["extensions"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gremlin-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: gremlin-role
subjects:
- kind: ServiceAccount
  name: gremlin
  namespace: gremlin
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gremlin
  namespace: gremlin
  labels:
    app: gremlin
    app.kubernetes.io/name: gremlin
EOF

  # Install Gremlin with proper security context and node affinity
  echo "Installing Gremlin using Helm..."
  
  # First, add the Gremlin repo if not already added
  if ! helm repo list | grep -q gremlin; then
    helm repo add gremlin https://helm.gremlin.com
    helm repo update
  fi
  
  # Create a values file for Gremlin
  cat > gremlin-values.yaml <<EOF
gremlin:
  hostPID: true
  hostNetwork: true
  container:
    driver: containerd-linux
  secret:
    create: true
    managed: true
    type: secret
    name: gremlin-secret
    teamID: ${TEAM_ID}
    clusterID: ${CLUSTER_NAME}
    teamSecret: ${TEAM_SECRET}
    existingSecret: ""
  teamID: ${TEAM_ID}
  clusterID: ${CLUSTER_NAME}
  serviceAccount:
    create: false
    name: gremlin
  podSecurityContext:
    runAsUser: 0
    runAsGroup: 0
  securityContext:
    privileged: true
    capabilities:
      add: [KILL, SYS_BOOT, SYS_TIME, NET_ADMIN, NET_RAW, SYS_PTRACE, SYS_CHROOT, MKNOD, AUDIT_WRITE, SETFCAP]
  nodeSelector:
    role: worker
  tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
  collect:
    processes: true
    containerLabels: true
    kubernetes: true
    network: true
    filesystem: true
    kubernetesPods: true
    kubernetesNodes: true
    kubernetesServices: true
    kubernetesDeployments: true
    kubernetesDaemonsets: true
    kubernetesStatefulsets: true
    kubernetesReplicasets: true
    kubernetesJobs: true
    kubernetesCronjobs: true
    kubernetesNamespaces: true
    kubernetesIngresses: true
    kubernetesConfigmaps: true
    kubernetesSecrets: true
    kubernetesServiceaccounts: true
    kubernetesRoles: true
    kubernetesRolebindings: true
    kubernetesClusterroles: true
    kubernetesClusterrolebindings: true
    kubernetesStorageclasses: true
    kubernetesPersistentvolumes: true
    kubernetesPersistentvolumeclaims: true
EOF

  # Install using the values file
  helm upgrade --install gremlin gremlin/gremlin \
    --namespace gremlin \
    --version 0.24.0 \
    -f gremlin-values.yaml
    
  # Wait for Gremlin pods to be ready
  echo -e "\nWaiting for Gremlin pods to be ready..."
  kubectl wait --namespace gremlin \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=gremlin \
    --timeout=300s
}

# Verify installation
verify_installation() {
  section "Verifying Gremlin Installation"
  
  echo "Gremlin pods:"
  kubectl get pods -n gremlin
  
  echo -e "\nGremlin daemonset status:"
  kubectl get daemonset -n gremlin
  
  echo -e "\nGremlin service status:"
  kubectl get svc -n gremlin
  
  echo -e "\n${GREEN}Gremlin installation completed successfully!${NC}"
  echo -e "To access the Gremlin web UI, run:"
  echo "kubectl port-forward -n gremlin svc/gremlin 8080:80 &"
  echo -e "Then open ${GREEN}http://localhost:8080${NC} in your browser"
}

# Cleanup function
cleanup() {
  echo -e "\n${YELLOW}Cleaning up...${NC}"
  # Add any cleanup tasks here if needed
}

# Main execution
trap cleanup EXIT

section "Starting Gremlin Workshop Installation"
check_requirements
create_cluster
install_gremlin
verify_installation

echo -e "\n${GREEN}✅ Gremlin Workshop setup completed successfully!${NC}"
echo -e "Cluster Name: ${CLUSTER_NAME}"
echo -e "Region: ${AWS_REGION}"
echo -e "Team ID: ${TEAM_ID}"

exit 0
