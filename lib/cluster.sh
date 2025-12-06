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

# NOTE: create_cluster() removed - Terraform handles EKS cluster creation
# Use terraform apply in fictional-computing-machine modules instead

# NOTE: cleanup_cloudformation_stacks() removed - Not needed with Terraform
# Terraform manages its own state and cleanup

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
    
    # Install AWS Load Balancer Controller (without problematic webhooks)
    install_aws_load_balancer_controller "$cluster_name"
    
    # Fix Gremlin EC2 permissions
    # This allows Gremlin agent to discover EC2 instances for service mapping
    if command -v fix_gremlin_ec2_permissions &>/dev/null; then
        fix_gremlin_ec2_permissions "$cluster_name" "$AWS_REGION" || {
            log_warning "EC2 permissions fix failed, continuing anyway..."
        }
    fi
    
    # Install Istio if explicitly requested via flag
    if [ "$install_istio" = "true" ]; then
        log_info "Installing Istio (optional service mesh)"
        install_istio
    else
        log_info "Skipping Istio installation (use --install-istio flag to enable)"
    fi
    
    # Create monitoring namespace
    ensure_namespace "monitoring"
    
    # Install monitoring base components based on selected platform
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
        "datadog")
            log_info "Datadog will be configured during monitoring setup"
            ;;
        "appdynamics")
            log_info "AppDynamics will be configured during monitoring setup"
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
    
    # Create IAM service account with cluster-specific role name to avoid conflicts
    local role_name="AmazonEKSLoadBalancerControllerRole-${cluster_name}"
    eksctl create iamserviceaccount \
        --cluster="$cluster_name" \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --role-name "$role_name" \
        --attach-policy-arn=arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy \
        --approve \
        --region="$AWS_REGION" 2>/dev/null || log_info "Service account already exists"
    
    # Add EKS Helm repository
    ensure_helm_repo "eks" "https://aws.github.io/eks-charts"
    
    # Get VPC ID for the cluster (required for Fargate/non-EC2 nodes)
    local vpc_id=$(aws eks describe-cluster --name "$cluster_name" --region "$AWS_REGION" --query 'cluster.resourcesVpcConfig.vpcId' --output text)
    log_info "Cluster VPC ID: $vpc_id"
    
    # Install AWS Load Balancer Controller (without webhooks to avoid blocking issues)
    helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName="$cluster_name" \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller \
        --set vpcId="$vpc_id" \
        --set enableWebhooks=false
    
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
    
    # NOTE: CloudFormation and IAM cleanup removed - Terraform handles this
    # Use terraform destroy to clean up all infrastructure
    
    log_success "Cluster '$cluster_name' deleted successfully"
}

# NOTE: cleanup_iam_resources() removed - Terraform manages IAM resources
# Use terraform destroy to clean up IAM roles and policies

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
