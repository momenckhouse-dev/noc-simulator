# On AWS the database is Amazon RDS instead of a Postgres Pod: AWS handles the disk,
# patching and backups. db.t4g.micro + 20 GB is in the free tier.

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_db_subnet_group" "db" {
  name       = "${var.project_name}-db"
  subnet_ids = module.vpc.private_subnets
}

# Firewall for the database: only the Kubernetes nodes may connect, only on 5432.
resource "aws_security_group" "db" {
  name        = "${var.project_name}-db"
  description = "PostgreSQL from EKS nodes only"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_nodes" {
  for_each = {
    nodes   = module.eks.node_security_group_id
    cluster = module.eks.cluster_primary_security_group_id
  }

  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS ${each.key}"
}

resource "aws_db_instance" "db" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp2"
  storage_encrypted = true

  db_name  = "noc"
  username = "noc"
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  # Lab settings: easy to destroy, no leftover snapshots costing money.
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
}
