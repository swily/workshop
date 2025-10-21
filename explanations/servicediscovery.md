# Gremlin Service Discovery Analysis

## Problem Summary

Gremlin agents were not discovering Kubernetes services despite proper installation, annotations, and traffic flow. After extensive troubleshooting, the root cause was identified as missing AWS EC2 permissions on the EKS node role.

## Root Cause Analysis

### Timeline of Discovery
- **Before Fix**: Only 1 service (`recommendation` from `test-cluster`) visible in Gremlin API
- **EC2ReadOnlyAccess Policy Applied**: ~21:52 UTC on 2025-09-11
- **Agent Restart**: ~21:52 UTC
- **Service Discovery Success**: All 20+ services discovered at `2025-09-11T21:55:11Z` (3 minutes later)
- **Discovery Window**: 21:55:10.967Z to 21:55:11.135Z (168ms span for all services)

### The Exact Fix
The missing component was the `AmazonEC2ReadOnlyAccess` IAM policy on the EKS node role, which includes:
- `ec2:DescribeTags` - Required for AWS tag collection
- `ec2:DescribeInstances` - Required for instance metadata

## Documentation Analysis

### Gremlin Documentation Findings
**Location**: `https://www.gremlin.com/docs/fault-injection-targets`
**Section**: Cloud tagging > AWS

**Critical Quote**:
> "To include custom AWS tags, ensure the **DescribeTags policy is granted to your EC2 instances**. For the case of RPM and DEB installations, you will also need to install the aws CLI."

### Documentation Issues
1. **Buried Information**: The requirement is hidden in "Fault Injection > Targets" not "Installation"
2. **Vague Guidance**: Says "DescribeTags policy" but doesn't specify `AmazonEC2ReadOnlyAccess`
3. **Missing EKS Context**: No guidance on attaching to EKS node roles
4. **Installation Gap**: Main Kubernetes/EKS installation docs don't mention this requirement

### AWS EKS Standard Policies
**Included by eksctl automatically**:
- `AmazonEKSWorkerNodePolicy` ✅
- `AmazonEC2ContainerRegistryPullOnly` ✅  
- `AmazonEKS_CNI_Policy` ✅

**NOT included by eksctl**:
- `AmazonEC2ReadOnlyAccess` ❌ (required for Gremlin)

## RBAC Analysis

### Kubernetes ClusterRole Configuration
The following RBAC resources exist and are properly configured:

**ClusterRole**: `gremlin-service-discovery`
```yaml
rules:
- apiGroups: [""]
  resources: ["services", "pods", "endpoints", "nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list", "watch"]
```

**ClusterRoleBinding**: `gremlin-service-discovery`
```yaml
subjects:
- kind: ServiceAccount
  name: chao
  namespace: gremlin
```

### RBAC Status
- ✅ **ClusterRole exists**: Proper Kubernetes API permissions for service discovery
- ✅ **ClusterRoleBinding exists**: Bound to `chao` service account
- ✅ **Permissions adequate**: Covers all necessary Kubernetes resources
- ⚠️ **Service account mismatch**: Bound to `chao` instead of `gremlin` (but works)

**Conclusion**: The Kubernetes RBAC was NOT the issue. The ClusterRole provides all necessary permissions for Kubernetes API access. The problem was AWS-level permissions for cloud metadata collection.

## Technical Details

### Why EC2 Permissions Matter
Gremlin's service discovery works in two layers:
1. **Kubernetes API**: Uses ClusterRole to read services/deployments (✅ working)
2. **Cloud Metadata**: Uses EC2 API to collect instance tags and metadata (❌ was failing)

Without EC2 permissions, Gremlin could see Kubernetes objects but couldn't correlate them with cloud infrastructure, preventing proper service registration.

### Agent Logs Evidence
**Before Fix**:
```
UnauthorizedOperation: You are not authorized to perform: ec2:DescribeTags
```

**After Fix**:
```
[INFO] gremlin_common::client - Metadata set for [ cloud: AWS ]
[INFO] gremlin_common::client - Metadata set for [ region: us-east-2 ]
```

## Solution Implementation

### Automated Fix
The solution has been integrated into the installation pipeline:

**File**: `lib/monitoring.sh`
```bash
# Fix Gremlin EC2 permissions for service discovery
local node_role_name
node_role_name=$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'nodegroups[0]' --output text)" --region "$AWS_REGION" --query 'nodegroup.nodeRole' --output text | awk -F'/' '{print $NF}')

if [ -n "$node_role_name" ]; then
    log_info "Attaching EC2ReadOnlyAccess policy to node role: $node_role_name"
    aws iam attach-role-policy --role-name "$node_role_name" --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess" 2>/dev/null || log_warning "Policy may already be attached"
fi
```

### Installation Flow
For new clusters, the `workshop.sh` script now automatically:
1. Attaches `AmazonEC2ReadOnlyAccess` to EKS node role
2. Installs Gremlin agent with correct cluster ID
3. Applies service annotations with team-id
4. Creates Kubernetes RBAC resources
5. Restarts agents to pick up new permissions

## Key Takeaways

1. **Two Permission Layers**: Gremlin needs both Kubernetes RBAC AND AWS IAM permissions
2. **Documentation Gap**: Critical AWS requirement is poorly documented
3. **EKS Limitation**: Standard EKS setup doesn't include EC2ReadOnlyAccess
4. **Service Discovery Dependency**: Cloud metadata collection is required for Kubernetes service discovery
5. **Timing Sensitivity**: Agents must restart after IAM policy changes

## Files Modified
- `lib/monitoring.sh` - Added automatic EC2 permission fix
- `config/gremlin/consolidated_annotations.sh` - Enhanced service annotation script
- `config/gremlin/gremlin-service-discovery-rbac.yaml` - Kubernetes RBAC resources

## Verification Commands
```bash
# Check if policy is attached
aws iam list-attached-role-policies --role-name <node-role-name>

# Verify service discovery
curl -H "Authorization: Key $GREMLIN_API_KEY" \
  "https://api.gremlin.com/v1/services?teamId=$GREMLIN_TEAM_ID"

# Check agent logs
kubectl logs -n gremlin -l app=gremlin --tail=10
```

This analysis confirms that the EC2ReadOnlyAccess policy was the exact fix needed, and the solution is now automated for future installations.
