# Chronosphere Integration Plan for Gremlin Health Checks

## Executive Summary

This document outlines a comprehensive plan to integrate Chronosphere monitoring with Gremlin health checks, similar to our existing Prometheus and Grafana integrations. Chronosphere provides a unified observability platform with monitors that can be queried via REST API to detect critical alerts.

---

## What is Chronosphere?

**Chronosphere** is a cloud-native observability platform that provides:
- **Unified monitoring** for metrics, logs, and traces
- **Advanced alerting** via monitors with customizable thresholds
- **PromQL compatibility** for querying metrics
- **GraphiteQL and LogQL** support for diverse data sources
- **REST API** for programmatic access to monitors and alerts

### Key Differences from Prometheus/Grafana

| Feature | Prometheus/Grafana | Chronosphere |
|---------|-------------------|--------------|
| **Architecture** | Self-hosted, separate tools | Cloud-native SaaS platform |
| **API Endpoint** | `/api/v1/alerts` | `/api/v1/config/monitors` |
| **Authentication** | Basic Auth or none | API Token required |
| **Alert Model** | Firing alerts list | Monitor state with signals |
| **Pagination** | Not required | Required for large result sets |
| **Query Language** | PromQL | PromQL, GraphiteQL, LogQL |

---

## Integration Architecture

### Current State (Prometheus/Grafana)

```
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│   Gremlin    │ ------> │  Prometheus  │         │   Grafana    │
│ Health Check │  HTTPS  │  /api/v1/    │         │  Datasource  │
│              │         │  alerts      │         │    Proxy     │
└──────────────┘         └──────────────┘         └──────────────┘
      |                         |                         |
      v                         v                         v
  Checks for              Returns alerts           Proxies to
  "critical"              with severity            Prometheus
  severity                labels                   alerts API
```

### Proposed State (with Chronosphere)

```
┌──────────────┐         ┌─────────────────────────────────────┐
│   Gremlin    │ ------> │      Chronosphere Platform          │
│ Health Check │  HTTPS  │  https://{domain}.chronosphere.io   │
│              │         │  /api/v1/config/monitors            │
└──────────────┘         └─────────────────────────────────────┘
      |                                  |
      v                                  v
  Checks monitor                  Returns monitors with
  state for                       state: ALERTING, CRITICAL
  critical alerts                 severity levels
```

---

## API Analysis

### Chronosphere Monitors API

**Endpoint:** `GET /api/v1/config/monitors`

**Base URL:** `https://{CHRONOSPHERE_DOMAIN}.chronosphere.io`

**Authentication:**
```bash
curl -H "API-Token: ${CHRONOSPHERE_API_TOKEN}" \
  "https://${CHRONOSPHERE_DOMAIN}.chronosphere.io/api/v1/config/monitors"
```

### Response Structure

```json
{
  "page": {
    "next_token": "abc123"
  },
  "monitors": [
    {
      "slug": "high-error-rate-checkout",
      "name": "High Error Rate - Checkout Service",
      "owner": {
        "slug": "platform-team",
        "name": "Platform Team"
      },
      "query": {
        "prometheus_expr": "rate(http_requests_total{status=~\"5..\"}[5m]) > 0.05"
      },
      "series_conditions": {
        "conditions": [
          {
            "severity": "CRITICAL",
            "sustain": "5m",
            "op": "GT",
            "value": 0.1
          },
          {
            "severity": "WARN",
            "sustain": "2m",
            "op": "GT",
            "value": 0.05
          }
        ]
      },
      "notification_policy": {
        "slug": "critical-alerts-policy"
      },
      "labels": {
        "service": "checkout",
        "team": "platform",
        "environment": "production"
      },
      "created_at": "2025-10-01T10:00:00Z",
      "updated_at": "2025-10-15T14:30:00Z"
    }
  ]
}
```

### Key Fields for Health Checks

| Field | Purpose | Example Value |
|-------|---------|---------------|
| `slug` | Unique monitor identifier | `"high-error-rate-checkout"` |
| `name` | Human-readable name | `"High Error Rate - Checkout Service"` |
| `series_conditions.conditions[].severity` | Alert severity level | `"CRITICAL"`, `"WARN"` |
| `labels` | Categorization metadata | `{"service": "checkout"}` |
| `notification_policy` | Alert routing | `{"slug": "critical-alerts-policy"}` |

