# How to Run the Workshop

This guide walks through running the workshop from scratch.

## Prerequisites

- AWS CLI installed and configured
- Terraform >= 1.13 installed
- kubectl installed
- Helm v3 installed
- jq installed

## Step 1: Configure AWS CLI for the correct account

The workshop requires AWS account `501454956990` (sa-demos).

1. Create access keys in the AWS Console while logged into account `501454956990`:
   - Go to: https://console.aws.amazon.com/iam/home#/security_credentials
   - Scroll to "Access keys" section
   - Click "Create access key"
   - Download the CSV file

2. Configure AWS CLI:
   ```bash
   # Remove old credentials if needed
   rm ~/.aws/credentials
   
   # Configure with new keys
   aws configure
   # Paste Access Key ID and Secret Access Key from the CSV
   # Set region: us-east-2
   # Set output: json
   ```

3. Verify you're in the correct account:
   ```bash
   aws sts get-caller-identity
   # Should show: "Account": "501454956990"
   ```

## Step 2: Store Gremlin credentials in AWS Secrets Manager

Create secrets for your Gremlin team credentials (replace with your actual values):

```bash
# Set your owner name (used for secret naming)
OWNER="sean.wiley"

# Create Team ID secret
aws secretsmanager create-secret \
  --name "${OWNER}/gremlin_team_id" \
  --secret-string "YOUR_TEAM_ID_HERE" \
  --region us-east-2

# Create Team Secret (optional, for secret-based auth)
aws secretsmanager create-secret \
  --name "${OWNER}/gremlin_team_secret" \
  --secret-string "YOUR_TEAM_SECRET_HERE" \
  --region us-east-2

# Create Team Certificate
aws secretsmanager create-secret \
  --name "${OWNER}/gremlin_team_certificate" \
  --secret-string "$(cat /path/to/team-certificate.pem)" \
  --region us-east-2

# Create Team Private Key
aws secretsmanager create-secret \
  --name "${OWNER}/gremlin_team_private_key" \
  --secret-string "$(cat /path/to/team-private-key.pem)" \
  --region us-east-2
```

## Step 3: Clone and configure fictional-computing-machine repository

The workshop requires the `fictional-computing-machine` Terraform modules:

```bash
cd ~/gremform  # or wherever you keep repos

# Clone if you haven't already
git clone https://github.com/gremlin/fictional-computing-machine.git

# Verify the path exists
ls ~/gremform/fictional-computing-machine
```

**Important fixes required:**

1. **Update module sources to use local paths** (avoids SSH authentication issues):

```bash
cd ~/gremform/fictional-computing-machine/terraform/modules/sa_demo

# Edit main.tf and replace all SSH Git URLs with relative paths:
# - git@github.com:gremlin/fictional-computing-machine.git//terraform/modules/dns  →  ../dns
# - git@github.com:gremlin/fictional-computing-machine.git//terraform/modules/iam  →  ../iam
# - git@github.com:gremlin/fictional-computing-machine.git//terraform/modules/alb  →  ../alb
# - git@github.com:gremlin/fictional-computing-machine.git//terraform/modules/demo_ecs_fargate  →  ../demo_ecs_fargate
```

2. **Create outputs.tf** (required for workshop integration):

The `sa_demo` module needs an `outputs.tf` file. Create it at:
`~/gremform/fictional-computing-machine/terraform/modules/sa_demo/outputs.tf`

See the workshop repo for the required outputs, or the module will fail validation.

## Step 4: Set FCM_LOCAL_PATH environment variable

Tell the workshop where to find the fictional-computing-machine repo:

```bash
export FCM_LOCAL_PATH=/Users/seanwiley/gremform/fictional-computing-machine

# Or use your actual path if different:
# export FCM_LOCAL_PATH=~/gremform/fictional-computing-machine
```

## Step 5: Run the workshop

```bash
cd /Users/seanwiley/workshop

# Set the FCM path and run
FCM_LOCAL_PATH=/Users/seanwiley/gremform/fictional-computing-machine \
./workshop.sh \
  --subdomain seanw \
  --owner sean.wiley \
  --enable-eks \
  --action build_new
```

**What this does:**
- Creates EKS cluster `seanw-eks` in `us-east-2`
- Deploys OpenTelemetry Demo (20+ microservices)
- Installs Prometheus + Grafana monitoring
- Installs Gremlin agent for chaos engineering
- Sets up DNS at:
  - Frontend: `https://demo-frontend.seanw.gremlinpoc.com`
  - Grafana: `https://monitoring.seanw.gremlinpoc.com`

**Time:** ~15-20 minutes for full deployment

**Recent Fixes Applied:**
- ✅ Removed broken two-phase Terraform apply logic
- ✅ Fixed stale plan issues
- ✅ Fixed kubeconfig update timing
- ✅ Simplified apply to single-phase auto-approve

## Troubleshooting

### Issue: S3 bucket already exists / access denied

The workshop now uses owner-specific bucket names to avoid conflicts:
- Bucket: `gremlin-tf-state-{owner}-us-east-2`
- DynamoDB: `gremlin-terraform-locks-{owner}`

These are automatically created on first run.

### Issue: fictional-computing-machine not found

Make sure:
1. The repo is cloned at the path you specified
2. `FCM_LOCAL_PATH` is set correctly
3. The path exists: `ls $FCM_LOCAL_PATH`

### Issue: Gremlin credentials not found

Verify secrets exist:
```bash
aws secretsmanager list-secrets \
  --region us-east-2 \
  --query "SecretList[?contains(Name, 'sean.wiley/gremlin')].[Name]" \
  --output table
```

Should show:
- `sean.wiley/gremlin_team_id`
- `sean.wiley/gremlin_team_certificate`
- `sean.wiley/gremlin_team_private_key`

## Cleanup

To destroy everything:

```bash
./workshop.sh \
  --subdomain seanw \
  --action cleanup
```

This will:
1. Delete Kubernetes resources (ingresses, LoadBalancers)
2. Run `terraform destroy`
3. Remove all AWS infrastructure
