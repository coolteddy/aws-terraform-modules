# Module: transit-gateway

Creates a Transit Gateway (TGW) — the central network hub that connects multiple VPCs across
accounts without needing a peering connection between every pair.

Run this module in the **shared-services account**. Spoke accounts (management, sandbox) create
VPC attachments using the `tgw_id` output — see usage examples below.

## Cost

| Resource | Monthly cost |
|---|---|
| ⚠ TGW (always on) | ~$36/month ($0.05/hr) |
| ⚠ Each VPC attachment (always on) | ~$36/month ($0.05/hr) each |
| Data transfer through TGW | $0.02/GB |
| 3-account org (1 TGW + 3 attachments) | **~$144/month** |
| RAM resource share | Free |

**Tip:** For a short test (2 hours), total cost is ~$0.40. See TGW-TEST-PLAN.md in the repo root.

---

## Hub-and-spoke topology

```
Management account (spoke)         Shared-services account (hub)         Sandbox account (spoke)
──────────────────────             ──────────────────────────────        ──────────────────────
VPC 10.0.0.0/16                   VPC 10.1.0.0/16                       VPC 10.2.0.0/16
    │                                  │                                      │
    │ VPC attachment                   │ TGW lives here                       │ VPC attachment
    └──────────────────────────────────┤◄─────────────────────────────────────┘
                                  Transit Gateway
                                  Route Table:
                                  10.0.0.0/16 → mgmt-attachment    (auto-propagated)
                                  10.1.0.0/16 → shared-svc-attachment (auto-propagated)
                                  10.2.0.0/16 → sandbox-attachment   (auto-propagated)
```

---

## Route table concepts — association and propagation

The TGW has its own route table (separate from VPC route tables). Two things happen automatically
when `default_route_table_association` and `default_route_table_propagation` are both `"enable"`:

**Association** — tells the TGW which route table to consult when traffic arrives from an attachment:
```
Traffic from sandbox → TGW looks up destination in the default route table → finds shared-services → forwards
```

**Propagation** — each attachment automatically announces its VPC CIDR into the route table:
```
Sandbox attaches (10.2.0.0/16)
  → route "10.2.0.0/16 via sandbox-attachment" appears in the TGW route table automatically
  → management and shared-services can now reach sandbox — no manual routes needed
```

With both enabled: attach a VPC → routing works immediately, zero manual route resources.

---

## RAM — Resource Access Manager explained

AWS accounts are completely isolated by default. Account B cannot see a TGW created in Account A.
RAM breaks this isolation in a controlled, explicit way.

### What RAM does step by step

```
1. You create a TGW in shared-services account
   TGW ID: tgw-0abc123

2. You create a RAM resource share
   Name: "myorg-tgw-share"
   Contains: tgw-0abc123

3. You add Account principals to the share
   Principal: "111111111111"  (management account)
   Principal: "333333333333"  (sandbox account)

4. Result:
   Management account → can see tgw-0abc123 in their EC2 console
   Sandbox account    → can see tgw-0abc123 in their EC2 console
   Any other account  → cannot see it at all

5. Spoke accounts create VPC attachments using the TGW ID
   (auto_accept_shared_attachments = "enable" means no manual approval needed)
```

### What RAM does NOT do

- It does NOT automatically route traffic — that's the TGW route table's job
- It does NOT bypass security groups — SGs on target instances still apply
- It does NOT give full access to the shared-services account — only the TGW resource

---

## Two RAM sharing approaches

### Approach 1 — Specific account IDs (start here, tightest security)

```hcl
module "transit_gateway" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/transit-gateway?ref=v1.0.0"

  name = "myorg"

  ram_share_principals = [
    "111111111111",   # management account ID
    "333333333333",   # sandbox account ID
  ]
}
```

**What Terraform creates:**
```
aws_ram_resource_share.this[0]                       ← the share container
aws_ram_resource_association.tgw[0]                  ← attaches TGW to the share
aws_ram_principal_association.principals["111111111111"]  ← management can see TGW
aws_ram_principal_association.principals["333333333333"]  ← sandbox can see TGW
```

Only those two accounts can see the TGW. A new account added to the org gets nothing — you
must explicitly add it to `ram_share_principals`.

No prerequisites — no `aws-org-infra` change required.

### Approach 2 — Org-level sharing (when you have many accounts)

```hcl
module "transit_gateway" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/transit-gateway?ref=v1.0.0"

  name = "myorg"

  ram_share_principals = [
    "arn:aws:organizations::111111111111:organization/o-abc123xyz"
  ]
}
```

**What Terraform creates:**
```
aws_ram_resource_share.this[0]
aws_ram_resource_association.tgw[0]
aws_ram_principal_association.principals["arn:aws:organizations::..."]  ← whole org can see TGW
```

All current AND future org accounts can see and attach to the TGW automatically.

**Prerequisite (one-time setup in aws-org-infra):**
```hcl
# Add to aws-org-infra before applying Approach 2
resource "aws_ram_sharing_with_organization" "this" {}
```

### Migration path: Approach 1 → Approach 2

When you have too many accounts to list individually:

