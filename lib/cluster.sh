#!/bin/bash
#
# Cluster operations for workshop scripts
# Handles EKS cluster creation, configuration, and management
#

# Source common functions if not already loaded
if [[ -z "$RED" ]]; then
    LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$LIB_DIR/common.sh"
fi

# Function to create new EKS cluster
create_cluster() {
    local cluster_name="$1"
    local region="$2"
    local node_type="${3:-m5.large}"
    local node_count="${4:-3}"
    
    log_section "Creating EKS Cluster: $cluster_name"
    
    # Check if cluster already exists
    if aws eks describe-cluster --region "$region" --name "$cluster_name" >/dev/null 2>&1; then
        log_warning "Cluster '$cluster_name' already exists in region '$region'"
        if ! confirm_action "Do you want to use the existing cluster?"; then
            log_error "Cluster creation cancelled"
            return 1
        fi
        log_info "Using existing cluster: $cluster_name"
        return 0
    fi
    
    log_info "Creating EKS cluster with the following configuration:"
    echo "  Name: $cluster_name"
    echo "  Region: $region"
    echo "  Node Type: $node_type"
    echo "  Node Count: $node_count"
    echo ""
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would create EKS cluster: $cluster_name"
        return 0
    fi
    
    # Create cluster using eksctl
    local eksctl_cmd="eksctl create cluster \
        --name $cluster_name \
        --region $region \
        --nodegroup-name standard-workers \
        --node-type $node_type \
        --nodes $node_count \
        --nodes-min 1 \
        --nodes-max 10 \
        --managed \
        --with-oidc \
        --ssh-access \
        --ssh-public-key ~/.ssh/id_rsa.pub \
        --full-ecr-access"
    
    log_info "Executing: $eksctl_cmd"
    
    if eval "$eksctl_cmd"; then
        log_success "EKS cluster '$cluster_name' created successfully"
        
        # Update kubeconfig
        update_kubeconfig "$cluster_name" "$region"
        
        # Verify cluster is ready
        wait_for_cluster_ready "$cluster_name" "$region"
        
        return 0
    else
        log_error "Failed to create EKS cluster: $cluster_name"
        return 1
    fi
}

# Function to cleanup CloudFormation stacks associated with the cluster
cleanup_cloudformation_stacks() {
    local cluster_name="$1"
    local region="$2"
    
    log_info "Checking CloudFormation stacks for cluster: $cluster_name"
    
    # Identify likely stacks (eksctl naming convention)
    local stacks=$(aws cloudformation list-stacks \
        --region "$region" \
        --query "StackSummaries[?contains(StackName, 'eksctl-${cluster_name}') && (StackStatus=='DELETE_FAILED' || StackStatus=='CREATE_COMPLETE' || StackStatus=='ROLLBACK_COMPLETE')].StackName" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$stacks" ]; then
        log_info "No matching CloudFormation stacks found for cluster: $cluster_name"
        return 0
    fi
    
    log_info "Found CloudFormation stacks to delete: $stacks"
    for s in $stacks; do
        log_info "Deleting CloudFormation stack: $s"
        aws cloudformation delete-stack --region "$region" --stack-name "$s" || log_warning "Failed to initiate delete for stack: $s"
    done
    
    # Wait for deletion attempts (best-effort)
    for s in $stacks; do
        log_info "Waiting for stack deletion: $s"
        aws cloudformation wait stack-delete-complete --region "$region" --stack-name "$s" 2>/dev/null || log_warning "Stack did not reach delete-complete: $s"
    done
    
    log_success "CloudFormation cleanup pass completed"
}

# Function to wait for cluster to be ready
wait_for_cluster_ready() {
    local cluster_name="$1"
    local region="$2"
    local timeout="${3:-1800}" # 30 minutes default
    local interval="${4:-30}"   # 30 seconds default
    
    log_info "Waiting for cluster to be ready..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local status=$(get_cluster_status "$cluster_name" "$region")
        
        if [ "$status" = "ACTIVE" ]; then
            log_success "Cluster is ready and active"
            return 0
        fi
        
        log_info "Cluster status: $status (waiting...)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "Timeout waiting for cluster to be ready"
    return 1
}

# Function to configure cluster base components
configure_cluster_base() {
    local cluster_name="$1"
    local install_istio="${2:-false}"
    local monitoring_type="${3:-grafana}"
    
    log_section "Configuring Cluster Base Components"
    
    # Ensure we're connected to the right cluster
    update_kubeconfig "$cluster_name" "$AWS_REGION"
    
    # Install AWS Load Balancer Controller
    install_aws_load_balancer_controller "$cluster_name"
    
    # Install Istio if requested
    if [ "$install_istio" = "true" ]; then
        install_istio
    fi
    
    # Create monitoring namespace
    ensure_namespace "monitoring"
    
    # Install monitoring base components
    case "$monitoring_type" in
        "grafana"|"prometheus")
            install_prometheus_operator
            ;;
        "dynatrace")
            log_info "Dynatrace will be configured during monitoring setup"
            ;;
        "newrelic")
            log_info "New Relic will be configured during monitoring setup"
            ;;
        *)
            log_info "Skipping monitoring base installation for: $monitoring_type"
            ;;
    esac
    
    log_success "Cluster base configuration completed"
}

