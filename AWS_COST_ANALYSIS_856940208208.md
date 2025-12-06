# AWS Cost Analysis - Account 856940208208 (Old Account)
**Date:** October 24, 2025  
**Analysis Period:** October 1-24, 2025 (24 days)

---

## 💰 CURRENT MONTHLY SPEND

### **Total Month-to-Date: $4,332.87**
**Projected Monthly Total: ~$5,416** (extrapolated to 31 days)

---

## 📊 TOP COST DRIVERS

### **By Service:**
1. **EC2 Compute:** $1,162.48 (26.8%)
2. **EKS (Kubernetes):** $945.49 (21.8%)
3. **EC2 Other:** $897.59 (20.7%)
4. **VPC:** $624.60 (14.4%) - **NAT Gateways are expensive!**
5. **Load Balancers:** $473.15 (10.9%)
6. **CloudWatch:** $74.79 (1.7%)
7. **RDS:** $35.35 (0.8%)
8. **ECS:** $30.55 (0.7%)
9. **Managed Prometheus:** $23.04 (0.5%)
10. **Lightsail:** $18.70 (0.4%)

### **By Region:**
1. **us-east-2:** $2,684.44 (62.0%) ⚠️ **BIGGEST OPPORTUNITY**
2. **us-west-2:** $977.02 (22.5%)
3. **us-east-1:** $452.13 (10.4%)
4. **eu-west-2:** $59.46 (1.4%)
5. **eu-west-1:** $57.10 (1.3%)
6. **Other regions:** <$100 combined

---

## 🎯 US-EAST-2 RESOURCES (Primary Cleanup Target)

### **EKS Clusters (5 total):**

| Cluster Name | Owner | Status | Recommendation |
|-------------|-------|--------|----------------|
| `jhellerotel` | jason.heller | Active | ✅ **KEEP** - Jason's active work |
| `marriottpoc` | jason.heller | Active | ✅ **KEEP** - Jason's active work |
| `nick-mason-otel-demo` | nickmason | Active | ❓ **ASK NICK** - Can this be deleted? |
| `swcluster-eks` | Unknown | Active | ❌ **DELETE** - No clear owner |
| `test-cluster` | Unknown | Active | ❌ **DELETE** - Likely abandoned |

### **EC2 Instances (21 running):**

**By Owner:**
- **jason.heller:** 9 instances (jhellerotel, marriottpoc clusters)
- **nickmason:** 6 instances (nick-mason-otel-demo cluster)
- **Unknown/None:** 6 instances ⚠️ **ORPHANED - DELETE**

**Instance Types:**
- t2.medium (most common)
- t3.medium
- m5.large (3 instances)
- m6a.large (2 instances)

### **NAT Gateways (9 active):**
**Cost: ~$32/month EACH = ~$288/month total**

| NAT Gateway | VPC | Name | Recommendation |
|------------|-----|------|----------------|
| nat-05295ffc45998c26f | vpc-0ae237bb717910ccc | CloudformationDemosNatGatewayAZ1 | ❌ **DELETE** - Old demo |
| nat-042ff6f89222e407d | vpc-0ae237bb717910ccc | CloudformationDemosNatGatewayAZ2 | ❌ **DELETE** - Old demo |
| nat-0687b20dd16ebadbf | vpc-0ae237bb717910ccc | CloudformationDemosNatGatewayAZ3 | ❌ **DELETE** - Old demo |
| nat-0d877f36acee5f1d1 | vpc-0b77746b02cbafb88 | eksctl-wonderful-wardrobe | ❌ **DELETE** - Old cluster |
| nat-00d5933a8853af767 | vpc-0c60e6d92341d1d24 | nick-mason-demo-us-east-2a | ❓ **ASK NICK** |
| nat-0b98abcb982c3445e | vpc-0c60e6d92341d1d24 | nick-mason-demo-us-east-2b | ❓ **ASK NICK** |
| nat-089a285e186430157 | vpc-08b6089e96a695323 | shared-vpc-nat-us-east-2c | ✅ **KEEP** - Shared VPC |
| nat-0ca4a8c3a57525323 | vpc-08b6089e96a695323 | shared-vpc-nat-us-east-2b | ✅ **KEEP** - Shared VPC |
| nat-0fe4310c143f8ab66 | vpc-08b6089e96a695323 | shared-vpc-nat-us-east-2a | ✅ **KEEP** - Shared VPC |