### Monitor States

Chronosphere monitors can be in the following states:
- **OK** - No alerts firing
- **WARN** - Warning threshold exceeded
- **CRITICAL** - Critical threshold exceeded
- **ALERTING** - Any alert firing (WARN or CRITICAL)
- **MUTED** - Alerts suppressed

---

## Health Check Strategy

### Option 1: Monitor State Query (Recommended)

**Approach:** Query monitors and check if any are in CRITICAL state

**Endpoint:** `GET /api/v1/config/monitors?state=CRITICAL`

**Evaluation Logic:**
```json
{
  "okStatusCodes": [200],
  "responseBodyEvaluation": {
    "op": "AND",
    "predicates": [{
      "comparator": "GREATER_THAN",
      "type": "Number",
      "jpQuery": "monitors.length",
      "rValue": "0"
    }]
  }
}
```

**Interpretation:**
- If `monitors.length > 0` → Critical monitors exist → Health check **FAILS** ❌
- If `monitors.length == 0` → No critical monitors → Health check **PASSES** ✅

---

### Option 2: Specific Monitor Query

**Approach:** Query a specific monitor by slug and check its state

**Endpoint:** `GET /api/v1/config/monitors/{slug}`

**Evaluation Logic:**
```json
{
  "okStatusCodes": [200],
  "responseBodyEvaluation": {
    "op": "AND",
    "predicates": [{
      "comparator": "CONTAINS",
      "type": "String",
      "jpQuery": "monitor.series_conditions.conditions[*].severity",
      "rValue": "CRITICAL"
    }]
  }
}
```

---

### Option 3: Label-Based Filtering

**Approach:** Query monitors with specific labels (e.g., service, environment)

**Endpoint:** `GET /api/v1/config/monitors?labels.service=checkout&labels.environment=production`

**Use Case:** Monitor specific services or environments

---

## Implementation Plan

### Phase 1: Research & Validation (1-2 days)

**Tasks:**
1. ✅ Review Chronosphere API documentation
2. ⬜ Obtain Chronosphere trial account or access
3. ⬜ Generate API token for testing
4. ⬜ Test API endpoints manually with curl
5. ⬜ Validate response structure matches documentation
6. ⬜ Identify pagination requirements
7. ⬜ Document authentication flow

**Deliverables:**
- API access credentials
- Tested curl commands
- Response samples
- Authentication documentation

---

### Phase 2: Script Development (2-3 days)

**Tasks:**
1. ⬜ Create `create_chronosphere_health_checks()` function
2. ⬜ Implement Chronosphere authentication integration
3. ⬜ Add pagination support for monitor listing
4. ⬜ Implement JSONPath query for critical monitors
5. ⬜ Add error handling and validation
6. ⬜ Create dry-run mode
7. ⬜ Add logging and status output

**Files to Modify:**
- `build_scripts/demo/healthchecks.sh` - Add Chronosphere platform
- `lib/monitoring.sh` - Add Chronosphere setup function
- `config/monitoring/chronosphere-values.yaml` - Configuration template

**New Functions:**
```bash
create_chronosphere_health_checks() {
    local platform="chronosphere"
    echo -e "${PURPLE}🔍 Creating Chronosphere health checks...${NC}"
    
    # Validate Chronosphere credentials
    if [[ -z "$CHRONOSPHERE_API_TOKEN" ]]; then
        log_error "CHRONOSPHERE_API_TOKEN not set"
        return 1
    fi
    
    if [[ -z "$CHRONOSPHERE_DOMAIN" ]]; then
        log_error "CHRONOSPHERE_DOMAIN not set"
        return 1
    fi
    
    # Create Chronosphere authorization
    local integration_payload=$(cat << EOF
{
  "name": "chronosphere-auth-working",
  "description": "Chronosphere authorization for monitoring critical alerts",
  "type": "CUSTOM",
  "privateNetwork": false,
  "lastAuthenticationStatus": "AUTHENTICATED",
  "url": "https://${CHRONOSPHERE_DOMAIN}.chronosphere.io",
  "headers": {
    "API-Token": "${CHRONOSPHERE_API_TOKEN}"
  }
}
EOF
)
    
    # Create integration
    create_gremlin_integration "$integration_payload"
    
    # Create health check
    local check_name="chronosphere-$(date +%s)"
    local health_check_payload=$(cat << EOF
{
  "name": "$check_name",
  "endpointType": "http",
  "isContinuous": true,
  "endpointConfiguration": {
    "url": "https://${CHRONOSPHERE_DOMAIN}.chronosphere.io/api/v1/config/monitors",
    "method": "GET",
    "headers": {}
  },
  "evaluationConfiguration": {
    "okStatusCodes": [200],
    "responseBodyEvaluation": {
      "op": "AND",
      "predicates": [{
        "comparator": "CONTAINS",
        "type": "String",
        "jpQuery": "monitors[*].series_conditions.conditions[*].severity",
        "rValue": "CRITICAL"
      }]
    }
  },
  "teamExternalIntegration": {
    "observabilityToolType": "CUSTOM",
    "name": "chronosphere-auth-working"
  },
  "pollingIntervalSeconds": 30
}
EOF
)
    
    # Create health check via Gremlin API
    create_gremlin_health_check "$health_check_payload"
    
    log_success "Chronosphere health check created successfully"
}
```

