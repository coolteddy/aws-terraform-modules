# Module: route53

Manages a Route 53 hosted zone and DNS records. Supports using an existing hosted zone
(default) or creating a new one.

## Cost

| Resource | Monthly cost |
|---|---|
| Hosted zone | $0.50/zone/month |
| Alias records (ALB, CloudFront) | Free — no query charges |
| A / CNAME queries | $0.40 per million queries |

---

## IMPORTANT — never delete an existing hosted zone

Deleting a hosted zone removes its NS records. Your domain registrar still points at the
old nameservers which no longer exist. DNS breaks globally for 24-48 hours while the
change propagates worldwide.

**Always use `terraform import` to bring an existing zone under Terraform management:**

```bash
# Find your zone ID in AWS console → Route 53 → Hosted zones
terraform import module.route53.aws_route53_zone.this[0] Z1234ABCDEF567
```

Then set `create_zone = true` in the module call so Terraform manages it without recreating it.

---

## Migration plan — moving zone from management to shared-services account

Your hosted zone currently lives in the management account. When ready to migrate:

```
Step 1 — Import zone into Terraform state (management account):
  terraform import aws_route53_zone.this Z1234ABCDEF567

Step 2 — Move DNS delegation to shared-services:
  Option A: Re-delegate the domain to new NS records in shared-services
  Option B: Use Route 53 Resolver rules to forward queries cross-account
  (full migration guide to be added when aws-shared-services-infra is built)
```

Do NOT recreate the zone — always import.

---

## Usage

### 1. Using an existing hosted zone (most common)

```hcl
module "route53" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/route53?ref=v1.0.0"

  create_zone = false
  zone_name   = "coolteddy.io"
  zone_id     = "Z1234ABCDEF567"   # from AWS console → Route 53 → Hosted zones

  # Alias record for ALB — free, handles dynamic IPs automatically
  alias_records = {
    "api" = {
      dns_name = module.alb.alb_dns_name
      zone_id  = module.alb.alb_zone_id
    }
    "videos" = {
      dns_name = module.cloudfront.distribution_domain_name
      zone_id  = module.cloudfront.distribution_hosted_zone_id  # always Z2FDTNDATAQYW2
    }
  }

  # A record for EC2 Elastic IP (greenhouse demo)
  a_records = {
    "demo" = module.ec2.public_ip
  }
}
```

### 2. Root domain → ALB (zone apex alias)

```hcl
module "route53" {
  source = "..."

  create_zone = false
  zone_name   = "coolteddy.io"
  zone_id     = "Z1234ABCDEF567"

  alias_records = {
    "" = {                               # "" = zone apex = coolteddy.io itself
      dns_name = module.alb.alb_dns_name
      zone_id  = module.alb.alb_zone_id
    }
    "www" = {                            # www.coolteddy.io → same ALB
      dns_name = module.alb.alb_dns_name
      zone_id  = module.alb.alb_zone_id
    }
  }
}
```

### 3. Creating a new hosted zone (fresh environment)

```hcl
module "route53" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/route53?ref=v1.0.0"

  create_zone = true
  zone_name   = "sandbox.coolteddy.io"   # subdomain zone for sandbox

  alias_records = {
    "api" = {
      dns_name = module.alb.alb_dns_name
      zone_id  = module.alb.alb_zone_id
    }
  }

  tags = { Env = "sandbox" }
}

# After apply — register these nameservers with the parent zone or registrar
output "nameservers" {
  value = module.route53.name_servers
}
```

### 4. CNAME records for third-party services

```hcl
module "route53" {
  source = "..."

  create_zone = false
  zone_name   = "coolteddy.io"
  zone_id     = "Z1234ABCDEF567"

  cname_records = {
    "www"  = "coolteddy.io"               # www → root
    "mail" = "ghs.googlehosted.com"       # Google Workspace
    "shop" = "shops.myshopify.com"        # Shopify storefront
  }
}
```

### 5. Passing zone_id to ACM module for certificate validation

```hcl
module "route53" {
  source      = "..."
  create_zone = false
  zone_name   = "coolteddy.io"
  zone_id     = "Z1234ABCDEF567"
}

module "acm" {
  source = "..."

  domain_name    = "coolteddy.io"
  hosted_zone_id = module.route53.zone_id   # ACM writes validation CNAME here
}
```

---

## Record types — when to use which

| Type | When to use | Notes |
|---|---|---|
| Alias A | ALB, NLB, CloudFront, S3 website endpoint | Free, works at root domain, AWS manages dynamic IPs |
| Plain A | EC2 Elastic IP, static IP | Charged per query, use `/32` always for EC2 |
| CNAME | Third-party services, `www` redirects | Cannot be used at zone apex (root domain) |

---

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `create_zone` | Create a new hosted zone. `false` = use existing. | `bool` | `false` | no |
| `zone_name` | Domain name (e.g. `coolteddy.io`) | `string` | — | yes |
| `zone_id` | Existing hosted zone ID — required when `create_zone = false` | `string` | `null` | no |
| `alias_records` | Map of subdomain → `{ dns_name, zone_id }` for ALB/CloudFront | `map(object)` | `{}` | no |
| `a_records` | Map of subdomain → IPv4 address for EC2 Elastic IPs | `map(string)` | `{}` | no |
| `cname_records` | Map of subdomain → target hostname | `map(string)` | `{}` | no |
| `default_ttl` | TTL in seconds for A and CNAME records | `number` | `300` | no |
| `tags` | Tags — applied to zone when `create_zone = true` | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `zone_id` | Hosted zone ID — pass to `module.acm` as `hosted_zone_id` |
| `zone_name` | Domain name of the hosted zone |
| `name_servers` | NS records — only when `create_zone = true`, register with domain registrar |
