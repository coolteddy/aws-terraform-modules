# ---------------------------------------------------------------
# ECR Repository
# ---------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_id : null
  }

  tags = merge(var.tags, { Name = var.name })
}

# ---------------------------------------------------------------
# Lifecycle Policy — controls image retention
# Rule 1: delete untagged images after N days (CI artifacts)
# Rule 2: keep only the last N tagged images per repository
# ---------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged images after ${var.lifecycle_untagged_days} day(s)"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.lifecycle_untagged_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last ${var.lifecycle_keep_tagged_count} tagged images"
        selection = {
          tagStatus   = "tagged"
          tagPatterns = ["*"]
          countType   = "imageCountMoreThan"
          countNumber = var.lifecycle_keep_tagged_count
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ---------------------------------------------------------------
# Repository Policy — org-scoped cross-account pull
# Only created when org_id is provided.
# Uses aws:PrincipalOrgID condition — any account in the org can pull,
# accounts outside the org cannot, even with the policy ARN.
# More scalable than listing individual account IDs and prevents
# external principals from ever gaining access.
# ---------------------------------------------------------------

data "aws_iam_policy_document" "org_pull" {
  count = var.org_id != null ? 1 : 0

  statement {
    sid    = "AllowOrgPull"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.org_id]
    }
  }
}

resource "aws_ecr_repository_policy" "this" {
  count = var.org_id != null ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = data.aws_iam_policy_document.org_pull[0].json
}
