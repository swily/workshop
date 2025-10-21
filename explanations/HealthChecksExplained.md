# Gremlin Health Checks - Complete Implementation Guide

This document consolidates all findings from extensive testing and provides the definitive guide for creating Gremlin health checks with authentication.

## Overview

Gremlin health checks monitor external endpoints and can authenticate using two approaches:
1. **Direct Authentication**: Credentials embedded in health check headers
2. **Integration Authentication**: Pre-configured authentication integrations referenced by name

## API Endpoints (Verified Working)

### Health Check Management
- **POST** `/v1/status-checks?teamId={TEAM_ID}` - Create health check
- **GET** `/v1/status-checks?teamId={TEAM_ID}` - List health checks
- **PUT** `/v1/status-checks/{id}?teamId={TEAM_ID}` - Update health check
- **DELETE** `/v1/status-checks/{id}?teamId={TEAM_ID}` - Delete health check

### Integration Management
- **POST** `/v1/external-integrations/status-check?teamId={TEAM_ID}&type=CUSTOM` - Create integration
- **GET** `/v1/external-integrations/status-check?teamId={TEAM_ID}` - List integrations

## Authentication Methods

### Gremlin API Authentication
All requests require one of these headers:
```bash
# API Key (Recommended)
Authorization: Key {API_KEY}

# Bearer Token
Authorization: Bearer {BEARER_TOKEN}
```

## Method 1: Direct Authentication (Simple)

Create health checks with credentials directly in headers:

```bash
curl -X POST \
  "https://api.gremlin.com/v1/status-checks?teamId={TEAM_ID}" \
  -H "Authorization: Key {API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "prometheus-direct-auth",
    "endpointType": "http",
    "endpointConfiguration": {
      "url": "http://prometheus:9090/api/v1/query?query=up",
      "method": "GET",
      "headers": {
        "Authorization": "Basic YWRtaW46cHJvbS1vcGVyYXRvcg=="
      }
    },
    "evaluationConfiguration": {
      "okStatusCodes": [200]
    },
    "pollingInterval": 60
  }'
```

### Common Direct Auth Headers

**Prometheus/Grafana Basic Auth:**
```json
"headers": {
  "Authorization": "Basic YWRtaW46cHJvbS1vcGVyYXRvcg=="
}
```

**Dynatrace API Token:**
```json
"headers": {
  "Authorization": "Api-Token dt0c01.ABC123..."
}
```

**New Relic API Key:**
```json
"headers": {
  "Authorization": "Bearer NRAK-ABC123...",
  "Content-Type": "application/json"
}
```

## Method 2: Integration Authentication (Advanced)

### Step 1: Create Authentication Integration

```bash
curl -X POST \
  "https://api.gremlin.com/v1/external-integrations/status-check?teamId={TEAM_ID}&type=CUSTOM" \
  -H "Authorization: Key {API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "prometheus-auth-integration",
    "description": "Prometheus authentication for health checks",
    "type": "CUSTOM",
    "privateNetwork": false,
    "lastAuthenticationStatus": "AUTHENTICATED",
    "configuration": {
      "baseUrl": "http://prometheus:9090",
      "auth": {
        "type": "BASIC",
        "username": "admin",
        "password": "prom-operator"
      }
    }
  }'
```

**Critical Requirements:**
- Query parameter `type=CUSTOM` is **required**
- `privateNetwork` field is **required** (true/false)
- `lastAuthenticationStatus` must be one of: `AUTHENTICATED`, `UNAUTHENTICATED`, `UNTESTED`

### Step 2: Create Health Check Referencing Integration

```bash
curl -X POST \
  "https://api.gremlin.com/v1/status-checks?teamId={TEAM_ID}" \
  -H "Authorization: Key {API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "prometheus-with-integration",
    "endpointType": "http",
    "endpointConfiguration": {
      "url": "http://prometheus:9090/api/v1/query?query=up",
      "method": "GET"
    },
    "evaluationConfiguration": {
      "okStatusCodes": [200]
    },
    "pollingInterval": 60,
    "teamExternalIntegration": {
      "observabilityToolType": "CUSTOM",
      "name": "prometheus-auth-integration"
    }
  }'
```

**Key Points:**
- `endpointConfiguration.headers` remains empty `{}`
- Authentication handled via `teamExternalIntegration.name`
- Use `observabilityToolType` (not `type`) in integration reference

## Platform-Specific Examples

### Prometheus Health Check
```bash
# Endpoint: /api/v1/query?query=up
# Expected Response: {"status":"success","data":...}
curl -X POST \
  "https://api.gremlin.com/v1/status-checks?teamId={TEAM_ID}" \
  -H "Authorization: Key {API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "prometheus-metrics-check",
    "endpointType": "http",
    "endpointConfiguration": {
      "url": "http://prometheus:9090/api/v1/query?query=up",
      "method": "GET",
      "headers": {
        "Authorization": "Basic YWRtaW46cHJvbS1vcGVyYXRvcg=="
      }
    },
    "evaluationConfiguration": {
      "okStatusCodes": [200]
    },
    "pollingInterval": 60
  }'
```

### Grafana Health Check
```bash
# Endpoint: /api/health
# Expected Response: {"database":"ok","version":"..."}
curl -X POST \
  "https://api.gremlin.com/v1/status-checks?teamId={TEAM_ID}" \
  -H "Authorization: Key {API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "grafana-health-check",
    "endpointType": "http",
    "endpointConfiguration": {
      "url": "http://grafana:3000/api/health",
      "method": "GET",
      "headers": {
        "Authorization": "Basic YWRtaW46cHJvbS1vcGVyYXRvcg=="
      }
    },
    "evaluationConfiguration": {
      "okStatusCodes": [200]
    },
    "pollingInterval": 60
  }'
```

