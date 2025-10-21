# Integration Strategy: Fictional Computing Machine + Workshop

## The Problem

We have **two separate codebases** that need to work together:

1. **fictional-computing-machine** (Infrastructure)
   - Location: `/Users/seanwiley/gremform/fictional-computing-machine`
   - Owner: Gremlin organization
   - Purpose: Terraform modules for infrastructure provisioning
   - Update frequency: Periodic updates by Gremlin team
   - Repository: `git@github.com:gremlin/fictional-computing-machine.git`

2. **workshop** (Application)
   - Location: `/Users/seanwiley/workshop`
   - Owner: Personal (swily)
   - Purpose: Application deployment scripts and workshop orchestration
   - Update frequency: Active development
   - Repository: `https://github.com/swily/workshop.git`

**Challenge:** How do we integrate them without:
- ❌ Duplicating code
- ❌ Breaking when fictional-computing-machine updates
- ❌ Creating tight coupling
- ❌ Losing ability to update independently

---

## Option 1: Git Submodule (Recommended)

### Architecture

```
workshop/
├── lib/
│   ├── common.sh
│   ├── cluster.sh
│   ├── monitoring.sh
│   └── terraform.sh          # Wrapper that calls submodule
├── terraform/                 # GIT SUBMODULE
│   └── fictional-computing-machine/
│       ├── terraform/
│       │   └── modules/
│       │       ├── demo_eks/
│       │       ├── alb/
│       │       └── dns/
│       └── README.md
├── scripts/
├── config/
└── workshop.sh
```

### Implementation

```bash
# Add fictional-computing-machine as submodule
cd /Users/seanwiley/workshop
git submodule add git@github.com:gremlin/fictional-computing-machine.git terraform/fictional-computing-machine

# Initialize submodule
git submodule update --init --recursive

# Create symlink for easier access
ln -s terraform/fictional-computing-machine/terraform/modules terraform/modules
```

### Terraform Wrapper (lib/terraform.sh)

```bash
#!/bin/bash

# Terraform directory (points to submodule)
TERRAFORM_BASE_DIR="${SCRIPT_DIR}/../terraform/fictional-computing-machine"
TERRAFORM_MODULES_DIR="${TERRAFORM_BASE_DIR}/terraform/modules"
TERRAFORM_WORK_DIR="${SCRIPT_DIR}/../terraform/workspace"

# Initialize Terraform workspace
terraform_init_workspace() {
    local subdomain="$1"
    local owner="$2"
    
    # Create workspace directory
    mkdir -p "$TERRAFORM_WORK_DIR/$subdomain"
    
    # Copy main.tf template
    cat > "$TERRAFORM_WORK_DIR/$subdomain/main.tf" <<EOF
module "demo" {
  source = "../../fictional-computing-machine/terraform/modules/sa_demo"
  
  subdomain = "$subdomain"
  owner = "$owner"
  
  enable_eks = var.enable_eks
  enable_ecs_fargate = var.enable_ecs_fargate
  
  gremlin_team_id_arn = var.gremlin_team_id_arn
  gremlin_team_certificate_arn = var.gremlin_team_certificate_arn
  gremlin_team_private_key_arn = var.gremlin_team_private_key_arn
}

output "cluster_name" { value = module.demo.cluster_name }
output "alb_dns_name" { value = module.demo.alb_dns_name }
# ... other outputs
EOF
    
    # Initialize Terraform
    cd "$TERRAFORM_WORK_DIR/$subdomain"
    terraform init
}
```

### Updating Submodule

```bash
# Update to latest fictional-computing-machine
cd /Users/seanwiley/workshop
git submodule update --remote terraform/fictional-computing-machine

# Commit the update
git add terraform/fictional-computing-machine
git commit -m "Update fictional-computing-machine to latest"
```

### Pros
- ✅ Clean separation of concerns
- ✅ Easy to update fictional-computing-machine
- ✅ No code duplication
- ✅ Version control for infrastructure modules
- ✅ Can pin to specific versions

### Cons
- ⚠️ Users need to run `git submodule update --init`
- ⚠️ Slightly more complex git workflow
- ⚠️ Submodule can get out of sync

---

## Option 2: Terraform Module Source (Git URL)

### Architecture

```
workshop/
├── lib/
│   └── terraform.sh
├── terraform/
│   └── workspace/
│       └── {subdomain}/
│           ├── main.tf        # References remote module
│           ├── variables.tf
│           └── outputs.tf
├── scripts/
└── workshop.sh
```

