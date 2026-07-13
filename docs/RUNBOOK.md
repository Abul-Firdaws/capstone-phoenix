# TaskApp Phoenix Runbook

## Provision

Terraform:

terraform init
terraform apply


## Configure Cluster

ansible-playbook -i inventory.ini site.yml


## Verify Nodes

kubectl get nodes


## Application Status

kubectl get pods -n taskapp


## Access Application

curl https://taskapp-firdaws.duckdns.org


## Recovery Procedures

### Failed Application Pod

Kubernetes automatically recreates failed replicas.


### Worker Failure

Drain worker:

kubectl drain NODE --ignore-daemonsets

Pods reschedule automatically.


### Database Recovery

Delete PostgreSQL pod:

kubectl delete pod postgres-0 -n taskapp

The PVC preserves database data.
