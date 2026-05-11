output "db_endpoint" {
  description = "Connection endpoint for the database (hostname:port) — use in application config"
  value       = aws_db_instance.this.endpoint
}

output "db_host" {
  description = "Hostname only (without port) — useful when host and port are configured separately"
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "Database port — always 5432 for PostgreSQL"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Name of the initial database"
  value       = aws_db_instance.this.db_name
}

output "db_username" {
  description = "Master username"
  value       = aws_db_instance.this.username
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the master password. Only populated when manage_master_user_password is true — null otherwise."
  value       = var.manage_master_user_password ? aws_db_instance.this.master_user_secret[0].secret_arn : null
  sensitive   = true
}

output "security_group_id" {
  description = "ID of the RDS security group — not typically needed by callers but useful for adding extra ingress rules"
  value       = aws_security_group.rds.id
}

output "instance_id" {
  description = "RDS instance identifier — use in CLI commands and monitoring tools"
  value       = aws_db_instance.this.identifier
}
