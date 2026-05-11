# ---------------------------------------------------------------
# Regional Certificate — for ALB in your workload region
# Uses the default aws provider (e.g. eu-west-2)
# ---------------------------------------------------------------

resource "aws_acm_certificate" "regional" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  lifecycle {
    # Create the new cert before destroying the old one — prevents ALB downtime
    # during certificate renewal or replacement
    create_before_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.domain_name}-regional" })
}

# Write ACM's validation CNAME records into Route 53
# One record per domain name on the certificate (primary + SANs)
resource "aws_route53_record" "regional_validation" {
  for_each = {
    for dvo in aws_acm_certificate.regional.domain_validation_options :
    dvo.domain_name => dvo
  }

  zone_id = var.hosted_zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60

  allow_overwrite = true
}

# Wait until ACM confirms the certificate is ISSUED before Terraform continues
# This is a synchronisation resource — not a real AWS resource
resource "aws_acm_certificate_validation" "regional" {
  certificate_arn         = aws_acm_certificate.regional.arn
  validation_record_fqdns = [for record in aws_route53_record.regional_validation : record.fqdn]
}

# ---------------------------------------------------------------
# CloudFront Certificate — must be in us-east-1
# Only created when create_cloudfront_cert = true
# Uses the aws.us_east_1 provider alias passed in by the caller
# ---------------------------------------------------------------

resource "aws_acm_certificate" "cloudfront" {
  count    = var.create_cloudfront_cert ? 1 : 0
  provider = aws.us_east_1

  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.domain_name}-cloudfront" })
}

# Validation records for the CloudFront cert
# allow_overwrite = true — the same CNAME records already exist from the regional cert
# ACM reuses the same validation records for the same domain, so overwriting is safe
resource "aws_route53_record" "cloudfront_validation" {
  for_each = var.create_cloudfront_cert ? {
    for dvo in aws_acm_certificate.cloudfront[0].domain_validation_options :
    dvo.domain_name => dvo
  } : {}

  zone_id = var.hosted_zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cloudfront" {
  count    = var.create_cloudfront_cert ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.cloudfront[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cloudfront_validation : record.fqdn]
}
