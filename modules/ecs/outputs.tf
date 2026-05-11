output "cluster_name" {
  description = "ECS cluster name — use in aws ecs commands and CI/CD deployment scripts"
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.this.arn
}

output "service_name" {
  description = "ECS service name — use with cluster_name to target deployments: aws ecs update-service --cluster <cluster> --service <service> --force-new-deployment"
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "Latest task definition ARN — use to check what version is currently deployed"
  value       = aws_ecs_task_definition.this.arn
}

output "task_role_name" {
  description = "Task IAM role name — attach additional policies here when the container needs more AWS permissions"
  value       = aws_iam_role.task.name
}

output "task_execution_role_name" {
  description = "Task execution IAM role name — used by ECS agent to pull images and write logs"
  value       = aws_iam_role.execution.name
}

output "security_group_id" {
  description = "Task security group ID — pass to RDS or other backends to allow traffic from these tasks"
  value       = aws_security_group.tasks.id
}

output "log_group_name" {
  description = "CloudWatch log group name — use to tail container logs: aws logs tail /ecs/<name> --follow"
  value       = aws_cloudwatch_log_group.this.name
}