### Implementation

**main.tf (generated dynamically):**
```hcl
module "demo" {
  # Reference fictional-computing-machine directly from GitHub
  source = "git@github.com:gremlin/fictional-computing-machine.git//terraform/modules/sa_demo?ref=v1.0.0"
  
  subdomain = var.subdomain
  owner = var.owner
  enable_eks = var.enable_eks
  # ...
}
```

**lib/terraform.sh:**
```bash
terraform_init_workspace() {
    local subdomain="$1"
    local owner="$2"
    local fcm_version="${FCM_VERSION:-main}"  # Can pin to version
    
    mkdir -p "$TERRAFORM_WORK_DIR/$subdomain"
    
    cat > "$TERRAFORM_WORK_DIR/$subdomain/main.tf" <<EOF
module "demo" {
  source = "git@github.com:gremlin/fictional-computing-machine.git//terraform/modules/sa_demo?ref=${fcm_version}"
  
  subdomain = "$subdomain"
  owner = "$owner"
  # ...
}
EOF
    
    cd "$TERRAFORM_WORK_DIR/$subdomain"
    terraform init  # Downloads module from GitHub
}
```

### Updating Module

```bash
# Update to specific version
FCM_VERSION="v1.1.0" ./workshop.sh --action create_new

# Or update in code
# Edit lib/terraform.sh and change default FCM_VERSION
```

### Pros
- ✅ No submodules needed
- ✅ Terraform handles module downloads
- ✅ Can pin to specific versions/tags
- ✅ Simpler git workflow
- ✅ Users don't need to manage submodules

### Cons
- ⚠️ Requires SSH key for private repos
- ⚠️ Module downloaded per workspace (more disk space)
- ⚠️ Less visibility into module code

---

## Option 3: Copy and Customize (Not Recommended)

### Architecture

```
workshop/
├── terraform/
│   └── modules/              # COPIED from fictional-computing-machine
│       ├── demo_eks/
│       ├── alb/
│       └── dns/
└── workshop.sh
```

### Pros
- ✅ Complete control
- ✅ No external dependencies

### Cons
- ❌ Code duplication
- ❌ Manual updates required
- ❌ Divergence from upstream
- ❌ Maintenance burden

---

## Option 4: Monorepo Merge (Full Integration)

### Architecture

```
gremlin-demo-platform/         # NEW unified repo
├── infrastructure/            # From fictional-computing-machine
│   └── terraform/
│       └── modules/
├── applications/              # From workshop
│   ├── scripts/
│   ├── config/
│   └── monitoring/
├── lib/
│   ├── common.sh
│   ├── terraform.sh
│   └── cluster.sh
└── deploy.sh                  # Unified entry point
```

### Implementation

```bash
# Create new unified repo
mkdir gremlin-demo-platform
cd gremlin-demo-platform
git init

# Merge fictional-computing-machine
git remote add fcm git@github.com:gremlin/fictional-computing-machine.git
git fetch fcm
git merge --allow-unrelated-histories fcm/main -m "Merge fictional-computing-machine"
mv terraform infrastructure/terraform

# Merge workshop
git remote add workshop https://github.com/swily/workshop.git
git fetch workshop
git merge --allow-unrelated-histories workshop/monitoring -m "Merge workshop"
mv scripts applications/scripts
mv config applications/config
```

### Pros
- ✅ Single source of truth
- ✅ Unified version control
- ✅ No submodules or external refs
- ✅ Easier to coordinate changes

### Cons
- ❌ Loses connection to upstream fictional-computing-machine
- ❌ Can't easily pull updates from Gremlin
- ❌ Requires organizational buy-in
- ❌ More complex initial setup

---

## Recommended Approach: Option 2 (Terraform Module Source)

### Why This is Best

1. **Clean Separation**
   - Infrastructure modules stay in fictional-computing-machine
   - Application scripts stay in workshop
   - Clear ownership boundaries

2. **Easy Updates**
   - Update by changing version tag
   - No git submodule complexity
   - Terraform handles downloads

3. **Version Control**
   - Pin to specific versions for stability
   - Test new versions before adopting
   - Rollback by changing version

4. **Minimal Changes**
   - No restructuring of either repo
   - Workshop just references modules
   - fictional-computing-machine unchanged

