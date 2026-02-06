# DevOps Lab - Kubernetes with Scale-to-Zero

> **Want to see this running live?** Contact me to request access to the live deployment at `api.codeseeker.dev/page`
>
> 📧 **wewanchu@ualberta.ca** | **ewanchukwilliam@gmail.com**

---

A production-ready Kubernetes deployment showcasing cost-optimized infrastructure with automatic scaling.

## Features

- **Scale-to-Zero** - Pods scale down to 0 when idle, saving costs
- **KEDA Autoscaling** - Event-driven scaling based on Prometheus RPS metrics
- **Custom Warming Page** - Friendly "brewing" page shown during cold starts with auto-retry
- **Dual Environment** - Local dev (Kind) and production (AWS EKS) with shared manifests
- **Infrastructure as Code** - Terraform modules for VPC, EKS, ECR, Route53, ACM
- **Interactive Dashboard** - View real-time pod metrics at `/page`

## Live Demo

- **Production**: https://api.codeseeker.dev/page (contact for access)
- **Local**: http://localhost/page (after running spinup-dev.sh)

## Tech Stack

- **App**: Python FastAPI + Redis
- **Container**: Docker
- **Orchestration**: Kubernetes (Kind local, EKS prod)
- **Scaling**: KEDA with Prometheus triggers
- **Ingress**: nginx-ingress with custom error pages
- **IaC**: Terraform, Kustomize, Helm
- **Monitoring**: Prometheus + Grafana

## Project Structure

```
├── src/                    # Application code
├── manifests/
│   ├── base/              # Base Kubernetes manifests
│   └── overlays/
│       ├── dev/           # Kind/local overrides
│       └── prod/          # EKS/AWS overrides
├── terraform/
│   ├── modules/           # Reusable TF modules (vpc, eks, ecr, dns)
│   └── environments/
│       └── prod/          # Production environment
├── helm/
│   ├── base/              # Shared Helm values
│   ├── dev/               # Dev-specific values
│   └── prod/              # Prod-specific values
├── scripts/
│   ├── spinup-dev.sh      # Bootstrap local Kind cluster
│   ├── spinup-prod.sh     # Deploy to AWS EKS
│   └── teardown-prod.sh   # Destroy AWS resources
└── grafana/               # Custom Grafana dashboards
```

## Quick Start

### Local Development (Kind)

```bash
./scripts/spinup-dev.sh
```

This creates a local Kind cluster with:
- Prometheus + Grafana
- KEDA for autoscaling
- nginx-ingress
- Redis
- Your app with scale-to-zero

Access the dashboard: http://localhost/page

### Production (AWS EKS)

```bash
./scripts/spinup-prod.sh
```

This provisions:
- VPC with public/private subnets
- EKS cluster (t3.small nodes, autoscaling 1-3)
- ECR repository
- ACM certificate + Route53 DNS
- Full monitoring stack

Access the dashboard: https://api.codeseeker.dev/page

## Endpoints

| Endpoint | Description |
|----------|-------------|
| `/` | Service info |
| `/health` | Health check with CPU/memory stats |
| `/metrics` | Detailed process metrics |
| `/page` | **Interactive monitoring dashboard** |

## Scale-to-Zero Flow

1. No traffic → KEDA scales pods to 0
2. Request arrives → nginx returns custom "brewing" page
3. Page auto-retries every 2 seconds
4. KEDA sees Prometheus metrics spike → scales up pod
5. Pod ready → auto-refresh loads the app

## Cost Optimization (t3.small)

| Component | Memory Request |
|-----------|----------------|
| nginx-ingress | 64Mi |
| KEDA | ~128Mi |
| Prometheus | 256Mi |
| Grafana | 64Mi |
| health-service | 128Mi |
| Redis | 64Mi |

Total: ~700Mi on t3.small (~1.5GB usable)

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WORKERS` | 10 | Uvicorn worker count (prod uses 2) |
| `REDIS_HOST` | localhost | Redis hostname |
| `PORT` | 8080 | App port |

## Development

```bash
# Run tests
source .venv/bin/activate && pytest tests/ -v

# Build image
docker build -t health-service:local .

# Apply changes to dev
kubectl apply -k manifests/overlays/dev/

# Apply changes to prod
kubectl apply -k manifests/overlays/prod/
kubectl set image deployment/health-service health-service=<ECR_URL>:latest
```
