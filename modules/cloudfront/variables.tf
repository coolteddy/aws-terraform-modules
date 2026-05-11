variable "name" {
  description = "Name prefix — used as the OAC name and CloudFront distribution comment"
  type        = string
}

variable "s3_origin_domain_name" {
  description = "Regional S3 domain name for the origin — from module.s3.bucket_regional_domain_name. Use the regional endpoint (e.g. my-bucket.s3.eu-west-2.amazonaws.com) not the global one to avoid 307 redirect issues with new buckets."
  type        = string
}

variable "s3_origin_id" {
  description = "Internal label for the S3 origin — referenced in cache behaviours. Arbitrary string, must be unique within the distribution."
  type        = string
  default     = "s3-origin"
}

# ---------------------------------------------------------------
# HTTPS and custom domain
# certificate_arn must be a us-east-1 ACM certificate — from module.acm.cloudfront_certificate_arn
# When null, CloudFront uses its own *.cloudfront.net domain with a free AWS certificate
# ---------------------------------------------------------------

variable "certificate_arn" {
  description = "ACM certificate ARN in us-east-1 for HTTPS on a custom domain — from module.acm.cloudfront_certificate_arn. Leave null to use the default *.cloudfront.net domain (free, no custom domain needed)."
  type        = string
  default     = null
}

variable "domain_aliases" {
  description = "Custom domain names served by this distribution (e.g. ['videos.coolteddy.io']). Required when certificate_arn is set. Leave empty to use the *.cloudfront.net domain."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------
# Caching
# ---------------------------------------------------------------

variable "default_root_object" {
  description = "Object to return when a request hits the root URL '/'. Typical values: 'index.html' for websites, leave empty for pure API or media distributions."
  type        = string
  default     = "index.html"
}

variable "price_class" {
  description = <<-EOT
    Which CloudFront edge locations to use — affects cost and latency coverage:
      PriceClass_100 — EU + North America only (cheapest, ~$0.0085/GB)
      PriceClass_200 — adds Middle East, Africa, Asia Pacific
      PriceClass_All — all edge locations worldwide (most expensive)
    For a European startup, PriceClass_100 covers your users at lowest cost.
  EOT
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

variable "default_ttl" {
  description = "Default cache duration in seconds when the origin does not send Cache-Control headers. Default 86400 = 1 day."
  type        = number
  default     = 86400
}

variable "max_ttl" {
  description = "Maximum cache duration in seconds regardless of origin Cache-Control headers. Default 31536000 = 1 year."
  type        = number
  default     = 31536000
}

variable "min_ttl" {
  description = "Minimum cache duration in seconds. Default 0 — allows origin to set Cache-Control: no-cache."
  type        = number
  default     = 0
}

# ---------------------------------------------------------------
# Logging
# ---------------------------------------------------------------

variable "web_acl_arn" {
  description = "ARN of an AWS WAFv2 WebACL to associate with this distribution. The WAF must be in us-east-1 (same requirement as CloudFront certificates). Leave null to disable WAF."
  type        = string
  default     = null
}

variable "enable_logging" {
  description = "Send CloudFront access logs to an S3 bucket. Useful for analytics and security auditing."
  type        = bool
  default     = false
}

variable "logging_bucket" {
  description = "S3 bucket domain name for CloudFront access logs (e.g. my-logs-bucket.s3.amazonaws.com). Required when enable_logging is true."
  type        = string
  default     = null
}

variable "logging_prefix" {
  description = "Key prefix for log files in the logging bucket (e.g. 'cloudfront/'). Helps organise logs when multiple distributions log to the same bucket."
  type        = string
  default     = "cloudfront/"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
