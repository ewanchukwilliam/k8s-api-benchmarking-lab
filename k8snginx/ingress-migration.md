# Migration: Service (NodePort) → Ingress (Request-Level Load Balancing)

## The Problem We're Solving

### Current Setup: Service with NodePort (Layer 4)

**How it works:**
- Kubernetes Service load balances at the **connection level**
- Once a TCP connection is established, all HTTP requests on that connection go to the same pod
- New pods added by HPA don't receive traffic until clients open **new connections**

**Example scenario:**
```
Time 0s:  k6 starts → opens 100 connections → distributed to Pods A, B, C
Time 30s: High CPU → HPA scales up → adds Pods D, E, F
Time 31s: Same 100 connections still pinned to A, B, C
Result:   Pods D, E, F sit idle with 0% CPU
```

### Why This Happens

**HTTP Keep-Alive Connections:**
- Modern HTTP clients (k6, browsers, curl) reuse connections for multiple requests
- A single connection can send 100s or 1000s of requests
- Kubernetes Service (iptables/IPVS) routes at Layer 4 (TCP)
- Layer 4 can't see individual HTTP requests within a connection

**Kubernetes Service Load Balancing:**
```
Client → Service (Layer 4 - connection-based)
           ↓
    Round-robin NEW connections only
           ↓
    [Pod A] [Pod B] [Pod C]
```

**After scaling:**
```
Client → Service (same connections still open)
           ↓
    [Pod A] [Pod B] [Pod C] [Pod D] [Pod E] [Pod F]
     ↑       ↑       ↑       (idle) (idle) (idle)
     └───────┴───────┘
    All traffic here
```

---

## The Solution: Ingress Controller (Layer 7)

### What is Ingress?

**Ingress** = Layer 7 (HTTP/HTTPS) load balancer that:
- Terminates HTTP connections
- Distributes **each request** (not just connections) to pods
- New pods immediately receive traffic
- Can do advanced routing (path-based, host-based, etc.)

### How it works

**With Ingress Controller:**
```
Client → Ingress Controller (Layer 7 - request-based)
           ↓
    Distribute EACH request
           ↓
    [Pod A] [Pod B] [Pod C] [Pod D] [Pod E] [Pod F]
      ↓       ↓       ↓       ↓       ↓       ↓
    All pods get traffic immediately
```

**Flow:**
1. Client opens connection to Ingress Controller
2. Ingress Controller receives all HTTP requests
3. For each request, Ingress picks a pod (round-robin, least-connections, etc.)
4. New pods scaled by HPA get requests immediately

---

## Migration Plan

### Current: service.yaml (NodePort)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: health-service
spec:
  type: NodePort
  selector:
    app: health-service
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080
```

**Limitations:**
- Layer 4 (connection-based) load balancing
- New pods don't get traffic until connections reset
- No HTTP routing capabilities
- No SSL termination

### New: ingress.yaml (Ingress)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: health-service-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: health-service
            port:
              number: 80
```

**Plus Internal Service (ClusterIP):**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: health-service
spec:
  type: ClusterIP  # Changed from NodePort
  selector:
    app: health-service
  ports:
  - port: 80
    targetPort: 8080
```

**Benefits:**
- Layer 7 (request-based) load balancing
- New pods get traffic immediately
- Advanced routing (paths, headers, hostnames)
- SSL/TLS termination
- Better observability

---

## Implementation Options

### Option 1: Nginx Ingress Controller (Recommended for local/kind)

**Install:**
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
```

**Or for kind specifically:**
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/kind/deploy.yaml
```

**Access:**
- kind forwards Ingress to localhost:80 automatically
- Access at: `http://localhost/health`

### Option 2: AWS Load Balancer Controller (For EKS)

**Install:**
```bash
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system
```

**Creates AWS Application Load Balancer (ALB):**
- Layer 7 load balancing
- Native AWS integration
- Public DNS endpoint
- SSL via ACM

**Access:**
- Get ALB DNS: `kubectl get ingress`
- Access at: `http://<alb-dns>/health`

### Option 3: Traefik (Alternative)

Simpler than Nginx, built-in dashboard.

---

## Testing the Difference

### Before (NodePort - connection-based):

```bash
# Start load test with 100 VUs
k6 run k6/maxrequests.js

# Scale up deployment
kubectl scale deployment health-service --replicas=10

# Check pod traffic distribution
for pod in $(kubectl get pods -l app=health-service -o name); do
  echo "=== $pod ===";
  kubectl logs $pod --tail=5 | grep "GET /health" | wc -l
done

# Result: Old pods get all traffic, new pods get 0
```

### After (Ingress - request-based):

```bash
# Start load test with 100 VUs
k6 run k6/maxrequests.js

# Scale up deployment
kubectl scale deployment health-service --replicas=10

# Check pod traffic distribution
for pod in $(kubectl get pods -l app=health-service -o name); do
  echo "=== $pod ===";
  kubectl logs $pod --tail=5 | grep "GET /health" | wc -l
done

# Result: ALL pods get traffic immediately
```

---

## Performance Considerations

### Layer 4 (Service) Pros:
- ✓ Lower latency (direct connection)
- ✓ Less overhead
- ✓ Simpler setup

### Layer 4 Cons:
- ✗ Connection-based load balancing
- ✗ No request-level control
- ✗ Poor scaling behavior with keep-alive

### Layer 7 (Ingress) Pros:
- ✓ Request-based load balancing
- ✓ Immediate scaling response
- ✓ Advanced routing capabilities
- ✓ SSL termination
- ✓ Better observability

### Layer 7 Cons:
- ✗ Slightly higher latency (extra hop)
- ✗ More complex setup
- ✗ Additional resource usage (Ingress controller pods)

---

## Migration Steps

### 1. Install Ingress Controller
Choose one: Nginx (local) or AWS ALB Controller (EKS)

### 2. Create Internal Service
Change `type: NodePort` → `type: ClusterIP` in service.yaml

### 3. Create Ingress Resource
Add ingress.yaml pointing to the internal service

### 4. Update Access Method
- **Local (kind):** `http://localhost/health`
- **EKS:** `http://<alb-dns>/health`

### 5. Test Load Distribution
Verify new pods receive traffic immediately after scaling

### 6. Remove Old NodePort (optional)
Once Ingress is working, can remove NodePort entirely

---

## Cost Impact (EKS)

### Current (NodePort):
- Service is free (built-in Kubernetes)
- Access via NodePort requires exposing nodes

### With LoadBalancer Service:
- **+$16-18/month** for Classic/Network Load Balancer

### With Ingress + ALB:
- **+$16-18/month** for Application Load Balancer
- Better features (Layer 7, SSL, path routing)

**Recommendation:** Use Ingress + ALB for production, worth the cost.

---

## Next Steps

1. Decide: Nginx (local) or ALB (EKS)
2. Install chosen Ingress controller
3. Create ingress.yaml
4. Modify service.yaml to ClusterIP
5. Test request distribution
6. Update k6 tests to use new endpoint
7. Monitor and verify behavior

---

## References

- [Kubernetes Ingress Docs](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Nginx Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
