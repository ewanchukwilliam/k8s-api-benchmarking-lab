#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform/environments/prod"

echo "=== Tearing Down Prod Environment ==="
echo ""
echo "WARNING: This will destroy all AWS resources!"
echo ""
read -p "Are you sure? Type 'destroy' to confirm: " confirm
if [ "$confirm" != "destroy" ]; then
  echo "Aborted."
  exit 1
fi

# Step 1: Remove Kubernetes resources (so load balancers etc. are deleted)
echo ""
echo "=== Step 1: Removing Kubernetes Resources ==="
kubectl delete -k "$PROJECT_ROOT/manifests/overlays/prod" --ignore-not-found || true
kubectl delete -k "$PROJECT_ROOT/grafana" --ignore-not-found || true

# Delete Helm releases
echo "Removing Helm releases..."
helm uninstall redis -n default --ignore-not-found || true
helm uninstall ingress-nginx -n ingress-nginx --ignore-not-found || true
helm uninstall keda -n keda --ignore-not-found || true
helm uninstall prometheus -n monitoring --ignore-not-found || true
helm uninstall metrics-server -n kube-system --ignore-not-found || true

# Wait for load balancers to be deleted
echo "Waiting for load balancers to be cleaned up..."
sleep 30

# Step 2: Terraform destroy
echo ""
echo "=== Step 2: Destroying AWS Infrastructure ==="
cd "$TERRAFORM_DIR"
terraform destroy

echo ""
echo "=== Teardown Complete ==="