---

### Phase 3: Testing & Validation (2 days)

**Test Cases:**

1. **Authentication Test**
   ```bash
   # Verify API token works
   curl -H "API-Token: ${CHRONOSPHERE_API_TOKEN}" \
     "https://${CHRONOSPHERE_DOMAIN}.chronosphere.io/api/v1/config/monitors"
   ```

2. **Monitor Query Test**
   ```bash
   # Get all monitors
   curl -H "API-Token: ${CHRONOSPHERE_API_TOKEN}" \
     "https://${CHRONOSPHERE_DOMAIN}.chronosphere.io/api/v1/config/monitors" | jq '.'
   ```

3. **Critical Monitor Test**
   ```bash
   # Filter for critical monitors
   curl -H "API-Token: ${CHRONOSPHERE_API_TOKEN}" \
     "https://${CHRONOSPHERE_DOMAIN}.chronosphere.io/api/v1/config/monitors" | \
     jq '.monitors[] | select(.series_conditions.conditions[].severity == "CRITICAL")'
   ```

4. **Pagination Test**
   ```bash
   # Test pagination with page token
   curl -H "API-Token: ${CHRONOSPHERE_API_TOKEN}" \
     "https://${CHRONOSPHERE_DOMAIN}.chronosphere.io/api/v1/config/monitors?page.token=abc123"
   ```

5. **Health Check Creation Test**
   ```bash
   # Create health check via script
   export CHRONOSPHERE_API_TOKEN="your-token"
   export CHRONOSPHERE_DOMAIN="your-domain"
   
   ./healthchecks.sh --platform chronosphere --subdomain test --dry-run
   ```

6. **End-to-End Test**
   ```bash
   # Full workflow test
   ./healthchecks.sh --platform chronosphere --subdomain test
   
   # Verify in Gremlin UI
   # https://app.gremlin.com/reliability/status-checks
   ```

**Validation Checklist:**
- ⬜ API authentication succeeds
- ⬜ Monitor list retrieval works
- ⬜ Pagination handles multiple pages
- ⬜ JSONPath query extracts severity correctly
- ⬜ Health check appears in Gremlin UI
- ⬜ Health check status updates correctly
- ⬜ Critical alerts trigger health check failure
- ⬜ No critical alerts result in health check pass

---

### Phase 4: Documentation (1 day)

**Documents to Create:**

1. **Chronosphere Health Checks Guide** (`explanations/chronosphere_health_checks.md`)
   - What Chronosphere monitors are
   - How the integration works
   - API endpoint details
   - Response structure explanation
   - JSONPath query breakdown
   - Troubleshooting guide

2. **Integration README** (`monitoring/chronosphere/README.md`)
   - Prerequisites
   - Setup instructions
   - Configuration options
   - Example usage
   - Common issues

3. **Update Existing Docs**
   - `build_scripts/demo/healthchecks.sh` - Add Chronosphere to help text
   - `WORKFLOW_ANALYSIS.md` - Add Chronosphere to platform list
   - `TESTING_CHECKLIST.md` - Add Chronosphere validation steps

---

### Phase 5: Integration & Deployment (1 day)

