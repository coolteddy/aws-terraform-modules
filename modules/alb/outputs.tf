output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB — use this as the target for Route 53 alias records"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB — required alongside alb_dns_name for Route 53 alias records"
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "ARN of the target group — pass this to ASG, ECS, or EKS modules to register backends"
  value       = aws_lb_target_group.this.arn
}

output "security_group_id" {
  description = "ID of the ALB security group — pass to ASG/ECS/EKS to allow inbound traffic from this ALB only"
  value       = aws_security_group.alb.id
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener — use to attach additional listener rules (e.g. path-based routing)"
  value       = var.enable_https ? aws_lb_listener.http_redirect[0].arn : aws_lb_listener.http_forward[0].arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener, or null if enable_https is false"
  value       = var.enable_https ? aws_lb_listener.https[0].arn : null
}
