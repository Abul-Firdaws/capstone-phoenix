# Runbook — Capstone Phoenix

## Provision from zero

```bash
# 1. Infra
cd infra/terraform
terraform init
terraform apply

# 2. Cluster
cd ../ansible
cp inventory.ini.example inventory.ini   # fill in the real IPs from `terraform output`
ansible-playbook site.yml

# 3. kubeconfig
export KUBECONFIG=$(pwd)/kubeconfig
sed -i "s/127.0.0.1/<CONTROL_PLANE_PUBLIC_IP>/" kubeconfig
kubectl get nodes -o wide         # expect 3 Ready nodes

# 4. Platform
helm repo add jetstack https://charts.jetstack.io && helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace --set installCRDs=true

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# k3s nodes often need --kubelet-insecure-tls for metrics-server; if `kubectl top nodes`
# fails, patch the metrics-server deployment to add that flag.

helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm install argocd argo/argo-cd --namespace argocd --create-namespace

# 5. Secret (out-of-band — never committed)
kubectl create secret generic taskapp-secret --namespace taskapp \
  --from-literal=POSTGRES_USER=taskapp_admin \
  --from-literal=POSTGRES_PASSWORD='<generate a strong password>' \
  --from-literal=DB_USER=taskapp_admin \
  --from-literal=DB_PASSWORD='<same password>' \
  --from-literal=SECRET_KEY='<random 32+ char string>'
# (create the taskapp namespace first: kubectl create namespace taskapp)

# 6. App — apply once by hand to verify it all works
kubectl apply -f manifests/

# 7. GitOps takes over
kubectl apply -f gitops/application.yaml
# Argo CD will detect these same resources already exist and adopt them — future
# changes must go through a git commit, not kubectl apply.
```

## Day-2 operations

- **Scale a tier:** edit `replicas:` in the manifest, commit, push — Argo CD applies it.
  (Avoid `kubectl scale` directly once GitOps owns the app; Argo's `selfHeal` will
  revert it back to whatever git says.)
- **Roll back a bad deploy:** `git revert` the bad commit and push — Argo CD syncs the
  previous state. (Or `kubectl rollout undo deployment/backend -n taskapp` for an
  immediate emergency rollback, then fix git to match.)
- **Run a new migration safely:** bump the image tag in `04-migration-job.yaml`,
  delete the old Job (`kubectl delete job taskapp-migrate -n taskapp`), commit, let
  Argo re-create it.
- **Rotate a secret:** `kubectl delete secret taskapp-secret -n taskapp` then re-run
  the `kubectl create secret generic` command with new values, then restart the
  Deployments (`kubectl rollout restart deployment/backend deployment/frontend -n taskapp`).

## Failure recovery (live demo)

- **A worker node dies / is drained:**
  ```bash
  kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
  ```
  Pods on that node are rescheduled onto the remaining nodes within roughly 30–60
  seconds; the PodDisruptionBudget ensures at least 1 replica of each tier stays up
  throughout.
- **A backend Pod crashloops:**
  ```bash
  kubectl logs <pod> -n taskapp --previous
  kubectl describe pod <pod> -n taskapp
  kubectl get events -n taskapp --sort-by=.lastTimestamp
  ```
- **A bad migration:** roll the backend image back to the previous tag (git revert),
  then manually reverse the migration if needed (`flask db downgrade` or equivalent).
- **Postgres Pod is rescheduled:** delete it and prove data survives:
  ```bash
  kubectl delete pod postgres-0 -n taskapp
  kubectl get pods -n taskapp -w        # watch it come back
  # then re-check your data through the app — it should still be there
  ```