**Tasks:**
1. ⬜ Merge Chronosphere functions into `healthchecks.sh`
2. ⬜ Update `lib/monitoring.sh` to support Chronosphere
3. ⬜ Add Chronosphere to `--platform` options
4. ⬜ Update workshop.sh to include Chronosphere
5. ⬜ Add environment variable validation
6. ⬜ Create example configuration files
7. ⬜ Test full deployment workflow

**Environment Variables:**
```bash
export CHRONOSPHERE_API_TOKEN="your-api-token-here"
export CHRONOSPHERE_DOMAIN="your-company"  # e.g., "acme" for acme.chronosphere.io
export GREMLIN_TEAM_ID="438c58ec-03db-47ac-8c58-ec03db67ac42"
export GREMLIN_API_KEY="your-gremlin-api-key"
```

---

## Technical Considerations

### 1. Pagination Handling

**Challenge:** Chronosphere API uses pagination for large result sets

**Solution:**
```bash
fetch_all_monitors() {
    local all_monitors="[]"
    local next_token=""
    
    while true; do
        local url="https://${CHRONOSPHERE_DOMAIN}.chronosphere.io/api/v1/config/monitors"
        if [[ -n "$next_token" ]]; then
            url="${url}?page.token=${next_token}"
        fi
        
        local response=$(curl -s -H "API-Token: ${CHRONOSPHERE_API_TOKEN}" "$url")
        
        # Append monitors to result
        all_monitors=$(echo "$all_monitors $response" | jq -s '.[0] + .[1].monitors')
        
        # Check for next page
        next_token=$(echo "$response" | jq -r '.page.next_token // empty')
        
        if [[ -z "$next_token" ]]; then
            break
        fi
    done
    
    echo "$all_monitors"
}
```

---

### 2. Authentication Security

**Challenge:** API tokens are sensitive credentials

**Solution:**
- Store in AWS Secrets Manager (like Gremlin credentials)
- Fetch dynamically during deployment
- Never commit to git
- Use environment variables for local testing

**Implementation:**
```bash
fetch_chronosphere_credentials() {
    log_info "Fetching Chronosphere credentials from Secrets Manager..."
    
    CHRONOSPHERE_API_TOKEN=$(aws secretsmanager get-secret-value \
        --secret-id "${OWNER}/chronosphere_api_token" \
        --region "$AWS_REGION" \
        --query 'SecretString' \
        --output text 2>/dev/null)
    
    CHRONOSPHERE_DOMAIN=$(aws secretsmanager get-secret-value \
        --secret-id "${OWNER}/chronosphere_domain" \
        --region "$AWS_REGION" \
        --query 'SecretString' \
        --output text 2>/dev/null)
    
    if [[ -z "$CHRONOSPHERE_API_TOKEN" ]] || [[ -z "$CHRONOSPHERE_DOMAIN" ]]; then
        log_error "Failed to fetch Chronosphere credentials"
        return 1
    fi
    
    export CHRONOSPHERE_API_TOKEN
    export CHRONOSPHERE_DOMAIN
    
    log_success "Chronosphere credentials fetched successfully"
}
```

---

### 3. Monitor State vs. Alert State

**Challenge:** Chronosphere monitors have multiple severity levels

**Solution:** Support multiple evaluation strategies

**Option A: Check for ANY critical monitors**
```json
{
  "jpQuery": "monitors[*].series_conditions.conditions[*].severity",
  "comparator": "CONTAINS",
  "rValue": "CRITICAL"
}
```

**Option B: Count critical monitors**
```json
{
  "jpQuery": "monitors[?(@.series_conditions.conditions[?(@.severity=='CRITICAL')])].length",
  "comparator": "GREATER_THAN",
  "rValue": "0"
}
```

**Option C: Check specific monitor by slug**
```json
{
  "jpQuery": "monitors[?(@.slug=='high-error-rate')].series_conditions.conditions[*].severity",
  "comparator": "CONTAINS",
  "rValue": "CRITICAL"
}
```

---

### 4. Rate Limiting

**Challenge:** API rate limits may apply

**Solution:**
- Use appropriate polling intervals (30-60 seconds)
- Implement exponential backoff on errors
- Cache results when possible
- Monitor API usage

---

## Comparison with Existing Integrations

### Prometheus Integration

**Similarities:**
- Both query for critical alerts
- Both use JSONPath for evaluation
- Both require authentication

