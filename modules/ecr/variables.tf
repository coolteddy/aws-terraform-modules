variable "name" {
  description = "Repository name. Use a path convention to group related images: 'myapp/api', 'myapp/worker', 'myapp/frontend'"
  type        = string
}

variable "image_tag_mutability" {
  description = <<-EOT
    IMMUTABLE (default, recommended): once pushed, a tag cannot be overwritten.
    Prevents accidental overwrite of production images — 'latest' always means
    the same image it did when deployed.
    MUTABLE: tags can be overwritten. Only use for development repositories.
  EOT
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be IMMUTABLE or MUTABLE."
  }
}

variable "scan_on_push" {
  description = "Scan images for CVE vulnerabilities on every push. Free — recommended always on."
  type        = bool
  default     = true
}

variable "encryption_type" {
  description = "Encryption at rest. AES256 uses AWS managed keys (free). KMS uses a customer-managed key for stricter audit trails."
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be AES256 or KMS."
  }
}

variable "kms_key_id" {
  description = "KMS key ARN for encryption. Only used when encryption_type = KMS."
  type        = string
  default     = null
}

variable "lifecycle_keep_tagged_count" {
  description = "Number of tagged images to keep per repository. Older tagged images are deleted automatically. Default 10 — keeps recent releases without accumulating forever."
  type        = number
  default     = 10
}

variable "lifecycle_untagged_days" {
  description = "Days to keep untagged images before deletion. Default 7 — provides a short recovery window before CI artifacts are permanently removed."
  type        = number
  default     = 7
}

variable "org_id" {
  description = <<-EOT
    AWS Organization ID to grant cross-account pull access via aws:PrincipalOrgID condition.
    Any account within this org can pull images — more scalable and secure than listing
    individual account IDs. Default null = no cross-account access.
    Find your org ID: aws organizations describe-organization --query 'Organization.Id'
    Example: "o-abc123xyz"
  EOT
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the repository"
  type        = map(string)
  default     = {}
}
