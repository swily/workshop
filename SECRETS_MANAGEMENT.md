# Secrets Management Guide

## Overview
This document explains how Gremlin credentials are stored and retrieved for multiple clusters and teams.

## Secrets Naming Convention

### Standard Pattern (Recommended)
```
{owner}/gremlin_team_id
{owner}/gremlin_team_certificate
{owner}/gremlin_team_private_key
{owner}/gremlin_team_secret  (optional, for secret-based auth)
```

### Examples
- **Single user, single team**: `sean.wiley/gremlin_team_id`
- **Single user, multiple teams**: `sean.wiley/gremlin_team_id_m00`, `sean.wiley/gremlin_team_id_prod`
- **Bootcamp users**: `/bootcamps/bootcamp-j00/gremlin_team_id`

## How Secrets Are Resolved

### Priority Order
1. **Explicit ARNs** (highest priority)
   - Pass via `--gremlin-team-id-arn`, `--gremlin-team-certificate-arn`, `--gremlin-team-private-key-arn`
   - Used by Terraform for infrastructure provisioning

2. **Owner-based lookup**
   - Pass via `--owner` flag
   - Script looks up `{owner}/gremlin_team_*` in AWS Secrets Manager
   - Used by `deploy_existing` action

3. **Environment variables** (fallback)
   - `GREMLIN_TEAM_ID`
   - `GREMLIN_TEAM_SECRET`
   - `GREMLIN_API_KEY`

## Multiple Clusters, Same Region

### Problem
When creating multiple EKS clusters in the same region, IAM role names must be unique.

### Solution
The ALB Controller IAM role is now cluster-specific:
```bash
# Old (caused conflicts):
AmazonEKSLoadBalancerControllerRole

# New (unique per cluster):
AmazonEKSLoadBalancerControllerRole-${cluster_name}
```

**Fixed in**: `/Users/seanwiley/workshop/lib/cluster.sh` line 128

## Multiple Teams, Same Owner

### Scenario
You want to deploy multiple clusters with different Gremlin teams (e.g., dev, staging, prod).

### Recommended Approach

#### Option 1: Separate Secrets (Recommended)
```bash
# Create team-specific secrets
aws secretsmanager create-secret \
  --name "sean.wiley/gremlin_team_id_dev" \
  --secret-string "team-id-for-dev"

aws secretsmanager create-secret \
  --name "sean.wiley/gremlin_team_id_prod" \
  --secret-string "team-id-for-prod"

# Deploy with explicit ARNs
./workshop.sh --action build_new \
  --subdomain dev \
  --owner sean.wiley \
  --gremlin-team-id-arn "arn:aws:secretsmanager:us-east-2:...:secret:sean.wiley/gremlin_team_id_dev-XXXXX"
```

#### Option 2: Different Owners
```bash
# Create secrets under different owner prefixes
sean.wiley.dev/gremlin_team_id
sean.wiley.prod/gremlin_team_id

# Deploy
./workshop.sh --action build_new \
  --subdomain dev \
  --owner sean.wiley.dev
```

## Deployment Actions

### `build_new` - Create new infrastructure + deploy apps
```bash
./workshop.sh --action build_new \
  --subdomain myapp \
  --owner sean.wiley \
  --region us-east-2 \
  --enable-eks \
  --monitoring grafana \
  --gremlin-team-id-arn "arn:aws:secretsmanager:..." \
  --gremlin-team-certificate-arn "arn:aws:secretsmanager:..." \
  --gremlin-team-private-key-arn "arn:aws:secretsmanager:..."
```

**When to use**: First-time deployment, creates Terraform infrastructure

### `deploy_existing` - Deploy apps to existing infrastructure
```bash
./workshop.sh --action deploy_existing \
  --cluster-name myapp-eks \
  --owner sean.wiley \
  --region us-east-2 \
  --monitoring grafana
```

**When to use**: 
- Infrastructure already exists (Terraform already ran)
- Redeploying applications
- Recovering from failed deployment

**Important**: Set `SUBDOMAIN` env var or it will use cluster name as subdomain

### `gremlin_only` - Install only Gremlin
```bash
./workshop.sh --action gremlin_only \
  --cluster-name myapp-eks \
  --owner sean.wiley
```

### `cleanup` - Destroy everything
```bash
./workshop.sh --action cleanup \
  --subdomain myapp \
  --owner sean.wiley
```

## Common Issues

### Issue: "Secrets not found for owner"
**Cause**: Owner doesn't match secret prefix in Secrets Manager
**Fix**: Pass correct `--owner` flag or create secrets with correct prefix

### Issue: "IAM role already exists"
**Cause**: Multiple clusters in same region with old code
**Fix**: Already fixed in `lib/cluster.sh` - role names are now cluster-specific

### Issue: Wrong DNS (e.g., `seanwm00-eks.gremlinpoc.com` instead of `seanwm00.gremlinpoc.com`)
**Cause**: `SUBDOMAIN` was set to `CLUSTER_NAME` 
**Fix**: Already fixed in `workshop.sh` - SUBDOMAIN no longer overridden for existing deployments
**Workaround**: Set `export SUBDOMAIN=seanwm00` before running `deploy_existing`

### Issue: kubectl warnings clutter output
**Cause**: Kubernetes warnings about duplicate env vars
**Fix**: Already fixed in `scripts/operations/deploy_otel.sh` - warnings now suppressed

## Best Practices

1. **Use explicit ARNs for Terraform** (`build_new`)
   - Ensures correct secrets are used
   - Avoids ambiguity

2. **Use owner-based lookup for app deployment** (`deploy_existing`)
   - Simpler command line
   - Secrets automatically discovered

3. **Standardize secret naming**
   - Use `{owner}/gremlin_team_*` pattern
   - Add suffixes for multiple teams: `_dev`, `_prod`, `_m00`

4. **Set SUBDOMAIN explicitly**
   - For `deploy_existing`, always set: `export SUBDOMAIN=myapp`
   - Prevents DNS issues

5. **One Terraform workspace per subdomain**
   - Workspace directory: `/Users/seanwiley/terraform/workspace/{subdomain}/`
   - Keeps infrastructure isolated

## Verification Commands

```bash
# Check secrets exist
aws secretsmanager list-secrets --region us-east-2 | grep gremlin

# Check Terraform outputs
cd /Users/seanwiley/terraform/workspace/seanwm00
terraform output

# Check ingresses
kubectl get ingress -A

# Check cluster state
cat /Users/seanwiley/workshop/cluster-state.json | jq
```
