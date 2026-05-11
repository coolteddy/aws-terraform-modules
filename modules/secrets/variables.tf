variable "name" {
  description = <<-EOT
    Secret name/path. Use a path convention to organise secrets by environment and tenant:
      /prod/tenant-acme/db-password
      /prod/tenant-acme/stripe-api-key
      /shared/sendgrid-api-key
    Secrets Manager charges $0.40/secret/month — one secret per sensitive value.
  EOT
  type        = string
}

variable "description" {
  description = "Human-readable description of what this secret contains and who uses it"
  type        = string
  default     = ""
}

variable "secret_string" {
  description = <<-EOT
    The secret value to store. Must be a string — use jsonencode() for structured values.
    Examples:
      Plain string:     "my-api-key-abc123"
      JSON structured:  jsonencode({ username = "admin", password = "secret" })
    Marked sensitive — never printed in terraform plan or apply output.
  EOT
  type        = string
  sensitive   = true
}

variable "kms_key_id" {
  description = "KMS key ARN for encrypting the secret. Leave null to use the AWS managed key (free). Provide a CMK ARN for stricter key management and audit trails."
  type        = string
  default     = null
}

variable "recovery_window_in_days" {
  description = <<-EOT
    Days to retain the secret after deletion before permanent removal.
    Default 7 — gives a recovery window if deleted accidentally.
    Set 0 for immediate deletion — useful in dev/POC so you can recreate
    the secret with the same name immediately without waiting.
    AWS minimum is 7 days unless you set 0 (force delete).
  EOT
  type        = number
  default     = 7

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "recovery_window_in_days must be 0 (immediate) or between 7 and 30."
  }
}

variable "cross_account_reader_arns" {
  description = <<-EOT
    IAM role ARNs from OTHER accounts allowed to call GetSecretValue on this secret.
    Used for the central secrets pattern — shared-services stores a secret that sandbox
    or management accounts need to read.
    Default [] = no cross-account access, secret is private to the creating account.
    Example: ["arn:aws:iam::333333333333:role/sandbox-app-role"]
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
