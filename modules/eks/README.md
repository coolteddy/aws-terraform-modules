# Module: eks

Creates a production-grade EKS cluster with a managed node group, OIDC provider for IRSA,
core managed add-ons, and EKS Access Entries for modern kubectl access management.

See [ADDONS.md](./ADDONS.md) for the full add-on catalogue — official and open-source.
See [AWS-ACCESS.md](../../AWS-ACCESS.md) in the repo root for VPN and SSM access setup.

## Cost

| Resource | Monthly cost |
|---|---|
| EKS control plane (standard support 1.33–1.35) | ~$73/month |
| EKS control plane (extended support 1.32 and older) | ~$511/month — **7x more** |
| Worker nodes — 2× t3.medium (default) | ~$60/month |
| EBS root volumes — 2× 20GB gp3 | ~$3.50/month |
| NAT Gateway (from VPC module) | ~$32/month |
| **Total minimum** | **~$168/month** |

**Always keep your cluster on a standard-support version.** Extended support adds ~$438/month.
Standard support versions: `1.33`, `1.34`, `1.35`. Check AWS docs before upgrading.

Destroy the cluster when not actively testing to avoid charges.

---

## Resource level diagram

Understanding what Terraform manages vs what kubectl manages:

```
┌─────────────────────────────────────────────────────────────────────┐
│  AWS LEVEL — managed by Terraform (this module)                     │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  EKS Cluster (control plane)                                 │   │
│  │  • cluster_version                                           │   │
│  │  • endpoint access + CIDRs                                   │   │
│  │  • IAM cluster role                                          │   │
│  │  • OIDC provider (enables IRSA — pods assume IAM roles)      │   │
│  │  • EKS Access Entries ← admin_arns (GitHub Actions role)     │   │
│  │  • Control plane logs → CloudWatch                           │   │
│  └───────────────────┬──────────────────────────────────────────┘   │
│                      │ controls                                     │
│  ┌───────────────────▼──────────────────────────────────────────┐   │
│  │  Managed Node Group (fleet of EC2 worker nodes)              │   │
│  │  • node_instance_types   what size EC2                       │   │
│  │  • node_capacity_type    ON_DEMAND or SPOT                   │   │
│  │  • node_disk_size        EBS root volume                     │   │
│  │  • node_labels ──────────────────────────────────────────┐  │   │
│  │  • node_taints ──────────────────────────────────────────┤  │   │
│  │    AWS stamps these on every node — survives replacement  │  │   │
│  └───────────────────┬──────────────────────────────────────┘  │   │
└──────────────────────┼─────────────────────────────────────────┼───┘
                       │ launches                                │
                       ▼                                         │
┌─────────────────────────────────────────────────────────────────────┐
│  EC2 LEVEL — individual nodes                                       │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │   Node 1     │  │   Node 2     │  │   Node 3     │             │
│  │ labels: ◄────┼──┼──────────────┼──┼── inherited from node group │
│  │  workload=ml │  │  workload=ml │  │  workload=ml │             │
│  │ taint: ◄─────┼──┼──────────────┼──┼── inherited from node group │
│  │  gpu:NoSched │  │  gpu:NoSched │  │  gpu:NoSched │             │
│  └──────────────┘  └──────────────┘  └──────────────┘             │
│                                                                     │
│  kubectl on individual nodes — NOT Terraform, NOT persistent:       │
│  kubectl cordon node-2   marks node-2 unschedulable (maintenance)  │
│  kubectl drain  node-2   evicts pods (before upgrade/replacement)  │
│  kubectl taint  node-2   adds taint to node-2 ONLY — lost on       │
│  kubectl label  node-2   adds label to node-2 ONLY   replacement   │
└─────────────────────────────────────────────────────────────────────┘
                       │ schedules pods on
                       ▼
┌─────────────────────────────────────────────────────────────────────┐
│  KUBERNETES LEVEL — managed by kubectl / Helm / ArgoCD             │
│                                                                     │
│  Pods ── Deployments ── Services ── ConfigMaps ── Secrets          │
│                                                                     │
│  nodeSelector: { workload: ml }  → targets nodes by label          │
│  tolerations:  [{ key: gpu }]    → allows pod on tainted nodes     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Accessing the cluster

### Option 1 — SSM Session Manager (recommended, free, zero open ports)

```bash
# Update kubeconfig — works even with private endpoint only
aws eks update-kubeconfig --name my-cluster --region eu-west-2

