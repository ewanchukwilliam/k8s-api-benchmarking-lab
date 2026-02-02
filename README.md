# devopshealthcheckk8testing

# Devops Lab - kubernetes api benchmarking
- containerized with **docker**
- deployed to **kubernetes** (kind/minikube)
- provisioned with **Ansible** onto a linux VM
- Built & tested with **GitLab CI**

the app itself is intentionaly simple ('\health' endpoint returing json) the foucs is **build systems, automation, and deployment pipelines** not complex business logic.

## Goals

- [x] Basic HTTP service with automated tests
- [x] Containerization with docker
- [x] Kubernetes deployment with kubectl
- [x] Kubrnetes deployment with eksctl 
- [x] Kubrnetes deployment with event driven scaling with KEDA
- [x] deploy to EKS with terraform
- [ ] define a temporary deploymetn procedure for a main branch with a cron job to turn off. 

## no longer goals for this project
- [ ] CI/CD with GitLab for build and testing
- [ ] VM practice

## tech stack
- python fastapi
- docker
- kubernetes
- ansible
- gitlab ci
- kustomize
- kind

folder structure
```
src/
tests/
k8s/
ansible/
Dockerfile
.gitlab-ci.yml
README.md
```

# endpoints
curl http://localhost:8080
curl http://localhost:8080/health
curl http://localhost:8080/containers
curl http://localhost:8080/metrics

# build the image
docker build -t health-service:local .

# run multiple containers from same image
docker run -d --name health-service -p 8080:8080 -v /var/run/docker.sock:/var/run/docker.sock health-service:local
docker run -d --name health-service -p 8081:8080 -v /var/run/docker.sock:/var/run/docker.sock health-service:local
docker run -d --name health-service -p 8082:8080 -v /var/run/docker.sock:/var/run/docker.sock health-service:local

# run pytest 
source .venv/bin/activate && pytest tests/ -v

