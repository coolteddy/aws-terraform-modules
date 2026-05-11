# Module: asg

Creates an Auto Scaling Group with a Launch Template and instance security group. Designed to run behind an ALB or NLB — instances live in private subnets and only accept traffic from the load balancer security group.

Security group rules follow the current Terraform/AWS provider v5 best practice — each rule is a separate `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule` resource, not inline blocks.

## Cost

| Resource | Monthly cost |
|---|---|
| EC2 instances | Depends on instance type — e.g. 2× t3.small ≈ $30/month, 2× t3.medium ≈ $60/month |
| EBS root volumes | ~$0.088/GB/month (gp3) — 2× 20GB ≈ $3.50/month |
| Launch Template | Free |
| Auto Scaling Group | Free |
| Free tier | 750 hours/month t2.micro or t3.micro, 12 months (new accounts only) |

Destroy the ASG when not actively testing to avoid EC2 charges.

## Security model

```
Internet → ALB (public subnet) → Instance SG ← ALB SG reference
                                       ↓
                               EC2 Instances (private subnet)
                                       ↓
                               RDS SG ← Instance SG reference
```

Instances never receive traffic directly from the internet. SSH is disabled by default — enable it only for specific IPs, never `0.0.0.0/0`.

---

## Usage

### 1. Basic — ALB + ASG with Amazon Linux 2023

```hcl
# Fetch the latest Amazon Linux 2023 AMI for your region
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

module "vpc" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/vpc?ref=v1.0.0"
  # ...
}

module "alb" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/alb?ref=v1.0.0"
  # ...
}

module "asg" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/asg?ref=v1.0.0"

  name                  = "sandbox"
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.private_subnet_ids
  target_group_arns     = [module.alb.target_group_arn]
  alb_security_group_id = module.alb.security_group_id
  ami_id                = data.aws_ami.al2023.id
  instance_type         = "t3.small"

  tags = {
    Env     = "sandbox"
    Project = "my-startup"
  }
}
```

### 2. With SSH access restricted to specific IPs

```hcl
module "asg" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/asg?ref=v1.0.0"

  name                  = "sandbox"
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.private_subnet_ids
  target_group_arns     = [module.alb.target_group_arn]
  alb_security_group_id = module.alb.security_group_id
  ami_id                = data.aws_ami.al2023.id
  instance_type         = "t3.small"
  key_name              = "my-keypair"
  ssh_allowed_cidrs     = ["203.0.113.5/32"]   # your office IP only — never 0.0.0.0/0
}
```

### 3. With bootstrap script (user data)

```hcl
module "asg" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/asg?ref=v1.0.0"

  name                  = "sandbox"
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.private_subnet_ids
  target_group_arns     = [module.alb.target_group_arn]
  alb_security_group_id = module.alb.security_group_id
  ami_id                = data.aws_ami.al2023.id
  instance_type         = "t3.medium"

  # templatefile() substitutes variables into your script before base64-encoding
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    db_host = module.rds.db_endpoint
    region  = var.region
  }))
}
```

### 4. Serving both ALB and NLB simultaneously

```hcl
module "asg" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/asg?ref=v1.0.0"

  # ...
  target_group_arns = [
    module.alb.target_group_arn,   # HTTP/HTTPS traffic
    module.nlb.target_group_arn    # TCP traffic (e.g. custom protocol)
  ]
  alb_security_group_id = module.alb.security_group_id
}
```

### 5. Wiring ASG instances to RDS — allow DB traffic from instances only

```hcl
module "rds" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/rds?ref=v1.0.0"

  # ...
  allowed_security_group_id = module.asg.security_group_id   # RDS only accepts connections from ASG instances
}
```

---

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name` | Name prefix for all resources | `string` | — | yes |
| `vpc_id` | VPC ID — from `module.vpc.vpc_id` | `string` | — | yes |
| `subnet_ids` | Private subnet IDs for instances — from `module.vpc.private_subnet_ids` | `list(string)` | — | yes |
| `target_group_arns` | ALB/NLB target group ARNs to register instances into | `list(string)` | — | yes |
| `alb_security_group_id` | ALB security group ID — instances only accept traffic from here | `string` | — | yes |
| `ami_id` | EC2 AMI ID — use a `data.aws_ami` source in the calling module | `string` | — | yes |
| `instance_type` | EC2 instance type | `string` | — | yes |
| `min_size` | Minimum number of instances | `number` | `1` | no |
| `max_size` | Maximum number of instances | `number` | `3` | no |
| `desired_capacity` | Desired number of instances at steady state | `number` | `2` | no |
| `root_volume_size` | Root EBS volume size in GB | `number` | `20` | no |
| `root_volume_type` | Root EBS volume type (`gp2`, `gp3`, `io1`, `io2`) | `string` | `"gp3"` | no |
| `key_name` | EC2 key pair name for SSH. `null` disables SSH entirely. | `string` | `null` | no |
| `ssh_allowed_cidrs` | IPv4 CIDRs allowed to SSH — only applies when `key_name` is set. Use `/32` for single IPs. | `list(string)` | `[]` | no |
| `user_data` | Base64-encoded bootstrap script — use `base64encode(templatefile(...))` | `string` | `null` | no |
| `extra_security_group_ids` | Additional SG IDs to attach to instances (e.g. bastion SG) | `list(string)` | `[]` | no |
| `tags` | Tags applied to ASG and propagated to all instances | `map(string)` | `{}` | no |
| `instance_tags` | Additional tags applied to instances only | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `asg_name` | Auto Scaling Group name — use in scaling policies and CloudWatch alarms |
| `asg_arn` | Auto Scaling Group ARN |
| `security_group_id` | Instance security group ID — pass to RDS or other backends to allow traffic from instances only |
| `launch_template_id` | Launch Template ID |
| `launch_template_latest_version` | Latest Launch Template version number |
