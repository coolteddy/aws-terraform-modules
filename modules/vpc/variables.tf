variable "name" {
  description = "Name prefix applied to all resources"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "cidr_block" {
  description = "CIDR block for the VPC (e.g. 10.0.0.0/16)"
  type        = string
}

variable "public_subnets" {
  description = "Map of AZ name to CIDR for public subnets (e.g. { \"eu-west-2a\" = \"10.0.0.0/24\" })"
  type        = map(string)
}

variable "private_subnets" {
  description = "Map of AZ name to CIDR for private subnets (e.g. { \"eu-west-2a\" = \"10.0.10.0/24\" })"
  type        = map(string)
}

variable "enable_nat_gateway" {
  description = "Create a NAT Gateway so private subnets can reach the internet. Set false in dev/test to save ~$32/month."
  type        = bool
  default     = true
}
