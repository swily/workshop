# Gremlin Credentials Strategy Analysis

## Current State (Before Changes)

### How Credentials Are Supplied Today

**Command-line arguments:**
```bash
./workshop.sh \
    --gremlin-team-id "438c58ec-..." \
    --gremlin-team-secret "secret-value" \
    --gremlin-api-key "api-key-value"
```

**Environment variables:**
```bash
export GREMLIN_TEAM_ID="438c58ec-..."
export GREMLIN_TEAM_SECRET="secret-value"
export GREMLIN_API_KEY="api-key-value"
./workshop.sh --action build_new
```

**Problems:**
- ❌ Credentials exposed in shell history
- ❌ Credentials visible in process list (`ps aux`)
- ❌ Must copy/paste long certificate strings
- ❌ No centralized credential management
- ❌ Different credentials per user/team

---

## Terraform Approach (Secrets Manager)

### How Terraform Expects Credentials

**Secrets Manager ARNs in terraform.tfvars:**
```hcl
gremlin_team_id_arn          = "arn:aws:secretsmanager:us-east-2:123:secret:alex.smith/gremlin_team_id-xxx"
gremlin_team_certificate_arn = "arn:aws:secretsmanager:us-east-2:123:secret:alex.smith/gremlin_team_certificate-yyy"
gremlin_team_private_key_arn = "arn:aws:secretsmanager:us-east-2:123:secret:alex.smith/gremlin_team_private_key-zzz"
```

**Terraform passes ARNs to workshop scripts via outputs:**
```json
{
  "gremlin_team_id_arn": {"value": "arn:aws:..."},
  "gremlin_team_certificate_arn": {"value": "arn:aws:..."},
  "gremlin_team_private_key_arn": {"value": "arn:aws:..."}
}
```

**Workshop scripts fetch actual values:**
```bash
GREMLIN_TEAM_ID=$(aws secretsmanager get-secret-value \
    --secret-id "$GREMLIN_TEAM_ID_ARN" \
    --query 'SecretString' --output text)
```

---

## Cost Analysis: Secrets Manager

### AWS Secrets Manager Pricing (us-east-2)

**Storage:**
- $0.40 per secret per month
- 3 secrets = $1.20/month

**API Calls:**
- $0.05 per 10,000 API calls
- Typical usage: ~100 calls/day = 3,000/month
- Cost: ~$0.015/month

**Total Monthly Cost:** ~$1.22/month per user

**Annual Cost:** ~$14.64/year per user

### Cost Comparison

| Approach | Setup Cost | Monthly Cost | Security | Convenience |
|----------|-----------|--------------|----------|-------------|
| **CLI Args** | $0 | $0 | ❌ Low | ❌ Poor |
| **Env Vars** | $0 | $0 | ❌ Low | ⚠️ Medium |
| **Secrets Manager** | $0 | $1.22 | ✅ High | ✅ Excellent |
| **Parameter Store** | $0 | $0 | ✅ High | ✅ Good |

### Alternative: AWS Systems Manager Parameter Store

**Standard Parameters:**
- **FREE** for up to 10,000 parameters
- No API call charges
- Same security as Secrets Manager
- No automatic rotation

**Recommendation:** Use Parameter Store for cost savings if rotation not needed.

---

## Proposed Credential Strategy

### Option 1: Team-Based Lookup (Recommended)

**User provides team name only:**
```bash
./workshop.sh \
    --subdomain alexs \
    --owner alex.smith \
    --gremlin-team "Solutions Engineering" \
    --action create_new
```

