variable "name" {
  description = <<-EOT
    S3 bucket name. Must be globally unique across all AWS accounts (this rule has not changed).
    Two naming approaches:
    1. Traditional: "coolteddy-videos-prod" — unique by convention, name can be claimed by
       another account if you delete the bucket.
    2. Account-scoped (AWS recommended): "{prefix}-{account-id}-{region}-an" — uniqueness is
       guaranteed by design since your account ID is embedded in the name.
       Example: "coolteddy-123456789012-eu-west-2-an"
  EOT
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_versioning" {
  description = "Keep previous versions of objects on overwrite or delete. Protects against accidental data loss. Note: each version counts as stored data — increases cost."
  type        = bool
  default     = false
}

variable "lifecycle_rules" {
  description = <<-EOT
    List of lifecycle rules to automatically transition or expire objects.
    Each rule supports:
      id         — unique rule name
      prefix     — object key prefix to apply the rule to (empty string = all objects)
      transition_days        — days before moving to STANDARD_IA (min 30)
      glacier_days           — days before moving to GLACIER (min 90)
      expiration_days        — days before permanently deleting objects (0 = disabled)
      noncurrent_expiry_days — days before deleting old versions (only when versioning enabled)
    Example:
      lifecycle_rules = [{
        id                   = "archive-videos"
        prefix               = "videos/"
        transition_days      = 30
        glacier_days         = 90
        expiration_days      = 365
        noncurrent_expiry_days = 30
      }]
  EOT
  type = list(object({
    id                     = string
    prefix                 = string
    transition_days        = optional(number, 0)
    glacier_days           = optional(number, 0)
    expiration_days        = optional(number, 0)
    noncurrent_expiry_days = optional(number, 0)
  }))
  default = []
}

variable "cors_rules" {
  description = <<-EOT
    CORS rules for browser-based direct access to S3 objects.
    Only needed when a browser fetches objects directly from S3 — not needed when
    CloudFront or EC2 accesses S3 server-side.
    Example:
      cors_rules = [{
        allowed_origins = ["https://app.coolteddy.io"]
        allowed_methods = ["GET", "HEAD"]
        allowed_headers = ["*"]
        max_age_seconds = 3600
      }]
  EOT
  type = list(object({
    allowed_origins = list(string)
    allowed_methods = list(string)
    allowed_headers = list(string)
    expose_headers  = optional(list(string), [])
    max_age_seconds = optional(number, 3600)
  }))
  default = []
}

variable "cloudfront_oac_arn" {
  description = "ARN of a CloudFront distribution to allow read access via Origin Access Control (OAC). When provided, a bucket policy is created allowing that CloudFront distribution to call s3:GetObject. OAC is the current AWS recommendation — do not use OAI (deprecated)."
  type        = string
  default     = null
}

variable "additional_policy_json" {
  description = "Optional additional bucket policy statements as a JSON string. Merged with any OAC policy. Use for custom cross-account access or service-specific permissions."
  type        = string
  default     = null
}
