# Wildcard Certificate Deployment Plan - Option 2

## Overview
This plan implements a wildcard ACM certificate strategy for `*.gremlinpoc.com` that can be reused across all subdomain deployments, eliminating per-subdomain DNS validation delays and making deployments faster and more reliable.

---

## Phase 1: Check for Existing Wildcard Certificate (2 minutes)

### Step 1.1: Search for existing wildcard cert
```bash
aws acm list-certificates --region us-east-2 \
  --query "CertificateSummaryList[?DomainName=='*.gremlinpoc.com'].[DomainName,CertificateArn,Status]" \
  --output table
```

**Expected Outcomes:**
- **If exists and ISSUED**: Skip to Phase 3 (use existing cert)
- **If exists but PENDING_VALIDATION**: Continue to Step 2.4 (validate it)
- **If not exists**: Continue to Step 2.2 (create new one)

**Verification:**
```bash
# Save the ARN if it exists
WILDCARD_CERT_ARN=$(aws acm list-certificates --region us-east-2 \
  --query "CertificateSummaryList[?DomainName=='*.gremlinpoc.com' && Status=='ISSUED'].CertificateArn" \
  --output text)

if [ -n "$WILDCARD_CERT_ARN" ]; then
  echo "✅ Wildcard certificate exists and is ISSUED: $WILDCARD_CERT_ARN"
  echo "Skip to Phase 3"
else
  echo "❌ No issued wildcard certificate found, proceeding to Phase 2"
fi
```

### Step 1.2: Check for any gremlinpoc.com certs
```bash
aws acm list-certificates --region us-east-2 \
  --query "CertificateSummaryList[?contains(DomainName, 'gremlinpoc.com')].[DomainName,CertificateArn,Status]" \
  --output table
```

**Verification:**
- Note any existing certificates
- Check their validation status
- Identify if we can reuse any

---

## Phase 2: Create/Validate Wildcard Certificate (10-15 minutes)

### Step 2.1: Stop current Terraform deployment

```bash
# Find and kill the terraform process
ps aux | grep terraform | grep apply

# Or just Ctrl+C in the terminal where it's running

# Navigate to workspace
cd /Users/seanwiley/terraform/workspace/swcluster

# Clean up the failed certificate resources
terraform destroy \
  -target=module.demo.module.alb.aws_acm_certificate_validation.subdomain \
  -target=module.demo.module.alb.aws_acm_certificate.subdomain \
  -target=module.demo.module.alb.aws_route53_record.subdomain_validation \
  -auto-approve
```

**Verification:**
```bash
# Confirm certificate is deleted
aws acm list-certificates --region us-east-2 \
  --query "CertificateSummaryList[?contains(DomainName, 'swcluster')]" \
  --output table
```

**Expected:** Empty result or no swcluster certificates

### Step 2.2: Create wildcard certificate (one-time setup)

```bash
# Request wildcard certificate
CERT_ARN=$(aws acm request-certificate \
  --domain-name "*.gremlinpoc.com" \
  --subject-alternative-names "gremlinpoc.com" \
  --validation-method DNS \
  --region us-east-2 \
  --tags Key=Name,Value=gremlinpoc-wildcard Key=ManagedBy,Value=manual Key=Purpose,Value=workshop-deployments \
  --query 'CertificateArn' \
  --output text)

echo "Certificate ARN: $CERT_ARN"
echo "export WILDCARD_CERT_ARN=$CERT_ARN" >> ~/.bashrc
```

**Verification:**
```bash
# Check certificate status
aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region us-east-2 \
  --query 'Certificate.Status' \
  --output text
```

**Expected:** `PENDING_VALIDATION`

### Step 2.3: Get validation records

```bash
# Get the DNS validation records
aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region us-east-2 \
  --query 'Certificate.DomainValidationOptions[*].[DomainName,ResourceRecord.Name,ResourceRecord.Value]' \
  --output table
```

