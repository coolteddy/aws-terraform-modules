# Module: s3

Creates a private, encrypted S3 bucket following current AWS best practices:
- ACLs disabled (`BucketOwnerEnforced`) — access via bucket policies and IAM only
- All public access blocked by default
- SSE-S3 (AES-256) encryption enabled by default — free, AWS manages keys
- Optional versioning, lifecycle rules, CORS, and CloudFront OAC policy

## Cost

| Resource | Monthly cost |
|---|---|
| Storage (Standard) | $0.023/GB/month |
| Storage (Standard-IA) | $0.0125/GB/month — min 30-day charge per object |
| Storage (Glacier) | $0.004/GB/month — retrieval takes minutes to hours |
| PUT/COPY/POST | $0.005 per 1,000 requests |
| GET/SELECT | $0.0004 per 1,000 requests |
| Versioning | Each version counts as a separate object — multiplies storage cost |
| Free tier | 5GB Standard, 20,000 GET, 2,000 PUT per month for 12 months |

## Bucket naming

S3 bucket names must be globally unique across all AWS accounts. Two approaches:

```
Traditional:      coolteddy-videos-prod
Account-scoped:   coolteddy-123456789012-eu-west-2-an   ← AWS recommended
```

The account-scoped format (`{prefix}-{account-id}-{region}-an`) guarantees name ownership —
no other account can claim it, even if you delete and recreate the bucket.

---

## Usage

### 1. Greenhouse demo — CSV data storage, EC2 reads via IAM role

```hcl
module "s3" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/s3?ref=v1.0.0"

  name = "coolteddy-greenhouse-123456789012-eu-west-2-an"

  tags = {
    Env     = "poc"
    Project = "greenhouse-demo"
  }
}

# Pass the bucket ARN to EC2 so the instance profile gets S3 read access
module "ec2" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/ec2?ref=v1.0.0"

  # ...
  s3_read_bucket_arns = [module.s3.bucket_arn]
}
```

### 2. Video storage with lifecycle — move to cheaper storage over time

```hcl
module "s3" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/s3?ref=v1.0.0"

  name              = "coolteddy-videos-123456789012-eu-west-2-an"
  enable_versioning = true

  lifecycle_rules = [
    {
      id              = "archive-videos"
      prefix          = "videos/"          # apply to videos/ prefix only
      transition_days = 30                 # move to Standard-IA after 30 days
      glacier_days    = 90                 # move to Glacier after 90 days
      expiration_days = 365                # delete after 1 year
      noncurrent_expiry_days = 30          # delete old versions after 30 days
    },
    {
      id              = "expire-temp"
      prefix          = "temp/"            # apply to temp/ prefix only
      transition_days = 0                  # no transition
      glacier_days    = 0
      expiration_days = 7                  # delete temp files after 7 days
      noncurrent_expiry_days = 0
    }
  ]

  tags = {
    Env     = "prod"
    Project = "my-startup"
  }
}
```

### 3. CloudFront CDN origin — OAC access (current AWS recommendation)

```hcl
module "s3" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/s3?ref=v1.0.0"

  name = "coolteddy-videos-123456789012-eu-west-2-an"

  # OAC ARN from the CloudFront module — allows CloudFront to read this bucket
  cloudfront_oac_arn = module.cloudfront.distribution_arn
}

module "cloudfront" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/cloudfront?ref=v1.0.0"

  # Use regional domain — avoids 307 redirect issues with new buckets
  s3_origin_domain_name = module.s3.bucket_regional_domain_name
}
```

**Why `bucket_regional_domain_name` not `bucket_domain_name`:**
Newly created buckets can return HTTP 307 redirects on the global endpoint for a few minutes
while DNS propagates. CloudFront does not follow redirects and will error. The regional endpoint
resolves immediately with no redirect.

### 4. CORS — browser fetches objects directly from S3

Only needed when JavaScript in the browser calls S3 directly.
Not needed when CloudFront or EC2 fetches objects server-side.

```hcl
module "s3" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/s3?ref=v1.0.0"

  name = "coolteddy-assets-123456789012-eu-west-2-an"

  cors_rules = [
    {
      allowed_origins = ["https://app.coolteddy.io"]
      allowed_methods = ["GET", "HEAD"]
      allowed_headers = ["*"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3600
    }
  ]
}
```

### 5. Additional policy — cross-account access

```hcl
module "s3" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/s3?ref=v1.0.0"

  name = "coolteddy-shared-123456789012-eu-west-2-an"

  additional_policy_json = jsonencode({
    Statement = [
      {
        Sid       = "AllowSharedServicesAccount"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::SHARED_ACCOUNT_ID:root" }
        Action    = ["s3:GetObject", "s3:ListBucket"]
        Resource  = [
          "arn:aws:s3:::coolteddy-shared-123456789012-eu-west-2-an",
          "arn:aws:s3:::coolteddy-shared-123456789012-eu-west-2-an/*"
        ]
      }
    ]
  })
}
```

---

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name` | Bucket name — globally unique. Use account-scoped format for guaranteed ownership. | `string` | — | yes |
| `tags` | Tags applied to all resources | `map(string)` | `{}` | no |
| `enable_versioning` | Keep previous object versions on overwrite/delete — increases storage cost | `bool` | `false` | no |
| `lifecycle_rules` | Automatic object tiering and expiration rules — see usage examples | `list(object)` | `[]` | no |
| `cors_rules` | CORS rules for browser-based direct S3 access — not needed when CloudFront is used | `list(object)` | `[]` | no |
| `cloudfront_oac_arn` | CloudFront distribution ARN — adds OAC bucket policy allowing CloudFront to read objects | `string` | `null` | no |
| `additional_policy_json` | Additional bucket policy statements as JSON — merged with OAC policy if both are set | `string` | `null` | no |

## Outputs

| Name | Description |
|---|---|
| `bucket_name` | Bucket name — use in application config and AWS CLI |
| `bucket_arn` | Bucket ARN — pass to `ec2` module's `s3_read_bucket_arns` or IAM policies |
| `bucket_regional_domain_name` | Regional domain name — use as CloudFront origin, not the global endpoint |
| `bucket_id` | Bucket ID (same as name) — used when other Terraform resources reference this bucket |

## Security notes

- **ACLs are disabled** — `BucketOwnerEnforced` means no ACL grants are accepted. Access is via bucket policies and IAM roles only.
- **Block public access** — all four settings enabled. Even if a policy accidentally grants public access, AWS will block it.
- **OAC not OAI** — if using CloudFront, always use Origin Access Control. OAI was deprecated by AWS in 2022.
- **Encryption** — SSE-S3 (AES-256) enabled by default. No cost, no performance impact.
