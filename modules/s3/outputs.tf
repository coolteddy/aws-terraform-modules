output "bucket_name" {
  description = "Name of the S3 bucket — use in application config and AWS CLI commands"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket — pass to ec2 module's s3_read_bucket_arns or any IAM policy that needs S3 access"
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name for the bucket (e.g. my-bucket.s3.eu-west-2.amazonaws.com) — use this as the CloudFront origin domain, not the global endpoint, to avoid redirect issues with new buckets"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_id" {
  description = "Bucket ID (same as bucket name) — used when other Terraform resources reference this bucket"
  value       = aws_s3_bucket.this.id
}
