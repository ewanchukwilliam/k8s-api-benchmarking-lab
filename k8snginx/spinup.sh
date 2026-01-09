#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

kind delete cluster --name devops-lab 2>/dev/null || true
kind create cluster --name devops-lab --config "$SCRIPT_DIR/kind-config.yaml"

cd "$PROJECT_ROOT"
docker build -t health-service:local .
kind load docker-image health-service:local --name devops-lab

kubectl apply -f "$SCRIPT_DIR/ingress-controller.yaml"
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

kubectl apply -f "$SCRIPT_DIR/"
kubectl wait --for=condition=ready pod --selector=app=health-service --timeout=60s

kubectl get pods
kubectl get svc
kubectl get ingress
kubectl get hpa

sleep 3
curl http://localhost/health
