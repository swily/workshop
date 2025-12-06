# Complete Gremlin Service Discovery Recipe

## Overview
This document provides the **exact, verified recipe** for complete Gremlin service auto-discovery in Kubernetes/EKS environments. This recipe is based on our working production setup and historical troubleshooting documented in `explanations/servicediscovery.md`.

---

## The Three Required Components

### 1. ✅ EC2ReadOnlyAccess IAM Policy
### 2. ✅ Complete Gremlin Annotations (Services + Deployments)  
### 3. ✅ Active Traffic (Load Generator)

---

## Component 1: EC2ReadOnlyAccess Policy

### What It Does
Allows Gremlin agents to collect AWS cloud metadata (instance tags, region, availability zone) which is **required** for service discovery to work, even though you're discovering Kubernetes services.

### Why It's Required
Gremlin's service discovery works in two layers:
1. **Kubernetes API** - Reads services/deployments via ClusterRole (RBAC)
2. **Cloud Metadata** - Correlates K8s objects with cloud infrastructure via EC2 API

Without EC2 permissions, Gremlin can see Kubernetes objects but cannot register them as services.

### Exact IAM Policy
```
arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess
```

This AWS-managed policy includes:
- `ec2:DescribeTags` - Required for AWS tag collection
- `ec2:DescribeInstances` - Required for instance metadata
- `ec2:DescribeRegions` - Required for region detection

### How to Apply (EKS)

**Step 1: Get your EKS node role name**
```bash
CLUSTER_NAME="your-cluster-name"
AWS_REGION="us-east-2"

NODE_ROLE_NAME=$(aws eks describe-nodegroup \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "$(aws eks list-nodegroups \
    --cluster-name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'nodegroups[0]' \
    --output text)" \
  --region "$AWS_REGION" \
  --query 'nodegroup.nodeRole' \
  --output text | awk -F'/' '{print $NF}')

echo "Node Role: $NODE_ROLE_NAME"
```

**Step 2: Attach the policy**
```bash
aws iam attach-role-policy \
  --role-name "$NODE_ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
```

**Step 3: Verify attachment**
```bash
aws iam list-attached-role-policies --role-name "$NODE_ROLE_NAME" | grep EC2ReadOnlyAccess
```

**Step 4: Restart Gremlin agents** (required to pick up new permissions)
```bash
kubectl rollout restart daemonset/gremlin -n gremlin
```

### Verification
Check agent logs for cloud metadata:
```bash
kubectl logs -n gremlin -l app=gremlin --tail=50 | grep -i "metadata set"
```

**Expected output:**
```
[INFO] gremlin_common::client - Metadata set for [ cloud: AWS ]
[INFO] gremlin_common::client - Metadata set for [ region: us-east-2 ]
```

**Error if missing:**
```
UnauthorizedOperation: You are not authorized to perform: ec2:DescribeTags
```

### Automated Implementation
Our setup automatically applies this in `lib/gremlin.sh`:
```bash
# Function: configure_eks_node_permissions()
# Lines: 161-186
```

---

## Component 2: Complete Gremlin Annotations

### What They Do
Tell Gremlin which Kubernetes resources to track as services and provide metadata for organization/filtering.

### Where to Apply
**BOTH** Services AND Deployments must be annotated:
- **Services** - Defines the service endpoint
- **Deployments** - Defines the workload and enables pod-level tracking

### Required Annotations

#### On Services:
```yaml
annotations:
  gremlin.com/service-id: "service-name"
  gremlin.com/service-type: "kubernetes"
  gremlin.com/tags: "environment:demo,app:otel-demo,category:frontend"
  gremlin.com/description: "OpenTelemetry Demo service-name service"
  gremlin.com/team-id: "your-team-id"  # Optional but recommended
```

#### On Deployments (Metadata):
```yaml
metadata:
  annotations:
    gremlin.com/service-id: "deployment-name"
    gremlin.com/service-type: "kubernetes"
    gremlin.com/tags: "environment:demo,app:otel-demo,category:frontend"
    gremlin.com/description: "OpenTelemetry Demo deployment-name deployment"
    gremlin.com/team-id: "your-team-id"  # Optional but recommended
```

#### On Deployments (Pod Template):
```yaml
spec:
  template:
    metadata:
      annotations:
        gremlin.com/service-id: "deployment-name"
        gremlin.com/service-type: "kubernetes"
        gremlin.com/tags: "environment:demo,app:otel-demo,category:frontend"
        gremlin.com/description: "OpenTelemetry Demo deployment-name deployment"
        gremlin.com/team-id: "your-team-id"  # Optional but recommended
```

