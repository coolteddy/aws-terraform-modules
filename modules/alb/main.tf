# ---------------------------------------------------------------
# Security Group
# Rules are separate resources per Terraform/AWS provider v5
# best practice — avoids inline rule conflicts and enables tagging
# ---------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "Security group for ${var.name} ALB"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-alb-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_ipv4" {
  for_each          = toset(var.allowed_ingress_cidrs)
  security_group_id = aws_security_group.alb.id
  description       = "HTTP IPv4"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
  tags              = merge(var.tags, { Name = "${var.name}-alb-http-ipv4" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_ipv6" {
  for_each          = toset(var.allowed_ingress_ipv6_cidrs)
  security_group_id = aws_security_group.alb.id
  description       = "HTTP IPv6"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv6         = each.value
  tags              = merge(var.tags, { Name = "${var.name}-alb-http-ipv6" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https_ipv4" {
  for_each          = var.enable_https ? toset(var.allowed_ingress_cidrs) : toset([])
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS IPv4"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
  tags              = merge(var.tags, { Name = "${var.name}-alb-https-ipv4" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https_ipv6" {
  for_each          = var.enable_https ? toset(var.allowed_ingress_ipv6_cidrs) : toset([])
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS IPv6"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv6         = each.value
  tags              = merge(var.tags, { Name = "${var.name}-alb-https-ipv6" })
}

resource "aws_vpc_security_group_egress_rule" "alb_all_ipv4" {
  security_group_id = aws_security_group.alb.id
  description       = "All outbound IPv4"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = merge(var.tags, { Name = "${var.name}-alb-egress-ipv4" })
}

resource "aws_vpc_security_group_egress_rule" "alb_all_ipv6" {
  security_group_id = aws_security_group.alb.id
  description       = "All outbound IPv6"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  tags              = merge(var.tags, { Name = "${var.name}-alb-egress-ipv6" })
}

# ---------------------------------------------------------------
# Load Balancer
# ---------------------------------------------------------------

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids
  ip_address_type    = var.ip_address_type

  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(var.tags, { Name = "${var.name}-alb" })
}

# ---------------------------------------------------------------
# Target Group
# ---------------------------------------------------------------

resource "aws_lb_target_group" "this" {
  name        = "${var.name}-tg"
  port        = var.target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = var.target_type

  deregistration_delay = var.deregistration_delay

  health_check {
    path                = var.health_check_path
    interval            = var.health_check_interval
    protocol            = "HTTP"
    matcher             = "200-299"
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, { Name = "${var.name}-tg" })
}

# ---------------------------------------------------------------
# Listeners
# ---------------------------------------------------------------

# HTTP forward — active when HTTPS is disabled
resource "aws_lb_listener" "http_forward" {
  count = var.enable_https ? 0 : 1

  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# HTTP redirect — active when HTTPS is enabled; sends all port-80 traffic to 443
resource "aws_lb_listener" "http_redirect" {
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener — only created when enable_https = true
resource "aws_lb_listener" "https" {
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
