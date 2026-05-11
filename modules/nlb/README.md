# Module: nlb

Creates a Network Load Balancer (Layer 4 — TCP/UDP/TLS) with a target group, security group, and listener. Optionally adds a TLS listener when a certificate is provided.

Security group rules follow the current Terraform/AWS provider v5 best practice — each rule is a separate `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule` resource, not inline blocks.

## Cost

| Resource | Monthly cost |
|---|---|
| NLB hourly | ~$5.76/month — charged even when idle |
| NLCU charges | ~$3–$15/month depending on traffic |
| Free tier | 750 hours/month for 12 months (new accounts only) |

## When to use NLB vs ALB

Use **NLB** when your workload speaks raw TCP or UDP — databases, game servers, IoT sensors, VoIP, or any protocol that is not HTTP. NLB preserves the client's source IP and provides one static IP address per AZ.

Use **ALB** when your workload speaks HTTP or HTTPS — web apps, REST APIs, gRPC.

---

## Usage

### 1. TCP listener (default — for databases, raw TCP services)

```hcl
module "vpc" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/vpc?ref=v1.0.0"
  # ...
}

module "nlb" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/nlb?ref=v1.0.0"

  name        = "data-pipeline"
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.public_subnet_ids
  target_port = 5432   # PostgreSQL

  tags = {
    Env     = "sandbox"
    Project = "my-startup"
  }
}
```

### 2. Internal NLB (service-to-service inside the VPC)

```hcl
module "nlb" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/nlb?ref=v1.0.0"

  name                  = "db-nlb"
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.private_subnet_ids
  target_port           = 5432
  internal              = true
  allowed_ingress_cidrs = [module.vpc.vpc_cidr_block]   # VPC traffic only

  tags = {
    Env     = "prod"
    Project = "my-startup"
  }
}
```

### 3. TLS termination (NLB decrypts, backend receives plain TCP)

```hcl
module "nlb" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/nlb?ref=v1.0.0"

  name            = "secure-pipeline"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.public_subnet_ids
  target_port     = 5432
  enable_tls      = true
  certificate_arn = module.acm.certificate_arn
}
```

### 4. HTTP health checks (when backend exposes a /health endpoint)

```hcl
module "nlb" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/nlb?ref=v1.0.0"

  name                  = "app-nlb"
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.public_subnet_ids
  target_port           = 8080
  health_check_protocol = "HTTP"
  health_check_path     = "/health"
  health_check_interval = 10
}
```

### 5. Wiring backends — allow inbound from NLB only

```hcl
module "asg" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/asg?ref=v1.0.0"

  # ...
  nlb_security_group_id = module.nlb.security_group_id   # backends only accept NLB traffic
  target_group_arn      = module.nlb.target_group_arn
}
```

### 6. IPv6 ingress (dual-stack)

```hcl
module "nlb" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/nlb?ref=v1.0.0"

  name                       = "sandbox"
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.public_subnet_ids
  target_port                = 8080
  allowed_ingress_cidrs      = ["0.0.0.0/0"]
  allowed_ingress_ipv6_cidrs = ["::/0"]
}
```

---

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name` | Name prefix for all resources (keep under 20 chars — AWS limits NLB names to 32) | `string` | — | yes |
| `vpc_id` | VPC ID — from `module.vpc.vpc_id` | `string` | — | yes |
| `subnet_ids` | Subnet IDs — public for internet-facing, private for internal | `list(string)` | — | yes |
| `target_port` | Port your backend listens on | `number` | — | yes |
| `tags` | Tags applied to all resources | `map(string)` | `{}` | no |
| `internal` | `true` = private internal NLB; `false` = internet-facing | `bool` | `false` | no |
| `listener_protocol` | NLB listener protocol: `TCP`, `UDP`, `TLS`, `TCP_UDP` | `string` | `"TCP"` | no |
| `target_protocol` | Protocol to backends: `TCP`, `UDP`, `TCP_UDP` | `string` | `"TCP"` | no |
| `target_type` | `instance` for EC2/ASG, `ip` for ECS Fargate or EKS pods | `string` | `"instance"` | no |
| `health_check_protocol` | Health check protocol: `TCP`, `HTTP`, `HTTPS` | `string` | `"TCP"` | no |
| `health_check_path` | Health check path — only used when `health_check_protocol` is HTTP/HTTPS | `string` | `"/"` | no |
| `health_check_interval` | Seconds between health checks — NLB accepts `10` or `30` only | `number` | `30` | no |
| `deregistration_delay` | Seconds to wait before removing a draining target | `number` | `30` | no |
| `cross_zone_load_balancing` | Distribute traffic evenly across all AZs | `bool` | `true` | no |
| `allowed_ingress_cidrs` | IPv4 CIDRs allowed to reach the NLB | `list(string)` | `["0.0.0.0/0"]` | no |
| `allowed_ingress_ipv6_cidrs` | IPv6 CIDRs allowed to reach the NLB | `list(string)` | `[]` | no |
| `ip_address_type` | `ipv4` (default) or `dualstack` (IPv4+IPv6) | `string` | `"ipv4"` | no |
| `enable_deletion_protection` | Prevent accidental destroy — set `true` in production | `bool` | `false` | no |
| `enable_tls` | Add TLS listener on port 443 — NLB terminates TLS, backends receive plain TCP | `bool` | `false` | no |
| `certificate_arn` | ACM certificate ARN — required when `enable_tls = true` | `string` | `null` | no |

## Outputs

| Name | Description |
|---|---|
| `nlb_arn` | ARN of the NLB |
| `nlb_dns_name` | DNS name — use as Route 53 alias target |
| `nlb_zone_id` | Hosted zone ID — required alongside `nlb_dns_name` for Route 53 alias records |
| `target_group_arn` | Target group ARN — pass to ASG, ECS, or EKS to register backends |
| `security_group_id` | NLB security group ID — pass to compute modules to restrict inbound to NLB only |
| `listener_arn` | Active listener ARN (plain or TLS) |
| `tls_listener_arn` | TLS listener ARN, or `null` if `enable_tls` is false |