### Annotation Breakdown

| Annotation | Required | Purpose | Example Value |
|------------|----------|---------|---------------|
| `gremlin.com/service-id` | **YES** | Unique identifier for the service | `opentelemetry-demo-frontend` |
| `gremlin.com/service-type` | **YES** | Type of service | `kubernetes` |
| `gremlin.com/tags` | **YES** | Comma-separated tags for filtering | `environment:demo,app:otel-demo,category:frontend` |
| `gremlin.com/description` | No | Human-readable description | `OpenTelemetry Demo frontend service` |
| `gremlin.com/team-id` | **Recommended** | Gremlin team ID for multi-team setups | `438c58ec-03db-47ac-8c58-ec03db67ac42` |

### How to Apply Annotations

**Option 1: Using kubectl annotate (existing resources)**
```bash
NAMESPACE="otel-demo"
SERVICE_NAME="opentelemetry-demo-frontend"
TEAM_ID="your-team-id"

# Annotate service
kubectl annotate service "$SERVICE_NAME" -n "$NAMESPACE" \
  "gremlin.com/service-id=$SERVICE_NAME" \
  "gremlin.com/service-type=kubernetes" \
  "gremlin.com/tags=environment:demo,app:otel-demo,category:frontend" \
  "gremlin.com/description=OpenTelemetry Demo ${SERVICE_NAME} service" \
  "gremlin.com/team-id=$TEAM_ID" \
  --overwrite

# Annotate deployment (metadata)
kubectl annotate deployment "$SERVICE_NAME" -n "$NAMESPACE" \
  "gremlin.com/service-id=$SERVICE_NAME" \
  "gremlin.com/service-type=kubernetes" \
  "gremlin.com/tags=environment:demo,app:otel-demo,category:frontend" \
  "gremlin.com/description=OpenTelemetry Demo ${SERVICE_NAME} deployment" \
  "gremlin.com/team-id=$TEAM_ID" \
  --overwrite

# Annotate deployment (pod template) - requires JSON patch
kubectl patch deployment "$SERVICE_NAME" -n "$NAMESPACE" --type=json -p='[
  {"op":"add","path":"/spec/template/metadata/annotations","value":{}},
  {"op":"add","path":"/spec/template/metadata/annotations/gremlin.com~1service-id","value":"'${SERVICE_NAME}'"},
  {"op":"add","path":"/spec/template/metadata/annotations/gremlin.com~1service-type","value":"kubernetes"},
  {"op":"add","path":"/spec/template/metadata/annotations/gremlin.com~1tags","value":"environment:demo,app:otel-demo,category:frontend"},
  {"op":"add","path":"/spec/template/metadata/annotations/gremlin.com~1team-id","value":"'${TEAM_ID}'"}
]'
```

**Option 2: Using our automated script**
```bash
./config/gremlin/gremlin_annotations.sh -t "your-team-id" otel-demo
```

This script:
- Annotates ALL services in the namespace
- Annotates ALL deployments (metadata + pod templates)
- Categorizes services automatically (frontend, shopping, payment, etc.)
- Configures Gremlin agent environment variables
- Restarts deployments to apply pod annotations

**Option 3: In Helm values.yaml (for new deployments)**
```yaml
# For each service
services:
  frontend:
    annotations:
      gremlin.com/service-id: "opentelemetry-demo-frontend"
      gremlin.com/service-type: "kubernetes"
      gremlin.com/tags: "environment:demo,app:otel-demo,category:frontend"
      gremlin.com/team-id: "your-team-id"

# For each deployment
deployments:
  frontend:
    metadata:
      annotations:
        gremlin.com/service-id: "opentelemetry-demo-frontend"
        gremlin.com/service-type: "kubernetes"
        gremlin.com/tags: "environment:demo,app:otel-demo,category:frontend"
        gremlin.com/team-id: "your-team-id"
    spec:
      template:
        metadata:
          annotations:
            gremlin.com/service-id: "opentelemetry-demo-frontend"
            gremlin.com/service-type: "kubernetes"
            gremlin.com/tags: "environment:demo,app:otel-demo,category:frontend"
            gremlin.com/team-id: "your-team-id"
```

