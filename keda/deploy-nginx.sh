#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

trap 'ec=$?; echo; echo "❌ FAILED (exit $ec) at line $LINENO:"; echo "   $BASH_COMMAND"; echo; exit $ec' ERR

echo "=== Checking for SSL Certificate ==="
SSL_ENABLED=false
if [ -f "$PROJECT_ROOT/route53/.env.route53" ]; then
  source "$PROJECT_ROOT/route53/.env.route53"
  if [ -n "${CERTIFICATE_ARN:-}" ]; then
    CERT_STATUS=$(aws acm describe-certificate \
      --certificate-arn $CERTIFICATE_ARN \
      --region us-east-1 \
      --query 'Certificate.Status' \
      --output text 2>/dev/null || echo "NOT_FOUND")
    if [ "$CERT_STATUS" = "ISSUED" ]; then
      SSL_ENABLED=true
      echo "✅ SSL Certificate found and ready!"
      echo "   Deploying with HTTPS enabled on port 443"
      echo ""
    else
      echo "⚠️  SSL Certificate exists but status: $CERT_STATUS"
      echo "   Deploying with HTTP only (port 80)"
      echo ""
    fi
  fi
fi

echo "=== Building and Pushing to ECR ==="
REGION=$AWS_DEFAULT_REGION
REPO_NAME="health-service"
ECR_IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest"

aws ecr create-repository --repository-name $REPO_NAME --region $REGION 2>/dev/null || true
aws ecr get-login-password --region $REGION | \
docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
cd "$PROJECT_ROOT"
docker build -t health-service:local .
docker tag health-service:local $ECR_IMAGE
docker push $ECR_IMAGE
echo "ECR Image: $ECR_IMAGE"
echo ""

echo "=== Creating EKS Cluster ==="
eksctl create cluster -f "$SCRIPT_DIR/eks-cluster.yaml"
echo ""

echo "=== Deploying Metrics Server ==="
eksctl create addon --cluster health-service-cluster-v3 --name metrics-server --force --region us-east-1 || true
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=120s || {
  echo "⚠️  Metrics-server taking longer than expected, checking status..."
  kubectl get pods -n kube-system -l k8s-app=metrics-server
}
echo ""

echo "=== Installing cert-manager for HTTPS ==="
helm repo add jetstack https://charts.jetstack.io
helm repo update jetstack
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --set global.leaderElection.namespace=cert-manager

kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager -n cert-manager --timeout=120s
echo ""

echo "=== Creating Let's Encrypt ClusterIssuer ==="
kubectl apply -f "$SCRIPT_DIR/letsencrypt-issuer.yaml"
echo ""

echo "=== Deploying Cluster Autoscaler ==="
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update autoscaler
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=health-service-cluster-v3 \
  --set awsRegion=us-east-1 \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.skip-nodes-with-system-pods=false \
  --set rbac.create=true
echo ""

echo "=== Installing NGINX Ingress Controller ==="
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update ingress-nginx
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.config.allow-snippet-annotations=true \
  --set controller.metrics.enabled=true \
  --set controller.metrics.port=10254 \
  --set controller.metrics.serviceMonitor.enabled=true \
  --set controller.metrics.serviceMonitor.namespace=monitoring \
  --set controller.podAnnotations."prometheus\.io/scrape"=true \
  --set controller.podAnnotations."prometheus\.io/port"=10254 \
  --set controller.podAnnotations."prometheus\.io/path"=/metrics

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
echo ""

echo "=== Installing Prometheus + Grafana Stack ==="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f "$SCRIPT_DIR/prometheus-values.yaml"

echo "Waiting for Prometheus to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=180s || {
  echo "⚠️  Prometheus taking longer than expected..."
  kubectl get pods -n monitoring
}
echo ""

echo ""

echo "=== Applying Grafana Dashboard ==="
kubectl apply -f "$SCRIPT_DIR/grafana-keda-dashboard.yaml"
echo ""

echo "=== Installing KEDA ==="
helm repo add kedacore https://kedacore.github.io/charts
helm repo update kedacore
helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  -f "$SCRIPT_DIR/keda-values.yaml"

echo "Waiting for KEDA to be ready..."
kubectl wait --for=condition=ready pod -l app=keda-operator -n keda --timeout=120s
echo ""

echo "=== Deploying Health Service Application ==="
ECR_REPO="$AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME"

# Deploy WITHOUT HPA (KEDA will manage scaling)
if [ "$SSL_ENABLED" = true ]; then
  helm install health-service "$SCRIPT_DIR/health-service" \
    --set image.repository="$ECR_REPO" \
    --set image.tag=latest \
    --set service.ssl.enabled=true \
    --set service.ssl.certificateArn="${CERTIFICATE_ARN:-}" \
    --set autoscaling.enabled=false
else
  helm install health-service "$SCRIPT_DIR/health-service" \
    --set image.repository="$ECR_REPO" \
    --set image.tag=latest \
    --set service.ssl.enabled=false \
    --set autoscaling.enabled=false
fi

echo "Waiting for application pods to be ready..."
kubectl wait --for=condition=ready pod --selector=app=health-service --timeout=120s
echo ""

echo "Waiting for Redis to be ready..."
kubectl wait --for=condition=ready pod --selector=app=redis --timeout=120s
echo ""

echo "=== Applying KEDA ScaledObject ==="
kubectl apply -f "$SCRIPT_DIR/keda-scaled-object.yaml"
echo ""

echo "=== Cluster Status ==="
kubectl get nodes
echo ""
kubectl get pods -A
echo ""

echo "=== Services ==="
kubectl get svc -A
echo ""

echo "=== KEDA ScaledObject Status ==="
kubectl get scaledobject -n default
kubectl get hpa -n default
echo ""

echo "=== LoadBalancer URL ==="
NLB_HOSTNAME=$(kubectl get svc nginx-ingress-ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "NLB: $NLB_HOSTNAME"
echo ""

# Update DNS if Route 53 is configured
if [ -f "$PROJECT_ROOT/route53/.env.route53" ]; then
  source "$PROJECT_ROOT/route53/.env.route53"
  echo "=== Updating DNS ==="
  "$PROJECT_ROOT/route53/update-dns.sh" api "$NLB_HOSTNAME"
  echo ""

  echo "=== Your Endpoints ==="
  echo "App:        https://api.$DOMAIN/health"
  echo "Prometheus: kubectl port-forward -n monitoring svc/prometheus-prometheus 9090:9090"
  echo "Grafana:    kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
  echo "            Login: admin / admin"
  echo ""
else
  echo "=== DNS Update Skipped ==="
  echo "Route 53 not configured. Run route53/setup-hosted-zone.sh to enable automatic DNS."
  echo ""
  echo "=== Access Monitoring ==="
  echo "Prometheus: kubectl port-forward -n monitoring svc/prometheus-prometheus 9090:9090"
  echo "Grafana:    kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
  echo ""
fi

echo "✅ Deployment complete with KEDA event-driven autoscaling!"