**Differences:**
- Prometheus: `/api/v1/alerts` endpoint
- Chronosphere: `/api/v1/config/monitors` endpoint
- Prometheus: No pagination
- Chronosphere: Pagination required
- Prometheus: Simple alert list
- Chronosphere: Rich monitor metadata

---

### Grafana Integration

**Similarities:**
- Both proxy to underlying data source
- Both check for critical severity
- Both use datasource authentication

**Differences:**
- Grafana: Proxies to Prometheus
- Chronosphere: Direct API access
- Grafana: Basic Auth
- Chronosphere: API Token
- Grafana: Datasource proxy path
- Chronosphere: Direct REST API

---

## Prerequisites

### Required Access

1. **Chronosphere Account**
   - Active Chronosphere subscription
   - Admin or API access permissions
   - Domain name (e.g., `acme.chronosphere.io`)

2. **API Token**
   - Generated from Chronosphere UI
   - Permissions: Read monitors
   - Stored securely in AWS Secrets Manager

3. **Gremlin Account**
   - Team ID: `438c58ec-03db-47ac-8c58-ec03db67ac42`
   - API access for health check creation

4. **AWS Resources**
   - Secrets Manager for credential storage
   - IAM permissions for secret access

---

### Required Configuration

1. **Environment Variables**
   ```bash
   CHRONOSPHERE_API_TOKEN="your-token"
   CHRONOSPHERE_DOMAIN="your-domain"
   GREMLIN_TEAM_ID="438c58ec-03db-47ac-8c58-ec03db67ac42"
   GREMLIN_API_KEY="your-api-key"
   ```

2. **Secrets Manager Entries**
   ```bash
   # Create secrets
   aws secretsmanager create-secret \
       --name "${OWNER}/chronosphere_api_token" \
       --secret-string "your-api-token" \
       --region us-east-2
   
   aws secretsmanager create-secret \
       --name "${OWNER}/chronosphere_domain" \
       --secret-string "your-domain" \
       --region us-east-2
   ```

3. **Chronosphere Monitors**
   - At least one monitor configured
   - Monitors with CRITICAL severity thresholds
   - Proper labels for filtering (optional)

---

## Usage Examples

### Create Chronosphere Health Check

```bash
# Set credentials
export CHRONOSPHERE_API_TOKEN="your-token"
export CHRONOSPHERE_DOMAIN="acme"
export GREMLIN_TEAM_ID="438c58ec-03db-47ac-8c58-ec03db67ac42"
export GREMLIN_API_KEY="your-api-key"

# Create health check
./build_scripts/demo/healthchecks.sh \
    --platform chronosphere \
    --subdomain alexs \
    --cluster-name alexs-eks
```

### Create All Platform Health Checks

```bash
# Create for Prometheus, Grafana, and Chronosphere
./build_scripts/demo/healthchecks.sh \
    --platform all \
    --subdomain alexs \
    --cluster-name alexs-eks
```

### Dry Run

```bash
# Preview what would be created
./build_scripts/demo/healthchecks.sh \
    --platform chronosphere \
    --subdomain alexs \
    --dry-run
```

### Cleanup Old Health Checks

```bash
# Remove old health checks before creating new ones
./build_scripts/demo/healthchecks.sh \
    --platform chronosphere \
    --subdomain alexs \
    --cleanup-services
```

---

## Verification

### 1. Test API Access

```bash
curl -H "API-Token: ${CHRONOSPHERE_API_TOKEN}" \
  "https://${CHRONOSPHERE_DOMAIN}.chronosphere.io/api/v1/config/monitors" | jq '.'
```

**Expected:** JSON response with monitors array

---

### 2. Check for Critical Monitors

```bash
curl -H "API-Token: ${CHRONOSPHERE_API_TOKEN}" \
  "https://${CHRONOSPHERE_DOMAIN}.chronosphere.io/api/v1/config/monitors" | \
  jq '.monitors[] | select(.series_conditions.conditions[].severity == "CRITICAL")'
```

**Expected:** List of monitors with CRITICAL severity

---

### 3. Verify Health Check in Gremlin UI

1. Go to: https://app.gremlin.com/reliability/status-checks
2. Find: `chronosphere-XXXXXXXXXX`
3. Status should show:
   - ✅ **Healthy** - No critical monitors
   - ❌ **Unhealthy** - Critical monitors detected

---

### 4. Test Health Check Evaluation

