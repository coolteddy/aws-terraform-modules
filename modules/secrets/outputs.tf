output "secret_arn" {
  description = "Secret ARN — use in IAM policies to grant GetSecretValue access, and in application config to reference the secret"
  value       = aws_secretsmanager_secret.this.arn
  sensitive   = true
}

output "secret_name" {
  description = "Secret name/path — use with AWS SDK: secretsmanager.GetSecretValue(SecretId=secret_name)"
  value       = aws_secretsmanager_secret.this.name
}

output "secret_version_id" {
  description = "Current secret version ID — use to pin application config to a specific version"
  value       = aws_secretsmanager_secret_version.this.version_id
  sensitive   = true
}
