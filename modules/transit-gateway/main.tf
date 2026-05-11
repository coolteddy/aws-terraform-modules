# ---------------------------------------------------------------
# Transit Gateway
# ---------------------------------------------------------------

resource "aws_ec2_transit_gateway" "this" {
  description                     = "${var.name} transit gateway"
  amazon_side_asn                 = var.amazon_side_asn
  dns_support                     = var.enable_dns_support ? "enable" : "disable"
  auto_accept_shared_attachments  = var.auto_accept_shared_attachments
  default_route_table_association = var.default_route_table_association
  default_route_table_propagation = var.default_route_table_propagation

  tags = merge(var.tags, { Name = "${var.name}-tgw" })
}

# ---------------------------------------------------------------
# TGW Default Route Table
# Explicitly named so consuming repos can reference it when adding
# custom static routes (e.g. for network segmentation scenarios)
# ---------------------------------------------------------------

resource "aws_ec2_transit_gateway_route_table" "default" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = merge(var.tags, { Name = "${var.name}-tgw-default-rt" })
}

# ---------------------------------------------------------------
# RAM — Resource Access Manager
# Only created when ram_share_principals is non-empty.
# One aws_ram_principal_association per principal in the list.
#
# Security: accounts not in ram_share_principals cannot see
# this TGW at all — they cannot attach even if auto_accept is on.
# ---------------------------------------------------------------

resource "aws_ram_resource_share" "this" {
  count = length(var.ram_share_principals) > 0 ? 1 : 0

  name                      = "${var.name}-tgw-share"
  allow_external_principals = var.ram_allow_external_principals
  tags                      = merge(var.tags, { Name = "${var.name}-tgw-share" })
}

resource "aws_ram_resource_association" "tgw" {
  count = length(var.ram_share_principals) > 0 ? 1 : 0

  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.this[0].arn
}

resource "aws_ram_principal_association" "principals" {
  for_each = toset(var.ram_share_principals)

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.this[0].arn

  # Ensure the share exists before associating principals
  depends_on = [aws_ram_resource_association.tgw]
}
