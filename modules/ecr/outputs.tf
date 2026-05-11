output "repository_url" {
  description = "Full ECR repository URL — use in docker push/pull and ECS task definition image field. Format: ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/REPO_NAME"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "Repository ARN — use in IAM policies granting ecr:GetDownloadUrlForLayer etc."
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Repository name — use in lifecycle policy and additional resource policy references"
  value       = aws_ecr_repository.this.name
}

output "registry_id" {
  description = "Registry ID (AWS account ID of the registry) — used in docker login command"
  value       = aws_ecr_repository.this.registry_id
  sensitive   = true
}
