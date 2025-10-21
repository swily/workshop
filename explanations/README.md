# Workshop Explanations & Documentation

This directory contains historical documentation, analysis, and troubleshooting guides that provide context for the workshop implementation.

## Documentation Files

### 📚 **HEALTH_CHECKS_SETUP.md**
**Created:** 2025-10-05  
**Status:** Current Reference  
**Purpose:** Complete guide for Gremlin health checks setup

**Contents:**
- Current configuration with monitoring.gremlinpoc.com endpoints
- Prometheus and Grafana health check implementation
- Usage instructions and troubleshooting
- Architecture overview

**Key URLs:**
- Prometheus: `https://monitoring.gremlinpoc.com/prometheus/api/v1/alerts`
- Grafana: `https://monitoring.gremlinpoc.com/api/datasources/proxy/1/api/v1/alerts`

---

### 📚 **HealthChecksExplained.md**
**Status:** API Reference  
**Purpose:** Gremlin health checks API documentation

**Contents:**
- Complete API endpoint documentation
- Authentication methods (Direct vs Integration)
- Platform-specific examples (Prometheus, Grafana, Dynatrace, New Relic)
- Common errors and solutions
- Best practices

**Key Insights:**
- API returns plain UUID on success (not JSON)
- Two authentication approaches available
- Service cleanup important for reinstalls

---

### 📚 **servicediscovery.md**
**Created:** 2025-09-11  
**Status:** Historical Troubleshooting  
**Purpose:** Analysis of Gremlin service discovery EC2 permissions issue

**Root Cause:** Missing `AmazonEC2ReadOnlyAccess` IAM policy on EKS node role

**Key Findings:**
- Gremlin needs both Kubernetes RBAC AND AWS IAM permissions
- EC2 permissions required for cloud metadata collection
- Documentation gap in Gremlin's official docs
- Solution automated in `lib/monitoring.sh`

**Required Permissions:**
- `ec2:DescribeTags` - AWS tag collection
- `ec2:DescribeInstances` - Instance metadata

---

### 📚 **gremlin-lambda-error-analysis.md**
**Created:** 2025-10-03  
**Status:** Historical Analysis  
**Purpose:** Lambda configuration error troubleshooting

**Error Summary:**
- Production Lambda missing TeamID, Certificate, Private Key
- Configuration loaded from SSM Parameter Store incomplete
- Different from example repo (failure-flags-v2-poc)

**Key Learnings:**
- SSM Parameter Store configuration validation
- Lambda vs Kubernetes deployment differences
- Certificate/key management for Lambda deployments

---

### 📚 **CODEBASE_REVIEW_FINDINGS.md**
**Created:** 2025-09-15  
**Status:** Historical Review  
**Purpose:** Codebase review findings and refactoring recommendations

**Key Findings:**
- Script consolidation opportunities identified
- Idempotency issues documented
- Monitoring platform integration patterns
- Cleanup and organization recommendations

**Impact:**
- Led to script reorganization under `scripts/operations/` and `lib/`
- Informed health check implementation
- Guided ALB consolidation strategy

---

## Related Files in Root

### Active Configuration:
- `/cluster-state.json` - Current cluster endpoints
- `/consolidated-demo-ingress.yaml` - Demo frontend ingress
- `/otel-demo-cross-namespace-services.yaml` - Cross-namespace services
- `/workshop.sh` - Main orchestration script

### Build Scripts:
- `/build_scripts/demo/healthchecks.sh` - Health check creation (uses docs from this folder)
- `/build_scripts/demo/cluster-state.json` - Build-specific cluster state

---

## Usage

These documents serve as:
1. **Reference Material** - API patterns, configuration examples
2. **Troubleshooting Guides** - Solutions to known issues
3. **Historical Context** - Why certain decisions were made
4. **Implementation Patterns** - Proven approaches for common tasks

When implementing new features or troubleshooting issues, check these documents first for relevant patterns and solutions.

---

## Maintenance

- Keep documents updated when implementations change
- Add new troubleshooting guides as issues are resolved
- Archive obsolete documents with clear deprecation notes
- Cross-reference related documents for easy navigation
