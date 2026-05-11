# ---------------------------------------------------------------
# Security Group
# ---------------------------------------------------------------

resource "aws_security_group" "this" {
  name        = "${var.name}-ec2-sg"
  description = "Security group for ${var.name} EC2 instance"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-ec2-sg" })
}

# One ingress rule per port per CIDR — configurable, not hardcoded to 0.0.0.0/0
resource "aws_vpc_security_group_ingress_rule" "public_ports_ipv4" {
  for_each = {
    for pair in setproduct(
      [for p in var.ingress_ports : tostring(p)],
      var.allowed_ingress_cidrs
    ) : "${pair[0]}-${pair[1]}" => { port = tonumber(pair[0]), cidr = pair[1] }
  }

  security_group_id = aws_security_group.this.id
  description       = "Port ${each.value.port} from ${each.value.cidr}"
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value.cidr
  tags              = merge(var.tags, { Name = "${var.name}-ec2-port-${each.value.port}" })
}

resource "aws_vpc_security_group_ingress_rule" "public_ports_ipv6" {
  for_each = length(var.allowed_ingress_ipv6_cidrs) > 0 ? {
    for pair in setproduct(
      [for p in var.ingress_ports : tostring(p)],
      var.allowed_ingress_ipv6_cidrs
    ) : "${pair[0]}-${pair[1]}" => { port = tonumber(pair[0]), cidr = pair[1] }
  } : {}

  security_group_id = aws_security_group.this.id
  description       = "Port ${each.value.port} IPv6 from ${each.value.cidr}"
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
  cidr_ipv6         = each.value.cidr
  tags              = merge(var.tags, { Name = "${var.name}-ec2-port-${each.value.port}-ipv6" })
}

# SSH — one rule per allowed CIDR, only when a key pair is provided
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = var.key_name != null ? toset(var.ssh_allowed_cidrs) : toset([])

  security_group_id = aws_security_group.this.id
  description       = "SSH from ${each.value}"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
  tags              = merge(var.tags, { Name = "${var.name}-ec2-ssh" })
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.this.id
  description       = "All outbound IPv4"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = merge(var.tags, { Name = "${var.name}-ec2-egress-ipv4" })
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.this.id
  description       = "All outbound IPv6"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  tags              = merge(var.tags, { Name = "${var.name}-ec2-egress-ipv6" })
}

# ---------------------------------------------------------------
# IAM Role + Instance Profile
# Always created — SSM Session Manager requires it regardless of S3 access.
# AmazonSSMManagedInstanceCore is always attached (enables SSH-free access).
# S3 read policy is added on top when s3_read_bucket_arns is provided.
# ---------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = merge(var.tags, { Name = "${var.name}-ec2-role" })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "s3_read" {
  count = length(var.s3_read_bucket_arns) > 0 ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = flatten([
      var.s3_read_bucket_arns,
      [for arn in var.s3_read_bucket_arns : "${arn}/*"]
    ])
  }
}

resource "aws_iam_role_policy" "s3_read" {
  count = length(var.s3_read_bucket_arns) > 0 ? 1 : 0

  name   = "${var.name}-s3-read"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.s3_read[0].json
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-ec2-profile"
  role = aws_iam_role.this.name
  tags = merge(var.tags, { Name = "${var.name}-ec2-profile" })
}

# ---------------------------------------------------------------
# EC2 Instance
# ---------------------------------------------------------------

resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name
  user_data              = var.user_data

  # IMDSv2: require session token — prevents SSRF attacks from stealing
  # instance credentials. hop_limit=1 blocks container/pod access.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = var.root_volume_type
    encrypted             = true
    delete_on_termination = true
  }

  lifecycle {
    # Prevent replacement if AMI is updated out-of-band — the instance keeps running.
    # To force replacement when intentional: terraform apply -replace="aws_instance.this"
    ignore_changes = [ami, user_data]
  }

  tags = merge(var.tags, { Name = var.name })
}

# ---------------------------------------------------------------
# Elastic IP — static public IP, survives reboots
# ---------------------------------------------------------------

resource "aws_eip" "this" {
  count  = var.create_elastic_ip ? 1 : 0
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-eip" })
}

resource "aws_eip_association" "this" {
  count         = var.create_elastic_ip ? 1 : 0
  instance_id   = aws_instance.this.id
  allocation_id = aws_eip.this[0].id
}

# ---------------------------------------------------------------
# Optional data volume — separate EBS disk for database/app data
# ---------------------------------------------------------------

resource "aws_ebs_volume" "data" {
  count = var.data_volume_size > 0 ? 1 : 0

  availability_zone = aws_instance.this.availability_zone
  size              = var.data_volume_size
  type              = var.data_volume_type
  encrypted         = true
  tags              = merge(var.tags, { Name = "${var.name}-data-volume" })
}

resource "aws_volume_attachment" "data" {
  count = var.data_volume_size > 0 ? 1 : 0

  device_name = var.data_volume_device_name
  volume_id   = aws_ebs_volume.data[0].id
  instance_id = aws_instance.this.id
}
