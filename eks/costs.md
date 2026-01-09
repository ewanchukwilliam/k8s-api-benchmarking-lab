# EKS Cluster Costs (us-east-1)

## Total Monthly Costs

| Scenario | Cost | What's Running |
|----------|------|----------------|
| **Cluster Not Deployed** | **$0** | Nothing - cluster deleted |
| **Minimum Usage (1 node)** | **$130/month** | 1 node, minimal traffic |
| **Maximum Usage (6 nodes)** | **$175/month** | 6 nodes, high traffic |
| **Baseline Running** | **$130-150/month** | 1-3 nodes typical |

## With Free Tier (First 12 Months)
| Scenario | Cost |
|----------|------|
| **Minimum Usage** | **$104/month** |
| **Maximum Usage** | **$149/month** |

---

## Cost Breakdown by Component

### Always Running (When Cluster Exists)
- EKS Control Plane: **$72/month**
- NAT Gateway: **$32/month**
- Load Balancer: **$16-18/month**
- **Subtotal: ~$120/month** (before any nodes)

### Per Node (t2.micro)
- EC2 Instance: **$8.50/month**
- EBS Storage (8GB): **$0.80/month**
- **Per Node Total: ~$9.30/month**

### Scaling Costs
- 1 node: +$9.30 = **$130/month total**
- 6 nodes: +$55.80 = **$175/month total**

---

## Data Transfer (Networking Tiers)

| Transfer Type | First Tier | Additional |
|---------------|------------|------------|
| Data IN (from internet) | **Free** | Always free |
| Data OUT (to internet) | **First 100GB free** | $0.09/GB |
| Between AZs (same region) | **$0.01/GB** | Both directions |
| Between Regions | **$0.02/GB** | Both directions |
| NAT Gateway Processing | **$0.045/GB** | All traffic through NAT |

### Example Monthly Data Costs
- 100GB out: **$0** (free tier)
- 500GB out: **$36** (400GB × $0.09)
- 1TB out: **$81** (900GB × $0.09)

---

## Key Takeaways

**Not Deployed:** $0
**Running (minimum):** ~$130/month
**Running (maximum):** ~$175/month

**To stop all charges:** Delete the entire cluster with `eksctl delete cluster`
