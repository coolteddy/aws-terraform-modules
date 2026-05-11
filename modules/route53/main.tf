# ---------------------------------------------------------------
# Hosted Zone — only created when create_zone = true
# For existing zones, provide zone_id variable instead.
# NEVER delete an existing hosted zone — NS record changes break
# DNS globally for 24-48 hours.
# ---------------------------------------------------------------

resource "aws_route53_zone" "this" {
  count = var.create_zone ? 1 : 0

  name = var.zone_name
  tags = merge(var.tags, { Name = var.zone_name })
}

# Look up existing zone by name when zone_id is not provided and create_zone is false.
# Use this when you know the domain name but not the zone ID — Terraform resolves it at plan time.
data "aws_route53_zone" "existing" {
  count = !var.create_zone && var.zone_id == null ? 1 : 0

  name         = var.zone_name
  private_zone = false
}

# Resolve zone ID from: created zone → provided ID → data source lookup
locals {
  zone_id = (
    var.create_zone ? aws_route53_zone.this[0].zone_id :
    var.zone_id != null ? var.zone_id :
    data.aws_route53_zone.existing[0].zone_id
  )
}

# ---------------------------------------------------------------
# Alias records — ALB, NLB, CloudFront
# Free — AWS updates IPs automatically when the target scales.
# Works at the zone apex (root domain) unlike CNAME.
# ---------------------------------------------------------------

resource "aws_route53_record" "alias" {
  for_each = var.alias_records

  zone_id = local.zone_id
  name    = each.key # "" = zone apex, "api" = api.coolteddy.io
  type    = "A"

  alias {
    name                   = each.value.dns_name
    zone_id                = each.value.zone_id
    evaluate_target_health = true
  }
}

# ---------------------------------------------------------------
# Plain A records — EC2 Elastic IPs and static addresses
# ---------------------------------------------------------------

resource "aws_route53_record" "a" {
  for_each = var.a_records

  zone_id = local.zone_id
  name    = each.key
  type    = "A"
  ttl     = var.default_ttl
  records = [each.value]
}

# ---------------------------------------------------------------
# CNAME records — name to name mapping
# ---------------------------------------------------------------

resource "aws_route53_record" "cname" {
  for_each = var.cname_records

  zone_id = local.zone_id
  name    = each.key
  type    = "CNAME"
  ttl     = var.default_ttl
  records = [each.value]
}
