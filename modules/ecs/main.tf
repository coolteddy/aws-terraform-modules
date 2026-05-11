data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------
# CloudWatch Log Group — container stdout/stderr
# ---------------------------------------------------------------

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = merge(var.tags, { Name = "/ecs/${var.name}" })
}

# ---------------------------------------------------------------
# ECS Cluster
# ---------------------------------------------------------------

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(var.tags, { Name = var.name })
}

# ---------------------------------------------------------------
# IAM — Task Execution Role
# Used by the ECS agent (not your code) to:
#   - Pull the container image from ECR
#   - Write container logs to CloudWatch
#   - Retrieve secrets from Secrets Manager before the container starts
# ---------------------------------------------------------------

data "aws_iam_policy_document" "execution_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.execution_assume_role.json
  tags               = merge(var.tags, { Name = "${var.name}-ecs-execution-role" })
}

# AWS managed policy covers most execution needs
resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Extra policy for ECR cross-account pull and Secrets Manager access
data "aws_iam_policy_document" "execution_extra" {
  # ECR pull permissions for specified repositories
  dynamic "statement" {
    for_each = length(var.ecr_repository_arns) > 0 ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
      ]
      resources = var.ecr_repository_arns
    }
  }

  # ECR auth token — always needed, operates at registry level
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Secrets Manager — inject secrets before container starts
  dynamic "statement" {
    for_each = length(var.secret_arns) > 0 ? [1] : []
    content {
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = values(var.secret_arns)
    }
  }
}

resource "aws_iam_role_policy" "execution_extra" {
  name   = "${var.name}-ecs-execution-extra"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_extra.json
}

# ---------------------------------------------------------------
# IAM — Task Role
# Assumed by your running container. Grants AWS permissions
# your application code needs (S3, DynamoDB, SQS, etc.)
# ---------------------------------------------------------------

data "aws_iam_policy_document" "task_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task" {
  name               = "${var.name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume_role.json
  tags               = merge(var.tags, { Name = "${var.name}-ecs-task-role" })
}

resource "aws_iam_role_policy_attachment" "task_extra" {
  for_each = toset(var.task_role_policy_arns)

  role       = aws_iam_role.task.name
  policy_arn = each.value
}

# ---------------------------------------------------------------
# Security Group — Fargate tasks
# ---------------------------------------------------------------

resource "aws_security_group" "tasks" {
  name        = "${var.name}-ecs-tasks-sg"
  description = "Security group for ${var.name} ECS Fargate tasks"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-ecs-tasks-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "Traffic from ALB"
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.alb_security_group_id
  tags                         = merge(var.tags, { Name = "${var.name}-ecs-from-alb" })
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.tasks.id
  description       = "All outbound IPv4 — needed to reach ECR, Secrets Manager, CloudWatch"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = merge(var.tags, { Name = "${var.name}-ecs-egress-ipv4" })
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.tasks.id
  description       = "All outbound IPv6"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  tags              = merge(var.tags, { Name = "${var.name}-ecs-egress-ipv6" })
}

# ---------------------------------------------------------------
# ECS Task Definition
# container_definitions is a JSON string — we build it with jsonencode()
# environment: plain env vars from var.environment_variables map
# secrets: Secrets Manager ARNs injected before container starts
# ---------------------------------------------------------------

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name  = var.name
    image = var.container_image

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    # Convert map to list of {name, value} objects
    environment = [for k, v in var.environment_variables : { name = k, value = v }]

    # Convert map to list of {name, valueFrom} objects
    # ECS retrieves each secret before the container starts — never in logs or task definition
    secrets = [for k, v in var.secret_arns : { name = k, valueFrom = v }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "ecs"
      }
    }

    essential = true
  }])

  tags = merge(var.tags, { Name = var.name })
}

# ---------------------------------------------------------------
# ECS Service — keeps desired_count tasks running
# Registers tasks with the ALB target group automatically
# ---------------------------------------------------------------

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.name
    container_port   = var.container_port
  }

  lifecycle {
    # Ignore task definition changes triggered by external deployments
    # (e.g. CI/CD updates the image tag outside Terraform)
    # Use terraform apply to update intentionally
    ignore_changes = [task_definition]
  }

  depends_on = [
    aws_iam_role_policy_attachment.execution_managed,
    aws_iam_role_policy.execution_extra,
  ]

  tags = merge(var.tags, { Name = var.name })
}