**Script logic:**
```bash
# Construct secret names from team name
TEAM_SLUG=$(echo "$GREMLIN_TEAM" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
GREMLIN_TEAM_ID_ARN="arn:aws:secretsmanager:us-east-2:${AWS_ACCOUNT}:secret:gremlin/${TEAM_SLUG}/team_id"
GREMLIN_TEAM_CERTIFICATE_ARN="arn:aws:secretsmanager:us-east-2:${AWS_ACCOUNT}:secret:gremlin/${TEAM_SLUG}/certificate"
GREMLIN_TEAM_PRIVATE_KEY_ARN="arn:aws:secretsmanager:us-east-2:${AWS_ACCOUNT}:secret:gremlin/${TEAM_SLUG}/private_key"

# Fetch credentials
fetch_gremlin_credentials
```

**Secret naming convention:**
```
gremlin/solutions-engineering/team_id
gremlin/solutions-engineering/certificate
gremlin/solutions-engineering/private_key
gremlin/sales/team_id
gremlin/sales/certificate
gremlin/sales/private_key
```

**Benefits:**
- ✅ User only needs to know team name
- ✅ Centralized credential management
- ✅ Easy to add new teams
- ✅ No credential exposure
- ✅ Works with Terraform

**Drawbacks:**
- ⚠️ Requires initial secret setup
- ⚠️ All users share same team credentials

---

### Option 2: Owner-Based Lookup

**User provides owner name (already required):**
```bash
./workshop.sh \
    --subdomain alexs \
    --owner alex.smith \
    --action create_new
```

**Script logic:**
```bash
# Construct secret names from owner
GREMLIN_TEAM_ID_ARN="arn:aws:secretsmanager:us-east-2:${AWS_ACCOUNT}:secret:${OWNER}/gremlin_team_id"
GREMLIN_TEAM_CERTIFICATE_ARN="arn:aws:secretsmanager:us-east-2:${AWS_ACCOUNT}:secret:${OWNER}/gremlin_team_certificate"
GREMLIN_TEAM_PRIVATE_KEY_ARN="arn:aws:secretsmanager:us-east-2:${AWS_ACCOUNT}:secret:${OWNER}/gremlin_team_private_key"

# Fetch credentials
fetch_gremlin_credentials
```

**Secret naming convention:**
```
alex.smith/gremlin_team_id
alex.smith/gremlin_team_certificate
alex.smith/gremlin_team_private_key
jane.doe/gremlin_team_id
jane.doe/gremlin_team_certificate
jane.doe/gremlin_team_private_key
```

**Benefits:**
- ✅ Per-user credentials (better isolation)
- ✅ No additional arguments needed
- ✅ Matches Terraform README convention
- ✅ Easy to track who owns what

**Drawbacks:**
- ⚠️ Each user needs their own secrets
- ⚠️ More secrets to manage

---

### Option 3: Hybrid Approach (Most Flexible)

**Support multiple lookup strategies:**

```bash
# Strategy 1: Explicit ARNs (Terraform-style)
./workshop.sh \
    --gremlin-team-id-arn "arn:aws:..." \
    --gremlin-team-certificate-arn "arn:aws:..." \
    --gremlin-team-private-key-arn "arn:aws:..."

# Strategy 2: Team name lookup
./workshop.sh \
    --gremlin-team "Solutions Engineering"

# Strategy 3: Owner-based lookup (default)
./workshop.sh \
    --owner alex.smith
    # Automatically looks up alex.smith/gremlin_* secrets

# Strategy 4: Legacy (backwards compatible)
export GREMLIN_TEAM_ID="..."
./workshop.sh
```

**Lookup order:**
1. Check for explicit ARNs (--gremlin-team-id-arn)
2. Check for team name (--gremlin-team)
3. Check for owner-based secrets (--owner)
4. Check environment variables (GREMLIN_TEAM_ID)
5. Fail with helpful error message