### Verification
```bash
# Check service annotations
kubectl get service opentelemetry-demo-frontend -n otel-demo -o jsonpath='{.metadata.annotations}' | jq 'with_entries(select(.key | startswith("gremlin.com/")))'

# Check deployment annotations
kubectl get deployment opentelemetry-demo-frontend -n otel-demo -o jsonpath='{.metadata.annotations}' | jq 'with_entries(select(.key | startswith("gremlin.com/")))'

# Check pod template annotations
kubectl get deployment opentelemetry-demo-frontend -n otel-demo -o jsonpath='{.spec.template.metadata.annotations}' | jq 'with_entries(select(.key | startswith("gremlin.com/")))'
```

### Additional Gremlin Agent Configuration

The Gremlin agent also needs environment variables to enable service discovery:

```yaml
env:
  - name: GREMLIN_CONTAINER_LABELS
    value: "app.kubernetes.io/component,app.kubernetes.io/name,app.kubernetes.io/instance"
  - name: GREMLIN_CLIENT_TAGS
    value: "app.kubernetes.io/component,app.kubernetes.io/name,app.kubernetes.io/instance"
  - name: GREMLIN_COLLECT_DNS
    value: "true"
  - name: GREMLIN_COLLECT_PODS
    value: "true"
```

Apply to Gremlin DaemonSet:
```bash
kubectl patch daemonset gremlin -n gremlin --patch 'spec:
  template:
    spec:
      containers:
      - name: gremlin
        env:
        - name: GREMLIN_CONTAINER_LABELS
          value: "app.kubernetes.io/component,app.kubernetes.io/name,app.kubernetes.io/instance"
        - name: GREMLIN_CLIENT_TAGS
          value: "app.kubernetes.io/component,app.kubernetes.io/name,app.kubernetes.io/instance"
        - name: GREMLIN_COLLECT_DNS
          value: "true"
        - name: GREMLIN_COLLECT_PODS
          value: "true"'

kubectl rollout restart daemonset/gremlin -n gremlin
```

---

## Component 3: Active Traffic

### What It Does
Generates HTTP requests to services, which Gremlin uses to:
- Detect active services
- Map service dependencies
- Measure baseline performance
- Validate service health

### Why It's Required
Gremlin's service discovery is **traffic-based**. Services with no traffic may not be discovered or may be marked as inactive.

### Implementation

**Option 1: Locust Load Generator (OpenTelemetry Demo built-in)**
```bash
# Check if load generator is running
kubectl get deployment opentelemetry-demo-loadgenerator -n otel-demo

# Check load generator logs
kubectl logs -n otel-demo -l app.kubernetes.io/component=loadgenerator --tail=50

# Expected output: HTTP requests being sent
# GET /api/products
# GET /api/cart
# POST /api/checkout
```

**Option 2: Manual curl loop**
```bash
FRONTEND_URL="http://demo-frontend.your-domain.com"

while true; do
  curl -s "$FRONTEND_URL" > /dev/null
  curl -s "$FRONTEND_URL/api/products" > /dev/null
  curl -s "$FRONTEND_URL/api/cart" > /dev/null
  sleep 5
done
```

**Option 3: K6 load testing**
```bash
k6 run --vus 10 --duration 30m loadtest.js
```

### Verification
Check service metrics in Gremlin:
```bash
curl -H "Authorization: Key $GREMLIN_API_KEY" \
  "https://api.gremlin.com/v1/services?teamId=$GREMLIN_TEAM_ID" | jq '.[] | {name, active, lastSeen}'
```

---

## Complete Setup Checklist

### Prerequisites
- [ ] EKS cluster running
- [ ] Gremlin agent installed (`kubectl get daemonset -n gremlin`)
- [ ] Application deployed (`kubectl get pods -n otel-demo`)

### Step 1: IAM Permissions (5 minutes)
- [ ] Get EKS node role name
- [ ] Attach `AmazonEC2ReadOnlyAccess` policy
- [ ] Verify policy attachment
- [ ] Restart Gremlin agents
- [ ] Check agent logs for cloud metadata

### Step 2: Annotations (10 minutes)
- [ ] Run annotation script: `./config/gremlin/gremlin_annotations.sh -t "your-team-id" otel-demo`
- [ ] Verify service annotations
- [ ] Verify deployment annotations
- [ ] Verify pod template annotations
- [ ] Configure Gremlin agent environment variables
- [ ] Restart Gremlin agents

### Step 3: Traffic Generation (2 minutes)
- [ ] Verify load generator is running
- [ ] Check load generator logs
- [ ] Confirm HTTP requests are being sent

