# Module: alb

Creates an Application Load Balancer (Layer 7 — HTTP/HTTPS) with a target group, security group, and HTTP listener. Optionally adds an HTTPS listener and HTTP→HTTPS redirect when a certificate is provided.

Security group rules follow the current Terraform/AWS provider v5 best practice — each rule is a separate `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule` resource, not inline blocks.

## Cost

| Resource | Monthly cost |
|---|---|
| ALB hourly | ~$5.76/month — charged even when idle |
| LCU charges | ~$5–$20/month depending on traffic |
| Free tier | 750 hours/month for 12 months (new accounts only) |

## When to use ALB vs NLB

Use **ALB** when your workload speaks HTTP or HTTPS — web apps, REST APIs, gRPC services. ALB understands HTTP headers, can route by path or host, and integrates with WAF.

Use **NLB** when your workload speaks raw TCP/UDP — databases, game servers, IoT, or anything that is not HTTP.

---

## Usage

### 1. HTTP only (simplest — good for dev/POC)

```hcl
module "vpc" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/vpc?ref=v1.0.0"
  # ...
}

module "alb" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/alb?ref=v1.0.0"

  name        = "sandbox"
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.public_subnet_ids
  target_port = 8080

  tags = {
    Env     = "sandbox"
    Project = "my-startup"
  }
}

output "alb_url" {
  value = "http://${module.alb.alb_dns_name}"
}
```

### 2. HTTPS enabled (after ACM certificate exists)

```hcl
module "alb" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/alb?ref=v1.0.0"

  name            = "prod"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.public_subnet_ids
  target_port     = 8080
  enable_https    = true
  certificate_arn = module.acm.certificate_arn

  tags = {
    Env     = "prod"
    Project = "my-startup"
  }
}
```

When `enable_https = true`:
- Port 443 HTTPS listener is created and forwards to backends
- Port 80 listener issues a 301 redirect to HTTPS (browsers are automatically upgraded)
- Port 443 ingress rule is added to the security group automatically

### 3. Internal ALB (service-to-service traffic inside the VPC)

```hcl
module "internal_alb" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/alb?ref=v1.0.0"

  name                  = "internal-api"
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.private_subnet_ids   # private subnets for internal ALB
  target_port           = 3000
  internal              = true
  allowed_ingress_cidrs = [module.vpc.vpc_cidr_block]     # restrict to VPC traffic only

  tags = {
    Env     = "prod"
    Project = "my-startup"
  }
}
```

### 4. ECS Fargate backend (target_type = "ip")

```hcl
module "alb" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/alb?ref=v1.0.0"

  name        = "ecs-frontend"
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.public_subnet_ids
  target_port = 8080
  target_type = "ip"   # ECS Fargate tasks register by IP, not instance ID
}
```

### 5. Wiring backends — allow inbound from ALB only

Pass `security_group_id` to your compute module. This ensures backends only accept traffic from the ALB security group, not the open internet.

```hcl
module "asg" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/asg?ref=v1.0.0"

  # ...
  alb_security_group_id = module.alb.security_group_id   # backends only accept ALB traffic
  target_group_arn      = module.alb.target_group_arn    # ASG registers instances here
}
```

### 6. IPv6 ingress (dual-stack)

```hcl
module "alb" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/alb?ref=v1.0.0"

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
| `name` | Name prefix for all resources (keep under 20 chars — AWS limits ALB names to 32) | `string` | — | yes |
| `vpc_id` | VPC ID — from `module.vpc.vpc_id` | `string` | — | yes |
| `subnet_ids` | Subnet IDs for the ALB — public for internet-facing, private for internal | `list(string)` | — | yes |
| `target_port` | Port your backend application listens on | `number` | — | yes |
| `tags` | Tags applied to all resources | `map(string)` | `{}` | no |
| `internal` | `true` = private internal ALB; `false` = internet-facing | `bool` | `false` | no |
| `target_type` | `instance` for EC2/ASG, `ip` for ECS Fargate or EKS pods | `string` | `"instance"` | no |
| `health_check_path` | HTTP path for backend health checks | `string` | `"/"` | no |
| `health_check_interval` | Seconds between health checks | `number` | `30` | no |
| `deregistration_delay` | Seconds to wait before removing a draining target | `number` | `30` | no |
| `allowed_ingress_cidrs` | IPv4 CIDRs allowed to reach the ALB | `list(string)` | `["0.0.0.0/0"]` | no |
| `allowed_ingress_ipv6_cidrs` | IPv6 CIDRs allowed to reach the ALB | `list(string)` | `[]` | no |
| `ip_address_type` | `ipv4` (default), `dualstack` (IPv4+IPv6), or `dualstack-without-public-ipv4` | `string` | `"ipv4"` | no |
| `enable_deletion_protection` | Prevent accidental destroy — set `true` in production | `bool` | `false` | no |
| `enable_https` | Add HTTPS listener on port 443 and redirect HTTP→HTTPS | `bool` | `false` | no |
| `certificate_arn` | ACM certificate ARN — required when `enable_https = true` | `string` | `null` | no |

## Outputs

| Name | Description |
|---|---|
| `alb_arn` | ARN of the ALB |
| `alb_dns_name` | DNS name — use as Route 53 alias target |
| `alb_zone_id` | Hosted zone ID — required alongside `alb_dns_name` for Route 53 alias records |
| `target_group_arn` | Target group ARN — pass to ASG, ECS, or EKS to register backends |
| `security_group_id` | ALB security group ID — pass to compute modules to restrict inbound to ALB only |
| `http_listener_arn` | Port-80 listener ARN — attach additional path-based routing rules here |
| `https_listener_arn` | Port-443 listener ARN, or `null` if HTTPS is disabled |
