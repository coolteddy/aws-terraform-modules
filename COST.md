# AWS Terraform Modules — Cost Reference

> Prices based on **eu-west-2 (Ireland)** as of May 2026.
> All figures are **per deployment** (i.e. one instance of the module).
> Costs are approximate — actual bills depend on data transfer, storage, and usage patterns.

---

## How to read this document

| Column | Meaning |
|---|---|
| **Idle cost** | Cost even when nothing is running through it |
| **Typical monthly** | Realistic cost for a lightly-used POC workload |
| **Free tier** | Whether AWS Free Tier applies (12-month new-account offer) |
| **⚠ Always-on** | This resource charges even when nothing is happening |

---

## Module: `vpc`

| Resource | Idle cost / month | Notes |
|---|---|---|
| VPC | $0.00 | Always free |
| Internet Gateway | $0.00 | Free; data transfer is charged separately |
| Subnets (4) | $0.00 | Always free |
| Route Tables | $0.00 | Always free |
| Elastic IP (1) | $0.00 | Free **only while attached to a running NAT**; $0.005/hr if unattached |
| ⚠ NAT Gateway | **~$32/month** | $0.045/hr × 730 hr — charged even with zero traffic |
| NAT data transfer | $0.045/GB | Separate from the hourly charge |

**Short-running (destroy after use):** $0 if you `terraform destroy` when done.
**Long-running (always on):** ~$32–$50/month depending on data transfer.

> **Flag:** The NAT Gateway is the only meaningful ongoing cost in this module.
> If you are running a dev/test environment and your private instances don't need internet access,
> you can set `enable_nat_gateway = false` in the module call to skip it entirely.
> The module will expose this as a configurable variable.

---

## Module: `eks`

| Resource | Idle cost / month | Notes |
|---|---|---|
| ⚠ EKS Control Plane | **~$72/month** | $0.10/hr — charged even with zero workloads |
| ⚠ Worker nodes (2× t3.medium, default) | **~$60/month** | $0.0416/hr each × 2 × 730 hr |
| EBS root volumes (2× 20 GB gp3) | ~$3/month | $0.088/GB/month |
| NAT Gateway (from VPC module) | ~$32/month | Nodes live in private subnets; need NAT to reach ECR |

**Short-running (destroy after use):** $0 if you destroy the cluster promptly.
**Long-running (always on):** **~$165/month** minimum (control plane + 2 nodes + NAT).

> **Flag:** EKS is the most expensive module here. The control plane alone costs ~$72/month
> with zero workloads. There is no free tier for EKS.
> Worker nodes can be scaled to zero manually, but the control plane keeps charging.
> For a pure POC, consider creating and destroying the cluster per-session.

---

## Module: `transit-gateway`

| Resource | Idle cost / month | Notes |
|---|---|---|
| ⚠ TGW (1 gateway) | **~$36/month** | $0.05/hr × 730 hr |
| ⚠ TGW VPC attachment (per account) | **~$36/month each** | $0.05/hr per attachment |
| Data transfer through TGW | $0.02/GB | Separate from hourly attachment charge |

**3-account org (management + shared-services + sandbox):**
- 1 TGW + 3 attachments = **~$144/month** just in TGW charges

**Short-running:** Still charges by the hour — but you could avoid it entirely during early POC
by using VPC peering instead (free to create, only data transfer costs).
**Long-running (always on):** ~$144/month for a 3-account org.

> **Flag:** Transit Gateway has the highest idle cost in this repo.
> Every VPC attachment charges ~$36/month whether traffic flows or not.
> For a startup POC with 3 accounts, consider starting with VPC Peering (free)
> and migrating to TGW when you have 5+ VPCs or need transitive routing.

---

## Module: `alb`

| Resource | Idle cost / month | Notes |
|---|---|---|
| ⚠ ALB (1 load balancer) | **~$5.76/month** | $0.008/hr × 730 hr minimum |
| LCU charges | ~$5–$20/month | Based on connections, bandwidth, rules evaluated |
| Free tier | ✅ 750 hours/month | New accounts only, first 12 months, single ALB |

**Short-running:** Near-zero if destroyed when not in use.
**Long-running (always on):** ~$10–$25/month for a lightly-used POC ALB.

> **Note:** The ALB is the cheapest always-on resource in this repo.
> The Free Tier covers one ALB for 12 months on a new AWS account.

---

## Combined POC Cost Summary

| Scenario | Monthly estimate |
|---|---|
| Everything deployed and running 24/7 | **~$340–$380/month** |
| EKS + VPC only (no TGW, no ALB) | **~$165/month** |
| VPC only (no EKS, no TGW, no ALB) | **~$32/month** |
| Nothing deployed (destroy everything) | **$0** |

> **Startup POC recommendation:**
> Deploy VPC first to validate networking.
> Create EKS only when you are actively testing workloads, then destroy it.
> Defer Transit Gateway until you have a real cross-account routing need.
> ALB is cheap enough to leave running if needed.

---

## Free Tier Summary

| Module | Free Tier? |
|---|---|
| vpc | Partially — VPC/subnets/IGW free forever; NAT Gateway is NOT free |
| eks | No |
| transit-gateway | No |
| alb | Yes — 750 hrs/month for 12 months (new account only) |
