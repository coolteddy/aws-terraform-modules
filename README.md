# aws-terraform-modules

Reusable Terraform module library for a multi-tenant SaaS AWS organisation.
Modules are versioned with git tags — consuming repos pin to a specific release:

```hcl
module "vpc" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/vpc?ref=v1.0.0"
}
```

---

## Modules

| Module | Description | Cost flag |
|--------|-------------|-----------|
| [`vpc`](modules/vpc/) | VPC with public/private subnets, NAT Gateway toggle, any number of AZs | NAT Gateway ~$32/month |
| [`alb`](modules/alb/) | Application Load Balancer — HTTP/HTTPS, dual-stack, WAF-ready | ~$6/month |
| [`nlb`](modules/nlb/) | Network Load Balancer — TCP/UDP/TLS, dual-stack | ~$6/month |
| [`asg`](modules/asg/) | Auto Scaling Group with Launch Template, IMDSv2, SSM instance profile | EC2 cost varies |
| [`ec2`](modules/ec2/) | Single EC2 instance — Elastic IP, IMDSv2, SSM, optional data volume | EC2 cost varies |
| [`s3`](modules/s3/) | Private encrypted S3 bucket — OAC, lifecycle rules, CORS | ~$0.023/GB/month |
| [`acm`](modules/acm/) | ACM certificates — regional + us-east-1 for CloudFront | Free |
| [`rds`](modules/rds/) | PostgreSQL RDS — managed password toggle, deletion protection | ~$15+/month |
| [`eks`](modules/eks/) | EKS cluster — OIDC/IRSA, Access Entries, IMDSv2, Karpenter-ready | ~$73/month + nodes |
| [`transit-gateway`](modules/transit-gateway/) | TGW — RAM sharing, org-scoped or account-scoped | ~$36/month + attachments |
| [`cloudfront`](modules/cloudfront/) | CloudFront CDN — OAC (not OAI), WAF, managed cache policies | Free tier / ~$0.009/GB |
| [`route53`](modules/route53/) | Route 53 — alias/A/CNAME records, existing zone import support | $0.50/zone/month |
| [`secrets`](modules/secrets/) | Secrets Manager — per-tenant + cross-account central pattern | $0.40/secret/month |
| [`ecr`](modules/ecr/) | ECR — IMMUTABLE tags, org-scoped pull via `aws:PrincipalOrgID` | $0.10/GB/month |
| [`ecs`](modules/ecs/) | ECS Fargate — execution/task roles, secrets injection, CloudWatch logs | ~$11+/month |

See [`COST.md`](COST.md) for detailed per-module cost breakdowns.

---

## Repository layout

```
modules/
  vpc/               versions.tf  variables.tf  main.tf  outputs.tf  README.md
  alb/               ...
  ...
COST.md              Estimated monthly cost for every module
KEYWORDS.md          38 Terraform concepts with Terraform Console examples
AWS-ACCESS.md        SSM, Tailscale, WireGuard, Client VPN setup guide
TGW-TEST-PLAN.md     3-account Transit Gateway validation test (~$0.43, ~2 hours)
CLAUDE.md            Session context for AI-assisted development
```

---

## Usage

### Pinning to a release

Always pin to a specific tag in consuming repos. Never use `?ref=main`.

```hcl
module "vpc" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/vpc?ref=v1.0.0"

  name       = "sandbox"
  cidr_block = "10.0.0.0/16"

  public_subnets  = { "eu-west-2a" = "10.0.0.0/24", "eu-west-2b" = "10.0.1.0/24" }
  private_subnets = { "eu-west-2a" = "10.0.10.0/24", "eu-west-2b" = "10.0.11.0/24" }
}
```

### Upgrading a module version

```bash
# Change ?ref= in your consuming repo, then:
terraform init -upgrade
terraform plan    # review changes carefully
terraform apply
```

---

## Standards

Every module follows these conventions:

- **`versions.tf`** — Terraform >= 1.5, AWS provider ~> 5.0
- **`variables.tf`** — all inputs typed and described, no hardcoded values
- **`main.tf`** — security group rules use separate `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule` resources (AWS provider v5 best practice)
- **`outputs.tf`** — all outputs a caller needs; sensitive values marked `sensitive = true`
- **`README.md`** — usage examples, full inputs/outputs table, cost note

---

## Region

All examples use **eu-west-2 (London)**. Modules are region-agnostic — pass your region via the AWS provider in the consuming repo.

---

## Consuming repos

| Repo | Purpose |
|------|---------|
| [`aws-org-infra`](https://github.com/coolteddy/aws-org-infra) | ✅ Complete — org structure, SCPs, GitHub OIDC |
| `aws-shared-services-infra` | Planned — ECR, Secrets Manager, TGW hub |
| `aws-sandbox-infra` | Planned — sandbox workloads, testing ground |

---

## Versioning

| Tag | Notes |
|-----|-------|
| `v1.0.0` | Initial release — all 15 modules |
| `v1.1.0` | Planned — RDS `storage_type` variable, EKS 1.34→1.35 upgrade demo, S3 prevent_destroy option |
