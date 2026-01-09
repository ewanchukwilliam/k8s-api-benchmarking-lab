Deployment:
- https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- API Reference: https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/deployment-v1/

Service:
- https://kubernetes.io/docs/concepts/services-networking/service/
- API Reference: https://kubernetes.io/docs/reference/kubernetes-api/service-resources/service-v1/

Pods (what Deployments create):
- https://kubernetes.io/docs/concepts/workloads/pods/

Helpful tutorials:
- Learn Kubernetes Basics: https://kubernetes.io/docs/tutorials/kubernetes-basics/
- Deploy an App: https://kubernetes.io/docs/tutorials/kubernetes-basics/deploy-app/deploy-intro/

YAML Structure Guide:
- https://kubernetes.io/docs/concepts/overview/working-with-objects/kubernetes-objects/

  kind cluster
  ├─ Control plane node (runs controllers)
  │  ├─ HPA controller (decides: need more pods?)
  │  ├─ Deployment controller (ensures pods exist)
  │  └─ Scheduler (picks which node for new pods)
  │
  └─ Worker nodes (run your workloads)
     ├─ metrics-server pod (collects stats)
     └─ health-service pods (your app, scaled by HPA)

# deployment steps:

kind create cluster --name devops-lab --config kind-config.yaml

kind load docker-image health-service:local --name devops-lab

kubectl apply -f k8s/

kubectl run curl-test --image=curlimages/curl -i --tty --rm -- curl -s http://health-service/health

# port forwarding

kubectl port-forward service/health-service 8080:80

curl -s http://localhost:8080/health | python3 -m json.tool
curl -s http://localhost:8080/metrics | python3 -m json.tool
curl -s http://localhost:8080/ | python3 -m json.tool

# delete cluster

kind delete cluster --name devops-lab

# k9s docs to remember 
:deploy
<ctrl+d> to delete deployment
<l> to view logs
<f> fullscreen logs
<0> to go to all pods
<1> to local pods in current namespace

# add logging to k9s with metrics container manifest
## ask gpt what line needs to be added to the metrics container manifest
curl -LO https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# eksctl installation (remote clustsers)
https://github.com/eksctl-io/eksctl

```bash
# for ARM systems, set ARCH to: `arm64`, `armv6` or `armv7`
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
# (Optional) Verify checksum
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
```
