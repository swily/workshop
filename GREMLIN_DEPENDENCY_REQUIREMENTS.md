# Gremlin Dependency Detection Requirements

## Critical Requirement: 2+ Replicas

**Gremlin requires at least 2 replicas of each service to detect dependencies.**

From Gremlin documentation:
> "Gremlin must detect the same dependency on at least two replicas of the service to make it available for testing."

---

## How Dependency Detection Works

1. **DNS Monitoring** - Every 30 seconds, Gremlin monitors UDP port 53 (DNS traffic)
2. **Socket Polling** - Every 5 seconds, polls the host/container socket table
3. **Matching** - Matches open sockets to DNS network traffic
4. **Reporting** - Sends DNS name, IP address, and port to Gremlin Control Plane
5. **Validation** - Must find the same dependency on **at least 2 replicas**

---

## Fix Applied

### Before (Bug)
All services had **1 replica** → No dependencies detected

### After (Fixed)
Key services scaled to **2 replicas**:
- frontend
- frontendProxy
- checkoutService
- cartService
- productCatalogService
- recommendationService
- adService
- currencyService
- paymentService
- shippingService
- emailService

### Implementation
Added to `/Users/seanwiley/workshop/scripts/operations/deploy_otel.sh`:

```yaml
# Scale services to 2 replicas for Gremlin dependency detection
# Gremlin requires at least 2 replicas to detect dependencies
components:
  frontend:
    replicas: 2
  frontendProxy:
    replicas: 2
  checkoutService:
    replicas: 2
  cartService:
    replicas: 2
  productCatalogService:
    replicas: 2
  recommendationService:
    replicas: 2
  adService:
    replicas: 2
  currencyService:
    replicas: 2
  paymentService:
    replicas: 2
  shippingService:
    replicas: 2
  emailService:
    replicas: 2
```

---

## Timeline for Dependency Detection

| Event | Time |
|-------|------|
| Services scaled to 2 replicas | T+0 |
| Socket polling starts | T+5s |
| DNS monitoring starts | T+30s |
| Traffic flows between services | T+1m |
| Dependencies detected | T+5-15m |
| **Full discovery cycle** | **Up to 1 hour** |

**Note**: Gremlin discovers services and updates characteristics once per hour.

---

## Verification

### Check Replica Counts
```bash
kubectl get deploy -n otel-demo -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.replicas}{"\n"}{end}' | grep -E "frontend|checkout|cart|product|recommend|payment|shipping|email|currency|adservice"
```

### Check Dependencies in Gremlin
```bash
curl -s -X GET \
  "https://api.gremlin.com/v1/services?teamId=YOUR_TEAM_ID" \
  -H "Authorization: Key YOUR_API_KEY" | \
  jq '[.items[] | {name, dependencies: (.dependencies // [] | length)}] | sort_by(.name)'
```

### Expected Result
After 5-60 minutes, services should show dependencies:
- frontend → adService, cartService, checkoutService, etc.
- checkoutService → cartService, currencyService, emailService, paymentService, productCatalogService, shippingService

---

## Troubleshooting

### No Dependencies After 1 Hour

**Check 1: Replica Count**
```bash
kubectl get deploy -n otel-demo
```
All key services should have `2/2` ready replicas.

**Check 2: Traffic Flow**
```bash
# Check load generator
kubectl logs -n otel-demo -l app.kubernetes.io/name=opentelemetry-demo-loadgenerator --tail=5

# Check Locust stats
kubectl port-forward -n otel-demo svc/opentelemetry-demo-loadgenerator 8089:8089
# Visit http://localhost:8089
```

**Check 3: Gremlin Agent Configuration**
```bash
kubectl get daemonset gremlin -n gremlin -o jsonpath='{.spec.template.spec.containers[0].env}' | jq '.[] | select(.name | contains("COLLECT"))'
```
Should show:
- `GREMLIN_COLLECT_DNS: "true"`
- `GREMLIN_COLLECT_PODS: "true"`

**Check 4: Service Discovery**
```bash
curl -s -X GET \
  "https://api.gremlin.com/v1/services?teamId=YOUR_TEAM_ID" \
  -H "Authorization: Key YOUR_API_KEY" | jq '.items | length'
```
Should return 20+ services.

---

## FAQ

**Q: Why 2 replicas specifically?**  
A: Gremlin uses this as a validation mechanism to avoid false positives from one-off connections or health checks.

**Q: Can I manually add dependencies?**  
A: Yes, if automatic detection fails, you can add dependencies manually in the Gremlin UI.

**Q: How long does it take?**  
A: Initial detection: 5-15 minutes. Full discovery cycle: up to 1 hour.

**Q: What if I only have 1 replica?**  
A: Dependencies will NOT be detected. You must scale to at least 2 replicas.

**Q: Does this apply to all services?**  
A: Only to services you want to test dependencies for. Infrastructure services (Redis, Kafka, etc.) don't need 2 replicas for dependency detection.

---

## Related Documentation

- Gremlin Dependency Detection: https://www.gremlin.com/docs/reliability-management/dependency-detection
- Service Discovery Recipe: `/Users/seanwiley/workshop/GREMLIN_SERVICE_DISCOVERY_RECIPE.md`
- Deployment Complete: `/Users/seanwiley/workshop/DEPLOYMENT_COMPLETE.md`

---

## Status

✅ **Fixed**: All services now deploy with 2 replicas by default  
✅ **Automated**: Included in `deploy_otel.sh` script  
✅ **Verified**: Services scaled and running  
⏱️ **Pending**: Dependencies will appear within 5-60 minutes
