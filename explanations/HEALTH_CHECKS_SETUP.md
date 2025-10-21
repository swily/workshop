# Health Checks Setup - Complete Configuration

## Summary of Changes (2025-10-05)

### ✅ Completed Actions:

1. **Updated cluster-state.json** with correct consolidated endpoints
2. **Removed redundant script** (`monitoring/create_prometheus_grafana_checks.sh`)
3. **Verified healthchecks.sh** is correctly configured
4. **Confirmed Grafana datasource proxy path** is properly set

---

## Current Configuration

### Endpoints (cluster-state.json)

```json
{
  "endpoints": {
    "frontend": "https://demo-frontend.gremlinpoc.com",
    "grafana_monitoring": "https://monitoring.gremlinpoc.com",
    "prometheus": "https://monitoring.gremlinpoc.com/prometheus"
  }
}
```

### Health Check Script

**Use:** `/Users/seanwiley/workshop/build_scripts/demo/healthchecks.sh`

**Capabilities:**
- ✅ Prometheus alerts monitoring
- ✅ Grafana alerts monitoring (via datasource proxy)
- ✅ Dynatrace integration
- ✅ New Relic integration
- ✅ Dynamic endpoint discovery
- ✅ DNS readiness validation
- ✅ Service cleanup

---

## Health Check Endpoints

### Prometheus
- **URL:** `https://monitoring.gremlinpoc.com/prometheus/api/v1/alerts`
- **Auth:** None required
- **Evaluation:** Checks for critical severity alerts
- **Response:** `{"status":"success","data":{"alerts":[...]}}`

### Grafana
- **URL:** `https://monitoring.gremlinpoc.com/api/datasources/proxy/1/api/v1/alerts`
- **Auth:** Basic Auth (admin:admin123)
- **Evaluation:** Checks for critical severity alerts via Prometheus datasource proxy
- **Response:** Same as Prometheus (proxied through Grafana)

---

## Usage

### Create Health Checks for Both Platforms

```bash
cd /Users/seanwiley/workshop/build_scripts/demo

# Set Gremlin credentials
export GREMLIN_TEAM_ID="438c58ec-03db-47ac-8c58-ec03db67ac42"
export GREMLIN_API_KEY="14bdb4c5b41e93955d4b0a32f79ddf93bac61cccd4ce59ed29b937fba2b970f7"

# Create health checks for Prometheus and Grafana
./healthchecks.sh --platform prometheus --platform grafana
```

### Other Options

```bash
# Create for all platforms
./healthchecks.sh --platform all

# Dry run (see what would be created)
./healthchecks.sh --platform prometheus --platform grafana --dry-run

# Cleanup old services first
./healthchecks.sh --cleanup-services --platform prometheus --platform grafana

# Validate existing health checks
./healthchecks.sh --validate-only
```

---

## Architecture

### Monitoring Ingress (monitoring.gremlinpoc.com)

**Paths:**
- `/prometheus/*` → Prometheus (kube-prometheus-stack)
- `/*` → Grafana (kube-prometheus-stack)

**Features:**
- HTTPS with ACM certificate
- ALB: `k8s-monitori-monitori-3823d4b4e3-1273204937.us-east-2.elb.amazonaws.com`
- Namespace: `monitoring`

### Demo Ingress (demo-frontend.gremlinpoc.com)

**Paths:**
- `/*` → OpenTelemetry Demo Frontend

**Features:**
- HTTPS with ACM certificate
- ALB: `k8s-oteldemo-consolid-c8b2fb6f86-330028353.us-east-2.elb.amazonaws.com`
- Namespace: `otel-demo`

---

## Gremlin Integration Details

### Prometheus Integration
- **Name:** `prometheus-auth-working`
- **Type:** CUSTOM
- **Private Network:** false
- **Polling:** 30 seconds

### Grafana Integration
- **Name:** `grafana-auth-working`
- **Type:** CUSTOM
- **Private Network:** false
- **Auth:** Basic Auth (embedded in integration)
- **Polling:** 30 seconds

### Health Check Evaluation

Both health checks use the same evaluation logic:

```json
{
  "okStatusCodes": [200],
  "responseBodyEvaluation": {
    "op": "AND",
    "predicates": [{
      "comparator": "CONTAINS",
      "type": "String",
      "jpQuery": "data.alerts[*].labels.severity",
      "rValue": "critical"
    }]
  }
}
```

This checks that:
1. HTTP 200 response
2. Response contains alerts with `severity: critical` label

---

## Troubleshooting

### Health Check Not Working

1. **Verify endpoints are accessible:**
   ```bash
   curl -s https://monitoring.gremlinpoc.com/prometheus/api/v1/alerts | jq '.status'
   # Should return: "success"
   
   curl -s -u admin:admin123 https://monitoring.gremlinpoc.com/api/datasources/proxy/1/api/v1/alerts | jq '.status'
   # Should return: "success"
   ```

2. **Check cluster-state.json has correct endpoints:**
   ```bash
   cat /Users/seanwiley/workshop/cluster-state.json | jq '.endpoints'
   ```

3. **Verify Gremlin credentials:**
   ```bash
   echo $GREMLIN_TEAM_ID
   echo $GREMLIN_API_KEY
   ```

4. **Check existing health checks:**
   ```bash
   curl -H "Authorization: Key $GREMLIN_API_KEY" \
     "https://api.gremlin.com/v1/status-checks?teamId=$GREMLIN_TEAM_ID" | jq '.[].name'
   ```

### DNS Issues

If DNS is not resolving:

```bash
# Check DNS records
dig demo-frontend.gremlinpoc.com
dig monitoring.gremlinpoc.com

# Wait for DNS propagation (script does this automatically)
./healthchecks.sh --dns-wait 600 --platform prometheus --platform grafana
```

---

## Files Reference

### Primary Script
- `/Users/seanwiley/workshop/build_scripts/demo/healthchecks.sh`

### Configuration
- `/Users/seanwiley/workshop/cluster-state.json`

### Documentation
- `/Users/seanwiley/workshop/HealthChecksExplained.md`
- `/Users/seanwiley/workshop/healthchecknext.txt`

### Deprecated (Removed)
- ~~`/Users/seanwiley/workshop/monitoring/create_prometheus_grafana_checks.sh`~~ (deleted - redundant)

---

## Next Steps

1. Run the health check creation script:
   ```bash
   cd /Users/seanwiley/workshop/build_scripts/demo
   ./healthchecks.sh --platform prometheus --platform grafana
   ```

2. Verify in Gremlin UI:
   - https://app.gremlin.com/reliability/status-checks

3. Monitor health check status and alerts

---

**Last Updated:** 2025-10-05T21:14:53Z
