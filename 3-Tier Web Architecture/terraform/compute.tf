data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_lb" "alb" {
  name               = "prod-web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_2a.id, aws_subnet.public_2b.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "prod-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "aws_launch_template" "web" {
  name_prefix   = "prod-web-template-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.app_sg.id]

  # Injects the userdata.sh script from the scripts folder located one directory up
  user_data = base64encode(templatefile("${path.module}/../scripts/userdata.sh", {
    db_endpoint = aws_db_instance.mysql.address
    db_password = var.db_password
  }))
}

resource "aws_autoscaling_group" "asg" {
  name                = "prod-web-asg"
  vpc_zone_identifier = [aws_subnet.app_2a.id, aws_subnet.app_2b.id]
  target_group_arns   = [aws_lb_target_group.tg.arn]
  health_check_type   = "ELB"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }
}