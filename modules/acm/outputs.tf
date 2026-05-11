output "regional_certificate_arn" {
  description = "ARN of the regional certificate (your workload region) — pass to module.alb as certificate_arn"
  value       = aws_acm_certificate_validation.regional.certificate_arn
}

output "cloudfront_certificate_arn" {
  description = "ARN of the us-east-1 certificate for CloudFront — pass to module.cloudfront as certificate_arn. Null if create_cloudfront_cert is false."
  value       = var.create_cloudfront_cert ? aws_acm_certificate_validation.cloudfront[0].certificate_arn : null
}
