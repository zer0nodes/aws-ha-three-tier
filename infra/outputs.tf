output "db_identifier" {
  description = "RDS instance identifier."
  value       = aws_db_instance.main.identifier
}

output "db_endpoint" {
  description = "PostgreSQL endpoint (host:port), reachable only from inside the VPC."
  value       = aws_db_instance.main.endpoint
}
