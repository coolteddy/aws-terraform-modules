variable "name" {
  description = "Name prefix for all resources — used as the EKS cluster name"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC — from module.vpc.vpc_id"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for EKS nodes and control plane ENIs — from module.vpc.private_subnet_ids. Minimum 2 subnets in different AZs required."
  type        = list(string)
}

# ---------------------------------------------------------------
# Cluster version
#
# COST WARNING — standard vs extended support:
#   Standard support (1.33, 1.34, 1.35): $0.10/hr = ~$73/month
#   Extended support (1.32 and older):   $0.70/hr = ~$511/month
#   Always stay on a standard-support version to avoid 7x cost increase.
#
# Upgrade rules:
#   - Sequential only: 1.34 → 1.35 (never skip minor versions)
#   - Control plane upgrades first, then node groups
#   - Module v1.0.0 defaults to 1.34; v1.1.0 will bump to 1.35
# ---------------------------------------------------------------

variable "cluster_version" {
  description = "Kubernetes version. Standard support (no extra cost): 1.33, 1.34, 1.35. Extended support adds ~$438/month. Default 1.34 is stable and within standard support."
  type        = string
  default     = "1.34"
}

# ---------------------------------------------------------------
# API endpoint access
# See AWS-ACCESS.md in the repo root for full access setup guide
# including SSM Session Manager, Tailscale, WireGuard, and Client VPN
# ---------------------------------------------------------------

variable "cluster_endpoint_public_access" {
  description = "Allow EKS API access from the internet. Restrict to known IPs via cluster_endpoint_public_access_cidrs. See AWS-ACCESS.md for NordVPN, Tailscale, and SSM options."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the EKS API over the internet. Default open — restrict in production to your home IP (curl ifconfig.me), VPN exit node, and CI/CD runner IPs."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_endpoint_private_access" {
  description = "Allow EKS API access from within the VPC. Recommended true — enables SSM Session Manager kubectl access without internet exposure."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------
# Managed Node Group
# node_labels and node_taints are set at the AWS node group level.
# AWS stamps them onto every node that joins — including replacements
# after scaling or upgrades. Unlike kubectl taint/label which applies
# to one specific node and is lost when that node is replaced.
# ---------------------------------------------------------------

variable "node_instance_types" {
  description = "EC2 instance types for nodes. List multiple for better Spot availability. Example SPOT mix: [\"t3.medium\", \"t3.large\", \"t3a.medium\"]"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
}

variable "node_capacity_type" {
  description = "ON_DEMAND is reliable. SPOT saves 60-90% but instances can be reclaimed with 2 minutes notice — use only for fault-tolerant workloads."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_disk_size" {
  description = "EBS root volume size in GB per node. Increase if running many large container images."
  type        = number
  default     = 20
}

variable "node_labels" {
  description = "Kubernetes labels applied to all nodes in the group. Persistent — survives node replacement. Used with nodeSelector in pod specs for workload targeting."
  type        = map(string)
  default     = {}
}

variable "node_taints" {
  description = "Kubernetes taints applied to all nodes in the group. Persistent — survives node replacement. Repels pods without a matching toleration. Used for dedicated node pools."
  type = list(object({
    key    = string
    value  = optional(string)
    effect = string
  }))
  default = []

  validation {
    condition = alltrue([
      for t in var.node_taints :
      contains(["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"], t.effect)
    ])
    error_message = "node_taints effect must be one of: NO_SCHEDULE, NO_EXECUTE, PREFER_NO_SCHEDULE."
  }
}

# ---------------------------------------------------------------
# Managed Add-ons
# Versions are resolved dynamically at plan time using
# data "aws_eks_addon_version" — returns AWS's recommended
# (validated, stable) version for the given cluster_version.
# No hardcoded version strings that go stale across EKS upgrades.
# ---------------------------------------------------------------

variable "enable_addons" {
  description = "Install the four core managed add-ons: coredns, kube-proxy, vpc-cni, aws-ebs-csi-driver. See ADDONS.md for the full catalogue."
  type        = bool
  default     = true
}

variable "addon_version_overrides" {
  description = "Override the AWS-recommended version for specific add-ons. Leave empty to use the recommended version resolved at plan time. Pin only for compliance or staged upgrades. Find versions: aws eks describe-addon-versions --addon-name coredns"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------
# Access management
# EKS Access Entries — the modern replacement for aws-auth ConfigMap.
# Managed entirely via AWS API, no Kubernetes ConfigMap patching.
# Pass your GitHub Actions IAM role ARN here so CI/CD can run kubectl.
# ---------------------------------------------------------------

variable "admin_arns" {
  description = "IAM role/user ARNs granted cluster-admin access via EKS Access Entries. Pass your GitHub Actions role ARN (from aws-org-infra) and any engineer IAM ARNs that need kubectl access."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------
# Karpenter discovery
# ---------------------------------------------------------------

variable "enable_karpenter_tags" {
  description = "Add karpenter.sh/discovery = cluster_name tag to node security group. Required for Karpenter to discover which security groups to attach to nodes it provisions. Enable when installing Karpenter in the consuming repo."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
