# ---------------------------------------------------------------
# Locals
# ---------------------------------------------------------------

locals {
  cluster_oidc_issuer = aws_eks_cluster.this.identity[0].oidc[0].issuer

  karpenter_tags = var.enable_karpenter_tags ? {
    "karpenter.sh/discovery" = var.name
  } : {}
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------
# Add-on version lookups — resolved at plan time
# most_recent = false returns AWS's recommended (validated) version
# for the given cluster version — not the absolute latest
# ---------------------------------------------------------------

data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = var.cluster_version
  most_recent        = false
}

data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = var.cluster_version
  most_recent        = false
}

data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = var.cluster_version
  most_recent        = false
}

data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = var.cluster_version
  most_recent        = false
}

# ---------------------------------------------------------------
# IAM — Cluster Role
# EKS control plane assumes this to call AWS APIs
# (describe VPCs, create ENIs, manage load balancers)
# ---------------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  tags               = merge(var.tags, { Name = "${var.name}-eks-cluster-role" })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------
# IAM — Node Group Role
# EC2 worker nodes assume this to register with the cluster,
# pull container images from ECR, and manage pod networking
# ---------------------------------------------------------------

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  tags               = merge(var.tags, { Name = "${var.name}-eks-node-role" })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ---------------------------------------------------------------
# EKS Cluster
# authentication_mode = "API" enables EKS Access Entries —
# the modern replacement for the aws-auth ConfigMap
# ---------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = var.cluster_endpoint_public_access
    endpoint_private_access = var.cluster_endpoint_private_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # All five control plane log types — audit is most valuable for security
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = merge(var.tags, local.karpenter_tags, { Name = var.name })

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
}

# ---------------------------------------------------------------
# Launch Template — enforces IMDSv2 and EBS encryption on nodes
# Not used to manage the AMI — EKS manages the AL2023 AMI
# ---------------------------------------------------------------

resource "aws_launch_template" "nodes" {
  name_prefix = "${var.name}-nodes-"
  description = "Launch template for ${var.name} EKS node group"

  # IMDSv2: requires a session token — prevents pods from
  # stealing node IAM credentials via SSRF attacks
  # hop_limit=1 blocks pod access to the metadata endpoint
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.name}-nodes-lt" })
}

# ---------------------------------------------------------------
# Managed Node Group
# ---------------------------------------------------------------

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type
  ami_type       = "AL2023_x86_64_STANDARD"

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # Rolling upgrade — at most 33% of nodes offline at once
  # Pods keep running on the remaining 2/3 during cluster upgrades
  update_config {
    max_unavailable_percentage = 33
  }

  labels = var.node_labels

  dynamic "taint" {
    for_each = var.node_taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(var.tags, local.karpenter_tags, { Name = "${var.name}-nodes" })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}

# ---------------------------------------------------------------
# OIDC Provider — enables IRSA (IAM Roles for Service Accounts)
# Pods can assume IAM roles without node-level credentials
# tls provider fetches the thumbprint of the OIDC issuer certificate
# ---------------------------------------------------------------

data "tls_certificate" "oidc" {
  url = local.cluster_oidc_issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = local.cluster_oidc_issuer
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
  client_id_list  = ["sts.amazonaws.com"]
  tags            = merge(var.tags, { Name = "${var.name}-oidc" })
}

# ---------------------------------------------------------------
# Managed Add-ons
# addon_version uses the data source recommended version unless
# the caller has overridden it via addon_version_overrides
# resolve_conflicts_on_update = OVERWRITE: EKS manages these
# add-ons — manual changes are overwritten on next apply
# ---------------------------------------------------------------

resource "aws_eks_addon" "coredns" {
  count = var.enable_addons ? 1 : 0

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = lookup(var.addon_version_overrides, "coredns", data.aws_eks_addon_version.coredns.version)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = merge(var.tags, { Name = "${var.name}-coredns" })

  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "kube_proxy" {
  count = var.enable_addons ? 1 : 0

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  addon_version               = lookup(var.addon_version_overrides, "kube-proxy", data.aws_eks_addon_version.kube_proxy.version)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = merge(var.tags, { Name = "${var.name}-kube-proxy" })

  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "vpc_cni" {
  count = var.enable_addons ? 1 : 0

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = lookup(var.addon_version_overrides, "vpc-cni", data.aws_eks_addon_version.vpc_cni.version)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = merge(var.tags, { Name = "${var.name}-vpc-cni" })

  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "ebs_csi" {
  count = var.enable_addons ? 1 : 0

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = lookup(var.addon_version_overrides, "aws-ebs-csi-driver", data.aws_eks_addon_version.ebs_csi.version)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # EBS CSI driver needs IRSA to create/attach EBS volumes on behalf of pods
  # The service account annotation is managed via the consuming repo IRSA role
  tags = merge(var.tags, { Name = "${var.name}-ebs-csi" })

  depends_on = [aws_eks_node_group.this]
}

# ---------------------------------------------------------------
# EKS Access Entries — modern replacement for aws-auth ConfigMap
# One entry + one policy association per IAM ARN in admin_arns
# Grants full cluster-admin (kubectl get/apply/delete anything)
# Pass your GitHub Actions role ARN from aws-org-infra here
# ---------------------------------------------------------------

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.admin_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  tags          = merge(var.tags, { Name = "${var.name}-access-${basename(each.value)}" })
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.admin_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