### Step 4: Verification (5 minutes)
- [ ] Wait 2-5 minutes for discovery
- [ ] Check Gremlin UI: https://app.gremlin.com/reliability/status-checks
- [ ] Verify services via API:
```bash
curl -H "Authorization: Key $GREMLIN_API_KEY" \
  "https://api.gremlin.com/v1/services?teamId=$GREMLIN_TEAM_ID" | jq 'length'
```
- [ ] Expected: 20+ services discovered

---

## Troubleshooting

### No Services Discovered

**Check 1: EC2 Permissions**
```bash
kubectl logs -n gremlin -l app=gremlin --tail=100 | grep -i "unauthorized\|ec2"
```
If you see `UnauthorizedOperation: ec2:DescribeTags`, the IAM policy is missing.

**Check 2: Annotations**
```bash
kubectl get services -n otel-demo -o json | jq '.items[] | select(.metadata.annotations["gremlin.com/service-id"] != null) | .metadata.name'
```
Should return list of annotated services.

**Check 3: Traffic**
```bash
kubectl logs -n otel-demo -l app.kubernetes.io/component=loadgenerator --tail=20
```
Should show HTTP requests being sent.

**Check 4: Agent Configuration**
```bash
kubectl get daemonset gremlin -n gremlin -o yaml | grep -A 10 "env:"
```
Should include `GREMLIN_COLLECT_PODS: "true"` and `GREMLIN_COLLECT_DNS: "true"`.

### Services Discovered But Inactive

**Cause**: No recent traffic
**Solution**: Ensure load generator is running continuously

### Only Some Services Discovered

**Cause**: Missing annotations on some services/deployments
**Solution**: Re-run annotation script or manually annotate missing resources

---

## Timeline for Discovery

Based on our production experience:

| Event | Time |
|-------|------|
| IAM policy attached | T+0 |
| Gremlin agents restarted | T+0 |
| Cloud metadata collected | T+30s |
| Services annotated | T+1m |
| Traffic starts flowing | T+2m |
| **Services discovered** | **T+3-5m** |

**Total time from zero to full discovery: ~5 minutes**

---

## Files Reference

### Automated Scripts
- `config/gremlin/gremlin_annotations.sh` - Complete annotation automation
- `lib/gremlin.sh` - IAM policy attachment (function: `configure_eks_node_permissions`)

### Documentation
- `explanations/servicediscovery.md` - Historical troubleshooting and root cause analysis
- `GREMLIN_SERVICE_DISCOVERY_RECIPE.md` - This document

### RBAC Resources
- ClusterRole: `gremlin-service-discovery` (created automatically by annotation script)
- ClusterRoleBinding: `gremlin-service-discovery` → `gremlin:chao` service account

---

## Success Metrics

When everything is working correctly:

✅ **Gremlin Agent Logs:**
```
[INFO] Metadata set for [ cloud: AWS ]
[INFO] Metadata set for [ region: us-east-2 ]
[INFO] Service discovery enabled
```

✅ **Gremlin API Response:**
```json
{
  "services": [
    {
      "name": "opentelemetry-demo-frontend",
      "active": true,
      "lastSeen": "2025-10-23T16:30:00Z",
      "tags": ["environment:demo", "app:otel-demo", "category:frontend"]
    }
  ]
}
```

✅ **Gremlin UI:**
- 20+ services visible in Status Checks
- All services marked as "Active"
- Service dependencies mapped correctly

---

## Additional Notes

### Why Both Services AND Deployments?
- **Services** define the network endpoint (how traffic reaches the service)
- **Deployments** define the workload (the pods that handle the traffic)
- Gremlin needs both to:
  - Map traffic flows (services)
  - Target specific pods for attacks (deployments)
  - Understand service topology

### Why Pod Template Annotations?
Pod template annotations ensure that:
- New pods created by scaling/rolling updates have annotations
- Gremlin can track individual pod instances
- Service discovery persists across pod restarts

### Team ID Best Practices
- **Required for multi-team setups** - Isolates services per team
- **Optional for single-team** - But recommended for organization
- **Format**: UUID from Gremlin team settings
- **Example**: `438c58ec-03db-47ac-8c58-ec03db67ac42`

---

## Summary

The complete recipe for Gremlin service discovery:

1. **EC2ReadOnlyAccess IAM policy** on EKS node role
2. **Complete annotations** on services + deployments (metadata + pod templates)
3. **Active traffic** via load generator

All three components are **required**. Missing any one will prevent service discovery from working.

Our automated setup handles all of this via:
```bash
# One command to rule them all
./workshop.sh --action deploy_existing --cluster-name your-cluster --enable-gremlin
```

This applies IAM permissions, installs Gremlin, annotates all services, and verifies discovery.
