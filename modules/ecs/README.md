# Module: ecs

Creates an ECS Fargate cluster, service, and task definition. Containers run in private subnets,
receive traffic from an ALB, and pull images from ECR. Secrets are injected at task start from
Secrets Manager — never hardcoded or visible in logs.

## Cost

| Resource | Monthly cost (256 CPU / 512MB) |
|---|---|
| Fargate task × 1 | ~$11/month |
| Fargate task × 2 (default) | ~$22/month |
| CloudWatch logs | ~$0.50/GB ingested |
| ECS cluster | Free |

Fargate pricing: $0.04048/vCPU/hour + $0.004445/GB/hour

## Fargate CPU and memory — valid combinations

| CPU | Valid memory values |
|---|---|
| 256 (0.25 vCPU) | 512, 1024, 2048 MB |
| 512 (0.5 vCPU) | 1024–4096 MB |
| 1024 (1 vCPU) | 2048–8192 MB |
| 2048 (2 vCPU) | 4096–16384 MB |
| 4096 (4 vCPU) | 8192–30720 MB |

## Two IAM roles — execution vs task

```
ECS Agent (AWS managed)
  └── Execution Role — pulls image from ECR, writes logs, reads secrets before start

Your container (your code)
  └── Task Role — calls AWS services from inside the app (S3, DynamoDB, SQS etc.)
```

---

## Usage

### 1. Basic API service — ALB + ECS + ECR + Secrets

```hcl
module "vpc" { ... }
module "alb" {
  source      = "...//modules/alb?ref=v1.0.0"
  target_type = "ip"   # ECS Fargate tasks register by IP
  target_port = 8080
  # ...
}
module "ecr" { ... }
module "secrets" {
  source        = "...//modules/secrets?ref=v1.0.0"
  name          = "/prod/myapp/db-password"
  secret_string = var.db_password
}

module "ecs" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/ecs?ref=v1.0.0"

  name                  = "myapp-api"
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.private_subnet_ids
  alb_security_group_id = module.alb.security_group_id
  target_group_arn      = module.alb.target_group_arn

  container_image = "${module.ecr.repository_url}:v1.2.3"
  container_port  = 8080
  desired_count   = 2

  task_cpu    = 256
  task_memory = 512

  environment_variables = {
    APP_ENV  = "production"
    LOG_LEVEL = "info"
  }

  secret_arns = {
    DB_PASSWORD = module.secrets.secret_arn   # injected as env var, never visible in logs
  }

  ecr_repository_arns = [module.ecr.repository_arn]

  tags = { Env = "prod", Service = "api" }
}
```

### 2. Deploying a new image version (CI/CD pattern)

Terraform manages infrastructure. Image updates go through CI/CD without terraform apply:

```bash
# CI/CD pipeline — after docker push
aws ecs update-service \
  --cluster $(terraform output -raw cluster_name) \
  --service  $(terraform output -raw service_name) \
  --force-new-deployment \
  --region eu-west-2

# Wait for deployment to complete
aws ecs wait services-stable \
  --cluster $(terraform output -raw cluster_name) \
  --services $(terraform output -raw service_name)
```

`ignore_changes = [task_definition]` in the service resource means Terraform does not
revert CI/CD image updates on the next `terraform apply`.

### 3. Tailing logs

```bash
aws logs tail $(terraform output -raw log_group_name) --follow --region eu-west-2
```

### 4. Wiring ECS tasks to RDS — allow DB traffic from tasks only

```hcl
module "rds" {
  source = "...//modules/rds?ref=v1.0.0"
  # ...
  allowed_security_group_id = module.ecs.security_group_id   # RDS accepts from ECS tasks only
}
```

### 5. Adding AWS permissions to the running container

```hcl
# Create a policy
resource "aws_iam_policy" "s3_read" {
  name   = "myapp-s3-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [module.s3.bucket_arn, "${module.s3.bucket_arn}/*"]
    }]
  })
}

# Pass the ARN to the ECS module
module "ecs" {
  # ...
  task_role_policy_arns = [aws_iam_policy.s3_read.arn]
}
```

---

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name` | Name prefix for all resources | `string` | — | yes |
| `vpc_id` | VPC ID | `string` | — | yes |
| `subnet_ids` | Private subnet IDs for Fargate tasks | `list(string)` | — | yes |
| `alb_security_group_id` | ALB SG ID — tasks only accept traffic from here | `string` | — | yes |
| `target_group_arn` | ALB target group ARN | `string` | — | yes |
| `container_image` | Full image URI with tag — from `module.ecr.repository_url` | `string` | — | yes |
| `container_port` | Port the container listens on | `number` | — | yes |
| `task_cpu` | Fargate CPU units (256/512/1024/2048/4096) | `number` | `256` | no |
| `task_memory` | Fargate memory in MB — must match cpu | `number` | `512` | no |
| `desired_count` | Number of running task instances | `number` | `2` | no |
| `environment_variables` | Plain env vars — never put secrets here | `map(string)` | `{}` | no |
| `secret_arns` | Secrets Manager ARNs injected as env vars | `map(string)` | `{}` | no |
| `ecr_repository_arns` | ECR repo ARNs the execution role can pull from | `list(string)` | `[]` | no |
| `task_role_policy_arns` | Additional policies for the running container | `list(string)` | `[]` | no |
| `log_retention_days` | CloudWatch log retention in days (`0` = never expire) | `number` | `30` | no |
| `tags` | Tags applied to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `cluster_name` | ECS cluster name — use in `aws ecs` CLI commands |
| `cluster_arn` | Cluster ARN |
| `service_name` | ECS service name — use with `aws ecs update-service` for deployments |
| `task_definition_arn` | Current task definition ARN |
| `task_role_name` | Task role name — attach additional policies for app AWS access |
| `task_execution_role_name` | Execution role name — used by ECS agent |
| `security_group_id` | Task SG ID — pass to RDS to allow DB traffic from tasks |
| `log_group_name` | CloudWatch log group — use with `aws logs tail` |
