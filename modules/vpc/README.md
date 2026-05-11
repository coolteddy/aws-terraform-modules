# Module: vpc

Creates a VPC with public and private subnets across any number of Availability Zones, an Internet Gateway, and an optional NAT Gateway.

## Cost

| Resource | Monthly cost |
|---|---|
| VPC, subnets, route tables, IGW | Free |
| NAT Gateway (when enabled) | ~$32/month + $0.045/GB — **charged even when idle** |

Set `enable_nat_gateway = false` in dev/test environments to avoid the NAT charge.

## Usage

```hcl
module "vpc" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/vpc?ref=v1.0.0"

  name       = "sandbox"
  cidr_block = "10.0.0.0/16"

  public_subnets = {
    "eu-west-2a" = "10.0.0.0/24"
    "eu-west-2b" = "10.0.1.0/24"
  }

  private_subnets = {
    "eu-west-2a" = "10.0.10.0/24"
    "eu-west-2b" = "10.0.11.0/24"
  }

  enable_nat_gateway = true

  tags = {
    Env     = "sandbox"
    Project = "my-startup"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name` | Name prefix applied to all resources | `string` | — | yes |
| `cidr_block` | CIDR block for the VPC | `string` | — | yes |
| `public_subnets` | Map of AZ → CIDR for public subnets | `map(string)` | — | yes |
| `private_subnets` | Map of AZ → CIDR for private subnets | `map(string)` | — | yes |
| `enable_nat_gateway` | Create a NAT Gateway for private subnet internet access | `bool` | `true` | no |
| `tags` | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `vpc_id` | ID of the VPC |
| `vpc_cidr_block` | CIDR block of the VPC |
| `public_subnet_ids` | List of public subnet IDs |
| `private_subnet_ids` | List of private subnet IDs |
| `igw_id` | ID of the Internet Gateway |
| `nat_gateway_id` | ID of the NAT Gateway, or `null` if disabled |
| `public_route_table_id` | ID of the public route table |
| `private_route_table_id` | ID of the private route table |
