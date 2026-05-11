output "nlb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.this.arn
}

output "nlb_dns_name" {
  description = "DNS name of the NLB — use as Route 53 alias target"
  value       = aws_lb.this.dns_name
}

output "nlb_zone_id" {
  description = "Hosted zone ID of the NLB — required alongside nlb_dns_name for Route 53 alias records"
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "ARN of the target group — pass to ASG, ECS, or EKS to register backends"
  value       = aws_lb_target_group.this.arn
}

output "security_group_id" {
  description = "NLB security group ID — pass to backend modules to restrict inbound to NLB only"
  value       = aws_security_group.nlb.id
}

output "listener_arn" {
  description = "ARN of the active listener (plain or TLS)"
  value       = var.enable_tls ? aws_lb_listener.tls[0].arn : aws_lb_listener.plain[0].arn
}

output "tls_listener_arn" {
  description = "ARN of the TLS listener, or null if enable_tls is false"
  value       = var.enable_tls ? aws_lb_listener.tls[0].arn : null
}
