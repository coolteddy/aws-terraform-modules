variable "name" {
  description = "Name prefix applied to all resources"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC — from module.vpc.vpc_id"
  type        = string
}

variable "subnet_id" {
  description = "Single subnet ID where the instance runs. Use a public subnet when create_elastic_ip = true."
  type        = string
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance. Use a data source in the calling module to fetch the latest Amazon Linux 2023 or Ubuntu AMI for your region."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (e.g. t3.micro, t3.medium, t3.xlarge)"
  type        = string
}

variable "ingress_ports" {
  description = "List of TCP ports to open from the internet (e.g. [443, 80]). Port 22 is controlled separately via ssh_allowed_cidrs."
  type        = list(number)
  default     = [443]
}

variable "allowed_ingress_cidrs" {
  description = "IPv4 CIDR blocks allowed to reach the open ingress_ports. Default 0.0.0.0/0 (open internet). Restrict for non-public-facing instances."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_ingress_ipv6_cidrs" {
  description = "IPv6 CIDR blocks allowed to reach the open ingress_ports. Default empty (no IPv6 ingress)."
  type        = list(string)
  default     = []
}

variable "key_name" {
  description = "EC2 key pair name for SSH access. Leave null to disable SSH entirely."
  type        = string
  default     = null
}

variable "ssh_allowed_cidrs" {
  description = "IPv4 CIDR blocks allowed to SSH into the instance. Only used when key_name is set. Use /32 for a single IP — never 0.0.0.0/0."
  type        = list(string)
  default     = []
}

variable "create_elastic_ip" {
  description = "Attach a static Elastic IP to the instance. Required for Route 53 A records and any workload that needs a stable public IP."
  type        = bool
  default     = true
}

variable "s3_read_bucket_arns" {
  description = "List of S3 bucket ARNs the instance is allowed to read (e.g. [module.s3.bucket_arn]). When non-empty, an IAM role and instance profile are created automatically."
  type        = list(string)
  default     = []
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

variable "data_volume_size" {
  description = "Size in GB of an optional second EBS volume for data (e.g. database files). Set 0 to skip creation."
  type        = number
  default     = 0
}

variable "data_volume_type" {
  description = "EBS volume type for the data volume."
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.data_volume_type)
    error_message = "data_volume_type must be one of: gp2, gp3, io1, io2."
  }
}

variable "data_volume_device_name" {
  description = "Device name for the data volume. Linux convention: /dev/xvdb for the second disk."
  type        = string
  default     = "/dev/xvdb"
}

variable "user_data" {
  description = "Base64-encoded bootstrap script to run on first boot. Use base64encode(templatefile(...)) in the calling module."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
