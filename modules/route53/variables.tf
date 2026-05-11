variable "create_zone" {
  description = <<-EOT
    Set true to create a new hosted zone.
    Set false (default) to use an existing hosted zone — provide zone_id below.
    WARNING: Never delete an existing hosted zone — it changes NS records and breaks
    DNS globally for 24-48 hours. Import existing zones instead of recreating them.
  EOT
  type        = bool
  default     = false
}

variable "zone_name" {
  description = "Domain name for the hosted zone (e.g. 'coolteddy.io'). Required when create_zone = true. Also used when create_zone = false to label resources."
  type        = string
}

variable "zone_id" {
  description = "ID of an existing Route 53 hosted zone. Required when create_zone = false. Find it in the AWS console under Route 53 → Hosted zones."
  type        = string
  default     = null
}

# ---------------------------------------------------------------
# Alias records — for ALB, NLB, CloudFront
# Each entry maps a subdomain name to an AWS resource.
# Alias records are free and handle dynamic IPs automatically.
# Use these instead of CNAME to avoid DNS query charges and to
# support alias at the zone apex (root domain).
#
# Example:
#   alias_records = {
#     "api"    = { dns_name = module.alb.alb_dns_name,        zone_id = module.alb.alb_zone_id }
#     "videos" = { dns_name = module.cloudfront.distribution_domain_name, zone_id = module.cloudfront.distribution_hosted_zone_id }
#     ""       = { dns_name = module.alb.alb_dns_name,        zone_id = module.alb.alb_zone_id }  # root domain
#   }
# ---------------------------------------------------------------

variable "alias_records" {
  description = "Map of subdomain name to alias target. Use empty string '' for the zone apex (root domain). Each value needs dns_name and zone_id from the target AWS resource (ALB, NLB, or CloudFront)."
  type = map(object({
    dns_name = string
    zone_id  = string
  }))
  default = {}
}

# ---------------------------------------------------------------
# Plain A records — for EC2 Elastic IPs and static addresses
# Example:
#   a_records = {
#     "demo"    = "18.134.56.23"
#     "bastion" = "54.76.100.5"
#   }
# ---------------------------------------------------------------

variable "a_records" {
  description = "Map of subdomain name to IPv4 address. Used for EC2 Elastic IPs and other static addresses."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------
# CNAME records — name to name mapping
# Example:
#   cname_records = {
#     "www"  = "coolteddy.io"
#     "shop" = "myshop.shopify.com"
#   }
# ---------------------------------------------------------------

variable "cname_records" {
  description = "Map of subdomain name to target hostname. Cannot be used at the zone apex — use alias_records for root domain."
  type        = map(string)
  default     = {}
}

variable "default_ttl" {
  description = "TTL in seconds for A and CNAME records. Lower TTL means faster DNS propagation but more Route 53 queries (billed). 300 seconds is a good balance."
  type        = number
  default     = 300
}

variable "tags" {
  description = "Tags applied to the hosted zone (when create_zone = true)"
  type        = map(string)
  default     = {}
}
