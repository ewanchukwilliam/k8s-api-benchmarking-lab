# KEDA Event-Driven Autoscaling Setup for EKS

This guide walks through setting up KEDA with Prometheus-based autoscaling on your EKS cluster, replacing the traditional CPU-based HPA with event-driven scaling based on HTTP traffic metrics.

## Architecture Overview

```
                    ┌─────────────────────────────────────────┐
                    │              NGINX Ingress               │
                    │         (exposes /metrics:10254)         │
                    └─────────────────┬───────────────────────┘
                                      │
                    ┌─────────────────▼───────────────────────┐
                    │              Prometheus                  │
                    │    (scrapes nginx + app metrics)         │
                    └─────────────────┬───────────────────────┘
                                      │
                    ┌─────────────────▼───────────────────────┐
                    │           KEDA Operator                  │
                    │  (queries Prometheus, manages HPA)       │
                    └─────────────────┬───────────────────────┘
                                      │
                    ┌─────────────────▼───────────────────────┐
                    │         health-service Deployment        │
                    │           (2-10 replicas)                │
                    └─────────────────────────────────────────┘
```

## Files Created

| File | Purpose |
|------|---------|
| `keda-prometheus-stack.yaml` | Namespaces and TriggerAuthentication resources |
| `keda-values.yaml` | Helm values for KEDA installation |
| `prometheus-values.yaml` | Helm values for kube-prometheus-stack |
| `keda-scaled-object.yaml` | **Main config** - ScaledObject with Prometheus triggers |
| `nginx-servicemonitor.yaml` | ServiceMonitor for nginx metrics scraping |
| `nginx-ingress-metrics-patch.yaml` | Enable metrics endpoint on nginx |
| `grafana-keda-dashboard.yaml` | Grafana dashboard for monitoring |

## Prerequisites

- EKS cluster running (your `eks-cluster.yaml`)
- kubectl configured for your cluster
- Helm 3.x installed
- nginx-ingress-controller deployed
- cert-manager with letsencrypt-prod issuer

## Installation Steps

### 1. Add Helm Repositories

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
```

### 2. Install Prometheus Stack

```bash
# Create monitoring namespace and install
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f prometheus-values.yaml
```

### 3. Enable NGINX Metrics

```bash
# Apply the metrics service for nginx
kubectl apply -f nginx-ingress-metrics-patch.yaml

# Or if using Helm for nginx-ingress, upgrade with metrics enabled:
# helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
#   -n ingress-nginx \
#   --set controller.metrics.enabled=true \
#   --set controller.metrics.serviceMonitor.enabled=true
```

### 4. Apply ServiceMonitors

```bash
kubectl apply -f nginx-servicemonitor.yaml
```

### 5. Install KEDA

```bash
helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  -f keda-values.yaml
```

### 6. Remove Existing HPA (Important!)

KEDA creates its own HPA, so remove the existing one to avoid conflicts:

```bash
# Check for existing HPA
kubectl get hpa -n default

# Delete the old HPA
kubectl delete hpa health-service-hpa -n default
```

### 7. Apply KEDA ScaledObject

```bash
kubectl apply -f keda-scaled-object.yaml
```

### 8. Apply Grafana Dashboard

```bash
kubectl apply -f grafana-keda-dashboard.yaml
```

## Scaling Triggers Configured

The ScaledObject uses 5 Prometheus-based triggers:

| Metric | Threshold | Description |
|--------|-----------|-------------|
| HTTP RPS per pod | 100 req/s | Scale when requests exceed 100/s per pod |
| P95 Latency | 500ms | Scale when response time exceeds 500ms |
| Active Connections | 50 | Scale on concurrent connection count |
| CPU Utilization | 70% | Fallback CPU-based scaling |
| Memory Utilization | 80% | Scale on memory pressure |

## Verification Commands

```bash
# Check KEDA operator status
kubectl get pods -n keda

# Check ScaledObject status
kubectl get scaledobject -n default
kubectl describe scaledobject health-service-scaledobject -n default

# Check the HPA KEDA created
kubectl get hpa -n default

# View Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-prometheus 9090:9090
# Visit http://localhost:9090/targets

# Access Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Visit http://localhost:3000 (admin/admin)
```

## Testing the Autoscaling

```bash
# Generate load with hey or ab
hey -n 10000 -c 100 https://api.codeseeker.dev/

# Watch scaling in real-time
watch kubectl get pods -n default -l app=health-service

# Check HPA metrics
kubectl get hpa -n default -w
```

## Key Differences from Traditional HPA

| Feature | Traditional HPA | KEDA |
|---------|----------------|------|
| Metrics Source | metrics-server (CPU/Memory) | Any external source (Prometheus, etc.) |
| Scale to Zero | Not supported | Supported |
| Event-Driven | No | Yes |
| Custom Metrics | Complex setup | Built-in scalers |
| Multiple Triggers | Manual configuration | Native support |

## Troubleshooting

### ScaledObject not scaling

```bash
# Check KEDA logs
kubectl logs -n keda -l app=keda-operator

# Verify Prometheus query works
kubectl exec -n monitoring prometheus-prometheus-0 -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=nginx_ingress_controller_requests'
```

### Metrics not appearing

```bash
# Check if nginx exposes metrics
kubectl exec -n ingress-nginx deploy/ingress-nginx-controller -- \
  wget -qO- http://localhost:10254/metrics | head -20

# Verify ServiceMonitor is picked up
kubectl get servicemonitor -n monitoring
```

### KEDA HPA conflicts

```bash
# Ensure only KEDA's HPA exists
kubectl get hpa -n default
# Should show: keda-hpa-health-service-scaledobject
```

## Cleanup

```bash
# Remove KEDA ScaledObject
kubectl delete scaledobject health-service-scaledobject -n default

# Uninstall KEDA
helm uninstall keda -n keda

# Uninstall Prometheus
helm uninstall prometheus -n monitoring

# Re-apply original HPA if needed
kubectl apply -f ../k8snginxtutorial/hpa.yaml
```
