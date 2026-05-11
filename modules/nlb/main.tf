# ---------------------------------------------------------------
# Security Group
# Rules are separate resources per Terraform/AWS provider v5
# best practice — avoids inline rule conflicts and enables tagging
# ---------------------------------------------------------------

resource "aws_security_group" "nlb" {
  name        = "${var.name}-nlb-sg"
  description = "Security group for ${var.name} NLB"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-nlb-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "nlb_listener_ipv4" {
  for_each          = toset(var.allowed_ingress_cidrs)
  security_group_id = aws_security_group.nlb.id
  description       = "Listener port IPv4"
  from_port         = var.target_port
  to_port           = var.target_port
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
  tags              = merge(var.tags, { Name = "${var.name}-nlb-listener-ipv4" })
}

resource "aws_vpc_security_group_ingress_rule" "nlb_listener_ipv6" {
  for_each          = toset(var.allowed_ingress_ipv6_cidrs)
  security_group_id = aws_security_group.nlb.id
  description       = "Listener port IPv6"
  from_port         = var.target_port
  to_port           = var.target_port
  ip_protocol       = "tcp"
  cidr_ipv6         = each.value
  tags              = merge(var.tags, { Name = "${var.name}-nlb-listener-ipv6" })
}

resource "aws_vpc_security_group_ingress_rule" "nlb_tls_ipv4" {
  for_each          = var.enable_tls ? toset(var.allowed_ingress_cidrs) : toset([])
  security_group_id = aws_security_group.nlb.id
  description       = "TLS port IPv4"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
  tags              = merge(var.tags, { Name = "${var.name}-nlb-tls-ipv4" })
}

resource "aws_vpc_security_group_ingress_rule" "nlb_tls_ipv6" {
  for_each          = var.enable_tls ? toset(var.allowed_ingress_ipv6_cidrs) : toset([])
  security_group_id = aws_security_group.nlb.id
  description       = "TLS port IPv6"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv6         = each.value
  tags              = merge(var.tags, { Name = "${var.name}-nlb-tls-ipv6" })
}

resource "aws_vpc_security_group_egress_rule" "nlb_all_ipv4" {
  security_group_id = aws_security_group.nlb.id
  description       = "All outbound IPv4"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = merge(var.tags, { Name = "${var.name}-nlb-egress-ipv4" })
}

resource "aws_vpc_security_group_egress_rule" "nlb_all_ipv6" {
  security_group_id = aws_security_group.nlb.id
  description       = "All outbound IPv6"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  tags              = merge(var.tags, { Name = "${var.name}-nlb-egress-ipv6" })
}

# ---------------------------------------------------------------
# Load Balancer
# ---------------------------------------------------------------

resource "aws_lb" "this" {
  name               = "${var.name}-nlb"
  internal           = var.internal
  load_balancer_type = "network"
  security_groups    = [aws_security_group.nlb.id]
  subnets            = var.subnet_ids
  ip_address_type    = var.ip_address_type

  enable_cross_zone_load_balancing = var.cross_zone_load_balancing
  enable_deletion_protection       = var.enable_deletion_protection

  tags = merge(var.tags, { Name = "${var.name}-nlb" })
}

# ---------------------------------------------------------------
# Target Group
# ---------------------------------------------------------------

resource "aws_lb_target_group" "this" {
  name        = "${var.name}-nlb-tg"
  port        = var.target_port
  protocol    = var.target_protocol
  vpc_id      = var.vpc_id
  target_type = var.target_type

  deregistration_delay = var.deregistration_delay

  health_check {
    protocol = var.health_check_protocol
    interval = var.health_check_interval
    path     = contains(["HTTP", "HTTPS"], var.health_check_protocol) ? var.health_check_path : null
  }

  tags = merge(var.tags, { Name = "${var.name}-nlb-tg" })
}

# ---------------------------------------------------------------
# Listeners
# ---------------------------------------------------------------

# Plain listener — TCP/UDP/TCP_UDP (active when enable_tls is false)
resource "aws_lb_listener" "plain" {
  count = var.enable_tls ? 0 : 1

  load_balancer_arn = aws_lb.this.arn
  port              = var.target_port
  protocol          = var.listener_protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# TLS listener — active when enable_tls = true
resource "aws_lb_listener" "tls" {
  count = var.enable_tls ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "TLS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
