# Deploy and Undeploy EKS Cluster

## Spin Up Cluster (Start Billing)

```bash
eksctl create cluster -f eks-cluster.yaml
```

**Time:** ~15-20 minutes
**Cost:** ~$130/month (starts immediately)

**What it creates:**
- EKS control plane
- VPC with subnets and NAT gateway
- 1 t2.micro worker node (scales to 6)
- Security groups and IAM roles

**Verify cluster is running:**
```bash
eksctl get cluster
kubectl get nodes
```

---

## Spin Down Cluster (Stop All Charges)

```bash
eksctl delete cluster -f eks-cluster.yaml
```

**Or by name:**
```bash
eksctl delete cluster --name health-service-cluster
```

**Time:** ~5-10 minutes
**Cost:** $0 (billing stops once deleted)

**What it removes:**
- Everything (cluster, nodes, VPC, NAT gateway, etc.)
- All deployed applications
- All data/state

---

## Check Cluster Status

```bash
# List all clusters
eksctl get cluster

# Get node info
kubectl get nodes

# Get all pods
kubectl get pods -A

# Get cluster details
kubectl cluster-info
```

---

## Important Notes

⚠️ **Once spun up, you're paying ~$130/month until you spin down**

⚠️ **Spinning down deletes everything** - you'll need to redeploy your app if you spin up again

✓ **Always spin down when not in use** to avoid charges

✓ **Check AWS console** after deletion to ensure all resources are removed
