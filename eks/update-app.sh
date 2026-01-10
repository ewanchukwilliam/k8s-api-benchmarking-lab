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

echo "=== Building and Pushing Updated Image ==="
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

cd "$PROJECT_ROOT"
docker build -t health-service:local .
docker tag health-service:local $ECR_IMAGE
docker push $ECR_IMAGE

echo "=== Restarting Pods with New Image ==="
kubectl rollout restart deployment/health-service

echo "=== Waiting for Rollout ==="
kubectl rollout status deployment/health-service

kubectl get pods
echo ""
echo "Application updated successfully!"