**Expected Output:**
```
---------------------------------------------------------
|              DescribeCertificate                      |
+-------------------------------------------------------+
|  *.gremlinpoc.com                                     |
|  _abc123def456.gremlinpoc.com.                        |
|  _xyz789uvw012.acm-validations.aws.                   |
+-------------------------------------------------------+
|  gremlinpoc.com                                       |
|  _abc123def456.gremlinpoc.com.                        |
|  _xyz789uvw012.acm-validations.aws.                   |
+-------------------------------------------------------+
```

**Note:** Both domains use the SAME validation record (this is normal for wildcard + apex)

### Step 2.4: Create validation records in parent zone

```bash
# Get parent zone ID
PARENT_ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='gremlinpoc.com.'].Id" \
  --output text | cut -d'/' -f3)

echo "Parent Zone ID: $PARENT_ZONE_ID"

# Get validation record details
VALIDATION_NAME=$(aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region us-east-2 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Name' \
  --output text)

VALIDATION_VALUE=$(aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region us-east-2 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Value' \
  --output text)

echo "Validation Name: $VALIDATION_NAME"
echo "Validation Value: $VALIDATION_VALUE"

# Create validation record
cat > /tmp/cert-validation.json <<EOF
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$VALIDATION_NAME",
      "Type": "CNAME",
      "TTL": 60,
      "ResourceRecords": [{"Value": "$VALIDATION_VALUE"}]
    }
  }]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id "$PARENT_ZONE_ID" \
  --change-batch file:///tmp/cert-validation.json
```

**Verification:**
```bash
# Check if record was created
aws route53 list-resource-record-sets \
  --hosted-zone-id "$PARENT_ZONE_ID" \
  --query "ResourceRecordSets[?contains(Name, '_')].[Name,Type,ResourceRecords[0].Value]" \
  --output table | grep -A 2 "$VALIDATION_NAME"
```

**Expected:** See the validation CNAME record with correct value

### Step 2.5: Wait for DNS propagation

```bash
# Query the validation record directly from Route53 nameservers
NAMESERVER=$(aws route53 get-hosted-zone \
  --id "$PARENT_ZONE_ID" \
  --query 'DelegationSet.NameServers[0]' \
  --output text)

echo "Querying nameserver: $NAMESERVER"
dig @$NAMESERVER $VALIDATION_NAME CNAME +short
```

**Expected Output:**
```
_xyz789uvw012.acm-validations.aws.
```

**Verification (public DNS):**
```bash
# Check from public DNS (may take 2-5 minutes)
dig $VALIDATION_NAME CNAME +short
```

**Expected:** Same value as above (may take 2-5 minutes to propagate)

**If empty:** Wait 2 minutes and try again. DNS propagation can take up to 5 minutes.

### Step 2.6: Wait for ACM validation

```bash
# Monitor certificate status (check every 30 seconds)
echo "Waiting for ACM validation... (this can take 5-10 minutes)"
while true; do
  STATUS=$(aws acm describe-certificate \
    --certificate-arn "$CERT_ARN" \
    --region us-east-2 \
    --query 'Certificate.Status' \
    --output text)
  
  echo "$(date '+%H:%M:%S') - Status: $STATUS"
  
  if [ "$STATUS" = "ISSUED" ]; then
    echo "✅ Certificate validated successfully!"
    break
  fi
  
  sleep 30
done
```

**Expected Timeline:**
- T+0: PENDING_VALIDATION
- T+2-5 min: Still PENDING_VALIDATION (DNS propagating)
- T+5-10 min: **ISSUED** ✅

**Verification:**
```bash
# Confirm certificate is issued
aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region us-east-2 \
  --query 'Certificate.[Status,DomainValidationOptions[*].ValidationStatus]' \
  --output table
```

**Expected Output:**
```
---------------------------------
|    DescribeCertificate        |
+-------------------------------+
|  ISSUED                       |
+-------------------------------+
||  SUCCESS                    ||
||  SUCCESS                    ||
+-------------------------------+
```

