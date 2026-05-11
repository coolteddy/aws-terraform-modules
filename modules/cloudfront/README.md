# Module: cloudfront

Creates a CloudFront distribution with an Origin Access Control (OAC) for private S3 access.
Serves content from S3 to users worldwide from the nearest edge location.

Uses OAC (Origin Access Control) — the current AWS recommendation. OAI (Origin Access Identity)
is deprecated and not supported by this module.

## Cost

| Resource | Monthly cost |
|---|---|
| Distribution | Free to create |
| Data transfer out — first 1TB (EU) | ~$8.50/TB ($0.0085/GB) |
| HTTP/HTTPS requests — first 10M | $0.0075 per 10,000 |
| Free tier | 1TB transfer + 10M requests/month for 12 months |

CloudFront is one of the cheapest AWS services. For a startup POC, costs are near zero.

---

## Important — avoiding circular dependency with the S3 module

This is a common mistake. **Do not** wire the modules like this:

```hcl
# WRONG — circular dependency, Terraform will error
module "s3" {
  cloudfront_oac_arn = module.cloudfront.distribution_arn  # S3 depends on CF
}
module "cloudfront" {
  s3_origin_domain_name = module.s3.bucket_regional_domain_name  # CF depends on S3
}
# Error: Cycle: module.s3, module.cloudfront
```

**Correct pattern — create the S3 bucket policy as a standalone resource:**

```hcl
# 1. S3 bucket — no CloudFront reference
module "s3" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/s3?ref=v1.0.0"
  name   = "coolteddy-videos-123456789012-eu-west-2-an"
}

# 2. CloudFront — references S3 (one-way dependency)
module "cloudfront" {
  source                = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/cloudfront?ref=v1.0.0"
  s3_origin_domain_name = module.s3.bucket_regional_domain_name
  # ...
}

# 3. Bucket policy — created in the root module, after both exist
resource "aws_s3_bucket_policy" "cloudfront_access" {
  bucket = module.s3.bucket_id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${module.s3.bucket_arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = module.cloudfront.distribution_arn
        }
      }
    }]
  })
}
```

Dependency order Terraform resolves automatically:
```
aws_s3_bucket → aws_cloudfront_distribution → aws_s3_bucket_policy
```

---

## Usage

### 1. Basic — S3 video delivery, no custom domain

```hcl
module "s3" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/s3?ref=v1.0.0"
  name   = "coolteddy-videos-123456789012-eu-west-2-an"
  tags   = { Env = "prod" }
}

module "cloudfront" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/cloudfront?ref=v1.0.0"

  name                  = "videos"
  s3_origin_domain_name = module.s3.bucket_regional_domain_name

  tags = { Env = "prod", Project = "my-startup" }
}

# Bucket policy — created here, not in the S3 module (avoids circular dependency)
resource "aws_s3_bucket_policy" "cloudfront_access" {
  bucket = module.s3.bucket_id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${module.s3.bucket_arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = module.cloudfront.distribution_arn }
      }
    }]
  })
}

output "cdn_url" {
  value = "https://${module.cloudfront.distribution_domain_name}"
}
```

### 2. Custom domain with ACM certificate

```hcl
data "aws_route53_zone" "this" {
  name = "coolteddy.io"
}

module "acm" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/acm?ref=v1.0.0"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1   # CloudFront cert must be in us-east-1
  }

  domain_name               = "coolteddy.io"
  subject_alternative_names = ["*.coolteddy.io"]
  hosted_zone_id            = data.aws_route53_zone.this.zone_id
}

module "cloudfront" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/cloudfront?ref=v1.0.0"

  name                  = "videos"
  s3_origin_domain_name = module.s3.bucket_regional_domain_name
  certificate_arn       = module.acm.cloudfront_certificate_arn   # us-east-1 cert
  domain_aliases        = ["videos.coolteddy.io"]
}
```

### 3. With access logging

```hcl
# Create a separate S3 bucket for logs first
module "log_bucket" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/s3?ref=v1.0.0"
  name   = "coolteddy-cf-logs-123456789012-eu-west-2-an"
}

module "cloudfront" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/cloudfront?ref=v1.0.0"

  name                  = "videos"
  s3_origin_domain_name = module.s3.bucket_regional_domain_name
  enable_logging        = true
  logging_bucket        = "${module.log_bucket.bucket_name}.s3.amazonaws.com"
  logging_prefix        = "cloudfront/"
}
```

### 4. Cache behaviour explained

```
PriceClass_100 (default) — edge locations in:
  EU, North America
  ~$0.0085/GB outbound

PriceClass_200 — adds:
  Middle East, Africa, South America, Asia Pacific (partial)

PriceClass_All — all edge locations worldwide (~600 locations)
  More expensive but lowest latency for global audiences
```

### 5. Cache invalidation after deploying new files

When you upload new files to S3, CloudFront may still serve the old cached version.
Invalidate the cache in CI/CD after deployment:

```bash
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw distribution_id) \
  --paths "/*"
```

Invalidations cost $0.005 per path after the first 1,000/month (free tier).
Use `/videos/new-file.mp4` to invalidate one file, or `/*` for everything.

### 6. Wiring to Route 53 (in consuming repo)

```hcl
resource "aws_route53_record" "videos" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "videos"
  type    = "A"

  alias {
    name                   = module.cloudfront.distribution_domain_name
    zone_id                = module.cloudfront.distribution_hosted_zone_id  # always Z2FDTNDATAQYW2
    evaluate_target_health = false
  }
}
```

---

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name` | Name prefix — used as OAC name and distribution comment | `string` | — | yes |
| `s3_origin_domain_name` | Regional S3 domain — from `module.s3.bucket_regional_domain_name` | `string` | — | yes |
| `s3_origin_id` | Internal label for the S3 origin | `string` | `"s3-origin"` | no |
| `certificate_arn` | ACM cert ARN in us-east-1 for custom domain — from `module.acm.cloudfront_certificate_arn` | `string` | `null` | no |
| `domain_aliases` | Custom domains (e.g. `["videos.coolteddy.io"]`) — required when `certificate_arn` is set | `list(string)` | `[]` | no |
| `default_root_object` | Object returned for requests to `/` | `string` | `"index.html"` | no |
| `price_class` | Edge location coverage — `PriceClass_100` (EU+NA), `PriceClass_200`, `PriceClass_All` | `string` | `"PriceClass_100"` | no |
| `default_ttl` | Default cache duration in seconds | `number` | `86400` | no |
| `max_ttl` | Maximum cache duration in seconds | `number` | `31536000` | no |
| `min_ttl` | Minimum cache duration in seconds | `number` | `0` | no |
| `web_acl_arn` | ARN of an AWS WAFv2 WebACL in us-east-1 to associate with this distribution | `string` | `null` | no |
| `enable_logging` | Send access logs to S3 | `bool` | `false` | no |
| `logging_bucket` | S3 bucket domain for logs — required when `enable_logging = true` | `string` | `null` | no |
| `logging_prefix` | Key prefix for log files | `string` | `"cloudfront/"` | no |
| `tags` | Tags applied to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `distribution_id` | Distribution ID — use in `aws cloudfront create-invalidation` after deployments |
| `distribution_arn` | Distribution ARN — **do not** pass to S3 module directly (circular dependency); create `aws_s3_bucket_policy` in consuming repo instead |
| `distribution_domain_name` | CloudFront domain (e.g. `d1234abcd.cloudfront.net`) — Route 53 alias target |
| `distribution_hosted_zone_id` | CloudFront hosted zone ID — always `Z2FDTNDATAQYW2`, required for Route 53 alias |
| `oac_id` | Origin Access Control ID |
