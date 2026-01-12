#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"


echo "=== Checking for SSL Certificate ==="
SSL_ENABLED=false
if [ -f "$PROJECT_ROOT/route53/.env.route53" ]; then
  source "$PROJECT_ROOT/route53/.env.route53"
  if [ -n "$CERTIFICATE_ARN" ]; then
    # Check certificate status
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

echo "=== Building and Pushing to ECR DOCKER STUFF ==="
REGION=$AWS_DEFAULT_REGION
REPO_NAME="health-service"
ECR_IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest"

echo "=== Building and Pushing to ECR ==="
aws ecr create-repository --repository-name $REPO_NAME --region $REGION 2>/dev/null || true
aws ecr get-login-password --region $REGION | \
docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
cd "$PROJECT_ROOT"
docker build -t health-service:local .
docker tag health-service:local $ECR_IMAGE
docker push $ECR_IMAGE
echo "ECR Image: $ECR_IMAGE"
echo ""

# Uncomment to update pods quickly (comment everything else out for a running deployment)
# kubectl rollout restart deployment health-service

echo "=== Creating EKS remote cluster ==="
eksctl create cluster -f "$SCRIPT_DIR/eks-cluster.yaml"
echo ""

echo "=== Deploying Metrics Server ==="
echo "Installing metrics-server as EKS managed add-on..."
eksctl create addon --cluster health-service-cluster-v3 --name metrics-server --force --region us-east-1 || true
echo "Waiting for metrics-server to be ready..."
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=120s || {
  echo "⚠️  Metrics-server taking longer than expected, checking status..."
  kubectl get pods -n kube-system -l k8s-app=metrics-server
}
echo ""

echo "=== Installing cert-manager for HTTPS ==="
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --set global.leaderElection.namespace=cert-manager

echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager -n cert-manager --timeout=120s
echo ""

echo "=== Creating Let's Encrypt ClusterIssuer ==="
kubectl apply -f "$SCRIPT_DIR/letsencrypt-issuer.yaml"
echo ""

echo "=== Deploying Cluster Autoscaler via Helm ==="
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=health-service-cluster-v3 \
  --set awsRegion=us-east-1 \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.skip-nodes-with-system-pods=false \
  --set rbac.create=true
echo ""

echo "=== Installing NGINX Ingress Controller via Helm ==="
# Add the ingress-nginx repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
# Install NGINX ingress controller with autoscaling
# For EKS, use LoadBalancer service type (default)
# For kind/local, use NodePort (see values-local.yaml)
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.config.allow-snippet-annotations=true \
  --set controller.autoscaling.enabled=true \
  --set controller.autoscaling.minReplicas=2 \
  --set controller.autoscaling.maxReplicas=10 \
  --set controller.autoscaling.targetCPUUtilizationPercentage=70
echo ""

echo "=== Waiting for NGINX controller to be ready ==="
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

echo ""
echo "=== NGINX Ingress Controller Status ==="
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
kubectl get hpa -n ingress-nginx

echo ""
echo "=== LoadBalancer URL ==="
kubectl get svc nginx-ingress-ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo ""

echo "=== Deploying Health Service Application via Helm ==="

# Check if SSL certificate is available
SSL_ENABLED=false
if [ -f "$PROJECT_ROOT/route53/.env.route53" ]; then
  source "$PROJECT_ROOT/route53/.env.route53"

  if [ -n "$CERTIFICATE_ARN" ]; then
    # Check certificate status
    CERT_STATUS=$(aws acm describe-certificate \
      --certificate-arn $CERTIFICATE_ARN \
      --region us-east-1 \
      --query 'Certificate.Status' \
      --output text 2>/dev/null || echo "NOT_FOUND")

    if [ "$CERT_STATUS" = "ISSUED" ]; then
      SSL_ENABLED=true
      echo "✅ SSL Certificate found and ready!"
      echo "   Deploying with HTTPS enabled on port 443"
    else
      echo "⚠️  SSL Certificate exists but status: $CERT_STATUS"
      echo "   Deploying with HTTP only (port 80)"
    fi
  fi
fi
echo ""

# Deploy the application with Helm
# Uses the image we pushed to ECR earlier
ECR_REPO="$AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME"

if [ "$SSL_ENABLED" = true ]; then
  helm install health-service "$SCRIPT_DIR/health-service" \
    --set image.repository="$ECR_REPO" \
    --set image.tag=latest \
    --set service.ssl.enabled=true \
    --set service.ssl.certificateArn="$CERTIFICATE_ARN"
else
  helm install health-service "$SCRIPT_DIR/health-service" \
    --set image.repository="$ECR_REPO" \
    --set image.tag=latest \
    --set service.ssl.enabled=false
fi

echo ""
echo "Waiting for application pods to be ready..."
kubectl wait --for=condition=ready pod --selector=app=health-service --timeout=120s
echo ""

echo "=== Cluster Status ==="
kubectl get nodes
kubectl get pods
kubectl get svc
kubectl get hpa
echo ""

echo "=== LoadBalancer URL ==="
# Get NGINX Ingress LoadBalancer (this is what handles all traffic)
NLB_HOSTNAME=$(kubectl get svc nginx-ingress-ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $NLB_HOSTNAME
echo ""

# Update DNS if Route 53 is configured
if [ -f "$PROJECT_ROOT/route53/.env.route53" ]; then
  source "$PROJECT_ROOT/route53/.env.route53"
  echo "=== Updating DNS ==="
  "$PROJECT_ROOT/route53/update-dns.sh" api "$NLB_HOSTNAME"
  echo ""

  echo "=== Your Endpoints ==="
  echo "HTTP:  http://api.$DOMAIN/health"
  if [ "$SSL_ENABLED" = true ]; then
    echo "HTTPS: https://api.$DOMAIN/health ✅"
  else
    echo "HTTPS: Not configured yet"
    echo ""
    echo "To enable HTTPS:"
    echo "  1. cd route53"
    echo "  2. ./request-ssl-cert.sh"
    echo "  3. ./add-ssl-validation.sh"
    echo "  4. Wait 5-30 minutes for validation"
    echo "  5. Redeploy cluster (./eks/deploy-eks.sh)"
  fi
  echo ""
else
  echo "=== DNS Update Skipped ==="
  echo "Route 53 not configured. Run route53/setup-hosted-zone.sh to enable automatic DNS."
  echo ""
fi

echo ""
echo "Waiting for application to be ready..."

echo "=== Health Check (HTTP/HTTPS) ==="
MAX_RETRIES=60
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  response=$(curl -s -o /dev/null -w "%{http_code}" http://$NLB_HOSTNAME/health 2>/dev/null || echo "000")
  if [ "$response" = "200" ]; then
    echo "✅ Application is ready!"
    if [ "$SSL_ENABLED" = true ]; then
      echo "   https://api.$DOMAIN/health"
    else
      echo "   http://$NLB_HOSTNAME/health"
    fi
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  sleep 5
done
if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "⚠️  Timed out waiting for health endpoint. Check: kubectl get pods"
fi

trap 'ec=$?; echo; echo "❌ FAILED (exit $ec) at line $LINENO:"; echo "   $BASH_COMMAND"; echo; exit $ec' ERR
