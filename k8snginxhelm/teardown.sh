#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Uninstalling Helm Releases ==="

# Uninstall health-service application
echo "Removing health-service..."
helm uninstall health-service 2>/dev/null || echo "health-service not found, skipping"

# Uninstall NGINX ingress controller
echo "Removing nginx-ingress..."
helm uninstall nginx-ingress --namespace ingress-nginx 2>/dev/null || echo "nginx-ingress not found, skipping"

# Uninstall cert-manager
echo "Removing cert-manager..."
helm uninstall cert-manager --namespace cert-manager 2>/dev/null || echo "cert-manager not found, skipping"

# Uninstall cluster autoscaler
echo "Removing cluster-autoscaler..."
helm uninstall cluster-autoscaler --namespace kube-system 2>/dev/null || echo "cluster-autoscaler not found, skipping"

echo ""
echo "=== Waiting for Kubernetes Services to be deleted ==="
# First check if any LoadBalancer services still exist in Kubernetes
MAX_WAIT=180  # 3 minutes max
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  LB_SERVICES=$(kubectl get svc --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace)/\(.metadata.name)"' | wc -l || echo "999")

  if [ "$LB_SERVICES" -eq 0 ]; then
    echo "✅ All Kubernetes LoadBalancer Services deleted"
    break
  fi

  if [ $ELAPSED -eq 0 ]; then
    echo "Found $LB_SERVICES LoadBalancer Service(s) still deleting..."
  fi

  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

if [ "$LB_SERVICES" -ne 0 ]; then
  echo "⚠️  Services still exist after ${ELAPSED}s, checking AWS resources..."
fi

echo ""
echo "=== Waiting for AWS LoadBalancers to be cleaned up ==="
# Now verify AWS LoadBalancers are actually gone
MAX_WAIT=300  # 5 minutes max
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  # Get VPC ID from cluster
  VPC_ID=$(aws ec2 describe-vpcs --region us-east-1 --filters "Name=tag:alpha.eksctl.io/cluster-name,Values=health-service-cluster-v3" --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

  if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
    echo "✅ VPC already deleted or not found"
    break
  fi

  # Count LoadBalancers in the VPC
  LB_COUNT=$(aws elbv2 describe-load-balancers --region us-east-1 2>/dev/null | jq -r --arg vpc "$VPC_ID" '.LoadBalancers[] | select(.VpcId==$vpc) | .LoadBalancerArn' | wc -l || echo "999")

  if [ "$LB_COUNT" -eq 0 ]; then
    echo "✅ All AWS LoadBalancers deleted from VPC"
    break
  fi

  if [ $ELAPSED -eq 0 ]; then
    echo "Found $LB_COUNT LoadBalancer(s) in VPC $VPC_ID"
  fi

  echo "⏳ Still deleting $LB_COUNT LoadBalancer(s)... (${ELAPSED}s elapsed)"
  sleep 15
  ELAPSED=$((ELAPSED + 15))
done

if [ "$LB_COUNT" -ne 0 ] && [ "$VPC_ID" != "None" ]; then
  echo "⚠️  Timeout waiting for LoadBalancers. They may still be deleting..."
  echo "    This might cause CloudFormation deletion to fail."
fi

echo ""
echo "=== Cleaning Up Metrics Server ==="
# Delete EKS managed add-on
eksctl delete addon --cluster health-service-cluster-v3 --name metrics-server --region us-east-1 || true

echo ""
echo "=== Deleting EKS Cluster ==="
# Removed --disable-nodegroup-eviction to allow proper cleanup of pods and dependencies
eksctl delete cluster -f "$SCRIPT_DIR/eks-cluster.yaml" --wait

echo ""
echo "✅ Cluster and all Helm releases deleted successfully!"
echo ""
echo "Optional cleanup:"
echo "  - ECR repository: aws ecr delete-repository --repository-name health-service --force"
echo "  - Route53 records: cd $PROJECT_ROOT/route53 && ./cleanup-hosted-zone.sh"




#      ~/Personal/devops  on    main !5          ▼  at 07:55:53 PM   
# ❯ ./k8snginxhelm/teardown.sh
# === Uninstalling Helm Releases ===
# Removing health-service...
# release "health-service" uninstalled
# Removing nginx-ingress...
# release "nginx-ingress" uninstalled
# Removing cert-manager...
# These resources were kept due to the resource policy:
# [CustomResourceDefinition] challenges.acme.cert-manager.io
# [CustomResourceDefinition] orders.acme.cert-manager.io
# [CustomResourceDefinition] certificaterequests.cert-manager.io
# [CustomResourceDefinition] certificates.cert-manager.io
# [CustomResourceDefinition] clusterissuers.cert-manager.io
# [CustomResourceDefinition] issuers.cert-manager.io
#
# release "cert-manager" uninstalled
# Removing cluster-autoscaler...
# release "cluster-autoscaler" uninstalled
#
# === Waiting for LoadBalancers to be cleaned up ===
#
# === Cleaning Up Metrics Server ===
# 2026-01-11 19:57:53 [ℹ]  Kubernetes version "1.31" in use by cluster "health-service-cluster-v3"
# 2026-01-11 19:57:53 [ℹ]  deleting addon: metrics-server
# 2026-01-11 19:57:54 [ℹ]  deleted addon: metrics-server
# 2026-01-11 19:57:54 [ℹ]  no associated IAM stacks found
#
# === Deleting EKS Cluster ===
# 2026-01-11 19:57:55 [ℹ]  deleting EKS cluster "health-service-cluster-v3"
# 2026-01-11 19:57:56 [ℹ]  will drain 1 unmanaged nodegroup(s) in cluster "health-service-cluster-v3"
# 2026-01-11 19:57:56 [ℹ]  starting parallel draining, max in-flight of 1
# 2026-01-11 19:57:56 [ℹ]  cordon node "ip-10-0-14-96.ec2.internal"
# 2026-01-11 19:57:56 [ℹ]  cordon node "ip-10-0-27-242.ec2.internal"
# 2026-01-11 19:57:56 [ℹ]  cordon node "ip-10-0-40-197.ec2.internal"
# 2026-01-11 19:57:56 [ℹ]  cordon node "ip-10-0-53-253.ec2.internal"
# 2026-01-11 19:57:57 [ℹ]  cordon node "ip-10-0-54-240.ec2.internal"
#
