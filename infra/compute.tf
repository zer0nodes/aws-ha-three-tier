data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_default_tags" "current" {}

locals {
  app_env = <<-EOT
    DB_HOST=${aws_db_instance.main.address}
    DB_PORT=${aws_db_instance.main.port}
    DB_NAME=${aws_db_instance.main.db_name}
    DB_SECRET_ARN=${aws_db_instance.main.master_user_secret[0].secret_arn}
    AWS_REGION=${var.aws_region}
    APP_VERSION=${var.app_version}
  EOT

  user_data = replace(templatefile("${path.module}/templates/user_data.yaml.tftpl", {
    app_py           = base64encode(replace(file("${path.module}/../app/app.py"), "\r\n", "\n"))
    requirements_txt = base64encode(replace(file("${path.module}/../app/requirements.txt"), "\r\n", "\n"))
    app_service      = base64encode(replace(file("${path.module}/../app/app.service"), "\r\n", "\n"))
    app_env          = base64encode(local.app_env)
  }), "\r\n", "\n")
}

resource "aws_launch_template" "app" {
  name                   = "${local.name}-app"
  image_id               = data.aws_ssm_parameter.al2023.insecure_value
  instance_type          = var.instance_type
  user_data              = base64encode(local.user_data)
  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.app.arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.app.id]
  }

  metadata_options {
    http_tokens = "required"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  dynamic "tag_specifications" {
    for_each = ["instance", "volume"]

    content {
      resource_type = tag_specifications.value
      tags          = merge(data.aws_default_tags.current.tags, { Name = "${local.name}-app" })
    }
  }

  tags = { Name = "${local.name}-app" }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${local.name}-app"
  vpc_zone_identifier       = [aws_subnet.this["app-a"].id, aws_subnet.this["app-b"].id]
  target_group_arns         = [aws_lb_target_group.app.arn]
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  health_check_type         = "ELB"
  health_check_grace_period = 300

  ignore_failed_scaling_activities = true

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }

  dynamic "tag" {
    for_each = data.aws_default_tags.current.tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }

  depends_on = [aws_route_table_association.this, aws_db_instance.main]
}
