# AWS Private Resource Access Guide

How to connect from your laptop to private AWS resources (EKS, RDS, EC2 in private subnets)
without exposing them to the internet.

---

## The problem

Private resources (RDS, EKS nodes, EC2 in private subnets) have no public IP.
By design — they are unreachable from the internet. But you, the engineer, need to
reach them for debugging, `kubectl`, `psql`, etc.

There are four practical solutions. Pick the one that matches your situation.

---

## Option 1 — AWS Systems Manager Session Manager (recommended, free) ⭐

No VPN. No open ports. No bastion host. AWS tunnels your connection through SSM.
The EC2 instance needs no public IP and no port 22 open.

**Cost:** Free.

**Requirements:**
- EC2 instance must have the `AmazonSSMManagedInstanceCore` IAM policy attached
- SSM agent installed (pre-installed on Amazon Linux 2023 and Ubuntu 20.04+)

### SSH into a private EC2 instance
```bash
aws ssm start-session --target i-0abc123def456
```

### Forward a remote port to your laptop (RDS, Redis, etc.)
```bash
# Access RDS on localhost:5432
aws ssm start-session \
  --target i-0abc123def456 \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters host="mydb.xyz.eu-west-2.rds.amazonaws.com",portNumber="5432",localPortNumber="5432"

# Now connect locally
psql -h localhost -p 5432 -U admin -d mydb
```

### kubectl access to EKS (through SSM)
```bash
# Update kubeconfig — works even if endpoint is private-only
aws eks update-kubeconfig --name my-cluster --region eu-west-2

# kubectl works through the EKS API endpoint
kubectl get nodes
kubectl get pods -A
```

**Who uses it:** AWS's own recommendation for all engineers. Zero infrastructure overhead.
Most AWS-native companies use this as their primary access method.

---

## Option 2 — Tailscale subnet router (easiest VPN, free tier) ⭐

Tailscale is a mesh VPN built on WireGuard. One small EC2 instance becomes a
"subnet router" that advertises your VPC CIDR to your Tailscale mesh.
Your laptop joins the mesh and can reach all private VPC resources directly.

**Cost:** Free tier covers 100 devices. EC2 t3.micro ~$8/month.

**Setup time:** ~15 minutes.

### Step 1 — Deploy a subnet router EC2

Use the `ec2` module from this repo:

```hcl
module "tailscale_router" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/ec2?ref=v1.0.0"

  name          = "tailscale-router"
  vpc_id        = module.vpc.vpc_id
  subnet_id     = module.vpc.private_subnet_ids[0]
  ami_id        = data.aws_ami.al2023.id
  instance_type = "t3.micro"

  ingress_ports     = []       # no internet ports — all access via Tailscale
  create_elastic_ip = false    # private subnet, no public IP needed

  user_data = base64encode(templatefile("${path.module}/tailscale_bootstrap.sh.tpl", {
    tailscale_auth_key = var.tailscale_auth_key
    vpc_cidr           = module.vpc.vpc_cidr_block
  }))
}
```

### Step 2 — Bootstrap script (`tailscale_bootstrap.sh.tpl`)
```bash
#!/bin/bash
curl -fsSL https://tailscale.com/install.sh | sh
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p
tailscale up --authkey="${tailscale_auth_key}" --advertise-routes="${vpc_cidr}"
```

### Step 3 — On your laptop
```bash
# Install Tailscale on your laptop
# https://tailscale.com/download

# Approve the subnet route in Tailscale admin console
# Then your laptop can reach any private IP in the VPC directly:
psql -h 10.0.10.5 -U admin -d mydb        # RDS private IP
kubectl get nodes                           # EKS via private endpoint
```

**Who uses it:** Most startups. HashiCorp, Notion, and many others use Tailscale internally.
Works great with NordVPN meshnet users — add the EC2 instance to your Tailscale network
alongside your NordVPN devices.

---

## Option 3 — WireGuard on EC2 (full control, cheap)

Deploy a t3.micro EC2 with WireGuard using our `ec2` module. Your laptop connects
via WireGuard tunnel and gets access to the whole VPC.

**Cost:** ~$8/month for t3.micro + Elastic IP.

**Setup time:** ~30 minutes.

```hcl
module "wireguard" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/ec2?ref=v1.0.0"

  name              = "wireguard"
  vpc_id            = module.vpc.vpc_id
  subnet_id         = module.vpc.public_subnet_ids[0]   # public subnet for WireGuard
  ami_id            = data.aws_ami.al2023.id
  instance_type     = "t3.micro"
  create_elastic_ip = true   # stable IP for WireGuard config

  ingress_ports     = [51820]           # WireGuard UDP port
  key_name          = "my-keypair"
  ssh_allowed_cidrs = ["YOUR_HOME_IP/32"]

  user_data = base64encode(file("${path.module}/wireguard_bootstrap.sh"))
}
```

**WireGuard config on laptop (`/etc/wireguard/aws.conf`):**
```ini
[Interface]
PrivateKey = <your-laptop-private-key>
Address    = 10.100.0.2/32
DNS        = 10.0.0.2             # VPC DNS resolver

[Peer]
PublicKey  = <wireguard-ec2-public-key>
Endpoint   = <elastic-ip>:51820
AllowedIPs = 10.0.0.0/16         # your VPC CIDR — all VPC traffic through tunnel
```

**Who uses it:** DevOps engineers who want full control without depending on Tailscale.

---

## Option 4 — AWS Client VPN (enterprise, managed)

AWS's managed OpenVPN service. Centralised access control, audit logs, MFA support.

**Cost:** ~$0.10/hr endpoint + $0.05/hr per connection = **~$108/month minimum**.

**Best for:** Teams of 20+ engineers needing centralised access management.

**Terraform module:** `terraform-aws-modules/client-vpn/aws`

```hcl
module "client_vpn" {
  source  = "terraform-aws-modules/client-vpn/aws"
  version = "~> 2.0"

  name               = "my-vpn"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  client_cidr_block  = "10.100.0.0/16"

  authentication_options = [{
    type                = "certificate-authentication"
    root_certificate_arn = aws_acm_certificate.vpn.arn
  }]
}
```

---

## Restricting EKS API access by IP

If you use `cluster_endpoint_public_access = true` (the default), lock it to known IPs:

```hcl
module "eks" {
  source = "...?ref=v1.0.0"

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = [
    "203.0.113.5/32",      # your home IP (find with: curl ifconfig.me)
    "198.51.100.10/32",    # office IP
    "185.234.219.100/32",  # NordVPN exit node IP
    "10.0.0.0/8",          # VPC internal access
  ]
}
```

For maximum security, set `cluster_endpoint_public_access = false` and access the API
only through SSM Session Manager or a VPN connected to the VPC.

---

## Quick comparison

| Option | Cost/month | Setup time | Open ports | Best for |
|---|---|---|---|---|
| SSM Session Manager | Free | 0 min | None | Everyone — start here |
| Tailscale subnet router | ~$8 | 15 min | None | Full VPC access, teams |
| WireGuard on EC2 | ~$8 | 30 min | UDP 51820 | Full control preference |
| AWS Client VPN | ~$108+ | 2 hrs | None | Enterprise 20+ engineers |

**Recommended starting point:**
1. SSM Session Manager for `kubectl` and port forwarding — free, zero infrastructure
2. Add Tailscale if you need persistent full-VPC access from multiple devices
