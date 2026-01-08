# devopshealthcheckk8testing

# Devops Lab - kubernetes api benchmarking
- containerized with **docker**
- deployed to **kubernetes** (kind/minikube)
- provisioned with **Ansible** onto a linux VM
- Built & tested with **GitLab CI**

the app itself is intentionaly simple ('\health' endpoint returing json) the foucs is **build systems, automation, and deployment pipelines** not complex business logic.

## Goals

- [ ] Basic HTTP service with automated tests
- [ ] Containerization with docker
- [ ] Kubernetes deployment with kubectl
- [ ] autonomous provisioning with Ansible
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



