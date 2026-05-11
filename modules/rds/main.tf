# ---------------------------------------------------------------
# Security Group — RDS instance
# Only accepts connections from the allowed compute SG on port 5432
# ---------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "Security group for ${var.name} RDS PostgreSQL instance"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-rds-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from allowed compute SG"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.allowed_security_group_id
  tags                         = merge(var.tags, { Name = "${var.name}-rds-postgres-ingress" })
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.rds.id
  description       = "All outbound IPv4"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = merge(var.tags, { Name = "${var.name}-rds-egress-ipv4" })
}

# ---------------------------------------------------------------
# DB Subnet Group
# AWS requires at least 2 subnets in different AZs even for
# single-AZ instances — it reserves the right to move the instance
# during maintenance
# ---------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-db-subnet-group"
  subnet_ids  = var.subnet_ids
  description = "Subnet group for ${var.name} RDS instance"
  tags        = merge(var.tags, { Name = "${var.name}-db-subnet-group" })
}

# ---------------------------------------------------------------
# RDS Instance — PostgreSQL
# ---------------------------------------------------------------

resource "aws_db_instance" "this" {
  identifier = "${var.name}-postgres"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.db_username

  # Password handling — flexible for POC vs production:
  # manage_master_user_password=true  → RDS generates + stores in Secrets Manager ($0.40/month)
  # manage_master_user_password=false → caller provides db_password (stored in Terraform state)
  manage_master_user_password = var.manage_master_user_password
  password                    = var.manage_master_user_password ? null : var.db_password

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final-snapshot"

  # Automatically apply minor version patches during the maintenance window
  auto_minor_version_upgrade = true

  lifecycle {
    # Ignore password changes made outside Terraform — RDS rotation or manual resets
    # should not cause Terraform to reset the password on next apply
    ignore_changes = [password]

    # Hard guard against terraform destroy — deletion_protection = true blocks the AWS API,
    # but prevent_destroy blocks the Terraform plan itself before any API call is made.
    prevent_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.name}-postgres" })
}
