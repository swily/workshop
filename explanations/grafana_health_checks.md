# Grafana Health Check - Complete Guide

## What This Health Check Does

This health check monitors **Grafana's ability to query Prometheus alerts** through its datasource proxy. It verifies that:
1. Grafana is running and accessible
2. Grafana can connect to its Prometheus datasource
3. Prometheus has critical alerts firing (which means the health check will FAIL - this is intentional!)

---

## The Actual Configuration (From Live API)

### Health Check Details

**From API Response:**
```json
{
  "identifier": "dcc7a319-85d1-4a85-87a3-1985d1aa85e6",
  "name": "grafana-1759699218",
  "isContinuous": true,
  "isPrivateNetwork": false,
  "endpointConfiguration": {
    "url": "https://monitoring.gremlinpoc.com/api/datasources/proxy/1/api/v1/alerts",
    "method": "GET",
    "headers": {},
    "payload": null
  },
  "evaluationConfiguration": {
    "okStatusCodes": ["200"],
    "responseBodyEvaluation": {
      "op": "AND",
      "predicates": [{
        "comparator": "CONTAINS",
        "type": "String",
        "jpQuery": "data.alerts[*].labels.severity",
        "rValue": "critical"
      }]
    }
  },
  "teamExternalIntegration": {
    "type": "CUSTOM",
    "observabilityToolType": "CUSTOM",
    "name": "grafana-auth-working"
  },
  "pollingIntervalSeconds": 30,
  "category": "UNKNOWN"
}
```

---

## Understanding the Endpoint

### The URL Breakdown

```
https://monitoring.gremlinpoc.com/api/datasources/proxy/1/api/v1/alerts
```

**Breaking it down:**

| Part | What It Is | Why? |
|------|------------|------|
| `https://monitoring.gremlinpoc.com` | Grafana base URL | Your Grafana instance |
| `/api/datasources/proxy/1/` | Grafana datasource proxy | Routes request through Grafana to datasource #1 |
| `api/v1/alerts` | Prometheus alerts API | The actual Prometheus endpoint |

### What's Happening Behind the Scenes

```
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│   Gremlin    │ ------> │   Grafana    │ ------> │  Prometheus  │
│ Health Check │  HTTPS  │ Datasource   │  Query  │  Alert API   │
│              │         │   Proxy      │         │              │
└──────────────┘         └──────────────┘         └──────────────┘
      |                        |                         |
      |                        |                         |
      v                        v                         v
  Calls Grafana          Forwards to              Returns alerts
  every 30 sec           Prometheus DS            with severity labels
```

**Why use Grafana proxy instead of calling Prometheus directly?**
1. Tests that Grafana can reach Prometheus
2. Validates Grafana datasource configuration
3. Ensures the full observability stack is working (not just Prometheus)

---

## The Response: What Grafana Returns

### Example Response (No Critical Alerts)

```json
{
  "status": "success",
  "data": {
    "alerts": [
      {
        "labels": {
          "alertname": "HighMemoryUsage",
          "severity": "warning",
          "service": "frontend",
          "namespace": "otel-demo"
        },
        "annotations": {
          "summary": "Memory usage above 80%",
          "description": "Frontend service memory at 85%"
        },
        "state": "firing",
        "activeAt": "2025-10-21T10:00:00Z",
        "value": "85"
      },
      {
        "labels": {
          "alertname": "SlowResponse",
          "severity": "info",
          "service": "checkout",
          "namespace": "otel-demo"
        },
        "state": "firing",
        "activeAt": "2025-10-21T10:15:00Z"
      }
    ]
  }
}
```

**In this case:**
- Severity labels: `["warning", "info"]`
- Contains "critical"? **NO**
- Health check result: ✅ **PASS** (no critical alerts)

---

### Example Response (Critical Alert Firing)

```json
{
  "status": "success",
  "data": {
    "alerts": [
      {
        "labels": {
          "alertname": "ServiceDown",
          "severity": "critical",
          "service": "payment",
          "namespace": "otel-demo"
        },
        "annotations": {
          "summary": "Payment service is down",
          "description": "Payment service has been down for 5 minutes"
        },
        "state": "firing",
        "activeAt": "2025-10-21T10:30:00Z",
        "value": "0"
      },
      {
        "labels": {
          "alertname": "HighErrorRate",
          "severity": "critical",
          "service": "checkout",
          "namespace": "otel-demo"
        },
        "state": "firing",
        "activeAt": "2025-10-21T10:35:00Z"
      }
    ]
  }
}
```

