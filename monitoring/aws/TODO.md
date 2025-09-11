# AWS CloudWatch Integration - TODO

## Status: Not Implemented

This directory is a placeholder for future AWS CloudWatch integration with the OpenTelemetry Demo workshop and Gremlin health checks.

## Planned Implementation

### Required Components:
- [ ] **Installation Script** (`install/install.sh`)
  - CloudWatch agent installation
  - IAM role and policy configuration
  - Integration with otel-demo namespace

- [ ] **Authentication Setup** (`auth/`)
  - AWS credentials configuration
  - Service account with CloudWatch permissions
  - Cross-account role setup if needed

- [ ] **Health Check Integration** (`health_check/`)
  - CloudWatch alarm creation for otel-demo services
  - Gremlin health check integration via CloudWatch API
  - Custom metric monitoring for application health

- [ ] **Values Configuration** (`values/`)
  - CloudWatch agent configuration
  - Custom metrics and log group setup

### Gremlin Integration Points:
- [ ] **CloudWatch Alarms API**: Monitor alarm states for otel-demo resources
- [ ] **Health Check Logic**: Query CloudWatch API for alarm status
  - Healthy: No alarms in ALARM state
  - Unhealthy: Any critical alarms in ALARM state
- [ ] **Metrics Monitoring**: Custom application metrics via CloudWatch

### API Requirements:
- AWS Access Key ID and Secret Access Key
- CloudWatch:DescribeAlarms permissions
- CloudWatch:GetMetricStatistics permissions
- CloudWatch:PutMetricData permissions (for custom metrics)

### Integration with Gremlin:
```bash
# Health check endpoint example
curl -H "Authorization: Bearer $GREMLIN_API_KEY" \
  "https://api.gremlin.com/v1/health-checks" \
  -d '{
    "name": "otel-demo-cloudwatch",
    "description": "Monitor otel-demo via CloudWatch alarms",
    "evaluationStrategy": "cloudwatch-alarms",
    "target": "https://monitoring.us-west-2.amazonaws.com/",
    "healthCheckType": "cloudwatch"
  }'
```

### Documentation:
- [ ] Installation and configuration guide
- [ ] CloudWatch alarm setup examples
- [ ] Troubleshooting guide
- [ ] Cost optimization recommendations

## Implementation Priority: Medium
AWS CloudWatch integration planned for comprehensive cloud-native monitoring.