```
Step 1 — In aws-org-infra repo:
  Add: resource "aws_ram_sharing_with_organization" "this" {}
  Apply → org-level RAM sharing is enabled

Step 2 — In aws-shared-services-infra (this module call):
  Change ram_share_principals from account IDs to the org ARN
  Apply → RAM share updates in place, zero TGW downtime

Step 3 — Remove individual account IDs from ram_share_principals
```

Existing VPC attachments from spoke accounts are **unaffected** during migration.

---

## Usage

### Step 1 — Shared-services account (hub) — create the TGW

```hcl
module "vpc" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/vpc?ref=v1.0.0"
  name       = "shared-services"
  cidr_block = "10.1.0.0/16"
  public_subnets  = { "eu-west-2a" = "10.1.0.0/24" }
  private_subnets = { "eu-west-2a" = "10.1.10.0/24" }
  enable_nat_gateway = false
}

module "transit_gateway" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/transit-gateway?ref=v1.0.0"

  name = "myorg"

  ram_share_principals = [
    "111111111111",   # management account ID
    "333333333333",   # sandbox account ID
  ]

  tags = { Env = "shared-services", Project = "myorg" }
}

# Attach shared-services own VPC to the TGW
resource "aws_ec2_transit_gateway_vpc_attachment" "shared_services" {
  transit_gateway_id = module.transit_gateway.tgw_id
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  tags               = { Name = "shared-services-attachment" }
}

# Route traffic to other VPCs via TGW in shared-services VPC route table
resource "aws_route" "to_tgw" {
  route_table_id         = module.vpc.private_route_table_id
  destination_cidr_block = "10.0.0.0/8"   # all spoke VPCs
  transit_gateway_id     = module.transit_gateway.tgw_id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.shared_services]
}

output "tgw_id" {
  value = module.transit_gateway.tgw_id
  # Share this ID with sandbox and management Terraform configs
}
```

### Step 2 — Sandbox account (spoke) — attach and route

```hcl
module "vpc" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/vpc?ref=v1.0.0"
  name       = "sandbox"
  cidr_block = "10.2.0.0/16"
  public_subnets  = { "eu-west-2a" = "10.2.0.0/24" }
  private_subnets = { "eu-west-2a" = "10.2.10.0/24" }
  enable_nat_gateway = false
}

# Attach sandbox VPC to the TGW (TGW ID from shared-services output)
resource "aws_ec2_transit_gateway_vpc_attachment" "sandbox" {
  transit_gateway_id = "tgw-0abc123"   # from module.transit_gateway.tgw_id in shared-services
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  tags               = { Name = "sandbox-attachment" }
}

# Route all cross-account traffic via TGW
resource "aws_route" "to_tgw" {
  route_table_id         = module.vpc.private_route_table_id
  destination_cidr_block = "10.0.0.0/8"   # test-only supernet — use specific /16s in production
  transit_gateway_id     = "tgw-0abc123"
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.sandbox]
}
```

### Verify TGW route table after all accounts attach

```bash
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id tgw-rtb-XXXXXXXXXX \
  --filters Name=type,Values=propagated \
  --profile shared-services-admin \
  --query 'Routes[].{Destination:DestinationCidrBlock,State:State}' \
  --output table

# Expected:
# 10.0.0.0/16  active   (management — auto-propagated)
# 10.1.0.0/16  active   (shared-services — auto-propagated)
# 10.2.0.0/16  active   (sandbox — auto-propagated)
```

---

## Security notes

- Accounts NOT in `ram_share_principals` cannot see the TGW at all — they cannot attach even if `auto_accept_shared_attachments = "enable"`
- Security groups on target instances still apply even when TGW routing succeeds — two layers of defence
- For production with many tenants: consider `auto_accept_shared_attachments = "disable"` and a Lambda function to approve only known accounts
- Use specific per-account /16 routes in production — not the `10.0.0.0/8` supernet used in the test plan

---

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name` | Name prefix for all resources | `string` | — | yes |
| `amazon_side_asn` | BGP ASN — only matters for Direct Connect/VPN | `number` | `64512` | no |
| `enable_dns_support` | Cross-VPC private DNS resolution | `bool` | `true` | no |
| `auto_accept_shared_attachments` | Auto-accept VPC attachments from shared accounts | `string` | `"enable"` | no |
| `default_route_table_association` | Auto-associate new attachments with default route table | `string` | `"enable"` | no |
| `default_route_table_propagation` | Auto-propagate attachment CIDRs into default route table | `string` | `"enable"` | no |
| `ram_share_principals` | Account IDs or org ARN to share TGW with. `[]` = private | `list(string)` | `[]` | no |
| `ram_allow_external_principals` | Allow sharing outside the org | `bool` | `false` | no |
| `tags` | Tags applied to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `tgw_id` | TGW ID — pass to spoke accounts to create `aws_ec2_transit_gateway_vpc_attachment` |
| `tgw_arn` | TGW ARN |
| `default_route_table_id` | Default route table ID — reference in consuming repos for custom routes |
| `ram_share_arn` | RAM share ARN — `null` if no sharing configured |
