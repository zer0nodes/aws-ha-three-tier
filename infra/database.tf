resource "aws_db_subnet_group" "main" {
  name        = "${local.name}-db"
  description = "Database subnets in two Availability Zones"
  subnet_ids  = [aws_subnet.this["db-a"].id, aws_subnet.this["db-b"].id]

  tags = { Name = "${local.name}-db" }
}

resource "aws_db_instance" "main" {
  identifier = "${local.name}-db"

  engine         = "postgres"
  engine_version = "18"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "appdb"
  username = "appadmin"

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period = 1
  apply_immediately       = true
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = { Name = "${local.name}-db" }
}