**If stuck at PENDING_VALIDATION after 15 minutes:**
1. Verify DNS record exists: `dig $VALIDATION_NAME CNAME +short`
2. Check ACM validation details: `aws acm describe-certificate --certificate-arn "$CERT_ARN" --query 'Certificate.DomainValidationOptions'`
3. Ensure validation record value matches exactly

---

## Phase 3: Deploy with Wildcard Certificate (10 minutes)

### Step 3.1: Verify Terraform changes are in place

The code changes have already been made to:
- `/Users/seanwiley/gremform/fictional-computing-machine/terraform/modules/alb/main.tf`
- `/Users/seanwiley/gremform/fictional-computing-machine/terraform/modules/alb/vars.tf`
- `/Users/seanwiley/gremform/fictional-computing-machine/terraform/modules/sa_demo/main.tf`
- `/Users/seanwiley/gremform/fictional-computing-machine/terraform/modules/sa_demo/vars.tf`
- `/Users/seanwiley/workshop/lib/terraform.sh`

**Verification:**
```bash
# Check ALB module has certificate_arn variable
grep -A 3 "variable \"certificate_arn\"" \
  /Users/seanwiley/gremform/fictional-computing-machine/terraform/modules/alb/vars.tf

# Check sa_demo module has wildcard_certificate_arn variable
grep -A 3 "variable \"wildcard_certificate_arn\"" \
  /Users/seanwiley/gremform/fictional-computing-machine/terraform/modules/sa_demo/vars.tf

# Check terraform.sh passes the variable
grep "wildcard_certificate_arn" /Users/seanwiley/workshop/lib/terraform.sh
```

**Expected:** All grep commands return matching lines

### Step 3.2: Commit Terraform module changes

```bash
cd /Users/seanwiley/gremform/fictional-computing-machine

git add terraform/modules/alb/main.tf \
        terraform/modules/alb/vars.tf \
        terraform/modules/sa_demo/main.tf \
        terraform/modules/sa_demo/vars.tf

git commit -m "feat: add wildcard certificate support for ALB module

- Add certificate_arn variable to ALB module (optional)
- Use existing wildcard cert if provided, create subdomain cert if not
- Pass wildcard_certificate_arn from sa_demo to ALB module
- Eliminates per-subdomain DNS validation delays
- Makes deployments faster and more reliable"

git push origin HEAD
```

**Verification:**
```bash
git log -1 --oneline
```

**Expected:** See the commit message

### Step 3.3: Clean up and reinitialize Terraform workspace

```bash
cd /Users/seanwiley/terraform/workspace/swcluster

# Remove old state and modules
rm -rf .terraform .terraform.lock.hcl

# Terraform will regenerate these with updated module code
```

**Verification:**
```bash
ls -la
```

**Expected:** No `.terraform` directory

### Step 3.4: Set wildcard certificate ARN environment variable

```bash
# Get the wildcard certificate ARN (from Phase 2)
export WILDCARD_CERT_ARN=$(aws acm list-certificates --region us-east-2 \
  --query "CertificateSummaryList[?DomainName=='*.gremlinpoc.com' && Status=='ISSUED'].CertificateArn" \
  --output text)

echo "Wildcard Certificate ARN: $WILDCARD_CERT_ARN"

# Verify it's set
if [ -z "$WILDCARD_CERT_ARN" ]; then
  echo "❌ ERROR: Wildcard certificate ARN not found or not issued"
  echo "Run Phase 2 to create and validate the certificate"
  exit 1
else
  echo "✅ Wildcard certificate ARN is set"
fi
```

**Verification:**
```bash
aws acm describe-certificate \
  --certificate-arn "$WILDCARD_CERT_ARN" \
  --region us-east-2 \
  --query 'Certificate.[DomainName,Status]' \
  --output table
```

**Expected:**
```
------------------------------
|  DescribeCertificate       |
+----------------------------+
|  *.gremlinpoc.com          |
|  ISSUED                    |
+----------------------------+
```

### Step 3.5: Deploy with wildcard certificate

