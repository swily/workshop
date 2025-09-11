- Status:
  - Added `get_frontend_fqdn()` in `lib/common.sh` to standardize frontend URL (FQDN first, ALB fallback).
  - `scripts/operations/deploy_otel.sh` now calls `set_locust_host()` post-deploy to set `LOCUST_HOST` to the preferred URL.
  - `export_cluster_state()` now includes `frontend_fqdn` for downstream consumers.
- Priority: High (done)
# Workshop Modernization Roadmap

This roadmap lists concrete, prioritized changes with exact references to current code. Each item includes "What to change", "Why", and "Priority" so we can execute and track progress.

## 1) Standardize on ALB Ingress for all public endpoints — [COMPLETED]
- What to change:
  - Ensure Grafana and Prometheus are exposed via Kubernetes Ingress (ALB) instead of Service type LoadBalancer.
  - Add or verify Ingress resources for:
    - `grafana` (likely in `monitoring/` or via `lib/monitoring.sh` functions)
    - `prometheus` (same)
  - Keep existing Ingress for frontend and Jaeger in `scripts/operations/deploy_otel.sh` (`setup_ingress()` already creates `frontend-proxy` and `jaeger-ingress`).
- Why:
  - Consistency, simpler DNS/TLS, and production parity. Current code already prefers Ingress and only falls back to LoadBalancer Services (`lib/common.sh::export_cluster_state()`); standardizing removes ambiguity.
- Status:
  - Implemented Prometheus ALB Ingress and wired it into Grafana/Prometheus monitoring setup.
  - Updated monitoring endpoints to use ALB hostnames for Prometheus.
  - Updated cluster state export to read Prometheus from `monitoring` namespace Ingress.
  - Exact changes:
    - `lib/monitoring.sh`:
      - Added `setup_prometheus_ingress()` (creates `prometheus-ingress` with ALB annotations targeting `kube-prometheus-stack-prometheus:9090`).
      - Called from `setup_grafana_monitoring()` after `setup_grafana_ingress()`.
      - `get_monitoring_endpoints()` now prints `http://<prometheus-ingress-hostname>` instead of a port-forward command.
    - `lib/common.sh`:
      - `export_cluster_state()` now discovers `prometheus-ingress` in `monitoring` namespace (previously checked `otel-demo`).
- Priority: High

## 2) Add ExternalDNS and cert-manager for automated DNS and HTTPS — [COMPLETED for ExternalDNS + ALB/ACM path]
- What to change:
  - Add deployment functions in `lib/monitoring.sh` (or a new `lib/addons.sh`) to install:
    - ExternalDNS with IRSA and Route53 permissions.
    - cert-manager with a ClusterIssuer (Let’s Encrypt or ACM PCA).
  - Annotate Ingress objects (frontend, grafana, prometheus, jaeger) with hostnames like:
    - `${CLUSTER_NAME}-frontend.gremlinpoc.com`, `${CLUSTER_NAME}-grafana.gremlinpoc.com`, `${CLUSTER_NAME}-prometheus.gremlinpoc.com`.
  - Add TLS sections to Ingress specs so cert-manager provisions certs automatically.
- Why:
  - Automatic DNS record management and TLS, no manual steps, aligns with the DNS mapping block already produced in `lib/common.sh::export_cluster_state()`.
 - Status:
   - Domain is fixed to `gremlin.poc.com` and discovered automatically in code; no user flags required.
   - ACM certificate is auto-discovered per region for `*.gremlin.poc.com`; if found, ALB TLS is enabled; otherwise HTTP-only fallback.
   - Implemented `setup_externaldns()` in `lib/monitoring.sh` (Bitnami chart, IRSA optional via `EXTERNALDNS_IAM_ROLE_ARN`).
   - Updated Ingress creation in `scripts/operations/deploy_otel.sh` (frontend/jaeger) and `lib/monitoring.sh` (grafana/prometheus) to add:
     - ExternalDNS hostname annotations using `${HOST_PREFIX}<app>.${BASE_DOMAIN}`.
     - Conditional ALB TLS annotations when ACM certificate is found.
   - Updated endpoint rendering to prefer ALB URLs. `export_cluster_state()` keeps working and now benefits from consistent hostnames.
 - Notes:
   - The cert-manager path is intentionally not implemented for ALB; ALB+ACM is the recommended approach on EKS. We can add cert-manager (NGINX-based) later if needed.
- Priority: High

## 3) Make export_cluster_state() Ingress-first and remove LB Service fallback once ALB is standard — [COMPLETED]
- What to change:
  - In `lib/common.sh::export_cluster_state()` (lines ~228–263), remove fallback to LoadBalancer Services:
    - Currently reads `frontend-proxy` Ingress first, then falls back to `svc frontend-proxy` hostname.
  - After completing Items 1 and 2, rely only on Ingress discovery for: `frontend-proxy`, `grafana-ingress`, `prometheus-ingress`, `jaeger-ingress`.
- Why:
  - Ensures consistent endpoint discovery and simplifies downstream consumers (health checks, README, and LOCUST_HOST).
