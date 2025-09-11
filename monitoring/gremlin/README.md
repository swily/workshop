# Gremlin Prometheus Health Check Integration

This directory contains a comprehensive solution for integrating Prometheus-based health checks with Gremlin chaos engineering platform.

## Overview

The integration provides:
- **Prometheus-based health checks** using actual metrics from your monitoring stack
- **Grafana alert integration** for comprehensive monitoring validation
- **Automatic service discovery** for all services in your Kubernetes cluster
- **Secure credential management** for Gremlin API access
- **Workshop.sh integration** for seamless setup during monitoring installation

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Prometheus    │    │     Grafana     │    │    Gremlin      │
│   (Metrics)     │◄──►│   (Alerts)      │◄──►│ (Health Checks) │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲                       ▲                       ▲
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│              OpenTelemetry Demo Services                        │
│  frontend │ cart │ checkout │ payment │ shipping │ ...          │
└─────────────────────────────────────────────────────────────────┘
```

## Files

### Core Scripts

- **`create_prometheus_health_checks.sh`** - Main script for creating Prometheus-based health checks
- **`gremlin_credentials_manager.sh`** - Secure credential management for Gremlin API
- **`setup_gremlin_health_checks.sh`** - Integration script for workshop.sh
- **`test_health_check_integration.sh`** - Comprehensive test suite

### Legacy Scripts (Deprecated)

- `create_health_checks_enhanced.sh` - Legacy enhanced health check script
- `create_health_checks.sh` - Original basic health check script

## Quick Start

### 1. Automatic Setup (Recommended)

Run the workshop script and select Prometheus/Grafana monitoring:

```bash
./workshop.sh
# Select option for Prometheus/Grafana installation
# Health checks will be created automatically
```

### 2. Manual Setup

If you want to set up health checks manually:

```bash
# Set up Gremlin credentials
./monitoring/gremlin/gremlin_credentials_manager.sh set

# Create health checks
./monitoring/gremlin/setup_gremlin_health_checks.sh
```

### 3. Advanced Usage

For advanced configuration:

```bash
# Create health checks with custom parameters
./monitoring/gremlin/create_prometheus_health_checks.sh \
  --team-id "your-team-id" \
  --bearer-token "your-token" \
  --grafana-api-key "your-grafana-key" \
  --namespace "otel-demo" \
  --cleanup-duplicates
```

## Configuration

### Required Credentials

1. **Gremlin Team ID** - Found in Gremlin UI → Settings → Teams
2. **Gremlin Bearer Token** - API key from Gremlin UI → Settings → API Keys
3. **Grafana API Key** (optional) - For enhanced alert-based health checks

### Environment Variables

The scripts support these environment variables:

```bash
export GREMLIN_TEAM_ID="your-team-id"
export BEARER_TOKEN="your-bearer-token"
export GRAFANA_API_KEY="your-grafana-key"
```

## Health Check Types

### 1. Prometheus Metrics Health Checks

- **Query**: `up{job="service-name",namespace="otel-demo"}`
- **Success Criteria**: Metric value equals "1"
- **Polling Interval**: 30 seconds
- **Use Case**: Validates service availability via Prometheus metrics

### 2. Grafana Alert Health Checks

- **Endpoint**: Grafana Alertmanager API
- **Success Criteria**: No firing alerts for the service
- **Polling Interval**: 30 seconds
- **Use Case**: Validates that monitoring alerts are not triggered

## Testing

Run the comprehensive test suite:

```bash
./monitoring/gremlin/test_health_check_integration.sh
```

This validates:
- ✅ Script files and permissions
- ✅ Prerequisites (kubectl, jq, curl)
- ✅ Monitoring installation (Prometheus/Grafana)
- ✅ Target services discovery
- ✅ Credentials manager functionality
- ✅ Health check script dry-run
- ✅ URL auto-detection
- ✅ Workshop.sh integration

## Troubleshooting

### Common Issues

1. **"No credentials found"**
   ```bash
   # Set up credentials
   ./monitoring/gremlin/gremlin_credentials_manager.sh set
   ```

2. **"Monitoring namespace not found"**
   ```bash
   # Install monitoring first
   ./workshop.sh
   # Select Prometheus/Grafana option
   ```

3. **"API request failed"**
   - Verify Gremlin credentials are correct
   - Check network connectivity to api.gremlin.com
   - Ensure Bearer token has proper permissions

4. **"No services found"**
   - Verify OpenTelemetry Demo is deployed
   - Check namespace name (default: otel-demo)

### Debug Mode

Enable debug output:

```bash
DEBUG=true ./monitoring/gremlin/create_prometheus_health_checks.sh --help
```

### Dry Run Mode

Test without making changes:

```bash
./monitoring/gremlin/create_prometheus_health_checks.sh \
  --team-id "your-team-id" \
  --bearer-token "your-token" \
  --dry-run
```

## API Endpoints Used

### Gremlin API

- **Base URL**: `https://api.gremlin.com/v1`
- **Health Checks**: `/status-checks`
- **Authentication**: Bearer token

### Prometheus API

- **Query Endpoint**: `/api/v1/query`
- **Health Check Query**: `up{job="service",namespace="namespace"}`

### Grafana API

- **Alertmanager**: `/api/alertmanager/grafana/api/v2/alerts`
- **Authentication**: Bearer token (Grafana API key)

## Integration with Chaos Engineering

### Scenario Creation

Use the created health checks in Gremlin scenarios:

1. **Pre-attack validation**: Verify services are healthy
2. **During attack**: Monitor service degradation
3. **Post-attack validation**: Verify service recovery

### Example Scenario

```yaml
name: "Frontend Service Chaos Test"
steps:
  - type: "validation"
    name: "Pre-attack Health Check"
    healthCheck: "frontend-prometheus-health"
  - type: "attack"
    target: "frontend"
    command: "cpu"
  - type: "validation"
    name: "Post-attack Recovery"
    healthCheck: "frontend-prometheus-health"
```

## Security Considerations

- Credentials are stored in `~/.gremlin_credentials` with 600 permissions
- Bearer tokens are masked in logs and output
- API keys are not logged or displayed in plain text
- Supports environment variable injection for CI/CD

## Contributing

When modifying the health check system:

1. Update the test suite in `test_health_check_integration.sh`
2. Run tests before committing changes
3. Update this documentation
4. Ensure backward compatibility with workshop.sh

## Support

For issues or questions:

1. Run the test suite to identify problems
2. Check the troubleshooting section
3. Review Gremlin API documentation: https://www.gremlin.com/docs/api-reference/
4. Review Prometheus API documentation: https://prometheus.io/docs/prometheus/latest/querying/api/
