variable "name" {
  description = "Name prefix applied to all resources"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC — from module.vpc.vpc_id"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs to attach the NLB to — public for internet-facing, private for internal"
  type        = list(string)
}

variable "target_port" {
  description = "Port your backend application listens on (e.g. 5432 for Postgres, 6379 for Redis)"
  type        = number
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "internal" {
  description = "Set true for an internal (private) NLB between services. Default false = internet-facing."
  type        = bool
  default     = false
}

variable "listener_protocol" {
  description = "Protocol for the NLB listener: TCP, UDP, TLS, or TCP_UDP"
  type        = string
  default     = "TCP"

  validation {
    condition     = contains(["TCP", "UDP", "TLS", "TCP_UDP"], var.listener_protocol)
    error_message = "listener_protocol must be one of: TCP, UDP, TLS, TCP_UDP."
  }
}

variable "target_protocol" {
  description = "Protocol used to connect to backends: TCP or UDP"
  type        = string
  default     = "TCP"

  validation {
    condition     = contains(["TCP", "UDP", "TCP_UDP"], var.target_protocol)
    error_message = "target_protocol must be one of: TCP, UDP, TCP_UDP."
  }
}

variable "target_type" {
  description = "Backend target type: 'instance' for EC2/ASG, 'ip' for ECS Fargate or EKS pods"
  type        = string
  default     = "instance"

  validation {
    condition     = contains(["instance", "ip"], var.target_type)
    error_message = "target_type must be one of: instance, ip. NLB does not support lambda targets."
  }
}

variable "health_check_protocol" {
  description = "Protocol for health checks: TCP (default), HTTP, or HTTPS"
  type        = string
  default     = "TCP"

  validation {
    condition     = contains(["TCP", "HTTP", "HTTPS"], var.health_check_protocol)
    error_message = "health_check_protocol must be one of: TCP, HTTP, HTTPS."
  }
}

variable "health_check_path" {
  description = "URL path for health checks — only used when health_check_protocol is HTTP or HTTPS"
  type        = string
  default     = "/"
}

variable "health_check_interval" {
  description = "Seconds between each health check. NLB supports 10 or 30 seconds only."
  type        = number
  default     = 30

  validation {
    condition     = contains([10, 30], var.health_check_interval)
    error_message = "NLB health_check_interval must be 10 or 30 seconds."
  }
}

variable "deregistration_delay" {
  description = "Seconds the NLB waits before removing a draining target"
  type        = number
  default     = 30
}

variable "cross_zone_load_balancing" {
  description = "Distribute traffic evenly across all targets in all AZs regardless of AZ target count. Recommended true."
  type        = bool
  default     = true
}

variable "allowed_ingress_cidrs" {
  description = "IPv4 CIDR blocks allowed to reach the NLB. Default: open to internet."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_ingress_ipv6_cidrs" {
  description = "IPv6 CIDR blocks allowed to reach the NLB. Default: none."
  type        = list(string)
  default     = []
}

variable "ip_address_type" {
  description = "IP address type for the NLB. 'ipv4' (default) = IPv4 only. 'dualstack' = IPv4 + IPv6."
  type        = string
  default     = "ipv4"

  validation {
    condition     = contains(["ipv4", "dualstack"], var.ip_address_type)
    error_message = "ip_address_type must be one of: ipv4, dualstack."
  }
}

variable "enable_deletion_protection" {
  description = "Prevent accidental terraform destroy of the NLB. Set true in production."
  type        = bool
  default     = false
}

variable "enable_tls" {
  description = "Add a TLS listener for encrypted TCP connections. Requires certificate_arn."
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate ARN for TLS listener. Required when enable_tls = true."
  type        = string
  default     = null
}