### Implementation Plan

**Phase 1: Setup Terraform Workspace Structure**

```bash
cd /Users/seanwiley/workshop

# Create workspace directory
mkdir -p terraform/workspace

# Create .gitignore
cat > terraform/.gitignore <<EOF
# Ignore Terraform state and workspaces
workspace/*/terraform.tfstate*
workspace/*/.terraform/
workspace/*/.terraform.lock.hcl
workspace/*/tfplan

# Keep workspace directory structure
!workspace/.gitkeep
EOF

touch terraform/workspace/.gitkeep
```

**Phase 2: Create lib/terraform.sh**

```bash
#!/bin/bash
#
# Terraform wrapper for fictional-computing-machine integration
#

# Configuration
FCM_REPO="git@github.com:gremlin/fictional-computing-machine.git"
FCM_VERSION="${FCM_VERSION:-main}"  # Can override with env var
TERRAFORM_WORK_DIR="${SCRIPT_DIR}/../terraform/workspace"

# Create Terraform workspace for deployment
terraform_create_workspace() {
    local subdomain="$1"
    local owner="$2"
    local enable_eks="$3"
    local enable_ecs="$4"
    local team_id_arn="$5"
    local cert_arn="$6"
    local key_arn="$7"
    
    local workspace_dir="$TERRAFORM_WORK_DIR/$subdomain"
    
    log_info "Creating Terraform workspace for: $subdomain"
    mkdir -p "$workspace_dir"
    
    # Create main.tf
    cat > "$workspace_dir/main.tf" <<EOF
# Generated by workshop.sh
# References fictional-computing-machine modules from GitHub

module "demo" {
  source = "${FCM_REPO}//terraform/modules/sa_demo?ref=${FCM_VERSION}"
  
  subdomain = var.subdomain
  owner = var.owner
  enable_eks = var.enable_eks
  enable_ecs_fargate = var.enable_ecs_fargate
  
  gremlin_team_id_arn = var.gremlin_team_id_arn
  gremlin_team_certificate_arn = var.gremlin_team_certificate_arn
  gremlin_team_private_key_arn = var.gremlin_team_private_key_arn
}

# Outputs for workshop scripts
output "cluster_name" {
  value = module.demo.cluster_name
}

output "cluster_endpoint" {
  value = module.demo.cluster_endpoint
}

output "cluster_region" {
  value = module.demo.cluster_region
}

output "alb_dns_name" {
  value = module.demo.alb_dns_name
}

output "demo_frontend_url" {
  value = module.demo.demo_frontend_url
}

output "monitoring_url" {
  value = module.demo.monitoring_url
}

output "otel_demo_target_group_arn" {
  value = module.demo.otel_demo_target_group_arn
}

output "monitoring_target_group_arn" {
  value = module.demo.monitoring_target_group_arn
}

output "gremlin_team_id_arn" {
  value = module.demo.gremlin_team_id_arn
  sensitive = true
}

output "gremlin_team_certificate_arn" {
  value = module.demo.gremlin_team_certificate_arn
  sensitive = true
}

output "gremlin_team_private_key_arn" {
  value = module.demo.gremlin_team_private_key_arn
  sensitive = true
}

output "subdomain" {
  value = module.demo.subdomain
}

output "owner" {
  value = module.demo.owner
}
EOF
    
    # Create variables.tf
    cat > "$workspace_dir/variables.tf" <<EOF
variable "subdomain" {
  description = "Unique subdomain for this deployment"
  type        = string
  default     = "$subdomain"
}

variable "owner" {
  description = "Owner of this deployment"
  type        = string
  default     = "$owner"
}

variable "enable_eks" {
  description = "Enable EKS cluster"
  type        = bool
  default     = $enable_eks
}

variable "enable_ecs_fargate" {
  description = "Enable ECS Fargate cluster"
  type        = bool
  default     = $enable_ecs
}

variable "gremlin_team_id_arn" {
  description = "ARN of Gremlin Team ID secret"
  type        = string
  default     = "$team_id_arn"
}

variable "gremlin_team_certificate_arn" {
  description = "ARN of Gremlin Team Certificate secret"
  type        = string
  default     = "$cert_arn"
}

variable "gremlin_team_private_key_arn" {
  description = "ARN of Gremlin Team Private Key secret"
  type        = string
  default     = "$key_arn"
}
EOF
    
    # Create terraform.tf (backend config)
    cat > "$workspace_dir/terraform.tf" <<EOF
terraform {
  required_version = ">= 1.13"
  
  backend "s3" {
    bucket = "gremlin-terraform-state-us-east-2"
    key    = "workshop/$subdomain/terraform.tfstate"
    region = "us-east-2"
    encrypt = true
    dynamodb_table = "gremlin-terraform-locks"
  }
}

provider "aws" {
  region = "us-east-2"
  allowed_account_ids = ["501454956990"]
}
EOF
    
    log_success "Terraform workspace created: $workspace_dir"
}

# Rest of terraform.sh functions...
# (export_terraform_outputs, fetch_gremlin_credentials, etc.)
```