```bash
cd /Users/seanwiley/workshop

# Clean up old workspace
rm -rf /Users/seanwiley/terraform/workspace/swcluster

# Deploy with wildcard certificate
FCM_LOCAL_PATH="/Users/seanwiley/gremform/fictional-computing-machine" \
TF_VAR_wildcard_certificate_arn="$WILDCARD_CERT_ARN" \
./workshop.sh \
  --action build_new \
  --subdomain swcluster \
  --owner sean.wiley \
  --enable-eks \
  --monitoring grafana
```

**What this does:**
1. Creates new Terraform workspace
2. Generates main.tf with `wildcard_certificate_arn` variable set
3. Initializes Terraform with updated modules
4. Plans infrastructure (should show NO certificate creation)
5. Applies infrastructure (ALB will use existing wildcard cert)

**Verification during apply:**
```bash
# In another terminal, watch the apply progress
tail -f /tmp/terraform-apply-v2.log | grep -E "(certificate|validation|ALB)"
```

**Expected:**
- ✅ NO `aws_acm_certificate.subdomain` creation
- ✅ NO `aws_acm_certificate_validation.subdomain` waiting
- ✅ `aws_lb_listener.https` creates immediately with wildcard cert
- ✅ Deployment completes in ~15 minutes (not 75+ minutes)

### Step 3.6: Monitor deployment progress

```bash
# Check Terraform apply status
cd /Users/seanwiley/terraform/workspace/swcluster
terraform show | grep -A 5 "aws_lb_listener.https"
```

**Expected Timeline:**
- T+0: VPC creation (2 minutes)
- T+2: ALB creation (3 minutes)
- T+5: **HTTPS listener created immediately** (no cert wait!)
- T+5: EKS cluster creation starts (10 minutes)
- T+15: **Deployment complete** ✅

**Verification:**
```bash
# Check ALB is using wildcard certificate
ALB_ARN=$(terraform output -raw alb_dns_name 2>/dev/null | xargs -I {} aws elbv2 describe-load-balancers --query "LoadBalancers[?DNSName=='{}'].LoadBalancerArn" --output text)

aws elbv2 describe-listeners \
  --load-balancer-arn "$ALB_ARN" \
  --query "Listeners[?Port==\`443\`].Certificates[0].CertificateArn" \
  --output text
```

**Expected:** Should match `$WILDCARD_CERT_ARN`

---

## Phase 4: Verification (5 minutes)

### Step 4.1: Verify infrastructure is created

```bash
cd /Users/seanwiley/terraform/workspace/swcluster

# Check Terraform outputs
terraform output
```

**Expected Output:**
```
alb_dns_name = "swcluster-alb-XXXXXXXXXX.us-east-2.elb.amazonaws.com"
cluster_endpoint = "https://XXXXX.gr7.us-east-2.eks.amazonaws.com"
cluster_name = "swcluster-eks"
cluster_region = "us-east-2"
demo_frontend_url = "https://demo-frontend.swcluster.gremlinpoc.com"
monitoring_url = "https://monitoring.swcluster.gremlinpoc.com"
subdomain = "swcluster"
owner = "sean.wiley"
```

### Step 4.2: Verify ALB and certificate

```bash
# Check ALB status
aws elbv2 describe-load-balancers \
  --names swcluster-alb \
  --query 'LoadBalancers[0].[LoadBalancerName,State.Code,DNSName]' \
  --output table

# Check HTTPS listener
ALB_ARN=$(aws elbv2 describe-load-balancers --names swcluster-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text)

aws elbv2 describe-listeners \
  --load-balancer-arn "$ALB_ARN" \
  --query 'Listeners[?Port==`443`].[Port,Protocol,Certificates[0].CertificateArn]' \
  --output table
```

**Expected:**
- ALB state: `active`
- HTTPS listener on port 443
- Certificate ARN matches wildcard cert

### Step 4.3: Verify EKS cluster

```bash
# Check cluster status
aws eks describe-cluster \
  --name swcluster-eks \
  --region us-east-2 \
  --query 'cluster.[name,status,endpoint]' \
  --output table

# Update kubeconfig
aws eks update-kubeconfig \
  --name swcluster-eks \
  --region us-east-2

# Check nodes
kubectl get nodes
```

