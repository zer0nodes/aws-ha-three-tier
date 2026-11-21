output "app_url" {
  description = "Application URL (HTTP through the load balancer)."
  value       = "http://${aws_lb.app.dns_name}"
}

output "asg_name" {
  description = "Auto Scaling group name."
  value       = aws_autoscaling_group.app.name
}

output "target_group_arn" {
  description = "Target group ARN, for checking target health."
  value       = aws_lb_target_group.app.arn
}

output "db_identifier" {
  description = "RDS instance identifier."
  value       = aws_db_instance.main.identifier
}

output "db_endpoint" {
  description = "PostgreSQL endpoint (host:port), reachable only from inside the VPC."
  value       = aws_db_instance.main.endpoint
}

output "dashboard_url" {
  description = "CloudWatch dashboard in the AWS console."
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}
