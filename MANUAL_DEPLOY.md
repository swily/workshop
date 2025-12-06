# Manual Workshop Deployment Guide

This guide provides a **simple, step-by-step** manual deployment that avoids the automation issues in workshop.sh.

## Prerequisites (Already Complete)

✅ AWS CLI configured for account `501454956990`  
✅ Gremlin credentials in Secrets Manager (`sean.wiley/gremlin_*`)  
✅ fictional-computing-machine repo at `/Users/seanwiley/gremform/fictional-computing-machine`  
✅ Terraform backend created (`gremlin-tf-state-sean-wiley-us-east-2`)

## Step 1: Deploy Infrastructure with Terraform

```bash
cd /Users/seanwiley/terraform/workspace/seanw

# Remove stale plan if it exists
rm -f tfplan

# Run terraform apply directly (no separate plan)
terraform apply -auto-approve
```

**Expected time:** 15-20 minutes  
**What gets created:**
- EKS cluster `seanw-eks`
- ALB with wildcard cert for `*.seanw.gremlinpoc.com`
- Route53 DNS records
- IAM roles and policies

**Wait for this to complete before proceeding.**

## Step 2: Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig --name seanw-eks --region us-east-2

# Verify connection
kubectl get nodes
```

You should see nodes in `Ready` state.

## Step 3: Install AWS Load Balancer Controller

```bash
cd /Users/seanwiley/workshop

# This is required for ALB ingress to work
./scripts/operations/cluster_create.sh --cluster-name seanw-eks --skip-cluster-creation
```

Or manually:

```bash
# Create IAM policy for ALB controller
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.4/docs/install/iam_policy.json

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam-policy.json

# Create service account
eksctl create iamserviceaccount \
  --cluster=seanw-eks \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::501454956990:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

# Install controller via Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=seanw-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

## Step 4: Deploy OpenTelemetry Demo

```bash
cd /Users/seanwiley/workshop

# Deploy OTel Demo
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

kubectl create namespace otel-demo --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install opentelemetry-demo open-telemetry/opentelemetry-demo \
  --namespace otel-demo \
  --set default.enabled=true \
  --wait
```

**Expected time:** 5-10 minutes

## Step 5: Install Prometheus + Grafana

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin \
  --wait
```

## Step 6: Install Gremlin Agent

```bash
# Fetch credentials from Secrets Manager
export GREMLIN_TEAM_ID=$(aws secretsmanager get-secret-value \
  --secret-id sean.wiley/gremlin_team_id \
  --region us-east-2 \
  --query SecretString --output text)

export GREMLIN_TEAM_CERTIFICATE=$(aws secretsmanager get-secret-value \
  --secret-id sean.wiley/gremlin_team_certificate \
  --region us-east-2 \
  --query SecretString --output text)

export GREMLIN_TEAM_PRIVATE_KEY=$(aws secretsmanager get-secret-value \
  --secret-id sean.wiley/gremlin_team_private_key \
  --region us-east-2 \
  --query SecretString --output text)

# Install Gremlin
kubectl create namespace gremlin --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic gremlin-team-cert \
  --namespace gremlin \
  --from-literal=GREMLIN_TEAM_ID="$GREMLIN_TEAM_ID" \
  --from-literal=GREMLIN_TEAM_CERTIFICATE="$GREMLIN_TEAM_CERTIFICATE" \
  --from-literal=GREMLIN_TEAM_PRIVATE_KEY="$GREMLIN_TEAM_PRIVATE_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

helm repo add gremlin https://helm.gremlin.com
helm repo update

helm upgrade --install gremlin gremlin/gremlin \
  --namespace gremlin \
  --set gremlin.secret.managed=true \
  --set gremlin.secret.type=certificate \
  --set gremlin.secret.teamID="$GREMLIN_TEAM_ID" \
  --set gremlin.secret.certificate="$GREMLIN_TEAM_CERTIFICATE" \
  --set gremlin.secret.key="$GREMLIN_TEAM_PRIVATE_KEY" \
  --wait
```

## Step 7: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -A

# Get ALB DNS name
kubectl get ingress -A

# Check Gremlin agents
kubectl get pods -n gremlin
```

## Step 8: Access URLs

Get the ALB DNS name from Terraform outputs:

```bash
cd /Users/seanwiley/terraform/workspace/seanw
terraform output alb_dns_name
```

Then access:
- Frontend: `https://demo-frontend.seanw.gremlinpoc.com`
- Grafana: `https://monitoring.seanw.gremlinpoc.com`

## Troubleshooting

### If Terraform apply fails

```bash
cd /Users/seanwiley/terraform/workspace/seanw

# Check what's in state
terraform state list

# If VPC exists but apply failed, try targeted apply
terraform apply -target=module.demo.module.eks -auto-approve
```

### If pods won't start

```bash
# Check events
kubectl get events -A --sort-by='.lastTimestamp'

# Check specific pod
kubectl describe pod <pod-name> -n <namespace>
```

### If DNS doesn't resolve

Wait 5-10 minutes for Route53 propagation, then:

```bash
dig demo-frontend.seanw.gremlinpoc.com
```

## Cleanup

```bash
# Delete Kubernetes resources first
kubectl delete namespace otel-demo monitoring gremlin

# Wait for load balancers to be deleted (2-3 minutes)
sleep 180

# Destroy infrastructure
cd /Users/seanwiley/terraform/workspace/seanw
terraform destroy -auto-approve
```
