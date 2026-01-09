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