**Phase 3: Update Workshop.sh**

```bash
# workshop.sh

# Source Terraform library
source "$SCRIPT_DIR/lib/terraform.sh"

provision_infrastructure() {
    log_section "Provisioning Infrastructure with Terraform"
    
    # Create workspace
    terraform_create_workspace \
        "$SUBDOMAIN" \
        "$OWNER" \
        "$ENABLE_EKS" \
        "$ENABLE_ECS_FARGATE" \
        "$GREMLIN_TEAM_ID_ARN" \
        "$GREMLIN_TEAM_CERTIFICATE_ARN" \
        "$GREMLIN_TEAM_PRIVATE_KEY_ARN"
    
    # Run Terraform
    local workspace_dir="$TERRAFORM_WORK_DIR/$SUBDOMAIN"
    terraform_init "$workspace_dir"
    terraform_apply "$workspace_dir"
    
    # Export outputs
    export_terraform_outputs "$workspace_dir"
    
    # Fetch Gremlin credentials
    fetch_gremlin_credentials
    
    log_success "Infrastructure provisioned"
}
```

---

## Updating fictional-computing-machine Modules

### When Gremlin Updates Modules

**Option A: Update to latest (main branch)**
```bash
# Use latest version
FCM_VERSION=main ./workshop.sh --action create_new
```

**Option B: Update to specific version (recommended)**
```bash
# Gremlin tags a new release: v1.2.0
FCM_VERSION=v1.2.0 ./workshop.sh --action create_new

# Or update default in lib/terraform.sh
FCM_VERSION="${FCM_VERSION:-v1.2.0}"
```

**Option C: Test before adopting**
```bash
# Test new version in separate workspace
FCM_VERSION=v1.2.0 ./workshop.sh --subdomain test-new --action create_new

# If successful, update default
vim lib/terraform.sh  # Change FCM_VERSION default
```

---

## Comparison Matrix

| Aspect | Submodule | Module Source | Copy | Monorepo |
|--------|-----------|---------------|------|----------|
| **Separation** | ✅ Clean | ✅ Clean | ❌ Duplicated | ⚠️ Merged |
| **Updates** | ⚠️ Manual | ✅ Easy | ❌ Manual | ❌ Lost |
| **Complexity** | ⚠️ Medium | ✅ Low | ✅ Low | ❌ High |
| **Version Control** | ✅ Yes | ✅ Yes | ❌ No | ✅ Yes |
| **Disk Space** | ✅ Efficient | ⚠️ Per-workspace | ✅ Efficient | ✅ Efficient |
| **Git Workflow** | ⚠️ Complex | ✅ Simple | ✅ Simple | ❌ Complex |
| **Upstream Sync** | ✅ Easy | ✅ Easy | ❌ Manual | ❌ Lost |

---

## Final Recommendation

**Use Option 2: Terraform Module Source with Version Pinning**

### Implementation Steps

1. ✅ Create `terraform/workspace/` directory structure
2. ✅ Create `lib/terraform.sh` with workspace generation
3. ✅ Update `workshop.sh` to use Terraform modules
4. ✅ Pin to specific fictional-computing-machine version
5. ✅ Test with test deployment
6. ✅ Document update process

### Benefits

- **Clean separation:** Each repo maintains its purpose
- **Easy updates:** Change version tag to update
- **No submodules:** Simpler git workflow
- **Version control:** Pin to stable versions
- **Terraform native:** Uses Terraform's module system

### Next Steps

1. Create `lib/terraform.sh` with full implementation
2. Update `workshop.sh` argument parsing for new parameters
3. Test workspace creation
4. Test Terraform apply
5. Test application deployment on Terraform-created infrastructure
