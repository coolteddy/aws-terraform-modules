# ---------------------------------------------------------------
# Security Group — EC2 instances
# Rules are separate resources per Terraform/AWS provider v5
# best practice — avoids inline rule conflicts and enables tagging
# ---------------------------------------------------------------

resource "aws_security_group" "instance" {
  name        = "${var.name}-instance-sg"
  description = "Security group for ${var.name} ASG instances"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-instance-sg" })
}

# Accept traffic from the ALB security group only — not from the open internet.
# Port range 80-65535 covers any app port without hardcoding it here.
resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.instance.id
  description                  = "All traffic from ALB"
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.alb_security_group_id
  tags                         = merge(var.tags, { Name = "${var.name}-instance-from-alb" })
}

# SSH — one rule per allowed CIDR, only when a key pair is provided.
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = var.key_name != null ? toset(var.ssh_allowed_cidrs) : toset([])

  security_group_id = aws_security_group.instance.id
  description       = "SSH from ${each.value}"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
  tags              = merge(var.tags, { Name = "${var.name}-instance-ssh" })
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.instance.id
  description       = "All outbound IPv4"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = merge(var.tags, { Name = "${var.name}-instance-egress-ipv4" })
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.instance.id
  description       = "All outbound IPv6"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  tags              = merge(var.tags, { Name = "${var.name}-instance-egress-ipv6" })
}

# ---------------------------------------------------------------
# IAM — SSM Instance Profile
# Always created so instances can be accessed via SSM Session Manager
# without needing SSH or a bastion host. See AWS-ACCESS.md.
# ---------------------------------------------------------------

data "aws_iam_policy_document" "instance_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name}-asg-instance-role"
  assume_role_policy = data.aws_iam_policy_document.instance_assume_role.json
  tags               = merge(var.tags, { Name = "${var.name}-asg-instance-role" })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-asg-instance-profile"
  role = aws_iam_role.instance.name
  tags = merge(var.tags, { Name = "${var.name}-asg-instance-profile" })
}

# ---------------------------------------------------------------
# Launch Template — EC2 instance blueprint
# ---------------------------------------------------------------

resource "aws_launch_template" "this" {
  name_prefix   = "${var.name}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  user_data     = var.user_data

  iam_instance_profile {
    name = aws_iam_instance_profile.instance.name
  }

  # IMDSv2: require session token — prevents SSRF attacks from stealing
  # instance credentials. hop_limit=1 blocks container/pod access.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups = concat(
      [aws_security_group.instance.id],
      var.extra_security_group_ids
    )
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      encrypted             = true
      delete_on_termination = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.name}-lt" })
}

# ---------------------------------------------------------------
# Auto Scaling Group
# ---------------------------------------------------------------

resource "aws_autoscaling_group" "this" {
  name                = "${var.name}-asg"
  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = var.target_group_arns
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 60

  dynamic "tag" {
    for_each = merge(var.tags, var.instance_tags)
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}
