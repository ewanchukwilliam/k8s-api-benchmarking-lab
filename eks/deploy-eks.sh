#!/bin/bash
set -e

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
kubectl apply -f "$SCRIPT_DIR/components.yaml"
kubectl apply -f "$SCRIPT_DIR/deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/hpa.yaml"
kubectl apply -f "$SCRIPT_DIR/service.yaml"
kubectl wait --for=condition=ready pod --selector=app=health-service --timeout=120s
echo ""

echo "=== Cluster Status ==="
kubectl get nodes
kubectl get pods
kubectl get svc
kubectl get hpa
echo ""

echo "=== LoadBalancer URL ==="
kubectl get svc health-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo ""
echo ""
echo "Cluster deployed successfully!"