**In this case:**
- Severity labels: `["critical", "critical"]`
- Contains "critical"? **YES**
- Health check result: ❌ **FAIL** (critical alerts detected!)

---

## How the Evaluation Works

### Step 1: Gremlin Makes the Request

```bash
GET https://monitoring.gremlinpoc.com/api/datasources/proxy/1/api/v1/alerts
```

Every 30 seconds, Gremlin calls this URL.

---

### Step 2: Check HTTP Status Code

```json
"okStatusCodes": ["200"]
```

**What this means:**
- If response is HTTP 200 → Continue to next check
- If response is HTTP 500, 404, etc. → ❌ **FAIL** (Grafana or Prometheus is broken)

---

### Step 3: Extract Alert Severity Labels

```json
"jpQuery": "data.alerts[*].labels.severity"
```

**This JSONPath query:**
1. Starts at `data` field
2. Goes into `alerts` array
3. For **every alert** (`[*]`)
4. Gets the `labels` object
5. Extracts the `severity` value

**Result:** An array of all severity values

**Example:**
```json
// Input (alerts array)
[
  {"labels": {"severity": "warning"}},
  {"labels": {"severity": "critical"}},
  {"labels": {"severity": "info"}}
]

// Output (jpQuery result)
["warning", "critical", "info"]
```

---

### Step 4: Check if Array Contains "critical"

```json
"comparator": "CONTAINS",
"rValue": "critical"
```

**What this means:**
- Does the array contain the string "critical"?
- If **YES** → ❌ **FAIL** (critical alert found!)
- If **NO** → ✅ **PASS** (no critical alerts)

---

### Complete Evaluation Logic

```
┌─────────────────────────────────────────────────────────────┐
│ Step 1: HTTP Status Check                                    │
│ ✅ Is status code 200?                                       │
│    YES → Continue                                            │
│    NO  → FAIL (Grafana/Prometheus unreachable)              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 2: Extract Severity Labels                              │
│ JSONPath: data.alerts[*].labels.severity                     │
│ Result: ["warning", "critical", "info"]                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 3: Check for "critical"                                 │
│ Does array CONTAIN "critical"?                               │
│    YES → FAIL (critical alerts detected!)                    │
│    NO  → PASS (no critical alerts)                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Why This Logic Makes Sense

### The "Inverted" Logic Explained

**At first glance, this seems backwards:**
- Finding "critical" = Health check **FAILS** ❌
- Not finding "critical" = Health check **PASSES** ✅

**But this is intentional!** Here's why:

1. **Purpose**: Monitor for critical issues in your application
2. **Healthy State**: No critical alerts = Everything is fine
3. **Unhealthy State**: Critical alerts exist = Something is broken

**Think of it like a smoke detector:**
- No smoke detected = ✅ All good
- Smoke detected = ❌ Alert! Fire!

---

## Testing the Health Check

### Test 1: Manual API Call

```bash
# Call the exact endpoint Gremlin uses
curl -s -u admin:admin123 \
  https://monitoring.gremlinpoc.com/api/datasources/proxy/1/api/v1/alerts | jq '.'
```

**Expected Response:**
```json
{
  "status": "success",
  "data": {
    "alerts": [...]
  }
}
```

---

### Test 2: Extract Severity Labels

```bash
# Get all severity labels (same as health check does)
curl -s -u admin:admin123 \
  https://monitoring.gremlinpoc.com/api/datasources/proxy/1/api/v1/alerts | \
  jq '.data.alerts[].labels.severity'
```

**Example Output:**
```
"warning"
"info"
"warning"
```

**Interpretation:**
- No "critical" in output → Health check will **PASS** ✅

---

### Test 3: Check for Critical Alerts

```bash
# Filter for only critical alerts
curl -s -u admin:admin123 \
  https://monitoring.gremlinpoc.com/api/datasources/proxy/1/api/v1/alerts | \
  jq '.data.alerts[] | select(.labels.severity == "critical")'