- Status:
  - Removed Service LoadBalancer fallback in `lib/common.sh::export_cluster_state()`; it now relies only on Ingress hostnames for frontend/Grafana/Prometheus.
- Priority: High (done)

## 3b) Update README to reflect domain/TLS automation and ALB standardization — [TODO]
- What to change:
  - Document that `BASE_DOMAIN` is fixed to `gremlin.poc.com` and that ACM wildcard (`*.gremlin.poc.com`) is auto-discovered per region.
  - Explain ExternalDNS installation and optional IRSA role (`EXTERNALDNS_IAM_ROLE_ARN`).
  - Show example endpoints using `${CLUSTER_NAME}-<app>.gremlin.poc.com`.
  - Clarify fallback to HTTP-only if ACM cert not present.
- Why:
  - Keep user-facing docs aligned with simplified inputs and reusable AWS resources, ensuring consistent demo experience.
- Priority: High

## 4) Harmonize DRY_RUN handling via lib/common.sh
- What to change:
  - Ensure all scripts use `is_dry_run()` and `execute_command()` from `lib/common.sh` for kubectl/helm/aws actions, instead of inlined `if DRY_RUN ...` blocks.
  - Source `lib/common.sh` in `scripts/gremlin_install.sh` and remove local color/log helpers; replace direct `helm`/`kubectl` invocations with `execute_command`.
  - In `scripts/operations/deploy_otel.sh`, wrap calls:
    - `helm upgrade --install opentelemetry-demo ...`
    - `kubectl apply -f -` (via process substitution or temporary files executed through `execute_command`)
    - `kubectl wait` loops may remain direct but guarded by `is_dry_run`.
  - In `scripts/operations/cluster_create.sh` and `cluster_cleanup.sh`, replace direct kubectl/helm/aws calls with `execute_command` where safe.
  - Normalize messaging: use `log_info/log_warning/log_success/log_error` exclusively for consistency.
- Why:
  - Consistent semantics for dry run across the repo, easier auditing and future changes.
- Priority: Medium
- Acceptance criteria:
  - Running any operation with `DRY_RUN=true` performs no mutations while printing the exact commands that would run (via `execute_command`).
  - No duplicate color/log functions in `scripts/`—all logging comes from `lib/common.sh`.
  - All helm/kubectl central paths flow through `execute_command` (except `kubectl wait`/read-only getters where appropriate).

## 5) Source lib/common.sh in scripts/gremlin_install.sh and remove duplicate logging/colors — [COMPLETED]
- What to change:
  - At the top of `scripts/gremlin_install.sh`, source `../lib/common.sh` (relative: `SCRIPT_DIR/../lib/common.sh`) and delete local color/log helpers in favor of `log_info/log_success/log_warning/log_error`.
  - Use `execute_command` for helm/kubectl invocations.
  - Validate credentials strictly based on `INSTALL_TYPE` (standard requires TEAM_ID/SECRET; PNI also requires API key if used).
- Why:
  - Removes duplicated code and centralizes behavior. Also ensures strict, early validation.
- Status:
  - `scripts/gremlin_install.sh` now sources `lib/common.sh` and uses `log_*`, `is_dry_run()`, and `execute_command()`.
  - Replaced direct `kubectl`/`helm` invocations with `execute_command` where appropriate.
  - Removed custom color definitions and ad-hoc dry-run printing.
- Priority: Medium-High (done)

## 6) Deduplicate help text patterns into a shared helper
- What to change:
  - Many scripts define their own `show_help()` (e.g., `scripts/operations/cluster_create.sh`, `deploy_otel.sh`, `cluster_cleanup.sh`, `scripts/gremlin_install.sh`).
  - Create a small helper (either in `lib/ui.sh` or `lib/help.sh`) to print a standard header/footer and style, with each script passing usage text blocks.
- Why:
  - Reduces copy/paste drift and keeps UX consistent.
- Priority: Low-Medium

## 7) Cleanup legacy monitoring scripts now covered by lib/monitoring.sh — [PARTIAL]
- What to change:
  - Audit `monitoring/` directory (e.g., `monitoring/grafana/ingress/*.sh`, `monitoring/setup_monitoring*.sh`).
  - Either migrate logic into `lib/monitoring.sh` or mark these scripts deprecated by moving to `monitoring/legacy/` with a README pointing to the new approach.
- Why:
  - Reduces confusion and keeps a single source of truth.
- Status:
  - Added deprecation header + runtime notice to `monitoring/setup_monitoring.sh` directing to `workshop.sh` + `lib/monitoring.sh`.
  - Full directory audit and move to `monitoring/legacy/` pending.
- Priority: Medium

## 8) Align load generator (LOCUST_HOST) and health checks to ALB hostnames — [COMPLETED]
- What to change:
  - Search/replace any references to ELB or hardcoded endpoints in:
    - `build_scripts/demo/update_loadgen_alb.sh`
    - `build_scripts/demo/otel-demo-values-enhanced.yaml`
    - `patches/load-generator-loadbalancer-patch.yaml`
    - `build_scripts/load-balancer/install.sh`
  - Ensure these derive the value from Ingress hostname (as exported by `export_cluster_state()` or directly via `kubectl get ingress`).
