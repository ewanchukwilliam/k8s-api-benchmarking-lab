#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Deleting EKS Cluster ==="
eksctl delete cluster -f "$SCRIPT_DIR/eks-cluster.yaml" --disable-nodegroup-eviction

echo "Cluster deleted successfully!"
