# Module: ec2

Creates a single EC2 instance with an optional Elastic IP, an IAM instance profile (always created — includes SSM access and optional S3 read),
and an optional second EBS volume for data storage. Designed for demos, bastion hosts,
dev boxes, and single-machine stacks (e.g. Nginx + Grafana + API + LLM on one instance).

Security group rules follow the current Terraform/AWS provider v5 best practice —
each rule is a separate `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule`
resource, not inline blocks.

## Cost

| Resource | Monthly cost |
|---|---|
| t3.xlarge (greenhouse demo) | ~$120/month |
| t3.medium | ~$30/month |
| t3.micro (free tier) | Free for 750 hrs/month, first 12 months |
| EBS gp3 root 20GB | ~$1.76/month |
| EBS gp3 data volume (optional) | ~$0.088/GB/month |
| Elastic IP (attached) | Free |
| Elastic IP (unattached) | $0.005/hr — always attach or release |

Destroy the instance when not actively using to avoid EC2 charges.

## When to use `ec2` vs `asg`

| | `ec2` | `asg` |
|---|---|---|
| Number of instances | Always 1 | Fleet (1–N) |
| Elastic IP (static IP) | Yes | No |
| Run a database | Yes — EBS persists | No — instances are replaced |
| SSH / persistent config | Natural fit | Bad fit |
| Self-healing | No | Yes — ASG replaces failed instances |
| Use case | Demos, dev boxes, single-machine stacks | Production stateless web/app tier |

## Security model

```
Internet
  ├── port 443 → EC2 Security Group → Nginx (handles TLS, routes internally)
  │                                       ├── :3000 Grafana   (internal only)
  │                                       ├── :8000 FastAPI   (internal only)
  │                                       └── :11434 Ollama   (internal only)
  └── port 22  → EC2 Security Group → SSH (restricted to ssh_allowed_cidrs only)

EC2 Instance → RDS Security Group (DB accepts from EC2 SG only)
```

---

## Usage

### 1. Greenhouse demo — Nginx + Grafana + LLM + API + TimescaleDB

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical (Ubuntu)
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

module "vpc" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/vpc?ref=v1.0.0"

  name       = "greenhouse"
  cidr_block = "10.0.0.0/16"

  public_subnets  = { "eu-west-2a" = "10.0.0.0/24" }
  private_subnets = { "eu-west-2a" = "10.0.10.0/24" }

  enable_nat_gateway = false   # no NAT needed — EC2 is in public subnet
}

module "ec2" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/ec2?ref=v1.0.0"

  name          = "greenhouse-demo"
  vpc_id        = module.vpc.vpc_id
  subnet_id     = module.vpc.public_subnet_ids[0]
  ami_id        = data.aws_ami.ubuntu.id
  instance_type = "t3.xlarge"   # needed for Ollama/Mistral 7B — ~$120/month

  ingress_ports     = [443]              # Nginx handles HTTPS
  key_name          = "my-keypair"
  ssh_allowed_cidrs = ["203.0.113.5/32"] # your office IP only

  root_volume_size = 50    # OS + Docker images
  data_volume_size = 100   # TimescaleDB data — kept separate from OS

  s3_read_bucket_arns = [module.s3.bucket_arn]   # read WUR CSV files from S3

  user_data = base64encode(templatefile("${path.module}/scripts/bootstrap.sh.tpl", {
    db_password = var.db_password
    region      = var.region
  }))

  tags = {
    Env     = "poc"
    Project = "greenhouse-demo"
  }
}

output "grafana_url" {
  value = "https://${module.ec2.public_ip}/grafana"
}

output "api_url" {
  value = "https://${module.ec2.public_ip}/api"
}
```

### 2. Simple bastion host (SSH jump box)

```hcl
module "bastion" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/ec2?ref=v1.0.0"

  name          = "bastion"
  vpc_id        = module.vpc.vpc_id
  subnet_id     = module.vpc.public_subnet_ids[0]
  ami_id        = data.aws_ami.al2023.id
  instance_type = "t3.micro"    # free tier eligible

  ingress_ports     = []                  # no web ports — SSH only
  key_name          = "my-keypair"
  ssh_allowed_cidrs = ["203.0.113.5/32"] # your IP only

  create_elastic_ip = true   # static IP so your SSH config never changes
}

