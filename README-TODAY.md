# START HERE — Today's Literal, Copy-Paste Walkthrough

Everything referenced below (Terraform, Ansible, manifests, docs) is in this same
folder, ready to use — you're not writing this from scratch, you're running it and
filling in the `VERIFY` / `CHANGE_ME` / `<...>` placeholders with your own values.

Do the phases **in order**. Each phase ends with a ✅ command that proves it worked
before you move to the next one — don't skip that check, it saves you from debugging
three problems at once later.

Run everything from your `cato` VM over SSH (WezTerm), since it already has a Linux
shell ready to go.

---

## Phase 0 — Tools & Accounts (15–20 min)

```bash
# On cato:
sudo apt update
sudo apt install -y ansible jq unzip

# Terraform (HashiCorp's official apt repo)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

aws configure
# Enter the access key / secret for an IAM user with EC2 + VPC permissions (not root).
```

✅ Check: `terraform -v`, `ansible --version`, `kubectl version --client`, `helm version`,
`aws sts get-caller-identity` all print something without errors.

**Get your public IP** (you'll need it in a moment):
```bash
curl -s ifconfig.me
```

**Create an SSH key pair for the cluster nodes:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/phoenix_key -N ""
```

**Register the key with AWS as an EC2 key pair:**
```bash
aws ec2 import-key-pair --key-name phoenix-key \
  --public-key-material fileb://~/.ssh/phoenix_key.pub \
  --region us-east-1
```

**Get a free domain (DuckDNS):**
1. Go to https://www.duckdns.org, sign in with GitHub.
2. Create a subdomain, e.g. `firdaws-taskapp` → this gives you `firdaws-taskapp.duckdns.org`.
3. Leave the IP field blank for now — you'll fill it in after `terraform apply`.

**Re-check your AWS budget alert** (you've done this before) so you get notified if
spend goes above a couple of dollars:
AWS Console → Billing → Budgets → confirm your zero/low-spend alert is still active.

---

## Phase 1 — Infrastructure (Terraform, ~30–45 min)

**Set up remote state first** (do this once, outside Terraform):
```bash
BUCKET="phoenix-tfstate-firdaws-$RANDOM"   # must be globally unique — note the name it prints
aws s3api create-bucket --bucket $BUCKET --region us-east-1
aws s3api put-bucket-versioning --bucket $BUCKET --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name phoenix-tf-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1
echo $BUCKET   # remember this — you need it in the next step
```

**Edit `infra/terraform/backend.tf`** — replace `REPLACE-WITH-YOUR-UNIQUE-BUCKET-NAME`
with the bucket name printed above.

**Fill in your variables:**
```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
# Set my_ip = "<the IP from `curl -s ifconfig.me`>/32"
# Set key_name = "phoenix-key"
```

**Provision the 3 nodes:**
```bash
terraform init
terraform plan
terraform apply     # type yes when prompted
```

**Capture the outputs** — you'll need every one of these:
```bash
terraform output
```

✅ Check: SSH into each node using the printed public IPs:
```bash
ssh -i ~/.ssh/phoenix_key ubuntu@<control_plane_public_ip>
```

**Point your DuckDNS domain at the control-plane's public IP** now — go back to
duckdns.org and paste the control-plane public IP into the IP field, then save.

---

## Phase 2 — Cluster Bring-Up (Ansible, ~20–30 min)

```bash
cd ../ansible
cp inventory.ini.example inventory.ini
nano inventory.ini
```
Fill in:
- `ansible_host` for `cp1` = control-plane **public** IP
- `private_ip` for `cp1` = control-plane **private** IP
- `ansible_host` for `worker1`/`worker2` = each worker's **public** IP

```bash
ansible-playbook site.yml
```

Run it again immediately — it should report `changed=0` on the tasks that already
succeeded (proves idempotency):
```bash
ansible-playbook site.yml
```

**Wire up kubectl:**
```bash
export KUBECONFIG=$(pwd)/kubeconfig
sed -i "s/127.0.0.1/<CONTROL_PLANE_PUBLIC_IP>/" kubeconfig
kubectl get nodes -o wide
```

✅ Check: 3 nodes, all `STATUS = Ready`. **Screenshot this — it's Evidence #1.**

---

## Phase 3 — Platform Install (~20 min)

```bash
cd ../..   # back to repo root

# cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace --set installCRDs=true

# metrics-server (needed for the HPA later)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# k3s note: if `kubectl top nodes` errors out with a TLS complaint after a minute,
# patch it:
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Argo CD
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd --namespace argocd --create-namespace
```

✅ Check:
```bash
kubectl get pods -n cert-manager
kubectl get pods -n argocd
kubectl top nodes    # should print real CPU/memory numbers, not an error
```

---

## Phase 4 — Deploy the App (~1–2 hours — the biggest phase)

**First, confirm the images actually pull:**
```bash
ssh -i ~/.ssh/phoenix_key ubuntu@<control_plane_public_ip> \
  "sudo docker pull ghcr.io/ts-a-devops/taskapp-backend:latest 2>&1 | tail -5 || sudo k3s ctr images pull ghcr.io/ts-a-devops/taskapp-backend:latest"
```
If this fails with an authentication error, the images are private — generate a GitHub
Personal Access Token with `read:packages`, then:
```bash
kubectl create secret docker-registry ghcr-pull-secret \
  --namespace taskapp \
  --docker-server=ghcr.io \
  --docker-username=<your-github-username> \
  --docker-password=<your-PAT> \
  -n taskapp
```
and add `imagePullSecrets: [{name: ghcr-pull-secret}]` under `spec.template.spec` in
both `05-backend-deployment.yaml` and `06-frontend-deployment.yaml`.

**Find the real, pinned image tag to use** (check the repo's Packages page on GitHub,
or ask your tutor which tag is the "release" build) — then replace every
`PINNED_TAG` placeholder in the `manifests/` files:
```bash
grep -rl "PINNED_TAG" manifests/
# edit each file, e.g.:
sed -i "s/PINNED_TAG/<real-tag-here>/" manifests/*.yaml
```

**Create the namespace and the real Secret (never committed to git):**
```bash
kubectl create namespace taskapp
kubectl create secret generic taskapp-secret --namespace taskapp \
  --from-literal=POSTGRES_USER=taskapp_admin \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 18)" \
  --from-literal=DB_USER=taskapp_admin \
  --from-literal=DB_PASSWORD="$(openssl rand -base64 18)" \
  --from-literal=SECRET_KEY="$(openssl rand -base64 32)"
```

**Before applying, open your actual TaskApp source** (frontend/backend repo from the
earlier Docker lesson) and check two things against `manifests/05-backend-deployment.yaml`
and `manifests/04-migration-job.yaml`:
1. The real health-check route (replace every `/health` `VERIFY` comment).
2. The real migration command (replace `["flask", "db", "upgrade"]` if different).

Also edit `manifests/07-ingress.yaml`: replace `taskapp.YOURNAME.duckdns.org` with your
real DuckDNS domain (both places), and replace the `YOUR_EMAIL@example.com` placeholder
with your real email.

**Apply everything:**
```bash
kubectl apply -f manifests/00-namespace.yaml
kubectl apply -f manifests/01-configmap.yaml
kubectl apply -f manifests/03-postgres.yaml
kubectl wait --for=condition=ready pod -l app=postgres -n taskapp --timeout=120s
kubectl apply -f manifests/04-migration-job.yaml
kubectl wait --for=condition=complete job/taskapp-migrate -n taskapp --timeout=120s
kubectl apply -f manifests/05-backend-deployment.yaml
kubectl apply -f manifests/06-frontend-deployment.yaml
kubectl apply -f manifests/07-ingress.yaml
kubectl apply -f manifests/08-hpa.yaml
kubectl apply -f manifests/09-pdb.yaml
```

✅ Check pods are spread and healthy:
```bash
kubectl get pods -n taskapp -o wide
```
**Screenshot this — Evidence #2** (confirm backend/frontend pairs land on different nodes).

**Prove Postgres survives a restart — Evidence #3:**
```bash
kubectl delete pod postgres-0 -n taskapp
kubectl get pods -n taskapp -w   # wait for it to come back Running
# then reload your app in the browser and confirm your data is still there
```

**Wait for the TLS certificate** (can take 1–2 minutes):
```bash
kubectl get certificate -n taskapp -w
```
Once `READY = True`:
```bash
curl -vI https://taskapp.<yourname>.duckdns.org 2>&1 | grep -E "HTTP|subject|issuer"
```
✅ **Screenshot this — Evidence #4** (valid cert, not self-signed).

**Prove zero-downtime rollout — Evidence #5:**
```bash
# terminal 1:
while true; do curl -o /dev/null -s -w "%{http_code}\n" https://taskapp.<yourname>.duckdns.org; sleep 0.5; done | tee rollout-log.txt

# terminal 2, while terminal 1 is running:
kubectl set image deployment/backend backend=ghcr.io/ts-a-devops/taskapp-backend:<same-or-new-tag> -n taskapp
kubectl rollout status deployment/backend -n taskapp
```
Stop terminal 1 after the rollout finishes, then check: `grep -v 200 rollout-log.txt`
should print nothing.

---

## Phase 5 — GitOps Takes Over (~30–45 min)

**Commit everything to your fork** (except what `.gitignore` excludes):
```bash
git add .
git commit -m "Infra, cluster, and TaskApp manifests for Capstone Phoenix"
git push
```

**Point Argo CD at your repo:**
```bash
nano gitops/application.yaml
# replace the repoURL with your fork's real URL

kubectl apply -f gitops/application.yaml
```

**Get the Argo CD UI password and log in to check status:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
kubectl port-forward svc/argocd-server -n argocd 8080:443
# then browse to https://<control-plane-public-ip>:8080 from your own machine
# (or open a second SSH tunnel: ssh -L 8080:localhost:8080 -i ~/.ssh/phoenix_key ubuntu@<ip>)
```
Log in as `admin` with that password, find the `taskapp` app, confirm it shows
**Synced / Healthy** (it will "adopt" the resources you already applied by hand).
✅ **Screenshot this — Evidence #6.**

**Prove the GitOps loop live — Evidence #7:**
```bash
# edit manifests/06-frontend-deployment.yaml, change replicas: 2 to replicas: 3
git add manifests/06-frontend-deployment.yaml
git commit -m "Scale frontend to 3 replicas"
git push
```
Watch the Argo CD UI (or `kubectl get pods -n taskapp -w`) — a 3rd frontend Pod should
appear **without you running `kubectl apply` yourself.** Screen-record or screenshot
this happening.

---

## Phase 6 — HPA Demo (~20 min) — Evidence #8

```bash
kubectl get hpa -n taskapp -w
```
In another terminal, generate load (installs a tiny load tool first):
```bash
go install github.com/rakyll/hey@latest 2>/dev/null || sudo apt install -y apache2-utils
hey -z 90s -c 60 https://taskapp.<yourname>.duckdns.org/
# or if using apache2-utils: ab -t 90 -c 60 https://taskapp.<yourname>.duckdns.org/
```
Watch replica count climb in the `kubectl get hpa -w` terminal, then drop back down a
few minutes after load stops. Screenshot both the climb and the drop.

---

## Phase 7 — PDB + Graceful Shutdown + securityContext — Evidence #9

These are already in your manifests (`09-pdb.yaml`, `terminationGracePeriodSeconds`,
`securityContext` blocks). Prove the PDB works with the same drain command you'll use
in the live demo:
```bash
kubectl get nodes
kubectl drain <a-worker-node-name> --ignore-daemonsets --delete-emptydir-data
# watch the app stay reachable the whole time:
curl -o /dev/null -s -w "%{http_code}\n" https://taskapp.<yourname>.duckdns.org
kubectl get pods -n taskapp -o wide     # confirm Pods rescheduled onto remaining nodes
# uncordon it afterward so it can schedule again:
kubectl uncordon <a-worker-node-name>
```
This is also your dry run for the live failover demo — rehearse it now so it's smooth
on camera later.

---

## Phase 8 — Docs & Final Submission (~45–60 min)

The `docs/ARCHITECTURE.md`, `docs/RUNBOOK.md`, and `docs/COST.md` in this folder are
already filled in based on this exact build — read through each once and adjust any
detail that doesn't match what you actually did (e.g. if you changed instance size or
skipped a step).

**Collect every screenshot above into `docs/EVIDENCE/`.**

**Final security sweep — run this exactly, fix anything it finds:**
```bash
grep -rn "latest" manifests/ infra/    # should return nothing except comments
cat .gitignore                          # confirm it covers tfstate/kubeconfig/.env/secret
git log --all -p | grep -i "password\|BEGIN PRIVATE\|secret_key" | head    # should be empty
```

**Submit** via the form link in the brief.

**After grading (not before!):**
```bash
cd infra/terraform
terraform destroy
```
And double-check your AWS budget/billing page shows nothing still running.

---

## If you run out of time partway through

Submit what's working, with an honest one-paragraph note at the top of
`docs/ARCHITECTURE.md` saying exactly which phase you reached and why (personal
circumstances, time). A submission that's honestly labeled "reached Phase 5, GitOps not
yet live" with everything before that genuinely working will score far better than
something broken that claims to be complete — and it gives you something concrete and
truthful to explain in the viva.
