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

# Delete Helm releases (nginx-ingress first to trigger NLB deletion)
echo "Removing Helm releases..."
helm uninstall ingress-nginx -n ingress-nginx --ignore-not-found || true
helm uninstall redis -n default --ignore-not-found || true
helm uninstall keda -n keda --ignore-not-found || true
helm uninstall prometheus -n monitoring --ignore-not-found || true
helm uninstall metrics-server -n kube-system --ignore-not-found || true

# Wait for NLB to be deleted (AWS can take 1-3 minutes)
echo "Waiting for load balancers to be cleaned up..."
echo "This can take 1-3 minutes..."
for i in {1..18}; do
  LB_COUNT=$(kubectl get svc -A -o json 2>/dev/null | grep -c "LoadBalancer" || echo "0")
  if [ "$LB_COUNT" = "0" ]; then
    echo "Load balancers cleaned up."
    break
  fi
  echo "  Still waiting... ($i/18)"
  sleep 10
done

# Delete namespaces to clean up any remaining PVCs
echo "Cleaning up namespaces..."
kubectl delete namespace monitoring --ignore-not-found || true
kubectl delete namespace ingress-nginx --ignore-not-found || true
kubectl delete namespace keda --ignore-not-found || true

# Step 2: Terraform destroy
echo ""
echo "=== Step 2: Destroying AWS Infrastructure ==="
cd "$TERRAFORM_DIR"
terraform destroy

echo ""
echo "=== Teardown Complete ==="