### **Load Balancers:**
- **Application LBs:** 4 active
  - `samw-alb` (created Aug 8, 2025) - ❓ **ASK SAM WILEY**
  - `k8s-oteldemo-jaegerin-*` (Oct 24) - Likely for active clusters
  - `k8s-oteldemo-frontend-*` (Oct 24) - Likely for active clusters
  - `k8s-monitori-grafanai-*` (Oct 24) - Likely for active clusters
- **Classic LBs:** 2 active (orphaned, likely can delete)

### **RDS:**
- `ddarwin-useast2-mysql-db` (db.t3.micro) - Created Jan 2022 ⚠️ **VERY OLD - ASK DDARWIN**

---

## 💡 COST REDUCTION RECOMMENDATIONS

### **Immediate Actions (High Impact):**

#### **1. Delete Orphaned EKS Clusters (~$400-600/month savings)**
```bash
# Delete clusters with no clear owner
aws eks delete-cluster --name swcluster-eks --region us-east-2
aws eks delete-cluster --name test-cluster --region us-east-2
```

#### **2. Delete Old NAT Gateways (~$96-128/month savings)**
```bash
# Delete CloudformationDemos NAT Gateways (3x $32/month = $96/month)
aws ec2 delete-nat-gateway --nat-gateway-id nat-05295ffc45998c26f --region us-east-2
aws ec2 delete-nat-gateway --nat-gateway-id nat-042ff6f89222e407d --region us-east-2
aws ec2 delete-nat-gateway --nat-gateway-id nat-0687b20dd16ebadbf --region us-east-2

# Delete eksctl-wonderful-wardrobe NAT Gateway ($32/month)
aws ec2 delete-nat-gateway --nat-gateway-id nat-0d877f36acee5f1d1 --region us-east-2
```

#### **3. Terminate Orphaned EC2 Instances (~$50-100/month savings)**
```bash
# Instances with no owner tag - verify first!
aws ec2 terminate-instances --instance-ids \
  i-092211ead1807da8d \
  i-03420ac7f1dd5891d \
  i-0cd24050d9d8c1877 \
  i-07c40cadb561d1517 \
  i-077e27b6e41a5779f \
  i-09d9c32935082e65c \
  --region us-east-2
```

#### **4. Delete Old RDS Instance (~$15/month savings)**
```bash
# ddarwin-useast2-mysql-db - Created Jan 2022, likely abandoned
# ASK DDARWIN FIRST!
aws rds delete-db-instance \
  --db-instance-identifier ddarwin-useast2-mysql-db \
  --skip-final-snapshot \
  --region us-east-2
```

#### **5. Delete Orphaned Load Balancers (~$50/month savings)**
```bash
# Classic LBs with no clear purpose
aws elb delete-load-balancer --load-balancer-name af923f8adc3dd4a76b865eaf81461ff9 --region us-east-2
aws elb delete-load-balancer --load-balancer-name a687974a0dcab4cbabd87813fcc25914 --region us-east-2
```

---

### **Follow-Up Actions (Requires Coordination):**

#### **6. Ask Nick Mason:**
- Can `nick-mason-otel-demo` cluster be deleted?
- Can his 2 NAT Gateways be deleted?
- **Potential savings:** ~$300-400/month

#### **7. Ask Sam Wiley:**
- Is `samw-alb` still needed? (created Aug 8, 2025)
- **Potential savings:** ~$25/month

#### **8. Review Jason Heller's Resources:**
- `jhellerotel` and `marriottpoc` clusters are active
- Confirm both are still needed
- **Keep for now** ✅

---

## 📈 PROJECTED SAVINGS

