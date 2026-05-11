output "distribution_id" {
  description = "CloudFront distribution ID — use in CI/CD to invalidate the cache after deploying new files: aws cloudfront create-invalidation --distribution-id <value> --paths '/*'"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN — pass to module.s3 as cloudfront_oac_arn so the S3 bucket policy allows only this distribution to read objects"
  value       = aws_cloudfront_distribution.this.arn
}

output "distribution_domain_name" {
  description = "CloudFront domain name (e.g. d1234abcd.cloudfront.net) — use as Route 53 alias target when no custom domain is configured"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "distribution_hosted_zone_id" {
  description = "CloudFront hosted zone ID — required alongside distribution_domain_name for Route 53 alias records (always Z2FDTNDATAQYW2 for CloudFront)"
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}

output "oac_id" {
  description = "Origin Access Control ID — attached to the S3 origin in this distribution"
  value       = aws_cloudfront_origin_access_control.this.id
}
