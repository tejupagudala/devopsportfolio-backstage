
# ==========================================
# Backstage PostgreSQL Database
# ==========================================

variable "rds_final_snapshot_identifier" {
  description = "Unique snapshot name to use when deleting RDS"
  type        = string
  default     = "backstage-idp-final-001"
}

# RDS subnet group across two Availability Zones
resource "aws_db_subnet_group" "backstage" {
  name = "${local.name}-db-subnets"

  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${local.name}-db-subnets"
  }
}

# Private database security group
resource "aws_security_group" "rds" {
  name_prefix = "${local.name}-rds-"
  description = "PostgreSQL access for Backstage EKS"
  vpc_id      = aws_vpc.idp.id

  tags = {
    Name = "${local.name}-rds-sg"
  }
}

# Only allow connections from the EKS cluster SG.
# The managed node group uses the cluster SG.
resource "aws_security_group_rule" "rds_from_eks" {
  type                     = "ingress"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_eks_cluster.idp.vpc_config[0].cluster_security_group_id

  protocol  = "tcp"
  from_port = 5432
  to_port   = 5432

  description = "PostgreSQL from Backstage EKS"
}

# ==========================================
# RDS PostgreSQL
# ==========================================

resource "aws_db_instance" "backstage" {
  identifier = "${local.name}-postgres"

  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  db_name  = "backstage"
  username = "backstageadmin"

  # AWS manages the database password in Secrets Manager.
  manage_master_user_password = true

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.backstage.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = false

  # Require TLS for all database connections.
  parameter_group_name = aws_db_parameter_group.backstage.name

  backup_retention_period = 1

  # On-demand portfolio: database can be destroyed,
  # but an RDS snapshot must be created first.
  deletion_protection       = false
  skip_final_snapshot       = false
  final_snapshot_identifier = var.rds_final_snapshot_identifier

  auto_minor_version_upgrade = true

  tags = {
    Name = "${local.name}-postgres"
  }
}

# Enforce TLS for PostgreSQL connections
resource "aws_db_parameter_group" "backstage" {
  name   = "${local.name}-postgres16"
  family = "postgres16"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }

  tags = {
    Name = "${local.name}-postgres16"
  }
}

# ==========================================
# Outputs
# ==========================================

output "rds_endpoint" {
  value = aws_db_instance.backstage.address
}

output "rds_port" {
  value = aws_db_instance.backstage.port
}

output "rds_database_name" {
  value = aws_db_instance.backstage.db_name
}

output "rds_master_secret_arn" {
  value = aws_db_instance.backstage.master_user_secret[0].secret_arn
}
