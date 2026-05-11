output "tgw_id" {
  description = "Transit Gateway ID — pass to spoke accounts to create VPC attachments: aws_ec2_transit_gateway_vpc_attachment { transit_gateway_id = module.transit_gateway.tgw_id }"
  value       = aws_ec2_transit_gateway.this.id
}

output "tgw_arn" {
  description = "Transit Gateway ARN — used in IAM policies and RAM resource associations"
  value       = aws_ec2_transit_gateway.this.arn
}

output "default_route_table_id" {
  description = "ID of the TGW default route table — use in consuming repos to add propagations or custom static routes for network segmentation"
  value       = aws_ec2_transit_gateway_route_table.default.id
}

output "ram_share_arn" {
  description = "ARN of the RAM resource share — null if ram_share_principals is empty"
  value       = length(var.ram_share_principals) > 0 ? aws_ram_resource_share.this[0].arn : null
}

# ---------------------------------------------------------------
# Alias outputs — standardised names for cross-module references
# ---------------------------------------------------------------

output "transit_gateway_id" {
  description = "Alias for tgw_id — standardised output name"
  value       = aws_ec2_transit_gateway.this.id
}

output "transit_gateway_arn" {
  description = "Alias for tgw_arn — standardised output name"
  value       = aws_ec2_transit_gateway.this.arn
}

output "route_table_id" {
  description = "Alias for default_route_table_id — standardised output name"
  value       = aws_ec2_transit_gateway_route_table.default.id
}
