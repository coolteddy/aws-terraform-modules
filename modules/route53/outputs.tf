output "zone_id" {
  description = "Hosted zone ID — pass to module.acm as hosted_zone_id for DNS certificate validation"
  value       = local.zone_id
}

output "zone_name" {
  description = "Domain name of the hosted zone"
  value       = var.zone_name
}

output "name_servers" {
  description = "Name servers for the hosted zone — only populated when create_zone = true. Register these with your domain registrar to point the domain at Route 53."
  value       = var.create_zone ? aws_route53_zone.this[0].name_servers : null
}
