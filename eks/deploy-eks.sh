#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$AWS_DEFAULT_REGION" ]; then
  echo "Error: AWS_ACCOUNT_ID and AWS_DEFAULT_REGION must be set"
  exit 1
fi

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

echo "=== Creating EKS Cluster ==="
eksctl create cluster -f "$SCRIPT_DIR/eks-cluster.yaml"
echo ""

echo "=== Deploying Cluster Autoscaler ==="
# Automatically adds/removes EC2 nodes when pods can't fit or nodes are idle
kubectl apply -f "$SCRIPT_DIR/cluster-autoscaler.yaml"
echo ""

echo "=== Deploying Application ==="
kubectl apply -f "$SCRIPT_DIR/deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/hpa.yaml"

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
      echo ""
    else
      echo "⚠️  SSL Certificate exists but status: $CERT_STATUS"
      echo "   Deploying with HTTP only (port 80)"
      echo ""
    fi
  fi
fi

# Deploy service with or without SSL
if [ "$SSL_ENABLED" = true ]; then
  # Create service.yaml with SSL annotations
  # kubectl apply -f "$SCRIPT_DIR/service-ssl.yaml"
  # rm "$SCRIPT_DIR/service-ssl.yaml"
  echo "⚠️  SSL Certificate exists but status: $CERT_STATUS"
else
  kubectl apply -f "$SCRIPT_DIR/service.yaml"
fi

kubectl wait --for=condition=ready pod --selector=app=health-service --timeout=120s
echo ""

echo "=== Cluster Status ==="
kubectl get nodes
kubectl get pods
kubectl get svc
kubectl get hpa
echo ""

echo "=== LoadBalancer URL ==="
NLB_HOSTNAME=$(kubectl get svc health-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
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

echo "Cluster deployed successfully!"


trap 'ec=$?; echo; echo "❌ FAILED (exit $ec) at line $LINENO:"; echo "   $BASH_COMMAND"; echo; exit $ec' ERR
