variable "domain_name" {
  description = "Primary domain name for the certificate (e.g. 'coolteddy.io' or '*.coolteddy.io' for wildcard)"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID where DNS validation CNAME records will be written. ACM generates the records; Terraform writes them; ACM confirms ownership automatically."
  type        = string
}

variable "subject_alternative_names" {
  description = <<-EOT
    Additional domain names covered by this certificate.
    Common patterns:
    - Wildcard: ["*.coolteddy.io"]          covers all subdomains
    - Specific:  ["api.coolteddy.io", "app.coolteddy.io"]
    - Both:      ["*.coolteddy.io", "coolteddy.io"]  covers root + all subdomains
  EOT
  type        = list(string)
  default     = []
}

variable "create_cloudfront_cert" {
  description = "Create a second identical certificate in us-east-1 for CloudFront. Set false if you only need the regional certificate for ALB."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