# kubectl works through the EKS API
kubectl get nodes
kubectl get pods -A
```

The EC2 node needs `AmazonSSMManagedInstanceCore` IAM policy. See [AWS-ACCESS.md](../../AWS-ACCESS.md).

### Option 2 — Public endpoint with IP restriction (simple, needs your IP)

```hcl
module "eks" {
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = [
    "203.0.113.5/32",    # your home IP — run: curl ifconfig.me
    "198.51.100.10/32",  # your CI/CD runner IP
  ]
}
```

### Option 3 — Private endpoint only (most secure)

```hcl
module "eks" {
  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true
}
# kubectl only works from within the VPC — via SSM, Tailscale, or WireGuard
# See AWS-ACCESS.md for full VPN setup guide
```

---

## Usage

### 1. Basic cluster — POC, public access

```hcl
module "vpc" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/vpc?ref=v1.0.0"
  name       = "sandbox"
  cidr_block = "10.0.0.0/16"
  public_subnets  = { "eu-west-2a" = "10.0.0.0/24", "eu-west-2b" = "10.0.1.0/24" }
  private_subnets = { "eu-west-2a" = "10.0.10.0/24", "eu-west-2b" = "10.0.11.0/24" }
}

module "eks" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/eks?ref=v1.0.0"

  name       = "sandbox"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  cluster_endpoint_public_access_cidrs = ["YOUR_IP/32"]  # curl ifconfig.me

  tags = {
    Env     = "sandbox"
    Project = "my-startup"
  }
}

# Configure kubectl after apply
output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region eu-west-2"
}
```

### 2. Production cluster — restricted access, Karpenter ready

```hcl
module "eks" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/eks?ref=v1.0.0"

  name            = "prod"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  cluster_version = "1.34"

  cluster_endpoint_public_access_cidrs = [
    "203.0.113.5/32",     # office
    "185.234.219.100/32", # VPN exit node
  ]

  node_instance_types = ["t3.medium", "t3.large", "t3a.medium"]  # Spot diversification
  node_capacity_type  = "SPOT"
  node_desired_size   = 3
  node_min_size       = 2
  node_max_size       = 10

  enable_karpenter_tags = true   # Karpenter will be installed in consuming repo

  admin_arns = [
    "arn:aws:iam::123456789012:role/github-actions-deployer",  # CI/CD
    "arn:aws:iam::123456789012:user/alice",                    # senior engineer
  ]

  tags = { Env = "prod", Project = "my-startup" }
}
```

### 3. Dedicated node pool — per-tenant isolation using taints

```hcl
module "eks_tenant_acme" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/eks?ref=v1.0.0"

  name       = "prod"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  node_labels = { "tenant" = "acme", "tier" = "premium" }
  node_taints = [{
    key    = "dedicated"
    value  = "acme"
    effect = "NO_SCHEDULE"   # only acme pods (with toleration) land here
  }]
}
```

### 4. Pinning add-on versions (production stability)

```hcl
module "eks" {
  # ...
  addon_version_overrides = {
    coredns            = "v1.11.1-eksbuild.4"
    "vpc-cni"          = "v1.16.4-eksbuild.2"
  }
  # kube-proxy and ebs-csi still use AWS recommended versions
}
```

Find available versions:
```bash
aws eks describe-addon-versions --addon-name coredns --kubernetes-version 1.34 \
  --query 'addons[].addonVersions[].addonVersion'
