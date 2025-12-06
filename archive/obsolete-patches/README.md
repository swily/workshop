# Obsolete Kubernetes Patches

These Kubernetes patch files were archived on 2025-10-21 because they are no longer used in the deployment workflow.

## Files in This Archive

- `load-generator-loadbalancer-patch.yaml` - LoadBalancer patch for load generator
- `otel-collector-grpc-metrics-patch.yaml` - gRPC metrics patch for OTel collector

## Why Archived

These patches were only referenced by `helper_scripts/update_loadgen_target.sh`, which is not part of the main deployment workflow.

Current approach:
- Load generator configuration via Helm values in `build_scripts/demo/otel-demo-values-enhanced.yaml`
- OTel collector configuration via Helm values (no patches needed)

## Verification

Only found in helper scripts, not main workflow:
```bash
grep -r "load-generator-loadbalancer-patch.yaml" *.sh
# Only result: helper_scripts/update_loadgen_target.sh

grep -r "otel-collector-grpc-metrics-patch.yaml" *.sh
# Only result: helper_scripts/update_loadgen_target.sh
```

**Archived:** 2025-10-21  
**Safe to delete:** Yes (after verification period)