output "bastion_ip" {
  value = module.bastion.public_ip
}
```

### 3. Dev box — no public internet exposure

```hcl
module "dev" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/ec2?ref=v1.0.0"

  name          = "dev-box"
  vpc_id        = module.vpc.vpc_id
  subnet_id     = module.vpc.private_subnet_ids[0]  # private subnet
  ami_id        = data.aws_ami.al2023.id
  instance_type = "t3.medium"

  ingress_ports     = []      # no inbound from internet
  create_elastic_ip = false   # private subnet — EIP not useful here
}
```

### 4. Wiring EC2 to RDS — allow DB traffic from instance only

```hcl
module "rds" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/rds?ref=v1.0.0"

  # ...
  allowed_security_group_id = module.ec2.security_group_id   # RDS only accepts from EC2
}
```

### 5. Wiring EC2 to Route 53 — A record pointing to Elastic IP

```hcl
module "route53" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/route53?ref=v1.0.0"

  # ...
  a_records = {
    "demo" = module.ec2.public_ip   # demo.yourdomain.com → Elastic IP
  }
}
```

### 6. Testing a new module version without affecting other resources

```hcl
# Production still on v1.0.0
module "ec2_prod" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/ec2?ref=v1.0.0"
  # ...
}

# Testing v1.1.0 in sandbox before promoting
module "ec2_sandbox" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/ec2?ref=v1.1.0"
  # ...
}
```

After validating, bump production to `?ref=v1.1.0` and run `terraform init -upgrade`.

### Forcing instance replacement (when user_data or AMI changes)

```bash
# Preview
terraform plan -replace="module.ec2.aws_instance.this"

# Apply
terraform apply -replace="module.ec2.aws_instance.this"
```

---

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name` | Name prefix for all resources | `string` | — | yes |
| `vpc_id` | VPC ID — from `module.vpc.vpc_id` | `string` | — | yes |
| `subnet_id` | Single subnet ID — public when using Elastic IP | `string` | — | yes |
| `ami_id` | AMI ID — use `data.aws_ami` in the calling module | `string` | — | yes |
| `instance_type` | EC2 instance type | `string` | — | yes |
| `ingress_ports` | TCP ports to open from the internet (e.g. `[443, 80]`) | `list(number)` | `[443]` | no |
| `allowed_ingress_cidrs` | IPv4 CIDRs allowed to reach the open `ingress_ports` | `list(string)` | `["0.0.0.0/0"]` | no |
| `allowed_ingress_ipv6_cidrs` | IPv6 CIDRs allowed to reach the open `ingress_ports` | `list(string)` | `[]` | no |
| `key_name` | EC2 key pair name for SSH. `null` disables SSH entirely. | `string` | `null` | no |
| `ssh_allowed_cidrs` | IPv4 CIDRs for SSH access — only when `key_name` is set. Use `/32` for single IPs. | `list(string)` | `[]` | no |
| `create_elastic_ip` | Attach a static Elastic IP — required for Route 53 A records | `bool` | `true` | no |
| `s3_read_bucket_arns` | S3 bucket ARNs the instance can read — S3 read policy added to the always-present IAM role | `list(string)` | `[]` | no |
| `root_volume_size` | Root EBS volume size in GB | `number` | `20` | no |
| `root_volume_type` | Root EBS volume type (`gp2`, `gp3`, `io1`, `io2`) | `string` | `"gp3"` | no |
| `data_volume_size` | Optional second EBS volume size in GB. `0` skips creation. | `number` | `0` | no |
| `data_volume_type` | Data volume type | `string` | `"gp3"` | no |
| `data_volume_device_name` | Device name for the data volume | `string` | `"/dev/xvdb"` | no |
| `user_data` | Base64-encoded bootstrap script — use `base64encode(templatefile(...))` | `string` | `null` | no |
| `tags` | Tags applied to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `instance_id` | EC2 instance ID |
| `private_ip` | Private IP — use for internal service references |
| `public_ip` | Elastic IP address, or `null` if `create_elastic_ip` is false — use for Route 53 A records |
| `security_group_id` | Instance security group ID — pass to RDS to allow DB traffic from this instance only |
| `iam_role_arn` | IAM role ARN — always present; includes SSM + any S3 read policies |
| `availability_zone` | AZ where the instance was placed |
| `data_volume_id` | Data EBS volume ID, or `null` if `data_volume_size` is 0 |