**Implementation:**
```bash
resolve_gremlin_credentials() {
    # Strategy 1: Explicit ARNs
    if [[ -n "${GREMLIN_TEAM_ID_ARN:-}" ]]; then
        log_info "Using explicit Secrets Manager ARNs"
        fetch_gremlin_credentials
        return 0
    fi
    
    # Strategy 2: Team name
    if [[ -n "${GREMLIN_TEAM:-}" ]]; then
        log_info "Looking up credentials for team: $GREMLIN_TEAM"
        TEAM_SLUG=$(echo "$GREMLIN_TEAM" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        GREMLIN_TEAM_ID_ARN="arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT}:secret:gremlin/${TEAM_SLUG}/team_id"
        GREMLIN_TEAM_CERTIFICATE_ARN="arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT}:secret:gremlin/${TEAM_SLUG}/certificate"
        GREMLIN_TEAM_PRIVATE_KEY_ARN="arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT}:secret:gremlin/${TEAM_SLUG}/private_key"
        fetch_gremlin_credentials
        return 0
    fi
    
    # Strategy 3: Owner-based lookup
    if [[ -n "${OWNER:-}" ]]; then
        log_info "Looking up credentials for owner: $OWNER"
        GREMLIN_TEAM_ID_ARN="arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT}:secret:${OWNER}/gremlin_team_id"
        GREMLIN_TEAM_CERTIFICATE_ARN="arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT}:secret:${OWNER}/gremlin_team_certificate"
        GREMLIN_TEAM_PRIVATE_KEY_ARN="arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT}:secret:${OWNER}/gremlin_team_private_key"
        
        # Check if secrets exist
        if aws secretsmanager describe-secret --secret-id "$GREMLIN_TEAM_ID_ARN" &>/dev/null; then
            fetch_gremlin_credentials
            return 0
        else
            log_warning "No Secrets Manager credentials found for owner: $OWNER"
            log_info "Falling back to environment variables..."
        fi
    fi
    
    # Strategy 4: Environment variables (legacy)
    if [[ -n "${GREMLIN_TEAM_ID:-}" && -n "${GREMLIN_TEAM_CERTIFICATE:-}" ]]; then
        log_info "Using credentials from environment variables"
        return 0
    fi
    
    # No credentials found
    log_error "No Gremlin credentials found!"
    log_info "Please provide credentials using one of these methods:"
    echo "  1. Explicit ARNs: --gremlin-team-id-arn, --gremlin-team-certificate-arn, --gremlin-team-private-key-arn"
    echo "  2. Team name: --gremlin-team 'Solutions Engineering'"
    echo "  3. Owner-based: --owner alex.smith (requires secrets in Secrets Manager)"
    echo "  4. Environment: export GREMLIN_TEAM_ID=... GREMLIN_TEAM_CERTIFICATE=..."
    return 1
}
```

---

## Recommended Implementation

### Phase 1: Add Secrets Manager Support (Backwards Compatible)

**Keep existing credential methods, add Secrets Manager:**

```bash
# lib/terraform.sh
fetch_gremlin_credentials() {
    local region="${AWS_REGION:-us-east-2}"
    
    if [[ -z "$GREMLIN_TEAM_ID_ARN" ]]; then
        log_error "GREMLIN_TEAM_ID_ARN not set"
        return 1
    fi
    
    log_info "Fetching Gremlin credentials from AWS Secrets Manager"
    
    export GREMLIN_TEAM_ID=$(aws secretsmanager get-secret-value \
        --secret-id "$GREMLIN_TEAM_ID_ARN" \
        --region "$region" \
        --query 'SecretString' \
        --output text 2>/dev/null)
    
    if [[ -z "$GREMLIN_TEAM_ID" ]]; then
        log_error "Failed to fetch Gremlin Team ID from Secrets Manager"
        return 1
    fi
    
    export GREMLIN_TEAM_CERTIFICATE=$(aws secretsmanager get-secret-value \
        --secret-id "$GREMLIN_TEAM_CERTIFICATE_ARN" \
        --region "$region" \
        --query 'SecretString' \
        --output text 2>/dev/null)
    
    if [[ -z "$GREMLIN_TEAM_CERTIFICATE" ]]; then
        log_error "Failed to fetch Gremlin Team Certificate from Secrets Manager"
        return 1
    fi
    
    export GREMLIN_TEAM_PRIVATE_KEY=$(aws secretsmanager get-secret-value \
        --secret-id "$GREMLIN_TEAM_PRIVATE_KEY_ARN" \
        --region "$region" \
        --query 'SecretString' \
        --output text 2>/dev/null)
    
    if [[ -z "$GREMLIN_TEAM_PRIVATE_KEY" ]]; then
        log_error "Failed to fetch Gremlin Team Private Key from Secrets Manager"
        return 1
    fi
    
    log_success "Gremlin credentials fetched from Secrets Manager"
    log_info "Team ID: ${GREMLIN_TEAM_ID:0:8}..."
}
```