```

### 5. IRSA — giving a pod AWS permissions (in consuming repo)

After this module creates the OIDC provider, create IRSA roles in the consuming repo:

```hcl
# Trust policy — only the specific service account can assume this role
data "aws_iam_policy_document" "s3_reader_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:production:s3-reader"]
    }
  }
}

resource "aws_iam_role" "s3_reader" {
  name               = "eks-s3-reader"
  assume_role_policy = data.aws_iam_policy_document.s3_reader_trust.json
}

resource "aws_iam_role_policy_attachment" "s3_reader" {
  role       = aws_iam_role.s3_reader.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}
```

In Kubernetes, annotate the service account:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3-reader
  namespace: production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/eks-s3-reader
```

### 6. Version upgrade workflow (v1.0.0 → v1.1.0)

This simulates how big organisations upgrade EKS in a controlled way:

```bash
# Step 1 — currently running v1.0.0 (EKS 1.34)
# modules/eks source = "...?ref=v1.0.0"

# Step 2 — module maintainer releases v1.1.0 with EKS 1.35 default
# Update source reference in your workload repo:
# modules/eks source = "...?ref=v1.1.0"

# Step 3 — pull new module version
terraform init -upgrade

# Step 4 — preview the upgrade plan CAREFULLY
terraform plan
# Expected: cluster_version: "1.34" → "1.35"
#           node group: replacement (rolling, 33% at a time)

# Step 5 — apply during a maintenance window
terraform apply
# AWS upgrades control plane first (~10 mins), then rolls nodes one by one
```

Rules:
- Upgrades are sequential — never skip a minor version
- Always test in sandbox before applying to production
- Upgrade add-ons after the cluster version upgrade completes

---

## Access entries vs aws-auth ConfigMap

This module uses **EKS Access Entries** (`authentication_mode = "API"`) — the modern approach introduced in EKS 1.23. The old `aws-auth` ConfigMap required patching a Kubernetes resource outside Terraform's control, causing frequent corruption incidents. Access Entries are managed entirely via the AWS API.

**In production**, scope GitHub Actions access to specific namespaces rather than cluster-admin:

```hcl
# In the consuming repo — more restrictive than cluster-admin
resource "aws_eks_access_policy_association" "deployer" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "arn:aws:iam::123456789012:role/github-actions"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["production", "staging"]  # not cluster-wide
  }
}
```

---

## User Access Management

### Don't add individual users via Terraform

Map **IAM Identity Center groups** to Access Entries instead. Users are managed via
group membership — Terraform is only touched when adding a new group or changing
what a group can do, not when individual users join or leave.

```
IAM Identity Center
├── Group: eks-admins      → AmazonEKSClusterAdminPolicy  (DevOps / platform team)
├── Group: eks-devops      → AmazonEKSAdminPolicy         (senior engineers)
├── Group: eks-developers  → AmazonEKSEditPolicy, namespace scoped (developers)
└── Group: eks-readonly    → AmazonEKSViewPolicy           (QA, support)
```

### One-time Terraform setup (per group)

```hcl
# In the consuming repo — do this once per group, not per user
resource "aws_eks_access_entry" "developers" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "<SSO-permission-set-role-ARN-for-eks-developers-group>"
}

resource "aws_eks_access_policy_association" "developers" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "<SSO-permission-set-role-ARN-for-eks-developers-group>"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["tenant-a"]   # scoped — developer cannot see other namespaces
  }
}
```

### Onboarding a new user (no Terraform needed)

**Console — 30 seconds:**
```
IAM Identity Center → Groups → eks-developers → Add users → search John Doe → Add
```

**AWS CLI:**
```bash
aws identitystore create-group-membership \
  --identity-store-id d-xxxxxxxxxx \
  --group-id <eks-developers-group-id> \
  --member-id UserId=<john-doe-user-id> \
  --profile setnay-admin
```

