# Capstone Phoenix Deployment Evidence

## Infrastructure
- AWS EC2 provisioned using Terraform
- Kubernetes cluster deployed using k3s
- Configuration automated with Ansible

## Kubernetes
- 3 node cluster
- ArgoCD GitOps deployment
- Traefik ingress controller
- cert-manager TLS automation

## Application
- Frontend: Running
- Backend: Running
- PostgreSQL: Running
- Health endpoint: Healthy

## Validation
- Kubernetes nodes: Ready
- ArgoCD application: Synced/Healthy
- TLS certificate: Ready
- API health: database connected
