# Module: rds

Creates a single PostgreSQL RDS instance in private subnets. Designed for per-tenant
hard isolation — each tenant gets their own database instance. Accepts traffic only from
a specified compute security group (EC2 or ASG).

**Known limitation in v1.0.0:** `storage_type` is hardcoded to `gp3`. A variable will be
added in v1.1.0.

## Cost

| Resource | Monthly cost |
|---|---|
| db.t3.micro | ~$15/month — free tier: 750 hrs/month for 12 months |
| db.t3.small | ~$30/month |
| db.t3.medium | ~$60/month |
| Storage gp3 20GB | ~$2.30/month |
| Multi-AZ | Doubles instance cost — off by default |
| Secrets Manager (managed password) | +$0.40/month — optional |
| Automated backups | Free up to DB storage size |

## Password management — two options

| Option | Variable | Cost | State |
|---|---|---|---|
| Caller provides password (default) | `db_password = "..."` | Free | Password in Terraform state (encrypted) |
| RDS manages password | `manage_master_user_password = true` | +$0.40/month | Nothing in state — stored in Secrets Manager |

For POC use the default (free). For production use managed password.

---

## Usage

### 1. Greenhouse demo — EC2 + RDS, plain password (POC)

```hcl
module "vpc" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/vpc?ref=v1.0.0"
  # ...
}

module "ec2" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/ec2?ref=v1.0.0"
  # ...
}

module "rds" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/rds?ref=v1.0.0"

  name                      = "greenhouse"
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.private_subnet_ids
  allowed_security_group_id = module.ec2.security_group_id   # only EC2 can reach DB

  db_name     = "greenhouse"
  db_username = "admin"
  db_password = var.db_password   # pass via tfvars or environment variable

  instance_class      = "db.t3.micro"   # free tier
  skip_final_snapshot = true            # POC — no need for final snapshot

  tags = {
    Env     = "poc"
    Project = "greenhouse-demo"
  }
}

output "db_endpoint" {
  value = module.rds.db_endpoint   # e.g. greenhouse-postgres.abc123.eu-west-2.rds.amazonaws.com:5432
}
```

### 2. Production tenant — managed password, deletion protection

```hcl
module "rds" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/rds?ref=v1.0.0"

  name                      = "tenant-acme"
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.private_subnet_ids
  allowed_security_group_id = module.asg.security_group_id

  db_name     = "tenant_acme"
  db_username = "admin"

  manage_master_user_password = true   # RDS generates + stores in Secrets Manager

  instance_class        = "db.t3.small"
  allocated_storage     = 50
  max_allocated_storage = 200
  backup_retention_days = 14
  deletion_protection   = true
  skip_final_snapshot   = false
  multi_az              = true         # standby in second AZ

  tags = {
    Env    = "prod"
    Tenant = "acme"
  }
}

# App retrieves password at runtime from Secrets Manager using IAM
output "db_secret_arn" {
  value = module.rds.db_secret_arn
}
```

### 3. Reading the managed password from Secrets Manager (app side)

When `manage_master_user_password = true`, the app reads the password at runtime:

```bash
# CLI
aws secretsmanager get-secret-value --secret-id <db_secret_arn> --query SecretString

# Python (boto3)
import boto3, json
client = boto3.client("secretsmanager")
secret = json.loads(client.get_secret_value(SecretId=secret_arn)["SecretString"])
password = secret["password"]
```

The EC2/ECS IAM role needs `secretsmanager:GetSecretValue` permission on the secret ARN.

### 4. Protecting from accidental deletion — production checklist

```hcl
module "rds" {
  # ...
  deletion_protection = true    # AWS blocks deletion until set to false
  skip_final_snapshot = false   # takes a snapshot before any deletion
}
```

To delete a protected instance:
1. Set `deletion_protection = false` and `terraform apply`
2. Then `terraform destroy`

---

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name` | Name prefix for all resources | `string` | — | yes |
| `vpc_id` | VPC ID — from `module.vpc.vpc_id` | `string` | — | yes |
| `subnet_ids` | Private subnet IDs — from `module.vpc.private_subnet_ids`. Min 2 AZs required. | `list(string)` | — | yes |
| `allowed_security_group_id` | Compute SG allowed to reach port 5432 — from `module.ec2.security_group_id` or `module.asg.security_group_id` | `string` | — | yes |
| `db_name` | Initial database name | `string` | — | yes |
| `db_username` | Master username | `string` | — | yes |
| `manage_master_user_password` | RDS manages password in Secrets Manager (+$0.40/month). When false, `db_password` is required. | `bool` | `false` | no |
| `db_password` | Master password — required when `manage_master_user_password = false` | `string` (sensitive) | `null` | no |
| `engine_version` | PostgreSQL version | `string` | `"16"` | no |
| `instance_class` | RDS instance class | `string` | `"db.t3.micro"` | no |
| `allocated_storage` | Initial storage in GB | `number` | `20` | no |
| `max_allocated_storage` | Max storage for autoscaling in GB | `number` | `100` | no |
| `backup_retention_days` | Days to retain backups. `0` disables backups. | `number` | `7` | no |
| `deletion_protection` | AWS-level deletion protection. Set `false` only for dev/POC. | `bool` | `true` | no |
| `skip_final_snapshot` | Skip final snapshot on deletion. Set `true` only for dev/POC. | `bool` | `false` | no |
| `multi_az` | Deploy standby in second AZ — doubles cost | `bool` | `false` | no |
| `tags` | Tags applied to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `db_endpoint` | Connection endpoint `hostname:port` — use in app config |
| `db_host` | Hostname only |
| `db_port` | Port — always 5432 |
| `db_name` | Initial database name |
| `db_username` | Master username |
| `db_secret_arn` | Secrets Manager secret ARN — only when `manage_master_user_password = true`, else `null` |
| `security_group_id` | RDS security group ID |
| `instance_id` | RDS instance identifier |