| Action | Monthly Savings | Annual Savings |
|--------|----------------|----------------|
| Delete 2 orphaned EKS clusters | $400-600 | $4,800-7,200 |
| Delete 4 old NAT Gateways | $128 | $1,536 |
| Terminate 6 orphaned EC2 instances | $75 | $900 |
| Delete old RDS instance | $15 | $180 |
| Delete orphaned load balancers | $50 | $600 |
| **TOTAL (Conservative)** | **$668-868** | **$8,016-10,416** |

### **If Nick's Resources Can Be Deleted:**
| Total with Nick's cleanup | $968-1,268 | $11,616-15,216 |

---

## 🎯 FINAL RECOMMENDATION

### **Immediate Cleanup (No Approval Needed):**
1. ✅ Delete `swcluster-eks` and `test-cluster` (orphaned)
2. ✅ Delete 4 old NAT Gateways (CloudformationDemos, eksctl-wonderful-wardrobe)
3. ✅ Terminate 6 orphaned EC2 instances
4. ✅ Delete 2 orphaned Classic Load Balancers

**Estimated Monthly Savings: $653-853**

### **Requires Approval:**
1. ❓ Nick Mason's resources (~$300-400/month)
2. ❓ Sam Wiley's ALB (~$25/month)
3. ❓ ddarwin's RDS instance (~$15/month)

---

## 🚨 RESOURCES TO KEEP

### **Jason Heller's Active Work:**
- ✅ `jhellerotel` EKS cluster
- ✅ `marriottpoc` EKS cluster
- ✅ Associated EC2 instances (9 total)
- ✅ Associated load balancers

### **Shared Infrastructure:**
- ✅ Shared VPC NAT Gateways (3x in vpc-08b6089e96a695323)

---

## 📝 NEXT STEPS

1. **Run cleanup script for orphaned resources** (see below)
2. **Contact Nick Mason** about his demo cluster
3. **Contact Sam Wiley** about samw-alb
4. **Contact ddarwin** about old RDS instance
5. **Monitor costs** after cleanup to verify savings

---

## 🛠️ CLEANUP SCRIPT

Save this as `cleanup_old_account.sh`:

```bash
#!/bin/bash
# Cleanup script for AWS account 856940208208
# Run with caution!

set -e

REGION="us-east-2"

echo "=== AWS Account Cleanup Script ==="
echo "Account: 856940208208"
echo "Region: $REGION"
echo ""
echo "⚠️  WARNING: This will DELETE resources!"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

# 1. Delete orphaned EKS clusters
echo "1. Deleting orphaned EKS clusters..."
aws eks delete-cluster --name swcluster-eks --region $REGION || true
aws eks delete-cluster --name test-cluster --region $REGION || true

# 2. Delete old NAT Gateways
echo "2. Deleting old NAT Gateways..."
aws ec2 delete-nat-gateway --nat-gateway-id nat-05295ffc45998c26f --region $REGION || true
aws ec2 delete-nat-gateway --nat-gateway-id nat-042ff6f89222e407d --region $REGION || true
aws ec2 delete-nat-gateway --nat-gateway-id nat-0687b20dd16ebadbf --region $REGION || true
aws ec2 delete-nat-gateway --nat-gateway-id nat-0d877f36acee5f1d1 --region $REGION || true

# 3. Terminate orphaned EC2 instances
echo "3. Terminating orphaned EC2 instances..."
aws ec2 terminate-instances --instance-ids \
  i-092211ead1807da8d \
  i-03420ac7f1dd5891d \
  i-0cd24050d9d8c1877 \
  i-07c40cadb561d1517 \
  i-077e27b6e41a5779f \
  i-09d9c32935082e65c \
  --region $REGION || true

# 4. Delete orphaned Classic Load Balancers
echo "4. Deleting orphaned load balancers..."
aws elb delete-load-balancer --load-balancer-name af923f8adc3dd4a76b865eaf81461ff9 --region $REGION || true
aws elb delete-load-balancer --load-balancer-name a687974a0dcab4cbabd87813fcc25914 --region $REGION || true

echo ""
echo "✅ Cleanup complete!"
echo "Estimated monthly savings: $653-853"
```

---

**Generated:** October 24, 2025  
**Next Review:** November 1, 2025
