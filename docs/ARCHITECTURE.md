# TaskApp Phoenix Architecture

## Infrastructure

The application runs on a 3-node Kubernetes cluster.

Components:

- Terraform provisions AWS infrastructure.
- Ansible installs and configures k3s.
- ArgoCD manages Kubernetes desired state.

Topology:

- 1 control-plane node
- 2 worker nodes


## Application Flow

User
|
HTTPS
|
DNS
|
Traefik Ingress
|
Frontend Deployment
|
Backend Deployment
|
PostgreSQL StatefulSet


## Kubernetes Design

Frontend:
- React/nginx
- 2 replicas
- readiness/liveness/startup probes


Backend:
- Flask API
- 2 replicas
- resource limits
- health probes


Database:
- PostgreSQL StatefulSet
- PersistentVolumeClaim storage


## Reliability Improvements

Compared with a single server:

- Multiple replicas prevent application downtime.
- Kubernetes reschedules failed pods.
- Persistent storage protects database data.
- Rolling updates prevent dropped requests.
- GitOps provides controlled deployment.
