# AppDynamics Integration - TODO

## Status: Not Implemented

This directory is a placeholder for future AppDynamics integration with the OpenTelemetry Demo workshop and Gremlin health checks.

## Planned Implementation

### Required Components:
- [ ] **Installation Script** (`install/install.sh`)
  - AppDynamics agent installation via Helm
  - Controller configuration and connectivity
  - Integration with otel-demo namespace

- [ ] **Authentication Setup** (`auth/`)
  - AppDynamics controller credentials
  - Account information and access key
  - SSL certificate configuration

- [ ] **Health Check Integration** (`health_check/`)
  - AppDynamics health rule creation for otel-demo services
  - Gremlin health check integration via AppDynamics REST API
  - Application performance baseline monitoring

- [ ] **Values Configuration** (`values/`)
  - Helm values for AppDynamics agents
  - Custom instrumentation configuration

### Gremlin Integration Points:
- [ ] **AppDynamics REST API**: Monitor health rule violations and application health
- [ ] **Health Check Logic**: Query AppDynamics API for application status
  - Healthy: No critical health rule violations
  - Unhealthy: Critical health rules in violation state
- [ ] **Performance Monitoring**: Application performance metrics and SLA violations

### API Requirements:
- AppDynamics Controller URL
- AppDynamics Account Name
- AppDynamics Access Key
- AppDynamics REST API credentials

### Integration with Gremlin:
```bash
# Health check endpoint example
curl -H "Authorization: Bearer $GREMLIN_API_KEY" \
  "https://api.gremlin.com/v1/health-checks" \
  -d '{
    "name": "otel-demo-appdynamics",
    "description": "Monitor otel-demo via AppDynamics health rules",
    "evaluationStrategy": "appdynamics-health-rules",
    "target": "https://your-controller.saas.appdynamics.com/",
    "healthCheckType": "appdynamics"
  }'
```

### Health Rule Examples:
- Application availability (>95% uptime)
- Response time thresholds (<500ms average)
- Error rate monitoring (<1% error rate)
- Throughput baselines (requests per minute)

### Documentation:
- [ ] Installation and configuration guide
- [ ] Health rule setup examples
- [ ] Performance baseline configuration
- [ ] Troubleshooting guide

## Implementation Priority: Low
AppDynamics integration planned for enterprise APM monitoring capabilities.
