# DataDog Integration - TODO

## Status: Not Implemented

This directory is a placeholder for future DataDog integration with the OpenTelemetry Demo workshop.

## Planned Implementation

### Required Components:
- [ ] **Installation Script** (`install/install.sh`)
  - DataDog agent installation via Helm
  - API key configuration
  - Integration with otel-demo namespace

- [ ] **Authentication Setup** (`auth/`)
  - API key generation automation
  - Service account configuration

- [ ] **Health Check Integration** (`health_check/`)
  - DataDog monitor creation for otel-demo services
  - Gremlin health check integration
  - Alert rule automation

- [ ] **Values Configuration** (`values/`)
  - Helm values for DataDog agent
  - Custom configuration for otel-demo monitoring

### Integration Points:
- [ ] Add DataDog option to `monitoring/setup_monitoring_numbered.sh` (option 4)
- [ ] Update `workshop.sh` orchestration to include DataDog selection
- [ ] Create health checks that monitor otel-demo resources via DataDog API
- [ ] Integrate with Gremlin chaos engineering platform

### API Requirements:
- DataDog API Key
- DataDog Application Key
- DataDog Site URL (e.g., datadoghq.com, datadoghq.eu)

### Documentation:
- [ ] Installation guide
- [ ] Configuration examples
- [ ] Troubleshooting guide

## Implementation Priority: Low
This integration is planned for future workshop enhancements.
