# Obsolete Configuration Files

These configuration files were archived on 2025-10-21 because they are no longer referenced by any active scripts.

## Monitoring Configs (4 files)

- `kubelet-servicemonitor.yaml` - ServiceMonitor for kubelet metrics
- `prometheus-operator-values.yaml` - Prometheus Operator Helm values
- `prometheus-rules.yaml` - Prometheus alerting rules
- `service-monitors.yaml` - ServiceMonitor definitions

## Build Scripts Configs (2 files)

- `otel-demo-values-enhanced.yaml` - Enhanced Helm values (replaced by inline generation)
- `golden-cluster-config.yaml` - eksctl cluster config (replaced by Terraform)

## Istio Configs (2 files)

- `istio-operator.yaml` - Istio operator configuration
- `kiali-values.yaml` - Kiali observability Helm values

## Why Archived

These files were replaced by:
- `monitoring/prometheus/values/prometheus-values.yaml` - Current Prometheus configuration
- `monitoring/prometheus/servicemonitors/otel-demo-servicemonitor.yaml` - Current ServiceMonitors
- Platform-specific configurations in respective directories

## Verification

No active scripts reference these files:
```bash
grep -r "kubelet-servicemonitor.yaml" *.sh  # No results
grep -r "prometheus-operator-values.yaml" *.sh  # No results
grep -r "prometheus-rules.yaml" *.sh  # No results
grep -r "service-monitors.yaml" *.sh  # No results
```

**Archived:** 2025-10-21  
**Safe to delete:** Yes (after verification period)
