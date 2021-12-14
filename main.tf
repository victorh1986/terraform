data "aws_ami" "app_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

data "template_file" "wordpress" {
  template = file("${path.module}/wordpress.sh")

  vars = {
    DB_NAME     = var.dbname
    DB_USER     = var.username
    DB_PASSWORD = var.password
    DB_HOST     = var.db_id
  }
}

resource "aws_key_pair" "terraform_Key" {
  key_name   = var.key_name
  public_key = file(var.public_key)

  tags = merge(
    {
      Name = "terraform-Key"
    },
    var.tags
  )
}

resource "aws_launch_configuration" "terraform_LC" {
  name                        = var.launch_configuration_name
  image_id                    = data.aws_ami.app_ami.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.terraform_Key.key_name
  security_groups             = var.sg_name
  associate_public_ip_address = true
  user_data                   = data.template_file.wordpress.rendered
  depends_on                  = [var.db_id]
}

resource "aws_autoscaling_group" "terraform_ASG" {
  name                      = var.asg_name
  launch_configuration      = aws_launch_configuration.terraform_LC.name
  min_size                  = 2
  max_size                  = 5
  desired_capacity          = 2
  wait_for_capacity_timeout = 0
  health_check_type         = var.health_check_type
  vpc_zone_identifier       = var.pub_sub_id
  target_group_arns         = var.tg_id

  tags = [
    {
      key                 = "Name"
      value               = "terraform-EC2"
      propagate_at_launch = true
    }
  ]
}

resource "aws_lb" "terraform_LB" {
  name               = var.lb_name
  internal           = false
  load_balancer_type = var.load_balancer_type
  security_groups    = var.sg_name
  subnets            = var.pub_sub_id

  tags = merge(
    {
      Name = "terraform-LB"
    },
    var.tags
  )
}

resource "aws_lb_listener" "terraform_listener" {
  load_balancer_arn = aws_lb.terraform_LB.arn
  port              = 80

  default_action {
    type             = var.default_action_type
    target_group_arn = aws_lb_target_group.terraform_TG.arn
  }
}

resource "aws_lb_target_group" "terraform_TG" {
  name     = var.target_group_name
  protocol = var.protocol
  port     = 80
  vpc_id   = var.vpc_id

  tags = merge(
    {
      Name = "terraform-TG"
    },
    var.tags
  )

  health_check {
    protocol            = var.protocol
    path                = var.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 6
  }
}

output "out_tg_id" {
  value = aws_lb_target_group.terraform_TG[*].id
}

output "out_elb_id" {
  value = aws_lb.terraform_LB.dns_name
}

output "out_zone_id" {
  value = aws_lb.terraform_LB.zone_id
}