**John sets up kubectl (runs once on his machine):**
```bash
aws sso login --profile john-profile
aws eks update-kubeconfig --name <cluster-name> --region eu-west-2 --profile john-profile
kubectl get pods -n tenant-a
```

### Offboarding

Remove John from the group in IAM Identity Center console. Access is revoked immediately —
no Terraform apply, no kubectl changes needed.

### Available EKS access policies

| Policy | What they can do |
|---|---|
| `AmazonEKSClusterAdminPolicy` | Everything — cluster-admin |
| `AmazonEKSAdminPolicy` | Most things except cluster-level RBAC |
| `AmazonEKSEditPolicy` | Deploy, scale, exec into pods — no RBAC changes |
| `AmazonEKSViewPolicy` | Read-only — `kubectl get/describe`, no exec |

### Scaling user management (growth path)

| Team size | Approach |
|---|---|
| 1–5 engineers | IAM Identity Center console |
| 5–20 engineers | Slack bot + boto3 (`identitystore` API) — one command onboards a user |
| 20–100 engineers | Buy Port or OpsLevel — SaaS internal developer portal |
| 100+ engineers | Evaluate Backstage (Spotify open source, self-hosted) |

---

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name` | Cluster name prefix | `string` | — | yes |
| `vpc_id` | VPC ID | `string` | — | yes |
| `subnet_ids` | Private subnet IDs — min 2 AZs | `list(string)` | — | yes |
| `cluster_version` | Kubernetes version — use standard support only | `string` | `"1.34"` | no |
| `cluster_endpoint_public_access` | Allow API access from internet | `bool` | `true` | no |
| `cluster_endpoint_public_access_cidrs` | Allowed CIDRs for public API access | `list(string)` | `["0.0.0.0/0"]` | no |
| `cluster_endpoint_private_access` | Allow API access from within VPC | `bool` | `true` | no |
| `node_instance_types` | EC2 instance types for nodes | `list(string)` | `["t3.medium"]` | no |
| `node_desired_size` | Desired node count | `number` | `2` | no |
| `node_min_size` | Minimum node count | `number` | `1` | no |
| `node_max_size` | Maximum node count | `number` | `3` | no |
| `node_capacity_type` | `ON_DEMAND` or `SPOT` | `string` | `"ON_DEMAND"` | no |
| `node_disk_size` | Node root EBS size in GB | `number` | `20` | no |
| `node_labels` | Kubernetes labels for all nodes — persistent across replacements | `map(string)` | `{}` | no |
| `node_taints` | Kubernetes taints for all nodes — persistent across replacements | `list(object)` | `[]` | no |
| `enable_addons` | Install coredns, kube-proxy, vpc-cni, aws-ebs-csi-driver | `bool` | `true` | no |
| `addon_version_overrides` | Pin specific add-on versions — uses AWS recommended if not set | `map(string)` | `{}` | no |
| `admin_arns` | IAM ARNs granted cluster-admin via Access Entries — include GitHub Actions role | `list(string)` | `[]` | no |
| `enable_karpenter_tags` | Add Karpenter discovery tag to node security group | `bool` | `false` | no |
| `tags` | Tags applied to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `cluster_name` | Cluster name — use in `aws eks update-kubeconfig --name <value>` |
| `cluster_endpoint` | API server endpoint — for Terraform kubernetes/helm providers |
| `cluster_certificate_authority_data` | CA data for kubectl TLS (sensitive) |
| `cluster_version` | Running Kubernetes version |
| `cluster_oidc_issuer_url` | OIDC issuer URL — for IRSA trust policy conditions |
| `oidc_provider_arn` | OIDC provider ARN — for IRSA trust policy Principal.Federated |
| `node_role_arn` | Node IAM role ARN — attach extra policies in consuming repo |
| `node_role_name` | Node IAM role name — for `aws_iam_role_policy_attachment` |
| `cluster_security_group_id` | EKS cluster security group ID |
