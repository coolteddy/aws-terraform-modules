variable "name" {
  description = "Name prefix applied to all resources"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC — from module.vpc.vpc_id"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs where instances run — from module.vpc.private_subnet_ids"
  type        = list(string)
}

variable "target_group_arns" {
  description = "List of ALB or NLB target group ARNs to register instances into — from module.alb.target_group_arn"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB — instances only accept traffic from this SG, not the open internet"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for EC2 instances. Use a data source in the calling module to fetch the latest Amazon Linux 2023 or Ubuntu AMI for your region."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (e.g. t3.small, t3.medium, t3.large)"
  type        = string
}

variable "min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances the ASG can scale up to"
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "Desired number of running instances at steady state"
  type        = number
  default     = 2
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

variable "root_volume_type" {
  description = "Root EBS volume type. gp3 is faster and cheaper than gp2 — recommended."
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.root_volume_type)
    error_message = "root_volume_type must be one of: gp2, gp3, io1, io2."
  }
}

variable "key_name" {
  description = "EC2 key pair name for SSH access. Leave null to disable SSH — recommended for production."
  type        = string
  default     = null
}

variable "ssh_allowed_cidrs" {
  description = "IPv4 CIDR blocks allowed to SSH into instances. Only used when key_name is set. Use specific IPs (e.g. '203.0.113.5/32') — never 0.0.0.0/0."
  type        = list(string)
  default     = []
}

variable "user_data" {
  description = "Base64-encoded user data script to run on first boot. Use base64encode(templatefile(...)) in the calling module."
  type        = string
  default     = null
}

variable "extra_security_group_ids" {
  description = "Additional security group IDs to attach to instances (e.g. a bastion SSH SG). The ALB SG is always included automatically."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the ASG and propagated to all instances"
  type        = map(string)
  default     = {}
}

variable "instance_tags" {
  description = "Additional tags applied to EC2 instances only (not the ASG resource itself)"
  type        = map(string)
  default     = {}
}