### Dynatrace Health Check
```bash
# Endpoint: /api/v2/problems
# Expected Response: {"totalCount":0,"pageSize":50,...}
curl -X POST \
  "https://api.gremlin.com/v1/status-checks?teamId={TEAM_ID}" \
  -H "Authorization: Key {API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "dynatrace-problems-check",
    "endpointType": "http",
    "endpointConfiguration": {
      "url": "https://tenant.live.dynatrace.com/api/v2/problems",
      "method": "GET",
      "headers": {
        "Authorization": "Api-Token dt0c01.ABC123..."
      }
    },
    "evaluationConfiguration": {
      "okStatusCodes": [200]
    },
    "pollingInterval": 60
  }'
```

## Service Cleanup (Important for Reinstalls)

Before creating new health checks, clean up old services to avoid UI confusion:

```bash
# List existing services
curl -H "Authorization: Key {API_KEY}" \
  "https://api.gremlin.com/v1/services?teamId={TEAM_ID}"

# Delete specific service
curl -X DELETE \
  -H "Authorization: Key {API_KEY}" \
  "https://api.gremlin.com/v1/services/{serviceId}?teamId={TEAM_ID}"
```

## Validation and Testing

### Verify Health Check Creation
```bash
# List all health checks
curl -H "Authorization: Key {API_KEY}" \
  "https://api.gremlin.com/v1/status-checks?teamId={TEAM_ID}" | jq '.[].name'

# Get specific health check details
curl -H "Authorization: Key {API_KEY}" \
  "https://api.gremlin.com/v1/status-checks/{health_check_id}?teamId={TEAM_ID}"
```

### Test Endpoint Manually
```bash
# Test Prometheus endpoint
curl -H "Authorization: Basic YWRtaW46cHJvbS1vcGVyYXRvcg==" \
  "http://prometheus:9090/api/v1/query?query=up"

# Test Grafana endpoint  
curl -H "Authorization: Basic YWRtaW46cHJvbS1vcGVyYXRvcg==" \
  "http://grafana:3000/api/health"
```

## Common Errors and Solutions

### "name: must not be blank"
- **Cause**: Missing `teamExternalIntegration.name` field
- **Solution**: Ensure integration name is correctly referenced

### "privateNetwork: must be provided"
- **Cause**: Missing required field in integration creation
- **Solution**: Add `"privateNetwork": false` to integration payload

### "Query param 'type' is required"
- **Cause**: Missing `type=CUSTOM` query parameter
- **Solution**: Add `?type=CUSTOM` to integration creation URL

### "okStatusCodes must contain at least one element"
- **Cause**: Empty or missing status codes array
- **Solution**: Add `"okStatusCodes": [200]` to evaluation configuration

### Health check created but authentication fails
- **Cause**: Incorrect credentials or endpoint URL
- **Solution**: Test endpoint manually with same credentials

## Best Practices

1. **Use Direct Authentication** for simple setups
2. **Use Integration Authentication** for complex auth or multiple health checks
3. **Test endpoints manually** before creating health checks
4. **Clean up old services** before reinstalling
5. **Use descriptive names** with timestamps for uniqueness
6. **Set appropriate polling intervals** (15-300 seconds)
7. **Validate credentials** before health check creation

## Workshop Integration

The `build_scripts/demo/healthchecks.sh` script implements these patterns:

```bash
# Create health checks with service cleanup
./build_scripts/demo/healthchecks.sh --cleanup-services --platform prometheus --platform grafana

# Dry run to see what would be created
./build_scripts/demo/healthchecks.sh --dry-run --platform all

# Validate existing health checks
./build_scripts/demo/healthchecks.sh --validate-only
```

## Endpoint URLs for Current Workshop

Based on cluster state and DNS configuration:

### ALB Endpoints (Dynamic)
- Frontend: `{ALB_HOSTNAME}` (from cluster-state.json)
- Grafana: `{GRAFANA_ALB_HOSTNAME}` (from cluster-state.json)
- Prometheus: `{PROMETHEUS_ALB_HOSTNAME}` (from cluster-state.json)

### DNS Endpoints (Static)
- Frontend: `http://{cluster-name}-frontend.gremlinpoc.com`
- Grafana: `http://{cluster-name}-grafana.gremlinpoc.com`
- Prometheus: `http://{cluster-name}-prometheus.gremlinpoc.com:9090`

### Health Check URLs
- **Prometheus Metrics**: `/api/v1/query?query=up`
- **Prometheus Rules**: `/api/v1/rules`
- **Prometheus Alerts**: `/api/v1/alerts`
- **Grafana Health**: `/api/health`
- **Grafana Alerts**: `/api/alerting/list`

## Summary

This guide provides the complete, tested approach for creating Gremlin health checks. The key insights:

1. **Direct auth is simpler** - embed credentials in headers
2. **Integration auth is more secure** - centralized credential management
3. **Service cleanup prevents confusion** - delete old services before reinstall
4. **Endpoint testing is crucial** - verify manually before automation
5. **Dynamic discovery works** - use cluster state for current endpoints

All examples have been validated against the Gremlin API and work correctly with the current workshop infrastructure.
