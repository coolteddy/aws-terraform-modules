# ---------------------------------------------------------------
# S3 Bucket
# Minimal resource — all configuration in separate resources
# per AWS provider v5 best practice
# ---------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket = var.name
  tags   = merge(var.tags, { Name = var.name })
}

# ---------------------------------------------------------------
# Ownership Controls — disable ACLs (AWS recommended since 2023)
# BucketOwnerEnforced: bucket owner always owns all objects,
# ACLs are completely disabled, access via policies only
# ---------------------------------------------------------------

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ---------------------------------------------------------------
# Block Public Access — all four settings enabled by default
# Overrides any policy or ACL that would make objects public
# ---------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------
# Server-Side Encryption — SSE-S3 (AES-256) by default
# Free, zero performance overhead, AWS manages the keys
# bucket_key_enabled = true reduces API call costs if upgraded to SSE-KMS later
# ---------------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# ---------------------------------------------------------------
# Versioning — optional, off by default
# Enable when data loss protection matters more than cost
# ---------------------------------------------------------------

resource "aws_s3_bucket_versioning" "this" {
  count = var.enable_versioning ? 1 : 0

  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ---------------------------------------------------------------
# Lifecycle Rules — optional, automatically tier or expire objects
# ---------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = "Enabled"

      filter {
        prefix = rule.value.prefix
      }

      # Move to STANDARD_IA after N days — cheaper for infrequently accessed data
      # Minimum 30 days required by AWS
      dynamic "transition" {
        for_each = rule.value.transition_days > 0 ? [1] : []
        content {
          days          = rule.value.transition_days
          storage_class = "STANDARD_IA"
        }
      }

      # Move to GLACIER after N days — cheapest storage, retrieval takes minutes
      # Minimum 90 days required by AWS
      dynamic "transition" {
        for_each = rule.value.glacier_days > 0 ? [1] : []
        content {
          days          = rule.value.glacier_days
          storage_class = "GLACIER"
        }
      }

      # Permanently delete objects after N days
      dynamic "expiration" {
        for_each = rule.value.expiration_days > 0 ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }

      # Delete old versions after N days — only useful when versioning is enabled
      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_expiry_days > 0 ? [1] : []
        content {
          noncurrent_days = rule.value.noncurrent_expiry_days
        }
      }
    }
  }
}

# ---------------------------------------------------------------
# CORS Configuration — optional
# Only needed when a browser fetches objects directly from S3
# Not needed when CloudFront or EC2 accesses S3 server-side
# ---------------------------------------------------------------

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_origins = cors_rule.value.allowed_origins
      allowed_methods = cors_rule.value.allowed_methods
      allowed_headers = cors_rule.value.allowed_headers
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

# ---------------------------------------------------------------
# Bucket Policy — built from OAC grant + optional extra statements
# depends_on public_access_block: AWS rejects policies that grant
# public access when block_public_policy = true — the block must
# exist before the policy is evaluated
# ---------------------------------------------------------------

locals {
  create_policy = var.cloudfront_oac_arn != null || var.additional_policy_json != null

  oac_statements = var.cloudfront_oac_arn != null ? [
    {
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.this.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = var.cloudfront_oac_arn
        }
      }
    }
  ] : []

  extra_statements = var.additional_policy_json != null ? jsondecode(var.additional_policy_json).Statement : []

  all_statements = concat(local.oac_statements, local.extra_statements)
}

resource "aws_s3_bucket_policy" "this" {
  count = local.create_policy ? 1 : 0

  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.all_statements
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}
