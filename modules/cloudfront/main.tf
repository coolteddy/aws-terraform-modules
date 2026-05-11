# ---------------------------------------------------------------
# Managed cache policy lookup — resolved at plan time
# CachingOptimized is AWS's recommended policy for S3 origins:
# caches based on query strings and headers CloudFront controls
# ---------------------------------------------------------------

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "cors_s3" {
  name = "Managed-CORS-S3Origin"
}

# ---------------------------------------------------------------
# Origin Access Control (OAC)
# Signs CloudFront requests to S3 using SigV4 — the current AWS
# recommended approach. Replaces deprecated Origin Access Identity (OAI).
# The OAC ARN is passed to the S3 module via cloudfront_oac_arn so the
# S3 bucket policy allows only this CloudFront distribution to read objects.
# ---------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.name}-oac"
  description                       = "OAC for ${var.name} CloudFront distribution"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------------------------------------------------------------
# CloudFront Distribution
# ---------------------------------------------------------------

resource "aws_cloudfront_distribution" "this" {
  comment             = var.name
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = var.default_root_object
  aliases             = var.domain_aliases
  price_class         = var.price_class
  web_acl_id          = var.web_acl_arn

  # S3 origin — uses OAC for authentication
  origin {
    origin_id                = var.s3_origin_id
    domain_name              = var.s3_origin_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  # Default cache behaviour — applies to all requests
  # CachingOptimized: designed for S3 — caches efficiently based on
  # headers that CloudFront can control (no cookies, no auth headers)
  default_cache_behavior {
    target_origin_id         = var.s3_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = true
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_optimized.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.cors_s3.id

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    min_ttl     = var.min_ttl
    default_ttl = var.default_ttl
    max_ttl     = var.max_ttl
  }

  # Viewer certificate — two mutually exclusive modes:
  # 1. certificate_arn = null  → use CloudFront's own *.cloudfront.net cert (free)
  # 2. certificate_arn = "arn" → use custom ACM cert (must be in us-east-1)
  viewer_certificate {
    cloudfront_default_certificate = var.certificate_arn == null ? true : null
    acm_certificate_arn            = var.certificate_arn
    ssl_support_method             = var.certificate_arn != null ? "sni-only" : null
    # TLSv1.2_2021 drops TLS 1.0/1.1 and weak cipher suites — current AWS recommendation
    minimum_protocol_version = var.certificate_arn != null ? "TLSv1.2_2021" : null
  }

  # No geo-restriction by default — open to all countries
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Access logs — optional
  dynamic "logging_config" {
    for_each = var.enable_logging && var.logging_bucket != null ? [1] : []
    content {
      bucket          = var.logging_bucket
      prefix          = var.logging_prefix
      include_cookies = false
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-cloudfront" })
}