- Why:
  - Keeps load generation and health checks aligned with the ALB-first strategy.
- Priority: Medium

## 9) Harden cleanup: include CloudFormation fallback when EKS deletion stalls — [COMPLETED]
- What to change:
  - In `scripts/operations/cluster_cleanup.sh`, add logic to detect stuck deletes and directly delete CloudFormation stacks (re-using the approach noted in memory).
  - Optionally factor these AWS cleanup functions into `lib/cluster.sh` so they can be reused.
- Why:
  - EKS deletes can stall due to CFN DELETE_FAILED; this makes cleanup robust.
- Status:
  - Implemented `cleanup_cloudformation_stacks()` in `lib/cluster.sh` and invoked from `cleanup_cluster()`.
- Priority: Medium (done)

## 10) Standardize strict mode across scripts — [IN PROGRESS]
- What to change:
  - Ensure all scripts use `#!/bin/bash` and `set -Eeuo pipefail`.
- Why:
  - Prevent regressions and catch common Bash pitfalls earlier.
- Status:
  - Enabled `set -Eeuo pipefail` in `workshop.sh`, `scripts/gremlin_install.sh`, `scripts/operations/deploy_otel.sh`, `scripts/operations/cluster_create.sh`.
  - Pending: `scripts/operations/cluster_cleanup.sh` (strict mode).
- Notes:
  - Decision: Skip adding ShellCheck CI to reduce complexity for now.
- Priority: Medium

## 11) Add tests/smoke.sh to validate end-to-end flows (dry run) — [COMPLETED]
- What to change:
  - Create `tests/smoke.sh` that runs:
    - `./workshop.sh --action build_new --cluster-name test --dry-run`
    - `./workshop.sh --action deploy_existing --cluster-name test --dry-run`
    - `./workshop.sh --action gremlin_only --cluster-name test --dry-run`
    - `./scripts/operations/cluster_cleanup.sh --cluster-name test --dry-run`
  - Assert expected log lines and non-error exits.
- Why:
  - CI confidence and quick validation of orchestration.
- Status:
  - Added `tests/smoke.sh` to run build_new, deploy_existing, gremlin_only, and cluster_cleanup in dry-run mode.
- Priority: Medium (done)

## 12) Ensure security context and resources match StandardEnv decisions
- What to change:
  - Audit Helm values and k8s manifests to confirm uniform `securityContext` (runAsNonRoot, runAsUser/group) and resource requests/limits (especially the load-generator fix: requests <= limits). Reference files:
    - `prometheus-rules.yaml`
    - any managed Helm values in `deploy_otel.sh` and `monitoring/`.
- Why:
  - Aligns with the hardened StandardEnv baseline and prevents deployment errors.
- Priority: Medium

## 13) Update README with new architecture and usage examples — [COMPLETED]
- What to change:
  - Document new modular layout (`lib/`, `scripts/operations/`), command examples for CLI and interactive modes, and the ALB+ExternalDNS+cert-manager model.
  - Include how Gremlin credentials are provided (no hardcoding), and recommended secure flows.
- Why:
  - Improves onboarding and reduces misconfiguration.
- Status:
  - Documented ALB-first architecture, fixed base domain `gremlin.poc.com`, ACM auto-discovery per region, and ExternalDNS IRSA workflow with minimal IAM policy snippet.
  - Documented minimal inputs (cluster name, region, Gremlin creds), LOCUST_HOST automation, and modern quick start examples.
- Priority: High (done)

## 14) Optional: NetworkPolicy and IRSA hardening
- What to change:
  - Add default deny `NetworkPolicy` and selective allow rules for otel-demo, monitoring, and gremlin namespaces.
  - Ensure IRSA for ALB controller, ExternalDNS, and cert-manager when introduced.
- Why:
  - Improves cluster security posture and follows AWS best practices.
- Priority: Low-Medium

---

## Trace verification notes
- Frontend and Jaeger Ingress are defined in `scripts/operations/deploy_otel.sh::setup_ingress()`.
- Endpoint export reads Ingress first, then falls back to LB service in `lib/common.sh::export_cluster_state()`.
- `workshop.sh` delegates to `scripts/operations/cluster_create.sh`, `scripts/operations/deploy_otel.sh`, `scripts/gremlin_install.sh`, and `lib/monitoring.sh::setup_comprehensive_monitoring()`.
- `display_workshop_endpoints()` is defined in `lib/ui.sh` (verified via grep) and called by `workshop.sh` post-deploy.
- Hardcoded Gremlin credentials in `scripts/gremlin_install.sh` were removed; credentials must be provided via CLI or env.

This roadmap is ready for execution. We can start with Items 1, 2, and 13 (ALB-only + ExternalDNS/cert-manager + README) to cement the architecture, then proceed down the list.
