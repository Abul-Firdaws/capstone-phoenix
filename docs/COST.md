# Cost — Capstone Phoenix

## Monthly itemized cost (if left running continuously — approximate, verify current
AWS pricing before relying on these numbers)

| Item | Spec | Qty | $/mo (approx) |
|---|---|---:|---:|
| Control-plane VM | t3.medium | 1 | ~$30 |
| Worker VMs | t3.medium | 2 | ~$60 |
| Block storage (root volumes) | gp3, 20GB each | 3 | ~$5 |
| Postgres PVC | local-path (uses worker's own disk) | 1 | included above |
| S3 (Terraform state) | a few KB | 1 | <$0.10 |
| DynamoDB (state lock) | pay-per-request | 1 | <$1 |
| Domain (DuckDNS) | free subdomain | 1 | $0 |
| **Total** | | | **~$96/mo** |

In practice this build only runs for the hours needed to develop, demo, and grade —
realistically a few dollars total, not a full month — and is destroyed with
`terraform destroy` immediately after.

## Compared to the single-server Compose + Portainer deploy

- That stack: 1 small VM, roughly $10–15/month.
- This cluster: ~$96/month if run continuously.
- **What the extra ~$80/month buys:** the app survives a node dying, zero-downtime
  deploys, automatic scaling under load, and self-healing — all things a single server
  simply cannot do. **When it's not worth it:** a low-traffic internal tool or a
  personal project where a few minutes of downtime during a manual restart is a
  non-issue; the single-server setup is far cheaper and simpler to operate for that
  case.

## How I'd halve this

Switch the 2 worker nodes to **Spot Instances** (roughly 60–70% cheaper than
on-demand) since workers are stateless and safely replaceable if reclaimed; drop the
instance size to `t3.small` for the workers once real resource usage is measured
(`kubectl top pods`) and requests/limits are right-sized accordingly; and stop
(not terminate) all 3 nodes outside of active development/demo hours using a
scheduled Lambda or a cron job, since a stopped EC2 instance is not billed for compute.
