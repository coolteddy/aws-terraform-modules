variable "name" {
  description = "Name prefix applied to all resources"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC — from module.vpc.vpc_id"
  type        = string
}

variable "subnet_ids" {
  description = "List of public subnet IDs to attach the ALB to — from module.vpc.public_subnet_ids"
  type        = list(string)
}

variable "target_port" {
  description = "Port your backend application listens on (e.g. 80, 8080, 3000)"
  type        = number
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "internal" {
  description = "Set true for an internal (private) ALB between services. Default false = internet-facing."
  type        = bool
  default     = false
}

variable "target_type" {
  description = "Backend target type: 'instance' for EC2/ASG, 'ip' for ECS Fargate or EKS pods"
  type        = string
  default     = "instance"

  validation {
    condition     = contains(["instance", "ip", "lambda"], var.target_type)
    error_message = "target_type must be one of: instance, ip, lambda."
  }
}

variable "health_check_path" {
  description = "URL path the ALB uses to health-check backends (e.g. '/' or '/health')"
  type        = string
  default     = "/"
}

variable "health_check_interval" {
  description = "Seconds between each health check"
  type        = number
  default     = 30
}

variable "deregistration_delay" {
  description = "Seconds the ALB waits before removing a draining target — allows in-flight requests to complete"
  type        = number
  default     = 30
}

variable "allowed_ingress_cidrs" {
  description = "IPv4 CIDR blocks allowed to reach the ALB on port 80 (and 443 if HTTPS enabled). Default: open to internet."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_ingress_ipv6_cidrs" {
  description = "IPv6 CIDR blocks allowed to reach the ALB on port 80 (and 443 if HTTPS enabled). Default: none."
  type        = list(string)
  default     = []
}

variable "ip_address_type" {
  description = "IP address type for the ALB. 'ipv4' (default) = IPv4 only. 'dualstack' = IPv4 + IPv6. 'dualstack-without-public-ipv4' = IPv6 + private IPv4 only."
  type        = string
  default     = "ipv4"

  validation {
    condition     = contains(["ipv4", "dualstack", "dualstack-without-public-ipv4"], var.ip_address_type)
    error_message = "ip_address_type must be one of: ipv4, dualstack, dualstack-without-public-ipv4."
  }
}

variable "enable_deletion_protection" {
  description = "Prevent accidental terraform destroy of the ALB. Set true in production."
  type        = bool
  default     = false
}

variable "enable_https" {
  description = "Add an HTTPS listener on port 443 and redirect HTTP to HTTPS. Requires certificate_arn."
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener. Required when enable_https = true."
  type        = string
  default     = null
}