```

**If output is empty:**
- No critical alerts → Health check will **PASS** ✅

**If output shows alerts:**
- Critical alerts exist → Health check will **FAIL** ❌

---

## Viewing Health Check Status

### In Gremlin UI

1. Go to: https://app.gremlin.com/reliability/status-checks
2. Find: `grafana-1759699218`
3. Status will show:
   - ✅ **Healthy** - No critical alerts detected
   - ❌ **Unhealthy** - Critical alerts found OR Grafana unreachable

---

### Via API

```bash
# Get health check details
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "https://api.gremlin.com/v1/status-checks/dcc7a319-85d1-4a85-87a3-1985d1aa85e6?teamId=438c58ec-03db-47ac-8c58-ec03db67ac42"
```

---

## Authentication: How It Works

### The Integration

```json
"teamExternalIntegration": {
  "type": "CUSTOM",
  "observabilityToolType": "CUSTOM",
  "name": "grafana-auth-working"
}
```

**What this means:**
- Health check references an integration named `grafana-auth-working`
- Integration contains Grafana credentials (username/password)
- Credentials are stored securely in Gremlin
- Health check doesn't need to know the actual credentials

### Why Use Integration?

**Without Integration:**
```json
"headers": {
  "Authorization": "Basic YWRtaW46YWRtaW4xMjM="
}
```
- Credentials embedded in health check
- Hard to update if password changes
- Less secure

**With Integration:**
```json
"headers": {},
"teamExternalIntegration": {"name": "grafana-auth-working"}
```
- Credentials stored separately
- Update once, affects all health checks
- More secure

---

## Common Scenarios

### Scenario 1: Everything is Healthy

**What you see:**
- Gremlin UI: ✅ Healthy
- No critical alerts in Prometheus

**What's happening:**
- Grafana successfully queries Prometheus
- Prometheus returns alerts
- No alerts have `severity: critical`
- Health check passes

---

### Scenario 2: Critical Alert Firing

**What you see:**
- Gremlin UI: ❌ Unhealthy
- Prometheus shows critical alert

**What's happening:**
- Grafana successfully queries Prometheus
- Prometheus returns alerts including critical ones
- Health check detects "critical" in severity labels
- Health check fails (as intended!)

**Action:** Investigate and resolve the critical alert

---

### Scenario 3: Grafana is Down

**What you see:**
- Gremlin UI: ❌ Unhealthy
- HTTP error (500, 503, timeout)

**What's happening:**
- Gremlin cannot reach Grafana
- HTTP status is not 200
- Health check fails immediately

**Action:** Check Grafana service, pods, ingress

---

### Scenario 4: Grafana Can't Reach Prometheus

**What you see:**
- Gremlin UI: ❌ Unhealthy
- Grafana returns error response

**What's happening:**
- Grafana is up
- But Grafana's Prometheus datasource is misconfigured
- Grafana cannot proxy request to Prometheus
- Health check fails

**Action:** Check Grafana datasource configuration

---

## Troubleshooting

### Health Check Shows Unhealthy

**Step 1: Check if critical alerts are actually firing**
```bash
curl -s -u admin:admin123 \
  https://monitoring.gremlinpoc.com/api/datasources/proxy/1/api/v1/alerts | \
  jq '.data.alerts[] | select(.labels.severity == "critical") | .labels.alertname'
```

**If alerts are shown:**
- This is expected behavior!
- Health check is working correctly
- Resolve the underlying issue causing the critical alert

**If no alerts are shown:**
- Continue to Step 2

---

**Step 2: Check if Grafana is accessible**
```bash
curl -I -u admin:admin123 https://monitoring.gremlinpoc.com/api/datasources/proxy/1/api/v1/alerts
```

**Expected:** `HTTP/2 200`

**If you get 401 Unauthorized:**
- Check Grafana credentials in integration
- Update `grafana-auth-working` integration

**If you get 404 Not Found:**
- Check Grafana datasource ID (should be `1`)
- Verify datasource exists in Grafana

**If you get 500 or timeout:**
- Check Grafana pods: `kubectl get pods -n monitoring`
- Check Grafana logs: `kubectl logs -n monitoring deployment/grafana`

---

**Step 3: Verify Prometheus is reachable from Grafana**
```bash
# Check Grafana datasource configuration
kubectl exec -n monitoring deployment/grafana -- \
  curl -s http://prometheus:9090/api/v1/alerts
