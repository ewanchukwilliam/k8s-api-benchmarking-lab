#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Cleaning Up Metrics Server ==="
# Delete metrics-server to avoid config conflicts on next deployment
kubectl delete deployment metrics-server -n kube-system --ignore-not-found=true
kubectl delete apiservice v1beta1.metrics.k8s.io --ignore-not-found=true
echo ""

echo "=== Deleting EKS Cluster ==="
eksctl delete cluster -f "$SCRIPT_DIR/eks-cluster.yaml" --disable-nodegroup-eviction

echo "Cluster deleted successfully!"
