# EKS Deployment Guide

## Prerequisites

### 1. Install AWS CLI v2

**Download and install:**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
cd /tmp && unzip -q awscliv2.zip
sudo /tmp/aws/install
```

**Verify installation:**
```bash
aws --version
# Should show: aws-cli/2.x.x
```

### 2. Install eksctl

**Download and install:**
```bash
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin/
```


## Cluster Configuration

The cluster is configured in `eks-cluster.yaml`:
- **Instance Type:** t2.micro (1 vCPU, 1GB RAM)
- **Nodes:** 1-6 (starts at 1, scales to 6)
- **Region:** us-east-1
- **Storage:** 8GB per node

See `costs.md` for pricing details.

---

## Deployment Steps

### 1. Create EKS Cluster

```bash
eksctl create cluster -f eks-cluster.yaml
```

This takes ~15-20 minutes. It creates:
- EKS control plane
- VPC with subnets
- NAT gateway
- Worker nodes
- Security groups

### 2. Verify Cluster

```bash
kubectl get nodes
kubectl get pods -A
```

### 3. Push Docker Image to Registry

Your local image won't work in EKS. Push to Docker Hub or AWS ECR.

**Option A: Docker Hub**
```bash
docker tag health-service:local YOUR_DOCKERHUB_USERNAME/health-service:latest
docker push YOUR_DOCKERHUB_USERNAME/health-service:latest
```

**Option B: AWS ECR**
```bash
# Create ECR repository
aws ecr create-repository --repository-name health-service

# Get login command
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Tag and push
docker tag health-service:local YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/health-service:latest
docker push YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/health-service:latest
```

### 4. Update Deployment Image

Edit deployment.yaml and change image reference from `health-service:local` to your registry image.

### 5. Deploy Application

```bash
kubectl apply -f eks/
```

This deploys:
- Service (LoadBalancer)
- Deployment (your app)
- HPA (autoscaling)
- Metrics server

### 6. Get LoadBalancer URL

```bash
kubectl get svc health-service
# Look for EXTERNAL-IP column - this is your LoadBalancer DNS
```

Wait a few minutes for the LoadBalancer to provision, then test:

```bash
curl http://EXTERNAL-IP/health
```

---

## Monitoring

**Watch pods:**
```bash
kubectl get pods -w
```

**Watch HPA:**
```bash
kubectl get hpa -w
```

**View logs:**
```bash
kubectl logs -f deployment/health-service
```

**Use k9s:**
```bash
k9s
```

---

## Cleanup

**Delete cluster (stops all charges):**
```bash
eksctl delete cluster -f eks-cluster.yaml
# Or by name:
eksctl delete cluster --name health-service-cluster
```

This removes all resources and stops billing.

---

## TODO

- [ ] Load balancer service.yaml configured
- [ ] Network policies for interpod communication
- [ ] IAM roles with AWS permissions
- [ ] Copy deployment.yaml (update image reference)
- [ ] Copy hpa.yaml
- [ ] Copy components.yaml (metrics-server)

---

## Troubleshooting

**Cluster creation fails:**
- Check AWS credentials: `aws sts get-caller-identity`
- Check IAM permissions
- Check service quotas in AWS console

**Pods not starting:**
- Check events: `kubectl describe pod POD_NAME`
- Check image pull: verify registry credentials
- Check node capacity: `kubectl describe nodes`

**LoadBalancer not working:**
- Wait 5-10 minutes for AWS to provision
- Check security groups allow traffic
- Verify service: `kubectl describe svc health-service`
