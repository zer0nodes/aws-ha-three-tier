locals {
  alb = aws_lb.app.arn_suffix
  tg  = aws_lb_target_group.app.arn_suffix
  asg = aws_autoscaling_group.app.name
  db  = aws_db_instance.main.identifier

  dashboard_widgets = [
    {
      title   = "ALB requests per minute"
      stat    = "Sum"
      metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb]]
    },
    {
      title   = "Target response time p95 (seconds)"
      stat    = "p95"
      metrics = [["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb]]
    },
    {
      title = "HTTP 5xx per minute"
      stat  = "Sum"
      metrics = [
        ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.alb],
        ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", local.alb],
      ]
    },
    {
      title = "Healthy and unhealthy targets"
      stat  = "Average"
      metrics = [
        ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.tg, "LoadBalancer", local.alb],
        ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", local.tg, "LoadBalancer", local.alb],
      ]
    },
    {
      title = "Instances in the Auto Scaling group"
      stat  = "Average"
      metrics = [
        ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", local.asg],
        ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", local.asg],
      ]
    },
    {
      title       = "Average CPU of the group (%)"
      stat        = "Average"
      metrics     = [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", local.asg]]
      annotations = { horizontal = [{ label = "Scaling target", value = 50 }] }
      yAxis       = { left = { min = 0, max = 100 } }
    },
    {
      title       = "RDS CPU (%)"
      stat        = "Average"
      metrics     = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", local.db]]
      annotations = { horizontal = [{ label = "Alarm threshold", value = 80 }] }
      yAxis       = { left = { min = 0, max = 100 } }
    },
    {
      title   = "RDS connections"
      stat    = "Average"
      metrics = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", local.db]]
    },
  ]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name
  dashboard_body = jsonencode({
    widgets = [for widget in local.dashboard_widgets : {
      type       = "metric"
      width      = 8
      height     = 6
      properties = merge(widget, { region = var.aws_region, period = 60 })
    }]
  })
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.name}-unhealthy-hosts"
  alarm_description   = "At least one target failed its health checks for 2 minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = local.alb
    TargetGroup  = local.tg
  }
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${local.name}-target-5xx"
  alarm_description   = "Targets returned at least 5 HTTP 5xx responses in 5 minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = local.alb
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${local.name}-rds-cpu"
  alarm_description   = "Database CPU above 80% for 10 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = local.db
  }
}
