# Module: acm

Issues free TLS certificates via AWS Certificate Manager with automatic DNS validation
through Route 53. Creates two certificates when needed:
- **Regional** — for ALB in your workload region (e.g. eu-west-2)
- **CloudFront** — in us-east-1, required by CloudFront regardless of workload region

## Cost

| Resource | Cost |
|---|---|
| ACM certificates | **Free** — no charge for issuing or renewing |
| Route 53 validation records | Free — standard hosted zone record pricing applies |

## How DNS validation works

1. You call this module with your domain and Route 53 hosted zone ID
2. ACM generates CNAME validation records for each domain on the certificate
3. Terraform writes those CNAME records to Route 53 automatically
4. ACM reads the records back to confirm you own the domain
5. Certificate status changes to `ISSUED` — Terraform unblocks and continues
6. ACM auto-renews the certificate every year — no manual action needed

---

## Caller setup — provider aliases required

The caller must configure two AWS providers and pass both to this module:

```hcl
# root providers.tf or main.tf in the calling repo
provider "aws" {
  region = "eu-west-2"   # your workload region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"   # required for CloudFront certs
}
```

---

## Usage

### 1. Wildcard cert for ALB + CloudFront (most common)

```hcl
data "aws_route53_zone" "this" {
  name = "coolteddy.io"
}

module "acm" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/acm?ref=v1.0.0"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  domain_name               = "coolteddy.io"
  subject_alternative_names = ["*.coolteddy.io"]   # covers all subdomains
  hosted_zone_id            = data.aws_route53_zone.this.zone_id

  tags = {
    Env     = "prod"
    Project = "my-startup"
  }
}

# Pass regional cert to ALB
module "alb" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/alb?ref=v1.0.0"
  # ...
  enable_https    = true
  certificate_arn = module.acm.regional_certificate_arn
}

# Pass CloudFront cert to CloudFront
module "cloudfront" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/cloudfront?ref=v1.0.0"
  # ...
  certificate_arn = module.acm.cloudfront_certificate_arn
}
```

### 2. ALB only — no CloudFront cert needed

```hcl
module "acm" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/acm?ref=v1.0.0"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  domain_name            = "coolteddy.io"
  hosted_zone_id         = data.aws_route53_zone.this.zone_id
  create_cloudfront_cert = false   # skip the us-east-1 cert
}
```

### 3. Greenhouse demo — single domain, no wildcard

```hcl
module "acm" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/acm?ref=v1.0.0"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  domain_name            = "demo.coolteddy.io"
  hosted_zone_id         = data.aws_route53_zone.this.zone_id
  create_cloudfront_cert = false   # Nginx on EC2 handles TLS, no CloudFront
}

module "ec2" {
  # Nginx on the instance uses this cert for HTTPS
  # (install cert on instance via user_data or Certbot)
}
```

---

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `domain_name` | Primary domain (e.g. `coolteddy.io` or `*.coolteddy.io`) | `string` | — | yes |
| `hosted_zone_id` | Route 53 hosted zone ID for DNS validation | `string` | — | yes |
| `subject_alternative_names` | Additional domains on the cert (e.g. `["*.coolteddy.io"]`) | `list(string)` | `[]` | no |
| `create_cloudfront_cert` | Create a second cert in us-east-1 for CloudFront | `bool` | `true` | no |
| `tags` | Tags applied to certificates | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `regional_certificate_arn` | Validated cert ARN for your workload region — pass to `module.alb` as `certificate_arn` |
| `cloudfront_certificate_arn` | Validated cert ARN in us-east-1 — pass to `module.cloudfront`. `null` if `create_cloudfront_cert = false` |

## Notes

- Outputs reference `aws_acm_certificate_validation` not `aws_acm_certificate` — this ensures the ARN is only available after the certificate is fully validated and `ISSUED`. Passing an unvalidated ARN to ALB or CloudFront causes a deployment error.
- Provider aliases must be passed explicitly — Terraform does not inherit the caller's providers automatically for modules that declare `configuration_aliases`.