```

**Expected:** JSON response with alerts

**If fails:**
- Check Prometheus service: `kubectl get svc -n monitoring prometheus`
- Check network policies
- Verify datasource URL in Grafana UI

---

### Health Check Not Appearing in UI

**Check if health check exists:**
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "https://api.gremlin.com/v1/status-checks?teamId=438c58ec-03db-47ac-8c58-ec03db67ac42" | \
  jq '.[] | select(.name | startswith("grafana"))'
```

**If not found:**
- Health check was not created
- Run healthchecks.sh script again

---

## Creating the Health Check

### Using the Script (Recommended)

```bash
cd /Users/seanwiley/workshop/build_scripts/demo

# Set credentials
export GREMLIN_TEAM_ID="438c58ec-03db-47ac-8c58-ec03db67ac42"
export GREMLIN_API_KEY="your-api-key-here"

# Create Grafana health check
./healthchecks.sh \
    --subdomain yourname \
    --cluster-name yourname-eks \
    --platform grafana
```

---

### Manual API Call

**Step 1: Create Integration (if not exists)**
```bash
curl -X POST \
  "https://api.gremlin.com/v1/external-integrations/status-check?teamId=438c58ec-03db-47ac-8c58-ec03db67ac42&type=CUSTOM" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "grafana-auth-working",
    "description": "Grafana authorization for monitoring alerts",
    "type": "CUSTOM",
    "privateNetwork": false,
    "lastAuthenticationStatus": "AUTHENTICATED",
    "url": "https://monitoring.gremlinpoc.com",
    "configuration": {
      "auth": {
        "type": "BASIC",
        "username": "admin",
        "password": "admin123"
      }
    }
  }'
```

**Step 2: Create Health Check**
```bash
curl -X POST \
  "https://api.gremlin.com/v1/status-checks?teamId=438c58ec-03db-47ac-8c58-ec03db67ac42" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "grafana-alerts-check",
    "endpointType": "http",
    "isContinuous": true,
    "endpointConfiguration": {
      "url": "https://monitoring.gremlinpoc.com/api/datasources/proxy/1/api/v1/alerts",
      "method": "GET",
      "headers": {}
    },
    "evaluationConfiguration": {
      "okStatusCodes": ["200"],
      "responseBodyEvaluation": {
        "op": "AND",
        "predicates": [{
          "comparator": "CONTAINS",
          "type": "String",
          "jpQuery": "data.alerts[*].labels.severity",
          "rValue": "critical"
        }]
      }
    },
    "teamExternalIntegration": {
      "observabilityToolType": "CUSTOM",
      "name": "grafana-auth-working"
    },
    "pollingIntervalSeconds": 30
  }'
```

---

## Summary

### What This Health Check Monitors

✅ **Grafana is running and accessible**  
✅ **Grafana can connect to Prometheus datasource**  
✅ **Prometheus is returning alert data**  
✅ **Critical alerts are detected** (health check fails when found)

### Key Configuration Details

| Setting | Value | Purpose |
|---------|-------|---------|
| **URL** | `https://monitoring.gremlinpoc.com/api/datasources/proxy/1/api/v1/alerts` | Grafana proxy to Prometheus alerts |
| **Method** | `GET` | HTTP GET request |
| **Polling** | 30 seconds | Check every 30 seconds |
| **Status Codes** | `[200]` | Only 200 is OK |
| **JSONPath** | `data.alerts[*].labels.severity` | Extract all severity labels |
| **Comparator** | `CONTAINS` | Check if array contains value |
| **Target Value** | `"critical"` | Look for critical alerts |
| **Logic** | Contains "critical" = FAIL | Alert when critical issues found |

### Remember

🔴 **Health check FAILS when critical alerts exist** - This is correct behavior!  
🟢 **Health check PASSES when no critical alerts** - Everything is healthy  
⚪ **Health check FAILS on HTTP errors** - Grafana or Prometheus is down

---

**Last Updated:** 2025-10-21  
**API Version:** v1  
**Health Check ID:** `dcc7a319-85d1-4a85-87a3-1985d1aa85e6`
