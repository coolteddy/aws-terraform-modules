# Module: ecr

Creates a private ECR repository in the shared-services account with lifecycle policies
and optional cross-account pull access for tenant accounts.

Run this module in **shared-services** only. Tenant accounts (sandbox, production) pull
images from here but never push.

## Cost

| Resource | Monthly cost |
|---|---|
| Storage | $0.10/GB/month |
| Data transfer (same region) | Free |
| Data transfer (cross-region) | $0.09/GB |
| Image scanning | Free (basic scanning) |

Storage costs are controlled by the lifecycle policy — without it, every push accumulates forever.

---

## Image tag immutability — why it matters

```
IMMUTABLE (default):
  docker push myapp/api:v1.2.3   → succeeds first time
  docker push myapp/api:v1.2.3   → ERROR: tag already exists, cannot overwrite
  Guarantees: what you deployed yesterday is still what v1.2.3 means today

MUTABLE:
  docker push myapp/api:latest   → overwrites previous latest
  Risk: rolling back to a previous deploy may get a different image than expected
```

Use `IMMUTABLE` for production repositories. Use `MUTABLE` only for development scratch repos
where you frequently rebuild the same tag during iteration.

---

## Usage

### 1. Basic repository — shared-services account, cross-account pull

```hcl
# In aws-shared-services-infra
module "ecr_api" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/ecr?ref=v1.0.0"

  name = "myapp/api"

  org_id = "o-abc123xyz"   # your AWS Organization ID — all org accounts can pull

  tags = { Project = "myapp", Component = "api" }
}

output "api_image_url" {
  value = module.ecr_api.repository_url
  # e.g. 123456789012.dkr.ecr.eu-west-2.amazonaws.com/myapp/api
}
```

### 2. Pushing an image from CI/CD

```bash
# Authenticate Docker to ECR (run in CI/CD pipeline)
aws ecr get-login-password --region eu-west-2 --profile shared-services-ci | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.eu-west-2.amazonaws.com

# Build and push
docker build -t myapp/api:v1.2.3 .
docker tag myapp/api:v1.2.3 123456789012.dkr.ecr.eu-west-2.amazonaws.com/myapp/api:v1.2.3
docker push 123456789012.dkr.ecr.eu-west-2.amazonaws.com/myapp/api:v1.2.3
```

The CI/CD role (GitHub Actions) needs:
```hcl
resource "aws_iam_role_policy" "ecr_push" {
  name = "ecr-push"
  role = "github-actions-role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:BatchCheckLayerAvailability",
      ]
      Resource = module.ecr_api.repository_arn
    },
    {
      Effect   = "Allow"
      Action   = "ecr:GetAuthorizationToken"
      Resource = "*"   # GetAuthorizationToken operates at the registry level, not repo
    }]
  })
}
```

### 3. Pulling from a tenant account (other side of the double-lock)

The ECR repo policy (created by this module) allows the account to pull.
The ECS task role in the tenant account also needs permissions:

```hcl
# In aws-sandbox-infra — the ECS task execution role needs pull permissions
resource "aws_iam_role_policy" "ecr_pull" {
  name = "ecr-pull-shared-services"
  role = module.ecs.task_execution_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
        ]
        Resource = "arn:aws:ecr:eu-west-2:SHARED_SERVICES_ACCOUNT:repository/myapp/*"
      },
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      }
    ]
  })
}
```

### 4. Multiple repositories for a service

```hcl
locals {
  repositories = ["myapp/api", "myapp/worker", "myapp/frontend"]
}

module "ecr" {
  source   = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/ecr?ref=v1.0.0"
  for_each = toset(local.repositories)

  name             = each.value
  org_id = "o-abc123xyz"

  tags = { Project = "myapp" }
}

output "repository_urls" {
  value = { for name, repo in module.ecr : name => repo.repository_url }
}
```

---

## Lifecycle policy explained

```
Rule 1 (priority 1 — checked first):
  Delete UNTAGGED images older than 7 days
  → CI build artifacts that were never tagged as a release are cleaned up quickly

Rule 2 (priority 2):
  Keep only the last 10 TAGGED images
  → Oldest tagged images are deleted when you push the 11th
  → Adjust lifecycle_keep_tagged_count for your release cadence
```

---

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name` | Repository name (e.g. `myapp/api`) | `string` | — | yes |
| `image_tag_mutability` | `IMMUTABLE` (recommended) or `MUTABLE` | `string` | `"IMMUTABLE"` | no |
| `scan_on_push` | Scan for CVEs on every push — free, always on recommended | `bool` | `true` | no |
| `encryption_type` | `AES256` (free) or `KMS` | `string` | `"AES256"` | no |
| `kms_key_id` | KMS key ARN — only when `encryption_type = KMS` | `string` | `null` | no |
| `lifecycle_keep_tagged_count` | Number of tagged images to retain | `number` | `10` | no |
| `lifecycle_untagged_days` | Days before untagged images are deleted | `number` | `7` | no |
| `org_id` | AWS Organization ID for cross-account pull via `aws:PrincipalOrgID`. `null` = no cross-account access. | `string` | `null` | no |
| `tags` | Tags applied to the repository | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `repository_url` | Full image URL — use in `docker push` and ECS task definitions |
| `repository_arn` | Repository ARN — use in IAM policies |
| `repository_name` | Repository name |
| `registry_id` | Registry ID (account ID) — use in `docker login` |
