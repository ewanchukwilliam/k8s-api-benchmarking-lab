#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HELM_BASE="$PROJECT_ROOT/helm/base"
HELM_DEV="$PROJECT_ROOT/helm/dev"
MANIFESTS_DEV="$PROJECT_ROOT/manifests/overlays/dev"

echo "=== Setting up Dev Environment (Kind) ==="

kind delete cluster --name devops-lab 2>/dev/null || true
kind create cluster --name devops-lab --config "$PROJECT_ROOT/kind/kind-config.yaml"

cd "$PROJECT_ROOT"
docker build -t health-service:local .
kind load docker-image health-service:local --name devops-lab

echo "=== Installing Metrics Server ==="
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update metrics-server
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args[0]="--kubelet-insecure-tls" \
  --set args[1]="--kubelet-preferred-address-types=InternalIP"

echo "=== Installing Prometheus + Grafana ==="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f "$HELM_BASE/prometheus-local.yaml" \
  -f "$HELM_DEV/prometheus.yaml"

echo "=== Installing KEDA ==="
helm repo add kedacore https://kedacore.github.io/charts
helm repo update kedacore
helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace

echo "=== Installing NGINX Ingress Controller ==="
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  -f "$HELM_BASE/nginx-ingress-values.yaml"

echo "Waiting for ingress controller..."
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s

sleep 10

echo "=== Installing Redis ==="
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update bitnami
helm install redis bitnami/redis \
  --namespace default \
  -f "$HELM_BASE/redis-values.yaml" \
  -f "$HELM_DEV/redis.yaml"

echo "=== Deploying Application (dev overlay) ==="
kubectl apply -k "$MANIFESTS_DEV"

echo "=== Waiting for Prometheus to be ready ==="
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=180s || true

echo "=== Waiting for KEDA to be ready ==="
kubectl wait --for=condition=ready pod -l app=keda-operator -n keda --timeout=120s

echo "=== Waiting for application ==="
kubectl wait --for=condition=ready pod --selector=app=health-service --timeout=60s

echo "=== Dashboard analytics for Grafana ==="
kubectl apply -k "$PROJECT_ROOT/grafana"

echo ""
echo "=== Status ==="
kubectl get pods
kubectl get pods -n monitoring
kubectl get pods -n keda
kubectl get scaledobject
kubectl get hpa

echo ""
echo "=== Access ==="
echo "App:        http://localhost/health"
echo "Prometheus: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "Grafana:    kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 (admin/admin)"

sleep 5
curl -s http://localhost/health || echo "App not ready yet - Redis may still be starting"
