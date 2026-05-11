output "cluster_name" {
  description = "EKS cluster name — use in: aws eks update-kubeconfig --name <value>, Helm chart values, Karpenter EC2NodeClass"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint — used by the Terraform kubernetes and helm providers in the consuming repo"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data — required for kubectl TLS verification"
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster — use to validate the version before upgrading add-ons"
  value       = aws_eks_cluster.this.version
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL — used in IRSA trust policy conditions to scope a role to a specific service account. Format: https://oidc.eks.<region>.amazonaws.com/id/<id>"
  value       = local.cluster_oidc_issuer
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider — used in IRSA trust policy Principal.Federated. Pass to consuming repo when creating IRSA roles for add-ons (ALB controller, Karpenter, ExternalDNS, etc.)"
  value       = aws_iam_openid_connect_provider.this.arn
}

output "node_role_arn" {
  description = "ARN of the node group IAM role — attach extra policies here if nodes need additional AWS permissions (e.g. S3 read, Parameter Store access)"
  value       = aws_iam_role.node.arn
}

output "node_role_name" {
  description = "Name of the node group IAM role — use with aws_iam_role_policy_attachment in the consuming repo to add extra permissions"
  value       = aws_iam_role.node.name
}

output "cluster_security_group_id" {
  description = "ID of the EKS-managed cluster security group — add extra ingress rules here if needed (e.g. allow a bastion host to reach nodes on a specific port)"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
