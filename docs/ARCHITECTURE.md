# Architecture — Capstone Phoenix

## 1. Topology

```
                         Internet
                            │
                     DNS (DuckDNS A record)
                            │
                 taskapp.<you>.duckdns.org
                            │
                            ▼
        ┌───────────────────────────────────────┐
        │   control-plane node (k3s server)      │
        │   Traefik ingress + cert-manager       │  ← TLS terminates here
        └───────────────────────────────────────┘
                 │                    │
        frontend Pods           backend Pods (Service: backend:5000)
        (Service: frontend)           │
        spread across:           spread across:
        control-plane + worker-1 control-plane + worker-2
                                       │
                                       ▼
                          postgres-0 (StatefulSet, PVC)
                          runs on whichever node the
                          scheduler placed it on
```

3 nodes total: 1 control-plane (also schedules workloads) + 2 workers, all in the same
AWS region/subnet, joined via k3s using each node's **private** IP.

## 2. Node & network

- Nodes: `t3.medium` x3, Ubuntu 24.04 LTS, same AZ, default VPC/subnet (chosen to save
  setup time — a production build would use a dedicated VPC with private subnets for
  the nodes and a NAT gateway/bastion for SSH).
- Firewall (Security Group): `22` and `6443` open **only to my own IP**; `80`/`443` open
  to the world (needed for app traffic and the Let's Encrypt HTTP-01 challenge);
  node-to-node ports (kubelet, flannel VXLAN, etc.) open **only within the security
  group itself** — never to `0.0.0.0/0`.
- CNI: k3s's bundled Flannel (default). Trade-off: Flannel does not enforce
  `NetworkPolicy`. Given the time available, NetworkPolicy was not attempted this round
  — the fix would be installing Calico as the CNI instead.

## 3. Request flow

A browser resolves `taskapp.<you>.duckdns.org` to the control-plane's public IP → hits
Traefik (k3s's built-in ingress controller) on port 443 → cert-manager's issued
Let's Encrypt certificate terminates TLS → Traefik routes all paths to the `frontend`
Service (port 80) → the frontend's nginx serves the React app and internally proxies
any `/api/*` request to `backend:5000` → the backend talks to `postgres:5432`
(headless Service → the single `postgres-0` Pod backed by its PVC).

## 4. Single-server assumptions this build fixes

| Single-server assumption | Why it breaks at scale | How it's fixed here |
|---|---|---|
| Migrations run in the app's entrypoint on boot | 2+ replicas race on the same migration command | A dedicated `Job` (`04-migration-job.yaml`) runs the migration once, before the app Deployments serve traffic |
| A named Docker volume on one host holds the DB data | Pods can be rescheduled to any node | Postgres is a `StatefulSet` with a `PersistentVolumeClaim`, so data follows the Pod regardless of node |
| `ports:` published directly on the host | Many Pods, many nodes — one front door is needed | An `Ingress` + Traefik gives one stable entry point regardless of which node serves the request |
| Docker Compose restarts a crashed container in place | A whole node can disappear | Kubernetes reschedules Pods onto healthy nodes automatically; probes catch unhealthy containers early |
| One deploy = brief downtime while the container restarts | Users mid-request get dropped | `RollingUpdate` with `maxUnavailable: 0` guarantees old Pods stay up until new ones are ready |
| `.env` file on the host holds secrets | No single host to protect once you have 3+ nodes | Secrets live as a Kubernetes `Secret`, created out-of-band (never committed to git) |

## 5. Choices & trade-offs

- **Raw YAML**, not Helm/kustomize — fastest to write and reason about under time
  pressure; the trade-off is more repetition across files.
- **Traefik** (k3s's bundled ingress controller), not ingress-nginx — it's already
  running the moment k3s starts, saving an install step.
- **Secrets**: created directly with `kubectl create secret generic` (out-of-band, not
  in git) rather than Sealed Secrets/External Secrets — the stretch-goal encrypted
  approach was out of scope for today's timeline.
- **Single control-plane, no HA etcd** — explicitly allowed by the brief; the
  difficulty asked for is Kubernetes itself, not control-plane quorum.