```bash
# Manually trigger evaluation
curl -H "Authorization: Key ${GREMLIN_API_KEY}" \
  "https://api.gremlin.com/v1/status-checks?teamId=${GREMLIN_TEAM_ID}" | \
  jq '.[] | select(.name | startswith("chronosphere"))'
```

---

## Troubleshooting

### Issue: Authentication Failed

**Symptoms:**
- HTTP 401 Unauthorized
- "Invalid API token" error

**Solutions:**
1. Verify API token is correct
2. Check token hasn't expired
3. Ensure token has read permissions
4. Regenerate token in Chronosphere UI

---

### Issue: No Monitors Returned

**Symptoms:**
- Empty monitors array
- `monitors.length == 0`

**Solutions:**
1. Verify monitors exist in Chronosphere
2. Check API token permissions
3. Test with Chronosphere UI
4. Verify domain name is correct

---

### Issue: Pagination Not Working

**Symptoms:**
- Only first page of results
- Missing monitors

**Solutions:**
1. Implement pagination loop
2. Check `page.next_token` field
3. Follow pagination example
4. Test with large monitor count

---

### Issue: Health Check Always Fails

**Symptoms:**
- Health check shows unhealthy
- No critical monitors visible in UI

**Solutions:**
1. Check JSONPath query syntax
2. Verify response structure
3. Test query with jq locally
4. Review evaluation logic

---

## Cost Considerations

### Chronosphere Costs

- **API Calls:** Included in subscription (check rate limits)
- **Monitor Count:** May affect pricing tier
- **Data Retention:** Based on plan

### Gremlin Costs

- **Health Checks:** Included in Gremlin subscription
- **Polling Frequency:** 30-second intervals (standard)
- **API Calls:** Minimal impact

### AWS Costs

- **Secrets Manager:** $0.40/secret/month + $0.05/10,000 API calls
- **Minimal:** ~$1/month for 2 secrets

---

## Timeline Summary

| Phase | Duration | Effort |
|-------|----------|--------|
| Research & Validation | 1-2 days | 8-16 hours |
| Script Development | 2-3 days | 16-24 hours |
| Testing & Validation | 2 days | 16 hours |
| Documentation | 1 day | 8 hours |
| Integration & Deployment | 1 day | 8 hours |
| **Total** | **7-9 days** | **56-72 hours** |

---

## Success Criteria

✅ **Phase 1 Complete:**
- Chronosphere API access verified
- Authentication working
- Response structure documented

✅ **Phase 2 Complete:**
- Script functions implemented
- Pagination support added
- Error handling robust

✅ **Phase 3 Complete:**
- All test cases passing
- Health check appears in Gremlin UI
- Critical alerts trigger failures

✅ **Phase 4 Complete:**
- Documentation comprehensive
- Examples tested
- Troubleshooting guide complete

✅ **Phase 5 Complete:**
- Integration merged
- Full workflow tested
- Production-ready

---

## Next Steps

### Immediate Actions

1. **Obtain Chronosphere Access**
   - Request trial account or use existing
   - Generate API token
   - Document domain name

2. **Test API Manually**
   - Run curl commands
   - Validate responses
   - Test pagination

3. **Create Proof of Concept**
   - Implement basic health check
   - Test with Gremlin
   - Validate evaluation logic

### Future Enhancements

1. **Advanced Filtering**
   - Filter by labels
   - Filter by owner/team
   - Filter by notification policy

2. **Multiple Health Checks**
   - One per service
   - One per environment
   - One per severity level

3. **Custom Evaluation**
   - Count monitors by severity
   - Check specific monitor slugs
   - Aggregate across teams

4. **Alerting Integration**
   - Gremlin alerts on health check failures
   - Slack/PagerDuty notifications
   - Custom webhooks

---

## References

- **Chronosphere API Docs:** https://docs.chronosphere.io/tooling/api-info
- **Monitor Documentation:** https://docs.chronosphere.io/alerts/monitors
- **Pagination Guide:** https://docs.chronosphere.io/tooling/api-info/pagination
- **Gremlin Health Checks:** https://www.gremlin.com/docs/reliability-management/health-checks
- **Our Prometheus Guide:** `/explanations/grafana_health_checks.md`

---

**Last Updated:** 2025-10-21  
**Author:** Workshop Automation Team  
**Version:** 1.0 (Planning Phase)