# Function to install AWS Load Balancer Controller
install_aws_load_balancer_controller() {
    local cluster_name="$1"
    
    log_info "Installing AWS Load Balancer Controller..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would install AWS Load Balancer Controller"
        return 0
    fi
    
    # Create IAM OIDC identity provider
    eksctl utils associate-iam-oidc-provider --region="$AWS_REGION" --cluster="$cluster_name" --approve
    
    # Download IAM policy
    curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.4/docs/install/iam_policy.json
    
    # Create IAM policy
    aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy \
        --policy-document file://iam_policy.json \
        --region "$AWS_REGION" 2>/dev/null || log_info "IAM policy already exists"
    
    # Create IAM service account
    eksctl create iamserviceaccount \
        --cluster="$cluster_name" \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --role-name "AmazonEKSLoadBalancerControllerRole" \
        --attach-policy-arn=arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy \
        --approve \
        --region="$AWS_REGION" 2>/dev/null || log_info "Service account already exists"
    
    # Add EKS Helm repository
    ensure_helm_repo "eks" "https://aws.github.io/eks-charts"
    
    # Install AWS Load Balancer Controller
    helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName="$cluster_name" \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller
    
    # Wait for deployment to be ready
    wait_for_pods "kube-system" "app.kubernetes.io/name=aws-load-balancer-controller"
    
    # Cleanup
    rm -f iam_policy.json
    
    log_success "AWS Load Balancer Controller installed successfully"
}

# Function to install Istio
install_istio() {
    log_info "Installing Istio service mesh..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would install Istio"
        return 0
    fi
    
    # Check if istioctl is available
    if ! command_exists istioctl; then
        log_error "istioctl not found. Please install Istio CLI first."
        return 1
    fi
    
    # Install Istio with demo profile
    istioctl install --set values.defaultRevision=default -y
    
    # Enable Istio injection for default namespace
    kubectl label namespace default istio-injection=enabled --overwrite
    
    # Install Istio addons (Kiali, Jaeger, Grafana)
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/kiali.yaml
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/jaeger.yaml
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/grafana.yaml
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/prometheus.yaml
    
    # Wait for Istio components to be ready
    wait_for_pods "istio-system" "app=istiod"
    
    log_success "Istio installed successfully"
}

# Function to install Prometheus Operator
install_prometheus_operator() {
    log_info "Installing Prometheus Operator..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would install Prometheus Operator"
        return 0
    fi
    
    # Add Prometheus community Helm repository
    ensure_helm_repo "prometheus-community" "https://prometheus-community.github.io/helm-charts"
    
    # Install kube-prometheus-stack
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.retention=30d \
        --set grafana.adminPassword=${GRAFANA_ADMIN_PASSWORD:-admin123} \
        --set grafana.persistence.enabled=false
    
    # Wait for Prometheus and Grafana to be ready
    wait_for_pods "monitoring" "app.kubernetes.io/name=prometheus"
    wait_for_pods "monitoring" "app.kubernetes.io/name=grafana"
    
    log_success "Prometheus Operator installed successfully"
}