**Update gremlin_install.sh:**
```bash
# scripts/gremlin_install.sh

# Check if credentials are already in environment
if [[ -z "$GREMLIN_TEAM_ID" ]]; then
    log_info "Gremlin credentials not found in environment"
    
    # Try to fetch from Secrets Manager if ARNs are set
    if [[ -n "${GREMLIN_TEAM_ID_ARN:-}" ]]; then
        log_info "Fetching credentials from AWS Secrets Manager"
        source "$SCRIPT_DIR/../lib/terraform.sh"
        fetch_gremlin_credentials
    else
        log_error "No Gremlin credentials available"
        log_info "Please provide credentials via:"
        echo "  1. Secrets Manager ARNs: --gremlin-team-id-arn, etc."
        echo "  2. Environment variables: GREMLIN_TEAM_ID, GREMLIN_TEAM_CERTIFICATE, etc."
        echo "  3. Command-line arguments: --team-id, --team-secret, etc."
        exit 1
    fi
fi

# Validate credentials are present
if [[ -z "$GREMLIN_TEAM_ID" || -z "$GREMLIN_TEAM_CERTIFICATE" || -z "$GREMLIN_TEAM_PRIVATE_KEY" ]]; then
    log_error "Incomplete Gremlin credentials"
    exit 1
fi

log_info "Installing Gremlin with Team ID: ${GREMLIN_TEAM_ID:0:8}..."
```

### Phase 2: Add Smart Lookup (Owner-Based)

**Add to lib/terraform.sh:**
```bash
resolve_gremlin_credentials_from_owner() {
    local owner="$1"
    local region="${AWS_REGION:-us-east-2}"
    local account=$(aws sts get-caller-identity --query Account --output text)
    
    log_info "Attempting to resolve Gremlin credentials for owner: $owner"
    
    # Construct ARNs
    export GREMLIN_TEAM_ID_ARN="arn:aws:secretsmanager:${region}:${account}:secret:${owner}/gremlin_team_id"
    export GREMLIN_TEAM_CERTIFICATE_ARN="arn:aws:secretsmanager:${region}:${account}:secret:${owner}/gremlin_team_certificate"
    export GREMLIN_TEAM_PRIVATE_KEY_ARN="arn:aws:secretsmanager:${region}:${account}:secret:${owner}/gremlin_team_private_key"
    
    # Check if secrets exist
    if ! aws secretsmanager describe-secret --secret-id "$GREMLIN_TEAM_ID_ARN" &>/dev/null; then
        log_warning "Secrets not found for owner: $owner"
        log_info "Expected secrets:"
        echo "  - ${owner}/gremlin_team_id"
        echo "  - ${owner}/gremlin_team_certificate"
        echo "  - ${owner}/gremlin_team_private_key"
        return 1
    fi
    
    # Fetch credentials
    fetch_gremlin_credentials
}
```

**Update workshop.sh:**
```bash
# After parse_arguments(), before main workflow
if [[ -z "${GREMLIN_TEAM_ID_ARN:-}" && -n "${OWNER:-}" ]]; then
    log_info "No explicit Gremlin credentials provided, attempting owner-based lookup"
    source "$SCRIPT_DIR/lib/terraform.sh"
    resolve_gremlin_credentials_from_owner "$OWNER" || {
        log_warning "Owner-based credential lookup failed"
        log_info "Falling back to environment variables or manual input"
    }
fi
```

