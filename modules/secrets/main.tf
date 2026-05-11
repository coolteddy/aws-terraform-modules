# ---------------------------------------------------------------
# Secret container
# ---------------------------------------------------------------

resource "aws_secretsmanager_secret" "this" {
  name                    = var.name
  description             = var.description
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, { Name = var.name })
}

# ---------------------------------------------------------------
# Secret value
# Stored separately from the container so the value can be
# rotated (updated) without replacing the secret resource itself
# ---------------------------------------------------------------

resource "aws_secretsmanager_secret_version" "this" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = var.secret_string
}

# ---------------------------------------------------------------
# Resource-based policy — cross-account read access
# Only created when cross_account_reader_arns is non-empty.
# Allows specific IAM roles in other accounts to call GetSecretValue.
# The calling role still needs an IAM identity policy allowing
# secretsmanager:GetSecretValue — both must allow (AWS double-lock).
# ---------------------------------------------------------------

data "aws_iam_policy_document" "cross_account_read" {
  count = length(var.cross_account_reader_arns) > 0 ? 1 : 0

  statement {
    sid    = "AllowCrossAccountRead"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.cross_account_reader_arns
    }

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [aws_secretsmanager_secret.this.arn]
  }
}

resource "aws_secretsmanager_secret_policy" "this" {
  count = length(var.cross_account_reader_arns) > 0 ? 1 : 0

  secret_arn = aws_secretsmanager_secret.this.arn
  policy     = data.aws_iam_policy_document.cross_account_read[0].json
}
