variable "name" {
  description = "Name prefix applied to all resources"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC — from module.vpc.vpc_id"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the DB subnet group. AWS requires at least 2 subnets in different AZs even for single-AZ instances — from module.vpc.private_subnet_ids"
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Security group ID of the EC2 or ASG instances that need DB access. Only this SG can reach port 5432 — from module.ec2.security_group_id or module.asg.security_group_id"
  type        = string
}

variable "db_name" {
  description = "Name of the initial database to create (e.g. 'greenhouse', 'tenant_abc')"
  type        = string
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
}

variable "manage_master_user_password" {
  description = <<-EOT
    When true: RDS generates a strong password, stores it in AWS Secrets Manager,
    and rotates it automatically. Most secure — nothing in Terraform state.
    Cost: +$0.40/month for the Secrets Manager secret.

    When false (default): caller must provide db_password. Password is stored
    in Terraform state (encrypted). Suitable for POC and dev environments.
  EOT
  type        = bool
  default     = false
}

variable "db_password" {
  description = "Master password for the database. Required when manage_master_user_password is false. Ignored when manage_master_user_password is true."
  type        = string
  sensitive   = true
  default     = null
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "RDS instance class. db.t3.micro is free-tier eligible for 750 hrs/month in the first 12 months."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage in GB for autoscaling. RDS grows the disk automatically when it approaches capacity. Set equal to allocated_storage to disable autoscaling."
  type        = number
  default     = 100
}

variable "backup_retention_days" {
  description = "Days to retain automated backups. Set 0 to disable backups (dev/POC only — not recommended for data you care about)."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the database. When true, terraform destroy will fail until this is set to false and re-applied. Set false only for dev/POC environments."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "When false (default), RDS takes a final snapshot before deletion — protects against accidental data loss. Set true only in dev/POC environments where data loss is acceptable."
  type        = bool
  default     = false
}

variable "multi_az" {
  description = "Deploy a standby instance in a second AZ for automatic failover. Doubles the cost. Recommended for production, not needed for POC."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
