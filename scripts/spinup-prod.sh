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

# Get outputs from Terraform
CLUSTER_NAME=$(terraform output -raw cluster_name)
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
ECR_REPO_URL=$(terraform output -raw ecr_repository_url)
ACM_CERT_ARN=$(terraform output -raw certificate_arn)

echo ""
echo "=== Configuring kubectl ==="
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

# Step 2: Build and push Docker image to ECR
echo ""
echo "=== Step 2: Building and Pushing Docker Image to ECR ==="
echo "ECR Repository: $ECR_REPO_URL"

# Login to ECR
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "${ECR_REPO_URL%%/*}"

# Build and push
cd "$PROJECT_ROOT"
docker build -t health-service:local .
docker tag health-service:local "$ECR_REPO_URL:latest"
docker push "$ECR_REPO_URL:latest"
echo "Pushed: $ECR_REPO_URL:latest"

# Step 3: Helm - Install platform components
echo ""
echo "=== Step 3: Installing Platform Components ==="

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
# Use --set for ACM cert and node selector override (no sed needed)
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  -f "$HELM_BASE/nginx-ingress-values.yaml" \
  -f "$HELM_PROD/nginx-ingress.yaml" \
  --set "controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-ssl-cert=$ACM_CERT_ARN" \
  --set "controller.nodeSelector.ingress-ready=null"

echo "Installing Redis..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update bitnami
helm upgrade --install redis bitnami/redis \
  --namespace default \
  -f "$HELM_BASE/redis-values.yaml" \
  -f "$HELM_PROD/redis.yaml"

# Step 4: Deploy application
echo ""
echo "=== Step 4: Deploying Application ==="
# Use kustomize edit to set the image (no sed needed)
pushd "$MANIFESTS_PROD" > /dev/null
kustomize edit set image health-service="$ECR_REPO_URL:latest"
popd > /dev/null
kubectl apply -k "$MANIFESTS_PROD"

# Step 5: Grafana dashboards (optional - may not schedule if resources tight)
echo ""
echo "=== Step 5: Installing Grafana Dashboards ==="
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

# Step 6: Update DNS to point to load balancer
echo ""
echo "=== Step 6: Updating DNS ==="
"$SCRIPT_DIR/update-dns.sh"

# Get Load Balancer hostname and domain info
echo ""
echo "=== Access ==="
LB_HOSTNAME=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
DOMAIN=$(cd "$TERRAFORM_DIR" && terraform output -raw domain 2>/dev/null || echo "")

echo "Configure kubectl: aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME"
echo "Load Balancer:     $LB_HOSTNAME"
echo "Domain:            $DOMAIN"
echo "ACM Certificate:   $ACM_CERT_ARN"
echo "ECR Repository:    $ECR_REPO_URL"
echo ""
echo "=== Next Steps ==="
echo "1. Point your domain ($DOMAIN) to the Load Balancer:"
echo "   Create a CNAME record: $DOMAIN -> $LB_HOSTNAME"
echo "   Or use Route53 alias record (Terraform dns module can do this)"
echo ""
echo "2. To update the app later:"
echo "   docker build -t health-service:local . && docker tag health-service:local $ECR_REPO_URL:latest && docker push $ECR_REPO_URL:latest"
echo "   kubectl rollout restart deployment/health-service"