**Expected:**
- Cluster status: `ACTIVE`
- 3+ nodes in `Ready` state

### Step 4.4: Test HTTPS endpoint

```bash
# Test ALB HTTPS endpoint
ALB_DNS=$(terraform output -raw alb_dns_name)
curl -k -I https://$ALB_DNS

# Check certificate
echo | openssl s_client -connect $ALB_DNS:443 -servername $ALB_DNS 2>/dev/null | openssl x509 -noout -subject -issuer
```

**Expected:**
- HTTP 200 response
- Certificate subject includes `*.gremlinpoc.com`
- Certificate issuer is Amazon

### Step 4.5: Verify DNS records

```bash
# Check subdomain A record
dig swcluster.gremlinpoc.com A +short

# Should resolve to ALB IP addresses
```

**Expected:** Multiple IP addresses (ALB endpoints)

---

## Phase 5: Future Deployments (2 minutes each)

### Using wildcard certificate for future deployments

Now that the wildcard certificate exists and is validated, all future deployments are FAST:

```bash
# Deploy another subdomain (e.g., "demo2")
FCM_LOCAL_PATH="/Users/seanwiley/gremform/fictional-computing-machine" \
TF_VAR_wildcard_certificate_arn="$WILDCARD_CERT_ARN" \
./workshop.sh \
  --action build_new \
  --subdomain demo2 \
  --owner sean.wiley \
  --enable-eks \
  --monitoring grafana
```

**Benefits:**
- ✅ No certificate creation (uses existing wildcard)
- ✅ No DNS validation wait
- ✅ HTTPS listener creates immediately
- ✅ Deployment completes in ~15 minutes (not 75+)
- ✅ Consistent and reliable

---

## Troubleshooting

### Issue: Certificate stuck at PENDING_VALIDATION

**Diagnosis:**
```bash
# Check DNS record exists
dig $VALIDATION_NAME CNAME +short

# Check from Route53 nameservers
NAMESERVER=$(aws route53 get-hosted-zone --id "$PARENT_ZONE_ID" --query 'DelegationSet.NameServers[0]' --output text)
dig @$NAMESERVER $VALIDATION_NAME CNAME +short
```

**Solutions:**
1. **DNS record missing**: Re-run Step 2.4
2. **DNS not propagated**: Wait 5-10 minutes, check again
3. **Wrong validation value**: Verify `$VALIDATION_VALUE` matches ACM's expected value

### Issue: Terraform can't find wildcard certificate

**Diagnosis:**
```bash
# Check environment variable is set
echo $WILDCARD_CERT_ARN

# Check certificate exists and is issued
aws acm describe-certificate --certificate-arn "$WILDCARD_CERT_ARN" --query 'Certificate.Status' --output text
```

**Solutions:**
1. **Variable not set**: Run Step 3.4 again
2. **Certificate not issued**: Run Phase 2 to validate it
3. **Wrong region**: Ensure certificate is in us-east-2

### Issue: ALB listener fails to create

**Diagnosis:**
```bash
# Check Terraform error
cd /Users/seanwiley/terraform/workspace/swcluster
terraform show | grep -A 10 "aws_lb_listener.https"

# Check certificate ARN in Terraform
terraform show | grep certificate_arn
```

**Solutions:**
1. **Invalid certificate ARN**: Verify `$WILDCARD_CERT_ARN` is correct
2. **Certificate not in same region**: ACM certificates must be in same region as ALB
3. **Certificate not issued**: Ensure certificate status is `ISSUED`

---

## Success Criteria

### Phase 2 Complete:
- ✅ Wildcard certificate exists
- ✅ Certificate status is `ISSUED`
- ✅ Validation records in Route53
- ✅ DNS resolves validation record

### Phase 3 Complete:
- ✅ Terraform applies without errors
- ✅ No certificate creation/validation in Terraform
- ✅ ALB created with HTTPS listener
- ✅ HTTPS listener uses wildcard certificate
- ✅ Deployment completes in ~15 minutes

