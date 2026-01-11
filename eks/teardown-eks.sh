#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Cleaning Up Metrics Server ==="
# Delete EKS managed add-on (cleaner than manual kubectl deletes)
eksctl delete addon --cluster health-service-cluster-v2 --name metrics-server --region us-east-1 || true
echo ""

echo "=== Deleting EKS Cluster ==="
eksctl delete cluster -f "$SCRIPT_DIR/eks-cluster.yaml" --disable-nodegroup-eviction

echo "Cluster deleted successfully!"
