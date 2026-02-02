#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform/environments/prod"
HELM_BASE="$PROJECT_ROOT/helm/base"
HELM_PROD="$PROJECT_ROOT/helm/prod"
MANIFESTS_PROD="$PROJECT_ROOT/manifests/overlays/prod"

echo "=== Setting up Prod Environment (EKS) ==="

# Step 1: Terraform - Create infrastructure
echo ""
echo "=== Step 1: Creating AWS Infrastructure with Terraform ==="
cd "$TERRAFORM_DIR"

terraform init
terraform plan -out=tfplan
echo ""
read -p "Apply this plan? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
  echo "Aborted."
  exit 1
fi

terraform apply tfplan

# Get cluster name and configure kubectl
CLUSTER_NAME=$(terraform output -raw cluster_name)
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

echo ""
echo "=== Configuring kubectl ==="
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

# Step 2: Helm - Install platform components
echo ""
echo "=== Step 2: Installing Platform Components ==="

echo "Installing Metrics Server..."
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update metrics-server
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system

echo "Installing Prometheus + Grafana..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f "$HELM_BASE/prometheus-local.yaml" \
  -f "$HELM_PROD/prometheus.yaml"

echo "Installing KEDA..."
helm repo add kedacore https://kedacore.github.io/charts
helm repo update kedacore
helm upgrade --install keda kedacore/keda \
  --namespace keda \
  --create-namespace

echo "Installing NGINX Ingress Controller..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  -f "$HELM_BASE/nginx-ingress-values.yaml"

echo "Installing Redis..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update bitnami
helm upgrade --install redis bitnami/redis \
  --namespace default \
  -f "$HELM_BASE/redis-values.yaml" \
  -f "$HELM_PROD/redis.yaml"

# Step 3: Deploy application
echo ""
echo "=== Step 3: Deploying Application ==="
kubectl apply -k "$MANIFESTS_PROD"

# Step 4: Grafana dashboards
echo ""
echo "=== Step 4: Installing Grafana Dashboards ==="
kubectl apply -k "$PROJECT_ROOT/grafana"

# Wait for components
echo ""
echo "=== Waiting for components ==="
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=keda-operator -n keda --timeout=180s || true
kubectl wait --for=condition=ready pod --selector=app=health-service --timeout=120s || true

echo ""
echo "=== Status ==="
kubectl get pods
kubectl get pods -n monitoring
kubectl get pods -n keda
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx

echo ""
echo "=== Access ==="
echo "Configure kubectl: aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME"
echo "Get Load Balancer: kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