# Function to cleanup cluster
cleanup_cluster() {
    local cluster_name="$1"
    local region="$2"
    local force="${3:-false}"
    
    log_section "Cleaning up Cluster: $cluster_name"
    
    # Confirm deletion unless forced
    if [ "$force" != "true" ]; then
        log_warning "This will permanently delete the cluster and all its resources!"
        if ! confirm_action "Are you sure you want to delete cluster '$cluster_name'?"; then
            log_info "Cluster deletion cancelled"
            return 0
        fi
    fi
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would delete cluster: $cluster_name"
        return 0
    fi
    
    # Delete Load Balancers first to avoid hanging resources
    log_info "Cleaning up Load Balancers..."
    # Delete all ingresses across namespaces
    kubectl get ingress -A -o name 2>/dev/null | xargs -r kubectl delete --ignore-not-found=true || true
    
    # Delete all Services of type LoadBalancer across namespaces
    while IFS= read -r line; do
        ns=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{print $2}')
        kubectl delete svc -n "$ns" "$name" --ignore-not-found=true || true
    done < <(kubectl get svc -A --field-selector spec.type=LoadBalancer -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null)
    
    # Wait for Load Balancers to be deleted
    sleep 30
    
    # Delete the cluster
    log_info "Deleting EKS cluster: $cluster_name"
    if ! eksctl delete cluster --name "$cluster_name" --region "$region" --wait; then
        log_warning "eksctl cluster delete reported an error; proceeding with CloudFormation cleanup"
    fi
    
    # Attempt CloudFormation stack cleanup (handles stuck deletions)
    cleanup_cloudformation_stacks "$cluster_name" "$region"

    # Clean up IAM roles and policies
    cleanup_iam_resources "$cluster_name"
    
    log_success "Cluster '$cluster_name' deleted successfully"
}

# Function to cleanup IAM resources
cleanup_iam_resources() {
    local cluster_name="$1"
    
    log_info "Cleaning up IAM resources..."
    
    # Delete service account IAM role
    aws iam detach-role-policy \
        --role-name "AmazonEKSLoadBalancerControllerRole" \
        --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy" \
        2>/dev/null || true
    
    aws iam delete-role \
        --role-name "AmazonEKSLoadBalancerControllerRole" \
        2>/dev/null || true
    
    # Note: We don't delete the IAM policy as it might be used by other clusters
    
    log_info "IAM cleanup completed"
}

# Function to get cluster nodes info
get_cluster_nodes() {
    local cluster_name="$1"
    
    log_info "Cluster nodes for '$cluster_name':"
    kubectl get nodes -o wide
}

# Function to get cluster services
get_cluster_services() {
    local namespace="${1:-all}"
    
    if [ "$namespace" = "all" ]; then
        log_info "All cluster services:"
        kubectl get services --all-namespaces
    else
        log_info "Services in namespace '$namespace':"
        kubectl get services -n "$namespace"
    fi
}

# Function to get cluster ingresses
get_cluster_ingresses() {
    local namespace="${1:-all}"
    
    if [ "$namespace" = "all" ]; then
        log_info "All cluster ingresses:"
        kubectl get ingress --all-namespaces
    else
        log_info "Ingresses in namespace '$namespace':"
        kubectl get ingress -n "$namespace"
    fi
}

# Function to scale cluster nodes
scale_cluster_nodes() {
    local cluster_name="$1"
    local nodegroup_name="${2:-standard-workers}"
    local desired_capacity="$3"
    local min_capacity="${4:-1}"
    local max_capacity="${5:-10}"
    
    log_info "Scaling cluster '$cluster_name' nodegroup '$nodegroup_name' to $desired_capacity nodes"
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would scale nodegroup to $desired_capacity nodes"
        return 0
    fi
    
    eksctl scale nodegroup \
        --cluster="$cluster_name" \
        --name="$nodegroup_name" \
        --nodes="$desired_capacity" \
        --nodes-min="$min_capacity" \
        --nodes-max="$max_capacity" \
        --region="$AWS_REGION"
    
    log_success "Nodegroup scaled successfully"
}

# Function to upgrade cluster
upgrade_cluster() {
    local cluster_name="$1"
    local target_version="$2"
    
    log_info "Upgrading cluster '$cluster_name' to version $target_version"
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would upgrade cluster to version $target_version"
        return 0
    fi
    
    # Upgrade control plane
    eksctl upgrade cluster --name="$cluster_name" --version="$target_version" --region="$AWS_REGION" --approve
    
    # Upgrade node groups
    eksctl upgrade nodegroup --cluster="$cluster_name" --name="standard-workers" --region="$AWS_REGION"
    
    log_success "Cluster upgrade completed"
}