### Phase 4 Complete:
- ✅ ALB is active
- ✅ EKS cluster is active
- ✅ HTTPS endpoint responds
- ✅ Certificate is valid
- ✅ DNS resolves correctly

---

## Timeline Summary

| Phase | Duration | Key Activities |
|-------|----------|----------------|
| Phase 1 | 2 min | Check for existing certificate |
| Phase 2 | 10-15 min | Create and validate wildcard certificate (one-time) |
| Phase 3 | 10 min | Deploy infrastructure with wildcard cert |
| Phase 4 | 5 min | Verify deployment |
| **Total** | **27-32 min** | **First deployment with cert creation** |
| **Future** | **15 min** | **Subsequent deployments (no cert wait)** |

---

## Comparison: Before vs After

### Before (Per-Subdomain Certificates):
- ❌ Create new certificate for each subdomain
- ❌ Wait 75+ minutes for DNS validation (often fails)
- ❌ Subdomain NS delegation issues
- ❌ Unreliable and frustrating
- ⏱️ **Total: 75+ minutes per deployment**

### After (Wildcard Certificate):
- ✅ Create wildcard certificate once
- ✅ Reuse for all subdomains
- ✅ No DNS validation wait
- ✅ Reliable and fast
- ⏱️ **First deployment: 27-32 minutes**
- ⏱️ **Subsequent deployments: 15 minutes**

---

## Next Steps

After successful deployment:

1. **Deploy OpenTelemetry Demo:**
   ```bash
   ./workshop.sh --action deploy_existing --cluster-name swcluster-eks --monitoring grafana
   ```

2. **Save wildcard certificate ARN for future use:**
   ```bash
   echo "export WILDCARD_CERT_ARN=$WILDCARD_CERT_ARN" >> ~/.bashrc
   source ~/.bashrc
   ```

3. **Document the wildcard certificate:**
   - ARN: `$WILDCARD_CERT_ARN`
   - Domain: `*.gremlinpoc.com`
   - Validation record in: `gremlinpoc.com` zone
   - Use for: All workshop subdomain deployments

4. **Update workshop documentation:**
   - Add wildcard certificate to prerequisites
   - Update deployment instructions
   - Add troubleshooting section

---

## Maintenance

### Wildcard Certificate Renewal

ACM automatically renews certificates if:
- ✅ Validation record remains in Route53
- ✅ Certificate is in use (attached to ALB)
- ✅ Certificate is checked regularly by AWS

**Action required:** None - ACM handles renewal automatically

**Monitoring:**
```bash
# Check certificate expiration
aws acm describe-certificate \
  --certificate-arn "$WILDCARD_CERT_ARN" \
  --query 'Certificate.[NotBefore,NotAfter,RenewalEligibility]' \
  --output table
```

### Cleanup

To remove the wildcard certificate (only if no longer needed):

```bash
# List all resources using the certificate
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[*].LoadBalancerArn" \
  --output text | \
  xargs -I {} aws elbv2 describe-listeners \
    --load-balancer-arn {} \
    --query "Listeners[?Certificates[?CertificateArn=='$WILDCARD_CERT_ARN']].LoadBalancerArn" \
    --output text

# If no resources using it, delete
aws acm delete-certificate --certificate-arn "$WILDCARD_CERT_ARN"
```

**Warning:** Only delete if you're sure no deployments are using it!

---

## Summary

This plan implements a **wildcard certificate strategy** that:

1. ✅ **Eliminates DNS validation delays** - Create once, use forever
2. ✅ **Makes deployments reliable** - No more stuck validations
3. ✅ **Speeds up deployments** - 15 minutes vs 75+ minutes
4. ✅ **Simplifies infrastructure** - One certificate for all subdomains
5. ✅ **Reduces complexity** - No per-subdomain zones or certificates
6. ✅ **Matches production patterns** - Industry standard approach

**This is the right solution for the workshop repository.**
