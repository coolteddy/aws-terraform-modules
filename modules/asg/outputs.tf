output "asg_name" {
  description = "Name of the Auto Scaling Group — use in scaling policies and CloudWatch alarms"
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.this.arn
}

output "security_group_id" {
  description = "ID of the instance security group — pass to RDS or other backend modules to allow traffic from these instances only"
  value       = aws_security_group.instance.id
}

output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "Latest version number of the Launch Template"
  value       = aws_launch_template.this.latest_version
}
