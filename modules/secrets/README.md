# Module: secrets

Creates an AWS Secrets Manager secret with optional cross-account read access.
Supports two patterns: per-tenant secrets in workload accounts, and central secrets
in shared-services shared to spoke accounts.

## Cost

| Resource | Monthly cost |
|---|---|
| Per secret | $0.40/month |
| API calls | $0.05 per 10,000 calls |

---

## The AWS double-lock model for cross-account secrets

When Account A stores a secret and Account B wants to read it, **both** must allow the access:

```
Account A (shared-services) — resource-based policy on the secret:
  "Allow arn:aws:iam::SANDBOX::role/app-role to GetSecretValue"
                    ↕ BOTH must allow
Account B (sandbox) — identity-based policy on the role:
  "Allow secretsmanager:GetSecretValue on arn:aws:secretsmanager:...:secret:/shared/*"
```

This module handles Account A's side. The consuming repo for Account B must add the
identity policy to the application role separately.

---

## Usage

### 1. Per-tenant secret (workload account)

```hcl
module "db_password" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/secrets?ref=v1.0.0"

  name          = "/prod/tenant-acme/db-password"
  description   = "PostgreSQL master password for tenant Acme"
  secret_string = var.db_password   # passed in via tfvars, never hardcoded

  tags = { Env = "prod", Tenant = "acme" }
}

# Grant the ECS task or EC2 role access (in the same account — no cross-account needed)
resource "aws_iam_role_policy" "read_secret" {
  name = "read-db-password"
  role = module.ecs.task_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = module.db_password.secret_arn
    }]
  })
}
```

### 2. Central secret in shared-services — read by sandbox

```hcl
# In aws-shared-services-infra:
module "sendgrid_key" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/secrets?ref=v1.0.0"

  name          = "/shared/sendgrid-api-key"
  description   = "SendGrid API key shared across all tenant accounts"
  secret_string = var.sendgrid_api_key

  cross_account_reader_arns = [
    "arn:aws:iam::333333333333:role/sandbox-app-role",   # sandbox account
    "arn:aws:iam::111111111111:role/mgmt-app-role",      # management account
  ]
}
```

```hcl
# In aws-sandbox-infra — the OTHER side of the double-lock:
resource "aws_iam_role_policy" "read_shared_secrets" {
  name = "read-shared-secrets"
  role = "sandbox-app-role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "arn:aws:secretsmanager:eu-west-2:SHARED_SERVICES_ACCOUNT:secret:/shared/*"
    }]
  })
}
```

### 3. Structured secret (multiple values in one secret)

```hcl
module "db_credentials" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/secrets?ref=v1.0.0"

  name        = "/prod/tenant-acme/db-credentials"
  description = "Full database connection info for tenant Acme"

  secret_string = jsonencode({
    host     = module.rds.db_host
    port     = module.rds.db_port
    dbname   = module.rds.db_name
    username = module.rds.db_username
    password = var.db_password
  })
}
```

Application reads and parses:
```python
import boto3, json
secret = json.loads(boto3.client("secretsmanager").get_secret_value(
    SecretId="/prod/tenant-acme/db-credentials"
)["SecretString"])
conn = f"postgresql://{secret['username']}:{secret['password']}@{secret['host']}:{secret['port']}/{secret['dbname']}"
```

### 4. Dev/POC — immediate deletion (no waiting period)

```hcl
module "dev_secret" {
  source = "..."

  name                 = "/dev/test-api-key"
  secret_string        = "test-key-abc123"
  recovery_window_in_days = 0   # immediate deletion — can recreate with same name straight away
}
```

### 5. Using with external-secrets-operator in EKS

After creating the secret, the `external-secrets-operator` in EKS can sync it to a
Kubernetes Secret automatically:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-password
  namespace: production
spec:
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: db-password
  data:
    - secretKey: password
      remoteRef:
        key: /prod/tenant-acme/db-password
```

The EKS pod's IRSA role needs `secretsmanager:GetSecretValue` on the secret ARN.

---

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name` | Secret path (e.g. `/prod/tenant/db-password`) | `string` | — | yes |
| `secret_string` | Secret value — use `jsonencode()` for structured secrets | `string` (sensitive) | — | yes |
| `description` | Human-readable description | `string` | `""` | no |
| `kms_key_id` | CMK ARN for encryption — null uses AWS managed key (free) | `string` | `null` | no |
| `recovery_window_in_days` | Days before permanent deletion. `0` = immediate, else 7–30. | `number` | `7` | no |
| `cross_account_reader_arns` | IAM ARNs from other accounts allowed to read this secret | `list(string)` | `[]` | no |
| `tags` | Tags applied to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `secret_arn` | Secret ARN — use in IAM policies and application config |
| `secret_name` | Secret name/path — use with AWS SDK `GetSecretValue` |
| `secret_version_id` | Current version ID — pin apps to a specific version |