---

## Secret Setup Guide

### For Users: Creating Your Secrets

```bash
# Set your owner name
OWNER="alex.smith"
REGION="us-east-2"

# Create Team ID secret
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_id" \
    --description "Gremlin Team ID for ${OWNER}" \
    --secret-string "438c58ec-03db-47ac-8c58-ec03db67ac42" \
    --region "$REGION"

# Create Team Certificate secret
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_certificate" \
    --description "Gremlin Team Certificate for ${OWNER}" \
    --secret-string "$(cat team-certificate.pem)" \
    --region "$REGION"

# Create Team Private Key secret
aws secretsmanager create-secret \
    --name "${OWNER}/gremlin_team_private_key" \
    --description "Gremlin Team Private Key for ${OWNER}" \
    --secret-string "$(cat team-private-key.pem)" \
    --region "$REGION"
```

### For Teams: Shared Credentials

```bash
# Set team name
TEAM="solutions-engineering"
REGION="us-east-2"

# Create shared team secrets
aws secretsmanager create-secret \
    --name "gremlin/${TEAM}/team_id" \
    --description "Gremlin Team ID for ${TEAM} team" \
    --secret-string "438c58ec-03db-47ac-8c58-ec03db67ac42" \
    --region "$REGION"

aws secretsmanager create-secret \
    --name "gremlin/${TEAM}/certificate" \
    --description "Gremlin Team Certificate for ${TEAM} team" \
    --secret-string "$(cat team-certificate.pem)" \
    --region "$REGION"

aws secretsmanager create-secret \
    --name "gremlin/${TEAM}/private_key" \
    --description "Gremlin Team Private Key for ${TEAM} team" \
    --secret-string "$(cat team-private-key.pem)" \
    --region "$REGION"
```

---

## Migration Path

### Week 1: Add Secrets Manager Support
- ✅ Create `lib/terraform.sh::fetch_gremlin_credentials()`
- ✅ Update `gremlin_install.sh` to check for Secrets Manager
- ✅ Keep backwards compatibility with env vars
- ✅ Test with explicit ARNs

### Week 2: Add Owner-Based Lookup
- ✅ Create `resolve_gremlin_credentials_from_owner()`
- ✅ Update workshop.sh to auto-detect owner secrets
- ✅ Document secret creation process
- ✅ Test with owner-based secrets

### Week 3: Deprecate Direct Credentials
- ⚠️ Add warnings for CLI args and env vars
- ⚠️ Update documentation to recommend Secrets Manager
- ⚠️ Provide migration guide

### Week 4: Remove Legacy Methods (Optional)
- ❌ Remove --gremlin-team-id, --gremlin-team-secret args
- ❌ Remove environment variable support
- ❌ Require Secrets Manager only

---

## Recommendation

**Implement Hybrid Approach (Option 3) with Owner-Based Default:**

1. **Default behavior:** Look up secrets by owner name
2. **Fallback:** Support explicit ARNs for Terraform
3. **Legacy support:** Keep env vars for backwards compatibility
4. **Cost:** Use Parameter Store instead of Secrets Manager ($0/month)

**User experience:**
```bash
# Simple case - just provide owner
./workshop.sh --subdomain alexs --owner alex.smith --enable-eks

# Advanced case - explicit ARNs
./workshop.sh --subdomain alexs --owner alex.smith \
    --gremlin-team-id-arn "arn:aws:..." \
    --enable-eks

# Legacy case - env vars still work
export GREMLIN_TEAM_ID="..."
./workshop.sh --subdomain alexs --owner alex.smith --enable-eks
```

**Cost:** $0/month with Parameter Store
**Security:** ✅ High
**Convenience:** ✅ Excellent
**Backwards Compatible:** ✅ Yes
