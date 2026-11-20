resource "aws_lb" "app" {
  name                       = "${local.name}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = [aws_subnet.this["public-a"].id, aws_subnet.this["public-b"].id]
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "app" {
  name                 = "${local.name}-app"
  target_type          = "instance"
  protocol             = "HTTP"
  port                 = 8080
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30

  health_check {
    path              = "/health"
    interval          = 15
    healthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  protocol          = "HTTP"
  port              = 80

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
