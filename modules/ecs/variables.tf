variable "name" {
  description = "Name prefix for all resources — used as cluster name, service name, and log group prefix"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID — from module.vpc.vpc_id"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs where Fargate tasks run — from module.vpc.private_subnet_ids"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ALB security group ID — tasks only accept traffic from this SG — from module.alb.security_group_id"
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group ARN to register tasks into — from module.alb.target_group_arn"
  type        = string
}

# ---------------------------------------------------------------
# Fargate sizing
# CPU and memory must be a valid combination — see README.
# ---------------------------------------------------------------

variable "task_cpu" {
  description = "Fargate task CPU units. Valid values: 256, 512, 1024, 2048, 4096. 256 = 0.25 vCPU."
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.task_cpu)
    error_message = "task_cpu must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "task_memory" {
  description = "Fargate task memory in MB. Must be compatible with task_cpu — see README for valid combinations."
  type        = number
  default     = 512
}

# ---------------------------------------------------------------
# Container
# ---------------------------------------------------------------

variable "container_image" {
  description = "Full container image URI including tag — from module.ecr.repository_url. Example: 123456789012.dkr.ecr.eu-west-2.amazonaws.com/myapp/api:v1.2.3"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on — must match the ALB target group's target_port"
  type        = number
}

variable "desired_count" {
  description = "Number of task instances to run. ECS replaces any that crash."
  type        = number
  default     = 2
}

variable "environment_variables" {
  description = "Plain-text environment variables injected into the container. Never put secrets here — use secret_arns instead."
  type        = map(string)
  default     = {}
}

variable "secret_arns" {
  description = <<-EOT
    Secrets Manager ARNs injected as environment variables at task start.
    Key = environment variable name in the container.
    Value = Secrets Manager secret ARN (from module.secrets.secret_arn).
    ECS retrieves the secret value before the container starts — never appears in task definition or logs.
    Example: { DB_PASSWORD = module.secrets.secret_arn }
  EOT
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------
# IAM
# ---------------------------------------------------------------

variable "ecr_repository_arns" {
  description = "List of ECR repository ARNs the task execution role can pull images from. Pass module.ecr.repository_arn for each ECR repo used by this service."
  type        = list(string)
  default     = []
}

variable "task_role_policy_arns" {
  description = "Additional IAM managed policy ARNs attached to the task role (what the running container can do). Example: allow S3 read, DynamoDB access."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days. Default 30. Set 0 to never expire."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
