variable "name" {
  description = "Name prefix applied to all resources"
  type        = string
}

# ---------------------------------------------------------------
# Transit Gateway configuration
# ---------------------------------------------------------------

variable "amazon_side_asn" {
  description = "BGP ASN for the TGW. Only relevant for Direct Connect or Site-to-Site VPN. For VPC-to-VPC routing this value is never visible. Must be in private ASN range 64512–65534."
  type        = number
  default     = 64512
}

variable "enable_dns_support" {
  description = "Allow resources in attached VPCs to resolve each other's private DNS names across the TGW. Recommended true."
  type        = bool
  default     = true
}

variable "auto_accept_shared_attachments" {
  description = "Auto-accept VPC attachment requests from accounts that can see this TGW. Safe to enable when ram_share_principals is a specific list of trusted accounts — only those accounts can see the TGW to begin with."
  type        = string
  default     = "enable"

  validation {
    condition     = contains(["enable", "disable"], var.auto_accept_shared_attachments)
    error_message = "auto_accept_shared_attachments must be 'enable' or 'disable'."
  }
}

# ---------------------------------------------------------------
# Route table behaviour
# With both enabled, routing is fully automatic:
#   1. New attachment associates with the default route table
#   2. Attachment's VPC CIDR propagates into the route table
#   3. All other attachments can route to that CIDR immediately
# No manual aws_ec2_transit_gateway_route resources needed.
# ---------------------------------------------------------------

variable "default_route_table_association" {
  description = "Automatically associate new VPC attachments with the default TGW route table."
  type        = string
  default     = "enable"

  validation {
    condition     = contains(["enable", "disable"], var.default_route_table_association)
    error_message = "default_route_table_association must be 'enable' or 'disable'."
  }
}

variable "default_route_table_propagation" {
  description = "Automatically propagate each attachment's VPC CIDR into the default route table. When enabled, routes appear automatically when VPCs attach — no static route resources needed."
  type        = string
  default     = "enable"

  validation {
    condition     = contains(["enable", "disable"], var.default_route_table_propagation)
    error_message = "default_route_table_propagation must be 'enable' or 'disable'."
  }
}

# ---------------------------------------------------------------
# RAM — Resource Access Manager
# Shares the TGW so other accounts can create VPC attachments.
#
# Two approaches — see README for migration path:
#
# Approach 1 (start here — tightest security):
#   List specific account IDs — only those accounts can see the TGW.
#   No aws-org-infra change needed.
#   ram_share_principals = ["111111111111", "333333333333"]
#
# Approach 2 (when you have many accounts):
#   Use the org ARN — all current and future org accounts can see the TGW.
#   Prerequisite: add aws_ram_sharing_with_organization to aws-org-infra first.
#   ram_share_principals = ["arn:aws:organizations::MGMT_ID:organization/o-XXXXX"]
#
# Default [] = no sharing — TGW stays private to the creating account.
# ---------------------------------------------------------------

variable "ram_share_principals" {
  description = "Account IDs or org/OU ARNs to share the TGW with. Default [] keeps TGW private. See README for security guidance and migration path between approaches."
  type        = list(string)
  default     = []
}

variable "ram_allow_external_principals" {
  description = "Allow sharing with accounts outside the AWS Organization. Keep false — only change if you have a specific cross-org use case."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
